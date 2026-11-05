/// A subclass of OcuTalon.Core.SessionOps for Test.Core.SessionOpsDocuments, which overrides the two private drop seams of End. Each call is
/// recorded as ^OcuTalonTest("SessionOpsDocuments", n) = <"documents" or "memories">_"|"_<the SessionRef> (n counted in
/// ^OcuTalonTest("SessionOpsDocuments")), and then FailDocuments / FailMemories decide the answer: "" calls the real method (##super), "error"
/// answers an error status and "throw" throws. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.SessionOpsDropProbe Extends OcuTalon.Core.SessionOps
{

/// "", "error" or "throw" for the documents drop.
Property FailDocuments As %String;

/// "", "error" or "throw" for the memories drop.
Property FailMemories As %String;

Method DropDocuments(sessionRef As %String) As %Status [ Private ]
{
	Set ^OcuTalonTest("SessionOpsDocuments", $Increment(^OcuTalonTest("SessionOpsDocuments"))) = "documents|"_sessionRef
	If ..FailDocuments = "error" Quit $SYSTEM.Status.Error(5001, "zz the documents drop failed")
	If ..FailDocuments = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the documents drop threw"))
	Quit ##super(sessionRef)
}

Method DropMemories(sessionRef As %String) As %Status [ Private ]
{
	Set ^OcuTalonTest("SessionOpsDocuments", $Increment(^OcuTalonTest("SessionOpsDocuments"))) = "memories|"_sessionRef
	If ..FailMemories = "error" Quit $SYSTEM.Status.Error(5001, "zz the memories drop failed")
	If ..FailMemories = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the memories drop threw"))
	Quit ##super(sessionRef)
}

}
