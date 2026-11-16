Include Ensemble

/// End-to-end tests of the escalation timer of the paging owner over the running production (Story 24.3b; AD-1, AD-5, AD-18, AD-19, AD-23, AD-25, AD-26, AD-27).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where the production does not run, every
/// test fails with that reason. An escalation is a SetReminder of Kind escalation that only the paging owner (origin system) may send; its row is owned by instance, never by a session.
/// The tests use fixture Refs (zzescp<run><name>, zzesci<run><name>) for the pages and incidents the timer only carries, and a real IncidentManager, with the rows a page would have,
/// where the backup is paged.
///   - TestAskMakesOneInstanceRow (AC1): the ask answers Ok 1 set with a Ref and the DueAt, one pending instance row of Kind escalation with both Refs and no Text, one live waiter
///     whose start header comes from ReminderOps with an empty SuperSession, and no live event;
///   - TestAskAgainSameRow (V2): the same page asked again, in each state of its first row, gets that row's Ref and DueAt and adds no row and no waiter; another page gets its own row;
///   - TestOnlySystemMayAsk (AC1, AD-1): web_user, web_admin, telegram, timer and tool (a bridge context), with a session given or missing, get not_allowed with CommandsIn's
///     sentence, before any session is looked up, and nothing is written; Kind other from system stays not_built; the same ask from system is the positive control;
///   - TestBadFieldsRefused (AC1): an empty IncidentRef or PageRef, a DelaySeconds that is empty, 0 or negative, and a DueAt or LocalDueAt, are refused bad_time and store nothing;
///   - TestOnlineDemoWritesNothing (V1c): on the online demo a valid ask is not_allowed, and no row, no ReminderStart and no ReminderTimer is made;
///   - TestNotInAnyList (AC5): an ask that names a session still makes an instance row, which is in no ListReminders answer, no Ownership reminder reader and no reminder event of that session;
///   - TestCancelFromSystem (AC2): a CancelReminder from system cancels the pending row under its lock with the command's key, ends its waiter at once and sends no Escalation; a row that
///     is not pending, and the same cancel from a session, are no_reminder and change nothing;
///   - TestDueSendsOneEscalation (AC2, V1c): at the due time exactly one Msg.Escalation (IncidentRef, PageRef) goes from ReminderTimer to IncidentManager and no request to Notify, even
///     with a second waiter started by Rearm, and the row is fired;
///   - TestRestartRearmsOnce (AC4, V1c): with the production stopped and started, a lost waiter is re-armed exactly once with an empty SuperSession, a timer that fell due fires once, a row
///     with a live waiter is left alone, and a second Reconcile starts nothing;
///   - TestBackupPagedOnceUnlessAcknowledged (AC3, V2): through the real IncidentManager, an unacknowledged on-call page of an open incident gets exactly one backup page when its escalation
///     falls due; a page acknowledged through AckPage first has its escalation cancelled and gets none.
/// The base's guard, fixture sessions, run number and clean-up are those of Test.Core.InProduction. OnAfterOneTest removes every escalation row of the test's pages with its waiters and
/// trace sessions (ReminderFixture.Remove), the trace sessions of the commands it sent (ReminderFixture.RemoveTraces) and the page rows and Delivery rows of its incidents, and starts
/// the production again when a test left it stopped. The online demo flag and the on-call keys are put back after the run.
Class OcuTalon.Test.Schedule.Escalations Extends OcuTalon.Test.Core.InProduction [ DependsOn = (OcuTalon.Test.Watch.Paging, OcuTalon.Test.Schedule.ReminderFixture) ]
{

Parameter SESSIONPREFIX = "zzescal";

/// Seconds to wait for a timer to fire, and for something that must not happen to have had its chance.
Parameter FIRESECONDS = 40;

Parameter QUIET = 4;

Parameter WAIT = 30;

/// The delay of the escalation C of TestRestartRearmsOnce in seconds: longer than the stop and the start, so that it falls due after the start.
Parameter RESTARTDELAY = 45;

/// The Refs of the pages whose escalation rows the test removes (a fixture Ref, or a real page's), comma-separated.
Property PageRefs As %String(MAXLEN = "");

/// The ids of the SetReminder and CancelReminder bodies of the commands that the tests sent, comma-separated.
Property SetBodies As %String(MAXLEN = "");

Property CancelBodies As %String(MAXLEN = "");

/// The incidents of the test, whose page rows and Delivery rows are removed.
Property Incidents As %String(MAXLEN = "");

/// The online demo flag before the run.
Property Online As %String;

/// The Refs of the session reminders that a test made, comma-separated.
Property Reminders As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..Online = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Test.Watch.Paging).SaveKeys()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Online)
	Do ##class(OcuTalon.Test.Watch.Paging).PutKeysBack()
	Quit ##super()
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Online)
	If (..Missing = "") && '##class(Ens.Director).IsItemEnabled("ReminderTimer") Do ##class(Ens.Director).EnableConfigItem("ReminderTimer", 1, 1)
	If (..Missing = "") && '##class(Ens.Director).IsProductionRunning() Do ##class(OcuTalon.Install.Step.Production).Start()
	For i = 1:1:$Length(..PageRefs, ",") {
		If $Piece(..PageRefs, ",", i) = "" Continue
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Reminder WHERE Kind = 'escalation' AND PageRef = ?", $Piece(..PageRefs, ",", i))
		Set refs = ""
		While result.%Next() {
			Set refs = refs _ $ListBuild(result.%Get("Ref"))
		}
		Set result = ""
		Set position = 0
		While $ListNext(refs, position, ref) {
			Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(ref)
		}
	}
	For i = 1:1:$Length(..Incidents, ",") {
		Set incident = $Piece(..Incidents, ",", i)
		If incident = "" Continue
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Page WHERE IncidentRef = ?", incident)
		While result.%Next() {
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE DecisionRef = ?", result.%Get("Ref"))
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Page WHERE IncidentRef = ?", incident)
	}
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTraces($ListFromString(..SetBodies, ","), "OcuTalon.Msg.Command.SetReminder")
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTraces($ListFromString(..CancelBodies, ","), "OcuTalon.Msg.Command.CancelReminder")
	For i = 1:1:$Length(..Reminders, ",") {
		If $Piece(..Reminders, ",", i) '= "" Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove($Piece(..Reminders, ",", i))
	}
	Set ..Reminders = ""
	Set ..PageRefs = "", ..SetBodies = "", ..CancelBodies = "", ..Incidents = ""
	Quit $$$OK
}

/// A fixture page Ref of the run, which the clean-up removes the escalation rows of.
Method Page(name As %String) As %String [ Private ]
{
	Set ref = "zzescp" _ ..Number _ name
	Set ..PageRefs = ..PageRefs _ $Select(..PageRefs = "": "", 1: ",") _ ref
	Quit ref
}

/// A fixture incident Ref that no row has: the timer only carries it.
ClassMethod IncidentRef(name As %String) As %String [ Private ]
{
	Quit "zzesci" _ name
}

/// A real incident of the instance, open, and its Ref; its page rows and their Delivery rows are removed by the clean-up, the row itself by the base's.
Method RealIncident() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , , , {"Cause": "zz escalation cause"})
	Set ..Refs = ..Refs _ "," _ ref
	Set ..Incidents = ..Incidents _ $Select(..Incidents = "": "", 1: ",") _ ref
	Quit ref
}

/// An escalation SetReminder for the page, with the delay (and the session when given), submitted from the origin; the CommandResult, or "" when Submit gave an error status. A tool origin is
/// submitted under the bridge context of the session (ReminderFixture.Submit), as the chat's tool call has it.
Method Ask(origin As %String, incident As %String, page As %String, delay As %String, session As %String = "", fields As %DynamicObject = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.Kind = "escalation"
	Set command.IncidentRef = incident
	Set command.PageRef = page
	Set command.DelaySeconds = delay
	Set command.SessionRef = session
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Set $Property(command, key) = value
		}
	}
	Set result = ""
	If origin = "tool" {
		Set result = ##class(OcuTalon.Test.Schedule.ReminderFixture).Submit(session, command)
	} Else {
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
		If $$$ISERR(sc) Set result = ""
	}
	If command.%Id() '= "" Set ..SetBodies = ..SetBodies _ $Select(..SetBodies = "": "", 1: ",") _ command.%Id()
	Quit result
}

/// A CancelReminder for the Ref from the origin (with the session when given), submitted through Commands.Submit; the CommandResult, or "" when Submit gave an error status.
Method Cancel(origin As %String, ref As %String, key As %String, session As %String = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Set command.ReminderRef = ref
	Set command.IdempotencyKey = key
	Set command.SessionRef = session
	Set result = ""
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
	If $$$ISERR(sc) Set result = ""
	If command.%Id() '= "" Set ..CancelBodies = ..CancelBodies _ $Select(..CancelBodies = "": "", 1: ",") _ command.%Id()
	Quit result
}

/// The number of escalation rows of the page, in any state.
ClassMethod Rows(page As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE Kind = 'escalation' AND PageRef = ?", page)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of rows of a table of the Schedule package or of Reminder (a whole-table count: nothing else starts a waiter in these tests).
ClassMethod Count(table As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of reminder events on the instance stream.
ClassMethod InstanceReminderEvents() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events("instance", "reminder").%Size()
}

/// The number of requests of the body class from ReminderTimer to the target in the trace sessions of every start header of the Ref.
ClassMethod Sent(ref As %String, target As %String, bodyClass As %String = "") As %Integer [ Private ]
{
	Set headers = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref)
	Set count = 0
	For i = 0:1:headers.%Size() - 1 {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(headers.%Get(i).sessionId), 1, "ReminderTimer", target)
		For k = 0:1:sent.%Size() - 1 {
			If (bodyClass = "") || (sent.%Get(k).bodyClass = bodyClass) Set count = count + 1
		}
	}
	Quit count
}

/// The number of ReminderStart headers of the Ref.
ClassMethod Starts(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref).%Size()
}

/// The number of live waiters of the Ref.
ClassMethod Waiting(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(ref)
}

/// The text of the CommandsIn refusal that an ask from a wrong origin gets.
ClassMethod NotAllowed() As %String [ Private ]
{
	Quit ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED
}

/// The answer as "Ok|outcome", or "none" when there was no answer.
ClassMethod Verdict(result As OcuTalon.Msg.CommandResult) As %String [ Private ]
{
	Quit $Select($IsObject(result): result.Ok _ "|" _ result.Outcome, 1: "none")
}

/// A pending escalation row made directly (a fixture row, as a lost waiter leaves it) and its Ref; removed by the clean-up with the page.
Method Row(page As %String, incident As %String, dueAt As %String, state As %String = "pending") As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Reminder(##class(OcuTalon.Schedule.Reminder).#OWNER, dueAt, state, {"Kind": "escalation", "IncidentRef": (incident), "PageRef": (page), "Text": ""})
}

/// The ask of the paging owner: Ok 1, set, the Ref and DueAt; one pending instance row of Kind escalation with the two Refs and no Text; one live waiter whose one start header comes from
/// ReminderOps with an empty SuperSession and begins its own trace session (there is no session TraceRef for instance); no live event on the instance stream.
Method TestAskMakesOneInstanceRow()
{
	If '..Guard() Quit
	Set page = ..Page("a"), incident = ..IncidentRef("a" _ ..Number)
	Set events = ..InstanceReminderEvents()
	Set start = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Set result = ..Ask("system", incident, page, 600)
	Do $$$AssertEquals(..Verdict(result), "1|set", "the ask from system is set")
	If '$IsObject(result) Quit
	Do $$$AssertTrue(result.Ref '= "", "the answer has the Ref")
	Do $$$AssertTrue($Match(result.DueAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "and a DueAt, UTC to the second")
	Set due = ##class(OcuTalon.Data.Time).Seconds(result.DueAt)
	Do $$$AssertTrue((due - start >= 598) && (due - start <= 625), "which is now plus the delay of 600 seconds")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.SessionRef _ "|" _ row.Kind _ "|" _ row.IncidentRef _ "|" _ row.PageRef _ "|" _ row.Text _ "|" _ row.State _ "|" _ row.Late, "instance|escalation|" _ incident _ "|" _ page _ "||pending|0", "it is a pending instance row of Kind escalation with both Refs and no Text")
	Do $$$AssertEquals(row.DueAt, result.DueAt, "with the answered DueAt")
	Do $$$AssertTrue($Match(row.CreatedAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "created at a UTC time")
	Do $$$AssertTrue(row.TraceHeaderId > 0, "the row keeps its waiter's header id")
	Set traceId = row.TraceHeaderId
	Set row = ""
	Do $$$AssertEquals(..Rows(page), 1, "the page has one escalation row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(result.Ref).%Size(), 1, "one ReminderTimer has the Ref")
	Do $$$AssertEquals(..Waiting(result.Ref), 1, "and it is live")
	Set starts = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(result.Ref)
	Do $$$AssertEquals(starts.%Size(), 1, "one start header names the Ref")
	If starts.%Size() = 1 {
		Do $$$AssertEquals(starts.%Get(0).source _ "|" _ starts.%Get(0).target _ "|" _ starts.%Get(0).superSession, "ReminderOps|ReminderTimer|", "it comes from ReminderOps with an empty SuperSession")
		Do $$$AssertEquals(starts.%Get(0).id _ "|" _ starts.%Get(0).sessionId, traceId _ "|" _ traceId, "and is the first header of the waiter's own trace session, the row's TraceHeaderId")
	}
	Do $$$AssertEquals(..InstanceReminderEvents(), events, "no live event was published on the instance stream")
}

/// V2, at most one escalation to the backup per page: the same page asked again gets the first row's Ref and DueAt while that row is pending, fired and cancelled, with one row and one
/// waiter; another page gets a row of its own.
Method TestAskAgainSameRow()
{
	If '..Guard() Quit
	Set page = ..Page("b"), incident = ..IncidentRef("b" _ ..Number)
	Set first = ..Ask("system", incident, page, 600)
	Do $$$AssertEquals(..Verdict(first), "1|set", "the first ask is set")
	If '$IsObject(first) Quit
	Set again = ..Ask("system", incident, page, 900)
	Do $$$AssertEquals(..Verdict(again), "1|set", "the same page asked again is set")
	If $IsObject(again) Do $$$AssertEquals(again.Ref _ "|" _ again.DueAt, first.Ref _ "|" _ first.DueAt, "with the first row's Ref and DueAt, not a new delay")
	Do $$$AssertEquals(..Rows(page) _ "|" _ ##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(first.Ref).%Size() _ "|" _ ..Starts(first.Ref), "1|1|1", "one row, one waiter and one start header")
	For state = "fired", "cancelled" {
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(first.Ref)
		Set row.State = state
		Do $$$AssertStatusOK(row.%Save(), "the row is " _ state)
		Set row = ""
		Set again = ..Ask("system", incident, page, 300)
		Do $$$AssertEquals(..Verdict(again), "1|set", "asked again when " _ state)
		If $IsObject(again) Do $$$AssertEquals(again.Ref _ "|" _ again.DueAt, first.Ref _ "|" _ first.DueAt, "it is still the first row's Ref and DueAt")
		Do $$$AssertEquals(..Rows(page), 1, "and there is still one row")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(first.Ref).%Size(), 1, "and one waiter")
	Set other = ..Page("c")
	Set second = ..Ask("system", incident, other, 600)
	Do $$$AssertEquals(..Verdict(second), "1|set", "control: another page is set")
	If $IsObject(second) Do $$$AssertTrue(second.Ref '= first.Ref, "with a row of its own")
	Do $$$AssertEquals(..Rows(other), 1, "one row for the other page")
}

/// AC1 and AD-1: from web_user, web_admin, telegram and timer, with a session given or missing, and from tool under a bridge context, the ask is Ok 0, not_allowed, with CommandsIn's
/// sentence, and no row names the page. The refusal comes before the session is looked up, so a missing session is not_allowed, not no_session. Kind other from system stays not_built.
/// The same ask from system, at the end, is the positive control. No ReminderStart and no ReminderTimer is made by any refusal.
Method TestOnlySystemMayAsk()
{
	If '..Guard() Quit
	Set page = ..Page("d"), incident = ..IncidentRef("d" _ ..Number)
	Set session = ..Session("origin")
	Set missing = "zznosess" _ ..Number
	Set starts = ..Count("OcuTalon_Schedule.ReminderStart"), timers = ..Count("OcuTalon_Schedule.ReminderTimer")
	For origin = "web_user", "web_admin", "telegram", "timer" {
		For given = session, missing {
			Set result = ..Ask(origin, incident, page, 600, given)
			Do $$$AssertEquals(..Verdict(result), "0|not_allowed", "from " _ origin _ " with " _ $Select(given = session: "a session", 1: "a missing session") _ ": not_allowed")
			If $IsObject(result) Do $$$AssertEquals(result.Message, ..NotAllowed(), "with CommandsIn's sentence")
		}
	}
	Set result = ..Ask("tool", incident, page, 600, session)
	Do $$$AssertEquals(..Verdict(result), "0|not_allowed", "from tool under a bridge context: not_allowed")
	If $IsObject(result) Do $$$AssertEquals(result.Message, ..NotAllowed(), "with CommandsIn's sentence")
	Do $$$AssertEquals(..Rows(page), 0, "no row names the page")
	Do $$$AssertEquals(..Count("OcuTalon_Schedule.ReminderStart") _ "|" _ ..Count("OcuTalon_Schedule.ReminderTimer"), starts _ "|" _ timers, "and no waiter was started")
	Set other = ..Ask("system", incident, page, 600, "", {"Kind": "other"})
	Do $$$AssertEquals(..Verdict(other), "0|not_built", "Kind other from system stays not_built")
	Do $$$AssertEquals(..Rows(page), 0, "and stores nothing")
	Set control = ..Ask("system", incident, page, 600, missing)
	Do $$$AssertEquals(..Verdict(control), "1|set", "positive control: the same ask from system is set, whatever the session it names")
	Do $$$AssertEquals(..Rows(page), 1, "and makes the page's one row")
}

/// AC1: an empty IncidentRef or PageRef, a DelaySeconds that is empty, 0 or negative, a DueAt and a LocalDueAt are refused bad_time with the Message of ReminderOps, and store nothing. A DelaySeconds
/// that is not a number (x) fails the command's own integer validation before ReminderOps, which answers failed and stores nothing.
Method TestBadFieldsRefused()
{
	If '..Guard() Quit
	Set page = ..Page("e"), incident = ..IncidentRef("e" _ ..Number)
	Set message = $Parameter("OcuTalon.Schedule.ReminderOps", "MESSAGEBADTIME")
	Set starts = ..Count("OcuTalon_Schedule.ReminderStart")
	Set cases = $ListBuild($ListBuild("an empty IncidentRef", "", page, 600, ""), $ListBuild("an empty PageRef", incident, "", 600, ""), $ListBuild("an empty DelaySeconds", incident, page, "", ""), $ListBuild("a DelaySeconds of 0", incident, page, 0, ""), $ListBuild("a negative DelaySeconds", incident, page, -5, ""), $ListBuild("a DueAt", incident, page, 600, "DueAt"), $ListBuild("a LocalDueAt", incident, page, 600, "LocalDueAt"), $ListBuild("a DueAt and no delay", incident, page, "", "DueAt"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set fields = ""
		If $List(case, 5) = "DueAt" Set fields = {"DueAt": "2099-01-01T00:00:00Z"}
		If $List(case, 5) = "LocalDueAt" Set fields = {"LocalDueAt": "2099-01-01T00:00:00"}
		Set result = ..Ask("system", $List(case, 2), $List(case, 3), $List(case, 4), "", fields)
		Do $$$AssertEquals(..Verdict(result), "0|refused", $List(case, 1) _ " is refused")
		If $IsObject(result) Do $$$AssertEquals(result.Message, message, "with the bad_time Message")
		Do $$$AssertEquals(..Rows(page) _ "|" _ ..Count("OcuTalon_Schedule.ReminderStart"), "0|" _ starts, $List(case, 1) _ " stores nothing and starts no waiter")
	}
	// A DelaySeconds that is not a number never reaches ReminderOps: the command's own integer property fails its validation when the message is saved, and Commands.Submit answers failed.
	Set result = ..Ask("system", incident, page, "x")
	Do $$$AssertEquals(..Verdict(result), "0|failed", "a DelaySeconds that is not a number is answered failed by the message's own validation")
	Do $$$AssertEquals(..Rows(page) _ "|" _ ..Count("OcuTalon_Schedule.ReminderStart"), "0|" _ starts, "and stores nothing and starts no waiter")
	Set control = ..Ask("system", incident, page, 600)
	Do $$$AssertEquals(..Verdict(control), "1|set", "positive control: a whole delay above 0 with both Refs is set")
}

/// V1c, nothing is written on the online demo: a valid ask from system is Ok 0, not_allowed, with no row, no ReminderStart and no ReminderTimer. Control: with the flag off the same ask is set.
Method TestOnlineDemoWritesNothing()
{
	If '..Guard() Quit
	Set page = ..Page("f"), incident = ..IncidentRef("f" _ ..Number)
	Set rows = ..Count("OcuTalon_Data.Reminder"), starts = ..Count("OcuTalon_Schedule.ReminderStart"), timers = ..Count("OcuTalon_Schedule.ReminderTimer")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..Ask("system", incident, page, 600)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(..Verdict(result), "0|not_allowed", "on the online demo the ask is not_allowed")
	If $IsObject(result) Do $$$AssertEquals(result.Message, ..NotAllowed(), "with CommandsIn's sentence")
	Do $$$AssertEquals(..Rows(page), 0, "no row names the page")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Reminder") _ "|" _ ..Count("OcuTalon_Schedule.ReminderStart") _ "|" _ ..Count("OcuTalon_Schedule.ReminderTimer"), rows _ "|" _ starts _ "|" _ timers, "and no Reminder row, no ReminderStart and no ReminderTimer was made")
	Set control = ..Ask("system", incident, page, 600)
	Do $$$AssertEquals(..Verdict(control), "1|set", "control: with the flag off, the same ask is set")
}

/// AC5: an ask that names a session makes a row owned by instance. It is in no ListReminders answer of the session, in none of the three Ownership reminder readers and in no reminder
/// event of the session. A reminder of the session is the positive control for each reader.
Method TestNotInAnyList()
{
	If '..Guard() Quit
	Set page = ..Page("g"), incident = ..IncidentRef("g" _ ..Number)
	Set session = ..Session("list")
	Set result = ..Ask("system", incident, page, 600, session)
	Do $$$AssertEquals(..Verdict(result), "1|set", "the ask that names a session is set")
	If '$IsObject(result) Quit
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(row.SessionRef, ##class(OcuTalon.Schedule.Reminder).#OWNER, "its row is owned by instance, not by the session")
	Set row = ""
	Set mine = ##class(OcuTalon.Test.Schedule.ReminderFixture).Set(session, "zz own " _ ..Number, 600)
	Do $$$AssertEquals(mine.ok _ "|" _ mine.outcome, "1|set", "control: a reminder of the session is set")
	Set ..Reminders = ..Reminders _ $Select(..Reminders = "": "", 1: ",") _ mine.ref
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.SessionRef = session
	Set listed = ##class(OcuTalon.Test.Schedule.ReminderFixture).Submit(session, command)
	Do $$$AssertEquals(..Verdict(listed), "1|listed", "the session's ListReminders is answered")
	If $IsObject(listed) {
		Set data = {}.%FromJSON(listed.Data)
		Do $$$AssertEquals(data.reminders.%Size(), 1, "it lists one reminder")
		If data.reminders.%Size() = 1 Do $$$AssertEquals(data.reminders.%Get(0).ref, mine.ref, "which is the session's own, not the escalation")
	}
	Set rows = ##class(OcuTalon.Data.Ownership).Reminders(session, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "Ownership.Reminders gives only the session's own")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Ref, mine.ref, "")
	Set newest = ##class(OcuTalon.Data.Ownership).ReminderSetOrFired(session, .sc)
	Do $$$AssertEquals($Select($IsObject(newest): newest.Ref, 1: ""), mine.ref, "Ownership.ReminderSetOrFired is the session's own")
	Set notes = ##class(OcuTalon.Data.Ownership).NoteReminders(session, "2000-01-01T00:00:00Z", "2100-01-01T00:00:00Z", .sc)
	Do $$$AssertEquals(notes.Count(), 1, "Ownership.NoteReminders gives only the session's own")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 1, ..#WAIT)
	Do $$$AssertEquals(events.%Size(), 1, "the session's reminder events are its own reminder's alone")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref, mine.ref, "")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Do $$$AssertEquals($Find(body, result.Ref), 0, "and the session's /state holds no escalation Ref")
}

/// AC2: a CancelReminder from system for the pending row cancels it with the command's key as CancelKey, answers Ok 1 cancelled with the Ref and DueAt, ends the waiter at once (the delay
/// is 600 seconds) and sends no Escalation. A second cancel, and one for a row that is fired, are no_reminder. The same cancel from a session origin, with the session, is no_reminder and
/// the row stays pending and keeps its waiter. A cancel names no session, which the system path does not need.
Method TestCancelFromSystem()
{
	If '..Guard() Quit
	Set page = ..Page("h"), incident = ..IncidentRef("h" _ ..Number)
	Set session = ..Session("cancel")
	Set events = ..InstanceReminderEvents()
	Set result = ..Ask("system", incident, page, 600)
	Do $$$AssertEquals(..Verdict(result), "1|set", "the ask is set")
	If '$IsObject(result) Quit
	Set sessionCancel = ..Cancel("web_user", result.Ref, "zzcanweb" _ ..Number, session)
	Do $$$AssertEquals(..Verdict(sessionCancel), "0|refused", "a cancel of the escalation from a session origin is refused")
	If $IsObject(sessionCancel) Do $$$AssertEquals(sessionCancel.Message, $Parameter("OcuTalon.Schedule.ReminderOps", "MESSAGENOREMINDER"), "as no_reminder")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(row.State _ "|" _ row.CancelKey, "pending|", "the row stays pending")
	Set row = ""
	Do $$$AssertEquals(..Waiting(result.Ref), 1, "and keeps its waiter")
	Set key = "zzcansys" _ ..Number
	Set start = $ZHorolog
	Set done = ..Cancel("system", result.Ref, key)
	Do $$$AssertEquals(..Verdict(done), "1|cancelled", "the cancel from system is carried out")
	If $IsObject(done) Do $$$AssertEquals(done.Ref _ "|" _ done.DueAt, result.Ref _ "|" _ result.DueAt, "with the Ref and DueAt")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(row.State _ "|" _ row.CancelKey, "cancelled|" _ key, "the row is cancelled with the command's key")
	Set row = ""
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(result.Ref, 10), "its waiter ends at once, well before its due time")
	Do $$$AssertTrue($ZHorolog - start < 15, "within seconds of the cancel")
	Do $$$AssertEquals(..Sent(result.Ref, "IncidentManager") _ "|" _ ..Sent(result.Ref, "Notify"), "0|0", "and sends no Escalation and no Notification")
	Do $$$AssertEquals(..InstanceReminderEvents(), events, "nothing is published")
	Set again = ..Cancel("system", result.Ref, "zzcansys2" _ ..Number)
	Do $$$AssertEquals(..Verdict(again), "0|refused", "a second cancel is refused")
	If $IsObject(again) Do $$$AssertEquals(again.Message, $Parameter("OcuTalon.Schedule.ReminderOps", "MESSAGENOREMINDER"), "as no_reminder")
	Set fired = ..Page("i")
	Set firedRef = ..Row(fired, incident, "2030-01-01T10:00:00Z", "fired")
	Set none = ..Cancel("system", firedRef, "zzcansys3" _ ..Number)
	Do $$$AssertEquals(..Verdict(none), "0|refused", "a cancel of a fired row is refused")
	If $IsObject(none) Do $$$AssertEquals(none.Message, $Parameter("OcuTalon.Schedule.ReminderOps", "MESSAGENOREMINDER"), "as no_reminder")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(firedRef)
	Do $$$AssertEquals(row.State _ "|" _ row.CancelKey, "fired|", "and changes nothing")
}

/// AC2 and V1c, never pages twice: a row due in a few seconds with a second waiter from Rearm: both wake, the first marks the row fired and sends one Msg.Escalation (IncidentRef, PageRef)
/// from ReminderTimer to IncidentManager, and the second finds the row not pending and sends nothing. No request goes to Notify, and no event is published.
Method TestDueSendsOneEscalation()
{
	If '..Guard() Quit
	Set page = ..Page("j"), incident = ..IncidentRef("j" _ ..Number)
	Set events = ..InstanceReminderEvents()
	Set result = ..Ask("system", incident, page, 6)
	Do $$$AssertEquals(..Verdict(result), "1|set", "the ask is set, due in 6 seconds")
	If '$IsObject(result) Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Rearm(result.Ref), "a second waiter is started")
	Do $$$AssertEquals(..Waiting(result.Ref) _ "|" _ ..Starts(result.Ref), "2|2", "two waiters wait, from two start headers")
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(result.Ref, ..#FIRESECONDS), "both waiters end within " _ ..#FIRESECONDS _ " seconds")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(row.State _ "|" _ row.Late, "fired|0", "the row is fired, not late")
	Set row = ""
	Do $$$AssertEquals(..Sent(result.Ref, "IncidentManager", "OcuTalon.Msg.Escalation"), 1, "exactly one Escalation goes from ReminderTimer to IncidentManager across both waiters")
	Set headers = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(result.Ref)
	Set checked = 0
	For i = 0:1:headers.%Size() - 1 {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(headers.%Get(i).sessionId), 1, "ReminderTimer", "IncidentManager")
		If sent.%Size() = 1 {
			Set body = ##class(OcuTalon.Msg.Escalation).%OpenId(sent.%Get(0).bodyId)
			Do $$$AssertEquals(body.IncidentRef _ "|" _ body.PageRef, incident _ "|" _ page, "it carries the IncidentRef and the PageRef")
			Set checked = checked + 1
		}
	}
	Do $$$AssertEquals(checked, 1, "and exactly one Escalation body was read")
	Do $$$AssertEquals(..Sent(result.Ref, "Notify"), 0, "no request goes to Notify")
	Do $$$AssertEquals(..InstanceReminderEvents(), events, "and nothing is published")
}

/// The restart (AC4, V1c): A is a pending row with no waiter, past its due time; B has no waiter and is due in an hour; C is set through the product with a live waiter, due after the start.
/// The production is stopped and started (so that ReconcileIn runs, as it does after any start the Production step did not make), and after ReconcileIn's Info row: A has fired once (one
/// Escalation, Late) and has had exactly one start header, from HeartbeatIn with an empty SuperSession; B has exactly one start header from HeartbeatIn with an empty SuperSession and one
/// live waiter; C has the one waiter and the one start header it had and fires once at its due time. A second Reconcile starts nothing, and no row sends a second Escalation.
Method TestRestartRearmsOnce()
{
	If '..Guard() Quit
	Set pageA = ..Page("ka"), pageB = ..Page("kb"), pageC = ..Page("kc"), incident = ..IncidentRef("k" _ ..Number)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set a = ..Row(pageA, incident, ##class(OcuTalon.Data.Time).AddSeconds(now, -30))
	Set b = ..Row(pageB, incident, ##class(OcuTalon.Data.Time).AddSeconds(now, 3600))
	Set c = ..Ask("system", incident, pageC, ..#RESTARTDELAY)
	Do $$$AssertEquals(..Verdict(c), "1|set", "C is set through the product, due after the restart")
	If '$IsObject(c) Quit
	Do $$$AssertEquals(..Waiting(a) _ "|" _ ..Waiting(b) _ "|" _ ..Waiting(c.Ref), "0|0|1", "A and B have no waiter, C has its live one")
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.Heartbeat).SettleScheduler(), "the scheduler is settled before the production stops (DW-28)")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set begun = $ZHorolog
	Set sc = ##class(Ens.Director).StopProduction(10, 0)
	Do $$$AssertStatusOK(sc, "the production stops")
	Do ..Timing("stop: " _ $FNumber($ZHorolog - begun, "", 1) _ " s")
	If $$$ISERR(sc) Quit
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 0, "it does not run")
	Set begun = $ZHorolog
	Set sc = ##class(Ens.Director).StartProduction(..#PRODUCTION)
	Do $$$AssertStatusOK(sc, "the production starts again, not through the Production step")
	Do ..Timing("start: " _ $FNumber($ZHorolog - begun, "", 1) _ " s")
	If $$$ISERR(sc) Quit
	Set reconciled = ..WaitReconciled(mark)
	Do ..Timing("ReconcileIn's Info row: " _ $FNumber($ZHorolog - begun, "", 1) _ " s after the start call")
	Do $$$AssertTrue(reconciled, "ReconcileIn logs its Info row after the start")
	If 'reconciled Quit
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(a, ..#FIRESECONDS), "A's new waiter ends within " _ ..#FIRESECONDS _ " seconds of the start")
	Set rowA = ##class(OcuTalon.Data.Reminder).RefIndexOpen(a)
	Do $$$AssertEquals(rowA.State _ "|" _ rowA.Late, "fired|1", "A is fired, late")
	Set rowA = ""
	Do $$$AssertEquals(..Sent(a, "IncidentManager", "OcuTalon.Msg.Escalation") _ "|" _ ..Sent(a, "Notify"), "1|0", "A sent one Escalation and no Notification")
	Set startsA = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(a)
	Do $$$AssertEquals(startsA.%Size(), 1, "A has exactly one start header")
	If startsA.%Size() = 1 Do $$$AssertEquals(startsA.%Get(0).source _ "|" _ startsA.%Get(0).target _ "|" _ startsA.%Get(0).superSession, "HeartbeatIn|ReminderTimer|", "from HeartbeatIn with an empty SuperSession")
	Set startsB = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(b)
	Do $$$AssertEquals(startsB.%Size(), 1, "B has exactly one start header")
	If startsB.%Size() = 1 Do $$$AssertEquals(startsB.%Get(0).source _ "|" _ startsB.%Get(0).target _ "|" _ startsB.%Get(0).superSession, "HeartbeatIn|ReminderTimer|", "from HeartbeatIn with an empty SuperSession")
	Do $$$AssertEquals(..Waiting(b), 1, "and B has one live waiter")
	Set rowB = ##class(OcuTalon.Data.Reminder).RefIndexOpen(b)
	Do $$$AssertEquals(rowB.State _ "|" _ rowB.DueAt, "pending|" _ ##class(OcuTalon.Data.Time).AddSeconds(now, 3600), "B is still pending with its due time")
	Set rowB = ""
	Do $$$AssertEquals(..Starts(c.Ref) _ "|" _ ..Waiting(c.Ref), "1|1", "C has the one start header and the one live waiter it had: a row with a live waiter is left alone")
	Set before = ..Starts(a) _ "|" _ ..Starts(b) _ "|" _ ..Starts(c.Ref)
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(a _ "," _ b _ "," _ c.Ref, .skipped), "a second Reconcile is OK")
	Do $$$AssertEquals(skipped, "", "it skips no row")
	Do $$$AssertEquals(..Starts(a) _ "|" _ ..Starts(b) _ "|" _ ..Starts(c.Ref), before, "and starts nothing")
	Do $$$AssertEquals(..Waiting(b) _ "|" _ ..Waiting(c.Ref), "1|1", "B and C still have one waiter each")
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(c.Ref, ..#RESTARTDELAY + ..#FIRESECONDS), "C fires at its due time")
	Set rowC = ##class(OcuTalon.Data.Reminder).RefIndexOpen(c.Ref)
	Do $$$AssertEquals(rowC.State, "fired", "C is fired")
	Set rowC = ""
	Do $$$AssertEquals(..Sent(c.Ref, "IncidentManager", "OcuTalon.Msg.Escalation") _ "|" _ ..Sent(a, "IncidentManager", "OcuTalon.Msg.Escalation") _ "|" _ ..Sent(b, "IncidentManager"), "1|1|0", "C sent one Escalation, A still only one, B none")
}

/// Waits up to FIRESECONDS for ReconcileIn's Info row (Install.ReconcileIn LOGTEXT) after the log mark; 1 when it came.
Method WaitReconciled(mark As %Integer) As %Boolean [ Private ]
{
	Set end = $ZHorolog + ..#FIRESECONDS + 30
	Set found = 0
	For {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND ConfigName = 'ReconcileIn' AND Type = 4 AND Text = ?", mark, ##class(OcuTalon.Install.ReconcileIn).#LOGTEXT)
		Do result.%Next()
		Set found = +result.%GetData(1)
		If found || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit found > 0
}

/// Makes a measured value visible in the output of a run that passes: a log message, and an assert of the status skipped, which ci/iris.sh prints as "SKIP <method>: <text>".
Method Timing(text As %String) [ Private ]
{
	Do $$$LogMessage(text)
	Do ..Manager.LogAssert(2, "Timing", text)
}

/// A real incident row with the page rows that IncidentManager would have made, a configured backup and the escalation timer: the page that is unacknowledged when its escalation falls due
/// gets exactly one backup page row, and it still has exactly one after the quiet time. The page that is acknowledged through AckPage (from the paged person's session) before its
/// escalation falls due has the escalation cancelled by IncidentManager's Followed (the row is cancelled and its waiter ended), and the incident gets no backup page.
Method TestBackupPagedOnceUnlessAcknowledged()
{
	If '..Guard() Quit
	Set n = ..Number
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.channels", "")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.channels", "")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.user", "")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.email", "zzesconcall" _ n _ "@example.test")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.user", "")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.email", "zzescbackup" _ n _ "@example.test")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.escalationMinutes", 15)
	// A: nobody acknowledges
	Set first = ..RealIncident()
	Set pageA = ..PageRow(first, "zzescperson" _ n _ "a@example.test")
	Set askStart = $ZHorolog
	Set resultA = ..Ask("system", first, pageA.Ref, 3)
	Do ..Timing("the escalation ask from the test process (Commands.Submit, ReminderOps, ReminderTimer): " _ $FNumber($ZHorolog - askStart, "", 3) _ " s")
	Do $$$AssertEquals(..Verdict(resultA), "1|set", "A: the escalation is set, due in 3 seconds")
	If '$IsObject(resultA) Quit
	Set end = $ZHorolog + ..#FIRESECONDS
	For {
		Set backups = ..BackupPages(first)
		If backups || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(backups, 1, "A: exactly one backup page row after the escalation falls due")
	Hang ..#QUIET
	Do $$$AssertEquals(..BackupPages(first), 1, "A: and still exactly one after the quiet time")
	Do $$$AssertEquals(..Sent(resultA.Ref, "IncidentManager", "OcuTalon.Msg.Escalation"), 1, "A: from one Escalation")
	// B: the paged person acknowledges first
	Set user = ..Session("ack")
	Set person = ##class(OcuTalon.Data.Session).RefIndexOpen(user).IrisUser
	Set second = ..RealIncident()
	Set pageB = ..PageRow(second, person)
	Set resultB = ..Ask("system", second, pageB.Ref, 12)
	Do $$$AssertEquals(..Verdict(resultB), "1|set", "B: the escalation is set, due in 12 seconds")
	If '$IsObject(resultB) Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.Paging).Armed(pageB.Ref, resultB.Ref), "B: the page records the escalation's Ref")
	Set ackStart = $ZHorolog
	Set sc = ##class(OcuTalon.Core.Commands).Submit(##class(OcuTalon.Test.Watch.Paging).Ack(pageB.Ref, user, "web"), "web_user", .acked)
	Do ..Timing("AckPage from web_user, IncidentManager Followed, the nested CancelReminder from system: " _ $FNumber($ZHorolog - ackStart, "", 3) _ " s")
	Do $$$AssertStatusOK(sc, "B: the acknowledgement is submitted")
	Do $$$AssertEquals(..Verdict(acked), "1|handled", "B: the page is acknowledged")
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(resultB.Ref, 10), "B: the escalation's waiter ended at once, well before its due time")
	Set rowB = ##class(OcuTalon.Data.Reminder).RefIndexOpen(resultB.Ref)
	Do $$$AssertEquals(rowB.State, "cancelled", "B: the row is cancelled by IncidentManager")
	Set rowB = ""
	Hang 12 + ..#QUIET
	Do $$$AssertEquals(..BackupPages(second), 0, "B: no backup page row, after the escalation's due time had passed")
	Do $$$AssertEquals(..Sent(resultB.Ref, "IncidentManager", "OcuTalon.Msg.Escalation"), 0, "B: and no Escalation was sent")
}

/// An on-call page row of the incident for the person, as IncidentManager records it (the Ref a real one has, the channels default); the row. Its Delivery rows and itself are removed by the clean-up.
Method PageRow(incident As %String, person As %String) As OcuTalon.Data.Page [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set page.IncidentRef = incident
	Set page.Role = "oncall"
	Set page.Person = person
	Set page.Channels = "email"
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(page.%Save(), "the on-call page row is made")
	Set ..PageRefs = ..PageRefs _ $Select(..PageRefs = "": "", 1: ",") _ page.Ref
	Quit page
}

/// The number of backup page rows of the incident.
ClassMethod BackupPages(incident As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Page WHERE IncidentRef = ? AND PageRole = 'backup'", incident)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
