/// Tests of the Public step (Story 3.8; AD-19, AD-23, DW-160). They set start variables in the test process, as Test.Install.ProviderEnv
/// does, and run the steps in process, as the after-start script does. They change the public keys, readiness, the three budget rows of
/// Decide, the instance's password-validation setting, the page size pins and, in TestDecisionAtTheCap, the runners' keys and Decide's host
/// sink: they run on throwaways and in CI only (Rule 21).
///   - TestEveryStartValue, TestDefaults, TestBadStartValues: the keys and the refusals (rows 1 to 3);
///   - TestFlagOffWritesOnlyTheFlag, TestOnlyOneIsOn, TestFlagOffKeepsARowOfAnotherSpecificity, TestBudgetRows, TestEmptyCountsAsUnset: the local
///     install, the flag's exact value, an empty variable and the budget rows (rows 4 and 5);
///   - TestStartValuesReachTheUsersStep: the chain from the keys to the accounts and the guard (row 6);
///   - TestDecisionAtTheCap: a decision at the cap falls back with daily_cap and sends nothing (row 7);
///   - TestReadyPinsThePublicAccounts: the last phase pins the page size, then sets readiness (row 8, DW-160).
/// Before each test it saves the 16 variables (present and value), the 13 keys and readiness, the three Decide rows, the guard (setting and
/// routine) and the runners' state, and after it puts them back, with the fixture accounts and their pins removed. The fixture accounts are
/// ZzPublic<n>Demo and ZzPublic<n>Ro, n from ^OcuTalonTest("Public","n"), which is never reset.
Class OcuTalon.Test.Install.Public Extends %UnitTest.TestCase
{

/// The step under test.
Parameter STEP = "OcuTalon.Install.Step.Public";

/// The accessor of the public keys.
Parameter ACCESSOR = "OcuTalon.Data.Public.Settings";

/// The shared helpers of the password guard's tests.
Parameter GUARD = "OcuTalon.Test.Install.PasswordGuard";

/// The runner fixture.
Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The production and the item of the budget rows.
Parameter PRODUCTION = "OcuTalon.Production";

/// The budget settings of Decide that the step writes.
Parameter SETTINGS = "DailyCostCapUSD,GatewaySpendUSD,GatewaySpendDate";

Property Number As %Integer;

Property Demo As %String;

Property Ro As %String;

Property Readme As %String;

/// The variables as a test found them: a dynamic object of variable: {present, value}.
Property Env As %DynamicObject;

/// The keys and readiness as a test found them, and the rows, the guard state and the runners' state.
Property Keys As %DynamicObject;

Property Rows As %List;

Property GuardState As %List;

/// 1 when the test pointed the runners' keys at the mock (RestoreKeys is then called).
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// 1 while a test holds a Decide row of a wider specificity (the item *), which OnAfterOneTest deletes.
Property WideRow As %Boolean [ InitialExpression = 0 ];

/// What UseItemSetting saved of Decide's HostSinkClass, while the sink is swapped.
Property SinkSaved As %DynamicObject;

/// The item ids of the decisions of the test, whose rows are deleted.
Property ItemIds As %List;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Public", "n"))
	Set ..Demo = "ZzPublic"_..Number_"Demo"
	Set ..Ro = "ZzPublic"_..Number_"Ro"
	Set ..Readme = "ZzPublic"_..Number_"Readme"
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Takes the variables, the keys, readiness, the rows and the guard as found, and starts the test with none of the 16 variables set.
Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Env = {}
	Set list = ..Variables()
	Set position = 0
	While $ListNext(list, position, variable) {
		Do ..Env.%Set(variable, {"present": (+##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable)), "value": ($SYSTEM.Util.GetEnviron(variable))})
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
	}
	Set ..Keys = {}
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS")_",ready")
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ..Keys.%Set(key, $ClassMethod(..#ACCESSOR, "Get", key))
	}
	Set rows = ""
	Set settings = $ListFromString(..#SETTINGS)
	Set position = 0
	While $ListNext(settings, position, setting) {
		Do $ClassMethod(..#FIXTURE, "RememberDefault", .rows, "Decide", setting)
	}
	Set ..Rows = rows
	Set ..GuardState = $ClassMethod(..#GUARD, "State")
	Set ..ItemIds = ""
	Do ..ClearAccounts()
	Quit $SYSTEM.Status.OK()
}

/// Puts everything back, also after a failure: the runners' keys and Decide's sink, today's day mark, the decisions' rows, the variables,
/// the keys and readiness, the rows, the guard, and removes the fixture accounts.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	If $IsObject(..SinkSaved) {
		Do $ClassMethod(..#FIXTURE, "RestoreItemSetting", "Decide", ..SinkSaved)
		Set ..SinkSaved = ""
	}
	Kill ^OcuTalonTest("ProbeSink")
	If ..WideRow {
		Set ..WideRow = 0
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||*||*||DailyCostCapUSD")
	}
	If ..Pointed {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys")
	}
	Kill ^OcuTalonBP.UsageCapped(today)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do $ClassMethod(..#FIXTURE, "RestoreDefaults", ..Rows)
	Do $ClassMethod(..#GUARD, "Restore", ..GuardState)
	If $IsObject(..Keys) {
		Set iterator = ..Keys.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			If key = "ready" {
				If value = 1 {
					Do $ClassMethod(..#ACCESSOR, "SetReady")
				} Else {
					Do $ClassMethod(..#ACCESSOR, "ClearReady")
				}
			} Else {
				Do $ClassMethod(..#ACCESSOR, "Set", key, value)
			}
		}
	}
	If $IsObject(..Env) {
		Set list = ..Variables()
		Set position = 0
		While $ListNext(list, position, variable) {
			Set was = ..Env.%Get(variable)
			If was.present {
				Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, was.value)
			} Else {
				Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
			}
		}
	}
	Do ..ClearAccounts()
	Quit $SYSTEM.Status.OK()
}

/// Matrix row 1: with the flag and all twelve other public variables set, Run is OK, every key reads back as given, onlineDemo is 1, the
/// three budget rows hold their values, and readiness, which was 1, is cleared.
Method TestEveryStartValue()
{
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Do ..Use({"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw", "OCUTALON_RESET_INTERVAL_HOURS": "6", "OCUTALON_RESET_ANCHOR": "2026-10-25T00:00:00Z", "OCUTALON_LAST_RESET": "2026-10-25T06:00:00Z", "OCUTALON_LAST_RESET_KIND": "unscheduled", "OCUTALON_PROXY_ADDRESS": "10.9.8.7", "OCUTALON_CONNECTION_CAP": "5", "OCUTALON_CONNECTION_RESERVE": "1", "OCUTALON_MESSAGE_ALLOWANCE": "30", "OCUTALON_DAILY_COST_CAP_USD": "12.5", "OCUTALON_GATEWAY_SPEND_USD": "3.2", "OCUTALON_GATEWAY_SPEND_DATE": (today)})
	Do $ClassMethod(..#ACCESSOR, "SetReady")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK")
	Set expected = {"onlineDemo": "1", "demoUser": "Zz-demo", "demoPassword": "Zz-demo-pw", "readonlyUser": "Zz-ro", "readonlyPassword": "Zz-ro-pw", "resetIntervalHours": "6", "resetAnchor": "2026-10-25T00:00:00Z", "lastReset": "2026-10-25T06:00:00Z", "lastResetKind": "unscheduled", "proxyAddress": "10.9.8.7", "connectionCap": "5", "connectionReserve": "1", "messageAllowance": "30"}
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key), value, key_" reads back as given")
	}
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), "", "readiness is cleared")
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), "12.5", "the cost cap row")
	Do $$$AssertEquals(..Row("GatewaySpendUSD"), "3.2", "the gateway spend row")
	Do $$$AssertEquals(..Row("GatewaySpendDate"), today, "the gateway date row")
}

/// Matrix row 2: with the flag and the four account variables only, the interval is 4, the cap 8, the reserve 2 and the allowance 50, and the
/// stale anchor, last reset, kind and proxy address are removed.
Method TestDefaults()
{
	Do ..Use({"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw"})
	For key = "resetAnchor", "lastReset", "lastResetKind", "proxyAddress" {
		Do $ClassMethod(..#ACCESSOR, "Set", key, "stale")
	}
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "resetIntervalHours"), 4, "the interval is 4")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "connectionCap"), 8, "the connection cap is 8")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "connectionReserve"), 2, "the reserve is 2")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "messageAllowance"), 50, "the allowance is 50")
	For key = "resetAnchor", "lastReset", "lastResetKind", "proxyAddress" {
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key), "", key_" is removed")
	}
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), 20, "the daily cap row is the default 20")
}

/// Matrix row 3: each bad value, one at a time, refuses the step with an error that names the variable and not the value. Every public key
/// and the three rows are as they were, and readiness is "".
Method TestBadStartValues()
{
	Set cases = ""
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_RESET_INTERVAL_HOURS", "0"), $ListBuild("OCUTALON_RESET_INTERVAL_HOURS", "x"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_CONNECTION_CAP", "0"), $ListBuild("OCUTALON_CONNECTION_CAP", "1.5"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_CONNECTION_RESERVE", "-1"), $ListBuild("OCUTALON_CONNECTION_RESERVE", "8"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_MESSAGE_ALLOWANCE", "0"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_RESET_ANCHOR", "2026-10-25 00:00"), $ListBuild("OCUTALON_RESET_ANCHOR", "2026-02-30T00:00:00Z"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_LAST_RESET", "2026-10-25T00:00:00+01:00"), $ListBuild("OCUTALON_LAST_RESET", "2026-10-25T25:00:00Z"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_LAST_RESET_KIND", "manual"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_DAILY_COST_CAP_USD", "-1"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_GATEWAY_SPEND_USD", "x"))
	Set cases = cases _ $ListBuild($ListBuild("OCUTALON_GATEWAY_SPEND_DATE", "2026-13-01"))
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, key) {
		Do $ClassMethod(..#ACCESSOR, "Set", key, "stale-"_key)
	}
	Do ..PutRows(9, 4, "2001-02-03")
	Set keysBefore = ..KeyState()
	Set rowsBefore = ..RowState()
	Set position = 0
	While $ListNext(cases, position, case) {
		Set variable = $List(case, 1)
		Set bad = $List(case, 2)
		Do ..Use({"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw"})
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, bad)
		Do $ClassMethod(..#ACCESSOR, "SetReady")
		Set sc = $ClassMethod(..#STEP, "Run")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Set label = variable_" '"_bad_"'"
		Do $$$AssertStatusNotOK(sc, "Run is refused for "_label)
		Do $$$AssertTrue(text [ variable, "and the error names the variable: "_text)
		If $Length(bad) > 3 Do $$$AssertNotTrue(text [ bad, "and not the value")
		Do $$$AssertEquals(..KeyState(), keysBefore, "every public key is as it was for "_label)
		Do $$$AssertEquals(..RowState(), rowsBefore, "and the three rows for "_label)
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), "", "readiness is cleared for "_label)
	}
}

/// Matrix row 4: with the flag unset and every other variable set, only onlineDemo changes (to 0) among the public keys, and readiness is
/// cleared. No gateway row is written. The cap row is 0 when it was absent, and an existing 7 is kept.
Method TestFlagOffWritesOnlyTheFlag()
{
	Do ..Use({"OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw", "OCUTALON_RESET_INTERVAL_HOURS": "6", "OCUTALON_RESET_ANCHOR": "2026-10-25T00:00:00Z", "OCUTALON_LAST_RESET": "2026-10-25T06:00:00Z", "OCUTALON_LAST_RESET_KIND": "unscheduled", "OCUTALON_PROXY_ADDRESS": "10.9.8.7", "OCUTALON_CONNECTION_CAP": "5", "OCUTALON_CONNECTION_RESERVE": "1", "OCUTALON_MESSAGE_ALLOWANCE": "30", "OCUTALON_DAILY_COST_CAP_USD": "12.5", "OCUTALON_GATEWAY_SPEND_USD": "3.2", "OCUTALON_GATEWAY_SPEND_DATE": "2026-10-25"})
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, key) {
		Do $ClassMethod(..#ACCESSOR, "Set", key, "stale-"_key)
	}
	Do $ClassMethod(..#ACCESSOR, "SetReady")
	Set before = ..KeyState()
	For setting = "DailyCostCapUSD", "GatewaySpendUSD", "GatewaySpendDate" {
		Do ..DeleteRow(setting)
	}
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK")
	Set after = ..KeyState()
	Set position = 0
	While $ListNext(keys, position, key) {
		If key = "onlineDemo" {
			Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key), 0, "onlineDemo is 0")
		} Else {
			Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", key), "stale-"_key, key_" is as it was")
		}
	}
	Do $$$AssertNotEquals(after, before, "the flag changed")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), "", "readiness is cleared")
	Do $$$AssertEquals(..Row("GatewaySpendUSD"), "<none>", "no gateway spend row")
	Do $$$AssertEquals(..Row("GatewaySpendDate"), "<none>", "and no gateway date row")
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), 0, "the cap row is the seed 0 when there was none")
	Do ..PutRows(7, "", "")
	Do ..DeleteRow("GatewaySpendUSD")
	Do ..DeleteRow("GatewaySpendDate")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK again")
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), 7, "an existing cap row of 7 is kept")
	Do $$$AssertEquals(..Row("GatewaySpendUSD"), "<none>", "and still no gateway row")
}

/// The flag is exactly 1: a near miss (01, 1.0, true, 0, 1 with a space, or empty) is a local install, which changes onlineDemo to 0 and
/// writes no other public key.
Method TestOnlyOneIsOn()
{
	For value = "01", "1.0", "true", "0", " 1", "" {
		Do ..Use({"OCUTALON_ONLINE_DEMO": (value), "OCUTALON_DEMO_USER": "Zz-demo"})
		Do $ClassMethod(..#ACCESSOR, "Set", "onlineDemo", 1)
		Do $ClassMethod(..#ACCESSOR, "Set", "demoUser", "stale")
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK for the flag '"_value_"'")
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "onlineDemo"), 0, "the flag '"_value_"' is a local install")
		Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "demoUser"), "stale", "and writes no other key for '"_value_"'")
	}
}

/// A start variable that is set but empty counts as unset: the defaults are written, and the gateway rows are written empty.
Method TestEmptyCountsAsUnset()
{
	Do ..Use({"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw", "OCUTALON_RESET_INTERVAL_HOURS": "", "OCUTALON_CONNECTION_CAP": "", "OCUTALON_CONNECTION_RESERVE": "", "OCUTALON_MESSAGE_ALLOWANCE": "", "OCUTALON_DAILY_COST_CAP_USD": "", "OCUTALON_GATEWAY_SPEND_USD": "", "OCUTALON_GATEWAY_SPEND_DATE": ""})
	Do ..PutRows(9, 4, "2001-02-03")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with empty variables")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "resetIntervalHours"), 4, "the interval is the default 4")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "connectionCap"), 8, "the connection cap is the default 8")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "connectionReserve"), 2, "the reserve is the default 2")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "messageAllowance"), 50, "the allowance is the default 50")
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), 20, "the cap row is the default 20")
	Do $$$AssertEquals(..Row("GatewaySpendUSD"), "", "the spend row is empty")
	Do $$$AssertEquals(..Row("GatewaySpendDate"), "", "and so is the date row")
}

/// With the flag off, a cap row of a wider specificity (the item *) is a row that resolves, so the seed is not written at the exact one.
Method TestFlagOffKeepsARowOfAnotherSpecificity()
{
	Set id = ..#PRODUCTION_"||*||*||DailyCostCapUSD"
	Do $$$AssertNotTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "no wider cap row exists before the test")
	Do ..DeleteRow("DailyCostCapUSD")
	Set ..WideRow = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(..#PRODUCTION, "*", "DailyCostCapUSD", 7, "Written by a test; the test deletes it."), "the wider cap row is 7")
	Do ..Use({})
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with the flag off")
	Do $$$AssertEquals(..Row("DailyCostCapUSD"), "<none>", "no cap row is written at the exact specificity")
	Do $$$AssertEquals(..Read("DailyCostCapUSD"), 7, "and the wider row still decides")
}

/// Matrix row 5: the cap row is 20 when the variable is unset, then 0, then 12.5, and the bridge's accessor reads it. The spend and its
/// date are written as given, and with no gateway variable both rows are rewritten empty over rows that held 9 and a date.
Method TestBudgetRows()
{
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Set base = {"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": "Zz-demo", "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw", "OCUTALON_READONLY_USER": "Zz-ro", "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw"}
	Do ..Use(base)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with the cap unset")
	Do $$$AssertEquals(..Read("DailyCostCapUSD"), 20, "the cap is 20, read through the bridge's accessor")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_DAILY_COST_CAP_USD", "0")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with the cap 0")
	Do $$$AssertEquals(..Read("DailyCostCapUSD"), 0, "the cap is 0, which means off")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_DAILY_COST_CAP_USD", "12.5")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_GATEWAY_SPEND_USD", "3.2")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_GATEWAY_SPEND_DATE", today)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with the cap and the spend")
	Do $$$AssertEquals(..Read("DailyCostCapUSD"), 12.5, "the cap is 12.5")
	Do $$$AssertEquals(..Read("GatewaySpendUSD"), 3.2, "the spend is 3.2")
	Do $$$AssertEquals(..Read("GatewaySpendDate"), today, "and its date is today")
	Do ..PutRows(9, 4, "2001-02-03")
	Do ..Use(base)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run is OK with no gateway variable")
	Do $$$AssertEquals(..Row("GatewaySpendUSD"), "", "the spend row is rewritten empty")
	Do $$$AssertEquals(..Row("GatewaySpendDate"), "", "and so is the date row")
}

/// Matrix row 6: with the start variables of the fixture accounts, Public.Run and then Users.Accounts leave both accounts with their published
/// passwords and the guard set, and a sign-in request with the old and a new password is refused for each account, whose password stays.
Method TestStartValuesReachTheUsersStep()
{
	Do ..Use({"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": (..Demo), "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw-1", "OCUTALON_READONLY_USER": (..Ro), "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw-1"})
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Public.Run is OK")
	Do $$$AssertStatusOK($ClassMethod("OcuTalon.Install.Step.Users", "Accounts", ..Readme), "Users.Accounts is OK")
	Do $$$AssertEquals($ClassMethod(..#GUARD, "Setting"), "Check^OcuTalonPasswordGuard", "the guard is set")
	Set accounts = $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1"), $ListBuild(..Ro, "Zz-ro-pw-1"))
	Set position = 0
	While $ListNext(accounts, position, account) {
		Set name = $List(account, 1)
		Set password = $List(account, 2)
		Do $$$AssertTrue($ClassMethod(..#GUARD, "PasswordOk", name, password), name_" holds its published password")
		Set status = $ClassMethod(..#GUARD, "SignInChange", name, password, "Zz-other-pw-9")
		Do $$$AssertTrue(status > 0, name_": the sign-in request is answered, status "_status)
		Do $$$AssertTrue($ClassMethod(..#GUARD, "PasswordOk", name, password), name_": the sign-in change is refused, and the password stays")
		Do $$$AssertNotTrue($ClassMethod(..#GUARD, "PasswordOk", name, "Zz-other-pw-9"), name_" does not have the new password")
	}
}

/// Matrix row 7: with the flag on and the cap unset (20), a control with the gateway's spend 0 today reaches the mock once. With the spend 20
/// today, Budget.State is cap 20 and capped, the decide is answered with a tellnow fallback with the reason daily_cap (answer, XML and row),
/// no request with its reference reaches the mock, and the probe sink gets budget.capped once.
Method TestDecisionAtTheCap()
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Kill ^OcuTalonBP.UsageCapped(today)
	Set ..Pointed = 1
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PointKeys"), "the entries of the runners are pointed at the CI mock key variable")
	Kill ^OcuTalonTest("ProbeSink")
	Set ^OcuTalonTest("ProbeSink", "shared") = 1
	Set sc = $ClassMethod(..#FIXTURE, "UseItemSetting", "Decide", "Host", "HostSinkClass", "OcuTalon.Test.Bridge.ProbeSink", .saved)
	If $IsObject(saved) Set ..SinkSaved = saved
	Do $$$AssertStatusOK(sc, "Decide's host sink is the probe sink, in its shared mode")
	Set base = {"OCUTALON_ONLINE_DEMO": "1", "OCUTALON_DEMO_USER": (..Demo), "OCUTALON_DEMO_PASSWORD": "Zz-demo-pw-1", "OCUTALON_READONLY_USER": (..Ro), "OCUTALON_READONLY_PASSWORD": "Zz-ro-pw-1", "OCUTALON_GATEWAY_SPEND_USD": "0", "OCUTALON_GATEWAY_SPEND_DATE": (today)}

	// the control: the gateway has spent nothing today
	Do ..Use(base)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Public.Run is OK with the spend 0")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(state.cap_"|"_state.capped, "20|0", "Budget.State is cap 20 and not capped")
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "decide", "untrusted", "Triage this item.", .control)
	Set ..ItemIds = ..ItemIds _ $ListBuild(control)
	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "the control decide is answered")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FindRequests", entries, control).%Size(), 1, "the control decide reached the mock once")

	// at the cap: the gateway has spent the whole cap today
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_GATEWAY_SPEND_USD", "20")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Public.Run is OK with the spend 20")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(state.cap_"|"_state.capped, "20|1", "Budget.State is cap 20 and capped")
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "decide", "untrusted", "Triage this item.", .capped)
	Set ..ItemIds = ..ItemIds _ $ListBuild(capped)
	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "the decide at the cap is answered")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", capped, "decide")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FallbackProblems", answer, row, "decide", "daily_cap"), "", "with a tellnow fallback with the reason daily_cap, in the answer, its XML and the row")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Drain", "TriageAgent"), "TriageAgent answered a request of its own, so it had handled everything sent to it")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read again")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FindRequests", entries, capped).%Size(), 0, "no request with its reference reached the mock")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "SinkCalls", "budget.capped").%Size(), 1, "the probe sink got budget.capped once")
}

/// Matrix row 8 (DW-160): with the flag on, Ready pins both public accounts' page size to 100 in OCUTALON and OCUORDERS and then sets
/// readiness. With the flag 0 it pins no name. A name that cannot be pinned (a subscript that is too long) fails Ready, and readiness
/// stays cleared.
Method TestReadyPinsThePublicAccounts()
{
	Set pinned = $Parameter("OcuTalon.Install.Step.Users", "TRACEPAGESIZE")
	Do $$$AssertTrue(##class(%SYS.Namespace).Exists("OCUORDERS"), "OCUORDERS exists on the stack")
	Do $ClassMethod(..#ACCESSOR, "Set", "onlineDemo", 1)
	Do $ClassMethod(..#ACCESSOR, "Set", "demoUser", ..Demo)
	Do $ClassMethod(..#ACCESSOR, "Set", "readonlyUser", ..Ro)
	Do ..ClearPins()
	Do $ClassMethod(..#ACCESSOR, "ClearReady")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Ready"), "Ready is OK with the flag on")
	For name = ..Demo, ..Ro {
		For namespace = "OCUTALON", "OCUORDERS" {
			Do $$$AssertEquals($Get(^|namespace|EnsPortal.Settings(name, "VisualTrace", "ItemsPerPage")), pinned, name_" is pinned to "_pinned_" in "_namespace)
		}
	}
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), 1, "and readiness is 1")

	Do ..ClearPins()
	Do $ClassMethod(..#ACCESSOR, "Set", "onlineDemo", 0)
	Do $ClassMethod(..#ACCESSOR, "Set", "demoUser", "ZzPublic"_..Number_"Other1")
	Do $ClassMethod(..#ACCESSOR, "Set", "readonlyUser", "ZzPublic"_..Number_"Other2")
	Do $ClassMethod(..#ACCESSOR, "ClearReady")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Ready"), "Ready is OK with the flag 0")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), 1, "readiness is 1")
	For name = "ZzPublic"_..Number_"Other1", "ZzPublic"_..Number_"Other2" {
		For namespace = "OCUTALON", "OCUORDERS" {
			Do $$$AssertEquals($Data(^|namespace|EnsPortal.Settings(name)), 0, "no page size is pinned for "_name_" in "_namespace)
		}
	}

	Do $ClassMethod(..#ACCESSOR, "Set", "onlineDemo", 1)
	Do $ClassMethod(..#ACCESSOR, "Set", "demoUser", $Translate($Justify("", 600), " ", "x"))
	Do $ClassMethod(..#ACCESSOR, "ClearReady")
	Do $$$AssertStatusNotOK($ClassMethod(..#STEP, "Ready"), "Ready fails when a name cannot be pinned")
	Do $$$AssertEquals($ClassMethod(..#ACCESSOR, "Get", "ready"), "", "and readiness stays cleared")
}

/// --- helpers ---
/// The 16 start variables: the flag and the variables of the step.
ClassMethod Variables() As %List [ Private ]
{
	Set list = $ListBuild($Parameter(..#STEP, "FLAG"))
	Set pairs = $ListFromString($Parameter(..#STEP, "VARIABLES"))
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set list = list _ $ListBuild($Piece(pair, "=", 1))
	}
	Quit list
}

/// Sets exactly the variables of the object in the process (a variable that it does not name is removed), and checks that the process sees them.
Method Use(values As %DynamicObject) [ Private ]
{
	Set list = ..Variables()
	Set position = 0
	While $ListNext(list, position, variable) {
		If values.%IsDefined(variable) {
			Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, values.%Get(variable))
			Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), values.%Get(variable), variable_" is set in the process")
		} Else {
			Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
		}
	}
}

/// The 13 public keys as one text.
ClassMethod KeyState() As %String [ Private ]
{
	Set text = ""
	Set keys = $ListFromString($Parameter(..#ACCESSOR, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, key) {
		Set text = text _ key _ "=" _ $ClassMethod(..#ACCESSOR, "Get", key) _ $Char(10)
	}
	Quit text
}

/// The three rows as one text.
ClassMethod RowState() As %String [ Private ]
{
	Set text = ""
	Set settings = $ListFromString(..#SETTINGS)
	Set position = 0
	While $ListNext(settings, position, setting) {
		Set text = text _ setting _ "=" _ ..Row(setting) _ $Char(10)
	}
	Quit text
}

/// The value of the System Default Settings row of the setting of Decide in OcuTalon.Production, or "<none>".
ClassMethod Row(setting As %String) As %String [ Private ]
{
	Set id = ..#PRODUCTION_"||Decide||*||"_setting
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit "<none>"
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// What the bridge's accessor reads for the setting of Decide.
ClassMethod Read(setting As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting, ..#PRODUCTION, "Decide", .sc)
}

/// Writes the three rows (the cap, the spend and its date) as a test would find them.
Method PutRows(cap As %String, spend As %String, date As %String) [ Private ]
{
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", "Decide", "DailyCostCapUSD", cap), "the cap row is "_cap)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", "Decide", "GatewaySpendUSD", spend), "the spend row is '"_spend_"'")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", "Decide", "GatewaySpendDate", date), "the date row is '"_date_"'")
}

/// Deletes the row of the setting of Decide.
ClassMethod DeleteRow(setting As %String) [ Private ]
{
	Do $ClassMethod(..#FIXTURE, "RestoreDefault", $ListBuild("Decide", setting, 0))
}

/// Kills the page size settings of the fixture names in OCUTALON and OCUORDERS.
ClassMethod ClearPins() [ Private ]
{
	For namespace = "OCUTALON", "OCUORDERS" {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Set name = "ZzPublic"
		For {
			Set name = $Order(^|namespace|EnsPortal.Settings(name))
			If $Extract(name, 1, 8) '= "ZzPublic" Quit
			Kill ^|namespace|EnsPortal.Settings(name)
		}
	}
}

/// Removes the fixture accounts of this run and their page size settings.
Method ClearAccounts() [ Private ]
{
	Do ..Remove(..Demo)
	Do ..Remove(..Ro)
	Do ..Remove(..Readme)
	Do ..ClearPins()
}

/// Deletes every fixture user that an earlier run may have left, and their page size settings.
ClassMethod Clean() [ Private ]
{
	Do ..ClearPins()
	New $Namespace
	Set $Namespace = "%SYS"
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM Security.Users WHERE Name %STARTSWITH 'ZzPublic'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

ClassMethod Remove(user As %String) [ Private ]
{
	If user = "" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
}

}
