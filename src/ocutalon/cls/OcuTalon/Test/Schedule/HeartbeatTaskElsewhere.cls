/// HeartbeatTask for a production that is not the one running (Story 8.1; AD-1, AD-18, FR-32): its PRODUCTION names a production that does not exist,
/// so while OcuTalon.Production runs, the production rule of the task ("OcuTalon.Production is not the running production") applies.
/// Test.Schedule.Heartbeat TestOtherProduction calls OnTask on it. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the Task Manager
/// has no task of this class. Nothing else loads it.
Class OcuTalon.Test.Schedule.HeartbeatTaskElsewhere Extends OcuTalon.Schedule.HeartbeatTask
{

Parameter TaskName = "OcuTalon heartbeat (test: other production)";

Parameter PRODUCTION = "OcuTalon.Test.Schedule.NoSuchProduction";

}
