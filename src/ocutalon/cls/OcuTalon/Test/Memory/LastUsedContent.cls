/// The content class of OcuTalon with a MemoryIn that does not exist, for the tests of Story 28.2 (QA): OcuTalon.Agent.Content whose Used send names a business service that the production
/// does not hold, so that a test sees what Accepted does when the send cannot be made. Nothing else differs.
Class OcuTalon.Test.Memory.LastUsedContent Extends OcuTalon.Agent.Content
{

Parameter MEMORYIN = "ZzNoSuchMemoryIn";

}
