/// Tests of how the Digest item handles a digest case of an evaluation run (Story 17.7; AD-2, AD-22, AD-28, AD-30). Safe on a slot: no production runs; a
/// DigestCase is handled on a shadow instance of OcuTalon.Test.Digest.ProcessProbe, which records every send, its Rows, Cost and Channels, and the
/// DigestResult it is asked to send (SendResult).
///   - TestNoSessionEffects: a DigestCase asks for no Rows, Cost or Channels, sends no Notification, Compose or summary request, writes no Sent row, and sends
///     one DigestResult;
///   - TestResults: the DigestResult of each situation of step 2 holds the key, AllClear, the named and the checked entries; the failed entries come first in
///     Named and Checked keeps the recorded order; healthy vital signs are needed for AllClear; an unreadable recorded value counts as [] or {}; an element that
///     is no result is left out;
///   - TestNeedsYouIsFailedRowsOnly: an eval case with Decisions and incidents of the owner eval still has only its failed rows in what needs the owner (an
///     AllClear of 1 needs none);
///   - TestSavedSummary: with RecordedSaved the case makes one summary request of the owner eval (untrusted, fresh, no seed), the DigestResult waits for the
///     answer, and the answer's DecisionRef goes into it;
///   - TestSavedFallback: a fallback, an answer that is not a Reply, an error and a send that fails each give a DigestResult with Fallback and a reason of
///     Msg.Enum FALLBACKREASON (unusable for the last three), and the DigestResult is still sent;
///   - TestNoDestination: DigestCase has no property that names an owner, session, channel or destination.
Class OcuTalon.Test.Digest.EvalCase Extends OcuTalon.Test.Digest.ProbeCase
{

/// A DigestCase with the rows as JSON text; "" for none.
Method Case(checks As %String, vitals As %String = "", saved As %String = "") As OcuTalon.Eval.Msg.DigestCase
{
	Set case = ##class(OcuTalon.Eval.Msg.DigestCase).%New()
	Set case.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set case.SourceItemId = "zz-evalcase"
	Set case.RecordedChecks = checks
	Set case.RecordedVitals = vitals
	Set case.RecordedSaved = saved
	Quit case
}

/// The vital signs of a digest case: the five healthy rows of the probe, as JSON text.
ClassMethod Vitals() As %String
{
	Quit $ClassMethod("OcuTalon.Test.Digest.ProcessProbe", "Healthy").%ToJSON()
}

/// The text of a checked row.
Method Row(result As %String, entry As %String, finding As %String = "", checkedAt As %String = "2030-06-03T12:00:00Z") As %DynamicObject
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (checkedAt)}
}

/// Hands the DigestCase to the host as the framework would; the status.
Method Handle2(case As OcuTalon.Eval.Msg.DigestCase, host As OcuTalon.Test.Digest.ProcessProbe) As %Status
{
	Kill response
	Quit host.OnRequest(case, .response)
}

/// The DigestResult n that the probe recorded, as an object of its fields; "" when there is none.
Method Result(n As %Integer = 1) As %DynamicObject
{
	Set record = $ClassMethod(..#PROBE, "Record", "result", n)
	If record = "" Quit ""
	Quit {"itemId": ($List(record, 1)), "sourceItemId": ($List(record, 2)), "catalogKey": ($List(record, 3)), "allClear": ($List(record, 4)), "named": ($List(record, 5)), "checked": ($List(record, 6)), "decisionRef": ($List(record, 7)), "fallback": ($List(record, 8)), "fallbackReason": ($List(record, 9))}
}

/// The result of a case handled on a fresh host: the first DigestResult. The probe is reset first.
Method Handled(case As OcuTalon.Eval.Msg.DigestCase) As %DynamicObject
{
	Do $ClassMethod(..#PROBE, "Reset")
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle2(case, host), "the DigestCase is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 1, "one DigestResult is sent")
	Quit ..Result(1)
}

Method TestNoSessionEffects()
{
	Set before = ..AllSentRows()
	Set checks = [(..Row("passed", "Results production")), (..Row("failed", "Orders production", "1 item in error"))]
	Set case = ..Case(checks.%ToJSON(), ..Vitals())
	Do $ClassMethod(..#PROBE, "Feed", [(..Row("passed", "A session's row"))])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle2(case, host), "the DigestCase is handled")
	For kind = "rows", "cost", "channels", "notice", "compose", "summary" {
		Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", kind), 0, "no "_kind_" is asked for or sent")
	}
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 1, "one DigestResult is sent")
	Do $$$AssertEquals(..SentRows(##class(OcuTalon.Data.Ownership).#EVAL), 0, "no Sent row of the owner eval is written")
	Do $$$AssertEquals(..AllSentRows(), before, "and no Sent row of any session")
	Set result = ..Result(1)
	Do $$$AssertEquals(result.itemId_"|"_result.sourceItemId, case.ItemId_"|zz-evalcase", "the DigestResult has the case's ItemId and name")
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.notEverythingRestPassed|0", "and the verdict of the recorded rows, not of the fed ones")
	Set request = ##class(Ens.StringRequest).%New("x")
	Do $$$AssertTrue($$$ISERR(host.OnRequest(request, .response)), "any other request is still refused")
}

Method TestResults()
{
	Set vitals = ..Vitals()
	Set passed = [(..Row("passed", "Results production")), (..Row("passed", "Orders production"))]
	Set result = ..Handled(..Case(passed.%ToJSON(), vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named, "checks.allPassed|1|[]", "every row passed: the all-clear")
	Do $$$AssertEquals(result.checked, "[""Results production"",""Orders production""]", "with what was checked, in the recorded order")
	Do $$$AssertEquals(result.decisionRef_"|"_result.fallback_"|"_result.fallbackReason, "|0|", "and no decision or fallback")
	Set result = ..Handled(..Case(passed.%ToJSON(), ""))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.allPassed|0", "no vital signs recorded: the key is still the checks', but there is no all-clear")
	Set noTime = ..Vitals()
	Set rows = {}.%FromJSON(noTime)
	Set row = rows.rows.%Get(2)
	Set row.checkedAt = ""
	Set result = ..Handled(..Case(passed.%ToJSON(), rows.%ToJSON()))
	Do $$$AssertEquals(result.allClear, 0, "a vital sign with no check time: no all-clear")
	Set dropped = {}.%FromJSON(..Vitals())
	Do dropped.rows.%Push(5)
	Set result = ..Handled(..Case(passed.%ToJSON(), dropped.%ToJSON()))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.allPassed|0", "a vital row that is no result is not passed over: no all-clear")
	Set result = ..Handled(..Case("[5, {""entry"": ""  ""}]", vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named_"|"_result.checked, "checks.nothingWatched|0|[]|[]", "watched elements that are no result: nothing watched")
	Set mixed = [(..Row("not_checked", "A production", "Couldn't be read")), (..Row("passed", "C production")), (..Row("failed", "B production", "2 items in error"))]
	Set result = ..Handled(..Case(mixed.%ToJSON(), vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.notEverythingRestPassed|0", "a failed, a not-checked and a passed row")
	Do $$$AssertEquals(result.named, "[""B production"",""A production""]", "Named has the failed entry first, then the not-checked one")
	Do $$$AssertEquals(result.checked, "[""A production"",""C production"",""B production""]", "Checked keeps the recorded order")
	Set paused = [(..Row("not_checked", "Orders production", "Background checks were paused")), (..Row("not_checked", "Results production", "Background checks were paused"))]
	Set result = ..Handled(..Case(paused.%ToJSON(), vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named, "checks.notEverything|0|[""Orders production"",""Results production""]", "nothing passed: both named, no all-clear")
	Set late = [(..Row("passed", "A production", "", ""))]
	Set result = ..Handled(..Case(late.%ToJSON(), vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named, "checks.notEverything|0|[""A production""]", "a pass with no check time is not checked")
	Set result = ..Handled(..Case("[]", vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named_"|"_result.checked, "checks.nothingWatched|0|[]|[]", "nothing watched: never an all-clear")
	Set result = ..Handled(..Case("not json", "also not json", "[""x"""))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear_"|"_result.named_"|"_result.checked, "checks.nothingWatched|0|[]|[]", "unreadable recorded values count as [] and {}")
	Set result = ..Handled(..Case("{}", "[]"))
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.nothingWatched|0", "and so do values of another kind")
	Set odd = [5, "text", {"entry": "  "}, {"result": "passed"}, (..Row("failed", "B production", "x"))]
	Set result = ..Handled(..Case(odd.%ToJSON(), vitals))
	Do $$$AssertEquals(result.catalogKey_"|"_result.named_"|"_result.checked, "checks.notEverything|[""B production""]|[""B production""]", "elements that are no result are left out")
}

Method TestNeedsYouIsFailedRowsOnly()
{
	Set owner = ##class(OcuTalon.Data.Ownership).#EVAL
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Summary": "An eval mail", "Outcome": "tellnow"})
	Do ..Keep(decision)
	Set passed = [(..Row("passed", "Results production"))]
	Set result = ..Handled(..Case(passed.%ToJSON(), ..Vitals()))
	Do $$$AssertEquals(result.allClear, 1, "a Decision of the owner eval that needs the user does not stop the all-clear of a case")
}

Method TestSavedSummary()
{
	Do $ClassMethod(..#PROBE, "Reset")
	Set checks = [(..Row("passed", "Results production"))]
	Set case = ..Case(checks.%ToJSON(), ..Vitals(), ["Partner mail", "A newsletter"].%ToJSON())
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle2(case, host), "the DigestCase is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 1, "exactly one request goes to Decide")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 0, "and the DigestResult waits for the answer")
	Set request = $ClassMethod(..#PROBE, "Summary", 1)
	Do $$$AssertEquals(request.kind_"|"_request.provenance_"|"_request.sessionMode_"|"_request.seedText_"|"_request.ownerRef_"|"_request.channel, "turn|untrusted|fresh||eval|system", "it is an untrusted, fresh turn with no seed, of the owner eval, on the channel system")
	Do $$$AssertTrue((request.input [ "Partner mail") && (request.input [ "A newsletter"), "its input quotes the recorded summaries")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "rows")_"|"_$ClassMethod(..#PROBE, "Count", "notice"), "0|0", "and still no Rows and no Notification")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "Two items."
	Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set reply.DecisionRef = decisionRef
	Kill response
	Do $$$AssertStatusOK(host.OnResponse(case, .response, "", reply, "summary"), "the answer is handled")
	Set result = ..Result(1)
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 1, "then one DigestResult is sent")
	Do $$$AssertEquals(result.decisionRef_"|"_result.fallback_"|"_result.fallbackReason, decisionRef_"|0|", "with the Decision of the request")
	Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.allPassed|1", "and the verdict of the rows")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice")_"|"_..SentRows(##class(OcuTalon.Data.Ownership).#EVAL), "0|0", "no Notification and no Sent row")
}

Method TestSavedFallback()
{
	Set checks = [(..Row("passed", "Results production"))]
	For which = "fallback", "notreply", "error", "send" {
		Do $ClassMethod(..#PROBE, "Reset")
		Set case = ..Case(checks.%ToJSON(), ..Vitals(), ["Partner mail"].%ToJSON())
		Set host = ..Host()
		If which = "send" Set host.FailSummary = 1
		Do $$$AssertStatusOK(..Handle2(case, host), which_": the DigestCase is handled")
		If which '= "send" {
			Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 0, which_": the DigestResult waits for the answer")
			Kill response
			If which = "fallback" {
				Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
				Set reply.Fallback = 1
				Set reply.FallbackReason = "timeout"
				Set reply.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			} ElseIf which = "notreply" {
				Set reply = ##class(Ens.StringContainer).%New("this is not a Reply")
			} Else {
				Set reply = ""
				Do host.OnError(case, .response, "", $SYSTEM.Status.Error(5001, "zz the call failed"), "summary")
			}
			Do $$$AssertStatusOK(host.OnResponse(case, .response, "", reply, "summary"), which_": the answer is handled")
		}
		Set result = ..Result(1)
		Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "result"), 1, which_": the DigestResult is still sent")
		Do $$$AssertEquals(result.fallback_"|"_result.fallbackReason, "1|"_$Case(which, "fallback": "timeout", : "unusable"), which_": as a fallback with its reason")
		Do $$$AssertEquals(result.catalogKey_"|"_result.allClear, "checks.allPassed|1", which_": the verdict is the rows'")
	}
}

Method TestNoDestination()
{
	Set names = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = 'OcuTalon.Eval.Msg.DigestCase' AND SUBSTRING(Name, 1, 1) <> '%' ORDER BY Name")
	While rs.%Next() {
		Set names = names_$Select(names = "": "", 1: ",")_rs.%Get("Name")
	}
	Do $$$AssertEquals(names, "ItemId,RecordedChecks,RecordedSaved,RecordedVitals,SourceItemId", "a DigestCase holds the case's rows and ids and nothing that names an owner, session, channel or destination")
}

/// The number of Sent rows of every session.
Method AllSentRows() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
