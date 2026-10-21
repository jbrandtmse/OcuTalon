/// Intake, the business process that takes in an untrusted item and asks for its attention decision (AD-30). A stub until Epic 2: it answers "not implemented".
Class OcuTalon.Core.Intake Extends Ens.BusinessProcess
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
