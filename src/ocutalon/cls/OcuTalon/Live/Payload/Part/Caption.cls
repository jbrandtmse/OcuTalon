/// The caption that a photo's reply saved as a memory (Story 25.6): the memory's Ref and the caption as saved. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.Caption Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the memory.
Property MemoryRef As %String(%JSONFIELDNAME = "memoryRef", MAXLEN = 128);

/// The caption, as saved.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// The part for a turn's Caption, the JSON object {memoryRef, text}, or "" when it is empty or not that object.
ClassMethod FromJSON(json As %String) As OcuTalon.Live.Payload.Part.Caption
{
	If json = "" Quit ""
	Set part = ""
	Try {
		Set caption = ##class(%DynamicAbstractObject).%FromJSON(json)
		If $ClassName(caption) '= "%Library.DynamicObject" Quit
		Set part = ..%New()
		Set part.MemoryRef = caption.%Get("memoryRef")
		Set part.Text = caption.%Get("text")
	} Catch {
		Set part = ""
	}
	Quit part
}

}
