/// Tests of OcuTalon.Bridge.ConfigStore.Merge (Story 1.1, changed by Story 17.3; AD-19, AD-7). Each test works on its own entry, AI.LLM.OcuTalonZzMerge<n>
/// (n from ^OcuTalonTest("ConfigStore","n"), never reset), which it creates after RebuildRegistry() and deletes at the end; no
/// other entry is touched. The entry holds the placeholder key only, and no test writes a real key anywhere. Merge accepts two shapes of fields
/// (the timeouts shape and the model-change shape) and refuses everything else.
///   - TestMerge: the timeouts shape changes only the fields it names; nested objects merge and other keys of http_config stay; the short name and the
///     full name name the same entry; an empty object merges nothing;
///   - TestMergeRefused: a literal api_key at any depth, an api_key that is not exactly one @{env:NAME}, an @{ in any other
///     string (value, array element or field name), any field outside the two shapes and fields that are not a dynamic object are refused with a text
///     that says why and holds no value, and the entry stays unchanged after each;
///   - TestMergeRefusedAmongValidFields: a refused field that follows valid fields, at the top level and inside an object, an
///     array or a field name, refuses the whole call, and the valid fields are not written either;
///   - TestMergePlaceholder: the model-change shape with the placeholder of the provider is accepted and stored as the literal placeholder;
///   - TestModelChangeShape (Story 17.3, DW-52): each way of putting anything but the provider, its own key placeholder and a model of that provider
///     into a model change is refused, naming the field, with the entry unchanged; the valid shape is accepted, and the entry never holds the model;
///     the timeouts shape plus another field is refused; the shapes cannot be mixed; a field whose name is shaped like a key is refused without the name
///     in the reason;
///   - TestRestore (Story 17.3): Restore puts back the details that Details read after a Merge, byte for byte; details that are no dynamic object and a
///     missing entry are refused, and nothing is created;
///   - TestMergeKeyNameCharacters: an api_key placeholder is exactly @{env:<the provider's variable>}; any other variable, a hyphen, a dot, a colon,
///     a dollar sign, a letter outside ASCII, a line end or a space around the placeholder is refused;
///   - TestProviderChangeDropsEndpoint (Story 17.4, DW-758): a provider change removes base_url, custom_headers and tls and keeps the timeouts; the same provider keeps them;
///   - TestMissingEntry: a missing entry is an error that names it, and nothing is created;
///   - TestDetails (Story 1.6): Details reads the entry with its placeholders unresolved, by its short or its full name; a missing entry
///     is an error that names it and leaves details empty; Merge and Keys read through it;
///   - TestKeepsSecretReference: an entry that holds a secret:// reference is merged without resolving the reference, so the
///     reference stays what is stored (Merge reads with resolveSecrets 0);
///   - TestExpansionSeesMerge: AI Hub's @{config:} expansion of the entry shows the merged and the untouched fields, and the
///     key is still the literal placeholder.
/// Added by Story 1.7 (AD-19):
///   - TestEntryOf: EntryOf gives the entry name of a provider configuration that is exactly one @{config:<name>}, ignoring white space around
///     it, and "" for anything else (an inline JSON object, an environment placeholder, two references, braces in the name, text around it).
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

/// The timeouts shape changes only the fields it names, and the entry keeps its other fields.
Method TestMerge()
{
	Set name = ..EntryName()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"http_config": {"request_timeout_secs": 20, "retry": {"max_retries": 1, "attempt_timeout_secs": 5}}}), "Merge accepts the timeouts shape")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."http_config"."request_timeout_secs", 20, "request_timeout_secs is replaced, with its type")
	Do $$$AssertEquals(details."http_config".retry.%ToJSON(), "{""max_retries"":1,""attempt_timeout_secs"":5}", "the retry block is added")
	Do $$$AssertEquals(details."http_config"."custom_headers"."x-keep", "1", "the headers of http_config stay")
	Do $$$AssertEquals(details."base_url", "http://old.invalid/v1/", "base_url stays")
	Do $$$AssertEquals(details."model_provider", "anthropic", "the provider stays")
	Do $$$AssertEquals(details."api_key", "@{env:ANTHROPIC_API_KEY}", "the key placeholder stays")
	Do $$$AssertEquals(details.extra.%ToJSON(), "[1,2]", "an untouched array stays")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge("AI.LLM."_name, {"http_config": {"retry": {"max_retries": 2, "max_backoff_ms": 2000}}}), "the full name names the same entry, and the retry block merges deep")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."http_config".retry.%ToJSON(), "{""max_retries"":2,""attempt_timeout_secs"":5,""max_backoff_ms"":2000}", "a field of retry is replaced, another stays and a new one is added")
	Do $$$AssertEquals(details."http_config"."request_timeout_secs", 20, "request_timeout_secs stays")
	Do $$$AssertEquals(details."http_config"."custom_headers"."x-keep", "1", "the headers still stay")
	Do $$$AssertEquals(details."model_provider", "anthropic", "the provider still stays")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {}), "an empty object is a merge of nothing")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), details.%ToJSON(), "and changes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"http_config": {}}), "an empty http_config is accepted")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), details.%ToJSON(), "and changes nothing")
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

/// A refused field that comes after valid fields refuses the whole call: the entry is the same after each, so none of the valid
/// fields is written, and the error holds no value.
Method TestMergeRefusedAmongValidFields()
{
	Set name = ..EntryName()
	Set before = ..EntryDetails().%ToJSON()
	Set cases = []
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "api_key": "plain-literal-value-1"})
	Do cases.%Push({"api_key": "@{env:OPENAI_API_KEY}", "base_url": "@{env:HOME}"})
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "api_key": "@{env:A}@{env:B}"})
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "note": "x @{wallet:plain-literal-value-2} y"})
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "@{env:HOME}": "1"})
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "count": 2, "extra": ["fine", "@{config:plain-literal-value-3}"]})
	Do cases.%Push({"http_config": {"custom_headers": {"a": "1"}, "api_key": "plain-literal-value-4"}})
	Do cases.%Push({"http_config": {"request_timeout_secs": 5, "custom_headers": {"a": "1", "b": "@{env:HOME}"}}})
	Do cases.%Push({"http_config": {"custom_headers": {"a": "1"}, "@{x": "1"}})
	Do cases.%Push({"base_url": "http://ok.invalid/v1/", "http_config": {"tls": {"ca_certificates": ["fine", "@{env:HOME}"]}}})
	For i = 1:1:cases.%Size() {
		Set fields = cases.%Get(i - 1)
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(name, fields)
		Do $$$AssertStatusNotOK(sc, "case "_i_" is refused: "_fields.%ToJSON())
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ "refuses the fields", "case "_i_" says why: "_text)
		Do $$$AssertTrue(text '[ "plain-literal-value", "case "_i_" holds no value in the error")
		Do $$$AssertEquals(..EntryDetails().%ToJSON(), before, "case "_i_" leaves the entry unchanged, valid fields included")
	}
}

/// The model-change shape with the placeholder of the provider is accepted and stored as the literal placeholder.
Method TestMergePlaceholder()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}"}), "a provider and its placeholder are accepted")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."api_key", "@{env:OPENAI_API_KEY}", "the key is stored as the literal placeholder")
	Do $$$AssertEquals(details."model_provider", "openai", "and the provider is changed")
	Do $$$AssertEquals(details.%IsDefined("base_url"), 0, "the base URL of the other provider is gone (DW-758)")
	Do $$$AssertEquals(details.extra.%ToJSON(), "[1,2]", "the other fields stay")
}

/// Story 17.4 (DW-758): the endpoint fields (base_url, http_config.custom_headers, http_config.tls) belong to the entry's provider. A model-change Merge that changes the
/// provider removes them and keeps the timeouts and every other field; one that keeps the provider (Anthropic onto an Anthropic entry) keeps them; DropEndpoint
/// does the same to any details object, leaves an object with no endpoint field as it is, and removes an http_config that it empties.
Method TestProviderChangeDropsEndpoint()
{
	Set store = "OcuTalon.Bridge.ConfigStore"
	Set name = ..EntryName()
	Set start = ..EntryDetails()
	Do start."http_config".%Set("tls", {"ca_certificates": ["/opt/ca/extra.pem"], "accept_invalid_certs": false, "accept_invalid_hostnames": false})
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Modify("AI.LLM."_name, start), "the entry gets a TLS block as well (written whole, as the Provider step writes it)")
	Set before = ..EntryDetails()
	Do $$$AssertTrue(before."http_config".%IsDefined("custom_headers") && before."http_config".%IsDefined("tls") && before.%IsDefined("base_url"), "control: it holds base_url, a header and a TLS block")
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "model": "claude-sonnet-5-5"}), "(4) Anthropic is merged onto the Anthropic entry")
	Set same = ..EntryDetails()
	Do $$$AssertEquals(same.%ToJSON(), before.%ToJSON(), "the endpoint fields and everything else are kept")
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}"}), "(1) OpenAI is merged onto it")
	Set after = ..EntryDetails()
	Do $$$AssertEquals(after.%IsDefined("base_url"), 0, "base_url is gone")
	Do $$$AssertEquals(after."http_config".%IsDefined("custom_headers")_"|"_after."http_config".%IsDefined("tls"), "0|0", "and so are the header and the TLS block")
	Do $$$AssertEquals(after."http_config"."request_timeout_secs", 10, "the request timeout stays")
	Do $$$AssertEquals(after."model_provider"_"|"_after."api_key"_"|"_after.extra.%ToJSON(), "openai|@{env:OPENAI_API_KEY}|[1,2]", "and so do the new pair and the other fields")
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}"}), "OpenAI merged onto OpenAI")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), after.%ToJSON(), "changes nothing")

	Set details = {"base_url": "http://x.invalid/v1/", "http_config": {"custom_headers": {"a": "1"}}, "model_provider": "openai"}
	Do $ClassMethod(store, "DropEndpoint", details)
	Do $$$AssertEquals(details.%ToJSON(), "{""model_provider"":""openai""}", "DropEndpoint removes an http_config that it empties")
	Set details = {"model_provider": "openai", "http_config": {"request_timeout_secs": 5, "tls": {}}}
	Do $ClassMethod(store, "DropEndpoint", details)
	Do $$$AssertEquals(details.%ToJSON(), "{""model_provider"":""openai"",""http_config"":{""request_timeout_secs"":5}}", "and keeps the timeouts")
	Set same = details.%ToJSON()
	Do $ClassMethod(store, "DropEndpoint", details)
	Do $ClassMethod(store, "DropEndpoint", "")
	Do $$$AssertEquals(details.%ToJSON(), same, "an object with no endpoint field is left as it is, and a value that is no object is ignored")
}

/// Story 17.3 (DW-52, AD-7): the model-change shape is exactly model_provider, api_key and optionally model. Each case is refused with a reason that names
/// the field and holds no value, and the entry is the same after it; the valid shapes are accepted, and the entry never holds a model.
Method TestModelChangeShape()
{
	Set store = "OcuTalon.Bridge.ConfigStore"
	Set name = ..EntryName()
	Set before = ..EntryDetails().%ToJSON()
	Set good = {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}"}
	Set cases = []
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:PATH}"}, "names": "api_key"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:OPENAI_API_KEY}"}, "names": "api_key"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "base_url": "http://x.invalid/v1/"}, "names": "base_url"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "http_config": {"custom_headers": {"x": "1"}}}, "names": "http_config"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "secret://zz.zz"}, "names": "api_key"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{config:zz}"}, "names": "api_key"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "org_id": "zz"}, "names": "org_id"})
	Do cases.%Push({"fields": {"model_provider": "nope", "api_key": "@{env:ANTHROPIC_API_KEY}"}, "names": "model_provider"})
	Do cases.%Push({"fields": {"model_provider": "@{env:PATH}", "api_key": "@{env:ANTHROPIC_API_KEY}"}, "names": "model_provider"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "model": "gpt-5.4"}, "names": "model"})
	Do cases.%Push({"fields": {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}", "model": "@{env:PATH}"}, "names": "model"})
	Do cases.%Push({"fields": {"api_key": "@{env:ANTHROPIC_API_KEY}"}, "names": "model_provider"})
	Do cases.%Push({"fields": {"model_provider": "anthropic"}, "names": "api_key"})
	Do cases.%Push({"fields": {"model": "claude-haiku-5-5"}, "names": "model_provider"})
	Do cases.%Push({"fields": {"http_config": {"request_timeout_secs": 5}, "base_url": "http://x.invalid/v1/"}, "names": "base_url"})
	Do cases.%Push({"fields": {"http_config": {"request_timeout_secs": 5, "custom_headers": {"x": "1"}}}, "names": "custom_headers"})
	Do cases.%Push({"fields": {"http_config": {"retry": {"max_retries": "1"}}}, "names": "retry"})
	Do cases.%Push({"fields": {"http_config": {"request_timeout_secs": "5"}}, "names": "request_timeout_secs"})
	Do cases.%Push({"fields": {"base_url": "http://x.invalid/v1/"}, "names": "base_url"})
	For i = 1:1:cases.%Size() {
		Set one = cases.%Get(i - 1)
		Set sc = $ClassMethod(store, "Merge", name, one.fields)
		Do $$$AssertStatusNotOK(sc, "case "_i_" is refused: "_one.fields.%ToJSON())
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ one.names, "case "_i_" names the field "_one.names_": "_text)
		Do $$$AssertTrue((text '[ "PATH") && (text '[ "secret://") && (text '[ "x.invalid") && (text '[ "gpt-5.4"), "case "_i_" holds no value in the error")
		Do $$$AssertEquals(..EntryDetails().%ToJSON(), before, "case "_i_" leaves the entry unchanged")
	}
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, good), "the provider and its own placeholder are accepted")
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}", "model": "gpt-5.4"}), "so is a model of the provider, with another provider")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details."model_provider"_"|"_details."api_key", "openai|@{env:OPENAI_API_KEY}", "the entry holds the provider and the placeholder")
	Do $$$AssertEquals(details.%IsDefined("model"), 0, "and never the model: the runner's Model setting carries it")
	Do $$$AssertEquals(details.%IsDefined("base_url"), 0, "and no base URL of the other provider (DW-758)")
	Do $$$AssertEquals(details.extra.%ToJSON(), "[1,2]", "the other fields stay")
	// a field named like a key (a Google-shaped name, built here so that no key-shaped text sits in this file) is refused, and the reason never echoes the name
	Set keyName = "AI"_"za"_"SyZzFieldName0123456789abcdefghijk"
	Set unchanged = ..EntryDetails().%ToJSON()
	For depth = 1:1:3 {
		Set fields = {}
		Set target = fields
		If depth > 1 {
			Do target.%Set("http_config", {})
			Set target = target."http_config"
		}
		If depth > 2 {
			Do target.%Set("retry", {})
			Set target = target.retry
		}
		Do target.%Set(keyName, "x")
		Set sc = $ClassMethod(store, "Merge", name, fields)
		Do $$$AssertStatusNotOK(sc, "a field named like a key is refused at depth "_depth)
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ keyName, "and the reason does not echo its name (depth "_depth_")")
		Do $$$AssertEquals(..EntryDetails().%ToJSON(), unchanged, "and the entry is unchanged (depth "_depth_")")
	}
	For provider = "anthropic", "openai", "gemini", "bedrock" {
		Set row = ##class(OcuTalon.Bridge.Providers).Row(provider)
		Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": (provider), "api_key": ("@{env:"_row.keyVariable_"}"), "model": (row.defaultModel)}), provider_" with its key variable and its default model is accepted")
	}
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"http_config": {"request_timeout_secs": 7, "retry": {"max_retries": 1}}}), "the timeouts shape is accepted")
}

/// Restore writes back exactly the details that Details read, after a Merge changed the entry; a missing entry and details that are no dynamic object
/// are errors, and nothing is created.
Method TestRestore()
{
	Set store = "OcuTalon.Bridge.ConfigStore"
	Set name = ..EntryName()
	Do $$$AssertStatusOK($ClassMethod(store, "Details", name, .before), "Details reads the entry")
	Set expected = ..EntryDetails().%ToJSON()
	Do $$$AssertStatusOK($ClassMethod(store, "Merge", name, {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}"}), "Merge changes the provider and the key placeholder")
	Do $$$AssertTrue(..EntryDetails().%ToJSON() '= expected, "so the entry is no longer as it was")
	Do $$$AssertStatusOK($ClassMethod(store, "Restore", name, before), "Restore puts the details back")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), expected, "and the entry is byte-equal to what Details read")
	Do $$$AssertStatusNotOK($ClassMethod(store, "Restore", name, "not an object"), "details that are no dynamic object are refused")
	Do $$$AssertStatusNotOK($ClassMethod(store, "Restore", name, ""), "so are empty details")
	Do $$$AssertEquals(..EntryDetails().%ToJSON(), expected, "and the entry stays as it was")
	Set missing = name_"Missing"
	Set sc = $ClassMethod(store, "Restore", missing, before)
	Do $$$AssertStatusNotOK(sc, "a missing entry is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ missing, "that names the entry: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists("AI.LLM."_missing), 0, "and nothing is created")
}

/// An api_key placeholder is exactly @{env:<the provider's variable>}: another variable, other characters, a line end or a space around the
/// placeholder make it a refused api_key, and the entry is unchanged.
Method TestMergeKeyNameCharacters()
{
	Set name = ..EntryName()
	For provider = "anthropic", "openai", "gemini", "bedrock" {
		Set variable = ##class(OcuTalon.Bridge.Providers).Row(provider).keyVariable
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"model_provider": (provider), "api_key": ("@{env:" _ variable _ "}")}), "the variable '"_variable_"' of "_provider_" is accepted")
		Do $$$AssertEquals(..EntryDetails()."api_key", "@{env:" _ variable _ "}", "and stored as the placeholder")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}"}), "the key is put back to the start value")
	Set before = ..EntryDetails().%ToJSON()
	Set refused = $ListBuild("@{env:A}", "@{env:a1_B2}", "@{env:_x}", "@{env:9}", "@{env:OPENAI_API_KEY}", "@{env:A-B}", "@{env:A.B}", "@{env:A:B}", "@{env:A$B}", "@{env:A/B}", "@{env:A"_$Char(233)_"}", "@{env:ANTHROPIC_API_KEY}"_$Char(10), "@{env:ANTHROPIC_API_KEY}"_$Char(13, 10), $Char(10)_"@{env:ANTHROPIC_API_KEY}", " @{env:ANTHROPIC_API_KEY}", "@{env:ANTHROPIC_API_KEY} ", "@{ env:ANTHROPIC_API_KEY}", "@{env: ANTHROPIC_API_KEY}", "@{env:ANTHROPIC_API_KEY")
	Set position = 0
	Set n = 0
	While $ListNext(refused, position, value) {
		Set n = n + 1
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(name, {"model_provider": "anthropic", "api_key": (value)})
		Do $$$AssertStatusNotOK(sc, "the api_key of case "_n_" ("_$Length(value)_" characters) is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "refuses the fields", "and the error says why")
		Do $$$AssertEquals(..EntryDetails().%ToJSON(), before, "and the entry is unchanged")
	}
}

/// A missing entry is an error that names it, and Merge creates nothing.
Method TestMissingEntry()
{
	Set missing = "OcuTalonZzMissing"_..Number
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(missing, {"http_config": {"request_timeout_secs": 5}})
	Do $$$AssertStatusNotOK(sc, "Merge of a missing entry is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("AI.LLM."_missing), "which names the entry")
	Do $$$AssertTrue('##class(%ConfigStore.Configuration).Exists("AI.LLM."_missing), "and creates nothing")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.ConfigStore).Merge("", {"http_config": {"request_timeout_secs": 5}}), "an empty name is an error")
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
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"http_config": {"request_timeout_secs": 7}}), "Merge reads it without resolving the reference")
	Set details = ..EntryDetails()
	Do $$$AssertEquals(details.note, reference, "and writes the reference back as it was")
	Do $$$AssertEquals(details."http_config"."request_timeout_secs", 7, "and the given field changed")
}

/// AI Hub's @{config:} expansion shows the merged fields and the untouched ones, and the key stays a placeholder.
Method TestExpansionSeesMerge()
{
	Do $$$AssertStatusOK(##class(%AI.Utils.SettingStore).RegisterDefaults(), "the setting stores are registered")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryName(), {"http_config": {"request_timeout_secs": 31, "retry": {"max_retries": 1}}}), "Merge accepts the fields")
	Set expanded = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand("@{config:"_..EntryName()_"}"))
	Do $$$AssertEquals(expanded."http_config"."request_timeout_secs", 31, "the expansion shows the merged timeout")
	Do $$$AssertEquals(expanded."http_config".retry."max_retries", 1, "and the merged retry block")
	Do $$$AssertEquals(expanded."http_config"."custom_headers"."x-keep", "1", "and the untouched header")
	Do $$$AssertEquals(expanded."base_url", "http://old.invalid/v1/", "and the untouched base_url")
	Do $$$AssertEquals(expanded."model_provider", "anthropic", "and the provider")
	Do $$$AssertEquals(expanded."api_key", "@{env:ANTHROPIC_API_KEY}", "and the key still as the literal placeholder")
}

/// Details gives the details of the entry, with the api_key as its placeholder, by the short and by the full name. A missing entry is an
/// error that names it, and details is empty.
Method TestDetails()
{
	Set store = "OcuTalon.Bridge.ConfigStore"
	Set name = ..EntryName()
	Do $$$AssertStatusOK($ClassMethod(store, "Details", name, .details), "Details reads the entry by its short name")
	Do $$$AssertEquals($Select($IsObject(details): details."api_key", 1: ""), "@{env:ANTHROPIC_API_KEY}", "the api_key is the placeholder, not a value")
	Do $$$AssertEquals($Select($IsObject(details): details."model_provider", 1: ""), "anthropic", "and the other fields are as they were written")
	Do $$$AssertStatusOK($ClassMethod(store, "Details", "AI.LLM."_name, .full), "and by its full name")
	Do $$$AssertEquals($Select($IsObject(full): full.%ToJSON(), 1: ""), $Select($IsObject(details): details.%ToJSON(), 1: ""), "with the same details")
	Set sc = $ClassMethod(store, "Details", "ZzNoSuchEntry", .none)
	Do $$$AssertStatusNotOK(sc, "a missing entry is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "AI.LLM.ZzNoSuchEntry", "that names the entry: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(none, "", "and details is empty")
}

/// --- helpers ---
/// EntryOf reads the name out of a runner's ProviderConfig when it is exactly one @{config:<name>} (Keys.Present and Timeouts.Apply use it).
Method TestEntryOf()
{
	Set store = "OcuTalon.Bridge.ConfigStore"
	Do $$$AssertEquals($ClassMethod(store, "EntryOf", "@{config:OcuTalonTriage}"), "OcuTalonTriage", "a reference gives the name")
	Do $$$AssertEquals($ClassMethod(store, "EntryOf", " "_$Char(9, 10)_"@{config:OcuTalonChat}"_$Char(13, 10, 32)), "OcuTalonChat", "also with white space and line ends around it")
	Do $$$AssertEquals($ClassMethod(store, "EntryOf", "@{config:AI.LLM.OcuTalonTriage}"), "AI.LLM.OcuTalonTriage", "a full name is given as written")
	Do $$$AssertEquals($ClassMethod(store, "EntryOf", "@{config:Zz-1.x_y}"), "Zz-1.x_y", "so is a name with other punctuation")
	For text = "", " ", "OcuTalonTriage", "{""api_key"":""@{env:ANTHROPIC_API_KEY}""}", "@{env:ANTHROPIC_API_KEY}", "@{config:}", "@{config:a}{b}", "@{config:a{b}", "@{config:a}@{config:b}", "x@{config:a}", "@{config:a}x", "@{CONFIG:a}", "@{config: }x}" {
		Do $$$AssertEquals($ClassMethod(store, "EntryOf", text), "", "'"_text_"' names no entry")
	}
	Do $$$AssertEquals($ClassMethod(store, "EntryOf"), "", "no argument names none")
	Set name = $ClassMethod(store, "EntryOf", "@{config:OcuTalonTriage}")
	Do $$$AssertEquals($ClassMethod(store, "FullName", name), "AI.LLM.OcuTalonTriage", "and the name is one that FullName takes")
}

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
