/// One document a session or an install has added (AD-21, AD-33): the row the Documents page lists. Lane A. The only writer is
/// OcuTalon.Docs.Ops (Story 19.4). A document belongs to a session on the online demo (OwnerRef is its SessionRef) and to the install on a
/// local install (OwnerRef is the literal instance); AddedBy keeps the session that added it. Row ids never leave the server.
Class OcuTalon.Data.Document Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Document";

/// The document's public Ref (AD-14), the source of each chunk in the knowledge base. Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The owner of the document: a session's Ref on the online demo, the literal instance on a local install (AD-4).
Property OwnerRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session that added the document.
Property AddedBy As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The file's name as the person gave it.
Property Name As %String(MAXLEN = 255);

/// The kind of file: markdown, text, pdf or docx.
Property ContentType As %String(MAXLEN = 16);

/// The file's size in bytes.
Property Size As %Integer;

/// When the document was added, UTC to the second.
Property AddedAt As %String(MAXLEN = 20);

/// Where the document is: indexing, ready or failed.
Property State As %String(MAXLEN = 16) [ InitialExpression = "indexing" ];

/// For a failed document, the code of the reason. Empty otherwise.
Property Reason As %String(MAXLEN = 32);

/// The knowledge-base table that holds the document's passages (OcuTalonKB.Docs, or OcuTalonKB.S followed by a session's row id).
Property KnowledgeBase As %String(MAXLEN = 128);

/// The document's text, as read from the file.
Property Text As %Stream.GlobalCharacter;

Index RefIndex On Ref [ Unique ];

Index OwnerRefAddedAtIndex On (OwnerRef, AddedAt);

Storage Default
{
<Data name="DocumentDefaultData">
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
<Value>AddedBy</Value>
</Value>
<Value name="5">
<Value>Name</Value>
</Value>
<Value name="6">
<Value>ContentType</Value>
</Value>
<Value name="7">
<Value>Size</Value>
</Value>
<Value name="8">
<Value>AddedAt</Value>
</Value>
<Value name="9">
<Value>State</Value>
</Value>
<Value name="10">
<Value>Reason</Value>
</Value>
<Value name="11">
<Value>KnowledgeBase</Value>
</Value>
<Value name="12">
<Value>Text</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.DocumentD</DataLocation>
<DefaultData>DocumentDefaultData</DefaultData>
<IdLocation>^OcuTalonP.DocumentD</IdLocation>
<IndexLocation>^OcuTalonP.DocumentI</IndexLocation>
<StreamLocation>^OcuTalonP.DocumentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
