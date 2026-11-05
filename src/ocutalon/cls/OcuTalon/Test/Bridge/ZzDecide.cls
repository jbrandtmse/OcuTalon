/// A Decide for the in-process tests (Test.Bridge.Decide): it records its timers and its sends in the process-private global
/// ^||ZzDecideCalls instead of making them, so that a test sees what OnResponse asked the framework for without a production to answer.
///   - ^||ZzDecideCalls("timer", n) is $ListBuild(timeout, completion key, controlled keys) of the nth SetTimer;
///   - ^||ZzDecideCalls("send", n) is $ListBuild(dispatch name, DecisionRef of the request, response required, completion key, ItemId) of the nth
///     SendRequestAsync, with the Position of the step as a sixth member when the message is an AgentStep (which has no ItemId, so its fifth
///     member is empty), and, for a Request, an empty sixth member and the Compact flag of the sent request as its seventh;
///   - ^||ZzDecideCalls("send", n, "retryOf") is the RetryOf of the nth sent Request (Story 17.2), apart from the list so that the list keeps its members;
///   - the count of each is the value of ^||ZzDecideCalls("timer") and ^||ZzDecideCalls("send").
///   - ToolsReadOnly answers ^||ZzDecideReadOnly (1 or 0) when the test sets it, so that a test can ask the timer rule about an agent whose tools are or are not
///     read-only, and the real answer otherwise (Story 17.2, R2).
/// It is never started or saved.
Class OcuTalon.Test.Bridge.ZzDecide Extends OcuTalon.Bridge.Process.Decide
{

Method SetTimer(pTimeout As %String, pCompletionKey As %String = "", pControlledCompletionKeys As %String = "*", Output pAlarmHandle As %String, pDescription As %String = "", pIsTimer = 1) As %Status
{
	Set pAlarmHandle = ""
	Set n = $Increment(^||ZzDecideCalls("timer"))
	Set ^||ZzDecideCalls("timer", n) = $ListBuild(pTimeout, pCompletionKey, pControlledCompletionKeys)
	Quit $$$OK
}

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As Ens.Request, pResponseRequired As %Boolean = 1, pCompletionKey As %String = "", pDescription As %String = "") As %Status
{
	Set n = $Increment(^||ZzDecideCalls("send"))
	Set call = $ListBuild(pTargetDispatchName, pRequest.DecisionRef, pResponseRequired, pCompletionKey, $Select(pRequest.%IsA("OcuTalon.Bridge.Msg.Request"): pRequest.ItemId, 1: ""))
	If pRequest.%IsA("OcuTalon.Bridge.Msg.AgentStep") Set call = call _ $ListBuild(pRequest.Position)
	If pRequest.%IsA("OcuTalon.Bridge.Msg.Request") Set call = call _ $ListBuild("", pRequest.Compact)
	Set ^||ZzDecideCalls("send", n) = call
	If pRequest.%IsA("OcuTalon.Bridge.Msg.Request") Set ^||ZzDecideCalls("send", n, "retryOf") = pRequest.RetryOf
	Quit $$$OK
}

ClassMethod ToolsReadOnly(runner As %String) As %Boolean
{
	If $Data(^||ZzDecideReadOnly) Quit +^||ZzDecideReadOnly
	Quit ##super(runner)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
