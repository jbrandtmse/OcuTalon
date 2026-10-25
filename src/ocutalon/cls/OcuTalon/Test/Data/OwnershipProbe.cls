/// A subclass of OcuTalon.Data.Ownership for the tests, which may call its private Rows: it only passes the call
/// through. It adds nothing to the product's surface; the product never refers to it.
Class OcuTalon.Test.Data.OwnershipProbe Extends OcuTalon.Data.Ownership
{

/// Ownership.Rows, as the subclass sees it.
ClassMethod Call(kind As %String, ownerRef As %String, Output sc As %Status, args...) As %ListOfObjects
{
	Quit ..Rows(kind, ownerRef, .sc, args...)
}

}
