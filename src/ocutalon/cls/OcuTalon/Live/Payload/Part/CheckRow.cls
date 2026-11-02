/// One check result shown under a reply (AD-28): what Checks.Render made of a result. Shared by both lanes, owned by Lane B.
Class OcuTalon.Live.Payload.Part.CheckRow Extends (%RegisteredObject, %JSON.Adaptor)
{

/// passed, failed or not_checked; any other value is shown as not checked.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 32);

/// What was checked.
Property Entry As %String(%JSONFIELDNAME = "entry", MAXLEN = 1000);

/// What the check found, or why it did not run.
Property Finding As %String(%JSONFIELDNAME = "finding", MAXLEN = 1000);

/// When the check ran, UTC to the second.
Property CheckedAt As %String(%JSONFIELDNAME = "checkedAt", MAXLEN = 32);

/// The rows of a JSON array of {result, entry, finding, checkedAt}, in order; an element that is not an object is skipped.
/// A text that is not a JSON array gives an empty list.
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
			Set row.Result = ..Text(element, "result")
			Set row.Entry = ..Text(element, "entry")
			Set row.Finding = ..Text(element, "finding")
			Set row.CheckedAt = ..Text(element, "checkedAt")
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
