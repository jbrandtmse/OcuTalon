/// Tests of the Provider installer step (Story 1.1; AD-7, AD-19, DW-39). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs the Config Store entries and the ProviderConfig rows that the after-start script's Provider step wrote,
/// it runs the step again, and it deletes one entry and its row. Each test puts back the entry and the row that it changes.
///   - TestDetails: the pure builder gives, for each row of the matrix, exactly the entry of the matrix: the judges' install,
///     CI, a base URL alone with every flag value, the flag alone, a CA file; and it never gives a model or anything but the
///     literal key placeholder, also with a key in the environment;
///   - TestBadOverrides: a base URL that is not http(s)://host/.../v1/ (or that holds a user name, a query or a fragment) and a
///     CA file that does not exist fail the step, naming the variable and never the URL, and leave every entry and row as they
///     were;
///   - TestApplyCaFile: a CA file that exists, given to the step, reaches every entry as the tls block of http_config, and a
///     run from the environment puts the entries back;
///   - TestEntries: after the start, each runner of OcuTalon.Production has the entry that Details gives for this environment,
///     with the default read and edit resources, and its ProviderConfig row is @{config:OcuTalon<Agent>}, which expands to
///     the entry with the key still a placeholder;
///   - TestRerun: stale fields in an entry (a model, a base URL, a header, a typed key) are gone after Run(), which modifies
///     the entry where a create would fail;
///   - TestEntryBeforeSetting: with an entry and its row deleted, Run() writes both, and the row can only be written after the
///     entry, because the setting's validation expands @{config:}.
Class OcuTalon.Test.Install.Provider Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The base URL of the CI mock.
Parameter MOCKURL = "http://mock:8080/v1/";

/// The literal placeholder of the key.
Parameter PLACEHOLDER = "@{env:ANTHROPIC_API_KEY}";

/// Every row of the matrix that the pure builder answers, and what the entry holds.
Method TestDetails()
{
	Set triage = "OcuTalon.Agent.Triage"
	Set base = "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}""}"
	Set agents = $ListBuild("OcuTalon.Agent.Triage", "triage", "OcuTalon.Agent.Diagnosis", "diagnosis", "OcuTalon.Agent.Chat", "chat")

	// Judges' install: no override, no base_url and no http_config.
	For i = 1:2:5 {
		Do ..Expect("the judges' install for "_$List(agents, i), ..Pure($List(agents, i)), base)
	}
	// CI: the base URL and the flag 1 give base_url and the agent's own mock key.
	For i = 1:2:5 {
		Do ..Expect("CI for "_$List(agents, i), ..Pure($List(agents, i), ..#MOCKURL, "", "1"), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":"""_$List(agents, i + 1)_"""}}}")
	}
	// Base URL alone: base_url only, whatever the flag is unless it is exactly 1 (DW-39).
	For flag = "", "0", "true", " 1", "1 ", "01", 2 {
		Do ..Expect("a base URL with the flag '"_flag_"'", ..Pure(triage, ..#MOCKURL, "", flag), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_"""}")
	}
	Do ..Expect("a base URL with no flag argument", ..Pure(triage, ..#MOCKURL), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_"""}")
	// Flag alone: the header and no base_url (owner value 11).
	Do ..Expect("the flag alone", ..Pure(triage, "", "", "1"), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""}}}")
	// CA file: the full tls block with both accept_invalid_* flags false.
	Set tls = """tls"":{""ca_certificates"":[""/opt/ca/extra.pem""],""accept_invalid_certs"":false,""accept_invalid_hostnames"":false}"
	Do ..Expect("a CA file", ..Pure(triage, "", "/opt/ca/extra.pem", ""), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""http_config"":{"_tls_"}}")
	Do ..Expect("a CA file with the base URL and the flag", ..Pure(triage, ..#MOCKURL, "/opt/ca/extra.pem", "1"), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""},"_tls_"}}")
	// An agent class with no MOCKKEY gets no header.
	Do ..Expect("an agent class that does not exist", ..Pure("OcuTalon.Agent.ZzNoSuchAgent", ..#MOCKURL, "", "1"), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_"""}")

	// Never a model, and never anything but the literal placeholder, whatever the overrides are.
	Set checked = 0
	For url = "", ..#MOCKURL {
		For file = "", "/opt/ca/extra.pem" {
			For flag = "", "1" {
				Set details = ..Pure(triage, url, file, flag)
				Set checked = checked + 1
				Do $$$AssertTrue('details.%IsDefined("model"), "no model: "_url_" "_file_" "_flag)
				Do $$$AssertEquals(details."api_key", ..#PLACEHOLDER, "the key is the literal placeholder: "_url_" "_file_" "_flag)
				Do $$$AssertEquals($Length(details.%ToJSON(), "@{"), 2, "and the only @{ is the placeholder's: "_url_" "_file_" "_flag)
			}
		}
	}
	Do $$$AssertEquals(checked, 8, "eight combinations of the overrides were built")

	// The key's value is never read: with a key in the environment the entry still holds the placeholder.
	Set fake = "ocutalon-details-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set variable = "ANTHROPIC_API_KEY"
	Set had = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable)
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Try {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, fake)
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), fake, "the fake key is in the environment of the process")
		Do ..Expect("a key in the environment", ..Pure(triage, ..#MOCKURL, "", "1"), "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""}}}")
		Do $$$AssertTrue(..Pure(triage).%ToJSON() '[ fake, "and the details hold no key")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the details are built without an exception")
	}
	If had {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, previous)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable), had, "the key variable is as it was found")
}

/// A bad base URL or a missing CA file fails the step, naming the variable (and the path), and nothing is written.
Method TestBadOverrides()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	For url = "", ..#MOCKURL, "https://api.anthropic.com/v1/", "http://host/prefix/v1/", "HTTPS://Host/v1/" {
		Do $$$AssertStatusOK($ClassMethod(provider, "CheckBaseUrl", url), "the base URL '"_url_"' is accepted")
	}
	For url = "api.anthropic.com/v1/", "ftp://host/v1/", "http://host/v1", "http://host/", "http://host/v1/x", " http://host/v1/", "http:///v1/", "http://v1/", "http://ho st/v1/", "http://user:secret-pass@host/v1/", "http://host/v1/?token=secret-pass", "http://host/?token=secret-pass/v1/", "http://host/#secret-pass/v1/", "http://host/a@b/v1/" {
		Set sc = $ClassMethod(provider, "CheckBaseUrl", url)
		Do $$$AssertStatusNotOK(sc, "the base URL '"_url_"' is refused")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ "OCUTALON_MODEL_BASE_URL", "and the error names OCUTALON_MODEL_BASE_URL")
		Do $$$AssertTrue(text '[ "secret-pass", "and holds none of its value")
		Do $$$AssertTrue(text '[ url, "and not the URL")
	}
	Set file = ##class(%File).TempFilename("pem")
	Do $$$AssertStatusOK($ClassMethod(provider, "CheckCaFile", ""), "no CA file is accepted")
	Do $$$AssertStatusOK($ClassMethod(provider, "CheckCaFile", file), "a CA file that exists is accepted")
	Do ##class(%File).Delete(file)
	Set sc = $ClassMethod(provider, "CheckCaFile", file)
	Do $$$AssertStatusNotOK(sc, "a CA file that does not exist is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_EXTRA_CA_FILE", "and the error names OCUTALON_EXTRA_CA_FILE")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ file, "and the path")

	Set before = ..State()
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Do $$$AssertTrue(..EntryJson("OcuTalon"_$Extract(item, 1, $Length(item) - 5)) '= "", "the entry of "_item_" exists before the runs")
		Do $$$AssertTrue(..Row(item) '= "", "and so does its ProviderConfig row")
	}
	Set sc = $ClassMethod(provider, "Apply", "http://host/v2/", "", "1")
	Do $$$AssertStatusNotOK(sc, "the step fails for a bad base URL")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_MODEL_BASE_URL", "naming the variable")
	Do $$$AssertEquals(..State(), before, "and writes nothing")
	Set sc = $ClassMethod(provider, "Apply", ..#MOCKURL, file, "1")
	Do $$$AssertStatusNotOK(sc, "the step fails for a missing CA file")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("OCUTALON_EXTRA_CA_FILE names a file that does not exist: "_file), "naming the variable and the path")
	Do $$$AssertEquals(..State(), before, "and writes nothing")
}

/// A CA file that exists, given to Apply, reaches every entry: the stored entry is the entry of Details for the file, with the
/// tls block of http_config and both accept_invalid_* flags false. A run from the environment then puts the entries back.
Method TestApplyCaFile()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	Set url = $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")
	Set flag = $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")
	Set file = ##class(%File).TempFilename("pem")
	Set before = ..State()
	Do $$$AssertTrue(before '= "", "the state is read before the run")
	Try {
		Do $$$AssertStatusOK($ClassMethod(provider, "Apply", url, file, flag), "Apply accepts a CA file that exists")
		For class = "OcuTalon.Agent.Triage", "OcuTalon.Agent.Diagnosis", "OcuTalon.Agent.Chat" {
			Set name = "OcuTalon"_$Piece(class, ".", $Length(class, "."))
			Set stored = ..EntryJson(name)
			Do $$$AssertEquals(stored, $ClassMethod(provider, "Details", class, url, file, flag).%ToJSON(), name_" is the entry of Details for the file")
			Set tls = {}.%FromJSON(stored)."http_config".tls
			Do $$$AssertEquals(tls."ca_certificates".%Get(0), file, name_" lists the file as its CA certificate")
			Do $$$AssertEquals(tls."accept_invalid_certs", 0, name_" accepts no invalid certificate")
			Do $$$AssertEquals(tls."accept_invalid_hostnames", 0, name_" accepts no invalid host name")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK($ClassMethod(provider, "Run"), "a run from the environment puts the entries back")
	Do $$$AssertEquals(..State(), before, "and the entries and rows are as they were")
}

/// After the start, each runner has the entry of Details for this environment, with the default resources, and its
/// ProviderConfig row names the entry.
Method TestEntries()
{
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(..#PRODUCTION, .runners)
	Do $$$AssertStatusOK(sc, "the runners are read")
	Do $$$AssertEquals(runners, 3, "there are three runners")
	Do $$$AssertStatusOK(##class(%AI.Utils.SettingStore).RegisterDefaults(), "the setting stores are registered")
	Set names = ""
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		Set class = $List(runners(i), 2)
		Set name = "OcuTalon"_$Piece(class, ".", $Length(class, "."))
		Set names = names _ $Select(names = "": "", 1: ",") _ name
		Set fqn = "AI.LLM."_name
		Do $$$AssertTrue(##class(%ConfigStore.Configuration).Exists(fqn), item_" has the entry "_fqn)
		Set sc = ##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 0)
		Do $$$AssertStatusOK(sc, "the entry "_fqn_" is read")
		If $$$ISERR(sc) Continue
		Do $$$AssertEquals(details.%ToJSON(), ..ForEnv(class).%ToJSON(), fqn_" is the entry of Details for this environment")
		Do $$$AssertTrue('details.%IsDefined("model"), fqn_" has no model")
		Do $$$AssertEquals(details."api_key", ..#PLACEHOLDER, fqn_" holds the literal placeholder")
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Get(fqn, .entry), fqn_" is opened")
		If $IsObject($Get(entry)) {
			Do $$$AssertTrue(entry.ReadResource [ "%Admin_ConfigStore", fqn_" keeps the default read resource: "_entry.ReadResource)
			Do $$$AssertTrue(entry.EditResource [ "%Admin_ConfigStore", fqn_" keeps the default edit resource: "_entry.EditResource)
		}
		Set row = ..Row(item)
		Do $$$AssertEquals(row, "@{config:"_name_"}", item_"'s ProviderConfig row names the entry")
		Set expanded = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand(row))
		Do $$$AssertEquals(expanded."api_key", ..#PLACEHOLDER, "and expands to the entry with the key still a placeholder")
	}
	Do $$$AssertEquals(names, "OcuTalonTriage,OcuTalonDiagnosis,OcuTalonChat", "the entries are those of the three agents, in the order of the runners")
}

/// Stale fields in the Triage entry are gone after Run(): the entry is modified, where a create would fail.
Method TestRerun()
{
	Set fqn = "AI.LLM.OcuTalonTriage"
	Set expected = ..ForEnv("OcuTalon.Agent.Triage").%ToJSON()
	Set found = ##class(%ConfigStore.Configuration).Exists(fqn)
	Do $$$AssertTrue(found, "the Triage entry exists")
	If 'found Quit
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(fqn, .snapshot, 0, 0), "the entry is read")
	Try {
		Set stale = {}.%FromJSON(snapshot.%ToJSON())
		Do stale.%Set("model", "claude-opus-stale")
		Do stale.%Set("base_url", "http://stale.invalid/v1/")
		Do stale.%Set("api_key", "ocutalon-stale-typed-value")
		Do stale.%Set("http_config", {"custom_headers": {"x-ocutalon-mockkey": "stale"}})
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Modify(fqn, stale), "stale fields are written into the entry")
		Do $$$AssertTrue(..EntryJson("OcuTalonTriage") [ "claude-opus-stale", "the entry now holds the stale model")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "Run() modifies the existing entries")
		Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), expected, "and the details are exactly the computed object again")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..RestoreEntry("OcuTalonTriage", snapshot)
	Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), snapshot.%ToJSON(), "the entry is as it was found")
}

/// With the Triage entry and its row deleted, Run() writes both. The row is validated against the entry, so it only saves
/// when the entry is written first.
Method TestEntryBeforeSetting()
{
	Set fqn = "AI.LLM.OcuTalonTriage"
	Set id = ..#PRODUCTION_"||TriageAgent||*||ProviderConfig"
	Set found = ##class(%ConfigStore.Configuration).Exists(fqn) && ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	Do $$$AssertTrue(found, "the Triage entry and its ProviderConfig row exist")
	If 'found Quit
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(fqn, .snapshot, 0, 0), "the entry is read")
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Set rowValue = row.SettingValue
	Set rowDescription = row.Description
	Try {
		Do $$$AssertStatusOK(##class(Ens.Config.DefaultSettings).%DeleteId(id), "the row is deleted")
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Delete(fqn), "and the entry")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "Run() writes both again")
		Do $$$AssertTrue(##class(%ConfigStore.Configuration).Exists(fqn), "the entry is back")
		Do $$$AssertEquals(..Row("TriageAgent"), "@{config:OcuTalonTriage}", "and so is the row")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..RestoreEntry("OcuTalonTriage", snapshot)
	Do ..RestoreRow(id, rowValue, rowDescription)
	Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), snapshot.%ToJSON(), "the entry is as it was found")
	Do $$$AssertEquals(..Row("TriageAgent"), rowValue, "and so is the row")
}

/// --- helpers ---
/// Details of the Provider step for an agent class under the overrides given, none by default. The builder reads no
/// environment.
ClassMethod Pure(class As %String, url As %String = "", file As %String = "", flag As %String = "") As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Provider).Details(class, url, file, flag)
}

/// Details of the Provider step for an agent class under the overrides of this environment.
ClassMethod ForEnv(class As %String) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Provider).Details(class, $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_EXTRA_CA_FILE"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"))
}

/// Asserts that the object is, field for field and in order, the JSON text.
Method Expect(label As %String, actual As %DynamicObject, json As %String) [ Private ]
{
	Do $$$AssertEquals(actual.%ToJSON(), {}.%FromJSON(json).%ToJSON(), label)
}

/// The details of an entry of AI.LLM as JSON text, or "" when there is no such entry.
ClassMethod EntryJson(name As %String) As %String [ Private ]
{
	If $$$ISERR(##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_name, .details, 0, 0)) Quit ""
	Quit details.%ToJSON()
}

/// The value of the ProviderConfig row of a runner, or "" when there is none.
ClassMethod Row(item As %String) As %String [ Private ]
{
	Set id = ..#PRODUCTION_"||"_item_"||*||ProviderConfig"
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit ""
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// Every entry and row that the step writes, as one text.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Set name = "OcuTalon"_$Extract(item, 1, $Length(item) - 5)
		Set state = state _ $Char(10) _ name _ " " _ ..EntryJson(name) _ " " _ ..Row(item)
	}
	Quit state
}

/// Puts an entry back as it was found: modified when it exists, created otherwise.
ClassMethod RestoreEntry(name As %String, details As %DynamicObject) [ Private ]
{
	If '$IsObject($Get(details)) Quit
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_name) {
		Do ##class(%ConfigStore.Configuration).Modify("AI.LLM."_name, details)
	} Else {
		Do ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", name, details)
	}
}

/// Puts a ProviderConfig row back as it was found.
ClassMethod RestoreRow(id As %String, value As %String, description As %String) [ Private ]
{
	Set row = $Select(##class(Ens.Config.DefaultSettings).%ExistsId(id): ##class(Ens.Config.DefaultSettings).%OpenId(id), 1: ##class(Ens.Config.DefaultSettings).%New())
	If 'row.%Id() {
		Set row.ProductionName = $Piece(id, "||", 1)
		Set row.ItemName = $Piece(id, "||", 2)
		Set row.HostClassName = "*"
		Set row.SettingName = $Piece(id, "||", 4)
	}
	Set row.SettingValue = value
	Set row.Description = description
	Do row.%Save()
}

}
