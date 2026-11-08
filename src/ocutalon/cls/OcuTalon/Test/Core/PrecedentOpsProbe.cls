/// A subclass of OcuTalon.Core.PrecedentOps for Test.Core.PrecedentOps, which overrides its private seams: ItemOf answers the Item held in Item (or calls the real
/// method when RealItemOf is 1) and counts its calls in Asked, and SaveRow answers as FailSave says: "" calls the real method (##super), "error" answers an error
/// status with no row, and "raced" saves the row and then answers an error status, as when another press won the unique SourceRef between the check and the
/// save. OnlineDemo answers the property DemoFlag: "" calls the real method, 0 or 1 is the answer. The sender is the SourceConfigName of the header that the test gives it. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.PrecedentOpsProbe Extends OcuTalon.Core.PrecedentOps
{

/// The Item that ItemOf answers.
Property Item As OcuTalon.Msg.Item;

/// 1 when ItemOf calls the real method.
Property RealItemOf As %Boolean [ InitialExpression = 0 ];

/// The number of ItemOf calls.
Property Asked As %Integer [ InitialExpression = 0 ];

/// "", "error" or "raced" for the row save.
Property FailSave As %String;

/// "" (the real OnlineDemo), 0 or 1.
Property DemoFlag As %String;

Method ItemOf(decision As OcuTalon.Bridge.Data.Decision) As OcuTalon.Msg.Item [ Private ]
{
	Set ..Asked = ..Asked + 1
	If ..RealItemOf Quit ##super(decision)
	Quit ..Item
}

Method SaveRow(row As OcuTalon.Data.Precedent) As %Status [ Private ]
{
	If ..FailSave = "error" Quit $SYSTEM.Status.Error(5001, "zz the precedent save failed")
	Set sc = ##super(row)
	If ..FailSave = "raced" Quit $SYSTEM.Status.Error(5001, "zz the precedent save raced")
	Quit sc
}

Method OnlineDemo() As %Boolean [ Private ]
{
	If ..DemoFlag = "" Quit ##super()
	Quit (..DemoFlag = 1)
}

}
