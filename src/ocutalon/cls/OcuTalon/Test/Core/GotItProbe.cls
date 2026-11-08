/// A subclass of Test.Core.SessionOpsProbe for Test.Core.GotIt, which also overrides the private seams of the Handled save and of End's Handled step. SaveHandled
/// is answered by FailSave: "" calls the real method (##super), "error" answers an error status with no row, and "raced" saves the row and then answers an
/// error status, as when another press won the unique Ref between the check and the save. Each DropHandled
/// call is recorded as ^OcuTalonTest("GotItProbe", n) = <the SessionRef> (n counted in ^OcuTalonTest("GotItProbe")), and then FailHandled decides
/// the answer: "" calls the real method (##super), "error" answers an error status and "throw" throws. It has no Test methods and the product
/// never refers to it.
Class OcuTalon.Test.Core.GotItProbe Extends OcuTalon.Test.Core.SessionOpsProbe
{

/// "", "error" or "throw" for the Handled drop.
Property FailHandled As %String;

/// "", "error" or "raced" for the Handled save.
Property FailSave As %String;

Method SaveHandled(ref As %String, sessionRef As %String, channel As %String) As %Status [ Private ]
{
	If ..FailSave = "error" Quit $SYSTEM.Status.Error(5001, "zz the handled save failed")
	Set sc = ##super(ref, sessionRef, channel)
	If ..FailSave = "raced" Quit $SYSTEM.Status.Error(5001, "zz the handled save raced")
	Quit sc
}

Method DropHandled(sessionRef As %String) As %Status [ Private ]
{
	Set ^OcuTalonTest("GotItProbe", $Increment(^OcuTalonTest("GotItProbe"))) = sessionRef
	If ..FailHandled = "error" Quit $SYSTEM.Status.Error(5001, "zz the handled drop failed")
	If ..FailHandled = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the handled drop threw"))
	Quit ##super(sessionRef)
}

}
