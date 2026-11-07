/// The tools of the read-only rule's tests (Story 17.2; AD-8, AD-10, lead ruling R2): a test fixture, never part of a production, and never in the package
/// OcuTalon.Tools. Each tool reads nothing and answers {"tool":"<its name>"}. The parameters, by the one naming rule of the tool parameters (the tool's name
/// in upper case with _ and - removed), make one case of Decide.ToolsetsReadOnly each:
///   - zz_ro_look is safe and read-only, with no Classify method: a read-only tool;
///   - zz_ro_risky is risky and read-only: not read-only, because it is not safe;
///   - zz_ro_hooked is safe and read-only and has a Classify method that decides per call (ClassifyZZROHOOKED, Internal, so it is no tool): not read-only.
/// Each tool is in a toolset of its own: ZzReadOnlySafe, ZzReadOnlyRisky and ZzReadOnlyHooked.
Class OcuTalon.Test.Bridge.ZzReadOnlyTool Extends %AI.Tool
{

Parameter CLASSIFICATIONZZROLOOK = "safe";

Parameter READONLYZZROLOOK = 1;

Parameter CLASSIFICATIONZZRORISKY = "risky";

Parameter READONLYZZRORISKY = 1;

Parameter CLASSIFICATIONZZROHOOKED = "safe";

Parameter READONLYZZROHOOKED = 1;

/// Safe and read-only.
ClassMethod Look() As %DynamicObject
{
	Quit {"tool": "zz_ro_look"}
}

/// Risky and read-only.
ClassMethod RiskyLook() As %DynamicObject
{
	Quit {"tool": "zz_ro_risky"}
}

/// Safe and read-only, with a per-call classification.
ClassMethod HookedLook() As %DynamicObject
{
	Quit {"tool": "zz_ro_hooked"}
}

/// The per-call classification of zz_ro_hooked: always safe. Its existence is what the rule judges.
ClassMethod ClassifyZZROHOOKED(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

}
