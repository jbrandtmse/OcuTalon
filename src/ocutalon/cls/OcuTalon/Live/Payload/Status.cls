/// The payload of the status live event: one status condition of the closed catalog (AD-12). Lane B publishes it.
/// The class is also the one computation of the conditions that this build derives from the bridge (AD-12, AD-20):
/// Readings reads the two bridge APIs, Computed turns the readings into the conditions, and Active answers the active ones
/// for /state. StatusMonitor publishes what Computed gives when it changes. Both call Computed with the two readings only, so that the
/// conditions that come from elsewhere (the heartbeat) are computed here, once, for both.
Class OcuTalon.Live.Payload.Status Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The closed catalog of status conditions (AD-12).
Parameter CONDITIONS = "allowance,dailyCap,noModelKey,heartbeatStalled,telegramPaused,resetSoon";

/// The runner items whose keys Keys.Status(agent) reads: the agents that call the model (AD-20).
Parameter AGENTS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// One of CONDITIONS.
Property Condition As %String(%JSONFIELDNAME = "condition", MAXLEN = 32);

/// True while the condition holds.
Property Active As %Boolean(%JSONFIELDNAME = "active") [ InitialExpression = 0 ];

/// The condition's slots.
Property Slots As OcuTalon.Live.Payload.Part.StatusSlots(%JSONFIELDNAME = "slots");

/// The two readings that the computed conditions come from, and the only place that calls the bridge for them (AD-20).
/// keys is {"TriageAgent": 0|1, "DiagnosisAgent": 0|1, "ChatAgent": 0|1}: Keys.Status of each item of AGENTS. budget is
/// Budget.State(), or {} when that is not an object.
ClassMethod Readings(Output keys As %DynamicObject, Output budget As %DynamicObject)
{
	Set keys = {}
	Set agents = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(agents, position, agent) {
		Do keys.%Set(agent, +''##class(OcuTalon.Bridge.Keys).Status(agent), "number")
	}
	Set budget = ##class(OcuTalon.Bridge.Budget).State()
	If '$IsObject(budget) || ($ClassName(budget) '= "%Library.DynamicObject") Set budget = {}
}

/// The conditions that this build computes, as Status payload objects in CONDITIONS order: dailyCap, noModelKey, then
/// heartbeatStalled. Each is there whether it holds or not, and an inactive one carries no slots.
///   - noModelKey holds when any of AGENTS reads 0 in keys; an agent that keys doesn't name counts as 0, so that a reading
///     that is missing never hides a missing key. It has no slots;
///   - dailyCap holds when budget.capped is true: the JSON boolean true, or a number other than 0; any other value, or a
///     reading with no capped member, is not a cap. Its slots are Cap, budget.cap when it is a number above 0 (0 is a cap that is
///     off, so a day marked capped while the cap is off names no cap), and Time, budget.resetsAt when it is a UTC time to the second;
///   - heartbeatStalled holds when Heartbeat.Stalled says the heartbeat reading's lastTick is more than 3 minutes older than its now.
///     Its one slot is Time, that lastTick verbatim. heartbeat is {"lastTick", "now"}, the shape of Heartbeat.Reading(); when it is
///     omitted Computed takes Heartbeat.Reading() itself, and a heartbeat that is given as "" or as anything but an object is no
///     tick, so the condition is off.
ClassMethod Computed(keys As %DynamicObject, budget As %DynamicObject, heartbeat As %DynamicObject) As %Library.ListOfObjects
{
	Set conditions = ##class(%Library.ListOfObjects).%New()
	Do conditions.Insert(..DailyCap($Get(budget)))
	Do conditions.Insert(..NoModelKey($Get(keys)))
	Do conditions.Insert(..HeartbeatStalled($Select($Data(heartbeat): heartbeat, 1: ##class(OcuTalon.Schedule.Heartbeat).Reading())))
	Quit conditions
}

/// The active conditions of a session as an array of JSON objects shaped like the payload's export:
/// {"condition", "active": true, "slots"?}. They are ActiveOf(Computed(keys, budget)) for the keys and budget of Readings(), and
/// Computed takes the real heartbeat reading itself. They are the same for every session: sessionRef is not used yet, and Epic 16
/// adds the conditions that depend on the session (allowance).
ClassMethod Active(sessionRef As %String) As %DynamicArray
{
	Do ..Readings(.keys, .budget)
	Quit ..ActiveOf(..Computed(keys, budget))
}

/// The active ones of a list of conditions, as an array of JSON objects shaped like the payload's export, in the list's order.
ClassMethod ActiveOf(conditions As %Library.ListOfObjects) As %DynamicArray
{
	Set active = []
	For i = 1:1:conditions.Count() {
		Set condition = conditions.GetAt(i)
		If 'condition.Active Continue
		Set sc = condition.%JSONExportToString(.json)
		If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Do active.%Push(##class(%DynamicObject).%FromJSON(json))
	}
	Quit active
}

/// The dailyCap condition for the budget reading.
ClassMethod DailyCap(budget As %DynamicObject) As OcuTalon.Live.Payload.Status [ Private ]
{
	Set condition = ..%New()
	Set condition.Condition = "dailyCap"
	If '$IsObject(budget) Quit condition
	Set type = budget.%GetTypeOf("capped")
	Set condition.Active = $Case(type, "boolean": budget.%Get("capped"), "number": budget.%Get("capped") '= 0, : 0)
	If 'condition.Active Quit condition
	Set condition.Slots = ##class(OcuTalon.Live.Payload.Part.StatusSlots).%New()
	If (budget.%GetTypeOf("cap") = "number") && (budget.%Get("cap") > 0) Set condition.Slots.Cap = budget.%Get("cap")
	Set resetsAt = $Select(budget.%GetTypeOf("resetsAt") = "string": budget.%Get("resetsAt"), 1: "")
	If resetsAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Set condition.Slots.Time = resetsAt
	Quit condition
}

/// The heartbeatStalled condition for the heartbeat reading {"lastTick", "now"}: off for a reading that is not a dynamic object.
ClassMethod HeartbeatStalled(heartbeat As %DynamicObject) As OcuTalon.Live.Payload.Status [ Private ]
{
	Set condition = ..%New()
	Set condition.Condition = "heartbeatStalled"
	If '$IsObject(heartbeat) || ($ClassName(heartbeat) '= "%Library.DynamicObject") Quit condition
	Set lastTick = $Select(heartbeat.%GetTypeOf("lastTick") = "string": heartbeat.%Get("lastTick"), 1: "")
	Set now = $Select(heartbeat.%GetTypeOf("now") = "string": heartbeat.%Get("now"), 1: "")
	If '##class(OcuTalon.Schedule.Heartbeat).Stalled(lastTick, now) Quit condition
	Set condition.Active = 1
	Set condition.Slots = ##class(OcuTalon.Live.Payload.Part.StatusSlots).%New()
	Set condition.Slots.Time = lastTick
	Quit condition
}

/// The noModelKey condition for the keys reading.
ClassMethod NoModelKey(keys As %DynamicObject) As OcuTalon.Live.Payload.Status [ Private ]
{
	Set condition = ..%New()
	Set condition.Condition = "noModelKey"
	Set agents = $ListFromString(..#AGENTS)
	Set position = 0
	While $ListNext(agents, position, agent) {
		If '$IsObject(keys) || ('keys.%Get(agent)) Set condition.Active = 1
	}
	Quit condition
}

}
