/// The coverage list of the daily digest (Story 17.5; AD-18, AD-28, AD-33): every entry that was or was not checked, each passed, failed, or not
/// checked with a reason. Only Checks says whether an entry passed, so the digest takes its rows and lines from here and never from a model.
///   - Build gives the rows, in this order, and never drops an entry: the five vital signs (IRIS instance, database space, journal space, license
///     use, system log), then one row per background check of the session in ID order (a source row is the entry named by its DisplayName), then the Mailbox row (see
///     MailboxRow) when the session owns the connected mailbox. A row is
///     {"result" (passed, failed or not_checked), "entry", "finding", "checkedAt" (UTC, YYYY-MM-DDThh:mm:ssZ)}, the shape that Checks.Render
///     reads. The row of a source also carries "kind" ("source"), and no other row does; Digest.Process uses it to name the entry as the admin typed it.
///     lines holds one {"key", "slots"} for each row, in the rows' order: the catalog line of the row (digest.passed, digest.failed or
///     digest.notChecked<Reason>). vitals is {"rows" (the five vital rows), "figures" {"upDays", "databasesFull", "licenseUse"}}; a figure is a
///     whole number, or "" when its sign was not read.
///   - A vital sign is read live (Watch.Reader.Vitals) against the thresholds. A sign that cannot be read is not_checked with the reason
///     Checks.Process REASONREAD, never passed. The comparisons use the unrounded readings; only the figures are rounded.
///   - database space: failed when the volume of any database has less free space than the disk threshold, whatever else was or was not read. Else
///     not_checked when a database could not be read. Else not_checked with REASONSIZELIMIT when any database has a maximum size, because its free
///     space within the maximum can only be read with the privilege %Admin_Operate:U, which OcuTalon never asks for, so a capped database never
///     gives a false all-clear. Else passed.
///   - A background check's result comes from the runs that Digest.Data.CheckRun recorded in the span, max(fromUtc, CreatedAt) to toUtc. The first
///     rule that applies wins: (1) paused: a heartbeat gap overlaps the span; (2) no run in the span: stale when an earlier run exists, else
///     missed from the span's start to toUtc; (3) missed: two consecutive runs, the span's start and the first run, or the last run and toUtc are
///     more than MISSEDSECONDS apart (the first such gap); (4) the latest run is not_checked: its reason gives error, timeout or unreachable
///     (an empty or unknown reason is error), for unreachable since the first run of the unbroken streak of unreachable runs that ends at the
///     latest, and stopped (Story 22.5: the source's tool is no longer Read-only) since the first run of the unbroken streak of stopped runs that
///     ends at the latest; (5) otherwise the latest run's result. For rule (3) the gap of a source row (Kind source) with an IntervalMinutes is
///     IntervalMinutes x 60 + MISSEDSECONDS seconds, since it runs once in each interval; any other row keeps MISSEDSECONDS.
///   - The Mailbox row (Story 22.5) is there only for the session that owns the connected mailbox (Channel.Email.In Owner) and only once the mark emailPoll
///     exists. It is passed when the mark says ok, its time is in the span and at most MAILSTALESECONDS before the end of the span; not checked when the mark says ok
///     but is older (stale); not checked as unreachable, with the time of the last good poll, for a failed poll whose reason is the adapter's REASONUNREACHABLE; and not
///     checked as an error for any other failed poll and for a mark that cannot be read.
///   - A production watch whose result comes from rule 5 adds a live read of the production (Watch.Reader.Failures, from the span's start, in one
///     switch): anything it finds makes the row failed with the live finding at the read time, and a read that cannot be made makes it not_checked
///     (unreachable, timeout or error), as the same reasons of Checks.Process do. The rules of that read are Checks.Process's public class methods
///     (NotCheckedReason, ScopedFailures, IsCut, StateText, FailureText and Joined), the ones a check's run applies, so that a row and a result cannot drift;
///     Live adds only what a run does not read (items in error, disabled items, queued and waiting messages) and picks the digest key from the reason
///     (ReasonOf and KeyOf: timeout, unreachable for an unreadable or not current namespace, else error), as RecordRun does for the CheckRun reason.
///   - RecordRun is the one writer of CheckRun. The trigger of OcuTalon.Data.BackgroundCheck calls it for each LastRunAt change.
/// The thresholds come through OcuTalon.Data.Setting Get (the 60-second cache) with the defaults of THRESHOLDS.
Class OcuTalon.Checks.Coverage
{

/// The default thresholds: the Names of the section check-thresholds of Core.SettingsOps with their default, name=value, comma-separated. The
/// keys are KEYPREFIX and the name: diskFreePercent and journalFreePercent (free below it fails), licenseUsePercent (use above it fails),
/// queueMessages and queueWaitMinutes (more messages than the first, or an oldest message waiting more minutes than the second, fails).
Parameter THRESHOLDS = "diskFreePercent=10,journalFreePercent=10,licenseUsePercent=90,queueMessages=100,queueWaitMinutes=10";

/// The start of the key of each threshold setting.
Parameter KEYPREFIX = "checks.thresholds.";

/// The most seconds between two runs, or between a run and an end of the span, before the check counts as having missed (AD-18).
Parameter MISSEDSECONDS = 180;

/// The most seconds before the end of the span that the last poll of the mailbox may have been made for the Mailbox row to be passed.
Parameter MAILSTALESECONDS = 900;

/// The entries of the vital signs (public text).
Parameter ENTRYINSTANCE = "IRIS instance";

Parameter ENTRYDATABASE = "database space";

Parameter ENTRYJOURNAL = "journal space";

Parameter ENTRYLICENSE = "license use";

Parameter ENTRYLOG = "system log";

/// The entry of the connected mailbox (public text).
Parameter ENTRYMAILBOX = "Mailbox";

/// The findings of a failed vital sign and of a failed live read (public text; {name}, {percent}, {count} and {minutes} are filled in).
Parameter FINDINGDATABASE = "{name} {percent}% free";

Parameter FINDINGFREE = "{percent}% free";

Parameter FINDINGINUSE = "{percent}% in use";

Parameter FINDINGERROR = "1 error";

Parameter FINDINGERRORS = "{count} errors";

Parameter FINDINGITEMERROR = "1 item in error";

Parameter FINDINGITEMSERROR = "{count} items in error";

Parameter FINDINGITEMDISABLED = "1 item disabled";

Parameter FINDINGITEMSDISABLED = "{count} items disabled";

Parameter FINDINGQUEUED = "{count} messages queued";

Parameter FINDINGWAITING = "a message waiting {minutes} minutes";

/// The findings of a not-checked row that no run explains (public text).
Parameter FINDINGPAUSED = "Background checks were paused";

Parameter FINDINGMISSED = "The check didn't run";

Parameter FINDINGSTALE = "Its last check was too long ago";

/// Why a database space row is not checked when a database has a maximum size (public text, ruled by the Contest Planner under the owner's
/// delegation, 2026-11-06).
Parameter REASONSIZELIMIT = "OcuTalon can't read this database's size limit";

/// The catalog keys of the coverage lines (Msg.Catalog.Watch).
Parameter KEYPASSED = "digest.passed";

Parameter KEYFAILED = "digest.failed";

Parameter KEYERROR = "digest.notCheckedError";

Parameter KEYTIMEOUT = "digest.notCheckedTimeout";

Parameter KEYUNREACHABLE = "digest.notCheckedUnreachable";

Parameter KEYSTALE = "digest.notCheckedStale";

Parameter KEYMISSED = "digest.notCheckedMissed";

Parameter KEYPAUSED = "digest.notCheckedPaused";

Parameter KEYSIZELIMIT = "digest.notCheckedSizeLimit";

Parameter KEYSTOPPED = "digest.notCheckedStopped";

/// The kind of check that has a live read, and the owner literal of what no session owns (Checks.Process).
Parameter KIND = "production";

/// The result and the reason of a CheckRun that is not_checked.
Parameter NOTCHECKED = "not_checked";

/// The threshold settings with their defaults, as {"<key>": "<default>"} for each name of THRESHOLDS: what the installer seeds.
ClassMethod Thresholds() As %DynamicObject
{
	Set seeds = {}
	Set pairs = $ListFromString(..#THRESHOLDS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Do seeds.%Set(..#KEYPREFIX_$Piece(pair, "=", 1), $Piece(pair, "=", 2))
	}
	Quit seeds
}

/// The rows and lines of the coverage of the session from fromUtc to toUtc (UTC, YYYY-MM-DDThh:mm:ssZ), and the vital signs (see the class
/// description). The status is an error only when the session's background checks cannot be read; the output is then empty, and the caller must
/// not use it. A sign, a check or a read that fails is a not_checked row, never a missing one and never a throw.
ClassMethod Build(sessionRef As %String, fromUtc As %String, toUtc As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject) As %Status
{
	Set rows = []
	Set lines = []
	Set vitals = {"rows": [], "figures": {"upDays": "", "databasesFull": "", "licenseUse": ""}}
	Set checks = ##class(OcuTalon.Data.Ownership).Checks($Get(sessionRef), .sc)
	If $$$ISERR(sc) || '$IsObject(checks) Quit $Select($$$ISERR(sc): sc, 1: $SYSTEM.Status.Error(5001, "The background checks of the session could not be read"))
	Set fromUtc = $Get(fromUtc)
	Set toUtc = $Get(toUtc)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set limit = ..Limits()
	Set namespaces = ""
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If (check.Kind = ..#KIND) && (check.Namespace '= "") && '$ListFind(namespaces, check.Namespace) Set namespaces = namespaces_$ListBuild(check.Namespace)
	}
	Try {
		Set reading = ..Vitals(namespaces, fromUtc, toUtc)
		If '$IsObject(reading) Set reading = {}
	} Catch {
		Set reading = {}
	}
	Do ..VitalRows(reading, limit, now, rows, lines, vitals)
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		Set before = rows.%Size()
		Try {
			Do ..WatchRow(check, fromUtc, toUtc, limit, rows, lines)
		} Catch exception {
			Do ..Add(rows, lines, ..#NOTCHECKED, ..EntryOf(check), ##class(OcuTalon.Checks.Process).#REASONREAD, now, ..#KEYERROR, {"entry": (..EntryOf(check)), "time": (now)})
		}
		If (check.Kind = ##class(OcuTalon.Checks.Process).#SOURCEKIND) && (rows.%Size() > before) Do rows.%Get(rows.%Size() - 1).%Set("kind", check.Kind)
	}
	Do ..MailboxRow(sessionRef, fromUtc, toUtc, rows, lines)
	Quit $$$OK
}

/// The thresholds as numbers, a member for each name of THRESHOLDS. Each is read through Data.Setting Get with its default
/// from THRESHOLDS, and a stored value that is not a number reads as the default.
ClassMethod Limits() As %DynamicObject [ Private ]
{
	Set limit = {}
	Set pairs = $ListFromString(..#THRESHOLDS)
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set name = $Piece(pair, "=", 1)
		Set default = $Piece(pair, "=", 2)
		Set value = ##class(OcuTalon.Data.Setting).Get(..#KEYPREFIX_name, default)
		Do limit.%Set(name, $Select($IsValidNum(value): +value, 1: +default))
	}
	Quit limit
}

/// Adds one row and its line. The row is returned.
ClassMethod Add(rows As %DynamicArray, lines As %DynamicArray, result As %String, entry As %String, finding As %String, checkedAt As %String, key As %String, slots As %DynamicObject) As %DynamicObject [ Private ]
{
	Set row = {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (checkedAt)}
	Do rows.%Push(row)
	Do lines.%Push({"key": (key), "slots": (slots)})
	Quit row
}

/// Adds a row that was checked: passed with no finding, or failed with one.
ClassMethod AddChecked(rows As %DynamicArray, lines As %DynamicArray, entry As %String, finding As %String, checkedAt As %String) As %DynamicObject [ Private ]
{
	If finding = "" Quit ..Add(rows, lines, "passed", entry, "", checkedAt, ..#KEYPASSED, {"entry": (entry), "time": (checkedAt)})
	Quit ..Add(rows, lines, "failed", entry, finding, checkedAt, ..#KEYFAILED, {"entry": (entry), "finding": (finding), "time": (checkedAt)})
}

/// Adds a row that was not checked because its reading failed (the reason of Checks.Process REASONREAD).
ClassMethod AddUnread(rows As %DynamicArray, lines As %DynamicArray, entry As %String, now As %String) As %DynamicObject [ Private ]
{
	Quit ..Add(rows, lines, ..#NOTCHECKED, entry, ##class(OcuTalon.Checks.Process).#REASONREAD, now, ..#KEYERROR, {"entry": (entry), "time": (now)})
}

/// The five vital-sign rows, added to rows and lines in order and to vitals.rows, with the figures of vitals.
ClassMethod VitalRows(reading As %DynamicObject, limit As %DynamicObject, now As %String, rows As %DynamicArray, lines As %DynamicArray, vitals As %DynamicObject) [ Private ]
{
	Set figures = vitals.figures
	Set sign = reading.instance
	If $IsObject(sign) && (sign.outcome = "read") {
		Do ..AddChecked(rows, lines, ..#ENTRYINSTANCE, "", now)
		Do figures.%Set("upDays", +sign.upSeconds \ 86400)
	} Else {
		Do ..AddUnread(rows, lines, ..#ENTRYINSTANCE, now)
	}
	Do ..DatabaseRow(reading.databases, limit, now, rows, lines, figures)
	Set sign = reading.journal
	If $IsObject(sign) && (sign.outcome = "read") {
		Do ..AddChecked(rows, lines, ..#ENTRYJOURNAL, $Select(sign.freePercent < limit.journalFreePercent: ..Fill(..#FINDINGFREE, {"percent": (sign.freePercent \ 1)}), 1: ""), now)
	} Else {
		Do ..AddUnread(rows, lines, ..#ENTRYJOURNAL, now)
	}
	Set sign = reading.license
	If $IsObject(sign) && (sign.outcome = "read") {
		Do ..AddChecked(rows, lines, ..#ENTRYLICENSE, $Select(sign.usePercent > limit.licenseUsePercent: ..Fill(..#FINDINGINUSE, {"percent": (..Ceiling(sign.usePercent))}), 1: ""), now)
		Do figures.%Set("licenseUse", ..Round(sign.usePercent))
	} Else {
		Do ..AddUnread(rows, lines, ..#ENTRYLICENSE, now)
	}
	Set sign = reading.systemLog
	If $IsObject(sign) && (sign.outcome = "read") {
		Do ..AddChecked(rows, lines, ..#ENTRYLOG, $Select(sign.count < 1: "", sign.count = 1: ..#FINDINGERROR, 1: ..Fill(..#FINDINGERRORS, {"count": (+sign.count)})), now)
	} Else {
		Do ..AddUnread(rows, lines, ..#ENTRYLOG, now)
	}
	For i = 0:1:4 {
		Do vitals.rows.%Push(rows.%Get(i))
	}
}

/// The database space row (see the class description): the databases are the entries of Watch.Reader.Vitals databases.
ClassMethod DatabaseRow(databases As %DynamicArray, limit As %DynamicObject, now As %String, rows As %DynamicArray, lines As %DynamicArray, figures As %DynamicObject) [ Private ]
{
	Set entry = ..#ENTRYDATABASE
	Set unread = ('$IsObject(databases) || (databases.%Size() = 0))
	Set capped = 0
	Set low = ""
	Set lowest = ""
	If $IsObject(databases) {
		Set iterator = databases.%GetIterator()
		While iterator.%GetNext(, .database) {
			If database.outcome '= "read" {
				Set unread = 1
				Continue
			}
			Set free = database.volumeFreePercent
			If (lowest = "") || (free < lowest) Set lowest = free
			If free < limit.diskFreePercent Set low = low_$ListBuild(..Fill(..#FINDINGDATABASE, {"name": (database.name), "percent": (free \ 1)}))
			If database.maxBlocks > 0 Set capped = 1
		}
	}
	If low '= "" {
		Do ..AddChecked(rows, lines, entry, $ListToString(low, ", "), now)
	} ElseIf unread {
		Do ..AddUnread(rows, lines, entry, now)
		Quit
	} ElseIf capped {
		Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#REASONSIZELIMIT, now, ..#KEYSIZELIMIT, {"entry": (entry)})
		Quit
	} Else {
		Do ..AddChecked(rows, lines, entry, "", now)
	}
	If lowest '= "" Do figures.%Set("databasesFull", ..Round(100 - lowest))
}

/// The row of one background check: its history (the runs of CheckRun in the span), then, for a production watch whose result stands on its
/// latest run, the live read.
ClassMethod WatchRow(check As OcuTalon.Data.BackgroundCheck, fromUtc As %String, toUtc As %String, limit As %DynamicObject, rows As %DynamicArray, lines As %DynamicArray) [ Private ]
{
	Set entry = ..EntryOf(check)
	Set spanStart = $Select(check.CreatedAt = "": fromUtc, fromUtc = "": check.CreatedAt, fromUtc ] check.CreatedAt: fromUtc, 1: check.CreatedAt)
	If spanStart = "" Set spanStart = toUtc
	If (toUtc '= "") && (spanStart ] toUtc) Set spanStart = toUtc
	Set paused = ..Gaps(spanStart, toUtc)
	If $IsObject(paused) && (paused.%Size() > 0) {
		Set gap = paused.%Get(0)
		Set from = $Select(gap.start = "": spanStart, spanStart ] gap.start: spanStart, 1: gap.start)
		Set to = $Select((gap.end = "") || (gap.end ] toUtc): toUtc, 1: gap.end)
		Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#FINDINGPAUSED, from, ..#KEYPAUSED, {"entry": (entry), "from": (from), "to": (to)})
		Quit
	}
	Set runs = ..Runs(check.Ref, spanStart, toUtc)
	If runs.%Size() = 0 {
		Set earlier = ..EarlierRun(check.Ref, spanStart)
		If earlier '= "" {
			Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#FINDINGSTALE, earlier, ..#KEYSTALE, {"entry": (entry), "time": (earlier)})
		} Else {
			Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#FINDINGMISSED, spanStart, ..#KEYMISSED, {"entry": (entry), "from": (spanStart), "to": (toUtc)})
		}
		Quit
	}
	Set previous = spanStart
	Set missed = 0
	Set allowed = ..#MISSEDSECONDS
	If (check.Kind = ##class(OcuTalon.Checks.Process).#SOURCEKIND) && (+check.IntervalMinutes > 0) Set allowed = (check.IntervalMinutes * 60) + ..#MISSEDSECONDS
	For i = 0:1:runs.%Size() {
		Set next = $Select(i = runs.%Size(): toUtc, 1: runs.%Get(i).ranAt)
		If ..Apart(previous, next) > allowed {
			Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#FINDINGMISSED, previous, ..#KEYMISSED, {"entry": (entry), "from": (previous), "to": (next)})
			Set missed = 1
			Quit
		}
		Set previous = next
	}
	If missed Quit
	Set latest = runs.%Get(runs.%Size() - 1)
	If latest.result = ..#NOTCHECKED {
		Set key = ..KeyOf(latest.reason)
		Set time = latest.ranAt
		If (key = ..#KEYUNREACHABLE) || (key = ..#KEYSTOPPED) {
			For j = runs.%Size() - 1:-1:0 {
				Set run = runs.%Get(j)
				If (run.result '= ..#NOTCHECKED) || (run.reason '= latest.reason) Quit
				Set time = run.ranAt
			}
		}
		Do ..Add(rows, lines, ..#NOTCHECKED, entry, latest.finding, time, key, {"entry": (entry), "time": (time)})
		Quit
	}
	If (latest.result '= "passed") && ((latest.result '= "failed") || (latest.finding = "")) {
		Do ..Add(rows, lines, ..#NOTCHECKED, entry, ##class(OcuTalon.Checks.Process).#REASONREAD, latest.ranAt, ..#KEYERROR, {"entry": (entry), "time": (latest.ranAt)})
		Quit
	}
	If check.Kind = ..#KIND {
		If ..Live(check, entry, spanStart, limit, rows, lines) Quit
	}
	Do ..AddChecked(rows, lines, entry, $Select(latest.result = "failed": latest.finding, 1: ""), latest.ranAt)
}

/// The Mailbox row (Story 22.5; AD-28): none unless MailOwner is the session and the mark emailPoll exists. The mark is {at, ok, reason, lastOkAt} (Channel.Email.Adapter Record).
/// Passed when ok is 1, at is in the span and at most MAILSTALESECONDS before toUtc (before now when toUtc is empty). Not checked, with FINDINGSTALE, when ok is 1 but at is outside the span or older
/// (digest.notCheckedStale). Not checked as unreachable, since lastOkAt (else at), when ok is 0 and the reason is the adapter's REASONUNREACHABLE. Not checked as an error
/// (at) for any other failed poll, and (now) for a mark that cannot be read. An error after the owner is known adds the error row; it never throws.
ClassMethod MailboxRow(sessionRef As %String, fromUtc As %String, toUtc As %String, rows As %DynamicArray, lines As %DynamicArray) [ Private ]
{
	Set entry = ..#ENTRYMAILBOX
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set known = 0
	Set end = $Select(toUtc = "": now, 1: toUtc)
	Try {
		If ($Get(sessionRef) = "") || (..MailOwner() '= sessionRef) Quit
		Set known = 1
		Set raw = ..Mark()
		If raw = "" Quit
		Set mark = {}.%FromJSON(raw)
		Set at = $Select(mark.%GetTypeOf("at") = "string": mark.at, 1: "")
		If at '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" {
			Do ..AddUnread(rows, lines, entry, now)
			Quit
		}
		Set reason = $Select(mark.%GetTypeOf("reason") = "string": mark.reason, 1: "")
		If mark.ok = 1 {
			Set inSpan = ((fromUtc = "") || '(fromUtc ] at)) && ((toUtc = "") || '(at ] toUtc))
			If inSpan && (..Apart(at, end) <= ..#MAILSTALESECONDS) {
				Do ..AddChecked(rows, lines, entry, "", at)
			} Else {
				Do ..Add(rows, lines, ..#NOTCHECKED, entry, ..#FINDINGSTALE, at, ..#KEYSTALE, {"entry": (entry), "time": (at)})
			}
		} ElseIf (mark.ok = 0) && (reason = ##class(OcuTalon.Channel.Email.Adapter).#REASONUNREACHABLE) {
			Set lastOkAt = $Select(mark.%GetTypeOf("lastOkAt") = "string": mark.lastOkAt, 1: "")
			Set time = $Select(lastOkAt '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z": at, 1: lastOkAt)
			Do ..Add(rows, lines, ..#NOTCHECKED, entry, reason, at, ..#KEYUNREACHABLE, {"entry": (entry), "time": (time)})
		} Else {
			Do ..Add(rows, lines, ..#NOTCHECKED, entry, $Select(reason = "": ##class(OcuTalon.Checks.Process).#REASONREAD, 1: reason), at, ..#KEYERROR, {"entry": (entry), "time": (at)})
		}
	} Catch {
		If known Do ..AddUnread(rows, lines, entry, now)
	}
}

/// The live read of a production watch. 1 when it added the row (the production has a finding now, or could not be read), 0 when it found
/// nothing and the history stands.
ClassMethod Live(check As OcuTalon.Data.BackgroundCheck, entry As %String, spanStart As %String, limit As %DynamicObject, rows As %DynamicArray, lines As %DynamicArray) As %Boolean [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set max = ##class(OcuTalon.Watch.Mark).#MAXFAILURES
	Set threw = 0
	Set outcome = ""
	Set state = ""
	Set failed = []
	Set disabled = []
	Set errored = []
	Set queues = []
	Set stoppedAt = ""
	Try {
		Set outcome = ..Read(check.Namespace, check.Production, ##class(OcuTalon.Watch.Mark).FromCreated(spanStart), max, .failed, .state, .disabled, .stoppedAt, .errored, .queues)
	} Catch {
		Set threw = 1
	}
	Set failures = 0
	Set cut = 0
	If $IsObject(failed) {
		Set failures = ##class(OcuTalon.Checks.Process).ScopedFailures(failed, check.SessionRef, ##class(OcuTalon.Watch.Reader).OnlineDemo())
		Set cut = ##class(OcuTalon.Checks.Process).IsCut(failed, max)
	}
	Set reason = ##class(OcuTalon.Checks.Process).NotCheckedReason(outcome, state, threw || '$IsObject(errored) || '$IsObject(queues), cut, failures)
	If reason '= "" {
		Do ..Add(rows, lines, ..#NOTCHECKED, entry, reason, now, ..KeyOf(..ReasonOf(reason)), {"entry": (entry), "time": (now)})
		Quit 1
	}
	Set parts = ""
	Set stateText = ##class(OcuTalon.Checks.Process).StateText(state)
	If stateText '= "" Set parts = parts_$ListBuild(stateText)
	If errored.%Size() > 0 Set parts = parts_$ListBuild($Select(errored.%Size() = 1: ..#FINDINGITEMERROR, 1: ..Fill(..#FINDINGITEMSERROR, {"count": (errored.%Size())})))
	If disabled.%Size() > 0 Set parts = parts_$ListBuild($Select(disabled.%Size() = 1: ..#FINDINGITEMDISABLED, 1: ..Fill(..#FINDINGITEMSDISABLED, {"count": (disabled.%Size())})))
	If failures > 0 Set parts = parts_$ListBuild(##class(OcuTalon.Checks.Process).FailureText(failures, cut))
	Set most = 0
	Set longest = 0
	Set nowSeconds = ##class(OcuTalon.Data.Time).Seconds(now)
	Set iterator = queues.%GetIterator()
	While iterator.%GetNext(, .queue) {
		Do ##class(OcuTalon.Checks.Queues).Over(queue, limit, nowSeconds, .byCount, .waited)
		If byCount && (queue.count > most) Set most = queue.count
		If waited > longest Set longest = waited
	}
	If most > 0 Set parts = parts_$ListBuild(..Fill(..#FINDINGQUEUED, {"count": (most)}))
	If longest > 0 Set parts = parts_$ListBuild(..Fill(..#FINDINGWAITING, {"minutes": (longest \ 60)}))
	If parts = "" Quit 0
	Do ..AddChecked(rows, lines, entry, ##class(OcuTalon.Checks.Process).Joined(parts), now)
	Quit 1
}

/// The entry of a background check: a production watch is {name} production (Tools.WatchAnswers ENTRY), any other kind its display name.
ClassMethod EntryOf(check As OcuTalon.Data.BackgroundCheck) As %String [ Private ]
{
	If check.Kind = ..#KIND Quit $Replace(##class(OcuTalon.Tools.WatchAnswers).#ENTRY, "{name}", check.DisplayName)
	Quit check.DisplayName
}

/// The runs of the check from the span's start to its end, oldest first, as a dynamic array of {"ranAt", "result", "reason", "finding"}.
ClassMethod Runs(checkRef As %String, spanStart As %String, toUtc As %String) As %DynamicArray [ Private ]
{
	Set runs = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT RanAt, Result, Reason, Finding FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? AND RanAt >= ? AND RanAt <= ? ORDER BY RanAt, ID", checkRef, spanStart, toUtc)
	If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The runs of a check could not be read: "_result.%Message))
	While result.%Next() {
		Do runs.%Push({"ranAt": (result.%Get("RanAt")), "result": (result.%Get("Result")), "reason": (result.%Get("Reason")), "finding": (result.%Get("Finding"))})
	}
	Quit runs
}

/// The time of the newest run of the check before the span's start, or "".
ClassMethod EarlierRun(checkRef As %String, spanStart As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 RanAt FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? AND RanAt < ? ORDER BY RanAt DESC, ID DESC", checkRef, spanStart)
	If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "The runs of a check could not be read: "_result.%Message))
	Quit $Select(result.%Next(): result.%Get("RanAt"), 1: "")
}

/// The seconds from one UTC time to a later one; 0 when either is unreadable.
ClassMethod Apart(earlier As %String, later As %String) As %Integer [ Private ]
{
	Set from = ##class(OcuTalon.Data.Time).Seconds(earlier)
	Set to = ##class(OcuTalon.Data.Time).Seconds(later)
	If (from = "") || (to = "") Quit 0
	Quit to - from
}

/// The text with each {name} of values replaced by the member's value.
ClassMethod Fill(text As %String, values As %DynamicObject) As %String [ Private ]
{
	Set iterator = values.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set text = $Replace(text, "{"_name_"}", value)
	}
	Quit text
}

/// A non-negative number rounded to a whole number, half up.
ClassMethod Round(value As %Numeric) As %Integer [ Private ]
{
	Quit (value + 0.5) \ 1
}

/// A non-negative number rounded up to a whole number.
ClassMethod Ceiling(value As %Numeric) As %Integer [ Private ]
{
	Quit $Select(value = (value \ 1): value, 1: (value \ 1) + 1)
}

/// The vital signs: Watch.Reader.Vitals. A seam for the tests.
ClassMethod Vitals(namespaces As %List, fromUtc As %String, toUtc As %String) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Vitals(namespaces, fromUtc, toUtc)
}

/// The live read of a production: Watch.Reader.Failures. A seam for the tests.
ClassMethod Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String, Output disabled As %DynamicArray, Output stoppedAt As %String, Output errored As %DynamicArray, Output queues As %DynamicArray) As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Reader).Failures(namespace, production, from, limit, .rows, .state, .disabled, .stoppedAt, .errored, .queues)
}

/// The value of the mark emailPoll (Data.StatusMark Get), "" when there is none. A seam for the tests.
ClassMethod Mark() As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Channel.Email.Adapter).#MARK)
}

/// The Ref of the session that owns the connected mailbox (Channel.Email.In Owner), "" for none. A seam for the tests.
ClassMethod MailOwner() As %String [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.In).Owner()
}

/// The gaps of the heartbeat that overlap the span: Schedule.Heartbeat.Gaps. A seam for the tests.
ClassMethod Gaps(fromUtc As %String, toUtc As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Schedule.Heartbeat).Gaps(fromUtc, toUtc)
}

/// The Reason of a not_checked run (the Reason of its CheckRun row) for the phrase that Checks.Process gave as its finding: timeout for REASONTIMEOUT,
/// unreachable for REASONUNREADABLE, REASONNOTCURRENT and REASONSOURCEUNREACHABLE, stopped for REASONNOTREADONLY, and error for anything else. RecordRun and the live read (Live) both take their reason from it.
ClassMethod ReasonOf(finding As %String) As %String [ Private ]
{
	Set process = "OcuTalon.Checks.Process"
	Quit $Case(finding, $Parameter(process, "REASONTIMEOUT"): "timeout", $Parameter(process, "REASONUNREADABLE"): "unreachable", $Parameter(process, "REASONNOTCURRENT"): "unreachable", $Parameter(process, "REASONSOURCEUNREACHABLE"): "unreachable", $Parameter(process, "REASONNOTREADONLY"): "stopped", : "error")
}

/// The catalog key of a not_checked row for its Reason (ReasonOf): KEYTIMEOUT for timeout, KEYUNREACHABLE for unreachable, KEYSTOPPED for stopped, else KEYERROR.
ClassMethod KeyOf(reason As %String) As %String [ Private ]
{
	Quit $Case(reason, "timeout": ..#KEYTIMEOUT, "unreachable": ..#KEYUNREACHABLE, "stopped": ..#KEYSTOPPED, : ..#KEYERROR)
}

/// Records one run of a background check as a Digest.Data.CheckRun row, the one writer of the table (see the class description). The Reason of
/// a not_checked run comes from its finding, the phrase that Checks.Process wrote: REASONTIMEOUT is timeout, REASONUNREADABLE and
/// REASONNOTCURRENT are unreachable, and anything else is error. It is called inside the update of the check's row and catches its own errors: a
/// run that could not be recorded logs one warning and never fails that update.
ClassMethod RecordRun(ref As %String, sessionRef As %String, ranAt As %String, result As %String, finding As %String, headerId As %Integer = "")
{
	Try {
		Set reason = ""
		If result = ..#NOTCHECKED Set reason = ..ReasonOf(finding)
		Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding, HeaderId) VALUES (?, ?, ?, ?, ?, ?, ?)", ref, sessionRef, ranAt, result, reason, finding, headerId)
		If insert.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, insert.%Message))
	} Catch exception {
		Do ##class(Ens.Util.Log).LogWarning("OcuTalon.Checks.Coverage", "RecordRun", "A run of check "_$Get(ref)_" could not be recorded: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// The thresholds as numbers (Limits): the one source of them for the digest's live read and for the queue-backlog check (Checks.Queues Over).
ClassMethod CurrentLimits() As %DynamicObject
{
	Quit ..Limits()
}

}
