/// The test of a diagnosis that waits in DiagnosisAgent's queue past Decide's timer (Story 5.14; AD-6, AD-8, AD-20; DW-879). THIS CLASS RUNS IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21): it needs OcuTalon.Production running after the Production step, started with the code under test (DiagnosisAgent has two jobs and its
/// adapter skips a concluded request), the CI override's environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails
/// with the reason where it does not have them. CI starts with no model key on purpose, so the test points the Config Store entry of each runner at the non-secret CI
/// variable OCUTALON_MOCK_KEY_HEADER, and OnAfterAllTests puts the entries back (Test.Agent.RunnerFixture PointKeys and RestoreKeys).
///   - TestSkippedAfterItsTimer: with a TimerSeconds row of 12 and Decide started again alone (the runners' entries keep the derivation of 60), two diagnoses R1 and
///     R2 (the scenario diagnosis-busy, a reply after 20 s) hold both jobs of DiagnosisAgent; R3 goes to Decide once the mock's log holds R1 and R2. R3 waits in the
///     queue, its timer fires, and Decide records one timeout fallback row for it. When a job frees, the runner skips R3: no mock request, no Usage row and no AgentStep,
///     and one Info row of Adapter.Agent Answer names DiagnosisAgent and R3's DecisionRef; its answer to Decide has no body and is marked Discarded. R1 and R2 reached
///     the mock and have one Usage row each. The test logs the send and answer times (UTC, from the message headers) of the three runner requests and the timer.
/// OnAfterOneTest puts the timer row back and starts Decide again, also after a failure, waits until DiagnosisAgent is idle, and deletes the Decision, Usage and AgentStep
/// rows of the three items.
Class OcuTalon.Test.Agent.QueuedPastTimer Extends %UnitTest.TestCase
{

Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The TimerSeconds row of Decide for the test.
Parameter TIMER = 12;

/// Seconds to wait for a step of the test (the rows and the answers); the diagnosis replies take 20.
Parameter WAITSECONDS = 90;

Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the three requests.
Property ItemIds As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture RememberDefault).
Property SavedRows As %List;

/// 1 when the test started Decide again with the timer row, which OnAfterOneTest puts back.
Property DecideChanged As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began.
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set fixture = ..#FIXTURE
	Set running = $ClassMethod(fixture, "Running")
	Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
	Set ..SavedRows = ""
	If ..DecideChanged && running {
		Set ..DecideChanged = 0
		Do $ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide")
	}
	If running Do $ClassMethod(fixture, "Idle", "DiagnosisAgent", ..#WAITSECONDS)
	Do $ClassMethod(fixture, "DropSince", ..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(fixture, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys")
	}
	Quit $$$OK
}

/// R3 waits in the queue past its timer and is skipped when a job frees; R1 and R2 are answered by their jobs.
Method TestSkippedAfterItsTimer()
{
	Set fixture = ..#FIXTURE
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(fixture, "PointKeys")
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit
	}
	Do $$$AssertTrue($ClassMethod(fixture, "Idle", "DiagnosisAgent", 60), "DiagnosisAgent is idle before the test")
	Set saved = ..SavedRows
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "TimerSeconds")
	Set ..SavedRows = saved
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", ..#TIMER), "the TimerSeconds row of Decide is "_..#TIMER)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a TimerSeconds of "_..#TIMER)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide"), ..#TIMER, "Decide's timer reads "_..#TIMER)

	Set mockMark = $ClassMethod(mock, "LogMark")
	Set eventMark = $ClassMethod(fixture, "EventMark")
	Set headerMark = $ClassMethod(fixture, "HeaderMark")
	For n = 1:1:3 {
		Set request(n) = $ClassMethod(fixture, "NewRequest", "diagnose", "untrusted", "[[mock:diagnosis-busy:"_n_"]] Diagnose this incident.", .ref)
		Set ref(n) = ref
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	}
	Do $$$AssertStatusOK(..SendAsync(request(1)), "R1 is sent to Decide")
	Do $$$AssertStatusOK(..SendAsync(request(2)), "R2 is sent to Decide")
	Do $$$AssertTrue(..WaitInLog(mockMark, ref(1), ref(2)), "R1 and R2 are both in the mock's log: both jobs are in Chat")
	Do $$$AssertStatusOK(..SendAsync(request(3)), "R3 is sent to Decide, with both jobs busy")

	// the three decisions, and the answers of DiagnosisAgent to the three runner requests
	For n = 1:1:3 {
		Do $$$AssertTrue(..WaitDecision(ref(n)), "R"_n_": Decide records its decision")
		Set session(n) = $ClassMethod(fixture, "SessionOf", request(n), headerMark)
		Do $$$AssertTrue(session(n) '= "", "R"_n_": its session is found")
		Set sent(n) = $Select(session(n) '= "": ..SentHeader(session(n)), 1: "")
		Do $$$AssertTrue(sent(n) '= "", "R"_n_": Decide sent DiagnosisAgent a request")
		Set answer(n) = $Select(sent(n) '= "": ..WaitAnswer(sent(n)), 1: "")
		Do $$$AssertTrue(answer(n) '= "", "R"_n_": DiagnosisAgent answers the request, within the ceiling")
	}
	If (sent(1) = "") || (sent(2) = "") || (sent(3) = "") || (answer(1) = "") || (answer(2) = "") || (answer(3) = "") Quit
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mockMark, .entries), "the mock's log is read")
	For n = 1:1:3 {
		Set body = ..BodyOf(sent(n))
		Set decisionRef(n) = $Select($IsObject(body): body.DecisionRef, 1: "")
		Do $$$AssertTrue(decisionRef(n) '= "", "R"_n_": its runner request carries a DecisionRef")
		Set took = $ClassMethod(..#FIXTURE, "HeaderMillis", sent(n), answer(n))
		Do $$$LogMessage("R"_n_": sent "_$ClassMethod(..#FIXTURE, "HeaderStamp", sent(n))_" UTC, answered "_$ClassMethod(..#FIXTURE, "HeaderStamp", answer(n))_" UTC, "_took_" ms; the timer is "_..#TIMER_" s")
	}

	// R3
	Set row = $ClassMethod(fixture, "DecisionOf", ref(3), "diagnose")
	Do $$$AssertTrue($IsObject(row), "R3: its decision row exists")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "1|timeout", "R3: it is the timeout fallback")
		Do $$$AssertEquals(row.Ref, decisionRef(3), "R3: with the DecisionRef of its runner request")
	}
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "DecisionRowCount", ref(3)), 1, "R3: Decide recorded one row for it and nothing more")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref(3)).%Size(), 0, "R3: no request reached the mock")
	Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "DecisionRef", decisionRef(3)).%Size(), 0, "R3: and no Usage row exists")
	Do $$$AssertEquals($ClassMethod(fixture, "StepsOf", decisionRef(3)).%Size(), 0, "R3: and no AgentStep")
	Do $$$AssertEquals($ClassMethod(fixture, "Warnings", eventMark, "OcuTalon.Bridge.Adapter.Agent", "Answer", $ListBuild("DiagnosisAgent", decisionRef(3)), 4), 1, "R3: one Info row names DiagnosisAgent and its DecisionRef")
	Do $$$AssertEquals(..BodyIdOf(answer(3)), "", "R3: its answer to Decide has no body")
	Do $$$AssertEquals(..StatusOf(answer(3)), "Discarded", "R3: and is marked Discarded")

	// R1 and R2
	For n = 1:1:2 {
		Do $$$AssertTrue($ClassMethod(fixture, "FindRequests", entries, ref(n)).%Size() > 0, "R"_n_": it reached the mock")
		Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "DecisionRef", decisionRef(n)).%Size(), 1, "R"_n_": and has one Usage row")
	}
}

/// Sends the request to Decide from ApprovalStartIn, without waiting for the answer.
Method SendAsync(request As OcuTalon.Bridge.Msg.Request) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("ApprovalStartIn", .service)
	If $$$ISERR(sc) Quit sc
	Quit service.SendRequestAsync("Decide", request)
}

/// 1 when the mock's log, after the mark, holds a request that carries each of the references, within WAITSECONDS.
Method WaitInLog(mark As %Integer, first As %String, second As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	Set found = 0
	For {
		If $$$ISOK($ClassMethod("OcuTalon.Test.Contract.Mock", "LogSince", mark, .entries)) {
			Set found = ($ClassMethod(..#FIXTURE, "FindRequests", entries, first).%Size() > 0) && ($ClassMethod(..#FIXTURE, "FindRequests", entries, second).%Size() > 0)
		}
		If found || ($ZHorolog '< deadline) Quit
		Hang 0.2
	}
	Quit found
}

/// 1 when the decision row of the item exists within WAITSECONDS.
Method WaitDecision(itemId As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	Set found = 0
	For {
		Set found = $IsObject($ClassMethod(..#FIXTURE, "DecisionOf", itemId, "diagnose"))
		If found || ($ZHorolog '< deadline) Quit
		Hang 0.5
	}
	Quit found
}

/// The id of the header from Decide to DiagnosisAgent in the session, or "".
Method SentHeader(session As %Integer) As %Integer [ Private ]
{
	Set header = $ClassMethod(..#FIXTURE, "HeaderTo", $ClassMethod(..#FIXTURE, "Headers", session, "Decide"), "DiagnosisAgent")
	Quit $Select($IsObject(header): header.id, 1: "")
}

/// The id of DiagnosisAgent's response header to the request header, once there is one (within WAITSECONDS), or "".
Method WaitAnswer(requestHeader As %Integer) As %Integer [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	Set id = ""
	For {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE CorrespondingMessageId = ? AND SourceConfigName = 'DiagnosisAgent' ORDER BY ID", requestHeader)
		If result.%Next() Set id = result.%GetData(1)
		If (id '= "") || ($ZHorolog '< deadline) Quit
		Hang 0.5
	}
	Quit id
}

/// The runner request that the header carries.
ClassMethod BodyOf(header As %Integer) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID = ?", header)
	If 'result.%Next() Quit ""
	Quit ##class(OcuTalon.Bridge.Msg.Request).%OpenId(result.%GetData(1))
}

/// The message body id of the header ("" for a response with no body).
ClassMethod BodyIdOf(header As %Integer) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID = ?", header)
	If 'result.%Next() Quit "?"
	Quit result.%GetData(1)
}

/// The status of the header, as its display name.
ClassMethod StatusOf(header As %Integer) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status FROM Ens.MessageHeader WHERE ID = ?", header)
	If 'result.%Next() Quit ""
	Set status = result.%GetData(1)
	If status '? 1.N Quit status
	Quit $Piece(##class(Ens.DataType.MessageStatus).#DISPLAYLIST, ",", status + 1)
}

}
