/// A MemoryOps whose statistics step and source step are under test control (test only; Story 19.3, Story 41.8). Test.Memory.Ops calls the handlers of a shadow
/// instance of it, in its own process, and Tuned records the id of each row that the handler saved in Tunes (a comma-separated list) instead of gathering
/// statistics. While SourceFails is set, TurnOf answers an error status as if the saving turn could not be read; otherwise it is MemoryOps' own. It is not an
/// item of any production.
Class OcuTalon.Test.Memory.OpsProbe Extends OcuTalon.Memory.Ops
{

/// The ids that Tuned was called with, comma-separated, in order.
Property Tunes As %String [ Transient ];

/// Whether Source fails instead of reading the turn.
Property SourceFails As %Boolean [ Transient ];

/// Text that the error status of an unreadable turn holds besides its own sentence (QA; a made-up value that the redaction must cover).
Property SourceFailText As %String [ Transient ];

/// No turn and the error status of an unreadable turn while SourceFails is set; MemoryOps' own TurnOf otherwise. MemoryOps' own Source runs either way
/// (code review: the probe fails the turn read, not the whole source step).
Method TurnOf(sessionRef As %String, itemId As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	If ..SourceFails {
		Set sc = $SYSTEM.Status.Error(5001, "The turn of the memory could not be read"_$Select(..SourceFailText '= "": ": "_..SourceFailText, 1: ""))
		Quit ""
	}
	Quit ##super(sessionRef, itemId, .sc)
}

/// Records the id instead of gathering the statistics, and returns 0 (nothing was gathered).
Method Tuned(id As %Integer) As %Boolean
{
	Set ..Tunes = ..Tunes _ $Select(..Tunes '= "": ",", 1: "") _ id
	Quit 0
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
