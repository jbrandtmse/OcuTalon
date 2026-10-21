/// Tests of the Provider installer step run the way the after-start script runs it (Story 1.1; AD-19, DW-39): Run() reads
/// OCUTALON_MODEL_BASE_URL, OCUTALON_EXTRA_CA_FILE and OCUTALON_MOCK_KEY_HEADER from the environment of the process, and each
/// runner's stored entry and ProviderConfig row are what the matrix says for that environment. The expected entries are written
/// out here as JSON text, not taken from the step's builder. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it sets
/// and removes the three variables in the process, rewrites the entries AI.LLM.OcuTalonTriage, ...Diagnosis and ...Chat and the
/// ProviderConfig rows of OcuTalon.Production, and puts the variables, the entries and the rows back, a missing one as missing.
///   - TestJudgesInstall: no variable set; each entry is the provider and the key placeholder alone, with no base_url and no
///     http_config;
///   - TestFlagAlone: the flag 1 alone; each entry has the header with its agent's own mock key and no base_url;
///   - TestBaseUrlAlone: the base URL with the flag unset, 0, true, " 1" or "1 "; each entry has base_url and no header;
///   - TestCiEnvironment: the base URL and the flag 1; each entry has base_url and the header with its agent's own mock key;
///   - TestCaFileFromEnvironment: a CA file that exists; each entry has the tls block with both accept_invalid_* flags false;
///   - TestBadEnvironment: a base URL that is not http(s)://host/.../v1/ and a CA file that does not exist each fail Run(), naming
///     the variable, and leave every entry and row as they were;
///   - TestDescriptions: an entry that Run() creates and the rows that it writes say that the step writes them at every start.
Class OcuTalon.Test.Install.ProviderEnv Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The last part of the agent class names, in the order of the runners.
Parameter AGENTS = "Triage,Diagnosis,Chat";

/// The three environment variables of the step.
Parameter VARIABLES = "OCUTALON_MODEL_BASE_URL,OCUTALON_EXTRA_CA_FILE,OCUTALON_MOCK_KEY_HEADER";

/// A base URL that is not the CI mock's, so that the value is shown to come from the environment.
Parameter URL = "http://env-test.invalid/v1/";

/// The environment variables as the test found them: for each, present (1 or 0) and value.
Property Env As %DynamicObject;

/// The entries and rows as the test found them, by agent.
Property Saved As %DynamicObject;

/// With no override, each entry is exactly the provider and the key placeholder.
Method TestJudgesInstall()
{
	Set before = ..Begin()
	Try {
		Do $$$AssertStatusOK(..RunWith("", "", ""), "Run() accepts an environment with no override")
		Do ..ExpectStored("the judges' install", "", 0, "")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// The flag 1 alone gives the header and no base_url.
Method TestFlagAlone()
{
	Set before = ..Begin()
	Try {
		Do $$$AssertStatusOK(..RunWith("", "", "1"), "Run() accepts the flag alone")
		Do ..ExpectStored("the flag alone", "", 1, "")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// A base URL with any value of the flag but exactly 1 gives base_url and no header.
Method TestBaseUrlAlone()
{
	Set before = ..Begin()
	Try {
		For flag = "", "0", "true", " 1", "1 " {
			Do $$$AssertStatusOK(..RunWith(..#URL, "", flag), "Run() accepts the base URL with the flag '"_flag_"'")
			Do ..ExpectStored("a base URL with the flag '"_flag_"'", ..#URL, 0, "")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// The base URL and the flag 1 give base_url and the header.
Method TestCiEnvironment()
{
	Set before = ..Begin()
	Try {
		Do $$$AssertStatusOK(..RunWith(..#URL, "", "1"), "Run() accepts the base URL with the flag 1")
		Do ..ExpectStored("the CI environment", ..#URL, 1, "")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// A CA file that exists gives the tls block; with the base URL and the flag it comes with them.
Method TestCaFileFromEnvironment()
{
	Set before = ..Begin()
	Set file = ##class(%File).TempFilename("pem")
	Try {
		Do $$$AssertTrue(##class(%File).Exists(file), "the CA file exists")
		Do $$$AssertStatusOK(..RunWith("", file, ""), "Run() accepts a CA file that exists")
		Do ..ExpectStored("a CA file", "", 0, file)
		Do $$$AssertStatusOK(..RunWith(..#URL, file, "1"), "Run() accepts a CA file with the base URL and the flag")
		Do ..ExpectStored("a CA file with the base URL and the flag", ..#URL, 1, file)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(%File).Delete(file)
	Do ..End(before)
}

/// A bad base URL and a missing CA file fail Run() and write nothing: every entry and row stays as the good run left it.
Method TestBadEnvironment()
{
	Set before = ..Begin()
	Set file = ##class(%File).TempFilename("pem")
	Do ##class(%File).Delete(file)
	Try {
		Do $$$AssertStatusOK(..RunWith("", "", ""), "Run() accepts an environment with no override")
		Set good = ..State()
		For agent = "Triage", "Diagnosis", "Chat" {
			Do $$$AssertTrue(..EntryJson(agent) '= "", "the entry of "_agent_" exists before the bad runs")
			Do $$$AssertTrue(..Row(agent) '= "", "and so does its ProviderConfig row")
		}
		Set sc = ..RunWith("http://env-test.invalid/v2/", "", "1")
		Do $$$AssertStatusNotOK(sc, "Run() fails for a base URL that does not end in /v1/")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_MODEL_BASE_URL", "naming the variable")
		Do $$$AssertEquals(..State(), good, "and writes nothing")
		Set sc = ..RunWith(..#URL, file, "1")
		Do $$$AssertStatusNotOK(sc, "Run() fails for a CA file that does not exist")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("OCUTALON_EXTRA_CA_FILE names a file that does not exist: "_file), "naming the variable and the path")
		Do $$$AssertEquals(..State(), good, "and writes nothing")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// A created entry and the rows say that the step writes them at every start.
Method TestDescriptions()
{
	Set before = ..Begin()
	Try {
		Set id = ..RowId("Triage")
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
		If ##class(%ConfigStore.Configuration).Exists("AI.LLM.OcuTalonTriage") Do ##class(%ConfigStore.Configuration).Delete("AI.LLM.OcuTalonTriage")
		Do $$$AssertTrue('##class(%ConfigStore.Configuration).Exists("AI.LLM.OcuTalonTriage"), "the Triage entry is deleted")
		Do $$$AssertStatusOK(..RunWith("", "", ""), "Run() creates it again")
		Do $$$AssertTrue(..EntryDescription("Triage") [ "every start", "the entry that was created says that the step writes it at every start: "_..EntryDescription("Triage"))
		For agent = "Triage", "Diagnosis", "Chat" {
			Do $$$AssertTrue(..RowDescription(agent) [ "every start", "the ProviderConfig row of "_agent_" says that the step writes it at every start: "_..RowDescription(agent))
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..End(before)
}

/// --- helpers ---
/// Takes the environment, the entries and the rows as found, and returns the state text.
Method Begin() As %String [ Private ]
{
	Set ..Env = {}
	Set ..Saved = {}
	Set list = $ListFromString(..#VARIABLES)
	Set position = 0
	While $ListNext(list, position, variable) {
		Do ..Env.%Set(variable, {"present": (+##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable)), "value": ($SYSTEM.Util.GetEnviron(variable))})
	}
	Set list = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(list, position, agent) {
		Set one = {}
		Set fqn = "AI.LLM.OcuTalon"_agent
		If ##class(%ConfigStore.Configuration).Exists(fqn) {
			Do ##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 0)
			Do one.%Set("entry", details)
			Do one.%Set("description", ..EntryDescription(agent))
		}
		If ##class(Ens.Config.DefaultSettings).%ExistsId(..RowId(agent)) {
			Do one.%Set("row", ..Row(agent))
			Do one.%Set("rowDescription", ..RowDescription(agent))
		}
		Do ..Saved.%Set(agent, one)
	}
	Quit ..State()
}

/// Puts the environment, the entries and the rows back, and asserts that they are as Begin found them.
Method End(before As %String) [ Private ]
{
	Do ..Restore()
	Do $$$AssertEquals(..State(), before, "the entries and rows are as they were found")
	Set list = $ListFromString(..#VARIABLES)
	Set position = 0
	While $ListNext(list, position, variable) {
		Set was = ..Env.%Get(variable)
		Do $$$AssertEquals(+##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable), was.present, variable_" is set as it was found")
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), was.value, variable_" has the value it had")
	}
}

/// Puts back what Begin took, and does nothing when it took nothing. The row is removed or written around the entry, because
/// writing a row validates it against the entry.
Method Restore() [ Private ]
{
	If '$IsObject(..Env) || '$IsObject(..Saved) Quit
	Set list = $ListFromString(..#VARIABLES)
	Set position = 0
	While $ListNext(list, position, variable) {
		Set was = ..Env.%Get(variable)
		If was.present {
			Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, was.value)
		} Else {
			Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
		}
	}
	Set list = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(list, position, agent) {
		Set one = ..Saved.%Get(agent)
		Set fqn = "AI.LLM.OcuTalon"_agent
		Set id = ..RowId(agent)
		If 'one.%IsDefined("row") && ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
		If one.%IsDefined("entry") {
			Do ##class(OcuTalon.Test.Install.Provider).RestoreEntry("OcuTalon"_agent, one.entry, one.description)
		} ElseIf ##class(%ConfigStore.Configuration).Exists(fqn) {
			Do ##class(%ConfigStore.Configuration).Delete(fqn)
		}
		If one.%IsDefined("row") Do ##class(OcuTalon.Test.Install.Provider).RestoreRow(id, one.row, one.rowDescription)
	}
}

/// Sets the three variables in the process (an empty value removes the variable), checks that the process sees them, and
/// runs the step.
Method RunWith(url As %String, file As %String, flag As %String) As %Status [ Private ]
{
	Set values = $ListBuild(url, file, flag)
	Set list = $ListFromString(..#VARIABLES)
	Set position = 0
	Set i = 0
	While $ListNext(list, position, variable) {
		Set i = i + 1
		Set value = $List(values, i)
		If value = "" {
			Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
		} Else {
			Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, value)
		}
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), value, variable_" is '"_value_"' in the process")
	}
	Quit ##class(OcuTalon.Install.Step.Provider).Run()
}

/// Asserts that each runner's stored entry is the JSON text of Entry(...) and that its ProviderConfig row names the entry.
Method ExpectStored(label As %String, url As %String, header As %Boolean, file As %String) [ Private ]
{
	Set list = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(list, position, agent) {
		Do $$$AssertEquals(..EntryJson(agent), {}.%FromJSON(..Entry(agent, url, header, file)).%ToJSON(), label_": the entry of "_agent)
		Do $$$AssertEquals(..Row(agent), "@{config:OcuTalon"_agent_"}", label_": the ProviderConfig row of "_agent)
	}
}

/// The JSON text of the entry that the matrix gives an agent: the provider and the placeholder, base_url when there is a URL,
/// and http_config with the agent's mock key header when header is 1 and the tls block when there is a CA file. The agent's
/// mock key is its name in lower case.
ClassMethod Entry(agent As %String, url As %String, header As %Boolean, file As %String) As %String [ Private ]
{
	Set json = "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"""
	If url '= "" Set json = json _ ",""base_url"":""" _ url _ """"
	If header || (file '= "") {
		Set parts = ""
		If header Set parts = """custom_headers"":{""x-ocutalon-mockkey"":""" _ $ZConvert(agent, "L") _ """}"
		If file '= "" Set parts = parts _ $Select(parts = "": "", 1: ",") _ """tls"":{""ca_certificates"":[""" _ file _ """],""accept_invalid_certs"":false,""accept_invalid_hostnames"":false}"
		Set json = json _ ",""http_config"":{" _ parts _ "}"
	}
	Quit json _ "}"
}

/// The details of an agent's entry as JSON text, or "" when there is no such entry.
ClassMethod EntryJson(agent As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Install.Provider).EntryJson("OcuTalon"_agent)
}

/// The description of an agent's entry, or "" when there is no such entry.
ClassMethod EntryDescription(agent As %String) As %String [ Private ]
{
	If $$$ISERR(##class(%ConfigStore.Configuration).Get("AI.LLM.OcuTalon"_agent, .config)) Quit ""
	Quit config.Description
}

/// The id of an agent's ProviderConfig row.
ClassMethod RowId(agent As %String) As %String [ Private ]
{
	Quit ..#PRODUCTION_"||"_agent_"Agent||*||ProviderConfig"
}

/// The value of an agent's ProviderConfig row, or "" when there is none.
ClassMethod Row(agent As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Install.Provider).Row(agent_"Agent")
}

/// The description of an agent's ProviderConfig row, or "" when there is none.
ClassMethod RowDescription(agent As %String) As %String [ Private ]
{
	If '##class(Ens.Config.DefaultSettings).%ExistsId(..RowId(agent)) Quit ""
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(..RowId(agent)).Description
}

/// Every entry and row that the step writes, with their descriptions, as one text.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	Set list = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(list, position, agent) {
		Set state = state _ $Char(10) _ agent _ " " _ ..EntryJson(agent) _ " [" _ ..EntryDescription(agent) _ "] " _ ..Row(agent) _ " [" _ ..RowDescription(agent) _ "]"
	}
	Quit state
}

}
