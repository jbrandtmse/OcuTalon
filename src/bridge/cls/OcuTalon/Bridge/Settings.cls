/// The one entry point of the bridge's settings for the settings operation (AD-19, AD-7, AD-18, AD-20; Lane A). OcuTalon.Core.SettingsOps
/// changes bridge values only through this class. Every method is built (Stories 17.3 and 17.4); each signature is pinned in
/// OcuTalon.Test.Contract.Ac. It delegates to ConfigStore.Merge, Ext.Accessor.WriteDefault, Budget, Data.Price, Providers and Time.SetZone, and
/// keeps this contract:
///   - Providers: the provider table's rows in their fixed order (Providers), each {provider, defaultModel, models, keyVariable, keySet,
///     supported}: keySet says that the key variable is set in this process, and no key is ever returned;
///   - Values: DecisionTokenBudget, DailyCostCapUSD and InstanceZone as strings, read as Decide, Budget and Time.Zone read them (a value that
///     is not acceptable counts as 0, and an unset zone is ""), and agents: for each first runner item (TriageAgent, DiagnosisAgent,
///     ChatAgent) {provider, model, secondProvider, secondModel}. The model is AgentRunner.ResolveModel of the item and each provider is the
///     row of the provider table that lists the model (Providers.ProviderOf); the second pair is "" when the item's RetryItem is "". It reads
///     no Config Store entry and holds no key;
///   - Check and Set: a value for one of DecisionTokenBudget (a whole number from 0 to Decide.MAXREQUESTTOKENS, 0 is off), DailyCostCapUSD (a
///     number from 0 to 10000 with at most two decimals, 0 is off) or InstanceZone ("" or an IANA name that Time.CheckZone accepts). Any other
///     name is refused, TimerSeconds included: only Timeouts.Apply changes the bridge timer. Set writes the System Default Settings row of Decide
///     (WriteRow; the two numbers as their canonical number text, so 7.50 is stored as 7.5; InstanceZone only through Time.SetZone) and returns
///     the value it replaced in old, as a scalar string; a value that Set or an install step wrote passes Check, so a caller can hand such an old
///     back (a value written by hand outside these bounds comes back as it is, and Check refuses it). The values apply to the next decision
///     with no restart. A Set of the cap that leaves it off or above the day's spend removes the day's capped mark (Budget.Unmark);
///   - CheckModel and SetModel: an agent's model, or its second model when second is 1. agent is the name of a first runner item: TriageAgent,
///     DiagnosisAgent or ChatAgent. The provider must be supported with its key variable set, and the model one that the provider table lists for
///     it. For a first model SetModel merges the agent's Config Store entry through ConfigStore.Merge with only the provider and
///     @{env:<its key variable>}, writes the runner's Model row, reads it back and restarts that runner item alone. For a second model it does the
///     same on the retry item <agent>Retry and then sets RetryItem of the first runner to that item; an empty provider and model sets RetryItem to
///     "" and leaves the retry item as it is. old holds {provider, model} that were replaced (and retryItem for a second model), never a key. A
///     failure after the first write puts back what was written. CheckModel changes nothing, and refuses with a plain-English reason an argument
///     that holds "@{", an agent outside the three, a provider that is not in the table, not supported or whose key variable is not set, a model
///     that the provider does not list, and an empty provider or model for a first model;
///   - SetPrice: the prices of a model in an existing Data.Price row. prices holds one or more of input, output, cacheRead, cacheWrite, longInput
///     and longOutput (numbers from 0 to 10000 with at most 4 decimals) and longThresholdTokens (a whole number from 0 to 10,000,000); keys that
///     are left out keep their values. old holds all seven values as they were. Earlier Usage rows keep their cost (Usage.FromStats fixes it when a
///     row is written);
///   - TestRequest and TestAnswer: TestRequest builds one request of the agent's own kind (decide, diagnose or turn) with provenance untrusted,
///     owner instance, channel system, a fresh session, an ItemId of TESTITEMPREFIX and a part of a fresh reference, and the fixed code-written
///     TESTINPUT and TESTSUMMARY, which the caller sends to Decide synchronously. IsTest names such a request, and Decide never sends it to a
///     second model. TestAnswer reads the response and the milliseconds it took and returns {answered, seconds, reason}: answered is true only for
///     a reply that is not a fallback and not busy, seconds has one decimal (at least 0.1 for a positive duration), and reason is "" when answered, the fallback reason when there is
///     one, and otherwise error.
/// Every method above refuses a value that holds "@{" or is off the allow-list, with a plain-English reason that never holds the value, and changes
/// nothing; the bridge timer stays at or under 110 seconds. WriteRow, which Set, SetModel and Time.SetZone share, checks nothing itself. The bridge references no OcuTalon package outside the bridge (AD-2).
Class OcuTalon.Bridge.Settings
{

/// The description of the System Default Settings row of Model that SetModel writes.
Parameter MODELROW = "Written by OcuTalon.Bridge.Settings.SetModel; the Production install step never overwrites it.";

/// The description of the System Default Settings row of RetryItem that SetModel writes.
Parameter RETRYROW = "Written by OcuTalon.Bridge.Settings.SetModel for a second model; the Production install step never overwrites it.";

/// The description of the System Default Settings row of DecisionTokenBudget, DailyCostCapUSD or InstanceZone that Set writes.
Parameter SETTINGROW = "Written by OcuTalon.Bridge.Settings.Set; the install steps never overwrite it.";

/// The names that Check and Set accept, as a list.
Parameter SETTINGS = "DecisionTokenBudget,DailyCostCapUSD,InstanceZone";

/// The largest daily cost cap, in US dollars.
Parameter MAXCAP = 10000;

/// The largest price, in US dollars per million tokens.
Parameter MAXPRICE = 10000;

/// The largest long-tier threshold, in tokens.
Parameter MAXTHRESHOLD = 10000000;

/// The prefix of the ItemId of a model test request; a reference never holds a dot (Ids.NewRef), so no other request has it.
Parameter TESTITEMPREFIX = "test.";

/// The input of a model test request.
Parameter TESTINPUT = "This is a connection test from the OcuTalon settings page. Nothing needs to be done: reply as briefly as you can.";

/// The summary of a model test request.
Parameter TESTSUMMARY = "Model test from Settings";

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

/// The bridge values that the settings page shows, as a dynamic object: DecisionTokenBudget, DailyCostCapUSD and InstanceZone as strings,
/// and agents, an object with one {provider, model, secondProvider, secondModel} for each first runner item. It reads no Config Store entry
/// and holds no key.
ClassMethod Values() As %DynamicObject
{
	Set values = {}
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Do values.%Set("DecisionTokenBudget", ..Current("DecisionTokenBudget", production), "string")
	Do values.%Set("DailyCostCapUSD", ..Current("DailyCostCapUSD", production), "string")
	Do values.%Set("InstanceZone", ..Current("InstanceZone", production), "string")
	Set agents = {}
	Set position = 0
	Set list = ..Agents()
	While $ListNext(list, position, agent) {
		Set model = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, production)
		Set retryItem = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", production, agent)
		Set second = $Select(retryItem = "": "", 1: ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(retryItem, production))
		Set one = {}
		Do one.%Set("provider", ##class(OcuTalon.Bridge.Providers).ProviderOf(model), "string")
		Do one.%Set("model", model, "string")
		Do one.%Set("secondProvider", ##class(OcuTalon.Bridge.Providers).ProviderOf(second), "string")
		Do one.%Set("secondModel", second, "string")
		Do agents.%Set(agent, one)
	}
	Do values.%Set("agents", agents)
	Quit values
}

/// OK when the value is acceptable for the named setting, without changing anything; otherwise an error whose plain-English reason never
/// holds the value. The name is one of SETTINGS, and TimerSeconds is not. A value that holds @{ is refused. DecisionTokenBudget is a whole number
/// from 0 to Decide.MAXREQUESTTOKENS, DailyCostCapUSD a number from 0 to MAXCAP with at most two decimals, and InstanceZone "" or a name that
/// Time.CheckZone accepts.
ClassMethod Check(name As %String, value As %String) As %Status
{
	Set name = $Get(name)
	Set value = $Get(value)
	If '$ListFind($ListFromString(..#SETTINGS), name) {
		Quit $$$ERROR($$$GeneralError, "That setting cannot be changed here: only "_$ListToString($ListFromString(..#SETTINGS), ", ")_" can")
	}
	If value [ "@{" Quit $$$ERROR($$$GeneralError, "The value of "_name_" is refused: a setting takes a plain value and never a placeholder")
	If name = "InstanceZone" Quit ##class(OcuTalon.Bridge.Time).CheckZone(value)
	If name = "DecisionTokenBudget" {
		Set limit = ##class(OcuTalon.Bridge.Process.Decide).#MAXREQUESTTOKENS
		If (value '? 1.6N) || (+value > limit) Quit $$$ERROR($$$GeneralError, "The token budget must be a whole number from 0 to "_limit_" (0 is off)")
		Quit $$$OK
	}
	If (value '? 1.5N.1(1"."1.2N)) || (+value > ..#MAXCAP) {
		Quit $$$ERROR($$$GeneralError, "The daily cost cap must be an amount in US dollars from 0 to "_..#MAXCAP_" with at most two decimals (0 is off)")
	}
	Quit $$$OK
}

/// Stores the value of the named setting after Check passes (and nothing is written when it does not); old is the value it replaced, as a
/// string, which passes Check when Set or an install step wrote it. DecisionTokenBudget and DailyCostCapUSD are written to the System Default Settings row of Decide as their canonical
/// number text and read back (WriteRow), and InstanceZone through Time.SetZone. A cap that is 0 or above the day's spend removes the day's
/// capped mark (Budget.Unmark), so that cost fallbacks stop from the next decision; a cap at or below the spend leaves it. The values apply
/// to the next decision, with no restart.
ClassMethod Set(name As %String, value As %String, Output old As %String) As %Status
{
	Set old = ""
	Set name = $Get(name)
	Set value = $Get(value)
	Set sc = ..Check(name, value)
	If $$$ISERR(sc) Quit sc
	Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" Quit $$$ERROR($$$GeneralError, "No production is active, so the setting cannot be changed")
	Set was = ..Current(name, production)
	If name = "InstanceZone" {
		Set sc = ##class(OcuTalon.Bridge.Time).SetZone(value)
		If $$$ISOK(sc) Set old = was
		Quit sc
	}
	Set text = ..Canonical(value)
	Set sc = ..WriteRow(production, "Decide", name, text, ..#SETTINGROW)
	If $$$ISERR(sc) Quit sc
	Set old = was
	If name = "DailyCostCapUSD" Do ..UnmarkAfter(+text)
	Quit $$$OK
}

/// Removes the capped mark of today when the cap is 0 or above the day's spend (State), and leaves it otherwise. When the spend cannot be
/// read in this process, only a cap of 0 removes it.
ClassMethod UnmarkAfter(cap As %Numeric) [ Private ]
{
	Set unmark = (cap = 0)
	If 'unmark {
		Set state = ##class(OcuTalon.Bridge.Budget).State(, .faults)
		Set unreadable = 0
		Set iterator = faults.%GetIterator()
		While iterator.%GetNext(, .fault) {
			If fault [ ##class(OcuTalon.Bridge.Budget).#NOPRIVILEGE Set unreadable = 1
		}
		Set unmark = 'unreadable && (cap > state.%Get("spent"))
	}
	If unmark Do ##class(OcuTalon.Bridge.Budget).Unmark()
}

/// The value of the setting as Decide, Budget and Time.Zone read it, as a string: the number settings in their canonical text (a value that
/// Decide or Budget cannot read counts as 0, as they count it), the zone as Time.Zone gives it ("" when Time.CheckZone refuses it). A value that
/// Set or an install step wrote passes Check.
ClassMethod Current(name As %String, production As %String) As %String [ Private ]
{
	If name = "InstanceZone" {
		Set zone = ##class(OcuTalon.Bridge.Time).Zone()
		Quit $Select($$$ISOK(##class(OcuTalon.Bridge.Time).CheckZone(zone)): zone, 1: "")
	}
	Set text = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(name, production, "Decide", .sc)
	If $$$ISERR(sc) Quit 0
	If name = "DecisionTokenBudget" Quit $Select(text ? 1.N: ..Canonical(text), 1: 0)
	Quit $Select((text '= "") && $IsValidNum(text, "", 0): ..Canonical(text), 1: 0)
}

/// The canonical text of a number that Check accepted: no leading zeros or trailing decimal zeros, and a zero before the point.
ClassMethod Canonical(number As %String) As %String [ Private ]
{
	Set number = +number
	Quit $Select((number > 0) && (number < 1): "0"_number, 1: number)
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
	Set retryId = production_"||"_agent_"||*||RetryItem"
	Set retryRow = ..RowState(retryId)
	If clear {
		Set sc = ..WriteRow(production, agent, "RetryItem", "", ..#RETRYROW)
		If $$$ISERR(sc) Set sc = $$$ADDSC(sc, ..PutBack(retryId, retryRow, production, agent, "RetryItem"))
		Return sc
	}

	Set modelId = production_"||"_item_"||*||Model"
	Set modelRow = ..RowState(modelId)
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

/// Stores the prices of a model in its existing Price row, after every key is checked (and nothing is written when one is refused); old holds
/// all seven values as they were, with the long-tier values of a model that has none as 0. prices holds one or more of PRICEKEYS (numbers or
/// numeric text from 0 to MAXPRICE with at most 4 decimals) and longThresholdTokens (a whole number from 0 to MAXTHRESHOLD); a key that is
/// left out keeps its value. It is refused for a model that has no Price row, an unknown key, a value that holds @{ or is negative or not a
/// number, an empty object, and a long-tier threshold above 0 without both long prices above 0 (LongTier). Cost is fixed when a Usage row is written, so earlier rows keep theirs.
ClassMethod SetPrice(model As %String, prices As %DynamicObject, Output old As %DynamicObject) As %Status
{
	Set old = {}
	Set model = $Get(model)
	If model [ "@{" Quit $$$ERROR($$$GeneralError, "The model is refused: a price change takes a plain model name and never a placeholder")
	If '$IsObject($Get(prices)) || 'prices.%IsA("%Library.DynamicObject") Quit $$$ERROR($$$GeneralError, "The prices must be an object of the prices to change")
	If prices.%Size() = 0 Quit $$$ERROR($$$GeneralError, "The prices are empty: name at least one price to change")
	Set keys = ..PriceKeys()
	Set refused = 0
	Set iterator = prices.%GetIterator()
	While 'refused && iterator.%GetNext(.key, .value) {
		Set type = prices.%GetTypeOf(key)
		If '$ListFind($ListFromString(keys), key) || ((type '= "number") && (type '= "string")) || (value [ "@{") {
			Set refused = 1
		} ElseIf key = "longThresholdTokens" {
			Set refused = (value '? 1.8N) || (+value > ..#MAXTHRESHOLD)
		} Else {
			Set refused = '$Match(value, "^([0-9]+(\.[0-9]{1,4})?|\.[0-9]{1,4})\z") || '$IsValidNum(value, 4, 0, ..#MAXPRICE)
		}
	}
	If refused Quit $$$ERROR($$$GeneralError, "The prices are refused: each price must be a number from 0 to "_..#MAXPRICE_" with at most 4 decimals, longThresholdTokens a whole number from 0 to "_..#MAXTHRESHOLD_", and no other key is accepted")
	If '##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) Quit $$$ERROR($$$GeneralError, "The model has no price row, so its prices cannot be changed")
	Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
	If '$IsObject(row) Quit $$$ERROR($$$GeneralError, "The price row of the model cannot be opened")
	Set tier = ..LongTier(row, prices)
	If tier = 0 Quit $$$ERROR($$$GeneralError, "A long-tier threshold needs both long prices above 0: set longInput and longOutput with longThresholdTokens, or set longThresholdTokens to 0")
	Set properties = $ListBuild("InputPerMTok", "OutputPerMTok", "CacheReadPerMTok", "CacheWritePerMTok", "LongInputPerMTok", "LongOutputPerMTok", "LongThresholdTokens")
	Set names = $ListFromString(keys)
	Set was = {}
	For i = 1:1:$ListLength(names) {
		Do was.%Set($List(names, i), +$Property(row, $List(properties, i)), "number")
	}
	For i = 1:1:$ListLength(names) {
		If prices.%IsDefined($List(names, i)) Set $Property(row, $List(properties, i)) = $Select($List(names, i) = "longThresholdTokens": +prices.%Get($List(names, i)), 1: $Number(prices.%Get($List(names, i)), 4))
	}
	Set sc = row.%Save()
	If $$$ISOK(sc) Set old = was
	Quit sc
}

/// 1 when the long tier that the row would hold after SetPrice merged prices is usable: no threshold, or a threshold with both long prices above 0
/// (Price.Cost prices a turn over the threshold at the long rates, so a 0 rate would make it free). Otherwise 0.
ClassMethod LongTier(row As OcuTalon.Bridge.Data.Price, prices As %DynamicObject) As %Boolean [ Private ]
{
	Set threshold = $Select(prices.%IsDefined("longThresholdTokens"): +prices.%Get("longThresholdTokens"), 1: +row.LongThresholdTokens)
	Set longInput = $Select(prices.%IsDefined("longInput"): +prices.%Get("longInput"), 1: +row.LongInputPerMTok)
	Set longOutput = $Select(prices.%IsDefined("longOutput"): +prices.%Get("longOutput"), 1: +row.LongOutputPerMTok)
	Quit (threshold = 0) || ((longInput > 0) && (longOutput > 0))
}

/// The keys of SetPrice's prices, in the order of the Price properties InputPerMTok, OutputPerMTok, CacheReadPerMTok, CacheWritePerMTok,
/// LongInputPerMTok, LongOutputPerMTok and LongThresholdTokens, as a comma-separated list.
ClassMethod PriceKeys() As %String [ Private ]
{
	Quit "input,output,cacheRead,cacheWrite,longInput,longOutput,longThresholdTokens"
}

/// Builds the request that tests the agent's first model, for the caller to send to Decide synchronously: one request of the runner's kind
/// (Decide RUNNERS), provenance untrusted, owner instance, channel system, a fresh session, the ItemId TESTITEMPREFIX and 17 characters of a
/// new reference, TESTINPUT and TESTSUMMARY. It is refused for an agent that is not a first runner item, or whose name holds @{; request is
/// then "". Nothing is sent or written.
ClassMethod TestRequest(agent As %String, Output request As OcuTalon.Bridge.Msg.Request) As %Status
{
	Set request = ""
	Set agent = $Get(agent)
	If agent [ "@{" Quit $$$ERROR($$$GeneralError, "The agent is refused: a model test takes a plain agent name and never a placeholder")
	If '$ListFind(..Agents(), agent) Quit $$$ERROR($$$GeneralError, "The agent is not one that has a model to test: it must be "_$ListToString(..Agents(), ", "))
	Set kind = ""
	Set pairs = $ListFromString(##class(OcuTalon.Bridge.Process.Decide).#RUNNERS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If $Piece(pair, ":", 2) = agent Set kind = $Piece(pair, ":", 1)
	}
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = "untrusted"
	Set request.OwnerRef = "instance"
	Set request.Channel = "system"
	Set request.SessionMode = "fresh"
	Set request.ItemId = ..#TESTITEMPREFIX_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 17)
	Set request.Input = ..#TESTINPUT
	Set request.Summary = ..#TESTSUMMARY
	Quit $$$OK
}

/// 1 when the request is a model test request: its ItemId starts with TESTITEMPREFIX. Decide sends no such request to a second model.
ClassMethod IsTest(request As OcuTalon.Bridge.Msg.Request) As %Boolean
{
	Quit $IsObject($Get(request)) && ($Extract(request.ItemId, 1, $Length(..#TESTITEMPREFIX)) = ..#TESTITEMPREFIX)
}

/// Reads the response to the test request as {answered, seconds, reason}: answered is true only for a response that is not a fallback and not
/// busy; seconds is durationMs / 1000 to one decimal, at least 0.1 for a positive duration; reason is "" when answered, the response's FallbackReason when it has one, and otherwise
/// error (no response, busy, or a fallback with no reason).
ClassMethod TestAnswer(response As %Persistent, durationMs As %Integer) As %DynamicObject
{
	Set answered = 0
	Set reason = "error"
	Set response = $Get(response)
	If $IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.Result") {
		If response.%IsA("OcuTalon.Bridge.Msg.Reply") && response.Busy {
			Set reason = "error"
		} ElseIf response.Fallback {
			If response.FallbackReason '= "" Set reason = response.FallbackReason
		} Else {
			Set answered = 1
			Set reason = ""
		}
	}
	Set result = {}
	Do result.%Set("answered", answered, "boolean")
	Set seconds = $Number(+$Get(durationMs) / 1000, 1)
	If (+$Get(durationMs) > 0) && (seconds = 0) Set seconds = 0.1
	Do result.%Set("seconds", seconds, "number")
	Do result.%Set("reason", reason, "string")
	Quit result
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
/// given): an error when what is read is not the value, which a more specific row or the production definition can cause; the row is then
/// put back as it was. It checks nothing itself: Set, SetModel and Time.SetZone check the value before they call it.
ClassMethod WriteRow(production As %String, item As %String, setting As %String, value As %String, description As %String, target As %String = "Host") As %Status
{
	Set id = production_"||"_item_"||*||"_setting
	Set state = ..RowState(id)
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, item, setting, value, description)
	If $$$ISERR(sc) Quit sc
	Set read = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting, production, item, .readSc, target)
	If $$$ISERR(readSc) || (read '= value) {
		Do ..PutBack(id, state, production, item, setting)
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
