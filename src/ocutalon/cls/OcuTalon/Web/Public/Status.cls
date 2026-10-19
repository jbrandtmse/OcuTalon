/// The dispatch class of the application /ocutalon/public (AD-13): GET /status, answered to anyone, with no
/// session. It reports readiness, the next reset, busy, and the last reset's time and kind from the public
/// settings, and always returns every key, null where a value is unset. Busy is true when the instance's licence
/// connections reach the stored cap minus the stored reserve; the count is read without taking a connection.
/// The class lives in OCUTALON_PUBLIC and references only %CSP, dynamic objects, $SYSTEM.License, $SYSTEM.Status,
/// its own package and OcuTalon.Data.Public.Settings (AD-3).
Class OcuTalon.Web.Public.Status Extends %CSP.REST
{

Parameter UseSession = 0;

Parameter CONTENTTYPE = "application/json";

Parameter HandleCorsRequest = 0;

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

/// GET /status
ClassMethod Show() As %Status
{
	Do %response.SetHeader("Cache-Control", "no-store")
	Write ..Body().%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// {ready, nextReset, busy, lastReset, lastResetKind}, every key present: a time or kind is null where the
/// setting is unset.
ClassMethod Body() As %DynamicObject
{
	Set body = {}
	Do body.%Set("ready", ''##class(OcuTalon.Data.Public.Settings).Get("ready"), "boolean")
	Do ..SetOrNull(body, "nextReset", ##class(OcuTalon.Data.Public.Settings).NextReset())
	Set busy = ..IsBusy($SYSTEM.License.InstanceConnections(), ##class(OcuTalon.Data.Public.Settings).Get("connectionCap"), ##class(OcuTalon.Data.Public.Settings).Get("connectionReserve"))
	Do body.%Set("busy", busy, "boolean")
	Do ..SetOrNull(body, "lastReset", ##class(OcuTalon.Data.Public.Settings).Get("lastReset"))
	Do ..SetOrNull(body, "lastResetKind", ##class(OcuTalon.Data.Public.Settings).Get("lastResetKind"))
	Quit body
}

/// 1 when connections have reached cap minus reserve. 0 without a valid cap (a whole number above zero); an empty
/// or invalid reserve counts as 0.
ClassMethod IsBusy(connections As %Integer, cap As %String, reserve As %String) As %Boolean
{
	If (cap '? 1.N) || (cap < 1) Quit 0
	If reserve '? 1.N Set reserve = 0
	Quit connections >= (cap - reserve)
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
