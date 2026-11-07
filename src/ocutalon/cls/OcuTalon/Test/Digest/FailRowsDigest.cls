/// OcuTalon.Digest.Process whose Rows seam always fails (test only; Story 17.6). Test.Digest.Send puts it behind the Digest item of the running production
/// (RunnerFixture UseItemClass), so that a Compose fails in the real framework and the failure shows on its message header and in its trace session. It is
/// not an item of the product's production, and the product never refers to it.
Class OcuTalon.Test.Digest.FailRowsDigest Extends OcuTalon.Digest.Process
{

/// The text of the error, which the tests look for.
Parameter FAILURE = "zz the rows could not be built";

Method Rows(sessionRef As %String, fromUtc As %String, toUtc As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, ..#FAILURE)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
