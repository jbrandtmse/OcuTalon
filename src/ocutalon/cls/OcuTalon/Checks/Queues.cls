/// The rules of the queue-backlog check (Story 23.7; AD-18, AD-19, AD-28). Pure: they read no table and no global and write nothing. Lane A.
///   - Over is the one threshold rule of a queue, applied by a queue-backlog run (Checks.Process RunQueues) and by the digest's live read
///     (Checks.Coverage Live): a queue is above when it holds more messages than limit.queueMessages, or when it holds messages and its oldest has
///     waited more than limit.queueWaitMinutes minutes. The limits come from Checks.Coverage CurrentLimits.
///   - Crossings is the reporting rule of a run. previous is the row's Reported before the run, JSON {"above": {"<namespace>": ["<item>", ...]},
///     "told": {"<namespace>": {"<item>": "<UTC time of its last report>"}}}; empty or invalid JSON is {}, so a first run has no baseline and every queue
///     that is above is new. readings is [{"namespace", "production", "displayName", "read" (1 when the namespace was read), "queues": [{"name", "count",
///     "oldestAt"}, ...]}]. The result is [{"namespace", "displayName", "item", "count", "oldestAt"}] in reading order and queue order, one for each queue
///     that is above now, was not in the previous above of its namespace and is not held back by the cooldown. reported is the Reported to store.
///   - A read namespace's new above is its queues that Over finds above, except the ones held back. A namespace that was not read, or is not in readings,
///     keeps its previous above.
///   - The cooldown: a queue is reported at most once in COOLDOWNSECONDS. A queue that is above, not in the previous above and was told less than that
///     before nowSeconds is held back: it is not reported and not added to above, so the first run after the cooldown that still finds it above reports
///     it. A report sets its told time to the run time, and a told time of COOLDOWNSECONDS or more is dropped from reported. The cooldown is no part of
///     Over, so the digest's live read is not changed by it.
///   - reported has an above member that holds only the namespaces with a non-empty list, and a told member only when it has an entry.
/// nowSeconds is the run time as Data.Time Seconds gives it.
Class OcuTalon.Checks.Queues [ Abstract ]
{

/// The least seconds between two reports of one queue.
Parameter COOLDOWNSECONDS = 3600;

/// The start of Data.Time's scale, from which the told time of a report is formed.
Parameter EPOCH = "1840-12-31T00:00:00Z";

/// 1 when the queue ({"name", "count", "oldestAt"}) is above the limits (see the class description). byCount is 1 when its count is over
/// limit.queueMessages. waited is the seconds its oldest message has waited when the queue holds messages, the time is readable and the wait exceeds
/// limit.queueWaitMinutes minutes, else 0.
ClassMethod Over(queue As %DynamicObject, limit As %DynamicObject, nowSeconds As %Integer, Output byCount As %Boolean, Output waited As %Integer) As %Boolean
{
	Set byCount = (queue.count > limit.queueMessages)
	Set waited = 0
	If queue.count > 0 {
		Set oldest = ##class(OcuTalon.Data.Time).Seconds(queue.oldestAt)
		If (oldest '= "") && (nowSeconds - oldest > (limit.queueWaitMinutes * 60)) Set waited = nowSeconds - oldest
	}
	Quit byCount || (waited > 0)
}

/// The queues of the readings that are newly above, and the Reported to store in reported (see the class description).
ClassMethod Crossings(previous As %String, readings As %DynamicArray, limit As %DynamicObject, nowSeconds As %Integer, Output reported As %String) As %DynamicArray
{
	Set found = []
	Set above = {}
	Set told = {}
	Set before = ..Parse($Get(previous))
	Set wasAbove = $Select(before.%GetTypeOf("above") = "object": before.above, 1: {})
	Set wasTold = $Select(before.%GetTypeOf("told") = "object": before.told, 1: {})
	Set iterator = wasAbove.%GetIterator()
	While iterator.%GetNext(.namespace, .names) {
		If $IsObject(names) && names.%IsA("%Library.DynamicArray") && names.%Size() Do above.%Set(namespace, names)
	}
	Set iterator = wasTold.%GetIterator()
	While iterator.%GetNext(.namespace, .entries) {
		If '$IsObject(entries) || 'entries.%IsA("%Library.DynamicObject") Continue
		Set kept = {}
		Set inner = entries.%GetIterator()
		While inner.%GetNext(.name, .at) {
			If ..Held(at, nowSeconds) Do kept.%Set(name, at, "string")
		}
		If kept.%GetIterator().%GetNext() Do told.%Set(namespace, kept)
	}
	Set now = ##class(OcuTalon.Data.Time).AddSeconds(..#EPOCH, nowSeconds)
	Set iterator = readings.%GetIterator()
	While iterator.%GetNext(, .reading) {
		If 'reading.read Continue
		Set namespace = reading.namespace
		Set previousNames = ""
		If above.%GetTypeOf(namespace) = "array" {
			Set listing = above.%Get(namespace).%GetIterator()
			While listing.%GetNext(, .name) {
				Set previousNames = previousNames_$ListBuild(name)
			}
		}
		Set names = []
		Set queues = $Select($IsObject(reading.queues): reading.queues, 1: [])
		Set queueIterator = queues.%GetIterator()
		While queueIterator.%GetNext(, .queue) {
			If '..Over(queue, limit, nowSeconds) Continue
			If $ListFind(previousNames, queue.name) {
				Do names.%Push(queue.name, "string")
				Continue
			}
			If told.%GetTypeOf(namespace) = "object" && ..Held(told.%Get(namespace).%Get(queue.name), nowSeconds) Continue
			Do names.%Push(queue.name, "string")
			If told.%GetTypeOf(namespace) '= "object" Do told.%Set(namespace, {})
			Do told.%Get(namespace).%Set(queue.name, now, "string")
			Do found.%Push({"namespace": (namespace), "displayName": (reading.displayName), "item": (queue.name), "count": (queue.count), "oldestAt": (queue.oldestAt)})
		}
		If names.%Size() {
			Do above.%Set(namespace, names)
		} Else {
			Do above.%Remove(namespace)
		}
	}
	Set after = {"above": (above)}
	If told.%GetIterator().%GetNext() Do after.%Set("told", told)
	Set reported = after.%ToJSON()
	Quit found
}

/// 1 when the time (UTC) is readable and less than COOLDOWNSECONDS before nowSeconds: the report it records still holds.
ClassMethod Held(at As %String, nowSeconds As %Integer) As %Boolean [ Private ]
{
	Set seconds = ##class(OcuTalon.Data.Time).Seconds($Get(at))
	Quit (seconds '= "") && (nowSeconds - seconds < ..#COOLDOWNSECONDS)
}

/// The JSON object of a Reported: {} when it is empty, not JSON or not an object.
ClassMethod Parse(json As %String) As %DynamicObject [ Private ]
{
	If json = "" Quit {}
	Try {
		Set parsed = ##class(%DynamicAbstractObject).%FromJSON(json)
	} Catch {
		Set parsed = ""
	}
	Quit $Select($IsObject(parsed) && parsed.%IsA("%Library.DynamicObject"): parsed, 1: {})
}

}
