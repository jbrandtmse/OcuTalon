/// A subclass of OcuTalon.Test.Mcp.OpsProbe for Test.Core.CommandsStep4 (Story 21.4), which also overrides McpOps' private DropEntry seam: each call is counted in
/// ^||ZzOps("drops") and drops through the real method, and the answer is an error with a recognizable text when ^||ZzOps("dropError") is 1 (after the real drop).
/// Every other seam is the parent's. Shadow gives a shadow instance of this class whose request header names the sender, as the parent's Shadow does for the parent.
/// It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.McpOpsProbe Extends OcuTalon.Test.Mcp.OpsProbe
{

/// A shadow instance of this probe whose request header names the sender.
ClassMethod Shadow(sender As %String, Output sc As %Status) As OcuTalon.Test.Mcp.OpsProbe
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.McpOpsProbe", .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = sender
	Set probe.%RequestHeader = header
	Quit probe
}

ClassMethod DropEntry(server As %String) As %Status [ Private ]
{
	Set ^||ZzOps("drops") = $Get(^||ZzOps("drops")) + 1
	Set sc = ##super(server)
	If $Get(^||ZzOps("dropError")) = 1 Quit $SYSTEM.Status.Error(5001, "zz the drop failed on purpose: zzwallettext")
	Quit sc
}

}
