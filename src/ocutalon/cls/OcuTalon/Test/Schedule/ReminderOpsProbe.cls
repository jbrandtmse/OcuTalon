/// A subclass of OcuTalon.Schedule.ReminderOps for the tests, which overrides its private seam StartWaiter: the waiter never starts and
/// the seam answers an error status. Everything else, the three verbs, the row and its removal and the answer, is the real one. The
/// product never refers to it.
Class OcuTalon.Test.Schedule.ReminderOpsProbe Extends OcuTalon.Schedule.ReminderOps
{

Method StartWaiter(row As OcuTalon.Data.Reminder) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, "zz the waiter did not start")
}

}
