/// MemoryIn (AD-1, AD-4, AD-26, Story 28.2; Lane A): the adapterless business service through which a job tells MemoryOps which memories a reply used. Agent.Content makes
/// it with Ens.Director.CreateBusinessService in the job of Decide and calls ProcessInput with one OcuTalon.Memory.Msg.Used. The Used is sent to MemoryOps asynchronously, in a
/// trace session of its own whose SuperSession is the TraceRef of the owner's Session row (none when the owner has no Session row), so that Visual Trace shows it with the
/// owner's other messages; the caller does not wait. Anything other than a Used is refused with an error status and sent nowhere. Like HeartbeatIn, it carries internal
/// messages that are not command verbs and that no tool, route or channel can send.
Class OcuTalon.Memory.In Extends Ens.BusinessService
{

/// The item that takes every Used.
Parameter TARGET = "MemoryOps";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject(pInput) || 'pInput.%IsA("OcuTalon.Memory.Msg.Used") Quit $SYSTEM.Status.Error(5001, "MemoryIn takes an OcuTalon.Memory.Msg.Used")
	Set ..%SessionId = ""
	Set ..%SuperSession = ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(pInput.SessionRef)
	If $IsObject(session) Set ..%SuperSession = session.TraceRef
	Quit ..SendRequestAsync(..#TARGET, pInput)
}

}
