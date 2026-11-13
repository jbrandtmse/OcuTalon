/// A reply from Conversation to Notify (AD-32). Lane B.
Class OcuTalon.Msg.Outbound Extends Ens.Request
{

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// The paired chat's Ref, never a chat id (AD-14).
Property ChatRef As %String(MAXLEN = 22);

/// The channel of the turn that is answered: one of Msg.Enum CHANNEL (AD-32).
Property OriginChannel As %String(MAXLEN = 32);

/// The reply text.
Property Text As %String(MAXLEN = "");

/// The catalog key when the reply is a fixed text, such as a fallback (AD-32).
Property CatalogKey As %String(MAXLEN = 128);

/// The slots of the catalog text, as JSON (AD-32).
Property Slots As %String(MAXLEN = "");

/// The check rows of the reply (AD-28), as a JSON array of {result, entry, finding, checkedAt}: what Checks.Render made of
/// the reply's HostData checks. Empty for a reply with none.
Property CheckRows As %String(MAXLEN = "");

/// The Ref of the decision the reply shows (AD-20): the one whose reasons and cost go with the reply; empty when it has none.
Property DecisionRef As %String(MAXLEN = 22);

/// The catalog key of the check results (AD-28); empty when the reply has none.
Property CheckKey As %String(MAXLEN = 128);

/// The citations of the reply, as a JSON array of {documentRef, document, section, passage, chunkIndex}: what the reply's
/// HostData carried, after the reply filter. Empty for a reply with none.
Property Citations As %String(MAXLEN = "");

/// The memories the reply recalled, as a JSON array of {memoryRef, text, savedAt}. Empty for a reply with none.
Property Memories As %String(MAXLEN = "");

/// The learned saves of the reply (Story 41.15), as a JSON array of {memoryRef, text}: for the trace and for TelegramOut, which shows them as lines under the
/// reply (OcuTalon.Memory.Learned). Empty for a reply with none.
Property Learned As %String(MAXLEN = "");

Storage Default
{
<Data name="OutboundDefaultData">
<Subscript>"Outbound"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>ChatRef</Value>
</Value>
<Value name="3">
<Value>OriginChannel</Value>
</Value>
<Value name="4">
<Value>Text</Value>
</Value>
<Value name="5">
<Value>CatalogKey</Value>
</Value>
<Value name="6">
<Value>Slots</Value>
</Value>
<Value name="7">
<Value>CheckRows</Value>
</Value>
<Value name="8">
<Value>DecisionRef</Value>
</Value>
<Value name="9">
<Value>CheckKey</Value>
</Value>
<Value name="10">
<Value>Citations</Value>
</Value>
<Value name="11">
<Value>Memories</Value>
</Value>
<Value name="12">
<Value>Learned</Value>
</Value>
</Data>
<DefaultData>OutboundDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
