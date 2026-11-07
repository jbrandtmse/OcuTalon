/// A Checks process (Test.Checks.Probe, so that a Tick runs over fixture rows only) whose send of the Tick to Digest is under test control (test only; Story 17.6).
/// SendRequestAsync to the DIGEST item records the request's class in ^||TickProbe("digest", n) and answers OK, an error status when FailDigest is 1, or throws
/// when FailDigest is 2; a send to any other item is the framework's. It is not an item of any production.
Class OcuTalon.Test.Digest.TickProbe Extends OcuTalon.Test.Checks.Probe
{

/// 0 for a send that works, 1 for one that answers an error status, 2 for one that throws.
Property FailDigest As %Integer [ InitialExpression = 0, Transient ];

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As Ens.Request, pResponseRequired As %Boolean = 1, pCompletionKey As %String = "", pDescription As %String = "") As %Status
{
	If pTargetDispatchName '= ..#DIGEST Quit ##super(pTargetDispatchName, pRequest, pResponseRequired, pCompletionKey, pDescription)
	Set n = $Increment(^||TickProbe("digest"))
	Set ^||TickProbe("digest", n) = $ListBuild($ClassName(pRequest), pResponseRequired)
	If ..FailDigest = 2 Throw ##class(%Exception.General).%New("zz the Digest item threw", 5001, , "zz the Digest item threw")
	If ..FailDigest = 1 Quit $SYSTEM.Status.Error(5001, "zz the Digest item could not be reached")
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
