/// The one entry point of the bridge's settings for the settings operation (AD-19, AD-7, AD-18; Lane A). OcuTalon.Core.SettingsOps changes bridge
/// values only through this class. THIS CLASS IS A STUB until Stories 17.3 and 17.4: every method that returns a %Status answers "not implemented"
/// (code 5003) and writes nothing, and every other method returns its empty value; each signature is pinned in OcuTalon.Test.Contract.Ac. The built
/// class will delegate to ConfigStore.Merge, Ext.Accessor.WriteDefault, Keys, Budget, Data.Price, Timeouts and Time.SetZone, and will keep this contract:
///   - Providers: the provider table's rows in their fixed order, each with keySet (its key variable is set) and supported;
///   - Values: DecisionTokenBudget, DailyCostCapUSD, InstanceZone, and for each agent its provider and model and its second model's;
///   - Check and Set: a value for one of DecisionTokenBudget, DailyCostCapUSD or InstanceZone (InstanceZone through Time.SetZone); Set returns the
///     value it replaced in old;
///   - CheckModel and SetModel: an agent's model, or its second model when second is 1, for a supported provider whose key is set and a model of the
///     provider table; an empty provider and model clears a second model; SetModel merges the agent's Config Store entry through
///     ConfigStore.Merge with only the provider and @{env:<its key variable>}, sets the runner's Model (for a second model, the retry item's Model
///     and the first runner's RetryItem), restarts the affected runner, and returns the replaced values in old;
///   - SetPrice: the non-negative prices of a model in Data.Price, returning the replaced prices in old;
///   - TestRequest and TestAnswer: TestRequest builds one request of the agent's own kind (decide, diagnose or turn) with provenance untrusted,
///     owner instance, a fresh ItemId and a fixed code-written input, which the caller sends to Decide synchronously; TestAnswer reads the response
///     and returns {answered, seconds, reason}, the reason a fallback reason.
/// Every method refuses a value that holds "@{" or is off the allow-list, with a plain-English reason, and changes nothing; the bridge timer stays at
/// or under 110 seconds. The bridge references no OcuTalon package outside the bridge (AD-2).
Class OcuTalon.Bridge.Settings
{

/// The provider table's rows in their fixed order, as a dynamic array. A stub: an empty array.
ClassMethod Providers() As %DynamicArray
{
	Quit []
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

/// Whether the provider and model are acceptable for the agent's model, or its second model when second is 1, without changing anything. A stub: not implemented.
ClassMethod CheckModel(agent As %String, provider As %String, model As %String, second As %Boolean = 0) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

/// Stores the provider and model of the agent, or of its second model when second is 1; old holds the replaced values. A stub: not implemented, nothing written, old empty.
ClassMethod SetModel(agent As %String, provider As %String, model As %String, second As %Boolean = 0, Output old As %DynamicObject) As %Status
{
	Set old = {}
	Quit $$$ERROR($$$NotImplemented)
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

}
