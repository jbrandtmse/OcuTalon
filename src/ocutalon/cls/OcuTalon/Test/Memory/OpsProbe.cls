/// A MemoryOps whose statistics step is under test control (test only; Story 19.3). Test.Memory.Ops calls the handlers of a shadow instance of it, in its own
/// process, and Tuned records the id of each row that the handler saved in Tunes (a comma-separated list) instead of gathering statistics. It is not an item
/// of any production.
Class OcuTalon.Test.Memory.OpsProbe Extends OcuTalon.Memory.Ops
{

/// The ids that Tuned was called with, comma-separated, in order.
Property Tunes As %String [ Transient ];

/// Records the id instead of gathering the statistics.
Method Tuned(id As %Integer)
{
	Set ..Tunes = ..Tunes _ $Select(..Tunes '= "": ",", 1: "") _ id
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
