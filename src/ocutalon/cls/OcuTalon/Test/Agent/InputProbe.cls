/// A subclass of OcuTalon.Agent.Input for the tests of the notes block (Story 41.4; AD-7) and the core-memory block (Story 41.12): it overrides the private NoteOf to throw for the one day
/// that ^||InputProbe("failDay") names, and the private CoreOf to throw while ^||InputProbe("failCore") is set (with "status", through Agent.Input's own CoreOf, from an error status); otherwise each gives what Agent.Input gives. It adds nothing else and the product never refers to it.
Class OcuTalon.Test.Agent.InputProbe Extends OcuTalon.Agent.Input
{

/// The note of the session for the day: an exception while ^||InputProbe("failDay") is the day, else Agent.Input's own read.
ClassMethod NoteOf(sessionRef As %String, day As %String, itemId As %String = "") As %String [ Private ]
{
	If $Get(^||InputProbe("failDay")) = day Throw ##class(%Exception.General).%New("InputProbe", 5001, , "zz the read of the note of "_day_" failed, password=zzsecretvalue")
	Quit ##super(sessionRef, day, itemId)
}

/// The core-memory block of the session: while ^||InputProbe("failCore") is "status", Agent.Input's own read for an empty session (Memory.CoreBlock answers an error status);
/// while it is otherwise set, an exception; else Agent.Input's own read.
ClassMethod CoreOf(sessionRef As %String) As %String [ Private ]
{
	If $Get(^||InputProbe("failCore")) = "status" Quit ##super("")
	If $Get(^||InputProbe("failCore")) Throw ##class(%Exception.General).%New("InputProbe", 5001, , "zz the read of the core memory failed, password=zzsecretvalue")
	Quit ##super(sessionRef)
}

}
