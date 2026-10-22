/// Tests of the model-key API (Story 1.6; AD-6, AD-19, AD-20, FR-38): Keys.Present and Keys.Status, in process. They need no mock and
/// send nothing. They read the environment of this process and, for the entries, the Config Store, where the test creates one entry of
/// its own, AI.LLM.OcuTalonZzKeys<n> (n from ^OcuTalonTest("Keys","n"), never reset), after RebuildRegistry(), and deletes it at the end.
/// The entry holds placeholders and one literal word, never a key, and no test writes a real key anywhere.
///   - TestPresent: Present of "", {}, {"api_key":""}, {"api_key":"@{env:PATH}"}, {"api_key":"@{env:ZZOCUTALONNOSUCHVAR}"},
///     {"api_key":"literal-value"}, @{config:ZzNoSuchEntry} and "not json" is 0, 0, 0, 1, 0, 1, 0 and 1; every result is exactly 0 or 1;
///     no row of the event log written since the test began holds the value of PATH; a control shows that PATH is set in this process and
///     that the other variable is not;
///   - TestPresentForms: further forms that Present has to judge, an api_key that is not one placeholder, a null or non-string api_key,
///     a JSON array, white space around the text, and a text that starts like JSON and is not;
///   - TestPresentEntry: @{config:<name>} reads the entry without resolving it: an api_key placeholder whose variable is set is 1,
///     one whose variable is not set is 0, an entry with no api_key is 0, a literal is 1, and the full name of the entry works too;
///   - TestStatus: Status of an item that is not in the production is 0 (and of an empty name), and the status of each runner item of the
///     active production is Present of its ProviderConfig, which names a Config Store entry; every result is exactly 0 or 1;
///   - TestStatusReadsProviderConfig: with the System Default Settings row ProviderConfig of TriageAgent (the Provider step writes it)
///     put to inline configurations, Status follows it, and the row is put back (Test.Agent.RunnerFixture.SnapshotDefault, PutDefault and
///     RestoreDefault).
Class OcuTalon.Test.Bridge.Keys Extends %UnitTest.TestCase
{

/// The variable that a CI start leaves unset, and that no process sets.
Parameter UNSET = "ZZOCUTALONNOSUCHVAR";

/// The run's number.
Property Number As %Integer;

/// The ProviderConfig row of TriageAgent before the test touched it (Test.Agent.RunnerFixture.SnapshotDefault), or "".
Property Saved As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("Keys", "n"))
	Quit ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteEntry()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DeleteEntry()
	If ..Saved '= "" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefault(..Saved)
		Set ..Saved = ""
	}
	Quit $$$OK
}

/// The Keys row of the matrix: the eight configurations and Status of an item that is not there, with the controls that make the
/// answers mean something, and the proof that no value is logged.
Method TestPresent()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set path = $SYSTEM.Util.GetEnviron("PATH")
	Do $$$AssertTrue(path '= "", "control: PATH is set in this process ("_$Length(path)_" characters)")
	Do $$$AssertEquals($SYSTEM.Util.GetEnviron(..#UNSET), "", "control: "_..#UNSET_" is not set")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set cases = $ListBuild("", "{}", "{""api_key"":""""}", "{""api_key"":""@{env:PATH}""}", "{""api_key"":""@{env:"_..#UNSET_"}""}", "{""api_key"":""literal-value""}", "@{config:ZzNoSuchEntry}", "not json")
	Set expected = $ListBuild(0, 0, 0, 1, 0, 1, 0, 1)
	For i = 1:1:$ListLength(cases) {
		Set text = $List(cases, i)
		Set result = $ClassMethod(keys, "Present", text)
		Do $$$AssertEquals(result, $List(expected, i), "Present of '"_text_"' is "_$List(expected, i))
		Do $$$AssertTrue((result = 0) || (result = 1), "and exactly 0 or 1: '"_result_"'")
	}
	Set result = $ClassMethod(keys, "Status", "ZzNoSuchItem")
	Do $$$AssertEquals(result, 0, "Status of an item that is not in the production is 0")
	Do $$$AssertTrue((result = 0) || (result = 1), "exactly 0 or 1")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, path), 0, "no row of the event log since the test began holds the value of PATH")
}

/// Forms that Present has to judge, beyond the matrix.
Method TestPresentForms()
{
	Set keys = "OcuTalon.Bridge.Keys"
	// not one placeholder: judged present, because the bridge cannot tell that the key is missing
	For key = "@{env:PATH}x", "x@{env:PATH}", "@{env:PATH:-fallback}", "@{env:NO-DASH}", "@{secret:x}", "secret://wallet/key", "@{env:"_..#UNSET_"} @{env:PATH}" {
		Set text = {"api_key": (key)}.%ToJSON()
		Do $$$AssertEquals($ClassMethod(keys, "Present", text), 1, "an api_key that is not exactly one placeholder counts as present: "_key)
	}
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":null}"), 0, "a null api_key is missing")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":"" ""}"), 0, "an api_key of white space is empty")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":5}"), 1, "an api_key that is no string is a form that is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":{""a"":1}}"), 1, "nor is an object")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "[]"), 1, "a JSON array is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{"), 1, "text that starts like JSON and is not is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", $Char(10, 9)_"{""api_key"":""@{env:PATH}""}"_$Char(13, 10)), 1, "white space around the text is ignored")
	Do $$$AssertEquals($ClassMethod(keys, "Present", " "), 0, "a text of white space is empty")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""model_provider"":""anthropic"",""api_key"":""@{env:PATH}"",""base_url"":""http://mock/v1/""}"), 1, "a full inline configuration is read")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "@{config:}"), 1, "a reference with no name is not judged")
}

/// @{config:<name>}: the entry AI.LLM.<name> is read without resolving it.
Method TestPresentEntry()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set name = ..EntryName()
	Set reference = "@{config:"_name_"}"
	Set sc = ..CreateEntry({"model_provider": "anthropic", "api_key": "@{env:PATH}"})
	Do $$$AssertStatusOK(sc, "an entry with the placeholder of PATH is created")
	If $$$ISERR(sc) Quit
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 1, "an api_key placeholder whose variable is set is present")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "@{config:AI.LLM."_name_"}"), 1, "the name may be written in full")
	Do ..DeleteEntry()
	Do $$$AssertStatusOK(..CreateEntry({"model_provider": "anthropic", "api_key": ("@{env:"_..#UNSET_"}")}), "an entry with a placeholder of an unset variable is created")
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an api_key placeholder whose variable is not set is missing")
	Do ..DeleteEntry()
	Do $$$AssertStatusOK(..CreateEntry({"model_provider": "anthropic", "api_key": "literal-value"}), "an entry with a literal word is created")
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 1, "a literal value is present")
	Do ..DeleteEntry()
	Set sc = ..CreateEntry({"model_provider": "anthropic"})
	If $$$ISOK(sc) {
		Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an entry with no api_key is missing")
	} Else {
		Do $$$LogMessage("an entry with no api_key cannot be created here, so the case is not tested: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do ..DeleteEntry()
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an entry that does not exist is missing")
}

/// Status reads the ProviderConfig adapter setting of the runner item in the active production.
Method TestStatus()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Do $$$AssertEquals($ClassMethod(keys, "Status", "ZzNoSuchItem"), 0, "an item that is not in the production has no key")
	Do $$$AssertEquals($ClassMethod(keys, "Status", ""), 0, "and neither has an empty name")
	Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" {
		Do $$$AssertTrue(0, "no production is active, so the ProviderConfig of the runners cannot be read")
		Quit
	}
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Set config = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "ProviderConfig", .sc)
		Do $$$AssertStatusOK(sc, item_"'s ProviderConfig is read")
		Do $$$AssertTrue(config [ "@{config:", item_"'s ProviderConfig names a Config Store entry")
		Set status = $ClassMethod(keys, "Status", item)
		Do $$$AssertTrue((status = 0) || (status = 1), item_": exactly 0 or 1: '"_status_"'")
		Do $$$AssertEquals(status, $ClassMethod(keys, "Present", config), item_": Status is Present of its ProviderConfig")
	}
}

/// Status follows the ProviderConfig setting of the item: an inline configuration whose api_key placeholder names a set variable is a
/// key, one that names an unset variable is none, and so are a configuration without an api_key and a reference to an entry that does
/// not exist; the row is put back afterwards.
Method TestStatusReadsProviderConfig()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	If ##class(Ens.Director).GetActiveProductionName() = "" {
		Do $$$AssertTrue(0, "no production is active, so the ProviderConfig of TriageAgent cannot be read")
		Quit
	}
	Set ..Saved = $ClassMethod(fixture, "SnapshotDefault", "TriageAgent", "ProviderConfig")
	Set cases = $ListBuild($ListBuild("{""api_key"":""@{env:PATH}""}", 1), $ListBuild("{""api_key"":""@{env:"_..#UNSET_"}""}", 0), $ListBuild("{}", 0), $ListBuild("@{config:ZzNoSuchEntry}", 0), $ListBuild("{""api_key"":""literal-value""}", 1), $ListBuild("not json", 1))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "TriageAgent", "ProviderConfig", $List(case, 1)), "the ProviderConfig of TriageAgent is '"_$List(case, 1)_"'")
		Do $$$AssertEquals($ClassMethod(keys, "Status", "TriageAgent"), $List(case, 2), "Status of TriageAgent is "_$List(case, 2))
	}
	Do $$$AssertEquals($ClassMethod(keys, "Status", "ZzNoSuchItem"), 0, "an item that is not in the production has no key, whatever the row says")
}

/// --- helpers ---
/// The name of this run's entry, without the area and type.
Method EntryName() As %String [ Private ]
{
	Quit "OcuTalonZzKeys"_..Number
}

/// Creates this run's entry with the details.
Method CreateEntry(details As %DynamicObject) As %Status [ Private ]
{
	Do ..DeleteEntry()
	Quit ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..EntryName(), details)
}

/// Deletes this run's entry when it exists.
Method DeleteEntry() [ Private ]
{
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_..EntryName()) Do ##class(%ConfigStore.Configuration).Delete("AI.LLM."_..EntryName())
}

}
