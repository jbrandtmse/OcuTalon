Include Ensemble

/// The model-key API (FR-38; AD-6, AD-19, AD-20). Status says whether a runner's model key is present, so that a start with no key shows
/// as such and Decide never sends a request that cannot be answered. It tests for presence only: the key is an environment variable
/// that the provider resolves inside AI Hub, and no method here returns, logs, stores or raises a value of it.
/// A key counts as absent only when the bridge can tell that it is: the runner's provider configuration is empty, names no Config Store
/// entry, or holds no api_key, or the api_key is exactly one environment placeholder (@{env:NAME}, ConfigStore KEYPATTERN) whose variable
/// is empty in this process. Every other form counts as present, a literal value, an entry that cannot be read and a configuration
/// that is neither an entry reference nor a JSON object included, so that the bridge never blocks a setup that it cannot judge: the
/// runner's own failure is classified then (Decide.Classify). This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Keys
{

/// 1 when the runner item has a model key, otherwise 0. agent is the name of the runner item in the active production (TriageAgent,
/// DiagnosisAgent or ChatAgent). It reads the ProviderConfig adapter setting of the item (Ens.Director.GetAdapterSettingValue, as
/// AgentRunner.ResolveModel does) and Present decides. It is 0 when there is no active production or no such item, and 1 when the
/// setting cannot be read for another reason. It returns 0 or 1 and never throws.
ClassMethod Status(agent As %String) As %Boolean
{
	Set present = 1
	Try {
		Set production = ##class(Ens.Director).GetActiveProductionName()
		If (production = "") || ($Get(agent) = "") {
			Set present = 0
		} Else {
			Set config = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_agent, "ProviderConfig", .sc)
			If $$$ISERR(sc) {
				If $SYSTEM.Status.Equals(sc, $$$EnsErrConfigItemNotFound) Set present = 0
			} Else {
				Set present = ..Present(config)
			}
		}
	} Catch {
		Set present = 1
	}
	Quit present
}

/// 1 when the provider configuration (the text of a ProviderConfig setting) has a key, otherwise 0.
///   - Empty: 0.
///   - @{config:<name>}: the Config Store entry AI.LLM.<name> is read without its secrets resolved (ConfigStore.Details). An entry
///     that does not exist is 0; one that cannot be read is 1; otherwise its api_key is judged as below.
///   - A JSON object: its api_key is judged. Missing or empty is 0. Exactly one @{env:NAME} placeholder is 1 when the environment
///     variable NAME is not empty in this process and 0 when it is. Any other value is 1: a literal value, or a form that this
///     method does not read.
///   - Anything else: 1.
/// It returns 0 or 1, never a value, and never throws.
ClassMethod Present(providerConfig As %String) As %Boolean
{
	Set present = 1
	Try {
		Set text = $ZStrip($Get(providerConfig), "<>WC")
		Set name = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(text)
		If text = "" {
			Set present = 0
		} ElseIf name '= "" {
			Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(name, .details)
			If $$$ISOK(sc) {
				Set present = ..KeyPresent(details)
			} Else {
				Set present = ##class(%ConfigStore.Configuration).Exists(##class(OcuTalon.Bridge.ConfigStore).FullName(name))
			}
		} ElseIf $Extract(text) = "{" {
			Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(text)
			If $IsObject(object) && object.%IsA("%Library.DynamicObject") Set present = ..KeyPresent(object)
		}
	} Catch {
		Set present = 1
	}
	Quit present
}

/// 1 when the api_key of the dynamic object is present (see Present), otherwise 0.
ClassMethod KeyPresent(object As %DynamicObject) As %Boolean [ Private ]
{
	Set type = object.%GetTypeOf("api_key")
	If (type = "unassigned") || (type = "null") Quit 0
	If type '= "string" Quit 1
	Set key = object.%Get("api_key")
	If $ZStrip(key, "<>WC") = "" Quit 0
	If '$Match(key, ##class(OcuTalon.Bridge.ConfigStore).#KEYPATTERN) Quit 1
	Quit $SYSTEM.Util.GetEnviron($Extract(key, 7, $Length(key) - 1)) '= ""
}

}
