Include %cspBuild

/// The dispatch class of the application /ocutalon/public (AD-13): GET /status, answered to anyone, with no
/// session. It reports readiness, the next reset, busy, and the last reset's time and kind from the public
/// settings, and always returns every key, null where a value is unset. It reads no session and takes no connection.
/// Two forms of the same five keys differ only in busy (Form):
///   - the plain form (no for, or any value but the exact one) is busy when the instance's licence connections reach the
///     stored cap minus the stored reserve (Busy, IsBusy), or when the live visitors reach VISITORCAP. The visitors are the
///     sessions of IRIS's CSP session store (%CSP's) that hold Shell's VISITORKEY and have not timed out (Visitors); a session
///     leaves the count at its sign-out and at its stored timeout. A store that cannot be read counts as busy;
///   - the trace form (for=trace, exactly once) is busy from the connection check alone, so that a visitor who got in is never
///     refused Visual Trace because the visitors are full.
/// The cap is the public setting, never the instance's high-water mark, and without a valid cap neither clause applies and the
/// store is never read. While the answer reports busy it carries the header X-OcuTalon-Busy: 1 (BUSYHEADER), which the demo
/// host's proxy counts; the status code stays 200. After sign-in Busy(own) leaves out the connections that the new session
/// itself holds. An error is answered with its status line only, so its cause never reaches the anonymous caller.
/// The class lives in OCUTALON_PUBLIC and references only %CSP, IRIS's CSP session store, dynamic objects, $SYSTEM.License,
/// $SYSTEM.Status, its own package and OcuTalon.Data.Public.Settings (AD-3).
Class OcuTalon.Web.Public.Status Extends %CSP.REST
{

Parameter UseSession = 0;

Parameter CONTENTTYPE = "application/json";

Parameter HandleCorsRequest = 0;

/// The live visitors at which the plain form is busy (about 6; P12, NFR-23). It is independent of the connection cap.
Parameter VISITORCAP = 6;

/// The marker header of a busy answer (value "1"): this status, the splash in state busy and the post-sign-in refusal.
Parameter BUSYHEADER = "X-OcuTalon-Busy";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/status" Method="GET" Call="Show"/>
</Routes>
}

/// Everyone may read the status. The default check needs Read on the data database, which the public account
/// doesn't hold.
ClassMethod AccessCheck(Output authorized As %Boolean = 0) As %Status
{
	Set authorized = 1
	Quit $SYSTEM.Status.OK()
}

/// The status line of an error, with no body: the cause of an error is never sent to an anonymous caller.
ClassMethod ReportHttpStatusCode(pHttpStatus, pSC As %Status = {$$$OK}) As %Status
{
	Set %response.Status = pHttpStatus
	Quit $SYSTEM.Status.OK()
}

/// GET /status
ClassMethod Show() As %Status
{
	Do %response.SetHeader("Cache-Control", "no-store")
	Set body = ..Body(..Form())
	If body.busy Do %response.SetHeader(..#BUSYHEADER, "1")
	Write body.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// "trace" when the query holds for exactly once and its value is exactly trace (case-sensitive, untrimmed), else "": any other
/// or missing value, and a repeated parameter, answer the plain form. Other query names are ignored.
ClassMethod Form() As %String
{
	If ($Data(%request.Data("for", 2)) = 0) && ($Get(%request.Data("for", 1)) = "trace") Quit "trace"
	Quit ""
}

/// {ready, nextReset, busy, lastReset, lastResetKind}, every key present: a time or kind is null where the
/// setting is unset. form is the status form (Form); busy is Busy(0, form).
ClassMethod Body(form As %String = "") As %DynamicObject
{
	Set body = {}
	Do body.%Set("ready", ''##class(OcuTalon.Data.Public.Settings).Get("ready"), "boolean")
	Do ..SetOrNull(body, "nextReset", ##class(OcuTalon.Data.Public.Settings).NextReset())
	Do body.%Set("busy", ..Busy(0, form), "boolean")
	Do ..SetOrNull(body, "lastReset", ##class(OcuTalon.Data.Public.Settings).Get("lastReset"))
	Do ..SetOrNull(body, "lastResetKind", ##class(OcuTalon.Data.Public.Settings).Get("lastResetKind"))
	Quit body
}

/// 1 when the demo cannot take another visitor, in the form given (Form). 0 without a valid stored cap, so the store is never
/// read on a local install. Otherwise 1 when the instance's licence connections, less own of them, have reached the stored cap
/// minus the stored reserve (IsBusy); else 0 in the trace form; else 1 when Visitors has reached VISITORCAP. A store read that
/// throws counts as busy. Before sign-in own is 0. The hook of a new session passes that session's own connection (none on build
/// 154, SessionEvents.OWNCONNECTIONS). The reads take no connection.
ClassMethod Busy(own As %Integer = 0, form As %String = "") As %Boolean
{
	Set cap = ##class(OcuTalon.Data.Public.Settings).Get("connectionCap")
	If '..ValidCap(cap) Quit 0
	Set connections = $SYSTEM.License.InstanceConnections() - own
	Set reserve = ##class(OcuTalon.Data.Public.Settings).Get("connectionReserve")
	If ..IsBusy(connections, cap, reserve) Quit 1
	If form = "trace" Quit 0
	Set busy = 1
	Try {
		Set busy = ..IsBusy(connections, cap, reserve, ..Visitors())
	} Catch exception {
		Set busy = 1
	}
	Quit busy
}

/// 1 when connections have reached cap minus reserve, or when visitors (a whole number; "" leaves the clause out) has reached
/// VISITORCAP. 0 without a valid cap (a whole number above zero), at any visitor count; an empty or invalid reserve counts as 0.
ClassMethod IsBusy(connections As %Integer, cap As %String, reserve As %String, visitors As %String = "") As %Boolean
{
	If '..ValidCap(cap) Quit 0
	If reserve '? 1.N Set reserve = 0
	If connections >= (cap - reserve) Quit 1
	Quit (visitors '= "") && (visitors >= ..#VISITORCAP)
}

/// 1 for a whole number above zero.
ClassMethod ValidCap(cap As %String) As %Boolean [ Private ]
{
	Quit (cap ? 1.N) && (cap > 0)
}

/// The number of live visitors in store, IRIS's CSP session store (by default ^%cspSession): the sessions from subscript 0 onward
/// (the nodes -2, -1 and 0 are the store's own) whose stored timeout (the list position $$$sesOldTimeout, an absolute time in
/// seconds) is ahead of now and whose data holds Shell's VISITORKEY. Another application's session never holds the key. The
/// reader takes no session and writes nothing.
ClassMethod Visitors(store As %String = "^%cspSession") As %Integer
{
	Set stamp = $ZTimeStamp
	Set now = ($Piece(stamp, ",") * 86400 + $Piece(stamp, ",", 2)) \ 1
	Set key = ##class(OcuTalon.Web.Public.Shell).#VISITORKEY
	Set count = 0
	Set id = 0
	For {
		Set id = $Order(@store@(id))
		If id = "" Quit
		If $ListGet($Get(@store@(id)), $$$sesOldTimeout) > now, $Get(@store@(id, 0, key)) = 1 Set count = count + 1
	}
	Quit count
}

/// Sets key to value, or to null when value is empty.
ClassMethod SetOrNull(object As %DynamicObject, key As %String, value As %String) [ Private ]
{
	If value = "" {
		Do object.%Set(key, "", "null")
	} Else {
		Do object.%Set(key, value)
	}
}

}
