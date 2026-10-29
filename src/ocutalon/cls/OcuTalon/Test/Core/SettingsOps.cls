/// Tests of OcuTalon.Core.SettingsOps (Story 4.1; AD-17, AD-19, AD-23). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21):
/// TestAuditAccepted writes real Settings entries to the IRIS audit log of the instance, so instance-wide auditing and OcuTalon's events
/// must be on, as a clean install leaves them. The tests drive a shadow instance of OcuTalon.Test.Core.SettingsOpsProbe, which stands in
/// for the Demo step and, except in TestAuditAccepted, for the audit write, so that no namespace is created or removed. The real switch is
/// the job of docker/tests/test-demo-switch.sh. Every text is written out here, never read from SettingsOps.
///   - TestSwitch: a SetDemoMode of 0 or 1 audits first, writes the value, and runs the step after the write; the answer is
///     on or off with its text, and the audit data has exactly the members of the Settings shape: setting, from (the row's value before the
///     write), to, irisUser, sessionRef and channel;
///   - TestFromAbsentRow: with no demo.mode row the entry's from is an empty string (still a member of the entry);
///   - TestFromIgnoresCache: from is the stored value even when this process holds an older value in its Setting cache;
///   - TestKept: a step that kept a foreign OCUORDERS answers off_kept with the note's how sentence;
///   - TestStepFails: a failed step answers step_failed with the error sentence, the value stays written, and the failure is
///     logged as an error;
///   - TestAuditFails: a failed audit answers not_audited, writes nothing, runs no step, and is logged as an error;
///   - TestSameMode: the mode the row already has is audited (from and to both that mode), written and the step rerun all the same;
///   - TestApplyFails: a value that cannot be saved answers failed after the audit, the step does not run, and the failure is
///     logged as an error;
///   - TestKeptOnlyForOff: a demoKept mark does not turn an on switch into off_kept;
///   - TestWarningsTaken: the step's warnings are taken, so none is left for the next step, and are logged;
///   - TestAuditAccepted: with the real Bridge.Audit.Record behind the seam (it writes a real Settings entry, so it needs the audit events
///     that the installer enables, like Test.Bridge.Audit), a switch is carried out for a user and answers not_audited, writing nothing,
///     for a command with no ActingUser or an unknown origin. Record's redaction of the entry is read back by Test.Bridge.Audit;
///   - TestOtherCommand: a command other than SetDemoMode answers unknown_command and writes nothing;
///   - TestStepThrows: an error thrown by the step is the step's error status and answers step_failed;
///   - TestThrown: an error thrown elsewhere inside answers failed and is logged once as an error;
///   - TestAllowList: the allow-list is demo.mode alone, and the guarded write refuses any other key;
///   - TestOnlyRunTimeWriter: no compiled OcuTalon class outside the tests and Data.Setting writes the Setting rows except
///     SettingsOps, and only the Install classes seed them.
/// The demo.mode row is saved before the tests and put back after them (Test.Demo.Step), and so are the demoKept mark and the
/// probe's global.
Class OcuTalon.Test.Core.SettingsOps Extends %UnitTest.TestCase
{

/// The probe under test.
Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

/// A 22-character Ref for the command's SessionRef.
Parameter REF = "zzsession0123456789abc";

/// The step, whose parameters name the setting and the mark.
Parameter STEP = "OcuTalon.Install.Step.Demo";

/// 1 when the demo.mode row existed before the tests.
Property Found As %Boolean;

/// The value of the row before the tests.
Property SavedValue As %String(MAXLEN = 1000);

/// The UpdatedAt of the row before the tests.
Property SavedUpdatedAt As %String(MAXLEN = 20);

/// The demoKept mark before the tests, "" when it was not set.
Property SavedMark As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..Found = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Set ..SavedMark = ##class(OcuTalon.Data.StatusMark).Get($Parameter(..#STEP, "KEPTMARK"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..Found, ..SavedValue, ..SavedUpdatedAt)
	Do ##class(OcuTalon.Data.StatusMark).Record($Parameter(..#STEP, "KEPTMARK"), ..SavedMark)
	Quit $$$OK
}

/// A SetDemoMode of 0 and of 1, from the system and from web_admin: Ok 1, off or on with its text, the row written with the new
/// value and the time, the audit call first and the step call second, the step seeing the new value, and the audit data.
Method TestSwitch()
{
	Set on = "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change."
	Set off = "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change."
	Set table = $ListBuild("0|system|system|off", "1|system|system|on", "0|web_admin|web|off", "1|web_admin|web|on")
	Set position = 0
	While $ListNext(table, position, row) {
		Set mode = $Piece(row, "|", 1), origin = $Piece(row, "|", 2), channel = $Piece(row, "|", 3), outcome = $Piece(row, "|", 4)
		Set label = outcome_" from "_origin
		Do ..Reset()
		Do ##class(OcuTalon.Test.Demo.Step).Put($Select(mode: "0", 1: "1"), "2000-01-01T00:00:00Z")
		Set result = ..Send(mode, origin, "zzadmin", ..#REF)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|"_outcome, label_": carried out")
		Do $$$AssertEquals(result.Message, $Select(mode: on, 1: off), label_": the text")
		Set written = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
		Do $$$AssertEquals(written.Value, mode, label_": the row holds the new value")
		Do $$$AssertTrue($Match(written.UpdatedAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$") && (written.UpdatedAt '= "2000-01-01T00:00:00Z"), label_": UpdatedAt is the time of the write")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, label_": two seams were called")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1)), "audit", label_": the audit came first")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 2)), "step", label_": the step came second")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "seen")), 'mode, label_": the audit saw the old value, so the write came after it")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 2, "seen")), mode, label_": the step saw the new value")
		Set data = {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data")))
		Do $$$AssertEquals(data.irisUser, "zzadmin", label_": the audit names the acting user")
		Do $$$AssertEquals(data.sessionRef, ..#REF, label_": the audit has the SessionRef")
		Do $$$AssertEquals(data.channel, channel, label_": the audit has the channel")
		Do $$$AssertEquals(data.setting, "demo.mode", label_": the audit has the setting")
		Do $$$AssertEquals(data.from, $Select(mode: "0", 1: "1"), label_": the audit has the value before the write")
		Do $$$AssertEquals(data.to, mode, label_": the audit has the new value")
		Do $$$AssertEquals(data.%Size(), 6, label_": and nothing else (irisUser, sessionRef, channel, setting, from and to)")
		Set types = ""
		For name = "setting", "from", "to", "irisUser", "sessionRef", "channel" Set types = types_$Select(types = "": "", 1: ",")_data.%GetTypeOf(name)
		Do $$$AssertEquals(types, "string,string,string,string,string,string", label_": every member is a JSON string (Record requires it; from and to are digits)")
	}
}

/// With no demo.mode row the audit's from is empty and the switch writes the row.
Method TestFromAbsentRow()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|on", "no row: carried out")
	Set data = {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data")))
	Do $$$AssertEquals(data.%GetTypeOf("from"), "string", "the audit's from is a string member")
	Do $$$AssertEquals(data.%Get("from"), "", "the audit's from is empty")
	Do $$$AssertEquals(data.%Size(), 6, "and the entry still has all six members")
	Do $$$AssertEquals(data.to, "1", "and its to is the new value")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode").Value, "1", "the row is written")
}

/// The audit's from is the row's stored value, not the per-process Setting cache's: with an older value cached in this process, from is
/// the one the row holds.
Method TestFromIgnoresCache()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("demo.mode"), "1", "the cache holds 1")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Set row.Value = "0"
	Do $$$AssertStatusOK(row.%Save(), "the row is changed behind the cache")
	Kill row
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("demo.mode"), "1", "and the cache still says 1")
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Outcome, "on", "the switch is carried out")
	Set data = {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data")))
	Do $$$AssertEquals(data.from, "0", "the audit's from is the row's value, not the cached one")
}

/// A step that kept a foreign OCUORDERS: Ok 1, off_kept, and the text is the note's how sentence between the fixed words.
Method TestKept()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set how = "OcuTalon left the OCUORDERS namespace in place because it holds zz. To remove it, delete it."
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "kept"
	Set ^OcuTalonTest("SettingsOpsProbe", "note") = {"text": "zz", "namespace": "OCUORDERS", "globals": "", "routines": "", "how": (how)}.%ToJSON()
	Set result = ..Send(0, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|off_kept", "kept: carried out as off_kept")
	Do $$$AssertEquals(result.Message, "Demo mode is off. "_how_" Reload the OcuTalon page in a minute to see the change.", "kept: the text carries the how sentence")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode").Value, "0", "kept: the row holds 0")
}

/// A step that returns an error: Ok 0, step_failed, the text names the value and the error sentence without its number, and
/// the row keeps the new value.
Method TestStepFails()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "error"
	Set logged0 = ..Logged("The Demo step failed: zz step failed", 2)
	Set result = ..Send(0, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|step_failed", "the step fails: step_failed")
	Do $$$AssertEquals(result.Message, "Demo mode is set to off, but the Demo step failed: zz step failed. OcuTalon runs the step again at its next start.", "the text carries the error sentence")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode").Value, "0", "the row keeps the new value")
	Do $$$AssertEquals(..Logged("The Demo step failed: zz step failed", 2), logged0 + 1, "the failure is in the Event Log as an error")
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "error"
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Message, "Demo mode is set to on, but the Demo step failed: zz step failed. OcuTalon runs the step again at its next start.", "and the text names on")
}

/// The mode the row already has: audited, written (UpdatedAt moves) and the step called, and the answer is that of the mode.
Method TestSameMode()
{
	For mode = 1, 0 {
		Do ..Reset()
		Do ##class(OcuTalon.Test.Demo.Step).Put(mode, "2000-01-01T00:00:00Z")
		Set result = ..Send(mode, "system", "zzadmin", "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|"_$Select(mode: "on", 1: "off"), "mode "_mode_" again: carried out")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, "mode "_mode_" again: the audit and the step were called")
		Set data = {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data")))
		Do $$$AssertEquals(data.%GetTypeOf("from")_"|"_data.from_"|"_data.to, "string|"_mode_"|"_mode, "mode "_mode_" again: the audit's from is the stored value, the same as to")
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
		Do $$$AssertEquals(row.Value, mode, "mode "_mode_" again: the row holds it")
		Do $$$AssertTrue(row.UpdatedAt '= "2000-01-01T00:00:00Z", "mode "_mode_" again: the row was written")
	}
}

/// A value that cannot be saved: Ok 0, failed with CommandsIn's text; the audit was written first and the step did not run, and the
/// row is as it was.
Method TestApplyFails()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "apply") = "error"
	Set logged0 = ..Logged("zz apply failed", 2)
	Set result = ..Send(0, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "the write fails: failed")
	Do $$$AssertEquals(..Logged("zz apply failed", 2), logged0 + 1, "the failed write is in the Event Log as an error")
	Do $$$AssertEquals(result.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", "the text")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "only the audit was called")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls", 1)), "audit", "the audit came first")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Do $$$AssertEquals(row.Value_"|"_row.UpdatedAt, "1|2000-01-01T00:00:00Z", "the row is as it was")
}

/// A demoKept mark that is set (the Demo step keeps a foreign OCUORDERS only when it removes) does not change an on switch.
Method TestKeptOnlyForOff()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "kept"
	Set ^OcuTalonTest("SettingsOpsProbe", "note") = {"text": "zz", "namespace": "OCUORDERS", "globals": "", "routines": "", "how": "zz how."}.%ToJSON()
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|on", "a kept mark and an on switch: on")
	Do $$$AssertEquals(result.Message, "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change.", "the on text")
}

/// The step's warning lines are taken (none is left in the process for the next step) and written to the Event Log as warnings.
Method TestWarningsTaken()
{
	Do ..Reset()
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "warn"
	Set logged0 = ..Logged("zz warning")
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|on", "a step with a warning still answers on")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step).TakeWarnings(), "", "no warning is left for the next step")
	Do $$$AssertEquals(..Logged("zz warning"), logged0 + 1, "the warning was logged once")
}

/// With the real Bridge.Audit.Record behind the seam: the data is an entry that Record accepts, so the switch is carried out, also with no
/// row (from is an empty string). A command with no ActingUser, and one from an origin without a channel, are refused by Record:
/// not_audited, and the row is as it was.
Method TestAuditAccepted()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set result = ..Send(0, "system", "zzadmin", ..#REF)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|off", "Record accepts the entry and the switch is carried out")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, "and the step ran after it")
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set result = ..Send(1, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|on", "with no row Record accepts the entry too (from is an empty string)")
	For case = "no user|system|", "no channel|nowhere|zzadmin" {
		Do ..Reset()
		Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
		Set result = ..Send(0, $Piece(case, "|", 2), $Piece(case, "|", 3), "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", $Piece(case, "|", 1)_": Record refuses the entry, so not_audited")
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
		Do $$$AssertEquals(row.Value_"|"_row.UpdatedAt, "1|2000-01-01T00:00:00Z", $Piece(case, "|", 1)_": the row is as it was")
		Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, $Piece(case, "|", 1)_": the step did not run")
	}
}

/// An audit that fails: Ok 0, not_audited, the row is as it was and the step did not run.
Method TestAuditFails()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set logged0 = ..Logged("The Settings audit entry could not be written: ERROR #5001: zz audit failed", 2)
	Set result = ..Send(0, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "the audit fails: not_audited")
	Do $$$AssertEquals(..Logged("The Settings audit entry could not be written: ERROR #5001: zz audit failed", 2), logged0 + 1, "the failed audit is in the Event Log as an error")
	Do $$$AssertEquals(result.Message, "OcuTalon couldn't write the audit entry, so demo mode was not changed.", "the text says nothing was changed")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Do $$$AssertEquals(row.Value_"|"_row.UpdatedAt, "1|2000-01-01T00:00:00Z", "the row is as it was")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "only the audit was called")
}

/// A command that is not SetDemoMode: Ok 0, unknown_command with CommandsIn's text, and no write and no seam call.
Method TestOtherCommand()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.Origin = "system"
	Set sc = ..Probe().OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|unknown_command", "unknown_command")
	Do $$$AssertEquals(result.Message, "OcuTalon doesn't know that command. Nothing was changed.", "the text")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Do $$$AssertEquals(row.Value_"|"_row.UpdatedAt, "1|2000-01-01T00:00:00Z", "the row is as it was")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "calls"), 0), 0, "no seam was called")
}

/// An error thrown by the step is its error status: step_failed with the error's text, and the value stays written.
Method TestStepThrows()
{
	Do ..Reset()
	Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2000-01-01T00:00:00Z")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "step") = "throw"
	Set result = ..Send(0, "system", "zzadmin", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|step_failed", "the step throws: step_failed")
	Do $$$AssertEquals(result.Message, "Demo mode is set to off, but the Demo step failed: zz step threw. OcuTalon runs the step again at its next start.", "the text carries the error sentence")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode").Value, "0", "the row keeps the new value")
}

/// An error thrown elsewhere inside (here the audit write) is answered as failed, with CommandsIn's text, and the status is OK.
Method TestThrown()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "throw"
	Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
	Set command.Origin = "system"
	Set logged0 = ..Logged("zz audit threw", 2)
	Set sc = ..Probe().OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "failed")
	Do $$$AssertEquals(result.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", "the text")
	Do $$$AssertEquals(..Logged("zz audit threw", 2), logged0 + 1, "the thrown error is in the Event Log once, as an error")
}

/// The allow-list is exactly demo.mode; the guarded write refuses another key with an error status and writes no row.
Method TestAllowList()
{
	Do $$$AssertEquals($Parameter(..#PROBE, "ALLOWLIST"), "demo.mode", "the allow-list is demo.mode")
	Set had = ##class(OcuTalon.Data.Setting).KeyIndexExists("digest.time")
	Set sc = $ClassMethod(..#PROBE, "Guarded", "digest.time", "x")
	Do $$$AssertStatusNotOK(sc, "digest.time is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexExists("digest.time"), had, "and no row was written")
	Set sc = $ClassMethod(..#PROBE, "Guarded", "", "x")
	Do $$$AssertStatusNotOK(sc, "an empty key is refused")
}

/// The run-time writer is SettingsOps alone: over every compiled OcuTalon class outside OcuTalon.Test and Data.Setting itself,
/// a code line that writes Data.Setting (Set, %New, %OpenId, %Open, KeyIndexOpen, KeyIndexDelete, %DeleteId, %Delete,
/// %DeleteExtent or %KillExtent of the class, its global, also by an extended reference, its SQL table, or a $ClassMethod of the
/// class) is in OcuTalon.Core.SettingsOps, and a Seed is in an OcuTalon.Install class. A code line that names the SQL table is a
/// write unless it reads it, with the table name directly after FROM or JOIN on the same line; a DELETE FROM is a write. The
/// scanner is first shown to flag synthetic violators and to pass a comment-only mention and the reads.
Method TestOnlyRunTimeWriter()
{
	Set writer = "(OcuTalon\.Data\.Setting\)\.(Set|%New|%OpenId|%Open|KeyIndexOpen|KeyIndexDelete|%DeleteId|%DeleteExtent|%Delete|%KillExtent)\(|\^(\|[^|]*\||\[[^\]]*\])?OcuTalonP\.Setting|(DELETE\s+(%[A-Za-z]+\s+)*FROM\s+|(?<!FROM\s{1,8})(?<!JOIN\s{1,8}))OcuTalon_Data\.Setting|\$ClassMethod\(.OcuTalon\.Data\.Setting)"
	Set seeder = "OcuTalon\.Data\.Setting\)\.Seed\("
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Do ##class(OcuTalon.Data.Setting).Set(k, v)", writer), "the scanner flags a Set")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Set row = ##class(OcuTalon.Data.Setting).%New()", writer), "the scanner flags a %New")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(k)", writer), "the scanner flags a KeyIndexOpen")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Kill ^OcuTalonP.SettingD(1)", writer), "the scanner flags the global")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Kill ^|""OCUTALON""|OcuTalonP.SettingD", writer), "the scanner flags the global by an extended reference")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Do ##class(OcuTalon.Data.Setting).%KillExtent()", writer), "the scanner flags a %KillExtent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(k)", writer), "the scanner flags a KeyIndexDelete")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(UPDATE OcuTalon_Data.Setting SET Value = 1)", writer), "the scanner flags an SQL write")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(INSERT INTO OcuTalon_Data.Setting (Value) VALUES (1))", writer), "the scanner flags an SQL INSERT INTO")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(INSERT OcuTalon_Data.Setting (Value) VALUES (1))", writer), "the scanner flags an SQL INSERT with no INTO")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(INSERT OR UPDATE INTO OcuTalon_Data.Setting (Value) VALUES (1))", writer), "the scanner flags an SQL INSERT OR UPDATE")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(DELETE FROM OcuTalon_Data.Setting WHERE Value = 1)", writer), "the scanner flags an SQL DELETE FROM")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(DELETE OcuTalon_Data.Setting WHERE Value = 1)", writer), "the scanner flags an SQL DELETE with no FROM")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(TRUNCATE TABLE OcuTalon_Data.Setting)", writer), "the scanner flags an SQL TRUNCATE TABLE")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(UPDATE %NOCHECK %NOLOCK OcuTalon_Data.Setting SET Value = 1)", writer), "the scanner flags an SQL UPDATE with keywords before the table")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(INSERT %NOCHECK INTO OcuTalon_Data.Setting (Value) VALUES (1))", writer), "the scanner flags an SQL INSERT with a keyword before INTO")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Set sc = ##class(%SQL.Statement).%ExecDirect(, ""delete from ocutalon_data.setting"")", writer), "the scanner flags a dynamic SQL write in lower case")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(DELETE %NOLOCK FROM OcuTalon_Data.Setting WHERE Value = 1)", writer), "the scanner flags an SQL DELETE with a keyword before FROM")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(DELETE  FROM"_$Char(9)_"OcuTalon_Data.Setting WHERE Value = 1)", writer), "the scanner flags an SQL DELETE FROM separated by several white space characters")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("      OcuTalon_Data.Setting SET Value = 1)", writer), "the scanner flags a table name that starts the line after its verb")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Set table = ""OcuTalon_Data.Setting""", writer), "the scanner flags the table name held in a variable")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(DROP TABLE OcuTalon_Data.Setting)", writer), "the scanner flags an SQL DROP TABLE")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  Set rs = ##class(%SQL.Statement).%ExecDirect(, ""SELECT COUNT(*) FROM OcuTalon_Data.Setting WHERE UpdatedAt >= ?"", since)", writer), "the scanner passes a SELECT of the table")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  &sql(SELECT Value INTO :v FROM OcuTalon_Data.Setting WHERE ID = 1)", writer), "the scanner passes an embedded SELECT INTO that reads the table")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  SELECT s.Value FROM Ens.Config.Item i JOIN OcuTalon_Data.Setting s ON s.ID = i.ID", writer), "the scanner passes a JOIN that reads the table")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  SELECT ID, LastUpdate FROM OcuTalon_Data.Setting", writer), "the scanner passes a SELECT of a column list")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  select Value from  "_$Char(9)_"ocutalon_data.setting where ID = 1", writer), "the scanner passes a lower-case SELECT with several white space characters before the table")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Do $ClassMethod(""OcuTalon.Data.Setting"", ""Set"", k, v)", writer), "the scanner flags a $ClassMethod write")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("  Do ##class(OcuTalon.Data.Setting).Seed(k, v)", seeder), "the scanner flags a Seed")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  /// ##class(OcuTalon.Data.Setting).Set(k, v) is the writer"_$Char(10)_"  // ##class(OcuTalon.Data.Setting).Seed(k, v)", writer_"|"_seeder), "the scanner passes a comment-only mention")
	Do $$$AssertTrue('##class(OcuTalon.Test.Bridge.Source).Matches("  Quit ##class(OcuTalon.Data.Setting).Get(k)", writer_"|"_seeder), "and a Get")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.' AND NOT Name %STARTSWITH 'OcuTalon.Test.' AND Name <> 'OcuTalon.Data.Setting'")
	Set scanned = 0
	While rs.%Next() {
		Set class = rs.%Get("Name")
		If '##class(OcuTalon.Test.Bridge.Source).Text(class, .text) Continue
		Set scanned = scanned + 1
		If class '= "OcuTalon.Core.SettingsOps" {
			Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Source).Lines(text, writer), "", class_" does not write the Setting rows")
		}
		If $Piece(class, ".", 1, 2) '= "OcuTalon.Install" {
			Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Source).Lines(text, seeder), "", class_" does not seed the Setting rows")
		}
	}
	Do $$$AssertTrue(scanned > 100, "the scan covered the product's classes ("_scanned_")")
	Set ok = ##class(OcuTalon.Test.Bridge.Source).Text("OcuTalon.Core.SettingsOps", .own)
	Do $$$AssertTrue(ok && ##class(OcuTalon.Test.Bridge.Source).Matches(own, writer), "and SettingsOps is found to write them")
}

/// --- helpers ---
/// The number of Event Log rows of the type (3 a warning, 2 an error) whose text contains the text.
ClassMethod Logged(text As %String, type As %Integer = 3) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = ? AND Text [ ?", type, text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Clears the probe's global and the demoKept mark.
Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Do ##class(OcuTalon.Data.StatusMark).Record($Parameter(..#STEP, "KEPTMARK"), "")
}

/// A shadow instance of the probe.
Method Probe() As OcuTalon.Test.Core.SettingsOpsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// Sends a SetDemoMode to the probe and returns its CommandResult.
Method Send(mode As %Boolean, origin As %String, user As %String, sessionRef As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
	Set command.DemoMode = mode
	Set command.Origin = origin
	Set command.ActingUser = user
	Set command.SessionRef = sessionRef
	Set sc = ..Probe().OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
