/// One row per session that has had a heartbeat beat (AD-18). Lane A. Written only by Checks (AD-33): the schedule (NextDueAt), the last beat's outcome,
/// the last skip, the last requested run, the back-off and the keys of the last snapshot and the last quiet reading. Times are UTC to the second.
Class OcuTalon.Data.HeartbeatBeat Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.HeartbeatBeat";

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// When the next beat is due.
Property NextDueAt As %String(MAXLEN = 20);

/// When the last beat ran.
Property LastBeatAt As %String(MAXLEN = 20);

/// The Ref of the item that the last beat produced.
Property LastItemId As %String(MAXLEN = 22);

/// The outcome of the last beat's decision.
Property LastOutcome As %String(MAXLEN = 32);

/// True when the last beat's decision was a fallback.
Property LastFallback As %Boolean [ InitialExpression = 0 ];

/// The cost in USD of the last beat's decision.
Property LastCostUSD As %Numeric(SCALE = 6);

/// The Ref of the last beat's decision.
Property LastDecisionRef As %String(MAXLEN = 22);

/// The trace session id of the last beat's decision.
Property LastTraceSessionId As %Integer;

/// When the last beat was skipped.
Property LastSkipAt As %String(MAXLEN = 20);

/// Why the last beat was skipped.
Property LastSkipReason As %String(MAXLEN = 32);

/// When the person last asked for a run.
Property LastRunNowAt As %String(MAXLEN = 20);

/// No beat runs before this time.
Property BackoffUntil As %String(MAXLEN = 20);

/// The key of the snapshot that the last beat read.
Property LastSnapshotKey As %String(MAXLEN = 64);

/// The key of the last quiet reading.
Property LastQuietKey As %String(MAXLEN = 64);

Index SessionRefIndex On SessionRef [ Unique ];

Storage Default
{
<Data name="HeartbeatBeatDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>NextDueAt</Value>
</Value>
<Value name="4">
<Value>LastBeatAt</Value>
</Value>
<Value name="5">
<Value>LastItemId</Value>
</Value>
<Value name="6">
<Value>LastOutcome</Value>
</Value>
<Value name="7">
<Value>LastFallback</Value>
</Value>
<Value name="8">
<Value>LastCostUSD</Value>
</Value>
<Value name="9">
<Value>LastDecisionRef</Value>
</Value>
<Value name="10">
<Value>LastTraceSessionId</Value>
</Value>
<Value name="11">
<Value>LastSkipAt</Value>
</Value>
<Value name="12">
<Value>LastSkipReason</Value>
</Value>
<Value name="13">
<Value>LastRunNowAt</Value>
</Value>
<Value name="14">
<Value>BackoffUntil</Value>
</Value>
<Value name="15">
<Value>LastSnapshotKey</Value>
</Value>
<Value name="16">
<Value>LastQuietKey</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.HeartbeatBeatD</DataLocation>
<DefaultData>HeartbeatBeatDefaultData</DefaultData>
<IdLocation>^OcuTalonP.HeartbeatBeatD</IdLocation>
<IndexLocation>^OcuTalonP.HeartbeatBeatI</IndexLocation>
<StreamLocation>^OcuTalonP.HeartbeatBeatS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
