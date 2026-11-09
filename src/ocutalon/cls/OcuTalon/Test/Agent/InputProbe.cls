/// A subclass of OcuTalon.Agent.Input for the tests of the notes block (Story 41.4; AD-7): it overrides the private NoteOf to throw for the one day
/// that ^||InputProbe("failDay") names, and otherwise gives the note that Agent.Input gives. It adds nothing else and the product never refers to it.
Class OcuTalon.Test.Agent.InputProbe Extends OcuTalon.Agent.Input
{

/// The note of the session for the day: an exception while ^||InputProbe("failDay") is the day, else Agent.Input's own read.
ClassMethod NoteOf(sessionRef As %String, day As %String) As %String [ Private ]
{
	If $Get(^||InputProbe("failDay")) = day Throw ##class(%Exception.General).%New("InputProbe", 5001, , "zz the read of the note of "_day_" failed, password=zzsecretvalue")
	Quit ##super(sessionRef, day)
}

}
