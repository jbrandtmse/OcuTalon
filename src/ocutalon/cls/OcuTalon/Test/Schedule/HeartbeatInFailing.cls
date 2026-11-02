/// HeartbeatIn with a send that always fails (Story 8.1; AD-1): Test.Schedule.Heartbeat TestSendFails makes it outside the Task Manager and calls
/// OnProcessInput, to show that a failed send is returned and records nothing. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): no
/// production item has this class.
Class OcuTalon.Test.Schedule.HeartbeatInFailing Extends OcuTalon.Schedule.HeartbeatIn
{

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pDescription As %String = "") As %Status
{
	Quit $SYSTEM.Status.Error(5001, "The send to "_pTargetDispatchName_" is refused by the test")
}

}
