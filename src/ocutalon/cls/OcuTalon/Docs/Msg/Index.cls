/// One batch of indexing for DocumentOps (AD-21, Story 19.4; Lane A): DocumentOps sends it to itself after it has saved a document's row, so that a large
/// document is indexed in batches of passages between the commands of the queue, and a RemoveDocument that arrives meanwhile is handled before the next
/// batch. Ref is the document's Ref and ChunkFrom the chunk_index of the first passage of the batch (0 for the first; the property is not called Next, an SQL reserved word). It holds no text.
Class OcuTalon.Docs.Msg.Index Extends Ens.Request
{

/// The document's Ref.
Property Ref As %String(MAXLEN = 22);

/// The chunk_index of the first passage of the batch.
Property ChunkFrom As %Integer [ InitialExpression = 0 ];

Storage Default
{
<Data name="IndexDefaultData">
<Subscript>"Index"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
<Value name="2">
<Value>ChunkFrom</Value>
</Value>
</Data>
<DefaultData>IndexDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
