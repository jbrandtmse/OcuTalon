/// The tools of the grant tests (Story 3.1; Consistency Conventions: Tool resources): a test fixture, never part of a production. The three
/// methods answer an empty object. Their resources, by the one naming rule: alpha declares its own, RESOURCESALPHA; beta has none of its own
/// and takes the class's RESOURCES; gamma declares an empty RESOURCESGAMMA, which wins over the class's. Gamma's STEPLABELGAMMA is empty
/// too, which does not win over the class's STEPLABEL. The resource ZzOcuTalonGrantProbe is made by the tests
/// (OcuTalon.Test.Install.Registry). A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Install.ZzGrantTools Extends OcuTalon.Tools.Result
{

Parameter STEPLABEL = "Probing the grants";

Parameter STEPLABELGAMMA = "";

Parameter RESOURCESALPHA = "ZzOcuTalonGrantProbe:U";

Parameter RESOURCES = "ZzOcuTalonGrantProbe:R";

Parameter RESOURCESGAMMA = "";

/// The tool with its own resources.
ClassMethod Alpha() As %DynamicObject
{
	Quit ..Return({})
}

/// The tool that takes the resources of the class.
ClassMethod Beta() As %DynamicObject
{
	Quit ..Return({})
}

/// The tool that declares no resources.
ClassMethod Gamma() As %DynamicObject
{
	Quit ..Return({})
}

}
