/// A subclass of OcuTalon.Core.AnswersIn for the tests of the Telegram entry, which overrides its private class-method seam Deliver: the
/// answer goes to the OnProcessInput of a shadow instance of OcuTalon.Test.Core.AnswersInProbe, whose AnswerOps stand-in calls the
/// ApprovalDouble, so that no production is needed. Every call of Deliver is counted in ^OcuTalonTest("AnswersTelegramProbe", "delivers"),
/// and when ^OcuTalonTest("AnswersTelegramProbe", "fail") is 1 it answers an error status and hands nothing over. The product never refers
/// to it.
Class OcuTalon.Test.Core.AnswersTelegramProbe Extends OcuTalon.Core.AnswersIn
{

ClassMethod Deliver(answer As OcuTalon.Core.Msg.Answer, Output result As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set result = ""
	Set ^OcuTalonTest("AnswersTelegramProbe", "delivers") = $Get(^OcuTalonTest("AnswersTelegramProbe", "delivers")) + 1
	If $Get(^OcuTalonTest("AnswersTelegramProbe", "fail")) Quit $SYSTEM.Status.Error(5001, "zz deliver failed")
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswersInProbe", .sc)
	If '$IsObject(service) Quit sc
	Quit service.OnProcessInput(answer, .result)
}

}
