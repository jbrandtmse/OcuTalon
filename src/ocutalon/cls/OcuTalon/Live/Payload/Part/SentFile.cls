/// The file that a chat message carries (Story 25.3): what the user's message shows, never the bytes. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.SentFile Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the stored file.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The file's name, to be shown as text.
Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 255);

/// The media type, read from the file's bytes.
Property MediaType As %String(%JSONFIELDNAME = "mediaType", MAXLEN = 128);

/// The size in bytes.
Property Size As %Integer(%JSONFIELDNAME = "size");

/// The part for a turn's SentFile, the JSON {ref, name, mediaType, size}, or "" when it is empty or not that object.
ClassMethod FromJSON(json As %String) As OcuTalon.Live.Payload.Part.SentFile
{
	If json = "" Quit ""
	Set part = ""
	Try {
		Set file = ##class(%DynamicAbstractObject).%FromJSON(json)
		If $ClassName(file) '= "%Library.DynamicObject" Quit
		Set part = ..%New()
		Set part.Ref = file.%Get("ref")
		Set part.Name = file.%Get("name")
		Set part.MediaType = file.%Get("mediaType")
		Set part.Size = file.%Get("size")
	} Catch {
		Set part = ""
	}
	Quit part
}

}
