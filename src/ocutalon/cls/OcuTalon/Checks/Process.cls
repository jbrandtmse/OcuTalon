/// Checks, the business process that runs the background checks on every heartbeat (AD-18, AD-28, AD-33). Its item keeps PoolSize 1. It handles two
/// requests, and answers OK to both (any other request class is an error 5001 that names the class):
///   - An OcuTalon.Msg.Tick (HeartbeatIn sends one every minute). now is Data.Time.NowUtc(), and the tick time is TickAt when that is a UTC stamp
///     (YYYY-MM-DDTHH:MM:SSZ), else now. First the quiet sweep: every Incident row that is not closed and whose LastAt is more than
///     IncidentManager.QUIETSECONDS before now (Watch.Settle.Quiet) gets one OcuTalon.Msg.IncidentCommand, verb closeQuiet, origin timer and no
///     session, sent synchronously to IncidentManager (SendQuiet; at most QUIETWAIT seconds) in the Tick's trace session with the TraceRef of the
///     incident's owner as its SuperSession (empty for instance or eval; AD-26), the process's own SuperSession being put back after the send.
///     Checks does not act on the answer: IncidentManager applies the table (AD-15) and publishes the incident event. A failed or late send logs one
///     Type 3 warning (LOGQUIET) and the sweep goes on. Then the fixes (Fixes, Story 7.5): the final OcuTalon.Fix.Msg.FixResults of OcuTalon.Fix.Run.Sweep()
///     (the seam FixRunSweep; the one Fix code that Checks calls) are each sent to IncidentManager, asynchronously with no answer wanted (SendFixResult), in the
///     trace session of the result's incident (its TraceHeaderId, when set) with the request's TraceRef as the SuperSession (AD-26), the process's own session
///     and SuperSession being put back after each send. A Sweep that throws logs one Type 3 warning (LOGFIXES), a failed send one Type 3 warning (LOGFIX, with
///     the request's Ref), and the other results still go. Then the checks: every row of Kind production is due when its NextDueAt is empty or at most
///     DUESLACKSECONDS after the tick time, and each due row runs once however many ticks were missed. An exception in one row's run logs one Type 3
///     warning (LOGRUN), and the next row still runs. The quiet sweep, the fixes and the due checks each have their own Try/Catch.
///   - An OcuTalon.Checks.Msg.CheckChanged (WatchOps sends one after a watch is started or stopped): Checks publishes the change as a check event
///     on the owner's stream, FromRow of the row it opens by Ref for a start (nothing when the row is gone), and for a stop a payload of the message's
///     fields with stopped true. A failed publish logs one Type 3 warning (LOGPUBLISH).
/// One run of a row:
///   - Read: Watch.Reader.Failures (the seam Read) from Watch.Mark.Start(LastRunAt, CreatedAt, now), the previous run less Mark.OVERLAP seconds, else
///     the watch's creation, at most Mark.MAXFAILURES failures, with the production's running state. The incidents come from the rows.
///   - Scope (AD-4): a failure is the session's when Watch.FailurePoller.Scope of its SuperSession is the row's SessionRef, or is instance and the
///     instance is not the online demo. The same rule picks the incidents of the row's namespace and production whose State is open, awaiting_approval
///     or fixing (noticed or not).
///   - Findings (Story 30.4; AC 1-3; FR-23, AD-14, AD-18, AD-30, AD-32): when the read gave the production's state (the outcome read, nothing thrown, a
///     state other than timeout, unknown and ""; a run that is not_checked only because the read was cut or the incidents could not be read still counts),
///     the state and the disabled items are compared with what the row last reported (BackgroundCheck.Reported, JSON {"stopped": 1 while the stop has been
///     reported, "disabled": [the names reported disabled]}); Findings applies the rule. A production stopped or suspended since the last run is one finding,
///     and each item disabled since is one, in the order the reader gave them; troubled, network_stopped and a restart are not stops, and a restart makes the
///     next stop new. A row whose Reported is empty (a new watch, or one from before this story) only records its baseline: the first reading run reports
///     nothing. A run that read no state leaves Reported as it was. Each finding is one OcuTalon.Msg.Item for Intake only (Channel system, Provenance
///     untrusted, a new ItemId, the row's SessionRef as owner, the Text TEXTSTOPPED or TEXTDISABLED with the display name, CatalogKey watch.productionStopped or
///     watch.itemDisabled, and Slots {"production", "time"} or {"itemName", "production", "time"}): producers never render. {time} is the stop time that IRIS
///     recorded for a stopped production (UTC to the second), else the time of the run; for a disabled item, which IRIS gives no time for, it is the run time,
///     so it can be up to one check interval after the change (AD-15 states that a change's time is known only to within the check interval).
///   - Result, the first rule that holds: not_checked with one reason (REASONUNREADABLE, REASONNOTCURRENT, REASONTIMEOUT, REASONREAD when the read
///     threw, the state is unknown or the incidents could not be read, REASONTOOMANY when the read was cut at its limit and none of its rows is the
///     session's); failed when the state is not running, or the session has a new failure, or an unclosed incident; else passed. The finding of a
///     failed check joins up to three parts with ", " and an upper-case first letter: the state, the new failures (counted; "at least" when the read
///     was cut) and the most urgent unclosed incident. The texts are the FINDING* and REASON* parameters, built by code: no error text, event-log
///     text or diagnosis text ever reaches a finding, which Story 5.7's check_status trusts.
///   - Record: one SQL UPDATE keyed by Ref sets LastRunAt, Result, Finding, LastRunHeaderId (this process's %SessionId, the Tick's trace session
///     (AD-26)), NextDueAt (the tick time plus INTERVALSECONDS) and Reported. Checks writes only these fields, and never re-creates a row: when no row is
///     updated (the watch was stopped meanwhile) nothing more happens, and nothing is sent. Only then is each finding sent (SendFinding), in the Tick's
///     session with the TraceRef of the row's session as SuperSession, the process's own SuperSession being put back after each send (AD-26). A send that
///     fails or throws logs one Type 3 warning (LOGFINDING, with the check's Ref), is never retried (its finding is already in Reported), and the other
///     findings still go.
///   - Event and log line: the row is opened again by Ref and published as a check event (Live.Payload.Check.FromRow) after the update's commit
///     (LOGPUBLISH on a failure), and one Type 4 line (LOGRAN) names the check's Ref, display name, result and finding in the Tick's session.
/// Nothing that decides "due" or "new" lives in memory (AD-5). The only namespace switch is in Watch.Reader (AD-3). This class is the only one that
/// publishes the check event.
Class OcuTalon.Checks.Process Extends Ens.BusinessProcess
{

/// The seconds between the runs of a check: the next due time is the tick time plus this.
Parameter INTERVALSECONDS = 60;

/// A check is due when its next due time is at most this many seconds after the tick, so that an early tick still runs it.
Parameter DUESLACKSECONDS = 5;

/// The longest the sweep waits for IncidentManager's answer to closeQuiet, in seconds.
Parameter QUIETWAIT = 30;

/// The configuration item that settles incidents (AD-15).
Parameter MANAGER = "IncidentManager";

/// The configuration item that takes the findings as items (AD-14).
Parameter INTAKE = "Intake";

/// The origin of a command from the heartbeat.
Parameter TIMER = "timer";

/// The only kind of check that runs.
Parameter KIND = "production";

/// The live event type of a check.
Parameter CHECKEVENT = "check";

/// The scope of what no session owns, and the owner literals that have no trace of their own.
Parameter INSTANCE = "instance";

Parameter EVAL = "eval";

/// The parts of a finding (public text; the first letter is made upper case, {count} is the number).
Parameter FINDINGSTOPPED = "production stopped";

Parameter FINDINGSUSPENDED = "production suspended";

Parameter FINDINGTROUBLED = "production troubled";

Parameter FINDINGNOTRUNNING = "production not running";

Parameter FINDINGFAILURE = "1 new failure";

Parameter FINDINGFAILURES = "{count} new failures";

Parameter FINDINGATLEAST = "at least {count} new failures";

Parameter FINDINGAWAITING = "a fix waiting for your approval";

Parameter FINDINGFIXING = "a fix running";

Parameter FINDINGOPEN = "an open incident";

/// The reasons that a check could not be made (public text).
Parameter REASONUNREADABLE = "No read access to its namespace";

Parameter REASONNOTCURRENT = "No longer its namespace's production";

Parameter REASONTIMEOUT = "No answer in time";

Parameter REASONREAD = "Couldn't be read";

Parameter REASONTOOMANY = "Too many new failures to count";

Parameter LOGDUE = "Checks could not read the checks that are due: ";

Parameter LOGSWEEP = "Checks could not read the quiet incidents: ";

Parameter LOGQUIET = "Checks could not send closeQuiet for incident ";

Parameter LOGFIXES = "Checks could not sweep the fix runs: ";

Parameter LOGFIX = "Checks could not send the result of request ";

Parameter LOGRUN = "Checks could not run check ";

Parameter LOGREAD = "Checks could not read the production of check ";

Parameter LOGPUBLISH = "Checks could not publish check ";

Parameter LOGRAN = "Checks ran check ";

Parameter LOGFINDING = "Checks could not send a finding of check ";

/// The text of a finding Item (public text; the first line becomes the item summary): {production} is the display name, {itemName} the item's name.
Parameter TEXTSTOPPED = "The {production} production stopped.";

Parameter TEXTDISABLED = "The {itemName} in the {production} production was disabled.";

/// The catalog keys of the findings (Msg.Catalog.Watch) and the channel of their Items.
Parameter KEYSTOPPED = "watch.productionStopped";

Parameter KEYDISABLED = "watch.itemDisabled";

Parameter SYSTEMCHANNEL = "system";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If $IsObject(request) {
		If request.%IsA("OcuTalon.Msg.Tick") Quit ..Tick(request)
		If request.%IsA("OcuTalon.Checks.Msg.CheckChanged") Quit ..Changed(request)
	}
	Quit $SYSTEM.Status.Error(5001, "Checks does not handle a request of the class '"_$Select($IsObject(request): $ClassName(request), 1: "none")_"'")
}

/// A Tick: the quiet sweep, then the fixes (Fixes), then the checks that are due (see the class description). Always OK.
Method Tick(tick As OcuTalon.Msg.Tick) As %Status [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set tickAt = $Select(tick.TickAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z": tick.TickAt, 1: now)
	Try {
		Do ..Sweep(now)
	} Catch exception {
		$$$LOGWARNING(..#LOGSWEEP_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Try {
		Do ..Fixes()
	} Catch exception {
		$$$LOGWARNING(..#LOGFIXES_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Try {
		Set due = ..Due(tickAt)
		Set iterator = due.%GetIterator()
		While iterator.%GetNext(, .row) {
			Try {
				Do ..Run(row, tickAt)
			} Catch exception {
				$$$LOGWARNING(..#LOGRUN_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGDUE_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// The fixes: each final FixResult that Fix.Run Sweep returns goes to IncidentManager (see the class description). A send that fails or throws logs one Type 3 warning (LOGFIX), and the
/// next result still goes.
Method Fixes() [ Private ]
{
	Set results = ..FixRunSweep()
	For i = 1:1:results.Count() {
		Set result = results.GetAt(i)
		Set session = ..%SessionId
		Set superSession = ..%SuperSession
		Set sc = $$$OK
		Try {
			Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(result.IncidentRef)
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(result.ApprovalRef)
			If $IsObject(incident) {
				If incident.TraceHeaderId '= "" Set ..%SessionId = incident.TraceHeaderId
				Set ..%SuperSession = $Select($IsObject(row): row.TraceRef, 1: "")
			}
			Set sc = ..SendFixResult(result)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Set ..%SessionId = session
		Set ..%SuperSession = superSession
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGFIX_result.ApprovalRef_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
}

/// The final FixResults of the runs that end now: OcuTalon.Fix.Run.Sweep(), a %ListOfObjects (a seam for the tests).
Method FixRunSweep() As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Fix.Run).Sweep()
}

/// Sends IncidentManager the FixResult, asynchronously, with no answer wanted, in this process's session and with its SuperSession (a seam for the tests).
Method SendFixResult(result As OcuTalon.Fix.Msg.FixResult) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#MANAGER, result, 0)
}

/// The quiet sweep: closeQuiet for each incident of Quiet(now), in the Tick's session with the owner's TraceRef as SuperSession.
Method Sweep(now As %String) [ Private ]
{
	Set quiet = ..Quiet(now)
	Set iterator = quiet.%GetIterator()
	While iterator.%GetNext(, .incident) {
		Set saved = ..%SuperSession
		Try {
			Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
			Set command.Verb = ##class(OcuTalon.Watch.Transitions).#CLOSEQUIET
			Set command.IncidentRef = incident.ref
			Set command.Origin = ..#TIMER
			Set ..%SuperSession = ..TraceOf(incident.ownerRef)
			Set answer = ""
			Set sc = ..SendQuiet(command, .answer)
			If $$$ISOK(sc) && '$IsObject(answer) Set sc = $SYSTEM.Status.Error(5001, "IncidentManager did not answer in "_..#QUIETWAIT_" seconds")
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Set ..%SuperSession = saved
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGQUIET_incident.ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
}

/// The unclosed incidents whose last failure is more than IncidentManager's QUIETSECONDS before now, as a dynamic array of {"ref", "ownerRef"}, in
/// the order of the rows.
Method Quiet(now As %String) As %DynamicArray [ Private ]
{
	Set quiet = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, OwnerRef, LastAt FROM OcuTalon_Data.Incident WHERE State <> ? ORDER BY ID", ##class(OcuTalon.Watch.Transitions).#CLOSED)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The incidents could not be read: "_rs.%Message))
	While rs.%Next() {
		If ##class(OcuTalon.Watch.Settle).Quiet(rs.%GetData(3), now, ##class(OcuTalon.Watch.IncidentManager).#QUIETSECONDS) {
			Do quiet.%Push({"ref": (rs.%GetData(1)), "ownerRef": (rs.%GetData(2))})
		}
	}
	Quit quiet
}

/// The TraceRef of the owner's session, "" for instance, eval, an empty owner or an owner with no session.
Method TraceOf(ownerRef As %String) As %String [ Private ]
{
	If (ownerRef = "") || (ownerRef = ..#INSTANCE) || (ownerRef = ..#EVAL) Quit ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ownerRef)
	Quit $Select($IsObject(session): session.TraceRef, 1: "")
}

/// Sends IncidentManager the command, synchronously, waiting at most QUIETWAIT seconds, in this process's session and with its SuperSession (a seam
/// for the tests). answer is IncidentManager's CommandResult, which it gives on every OK status, and no object when the wait ran out (the status is
/// still OK then); the sweep only tells the two apart.
Method SendQuiet(command As OcuTalon.Msg.IncidentCommand, Output answer As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ..SendRequestSync(..#MANAGER, command, .answer, ..#QUIETWAIT)
}

/// The production checks that are due at the tick time, as a dynamic array of {"ref", "sessionRef", "namespace", "production", "displayName",
/// "createdAt", "lastRunAt", "reported"}, in the order of the rows: those whose NextDueAt is empty or at most DUESLACKSECONDS after the tick time.
Method Due(tickAt As %String) As %DynamicArray [ Private ]
{
	Set due = []
	Set limit = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, ..#DUESLACKSECONDS))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, SessionRef, Namespace, Production, DisplayName, CreatedAt, LastRunAt, NextDueAt, Reported FROM OcuTalon_Data.BackgroundCheck WHERE Kind = ? ORDER BY ID", ..#KIND)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The checks could not be read: "_rs.%Message))
	While rs.%Next() {
		Set next = rs.%GetData(8)
		If (next '= "") && (next ] limit) Continue
		Do due.%Push({"ref": (rs.%GetData(1)), "sessionRef": (rs.%GetData(2)), "namespace": (rs.%GetData(3)), "production": (rs.%GetData(4)), "displayName": (rs.%GetData(5)), "createdAt": (rs.%GetData(6)), "lastRunAt": (rs.%GetData(7)), "reported": (rs.%GetData(9))})
	}
	Quit due
}

/// One run of a due row (see the class description): the read, the result, the record, the event and the log line.
Method Run(row As %DynamicObject, tickAt As %String) [ Private ]
{
	Set runAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set from = ##class(OcuTalon.Watch.Mark).Start(row.lastRunAt, row.createdAt, ##class(OcuTalon.Watch.Mark).Normal(runAt))
	Set limit = ##class(OcuTalon.Watch.Mark).#MAXFAILURES
	Set outcome = ""
	Set state = ""
	Set rows = []
	Set disabled = []
	Set stoppedAt = ""
	Set threw = 0
	Try {
		Set outcome = ..Read(row.namespace, row.production, from, limit, .rows, .state, .disabled, .stoppedAt)
	} Catch exception {
		Set threw = 1
		Set outcome = ""
		Set state = ""
		Set rows = []
		Set disabled = []
		Set stoppedAt = ""
		$$$LOGWARNING(..#LOGREAD_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Set onlineDemo = ##class(OcuTalon.Watch.Reader).OnlineDemo()
	Set failures = 0
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set scope = ##class(OcuTalon.Watch.FailurePoller).Scope(failure.superSession)
		If (scope = row.sessionRef) || ((scope = ..#INSTANCE) && 'onlineDemo) Set failures = failures + 1
	}
	Set cut = (rows.%Size() '< limit)
	Set incident = ""
	Set unread = 0
	If (outcome = "read") && 'threw {
		Try {
			Set incident = ..Unclosed(row, onlineDemo)
		} Catch exception {
			Set unread = 1
		}
	}
	Set reason = $Case(outcome, "unreadable": ..#REASONUNREADABLE, "not_current": ..#REASONNOTCURRENT, : "")
	If reason = "" {
		If state = "timeout" {
			Set reason = ..#REASONTIMEOUT
		} ElseIf threw || (outcome '= "read") || (state = "unknown") || (state = "") || unread {
			Set reason = ..#REASONREAD
		} ElseIf cut && (failures = 0) {
			Set reason = ..#REASONTOOMANY
		}
	}
	If reason '= "" {
		Set result = "not_checked"
		Set finding = reason
	} Else {
		Set finding = ..Finding(state, failures, cut, incident)
		Set result = $Select(finding = "": "passed", 1: "failed")
	}
	Set reported = row.reported
	Set items = ##class(%ListOfObjects).%New()
	If (outcome = "read") && 'threw {
		Set found = ..Findings(row.reported, state, disabled, .reported)
		Set iterator = found.%GetIterator()
		While iterator.%GetNext(, .one) {
			If one.kind = "stopped" {
				Set at = ##class(OcuTalon.Watch.Mark).FailedAt(stoppedAt)
				Do items.Insert(..FindingItem(row, ..#KEYSTOPPED, ..#TEXTSTOPPED, {}, $Select(at '= "": at, 1: runAt)))
			} Else {
				Do items.Insert(..FindingItem(row, ..#KEYDISABLED, ..#TEXTDISABLED, {"itemName": (one.item)}, runAt))
			}
		}
	}
	Do ..Record(row, tickAt, runAt, result, finding, reported, items)
}

/// Records the run and what it reported on the row by Ref, then sends the findings (items, a %ListOfObjects of OcuTalon.Msg.Item), publishes the row and logs
/// the run (see the class description). Nothing at all when no row is updated.
Method Record(row As %DynamicObject, tickAt As %String, runAt As %String, result As %String, finding As %String, reported As %String, items As %ListOfObjects) [ Private ]
{
	Set nextDueAt = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, ..#INTERVALSECONDS))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ?, Finding = ?, LastRunHeaderId = ?, NextDueAt = ?, Reported = ? WHERE Ref = ?", runAt, result, finding, ..%SessionId, nextDueAt, reported, row.ref)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The run could not be recorded: "_rs.%Message))
	If +rs.%ROWCOUNT < 1 Quit
	For i = 1:1:items.Count() {
		Set item = items.GetAt(i)
		Set saved = ..%SuperSession
		Try {
			Set ..%SuperSession = ..TraceOf(row.sessionRef)
			Set sc = ..SendFinding(item)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Set ..%SuperSession = saved
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGFINDING_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	}
	Set stored = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(row.ref)
	If $IsObject(stored) Do stored.%Reload()
	If $IsObject(stored) Do ..Announce(stored.SessionRef, row.ref, ##class(OcuTalon.Live.Payload.Check).FromRow(stored))
	$$$LOGINFO(..#LOGRAN_row.ref_" ("_row.displayName_"): "_result_$Select(finding = "": "", 1: ", "_finding))
}

/// The findings of a run (pure; see the class description, rows 1-9 of the story's matrix): previous is the row's Reported before the run, state the
/// production's running state, disabled the dynamic array of the names of its disabled items. The result is a dynamic array of {"kind": "stopped"} and
/// {"kind": "disabled", "item"}, the stop first and the items in the order of disabled, and reported is the Reported to store. Empty previous (or one
/// that is not JSON) is a baseline: no finding, and reported records the state. A state of timeout, unknown or "" was not read: no finding, and reported
/// is previous, unchanged.
ClassMethod Findings(previous As %String, state As %String, disabled As %DynamicArray, Output reported As %String) As %DynamicArray
{
	Set found = []
	Set reported = $Get(previous)
	If ($Get(state) = "") || (state = "timeout") || (state = "unknown") Quit found
	Set stopped = $Select((state = "stopped") || (state = "suspended"): 1, 1: 0)
	Set before = ""
	If $Get(previous) '= "" {
		Try {
			Set before = ##class(%DynamicAbstractObject).%FromJSON(previous)
		} Catch {
			Set before = ""
		}
	}
	Set names = []
	Set iterator = disabled.%GetIterator()
	While iterator.%GetNext(, .name) {
		Do names.%Push(name, "string")
	}
	If $IsObject(before) {
		If stopped && 'before.stopped Do found.%Push({"kind": "stopped"})
		Set seen = ""
		If $IsObject(before.disabled) {
			Set iterator = before.disabled.%GetIterator()
			While iterator.%GetNext(, .name) {
				Set seen(name) = ""
			}
		}
		Set iterator = names.%GetIterator()
		While iterator.%GetNext(, .name) {
			If '$Data(seen(name)) Do found.%Push({"kind": "disabled", "item": (name)})
		}
	}
	Set now = {}
	Do now.%Set("stopped", stopped, "number")
	Do now.%Set("disabled", names)
	Set reported = now.%ToJSON()
	Quit found
}

/// One finding Item for Intake (see the class description): the catalog key, the slots (the production's display name, the time and what slots adds) and
/// the text, which is text with the display name and the item's name put in.
Method FindingItem(row As %DynamicObject, key As %String, text As %String, slots As %DynamicObject, time As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = row.sessionRef
	Set item.Channel = ..#SYSTEMCHANNEL
	Set item.Provenance = "untrusted"
	Set item.CatalogKey = key
	Do slots.%Set("production", row.displayName, "string")
	Do slots.%Set("time", time, "string")
	Set item.Slots = slots.%ToJSON()
	Set item.Text = $Replace($Replace(text, "{production}", row.displayName), "{itemName}", $Select(slots.itemName '= "": slots.itemName, 1: ""))
	Quit item
}

/// The unclosed incidents of the row's namespace and production that count for its session: the most urgent state among them (awaiting_approval,
/// else fixing, else open), "" when there is none.
Method Unclosed(row As %DynamicObject, onlineDemo As %Boolean) As %String [ Private ]
{
	Set urgent = ""
	Set open = ##class(OcuTalon.Watch.Transitions).#OPEN
	Set awaiting = ##class(OcuTalon.Watch.Transitions).#AWAITING
	Set fixing = ##class(OcuTalon.Watch.Transitions).#FIXING
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT OwnerRef, State FROM OcuTalon_Data.Incident WHERE Namespace = ? AND Production = ? AND State IN (?, ?, ?)", row.namespace, row.production, open, awaiting, fixing)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The incidents could not be read: "_rs.%Message))
	While rs.%Next() {
		Set owner = rs.%GetData(1)
		If (owner '= row.sessionRef) && ((owner '= ..#INSTANCE) || onlineDemo) Continue
		Set state = rs.%GetData(2)
		If state = awaiting Set urgent = state
		If (state = fixing) && (urgent '= awaiting) Set urgent = state
		If (state = open) && (urgent = "") Set urgent = state
	}
	Quit urgent
}

/// The finding of a failed run, or "" when the run passed: the state, the new failures and the incident, as the class description gives them.
ClassMethod Finding(state As %String, failures As %Integer, cut As %Boolean, incident As %String) As %String [ Private ]
{
	Set parts = ""
	Set stateText = $Case(state, "stopped": ..#FINDINGSTOPPED, "suspended": ..#FINDINGSUSPENDED, "troubled": ..#FINDINGTROUBLED, "network_stopped": ..#FINDINGNOTRUNNING, : "")
	If stateText '= "" Set parts = parts_$ListBuild(stateText)
	If failures > 0 {
		Set text = $Select(cut: ..#FINDINGATLEAST, failures = 1: ..#FINDINGFAILURE, 1: ..#FINDINGFAILURES)
		Set parts = parts_$ListBuild($Replace(text, "{count}", failures))
	}
	Set incidentText = $Case(incident, ##class(OcuTalon.Watch.Transitions).#AWAITING: ..#FINDINGAWAITING, ##class(OcuTalon.Watch.Transitions).#FIXING: ..#FINDINGFIXING, ##class(OcuTalon.Watch.Transitions).#OPEN: ..#FINDINGOPEN, : "")
	If incidentText '= "" Set parts = parts_$ListBuild(incidentText)
	Set finding = $ListToString(parts, ", ")
	Quit $ZConvert($Extract(finding), "U")_$Extract(finding, 2, *)
}

/// A CheckChanged from WatchOps: the change goes out as a check event (see the class description). Always OK.
Method Changed(change As OcuTalon.Checks.Msg.CheckChanged) As %Status [ Private ]
{
	Try {
		Set payload = ""
		If change.Stopped {
			Set payload = ##class(OcuTalon.Live.Payload.Check).%New()
			Set payload.Ref = change.CheckRef
			Set payload.Kind = change.Kind
			Set payload.Namespace = change.Namespace
			Set payload.Production = change.Production
			Set payload.DisplayName = change.DisplayName
			Set payload.Stopped = 1
		} Else {
			Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(change.CheckRef)
			If $IsObject(row) Set payload = ##class(OcuTalon.Live.Payload.Check).FromRow(row)
		}
		If $IsObject(payload) Do ..Announce(change.SessionRef, change.CheckRef, payload)
	} Catch exception {
		$$$LOGWARNING(..#LOGPUBLISH_change.CheckRef_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// Publishes the payload as a check event on the session's stream, after the change has committed. A failed publish logs one Type 3 warning.
Method Announce(sessionRef As %String, ref As %String, payload As OcuTalon.Live.Payload.Check) [ Private ]
{
	Set sc = ##class(OcuTalon.Live.Publish).Publish(sessionRef, ..#CHECKEVENT, payload)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPUBLISH_ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The failures of the production from the stamp on, at most limit, and its running state: OcuTalon.Watch.Reader.Failures, its outcome (read,
/// unreadable or not_current), its rows, its state, the names of its disabled items and its recorded stop time. A seam for the tests.
Method Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String, Output disabled As %DynamicArray, Output stoppedAt As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Failures(namespace, production, from, limit, .rows, .state, .disabled, .stoppedAt)
}

/// Sends Intake the finding Item, asynchronously, with no answer wanted, in this process's session and with its SuperSession (a seam for the tests).
Method SendFinding(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#INTAKE, item, 0)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
