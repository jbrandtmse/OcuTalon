/// Removes one of the session's documents (AD-1, AD-21, AD-29; Story 34.2). Owner: DocumentOps (OcuTalon.Docs.Ops, Lane A).
/// Origin: web_user only; the documents route checks that the session can see the document before it submits one.
Class OcuTalon.Msg.Command.RemoveDocument Extends OcuTalon.Msg.Command
{

/// The document's Ref (OcuTalon.Data.Document).
Property DocumentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="RemoveDocumentDefaultData">
<Subscript>"RemoveDocument"</Subscript>
<Value name="1">
<Value>DocumentRef</Value>
</Value>
</Data>
<DefaultData>RemoveDocumentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
