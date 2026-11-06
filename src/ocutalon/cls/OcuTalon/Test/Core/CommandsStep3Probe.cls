/// A subclass of OcuTalon.Core.CommandsIn for Test.Core.CommandsStep3, whose send hands the request to a shadow instance of the REAL owner class
/// of the item that the route names (DocumentOps: OcuTalon.Docs.Ops; MemoryOps: OcuTalon.Memory.Ops) and answers the owner's status as it is, so
/// that the stub era's answer is measured on the real classes. It records the request and the item of the last send. It has no Test methods and
/// the product never refers to it.
Class OcuTalon.Test.Core.CommandsStep3Probe Extends OcuTalon.Test.Core.CommandsInProbe
{

/// The item name of the last send.
Property SeenTarget As %String;

Method Send(target As %String, request As OcuTalon.Msg.Command, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set response = ""
	Set ..SeenTarget = target
	Set ..LastRequest = request
	Set class = $Case(target, "DocumentOps": "OcuTalon.Docs.Ops", "MemoryOps": "OcuTalon.Memory.Ops", : "")
	If class = "" Quit $SYSTEM.Status.Error(5001, "zz no real owner class for "_target)
	Set owner = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
	If '$IsObject(owner) Quit sc
	Set sc = owner.OnMessage(request, .response)
	Set ..LastResponse = response
	Quit sc
}

}
