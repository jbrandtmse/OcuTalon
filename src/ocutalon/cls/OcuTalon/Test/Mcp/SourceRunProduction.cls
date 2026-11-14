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

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Session = ""
	Set ..Source = ""
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
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
