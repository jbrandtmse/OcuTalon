Include Ensemble

/// The business operation behind ExampleNotifyOut, ExampleDigestOut and ExampleFallbackOut (FR-5): the three places where the example's
/// router sends a decision. For an OcuTalon.BridgeExample.Msg.Decided it writes one line to the event log (its item name, the outcome,
/// the DecisionRef, the ItemId and, for a fallback, the reason; never model text) and answers OK with no response, as the message in
/// Visual Trace is the record. Any other message class gets "not implemented".
Class OcuTalon.BridgeExample.Outcome Extends Ens.BusinessOperation
{

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	If '$IsObject(pRequest) || 'pRequest.%IsA("OcuTalon.BridgeExample.Msg.Decided") Quit $$$ERROR($$$NotImplemented)
	Set line = ..%ConfigName_": outcome "_pRequest.Outcome_", decision "_pRequest.DecisionRef_", item "_pRequest.ItemId
	If pRequest.Fallback Set line = line_", fallback "_pRequest.FallbackReason
	$$$LOGINFO(line)
	Quit $$$OK
}

}
