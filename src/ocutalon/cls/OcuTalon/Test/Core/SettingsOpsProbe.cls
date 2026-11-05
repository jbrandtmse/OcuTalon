/// A subclass of OcuTalon.Core.SettingsOps for the tests, which override its private seams WriteAudit and RunDemo: they
/// write nothing to the audit log (unless the "audit" answer is "record") and run no Demo step. RunStep, with its Try/Catch, its
/// warnings and its kept sentence, is the real one. Each call is recorded under ^OcuTalonTest("SettingsOpsProbe", "calls", n) as
/// "audit" or "step", with the value that Setting.Get reads for demo.mode while it runs ("seen"), and for the audit the data as JSON
/// ("data"). The answers come from ^OcuTalonTest("SettingsOpsProbe", "answer", seam): "" is OK, "error" is an error status, "throw"
/// throws, for "audit" "record" hands the data to Bridge.Audit.Record and answers its status, and for "step" "kept" records the
/// demoKept mark with the note in ^OcuTalonTest("SettingsOpsProbe", "note") and answers OK, and "warn" records one step warning line
/// ("zz warning") and answers OK. The guarded write Apply answers an error status when the "apply" answer is "error" and is the real
/// one otherwise. The answers "auditAt" and "applyAt" (a number n) make the nth audit write, or the nth guarded write, since the counters were killed
/// (^||OcuTalonSettingsOpsProbe("n", seam), a process-private global, which a TROLLBACK does not undo) answer an error status, for the
/// all-or-nothing tests of a section's save (Story 33.2).
/// The bridge seams BridgeCurrent, BridgeCheck and BridgeSet stand in for Bridge.Settings: each call is recorded under
/// ^OcuTalonTest("SettingsOpsProbe", "bridge", n) as "check" or "set" with the name and value ("what"); the answer "check" is "" for OK, "stub" for
/// "not implemented" (code 5003), "error" for an error status and "error:<name>" for an error status for that name only; the answer "set" is "" for
/// OK and "error" for an error status, "setAt" (a number n) fails the nth Set call only and "throwAt" (a number n) makes it throw. A Set stores the value in
/// ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name) and answers the value it replaced in old. The product never refers to it.
Class OcuTalon.Test.Core.SettingsOpsProbe Extends OcuTalon.Core.SettingsOps
{

Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "calls"))
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit"
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "data") = data.%ToJSON()
	Set ^OcuTalonTest("SettingsOpsProbe", "calls", n, "seen") = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY)
	If $Increment(^||OcuTalonSettingsOpsProbe("n", "audit")) = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt")) Quit $SYSTEM.Status.Error(5001, "zz audit failed at its turn")
	If $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "audit")) = "record" Quit ##class(OcuTalon.Bridge.Audit).Record("Settings", data)
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
	If $Increment(^||OcuTalonSettingsOpsProbe("n", "apply")) = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "applyAt")) Quit $SYSTEM.Status.Error(5001, "zz apply failed at its turn")
	Quit ##super(key, value)
}

Method BridgeCurrent(name As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name))
}

Method BridgeCheck(name As %String, value As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "bridge"))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n) = "check"
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n, "what") = name_"="_value
	Set answer = $Get(^OcuTalonTest("SettingsOpsProbe", "answer", "check"))
	If answer = "stub" Quit $$$ERROR($$$NotImplemented)
	If (answer = "error") || (answer = ("error:"_name)) Quit $SYSTEM.Status.Error(5001, "zz "_name_" refused")
	Quit $$$OK
}

Method BridgeSet(name As %String, value As %String, Output old As %String) As %Status [ Private ]
{
	Set old = ""
	Set n = $Increment(^OcuTalonTest("SettingsOpsProbe", "bridge"))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n) = "set"
	Set ^OcuTalonTest("SettingsOpsProbe", "bridge", n, "what") = name_"="_value
	Set sets = $Increment(^||OcuTalonSettingsOpsProbe("n", "set"))
	If sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "throwAt")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz set threw"))
	If ($Get(^OcuTalonTest("SettingsOpsProbe", "answer", "set")) = "error") || (sets = +$Get(^OcuTalonTest("SettingsOpsProbe", "answer", "setAt"))) Quit $SYSTEM.Status.Error(5001, "zz set failed")
	Set old = $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name))
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name) = value
	Quit $$$OK
}

/// The guarded write of SettingsOps, which is private there, for the tests.
ClassMethod Guarded(key As %String, value As %String) As %Status
{
	Quit ..Apply(key, value)
}

}
