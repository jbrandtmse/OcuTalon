/// A stub standing in for Checks (Story 8.1; AD-29): it carries STUB and answers "not implemented", as Lane A's OcuTalon.Checks.Process does until
/// Story 5.6. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): Test.Schedule.Heartbeat TestStubSkipped puts it behind the Checks
/// item when the class that the item had no longer carries STUB, so that the test keeps pinning ruling U-52 once Checks is built. Nothing else loads it.
Class OcuTalon.Test.Schedule.ChecksStub Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet, as the stub of Lane A does.
Parameter STUB = 1;

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
