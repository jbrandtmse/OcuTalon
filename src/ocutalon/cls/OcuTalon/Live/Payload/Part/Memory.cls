/// One memory shown under a reply: a memory that a memory search returned for the turn. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.Memory Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the memory.
Property MemoryRef As %String(%JSONFIELDNAME = "memoryRef", MAXLEN = 128);

/// The remembered text.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// When the memory was saved, UTC to the second.
Property SavedAt As %String(%JSONFIELDNAME = "savedAt", MAXLEN = 32);

/// The memories of a JSON array of {memoryRef, text, savedAt}, in order; an element that is not an object is skipped. A text
/// that is not a JSON array gives an empty list.
ClassMethod ListFromJSON(json As %String) As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	If json = "" Quit list
	Try {
		Set array = ##class(%DynamicAbstractObject).%FromJSON(json)
		If $ClassName(array) '= "%Library.DynamicArray" Quit
		For i = 0:1:array.%Size() - 1 {
			If array.%GetTypeOf(i) '= "object" Continue
			Set element = array.%Get(i)
			Set row = ..%New()
			Set row.MemoryRef = ..Value(element, "memoryRef")
			Set row.Text = ..Value(element, "text")
			Set row.SavedAt = ..Value(element, "savedAt")
			Do list.Insert(row)
		}
	} Catch exception {
		Set list = ##class(%ListOfObjects).%New()
	}
	Quit list
}

/// The member of the element as text, "" unless it is a string or a number.
ClassMethod Value(element As %DynamicObject, name As %String) As %String [ Private ]
{
	Quit $Select(element.%GetTypeOf(name) = "string": element.%Get(name), element.%GetTypeOf(name) = "number": element.%Get(name), 1: "")
}

}
