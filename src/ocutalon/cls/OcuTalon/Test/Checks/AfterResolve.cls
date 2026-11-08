Include Ensemble

/// Tests that the status answer and the rail say so within seconds after an incident resolves, reopens or is dismissed (Story 5.15, DW-851, DW-957; AD-4, AD-12, AD-15, AD-18, AD-26,
/// AD-28, AD-33). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (IncidentManager and Checks are code of the running production, so a warm stack's jobs keep
/// their old code), with demo mode on, through Test.Watch.Case: the real IncidentManager and the real Checks over fixture sessions, watches, an incident and its fix request.
/// A FixResult, an ApprovalOutcome or an IncidentCommand is injected from SimMailboxIn (the producers are pinned by Test.Fix.Execute, Test.Bridge.Approval and Test.Web.DismissApi). A test waits at most 10 seconds
/// for the answer (a test bound, not an NFR).
///   - TestResolvedFixIsCheckedAtOnce (AC 4; matrix "Integration: resolved"): session S watches Orders (due a day ahead; the row says failed, "A fix running"), T watches Orders
///     too and S watches ZZNS/Zz.Production. S's incident on OCUORDERS/Orders is fixing with R1 approved, and a final FixResult for R1 goes to IncidentManager. Within 10 seconds
///     check_status for S gives Orders passed with no finding and a checked time after the send, and /state's rail shows the same run. One check event, FromRow of the row, is
///     on S's stream, the run is in the incident's trace session, NextDueAt is unchanged, and T's row and S's ZZNS row are unchanged;
///   - TestRejectedFixIsCheckedAtOnce (AC 4; "Integration: rejected"): as above with the incident awaiting approval, R1 rejected and the row failed, "A fix waiting for your
///     approval"; an ApprovalOutcome rejected makes check_status give failed, "An open incident" within 10 seconds, with the same row, event and trace assertions.
///   - TestDismissedIncidentIsCheckedAtOnce (AC 1 and AC 4, DW-957; matrix "Dismissed" at the real-runtime level): as above with S's noticed incident open (no request) and the
///     row failed, "An open incident"; an IncidentCommand dismiss from S makes check_status give Orders passed with no finding within 10 seconds, with the same row, event and
///     trace assertions.
/// The milliseconds from the send to the answer that shows the new run are logged. The sessions, rows, incidents, requests and messages are removed after each test.
Class OcuTalon.Test.Checks.AfterResolve Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzresolve";

/// The longest a test waits for the answer, in seconds.
Parameter WAITANSWER = 10;

/// The fields of the run that a CheckNow must leave alone in the rows of T and of S's other watch.
Parameter RUNFIELDS = "LastRunAt,Result,Finding,LastRunHeaderId,NextDueAt";

Method TestResolvedFixIsCheckedAtOnce()
{
	If '..Ready() Quit
	Do ..Scenario("resolved", "fixing", "done", "A fix running", "passed", "")
}

Method TestRejectedFixIsCheckedAtOnce()
{
	If '..Ready() Quit
	Do ..Scenario("rejected", "awaiting_approval", "rejected", "A fix waiting for your approval", "failed", "An open incident")
}

Method TestDismissedIncidentIsCheckedAtOnce()
{
	If '..Ready() Quit
	Do ..Scenario("dismissed", "open", "", "An open incident", "passed", "")
}

/// One scenario: S's incident in the state with R1 in the request state (none when it is empty), the Orders row of S saying failed with the finding, then the message of
/// the kind (resolved: a final FixResult; rejected: an ApprovalOutcome rejected; dismissed: an IncidentCommand dismiss from S) goes to IncidentManager; the answer must
/// give the result and the finding within WAITANSWER seconds.
Method Scenario(kind As %String, state As %String, requestState As %String, before As %String, result As %String, finding As %String) [ Private ]
{
	Set s = ..Session("s")
	Set t = ..Session("t")
	Set started = ##class(OcuTalon.Data.Time).NowUtc()
	Set due = ..Ahead()
	Set orders = ..Orders(s, started, due, before)
	Set theirs = ..Orders(t, started, due, "")
	Set other = ##class(OcuTalon.Test.Data.Fixture).Check(s, "ZZNS", "Zz.Production", {"DisplayName": "Zz", "AskedBy": "zzfixture", "CreatedAt": (started), "NextDueAt": (due)})
	Set ..Refs = ..Refs_","_other
	Set trace = 910000000 + $Increment(^OcuTalonTest("AfterResolve", "trace"))
	Set ..ExecuteSessions = ..ExecuteSessions _ $Select(..ExecuteSessions = "": "", 1: ",") _ trace
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(s, started, ..#ORDERS, ..#ORDERSPRODUCTION, {"State": (state), "OpenVariant": "", "TraceHeaderId": (trace)})
	Set approval = ""
	Set ..Refs = ..Refs_","_incident
	If requestState '= "" {
		Set approval = ##class(OcuTalon.Test.Data.Fixture).Approval(s, incident, requestState, , {"AnsweredChannel": "web", "AnsweredAt": (started)})
		Set ..Refs = ..Refs_","_approval
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Set row.RequestRefs = approval
		Do $$$AssertStatusOK(row.%Save(), "the incident lists its request")
		Kill row
	}
	Set unrelated = ..Unrelated(s, incident)
	Do $$$AssertEquals(unrelated, "", "no other unclosed incident of "_..#ORDERS_"/"_..#ORDERSPRODUCTION_" is in S's scope (a leftover would change the answer): "_unrelated)
	If unrelated '= "" Quit
	Set unchanged = ..Fields(theirs)_"|"_..Fields(other)
	Set expectedDue = ..Check(orders).NextDueAt
	Do $$$AssertEquals(expectedDue, due, "S's Orders row is due a day ahead")
	Do ..Begin(s, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set answer = ..OrdersEntry()
	Do $$$AssertEquals(answer.result_"|"_answer.finding, "failed|"_before, "before the message, the answer still reads the old run")
	Set sentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set begun = $ZHorolog
	Set final = $Select(kind = "resolved": "resolved", kind = "dismissed": "closed", 1: "open")
	If kind = "dismissed" {
		Set message = ##class(OcuTalon.Msg.IncidentCommand).%New()
		Set message.Verb = "dismiss"
		Set message.IncidentRef = incident
		Set message.SessionRef = s
		Set message.Origin = "web_user"
	} ElseIf kind = "resolved" {
		Set message = ##class(OcuTalon.Fix.Msg.FixResult).%New()
		Set message.ApprovalRef = approval
		Set message.IncidentRef = incident
		Set message.Final = 1
		Set message.Total = 3
		Set message.Resent = 3
		Set message.Completed = 3
	} Else {
		Set message = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
		Set message.ApprovalRef = approval
		Set message.IncidentRef = incident
		Set message.Outcome = "rejected"
	}
	Do $$$AssertStatusOK(..SendToManager(message), "the "_message.%ClassName()_" is sent to IncidentManager")
	Set end = begun + ..#WAITANSWER
	Set elapsed = ""
	For {
		Set answer = ..OrdersEntry()
		If (answer.result = result) && (answer.finding = finding) {
			Set elapsed = ($ZHorolog - begun) * 1000 \ 1
			Quit
		}
		If $ZHorolog > end Quit
		Hang 0.25
	}
	Do $$$AssertEquals(answer.result_"|"_answer.finding, result_"|"_finding, "within "_..#WAITANSWER_" seconds check_status gives Orders "_result_$Select(finding = "": ", with no finding", 1: ", '"_finding_"'"))
	Do $$$LogMessage("the answer showed the new run "_elapsed_" ms after the "_kind_" message was sent")
	Do $$$AssertTrue(answer.checked '= "", "with a checked time: "_answer.checked)
	Do $$$AssertEquals(..WaitIncidentState(incident, final, ..#WAITANSWER), final, "the incident is "_final)
	Set check = ..Check(orders)
	Do $$$AssertEquals(check.Result_"|"_check.Finding, result_"|"_finding, "S's row holds the run")
	Do $$$AssertTrue('(sentAt ] check.LastRunAt), "which ran after the send: "_check.LastRunAt_" against "_sentAt)
	Do $$$AssertEquals(check.LastRunHeaderId, trace, "in the incident's trace session")
	Do $$$AssertEquals(check.NextDueAt, expectedDue, "and NextDueAt is unchanged")

	// the rail and the event
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(s))
	Set found = ""
	Set iterator = body.rail.checks.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.ref = orders Set found = entry
	}
	Do $$$AssertTrue($IsObject(found), "/state lists the Orders check")
	If $IsObject(found) {
		Do $$$AssertEquals(found.lastRunAt_"|"_found.result, check.LastRunAt_"|"_result, "with the same run")
		Do $$$AssertEquals(found.traceHeaderId, trace, "and the incident's trace session")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(s, "check", 1, ..#WAITANSWER)
	Hang 1
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(s, "check")
	Do $$$AssertEquals(events.%Size(), 1, "exactly one check event is on S's stream")
	Do ##class(OcuTalon.Live.Payload.Check).FromRow(..Check(orders)).%JSONExportToString(.expected)
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), expected, "and it is FromRow of the row")

	// the rows that must not change
	Do $$$AssertEquals(..Fields(theirs)_"|"_..Fields(other), unchanged, "T's Orders row and S's row of the other production are unchanged")
}

/// A fixture row: the session watches Orders, created at the time and due at due; with a finding it holds an earlier run (LastRunAt the time, so that the read window
/// starts then; result failed, that finding, not the trace of any session). Its Ref.
Method Orders(session As %String, started As %String, due As %String, finding As %String) As %String [ Private ]
{
	Set fields = {"DisplayName": "Orders", "AskedBy": "zzfixture", "CreatedAt": (started), "NextDueAt": (due)}
	If finding '= "" {
		Do fields.%Set("LastRunAt", started)
		Do fields.%Set("Result", "failed")
		Do fields.%Set("Finding", finding)
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, ..#ORDERS, ..#ORDERSPRODUCTION, fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The Refs, comma-separated, of the other unclosed incidents of the namespace and production that count for the session (its own and the instance's).
Method Unrelated(session As %String, incident As %String) As %String [ Private ]
{
	Set list = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Incident WHERE Namespace = ? AND Production = ? AND State IN ('open', 'awaiting_approval', 'fixing') AND (OwnerRef = ? OR OwnerRef = 'instance') AND Ref <> ?", ..#ORDERS, ..#ORDERSPRODUCTION, session, incident)
	While rs.%Next() {
		Set list = list_$Select(list = "": "", 1: ",")_rs.%GetData(1)
	}
	Quit list
}

/// check_status for the session of the begun context: the entry of Orders, {result, finding, checked}, or empty strings when it has none.
Method OrdersEntry() As %DynamicObject [ Private ]
{
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Set found = {"result": "", "finding": "", "checked": ""}
	If '$IsObject(answer.checks) Quit found
	Set name = $Replace($Parameter("OcuTalon.Tools.WatchAnswers", "ENTRY"), "{name}", "Orders")
	Set iterator = answer.checks.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.entry = name Set found = entry
	}
	Quit found
}

/// The run fields of the row, as text.
Method Fields(ref As %String) As %String [ Private ]
{
	Set row = ..Check(ref)
	Set text = ""
	For i = 1:1:$Length(..#RUNFIELDS, ",") {
		Set text = text_$Select(text = "": "", 1: ";")_$Property(row, $Piece(..#RUNFIELDS, ",", i))
	}
	Quit text
}

/// A BackgroundCheck row as stored now.
ClassMethod Check(ref As %String) As OcuTalon.Data.BackgroundCheck [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// Sends the message to the IncidentManager item from the SimMailboxIn service (an adapterless host, in a session of its own), asynchronously. The session is kept in
/// ExecuteSessions, so that DropExecuteSessions removes it. The status of the send.
Method SendToManager(message As Ens.Request) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	If $$$ISERR(sc) Quit sc
	Set sc = service.SendRequestAsync(..#MANAGER, message)
	Set ..ExecuteSessions = ..ExecuteSessions _ $Select(..ExecuteSessions = "": "", 1: ",") _ service.%SessionId
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", $Piece(..Sessions, ",", i))
	}
	Quit ##super(testname)
}

}
