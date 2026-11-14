/// The run of a source through the real production (Story 22.11, QA; AD-1, AD-6, AD-10, AD-18, AD-21, AD-30, AD-33): a Tick that reaches the real Checks item polls a due source through
/// Decide and TriageAgent and the mock MCP server, and Checks records the answer and sends the new result to Intake. THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need the
/// running OcuTalon.Production and the CI mock (RunnerFixture), and they make the fixtures of the server zzmcp (Test.Mcp.JobFixture: the loopback mock that checks a header, the Config Store entry,
/// the wallet secret, the Use permission, the tool rows) and a fixture session with source rows of Kind source, which the production's own Checks item also runs: the tests wait for the
/// run, whichever Tick of the two made it. This class extends JobFixture, not Test.Core.InProduction (both are test cases), and keeps InProduction's clean-up itself: it waits for PrecedentOps,
/// removes the messages of the run's sessions, the fixture rows and the Precedent rows. Each test removes what it made, whether it passed or failed.
///   - TestPollRuns (the AC of the run; the runner is restarted with its key at the CI mock, so that a model request would show): a Tick makes one poll of a Read-only source through Decide and TriageAgent: one MCP called audit entry, the step "Running zz_lookup on zzmcp" in the
///     AgentStep messages of the poll's Decide, no Decision row for the poll's ItemId and no model request in the CI mock's log; Checks records passed, the baseline and one CheckRun row;
///   - TestNewResultReachesIntake (the Integration AC): a source with a baseline whose mock answer changes sends one Item that reaches Intake and produces an ItemDecision, with one decide
///     request in the model mock's log (the keys are pointed at the mock for the test);
///   - TestNoSecretLeaks: no argument value of the source, URL or wallet secret shows in a message, an event-log row, an audit entry or a step label of the run.
/// The QA pass adds the matrix rows that only the real runtime can show (every one restarts the Checks item first, so that it runs the classes as they are now):
///   - TestSourceRemovedInFlight and TestServerRemovedInFlight (matrix 6): the source row, or the server with its tool rows and its sources, is removed while the poll waits on a silent mock; the answer
///     that follows updates no row: no row is made again, no CheckRun row, no Item to Intake, no check event;
///   - TestOnlineDemoNoPollInProduction (matrix 7): with a real source row and the real onlineDemo setting 1, a Tick to the real Checks sends no poll request, the mock hears nothing and the row is as it was;
///     with the setting back as it was the same row is polled (the control);
///   - TestStopThenResume (matrix 5): a tool classified risky is not polled (no request reaches the mock, the run is not_checked with Reason stopped); classified read-only again, the next due run polls
///     and clears stopped;
///   - TestNoSecretLeaksOnFailure: after a poll that the mock refuses (401) and one that finds the mock down, and after a stopped run, no argument value, URL or secret shows in a message, an event-log row,
///     an audit entry, a step label, the finding or the CheckRun row.
Class OcuTalon.Test.Mcp.SourceRunProduction Extends OcuTalon.Test.Mcp.JobFixture
{

/// The argument value of the fixture source, which no message, log, audit entry or step may hold.
Parameter ARGUMENT = "zzsrcprodargvalue";

/// The longest to wait for a run to be recorded, in seconds.
Parameter WAIT = 40;

/// The Ref of the fixture session of the test.
Property Session As %String;

/// The Ref of the source row of the test.
Property Source As %String;

/// The ID of the newest message header when the test began.
Property Mark As %Integer;

/// What the public online-demo flag held before the test, and 1 once the test has changed it.
Property SavedDemo As %String;

Property DemoSaved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Session = ""
	Set ..Source = ""
	Set ..DemoSaved = 0
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..DemoSaved Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Set sc = ##super(testname)
	Do $ClassMethod(..#MOCK, "Speak", ..Port)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef IN (SELECT Ref FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?)", ..#SERVER)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?", ..#SERVER)
	If ..Session '= "" {
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(..Session).TraceRef
		Set end = $ZHorolog + 10
		While (##class(Ens.Queue).GetCount("PrecedentOps") > 0) && ($ZHorolog < end) {
			Hang 0.1
		}
		Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages([(trace)])
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?", ..Session)
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Session)
		Do ##class(OcuTalon.Data.Precedent).DropSession(..Session)
		Set ..Session = ""
	}
	Quit sc
}

/// A Tick through the production (see the class description).
Method TestPollRuns()
{
	If '..Ready() Quit
	Do ..PointRunner()
	Set ref = ..Prepare()
	Set logMark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do ..Poll(ref)
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding, "passed|", "Checks recorded the poll as passed")
	Do $$$AssertEquals(row.Reported, "{""seen"":[""" _ ..Hash("The mock ran zz_lookup") _ """],""baseline"":1,""stopped"":""""}", "with the hash of the answer and the baseline")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", ..#SERVER, , 1)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP entry names the server")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change _ "|" _ entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.outcome, "called|zz_lookup|ok", "it says called, for the tool, ok")
	Set poll = ..PollRequest()
	Do $$$AssertTrue($IsObject(poll), "a poll request went from Checks to Decide")
	If $IsObject(poll) {
		Do $$$AssertEquals(poll.Kind _ "|" _ poll.Provenance _ "|" _ poll.Input _ "|" _ poll.OwnerRef _ "|" _ poll.Channel, "tool|untrusted|" _ {"source": (ref)}.%ToJSON() _ "|" _ ..Session _ "|system", "of kind tool, untrusted, with the Ref as its Input, for the row's session")
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", poll.ItemId)
		Do rows.%Next()
		Do $$$AssertEquals(+rows.%GetData(1), 0, "no Decision row exists for the poll's ItemId")
		Set ..ItemIds = ..ItemIds _ $ListBuild(poll.ItemId)
		Set steps = ..StepLabels()
		Do $$$AssertEquals(steps, "Running zz_lookup on " _ ..#SERVER, "the one step of the poll is labelled for the tool and the server")
	}
	Do ##class(OcuTalon.Test.Contract.Mock).LogSince(logMark, .modelEntries)
	Do $$$AssertEquals(modelEntries.%Size(), 0, "the model mock's log has no request: the poll called no model")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "the mock logged one tools/call")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Set clients = ""
	For i = 0:1:requests.%Size() - 1 {
		Set clients = clients _ $Select(clients = "": "", 1: ",") _ requests.%Get(i).client
	}
	Do $$$AssertEquals($Replace(clients, "iris", ""), ",,,,,,", "every request came from OcuTalon's own client, none from AI Hub's: seed listing, initialize, tools/list, tools/call")
	Do $$$AssertEquals(..Items(), 0, "the baseline sent no Item to Intake")
}

/// A changed answer reaches Intake (see the class description).
Method TestNewResultReachesIntake()
{
	If '..Ready() Quit
	Do ..PointRunner()
	Set ref = ..Prepare()
	Do ..Poll(ref)
	Do $$$AssertEquals(..Stored(ref).Result, "passed", "the first poll is the baseline")
	Do $$$AssertEquals(..Items(), 0, "no Item was sent")
	Set logMark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $ClassMethod(..#MOCK, "Call", ..Port, "text", "T-1 open" _ $Char(10) _ "T-2 open")
	Set before = ..Stored(ref).LastRunAt
	Do ..Poll(ref, before)
	Do $$$AssertEquals(..Stored(ref).Result, "passed", "the second poll is passed")
	Set end = $ZHorolog + ..#WAIT
	While (..Decisions() < 1) && ($ZHorolog < end) {
		Hang 0.5
	}
	Do $$$AssertEquals(..Items(), 1, "one Item went from Checks to Intake")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(..Session).TraceRef
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set item = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Checks", "Intake")
	If item.%Size() = 1 {
		Set body = ##class(OcuTalon.Msg.Item).%OpenId(item.%Get(0).bodyId)
		Do $$$AssertEquals(body.Provenance _ "|" _ body.Channel _ "|" _ body.Subject _ "|" _ body.Text _ "|" _ body.SessionRef, "untrusted|system|Jira|T-1 open" _ $Char(10) _ "T-2 open|" _ ..Session, "an untrusted Item of the system channel, whose Subject is the source's name and Text the answer")
		Set ..ItemIds = ..ItemIds _ $ListBuild(body.ItemId)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(body.ItemId, "decide"), 1, "Decide recorded a decision of kind decide for the Item")
		Set decisions = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "OutcomeRouter")
		Do $$$AssertEquals(decisions.%Size(), 1, "Intake produced one ItemDecision for it")
	}
	Do ##class(OcuTalon.Test.Contract.Mock).LogSince(logMark, .modelEntries)
	Set requests = 0
	Set iterator = modelEntries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && (entry.scenario = "triage") Set requests = requests + 1
	}
	Do $$$AssertEquals(requests, 1, "the model mock's log has one decide request (the triage scenario's message)")
}

/// No argument, URL or secret leaks (see the class description).
Method TestNoSecretLeaks()
{
	If '..Ready() Quit
	Set ref = ..Prepare()
	Do ..Poll(ref)
	Set url = "http://127.0.0.1:" _ ..Port
	Set holds = ..TraceHolds(..Mark, $ListBuild(..#ARGUMENT, ..Secret, url), .scanned)
	Do $$$AssertTrue(scanned > 0, "the messages of the run were scanned (" _ scanned _ ")")
	Do $$$AssertEquals($ListToString(holds), "0,0,0", "no message of the run holds the argument value, the secret or the URL")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, ..#ARGUMENT), 0, "no event-log row holds the argument value")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, url), 0, "nor the URL")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , ..#ARGUMENT).%Size(), 0, "no audit entry holds the argument value")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , url).%Size(), 0, "nor the URL")
	Do $$$AssertEquals($Find(..StepLabels(), ..#ARGUMENT), 0, "no step label holds the argument value")
	Do $$$AssertEquals(..Stored(ref).Finding _ "|" _ (..Stored(ref).Reported [ ..#ARGUMENT), "|0", "and neither the finding nor Reported holds it")
}

/// matrix 6, the source removed while its poll is in flight (see the class description).
Method TestSourceRemovedInFlight()
{
	If '..Ready() Quit
	Do ..RemovedInFlight("source")
}

/// matrix 6, the server removed while the poll of its source is in flight (see the class description).
Method TestServerRemovedInFlight()
{
	If '..Ready() Quit
	Do ..RemovedInFlight("server")
}

/// matrix 7 on the real Checks item and the real setting (see the class description).
Method TestOnlineDemoNoPollInProduction()
{
	If '..Ready() Quit
	Do ..FreshChecks()
	Do ..Setup()
	Set ..Session = ##class(OcuTalon.Test.Data.Fixture).Session("zzsrcdemo" _ $Increment(^OcuTalonTest("SourceRunProduction", "n")))
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Ok(##class(OcuTalon.Watch.Ops).SetSource(..Session, ..#SERVER, "zz_lookup", "Jira", {"q": (..#ARGUMENT)}.%ToJSON(), 5, "zzsrcprod", .ref, .created), "the source row is made while the setting is 1")
	Set ..Source = ref
	Set due = ..Stored(ref).NextDueAt
	Set ..Mark = ..HeaderMark()
	Hang 1.1
	Do ..Tick()
	Hang 6
	Do $$$AssertEquals(##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), 1, "the real setting onlineDemo is 1")
	Do $$$AssertNotTrue($IsObject(..PollRequest()), "the Tick sent no poll request to Decide")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), 0, "the mock heard nothing: no listing, no call")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.LastRunAt _ "|" _ row.Result _ "|" _ row.Finding _ "|" _ row.Reported _ "|" _ (row.NextDueAt = due), "||||1", "the row is as it was: nothing is recorded")
	Do $$$AssertEquals(..CheckRuns(ref), 0, "no CheckRun row is written")
	Do $$$AssertEquals(..Items(), 0, "and no Item is sent")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Do ..Poll(ref)
	Do $$$AssertEquals(..Stored(ref).Result, "passed", "control: with the setting back as it was the same row is polled")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "and the mock logged its one tools/call")
}

/// matrix 5 on the real Checks item and the real classification rows (see the class description).
Method TestStopThenResume()
{
	If '..Ready() Quit
	Do ..FreshChecks()
	Set ref = ..Prepare()
	Do ..Classify("risky")
	Do ..Poll(ref)
	Set row = ..Stored(ref)
	Set reported = ##class(%DynamicAbstractObject).%FromJSON(row.Reported)
	Do $$$AssertEquals(row.Result _ "|" _ reported.stopped _ "|" _ (reported.baseline = 1), "not_checked|not_read_only|0", "a risky tool: the run is not_checked and stopped, and it is not the baseline")
	Do $$$AssertEquals(..LastRunReason(ref), "stopped", "the CheckRun row says Reason stopped")
	Do $$$AssertNotTrue($IsObject(..PollRequest()), "no poll request went to Decide")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), 0, "no request reached the mock: no listing and no tools/call")
	Set before = row.LastRunAt
	Do ..Classify("read-only")
	Do ..Poll(ref, before)
	Set row = ..Stored(ref)
	Set reported = ##class(%DynamicAbstractObject).%FromJSON(row.Reported)
	Do $$$AssertEquals(row.Result _ "|" _ reported.stopped _ "|" _ reported.baseline, "passed||1", "read-only again: the next due run polls, passes and clears stopped; it is the baseline")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "the mock logged one tools/call, from the run after the stop")
	Do $$$AssertEquals(..Items(), 0, "no Item (the baseline)")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..AuditMark, "OcuTalon", "MCP", "MCP", ..#SERVER, , 1)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP called entry: the stopped run wrote none")
}

/// The failure and stop paths leak nothing (see the class description).
Method TestNoSecretLeaksOnFailure()
{
	If '..Ready() Quit
	Do ..FreshChecks()
	Set ref = ..Prepare()
	Do $ClassMethod(..#MOCK, "Status", ..Port, "401 Unauthorized")
	Do ..Poll(ref)
	Set first = ..Stored(ref)
	Do $$$AssertEquals(first.Result, "not_checked", "the refused poll is recorded as not_checked")
	Do ..Classify("risky")
	Do ..Poll(ref, first.LastRunAt)
	Set second = ..Stored(ref)
	Do $$$AssertEquals(second.Result _ "|" _ ..LastRunReason(ref), "not_checked|stopped", "the stopped run is recorded")
	Do ..Classify("read-only")
	Set mock = ..Port
	Do $ClassMethod(..#MOCK, "Stop", mock)
	Do ..Poll(ref, second.LastRunAt)
	Set third = ..Stored(ref)
	Do $$$AssertEquals(third.Result, "not_checked", "the poll of a mock that is down is recorded as not_checked")
	Set url = "http://127.0.0.1:" _ mock
	Set holds = ..TraceHolds(..Mark, $ListBuild(..#ARGUMENT, ..Secret, url), .scanned)
	Do $$$AssertTrue(scanned > 0, "the messages of the runs were scanned (" _ scanned _ ")")
	Do $$$AssertEquals($ListToString(holds), "0,0,0", "no message holds the argument value, the secret or the URL")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, ..#ARGUMENT) _ "|" _ $ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, url), "0|0", "no event-log row holds the argument value or the URL")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , ..#ARGUMENT).%Size() _ "|" _ ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , url).%Size(), "0|0", "no audit entry holds the argument value or the URL")
	Do $$$AssertEquals($Find(..StepLabels(), ..#ARGUMENT) _ "|" _ $Find(..StepLabels(), url), "0|0", "no step label holds the argument value or the URL")
	Set leaked = 0
	For row = first, second, third {
		If (row.Finding [ ..#ARGUMENT) || (row.Finding [ url) || (row.Finding [ ..Secret) || (row.Reported [ ..#ARGUMENT) || (row.Reported [ url) Set leaked = leaked + 1
	}
	Do $$$AssertEquals(leaked, 0, "neither a finding nor Reported holds them")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? AND (Finding [ ? OR Finding [ ? OR Finding [ ?)", ref, ..#ARGUMENT, url, ..Secret)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and no CheckRun row holds them")
}

/// The poll of the removal is in flight (a silent mock that the runner has reached), then what is removed is removed, and the answer must record nothing.
Method RemovedInFlight(what As %String) [ Private ]
{
	Do ..FreshChecks()
	Set ref = ..Prepare()
	Set session = ..Session
	Do $ClassMethod(..#MOCK, "Silence", ..Port, 8)
	Hang 1.1
	Do ..Tick()
	Set end = $ZHorolog + ..#WAIT
	While (('$IsObject(..PollRequest())) || ($ClassMethod(..#MOCK, "Requests", ..Port).%Size() < 1)) && ($ZHorolog < end) {
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(..PollRequest()), "the poll was sent to Decide")
	Do $$$AssertTrue($ClassMethod(..#MOCK, "Requests", ..Port).%Size() > 0, "the runner reached the silent mock: the poll is in flight")
	Do $$$AssertEquals(..Stored(ref).LastRunAt _ "|" _ ..Stored(ref).Result, "|", "nothing is recorded yet")
	If what = "source" {
		Do ..Ok(##class(OcuTalon.Watch.Ops).RemoveSource(ref), "the source row is removed")
	} Else {
		Set refs = ##class(OcuTalon.Watch.Ops).SourcesOf(..#SERVER)
		Set iterator = refs.%GetIterator()
		While iterator.%GetNext(, .each) {
			Do ..Ok(##class(OcuTalon.Watch.Ops).RemoveSource(each), "a source of the server is removed")
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
		If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(..#SERVER)
		If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ ..#SERVER) Do ##class(%ConfigStore.Configuration).Delete("AI.MCP.OcuTalon_" _ ..#SERVER)
	}
	Do $ClassMethod(..#MOCK, "Speak", ..Port)
	Set end = $ZHorolog + ..#WAIT
	While ('..Answered()) && ($ZHorolog < end) {
		Hang 0.25
	}
	Do $$$AssertTrue(..Answered(), "Decide's answer reached Checks")
	Hang 1.5
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(ref), 0, "the row is not made again")
	Do $$$AssertEquals(..CheckRuns(ref), 0, "no CheckRun row is written")
	Do $$$AssertEquals(..Items(), 0, "no Item is sent to Intake")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "check").%Size(), 0, "no check event is published")
}

/// Restarts the Checks item, so that its job runs the classes as they are now (a job keeps the class it started with).
Method FreshChecks() [ Private ]
{
	Do ..Ok($ClassMethod(..#FIXTURE, "Restart", "Checks"), "the Checks item is restarted")
}

/// Sends a Tick to Checks in the fixture session's trace (the Tick of Poll, with no wait).
Method Tick() [ Private ]
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $$$ISOK(sc) {
		Set service.%SuperSession = ##class(OcuTalon.Data.Session).RefIndexOpen(..Session).TraceRef
		Set sc = service.SendRequestAsync("Checks", tick)
	}
	Do ..Ok(sc, "a Tick is sent to Checks")
}

/// Sets the classification of the fixture tool zz_lookup, as an admin's classification does (the rows alone: the gate and Checks read them).
Method Classify(classification As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Mcp.ToolClassification SET Classification = ? WHERE Server = ? AND Tool = 'zz_lookup'", classification, ..#SERVER)
}

/// Whether Decide's answer to a poll has been delivered to and handled by Checks since the test began.
Method Answered() As %Boolean [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Decide' AND TargetConfigName = 'Checks' AND Type = 2 AND Status = 9", ..Mark)
	Do rs.%Next()
	Quit +rs.%GetData(1) > 0
}

/// The CheckRun rows of the source.
Method CheckRuns(ref As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ?", ref)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The Reason of the newest CheckRun row of the source.
Method LastRunReason(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Reason FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? ORDER BY RanAt DESC, ID DESC", ref)
	If rs.%Next() Quit rs.%GetData(1)
	Quit ""
}

/// Points the key entry of TriageAgent at the CI mock, which restarts the runner (so that it runs the classes as they are now, and a model request of a poll would show in the mock's log),
/// and waits for it; OnAfterOneTest puts the entry back.
Method PointRunner() [ Private ]
{
	Do ..Ok($ClassMethod(..#FIXTURE, "PointKeys", "TriageAgent"), "the key entry of TriageAgent is pointed at the CI mock")
	Set ..Pointed = 1
	Do ..Ok($ClassMethod(..#FIXTURE, "WaitRecords", "TriageAgent"), "the runner recorded its key state")
}

/// 1 when the production and the CI environment are ready; otherwise the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// The fixtures of the server, a fixture session and a source row of Kind source on the mock, due at once; its Ref.
Method Prepare() As %String [ Private ]
{
	Do ..Setup()
	Set ..Session = ##class(OcuTalon.Test.Data.Fixture).Session("zzsrcprod" _ $Increment(^OcuTalonTest("SourceRunProduction", "n")))
	Do ..Ok(##class(OcuTalon.Watch.Ops).SetSource(..Session, ..#SERVER, "zz_lookup", "Jira", {"q": (..#ARGUMENT)}.%ToJSON(), 5, "zzsrcprod", .ref, .created), "the source row is made")
	Set ..Source = ref
	Set ..Mark = ..HeaderMark()
	Quit ref
}

/// Sends a Tick to Checks and waits until the row's LastRunAt is not the time given (a new run is recorded), at most WAIT seconds.
Method Poll(ref As %String, was As %String = "") [ Private ]
{
	If was '= "" Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = '' WHERE Ref = ?", ref)
	Hang 1.1
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $$$ISOK(sc) {
		Set service.%SuperSession = ##class(OcuTalon.Data.Session).RefIndexOpen(..Session).TraceRef
		Set sc = service.SendRequestAsync("Checks", tick)
	}
	Do ..Ok(sc, "a Tick is sent to Checks")
	Set end = $ZHorolog + ..#WAIT
	While (..Stored(ref).LastRunAt = was) && ($ZHorolog < end) {
		Hang 0.25
	}
	Do $$$AssertTrue(..Stored(ref).LastRunAt '= was, "the poll was recorded within " _ ..#WAIT _ " seconds")
}

/// The source row as stored now.
Method Stored(ref As %String) As OcuTalon.Data.BackgroundCheck [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The poll's request (the body of the newest header from Checks to Decide since the test began), or "".
Method PollRequest() As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Checks' AND TargetConfigName = 'Decide' AND Type = 1 ORDER BY ID DESC", ..Mark)
	If rs.%Next() Quit ##class(OcuTalon.Bridge.Msg.Request).%OpenId(rs.%GetData(1))
	Quit ""
}

/// The labels of the AgentStep messages that Decide sent since the test began, line feed separated.
Method StepLabels() As %String [ Private ]
{
	Set labels = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Decide' AND TargetConfigName = 'AgentSteps' AND Type = 1 ORDER BY ID", ..Mark)
	While rs.%Next() {
		Set step = ##class(OcuTalon.Bridge.Msg.AgentStep).%OpenId(rs.%GetData(1))
		If $IsObject(step) Set labels = labels _ $Select(labels = "": "", 1: $Char(10)) _ step.Label
	}
	Quit labels
}

/// The Items that Checks sent to Intake since the test began.
Method Items() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Checks' AND TargetConfigName = 'Intake' AND Type = 1", ..Mark)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The decisions that Intake has answered with an ItemDecision since the test began.
Method Decisions() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Intake' AND TargetConfigName = 'OutcomeRouter' AND Type = 1", ..Mark)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The SHA-256 of the UTF-8 text as 64 lower-case hexadecimal characters.
ClassMethod Hash(text As %String) As %String [ Private ]
{
	Set digest = $SYSTEM.Encryption.SHAHash(256, $ZConvert(text, "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(digest) {
		Set hex = hex _ $ZConvert($Extract($ZHex(256 + $Ascii(digest, i)), 2, 3), "L")
	}
	Quit hex
}

}
