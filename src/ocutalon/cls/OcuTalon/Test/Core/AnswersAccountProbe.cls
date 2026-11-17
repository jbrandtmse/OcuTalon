/// A subclass of OcuTalon.Test.Core.AnswersInProbe for Test.Core.AnswersAccount (DW-1482): the approval API of rule 6 is the real OcuTalon.Bridge.Approval, so that the role check and the account
/// check (Core.Access AccountUsable) both run over real IRIS accounts; the send still goes to the shadow AnswerOps whose approval API is the ApprovalDouble, which records what Approval.Answer would
/// have received. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.AnswersAccountProbe Extends OcuTalon.Test.Core.AnswersInProbe
{

Parameter APPROVALAPI = "OcuTalon.Bridge.Approval";

}
