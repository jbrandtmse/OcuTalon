/// Tests of the Audit step's report on instance-wide auditing (Story 3.7, DW-10; AD-17, AD-23). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it switches instance-wide auditing off and on in %SYS and writes the status mark instanceAuditing. OnBeforeOneTest saves the setting and
/// the mark, and OnAfterOneTest puts both back, also after a failed test.
///   - TestInstanceAuditingOff: with auditing off, Run is OK, warns exactly once with the one sentence that says IRIS writes none of OcuTalon's entries
///     and that OcuTalon does not change the setting, records the mark off (and a second Run does not stamp it again), leaves the setting off, and
///     Audit.Record returns the error that no entry was written;
///   - TestInstanceAuditingOn: with auditing on, Run is OK with no warning, records the mark on over a stored off, leaves the setting on, and Record writes.
/// A start that finds an event missing or disabled still fails (the step's CheckAudit); the live check of the fresh stack shows the start itself.
Class OcuTalon.Test.Install.Audit Extends %UnitTest.TestCase
{

/// The warning of an off setting, exactly.
Parameter OFFWARNING = "instance-wide auditing is off, so IRIS writes none of OcuTalon's audit entries; OcuTalon does not change this setting: an administrator turns it on in the Management Portal (System Administration > Security > Auditing > Enable Auditing)";

/// Instance-wide auditing before the test, "1" or "0", "" when it was not read.
Property WasAuditing As %String;

/// The value of the mark before the test, "" when it had none.
Property WasMark As %String;

/// 1 once OnBeforeOneTest has saved the state.
Property Saved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled)
	Do $$$AssertStatusOK(sc, "instance-wide auditing is read")
	Set ..WasAuditing = enabled
	Set ..WasMark = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Install.Step.Audit).#MARK)
	Set ..Saved = 1
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Saved {
		If ..WasAuditing '= "" Do ..SetAuditing(..WasAuditing)
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "instance-wide auditing is read again")
		Do $$$AssertEquals(enabled, ..WasAuditing, "instance-wide auditing is as it was: "_..WasAuditing)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Install.Step.Audit).#MARK, ..WasMark), "the mark is put back")
		Set ..Saved = 0
	}
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Quit $$$OK
}

/// Row 10, off: Run is OK with the one warning and the mark off; the setting stays off; Record returns the not-written error.
Method TestInstanceAuditingOff()
{
	Set mark = ##class(OcuTalon.Install.Step.Audit).#MARK
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(mark, "on"), "the mark is on to begin with")
	Do ..SetAuditing(0)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "control: the setting is read")
	Do $$$AssertEquals(enabled, 0, "control: instance-wide auditing is off")
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Audit).Run(), "Run is OK with auditing off")
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertEquals($ListLength(lines), 1, "Run warned exactly once")
	Do $$$AssertEquals($ListGet(lines, 1), ..#OFFWARNING, "and the warning is the one sentence")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get(mark), "off", "the mark is off")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "the setting is read again")
	Do $$$AssertEquals(enabled, 0, "OcuTalon did not change the setting: it is still off")
	Set stamped = ..RecordedAt(mark)
	Hang 1.2
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Audit).Run(), "a second Run is OK")
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertEquals($ListLength(lines), 1, "and warns once again")
	Do $$$AssertEquals(..RecordedAt(mark), stamped, "the mark is not stamped again while its value holds")
	Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set data = {"action": "resend", "target": (marker), "result": "done", "counts": {}, "approvalRef": "", "irisUser": "ocutalon", "sessionRef": (marker), "channel": "web"}
	Set sc = ##class(OcuTalon.Bridge.Audit).Record("Action", data)
	Do $$$AssertStatusNotOK(sc, "Record returns an error: IRIS writes nothing")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "no entry of type Action was written", "that says no entry of type Action was written: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "the setting is read after Record")
	Do $$$AssertEquals(enabled, 0, "and Record did not change it")
}

/// Row 10, on: Run is OK with no warning and the mark on; the setting stays on.
Method TestInstanceAuditingOn()
{
	Set mark = ##class(OcuTalon.Install.Step.Audit).#MARK
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(mark, "off"), "the mark is off to begin with")
	Do ..SetAuditing(1)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "control: the setting is read")
	Do $$$AssertEquals(enabled, 1, "control: instance-wide auditing is on")
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Audit).Run(), "Run is OK with auditing on")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Install.Step).TakeWarnings()), 0, "Run warned of nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get(mark), "on", "the mark is on")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).InstanceAuditing(.enabled), "the setting is read again")
	Do $$$AssertEquals(enabled, 1, "OcuTalon did not change the setting: it is still on")
	Set marker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set data = {"action": "resend", "target": (marker), "result": "done", "counts": {}, "approvalRef": "", "irisUser": "ocutalon", "sessionRef": (marker), "channel": "web"}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Action", data), "Record writes with auditing on")
}

/// The mark's RecordedAt, "" when it has no row.
ClassMethod RecordedAt(mark As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.StatusMark).MarkIndexOpen(mark)
	Quit $Select($IsObject(row): row.RecordedAt, 1: "")
}

/// Switches instance-wide auditing on (1) or off (0), in %SYS. Throwaway stacks only: nothing of OcuTalon does this.
ClassMethod SetAuditing(enabled As %Boolean) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("AuditEnabled") = enabled
	Do ##class(Security.System).Modify("SYSTEM", .properties)
}

}
