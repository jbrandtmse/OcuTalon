/// The agent heartbeat's beats and the names of its settings (AD-18, AD-19). Lane A. Checks calls RunDue on every Tick, after the due checks, and RunNow
/// for a BeatNow. A beat is no background check (AD-28): it adds no BackgroundCheck row, check result or coverage entry. The tick never calls the model:
/// RunDue and RunNow only decide, write the person's HeartbeatBeat row and return the beat's OcuTalon.Msg.Item, which Checks sends to Intake (this class has
/// no business host). Every model request comes from Intake, after that send.
///   - Values reads a person's five settings through Data.Setting.Get on every call (nothing is kept in memory, AD-5). A key with no row takes its default:
///     on is DEFAULTON (DEFAULTONDEMO on the online demo), the others DEFAULTINTERVAL, DEFAULTFROM, DEFAULTTO and "". A stored interval outside INTERVALS
///     reads as 30. from and to both stored as "" mean all day, and any other pair that is not two HH:MM values reads as the defaults.
///   - A beat is due when its person's row is missing, its NextDueAt is empty, or NextDueAt is at most Process.DUESLACKSECONDS after the tick. A beat that
///     runs sets NextDueAt to the tick plus one interval, so a beat missed across several intervals runs once.
///   - Skip gives the first rule that holds, in AD-18's order: empty (the checklist is empty after white space is stripped), hours (outside the active hours,
///     read in the instance zone through Data.Time), backoff (BackoffUntil is after the time), cap (the daily cost cap is reached), nokey (the
///     TriageAgent's model key is not present) and unchanged (the snapshot's key is the row's LastQuietKey; an empty LastQuietKey never matches). The
///     snapshot is built only when none of the first five holds. A run now leaves out hours and unchanged.
///   - A skip writes LastSkipAt and LastSkipReason, and moves NextDueAt to the next active-hours start (hours) or one interval on. A beat that runs writes
///     LastBeatAt, LastItemId and LastSnapshotKey, moves NextDueAt one interval on and clears the five decision fields (LastOutcome, LastFallback,
///     LastCostUSD, LastDecisionRef, LastTraceSessionId), so that a pending beat is a row with LastItemId set and LastDecisionRef empty. The row is saved
///     before the Item is returned.
///   - The decision of a pending beat (Kind decide, same ItemId, the person as owner) is recorded on the row by the next RunDue or RunNow: the outcome,
///     the fallback, the cost, the decision's Ref and trace session. An ignore copies LastSnapshotKey to LastQuietKey, and a fallback sets BackoffUntil to
///     the time plus the longer of BACKOFFSECONDS and one interval.
///   - Each person runs in its own Try/Catch. A person whose pending decision could not be recorded does not run in that RunDue, so that a new beat never
///     overwrites a decision that is still to be recorded (RunNow stops there too). RunDue answers an error status that holds only the count of failures and
///     their error codes, never a SessionRef; a read of the rows that stops partway counts as one failure.
///   - Until Story 39.4 the snapshot is the checklist alone. Key is the SHA-256 of the snapshot without its status line, so that a status line never
///     changes it.
Class OcuTalon.Checks.Beat
{

/// The setting names of a person's heartbeat: person.<SessionRef>.heartbeat.<name> (AD-19).
Parameter KEYS = "on,interval,from,to,checklist";

/// The allowed intervals in minutes.
Parameter INTERVALS = "30,60,120,240,480,1440";

/// The defaults of the settings: on (0 on the online demo), the interval in minutes, and the window from and to (HH:MM). The default checklist is empty.
Parameter DEFAULTON = 1;

Parameter DEFAULTONDEMO = 0;

Parameter DEFAULTINTERVAL = 30;

Parameter DEFAULTFROM = "08:00";

Parameter DEFAULTTO = "20:00";

/// The most characters that the checklist may hold.
Parameter CHECKLISTMAX = 1000;

/// The channel and the subject of a beat's Item, and the runner item whose model key a beat needs.
Parameter CHANNEL = "heartbeat";

Parameter SUBJECT = "Heartbeat check-in";

Parameter AGENT = "TriageAgent";

/// The seconds that a request to run now waits after the last one, and the seconds that a fallback holds the beats back at least.
Parameter RUNNOWSECONDS = 120;

Parameter BACKOFFSECONDS = 14400;

/// The codes of a skip, and of a run now's outcome besides them.
Parameter SKIPEMPTY = "empty";

Parameter SKIPHOURS = "hours";

Parameter SKIPBACKOFF = "backoff";

Parameter SKIPCAP = "cap";

Parameter SKIPNOKEY = "nokey";

Parameter SKIPUNCHANGED = "unchanged";

Parameter SENT = "sent";

Parameter COOLDOWN = "cooldown";

Parameter FAILED = "failed";

/// The line that the status snapshot adds (Story 39.4) starts and ends with these, and Key leaves it out.
Parameter STATUSPREFIX = "Status at ";

Parameter STATUSSUFFIX = "(built by OcuTalon):";

/// The values of the session's heartbeat settings, read now: a dynamic object of on (1 or 0), interval (minutes), from and to (HH:MM, or "" for both when
/// the window is all day) and checklist.
ClassMethod Values(sessionRef As %String) As %DynamicObject
{
	Set default = $Select(##class(OcuTalon.Watch.Reader).OnlineDemo(): ..#DEFAULTONDEMO, 1: ..#DEFAULTON)
	Set on = (+##class(OcuTalon.Data.Setting).Get(..SettingKey(sessionRef, "on"), default) = 1)
	Set interval = ##class(OcuTalon.Data.Setting).Get(..SettingKey(sessionRef, "interval"), ..#DEFAULTINTERVAL)
	If (interval '= +interval) || '$ListFind($ListFromString(..#INTERVALS), +interval) Set interval = 30
	Set fromKey = ..SettingKey(sessionRef, "from")
	Set toKey = ..SettingKey(sessionRef, "to")
	Set from = $Select(##class(OcuTalon.Data.Setting).KeyIndexExists(fromKey): ##class(OcuTalon.Data.Setting).Get(fromKey), 1: ..#DEFAULTFROM)
	Set to = $Select(##class(OcuTalon.Data.Setting).KeyIndexExists(toKey): ##class(OcuTalon.Data.Setting).Get(toKey), 1: ..#DEFAULTTO)
	If (from = "") && (to = "") {
		// all day
	} ElseIf '(..Clock(from) && ..Clock(to)) {
		Set from = ..#DEFAULTFROM
		Set to = ..#DEFAULTTO
	}
	Set values = {}
	Do values.%Set("on", on, "number")
	Do values.%Set("interval", +interval, "number")
	Do values.%Set("from", from)
	Do values.%Set("to", to)
	Do values.%Set("checklist", ##class(OcuTalon.Data.Setting).Get(..SettingKey(sessionRef, "checklist"), ""))
	Quit values
}

/// 1 when the text is a time of day, HH:MM.
ClassMethod Clock(text As %String) As %Boolean [ Private ]
{
	Quit ($Get(text) ? 2N1":"2N) && ($Extract(text, 1, 2) < 24) && ($Extract(text, 4, 5) < 60)
}

/// 1 when the UTC time at is inside the active hours of the values, read in the instance zone: all day, from <= local time < to, or, when from is after to,
/// the window over midnight. from = to counts as all day.
ClassMethod InHours(values As %DynamicObject, at As %String) As %Boolean
{
	Set from = values.from
	Set to = values.to
	If (from = "") || (to = "") || (from = to) Quit 1
	Set local = ##class(OcuTalon.Data.Time).ToLocal(at)
	If local = "" Quit 1
	Set clock = $Extract(local, 12, 16)
	If to ] from Quit '(from ] clock) && (to ] clock)
	Quit '(from ] clock) || (to ] clock)
}

/// The next due time (UTC) after a beat at the UTC time at for the reason: the next start of the active hours for hours, else one interval after at.
ClassMethod NextDue(values As %DynamicObject, at As %String, reason As %String) As %String
{
	Set later = ##class(OcuTalon.Data.Time).AddSeconds(at, values.interval * 60)
	If (reason '= ..#SKIPHOURS) || (values.from = "") Quit later
	Set local = ##class(OcuTalon.Data.Time).ToLocal(at)
	If local = "" Quit later
	Set day = $Piece(local, "T", 1)
	If '(values.from ] $Extract(local, 12, 16)) Set day = $ZDate($ZDateH(day, 3) + 1, 3)
	Set start = ##class(OcuTalon.Data.Time).FromLocal(day_"T"_values.from_":00")
	Quit $Select(start = "": later, 1: start)
}

/// The first reason to skip, or "" when the beat runs (see the class description). row is the person's HeartbeatBeat or "", at the UTC time, runNow 1 for a
/// run now (hours and unchanged do not hold it), capped and keyed what Capped and Keyed give, and key the snapshot's key ("" leaves unchanged out).
ClassMethod Skip(values As %DynamicObject, row As %RegisteredObject, at As %String, runNow As %Boolean, capped As %Boolean, keyed As %Boolean, key As %String = "") As %String
{
	If $ZStrip(values.checklist, "*", $Char(9, 10, 11, 12, 13, 32, 160)) = "" Quit ..#SKIPEMPTY
	If 'runNow && '..InHours(values, at) Quit ..#SKIPHOURS
	Set backoff = $Select($IsObject(row): row.BackoffUntil, 1: "")
	If (backoff '= "") && (backoff ] at) Quit ..#SKIPBACKOFF
	If capped Quit ..#SKIPCAP
	If 'keyed Quit ..#SKIPNOKEY
	Set quiet = $Select($IsObject(row): row.LastQuietKey, 1: "")
	If 'runNow && (key '= "") && (quiet '= "") && (quiet = key) Quit ..#SKIPUNCHANGED
	Quit ""
}

/// 1 when the daily cost cap is reached at the UTC time (Bridge.Budget).
ClassMethod Capped(at As %String) As %Boolean
{
	Quit +##class(OcuTalon.Bridge.Budget).State(at).capped
}

/// 1 when the model key of the TriageAgent is present (Bridge.Keys).
ClassMethod Keyed() As %Boolean
{
	Quit +##class(OcuTalon.Bridge.Keys).Status(..#AGENT)
}

/// The snapshot of what a beat reads for the session at now: the checklist, until Story 39.4 adds the status.
ClassMethod Snapshot(sessionRef As %String, now As %String) As %String
{
	Quit ..Values(sessionRef).checklist
}

/// The key of a snapshot: the lower-case hexadecimal SHA-256 (64 characters) of its UTF-8 text without the line that starts STATUSPREFIX and ends
/// STATUSSUFFIX.
ClassMethod Key(snapshot As %String) As %String
{
	Set text = ""
	Set kept = 0
	Set lines = $Length(snapshot, $Char(10))
	For i = 1:1:lines {
		Set line = $Piece(snapshot, $Char(10), i)
		Set bare = $Select($Extract(line, *) = $Char(13): $Extract(line, 1, *-1), 1: line)
		Set size = $Length(bare)
		Set tail = $Length(..#STATUSSUFFIX)
		If ($Extract(bare, 1, $Length(..#STATUSPREFIX)) = ..#STATUSPREFIX) && (size '< tail) && ($Extract(bare, size - tail + 1, size) = ..#STATUSSUFFIX) Continue
		Set text = text_$Select(kept: $Char(10), 1: "")_line
		Set kept = 1
	}
	Set hash = $SYSTEM.Encryption.SHAHash(256, $ZConvert(text, "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(hash) {
		Set byte = $Ascii(hash, i)
		Set hex = hex_$Extract("0123456789abcdef", (byte \ 16) + 1)_$Extract("0123456789abcdef", (byte # 16) + 1)
	}
	Quit hex
}

/// Runs the beats that are due at the tick time (UTC, YYYY-MM-DDTHH:MM:SSZ), after recording the decisions of the beats sent before. items is a
/// %ListOfObjects of the Items to send, one for each beat that ran, whatever the status is. sessions limits the people to the comma-separated Refs (a test
/// seam; empty means everyone), and capped and keyed give what Capped and Keyed would ("" means read them, once, when the first due person needs them).
/// Each person runs in its own Try/Catch; the status is an error that holds the number of failures and their error codes (see the class description).
ClassMethod RunDue(tickAt As %String, Output items As %ListOfObjects, sessions As %String = "", capped As %String = "", keyed As %String = "") As %Status
{
	Set items = ##class(%ListOfObjects).%New()
	Set failed = 0
	Set codes = ""
	Set limit = ##class(OcuTalon.Data.Time).AddSeconds(tickAt, ##class(OcuTalon.Checks.Process).#DUESLACKSECONDS)

	// the decisions of the beats sent before
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionRef, LastItemId, LastDecisionRef FROM OcuTalon_Data.HeartbeatBeat ORDER BY ID")
	If rs.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The heartbeat rows could not be read: "_rs.%Message)
	While rs.%Next() {
		Set ref = rs.%Get("SessionRef")
		If (rs.%Get("LastItemId") = "") || (rs.%Get("LastDecisionRef") '= "") Continue
		If (sessions '= "") && '$ListFind($ListFromString(sessions), ref) Continue
		Try {
			Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
			If $IsObject(row) $$$ThrowOnError(..Settle(row, tickAt))
		} Catch exception {
			Set unsettled(ref) = 1
			Do ..Failed(exception.AsStatus(), .failed, .codes)
		}
	}
	If rs.%SQLCODE < 0 Do ..Failed($SYSTEM.Status.Error(5001, "The heartbeat rows could not be read"), .failed, .codes)

	// the due people
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session ORDER BY ID")
	If rs.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The sessions could not be read: "_rs.%Message)
	While rs.%Next() {
		Set ref = rs.%Get("Ref")
		If (sessions '= "") && '$ListFind($ListFromString(sessions), ref) Continue
		If $Data(unsettled(ref)) Continue
		Try {
			Set values = ..Values(ref)
			Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(ref)
			If values.on && ('$IsObject(row) || (row.NextDueAt = "") || '(row.NextDueAt ] limit)) {
				If capped = "" Set capped = ..Capped(tickAt)
				If keyed = "" Set keyed = ..Keyed()
				If '$IsObject(row) {
					Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
					Set row.SessionRef = ref
				}
				Set item = ..Run(row, values, tickAt, 0, capped, keyed, .reason)
				If $IsObject(item) Do items.Insert(item)
			}
		} Catch exception {
			Do ..Failed(exception.AsStatus(), .failed, .codes)
		}
	}
	If rs.%SQLCODE < 0 Do ..Failed($SYSTEM.Status.Error(5001, "The sessions could not be read"), .failed, .codes)
	If failed Quit $SYSTEM.Status.Error(5001, failed_" heartbeat beat"_$Select(failed = 1: "", 1: "s")_" failed, error codes "_codes)
	Quit $$$OK
}

/// Runs a beat now for the session at the UTC time now (see the class description): its pending decision is recorded first, then a request within RUNNOWSECONDS
/// of LastRunNowAt gives the outcome COOLDOWN with availableAt = LastRunNowAt plus RUNNOWSECONDS and writes nothing; else LastRunNowAt becomes now, on is
/// ignored, and the outcome is SENT (item is the Item to send, NextDueAt is now plus one interval) or the first reason that holds (no Item; availableAt is
/// BackoffUntil for backoff). capped and keyed as in RunDue.
ClassMethod RunNow(sessionRef As %String, now As %String, Output item As OcuTalon.Msg.Item, Output outcome As %String, Output availableAt As %String, capped As %String = "", keyed As %String = "") As %Status
{
	Set item = ""
	Set outcome = ""
	Set availableAt = ""
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(sessionRef)
	If $IsObject(row) {
		Set sc = ..Settle(row, now)
		If $$$ISERR(sc) Quit sc
	} Else {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = sessionRef
	}
	Set last = ##class(OcuTalon.Data.Time).AddSeconds(row.LastRunNowAt, ..#RUNNOWSECONDS)
	If (row.LastRunNowAt '= "") && (last '= "") && (last ] now) {
		Set outcome = ..#COOLDOWN
		Set availableAt = last
		Quit $$$OK
	}
	Set row.LastRunNowAt = now
	If capped = "" Set capped = ..Capped(now)
	If keyed = "" Set keyed = ..Keyed()
	Set item = ..Run(row, ..Values(sessionRef), now, 1, capped, keyed, .outcome)
	If '$IsObject(item) {
		If outcome = ..#SKIPBACKOFF Set availableAt = row.BackoffUntil
	} Else {
		Set outcome = ..#SENT
	}
	Quit $$$OK
}

/// One beat of the person's row at the UTC time at: the Item to send after the row is saved, or "" after a skip. For a run now (runNow 1) a skip writes only
/// LastRunNowAt, which the caller has set, and reason is the code that held it; otherwise a skip writes LastSkipAt, LastSkipReason and NextDueAt. Throws
/// when the row cannot be saved.
ClassMethod Run(row As OcuTalon.Data.HeartbeatBeat, values As %DynamicObject, at As %String, runNow As %Boolean, capped As %Boolean, keyed As %Boolean, Output reason As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set reason = ..Skip(values, row, at, runNow, capped, keyed)
	Set snapshot = ""
	Set key = ""
	If reason = "" {
		Set snapshot = ..Snapshot(row.SessionRef, at)
		Set key = ..Key(snapshot)
		Set reason = ..Skip(values, row, at, runNow, capped, keyed, key)
	}
	If reason '= "" {
		If 'runNow {
			Set row.LastSkipAt = at
			Set row.LastSkipReason = reason
			Set row.NextDueAt = ..NextDue(values, at, reason)
		}
		$$$ThrowOnError(row.%Save())
		Quit ""
	}
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = row.SessionRef
	Set item.Channel = ..#CHANNEL
	Set item.Provenance = "untrusted"
	Set item.Subject = ..#SUBJECT
	Set item.Text = snapshot
	Set row.LastBeatAt = at
	Set row.LastItemId = item.ItemId
	Set row.LastSnapshotKey = key
	Set row.NextDueAt = ##class(OcuTalon.Data.Time).AddSeconds(at, values.interval * 60)
	Set row.LastOutcome = ""
	Set row.LastFallback = 0
	Set row.LastCostUSD = ""
	Set row.LastDecisionRef = ""
	Set row.LastTraceSessionId = ""
	$$$ThrowOnError(row.%Save())
	Quit item
}

/// Records the decision of the row's pending beat when there is one (see the class description), and saves the row.
ClassMethod Settle(row As OcuTalon.Data.HeartbeatBeat, at As %String) As %Status [ Private ]
{
	If (row.LastItemId = "") || (row.LastDecisionRef '= "") Quit $$$OK
	Set decision = ##class(OcuTalon.Data.Ownership).DecisionOfItem(row.LastItemId, row.SessionRef, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(decision) Quit $$$OK
	Set row.LastOutcome = decision.Outcome
	Set row.LastFallback = decision.Fallback
	Set row.LastCostUSD = decision.CostUSD
	Set row.LastDecisionRef = decision.Ref
	Set row.LastTraceSessionId = decision.TraceSessionId
	If decision.Outcome = "ignore" Set row.LastQuietKey = row.LastSnapshotKey
	If decision.Fallback {
		Set wait = ..Values(row.SessionRef).interval * 60
		Set row.BackoffUntil = ##class(OcuTalon.Data.Time).AddSeconds(at, $Select(wait > ..#BACKOFFSECONDS: wait, 1: ..#BACKOFFSECONDS))
	}
	Quit row.%Save()
}

/// Counts one failure and adds the error codes of the status to the comma-separated codes.
ClassMethod Failed(sc As %Status, ByRef failed As %Integer, ByRef codes As %String) [ Private ]
{
	Set failed = failed + 1
	Set list = $ListFromString($SYSTEM.Status.GetErrorCodes(sc))
	Set position = 0
	While $ListNext(list, position, code) {
		If '$ListFind($ListFromString(codes), code) Set codes = codes_$Select(codes = "": "", 1: ",")_code
	}
}

/// The settings key of the session for a name in KEYS, else "".
ClassMethod SettingKey(sessionRef As %String, name As %String) As %String
{
	If name = "" || '$ListFind($ListFromString(..#KEYS), name) Quit ""
	Quit "person."_sessionRef_".heartbeat."_name
}

}
