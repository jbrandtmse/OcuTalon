/// A subclass of OcuTalon.Test.Web.HookProbe for the tests of the Slack route (Story 27.1); it has no Test methods and the product never refers to it. It replaces the
/// parts of a request that a stand-in cannot carry, from ^OcuTalonTest("HookProbe", ...) (the node names of HookProbe, which it shares for "size", "form", "now", "online",
/// "mode" and "header"): "slackBody" (the body bytes: a string of characters 0 to 255), "slackTs" and "slackSig" (the values of the two Slack headers; absent means
/// no header). The secret is the environment's, as the route reads it, so a test sets SLACK_SIGNING_SECRET and SLACK_BOT_TOKEN itself. "mode" "fail" makes the hand-over to
/// SlackIn an error status, "throw" makes it throw and "real" runs the route's own hand-over. It records "slackSent" (the number of events handed over) with
/// "slackSent",n,<field> for each Event field, "bodyReads" (how often the body bytes were read) and "auditCounts" (the rejections that the audit writes named, in all).
Class OcuTalon.Test.Channel.SlackHookProbe Extends OcuTalon.Test.Web.HookProbe
{

ClassMethod BodySize() As %Integer [ Private ]
{
	Quit $Get(^OcuTalonTest("HookProbe", "size"), $Length($Get(^OcuTalonTest("HookProbe", "slackBody"))))
}

ClassMethod RawBody() As %String [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "bodyReads") = $Get(^OcuTalonTest("HookProbe", "bodyReads")) + 1
	Quit $Get(^OcuTalonTest("HookProbe", "slackBody"))
}

ClassMethod SlackHeader(variable As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("HookProbe", $Case(variable, ##class(OcuTalon.Web.Hook).#SLACKTIMESTAMP: "slackTs", ##class(OcuTalon.Web.Hook).#SLACKSIGNATURE: "slackSig", : "slackOther")))
}

ClassMethod Audit(slot As %String, count As %Integer) As %Status [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "auditCounts") = $Get(^OcuTalonTest("HookProbe", "auditCounts")) + count
	Quit ##super(slot, count)
}

ClassMethod SlackHand(event As OcuTalon.Channel.Slack.Event) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("HookProbe", "header")) Do %response.SetHeader(..#SUPERSESSIONHEADER, "zz-trace-ref")
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz SlackIn threw"))
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz SlackIn is not running")
	If $Get(^OcuTalonTest("HookProbe", "mode")) = "real" Quit ##super(event)
	Set n = $Increment(^OcuTalonTest("HookProbe", "slackSent"))
	For field = "EventId", "EnvelopeType", "EventType", "ChannelType", "Subtype", "BotId", "TeamId", "MemberId", "Text" {
		Set ^OcuTalonTest("HookProbe", "slackSent", n, field) = $Property(event, field)
	}
	Quit $SYSTEM.Status.OK()
}

}
