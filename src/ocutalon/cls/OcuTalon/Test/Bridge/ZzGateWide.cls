/// The class-wide hook of the gate tests (Story 3.2; AD-10): a test fixture, never part of a production and in no toolset. The gate tries the
/// code Classify methods of a class (Classify<NAME>, else Classify) before any CLASSIFICATION parameter, so the class-wide hook of this class,
/// which says risky, decides every tool of it that has no hook of its own:
///   - wide_plain declares nothing, so the class-wide hook says risky;
///   - wide_param declares CLASSIFICATIONWIDEPARAM as safe, which the hook outranks, so the tool stays risky;
///   - wide_own has its own hook (ClassifyWIDEOWN), which says safe and outranks the class-wide one.
Class OcuTalon.Test.Bridge.ZzGateWide
{

Parameter CLASSIFICATIONWIDEPARAM = "safe";

ClassMethod Classify(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "risky"
}

ClassMethod ClassifyWIDEOWN(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

}
