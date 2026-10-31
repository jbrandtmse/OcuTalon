/// Tests of OcuTalon.Install.ReconcileIn (Story 15.2; AD-5, AD-23).
///   - TestNext: the decision of one poll, a pure class method: a start made by the Production step is skipped, and so is a reconcile
///     that ran; items that do not run give "wait" until WAITWARNSECONDS have passed, then one "warn" and "wait" again; no missing item
///     gives "run";
///   - TestFailedReconcile: one poll of a shadow instance of the item, with the start lock free and every item of the running production
///     running, over a fixture area (OcuTalon.Install.Step.ZzReconcileIn<n>) whose Reconcile warns, changes the job's session id and
///     current header id and fails: the poll returns OK, sets Done, logs the warning as one Warning row and the failure as one Error row
///     naming the area and no Info row (LOGTEXT), puts the session id back and kills the header id again, and a later poll logs nothing.
///     It needs the production running (the throwaway's start); it waits up to 60 s for every item to run. The rows are those of the
///     test's own job. The fixture area exists only for the length of the test, and the job's ids are put back after it.
Class OcuTalon.Test.Install.ReconcileIn Extends %UnitTest.TestCase
{

Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("ReconcileIn", "n"))
	Quit $$$OK
}

/// Removes the fixture area when a test left it.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set area = ..Area()
	If ##class(%Dictionary.ClassDefinition).%ExistsId(area) Do $SYSTEM.OBJ.Delete(area, "-d")
	Quit $$$OK
}

Method TestNext()
{
	Set item = "OcuTalon.Install.ReconcileIn"
	Set limit = $Parameter(item, "WAITWARNSECONDS")
	Do $$$AssertEquals(limit, 60, "the warning comes after 60 s")

	Do $$$AssertEquals($ClassMethod(item, "Next", 1, 0, "", 0, 0), "skip", "a start made by the Production step is skipped")
	Do $$$AssertEquals($ClassMethod(item, "Next", 1, 0, "Decide", 500, 0), "skip", "also with items missing, however long it waited")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 1, "", 0, 0), "skip", "a reconcile that ran is not repeated")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 1, "Decide", 500, 1), "skip", "also with items missing")

	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", 0, 0), "wait", "an item that does not run gives wait")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide,Checks", limit - 1, 0), "wait", "also just under the limit")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "OcuTalon.Production is not running", 5, 0), "wait", "and a production that does not run")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit, 0), "warn", "at the limit the first poll warns")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit + 30, 0), "warn", "and so does any later poll before the warning was logged")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit + 30, 1), "wait", "after the warning it waits again")

	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "", 0, 0), "run", "nothing missing gives run")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "", limit + 30, 1), "run", "also after a warning")
}

Method TestFailedReconcile()
{
	Set n = ..Number
	Set area = ..Area()
	Set text = $Replace($Replace(##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||FixtureArea").Data.Read(100000), $Char(13), ""), "@N@", n)
	Set sc = ##class(%Compiler.UDL.TextServices).SetTextFromString($Namespace, area, text, $Char(10))
	If $$$ISOK(sc) Set sc = $SYSTEM.OBJ.Compile(area, "ck-d")
	Do $$$AssertStatusOK(sc, "the fixture area compiles")
	If $$$ISERR(sc) Quit
	Set end = $ZHorolog + 60
	While (##class(OcuTalon.Install.Step.Production).NotRunning() '= "") && (end > $ZHorolog) {
		Hang 1
	}
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item of the production runs, so a poll reconciles")
	Set item = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Install.ReconcileIn", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the item is made")
	If '$IsObject(item) Quit
	Do $$$AssertStatusOK(item.OnInit(), "OnInit runs")
	Do $$$AssertEquals(item.ByStep, 0, "with the start lock free")

	Merge saved = %Ensemble
	Set %Ensemble("SessionId") = 900000000 + n
	Kill %Ensemble("CurrentHeaderId")
	Set first = ..LastRow()
	Set sc = item.OnProcessInput("", .output)
	Set session = $Get(%Ensemble("SessionId"))
	Set header = $Data(%Ensemble("CurrentHeaderId"))
	Set second = ..LastRow()
	Set sc2 = item.OnProcessInput("", .output)
	Set third = ..LastRow()
	Kill %Ensemble("SessionId"), %Ensemble("CurrentHeaderId")
	Merge %Ensemble("SessionId") = saved("SessionId"), %Ensemble("CurrentHeaderId") = saved("CurrentHeaderId")
	Do $SYSTEM.OBJ.Delete(area, "-d")

	Do $$$AssertStatusOK(sc, "the poll returns OK although the reconcile failed")
	Do $$$AssertEquals(item.Done, 1, "and the reconcile ran")
	Do $$$AssertEquals(..Rows(first, second, 3, "ReconcileIn: ReconcileIn fixture warning "_n), 1, "its warning is one Warning row")
	Do $$$AssertEquals(..Rows(first, second, 2, "ReconcileIn: the reconcile failed: %"_area_"%ReconcileIn fixture failure "_n_"%"), 1, "its failure is one Error row naming the area")
	Do $$$AssertEquals(..Rows(first, second, 4, ##class(OcuTalon.Install.ReconcileIn).#LOGTEXT), 0, "and no Info row says that it reconciled")
	Do $$$AssertEquals(session, 900000000 + n, "the job's session id is put back after the reconcile")
	Do $$$AssertEquals(header, 0, "and its current header id, which was not defined, is killed again")
	Do $$$AssertStatusOK(sc2, "a later poll returns OK")
	Do $$$AssertEquals(..Rows(second, third), 0, "and logs nothing: a failed reconcile is not repeated")
}

/// The fixture area's class name.
Method Area() As %String [ Private ]
{
	Quit "OcuTalon.Install.Step.ZzReconcileIn"_..Number
}

/// The highest row id of the event log, 0 when it is empty.
ClassMethod LastRow() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of event log rows of ReconcileIn that this job logged after row id from and up to row id to; with type (2 Error, 3 Warning,
/// 4 Info) only those of the type, and with text only those whose Text is LIKE it.
ClassMethod Rows(from As %Integer, to As %Integer, type As %Integer = "", text As %String = "") As %Integer [ Private ]
{
	Set query = "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND ID <= ? AND Job = ? AND SourceClass = ?"
	Set args = 4, args(1) = from, args(2) = to, args(3) = $Job, args(4) = "OcuTalon.Install.ReconcileIn"
	If type '= "" Set query = query_" AND Type = ?", args($Increment(args)) = type
	If text '= "" Set query = query_" AND Text LIKE ?", args($Increment(args)) = text
	Set result = ##class(%SQL.Statement).%ExecDirect(, query, args...)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// An area whose Reconcile warns, changes the job's session id and current header id, and fails.
XData FixtureArea [ MimeType = text/plain ]
{
Class OcuTalon.Install.Step.ZzReconcileIn@N@ Extends OcuTalon.Install.Step
{

ClassMethod Reconcile() As %Status
{
	Do ..Warn("ReconcileIn fixture warning @N@")
	Set %Ensemble("SessionId") = 800000000 + @N@, %Ensemble("CurrentHeaderId") = 700000000 + @N@
	Quit $SYSTEM.Status.Error(5001, "ReconcileIn fixture failure @N@")
}

}
}

}
