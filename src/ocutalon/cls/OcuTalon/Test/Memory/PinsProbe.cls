/// A subclass of OcuTalon.Memory.Ops for Test.Memory.Pins: its Lock cannot take the session's lock while ^||PinsProbe("busy") is set, and otherwise takes it as MemoryOps does. It has no
/// Test methods and the product never refers to it.
Class OcuTalon.Test.Memory.PinsProbe Extends OcuTalon.Memory.Ops
{

/// 0 while ^||PinsProbe("busy") is set, else MemoryOps' own Lock.
ClassMethod Lock(sessionRef As %String) As %Boolean [ Private ]
{
	If $Get(^||PinsProbe("busy")) Quit 0
	Quit ##super(sessionRef)
}

}
