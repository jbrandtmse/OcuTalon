/// Tests of OcuTalon.Bridge.ConfigStore.Merge (Story 1.1; AD-19). Each test works on its own entry, AI.LLM.OcuTalonZzMerge<n>
/// (n from ^OcuTalonTest("ConfigStore","n"), never reset), which it creates after RebuildRegistry() and deletes at the end; no
/// other entry is touched. The entry holds the placeholder key only, and no test writes a real key anywhere.
///   - TestMerge: only the given fields change; nested objects merge and other keys of http_config stay; a JSON null removes a
///     field, also a nested one; an array and a scalar replace; the short name and the full name name the same entry;
///   - TestMergeRefused: a literal api_key at any depth, an api_key that is not exactly one @{env:NAME}, an @{ in any other
///     string (value, array element or field name), and fields that are not a dynamic object are refused with a text that says
///     why and holds no value, and the entry stays unchanged after each;
///   - TestMergePlaceholder: api_key @{env:OPENAI_API_KEY} is accepted, because Story 17.3 sends that form;
///   - TestMissingEntry: a missing entry is an error that names it, and nothing is created;
///   - TestKeepsSecretReference: an entry that holds a secret:// reference is merged without resolving the reference, so the
///     reference stays what is stored (Merge reads with resolveSecrets 0);
///   - TestExpansionSeesMerge: AI Hub's @{config:} expansion of the entry shows the merged and the untouched fields, and the
///     key is still the literal placeholder.
Class OcuTalon.Test.Bridge.ConfigStore Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The details that every test starts its entry with.
Parameter START = "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":""http://old.invalid/v1/"",""http_config"":{""custom_headers"":{""x-keep"":""1"",""a"":""0""},""request_timeout_secs"":10},""extra"":[1,2]}";

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("ConfigStore", "n"))
	Quit ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteEntry()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ..DeleteEntry()
	Set sc = ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..EntryName(), {}.%FromJSON(..#START))
	Quit sc
}

Method OnAfterOneTest() As %Status
{
	Do ..DeleteEntry()
	Quit $SYSTEM.Status.OK()
}

/// Only the given fields change, and the entry keeps its other fields.
Method TestMerge()
{
	Set name = ..EntryName()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"base_url": "x", "http_config": {"custom_headers": {"a": "1"}}}), "Merge accepts the fields")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."base_url", "x", "base_url is replaced")
	Do $$$AssertEquals(details."http_config"."custom_headers".a, "1", "the nested header is replaced")
	Do $$$AssertEquals(details."http_config"."custom_headers"."x-keep", "1", "the other header stays")
	Do $$$AssertEquals(details."http_config"."request_timeout_secs", 10, "the other key of http_config stays, with its type")
	Do $$$AssertEquals(details."model_provider", "anthropic", "the provider stays")
	Do $$$AssertEquals(details."api_key", "@{env:ANTHROPIC_API_KEY}", "the key placeholder stays")
	Do $$$AssertEquals(details.extra.%ToJSON(), "[1,2]", "an untouched array stays")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge("AI.LLM."_name, {"base_url": null, "http_config": {"custom_headers": {"a": null}, "tls": {"accept_invalid_certs": false}}, "extra": [3], "flag": true, "count": 2}), "the full name names the same entry; null, a new object, an array and scalars are accepted")
	Set details = ..EntryDetails()
	Do $$$AssertTrue('details.%IsDefined("base_url"), "a null removes base_url")
	Do $$$AssertTrue('details."http_config"."custom_headers".%IsDefined("a"), "a nested null removes the header")
	Do $$$AssertEquals(details."http_config"."custom_headers"."x-keep", "1", "the other header still stays")
	Do $$$AssertEquals(details."http_config".tls."accept_invalid_certs", 0, "a new nested object is added")
	Do $$$AssertEquals(details."http_config".tls.%GetTypeOf("accept_invalid_certs"), "boolean", "with its boolean type")
	Do $$$AssertEquals(details.extra.%ToJSON(), "[3]", "an array replaces the array")
	Do $$$AssertEquals(details.%GetTypeOf("flag"), "boolean", "a boolean keeps its type")
	Do $$$AssertEquals(details.count, 2, "a number is added")
	Do $$$AssertEquals(details."model_provider", "anthropic", "the provider still stays")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"http_config": {"tls": {"x": {"y": null}}}}), "a null under an object that is new removes nothing and adds no null")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."http_config".tls.x.%ToJSON(), "{}", "the new object is empty")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {}), "an empty object is a merge of nothing")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), details.%ToJSON(), "and changes nothing")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"model_provider": null}), "a merge that leaves the entry invalid is an error")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), details.%ToJSON(), "and leaves it as it was")
}

/// A literal key, an api_key that is not one placeholder, an @{ in any other string and fields that are not an object are
/// refused; the entry is the same after each, and the text of the error holds no value.
Method TestMergeRefused()
{
	Set name = ..EntryName()
	Set before = ..EntryDetails().%ToJSON()
	Set cases = []
	Do cases.%Push({"api_key": "plain-literal-value-1"})
	Do cases.%Push({"http_config": {"api_key": "plain-literal-value-2"}})
	Do cases.%Push({"extra": [{"api_key": "plain-literal-value-3"}]})
	Do cases.%Push({"api_key": "@{wallet:plain-literal-value-4}"})
	Do cases.%Push({"api_key": "@{env:A}@{env:B}"})
	Do cases.%Push({"api_key": "x@{env:A}"})
	Do cases.%Push({"api_key": "@{env:A}x"})
	Do cases.%Push({"api_key": "@{env:A B}"})
	Do cases.%Push({"api_key": "@{env:}"})
	Do cases.%Push({"api_key": ""})
	Do cases.%Push({"api_key": 12345})
	Do cases.%Push({"api_key": {"v": "@{env:A}"}})
	Do cases.%Push({"api_key": null})
	Do cases.%Push({"base_url": "@{env:HOME}"})
	Do cases.%Push({"http_config": {"custom_headers": {"a": "x @{wallet:plain-literal-value-5} y"}}})
	Do cases.%Push({"extra": ["fine", "@{config:plain-literal-value-6}"]})
	Do cases.%Push({"@{env:HOME}": "1"})
	Do cases.%Push({"http_config": {"@{x": "1"}})
	For i = 1:1:cases.%Size() {
		Set fields = cases.%Get(i - 1)
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(name, fields)
		Do $$$AssertStatusNotOK(sc, "case "_i_" is refused: "_fields.%ToJSON())
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ "refuses the fields", "case "_i_" says why: "_text)
		Do $$$AssertTrue(text '[ "plain-literal-value", "case "_i_" holds no value in the error")
		Do $$$AssertEquals(..EntryDetails().%ToJSON(), before, "case "_i_" leaves the entry unchanged")
	}
	For bad = "", "text", 7 {
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(name, bad)
		Do $$$AssertStatusNotOK(sc, "fields '"_bad_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "not a dynamic object", "and the error says that it is not a dynamic object")
	}
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(name, [{"base_url": "x"}])
	Do $$$AssertStatusNotOK(sc, "an array is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "not a dynamic object", "and the error says that it is not a dynamic object")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), before, "the entry is unchanged after all of them")
}

/// api_key @{env:OPENAI_API_KEY} is accepted: it is the form that Story 17.3 sends.
Method TestMergePlaceholder()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"api_key": "@{env:OPENAI_API_KEY}"}), "a placeholder is accepted")
	Do $$$AssertEquals(..EntryDetails()."api_key", "@{env:OPENAI_API_KEY}", "and stored as the literal placeholder")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"http_config": {"api_key": "@{env:Some_Key_2}"}}), "also at a depth")
}

/// A missing entry is an error that names it, and Merge creates nothing.
Method TestMissingEntry()
{
	Set missing = "OcuTalonZzMissing"_..Number
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(missing, {"base_url": "x"})
	Do $$$AssertStatusNotOK(sc, "Merge of a missing entry is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("AI.LLM."_missing), "which names the entry")
	Do $$$AssertTrue('##class(%ConfigStore.Configuration).Exists("AI.LLM."_missing), "and creates nothing")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.ConfigStore).Merge("", {"base_url": "x"}), "an empty name is an error")
}

/// An entry that holds a reference to a secret that cannot be resolved is merged and written back with the reference as it was:
/// Merge reads the entry without resolving secrets, so it neither fails on the reference nor stores a resolved value.
Method TestKeepsSecretReference()
{
	Set reference = "secret://OcuTalonZzNoCollection.OcuTalonZzNoSecret"
	Do ..DeleteEntry()
	Set start = {}.%FromJSON(..#START)
	Do start.%Set("note", reference)
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..EntryName(), start), "an entry that holds a secret reference is created")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"base_url": "x"}), "Merge reads it without resolving the reference")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details.note, reference, "and writes the reference back as it was")
	Do $$$AssertEquals(details."base_url", "x", "and the given field changed")
}

/// AI Hub's @{config:} expansion shows the merged fields and the untouched ones, and the key stays a placeholder.
Method TestExpansionSeesMerge()
{
	Do $$$AssertStatusOK(##class(%AI.Utils.SettingStore).RegisterDefaults(), "the setting stores are registered")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"base_url": "http://merged.invalid/v1/", "http_config": {"custom_headers": {"a": "1"}}}), "Merge accepts the fields")
	Set expanded = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand("@{config:"_..EntryName()_"}"))
	Do $$$AssertEquals(expanded."base_url", "http://merged.invalid/v1/", "the expansion shows the merged base_url")
	Do $$$AssertEquals(expanded."http_config"."custom_headers".a, "1", "and the merged header")
	Do $$$AssertEquals(expanded."http_config"."custom_headers"."x-keep", "1", "and the untouched header")
	Do $$$AssertEquals(expanded."model_provider", "anthropic", "and the provider")
	Do $$$AssertEquals(expanded."api_key", "@{env:ANTHROPIC_API_KEY}", "and the key still as the literal placeholder")
}

/// --- helpers ---
/// The name of this run's entry, without the area and type.
Method EntryName() As %String [ Private ]
{
	Quit "OcuTalonZzMerge"_..Number
}

/// The details of this run's entry.
Method EntryDetails() As %DynamicObject [ Private ]
{
	Do ##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_..EntryName(), .details, 0, 0)
	Quit details
}

/// Deletes this run's entry when it exists.
Method DeleteEntry() [ Private ]
{
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_..EntryName()) Do ##class(%ConfigStore.Configuration).Delete("AI.LLM."_..EntryName())
}

}
