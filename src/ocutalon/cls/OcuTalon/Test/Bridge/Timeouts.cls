/// Tests of the timeout API of the bridge (Story 1.7; AD-5, AD-8, AD-19): Derive and Check are pure, and Apply is tested for its refusals,
/// which change nothing. The run-time change itself (the row, the entries, the restarts and the next decision) is Test.Agent.Decide.TestApplyTimer,
/// which needs the live production. The refusals that name a runner need OcuTalon.Production to run (the throwaway stacks and CI), and
/// fail with the reason where it does not.
///   - TestDerive: for 60, 12, 13, 59 and 110 the exact JSON (60 gives 55000 and 25); for every timer from 12 to 110 the four keys of the
///     retry block with attempt_timeout_secs equal to request_timeout_secs, the numbers as numbers, and a worst case of one Chat request,
///     (max_retries + 1) x attempt + max_retries x the back-off cap, of at most the timer minus 8 seconds (52 for 60);
///   - TestRefused: 11, 111, 0, -1, "", "x", "60.5", " 60" and "6e1" give {} from Derive and an error from Check that names TimerSeconds and
///     "12 to 110", with the value cut to 40 characters and redacted; Decide.CheckSettings refuses each and accepts 12 and 110; a string of
///     1,000 digits is refused too, and nothing throws;
///   - TestApplyRefuses: Apply of a timer outside 12 to 110 or not a whole number, of a production whose runner has no @{config:} entry
///     (OcuTalon.BridgeExample.Production) and of a production one of whose runners names an entry that does not exist, is an error that
///     names TimerSeconds or the runner, and changes nothing: not the System Default Settings row of TimerSeconds, not an entry, not a job;
///   - TestApplyDefinedTimer: for a production whose definition sets the TimerSeconds of Decide (OcuTalon.Test.Bridge.ZzTimerProduction), Apply
///     writes the System Default Settings row, finds that the setting does not take it, puts the row back (deleted when there was none, as it
///     was when there was one) and fails naming TimerSeconds, with no entry changed.
/// Added by the QA stage of Story 1.7 (AD-5, AD-19):
///   - TestApplyStopped: Apply to a production that does not run (OcuTalon.Test.Bridge.ZzStoppedProduction, whose TriageAgent names an entry of
///     its own) writes the production's TimerSeconds row and merges the block into the entry, keeps the entry's other fields, restarts nothing and
///     leaves the running production as it was: its row, its entries and its jobs;
///   - TestRestartError: Restart of an item that the production cannot stop (Ens.Alarm, which the production adds itself and its definition does
///     not list) is an error that names the item, and the item is not left stopped.
/// Every row that a test puts is put back by OnAfterOneTest, and so are the definition of the test production that a test loaded and the
/// Config Store entry that a test created.
Class OcuTalon.Test.Bridge.Timeouts Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The class under test.
Parameter TIMEOUTS = "OcuTalon.Bridge.Timeouts";

/// The production whose definition sets the timer of Decide.
Parameter ZZPRODUCTION = "OcuTalon.Test.Bridge.ZzTimerProduction";

/// The production that is not started, whose TriageAgent names the Config Store entry ZZENTRY and whose Decide sets no timer.
Parameter ZZSTOPPED = "OcuTalon.Test.Bridge.ZzStoppedProduction";

/// The name of the Config Store entry (AI.LLM) that a test creates for the TriageAgent of ZZSTOPPED and of ZZPRODUCTION (CreateEntry).
Parameter ZZENTRY = "OcuTalonZzStopped";

/// The System Default Settings rows before the test touched them (Test.Agent.RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

/// The name of the test production whose definition the test loaded, to be deleted again, or "".
Property Loaded As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#ZZPRODUCTION_"||Decide||*||TimerSeconds")
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#ZZSTOPPED_"||Decide||*||TimerSeconds")
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_..#ZZENTRY) Do ##class(%ConfigStore.Configuration).Delete("AI.LLM."_..#ZZENTRY)
	If ..Loaded '= "" {
		Do ##class(Ens.Config.Production).%DeleteId(..Loaded)
		Set ..Loaded = ""
	}
	Quit $$$OK
}

/// Derive gives exactly {"timeout_ms", "http_config": {"request_timeout_secs", "retry": {...}}}: the timer minus 5 seconds in milliseconds, and
/// (timer - 10) \ 2 seconds for the request and for each attempt, with one retry, a first back-off of 500 ms and a cap of 2000 ms.
Method TestDerive()
{
	Set timeouts = ..#TIMEOUTS
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 60).%ToJSON(), ..Expected(55000, 25), "60 gives timeout_ms 55000 and a request timeout of 25")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 12).%ToJSON(), ..Expected(7000, 1), "12 gives 7000 and 1")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 13).%ToJSON(), ..Expected(8000, 1), "13 gives 8000 and 1")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 59).%ToJSON(), ..Expected(54000, 24), "59 gives 54000 and 24")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 110).%ToJSON(), ..Expected(105000, 50), "110 gives 105000 and 50")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", "60").%ToJSON(), ..Expected(55000, 25), "a timer given as text gives the same as the number")
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", "060").%ToJSON(), ..Expected(55000, 25), "and so does one with a leading zero, which is still a whole number of digits")

	Set derived = $ClassMethod(timeouts, "Derive", 60)
	Set retry = derived."http_config".retry
	Do $$$AssertEquals((retry."max_retries" + 1) * retry."attempt_timeout_secs" + (retry."max_retries" * (retry."max_backoff_ms" \ 1000)), 52, "the worst case of one Chat request under 60 is 52 seconds")
	Do $$$AssertEquals(derived.%GetTypeOf("timeout_ms")_"|"_derived."http_config".%GetTypeOf("request_timeout_secs")_"|"_retry.%GetTypeOf("max_retries")_"|"_retry.%GetTypeOf("attempt_timeout_secs")_"|"_retry.%GetTypeOf("initial_backoff_ms")_"|"_retry.%GetTypeOf("max_backoff_ms"), "number|number|number|number|number|number", "every value is a number")
	Do derived."http_config".%Set("request_timeout_secs", 1)
	Do $$$AssertEquals($ClassMethod(timeouts, "Derive", 60).%ToJSON(), ..Expected(55000, 25), "Derive is pure: changing a result changes nothing for the next call")

	Set bad = ""
	For timer = 12:1:110 {
		Set derived = $ClassMethod(timeouts, "Derive", timer)
		Set attempt = (timer - 10) \ 2
		Set block = derived."http_config"
		Set retry = block.retry
		Set worst = (retry."max_retries" + 1) * retry."attempt_timeout_secs" + (retry."max_retries" * (retry."max_backoff_ms" \ 1000))
		If derived.%Size() '= 2 Set bad = bad _ $ListBuild(timer_": top-level keys")
		If derived."timeout_ms" '= ((timer - 5) * 1000) Set bad = bad _ $ListBuild(timer_": timeout_ms")
		If block."request_timeout_secs" '= attempt Set bad = bad _ $ListBuild(timer_": request_timeout_secs")
		If retry.%Size() '= 4 Set bad = bad _ $ListBuild(timer_": retry keys")
		If retry."attempt_timeout_secs" '= block."request_timeout_secs" Set bad = bad _ $ListBuild(timer_": attempt_timeout_secs")
		If (retry."max_retries" '= 1) || (retry."initial_backoff_ms" '= 500) || (retry."max_backoff_ms" '= 2000) Set bad = bad _ $ListBuild(timer_": retry values")
		If (attempt < 1) || (worst > (timer - 8)) Set bad = bad _ $ListBuild(timer_": worst case "_worst)
	}
	Do $$$AssertEquals($ListToString(bad, "; "), "", "every timer from 12 to 110 gives two keys, the four keys of the retry block, an attempt timeout equal to the request timeout, and a worst case of at most the timer minus 8")
}

/// A timer that is not a whole number (digits only) from 12 to 110 gives {} from Derive and an error from Check, which names the setting
/// TimerSeconds of Decide and the range. Decide.CheckSettings refuses it the same way, and accepts 12 and 110. Nothing throws. The value in
/// the error is cut to 40 characters and redacted.
Method TestRefused()
{
	Set timeouts = ..#TIMEOUTS
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set filter = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set replyClass = "OcuTalon.Bridge.Msg.DecisionPayload"
	For timer = 11, 111, 0, -1, "", "x", "60.5", " 60", "6e1", "60 ", "+60", "1e2", $Char(9)_"60", "1.2.3" {
		Set label = "a timer of '"_$Translate(timer, $Char(9), "T")_"'"
		Do $$$AssertEquals($ClassMethod(timeouts, "Derive", timer).%ToJSON(), "{}", label_": Derive gives an empty object")
		Set sc = $ClassMethod(timeouts, "Check", timer)
		Do $$$AssertStatusNotOK(sc, label_": Check refuses it")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue((text [ "The setting TimerSeconds of Decide is '") && (text [ "12 to 110"), label_": with an error that names TimerSeconds and the range: "_text)
		Set sc = $ClassMethod(decide, "CheckSettings", "decide", "TriageAgent", replyClass, filter, timer)
		Do $$$AssertStatusNotOK(sc, label_": Decide.CheckSettings refuses it")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), text, label_": with the error of Check")
	}
	For timer = 12, 13, 59, 60, 110, "12", "110", "012" {
		Do $$$AssertStatusOK($ClassMethod(timeouts, "Check", timer), "a timer of "_timer_" passes Check")
		Do $$$AssertStatusOK($ClassMethod(decide, "CheckSettings", "decide", "TriageAgent", replyClass, filter, timer), "and Decide.CheckSettings")
		Do $$$AssertNotTrue($ClassMethod(timeouts, "Derive", timer).%ToJSON() = "{}", "and Derive gives its values")
	}
	Do $$$AssertEquals($Parameter(decide, "MINTIMER"), 12, "the shortest timer is 12")
	Do $$$AssertEquals($Parameter(decide, "MAXTIMER"), 110, "and the longest is 110")

	// the value is cut to 40 characters, and redacted
	Set long = "7777777777888888888899999999990000000000ZZZZZZZZZZ"
	Set text = $SYSTEM.Status.GetErrorText($ClassMethod(timeouts, "Check", long))
	Do $$$AssertTrue((text [ "'7777777777888888888899999999990000000000'") && (text '[ "ZZZZZZZZZZ"), "a long value is cut to 40 characters: "_text)
	Set token = "zzfakebearer0123456789"
	Set text = $SYSTEM.Status.GetErrorText($ClassMethod(timeouts, "Check", "Bearer "_token))
	Do $$$AssertTrue((text '[ token) && (text [ "TimerSeconds"), "a value that holds a bearer token is redacted: "_text)
	Do $$$AssertStatusNotOK($ClassMethod(timeouts, "Check", $Char(0)), "a control character is refused too")
	Set thrown = ""
	Try {
		Do $ClassMethod(timeouts, "Check")
		Do $ClassMethod(timeouts, "Derive")
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "Check and Derive with no argument throw nothing")
	Set huge = $Translate($Justify("", 1000), " ", "9")
	Set thrown = ""
	Try {
		Set sc = $ClassMethod(timeouts, "Check", huge)
		Set derived = $ClassMethod(timeouts, "Derive", huge).%ToJSON()
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "a string of 1,000 digits throws nothing")
	If thrown = "" Do $$$AssertTrue($$$ISERR(sc) && (derived = "{}"), "and is refused: Check gives an error and Derive gives {}")
}

/// Apply refuses what it should, and a refusal changes nothing. The timers outside 12 to 110, and "x", are refused first, naming TimerSeconds.
/// A production whose runner has no @{config:} entry (the example production, whose TriageAgent has an empty ProviderConfig) is refused
/// naming the runner, though 30 is a good timer; so is OcuTalon.Production when one runner names an entry that does not exist, though the
/// runners before it are fine, which shows that every runner is checked before anything is written. The row of TimerSeconds, the JSON of
/// every entry and the jobs of Decide and the runners are as they were.
Method TestApplyRefuses()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set timeouts = ..#TIMEOUTS
	Set before = ..State()
	For timer = 111, 11, "x", "", 0, -5, "30.5" {
		Set sc = $ClassMethod(timeouts, "Apply", timer)
		Do $$$AssertStatusNotOK(sc, "Apply of '"_timer_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "with an error that names TimerSeconds: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do $$$AssertTrue(..State() = before, "nothing changed: the row of TimerSeconds, the entries and the jobs are as they were")

	Set example = "OcuTalon.BridgeExample.Production"
	Set sc = $ClassMethod(timeouts, "Apply", 30, example)
	Do $$$AssertStatusNotOK(sc, "Apply of 30 to the example production, whose TriageAgent has no @{config:} entry, is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "TriageAgent") && (text [ "@{config:"), "with an error that names the runner: "_text)
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(example_"||Decide||*||TimerSeconds"), 0, "and no row of TimerSeconds was written for it")
	Do $$$AssertTrue(..State() = before, "nothing changed in OcuTalon.Production either")

	// a runner whose entry does not exist, the first two being fine
	Set saved = ..SavedRows
	Do $ClassMethod(fixture, "RememberDefault", .saved, "ChatAgent", "ProviderConfig")
	Set ..SavedRows = saved
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "ChatAgent", "ProviderConfig", "@{config:ZzNoSuchEntry}"), "ChatAgent is given a ProviderConfig that names an entry that does not exist")
	Set before = ..State()
	Set sc = $ClassMethod(timeouts, "Apply", 25, ..#PRODUCTION)
	Do $$$AssertStatusNotOK(sc, "Apply of 25 is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "ChatAgent") && (text [ "ZzNoSuchEntry"), "with an error that names the runner and the entry: "_text)
	Do $$$AssertTrue(..State() = before, "and the other runners' entries, the row and the jobs are as they were: every runner was checked first")
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(..#PRODUCTION_"||Decide||*||TimerSeconds"), $ListGet(before, 1), "in particular the row of TimerSeconds was not written")
}

/// Apply writes the row of TimerSeconds, reads the setting again and, when the timer it reads is not the one given, because the production
/// definition sets it, puts the row back and fails naming TimerSeconds, before it changes an entry or a job. The test production sets 45 in its
/// definition: Apply(30) to it fails whether the row was absent (it is absent again) or held 33 (it holds 33 again), and the Config Store entries
/// of the runners are as they were: the product's, and the one that the test creates for the test production's TriageAgent (CreateEntry).
Method TestApplyDefinedTimer()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set production = ..#ZZPRODUCTION
	Do ..CreateEntry({"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "base_url": "http://zz.invalid/v1/", "http_config": {"request_timeout_secs": 99}})
	Set entry = ..EntryJson()
	If '##class(Ens.Config.Production).%ExistsId(production) {
		Do ##class(Ens.Config.Production).LoadFromClass(production)
		Set ..Loaded = production
	}
	Set id = production_"||Decide||*||TimerSeconds"
	Set accessor = "OcuTalon.Bridge.Ext.Accessor"
	Do $$$AssertEquals($ClassMethod(accessor, "ValueFor", "TimerSeconds", production, "Decide"), 45, "control: the definition of the test production sets the timer to 45")
	Set before = ..State()
	Set sc = $ClassMethod(..#TIMEOUTS, "Apply", 30, production)
	Do $$$AssertStatusNotOK(sc, "Apply of 30 to it fails")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "TimerSeconds") && (text [ "production definition"), "naming TimerSeconds and the production definition: "_text)
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(id), 0, "the row of TimerSeconds is not there: Apply put it back by deleting it")
	Do $$$AssertTrue(..State() = before, "and no entry and no job changed")
	Do $$$AssertTrue((entry '= "none") && (..EntryJson() = entry), "and neither did the entry of the test production's runner")

	Do $$$AssertStatusOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", 33, "Written by a test; the test deletes it."), "a row of 33 is written")
	Set sc = $ClassMethod(..#TIMEOUTS, "Apply", 30, production)
	Do $$$AssertStatusNotOK(sc, "Apply of 30 fails again")
	Do $$$AssertEquals($Select(##class(Ens.Config.DefaultSettings).%ExistsId(id): ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue_"|"_##class(Ens.Config.DefaultSettings).%OpenId(id).Description, 1: "none"), "33|Written by a test; the test deletes it.", "and the row is back as it was, with its value and its description")
	Do $$$AssertTrue((..State() = before) && (..EntryJson() = entry), "and no entry and no job changed either")
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
}

/// Apply to a production that does not run (AD-5, AD-19): the System Default Settings row of TimerSeconds is written for that production, the
/// block of Derive is merged into the entry that its TriageAgent names, whose other fields stay (the key placeholder, the base URL, a header),
/// and no item is restarted, because Restart acts only for the production that runs. The call is OK. The running production is as it was: its
/// row, the JSON of its entries and the jobs of Decide and the runners. The test creates the entry and loads the production, and OnAfterOneTest
/// deletes them and the row.
Method TestApplyStopped()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set production = ..#ZZSTOPPED
	Do ..CreateEntry({"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "base_url": "http://zz.invalid/v1/", "http_config": {"custom_headers": {"x-keep": "1"}, "request_timeout_secs": 99, "retry": {"max_retries": 7}}})
	If '##class(Ens.Config.Production).%ExistsId(production) {
		Do ##class(Ens.Config.Production).LoadFromClass(production)
		Set ..Loaded = production
	}
	Do $$$AssertTrue(##class(Ens.Config.Production).%ExistsId(production), "the test production's definition is loaded")
	Set id = production_"||Decide||*||TimerSeconds"
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(id), 0, "control: it has no row of TimerSeconds")
	Set before = ..State()
	Set sc = $ClassMethod(..#TIMEOUTS, "Apply", 30, production)
	Do $$$AssertStatusOK(sc, "Apply of 30 to a production that does not run is OK")
	Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "its row of TimerSeconds is written")
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, 30, "and is 30")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Ext.Accessor", "ValueFor", "TimerSeconds", production, "Decide"), 30, "which is the timer that its Decide reads")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Details(..#ZZENTRY, .details), "the entry is read")
	If $IsObject($Get(details)) {
		Set block = details."http_config"
		Set retry = block.%Get("retry")
		Do $$$AssertEquals(block."request_timeout_secs", 10, "its request timeout is 10, from (30 - 10) \ 2")
		Do $$$AssertTrue($IsObject(retry), "and it has a retry block")
		If $IsObject(retry) Do $$$AssertEquals(retry."max_retries"_"|"_retry."attempt_timeout_secs"_"|"_retry."initial_backoff_ms"_"|"_retry."max_backoff_ms"_"|"_retry.%Size(), "1|10|500|2000|4", "whole: the four members of Derive's block, the stale max_retries of 7 replaced")
		Do $$$AssertEquals(block."custom_headers"."x-keep", "1", "the header of the entry stays")
		Do $$$AssertEquals(details."api_key"_"|"_details."base_url"_"|"_details."model_provider", "@{env:ANTHROPIC_API_KEY}|http://zz.invalid/v1/|anthropic", "and so do the key placeholder, the base URL and the provider")
	}
	Do $$$AssertTrue(..State() = before, "the running production is as it was: its row, its entries and the jobs of Decide and the runners")
}

/// Restart acts item by item and says which item could not be restarted (AD-5, AD-19). Ens.Alarm is an item that the running production adds
/// itself and that its definition does not list, so the director cannot stop it temporarily: Restart (Decide first, which it restarts) ends
/// with an error that names Ens.Alarm and says that it could not be restarted, and the item is not left stopped: it has the job it had, and
/// every item of the production runs.
Method TestRestartError()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set alarm = $ClassMethod(fixture, "Jobs", "Ens.Alarm")
	Do $$$AssertTrue(alarm '= "", "control: Ens.Alarm has a job")
	If alarm = "" Quit
	Set sc = $ClassMethod(..#TIMEOUTS, "Restart", ..#PRODUCTION, $ListBuild($ListBuild("Ens.Alarm", "OcuTalonTriage")))
	Do $$$AssertStatusNotOK(sc, "Restart of an item that cannot be stopped is an error")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "The item Ens.Alarm could not be restarted") && (text '[ "within"), "that names the item and says that it could not be restarted, not that it did not run again in time: "_text)
	Do $$$AssertEquals($ClassMethod(fixture, "Jobs", "Ens.Alarm"), alarm, "control: Ens.Alarm keeps the job it had (its stop fails before any stop flag is set, so this does not exercise the clean-up of a stop that set one)")
	Do $$$AssertTrue($ClassMethod(fixture, "WaitAllRun"), "and every item of the production runs")
}

/// Creates the Config Store entry ZZENTRY, the one that the TriageAgent of the test productions names, with the details start, after the
/// registry is built. OnAfterOneTest deletes it.
Method CreateEntry(start As %DynamicObject) [ Private ]
{
	Do $$$AssertStatusOK(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is built")
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..#ZZENTRY, start), "the entry of the test production's runner is created")
}

/// The JSON of the entry ZZENTRY (compared, never shown), or "none".
ClassMethod EntryJson() As %String [ Private ]
{
	Do ##class(OcuTalon.Bridge.ConfigStore).Details(..#ZZENTRY, .details)
	Quit $Select($IsObject($Get(details)): details.%ToJSON(), 1: "none")
}

/// What Apply may change, as a list: whether the row of TimerSeconds exists and its value, the JSON of the entry of each runner (compared,
/// never shown) and the jobs of Decide and each runner.
ClassMethod State() As %List [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set id = ..#PRODUCTION_"||Decide||*||TimerSeconds"
	Set exists = ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	Set state = $ListBuild(exists, $Select(exists: ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, 1: ""))
	Set entries = $ListBuild("OcuTalonTriage", "OcuTalonDiagnosis", "OcuTalonChat")
	Set position = 0
	While $ListNext(entries, position, name) {
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(name, .details)
		Set state = state _ $ListBuild($Select($IsObject(details): details.%ToJSON(), 1: "none"))
	}
	Set items = $ListFromString("Decide,TriageAgent,DiagnosisAgent,ChatAgent")
	Set position = 0
	While $ListNext(items, position, item) {
		Set state = state _ $ListBuild($ListToString($ClassMethod(fixture, "Jobs", item)))
	}
	Quit state
}

/// The JSON that Derive gives for the timer and the timeout_ms, with the request timeout and the attempt timeout.
ClassMethod Expected(timeoutMs As %Integer, attempt As %Integer) As %String [ Private ]
{
	Quit "{""timeout_ms"":"_timeoutMs_",""http_config"":{""request_timeout_secs"":"_attempt_",""retry"":{""max_retries"":1,""attempt_timeout_secs"":"_attempt_",""initial_backoff_ms"":500,""max_backoff_ms"":2000}}}"
}

}
