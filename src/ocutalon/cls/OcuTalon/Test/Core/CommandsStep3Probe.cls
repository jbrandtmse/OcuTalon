/// A subclass of OcuTalon.Core.CommandsIn for Test.Core.CommandsStep3, whose send hands the request to a shadow instance of the REAL owner class
/// of the item that the route names (DocumentOps: OcuTalon.Docs.Ops; MemoryOps: OcuTalon.Memory.Ops) and answers the owner's status as it is, so
/// that the answer is measured on the real classes. A command that MemoryOps has no handler for (a pin) is answered with error 5001, never sent to another handler; a SearchMemory goes to OnSearch. MemoryOps (built in Story 19.3) and DocumentOps (built in Story 19.4) have a message map, which OnMessage does not dispatch, so their handler for the verb is called. It records the request and the item of the last send. It has no Test methods and
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
	If target = "MemoryOps" {
		Set method = $Case($ClassName(request), "OcuTalon.Msg.Command.SaveMemory": "OnSave", "OcuTalon.Msg.Command.ForgetMemory": "OnForget", "OcuTalon.Msg.Command.SearchMemory": "OnSearch", : "")
		If method = "" Quit $SYSTEM.Status.Error(5001, "zz MemoryOps has no handler for "_$ClassName(request))
		Set sc = $Method(owner, method, request, .response)
	} Else {
		Set sc = $Method(owner, $Select(request.%IsA("OcuTalon.Msg.Command.AddDocument"): "OnAdd", 1: "OnRemove"), request, .response)
	}
	Set ..LastResponse = response
	Quit sc
}

}
