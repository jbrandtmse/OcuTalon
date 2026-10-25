/// A subclass of OcuTalon.Core.SettingsOps for the tests, which override its private seams WriteAudit and RunDemo: they
/// write nothing to the audit log and run no Demo step. RunStep, with its Try/Catch, its warnings and its kept sentence, is
/// the real one. Each call is recorded under ^OcuTalonTest("SettingsOpsProbe", "calls", n) as "audit" or "step", with the
/// value that Setting.Get reads for demo.mode while it runs ("seen"), and for the audit the data as JSON ("data") and the
/// description ("description"). The answers come from ^OcuTalonTest("SettingsOpsProbe", "answer", seam): "" is OK, "error" is
/// an error status, "throw" throws, and for "step" "kept" records the demoKept mark with the note in
/// ^OcuTalonTest("SettingsOpsProbe", "note") and answers OK, and "warn" records one step warning line ("zz warning") and answers
/// OK. The guarded write Apply answers an error status when the "apply" answer is "error" and is the real one otherwise. The
/// product never refers to it.
Class OcuTalon.Test.Core.SettingsOpsProbe Extends OcuTalon.Core.SettingsOps
{

Method WriteAudit(data As %DynamicObject, description As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "calls"))
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit"
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "data") = data.%ToJSON()
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "description") = description
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "seen") = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY)
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz audit threw"))
	Quit $Select($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "error": $SYSTEM.Status.Error(5001, "zz audit failed"), 1: $$$OK)
}

Method RunDemo() As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "calls"))
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "step"
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "seen") = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY)
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "step"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz step threw"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz step failed.")
	If answer = "warn" Do ##class(OcuTalon.Install.Step).Warn("zz warning")
	If answer = "kept" {
		Set sc = ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Install.Step.Demo).#KEPTMARK, $Get(^OcuTalonTest("SettingsOpsProbe", "note")))
		If $$$ISERR(sc) Quit sc
	}
	Quit $$$OK
}

/// The guarded write, failing when the test says so: the value could not be saved.
ClassMethod Apply(key As %String, value As %String) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "apply")) = "error" Quit $SYSTEM.Status.Error(5001, "zz apply failed")
	Quit ##super(key, value)
}

/// The guarded write of SettingsOps, which is private there, for the tests.
ClassMethod Guarded(key As %String, value As %String) As %Status
{
	Quit ..Apply(key, value)
}

}
