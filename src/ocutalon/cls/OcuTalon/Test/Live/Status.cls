/// Tests of OcuTalon.Live.Payload.Status as the computation of the status conditions (Story 2.10; AD-12, AD-20), with fixture
/// readings, so that they hold whatever Keys.Status and Budget.State answer:
///   - TestComputedNoModelKey: each of the three agents at 0 alone makes noModelKey active, all three at 1 make it inactive, and
///     a missing agent or a keys reading that is not an object counts as no key. The condition never has slots;
///   - TestComputedDailyCap: capped true gives dailyCap with the cap and the reset time as slots, capped false (or a reading that
///     is not an object) gives it with no slots, capped as the number 1 or 0 follows the number while a string is no cap, and a
///     reset time that is not a UTC time to the second gives no time;
///   - TestComputedOrder: the conditions are dailyCap, noModelKey, then heartbeatStalled, the CONDITIONS order, each there whether active or
///     not (the heartbeat reading is passed as "", so that the tests do not depend on the real heartbeat);
///   - TestActive: only the active conditions, as JSON objects shaped like the payload's export, with a clear carrying no slots;
///   - TestReadings: the keys are the agents' Keys.Status readings and the budget is Budget.State(), both as direct calls give them.
/// The tests write no row and no global.
Class OcuTalon.Test.Live.Status Extends %UnitTest.TestCase
{

/// noModelKey: one agent at 0 is enough, and all at 1 clears it.
Method TestComputedNoModelKey()
{
	Set budget = {"spent": 0, "cap": 0, "capped": false, "resetsAt": ""}
	Set agents = $ListFromString(##class(OcuTalon.Live.Payload.Status).#AGENTS)
	Do $$$AssertEquals($ListLength(agents), 3, "three agents are read")
	Set position = 0
	While $ListNext(agents, position, alone) {
		Set keys = {}
		Set each = 0
		While $ListNext(agents, each, agent) {
			Do keys.%Set(agent, $Select(agent = alone: 0, 1: 1), "number")
		}
		Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, budget), "noModelKey")
		Do $$$AssertEquals(condition.Active, 1, alone_" alone at 0 makes noModelKey active")
		Do $$$AssertEquals(condition.Slots, "", "and it has no slots")
	}
	Set keys = {"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, budget), "noModelKey")
	Do $$$AssertEquals(condition.Active, 0, "all three at 1: noModelKey is inactive")
	Do $$$AssertEquals(condition.Slots, "", "with no slots")
	Set keys = {"TriageAgent": 0, "DiagnosisAgent": 0, "ChatAgent": 0}
	Do $$$AssertEquals(..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, budget), "noModelKey").Active, 1, "all three at 0: active")
	Set keys = {"TriageAgent": 1, "DiagnosisAgent": 1}
	Do $$$AssertEquals(..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, budget), "noModelKey").Active, 1, "an agent that the reading doesn't name counts as no key")
	Do $$$AssertEquals(..Find(##class(OcuTalon.Live.Payload.Status).Computed({}, budget), "noModelKey").Active, 1, "an empty keys reading is no key")
	Do $$$AssertEquals(..Find(##class(OcuTalon.Live.Payload.Status).Computed("", budget), "noModelKey").Active, 1, "and so is a keys reading that is not an object")
}

/// dailyCap follows capped, with cap and resetsAt as its slots.
Method TestComputedDailyCap()
{
	Set keys = {"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"spent": 20, "cap": 20, "capped": true, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 1, "capped true: dailyCap is active")
	Do $$$AssertTrue($IsObject(condition.Slots), "with slots")
	Do $$$AssertEquals(+condition.Slots.Cap, 20, "the cap is budget.cap")
	Do $$$AssertEquals(condition.Slots.Time, "2026-10-24T04:00:00Z", "the time is budget.resetsAt")
	Do $$$AssertEquals(condition.Slots.Limit, "", "and there is no limit")

	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"spent": 1.5, "cap": 20, "capped": true, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 1, "a cap that is reached by a mark and not by the spend: still active")
	Do $$$AssertEquals(+condition.Slots.Cap, 20, "with the cap")

	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"spent": 1, "cap": 20, "capped": false, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 0, "capped false: inactive")
	Do $$$AssertEquals(condition.Slots, "", "and it carries no slots, whatever cap and resetsAt say")

	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"cap": 20, "capped": 1, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 1, "capped as the number 1: active")
	Do $$$AssertEquals(+condition.Slots.Cap, 20, "with the cap")
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"cap": 20, "capped": 0, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 0, "capped as the number 0: inactive")
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"cap": 20, "capped": "true", "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 0, "capped as a string is not a cap: only a boolean or a number is")

	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 0, "a budget reading with no capped member: inactive")
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, ""), "dailyCap")
	Do $$$AssertEquals(condition.Active, 0, "a budget reading that is not an object: inactive")

	For time = "", "tomorrow", "2026-10-24 04:00:00", "2026-10-24T04:00:00", "2026-10-24T04:00:00+02:00", "2026-10-24T04:00:00.5Z" {
		Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"cap": 20, "capped": true, "resetsAt": (time)}), "dailyCap")
		Do $$$AssertEquals(condition.Active, 1, "'"_time_"': the cap still holds")
		Do $$$AssertEquals(condition.Slots.Time, "", "'"_time_"' is not a UTC time to the second, so there is no time")
		Do $$$AssertEquals(+condition.Slots.Cap, 20, "'"_time_"': the cap is still a slot")
	}
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"capped": true, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 1, "a cap that is missing: still active")
	Do $$$AssertEquals(condition.Slots.Cap_"|"_condition.Slots.Time, "|2026-10-24T04:00:00Z", "with no cap slot and the time")
	Set condition = ..Find(##class(OcuTalon.Live.Payload.Status).Computed(keys, {"spent": 5, "cap": 0, "capped": true, "resetsAt": "2026-10-24T04:00:00Z"}), "dailyCap")
	Do $$$AssertEquals(condition.Active, 1, "a day marked capped while the cap is off (0): still active")
	Do $$$AssertEquals(condition.Slots.Cap_"|"_condition.Slots.Time, "|2026-10-24T04:00:00Z", "with no cap slot, since 0 is no cap to name, and the time")
}

/// The conditions come in CONDITIONS order, each there whether it holds or not.
Method TestComputedOrder()
{
	Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed({"TriageAgent": 0, "DiagnosisAgent": 0, "ChatAgent": 0}, {"cap": 20, "capped": true, "resetsAt": "2026-10-24T04:00:00Z"}, "")
	Do $$$AssertEquals(..Names(conditions), "dailyCap,noModelKey,heartbeatStalled", "dailyCap, noModelKey, then heartbeatStalled")
	Do $$$AssertEquals(conditions.GetAt(1).Active_conditions.GetAt(2).Active_conditions.GetAt(3).Active, "110", "the first two hold, the heartbeat reading is no tick")
	Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed({"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}, {"capped": false}, "")
	Do $$$AssertEquals(..Names(conditions), "dailyCap,noModelKey,heartbeatStalled", "the same three when none holds")
	Do $$$AssertEquals(conditions.GetAt(1).Active_conditions.GetAt(2).Active_conditions.GetAt(3).Active, "000", "and none is active")
	Set catalog = $ListFromString($Parameter("OcuTalon.Live.Payload.Status", "CONDITIONS"))
	Set last = 0
	For i = 1:1:conditions.Count() {
		Set at = $ListFind(catalog, conditions.GetAt(i).Condition)
		Do $$$AssertTrue(at > last, conditions.GetAt(i).Condition_" is in the catalog, after the one before it")
		Set last = at
	}
}

/// Active holds only the active conditions, as the payload's JSON.
Method TestActive()
{
	Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed({"TriageAgent": 0, "DiagnosisAgent": 1, "ChatAgent": 1}, {"cap": 20, "capped": true, "resetsAt": "2026-10-24T04:00:00Z"}, "")
	Set active = ##class(OcuTalon.Live.Payload.Status).ActiveOf(conditions)
	Do $$$AssertEquals(active.%Size(), 2, "two conditions are active")
	Do $$$AssertEquals(active.%Get(0).condition_"|"_active.%Get(0).active_"|"_+active.%Get(0).slots.cap_"|"_active.%Get(0).slots.time, "dailyCap|1|20|2026-10-24T04:00:00Z", "dailyCap with its slots")
	Do $$$AssertEquals(active.%Get(1).%ToJSON(), "{""condition"":""noModelKey"",""active"":true}", "noModelKey with no slots")
	Do $$$AssertEquals(active.%Get(0).%GetTypeOf("active"), "boolean", "active is a boolean")

	Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed({"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}, {"capped": false}, "")
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Status).ActiveOf(conditions).%Size(), 0, "no condition active: an empty array")
	Do $$$AssertStatusOK(conditions.GetAt(1).%JSONExportToString(.json), "an inactive condition exports")
	Do $$$AssertEquals(json, "{""condition"":""dailyCap"",""active"":false}", "as the condition with active false and no slots")

	Set active = ##class(OcuTalon.Live.Payload.Status).Active("ZzSession")
	Do $$$AssertEquals($ClassName(active), "%Library.DynamicArray", "Active answers an array")
	Do ##class(OcuTalon.Live.Payload.Status).Readings(.keys, .budget)
	Set expected = ##class(OcuTalon.Live.Payload.Status).ActiveOf(##class(OcuTalon.Live.Payload.Status).Computed(keys, budget))
	Do $$$AssertEquals(active.%ToJSON(), expected.%ToJSON(), "Active is the active conditions of Computed(Readings())")
}

/// Readings are the bridge's own answers.
Method TestReadings()
{
	Do ##class(OcuTalon.Live.Payload.Status).Readings(.keys, .budget)
	Do $$$AssertEquals(keys.%GetTypeOf("TriageAgent")_keys.%GetTypeOf("DiagnosisAgent")_keys.%GetTypeOf("ChatAgent"), "numbernumbernumber", "keys holds a number for each of the three agents")
	Set names = ""
	Set iterator = keys.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set names = names_$Select(names = "": "", 1: ",")_name
		Do $$$AssertEquals(value, +''##class(OcuTalon.Bridge.Keys).Status(name), name_" is Keys.Status("_name_")")
	}
	Do $$$AssertEquals(names, ##class(OcuTalon.Live.Payload.Status).#AGENTS, "the agents, in AGENTS order")
	Do $$$AssertEquals(budget.%ToJSON(), ##class(OcuTalon.Bridge.Budget).State().%ToJSON(), "budget is Budget.State()")
	Do $$$AssertEquals($ClassName(budget), "%Library.DynamicObject", "an object")
}

/// The condition of the list with that name.
ClassMethod Find(conditions As %Library.ListOfObjects, name As %String) As OcuTalon.Live.Payload.Status [ Private ]
{
	For i = 1:1:conditions.Count() {
		If conditions.GetAt(i).Condition = name Return conditions.GetAt(i)
	}
	Quit ""
}

/// The names of the conditions of the list, comma-separated, in order.
ClassMethod Names(conditions As %Library.ListOfObjects) As %String [ Private ]
{
	Set names = ""
	For i = 1:1:conditions.Count() {
		Set names = names_$Select(names = "": "", 1: ",")_conditions.GetAt(i).Condition
	}
	Quit names
}

}
