/// A tool class for the security overview tests (Story 14.1): a test fixture, never part of a production and in no toolset. It classifies by
/// code, so the overview shows the text of a rule instead of a classification:
///   - the tool plain has no hook of its own, so the class-wide Classify decides it and the rule is CLASSIFYRULE;
///   - the tool own has its own hook, ClassifyOWN, and its own rule, CLASSIFYRULEOWN, which outranks CLASSIFYRULE.
/// It also declares RESOURCES, so that the Resources column of a tool row has a value to show (QA of Story 14.1; no shipped tool has one):
///   - own has RESOURCESOWN, two resource:permission pairs, which outrank RESOURCES;
///   - plain has no value of its own, so the class-wide RESOURCES is its value;
///   - quiet has an empty RESOURCESQUIET, which outranks the class-wide value, so its cell reads none;
///   - bad has a RESOURCESBAD that is not resource:permission, so a row for it cannot be made.
Class OcuTalon.Test.Install.ZzOverviewRule
{

Parameter CLASSIFYRULE = "risky when the request names a production | else safe";

Parameter CLASSIFYRULEOWN = "safe unless the text holds a delete";

Parameter STEPLABEL = "Probing the overview";

Parameter RESOURCES = "ZzOverviewProbe:W";

Parameter RESOURCESOWN = "ZzOverviewProbe:R,%Ens_Portal:U";

Parameter RESOURCESQUIET;

Parameter RESOURCESBAD = "nocolon";

ClassMethod Classify(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

ClassMethod ClassifyOWN(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit "safe"
}

}
