/// The Users step with two values pinned for tests (Story 3.1): a test fixture, never an installer area (it is outside OcuTalon.Install.Step,
/// so the registry does not discover it).
///   - Its list of namespaces for the Visual Trace page size pin names first a namespace that does not exist and leaves OCUORDERS out, so a
///     test can tell a pin that skips a missing namespace from one that pins every namespace of the list.
///   - Its NewPassword is a known value, so a test can tell that EnsureService gives the service user the password that NewPassword makes.
Class OcuTalon.Test.Install.ZzUsersPins Extends OcuTalon.Install.Step.Users
{

Parameter TRACENAMESPACES = "ZZNOSUCHNAMESPACE,OCUTALON";

ClassMethod NewPassword() As %String
{
	Quit "Zz-known-service-pw-1"
}

}
