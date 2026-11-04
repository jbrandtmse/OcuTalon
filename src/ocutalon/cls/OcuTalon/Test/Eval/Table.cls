/// Tests of the result table's own methods and of the wait for a run (Story 9.1; AD-3, AD-22, AD-33). WARM-SAFE: they start no
/// production and send no message. Every run Ref is a 22-character-or-shorter text that starts with zz, every case name starts with
/// zz-table-, and each test removes the rows of the runs it made.
///   - TestOpen: Open saves one row in state sent with the ids as given and SentAt now (UTC), refuses a second row for the same case of
///     a run (the first stays as it was), allows the same case in another run, and refuses an empty run, case or ItemId with nothing stored;
///   - TestPending: Pending gives the row of an ItemId that is still sent, and gives none for an empty ItemId, an ItemId nobody opened or
///     a row already decided;
///   - TestUnanswered: it counts the sent rows of the run only, and falls when a row is decided;
///   - TestRemove: Remove deletes the row of one case, or every row of the run, and never another run's; an empty run is refused and
///     deletes nothing;
///   - TestWait: EvalIn's Wait returns how many rows of the run are still sent, waits for the seconds while one is, and returns at once
///     when none is.
Class OcuTalon.Test.Eval.Table Extends %UnitTest.TestCase
{

/// The start of every run Ref the tests make.
Parameter RUNPREFIX = "zz";

/// The start of every case name the tests make.
Parameter CASEPREFIX = "zz-table-";

/// The Refs of the runs that the test made, comma-separated.
Property Runs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ..RemoveRows()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Runs = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Runs, ",") {
		If $Piece(..Runs, ",", i) '= "" Do ##class(OcuTalon.Eval.Data.CaseResult).Remove($Piece(..Runs, ",", i))
	}
	Do ..RemoveRows()
	Quit $$$OK
}

/// Open saves the row of a case that was sent, and only one row for a case of a run.
Method TestOpen()
{
	Set run = ..NewRun(), other = ..NewRun()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set before = ##class(OcuTalon.Bridge.Time).NowUtc()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"a", "source-a", itemId), "Open saves the row of a case")
	Set after = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row = ..RowOf(run, "a")
	If $IsObject(row) {
		Do $$$AssertEquals(row.RunRef_"|"_row.CaseName_"|"_row.SourceItemId_"|"_row.ItemId_"|"_row.State, run_"|"_..#CASEPREFIX_"a|source-a|"_itemId_"|sent", "the row holds the ids as given, in state sent")
		Do $$$AssertTrue(row.SentAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "SentAt is UTC to the second: "_row.SentAt)
		Do $$$AssertTrue((before '] row.SentAt) && (row.SentAt '] after), "and lies between the clock before the call ("_before_") and after it ("_after_")")
		Do $$$AssertEquals(row.DecidedAt_row.DecisionRef_row.Outcome_row.CostUSD_row.TurnDecisionRef_row.LargestRequestTokens, "", "nothing of a decision is on it")
		Do $$$AssertEquals(row.Fallback, 0, "and it is not a fallback")
	}

	Set sc = ##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"a", "source-again", ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a second row for the same case of the run is refused")
	Do $$$AssertEquals(..Count(run), 1, "the run still has one row")
	Set row = ..RowOf(run, "a")
	If $IsObject(row) Do $$$AssertEquals(row.SourceItemId_"|"_row.ItemId, "source-a|"_itemId, "and it is the first one, unchanged")

	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(other, ..#CASEPREFIX_"a", "source-a", ##class(OcuTalon.Bridge.Ids).NewRef()), "the same case in another run is a row of its own")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"b", "source-b", ##class(OcuTalon.Bridge.Ids).NewRef()), "and so is another case of the run")

	Set refused = $ListBuild($ListBuild("", ..#CASEPREFIX_"c", ##class(OcuTalon.Bridge.Ids).NewRef()), $ListBuild(run, "", ##class(OcuTalon.Bridge.Ids).NewRef()), $ListBuild(run, ..#CASEPREFIX_"c", ""))
	Set position = 0
	While $ListNext(refused, position, args) {
		Set label = "run '"_$List(args, 1)_"', case '"_$List(args, 2)_"', ItemId '"_$List(args, 3)_"': "
		Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Eval.Data.CaseResult).Open($List(args, 1), $List(args, 2), "source-c", $List(args, 3))), label_"refused")
	}
	Do $$$AssertEquals(..Count(run)_"|"_..Count(other), "2|1", "and nothing was stored for them")
}

/// Pending gives the row of the ItemId that is still sent, and nothing else.
Method TestPending()
{
	Set run = ..NewRun()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef(), otherId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"a", "source-a", itemId), "a case is opened")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"b", "source-b", otherId), "and another")
	Set pending = ##class(OcuTalon.Eval.Data.CaseResult).Pending(itemId)
	Do $$$AssertTrue($IsObject(pending), "the ItemId has a pending row")
	If $IsObject(pending) {
		Do $$$AssertEquals(pending.CaseName_"|"_pending.State, ..#CASEPREFIX_"a|sent", "it is the case's row, in state sent")
	}
	Do $$$AssertTrue('$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending("")), "an empty ItemId has none")
	Do $$$AssertTrue('$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(##class(OcuTalon.Bridge.Ids).NewRef())), "an ItemId nobody opened has none")
	If $IsObject(pending) {
		Set pending.State = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED
		Do $$$AssertStatusOK(pending.%Save(), "the row is decided")
	}
	Do $$$AssertTrue('$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(itemId)), "a decided row is no longer pending")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(otherId)), "the other case's row still is")
}

/// Unanswered counts the sent rows of the run.
Method TestUnanswered()
{
	Set run = ..NewRun(), other = ..NewRun()
	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"a", "source-a", first), "the first case of the run is opened")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"b", "source-b", ##class(OcuTalon.Bridge.Ids).NewRef()), "the second case of the run is opened")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(other, ..#CASEPREFIX_"a", "source-a", ##class(OcuTalon.Bridge.Ids).NewRef()), "a case of another run is opened")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(run), 2, "the run has two sent rows")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(other), 1, "the other run has one")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(""), 0, "no run has none")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(##class(OcuTalon.Bridge.Ids).NewRef()), 0, "and a run that was never started has none")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).Pending(first)
	If '$IsObject(row) Do $$$AssertTrue(0, "the first case has a pending row") Quit
	Set row.State = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED
	Do $$$AssertStatusOK(row.%Save(), "the first case is decided")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(run), 1, "the run has one sent row left")
	Do $$$AssertEquals(##class(OcuTalon.Eval.Data.CaseResult).Unanswered(other), 1, "and the other run's count is as it was")
}

/// Remove deletes one case's row or the run's rows, and no other run's.
Method TestRemove()
{
	Set run = ..NewRun(), other = ..NewRun()
	For name = "a", "b" {
		Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_name, "source-"_name, ##class(OcuTalon.Bridge.Ids).NewRef()), "case "_name_" of the run is opened")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(other, ..#CASEPREFIX_"a", "source-a", ##class(OcuTalon.Bridge.Ids).NewRef()), "a case of another run is opened")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Remove(run, ..#CASEPREFIX_"a"), "one case of the run is removed")
	Do $$$AssertEquals(..Count(run)_"|"_..Count(other), "1|1", "only that row went: the run's other case and the other run's case stay")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(run, ..#CASEPREFIX_"b")), "the one that stays is case b")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Remove(run, ..#CASEPREFIX_"missing"), "removing a case that has no row is no error")
	Do $$$AssertEquals(..Count(run)_"|"_..Count(other), "1|1", "and removes nothing")
	Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Eval.Data.CaseResult).Remove("")), "an empty run is refused")
	Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Eval.Data.CaseResult).Remove("", ..#CASEPREFIX_"a")), "also with a case")
	Do $$$AssertEquals(..Count(run)_"|"_..Count(other), "1|1", "and deletes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Remove(run), "the run is removed")
	Do $$$AssertEquals(..Count(run)_"|"_..Count(other), "0|1", "every row of the run went and the other run's row stays")
}

/// Wait returns how many rows of the run are still sent: it waits for the seconds while one is, and returns at once when none is.
Method TestWait()
{
	Set run = ..NewRun()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.Data.CaseResult).Open(run, ..#CASEPREFIX_"a", "source-a", itemId), "a case is opened")
	Do $$$AssertEquals(##class(OcuTalon.Eval.In).Wait(run, 0), 1, "with no time to wait, Wait still says that one row is sent")
	Set start = $ZHorolog
	Set open = ##class(OcuTalon.Eval.In).Wait(run, 1)
	Set elapsed = $ZHorolog - start
	Do $$$AssertEquals(open, 1, "after a second the row is still sent, and Wait says so")
	Do $$$AssertTrue((elapsed '< 0.9) && (elapsed < 3), "and it waited for about the second: "_elapsed_" s")
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).Pending(itemId)
	If '$IsObject(row) Do $$$AssertTrue(0, "the case has a pending row") Quit
	Set row.State = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED
	Do $$$AssertStatusOK(row.%Save(), "the case is decided")
	Set start = $ZHorolog
	Do $$$AssertEquals(##class(OcuTalon.Eval.In).Wait(run, 30), 0, "with every row decided, Wait says that none is sent")
	Do $$$AssertTrue($ZHorolog - start < 1, "and does not wait: "_($ZHorolog - start)_" s")
	Set start = $ZHorolog
	Do $$$AssertEquals(##class(OcuTalon.Eval.In).Wait("", 30), 0, "a run with no Ref has none")
	Do $$$AssertTrue($ZHorolog - start < 1, "and Wait does not wait for it either: "_($ZHorolog - start)_" s")
}

/// --- helpers ---
/// Deletes every row whose case name starts with the tests' prefix, whatever its run (a row that a faulty Open saved with no run included).
ClassMethod RemoveRows() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Eval_Data.CaseResult WHERE CaseName %STARTSWITH ?", ..#CASEPREFIX)
}

/// A new run Ref that starts with zz, kept for the clean-up.
Method NewRun() As %String [ Private ]
{
	Set run = ..#RUNPREFIX_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Runs = ..Runs_$Select(..Runs = "": "", 1: ",")_run
	Quit run
}

/// The row of the case of the run, opened afresh, or "" with a failed assertion.
Method RowOf(run As %String, name As %String) As OcuTalon.Eval.Data.CaseResult [ Private ]
{
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).RunCaseIndexOpen(run, ..#CASEPREFIX_name)
	Do $$$AssertTrue($IsObject(row), name_": the row exists")
	Quit row
}

/// The number of rows of the run.
ClassMethod Count(run As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", run)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
