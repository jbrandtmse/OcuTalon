/// The Provider step (AD-19, AD-23): the only install-time writer of the Config Store entries of the agent runners, one
/// AI.LLM.OcuTalon<Agent> entry per runner of OcuTalon.Production, where <Agent> is the last part of the runner's agent
/// class name (AI.LLM.OcuTalonTriage). It then writes each runner's ProviderConfig setting, @{config:OcuTalon<Agent>}.
/// An entry holds the provider, the key placeholder @{env:ANTHROPIC_API_KEY} and the endpoint overrides of the environment,
/// and never a model (the model is the runner's Model setting, AD-7) and never a key: the placeholder stays unresolved
/// through the Config Store and AI Hub's provider resolves it. No code here reads the key's value.
/// Every value the step writes is structural: it is rewritten whole at every start, so a stale field disappears, and every
/// entry gets the Config Store's default read and edit resource, %Admin_ConfigStore, again.
/// The overrides, read from the environment at every start (AD-19, DW-39):
///   - OCUTALON_MODEL_BASE_URL: becomes base_url; it must be http(s)://host/... with no user name, query or fragment, and end
///     with /v1/;
///   - OCUTALON_EXTRA_CA_FILE: a file that exists; becomes the tls block of http_config;
///   - OCUTALON_MOCK_KEY_HEADER: only the text 1 adds the header x-ocutalon-mockkey, with the MOCKKEY of the agent class,
///     to custom_headers of http_config; the base URL alone never adds it.
/// The order of a run: RebuildRegistry first (a fresh instance has no descriptor for AI.LLM until then), the overrides
/// are checked (a bad one fails the step, and no entry or row is written), then for each runner its entry is written
/// (Modify when it exists, Create otherwise), checked to exist, and only then is its ProviderConfig row written, because
/// the row's validation expands @{config:}.
Class OcuTalon.Install.Step.Provider Extends OcuTalon.Install.Step
{

/// The area and type of the entries.
Parameter ENTRYPREFIX = "AI.LLM.";

/// The prefix of an entry's name, before the last part of the agent class name.
Parameter NAMEPREFIX = "OcuTalon";

/// The key placeholder of every entry.
Parameter KEYPLACEHOLDER = "@{env:ANTHROPIC_API_KEY}";

/// The header that carries an agent's MOCKKEY to the CI mock (AD-22).
Parameter MOCKKEYHEADER = "x-ocutalon-mockkey";

/// The environment variable of the base URL.
Parameter BASEURLVARIABLE = "OCUTALON_MODEL_BASE_URL";

/// The environment variable of the extra CA file.
Parameter CAFILEVARIABLE = "OCUTALON_EXTRA_CA_FILE";

/// The environment variable of the mock-key header switch.
Parameter MOCKKEYVARIABLE = "OCUTALON_MOCK_KEY_HEADER";

/// The read and edit resource of every entry: the Config Store's default (AD-19).
Parameter ENTRYRESOURCE = "%Admin_ConfigStore";

/// An ICU pattern of a base URL: http or https, a host with no user name, any path with no query or fragment, and a last
/// segment /v1/. It keeps a user name and password, a query and a fragment out of an entry; it does not judge the path.
Parameter URLPATTERN = "^(?i:https?)://[^/\s@?#]+/([^\s@?#]*/)?v1/\z";

/// Writes the entries and the ProviderConfig rows from the environment of the process.
ClassMethod Run() As %Status
{
	Quit ..Apply($SYSTEM.Util.GetEnviron(..#BASEURLVARIABLE), $SYSTEM.Util.GetEnviron(..#CAFILEVARIABLE), $SYSTEM.Util.GetEnviron(..#MOCKKEYVARIABLE))
}

/// The run of the step for given values of the three environment variables: RebuildRegistry, the checks of the overrides,
/// and then, for each runner, its entry and its ProviderConfig row. Fails at the first error; a failed check of an
/// override writes no entry and no row.
ClassMethod Apply(baseUrl As %String, caFile As %String, mockKeyFlag As %String) As %Status
{
	Set sc = ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
	If $$$ISERR(sc) Quit sc
	Set sc = ..CheckBaseUrl(baseUrl)
	If $$$ISOK(sc) Set sc = ..CheckCaFile(caFile)
	If $$$ISERR(sc) Quit sc
	Set production = ##class(OcuTalon.Install.Step.Production).#PRODUCTION
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(production, .runners)
	For i = 1:1:runners {
		If $$$ISERR(sc) Quit
		Set sc = ..WriteRunner(production, $List(runners(i), 1), $List(runners(i), 2), $List(runners(i), 3), baseUrl, caFile, mockKeyFlag)
	}
	Quit sc
}

/// The details of the entry of an agent class: the provider anthropic and the key placeholder, and then only what an
/// override asks for. The model is never in it.
///   - baseUrl, when not empty, is base_url;
///   - caFile, when not empty, is the tls block of http_config: ca_certificates with the path, and both accept_invalid_*
///     flags false;
///   - mockKeyFlag exactly the text 1 adds the agent class's MOCKKEY to custom_headers of http_config under MOCKKEYHEADER,
///     whatever the base URL is; an agent class with no MOCKKEY adds none.
/// A pure method: it reads no environment and checks no file.
ClassMethod Details(agentClass As %String, baseUrl As %String = "", caFile As %String = "", mockKeyFlag As %String = "") As %DynamicObject
{
	Set details = {"model_provider": "anthropic", "api_key": (..#KEYPLACEHOLDER)}
	If baseUrl '= "" Do details.%Set("base_url", baseUrl)
	Set httpConfig = {}
	Set mockKey = $Select(##class(%Dictionary.CompiledClass).%ExistsId(agentClass): $Parameter(agentClass, "MOCKKEY"), 1: "")
	If (mockKeyFlag = "1") && (mockKey '= "") {
		Do httpConfig.%Set("custom_headers", {})
		Do httpConfig."custom_headers".%Set(..#MOCKKEYHEADER, mockKey)
	}
	If caFile '= "" {
		Do httpConfig.%Set("tls", {"ca_certificates": [(caFile)], "accept_invalid_certs": false, "accept_invalid_hostnames": false})
	}
	If httpConfig.%Size() > 0 Do details.%Set("http_config", httpConfig)
	Quit details
}

/// OK for an empty base URL (no override) and for one that is http(s)://host/.../v1/; otherwise an error that names
/// OCUTALON_MODEL_BASE_URL and never holds its value.
ClassMethod CheckBaseUrl(baseUrl As %String) As %Status
{
	If (baseUrl = "") || $Match(baseUrl, ..#URLPATTERN) Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.Status.Error(5001, ..#BASEURLVARIABLE_" must be an http:// or https:// address with a host, with no user name, query or fragment, that ends with /v1/, for example http://mock:8080/v1/")
}

/// OK for an empty path (no override) and for a file that exists; otherwise an error that names OCUTALON_EXTRA_CA_FILE
/// and the path.
ClassMethod CheckCaFile(caFile As %String) As %Status
{
	If (caFile = "") || ##class(%File).Exists(caFile) Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.Status.Error(5001, ..#CAFILEVARIABLE_" names a file that does not exist: "_caFile)
}

/// The name of the entry of an agent class, without the area and type: OcuTalon plus the last part of the class name.
ClassMethod EntryName(agentClass As %String) As %String
{
	Quit ..#NAMEPREFIX_$Piece(agentClass, ".", $Length(agentClass, "."))
}

/// Writes one runner's entry with the default resources, checks that it exists, and then writes the runner's ProviderConfig
/// row. A runner that is disabled and has no usable agent class gets neither; an enabled one fails the step by name.
ClassMethod WriteRunner(production As %String, item As %String, agentClass As %String, enabled As %Boolean, baseUrl As %String, caFile As %String, mockKeyFlag As %String) As %Status [ Private ]
{
	If (agentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) || '$ClassMethod(agentClass, "%Extends", "%AI.Agent") {
		If 'enabled Quit $SYSTEM.Status.OK()
		Quit $SYSTEM.Status.Error(5001, "The runner "_item_" has no usable agent class: its AgentClass is '"_agentClass_"'")
	}
	Set name = ..EntryName(agentClass)
	Set fqn = ..#ENTRYPREFIX_name
	Set details = ..Details(agentClass, baseUrl, caFile, mockKeyFlag)
	If ##class(%ConfigStore.Configuration).Exists(fqn) {
		Set sc = ##class(%ConfigStore.Configuration).Modify(fqn, details, , , ..#ENTRYRESOURCE, ..#ENTRYRESOURCE)
	} Else {
		Set sc = ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", name, details, "", "Written by the Provider install step at every start; do not edit.", ..#ENTRYRESOURCE, ..#ENTRYRESOURCE)
	}
	If $$$ISERR(sc) Quit sc
	If '##class(%ConfigStore.Configuration).Exists(fqn) {
		Quit $SYSTEM.Status.Error(5001, "The Config Store entry "_fqn_" does not exist after it was written")
	}
	Quit ##class(OcuTalon.Install.Step.Production).WriteDefault(production, item, "ProviderConfig", "@{config:"_name_"}", "Written by the Provider install step at every start; do not edit.")
}

}
