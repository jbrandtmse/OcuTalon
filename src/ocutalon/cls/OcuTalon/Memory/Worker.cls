/// The queue-and-wait code that every Python worker category shares (AD-6, AD-21). A subclass names its WorkMgr category in CATEGORY and holds the work items
/// (class methods) that the workers of the category run; its callers call Submit and hold no Python. This class holds none either, so it is among the callback
/// helpers that Test.Bridge.CodeRules scans.
///   - Submit(entry, timeout, .result, args...) queues one work item to the category and waits at most timeout seconds. entry is a class method of the
///     calling class, or a full ##class(<class>).<method> reference. The work item's %result nodes come back in result. It returns the work item's status,
///     or an error status when no group could be made, the item could not be queued or it did not finish in time, and never throws.
///   - On a timeout the error status says "The work item <entry> did not finish within <n> seconds" and result (its top node) is the word timeout, so a caller
///     tells a timeout from another error without matching text.
///   - A timeout also releases the work group lock that build 154 leaves with the caller (ReleaseGroupLocks). The scan for the held locks before the queue
///     and that release fail quiet (a failed scan means no release), so neither makes Submit throw; the timeout is recorded before the group is cleared.
///   - STOPONTIMEOUT: when 1, a timeout also ends the group's busy worker (the work group's Clear, without a further wait, as the wait is spent), so that a work
///     item that never ends cannot hold a worker; when 0 (the default) the item keeps running until the worker's own end.
Class OcuTalon.Memory.Worker [ Abstract ]
{

/// The WorkMgr category of the workers: set by the subclass and created by the Memory install step.
Parameter CATEGORY As STRING;

/// 1 stops the busy worker after a timeout (see above).
Parameter STOPONTIMEOUT = 0;

ClassMethod Submit(entry As %String, timeout As %Integer, Output result, args... As %String) As %Status
{
	Kill result
	Set sc = $SYSTEM.Status.OK()
	Set timedOut = 0
	Set held = ""
	Set scanned = 0
	Try {
		Set held = ..GroupLocks()
		Set scanned = 1
	} Catch {
	}
	Try {
		Set queue = $SYSTEM.WorkMgr.%New("", 1, ..#CATEGORY)
		If queue = "" {
			Set sc = $SYSTEM.Status.Error(5001, "No work group of category " _ ..#CATEGORY _ " could be made: " _ $SYSTEM.Status.GetErrorText($Get(%objlasterror)))
		} Else {
			Set sc = queue.Queue($Select($Extract(entry, 1, 8) = "##class(": entry, 1: "##class(" _ $ClassName() _ ")." _ entry), args...)
			If $SYSTEM.Status.IsOK(sc) {
				If 'queue.WaitOne(timeout, .workStatus, .workArgs, .workResult) || $$$ERRORISTYPE(workStatus, $$$MultiTimeout) {
					Set sc = $SYSTEM.Status.Error(5001, "The work item " _ entry _ " did not finish within " _ timeout _ " seconds")
					Set result = "timeout"
					Set timedOut = 1
					If ..#STOPONTIMEOUT {
						Try {
							Do queue.Clear(0)
						} Catch {
						}
					}
				} ElseIf $SYSTEM.Status.IsError(workStatus) {
					Set sc = workStatus
				} Else {
					Merge result = workResult
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Kill queue
	If timedOut && scanned {
		Try {
			Do ..ReleaseGroupLocks(held)
		} Catch {
		}
	}
	Quit sc
}

/// The work group locks that this process holds, as a list of lock names.
ClassMethod GroupLocks() As %List
{
	Set held = ""
	Set prefix = "^IRIS.WorkQueue(""Group"","
	Set name = $Order(^$LOCK(""))
	While name '= "" {
		If ($Extract(name, 1, $Length(prefix)) = prefix) && ($Get(^$LOCK(name, "OWNER")) = $Job) Set held = held _ $ListBuild(name)
		Set name = $Order(^$LOCK(name))
	}
	Quit held
}

/// The work group of a timed-out item is deleted with its worker still busy, and build 154 then leaves the group's lock with the calling process for
/// the life of the process. This releases the work group locks that the process holds now and did not hold when Submit began (held).
ClassMethod ReleaseGroupLocks(held As %List) [ Private ]
{
	Set now = ..GroupLocks()
	Set position = 0
	While $ListNext(now, position, name) {
		If '$ListFind(held, name) Lock -@name
	}
}

}
