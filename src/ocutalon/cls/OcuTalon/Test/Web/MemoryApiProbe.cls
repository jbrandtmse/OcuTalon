/// A subclass of OcuTalon.Web.Api for the tests of the memory routes (Stories 41.2 and 41.9), which overrides the private seams SubmitMemory, ReadMemories and NoteText
/// so that a test can reach every answer of the owner without a running production, and records the cause of each 500. The precedent reads (Ownership) are the real
/// ones. It has no Test methods and the product never refers to it.
///   - SubmitMemory records each command under ^OcuTalonTest("MemoryApiProbe", "submitted", n) as "class", "session", "ref" (the DecisionRef, the
///     PrecedentRef or the MemoryRef) and "channel" (a MarkNoise's), and answers from ^OcuTalonTest("MemoryApiProbe", "submit"): "fail" is an error status,
///     "none" is an OK status with no result, "real" sets the origin web_user as Commands.Submit does and has a shadow Test.Core.CommandsStep3Probe answer, so
///     that the real gate and the real MemoryOps answer (a memory verb only), and any other text is the JSON {"ok", "outcome", "message", "data"} of the
///     CommandResult to answer; "timeout" has a shadow Test.Core.CommandsTimeoutProbe answer, so that the real gate gets no answer from its owner in time (the wait it asked for
///     is recorded under ("waited")); a SearchMemory records its Query as "ref";
///   - ReadPinned (Story 41.13) records its session under ("readPinned", "session") and answers from ^OcuTalonTest("MemoryApiProbe", "readPinnedMode"): "fail" is an error status, "record" is OK with no items and used 0 (no read is made), and anything else is the real read
///     (a ListPinnedMemories through SubmitMemory);
///   - ReadMemories records its session and query under ^OcuTalonTest("MemoryApiProbe", "read", "session") and ("query"), and answers from
///     ^OcuTalonTest("MemoryApiProbe", "readMode"): "fail" is an error status, "record" is OK with no items (no read is made), "ownershipFails" runs the real read for an empty SessionRef, which Ownership refuses, and anything else is the real read (the list through
///     Ownership, the search through SubmitMemory);
///   - NoteText records its arguments under ^OcuTalonTest("MemoryApiProbe", "note", "session") and ("date"), throws when ^OcuTalonTest("MemoryApiProbe", "noteText") is
///     "throw", and otherwise answers that text;
///   - HasUserRole (Story 41.9, QA) answers 1, so that a test can run OnPreDispatch past the role check to the AD-13 envelope that follows it (the test process holds
///     no OcuTalon role);
///   - ServerError records the text of the status it is given under ^OcuTalonTest("MemoryApiProbe", "logged") and answers as the route's own.
Class OcuTalon.Test.Web.MemoryApiProbe Extends OcuTalon.Web.Api
{

ClassMethod SubmitMemory(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set n = $Increment(^OcuTalonTest("MemoryApiProbe", "submitted"))
	Set ^OcuTalonTest("MemoryApiProbe", "submitted", n, "class") = $ClassName(command)
	Set ^OcuTalonTest("MemoryApiProbe", "submitted", n, "session") = command.SessionRef
	Set ^OcuTalonTest("MemoryApiProbe", "submitted", n, "ref") = $Case($ClassName(command), "OcuTalon.Msg.Command.MarkNoise": command.DecisionRef, "OcuTalon.Msg.Command.ForgetPrecedent": command.PrecedentRef, "OcuTalon.Msg.Command.SearchMemory": command.Query, "OcuTalon.Msg.Command.ListPinnedMemories": "", : command.MemoryRef)
	Set ^OcuTalonTest("MemoryApiProbe", "submitted", n, "channel") = $Select(command.%IsA("OcuTalon.Msg.Command.MarkNoise"): command.Channel, 1: "")
	Set answer = $Get(^OcuTalonTest("MemoryApiProbe", "submit"))
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz CommandsIn is not running")
	If answer = "none" Quit $SYSTEM.Status.OK()
	If answer = "real" {
		Set command.Origin = "web_user"
		Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsStep3Probe", .sc)
		If '$IsObject(probe) Quit sc
		Quit probe.OnProcessInput(command, .result)
	}
	If answer = "timeout" {
		Set command.Origin = "web_user"
		Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
		If '$IsObject(probe) Quit sc
		Set sc = probe.OnProcessInput(command, .result)
		Set ^OcuTalonTest("MemoryApiProbe", "waited") = probe.SeenTimeout
		Quit sc
	}
	Set spec = {}.%FromJSON(answer)
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = spec.ok
	Set result.Outcome = spec.outcome
	Set result.Message = spec.message
	Set result.Data = spec.data
	Quit $SYSTEM.Status.OK()
}

ClassMethod ReadMemories(sessionRef As %String, query As %String, Output items As %DynamicArray, Output total As %Integer, Output busy As %Boolean, Output refusal As %DynamicObject) As %Status [ Private ]
{
	Set ^OcuTalonTest("MemoryApiProbe", "read", "session") = sessionRef
	Set ^OcuTalonTest("MemoryApiProbe", "read", "query") = query
	Set mode = $Get(^OcuTalonTest("MemoryApiProbe", "readMode"))
	Set items = [], total = 0, busy = 0, refusal = ""
	If mode = "fail" Quit $SYSTEM.Status.Error(5001, "zz the memories could not be read")
	If mode = "record" Quit $SYSTEM.Status.OK()
	If mode = "ownershipFails" Quit ##super("", query, .items, .total, .busy, .refusal)
	Quit ##super(sessionRef, query, .items, .total, .busy, .refusal)
}

ClassMethod ReadPinned(sessionRef As %String, Output items As %DynamicArray, Output used As %Integer, Output busy As %Boolean) As %Status [ Private ]
{
	Set ^OcuTalonTest("MemoryApiProbe", "readPinned", "session") = sessionRef
	Set mode = $Get(^OcuTalonTest("MemoryApiProbe", "readPinnedMode"))
	Set items = [], used = 0, busy = 0
	If mode = "fail" Quit $SYSTEM.Status.Error(5001, "zz the pinned memories could not be read")
	If mode = "record" Quit $SYSTEM.Status.OK()
	Quit ##super(sessionRef, .items, .used, .busy)
}

ClassMethod NoteText(sessionRef As %String, date As %String) As %String [ Private ]
{
	Set ^OcuTalonTest("MemoryApiProbe", "note", "session") = sessionRef
	Set ^OcuTalonTest("MemoryApiProbe", "note", "date") = date
	Set text = $Get(^OcuTalonTest("MemoryApiProbe", "noteText"))
	If text = "throw" Throw ##class(%Exception.General).%New("NoteText", 5001, , "zz the note could not be built")
	Quit text
}

ClassMethod HasUserRole() As %Boolean [ Private ]
{
	Quit 1
}

/// The live role set of OnPreDispatch's re-read: the OcuTalon user role, as HasUserRole says.
ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = ##class(OcuTalon.Web.Public.Shell).#ROLE
	Quit $$$OK
}

ClassMethod ServerError(sc As %Status = {$SYSTEM.Status.OK()}) As %Status [ Private ]
{
	Set ^OcuTalonTest("MemoryApiProbe", "logged") = $SYSTEM.Status.GetErrorText(sc)
	Quit ##super(sc)
}

}
