/// A subclass of OcuTalon.Memory.Ops for Test.Memory.Pins: its Lock cannot take the session's lock while ^||PinsProbe("busy") is set, and otherwise takes it as MemoryOps does; its
/// Answer throws for the one outcome that ^||PinsProbe("throw") names (so the handlers' Catch is reached before any write, when the outcome is over_cap or not_found), and otherwise builds the answer as MemoryOps does. It has no
/// Test methods and the product never refers to it.
Class OcuTalon.Test.Memory.PinsProbe Extends OcuTalon.Memory.Ops
{

/// 0 while ^||PinsProbe("busy") is set, else MemoryOps' own Lock.
ClassMethod Lock(sessionRef As %String) As %Boolean [ Private ]
{
	If $Get(^||PinsProbe("busy")) Quit 0
	Quit ##super(sessionRef)
}

/// An exception for the outcome that ^||PinsProbe("throw") names (the handlers answer from inside their Try, so this reaches their Catch), else MemoryOps' own Answer.
ClassMethod Answer(ByRef response As OcuTalon.Msg.CommandResult, ok As %Boolean, outcome As %String, message As %String, ref As %String = "") As %Status [ Private ]
{
	If ($Get(^||PinsProbe("throw")) '= "") && ($Get(^||PinsProbe("throw")) = outcome) Throw ##class(%Exception.General).%New("PinsProbe", 5001, , "zz the answer failed, password=zzsecretvalue")
	Quit ##super(.response, ok, outcome, message, ref)
}

}
