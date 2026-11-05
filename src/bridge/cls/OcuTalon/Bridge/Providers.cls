/// The provider table of the bridge (AD-7, AD-8, AD-19): the fixed list of the providers that an agent can be configured for, in the order
/// that resolution tries them; an agent runs only on a provider whose supported flag is set. Each row holds the provider's name, its default model (its cheap tier), the models that can be selected, the
/// environment variable that holds its key and the supported flag.
///   - The key variable is the only form in which a key reaches a provider: the entry holds @{env:<the variable>} and AI Hub resolves
///     it inside its provider. This class asks only whether a variable is set (KeySet) and never reads, returns, stores or logs a value.
///   - The supported flag says that the provider has been tried by hand with a real key. A flag is set to 1 only by the Release check
///     (REL-7), never by a story: a provider that is not supported is never offered for a model change, and resolution never picks it.
///   - Every selectable model has a Price row (Installer.Prices).
/// Resolution (AD-7, AD-8) is what a runner does when its own key is missing, before it falls back with no_key. It applies to any runner
/// item, the retry runners included, and only when the item's entry key is absent (Keys.State) and its model is its agent class's own
/// MODEL, the default. The runner then uses the first row in table order that is not the entry's own provider, is supported and has its key
/// variable set, on that row's default model, with an in-memory configuration: the entry's details with model_provider and api_key
/// replaced (Resolve). Nothing is written. An unknown key state never resolves, and neither does a model that an admin chose.
/// Rows reads the Table of the class it is called on, so that a test class can replace the table. This class names no other OcuTalon
/// package (AD-2).
Class OcuTalon.Bridge.Providers
{

/// The rows, in order: provider, defaultModel, models (the selectable ones), keyVariable and supported. Bedrock's region comes from
/// AWS_REGION inside AI Hub.
XData Table [ MimeType = application/json ]
{
[
 {"provider": "anthropic", "defaultModel": "claude-haiku-5-5", "models": ["claude-haiku-5-5", "claude-sonnet-5-5"], "keyVariable": "ANTHROPIC_API_KEY", "supported": true},
 {"provider": "openai", "defaultModel": "gpt-5.4-mini", "models": ["gpt-5.4-mini", "gpt-5.4"], "keyVariable": "OPENAI_API_KEY", "supported": false},
 {"provider": "gemini", "defaultModel": "gemini-3.1-flash-lite", "models": ["gemini-3.1-flash-lite", "gemini-3.1-pro-preview"], "keyVariable": "GEMINI_API_KEY", "supported": false},
 {"provider": "bedrock", "defaultModel": "us.anthropic.claude-haiku-5-5", "models": ["us.anthropic.claude-haiku-5-5", "us.anthropic.claude-sonnet-5-5"], "keyVariable": "AWS_BEARER_TOKEN_BEDROCK", "supported": false}
]
}

/// The rows of the Table of the class this method is called on, as a dynamic array of objects; an empty array when the table cannot be read.
ClassMethod Rows() As %DynamicArray
{
	Set rows = []
	Try {
		Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Table")
		If $IsObject(xdata) Set rows = [].%FromJSON(xdata.Data)
	} Catch {
		Set rows = []
	}
	Quit rows
}

/// The row of the provider as a dynamic object, or "" when the table has none.
ClassMethod Row(provider As %String) As %DynamicObject
{
	Set found = ""
	Set provider = $Get(provider)
	If provider = "" Quit ""
	Set iterator = ..Rows().%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.%Get("provider") = provider {
			Set found = row
			Quit
		}
	}
	Quit found
}

/// 1 when the key variable of the provider is not empty in this process. It tests presence only and never returns a value. 0 for a provider that
/// the table does not have.
ClassMethod KeySet(provider As %String) As %Boolean
{
	Set row = ..Row($Get(provider))
	If '$IsObject(row) Quit 0
	Quit ..VariableSet(row.%Get("keyVariable"))
}

/// 1 when the environment variable is not empty in this process (presence only).
ClassMethod VariableSet(variable As %String) As %Boolean [ Private ]
{
	If $Get(variable) = "" Quit 0
	Quit $SYSTEM.Util.GetEnviron(variable) '= ""
}

/// Chooses the provider that a runner resolves to (pure but for the presence of the key variables). rows is a dynamic array like Rows gives.
/// It chooses only when entryState is "absent" and isDefault is true, and then takes the first row in order whose provider is not
/// entryProvider, is supported and has its key variable set: provider and model (its default model) are set and the result is 1. In every
/// other case provider and model are empty and the result is 0.
ClassMethod Choose(rows As %DynamicArray, entryProvider As %String, entryState As %String, isDefault As %Boolean, Output provider As %String, Output model As %String) As %Boolean
{
	Set provider = ""
	Set model = ""
	If ($Get(entryState) '= "absent") || '$Get(isDefault) || '$IsObject($Get(rows)) Quit 0
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If row.%Get("provider") = $Get(entryProvider) Continue
		If 'row.%Get("supported") Continue
		If '..VariableSet(row.%Get("keyVariable")) Continue
		Set provider = row.%Get("provider")
		Set model = row.%Get("defaultModel")
		Quit
	}
	Quit provider '= ""
}

/// The provider that the runner item resolves to, or "" when it resolves to none. providerConfig is the item's ProviderConfig setting. On a
/// resolution, config is the in-memory provider configuration (a dynamic object: the entry's details with model_provider and api_key
/// replaced, the key as @{env:<the provider's variable>}) and model is the provider's default model; otherwise both are empty.
/// The item's agent class and its Model setting are read from the item of the production (an empty production is the active one) unless
/// agentClass is given, which a runner's adapter passes with its own Model, because a shadow runner is no item of the production. The model
/// is the default when the Model setting is empty or equals the MODEL of the agent class, and the agent class has a MODEL. It never throws
/// and reads no value of a key.
ClassMethod Resolve(item As %String, production As %String, providerConfig As %String, Output config As %DynamicObject, Output model As %String, agentClass As %String = "", configured As %String = "") As %String
{
	Set config = ""
	Set model = ""
	Set provider = ""
	Try {
		Set state = ##class(OcuTalon.Bridge.Keys).State($Get(providerConfig))
		If state '= "absent" Quit
		If agentClass = "" {
			If $Get(production) = "" Set production = ##class(Ens.Director).GetActiveProductionName()
			If (production = "") || ($Get(item) = "") Quit
			Set agentClass = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "AgentClass", .sc)
			If $$$ISERR(sc) Quit
			Set configured = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "Model", .sc)
			If $$$ISERR(sc) Quit
		}
		If (agentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) Quit
		If '$ClassMethod(agentClass, "%Extends", "%AI.Agent") Quit
		Set own = $Parameter(agentClass, "MODEL")
		Set isDefault = (own '= "") && ((configured = "") || (configured = own))
		Set details = ..EntryDetails($Get(providerConfig))
		Set entryProvider = $Select(details.%GetTypeOf("model_provider") = "string": details.%Get("model_provider"), 1: "")
		If '..Choose(..Rows(), entryProvider, state, isDefault, .chosen, .chosenModel) Quit
		Set row = ..Row(chosen)
		Do details.%Set("model_provider", chosen)
		Do details.%Set("api_key", "@{env:"_row.%Get("keyVariable")_"}")
		Set config = details
		Set model = chosenModel
		Set provider = chosen
	} Catch {
		Set config = ""
		Set model = ""
		Set provider = ""
	}
	Quit provider
}

/// A copy of the details of the provider configuration as a dynamic object: the Config Store entry that @{config:<name>} names, or the JSON
/// object, or {} for an empty configuration or one that cannot be read.
ClassMethod EntryDetails(providerConfig As %String) As %DynamicObject [ Private ]
{
	Set text = $ZStrip($Get(providerConfig), "<>WC")
	Set details = {}
	Set name = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(text)
	If name '= "" {
		If $$$ISOK(##class(OcuTalon.Bridge.ConfigStore).Details(name, .read)) && $IsObject(read) Set details = read
	} ElseIf $Extract(text) = "{" {
		Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(text)
		If $IsObject(object) && object.%IsA("%Library.DynamicObject") Set details = object
	}
	Quit {}.%FromJSON(details.%ToJSON())
}

}
