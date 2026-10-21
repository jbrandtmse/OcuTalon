/// The Users step: the README account (AD-23, AD-24). User "ocutalon" is created once, with the published
/// password, holding the three OcuTalon roles, a non-expiring password and no forced change. It is seed (AD-19):
/// created when absent and never changed afterwards, so a password changed as the README says survives every
/// start and upgrade. The step also declares the two roles that hold no resource of their own: the applications
/// grant the database access (AD-13).
Class OcuTalon.Install.Step.Users Extends OcuTalon.Install.Step
{

/// The README account's name.
Parameter USER = "ocutalon";

/// The published password, which the README says how to change.
Parameter PASSWORD = "ocutalon";

/// The roles of the README account. OcuTalonTraceViewer is declared by the Web step.
Parameter ROLES = "OcuTalonUser,OcuTalonAdmin,OcuTalonTraceViewer";

ClassMethod Run() As %Status
{
	Quit ..Ensure(..#USER, ..#PASSWORD, ..#ROLES)
}

/// OcuTalonUser and OcuTalonAdmin hold no resource.
ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"OcuTalonUser","resource":"","permission":""},{"role":"OcuTalonAdmin","resource":"","permission":""}]
}

/// Creates the account when it does not exist, holding the comma list of roles, with PasswordNeverExpires 1,
/// ChangePassword 0, AccountNeverExpires 1 and Enabled 1. An account that exists is left exactly as it is:
/// password, roles and flags. Runs in %SYS.
ClassMethod Ensure(user As %String, password As %String, roles As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Quit $SYSTEM.Status.OK()
	Quit ##class(Security.Users).Create(user, roles, password, "OcuTalon README account", "OCUTALON", "", "", 0, 1, "Created by the OcuTalon installer; the README says how to change the password.", 1, "", "", , 1, 1)
}

}
