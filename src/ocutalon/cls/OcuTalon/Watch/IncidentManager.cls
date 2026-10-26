/// IncidentManager, the business process that settles failures into incidents and moves each incident through its states (AD-15). Built in parts
/// during Epic 5; a stub until it is whole.
///   - A FailureBatch (OcuTalon.Watch.Msg.FailureBatch, from FailurePoller) is accepted: the request completes with no response and nothing is written.
///     Story 5.3 groups the failures of a batch into incidents and ignores a failure it already holds, known by its key (OcuTalon.Watch.Mark.Key):
///     the header id of a header failure, the log id of an event-log row with no session, whose HeaderId is empty.
///   - Anything else is still answered "not implemented" (the stub's answer), so the commands and the approval outcomes that Story 5.3 and 5.5
///     build are not accepted by mistake.
Class OcuTalon.Watch.IncidentManager Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If $IsObject(request) && request.%IsA("OcuTalon.Watch.Msg.FailureBatch") Quit $$$OK
	Quit $$$ERROR($$$NotImplemented)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
