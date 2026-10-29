/// Tests of check_status's eval branch (Story 9.7, AC4; AD-22, AD-28; orchestrator ruling U-143). WARM-SAFE: no production runs. Each test begins a
/// bridge context from an OcuTalon.Bridge.Msg.Request, as a turn does, saves OcuTalon.Eval.Msg.TurnResult bodies whose SourceItemId starts with
/// zz-checks-, and calls the tool method OcuTalon.Tools.WatchTools.CheckStatus in this process. OnBeforeAllTests, OnAfterOneTest and OnAfterAllTests
/// delete those bodies and the check rows of the tests, and end the context.
///   - TestEvalBranch: a call whose context's owner is eval and whose ItemId has a TurnResult with recorded rows (a failed and a passed one) answers
///     those rows in the form of check_status (WatchAnswers.Checked) and puts them in HostData, with the UTC time;
///   - TestEvalNothingWatched: recorded rows [] answer ok with no check and put {"checks": []} in HostData;
///   - TestNotEvalBranch: owner eval with no TurnResult of its ItemId, with RecordedChecks that are empty, an object, not JSON or a JSON string, or
///     an empty ItemId; an owner that is only like eval in its case; the owner instance; and no context all answer NOSESSION and leave HostData as it was,
///     also when a TurnResult with recorded rows exists. This is the ruling's pin that owner eval has no fall-through to live checks;
///   - TestSessionOwner: a session's Ref as the owner, with a TurnResult of the call's ItemId, gets the answer of CheckResults for that session, its own
///     rows, or none, and never the recorded rows (a non-eval owner never reaches the branch).
Class OcuTalon.Test.Eval.Checks Extends %UnitTest.TestCase
{

/// The start of the SourceItemId of the TurnResult bodies of these tests.
Parameter PREFIX = "zz-checks-";

/// The refs of the check rows that a test made.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ..Sweep()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Sweep()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ..Sweep()
	Quit $$$OK
}

/// The recorded rows of the case come out of check_status in its form, and go to HostData as they were recorded.
Method TestEvalBranch()
{
	Set failedAt = "2026-10-16T18:13:00Z", passedAt = "2026-10-16T18:14:00Z"
	Set rows = [{"result": "failed", "entry": "Orders production", "finding": "a fix waiting for your approval", "checkedAt": (failedAt)}, {"result": "passed", "entry": "Results production", "finding": "", "checkedAt": (passedAt)}]
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(itemId, rows.%ToJSON())
	Do ..Begin("eval", itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Set seen = [{"result": "failed", "entry": "Orders production", "finding": "a fix waiting for your approval", "checked": (##class(OcuTalon.Data.Time).ForMessage(failedAt))}, {"result": "passed", "entry": "Results production", "finding": "", "checked": (##class(OcuTalon.Data.Time).ForMessage(passedAt))}]
	Do $$$AssertEquals(answer.%ToJSON(), {"ok": true, "checks": (seen)}.%ToJSON(), "check_status answers the recorded rows")
	Do $$$AssertEquals(answer.%ToJSON(), ##class(OcuTalon.Tools.WatchAnswers).Checked(rows).%ToJSON(), "in the form of WatchAnswers.Checked")
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).ForMessage(failedAt) '= "", "the time that the model reads is not empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, {"checks": (rows)}.%ToJSON(), "HostData holds the recorded rows, with the UTC time")
	Do $$$AssertEquals(##class(OcuTalon.Tools.WatchAnswers).EvalCheckResults(##class(OcuTalon.Bridge.Context).Current(), .results), 1, "the branch answers 1")
	Do $$$AssertEquals(results.%ToJSON(), rows.%ToJSON(), "with the rows")

	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(other, [{"result": "not_checked", "entry": "Other production", "finding": "Not run yet", "checkedAt": ""}].%ToJSON())
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("eval", itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do $$$AssertEquals(answer.checks.%Size(), 2, "another case's TurnResult does not change the rows of this ItemId")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("eval", other)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do $$$AssertEquals(answer.checks.%Size()_"|"_answer.checks.%Get(0).entry, "1|Other production", "and the other ItemId gets its own rows")
}

/// Nothing watched: recorded rows [] are an answer of no checks, not a refusal.
Method TestEvalNothingWatched()
{
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(itemId, "[]")
	Do ..Begin("eval", itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do $$$AssertEquals(answer.%ToJSON(), {"ok": true, "checks": []}.%ToJSON(), "check_status answers ok with no check")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""checks"":[]}", "HostData holds the empty list")
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""zz"":1}")
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""zz"":1,""checks"":[]}", "and keeps the other members of a JSON object HostData, as for a session")
}

/// Every call that is not owner eval with recorded rows is refused as before and leaves HostData alone, also when a TurnResult exists. An
/// owner eval call with no recorded rows gets no checks at all: it never falls through to the results of the live system.
Method TestNotEvalBranch()
{
	Set rows = [{"result": "failed", "entry": "Orders production", "finding": "a fix waiting for your approval", "checkedAt": "2026-10-16T18:13:00Z"}].%ToJSON()
	Set noSession = {"ok": false, "message": ($Parameter("OcuTalon.Tools.CommandCall", "NOSESSION"))}.%ToJSON()
	Set cases = ""
	Set none = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set cases = cases_$ListBuild($ListBuild("owner eval, no TurnResult of its ItemId", "eval", none, ""))
	For text = "", "{}", "not json", """a text""", "{""checks"":[]}", "7" {
		Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do ..Record(itemId, text)
		Set cases = cases_$ListBuild($ListBuild("owner eval, RecordedChecks '"_text_"'", "eval", itemId, ""))
	}
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(itemId, rows)
	Set cases = cases_$ListBuild($ListBuild("the owner instance", "instance", itemId, ""))
	Set cases = cases_$ListBuild($ListBuild("the owner EVAL", "EVAL", itemId, ""))
	Set cases = cases_$ListBuild($ListBuild("the owner eval and a space", "eval ", itemId, ""))
	Set cases = cases_$ListBuild($ListBuild("an empty owner", "", itemId, ""))
	Set cases = cases_$ListBuild($ListBuild("no context", "", itemId, "none"))
	Do ..Record("", rows)
	Set cases = cases_$ListBuild($ListBuild("owner eval, an empty ItemId", "eval", "", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Bridge.Context).End()
		If $List(case, 4) = "" {
			Do ..Begin($List(case, 2), $List(case, 3))
			Do ##class(OcuTalon.Bridge.Context).Put("HostData", "{""zz"":1}")
		}
		Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
		Do $$$AssertEquals(answer.%ToJSON(), noSession, $List(case, 1)_": check_status answers NOSESSION")
		If $List(case, 4) = "" Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""zz"":1}", $List(case, 1)_": and leaves HostData as it was")
		Do $$$AssertEquals(##class(OcuTalon.Tools.WatchAnswers).EvalCheckResults($Select($List(case, 4) = "": ##class(OcuTalon.Bridge.Context).Current(), 1: ""), .results), 0, $List(case, 1)_": the branch answers 0")
		Do $$$AssertEquals(results.%ToJSON(), "[]", $List(case, 1)_": with no rows")
	}
}

/// A session's Ref as the owner never reaches the branch: its answer is that of CheckResults, whatever a TurnResult of the call's ItemId holds.
Method TestSessionOwner()
{
	Set recorded = [{"result": "failed", "entry": "Recorded production", "finding": "a recorded finding", "checkedAt": "2026-10-16T18:13:00Z"}].%ToJSON()
	Set owner = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set passedAt = "2030-01-01T10:00:00Z"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(owner, "ZZNS", "Zz.Passed", {"DisplayName": "Orders", "Result": "passed", "LastRunAt": (passedAt), "NextDueAt": "2099-01-01T00:00:00Z"})
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(itemId, recorded)
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Set own = [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": (passedAt)}]
	Do $$$AssertEquals(answer.%ToJSON(), ##class(OcuTalon.Tools.WatchAnswers).Checked(own).%ToJSON(), "a session's check_status answers its own rows")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, {"checks": (own)}.%ToJSON(), "and puts them in HostData, not the recorded rows")
	Do $$$AssertTrue(answer.%ToJSON() '[ "Recorded production", "the recorded rows are not in the answer")

	Set empty = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Record(itemId, recorded)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin(empty, itemId)
	Set answer = ##class(OcuTalon.Tools.WatchTools).CheckStatus()
	Do $$$AssertEquals(answer.%ToJSON(), {"ok": true, "checks": []}.%ToJSON(), "a session that watches nothing gets no check, not the recorded rows")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""checks"":[]}", "and HostData holds the empty list")
	Do $$$AssertEquals(##class(OcuTalon.Tools.WatchAnswers).EvalCheckResults(##class(OcuTalon.Bridge.Context).Current(), .results), 0, "the branch answers 0 for a session's owner")
}

/// --- helpers ---
/// Begins the bridge context of a turn from a request.
Method Begin(owner As %String, itemId As %String) [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "web"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of '"_owner_"'")
}

/// Saves a TurnResult body of the ItemId with the recorded checks text.
Method Record(itemId As %String, recorded As %String) [ Private ]
{
	Set body = ##class(OcuTalon.Eval.Msg.TurnResult).%New()
	Set body.ItemId = itemId
	Set body.SourceItemId = ..#PREFIX_$Increment(^||OcuTalonChecks)
	Set body.RecordedChecks = recorded
	Do $$$AssertStatusOK(body.%Save(), "a TurnResult is saved for the ItemId '"_itemId_"'")
}

/// Deletes the TurnResult bodies of these tests.
ClassMethod Sweep() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Eval_Msg.TurnResult WHERE SourceItemId %STARTSWITH ?", ..#PREFIX)
	Set ids = ""
	While result.%Next() {
		Set ids = ids_$ListBuild(result.%Get("ID"))
	}
	Set position = 0
	While $ListNext(ids, position, id) {
		Do ##class(OcuTalon.Eval.Msg.TurnResult).%DeleteId(id)
	}
}

}
