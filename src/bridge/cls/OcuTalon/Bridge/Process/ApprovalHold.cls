/// ApprovalHold, the business process that holds one approval request until it is answered or expires (AD-11). A stub
/// until Epic 3: it answers "not implemented".
Class OcuTalon.Bridge.Process.ApprovalHold Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
