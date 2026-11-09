/// A subclass of OcuTalon.Core.CommandsIn for the tests of a send that gets no answer in time (Story 41.9). It overrides the framework's synchronous send, which the
/// product's Send and SendSearch call, and does what the framework does when the wait ends with no answer from the owner: it answers an OK status and no response. It
/// records the target, the request and the wait (seconds) that the product asked for under Seen... and sends nothing to any owner. It has no Test methods and the
/// product never refers to it.
Class OcuTalon.Test.Core.CommandsTimeoutProbe Extends OcuTalon.Core.CommandsIn
{

/// The target of the last send.
Property SeenTarget As %String;

/// The request of the last send.
Property SeenRequest As %Library.Persistent;

/// The wait (seconds) that the last send asked for.
Property SeenTimeout As %Numeric;

/// How many sends were made.
Property Sends As %Integer [ InitialExpression = 0 ];

Method SendRequestSync(pTargetDispatchName As %String, pRequest As %Library.Persistent, ByRef pResponse As %Library.Persistent, pTimeout As %Numeric = -1, pDescription As %String = "", ByRef pSendSyncHandling As %String) As %Status
{
	Set ..Sends = ..Sends + 1
	Set ..SeenTarget = pTargetDispatchName
	Set ..SeenRequest = pRequest
	Set ..SeenTimeout = pTimeout
	Set pResponse = ""
	Quit $SYSTEM.Status.OK()
}

}
