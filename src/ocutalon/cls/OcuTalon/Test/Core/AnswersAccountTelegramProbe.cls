/// A subclass of OcuTalon.Core.AnswersIn for the tests of DW-1482 which overrides its private class-method seam Deliver: the answer goes to the OnProcessInput of a shadow instance of
/// OcuTalon.Test.Core.AnswersAccountProbe (the real role and account checks, the ApprovalDouble behind AnswerOps), so that no production is needed. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.AnswersAccountTelegramProbe Extends OcuTalon.Core.AnswersIn
{

ClassMethod Deliver(answer As OcuTalon.Core.Msg.Answer, Output result As OcuTalon.Core.Msg.AnswerResult, Output refusal As %DynamicObject) As %Status [ Private ]
{
	Set result = ""
	Set refusal = {}
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswersAccountProbe", .sc)
	If '$IsObject(service) Quit sc
	Set sc = service.OnProcessInput(answer, .result)
	Set refusal = $Select($IsObject(service.Refusal): service.Refusal, 1: {})
	Quit sc
}

}
