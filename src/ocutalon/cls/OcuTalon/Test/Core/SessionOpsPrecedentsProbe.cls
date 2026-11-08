/// A subclass of OcuTalon.Core.SessionOps for Test.Core.SessionOpsPrecedents, which overrides the private seam of End's precedents step, DropPrecedents. Each call is
/// recorded as ^OcuTalonTest("SessionOpsPrecedents", n) = <the SessionRef> (n counted in ^OcuTalonTest("SessionOpsPrecedents")), and then FailDrop decides
/// the answer: "" hands the EndSession to a shadow instance of the real OcuTalon.Core.PrecedentOps, whose request header names SessionOps as the sender (the
/// test has no production, so it stands in for the owner item that Carry would send to), "error" answers a failed drop (1) and "throw" throws. It has no Test
/// methods and the product never refers to it.
Class OcuTalon.Test.Core.SessionOpsPrecedentsProbe Extends OcuTalon.Core.SessionOps
{

/// "", "error" or "throw" for the precedents drop.
Property FailDrop As %String;

Method DropPrecedents(request As OcuTalon.Msg.Command.EndSession) As %Integer [ Private ]
{
	Set ^OcuTalonTest("SessionOpsPrecedents", $Increment(^OcuTalonTest("SessionOpsPrecedents"))) = request.SessionRef
	If ..FailDrop = "error" Quit 1
	If ..FailDrop = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the precedents drop threw"))
	Set owner = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.PrecedentOps", .sc)
	If '$IsObject(owner) Quit 1
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = "SessionOps"
	Set owner.%RequestHeader = header
	Set sc = owner.OnMessage(request, .response)
	Quit $Select($$$ISERR(sc) || '$IsObject(response) || (response.Outcome = "failed"): 1, 1: 0)
}

}
