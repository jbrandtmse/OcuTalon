/// Adds one document to the session's knowledge base (AD-1, AD-21, AD-29; Story 34.2). Owner: DocumentOps (OcuTalon.Docs.Ops, Lane A).
/// Origin: web_user only; the documents route checks the type and the size, and stores the bytes as an Upload row, before it submits one.
Class OcuTalon.Msg.Command.AddDocument Extends OcuTalon.Msg.Command
{

/// The file's name as the person gave it.
Property Name As %String(MAXLEN = 255);

/// One of markdown, text, pdf or docx.
Property ContentType As %String(MAXLEN = 16, VALUELIST = ",markdown,text,pdf,docx");

/// The Ref of the OcuTalon.Data.Upload row that holds the file's bytes. DocumentOps reads them with Upload.Take; a message body holds no
/// global stream (DW-448's key proof).
Property UploadRef As %String(COLLATION = "EXACT", MAXLEN = 22);

Storage Default
{
<Data name="AddDocumentDefaultData">
<Subscript>"AddDocument"</Subscript>
<Value name="1">
<Value>Name</Value>
</Value>
<Value name="2">
<Value>ContentType</Value>
</Value>
<Value name="3">
<Value>UploadRef</Value>
</Value>
</Data>
<DefaultData>AddDocumentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
