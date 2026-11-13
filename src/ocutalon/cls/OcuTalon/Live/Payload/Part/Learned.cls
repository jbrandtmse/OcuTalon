/// One learned save the reply announces (Story 41.15): a fact that the turn saved from the person's own words, as the line under the reply shows it. Owned by Lane B.
Class OcuTalon.Live.Payload.Part.Learned Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The Ref of the memory.
Property MemoryRef As %String(%JSONFIELDNAME = "memoryRef", MAXLEN = 128);

/// The fact as the line shows it (OcuTalon.Memory.Learned.Fact): the stored text with one trailing full stop removed and cut to 200 characters. The page only fills the line's slot with it.
Property Fact As %String(%JSONFIELDNAME = "fact", MAXLEN = "");

/// The entries of an array of {memoryRef, fact} (OcuTalon.Memory.Learned.Shown), in order; an element that is not an object is skipped. Anything else gives an empty list.
ClassMethod ListFromShown(shown As %DynamicArray) As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	Try {
		If '$IsObject(shown) || ($ClassName(shown) '= "%Library.DynamicArray") Quit
		For i = 0:1:shown.%Size() - 1 {
			If shown.%GetTypeOf(i) '= "object" Continue
			Set element = shown.%Get(i)
			Set row = ..%New()
			Set row.MemoryRef = element.%Get("memoryRef")
			Set row.Fact = element.%Get("fact")
			Do list.Insert(row)
		}
	} Catch exception {
		Set list = ##class(%ListOfObjects).%New()
	}
	Quit list
}

}
