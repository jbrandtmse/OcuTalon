/// The heartbeat's rules and records (AD-18; FR-32): which Tick a run makes, and the two kinds of status mark that a run leaves.
/// HeartbeatIn calls these; Story 8.2 reads the tick mark for the stalled warning and Story 17.5's digest reads the gaps.
///   - The tick mark, heartbeatTick: the UTC time of the last tick that was taken.
///   - A gap mark, heartbeatGap.<start UTC>: one per gap of whole clock minutes between two ticks, {"start","end","missed"}. The
///     mark is named by the start, so a run that records the same gap again replaces it. Marks are kept like every other mark.
/// Minutes count by the clock minute (the seconds of Data.Time.Seconds, divided by 60), so a run that is a few seconds late is
/// not a gap.
Class OcuTalon.Schedule.Heartbeat
{

/// The status mark that holds the time of the last tick.
Parameter TICKMARK = "heartbeatTick";

/// The start of the name of a gap mark; the start of the gap (UTC) follows.
Parameter GAPMARK = "heartbeatGap.";

/// The production item that receives the Tick.
Parameter TARGET = "Checks";

/// The lock that HeartbeatIn works under. It names no data; it only serializes the runs.
Parameter LOCK = "^OcuTalonP.HeartbeatLock";

/// The Tick for a run at now when the previous tick was taken at previous (the tick mark, "" when there is none), and the number
/// of clock minutes that passed with no tick in missed. It saves and sends nothing.
///   - A previous that is empty or unreadable makes a first tick: PreviousTickAt is "", and missed is 0.
///   - missed is (the minute of now - the minute of previous) - 1, and never below 0. A previous in the same minute as now, or
///     later than now (the clock moved back), leaves it at 0, and PreviousTickAt keeps the previous tick.
///   - CatchUp is 1 exactly when missed is more than 0.
ClassMethod Next(previous As %String, now As %String, Output missed As %Integer) As OcuTalon.Msg.Tick
{
	Set missed = 0
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = $Get(now)
	Set before = ##class(OcuTalon.Data.Time).Seconds($Get(previous))
	If before = "" Quit tick
	Set tick.PreviousTickAt = previous
	Set current = ##class(OcuTalon.Data.Time).Seconds($Get(now))
	If current = "" Quit tick
	Set missed = (current \ 60) - (before \ 60) - 1
	If missed < 0 Set missed = 0
	Set tick.CatchUp = $Select(missed > 0: 1, 1: 0)
	Quit tick
}

/// Records the run: the gap mark first, when missed is more than 0 and the tick has a previous time, and then the tick mark, the
/// time of the tick. A failed gap mark returns its status and leaves the tick mark as it was, so the next run finds the same gap
/// and writes the same gap mark again.
ClassMethod Record(tick As OcuTalon.Msg.Tick, missed As %Integer = 0) As %Status
{
	If (+missed > 0) && (tick.PreviousTickAt '= "") {
		Set gap = {"start": (tick.PreviousTickAt), "end": (tick.TickAt), "missed": (+missed)}
		Set sc = ##class(OcuTalon.Data.StatusMark).Record(..#GAPMARK _ tick.PreviousTickAt, gap.%ToJSON())
		If $$$ISERR(sc) Quit sc
	}
	Quit ##class(OcuTalon.Data.StatusMark).Record(..#TICKMARK, tick.TickAt)
}

/// The gaps that overlap the window from fromUtc to toUtc (UTC times, both ends included), oldest first, as a dynamic array of
/// {"start","end","missed"}. A gap overlaps when it starts no later than toUtc and ends no earlier than fromUtc, so a gap that
/// began before the window and ends in it counts, and so does one that spans it. An empty fromUtc or toUtc leaves that side open.
/// A gap mark whose value is not a JSON object is left out.
ClassMethod Gaps(fromUtc As %String = "", toUtc As %String = "") As %DynamicArray
{
	Set gaps = []
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Value FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH ? ORDER BY Mark", ..#GAPMARK)
	While rows.%Next() {
		Set gap = ""
		Try {
			Set gap = {}.%FromJSON(rows.%GetData(1))
		} Catch {
			Set gap = ""
		}
		If '$IsObject(gap) || 'gap.%IsA("%Library.DynamicObject") Continue
		Set start = gap.start
		Set end = gap.end
		If (start = "") || (end = "") Continue
		If (toUtc '= "") && (start ] toUtc) Continue
		If (fromUtc '= "") && (fromUtc ] end) Continue
		Do gaps.%Push({"start": (start), "end": (end), "missed": (+gap.missed)})
	}
	Quit gaps
}

}
