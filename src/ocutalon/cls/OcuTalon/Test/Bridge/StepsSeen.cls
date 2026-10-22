/// A test-only audit policy (Story 1.5; AD-6): a fixture, never part of a production. Test.Bridge.Runner chains it after the step audit
/// policy to see what the tools were called with. It records, for every tool call, $ListBuild(the tool's name, the call's arguments as AI
/// Hub gave them: a JSON string) in the process-private global ^||ZzStepsSeen(n), with the count at ^||ZzStepsSeen. It returns OK always
/// and catches every exception. It makes no call into AI Hub beyond the base class and runs no Python (AD-6); only the Class line names
/// the AI Hub package.
Class OcuTalon.Test.Bridge.StepsSeen Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
	Try {
		Set n = $Increment(^||ZzStepsSeen)
		Set ^||ZzStepsSeen(n) = $ListBuild(call.%Get("name"), call.%Get("arguments"))
	} Catch {
	}
	Quit $$$OK
}

}
