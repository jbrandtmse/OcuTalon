/// The base of the test feed's typed records (Story 9.9). A typed record is what a message must be valid as: its properties have the datatypes and
/// constraints that the receiving item enforces, and %ValidateObject judges it with IRIS's own validation. A record has no storage and is never saved.
/// NewPinned gives a record at a fixed object reference number, and Copy sets each property of a record from the request's property of the same name.
Class OcuTalon.Test.Eval.Feed.TypedRecord Extends %RegisteredObject [ Abstract ]
{

/// The object reference number of the record that NewPinned gives. It is above any number that a job of the feed holds.
Parameter REFNUMBER = 128;

/// The most instances that NewPinned takes while it looks for REFNUMBER.
Parameter PADMAX = 400;

/// A new record whose object reference number is REFNUMBER. IRIS prints the number in some validation errors (a required property is reported as
/// Property(6@Class)), and the number a new object gets depends on the objects the job held and released before, so the error text would differ
/// between runs and between recordings. NewPinned takes instances until one has the number, releases the others and then that one, and the next %New()
/// gets the number again (a released number is reused last in, first out). When the job already holds numbers above REFNUMBER, or PADMAX instances do
/// not reach it, the record gets the number that IRIS gives it. The markers of the case claims-member-missing in Fixture (XData Cases) name REFNUMBER,
/// so that a record that was not pinned fails that case at once.
ClassMethod NewPinned() As OcuTalon.Test.Eval.Feed.TypedRecord
{
	Set hit = 0, count = 0
	For {
		Set pad = ..%New()
		Set count = count + 1, held(count) = pad
		If +pad = ..#REFNUMBER Set hit = count
		If (+pad '< ..#REFNUMBER) || (count '< ..#PADMAX) Quit
	}
	Kill pad
	For i = 1:1:count {
		If i '= hit Kill held(i)
	}
	If hit Kill held(hit)
	Quit ..%New()
}

/// The record with each of its own properties (the ones whose names do not start with %) set from the request's property of the same name. A property
/// that the request lacks is an error (thrown by IRIS).
ClassMethod Copy(record As %RegisteredObject, request As Ens.Request) As %RegisteredObject
{
	Set compiled = ##class(%Dictionary.CompiledClass).%OpenId($ClassName(record))
	For i = 1:1:compiled.Properties.Count() {
		Set name = compiled.Properties.GetAt(i).Name
		If $Extract(name) '= "%" Set $Property(record, name) = $Property(request, name)
	}
	Quit record
}

}
