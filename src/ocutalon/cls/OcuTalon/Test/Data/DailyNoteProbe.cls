/// A subclass of OcuTalon.Data.DailyNote for the tests, whose read of the reminders fails with an error status, as Ownership gives for a failed read, so that a test sees that
/// Build throws it, and whose Read runs one of DailyNote's own reads with an empty window, which Ownership answers with an error status. It adds nothing to the product's
/// surface; the product never refers to it.
Class OcuTalon.Test.Data.DailyNoteProbe Extends OcuTalon.Data.DailyNote
{

/// The read of the reminders: failed, except inside Read, which runs DailyNote's own.
ClassMethod Reminders(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	If $Get(^||DailyNoteProbe("own")) {
		Do ##super(sessionRef, from, to, .entries)
		Quit
	}
	Do ..Check($SYSTEM.Status.Error(5001, "zz the read of the reminders failed"))
}

/// DailyNote's own read of the kind (messages, decisions, incidents, approvals or reminders) with an empty window, for which Ownership answers an error status: the read throws it.
ClassMethod Read(kind As %String, sessionRef As %String)
{
	Kill entries
	Set ^||DailyNoteProbe("own") = 1
	Try {
		If kind = "messages" Do ..Messages(sessionRef, "", "", .entries)
		If kind = "decisions" Do ..Decisions(sessionRef, "", "", .entries)
		If kind = "incidents" Do ..Incidents(sessionRef, "", "", .entries)
		If kind = "approvals" Do ..Approvals(sessionRef, "", "", .entries)
		If kind = "reminders" Do ..Reminders(sessionRef, "", "", .entries)
	} Catch exception {
		Kill ^||DailyNoteProbe
		Throw exception
	}
	Kill ^||DailyNoteProbe
}

}
