/// The second early step of the package's first install run (AD-23, FR-57): it makes IPM available in namespace OCUTALON and,
/// outside OCUTALON, maps IPM's repository definitions into it and stops the run with the next command. The manifest invokes MapAndStop at Initialize, after the CPF
/// resource has created OCUTALON, and IPM compiles this class from its preload tree before that, so it exists before Reload.
Class OcuTalon.Install.Ipm
{

/// The stop sentence, the whole text of the status that a run outside OCUTALON returns.
Parameter STOP = "OcuTalon created namespace OCUTALON. Now run: zn ""OCUTALON"" then the same install command.";

/// Maps the %IPM package and the %IPM.* routines into OCUTALON, from the database where %IPM resolves in the run namespace
/// (IPM's own command "enable -map -ns OCUTALON -q"). Outside OCUTALON it then maps IPM's repository definitions the same way (U-232,
/// see MapRepos), so that the second install command finds the repositories of the first namespace. All of it runs with
/// transactions suspended, so that the rollback of a stopped run cannot undo the mapping. The suspension state before the call is
/// restored on every path.
/// Returns the first mapping error unchanged. Otherwise returns an error status with the stop sentence when the run namespace is
/// not OCUTALON, and OK in OCUTALON, where the install continues. It prints nothing and switches no namespace. IPM's command
/// rewrites the instance's CPF file and reloads OCUTALON's mappings on every call, also when the mapping exists already.
ClassMethod MapAndStop() As %Status
{
	Set suspended = $SYSTEM.Process.TransactionsSuspended(1)
	Try {
		Set sc = ##class(%IPM.Main).Shell("enable -map -ns OCUTALON -q")
		If $$$ISOK(sc), $Namespace '= "OCUTALON" Set sc = ..MapRepos()
	} Catch e {
		Set sc = e.AsStatus()
	}
	Do $SYSTEM.Process.TransactionsSuspended(suspended)
	If $$$ISERR(sc) Quit sc
	If $Namespace '= "OCUTALON" Quit $SYSTEM.Status.Error(5001, ..#STOP)
	Quit $$$OK
}

/// Maps IPM's repository definitions, the globals ^IPM.Repo.DefinitionD, S and I, into OCUTALON from the database where each resolves
/// in the run namespace (%IPM.Utils.Build MapGlobalEquivalently; IPM's own "enable -map -repos" skips OCUTALON). The definitions are
/// mapped as they are: nothing is copied, created, edited or printed. Like IPM's own rule, it maps nothing when OCUTALON already
/// sees repository definitions. Returns the first error unchanged. The caller suspends transactions.
ClassMethod MapRepos() As %Status [ Private ]
{
	If $Data(^|"OCUTALON"|IPM.Repo.DefinitionD)\2 Quit $$$OK
	Set sc = $$$OK
	Set list = $ListBuild("IPM.Repo.DefinitionD", "IPM.Repo.DefinitionS", "IPM.Repo.DefinitionI")
	Set pointer = 0
	While $ListNext(list, pointer, global) && $$$ISOK(sc) {
		Set sc = ##class(%IPM.Utils.Build).MapGlobalEquivalently(global, $Namespace, "OCUTALON")
	}
	Quit sc
}

/// The package's Unconfigure step: removes the mapping of IPM's repository definitions that MapAndStop made in OCUTALON, with IPM's
/// own "unmap -repos-only -ns OCUTALON -q", which unmaps those three globals and nothing else. Transactions are suspended during the
/// call and restored on every path. It prints nothing and kills and sets no global, so the definitions of the namespace that holds
/// them stay as they are. Returns IPM's status.
ClassMethod UnmapRepos() As %Status
{
	Set suspended = $SYSTEM.Process.TransactionsSuspended(1)
	Try {
		Set sc = ##class(%IPM.Main).Shell("unmap -repos-only -ns OCUTALON -q")
	} Catch e {
		Set sc = e.AsStatus()
	}
	Do $SYSTEM.Process.TransactionsSuspended(suspended)
	Quit sc
}

}
