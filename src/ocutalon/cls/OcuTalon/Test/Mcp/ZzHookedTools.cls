/// Two tools that are safe and read-only by their class parameters but that classify or hold by their arguments (Story 28.3, R-28.3-1): zz_hooked has the classification hook
/// ClassifyZZHOOKED and zz_held has the hold hook HoldZZHELD, named as the gate's HookFor reads them. Test.Mcp.ServiceReadOnly proves that Service ToolProblem refuses each of them.
/// Nothing offers them as tools. It is no test case.
Class OcuTalon.Test.Mcp.ZzHookedTools Extends %RegisteredObject
{

Parameter CLASSIFICATIONZZHOOKED = "safe";

Parameter READONLYZZHOOKED = 1;

Parameter CLASSIFICATIONZZHELD = "safe";

Parameter READONLYZZHELD = 1;

ClassMethod ClassifyZZHOOKED(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

ClassMethod HoldZZHELD(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit ""
}

}
