/// The odd declarations of the gate tests (Story 3.2; AD-10): a test fixture, never part of a production and in no toolset. The gate reads
/// the declarations of a (class, tool) pair from the class dictionary, so the tests ask it about these tools by name
/// (Gate.ClassificationOf, Gate.Check) without a tool manager:
///   - odd_param declares CLASSIFICATION as Safe (not exactly safe), and odd_hook classifies in code with Safe: what code declares is final,
///     so the tool is unclassified and no setting or extension changes that;
///   - odd_empty declares an empty CLASSIFICATION, which counts as no declaration, so the setting is read;
///   - odd_flags is safe and declares READONLY as 1.0 and TRUSTEDOUTPUT as true: a flag is 1 only when it is exactly 1;
///   - odd_res is safe and declares RESOURCES that are not resources;
///   - odd_two_held, odd_two_late and odd_two_first are safe and declare two pairs of RESOURCES: both held by the public (R of %DB_IRISLIB and RW of
///     %DB_IRISTEMP), the second pair missing, and both pairs missing (the first of them is the one the denial names);
///   - odd_risky_res is risky and declares a resource that the service user lacks: the missing privilege is what denies it;
///   - odd_long is safe and declares a step label of 250 characters.
Class OcuTalon.Test.Bridge.ZzGateOdd
{

Parameter CLASSIFICATIONODDPARAM = "Safe";

Parameter CLASSIFICATIONODDEMPTY = "";

Parameter CLASSIFICATIONODDFLAGS = "safe";

Parameter READONLYODDFLAGS = "1.0";

Parameter TRUSTEDOUTPUTODDFLAGS = "true";

Parameter CLASSIFICATIONODDRES = "safe";

Parameter RESOURCESODDRES = "x";

Parameter CLASSIFICATIONODDTWOHELD = "safe";

Parameter RESOURCESODDTWOHELD = "%DB_IRISLIB:R,%DB_IRISTEMP:RW";

Parameter CLASSIFICATIONODDTWOLATE = "safe";

Parameter RESOURCESODDTWOLATE = "%DB_IRISLIB:R,%Admin_Secure:U";

Parameter CLASSIFICATIONODDTWOFIRST = "safe";

Parameter RESOURCESODDTWOFIRST = "%Admin_Secure:U,%DB_IRISLIB:W";

Parameter CLASSIFICATIONODDLONG = "safe";

Parameter STEPLABELODDLONG = {$Translate($Justify("", 250), " ", "x")};

Parameter CLASSIFICATIONODDRISKYRES = "risky";

Parameter RESOURCESODDRISKYRES = "%Admin_Secure:U";

ClassMethod ClassifyODDHOOK(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "Safe"
}

}
