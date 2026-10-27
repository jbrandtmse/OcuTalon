/// A subclass of OcuTalon.Schedule.ReminderOps for the tests, which overrides its private seam StartWaiter: no waiter starts and the
/// seam answers OK, as if the waiter had started. Everything else, the three verbs, the row and the events, is the real one.
/// The product never refers to it.
Class OcuTalon.Test.Schedule.ReminderOpsStartedProbe Extends OcuTalon.Schedule.ReminderOps
{

Method StartWaiter(row As OcuTalon.Data.Reminder) As %Status [ Private ]
{
	Quit $$$OK
}

}
