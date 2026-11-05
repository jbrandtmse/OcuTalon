/// The stubs of the bridge's settings API (Story 33.1; AD-18, AD-19). Until Story 17.4 builds them, the OcuTalon.Bridge.Settings methods that Story 17.3 does
/// not build (Check, Set, SetPrice, TestRequest, TestAnswer and Values) are stubs: every one that returns a %Status answers "not implemented" (code 5003)
/// and writes nothing, Values and TestAnswer are empty objects, and an Output argument comes back empty; OcuTalon.Bridge.Time.Zone is "", SetZone answers
/// 5003 and Apply does nothing. Providers, CheckModel and SetModel are built (Test.Bridge.Providers, Test.Bridge.ModelChange).
///   - TestSettingsStubs: each remaining stub gives its stub answer, with old and request empty;
///   - TestNothingWritten: the calls, SetModel calls that CheckModel refuses included, leave the System Default Settings rows, the Config Store entries (the
///     retry entries included, absent or present) and the Price rows (by value) as they were, and no row named InstanceZone or RetryItem exists after them;
///   - TestTimeStubs: Zone is "", SetZone answers 5003, and after Apply the conversions give what they gave before the calls, under the process
///     zone that the test sets (the base puts the zone back).
Class OcuTalon.Test.Bridge.SettingsStubs Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Method TestSettingsStubs()
{
	Set class = ..#SETTINGS
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes($ClassMethod(class, "Check", "DailyCostCapUSD", "5")), 5003, "Check answers 5003")
	Set old = "x"
	Set sc = $ClassMethod(class, "Set", "DailyCostCapUSD", "5", .old)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "Set answers 5003")
	Do $$$AssertEquals(old, "", "and old is empty")
	Set old = "x"
	Set sc = $ClassMethod(class, "SetPrice", "claude-haiku-5-5", {"input": 1}, .old)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "SetPrice answers 5003")
	Do $$$AssertTrue($IsObject(old) && (old.%ToJSON() = "{}"), "and old is an empty object")
	Set request = "x"
	Set sc = $ClassMethod(class, "TestRequest", "Chat", .request)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "TestRequest answers 5003")
	Do $$$AssertEquals(request, "", "and request is empty")
	Set values = $ClassMethod(class, "Values")
	Do $$$AssertTrue($IsObject(values) && (values.%ToJSON() = "{}"), "Values is an empty object")
	Set answer = $ClassMethod(class, "TestAnswer", "", 12)
	Do $$$AssertTrue($IsObject(answer) && (answer.%ToJSON() = "{}"), "TestAnswer is an empty object")
}

Method TestNothingWritten()
{
	Set before = ..State()
	Do ..CallEverything()
	Do $$$AssertEquals(..State(), before, "the System Default Settings, the Config Store entries and the Price rows are as they were")
	Do $$$AssertEquals(..Rows("InstanceZone"), 0, "no System Default Settings row named InstanceZone exists")
	Do $$$AssertEquals(..Rows("RetryItem"), 0, "no System Default Settings row named RetryItem exists")
}

Method TestTimeStubs()
{
	Set time = "OcuTalon.Bridge.Time"
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set utc = "2025-07-01T12:00:00Z"
	Set before = $ClassMethod(time, "ToLocal", utc)
	Do $$$AssertEquals(before, "2025-07-01T08:00:00", "control: the process zone is New York's")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "", "Zone is empty")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes($ClassMethod(time, "SetZone", "Europe/Berlin")), 5003, "SetZone answers 5003")
	Do $ClassMethod(time, "Apply")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", utc), before, "ToLocal gives the same local time after the calls")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(utc), before, "and so does Data.Time")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "", "Zone is still empty")
}

/// Calls every method of the settings API and the zone writer once, SetModel with arguments that CheckModel refuses (an agent outside the three, an
/// unsupported provider, a placeholder) included.
Method CallEverything() [ Private ]
{
	Set class = ..#SETTINGS
	Do $ClassMethod(class, "Providers")
	Do $ClassMethod(class, "Values")
	Do $ClassMethod(class, "Check", "InstanceZone", "Europe/Berlin")
	Do $ClassMethod(class, "Set", "InstanceZone", "Europe/Berlin", .old)
	Do $ClassMethod(class, "Set", "DailyCostCapUSD", "5", .old)
	Do $ClassMethod(class, "CheckModel", "Chat", "anthropic", "claude-haiku-5-5", 1)
	Do $ClassMethod(class, "SetModel", "Chat", "anthropic", "claude-haiku-5-5", 1, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgent", "openai", "gpt-5.4", 1, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgent", "anthropic", "@{env:ZZ}", 0, .old)
	Do $ClassMethod(class, "SetModel", "ChatAgentRetry", "anthropic", "claude-haiku-5-5", 1, .old)
	Do $ClassMethod(class, "SetPrice", "claude-haiku-5-5", {"input": 1}, .old)
	Do $ClassMethod(class, "TestRequest", "Chat", .request)
	Do $ClassMethod(class, "TestAnswer", "", 12)
	Do $ClassMethod("OcuTalon.Bridge.Time", "SetZone", "Europe/Berlin")
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
