/// The installer-step registry (AD-23, AD-29): the fixed order in which the steps run at every start,
/// the discovery of the areas that declare grants, reconcilers, tasks and purges, and the purge entry point.
Class OcuTalon.Install.Registry
{

/// The package whose non-abstract subclasses of OcuTalon.Install.Step are the areas.
Parameter AREAPACKAGE = "OcuTalon.Install.Step.";

/// The steps in the order they run. "Bridge.Installer" is OcuTalon.Bridge.Installer, "Ready" is the Ready()
/// method of OcuTalon.Install.Step.Public, and every other name is a class under OcuTalon.Install.Step
/// whose Run() is the step.
ClassMethod Order() As %List
{
	Quit $ListBuild("Bridge.Installer", "Public", "Roles", "Users", "Web", "SSL", "Tasks", "Demo", "Provider", "Audit", "Telegram", "Production", "Reconcile", "PrivateData", "Ready")
}

/// The class names of the areas, sorted by name: every compiled, non-abstract subclass of
/// OcuTalon.Install.Step that is named OcuTalon.Install.Step.<name>. A class in the order that is not
/// among them still runs, and a class that is among them but not in the order only declares.
ClassMethod Areas() As %List
{
	Set areas = ""
	Set sc = $$GetAllDerivedClasses^%occLibrary("OcuTalon.Install.Step", .derived)
	If $$$ISERR(sc) Quit areas
	Set prefix = ..#AREAPACKAGE
	Set name = ""
	For {
		Set name = $Order(derived(name))
		Quit:name=""
		If $Extract(name, 1, $Length(prefix)) '= prefix Continue
		If '##class(%Dictionary.CompiledClass).%ExistsId(name) Continue
		If $$$comClassKeyGet(name, $$$cCLASSabstract) Continue
		Set areas = areas _ $ListBuild(name)
	}
	Quit areas
}

/// Runs every step in the order, in the namespace OCUTALON only. Writes one line per step:
/// STEP <name> OK <seconds>s, or STEP <name> FAILED <text> for the first step that fails, which stops the run.
/// A step's warnings (Install.Step Warn) are discarded before it runs and written after its line, one line each:
/// WARN <name> <text>.
/// caller names the entry point ("after-start", "ipm") in the refusal of another namespace and, for the length of the run, to the steps
/// (OcuTalon.Install.Step Caller).
ClassMethod Run(caller As %String = "") As %Status
{
	If $Namespace '= "OCUTALON" {
		Quit $SYSTEM.Status.Error(5001, "The installer steps run only in namespace OCUTALON, not in "_$Namespace_" (called by "_caller_")")
	}
	Set ^||OcuTalonStepCaller = caller
	Set order = ..Order()
	Set position = 0
	Set sc = $SYSTEM.Status.OK()
	While $ListNext(order, position, name) {
		Do ##class(OcuTalon.Install.Step).TakeWarnings()
		Set started = $ZHorolog
		Set sc = ..RunStep(name)
		If $$$ISERR(sc) {
			Write !, "STEP ", name, " FAILED ", ..OneLine(sc)
		} Else {
			Write !, "STEP ", name, " OK ", $FNumber($ZHorolog - started, "", 1), "s"
		}
		Set warnings = ##class(OcuTalon.Install.Step).TakeWarnings()
		Set warning = 0
		While $ListNext(warnings, warning, line) {
			Write !, "WARN ", name, " ", line
		}
		If $$$ISERR(sc) Quit
	}
	Kill ^||OcuTalonStepCaller
	Quit sc
}

/// The IPM entry point (AD-23), the Configure, After Invoke of the package. On the Docker image, where the version file exists, it does
/// nothing and returns OK: the after-start script runs the steps there. Elsewhere it runs the steps once, with Run("ipm"). The steps
/// cannot run inside IPM's open transaction (the production cannot start there: ErrCanNotAcquireRuntimeLock), so it commits that
/// transaction to level 0, runs the steps, and opens the same number of levels again on every path, so that IPM's own commit follows.
/// A Reload, Validate or Compile failure is still IPM's rollback, because Configure runs after Compile and after the bundle copy; a failed
/// step leaves the installed code in place and the same install command runs the steps again. Returns the status of Run.
ClassMethod Ipm(versionFile As %String = {##class(OcuTalon.Install.Step.Demo).#VERSIONFILE}) As %Status
{
	If ##class(%File).Exists(versionFile) Quit $SYSTEM.Status.OK()
	Set level = $TLevel
	While $TLevel > 0 {
		TCommit
	}
	Try {
		Set sc = ..Run("ipm")
	} Catch exception {
		Set sc = exception.AsStatus()
		Kill ^||OcuTalonStepCaller
	}
	While $TLevel < level {
		TStart
	}
	Quit sc
}

/// Calls Purge(days) of every area and combines the failures into one status.
ClassMethod Purge(days As %Integer) As %Status
{
	Quit ..CallAreas("Purge", days)
}

/// Calls a class method of every area with the given arguments and combines the failures into one status.
/// Each failure names its area. Every area is called, whatever an earlier one returned.
ClassMethod CallAreas(method As %String, args...) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Set areas = ..Areas()
	Set position = 0
	While $ListNext(areas, position, area) {
		Try {
			Set one = $ClassMethod(area, method, args...)
		} Catch exception {
			Set one = exception.AsStatus()
		}
		If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, area_" "_method_"(): "_..OneLine(one)))
	}
	Quit sc
}

/// Collects what every area declares through a method that returns a dynamic array of objects
/// (Grants, Tasks) into entries(n) = the object, with entries(n, "area") = the area's class name.
/// A method that fails or returns anything else is an error naming the area.
ClassMethod Declared(method As %String, Output entries) As %Status
{
	Kill entries
	Set sc = $SYSTEM.Status.OK()
	Set count = 0
	Set areas = ..Areas()
	Set position = 0
	While $ListNext(areas, position, area) {
		Try {
			Set list = $ClassMethod(area, method)
			Set iterator = list.%GetIterator()
			While iterator.%GetNext(.key, .entry) {
				If '$IsObject(entry) || 'entry.%IsA("%Library.DynamicObject") {
					Set sc = $SYSTEM.Status.Error(5001, area_" "_method_"(): entry "_key_" is not an object")
					Quit
				}
				Set count = count + 1
				Set entries(count) = entry
				Set entries(count, "area") = area
			}
		} Catch exception {
			Set sc = $SYSTEM.Status.Error(5001, area_" "_method_"(): "_..OneLine(exception.AsStatus()))
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// Runs one step of the order and returns its status. An exception is a failed step.
ClassMethod RunStep(name As %String) As %Status [ Private ]
{
	Try {
		If name = "Bridge.Installer" {
			Set sc = ##class(OcuTalon.Bridge.Installer).Run()
		} ElseIf name = "Ready" {
			Set sc = ##class(OcuTalon.Install.Step.Public).Ready()
		} Else {
			Set sc = $ClassMethod(..#AREAPACKAGE_name, "Run")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The text of a status on one line.
ClassMethod OneLine(sc As %Status) As %String [ Private ]
{
	Quit $Translate($SYSTEM.Status.GetErrorText(sc), $Char(13, 10), "  ")
}

}
