/// A subclass of OcuTalon.Web.Hook for the tests (Story 35.3); it has no Test methods and the product never refers to it. It replaces the parts of a request
/// that a stand-in cannot carry, from ^OcuTalonTest("HookProbe", ...): "secret" (the header value), "body" (the text), "size" (the declared size; the length of
/// the body when absent), "form" (1 for a form), "now" (the UTC time; the clock when absent), "online" (the flag; the setting when absent), "mode" ("fail" makes
/// the hand-over to WebhookIn an error status, "throw" makes it throw, "real" runs the hook's own hand-over (the real WebhookIn, Test.Web.HookProductionStopped), "auditfail" makes the rejection audit write an error status) and "header" (1 sets the
/// SuperSession response header in the hand-over, as a business service created in a CSP process does). It records under the same global: "sent" (the number
/// of events handed over) with "sent",n,"session"/"name"/"text", "bodyReads" (how often the body was read), "compared" (the hashes the secret was compared
/// against, in order) and "logs" (the console lines).
Class OcuTalon.Test.Web.HookProbe Extends OcuTalon.Web.Hook
{

ClassMethod Secret() As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("HookProbe", "secret"))
}

ClassMethod BodySize() As %Integer [ Private ]
{
	Quit $Get(^OcuTalonTest("HookProbe", "size"), $Length($Get(^OcuTalonTest("HookProbe", "body"))))
}

ClassMethod BodyText() As %String [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "bodyReads") = $Get(^OcuTalonTest("HookProbe", "bodyReads")) + 1
	Quit $Get(^OcuTalonTest("HookProbe", "body"))
}

ClassMethod IsForm() As %Boolean [ Private ]
{
	Quit +$Get(^OcuTalonTest("HookProbe", "form"))
}

ClassMethod Hand(event As OcuTalon.Channel.Webhook.Event) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("HookProbe", "header")) Do %response.SetHeader(..#SUPERSESSIONHEADER, "zz-trace-ref")
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz WebhookIn threw"))
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz WebhookIn is not running")
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "real" Quit ##super(event)
	Set n = $Increment(^OcuTalonTest("HookProbe", "sent"))
	Set ^OcuTalonTest("HookProbe", "sent", n, "session") = event.SessionRef
	Set ^OcuTalonTest("HookProbe", "sent", n, "name") = event.Name
	Set ^OcuTalonTest("HookProbe", "sent", n, "text") = event.Text
	Quit $SYSTEM.Status.OK()
}

ClassMethod Now() As %String [ Private ]
{
	If $Data(^OcuTalonTest("HookProbe", "now")) Quit ^OcuTalonTest("HookProbe", "now")
	Quit ##super()
}

ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("HookProbe", "online")) Quit ^OcuTalonTest("HookProbe", "online")
	Quit ##super()
}

ClassMethod Compare(stored As %String, secret As %String) As %Boolean [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "compared", $Increment(^OcuTalonTest("HookProbe", "compared"))) = stored
	Quit ##super(stored, secret)
}

ClassMethod Audit(slot As %String, count As %Integer) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "auditfail" Quit $SYSTEM.Status.Error(5001, "zz the audit log is off")
	Quit ##super(slot, count)
}

ClassMethod Log(text As %String) [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "logs", $Increment(^OcuTalonTest("HookProbe", "logs"))) = text
}

}
