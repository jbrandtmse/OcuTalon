/// Checks, the business process that runs the background checks on every heartbeat, and at once after a CheckNow (AD-18, AD-28, AD-33). Its item keeps PoolSize 1. It handles four
/// requests, and answers OK to all of them (any other request class is an error 5001 that names the class):
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
///     warning (LOGRUN), and the next row still runs. Last, the agent heartbeat's due beats: OcuTalon.Checks.Beat.RunDue(tickAt, .items) (the seam BeatRunDue). An error
///     status or an exception from it logs one Type 3 warning (LOGBEAT), and the Tick still answers OK. Every Item that RunDue returned, also when it gave an
///     error status, goes to Intake through SendOwn, in a trace session of its own with the TraceRef of the person's session as SuperSession (AD-26); the row
///     was saved before, and a send that fails logs one Type 3 warning (LOGBEATSEND, with the ItemId). The Tick itself never calls the model: every request
///     comes from Intake. The quiet sweep, the fixes, the due checks and the beats each have their own Try/Catch. A beat is no background check (AD-28): it
///     adds no row, check result or coverage entry. After the Items are sent (outside any transaction), each view that RunDue gave (one for each committed row
///     change of a person's HeartbeatBeat: a skip, a beat or a recorded decision) is published, in commit order, as a heartbeat event on that person's stream
///     (Live.Payload.Heartbeat, AnnounceBeat; Story 39.7). The one exception is a Tick's skip because the checklist is empty (Beat's SKIPEMPTY, AD-18): it saves
///     its row, gives no view and publishes nothing, while a run now that the empty checklist holds still publishes. The views that were made before an error
///     status or an exception from RunDue go out too. A publish that fails or throws logs one Type 3 warning (LOGBEATPUBLISH, without the SessionRef), and the
///     other views still go.
///   - An OcuTalon.Checks.Msg.CheckNow (IncidentManager sends one, asynchronously with no answer wanted and in the incident's trace session, after an accepted
///     move that resolves an incident, reopens it after a rejected or expired fix request, or closes a noticed open incident by dismiss or closeQuiet): Checks
///     runs each row of Kind production with the request's Namespace and Production that its OwnerRef covers (Watching; the scope rule of Unclosed, InScope: the
///     row's session, or every session's row for owner instance while the instance is not the online demo; none at all for eval or an empty owner, and never a row
///     of the session eval, an evaluation run's watch) once, at once,
///     in ID order, through Run and Record with keep (see Record). It runs no sweep, no fix sweep and no beat, and forwards nothing to Digest. A row whose
///     run throws logs the Tick's LOGRUN and the other rows still run; a Watching that throws logs one Type 3 warning (LOGNOW, with the request's IncidentRef)
///     and nothing changes; no matching row logs nothing.
///   - An OcuTalon.Checks.Msg.CheckChanged (WatchOps sends one after a watch is started or stopped): Checks publishes the change as a check event
///     on the owner's stream, FromRow of the row it opens by Ref for a start (nothing when the row is gone), and for a stop a payload of the message's
///     fields with stopped true. A failed publish logs one Type 3 warning (LOGPUBLISH).
///   - An OcuTalon.Checks.Msg.BeatNow (CommandsIn sends one for the RunHeartbeat command): Checks calls OcuTalon.Checks.Beat.RunNow(SessionRef, now, .item, .outcome,
///     .availableAt) (the seam BeatRunNow; now is RequestedAt when that is a UTC stamp, else the current time) and sends the Item that it returns to Intake
///     through SendOwn, as the Tick does. It answers OK with an OcuTalon.Msg.CommandResult: Ok when the outcome is sent, Outcome the outcome (sent, cooldown, the
///     reason that held the beat, or failed), Ref the ItemId when sent, Data {"availableAt": <UTC time>} when there is one, and no Message. An error status or
///     an exception from RunNow logs one Type 3 warning (LOGBEATNOW), a failed send one (LOGBEATSEND), and the outcome becomes failed. No log line names a
///     SessionRef. The views that RunNow gave are published after the send, as the Tick's are, whatever the outcome.
/// One run of a row:
///   - Read: Watch.Reader.Failures (the seam Read) from Watch.Mark.Start(LastRunAt, CreatedAt, now), the previous run less Mark.OVERLAP seconds, else
///     the watch's creation, at most Mark.MAXFAILURES failures, with the production's running state. The incidents come from the rows.
///   - Scope (AD-4): a failure is the session's when Watch.FailurePoller.Scope of its SuperSession is the row's SessionRef, or is instance and the
///     instance is not the online demo. The same rule picks the incidents of the row's namespace and production whose State is open, awaiting_approval
///     or fixing (noticed or not).
///   - Findings (Story 30.4; AC 1-3; FR-23, AD-14, AD-18, AD-30, AD-32): when the read gave the production's state (the outcome read, nothing thrown, a
///     state other than timeout, unknown and ""; a run that is not_checked only because the read was cut or the incidents could not be read still counts),
///     the state and the disabled items are compared with what the row last reported (BackgroundCheck.Reported, JSON {"stopped": 1 while the stop has been
///     reported, "disabled": [the names reported disabled], "ours": [the names of the disabled items that OcuTalon suspended, only when there is one]}); Findings applies the rule. A production stopped or suspended since the last run is one finding,
///     and each item disabled since is one, in the order the reader gave them; an item that OcuTalon itself suspended (Fix.Run Suspended, Story 23.2) is recorded in Reported but gets no finding, and a disable by anyone else after that (the item enabled and disabled again) does, while a second suspend by OcuTalon does not; an item whose suspend belongs to a closed incident (Fix.Run Suspended's released, Story 23.9) and that was in the previous ours is reported once, with the suspend's end as its time, and leaves ours;
///     troubled, network_stopped and a restart are not stops, and a restart makes the
///     next stop new. A row whose Reported is empty (a new watch, or one from before this story) only records its baseline: the first reading run reports
///     nothing. A run that read no state leaves Reported as it was. Each finding is one OcuTalon.Msg.Item for Intake only (Channel system, Provenance
///     untrusted, a new ItemId, the row's SessionRef as owner, the Text TEXTSTOPPED or TEXTDISABLED with the display name, CatalogKey watch.productionStopped or
///     watch.itemDisabled, and Slots {"production", "time"} or {"itemName", "production", "time"}): producers never render. {time} is the stop time that IRIS
///     recorded for a stopped production (UTC to the second), else the time of the run; for a disabled item, which IRIS gives no time for, it is the run time,
///     so it can be up to one check interval after the change (AD-15 states that a change's time is known only to within the check interval); for an item that OcuTalon suspended and whose incident was then closed it is the end of the suspend.
///   - Result, the first rule that holds: not_checked with one reason (REASONUNREADABLE, REASONNOTCURRENT, REASONTIMEOUT, REASONREAD when the read
///     threw, the state is unknown or the incidents could not be read, REASONTOOMANY when the read was cut at its limit and none of its rows is the
///     session's); failed when the state is not running, or the session has a new failure, or an unclosed incident; else passed. The finding of a
///     failed check joins up to three parts with ", " and an upper-case first letter: the state, the new failures (counted; "at least" when the read
///     was cut) and the most urgent unclosed incident. The texts are the FINDING* and REASON* parameters, built by code: no error text, event-log
///     text or diagnosis text ever reaches a finding, which Story 5.7's check_status trusts.
///   - The live-read rules are public class methods, so that Checks.Coverage Live (the digest's coverage rows) applies the same ones as a run and the two
///     cannot drift: NotCheckedReason (the reason chain above), ScopedFailures (the failures that are the session's), IsCut (the read stopped at its
///     limit), StateText, FailureText and Joined (the join and the upper-case first letter), which Finding is built from.
///   - Record: one SQL UPDATE keyed by Ref sets LastRunAt, Result, Finding, LastRunHeaderId (this process's %SessionId: the Tick's trace session, or
///     for a CheckNow the incident's (AD-26)), NextDueAt (the tick time plus INTERVALSECONDS; a CheckNow's run, with keep, leaves NextDueAt out) and Reported. Checks writes only these fields, and never re-creates a row: when no row is
///     updated (the watch was stopped meanwhile) nothing more happens, and nothing is sent. Only then is each finding sent (SendFinding), each in a trace
///     session of its own, as AD-26 gives every untrusted item (%SessionId is cleared for the send), with the TraceRef of the row's session as SuperSession;
///     the process's own %SessionId and SuperSession are put back after each send. A send that fails or throws logs one Type 3 warning (LOGFINDING, with
///     the check's Ref), is never retried (its finding is already in Reported), and the other findings still go.
///   - Event and log line: the row is opened again by Ref and published as a check event (Live.Payload.Check.FromRow) after the update's commit
///     (LOGPUBLISH on a failure), and one Type 4 line (LOGRAN) names the check's Ref, display name, result and finding in the Tick's session.
///   - Queue rows (Story 23.7; AD-18; FR-33): after the production checks of a Tick, each row of Kind QUEUEKIND that is due (the same due rule, DueOf) runs once
///     through RunQueues, each in its own Try (LOGRUN), the list read in a Try of its own (LOGDUE). A run reads, through Watch.Reader alone (ReadEntries, then
///     ReadQueues for each entry: Failures with limit 0), the queues of every production that Reader.Productions lists, and sends one Item (CatalogKey KEYQUEUE,
///     Channel system, Provenance untrusted, the row's SessionRef as owner, TEXTQUEUE or TEXTQUEUEONE) for each queue that Checks.Queues Crossings reports, with
///     the limits of Checks.Coverage CurrentLimits. The row's Reported holds the crossings that Crossings keeps. A run that lists no production, cannot list
///     them, or cannot read a listed namespace is not_checked with REASONREAD, REASONUNREADABLE or REASONNOTCURRENT (the first unread namespace in list order),
///     never passed; the crossings of the namespaces that were read are still sent. Else the run is failed with FINDINGQUEUE or FINDINGQUEUES while any
///     queue is above its limits, else passed. Record's row-count rule applies: a watch stopped meanwhile records, sends and publishes nothing.
///   - Source rows (Story 22.11; AD-18, AD-21, AD-30, AD-33): after the queue rows of a Tick, each row of Kind SOURCEKIND that is due runs through RunSources, unless the install is the online
///     demo (nothing runs, nothing is recorded). At most one poll is in flight: a source's Reported holds inflight, the send time, from its send to
///     the record of its answer, and a due source that is not stopped sends nothing, and keeps its NextDueAt, while another source holds a mark younger than INFLIGHTSECONDS, so TriageAgent
///     never holds more than one poll. For each due row that sends, one UPDATE sets NextDueAt to the tick time plus the row's IntervalMinutes, at the send. A source whose tool is no longer
///     Read-only (the seam SourceClass) makes no call: it records not_checked with REASONNOTREADONLY at once (keep 1), and the transition to stopped sends the admins mcp.sourceStopped once
///     (the seam StopNotice, Mcp.Ops SourceStopped). Any other source is sent one asynchronous request of kind tool and provenance untrusted to POLLTARGET (the seam SendPoll), whose Input
///     is {"source": <the Ref>} and nothing else, in the Tick's session, with the completion key <Ref>|<the send time>. The answer reaches OnResponse (a failed call reaches OnError, which
///     reads it as a failed poll). The row is read again; a missing row records nothing, and so does a send time before the row's CreatedAt (the answer of a poll made before a repoint).
///     Reported is {"seen": [at most 50 SHA-256 hex hashes of whole answers, newest last], "baseline": 1 once a run succeeded, "stopped": "" or "not_read_only"}, and starts as {} when
///     LastRunAt is empty or before CreatedAt. The Reply maps to the run: no FailureText is passed (the first one since CreatedAt is the baseline and sends no Item; later an answer whose
///     hash is not in seen sends one Item, Channel system, Provenance untrusted, Subject the source's name, Text the answer; an empty answer is passed and never an Item); notreadonly and
///     changed are stopped; denied is stopped when the tool is no longer Read-only, else REASONREAD; unreachable is REASONSOURCEUNREACHABLE; timeout is REASONTIMEOUT; any other word is
///     REASONREAD. A run that is not a stop clears stopped. Record is called with keep 1, so the send's NextDueAt stands. The latest run counts (DW-1326), and no argument value, URL or
///     secret reaches a request, log line, finding or notice.
/// Nothing that decides "due" or "new" lives in memory (AD-5). The only namespace switch is in Watch.Reader (AD-3). This class is the only one that
/// publishes the check event and the heartbeat event.
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

/// The configuration item that gets the Tick after the checks of the tick, so that it can send the digest that is due (AD-18).
Parameter DIGEST = "Digest";

/// The origin of a command from the heartbeat.
Parameter TIMER = "timer";

/// The only kind of check that runs.
Parameter KIND = "production";

/// The live event type of a check.
Parameter CHECKEVENT = "check";

/// The live event type of a person's heartbeat.
Parameter HEARTBEATEVENT = "heartbeat";

/// The scope of what no session owns, and the owner literals that have no trace of their own.
Parameter INSTANCE = "instance";

Parameter EVAL = "eval";

/// The columns of a BackgroundCheck row that Due and Watching select, in the order that RowOf reads them.
Parameter ROWCOLUMNS = "Ref, SessionRef, Namespace, Production, DisplayName, CreatedAt, LastRunAt, NextDueAt, Reported, Server, Tool, IntervalMinutes";

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

Parameter LOGNOW = "Checks could not read the checks to run now for incident ";

Parameter LOGFINDING = "Checks could not send a finding of check ";

Parameter LOGBEAT = "Checks could not run the heartbeat's due beats: ";

Parameter LOGBEATNOW = "Checks could not run a requested heartbeat: ";

Parameter LOGBEATSEND = "Checks could not send a heartbeat beat, item ";

Parameter LOGBEATPUBLISH = "Checks could not publish a heartbeat event: ";

/// The text of a finding Item (public text, veto U-180; the first line becomes the item summary): {production} is the display name, {itemName} the item's name.
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
		If request.%IsA("OcuTalon.Checks.Msg.CheckNow") Quit ..Now(request)
		If request.%IsA("OcuTalon.Checks.Msg.BeatNow") Quit ..BeatNow(request, .response)
	}
	Quit $SYSTEM.Status.Error(5001, "Checks does not handle a request of the class '"_$Select($IsObject(request): $ClassName(request), 1: "none")_"'")
}

/// A Tick: the quiet sweep, then the fixes (Fixes), then the checks that are due, then the heartbeat's due beats (see the class description). Always OK.
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
	Try {
		Set due = ..QueueDue(tickAt)
		Set iterator = due.%GetIterator()
		While iterator.%GetNext(, .row) {
			Try {
				Do ..RunQueues(row, tickAt)
			} Catch exception {
				$$$LOGWARNING(..#LOGRUN_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGDUE_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Try {
		Do ..RunSources(tickAt)
	} Catch exception {
		$$$LOGWARNING(..#LOGDUE_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Do ##class(OcuTalon.Watch.SettingHistory).Watch(tickAt)
	Set items = ""
	Kill views
	Try {
		Set sc = ..BeatRunDue(tickAt, .items, .views)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGBEAT_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGBEAT_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	If $IsObject(items) {
		For i = 1:1:items.Count() {
			Set item = items.GetAt(i)
			Set sc = ..SendOwn(item)
			If $$$ISERR(sc) {
				$$$LOGWARNING(..#LOGBEATSEND_item.ItemId_": "_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)), item.SessionRef))
			}
		}
	}
	Do ..AnnounceBeats(.views)
	Try {
		Set sc = ..SendRequestAsync(..#DIGEST, tick, 0)
		If $$$ISERR(sc) $$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	} Catch exception {
		$$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// A CheckNow: each row that Watching gives runs once through Run with keep (see the class description). Always OK.
Method Now(request As OcuTalon.Checks.Msg.CheckNow) As %Status [ Private ]
{
	Try {
		Set rows = ..Watching(request.Namespace, request.Production, request.OwnerRef)
		Set iterator = rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			Try {
				Do ..Run(row, "", 1)
			} Catch exception {
				$$$LOGWARNING(..#LOGRUN_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGNOW_request.IncidentRef_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// A BeatNow: Beat.RunNow for the request's session, the Item it returns sent to Intake, and a CommandResult as the answer (see the class description). Always OK.
Method BeatNow(request As OcuTalon.Checks.Msg.BeatNow, Output response As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set now = $Select(request.RequestedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z": request.RequestedAt, 1: ##class(OcuTalon.Data.Time).NowUtc())
	Set item = ""
	Set outcome = ""
	Set availableAt = ""
	Kill views
	Try {
		Set sc = ..BeatRunNow(request.SessionRef, now, .item, .outcome, .availableAt, .views)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGBEATNOW_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)), request.SessionRef))
			Set outcome = ##class(OcuTalon.Checks.Beat).#FAILED
			Set item = ""
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGBEATNOW_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()), request.SessionRef))
		Set outcome = ##class(OcuTalon.Checks.Beat).#FAILED
		Set item = ""
	}
	If $IsObject(item) {
		Set sc = ..SendOwn(item)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGBEATSEND_item.ItemId_": "_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)), item.SessionRef))
			Set outcome = ##class(OcuTalon.Checks.Beat).#FAILED
			Set item = ""
		}
	}
	Do ..AnnounceBeats(.views)
	Set sent = (outcome = ##class(OcuTalon.Checks.Beat).#SENT)
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	Set response.Ok = sent
	Set response.Outcome = outcome
	Set response.Ref = $Select(sent && $IsObject(item): item.ItemId, 1: "")
	Set response.Data = $Select(availableAt '= "": {"availableAt": (availableAt)}.%ToJSON(), 1: "")
	Quit $$$OK
}

/// The text with every occurrence of the SessionRef taken out, in any case (a uniqueness error of %Save prints the collated, upper-case value), so that a log
/// line never names a person's session.
ClassMethod WithoutRef(text As %String, sessionRef As %String) As %String [ Private ]
{
	Quit $Select(sessionRef = "": text, 1: $Replace(text, sessionRef, "", 1, -1, 1))
}

/// The heartbeat's due beats at the tick time: OcuTalon.Checks.Beat.RunDue, with the Items to send in items and the views to publish in views (a seam for the tests).
Method BeatRunDue(tickAt As %String, Output items As %ListOfObjects, Output views) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Checks.Beat).RunDue(tickAt, .items, , , , .views)
}

/// The requested beat of the session at now: OcuTalon.Checks.Beat.RunNow, with the views to publish in views (a seam for the tests).
Method BeatRunNow(sessionRef As %String, now As %String, Output item As OcuTalon.Msg.Item, Output outcome As %String, Output availableAt As %String, Output views) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Checks.Beat).RunNow(sessionRef, now, .item, .outcome, .availableAt, , , .views)
}

/// Publishes each view of a Beat call, in order (views is the count, views(n) the SessionRef, views(n, "payload") the Live.Payload.Heartbeat). Never throws.
Method AnnounceBeats(ByRef views) [ Private ]
{
	For i = 1:1:+$Get(views) {
		If $Data(views(i, "payload")) Do ..AnnounceBeat(views(i), views(i, "payload"))
	}
}

/// Publishes the payload as a heartbeat event on the session's stream, after the row has committed (PublishBeat). A publish that answers an error status or throws
/// logs one Type 3 warning (LOGBEATPUBLISH) with the error text redacted and without the SessionRef, in any case. Never throws.
Method AnnounceBeat(sessionRef As %String, payload As OcuTalon.Live.Payload.Heartbeat) [ Private ]
{
	Try {
		Set sc = ..PublishBeat(sessionRef, payload)
		If $$$ISERR(sc) {
			$$$LOGWARNING(..#LOGBEATPUBLISH_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)), sessionRef))
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGBEATPUBLISH_..WithoutRef(##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()), sessionRef))
	}
}

/// Publishes the heartbeat event: Live.Publish.Publish (a seam for the tests).
Method PublishBeat(sessionRef As %String, payload As OcuTalon.Live.Payload.Heartbeat) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Live.Publish).Publish(sessionRef, ..#HEARTBEATEVENT, payload)
}

/// Sends Intake the Item in a trace session of its own, with the TraceRef of the Item's owner as SuperSession (AD-26); this process's own %SessionId and
/// SuperSession are put back after the send. The status of the send; a throw is its error status.
Method SendOwn(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set saved = ..%SuperSession
	Set session = ..%SessionId
	Try {
		Set ..%SessionId = ""
		Set ..%SuperSession = ..TraceOf(item.SessionRef)
		Set sc = ..SendFinding(item)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ..%SessionId = session
	Set ..%SuperSession = saved
	Quit sc
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
	Quit ..DueOf(tickAt, ..#KIND)
}

/// The rows of Kind production with the namespace and production whose scope includes the owner (InScope, with the online demo as it is now), as the
/// dynamic array of Due's row objects, in the order of the rows: a session's owner gives its row only, instance every session's row (none on the online
/// demo), eval or an empty owner none. A row of the session eval (an evaluation run's watch, never due for Checks) is never given, whatever the owner.
Method Watching(namespace As %String, production As %String, ownerRef As %String) As %DynamicArray [ Private ]
{
	Set rows = []
	If (ownerRef = "") || (ownerRef = ..#EVAL) Quit rows
	Set onlineDemo = ##class(OcuTalon.Watch.Reader).OnlineDemo()
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT "_..#ROWCOLUMNS_" FROM OcuTalon_Data.BackgroundCheck WHERE Kind = ? AND Namespace = ? AND Production = ? ORDER BY ID", ..#KIND, namespace, production)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The checks could not be read: "_rs.%Message))
	While rs.%Next() {
		Set row = ..RowOf(rs)
		If row.sessionRef = ..#EVAL Continue
		If ..InScope(ownerRef, row.sessionRef, onlineDemo) Do rows.%Push(row)
	}
	Quit rows
}

/// The row object of a result set positioned on a BackgroundCheck row of ROWCOLUMNS: {"ref", "sessionRef", "namespace", "production", "displayName",
/// "createdAt", "lastRunAt", "reported", "nextDueAt", "server", "tool", "interval"} (the last three are a source row's).
Method RowOf(rs As %SQL.StatementResult) As %DynamicObject [ Private ]
{
	Quit {"ref": (rs.%GetData(1)), "sessionRef": (rs.%GetData(2)), "namespace": (rs.%GetData(3)), "production": (rs.%GetData(4)), "displayName": (rs.%GetData(5)), "createdAt": (rs.%GetData(6)), "lastRunAt": (rs.%GetData(7)), "reported": (rs.%GetData(9)), "nextDueAt": (rs.%GetData(8)), "server": (rs.%GetData(10)), "tool": (rs.%GetData(11)), "interval": (rs.%GetData(12))}
}

/// 1 when an incident of this owner counts for the session's row (AD-4): the owner is the session, or is INSTANCE while the instance is not the online
/// demo (onlineDemo). The one scope rule of Unclosed and of a CheckNow.
ClassMethod InScope(owner As %String, sessionRef As %String, onlineDemo As %Boolean) As %Boolean
{
	Quit (owner = sessionRef) || ((owner = ..#INSTANCE) && 'onlineDemo)
}

/// One run of a due row (see the class description): the read, the result, the record, the event and the log line. keep 1 (a CheckNow) leaves the row's
/// NextDueAt as it was (see Record).
Method Run(row As %DynamicObject, tickAt As %String, keep As %Boolean = 0) [ Private ]
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
	Set failures = ..ScopedFailures(rows, row.sessionRef, onlineDemo)
	Set cut = ..IsCut(rows, limit)
	Set incident = ""
	Set unread = 0
	If (outcome = "read") && 'threw {
		Try {
			Set incident = ..Unclosed(row, onlineDemo)
		} Catch exception {
			Set unread = 1
		}
	}
	Set reason = ..NotCheckedReason(outcome, state, threw || unread, cut, failures)
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
		Set suspended = ##class(OcuTalon.Fix.Run).Suspended(row.namespace, row.production, row.lastRunAt, .fresh, , .released)
		Set found = ..Findings(row.reported, state, disabled, .reported, suspended, fresh, released)
		Set iterator = found.%GetIterator()
		While iterator.%GetNext(, .one) {
			If one.kind = "stopped" {
				Set at = ##class(OcuTalon.Watch.Mark).FailedAt(stoppedAt)
				Do items.Insert(..FindingItem(row, ..#KEYSTOPPED, ..#TEXTSTOPPED, {}, $Select(at '= "": at, 1: runAt)))
			} Else {
				Do items.Insert(..FindingItem(row, ..#KEYDISABLED, ..#TEXTDISABLED, {"itemName": (one.item)}, $Select(one.at '= "": one.at, 1: runAt)))
			}
		}
	}
	Do ..Record(row, tickAt, runAt, result, finding, reported, items, keep)
}

/// Records the run and what it reported on the row by Ref, then sends the findings (items, a %ListOfObjects of OcuTalon.Msg.Item), publishes the row and logs
/// the run (see the class description). Nothing at all when no row is updated. With keep 1 the UPDATE leaves NextDueAt out, so the schedule stays as it was.
Method Record(row As %DynamicObject, tickAt As %String, runAt As %String, result As %String, finding As %String, reported As %String, items As %ListOfObjects, keep As %Boolean = 0) [ Private ]
{
	If keep {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ?, Finding = ?, LastRunHeaderId = ?, Reported = ? WHERE Ref = ?", runAt, result, finding, ..%SessionId, reported, row.ref)
	} Else {
		Set nextDueAt = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, ..#INTERVALSECONDS))
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ?, Finding = ?, LastRunHeaderId = ?, NextDueAt = ?, Reported = ? WHERE Ref = ?", runAt, result, finding, ..%SessionId, nextDueAt, reported, row.ref)
	}
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The run could not be recorded: "_rs.%Message))
	If +rs.%ROWCOUNT < 1 Quit
	For i = 1:1:items.Count() {
		Set item = items.GetAt(i)
		Set sc = ..SendOwn(item)
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
/// {"kind": "disabled", "item"} (with "at", the time of the suspend, for an item of released), the stop first and the items in the order of disabled, and reported is the Reported to store. Empty previous (or one
/// that is not JSON) is a baseline: no finding, and reported records the state. A state of timeout, unknown or "" was not read: no finding, and reported
/// is previous, unchanged. suspended is a list of the item names that OcuTalon itself suspended (Fix.Run Suspended); reported may also carry "ours", the names of those items that
/// were disabled when sighted, written only when there is one. A disabled item that suspended lists gets no finding when it is not in the previous ours (it is added to ours), so that a
/// suspend the user approved is not reported as a new state change (Story 23.2); when it is in the previous ours and was not in the previous disabled, someone else disabled it again
/// and it is a finding, unless fresh (Fix.Run Suspended's names whose suspending run ended since the previous run) lists it: then OcuTalon suspended it again. The new ours is the
/// previous ours restricted to suspended, plus the names just added; a baseline records the disabled names that suspended lists. An item that
/// suspended does not list follows the plain rule: a finding when it was not in the previous disabled, except that released (Fix.Run Suspended's released: a %DynamicObject
/// from an item whose suspend belongs to a closed incident to that suspend's end, or "") gives a disabled item that is in the previous ours the finding {"kind": "disabled", "item",
/// "at": the released time} whether or not it was in the previous disabled, and it is not kept in ours, so that it is reported once.
ClassMethod Findings(previous As %String, state As %String, disabled As %DynamicArray, Output reported As %String, suspended As %List = "", fresh As %List = "", released As %DynamicObject = "") As %DynamicArray
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
	Set ours = []
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
		If $IsObject(before.ours) {
			Set iterator = before.ours.%GetIterator()
			While iterator.%GetNext(, .name) {
				Set wasOurs(name) = ""
				If $ListFind(suspended, name) Do ours.%Push(name, "string")
			}
		}
	}
	Set iterator = names.%GetIterator()
	While iterator.%GetNext(, .name) {
		If $ListFind(suspended, name) {
			If '$Data(wasOurs(name)) {
				Do ours.%Push(name, "string")
			} ElseIf '$Data(seen(name)) && '$ListFind(fresh, name) {
				Do found.%Push({"kind": "disabled", "item": (name)})
			}
		} ElseIf $IsObject(released) && $Data(wasOurs(name)) && (released.%Get(name) '= "") {
			Do found.%Push({"kind": "disabled", "item": (name), "at": (released.%Get(name))})
		} ElseIf $IsObject(before) && '$Data(seen(name)) {
			Do found.%Push({"kind": "disabled", "item": (name)})
		}
	}
	Set now = {}
	Do now.%Set("stopped", stopped, "number")
	Do now.%Set("disabled", names)
	If ours.%Size() Do now.%Set("ours", ours)
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
	Set item.Text = $Replace($Replace(text, "{production}", row.displayName), "{itemName}", slots.itemName)
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
		If '..InScope(owner, row.sessionRef, onlineDemo) Continue
		Set state = rs.%GetData(2)
		If state = awaiting Set urgent = state
		If (state = fixing) && (urgent '= awaiting) Set urgent = state
		If (state = open) && (urgent = "") Set urgent = state
	}
	Quit urgent
}

/// The reason that a live read of a production could not be checked, or "" when it can: the one reason chain of Run and of Checks.Coverage Live. outcome
/// is the read's outcome (read, unreadable or not_current), state the production's running state, unread 1 when the read threw or anything else it
/// needs (the incidents) could not be read, cut 1 when the read stopped at its limit, and failures the session's scoped failures (ScopedFailures). The
/// first rule that holds: REASONUNREADABLE (outcome unreadable), REASONNOTCURRENT (outcome not_current), REASONTIMEOUT (state timeout), REASONREAD (unread,
/// an outcome other than read, or a state that is unknown or empty), REASONTOOMANY (cut with no failure of the session).
ClassMethod NotCheckedReason(outcome As %String, state As %String, unread As %Boolean, cut As %Boolean, failures As %Integer) As %String
{
	Set reason = $Case(outcome, "unreadable": ..#REASONUNREADABLE, "not_current": ..#REASONNOTCURRENT, : "")
	If reason '= "" Quit reason
	If state = "timeout" Quit ..#REASONTIMEOUT
	If unread || (outcome '= "read") || (state = "unknown") || (state = "") Quit ..#REASONREAD
	If cut && (failures = 0) Quit ..#REASONTOOMANY
	Quit ""
}

/// The number of the failures in rows (a dynamic array of the read's failures, each with a superSession) that are the session's (AD-4): the scope of
/// a failure's SuperSession (Watch.FailurePoller Scope) is sessionRef, or is INSTANCE while the instance is not the online demo (onlineDemo). rows
/// must be a dynamic array: anything else throws, as a read that gave no array does in a run.
ClassMethod ScopedFailures(rows As %DynamicArray, sessionRef As %String, onlineDemo As %Boolean) As %Integer
{
	Set count = 0
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set scope = ##class(OcuTalon.Watch.FailurePoller).Scope(failure.superSession)
		If (scope = sessionRef) || ((scope = ..#INSTANCE) && 'onlineDemo) Set count = count + 1
	}
	Quit count
}

/// 1 when the read was cut at its limit: rows, the dynamic array of its failures, holds at least limit of them.
ClassMethod IsCut(rows As %DynamicArray, limit As %Integer) As %Boolean
{
	Quit rows.%Size() '< limit
}

/// The part of a finding that names a production state that is not running (FINDINGSTOPPED, FINDINGSUSPENDED, FINDINGTROUBLED or FINDINGNOTRUNNING for a
/// network_stopped one), or "" for any other state.
ClassMethod StateText(state As %String) As %String
{
	Quit $Case(state, "stopped": ..#FINDINGSTOPPED, "suspended": ..#FINDINGSUSPENDED, "troubled": ..#FINDINGTROUBLED, "network_stopped": ..#FINDINGNOTRUNNING, : "")
}

/// The part of a finding that counts the new failures (failures, at least 1): FINDINGATLEAST when the read was cut, else FINDINGFAILURE for one and
/// FINDINGFAILURES for more, with {count} put in.
ClassMethod FailureText(failures As %Integer, cut As %Boolean) As %String
{
	Quit $Replace($Select(cut: ..#FINDINGATLEAST, failures = 1: ..#FINDINGFAILURE, 1: ..#FINDINGFAILURES), "{count}", failures)
}

/// The finding that joins its parts (a $List of texts) with ", " and makes the first letter upper case; "" when there is no part.
ClassMethod Joined(parts As %List) As %String
{
	Set finding = $ListToString(parts, ", ")
	Quit $ZConvert($Extract(finding), "U")_$Extract(finding, 2, *)
}

/// The finding of a failed run, or "" when the run passed: the state, the new failures and the incident, as the class description gives them,
/// built from StateText, FailureText and Joined.
ClassMethod Finding(state As %String, failures As %Integer, cut As %Boolean, incident As %String) As %String [ Private ]
{
	Set parts = ""
	Set stateText = ..StateText(state)
	If stateText '= "" Set parts = parts_$ListBuild(stateText)
	If failures > 0 Set parts = parts_$ListBuild(..FailureText(failures, cut))
	Set incidentText = $Case(incident, ##class(OcuTalon.Watch.Transitions).#AWAITING: ..#FINDINGAWAITING, ##class(OcuTalon.Watch.Transitions).#FIXING: ..#FINDINGFIXING, ##class(OcuTalon.Watch.Transitions).#OPEN: ..#FINDINGOPEN, : "")
	If incidentText '= "" Set parts = parts_$ListBuild(incidentText)
	Quit ..Joined(parts)
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

/// Sends Intake the Item of a finding or a beat, asynchronously, with no answer wanted, with this process's %SessionId and SuperSession as SendOwn set them (a seam
/// for the tests).
Method SendFinding(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#INTAKE, item, 0)
}

/// The check of a queue-backlog row (see the class description).
Parameter QUEUEKIND = "queues";

/// The catalog key of a queue-backlog finding (Msg.Catalog.Watch).
Parameter KEYQUEUE = "watch.queueBacklog";

/// The text of a queue-backlog finding Item (public text; the first line becomes the item summary): {itemName} is the queue's item, {production} the
/// production's display name, {count} the number of messages.
Parameter TEXTQUEUE = "The {itemName} queue in the {production} production has {count} messages waiting.";

Parameter TEXTQUEUEONE = "The {itemName} queue in the {production} production has 1 message waiting.";

/// The finding of a queue-backlog row that has queues above their limits (public text; {count} is the number of queues).
Parameter FINDINGQUEUE = "1 queue over its threshold";

Parameter FINDINGQUEUES = "{count} queues over their threshold";

/// The rows of the Kind that are due at the tick time, as a dynamic array of the row objects of RowOf, in the order of the rows: those whose NextDueAt is
/// empty or at most DUESLACKSECONDS after the tick time.
Method DueOf(tickAt As %String, kind As %String) As %DynamicArray [ Private ]
{
	Set due = []
	Set limit = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, ..#DUESLACKSECONDS))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT "_..#ROWCOLUMNS_" FROM OcuTalon_Data.BackgroundCheck WHERE Kind = ? ORDER BY ID", kind)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The checks could not be read: "_rs.%Message))
	While rs.%Next() {
		Set next = rs.%GetData(8)
		If (next '= "") && (next ] limit) Continue
		Do due.%Push(..RowOf(rs))
	}
	Quit due
}

/// The queue-backlog checks that are due at the tick time (DueOf with QUEUEKIND).
Method QueueDue(tickAt As %String) As %DynamicArray [ Private ]
{
	Quit ..DueOf(tickAt, ..#QUEUEKIND)
}

/// One run of a queue-backlog row (see the class description): the read of every listed production's queues, the crossings, the result and the record.
Method RunQueues(row As %DynamicObject, tickAt As %String) [ Private ]
{
	Set runAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set nowSeconds = ##class(OcuTalon.Data.Time).Seconds(runAt)
	Set reason = ""
	Set entries = ""
	Set readings = []
	Try {
		Set entries = ..ReadEntries()
	} Catch exception {
		Set entries = ""
		Set reason = ..#REASONREAD
		$$$LOGWARNING(..#LOGREAD_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	If (reason = "") && ('$IsObject(entries) || 'entries.%Size()) Set reason = ..#REASONREAD
	Set listed = (reason = "")
	If listed {
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set outcome = ""
			Set queues = ""
			Try {
				Set outcome = ..ReadQueues(entry.namespace, entry.production, .queues)
			} Catch exception {
				Set outcome = ""
				Set queues = ""
				$$$LOGWARNING(..#LOGREAD_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
			Set readOk = (outcome = "read") && $IsObject(queues) && queues.%IsA("%Library.DynamicArray")
			If 'readOk && (reason = "") Set reason = $Case(outcome, "unreadable": ..#REASONUNREADABLE, "not_current": ..#REASONNOTCURRENT, : ..#REASONREAD)
			Do readings.%Push({"namespace": (entry.namespace), "production": (entry.production), "displayName": (entry.displayName), "read": (readOk), "queues": ($Select(readOk: queues, 1: []))})
		}
	}
	Set reported = row.reported
	Set items = ##class(%ListOfObjects).%New()
	Set above = 0
	If listed {
		Set limit = ##class(OcuTalon.Checks.Coverage).CurrentLimits()
		Set found = ##class(OcuTalon.Checks.Queues).Crossings(row.reported, readings, limit, nowSeconds, .reported)
		Set iterator = readings.%GetIterator()
		While iterator.%GetNext(, .reading) {
			Set queueIterator = reading.queues.%GetIterator()
			While queueIterator.%GetNext(, .queue) {
				If ##class(OcuTalon.Checks.Queues).Over(queue, limit, nowSeconds) Set above = above + 1
			}
		}
		Set iterator = found.%GetIterator()
		While iterator.%GetNext(, .one) {
			Set oldestAt = $Select(##class(OcuTalon.Data.Time).Seconds(one.oldestAt) '= "": one.oldestAt, 1: runAt)
			Set slots = {}
			Do slots.%Set("itemName", one.item, "string")
			Do slots.%Set("count", one.count, "number")
			Do slots.%Set("oldestAt", oldestAt, "string")
			Set text = $Replace($Select(one.count = 1: ..#TEXTQUEUEONE, 1: ..#TEXTQUEUE), "{count}", one.count)
			Do items.Insert(..FindingItem({"sessionRef": (row.sessionRef), "displayName": (one.displayName)}, ..#KEYQUEUE, text, slots, runAt))
		}
	}
	If reason '= "" {
		Set result = "not_checked"
		Set finding = reason
	} ElseIf above {
		Set result = "failed"
		Set finding = ..Joined($ListBuild($Replace($Select(above = 1: ..#FINDINGQUEUE, 1: ..#FINDINGQUEUES), "{count}", above)))
	} Else {
		Set result = "passed"
		Set finding = ""
	}
	Do ..Record(row, tickAt, runAt, result, finding, reported, items)
}

/// The productions whose queues a queue-backlog run reads: OcuTalon.Watch.Reader.Productions, a dynamic array of {"namespace", "production",
/// "displayName"}. A seam for the tests.
Method ReadEntries() As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Productions()
}

/// The queues of the production, as the dynamic array of {"name", "count", "oldestAt"} in queues ("" when they could not be read), and the outcome of
/// the read (read, unreadable or not_current): OcuTalon.Watch.Reader.Failures with limit 0, which reads no failure. A seam for the tests.
Method ReadQueues(namespace As %String, production As %String, Output queues As %DynamicArray) As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Failures(namespace, production, "", 0, , , , , , .queues)
}

/// The kind of a source row (Story 22.5), the Watch.Ops SOURCEKIND: a Read-only MCP tool that is polled on a schedule. Story 22.11 runs it.
Parameter SOURCEKIND = "source";

/// The finding of a source run that could not reach the tool's MCP server (public text), written by the run of Story 22.11. Coverage ReasonOf maps it to unreachable.
Parameter REASONSOURCEUNREACHABLE = "Couldn't reach its MCP server";

/// The finding of a source run that was not made because the source's tool is no longer Read-only (public text), written by the run of Story 22.11. Coverage ReasonOf
/// maps it to stopped.
Parameter REASONNOTREADONLY = "Its tool is no longer Read-only";

/// The completion key of a poll whose error OnError has recorded, until the OnResponse call that follows it for the same key has been skipped.
Property ErroredKey As %String(MAXLEN = 100) [ Internal, Transient ];

/// The class whose SourceStopped tells the admins that a source stopped (Mcp.Ops; the tests name a probe).
Parameter OPSCLASS = "OcuTalon.Mcp.Ops";

/// The configuration item that runs a source poll (the Decide process).
Parameter POLLTARGET = "Decide";

/// The most hashes of whole answers that a source row's Reported keeps.
Parameter SEENMAX = 50;

/// The value of stopped in a source row's Reported.
Parameter STOPPEDVALUE = "not_read_only";

/// How long a poll's in-flight mark counts, in seconds: Decide answers a poll within its timer (110 seconds at most), so an older mark is stale.
Parameter INFLIGHTSECONDS = 150;

Parameter LOGPOLL = "Checks could not poll source ";

Parameter LOGPOLLSEND = "Checks could not send the poll of source ";

Parameter LOGPOLLANSWER = "Checks could not record the answer of source ";

/// The summary of the request of a source poll.
Parameter POLLSUMMARY = "Source poll";

/// Runs the sources that are due at the tick time (see the class description): nothing on the online demo. At most one poll is in flight (PollInFlight): a
/// source that is due while another's poll is outstanding sends nothing and keeps its NextDueAt, so it polls at a later Tick. The due sources run oldest NextDueAt first (a source that has
/// never run first), so that a source that waits is never passed over by one that is due again. Each row runs in a Try of its own (LOGPOLL).
Method RunSources(tickAt As %String) [ Private ]
{
	If ..PollsOff() Quit
	Set busy = ..PollInFlight()
	Set due = ..DueOf(tickAt, ..#SOURCEKIND)
	Kill order
	Set iterator = due.%GetIterator()
	While iterator.%GetNext(.position, .row) {
		Set order(row.nextDueAt _ "|" _ $Justify(position, 8)) = row
	}
	Set key = ""
	For {
		Set key = $Order(order(key), 1, row)
		Quit:key=""
		Try {
			If ..PollSource(row, tickAt, busy) Set busy = 1
		} Catch exception {
			$$$LOGWARNING(..#LOGPOLL_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
	}
}

/// The online demo runs no source (a seam for the tests): 1 when Watch.Reader says the install is the online demo.
Method PollsOff() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).OnlineDemo()
}

/// 1 when a source's poll is in flight: a source row whose Reported holds inflight, the send time of a poll whose answer has not been recorded, less than INFLIGHTSECONDS ago. Decide
/// answers every poll within its timer (MAXTIMER seconds at most), so an older mark is stale and counts for nothing. The state is on the rows (AD-5).
Method PollInFlight() As %Boolean [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Reported FROM OcuTalon_Data.BackgroundCheck WHERE Kind = ? AND Reported IS NOT NULL AND Reported <> ''", ..#SOURCEKIND)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The sources could not be read: "_rs.%Message))
	Set sent = ""
	While rs.%Next() {
		Try {
			Set state = ##class(%DynamicAbstractObject).%FromJSON(rs.%GetData(1))
			Set sent = $Select($IsObject(state) && (state.%GetTypeOf("inflight") = "string"): ##class(OcuTalon.Data.Time).Seconds(state.inflight), 1: "")
		} Catch {
			Set sent = ""
		}
		If (sent '= "") && ((now - sent) < ..#INFLIGHTSECONDS) Quit
		Set sent = ""
	}
	Quit (sent '= "")
}

/// One due source: a source whose tool is no longer Read-only records a stopped run at once (its NextDueAt is set to the tick time plus its interval first); another source waits, with
/// its NextDueAt as it was, while busy is 1 (a poll is in flight); any other has its NextDueAt set to the tick time plus its interval, is marked in flight and is sent its poll. 1 when a poll
/// was sent.
Method PollSource(row As %DynamicObject, tickAt As %String, busy As %Boolean) As %Boolean [ Private ]
{
	Set stopped = (..SourceClass(row.server, row.tool) '= "read-only")
	If 'stopped && busy Quit 0
	Set minutes = +row.interval
	If minutes < 1 Set minutes = 1
	Set nextDueAt = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, minutes * 60))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = ? WHERE Ref = ?", nextDueAt, row.ref)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The next due time of a source could not be set: "_rs.%Message))
	If +rs.%ROWCOUNT < 1 Quit 0
	If stopped {
		Do ..RecordSource(row, ##class(OcuTalon.Data.Time).NowUtc(), "stopped", "")
		Quit 0
	}
	Set sentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..MarkInFlight(row, sentAt)
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "tool"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = row.sessionRef
	Set request.TraceRef = ..TraceOf(row.sessionRef)
	Set request.Channel = ..#SYSTEMCHANNEL
	Set request.Summary = ..#POLLSUMMARY
	Set request.Input = {"source": (row.ref)}.%ToJSON()
	Try {
		Set sc = ..SendPoll(request, row.ref_"|"_sentAt)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPOLLSEND_row.ref_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Do ..ClearInFlight(row.ref)
		Quit 0
	}
	Quit 1
}

/// The state that a source row's Reported holds, as {"seen", "baseline", "stopped"}: empty when the row has not run since its CreatedAt (LastRunAt empty or before it), or its Reported
/// is not that shape.
Method StateOf(row As %DynamicObject) As %DynamicObject [ Private ]
{
	Set state = {"seen": [], "baseline": 0, "stopped": ""}
	If (row.lastRunAt '= "") && '(row.createdAt ] row.lastRunAt) && (row.reported '= "") {
		Try {
			Set before = ##class(%DynamicAbstractObject).%FromJSON(row.reported)
			If $IsObject(before) && (before.%GetTypeOf("seen") = "array") {
				Set state.seen = before.seen
				Set state.baseline = $Select(before.baseline = 1: 1, 1: 0)
				Set state.stopped = $Select(before.%GetTypeOf("stopped") = "string": before.stopped, 1: "")
			}
		} Catch {
		}
	}
	Quit state
}

/// Marks the source's poll as in flight: its Reported with inflight, the send time, added. The answer's record (RecordSource) writes Reported without it.
Method MarkInFlight(row As %DynamicObject, sentAt As %String) [ Private ]
{
	Set state = ..StateOf(row)
	Do state.%Set("inflight", sentAt, "string")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = ? WHERE Ref = ?", state.%ToJSON(), row.ref)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "A source's poll could not be marked: "_rs.%Message))
}

/// Takes the in-flight mark off the source's Reported (a poll that was not sent, or whose answer is dropped). Nothing happens for a row that is gone or holds no mark.
Method ClearInFlight(ref As %String) [ Private ]
{
	Set row = ..SourceRow(ref)
	If '$IsObject(row) || (row.reported = "") Quit
	Try {
		Set state = ##class(%DynamicAbstractObject).%FromJSON(row.reported)
		If '$IsObject(state) || (state.%GetTypeOf("inflight") = "unassigned") Quit
		Do state.%Remove("inflight")
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = ? WHERE Ref = ?", state.%ToJSON(), ref)
	} Catch {
	}
}

/// Sends the poll request to POLLTARGET asynchronously, wanting the answer, with the completion key (a seam for the tests).
Method SendPoll(request As OcuTalon.Bridge.Msg.Request, key As %String) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#POLLTARGET, request, 1, key)
}

/// The classification of the tool of a source as the gate reads it (OcuTalon.Mcp.ToolClassification), or "" when it has none (a seam for the tests).
Method SourceClass(server As %String, tool As %String) As %String [ Private ]
{
	Set row = $Select((server '= "") && (tool '= ""): ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, tool), 1: "")
	Quit $Select($IsObject(row): row.Classification, 1: "")
}

/// Tells the admins that the source stopped polling (a seam for the tests): Mcp.Ops SourceStopped, with the source's name, tool and server and the time. A failure is one warning.
Method StopNotice(row As %DynamicObject, time As %String) [ Private ]
{
	Set sc = $ClassMethod(..#OPSCLASS, "SourceStopped", row.displayName, row.tool, row.server, time)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPOLL_row.ref_": the stop notice was not sent")
	}
}

/// The answer of a source's poll: the Reply of Decide, with the completion key <Ref>|<sentAt> (see the class description). Any other completion key is not Checks' own and does nothing.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	If (pCompletionKey '= "") && (pCompletionKey = ..ErroredKey) {
		Set ..ErroredKey = ""
		Quit $$$OK
	}
	If $Length(pCompletionKey, "|") = 2 {
		Try {
			Do ..SourceAnswer(pCompletionKey, callresponse)
		} Catch exception {
			$$$LOGWARNING(..#LOGPOLLANSWER_$Piece(pCompletionKey, "|", 1)_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
		}
	}
	Quit $$$OK
}

/// A source's poll that Decide answered with an error status counts as a failed poll; any other error keeps its status. The host then calls OnResponse for the same key once more, and
/// that call records nothing (ErroredKey).
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If $Length(pCompletionKey, "|") '= 2 Quit pErrorStatus
	Set ..ErroredKey = pCompletionKey
	Try {
		Do ..SourceAnswer(pCompletionKey, "")
	} Catch exception {
		$$$LOGWARNING(..#LOGPOLLANSWER_$Piece(pCompletionKey, "|", 1)_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// Records the answer of a poll on its row (see the class description). reply is the Reply, or "" for a poll that failed. An answer for a target that was set again since the send
/// (a send time before the row's CreatedAt) records nothing and takes the in-flight mark off.
Method SourceAnswer(key As %String, reply As %RegisteredObject) [ Private ]
{
	Set ref = $Piece(key, "|", 1)
	Set sentAt = $Piece(key, "|", 2)
	Set row = ..SourceRow(ref)
	If '$IsObject(row) Quit
	If row.createdAt ] sentAt {
		Do ..ClearInFlight(ref)
		Quit
	}
	Set word = $Select($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"): reply.FailureText, 1: "failed")
	Set text = $Select($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"): reply.Text, 1: "")
	Set outcome = $Case(word, "": "passed", "notreadonly": "stopped", "changed": "stopped", "denied": $Select(..SourceClass(row.server, row.tool) '= "read-only": "stopped", 1: "error"), "unreachable": "unreachable", "timeout": "timeout", : "error")
	Do ..RecordSource(row, ##class(OcuTalon.Data.Time).NowUtc(), outcome, text)
}

/// The row of a source by Ref as RowOf gives it, or "" when there is none or it is not a source row.
Method SourceRow(ref As %String) As %DynamicObject [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT "_..#ROWCOLUMNS_" FROM OcuTalon_Data.BackgroundCheck WHERE Ref = ? AND Kind = ?", ref, ..#SOURCEKIND)
	If rs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The source could not be read: "_rs.%Message))
	If rs.%Next() Quit ..RowOf(rs)
	Quit ""
}

/// Records a run of a source with the outcome (passed, stopped, unreachable, timeout or error) and, for passed, the answer's text: the result, the finding and the new Reported are made
/// from it, the new result's Item (if any) is sent after the update by Record, and a transition to stopped sends the stop notice once. Record gets keep 1, so NextDueAt stays as the send set it.
/// The new Reported has no in-flight mark.
Method RecordSource(row As %DynamicObject, runAt As %String, outcome As %String, text As %String) [ Private ]
{
	Set state = ..StateOf(row)
	Set wasStopped = (state.stopped '= "")
	Set items = ##class(%ListOfObjects).%New()
	Set finding = ""
	If outcome = "passed" {
		Set result = "passed"
		Set state.stopped = ""
		Set hash = $Select(text = "": "", 1: ..HashOf(text))
		If state.baseline '= 1 {
			Set state.baseline = 1
			If hash '= "" Do state.seen.%Push(hash, "string")
		} ElseIf (hash '= "") && '..Contains(state.seen, hash) {
			Do state.seen.%Push(hash, "string")
			Do items.Insert(..SourceItem(row, text))
		}
		Set state.seen = ..Newest(state.seen)
	} Else {
		Set result = "not_checked"
		If outcome = "stopped" {
			Set finding = ..#REASONNOTREADONLY
			Set state.stopped = ..#STOPPEDVALUE
		} Else {
			Set state.stopped = ""
			Set finding = $Case(outcome, "unreachable": ..#REASONSOURCEUNREACHABLE, "timeout": ..#REASONTIMEOUT, : ..#REASONREAD)
		}
	}
	Do ..Record(row, "", runAt, result, finding, state.%ToJSON(), items, 1)
	If (outcome = "stopped") && 'wasStopped Do ..StopNotice(row, runAt)
}

/// 1 when the array holds the text (a hash that was seen before).
ClassMethod Contains(array As %DynamicArray, text As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .value) {
		If value = text {
			Set found = 1
			Quit
		}
	}
	Quit found
}

/// The newest SEENMAX hashes of the array (the array keeps them oldest first), as a new array.
ClassMethod Newest(seen As %DynamicArray) As %DynamicArray [ Private ]
{
	Set size = seen.%Size()
	If size <= ..#SEENMAX Quit seen
	Set kept = []
	For i = (size - ..#SEENMAX):1:(size - 1) {
		Do kept.%Push(seen.%Get(i), "string")
	}
	Quit kept
}

/// The SHA-256 of the UTF-8 text, as 64 lower-case hexadecimal characters.
ClassMethod HashOf(text As %String) As %String [ Private ]
{
	Set digest = $SYSTEM.Encryption.SHAHash(256, $ZConvert(text, "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(digest) {
		Set hex = hex_$ZConvert($Extract($ZHex(256 + $Ascii(digest, i)), 2, 3), "L")
	}
	Quit hex
}

/// The Item of a result that was not seen before (see the class description): a new ItemId, the row's session, Channel system, Provenance untrusted, Subject the source's name, Text the answer.
Method SourceItem(row As %DynamicObject, text As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = row.sessionRef
	Set item.Channel = ..#SYSTEMCHANNEL
	Set item.Provenance = "untrusted"
	Set item.Subject = row.displayName
	Set item.Text = text
	Quit item
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
