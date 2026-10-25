/// ApprovalHold, the business process that holds one approval request until it is answered or expires (AD-11). It stores only the
/// request's Ref (AD-5): its two methods each call OcuTalon.Bridge.Approval, where the logic lives. Story 3.4 sends the Workflow task and sets
/// the expiry timer; answering and expiring the request are Story 3.5's.
Class OcuTalon.Bridge.Process.ApprovalHold Extends Ens.BusinessProcess
{

/// The Ref of the ApprovalRequest row that this process holds.
Property Ref As %String(MAXLEN = 22);

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit ##class(OcuTalon.Bridge.Approval).Hold($this, request, .response)
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Quit ##class(OcuTalon.Bridge.Approval).HoldResponse($this, callresponse, pCompletionKey)
}

Storage Default
{
<Data name="ApprovalHoldDefaultData">
<Subscript>"ApprovalHold"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
</Data>
<DefaultData>ApprovalHoldDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
