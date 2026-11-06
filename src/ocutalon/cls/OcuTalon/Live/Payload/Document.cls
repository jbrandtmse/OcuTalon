/// The payload of the document live event: one document (AD-12, AD-21). DocumentOps (Lane A, Story 19.4) is the only publisher; the class is
/// Lane B's file until then (Story 34.2). removed is true on a removed document's last event, which takes the row off the Documents page.
Class OcuTalon.Live.Payload.Document Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The document's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The file's name as the person gave it.
Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 255);

/// When the document was added, UTC to the second.
Property AddedAt As %String(%JSONFIELDNAME = "addedAt", MAXLEN = 20);

/// The file's size in bytes.
Property Size As %Integer(%JSONFIELDNAME = "size");

/// Where the document is: indexing, ready or failed.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16);

/// For a failed document, the code of the reason. Empty otherwise.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 32);

/// True on a removed document's last event.
Property Removed As %Boolean(%JSONFIELDNAME = "removed") [ InitialExpression = 0 ];

/// The payload for a document row, with every row-backed field set; removed is false.
ClassMethod FromRow(row As OcuTalon.Data.Document) As OcuTalon.Live.Payload.Document
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Name = row.Name
	Set payload.AddedAt = row.AddedAt
	Set payload.Size = row.Size
	Set payload.State = row.State
	Set payload.Reason = row.Reason
	Quit payload
}

}
