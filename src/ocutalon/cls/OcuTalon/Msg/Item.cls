/// An inbound item: the one message every channel service sends to Intake or Conversation (AD-14). Lane B.
Class OcuTalon.Msg.Item Extends Ens.Request
{

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// Set only by EvalIn to the evaluation case id, copied by every hop, empty otherwise (AD-14).
Property SourceItemId As %String(MAXLEN = 128);

/// The owner: a session's Ref, instance, or eval, which only EvalIn sets; Intake copies it to ItemDecision.OwnerRef (AD-14).
Property SessionRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// user for text the user writes on any channel, untrusted for everything else: one of Msg.Enum PROVENANCE (AD-14).
Property Provenance As %String(MAXLEN = 32);

/// The content of the item.
Property Text As %String(MAXLEN = "");

/// The sender, as the channel reports it.
Property Sender As %String(MAXLEN = 1000);

/// The subject line of a mail item.
Property Subject As %String(MAXLEN = 1000);

/// True when the text came from a guide prompt; display only (AD-30).
Property FromGuide As %Boolean [ InitialExpression = 0 ];

/// Optional: the catalog key of an item whose notice text is fixed by code rather than written by the model (AD-14).
Property CatalogKey As %String(MAXLEN = 128);

/// Optional: the slots of CatalogKey, as JSON (AD-32).
Property Slots As %String(MAXLEN = "");

/// The page's own id for the message; set only by WebChatIn (AD-30), empty otherwise.
Property ClientId As %String(MAXLEN = 128);

Storage Default
{
<Data name="ItemDefaultData">
<Subscript>"Item"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>SourceItemId</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>Channel</Value>
</Value>
<Value name="5">
<Value>Provenance</Value>
</Value>
<Value name="6">
<Value>Text</Value>
</Value>
<Value name="7">
<Value>Sender</Value>
</Value>
<Value name="8">
<Value>Subject</Value>
</Value>
<Value name="9">
<Value>FromGuide</Value>
</Value>
<Value name="10">
<Value>CatalogKey</Value>
</Value>
<Value name="11">
<Value>Slots</Value>
</Value>
<Value name="12">
<Value>ClientId</Value>
</Value>
</Data>
<DefaultData>ItemDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
