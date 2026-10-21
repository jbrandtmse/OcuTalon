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

/// The check rows a tool filled, as JSON (AD-6 HostData).
Property CheckRows As %String(MAXLEN = "");

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
</Data>
<DefaultData>OutboundDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
