/// The second early step of the package's first install run (AD-23, FR-57): it makes IPM available in namespace OCUTALON and,
/// outside OCUTALON, stops the run with the next command. The manifest invokes MapAndStop at Initialize, after the CPF
/// resource has created OCUTALON, and IPM compiles this class from its preload tree before that, so it exists before Reload.
Class OcuTalon.Install.Ipm
{

/// The stop sentence, the whole text of the status that a run outside OCUTALON returns.
Parameter STOP = "OcuTalon created namespace OCUTALON. Now run: zn ""OCUTALON"" then the same install command.";

/// Maps the %IPM package and the %IPM.* routines into OCUTALON, from the database where %IPM resolves in the run namespace
/// (IPM's own command "enable -map -ns OCUTALON -q"), with transactions suspended, so that the rollback of a stopped run cannot
/// undo the mapping. The suspension state before the call is restored on every path.
/// Returns the mapping's error unchanged. Otherwise returns an error status with the stop sentence when the run namespace is
/// not OCUTALON, and OK in OCUTALON, where the install continues. It prints nothing and switches no namespace. IPM's command
/// rewrites the instance's CPF file and reloads OCUTALON's mappings on every call, also when the mapping exists already.
ClassMethod MapAndStop() As %Status
{
	Set suspended = $SYSTEM.Process.TransactionsSuspended(1)
	Try {
		Set sc = ##class(%IPM.Main).Shell("enable -map -ns OCUTALON -q")
	} Catch e {
		Set sc = e.AsStatus()
	}
	Do $SYSTEM.Process.TransactionsSuspended(suspended)
	If $$$ISERR(sc) Quit sc
	If $Namespace '= "OCUTALON" Quit $SYSTEM.Status.Error(5001, ..#STOP)
	Quit $$$OK
}

}
