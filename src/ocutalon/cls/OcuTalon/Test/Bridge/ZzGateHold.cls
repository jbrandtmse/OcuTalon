/// The hold hooks of the gate tests (Story 22.7; AD-10): a test fixture, never part of a production and in no toolset. The gate holds a risky call of a class that declares
/// Hold<NAME> by that method and not by a tool_call request. Every tool of this class is risky in code, and each hook records its call in the process-private global
/// ^||ZzGateHold(n) as $ListBuild(the tool's name, the arguments as JSON, ownerRef, traceRef, sinkClass), n counting in ^||ZzGateHold:
///   - zz_hold_raise sets ref (it raises nothing itself), zz_hold_refuse sets refusal, zz_hold_both sets both (a refusal outranks a ref), zz_hold_neither sets neither;
///   - zz_hold_error returns an error status and zz_hold_throw raises <UNDEFINED>;
///   - zz_hold_plain has no hold hook of its own: only the class-wide Hold, which the gate never calls because a hold hook has no class-wide form, so its call is held as a tool_call
///     request;
///   - zz_hold_safe is safe in code and has a hold hook, which the gate never calls for a call that it allows.
Class OcuTalon.Test.Bridge.ZzGateHold
{

/// The sentence of zz_hold_refuse.
Parameter REFUSAL = "The zz hook refused this call.";

/// The Ref of zz_hold_raise.
Parameter REF = "zzHoldHookRef00000001";

ClassMethod ClassifyZZHOLDRAISE(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDREFUSE(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDBOTH(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDNEITHER(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDERROR(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDTHROW(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDPLAIN(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyZZHOLDSAFE(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

ClassMethod HoldZZHOLDRAISE(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_raise", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ..#REF
	Set refusal = ""
	Quit $$$OK
}

ClassMethod HoldZZHOLDREFUSE(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_refuse", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ""
	Set refusal = ..#REFUSAL
	Quit $$$OK
}

ClassMethod HoldZZHOLDBOTH(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_both", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ..#REF
	Set refusal = ..#REFUSAL
	Quit $$$OK
}

ClassMethod HoldZZHOLDNEITHER(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_neither", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ""
	Set refusal = ""
	Quit $$$OK
}

ClassMethod HoldZZHOLDERROR(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_error", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ..#REF
	Set refusal = ""
	Quit $SYSTEM.Status.Error(5001, "The zz hook failed")
}

ClassMethod HoldZZHOLDTHROW(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_throw", arguments, ownerRef, traceRef, sinkClass)
	Quit zzHoldNeverSet
}

ClassMethod HoldZZHOLDSAFE(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("zz_hold_safe", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ..#REF
	Quit $$$OK
}

/// The class-wide form, which the gate must never call.
ClassMethod Hold(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Do ..Record("class-wide", arguments, ownerRef, traceRef, sinkClass)
	Set ref = ..#REF
	Quit $$$OK
}

ClassMethod Record(name As %String, arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String) [ Private ]
{
	Set n = $Increment(^||ZzGateHold)
	Set ^||ZzGateHold(n) = $ListBuild(name, arguments.%ToJSON(), ownerRef, traceRef, sinkClass)
}

}
