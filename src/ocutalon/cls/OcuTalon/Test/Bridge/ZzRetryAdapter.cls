/// The runner's adapter for the retried-turn tests of Test.Bridge.Conversation (Story 17.2). A shadow host is no item of the production, so the setting
/// RetryItem of the first runner cannot name it; this adapter answers RetryAllowed itself:
///   - RetryAllowed is 1 only for a RetryOf that is ZzRunner, the shadow first runner of the tests;
///   - with a LateToken, SaveLinked of a linked turn first notes ^IRIS.Temp.ZzLate(token, "waiting") and waits, up to a minute, for
///     ^IRIS.Temp.ZzLate(token, "go"), so that a test can run the retry while the first attempt still holds the conversation lock, and then
///     lets the late attempt save and point the link;
///   - SessionConfigFor notes the timeout_ms of each config it composes, and whether the request being served carries a RetryOf, in
///     ^||ZzRetryConfig(n), as "timeout_ms|retrying".
/// Nothing else differs from the adapter.
Class OcuTalon.Test.Bridge.ZzRetryAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// The token of the test that waits for this adapter's save, or "" for none.
Property LateToken As %String;

Method RetryAllowed(retryOf As %String) As %Boolean
{
	Quit retryOf = "ZzRunner"
}

Method SessionConfigFor(Output config As %DynamicObject) As %Status
{
	Set sc = ##super(.config)
	If $$$ISOK(sc) && $IsObject(config) Set ^||ZzRetryConfig($Increment(^||ZzRetryConfig)) = config.%Get("timeout_ms")_"|"_..Retrying
	Quit sc
}

Method SaveLinked(request As OcuTalon.Bridge.Msg.Request, session As %AI.Agent.Session, fresh As %Boolean, reply As OcuTalon.Bridge.Msg.Reply) [ Private ]
{
	If ..LateToken '= "" {
		Set ^IRIS.Temp.ZzLate(..LateToken, "waiting") = 1
		Set deadline = $ZHorolog + 60
		While '$Data(^IRIS.Temp.ZzLate(..LateToken, "go")) && ($ZHorolog < deadline) {
			Hang 0.1
		}
	}
	Do ##super(request, session, fresh, reply)
}

}
