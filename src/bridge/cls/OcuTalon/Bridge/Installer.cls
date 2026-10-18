/// The bridge's own installer. It loads and runs without IPM and without any other OcuTalon package,
/// so the bridge can be installed alone from src/bridge/ (AD-2).
/// The after-start script's registry calls Run() as its first step.
Class OcuTalon.Bridge.Installer
{

/// Prepares what the bridge needs in the current namespace.
/// Returns an error naming the namespace when it is not an Interoperability namespace.
ClassMethod Run() As %Status
{
	If '##class(%Library.EnsembleMgr).IsEnsembleNamespace($Namespace) {
		Quit $$$ERROR($$$GeneralError, "Namespace "_$Namespace_" is not an Interoperability namespace")
	}
	Quit $$$OK
}

}
