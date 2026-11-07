/// OcuTalon.Digest.Process whose Rows seam answers fixed rows (test only; Story 17.7): the five healthy vital signs and one watched row that failed, the Orders
/// production with 3 items in error. Test.Digest.Send puts it behind the Digest item of the running production (RunnerFixture UseItemClass), so that a digest
/// with a failing check goes through the real Decide, reply guard and mock. It is not an item of the product's production, and the product never refers to it.
Class OcuTalon.Test.Digest.FedRowsDigest Extends OcuTalon.Digest.Process
{

/// The entry and the finding of the failed row.
Parameter ENTRY = "Orders production";

Parameter FINDING = "3 items in error";

Method Rows(sessionRef As %String, fromUtc As %String, toUtc As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject) As %Status [ Private ]
{
	Set vitals = ##class(OcuTalon.Test.Digest.ProcessProbe).Healthy()
	Set rows = [], lines = []
	Set iterator = vitals.rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do rows.%Push(row)
		Do lines.%Push({"key": "digest.passed", "slots": {"entry": (row.entry), "time": (row.checkedAt)}})
	}
	Set time = "2030-06-03T12:00:00Z"
	Do rows.%Push({"result": "failed", "entry": (..#ENTRY), "finding": (..#FINDING), "checkedAt": (time)})
	Do lines.%Push({"key": "digest.failed", "slots": {"entry": (..#ENTRY), "finding": (..#FINDING), "time": (time)}})
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
