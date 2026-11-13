/// A test helper of Test.Tools.Memory (Story 41.15, QA): a subclass of OcuTalon.Tools.MemoryTools that reaches the private Announce, so that a read of the saved row that
/// fails can be tested without a session the context would not accept. It holds no tool of its own and nothing runs it but that test.
Class OcuTalon.Test.Tools.MemoryAnnouncer Extends OcuTalon.Tools.MemoryTools
{

/// Announce(memoryRef, sessionRef) of MemoryTools, public here.
ClassMethod Run(memoryRef As %String, sessionRef As %String)
{
	Do ..Announce(memoryRef, sessionRef)
}

}
