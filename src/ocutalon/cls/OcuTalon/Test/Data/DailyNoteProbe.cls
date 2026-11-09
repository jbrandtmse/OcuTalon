/// A subclass of OcuTalon.Data.DailyNote for the tests, whose read of the reminders fails with an error status, as Ownership gives for a failed read, so that a test sees that
/// Build throws it; whose Read runs one of DailyNote's own reads with an empty window, which Ownership answers with an error status; and whose Fail builds the note with one
/// of the reads of a row (the turn, the usage channel or the fix requests) failed. It adds nothing to the product's surface; the product never refers to it.
Class OcuTalon.Test.Data.DailyNoteProbe Extends OcuTalon.Data.DailyNote
{

/// The read of the reminders: failed, except inside Read and Fail, which run DailyNote's own.
ClassMethod Reminders(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	If $Get(^||DailyNoteProbe("own")) {
		Do ##super(sessionRef, from, to, .entries)
		Quit
	}
	Do ..Check($SYSTEM.Status.Error(5001, "zz the read of the reminders failed"))
}

/// The read of a decision's turn: failed inside Fail("turn"), else DailyNote's own.
ClassMethod TurnOf(itemId As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn [ Private ]
{
	If $Get(^||DailyNoteProbe("fail")) = "turn" {
		Set sc = $SYSTEM.Status.Error(5001, "zz the read of the turn failed")
		Quit ""
	}
	Quit ##super(itemId, sessionRef, .sc)
}

/// The read of a decision's usage channel: failed inside Fail("channel"), else DailyNote's own.
ClassMethod UsageChannel(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %String [ Private ]
{
	If $Get(^||DailyNoteProbe("fail")) = "channel" {
		Set sc = $SYSTEM.Status.Error(5001, "zz the read of the channel failed")
		Quit ""
	}
	Quit ##super(decisionRef, sessionRef, .sc)
}

/// The read of an incident's fix requests: failed inside Fail("fix"), else DailyNote's own.
ClassMethod FixRequests(incidentRef As %String, sessionRef As %String, Output sc As %Status) As %ListOfObjects [ Private ]
{
	If $Get(^||DailyNoteProbe("fail")) = "fix" {
		Set sc = $SYSTEM.Status.Error(5001, "zz the read of the fix failed")
		Quit ##class(%ListOfObjects).%New()
	}
	Quit ##super(incidentRef, sessionRef, .sc)
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

/// Build with the read of a row (turn, channel or fix) failed and every other read DailyNote's own: the note, or the throw of the failed read.
ClassMethod Fail(read As %String, sessionRef As %String, day As %String) As %String
{
	Set ^||DailyNoteProbe("own") = 1
	Set ^||DailyNoteProbe("fail") = read
	Try {
		Set note = ..Build(sessionRef, day)
	} Catch exception {
		Kill ^||DailyNoteProbe
		Throw exception
	}
	Kill ^||DailyNoteProbe
	Quit note
}

}
