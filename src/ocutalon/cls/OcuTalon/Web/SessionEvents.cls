/// The session events of the application /ocutalon (AD-4). OnLogin runs at the sign-in request, as the signed-in
/// user with the application's roles, and on a local or IPM install attaches the user's durable OcuTalon session to the
/// CSP session (Ownership.Attach), so that the first API call finds it. A user without the OcuTalon user role gets no
/// session row, cookie or counter row. OnLogin always answers OK: an error status would neither log the user out nor show
/// the sign-in page. On a local install a session that was not attached here is attached by the first API call
/// (Ownership.SessionRef); on the online demo it is not, and the API answers that CSP session with an error. A failure is
/// written to the console log, without the user name.
/// On the online demo (onlineDemo on, read through Data.Setting) the sign-in gives the visitor a session of their own
/// instead (AD-4, AD-13, Story 16.3), and only /ocutalon does so, because the trace applications have no session event class:
///   - a request that came through the proxy while the demo is busy (Status.Busy with the new session's own connection, OWNCONNECTIONS,
///     left out, so that it refuses exactly when connections exceed the cap minus the reserve) is refused first: nothing is resumed,
///     created, locked or counted and no cookie is set, and the refusal $ListBuild("busy") is recorded in the CSP session for Shell,
///     which ends the CSP session in the same request and shows the splash's busy error with the marker header. A request that did
///     not come through the proxy (the probe, an operator) is exempt;
///   - a cookie RESUMECOOKIE whose reference opens a row of the signed-in user attaches that row, sets no cookie and is
///     never counted or refused at the address limit (the busy refusal above comes first);
///   - otherwise a new row is created (Ownership.StartVisitor) and the cookie is set once, expiring at the next reset;
///   - the creation is counted per client address (ClientAddress) in Data.AddressCounter when the request came through the
///     proxy: at the limit nothing is created, and the refusal is recorded in the CSP session for Shell, which ends the CSP
///     session in the same request and shows the splash's field error. A request that did not come through the proxy is exempt.
/// The resume reference is held in local variables of this request and the cookie alone; no line of the log carries it.
Class OcuTalon.Web.SessionEvents Extends %CSP.SessionEvents [ ProcedureBlock ]
{

/// The name of the resume cookie (AD-4). Story 16.4 expires it at sign-out.
Parameter RESUMECOOKIE = "OcuTalonResume";

/// The licence connections that the signing-in session itself holds when OnLogin runs; the busy check leaves them out.
Parameter OWNCONNECTIONS = 1;

/// Attaches the signed-in user's session when the user holds the OcuTalon user role (AttachFor).
ClassMethod OnLogin() As %Status
{
	Quit ..AttachFor(##class(OcuTalon.Web.Public.Shell).HasRole())
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
/// a visitor's row and sets the cookie, or records the refusal at the address limit. Returns the first error status.
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
			}
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Do ##class(OcuTalon.Data.AddressCounter).Unlock(address)
	}
	If $SYSTEM.Status.IsOK(sc), reference '= "" {
		Do %response.SetCookie(..#RESUMECOOKIE, reference, ..CookieExpiry(##class(OcuTalon.Data.Public.Settings).NextReset()), "/ocutalon/", "", 1, 1, "Strict")
	}
	Quit sc
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
