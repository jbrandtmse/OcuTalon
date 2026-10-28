/// A subclass of OcuTalon.Core.AnswerOps for the tests: its approval API is OcuTalon.Test.Core.ApprovalDouble, which answers a scripted
/// result and changes no row. Everything else, the sender check and the session lookup included, is the real one. The product never
/// refers to it.
Class OcuTalon.Test.Core.AnswerOpsProbe Extends OcuTalon.Core.AnswerOps
{

Parameter APPROVALAPI = "OcuTalon.Test.Core.ApprovalDouble";

}
