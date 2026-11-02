/// A test double for the Checks business process (Story 8.1; AD-1, AD-22, AD-29): it records every Tick it receives and answers OK.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): Test.Schedule.Heartbeat puts it behind the Checks item of
/// OcuTalon.Production (Test.Agent.RunnerFixture UseItemClass) and puts Lane A's class back. Nothing else loads it.
///   - OnRequest appends $ListBuild(TickAt, PreviousTickAt, CatchUp, the id of the request's message header) to
///     ^OcuTalonTest("ChecksDouble","ticks",n), n counting from 1 in ^OcuTalonTest("ChecksDouble","ticks") (the pattern of
///     Test.Tools.CommandsDouble); the tick is set before the count, so a reader that sees the count finds the tick. A request
///     that is not a Tick is not recorded.
///   - ^OcuTalonTest("ChecksDouble","hang") = <seconds>: OnRequest waits that long after it has recorded the tick, so that a test can
///     show that the heartbeat does not wait for a check. The test that sets it kills ^OcuTalonTest("ChecksDouble").
///   - It sends no response, as Checks sends none.
Class OcuTalon.Test.Schedule.ChecksDouble Extends Ens.BusinessProcess
{

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Msg.Tick") Quit $$$OK
	Set n = +$Get(^OcuTalonTest("ChecksDouble", "ticks")) + 1
	Set ^OcuTalonTest("ChecksDouble", "ticks", n) = $ListBuild(request.TickAt, request.PreviousTickAt, request.CatchUp, ..%PrimaryRequestHeader.%Id())
	Set ^OcuTalonTest("ChecksDouble", "ticks") = n
	Set seconds = +$Get(^OcuTalonTest("ChecksDouble", "hang"))
	If seconds > 0 Hang seconds
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
