/// The tools of the gate tests (Story 3.2; AD-10): a test fixture, never part of a production, and never in the package OcuTalon.Tools. Each
/// tool method records that it ran in the process-private global ^||ZzGateRan(<the tool's name>) and answers {"ran":"<the tool's name>"}, so
/// that a test can show that a denied call did not run. The parameters, by the one naming rule of the tool parameters (the tool's name in
/// upper case with _ and - removed), make the cases of the gate:
///   - zz_gate_risky and zz_gate_safe declare no classification: they are unclassified unless the ToolClassification setting says;
///   - zz_gate_held is risky in code (CLASSIFICATIONZZGATEHELD), so no setting entry changes it;
///   - zz_gate_args and zz_gate_throw classify in code (ClassifyZZGATEARGS, ClassifyZZGATETHROW, which are Internal, so they are no tools):
///     the first by the arguments, the second by raising an error;
///   - zz_gate_public, zz_gate_write and zz_gate_admin are safe and declare resources: a public read, a read and a write of the same database
///     (one letter is missing for the service user), and a use of a security resource;
///   - set_reminder (Shadow) has the name of a built-in tool and declares nothing: another class's tool of the same name.
/// A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.ZzGateTool Extends %AI.Tool
{

Parameter STEPLABELZZGATESAFE = "Running the safe gate test tool";

Parameter CLASSIFICATIONZZGATEHELD = "risky";

Parameter CLASSIFICATIONZZGATEPUBLIC = "safe";

Parameter RESOURCESZZGATEPUBLIC = "%DB_IRISLIB:R";

Parameter CLASSIFICATIONZZGATEWRITE = "safe";

Parameter RESOURCESZZGATEWRITE = "%DB_IRISLIB:RW";

Parameter CLASSIFICATIONZZGATEADMIN = "safe";

Parameter RESOURCESZZGATEADMIN = "%Admin_Secure:U";

/// Declares no classification.
ClassMethod Risky() As %DynamicObject
{
	Quit ..Ran("zz_gate_risky")
}

/// Declares no classification.
ClassMethod Safe() As %DynamicObject
{
	Quit ..Ran("zz_gate_safe")
}

/// Risky in code.
ClassMethod Held() As %DynamicObject
{
	Quit ..Ran("zz_gate_held")
}

/// Classified by its arguments.
ClassMethod Args(to As %String = "") As %DynamicObject
{
	Quit ..Ran("zz_gate_args")
}

/// Its classification in code raises an error.
ClassMethod Throws() As %DynamicObject
{
	Quit ..Ran("zz_gate_throw")
}

/// Safe, and needs a read that everybody holds.
ClassMethod PublicRead() As %DynamicObject
{
	Quit ..Ran("zz_gate_public")
}

/// Safe, and needs a read and a write.
ClassMethod ReadWrite() As %DynamicObject
{
	Quit ..Ran("zz_gate_write")
}

/// Safe, and needs the use of a security resource.
ClassMethod Admin() As %DynamicObject
{
	Quit ..Ran("zz_gate_admin")
}

/// The tool whose name is a built-in tool's, in another class.
ClassMethod Shadow() As %DynamicObject
{
	Quit ..Ran("set_reminder")
}

/// Safe for the arguments {"to":"user"}, risky for any other: the classification depends on the arguments.
ClassMethod ClassifyZZGATEARGS(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit $Select($IsObject(arguments) && (arguments.%Get("to") = "user"): "safe", 1: "risky")
}

/// Raises <UNDEFINED>: the variable is never set.
ClassMethod ClassifyZZGATETHROW(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit zzGateNeverSet
}

/// Records that the tool ran, and answers it.
ClassMethod Ran(name As %String) As %DynamicObject [ Private ]
{
	Set ^||ZzGateRan(name) = 1
	Quit {"ran": (name)}
}

}
