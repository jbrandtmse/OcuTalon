/// An incident; IncidentManager is its only writer (AD-15). Lane A.
Class OcuTalon.Data.Incident Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Incident";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// One of Msg.Enum INCIDENTSTATE.
Property State As %String(MAXLEN = 32);

/// One of Msg.Enum INCIDENTOPENVARIANT, stored beside the state (AD-15).
Property OpenVariant As %String(MAXLEN = 32);

/// When the notice was sent; empty until then (AD-15).
Property NoticedAt As %String(MAXLEN = 20);

/// The failure count.
Property Count As %Integer [ SqlFieldName = FailureCount ];

/// The failure count at the notice.
Property NoticeCount As %Integer;

/// When the first failure arrived.
Property FirstAt As %String(MAXLEN = 20);

/// When the last failure arrived.
Property LastAt As %String(MAXLEN = 20);

/// The item noun as {"one","other"} (AD-15).
Property ItemNoun As %String(MAXLEN = "");

/// The diagnosed cause.
Property Cause As %String(MAXLEN = 1000);

/// The category of the cause.
Property CauseCategory As %String(MAXLEN = 32);

/// The element that failed.
Property Element As %String(MAXLEN = 128);

/// A one-line summary of the proposed fix.
Property FixSummary As %String(MAXLEN = 1000);

/// True when the result took the fallback route (AD-8).
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

/// The diagnosis decision's Ref.
Property DecisionRef As %String(MAXLEN = 22);

/// The incident's trace session id (AD-26).
Property TraceHeaderId As %Integer;

/// When the incident was closed, UTC to the second.
Property ClosedAt As %String(MAXLEN = 20);

/// The header id of the earliest failure, in the watched namespace; empty when that failure is an event-log row. Moves with FirstAt.
Property FirstHeaderId As %Integer;

/// The header id of the diagnosis pack's sample failed message, in the watched namespace; empty when the sample is a log row or was not read.
Property SampleHeaderId As %Integer;

/// The sample's error as the pack gives it (OcuTalon.Watch.ErrorText.Text).
Property SampleError As %String(MAXLEN = 1000);

/// The Refs of the incident's approval requests, comma-separated, in the order they were raised.
Property RequestRefs As %String(MAXLEN = "");

/// When the first of the same-cause failures that joined after a dry-run ask arrived (UTC, the earliest FailedAt of them); empty while none waits. It starts
/// a later round and is the round's {time} (Story 7.6). Written by IncidentManager only.
Property LaterSince As %String(MAXLEN = 20);

/// While a later round's dry run is on its way: the round's {time}, moved here from LaterSince when the ask was made (UTC); empty otherwise. One ask is on its
/// way at a time (Story 7.6). Written by IncidentManager only.
Property AskingSince As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index OwnerRefIndex On OwnerRef;

Storage Default
{
<Data name="IncidentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>OwnerRef</Value>
</Value>
<Value name="4">
<Value>Namespace</Value>
</Value>
<Value name="5">
<Value>Production</Value>
</Value>
<Value name="6">
<Value>State</Value>
</Value>
<Value name="7">
<Value>OpenVariant</Value>
</Value>
<Value name="8">
<Value>NoticedAt</Value>
</Value>
<Value name="9">
<Value>Count</Value>
</Value>
<Value name="10">
<Value>NoticeCount</Value>
</Value>
<Value name="11">
<Value>FirstAt</Value>
</Value>
<Value name="12">
<Value>LastAt</Value>
</Value>
<Value name="13">
<Value>ItemNoun</Value>
</Value>
<Value name="14">
<Value>Cause</Value>
</Value>
<Value name="15">
<Value>CauseCategory</Value>
</Value>
<Value name="16">
<Value>Element</Value>
</Value>
<Value name="17">
<Value>FixSummary</Value>
</Value>
<Value name="18">
<Value>Fallback</Value>
</Value>
<Value name="19">
<Value>FallbackReason</Value>
</Value>
<Value name="20">
<Value>DecisionRef</Value>
</Value>
<Value name="21">
<Value>TraceHeaderId</Value>
</Value>
<Value name="22">
<Value>ClosedAt</Value>
</Value>
<Value name="23">
<Value>FirstHeaderId</Value>
</Value>
<Value name="24">
<Value>SampleHeaderId</Value>
</Value>
<Value name="25">
<Value>SampleError</Value>
</Value>
<Value name="26">
<Value>RequestRefs</Value>
</Value>
<Value name="27">
<Value>LaterSince</Value>
</Value>
<Value name="28">
<Value>AskingSince</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.IncidentD</DataLocation>
<DefaultData>IncidentDefaultData</DefaultData>
<IdLocation>^OcuTalonP.IncidentD</IdLocation>
<IndexLocation>^OcuTalonP.IncidentI</IndexLocation>
<StreamLocation>^OcuTalonP.IncidentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
