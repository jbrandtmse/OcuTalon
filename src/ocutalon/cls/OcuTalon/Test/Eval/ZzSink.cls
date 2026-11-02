/// A test double of OcuTalon.Eval.Sink (Test.Eval.Sink, Story 9.1): the size read throws the exception that
/// ^OcuTalonTest("EvalSink", "throw") holds as its text when that is not empty, and is EvalSink's own read otherwise. It lets a test
/// show that OnMessage never throws: a failure inside the row's completion is logged and the call answers OK.
Class OcuTalon.Test.Eval.ZzSink Extends OcuTalon.Eval.Sink
{

Method Largest(decisionRef As %String, turnRef As %String) As %Integer [ Private ]
{
	Set throw = $Get(^OcuTalonTest("EvalSink", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Quit ##super(decisionRef, turnRef)
}

}
