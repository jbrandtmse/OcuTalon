/// A helper of the browser cases, not a test: holds one reminder row open with concurrency 4 in a background job, so that ReminderOps cannot
/// cancel the reminder and an EndSession that reaches it is answered failed, as a row that another process holds does in
/// Test.Core.SessionOpsProduction. The case starts it with Start and ends it with Release; the job also ends by itself after the seconds it
/// was given, so that a case that dies leaves no lock behind. The job's state is ^OcuTalonTest("HeldReminder", ref): held while it holds the
/// row, release when Release asked it to let go, done when it has. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Web.HeldReminder Extends %RegisteredObject
{

/// The longest, in seconds, that Start and Release wait for the job.
Parameter WAIT = 10;

/// Starts the job that holds the row of the reminder for at most seconds seconds, and waits until it holds it. Returns 1 when the row is
/// held, 0 when the reminder has no row or the job did not hold it in time.
ClassMethod Start(ref As %String, seconds As %Integer = 120) As %Boolean
{
	Kill ^OcuTalonTest("HeldReminder", ref)
	Job ##class(OcuTalon.Test.Web.HeldReminder).Hold(ref, seconds)
	Set end = $ZHorolog + ..#WAIT
	While ($Get(^OcuTalonTest("HeldReminder", ref)) '= "held") && ($ZHorolog < end) {
		Hang 0.25
	}
	Quit $Get(^OcuTalonTest("HeldReminder", ref)) = "held"
}

/// The job: opens the row with concurrency 4, says so, and holds it until Release asks or the seconds have passed; it says done at the end.
ClassMethod Hold(ref As %String, seconds As %Integer)
{
	Try {
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4)
		If $IsObject(row) {
			Set ^OcuTalonTest("HeldReminder", ref) = "held"
			Set end = $ZHorolog + seconds
			While ($Get(^OcuTalonTest("HeldReminder", ref)) = "held") && ($ZHorolog < end) {
				Hang 0.5
			}
		}
		Set row = ""
	} Catch {
	}
	Set ^OcuTalonTest("HeldReminder", ref) = "done"
}

/// Asks the job to let go of the row and waits until it has. Returns 1 when the job is done, or was never started.
ClassMethod Release(ref As %String) As %Boolean
{
	If $Get(^OcuTalonTest("HeldReminder", ref)) = "" Quit 1
	If $Get(^OcuTalonTest("HeldReminder", ref)) = "held" Set ^OcuTalonTest("HeldReminder", ref) = "release"
	Set end = $ZHorolog + ..#WAIT
	While ($Get(^OcuTalonTest("HeldReminder", ref)) '= "done") && ($ZHorolog < end) {
		Hang 0.25
	}
	Set done = ($Get(^OcuTalonTest("HeldReminder", ref)) = "done")
	If done Kill ^OcuTalonTest("HeldReminder", ref)
	Quit done
}

}
