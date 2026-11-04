/// The session events of the application /ocutalon (AD-4). OnLogin runs at the sign-in request, as the signed-in
/// user with the application's roles, and on a local or IPM install attaches the user's durable OcuTalon session to the
/// CSP session (Ownership.Attach), so that the first API call finds it. A user without the OcuTalon user role gets no
/// session row, cookie or counter row. OnLogin always answers OK: an error status would neither log the user out nor show
/// the sign-in page. On a local install a session that was not attached here is attached by the first API call
/// (Ownership.SessionRef); on the online demo it is not, and the API answers that CSP session with an error. A failure is
/// written to the console log, without the user name.
/// On the online demo (onlineDemo on, read through Data.Setting) the sign-in gives the visitor a session of their own
/// instead (AD-4, AD-13, Story 16.3), and only /ocutalon does so, because the trace applications have no session event class:
///   - a request that came through the proxy while the demo is busy (Status.Busy with the new session's own connections, OWNCONNECTIONS,
///     left out: none, so that it refuses exactly when the status reports busy, from the connections or from the live visitors,
///     the 7th visitor included) is refused first: nothing is resumed,
///     created, locked or counted and no cookie is set, and the refusal $ListBuild("busy") is recorded in the CSP session for Shell,
///     which ends the CSP session in the same request and shows the splash's busy error with the marker header. A request that did
///     not come through the proxy (the probe, an operator) is exempt;
///   - a cookie RESUMECOOKIE whose reference opens a row of the signed-in user attaches that row, sets no cookie and is
///     never counted or refused at the address limit (the busy refusal above comes first);
///   - a proxied sign-in that attaches, by resume or by creation, marks its CSP session with Shell.VISITORKEY = 1 in the
///     session data, which is how Status.Visitors counts it until its sign-out or its CSP timeout. A refusal, a request that did
///     not come through the proxy (the probe's path, an operator) and a user without the role are never marked;
///   - otherwise a new row is created (Ownership.StartVisitor) and the cookie is set once, expiring at the next reset;
///   - the creation is counted per client address (ClientAddress) in Data.AddressCounter when the request came through the
///     proxy: at the limit nothing is created, and the refusal is recorded in the CSP session for Shell, which ends the CSP
///     session in the same request and shows the splash's field error. A request that did not come through the proxy is exempt.
/// The resume reference is held in local variables of this request and the cookie alone; no line of the log carries it.
/// The class has no OnEndSession or OnTimeout: a CSP session that ends (a closed page, the idle cap, the timeout) ends nothing
/// else (AD-4). Only Sign out ends the OcuTalon session, through SessionOps.End. Its OnLogout, which runs at a sign-out (the API's
/// and ?IRISLogout=end), only raises the session's sign-out mark off the online demo (Data.Session.MarkSignedOut) and wakes the
/// session's WebSocket, so that an open socket ends within one loop (U-174); it ends no OcuTalon state, and it answers OK in every case.
Class OcuTalon.Web.SessionEvents Extends %CSP.SessionEvents [ ProcedureBlock ]
{

/// The name of the resume cookie (AD-4). Its one definition is the public class Web.Public.Shell's, which the splash reads it
/// from (AD-3); this parameter answers it for the writers of the cookie.
Parameter RESUMECOOKIE As COSEXPRESSION = "##class(OcuTalon.Web.Public.Shell).#RESUMECOOKIE";

/// The Expires date of an expired resume cookie: an RFC 1123 date in the past.
Parameter EXPIREDDATE = "Thu, 01 Jan 1970 00:00:00 GMT";

/// The licence connections that the signing-in session itself holds when OnLogin runs; the busy check leaves them out. A new
/// session holds none on build 154, so the check leaves none out and the post-sign-in refusal is the status's own rule.
Parameter OWNCONNECTIONS = 0;

/// Attaches the signed-in user's session when the user holds the OcuTalon user role (AttachFor).
ClassMethod OnLogin() As %Status
{
	Quit ..AttachFor(##class(OcuTalon.Web.Public.Shell).HasRole())
}

/// The sign-out hook: off the online demo, and when the CSP session names an OcuTalon session, raises that session's sign-out mark and
/// wakes the session's WebSocket. The answer is OK in every case, because an error status stops a non-forced logout, and every failure is
/// caught and logged without the user name.
ClassMethod OnLogout() As %Status
{
	Try {
		If ##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1 {
			Set ref = $Get(%session.Data(##class(OcuTalon.Data.Ownership).#SESSIONKEY))
			If ref '= "" {
				Set sc = ##class(OcuTalon.Data.Session).MarkSignedOut(ref)
				If $SYSTEM.Status.IsError(sc) Do ..Log("the sign-out could not be marked, error "_$SYSTEM.Status.GetErrorCodes(sc))
				Do ##class(OcuTalon.Live.Publish).Wake(ref)
			}
		}
	} Catch exception {
		Do ..Log("the sign-out could not be marked, error "_$SYSTEM.Status.GetErrorCodes(exception.AsStatus()))
	}
	Quit $SYSTEM.Status.OK()
}

/// OnLogin's work for a user who holds the role (hasRole 1) or does not (0): the role attaches the durable session, or on the
/// online demo the visitor's own (AttachVisitor); no role does nothing. The answer is OK in every case, and a failure is logged.
ClassMethod AttachFor(hasRole As %Boolean) As %Status
{
	Try {
		If hasRole {
			If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 {
				Set sc = ..AttachVisitor()
			} Else {
				Set sc = ##class(OcuTalon.Data.Ownership).Attach()
			}
			If $SYSTEM.Status.IsError(sc) Do ..Log("the session could not be attached, error "_$SYSTEM.Status.GetErrorCodes(sc))
		}
	} Catch exception {
		Do ..Log("the session could not be attached, error "_$SYSTEM.Status.GetErrorCodes(exception.AsStatus()))
	}
	Quit $SYSTEM.Status.OK()
}

/// The online demo's attach: records the busy refusal of a proxied request, or resumes the row of the browser's cookie, or creates
/// a visitor's row and sets the cookie, or records the refusal at the address limit. A proxied attach that succeeds marks the CSP
/// session as a counted visitor (Shell.VISITORKEY). Returns the first error status.
ClassMethod AttachVisitor() As %Status [ Private ]
{
	Set address = ..ClientAddress($Get(%request.CgiEnvs("REMOTE_ADDR")), $Get(%request.CgiEnvs("HTTP_X_FORWARDED_FOR")), ##class(OcuTalon.Data.Public.Settings).Get("proxyAddress"), .proxied)
	If proxied, ##class(OcuTalon.Web.Public.Status).Busy(..#OWNCONNECTIONS) {
		Set %session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY) = $ListBuild("busy")
		Quit $SYSTEM.Status.OK()
	}
	Set reference = $Get(%request.Cookies(..#RESUMECOOKIE, 1))
	If reference '= "" {
		Set ref = ##class(OcuTalon.Data.Ownership).Resume(reference, .sc)
		If $SYSTEM.Status.IsOK(sc), ref '= "", proxied Set %session.Data(##class(OcuTalon.Web.Public.Shell).#VISITORKEY) = 1
		If (ref '= "") || $SYSTEM.Status.IsError(sc) Quit sc
	}
	Set reference = ""
	If 'proxied {
		Set ref = ##class(OcuTalon.Data.Ownership).StartVisitor(.reference, .sc)
	} Else {
		If '##class(OcuTalon.Data.AddressCounter).Lock(address) Quit $SYSTEM.Status.Error(5001, "The address counter is busy")
		Try {
			Set limit = +##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Data.Setting).#ADDRESSLIMITKEY, ##class(OcuTalon.Data.Setting).#ADDRESSLIMITSEED)
			If ##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest) >= limit {
				Set until = ##class(OcuTalon.Data.AddressCounter).Shift(oldest, ##class(OcuTalon.Data.AddressCounter).#WINDOW)
				Set %session.Data(##class(OcuTalon.Web.Public.Shell).#REFUSALKEY) = $ListBuild("addressLimit", until)
				Set sc = $SYSTEM.Status.OK()
			} Else {
				Set ref = ##class(OcuTalon.Data.Ownership).StartVisitor(.reference, .sc)
				If $SYSTEM.Status.IsOK(sc) Set sc = ##class(OcuTalon.Data.AddressCounter).Add(address)
				If $SYSTEM.Status.IsOK(sc) Set %session.Data(##class(OcuTalon.Web.Public.Shell).#VISITORKEY) = 1
			}
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	}
	If $SYSTEM.Status.IsOK(sc), reference '= "" {
		Do ..ResumeCookie(reference, ..CookieExpiry(##class(OcuTalon.Data.Public.Settings).NextReset()))
	}
	Quit sc
}

/// The one write of the resume cookie (AD-4): the value and the Expires date (an RFC 1123 date, see CookieExpiry), with path
/// /ocutalon/, Secure, HttpOnly and SameSite Strict. The sign-in sets the reference with the next reset's date; Sign out
/// (Web.Api.EndSession) expires it with an empty value and EXPIREDDATE, under the same name and path.
ClassMethod ResumeCookie(value As %String, expiry As %String)
{
	Do %response.SetCookie(..#RESUMECOOKIE, value, expiry, "/ocutalon/", "", 1, 1, "Strict")
}

/// The client address that the address limit counts, and whether the request is proxied. A request is proxied when proxy is
/// set and equals remote exactly (the proxy's own address); its address is the right-most entry of the forwarded list,
/// trimmed, or remote when the list has none. A request that is not proxied is exempt: proxied is 0, the result is "", and
/// its forwarded list is ignored, because only the proxy overwrites it (AD-13).
ClassMethod ClientAddress(remote As %String, forwarded As %String, proxy As %String, Output proxied As %Boolean) As %String
{
	Set proxied = (proxy '= "") && (proxy = remote)
	If 'proxied Quit ""
	Set last = $ZStrip($Piece(forwarded, ",", $Length(forwarded, ",")), "<>W")
	Quit $Select(last = "": remote, 1: last)
}

/// A UTC time, YYYY-MM-DDThh:mm:ssZ, as the RFC 1123 date of a cookie's Expires ("Sun, 25 Oct 2026 20:00:00 GMT"); "" for an
/// empty or unreadable time, which makes the cookie a browser-session cookie.
ClassMethod CookieExpiry(nextReset As %String) As %String
{
	Set seconds = ##class(OcuTalon.Data.Public.Settings).ToSeconds(nextReset)
	If seconds = "" Quit ""
	Set weekday = $Piece(##class(OcuTalon.Data.Time).#WEEKDAYS, ",", ($ZDate(seconds \ 86400, 10) + 1))
	Set month = $Piece(##class(OcuTalon.Data.Time).#MONTHS, ",", +$Extract(nextReset, 6, 7))
	Quit $Extract(weekday, 1, 3)_", "_$Extract(nextReset, 9, 10)_" "_month_" "_$Extract(nextReset, 1, 4)_" "_$Extract(nextReset, 12, 19)_" GMT"
}

/// Writes one line to the console log; a failure of the log itself is ignored.
ClassMethod Log(text As %String) [ Private ]
{
	Try {
		Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Web.SessionEvents: "_text, 0, 1)
	} Catch {
	}
}

}
