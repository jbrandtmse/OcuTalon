/// The test of two incidents that settle together and are diagnosed at once (Story 5.14; AD-6, AD-8, AD-15, NFR-7; DW-879). THIS CLASS RUNS IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, over the RUNNING production: IncidentManager, Decide and DiagnosisAgent (a pool of 2)
/// are items of it, so the class runs on a stack whose production was started with the code under test. The model is the CI mock: a failure whose error text
/// holds the marker [[mock:diagnosis-slow:<key>]] gets the no-fix diagnosis of the scenario diagnosis-slow after 10 seconds.
///   - TestTwoAtOnce: one batch of two synthetic failures with the markers diagnosis-slow:one and diagnosis-slow:two gives two incidents, each with its usable no-fix
///     diagnosis (partner_outage, no fix, no fallback). Decide sent both runner requests to DiagnosisAgent within 3 seconds of each other, and both model requests
///     reached the mock less than 10 seconds apart, so the two diagnoses ran at the same time. Each is answered within 16 seconds of its send (with one job the
///     second would take 20 seconds or more) and within half of Decide's timer. The test logs the send and answer time (UTC, from the message headers), the
///     milliseconds between them, and the timer.
Class OcuTalon.Test.Watch.DiagnoseTogether Extends OcuTalon.Test.Watch.Case
{

/// The namespace and the production of the incidents that SendBatch makes: nothing runs there, so the pack has no sample.
Parameter SYNTHNS = "ZZNS";

Parameter SYNTH = "Zz.Diagnose";

/// The most that Decide's two sends may be apart, in milliseconds.
Parameter SENDGAP = 3000;

/// The most that the two model requests may be apart at the mock, in milliseconds: the reply takes 10 seconds, so a request that waited for the other would be 10 seconds later.
Parameter MOCKGAP = 10000;

/// The most that a diagnosis may take from the send to the answer, in milliseconds.
Parameter ANSWERLIMIT = 16000;

/// Two incidents that settle together are diagnosed at once, each inside its timer.
Method TestTwoAtOnce()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("together")
	Set fixture = ..#FIXTURE
	Do $$$AssertTrue($ClassMethod(fixture, "Idle", "DiagnosisAgent", 60), "DiagnosisAgent is idle before the batch")
	Set timer = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide", .sc)
	Do $$$AssertStatusOK(sc, "Decide's timer is read")
	Set failures = []
	For name = "one", "two" {
		Do failures.%Push({"item": (..Item("slow-"_name)), "text": ("[[mock:diagnosis-slow:"_name_"]] Field 'Qty' was empty"), "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))})
	}
	Set mockMark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, failures), "one batch of two failures is sent")
	Set rows = ..WaitIncident(a, ..#SYNTH, 2)
	Do $$$AssertEquals(rows.%Size(), 2, "two incidents")
	If rows.%Size() '= 2 Quit
	For i = 0:1:1 {
		Set ..ItemIds = ..ItemIds _ $ListBuild(rows.%Get(i).ref)
	}
	Kill sends, answers
	For i = 0:1:1 {
		Set ref = rows.%Get(i).ref
		Set name = $Extract(..Group(ref).itemName, $Length(..Item("slow-")) + 1, *)
		Do $$$AssertTrue((name = "one") || (name = "two"), "incident "_(i + 1)_" is the failure '"_name_"'")
		Do $$$AssertTrue(..WaitDiagnosed(ref), name_": the incident holds its diagnosis")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		Set decision = $ClassMethod(fixture, "DecisionOf", ref, "diagnose")
		If '$IsObject(row) || '$IsObject(decision) {
			Do $$$AssertTrue(0, name_": the row and its decision exist")
			Continue
		}
		Do $$$AssertEquals(decision.Fallback_"|"_row.Fallback_"|"_row.CauseCategory_"|"_row.FixSummary, "0|0|partner_outage|", name_": a usable no-fix diagnosis, not a fallback")
		Set sent = ..SentHeader(decision)
		Do $$$AssertTrue(sent '= "", name_": Decide sent DiagnosisAgent a request that carries the decision's Ref")
		If sent = "" Continue
		Set answer = ..AnswerHeader(sent)
		Do $$$AssertTrue(answer '= "", name_": DiagnosisAgent answered it")
		If answer = "" Continue
		Set sends(name) = sent
		Set answers(name) = answer
	}
	If '($Data(sends("one")) && $Data(sends("two"))) Quit
	Set gap = $ClassMethod(..#FIXTURE, "HeaderMillis", sends("one"), sends("two"))
	Do $$$AssertTrue($Select(gap < 0: -gap, 1: gap) < ..#SENDGAP, "Decide sent both runner requests within "_(..#SENDGAP \ 1000)_" s of each other: "_gap_" ms")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mockMark, .entries), "the mock's log is read")
	Set one = ..ModelRequestTime(entries, "diagnosis-slow:one")
	Set two = ..ModelRequestTime(entries, "diagnosis-slow:two")
	Do $$$AssertTrue((one '= "") && (two '= ""), "both model requests reached the mock")
	If (one '= "") && (two '= "") {
		Set apart = $Select(one > two: one - two, 1: two - one)
		Do $$$AssertTrue(apart < ..#MOCKGAP, "and less than "_(..#MOCKGAP \ 1000)_" s apart: "_apart_" ms")
	}
	For name = "one", "two" {
		Set took = $ClassMethod(..#FIXTURE, "HeaderMillis", sends(name), answers(name))
		Do $$$LogMessage(name_": sent "_$ClassMethod(..#FIXTURE, "HeaderStamp", sends(name))_" UTC, answered "_$ClassMethod(..#FIXTURE, "HeaderStamp", answers(name))_" UTC, "_took_" ms; the timer is "_timer_" s")
		Do $$$AssertTrue((took '< 0) && (took < ..#ANSWERLIMIT), name_": answered within "_(..#ANSWERLIMIT \ 1000)_" s of its send: "_took_" ms")
		Do $$$AssertTrue(took < (timer * 500), name_": and within half of the "_timer_" s timer")
	}
}

/// The id of the header from Decide to DiagnosisAgent that carries the decision's Ref, or "".
Method SentHeader(decision As OcuTalon.Bridge.Data.Decision) As %Integer [ Private ]
{
	Set headers = $ClassMethod(..#FIXTURE, "Headers", decision.TraceSessionId, "Decide")
	Set found = ""
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If (found = "") && (header.target = "DiagnosisAgent") && (header.bodyClass = "OcuTalon.Bridge.Msg.Request") {
			Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
			If $IsObject(body) && (body.DecisionRef = decision.Ref) Set found = header.id
		}
	}
	Quit found
}

/// The id of DiagnosisAgent's response header to the request header, or "".
ClassMethod AnswerHeader(requestHeader As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE CorrespondingMessageId = ? AND SourceConfigName = 'DiagnosisAgent' ORDER BY ID", requestHeader)
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

/// The time, in milliseconds, of the first POST /v1/messages entry of the mock's log whose marker is the label, or "".
ClassMethod ModelRequestTime(entries As %DynamicArray, label As %String) As %Integer [ Private ]
{
	Set time = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (time = "") && (entry.method = "POST") && (entry.path = "/v1/messages") && (entry.marker = label) {
			Set ts = entry.ts
			Set time = (($ZDateH($Extract(ts, 1, 10), 3) * 86400) + ($Extract(ts, 12, 13) * 3600) + ($Extract(ts, 15, 16) * 60) + $Extract(ts, 18, 19)) * 1000 + $Extract(ts, 21, 23)
		}
	}
	Quit time
}

}
