/// HeartbeatTask whose service is not in the production (Story 8.1; AD-1, AD-18, FR-32): its ITEM names an item that does not exist, so while
/// OcuTalon.Production runs, CreateBusinessService fails with a code that is not one of the quiet ones, and the task must return that failure.
/// Test.Schedule.Heartbeat TestFailureReturned calls OnTask on it. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the Task Manager
/// has no task of this class. Nothing else loads it.
Class OcuTalon.Test.Schedule.HeartbeatTaskMissingItem Extends OcuTalon.Schedule.HeartbeatTask
{

Parameter TaskName = "OcuTalon heartbeat (test: missing item)";

Parameter ITEM = "HeartbeatInMissing";

}
