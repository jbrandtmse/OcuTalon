/// Tests of the CreateWebhook and SetWebhookSecret commands in OcuTalon.Core.SettingsOps (Story 35.3; AD-1, AD-13, AD-19), called on a shadow instance of
/// OcuTalon.Test.Core.SettingsOpsProbe, whose audit write is a recording seam, with the secret in a real SecretHandoff. Safe on a slot: no production runs.
/// These tests pin the operation's own guards, which the REST route's checks would otherwise hide.
///   - TestCreateAuditsFirst: a create whose audit write fails answers not_audited and stores no row, and a create that succeeds records one entry naming
///     webhook.<Ref> and the name, with the salted hash in the row and the secret in no entry;
///   - TestRotateOfAnotherSession: a rotation of a Ref that another session owns, and of an unknown Ref, answers not_found and leaves the hash and the audit alone;
///   - TestOnlineDemo: with the online-demo flag set both commands answer not_available, store nothing and audit nothing;
///   - TestNoSecret: a command whose handoff uri has no secret behind it answers failed and stores nothing;
///   - TestNameTakenAtSave: a create whose name is taken between its check and its save (another row stored at its audit write) answers name_taken with the
///     name's field text, writes a second audit entry that undoes the first (from the name to ""), and stores no row of its own.
Class OcuTalon.Test.Core.SettingsWebhooks Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

Parameter SECRET = "zz-ops-secret-0123456789";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Refs of the fixture sessions A and B.
Property A As %String;

Property B As %String;

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..A = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..B = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Webhook WHERE SessionRef IN (?, ?)", ..A, ..B)
	While result.%Next() {
		Do ##class(OcuTalon.Data.Webhook).%DeleteId(result.%GetData(1))
	}
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $$$OK
}

Method TestCreateAuditsFirst()
{
	Set name = "zz ops "_$Random(1000000)
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set result = ..Create(name, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "a create whose audit write fails is not_audited")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken(name), 0, "and stores no row")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "after one audit attempt")

	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set result = ..Create(name, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a create that is audited is done")
	Set data = {}.%FromJSON(result.Data)
	Set row = ##class(OcuTalon.Data.Webhook).Lookup(data.ref)
	Do $$$AssertTrue($IsObject(row), "and stores the row")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(row.SecretHash, ..#SECRET), "whose hash is of the secret")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "with one audit entry")
	Set entry = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data"))
	Do $$$AssertEquals(entry.setting, "webhook."_data.ref, "which names the webhook")
	Do $$$AssertEquals(entry.to, name, "and its name")
	Do $$$AssertTrue(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data") '[ ..#SECRET, "and holds no secret")
}

Method TestRotateOfAnotherSession()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..A, "zz ops rotate "_$Random(1000000), "zz-ops-original-0123456789")
	Set hash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	Set result = ..Rotate(ref, ..B)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "session B's rotation of A's webhook is not_found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "and leaves the hash alone")
	Set result = ..Rotate("AAAAAAAAAAAAAAAAAAAAAA", ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "an unknown Ref is not_found")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "and neither writes an audit entry")
	Set result = ..Rotate(ref, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the owner's rotation is done")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, ..#SECRET), "and replaces the hash")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 1, "with one audit entry")
}

Method TestOnlineDemo()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..A, "zz ops demo "_$Random(1000000), "zz-ops-original-0123456789")
	Set hash = ##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash
	Set name = "zz ops demo new "_$Random(1000000)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..Create(name, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "a create on the online demo is not_available")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken(name), 0, "and stores no row")
	Set result = ..Rotate(ref, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "so is a rotation")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(ref).SecretHash, hash, "and it leaves the hash alone")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "neither writes an audit entry")
}

Method TestNameTakenAtSave()
{
	Set name = "zz ops clash "_$Random(1000000)
	Set ^OcuTalonTest("SettingsOpsProbe", "clash") = name
	Set ^OcuTalonTest("SettingsOpsProbe", "clashSession") = ..B
	Set result = ..Create(name, ..A)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|name_taken", "a create whose name is taken at its save is name_taken")
	Set data = {}.%FromJSON(result.Data)
	Do $$$AssertEquals(data.fields.name, ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.webhookNameTaken", name), "with the name's field text")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 2, "after two audit entries")
	Set first = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 1, "data"))
	Set undone = {}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", 2, "data"))
	Do $$$AssertEquals(undone.setting, first.setting, "the second names the same webhook")
	Do $$$AssertEquals(undone.from_"|"_undone.to, name_"|", "and undoes the first, from the name to nothing")
	Set rows = 0, result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Webhook WHERE SessionRef = ?", ..A)
	While result.%Next() { Set rows = rows + 1 }
	Do $$$AssertEquals(rows, 0, "and session A has no row")
}

Method TestNoSecret()
{
	Set name = "zz ops none "_$Random(1000000)
	Set command = ##class(OcuTalon.Msg.Command.CreateWebhook).%New()
	Set command.Name = name
	Set command.Handoff = "secret://handoff/AAAAAAAAAAAAAAAAAAAAAA"
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..A
	Set command.Origin = "web_admin"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a handoff with no secret behind it is failed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken(name), 0, "and stores no row")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), 0, "and writes no audit entry")
}

/// --- helpers ---
/// A CreateWebhook of the name for the session, with the fixed secret in a handoff of its own; returns the CommandResult.
Method Create(name As %String, session As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.CreateWebhook).%New()
	Set command.Name = name
	Set command.Handoff = ..Handoff()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = session
	Set command.Origin = "web_admin"
	Quit ..Carry(command)
}

/// A SetWebhookSecret of the Ref for the session, with the fixed secret in a handoff of its own; returns the CommandResult.
Method Rotate(ref As %String, session As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetWebhookSecret).%New()
	Set command.WebhookRef = ref
	Set command.Handoff = ..Handoff()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = session
	Set command.Origin = "web_admin"
	Quit ..Carry(command)
}

Method Handoff() As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(..#SECRET, .uri), "the secret is put into a handoff")
	Quit uri
}

Method Carry(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
