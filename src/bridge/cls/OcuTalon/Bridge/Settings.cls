/// The one entry point of the bridge's settings for the settings operation (AD-19, AD-7, AD-18; Lane A). OcuTalon.Core.SettingsOps changes bridge
/// values only through this class. Providers, CheckModel and SetModel are built (Story 17.3). THE OTHER METHODS ARE STUBS until Story 17.4: every
/// method that returns a %Status answers "not implemented" (code 5003) and writes nothing, and every other method returns its empty value; each
/// signature is pinned in OcuTalon.Test.Contract.Ac. The built class will delegate to ConfigStore.Merge, Ext.Accessor.WriteDefault, Keys, Budget,
/// Data.Price, Timeouts and Time.SetZone, and will keep this contract:
///   - Providers: the provider table's rows in their fixed order (Providers), each {provider, defaultModel, models, keyVariable, keySet,
///     supported}: keySet says that the key variable is set in this process, and no key is ever returned;
///   - Values: DecisionTokenBudget, DailyCostCapUSD, InstanceZone, and for each agent its provider and model and its second model's;
///   - Check and Set: a value for one of DecisionTokenBudget, DailyCostCapUSD or InstanceZone (InstanceZone through Time.SetZone); Set returns the
///     value it replaced in old;
///   - CheckModel and SetModel: an agent's model, or its second model when second is 1. agent is the name of a first runner item: TriageAgent,
///     DiagnosisAgent or ChatAgent. The provider must be supported with its key variable set, and the model one that the provider table lists for
///     it. For a first model SetModel merges the agent's Config Store entry through ConfigStore.Merge with only the provider and
///     @{env:<its key variable>}, writes the runner's Model row, reads it back and restarts that runner item alone. For a second model it does the
///     same on the retry item <agent>Retry and then sets RetryItem of the first runner to that item; an empty provider and model sets RetryItem to
///     "" and leaves the retry item as it is. old holds {provider, model} that were replaced (and retryItem for a second model), never a key. A
///     failure after the first write puts back what was written. CheckModel changes nothing, and refuses with a plain-English reason an argument
///     that holds "@{", an agent outside the three, a provider that is not in the table, not supported or whose key variable is not set, a model
///     that the provider does not list, and an empty provider or model for a first model;
///   - SetPrice: the non-negative prices of a model in Data.Price, returning the replaced prices in old;
///   - TestRequest and TestAnswer: TestRequest builds one request of the agent's own kind (decide, diagnose or turn) with provenance untrusted,
///     owner instance, a fresh ItemId and a fixed code-written input, which the caller sends to Decide synchronously; TestAnswer reads the response
///     and returns {answered, seconds, reason}, the reason a fallback reason.
/// Every method refuses a value that holds "@{" or is off the allow-list, with a plain-English reason, and changes nothing; the bridge timer stays at
/// or under 110 seconds. The bridge references no OcuTalon package outside the bridge (AD-2).
Class OcuTalon.Bridge.Settings
{

/// The description of the System Default Settings row of Model that SetModel writes.
Parameter MODELROW = "Written by OcuTalon.Bridge.Settings.SetModel; the Production install step never overwrites it.";

/// The description of the System Default Settings row of RetryItem that SetModel writes.
Parameter RETRYROW = "Written by OcuTalon.Bridge.Settings.SetModel for a second model; the Production install step never overwrites it.";

/// The provider table's rows in their fixed order, as a dynamic array of {provider, defaultModel, models, keyVariable, keySet, supported}.
ClassMethod Providers() As %DynamicArray
{
	Set result = []
	Set iterator = ##class(OcuTalon.Bridge.Providers).Rows().%GetIterator()
	While iterator.%GetNext(, .row) {
		Set one = {}
		Do one.%Set("provider", row.%Get("provider"))
		Do one.%Set("defaultModel", row.%Get("defaultModel"))
		Do one.%Set("models", row.%Get("models"))
		Do one.%Set("keyVariable", row.%Get("keyVariable"))
		Do one.%Set("keySet", ##class(OcuTalon.Bridge.Providers).KeySet(row.%Get("provider")), "boolean")
		Do one.%Set("supported", +row.%Get("supported"), "boolean")
		Do result.%Push(one)
	}
	Quit result
}

/// The bridge values that the settings page shows, as a dynamic object. A stub: an empty object.
ClassMethod Values() As %DynamicObject
{
	Quit {}
}

/// Whether the value is acceptable for the named setting, without changing anything. A stub: not implemented.
ClassMethod Check(name As %String, value As %String) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

/// Stores the value of the named setting; old is the value it replaced. A stub: not implemented, nothing written, old empty.
ClassMethod Set(name As %String, value As %String, Output old As %String) As %Status
{
	Set old = ""
	Quit $$$ERROR($$$NotImplemented)
}

/// OK when the provider and model are acceptable for the agent's model, or its second model when second is 1, without changing anything;
/// otherwise an error whose plain-English reason names the argument and never holds its value. It refuses:
///   - an argument that holds @{;
///   - an agent that is not TriageAgent, DiagnosisAgent or ChatAgent;
///   - an empty provider or model for a first model, and for a second model one that is empty when the other is not (both empty clear the second model);
///   - a provider that is not in the table, is not supported, or whose key variable is not set;
///   - a model that the provider does not list.
ClassMethod CheckModel(agent As %String, provider As %String, model As %String, second As %Boolean = 0) As %Status
{
	Set agent = $Get(agent)
	Set provider = $Get(provider)
	Set model = $Get(model)
	Set names = $ListBuild("agent", "provider", "model")
	Set values = $ListBuild(agent, provider, model)
	For i = 1:1:3 {
		If $List(values, i) [ "@{" Return $$$ERROR($$$GeneralError, "The "_$List(names, i)_" is refused: a model change takes a plain name and never a placeholder")
	}
	If '$ListFind(..Agents(), agent) Return $$$ERROR($$$GeneralError, "The agent is not one that has a model to change: it must be "_$ListToString(..Agents(), ", "))
	If $Get(second) && (provider = "") && (model = "") Quit $$$OK
	If provider = "" Quit $$$ERROR($$$GeneralError, "The provider is empty: name one of the providers of the table"_$Select($Get(second): " (or leave both the provider and the model empty to stop using a second model)", 1: ""))
	Set row = ##class(OcuTalon.Bridge.Providers).Row(provider)
	If '$IsObject(row) Quit $$$ERROR($$$GeneralError, "The provider is not in the provider table")
	If 'row.%Get("supported") Quit $$$ERROR($$$GeneralError, "The provider "_provider_" is not supported yet, so no agent can run on it")
	If '##class(OcuTalon.Bridge.Providers).KeySet(provider) Quit $$$ERROR($$$GeneralError, "The key of the provider "_provider_" is not set: its environment variable "_row.%Get("keyVariable")_" is empty")
	If model = "" Quit $$$ERROR($$$GeneralError, "The model is empty: name a model of the provider "_provider)
	Set listed = 0
	Set iterator = row.%Get("models").%GetIterator()
	While iterator.%GetNext(, .name) {
		If name = model Set listed = 1
	}
	If 'listed Quit $$$ERROR($$$GeneralError, "The provider "_provider_" does not list that model")
	Quit $$$OK
}

/// Stores the provider and model of the agent, or of its second model when second is 1, after CheckModel passes (and nothing is written
/// when it does not). With second 0:
///   1. the entry of the agent's runner item (its ProviderConfig names it) is merged through ConfigStore.Merge in the model-change shape: the
///      provider and @{env:<its key variable>}; the entry holds no model;
///   2. the Model row of the item (Ext.Accessor.WriteDefault) is written and read back;
///   3. the item alone is restarted (Timeouts.Restart, without Decide).
/// With second 1 it does the same on the retry item <agent>Retry, and then writes the RetryItem row of the first runner, <agent>Retry. An empty
/// provider and model with second 1 writes the RetryItem row "" and leaves the retry item as it is.
/// old is {provider, model} as they stood (and retryItem, the RetryItem value, for a second model); it never holds a key. A failure after the
/// first write puts back what was written, restarts the item again where it was restarted, and returns the error with the errors of any
/// step that could not be put back appended.
ClassMethod SetModel(agent As %String, provider As %String, model As %String, second As %Boolean = 0, Output old As %DynamicObject) As %Status
{
	Set old = {}
	Set sc = ..CheckModel($Get(agent), $Get(provider), $Get(model), $Get(second))
	If $$$ISERR(sc) Quit sc
	Set second = +$Get(second)
	Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" Quit $$$ERROR($$$GeneralError, "No production is active, so the model cannot be changed")
	Set clear = second && ($Get(provider) = "") && ($Get(model) = "")
	Set item = agent_$Select(second: ##class(OcuTalon.Bridge.Timeouts).#RETRYSUFFIX, 1: "")
	Set sc = ..Entries(production, item, .entry, .pair)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(entry, .before)
	If $$$ISERR(sc) Quit sc
	Set was = {}
	Do was.%Set("provider", $Select(before.%GetTypeOf("model_provider") = "string": before.%Get("model_provider"), 1: ""))
	Do was.%Set("model", ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, production))
	If second Do was.%Set("retryItem", ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", production, agent))
	Set old = was
	If clear Quit ..WriteRow(production, agent, "RetryItem", "", ..#RETRYROW)

	Set modelId = production_"||"_item_"||*||Model"
	Set modelRow = ..RowState(modelId)
	Set retryId = production_"||"_agent_"||*||RetryItem"
	Set retryRow = ..RowState(retryId)
	Set fields = {"model_provider": (provider), "api_key": ("@{env:"_##class(OcuTalon.Bridge.Providers).Row(provider).%Get("keyVariable")_"}"), "model": (model)}
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge(entry, fields)
	If $$$ISERR(sc) Quit sc
	Set restarted = 0
	Set sc = ..WriteRow(production, item, "Model", model, ..#MODELROW, "Adapter")
	If $$$ISOK(sc) {
		Set restarted = 1
		Set sc = ..Restart(production, pair)
	}
	If $$$ISOK(sc) && second Set sc = ..WriteRow(production, agent, "RetryItem", item, ..#RETRYROW)
	If $$$ISERR(sc) {
		Set undo = ##class(OcuTalon.Bridge.ConfigStore).Restore(entry, before)
		Set undo = $$$ADDSC(undo, ..PutBack(modelId, modelRow, production, item, "Model"))
		If second Set undo = $$$ADDSC(undo, ..PutBack(retryId, retryRow, production, agent, "RetryItem"))
		If restarted Set undo = $$$ADDSC(undo, ..Restart(production, pair))
		Set sc = $$$ADDSC(sc, undo)
	}
	Quit sc
}

/// Stores the prices of a model; old holds the replaced prices. A stub: not implemented, nothing written, old empty.
ClassMethod SetPrice(model As %String, prices As %DynamicObject, Output old As %DynamicObject) As %Status
{
	Set old = {}
	Quit $$$ERROR($$$NotImplemented)
}

/// Builds the request that tests the agent's first model, for the caller to send to Decide. A stub: not implemented, request empty.
ClassMethod TestRequest(agent As %String, Output request As OcuTalon.Bridge.Msg.Request) As %Status
{
	Set request = ""
	Quit $$$ERROR($$$NotImplemented)
}

/// Reads the response to the test request as {answered, seconds, reason}. A stub: an empty object.
ClassMethod TestAnswer(response As %Persistent, durationMs As %Integer) As %DynamicObject
{
	Quit {}
}

/// The first runner items that have a model to change, as a list: the second part of each pair of Decide.#RUNNERS.
ClassMethod Agents() As %List [ Private ]
{
	Set agents = ""
	Set pairs = $ListFromString(##class(OcuTalon.Bridge.Process.Decide).#RUNNERS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set agents = agents _ $ListBuild($Piece(pair, ":", 2))
	}
	Quit agents
}

/// The Config Store entry of the runner item in the production, and the list $ListBuild($ListBuild(item, entry)) that Timeouts.Restart takes:
/// an error that names the item when the production does not have it with an entry that exists (Timeouts.Entries).
ClassMethod Entries(production As %String, item As %String, Output entry As %String, Output pair As %List) As %Status [ Private ]
{
	Set entry = ""
	Set pair = ""
	Set sc = ##class(OcuTalon.Bridge.Timeouts).Entries(production, .runners)
	If $$$ISERR(sc) Quit sc
	For i = 1:1:$ListLength(runners) {
		If $List($List(runners, i), 1) = item {
			Set entry = $List($List(runners, i), 2)
			Set pair = $ListBuild($List(runners, i))
		}
	}
	If entry = "" Quit $$$ERROR($$$GeneralError, "The runner "_item_" is not an item of the production with a Config Store entry, so its model cannot be changed")
	Quit $$$OK
}

/// Writes the System Default Settings row of the setting for the item and reads the setting back (Ext.Accessor ValueFor, target Host unless
/// given): an error when what is read is not the value, which a more specific row or the production definition can cause.
ClassMethod WriteRow(production As %String, item As %String, setting As %String, value As %String, description As %String, target As %String = "Host") As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, item, setting, value, description)
	If $$$ISERR(sc) Quit sc
	Set read = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting, production, item, .readSc, target)
	If $$$ISERR(readSc) || (read '= value) {
		Quit $$$ERROR($$$GeneralError, "The setting "_setting_" of "_item_" stays as it was whatever is written to its System Default Settings row, because the production definition or a more specific row sets it, so it is not changed")
	}
	Quit $$$OK
}

/// $ListBuild(existed, value, description) of the System Default Settings row with the id.
ClassMethod RowState(id As %String) As %List [ Private ]
{
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit $ListBuild(0, "", "")
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Quit $ListBuild(1, row.SettingValue, row.Description)
}

/// Puts the System Default Settings row back as RowState read it: the value and description of a row that existed, otherwise no row.
ClassMethod PutBack(id As %String, state As %List, production As %String, item As %String, setting As %String) As %Status [ Private ]
{
	If $List(state, 1) Quit ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, item, setting, $List(state, 2), $List(state, 3))
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Quit $$$OK
}

/// Restarts the runner item of the list alone (Timeouts.Restart without Decide).
ClassMethod Restart(production As %String, pair As %List) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Timeouts).Restart(production, pair, 0)
}

}
