/// The refusal contract of the bridge's settings API (Story 33.1 pinned the stubs; Story 17.4 built them; AD-18, AD-19). The class keeps its name so that its
/// references and the shard's class list stand. A call that is refused (a placeholder, a name or value off the allow-list, an unknown model or agent, a zone that
/// no file backs) returns an error, leaves an Output argument empty and writes nothing. Providers, CheckModel and SetModel are tested in Test.Bridge.Providers and
/// Test.Bridge.ModelChange, and the built behaviour in Test.Bridge.SettingsValues and Test.Bridge.SettingsApply.
///   - TestSettingsRefused: Check, Set, SetPrice and TestRequest each refuse their calls, with old and request empty;
///   - TestNothingWritten: the refused calls, SetModel calls that CheckModel refuses included, leave the System Default Settings rows, the Config Store entries (the
///     retry entries included, absent or present) and the Price rows (by value) as they were, and no row named InstanceZone or RetryItem exists after them;
///   - TestTimeRefused: a refused SetZone answers an error and writes nothing, Zone is still empty, and after Apply the conversions give what they gave before
///     the calls, under the process zone that the test sets (the base puts the zone back).
Class OcuTalon.Test.Bridge.SettingsStubs Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Method TestSettingsRefused()
{
	Set class = ..#SETTINGS
	Do $$$AssertTrue($$$ISERR($ClassMethod(class, "Check", "DailyCostCapUSD", "@{env:X}")), "Check refuses a placeholder")
	Do $$$AssertTrue($$$ISERR($ClassMethod(class, "Check", "TimerSeconds", "60")), "and a name off the allow-list")
	Set old = "x"
	Set sc = $ClassMethod(class, "Set", "DailyCostCapUSD", "-5", .old)
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorCodes(sc) '= 5003), "Set refuses a negative cap, and the answer is no stub's")
	Do $$$AssertEquals(old, "", "and old is empty")
	Set old = "x"
	Set sc = $ClassMethod(class, "SetPrice", "no-such-model", {"input": 1}, .old)
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorCodes(sc) '= 5003), "SetPrice refuses an unknown model")
	Do $$$AssertTrue($IsObject(old) && (old.%ToJSON() = "{}"), "and old is an empty object")
	Set request = "x"
	Set sc = $ClassMethod(class, "TestRequest", "Chat", .request)
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorCodes(sc) '= 5003), "TestRequest refuses an agent that is not a first runner item")
	Do $$$AssertEquals(request, "", "and request is empty")
	Set values = $ClassMethod(class, "Values")
	Do $$$AssertTrue($IsObject(values) && values.%IsDefined("DecisionTokenBudget") && values.%IsDefined("agents"), "Values holds the values and the agents")
}

Method TestNothingWritten()
{
	Set before = ..State()
	Do ..CallEverything()
	Do $$$AssertEquals(..State(), before, "the System Default Settings, the Config Store entries and the Price rows are as they were")
	Do $$$AssertEquals(..Rows("InstanceZone"), 0, "no System Default Settings row named InstanceZone exists")
	Do $$$AssertEquals(..Rows("RetryItem"), 0, "no System Default Settings row named RetryItem exists")
}

Method TestTimeRefused()
{
	Set time = "OcuTalon.Bridge.Time"
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set utc = "2025-07-01T12:00:00Z"
	Set before = $ClassMethod(time, "ToLocal", utc)
	Do $$$AssertEquals(before, "2025-07-01T08:00:00", "control: the process zone is New York's")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "", "Zone is empty")
	Set sc = $ClassMethod(time, "SetZone", "Mars/Olympus")
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorCodes(sc) '= 5003), "SetZone refuses a zone that no file backs")
	Do $$$AssertTrue($$$ISERR($ClassMethod(time, "SetZone", "@{env:X}")), "and a placeholder")
	Do $ClassMethod(time, "Apply")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", utc), before, "ToLocal gives the same local time after the calls")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(utc), before, "and so does Data.Time")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "", "Zone is still empty")
	Do $$$AssertEquals(..Rows("InstanceZone"), 0, "and no row was written")
}

/// Calls every method of the settings API and the zone writer once with arguments that are refused: a placeholder, a name off the allow-list, a value off the
/// bounds, an unknown model or agent, a zone that no file backs. SetModel gets arguments that CheckModel refuses (an agent outside the three, an unsupported
/// provider, a placeholder).
Method CallEverything() [ Private ]
{
	Set class = ..#SETTINGS
	Do $ClassMethod(class, "Providers")
	Do $ClassMethod(class, "Values")
	Do $ClassMethod(class, "Check", "InstanceZone", "Mars/Olympus")
	Do $ClassMethod(class, "Set", "InstanceZone", "Mars/Olympus", .old)
	Do $ClassMethod(class, "Set", "InstanceZone", "@{env:X}", .old)
	Do $ClassMethod(class, "Set", "DailyCostCapUSD", "@{env:X}", .old)
	Do $ClassMethod(class, "Set", "DailyCostCapUSD", "10000.01", .old)
	Do $ClassMethod(class, "Set", "DecisionTokenBudget", "100001", .old)
	Do $ClassMethod(class, "Set", "TimerSeconds", "60", .old)
	Do $ClassMethod(class, "CheckModel", "Chat", "anthropic", "claude-haiku-5-5", 1)
	Do $ClassMethod(class, "SetModel", "Chat", "anthropic", "claude-haiku-5-5", 1, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgent", "openai", "gpt-5.4", 1, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgent", "anthropic", "@{env:ZZ}", 0, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgentRetry", "anthropic", "claude-haiku-5-5", 1, .old)
	Do $ClassMethod(class, "SetPrice", "no-such-model", {"input": 1}, .old)
	Do $ClassMethod(class, "SetPrice", "claude-haiku-5-5", {"input": -1}, .old)
	Do $ClassMethod(class, "SetPrice", "claude-haiku-5-5", {}, .old)
	Do $ClassMethod(class, "TestRequest", "Chat", .request)
	Do $ClassMethod(class, "TestAnswer", "", 12)
	Do $ClassMethod("OcuTalon.Bridge.Time", "SetZone", "Mars/Olympus")
	Do $ClassMethod("OcuTalon.Bridge.Time", "Apply")
}

/// The rows that the calls could change, as one text: the System Default Settings rows of the production, the Config Store entries of the runners
/// and the Price rows.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SettingValue FROM Ens_Config.DefaultSettings ORDER BY ID")
	While result.%Next() {
		Set state = state _ $Char(10) _ result.%GetData(1) _ "=" _ result.%GetData(2)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID, Model, InputPerMTok, OutputPerMTok, CacheReadPerMTok, CacheWritePerMTok, LongThresholdTokens, LongInputPerMTok, LongOutputPerMTok FROM OcuTalon_Bridge_Data.Price ORDER BY %ID")
	While result.%Next() {
		Set row = ""
		For column = 1:1:9 Set row = row _ "," _ result.%GetData(column)
		Set state = state _ $Char(10) _ "price" _ row
	}
	For name = "OcuTalonTriage", "OcuTalonDiagnosis", "OcuTalonChat", "OcuTalonTriageRetry", "OcuTalonDiagnosisRetry", "OcuTalonChatRetry" {
		Set found = ##class(%ConfigStore.Configuration).Exists("AI.LLM."_name)
		Set state = state _ $Char(10) _ name _ " " _ $Select(found && $$$ISOK(##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_name, .details, 0, 0)): details.%ToJSON(), 1: "absent")
	}
	Quit state
}

/// The number of System Default Settings rows for the setting.
ClassMethod Rows(setting As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.DefaultSettings WHERE SettingName = ?", setting)
	Do result.%Next()
	Quit result.%GetData(1)
}

}
