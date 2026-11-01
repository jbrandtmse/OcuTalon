/// A test double of OcuTalon.Eval.Gate (Test.Eval.Gate; test only): RunOnce, the gate's one run of the demo case, sends nothing and starts no production.
///   - It counts its calls in ^OcuTalonTest("EvalGate", "calls").
///   - For its nth call it answers the error status whose text ^OcuTalonTest("EvalGate", "fail", n) holds, throws an exception with the text of
///     ^OcuTalonTest("EvalGate", "throw", n), or else answers OK with the report that ^OcuTalonTest("EvalGate", n) holds as JSON (no report when
///     that is empty).
Class OcuTalon.Test.Eval.ZzGate Extends OcuTalon.Eval.Gate
{

ClassMethod RunOnce(folder As %String, seconds As %Integer, Output report As %DynamicObject) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("EvalGate", "calls"))
	Set report = ""
	If $Data(^OcuTalonTest("EvalGate", "fail", n)) Quit $SYSTEM.Status.Error(5001, ^OcuTalonTest("EvalGate", "fail", n))
	If $Data(^OcuTalonTest("EvalGate", "throw", n)) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, ^OcuTalonTest("EvalGate", "throw", n)))
	Set json = $Get(^OcuTalonTest("EvalGate", n))
	If json '= "" Set report = ##class(%DynamicAbstractObject).%FromJSON(json)
	Quit $$$OK
}

}
