/// ExampleItemIn, the adapterless business service through which an item enters the bridge example (FR-5). It sends each item
/// asynchronously to its target, ExampleTriage. A developer sends an item from a terminal with one line:
///   Set sc = ##class(OcuTalon.BridgeExample.ItemIn).Send("Subject", "Body text", "untrusted", .itemId) If $SYSTEM.Status.IsError(sc) Do $SYSTEM.Status.DisplayError(sc)
Class OcuTalon.BridgeExample.ItemIn Extends Ens.BusinessService
{

/// The item that every item is sent to.
Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "ExampleTriage" ];

Parameter SETTINGS = "TargetConfigName:Basic";

/// The name of this service in OcuTalon.BridgeExample.Production.
Parameter SERVICE = "ExampleItemIn";

/// Refuses anything but an Item, and an item that Check refuses. An empty ItemId gets a new Ref (OcuTalon.Bridge.Ids). Then the item is
/// sent to the target and nothing is answered.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject(pInput) || 'pInput.%IsA("OcuTalon.BridgeExample.Msg.Item") Quit $$$ERROR($$$GeneralError, "ExampleItemIn takes an OcuTalon.BridgeExample.Msg.Item and nothing else")
	Set sc = ..Check(pInput)
	If $$$ISERR(sc) Quit sc
	If pInput.ItemId = "" Set pInput.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Quit ..SendRequestAsync(..TargetConfigName, pInput)
}

/// OK when the item has something to decide on; otherwise an error that names Subject and Body: both are empty once white space and
/// control characters are removed.
ClassMethod Check(item As OcuTalon.BridgeExample.Msg.Item) As %Status
{
	If '$IsObject(item) Quit $$$ERROR($$$GeneralError, "There is no item")
	If ($ZStrip(item.Subject, "*WC") = "") && ($ZStrip(item.Body, "*WC") = "") {
		Quit $$$ERROR($$$GeneralError, "The Subject and the Body of the item are both empty, so there is nothing to decide on")
	}
	Quit $$$OK
}

/// Builds an item and sends it through ExampleItemIn of the running example production. itemId is the item's Ref. Nothing is sent, and no
/// header is written, for an item that Check refuses.
ClassMethod Send(subject As %String, body As %String, provenance As %String = "untrusted", Output itemId As %String) As %Status
{
	Set itemId = ""
	Set item = ##class(OcuTalon.BridgeExample.Msg.Item).%New()
	Set item.Subject = $Get(subject)
	Set item.Body = $Get(body)
	Set item.Provenance = $Select($Get(provenance) = "": "untrusted", 1: provenance)
	Set sc = ..Check(item)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SERVICE, .service)
	If $$$ISERR(sc) Quit sc
	Set sc = service.ProcessInput(item)
	Set itemId = item.ItemId
	Quit sc
}

}
