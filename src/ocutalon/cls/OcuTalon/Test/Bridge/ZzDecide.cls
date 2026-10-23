/// A Decide for the in-process tests (Test.Bridge.Decide): it records its timers and its sends in the process-private global
/// ^||ZzDecideCalls instead of making them, so that a test sees what OnResponse asked the framework for without a production to answer.
///   - ^||ZzDecideCalls("timer", n) is $ListBuild(timeout, completion key, controlled keys) of the nth SetTimer;
///   - ^||ZzDecideCalls("send", n) is $ListBuild(dispatch name, DecisionRef of the request, response required, completion key, ItemId) of the nth
///     SendRequestAsync;
///   - the count of each is the value of ^||ZzDecideCalls("timer") and ^||ZzDecideCalls("send").
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
	Set ^||ZzDecideCalls("send", n) = $ListBuild(pTargetDispatchName, pRequest.DecisionRef, pResponseRequired, pCompletionKey, pRequest.ItemId)
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
