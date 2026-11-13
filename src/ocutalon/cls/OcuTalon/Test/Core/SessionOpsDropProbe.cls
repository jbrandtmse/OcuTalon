/// A subclass of OcuTalon.Core.SessionOps for Test.Core.SessionOpsDocuments, which overrides the three private drop seams of End. Each call is
/// recorded as ^OcuTalonTest("SessionOpsDocuments", n) = <"documents" or "memories">_"|"_<the SessionRef> (n counted in
/// ^OcuTalonTest("SessionOpsDocuments")), and then FailDocuments / FailMemories decide the answer: "" calls the real method (##super), "error"
/// answers an error status and "throw" throws. The uploads drop is recorded as ^OcuTalonTest("SessionOpsUploads", n) = <the SessionRef> (n counted
/// in ^OcuTalonTest("SessionOpsUploads")) and answered by FailUploads in the same way; the sent files drop is recorded under ^OcuTalonTest("SessionOpsSentFiles", n) and
/// answered by FailSentFiles in the same way. DropPrecedents answers 0 and sends nothing for a session with no precedent
/// rows, so that an End without a production sends nothing to PrecedentOps. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.SessionOpsDropProbe Extends OcuTalon.Core.SessionOps
{

/// "", "error" or "throw" for the documents drop.
Property FailDocuments As %String;

/// "", "error" or "throw" for the memories drop.
Property FailMemories As %String;

/// "", "error" or "throw" for the uploads drop.
Property FailUploads As %String;

/// "", "error" or "throw" for the sent files drop.
Property FailSentFiles As %String;

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

Method DropPrecedents(request As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	If '##class(OcuTalon.Data.Precedent).Has(request.SessionRef) Quit 0
	Quit ##super(request)
}

Method DropUploads(sessionRef As %String) As %Status [ Private ]
{
	Set ^OcuTalonTest("SessionOpsUploads", $Increment(^OcuTalonTest("SessionOpsUploads"))) = sessionRef
	If ..FailUploads = "error" Quit $SYSTEM.Status.Error(5001, "zz the uploads drop failed")
	If ..FailUploads = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the uploads drop threw"))
	Quit ##super(sessionRef)
}

Method DropSentFiles(sessionRef As %String) As %Status [ Private ]
{
	Set ^OcuTalonTest("SessionOpsSentFiles", $Increment(^OcuTalonTest("SessionOpsSentFiles"))) = sessionRef
	If ..FailSentFiles = "error" Quit $SYSTEM.Status.Error(5001, "zz the sent files drop failed")
	If ..FailSentFiles = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the sent files drop threw"))
	Quit ##super(sessionRef)
}

}
