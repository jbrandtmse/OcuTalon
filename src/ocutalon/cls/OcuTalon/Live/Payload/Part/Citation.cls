/// One citation shown under a reply: a passage of one of the user's documents that a documents tool call returned for the
/// turn. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.Citation Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the document.
Property DocumentRef As %String(%JSONFIELDNAME = "documentRef", MAXLEN = 128);

/// The document's name.
Property Document As %String(%JSONFIELDNAME = "document", MAXLEN = 1000);

/// The heading the passage sits under; empty for a passage under no heading.
Property Section As %String(%JSONFIELDNAME = "section", MAXLEN = 1000);

/// The passage text.
Property Passage As %String(%JSONFIELDNAME = "passage", MAXLEN = "");

/// The position of the passage among the document's chunks.
Property ChunkIndex As %Integer(%JSONFIELDNAME = "chunkIndex");

/// The citations of a JSON array of {documentRef, document, section, passage, chunkIndex}, in order; an element that is not an
/// object is skipped. A text that is not a JSON array gives an empty list.
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
			Set row.DocumentRef = ..Text(element, "documentRef")
			Set row.Document = ..Text(element, "document")
			Set row.Section = ..Text(element, "section")
			Set row.Passage = ..Text(element, "passage")
			Set row.ChunkIndex = $Select(element.%GetTypeOf("chunkIndex") = "number": element.%Get("chunkIndex"), 1: 0)
			Do list.Insert(row)
		}
	} Catch exception {
		Set list = ##class(%ListOfObjects).%New()
	}
	Quit list
}

/// The member of the element as text, "" unless it is a string or a number.
ClassMethod Text(element As %DynamicObject, name As %String) As %String [ Private ]
{
	Quit $Select(element.%GetTypeOf(name) = "string": element.%Get(name), element.%GetTypeOf(name) = "number": element.%Get(name), 1: "")
}

}
