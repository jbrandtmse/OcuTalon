/// A tool class for the security overview tests (Story 14.1): a test fixture, never part of a production and in no toolset. It classifies by
/// code, so the overview shows the text of a rule instead of a classification:
///   - the tool plain has no hook of its own, so the class-wide Classify decides it and the rule is CLASSIFYRULE;
///   - the tool own has its own hook, ClassifyOWN, and its own rule, CLASSIFYRULEOWN, which outranks CLASSIFYRULE.
Class OcuTalon.Test.Install.ZzOverviewRule
{

Parameter CLASSIFYRULE = "risky when the request names a production | else safe";

Parameter CLASSIFYRULEOWN = "safe unless the text holds a delete";

ClassMethod Classify(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

ClassMethod ClassifyOWN(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

}
