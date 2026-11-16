/// The read result of a chat message's file (Story 25.6): whether OcuTalon read it and whether it can be added to the documents; never the bytes and never the extracted text. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.FileRead Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the stored file.
Property FileRef As %String(%JSONFIELDNAME = "fileRef", MAXLEN = 22);

/// One of document, photo.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 16);

/// 1 when the file was read, else 0.
Property Read As %Integer(%JSONFIELDNAME = "read") [ InitialExpression = 0 ];

/// 1 when the file is a document that was read and can be added to the documents, else 0.
Property Addable As %Integer(%JSONFIELDNAME = "addable") [ InitialExpression = 0 ];

/// The part for a turn's FileRead, the JSON object that Conversation keeps, or "" when it is empty or not that object. Only the four members above are taken from it.
ClassMethod FromJSON(json As %String) As OcuTalon.Live.Payload.Part.FileRead
{
	If json = "" Quit ""
	Set part = ""
	Try {
		Set result = ##class(%DynamicAbstractObject).%FromJSON(json)
		If $ClassName(result) '= "%Library.DynamicObject" Quit
		Set part = ..%New()
		Set part.FileRef = result.%Get("fileRef")
		Set part.Kind = result.%Get("kind")
		Set part.Read = +result.%Get("read")
		Set part.Addable = +result.%Get("addable")
	} Catch {
		Set part = ""
	}
	Quit part
}

}
