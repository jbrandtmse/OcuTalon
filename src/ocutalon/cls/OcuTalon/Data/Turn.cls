/// A turn in a session's queue (AD-30): the user's message, its two decisions and the reply as it was sent. Lane B.
Class OcuTalon.Data.Turn Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Turn";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// queued, running, done or refused (the record of a message the online demo's allowance turned away, AD-20: never queued, never shown).
Property State As %String(MAXLEN = 32);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// Display only (AD-30).
Property FromGuide As %Boolean [ InitialExpression = 0 ];

/// The Ref of the turn's triage decision (AD-20).
Property TriageDecisionRef As %String(MAXLEN = 22);

/// The Ref of the turn's reply decision (AD-20).
Property TurnDecisionRef As %String(MAXLEN = 22);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

/// The Ref of the Item message that made the turn (AD-14); unique, so that a re-delivered Item makes no second turn.
Property ItemId As %String(MAXLEN = 22);

/// The page's own id for the message, compared exactly; empty for a message from another channel.
Property ClientId As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The user's message.
Property Text As %String(MAXLEN = "");

/// The reply as it was sent; empty until the turn is done, and for a fallback.
Property ReplyText As %String(MAXLEN = "");

/// The catalog key of a fallback reply (AD-32); empty for a reply the model wrote.
Property ReplyCatalogKey As %String(MAXLEN = 128);

/// The reason of a fallback reply: one of Msg.Enum FALLBACKREASON.
Property FallbackReason As %String(MAXLEN = 32);

/// The ID of the Item message's header, where the turn's trace opens (AD-26); the namespace is the running one.
Property TraceHeaderId As %Integer;

/// The position of the Item's header in the item list that Visual Trace draws for its session, with the event-log and
/// rule-log rows shown (AD-26); empty until Conversation has taken the Item, and when the position could not be worked out.
Property TraceItemIndex As %Integer;

/// The same position with the event-log and rule-log rows hidden.
Property TraceItemIndexNoEvents As %Integer;

/// True when the reply let untrusted content into the conversation (AD-10): the next turn then starts a fresh session.
Property Tainted As %Boolean [ InitialExpression = 0 ];

/// How many times the turn has started; a Conversation instance whose count differs from the row's is stale (AD-30).
Property Attempt As %Integer [ InitialExpression = 0 ];

/// The catalog key of the check results that Checks.Render made for the reply (AD-28); empty for a reply with none.
Property CheckKey As %String(MAXLEN = 128);

/// The check rows that Checks.Render made for the reply, as a JSON array of {result, entry, finding, checkedAt}; empty for
/// a reply with none.
Property CheckRows As %String(MAXLEN = "");

/// The Ref of the decision whose figures the turn shows (AD-20): for a fallback reply the reply decision, else the triage
/// decision; the other one when the first is empty.
Method ShownDecisionRef() As %String
{
	If ..ReplyCatalogKey '= "" Quit $Select(..TurnDecisionRef '= "": ..TurnDecisionRef, 1: ..TriageDecisionRef)
	Quit $Select(..TriageDecisionRef '= "": ..TriageDecisionRef, 1: ..TurnDecisionRef)
}

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Index ItemIdIndex On ItemId [ Unique ];

Index ClientIdIndex On (SessionRef, ClientId);

Storage Default
{
<Data name="TurnDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>Channel</Value>
</Value>
<Value name="6">
<Value>FromGuide</Value>
</Value>
<Value name="7">
<Value>TriageDecisionRef</Value>
</Value>
<Value name="8">
<Value>TurnDecisionRef</Value>
</Value>
<Value name="9">
<Value>CreatedAt</Value>
</Value>
<Value name="10">
<Value>ItemId</Value>
</Value>
<Value name="11">
<Value>ClientId</Value>
</Value>
<Value name="12">
<Value>Text</Value>
</Value>
<Value name="13">
<Value>ReplyText</Value>
</Value>
<Value name="14">
<Value>ReplyCatalogKey</Value>
</Value>
<Value name="15">
<Value>FallbackReason</Value>
</Value>
<Value name="16">
<Value>TraceHeaderId</Value>
</Value>
<Value name="17">
<Value>Tainted</Value>
</Value>
<Value name="18">
<Value>Attempt</Value>
</Value>
<Value name="19">
<Value>CheckKey</Value>
</Value>
<Value name="20">
<Value>CheckRows</Value>
</Value>
<Value name="21">
<Value>TraceItemIndex</Value>
</Value>
<Value name="22">
<Value>TraceItemIndexNoEvents</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.TurnD</DataLocation>
<DefaultData>TurnDefaultData</DefaultData>
<IdLocation>^OcuTalonP.TurnD</IdLocation>
<IndexLocation>^OcuTalonP.TurnI</IndexLocation>
<StreamLocation>^OcuTalonP.TurnS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
