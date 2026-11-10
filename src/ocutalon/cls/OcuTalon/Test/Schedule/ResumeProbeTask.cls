/// The task class of the probe tasks of Test.Schedule.TaskResume (Story 8.8; DW-1018): OnTask ends OK and does nothing. A probe task
/// never ticks the heartbeat, and Heartbeat.TaskCount() (which counts the tasks of HeartbeatTask) never sees it.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the Task Manager has no task of this class except the probes that the
/// tests create for the length of one test. Nothing else loads it.
Class OcuTalon.Test.Schedule.ResumeProbeTask Extends %SYS.Task.Definition
{

Parameter TaskName = "OcuTalon resume probe (test)";

Method OnTask() As %Status
{
	Quit $$$OK
}

}
