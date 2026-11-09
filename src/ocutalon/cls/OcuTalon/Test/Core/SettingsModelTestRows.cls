/// What a model Test press leaves behind (Story 18.3, DW-965; AD-20, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running with its
/// runner items and the CI mock. A TestModel goes through Commands.Submit to the real SettingsOps job and Decide, which records one Decision row and one Usage row with the ItemId
/// test.<ref>. The tests pin where those rows are visible:
///   - TestPressRowsAreOwnedByTheInstance: the rows are Kind decide, owner instance, channel system, with the model, a cost and a duration. Every session-bound reader of
///     Data.Ownership (the Recent decisions list of /v1/state, the run cost) takes the owner from the session and refuses owner instance, so a session sees none of them;
///   - the cost of the press is also logged (LogMessage, never asserted) as read by the two readers that are not session-bound: Bridge.Budget.State (the daily cost cap)
///     and Digest.Cost (the digest's cost line), both Lane A. They sum every Usage row that is not owner eval, so the press is counted in both (DW-965).
/// OnAfterOneTest deletes the rows of the press and puts back the runner's key entry and the day's capped mark.
Class OcuTalon.Test.Core.SettingsModelTestRows Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsetrows";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The runner whose key entry the test points at the CI mock key variable.
Parameter RUNNERS = "TriageAgent";

/// 1 while the entry of the runner is pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing = "" {
		Set fixture = ..#FIXTURE
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT ItemId FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
		While result.%Next() {
			Do $ClassMethod(fixture, "DeleteSteps", result.%GetData(1))
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId LIKE 'test.%'")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
		Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
		Do $ClassMethod(fixture, "DropSince", ..SessionMark)
		If ..Pointed {
			Set ..Pointed = 0
			Do $ClassMethod(fixture, "RestoreKeys", ..#RUNNERS)
		}
	}
	Quit $$$OK
}

/// A press for TriageAgent leaves one Decision row and one Usage row of owner instance, and no session-bound reader returns them.
Method TestPressRowsAreOwnedByTheInstance()
{
	If '..Guard() Quit
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Set ..Pointed = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", ..#RUNNERS), "the entry of the runner is pointed at the CI mock key variable")
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tomorrow = ##class(OcuTalon.Digest.Cost).Midnight(##class(OcuTalon.Data.Time).NowUtc(), 1)
	Set capBefore = ##class(OcuTalon.Bridge.Budget).State().spent
	Set digestBefore = ##class(OcuTalon.Digest.Cost).Yesterday(session, tomorrow, .sc)
	Do $$$AssertStatusOK(sc, "control: the digest's cost line reads today's cost")
	Set floors = ..Floors()

	Set command = ##class(OcuTalon.Msg.Command.TestModel).%New()
	Set command.Agent = "TriageAgent"
	Set command.SessionRef = session
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result), "the press is submitted")
	Do $$$AssertTrue($IsObject(result), "and answered")
	If '$IsObject(result) Quit
	Set answer = {}.%FromJSON(result.Data)
	Do $$$AssertEquals(result.Outcome_"|"_answer.answered, "tested|1", "the model answered: "_result.Data)

	Set decisions = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), MIN(%EXACT(Kind)), MIN(%EXACT(OwnerRef)), MIN(%EXACT(Model)), MIN(%EXACT(ItemId)), MIN(CostUSD), MIN(DurationMs) FROM OcuTalon_Bridge_Data.Decision WHERE ID > ? AND ItemId LIKE 'test.%'", $Piece(floors, "|", 1))
	Do decisions.%Next()
	Do $$$AssertEquals(decisions.%GetData(1), 1, "the press left one Decision row")
	Do $$$AssertEquals(decisions.%GetData(2)_"|"_decisions.%GetData(3), "decide|instance", "of Kind decide and owner instance")
	Do $$$AssertTrue((decisions.%GetData(4) '= "") && (decisions.%GetData(6) > 0) && (decisions.%GetData(7) '< 0), "with the model, a cost and a duration")
	Set itemId = decisions.%GetData(5)
	Set usage = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), MIN(%EXACT(OwnerRef)), MIN(%EXACT(Channel)), MIN(CostUSD), MIN(%EXACT(ItemId)) FROM OcuTalon_Bridge_Data.Usage WHERE ID > ? AND ItemId LIKE 'test.%'", $Piece(floors, "|", 2))
	Do usage.%Next()
	Do $$$AssertEquals(usage.%GetData(1), 1, "and one Usage row")
	Do $$$AssertEquals(usage.%GetData(2)_"|"_usage.%GetData(3)_"|"_usage.%GetData(5), "instance|system|"_itemId, "of owner instance, channel system, with the ItemId of the Decision row")
	Set cost = usage.%GetData(4)
	Do $$$AssertTrue(cost > 0, "priced "_cost)

	Set rows = ##class(OcuTalon.Data.Ownership).Decisions(session, 20, .sc)
	Do $$$AssertStatusOK(sc, "the Recent decisions list reads for the session")
	Do $$$AssertEquals(rows.Count(), 0, "and holds none of the press's rows (the list is the session's own decisions)")
	Set rows = ##class(OcuTalon.Data.Ownership).Decisions("instance", 20, .sc)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && (rows.Count() = 0), "no reader takes owner instance as a session: the list refuses it")
	Set run = ##class(OcuTalon.Data.Ownership).RunCost(session, "", .sc)
	Do $$$AssertEquals(run.decisions_"|"_run.costUSD, "0|0", "the session's run cost counts none of it")
	Set run = ##class(OcuTalon.Data.Ownership).RunCost("instance", "", .sc)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "and the run cost refuses owner instance")

	Set capAfter = ##class(OcuTalon.Bridge.Budget).State().spent
	Set digestAfter = ##class(OcuTalon.Digest.Cost).Yesterday(session, tomorrow, .sc)
	Do $$$LogMessage("DW-965: the press cost "_cost_"; the daily cost cap's spent went from "_capBefore_" to "_capAfter_"; the digest's cost line for the day went from "_digestBefore_" to "_digestAfter)
}

/// The highest ID of the Decision table and of the Usage table now, as "decision|usage", 0 for none: a row above it is a row of the test.
ClassMethod Floors() As %String [ Private ]
{
	Set decision = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Bridge_Data.Decision")
	Do decision.%Next()
	Set usage = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Bridge_Data.Usage")
	Do usage.%Next()
	Quit +decision.%GetData(1)_"|"_+usage.%GetData(1)
}

}
