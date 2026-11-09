/// The Budgets save of OcuTalon.Core.SettingsOps against the real bridge and the running production (Story 18.3 AC 4; AD-19, AD-20). THEY RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21): they need OcuTalon.Production running with its runner items and the CI mock, and the CI override's environment.
///   - TestSavedBudgetsApplyToTheNextDecide: the real SettingsOps (no double) saves DecisionTokenBudget and DailyCostCapUSD from web_admin. Bridge.Settings.Values and
///     Bridge.Budget.State show the new values; the next decide, with no restart, is answered with the fallback reason budget (and, before the save, with no fallback, so that
///     the fallback is the save's); one Settings audit entry for each value is read back from the IRIS audit log. OnAfterOneTest puts back the System Default Settings rows of
///     Decide as found, the capped mark of the day, the rows of the decides, and the runners' key entries.
Class OcuTalon.Test.Core.SettingsBudgetsLive Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsetbudg";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter AUDITLOG = "OcuTalon.Test.Bridge.AuditLog";

/// The runners of the decide kind, whose key entries the test points at the CI mock key variable.
Parameter RUNNERS = "TriageAgent,TriageAgentRetry";

/// The token budget that the test saves: any request is over it.
Parameter BUDGET = 1;

/// The cap that the test saves, in US dollars, far above the day's spend.
Parameter CAP = "987.65";

/// Seconds to wait for an audit entry.
Parameter AUDITSECONDS = 180;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The System Default Settings rows of Decide before the test (RunnerFixture RememberDefault), to be put back.
Property SavedRows As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set ..ItemIds = ""
	Set ..SavedRows = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing = "" {
		Set fixture = ..#FIXTURE
		Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
		Set ..SavedRows = ""
		Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
		Set position = 0
		While $ListNext(..ItemIds, position, itemId) {
			Do $ClassMethod(fixture, "DeleteSteps", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
		}
		Set ..ItemIds = ""
		Do $ClassMethod(fixture, "DropSince", ..SessionMark)
		If ..Pointed {
			Set ..Pointed = 0
			Do $ClassMethod(fixture, "RestoreKeys", ..#RUNNERS)
		}
	}
	Quit $$$OK
}

/// The real SettingsOps saves the two budgets. The values read back from the bridge, the next decide runs under them (a token budget of 1 refuses any request, with the
/// reason budget), and each change has its Settings audit entry in the IRIS audit log.
Method TestSavedBudgetsApplyToTheNextDecide()
{
	If '..Guard() Quit
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "DecisionTokenBudget")
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "DailyCostCapUSD")
	Set ..SavedRows = saved
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Set ..Pointed = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", ..#RUNNERS), "the entries of the decide runners are pointed at the CI mock key variable")

	Set before = ##class(OcuTalon.Bridge.Settings).Values()
	Set budgetWas = before.DecisionTokenBudget
	Set capWas = before.DailyCostCapUSD
	Do $$$AssertTrue((budgetWas '= ..#BUDGET) && (capWas '= ..#CAP), "control: the budgets are not the values that the test saves ("_budgetWas_", "_capWas_")")
	Set first = ..Decide()
	Do $$$AssertEquals(first.Fallback_"|"_first.FallbackReason, "0|", "control: before the save the decide is answered by the model")

	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = $ClassMethod(..#AUDITLOG, "Now")
	Set result = ..Save({"DecisionTokenBudget": (..#BUDGET), "DailyCostCapUSD": (..#CAP)}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "SettingsOps saves the two budgets: "_result.Data)

	Set values = ##class(OcuTalon.Bridge.Settings).Values()
	Do $$$AssertEquals(values.DecisionTokenBudget_"|"_values.DailyCostCapUSD, ..#BUDGET_"|"_..#CAP, "Bridge.Settings.Values shows the new token budget and cap")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(state.cap, +..#CAP, "and the daily cost cap that Bridge.Budget enforces is the new one")
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).Values().bridge.DecisionTokenBudget, ..#BUDGET, "and the page's GET body shows the token budget")

	Set second = ..Decide()
	Do $$$AssertEquals(second.Fallback_"|"_second.FallbackReason, "1|budget", "the next decide, with no restart, is refused by the new token budget")

	Set entries = $ClassMethod(..#AUDITLOG, "Wait", since, "OcuTalon", "Settings", "", ref, "", 2, ..#AUDITSECONDS)
	Do $$$AssertEquals(entries.%Size(), 2, "two Settings entries are read back from the IRIS audit log, one for each value")
	If entries.%Size() < 2 Quit
	Set found = ""
	For i = 0:1:1 {
		Set data = entries.%Get(i).data
		Set found = found_$ListBuild(data.setting_"|"_data.from_"|"_data.to_"|"_data.channel)
	}
	Do $$$AssertEquals($ListToString(found, ";"), "DecisionTokenBudget|"_budgetWas_"|"_..#BUDGET_"|web;DailyCostCapUSD|"_capWas_"|"_..#CAP_"|web", "the token budget, then the cap, each with the value it replaced")
}

/// A decide of kind decide for TriageAgent, answered through Decide; the Response. Its ItemId is cleaned up after the test.
Method Decide() As OcuTalon.Bridge.Msg.Result [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Quit response
}

/// A SaveSettings of the budgets section with the body for the session Ref, from web_admin for zzadmin, carried out by a shadow instance of the real SettingsOps in this process.
Method Save(body As %DynamicObject, ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "budgets"
	Set command.Changes = body.%ToJSON()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ref
	Set command.Origin = "web_admin"
	Set operation = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.SettingsOps", .sc)
	Do $$$AssertStatusOK(sc, "the real operation is made")
	Set sc = operation.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
