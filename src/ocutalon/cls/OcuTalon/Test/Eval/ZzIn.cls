/// A test double of OcuTalon.Eval.In (Test.Eval.In): Dispatch sends nothing. It records each Item it is given, with the SuperSession of the
/// service and whether the case's row was open at that moment, under ^OcuTalonTest("EvalIn", "seen", n), and answers the error status
/// that ^OcuTalonTest("EvalIn", "fail") holds, or OK when that is empty; it throws an exception with the text that
/// ^OcuTalonTest("EvalIn", "throw") holds when that is not empty.
Class OcuTalon.Test.Eval.ZzIn Extends OcuTalon.Eval.In
{

Method Dispatch(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set open = ''$IsObject(##class(OcuTalon.Eval.Data.CaseResult).Pending(item.ItemId))
	Set ^OcuTalonTest("EvalIn", "seen", $Increment(^OcuTalonTest("EvalIn", "seen"))) = $ListBuild(item.ItemId, item.SourceItemId, item.SessionRef, item.Channel, item.Provenance, item.Sender, item.Subject, item.Text, item.CatalogKey, item.Slots, ..%SuperSession, open)
	Set throw = $Get(^OcuTalonTest("EvalIn", "throw"))
	If throw '= "" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, throw))
	Set fail = $Get(^OcuTalonTest("EvalIn", "fail"))
	Quit $Select(fail '= "": $SYSTEM.Status.Error(5001, fail), 1: $$$OK)
}

}
