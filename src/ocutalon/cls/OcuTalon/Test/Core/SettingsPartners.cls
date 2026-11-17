/// Tests of the partner-contacts section of OcuTalon.Core.SettingsOps and of OcuTalon.Data.PartnerContact (Story 24.2; AD-1, AD-13, AD-19, AD-33; DW-1254), called on a shadow
/// instance of OcuTalon.Test.Core.SettingsOpsProbe, whose audit write is a recording seam and whose productions are a scripted list, with the body in a real SecretHandoff, as the
/// route offers it. Safe on a slot: no production runs. The class declares TABLE = 1 so that PartnersShown can be shown to read the parameter of the class it is given. The
/// contacts that the tests make (names that begin zzpc), the online-demo flag and the fixture sessions are put back after each test.
///   - TestAddEditRemoveAudited: an add, an edit and a remove each write the row and then one Settings audit entry, partnerContact.<Ref>, whose from and to name the changed
///     fields and never a value, with the admin, the session and the web channel; an entry that cannot be written, or a write that throws, rolls the row back, read from storage;
///   - TestRefusalsNameFieldsOnly: a bad name, address or production list is refused with its field named, a body of the wrong shape with no field, and nothing is written or
///     audited; no refusal holds a value;
///   - TestNothingChanged: the stored values again, in another spelling or order, write no audit entry and leave the row untouched;
///   - TestProductionsMustBeCurrent: each production must be an entry of the productions that Watch.Reader gives, once; one that cannot be read is failed;
///   - TestOnlineDemo: with the flag set a save is not_available with the accepted text, the handoff is gone, nothing is written, and Values has no partner-contacts member;
///   - TestHandoffMissing: a handoff with nothing behind it is failed, and Changes that are not exactly the handoff are refused;
///   - TestForProductionOnlyStoredContacts: ForProduction gives only the stored contacts that name the exact namespace and production, as [{id, name, address}] in ID order,
///     and an edited-away or removed contact is gone at once;
///   - TestTableStates: PartnersShown is 1 for a class that declares TABLE = 1 and 0 for one that declares TABLE = 0, for one with no TABLE, and for a class that does not exist;
///     the real Values has the member exactly when the real PartnersShown is 1;
///   - TestListOrder: List gives the contacts by the upper-cased name, then by Ref;
///   - TestSectionShownAtTableOne: with the switch on, Values has the member {contacts, productions} with the stored contacts and the productions; off, it has none;
///   - TestListProductionsVerb: the verb answers Ok 1 listed with exactly two scripted productions as {namespace, production, displayName} only, and with the productions
///     of Watch.Reader as the same three fields, not_available on the online demo, and failed when the reader throws;
///   - TestProductionsRosterFailureIsEmpty: a submit that fails, throws or is busy, and an answer that is not a list of productions, each give productions [];
///   - TestTextOffOnDemo: the off-on-demo text is the accepted one, verbatim.
///   - TestRowWriteFailureRollsBack (QA): a row write that fails (productions over the 4000-character MAXLEN of the row) is failed, leaves no open transaction, attempts no
///     audit write, leaves no entry for its session in the real audit log (a control add of the same session wrote one) and leaves the row as it was, for an add and for an edit.
Class OcuTalon.Test.Core.SettingsPartners Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

Parameter REF = "zzsession0123456789abc";

/// The switch of the section, as OcuTalon.Fix.PartnerContacts declares it when the partner warnings read the table.
Parameter TABLE = 1;

/// The online-demo flag before the test.
Property SavedOnline As %String;

/// The unique part of the names of the contacts of the test.
Property Tag As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clear()
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ..Clear()
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..Tag = $Random(1000000000)
	Set ^OcuTalonTest("SettingsOpsProbe", "rows") = ..Rows().%ToJSON()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..Clear()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clear()
	Quit $$$OK
}

Method TestAddEditRemoveAudited()
{
	Set a = ..Entry(1), b = ..Entry(2)
	Set name = ..Name("A"), email = ..Email("a")
	Set result = ..Save("", name, email, [(a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an add is done")
	Set contact = ..Find(name)
	Do $$$AssertTrue($IsObject(contact), "the contact is in the list")
	If '$IsObject(contact) Quit
	Set ref = contact.ref
	Do $$$AssertEquals($Length(ref), 22, "its Ref is 22 characters")
	Set row = ##class(OcuTalon.Data.PartnerContact).RefOpen(ref)
	Do $$$AssertEquals(row.Name_"|"_row.Email, name_"|"_email, "the row holds the name and the address")
	Do $$$AssertEquals(row.Productions, [(a)].%ToJSON(), "and the productions as JSON")
	Do $$$AssertTrue(row.CreatedAt?4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a UTC time")
	Do $$$AssertEquals(row.UpdatedAt, row.CreatedAt, "and UpdatedAt is the same on an add")
	Do $$$AssertEquals(..Audits(), 1, "one audit entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "partnerContact."_ref_"||name,email,productions", "an add is from nothing to the three field names")
	Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, "zzadmin|"_..#REF_"|web", "it names the admin, the session and the web channel")
	Do $$$AssertEquals(data.%Size(), 6, "and has exactly the six members of the Settings shape")
	Do $$$AssertTrue((data.%ToJSON() '[ name) && (data.%ToJSON() '[ email), "no value is in it")
	Do ..Reset()
	Set row.UpdatedAt = "zz-before"
	Do row.%Save()
	Set email2 = ..Email("a2")
	Set result = ..Save(ref, name, email2, [(a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an edit of the address is done")
	Do $$$AssertEquals(..Audits(), 1, "one audit entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "partnerContact."_ref_"|email|email", "it names only the changed field, on both sides")
	Set row = ##class(OcuTalon.Data.PartnerContact).RefOpen(ref)
	Do $$$AssertEquals(row.Email_"|"_row.Name, email2_"|"_name, "the row holds the new address and the same name")
	Do $$$AssertTrue(row.UpdatedAt '= "zz-before", "UpdatedAt is set")
	Do $$$AssertTrue((data.%ToJSON() '[ email) && (data.%ToJSON() '[ email2), "neither address is in the entry")
	Kill row
	Do ..Reset()
	Set name2 = ..Name("B")
	Set result = ..Save(ref, name2, email2, [(a), (b)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an edit of the name and the productions is done")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(..Audits()_"|"_data.from_"|"_data.to, "1|name,productions|name,productions", "one entry that names the two changed fields, in order, on both sides")
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set added = ..Name("C")
	Set result = ..Save("", added, ..Email("c"), [(a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "an audit entry that cannot be written stops an add")
	Do $$$AssertEquals(..Find(added), "", "and the row it wrote is rolled back")
	Set result = ..Save(ref, name2, ..Email("a3"), [(a), (b)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "an audit entry that cannot be written stops the edit")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).RefOpen(ref).Email, email2, "and the row is as it was, read from storage")
	Set result = ..Remove(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "and stops a removal")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.PartnerContact).RefOpen(ref)), "which leaves the row")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "throw"
	Set result = ..Remove(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a write that throws is failed")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.PartnerContact).RefOpen(ref)), "and leaves the row")
	Do ..Reset()
	Set result = ..Remove(ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a removal is done")
	Do $$$AssertEquals(..Audits(), 1, "one audit entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "partnerContact."_ref_"|name,email,productions|", "a removal is from the three field names to nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).RefOpen(ref), "", "the row is gone")
	Do $$$AssertEquals(..Find(name2), "", "and so is the contact in the list")
}

Method TestRefusalsNameFieldsOnly()
{
	Set a = ..Entry(1), b = ..Entry(2)
	Set good = ..Name("R"), mail = ..Email("r")
	Set long = $Translate($Justify("", 129), " ", "x")
	Set cases = [
		{"label": "an empty name", "name": "", "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "a name of spaces", "name": "   ", "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "a name over 128 characters", "name": (long), "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "a name with @{", "name": "zz@{x", "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "a name with a control character", "name": (good_$Char(7)), "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "a name with a tab inside", "name": ("zz"_$Char(9)_"x"), "email": (mail), "productions": [(a)], "fields": "name"},
		{"label": "an address that is not one", "name": (good), "email": "nope", "productions": [(a)], "fields": "email"},
		{"label": "an empty address", "name": (good), "email": "", "productions": [(a)], "fields": "email"},
		{"label": "an address with a space", "name": (good), "email": "zz x@example.com", "productions": [(a)], "fields": "email"},
		{"label": "an address over 254 characters", "name": (good), "email": ($Translate($Justify("", 250), " ", "x")_"@example.com"), "productions": [(a)], "fields": "email"},
		{"label": "no production", "name": (good), "email": (mail), "productions": [], "fields": "productions"},
		{"label": "a production that is not current", "name": (good), "email": (mail), "productions": [{"namespace": "zznone", "production": "zznone"}], "fields": "productions"},
		{"label": "the namespace of another production", "name": (good), "email": (mail), "productions": [{"namespace": "zzns2", "production": "zzp2"}], "fields": "productions"},
		{"label": "a repeated production", "name": (good), "email": (mail), "productions": [(a), (a)], "fields": "productions"},
		{"label": "a production in another case", "name": (good), "email": (mail), "productions": [{"namespace": "ZZNS1", "production": "zzp1"}], "fields": "productions"},
		{"label": "every field", "name": "", "email": "nope", "productions": [], "fields": "name,email,productions"}]
	Set iterator = cases.%GetIterator()
	While iterator.%GetNext(, .case) {
		Do ..Reset()
		Set result = ..Save("", case.name, case.email, case.productions)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", case.label_" is refused")
		Do $$$AssertEquals(..Fields(result), case.fields, "and names "_case.fields)
		Do $$$AssertTrue($Match(result.Data, "^\{""fields"":\[(""[a-z]+""(,""[a-z]+"")*)?\]\}$"), "and its Data is the field names only")
		Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "nothing is written or audited")
	}
	Do ..Reset()
	Set result = ..Save("", "zzpc"_..Tag_$Translate($Justify("", 124 - $Length(..Tag)), " ", "y"), mail, [(a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a name of exactly 128 characters is saved")
	Do $$$AssertEquals($Length(..Find("zzpc"_..Tag_$Translate($Justify("", 124 - $Length(..Tag)), " ", "y")).name), 128, "and is stored whole")
	Do ..Clear()
	Set body = ..Body("save", "", good, mail, [(a)])
	Set cases = [
		{"label": "a missing action", "body": (..Without(body, "action"))},
		{"label": "a missing ref", "body": (..Without(body, "ref"))},
		{"label": "a missing name", "body": (..Without(body, "name"))},
		{"label": "a missing address", "body": (..Without(body, "email"))},
		{"label": "missing productions", "body": (..Without(body, "productions"))},
		{"label": "an extra member", "body": (..With(body, "note", "zz"))},
		{"label": "an unknown action", "body": (..With(body, "action", "update"))},
		{"label": "an action that is a number", "body": (..With(body, "action", 5))},
		{"label": "a name that is a number", "body": (..With(body, "name", 5))},
		{"label": "an address that is null", "body": (..With(body, "email", "", "null"))},
		{"label": "productions that are an object", "body": (..With(body, "productions", {}))},
		{"label": "a production that is not an object", "body": (..With(body, "productions", ["zz"]))},
		{"label": "a production with an extra member", "body": (..With(body, "productions", [{"namespace": "zzns1", "production": "zzp1", "x": "y"}]))},
		{"label": "a production whose namespace is a number", "body": (..With(body, "productions", [{"namespace": 5, "production": "zzp1"}]))},
		{"label": "a ref that no contact has", "body": (..With(body, "ref", "zzunknown0123456789abc"))},
		{"label": "a ref that is a number", "body": (..With(body, "ref", 5))},
		{"label": "a ref over 22 characters", "body": (..With(body, "ref", "zzunknown0123456789abcdef"))},
		{"label": "a remove of no ref", "body": {"action": "remove", "ref": ""}},
		{"label": "a remove of an unknown ref", "body": {"action": "remove", "ref": "zzunknown0123456789abc"}},
		{"label": "a remove with a member besides the ref", "body": {"action": "remove", "ref": "zzunknown0123456789abc", "name": "zz"}},
		{"label": "a remove without a ref", "body": {"action": "remove"}}]
	Set iterator = cases.%GetIterator()
	While iterator.%GetNext(, .case) {
		Do ..Reset()
		Set result = ..SaveText(case.body.%ToJSON())
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", case.label_" is refused")
		Do $$$AssertEquals(..Fields(result), "", "with no field named")
		Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "and nothing is written or audited")
	}
	For text = "[]", "5", """zz""", "null", "not json" {
		Set result = ..SaveText(text)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|", "the body '"_text_"' is refused with no field")
	}
	Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "and nothing is written or audited")
}

Method TestNothingChanged()
{
	Set a = ..Entry(1), b = ..Entry(2)
	Set name = ..Name("N"), email = ..Email("n")
	Do ..Save("", name, email, [(a), (b)])
	Set ref = ..Find(name).ref
	Set row = ##class(OcuTalon.Data.PartnerContact).RefOpen(ref)
	Set row.UpdatedAt = "zz-marker"
	Do row.%Save()
	Do ..Reset()
	Set result = ..Save(ref, "  "_name_" ", " "_email_" ", [(b), (a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the stored values again, trimmed and in another order, are done")
	Do $$$AssertEquals(..Audits(), 0, "and write no audit entry")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).RefOpen(ref).UpdatedAt, "zz-marker", "and leave the row untouched")
	Set result = ..Save(ref, name, email, [(a)])
	Do $$$AssertEquals(result.Outcome_"|"_..Audits(), "done|1", "a change of the productions alone is audited")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.from_"|"_data.to, "productions|productions", "as the one field")
}

Method TestProductionsMustBeCurrent()
{
	Set name = ..Name("P")
	Set cases = [
		{"label": "one current production", "productions": [{"namespace": "zzns1", "production": "zzp1"}], "outcome": "done"},
		{"label": "two current productions", "productions": [{"namespace": "zzns1", "production": "zzp1"}, {"namespace": "zzns2", "production": "zzp1"}], "outcome": "done"},
		{"label": "a production of another namespace", "productions": [{"namespace": "zzns2", "production": "zzp2"}], "outcome": "refused"},
		{"label": "a production that is repeated", "productions": [{"namespace": "zzns1", "production": "zzp1"}, {"namespace": "zzns1", "production": "zzp1"}], "outcome": "refused"},
		{"label": "a namespace that is empty", "productions": [{"namespace": "", "production": "zzp1"}], "outcome": "refused"},
		{"label": "a production that is empty", "productions": [{"namespace": "zzns1", "production": ""}], "outcome": "refused"}]
	Set iterator = cases.%GetIterator()
	While iterator.%GetNext(, .case) {
		Do ..Clear()
		Do ..Reset()
		Set result = ..Save("", name, ..Email("p"), case.productions)
		Do $$$AssertEquals(result.Outcome, case.outcome, case.label_" is "_case.outcome)
		Do $$$AssertEquals(..Fields(result), $Select(case.outcome = "refused": "productions", 1: ""), "and names productions only when refused")
	}
	Do ..Clear()
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "productions") = "readerthrows"
	Set result = ..Save("", name, ..Email("p"), [(..Entry(1))])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "productions that cannot be read are failed")
	Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "and nothing is written or audited")
	Set ^OcuTalonTest("SettingsOpsProbe", "rows") = [(..Entry(1))].%ToJSON()
	Kill ^OcuTalonTest("SettingsOpsProbe", "answer", "productions")
	Do ..Save("", name, ..Email("p"), [(..Entry(1))])
	Set ref = ..Find(name).ref
	Set ^OcuTalonTest("SettingsOpsProbe", "rows") = [(..Entry(2))].%ToJSON()
	Do ..Reset()
	Set result = ..Save(ref, name, ..Email("p"), [(..Entry(1))])
	Do $$$AssertEquals(result.Outcome, "refused", "a stored production that is no longer current is refused when the contact is saved with it")
}

Method TestOnlineDemo()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "table") = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..Body("save", "", ..Name("D"), ..Email("d"), [(..Entry(1))])
	Set uri = ..Handoff(body)
	Set result = ..Carry(..Command({"handoff": (uri)}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "on the online demo the save is not_available")
	Do $$$AssertEquals(result.Message, "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.", "with the accepted text")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "the handoff is gone")
	Do $$$AssertEquals(left, "", "and held nothing for anyone")
	Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "nothing was written or audited")
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("partner-contacts"), 0, "Values has no partner-contacts member, even with the switch on")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "productions")), 0, "and submitted no ListProductions")
	Set command = ##class(OcuTalon.Msg.Command.ListProductions).%New()
	Set command.Origin = "web_admin"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|not_available|", "a ListProductions is not_available with no data")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("partner-contacts"), 1, "and it has one when the flag is off")
}

Method TestHandoffMissing()
{
	Set result = ..Carry(..Command({"handoff": "secret://handoff/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a handoff with nothing behind it is failed")
	Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "and nothing is written or audited")
	Set body = ..Body("save", "", ..Name("H"), ..Email("h"), [(..Entry(1))])
	Set result = ..Carry(..Command(body.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "a body in the command's Changes is refused: only a handoff is read")
	Set uri = ..Handoff(body)
	Set result = ..Carry(..Command({"handoff": (uri), "name": "zz"}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "Changes with a member besides the handoff are refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "and the handoff is discarded")
	Set result = ..Carry(..Command({"handoff": 5}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "a handoff that is not a text is refused")
	Do $$$AssertEquals(..Count()_"|"_..Audits(), "0|0", "nothing is written or audited")
}

Method TestForProductionOnlyStoredContacts()
{
	Set one = ..Entry(1), two = ..Entry(2), three = ..Entry(3)
	Do ..Save("", ..Name("F1"), ..Email("f1"), [(one), (two)])
	Do ..Save("", ..Name("F2"), ..Email("f2"), [(three)])
	Do ..Save("", ..Name("F3"), ..Email("f3"), [(one)])
	Set ref1 = ..Find(..Name("F1")).ref, ref3 = ..Find(..Name("F3")).ref
	Set found = ##class(OcuTalon.Data.PartnerContact).ForProduction(one.namespace, one.production)
	Do $$$AssertEquals(..Names(found), ..Name("F1")_","_..Name("F3"), "a production gives the contacts that name it, in ID order")
	Set first = found.%Get(0)
	Do $$$AssertEquals(first.%Size()_"|"_first.address_"|"_first.%GetTypeOf("id"), "3|"_..Email("f1")_"|number", "each is {id, name, address}, the id a number")
	Do $$$AssertEquals(first.id, ##class(OcuTalon.Data.PartnerContact).RefOpen(ref1).%Id(), "the id is the row ID")
	Do $$$AssertTrue(found.%Get(0).id < found.%Get(1).id, "in ascending ID order")
	Do $$$AssertEquals(..Names(##class(OcuTalon.Data.PartnerContact).ForProduction(two.namespace, two.production)), ..Name("F1"), "a contact that names two productions is in each")
	Do $$$AssertEquals(..Names(##class(OcuTalon.Data.PartnerContact).ForProduction(three.namespace, three.production)), ..Name("F2"), "the same production name under another namespace is not the first one")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).ForProduction(three.namespace, two.production).%Size(), 0, "a namespace and a production that no contact names together give none")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).ForProduction("zznone", "zznone").%Size(), 0, "an unknown production gives none")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).ForProduction("", "").%Size(), 0, "and so does an empty pair")
	Do ..Save(ref1, ..Name("F1"), ..Email("f1"), [(three)])
	Do $$$AssertEquals(..Names(##class(OcuTalon.Data.PartnerContact).ForProduction(one.namespace, one.production)), ..Name("F3"), "a contact edited away from a production is gone from it at once")
	Do $$$AssertEquals(..Names(##class(OcuTalon.Data.PartnerContact).ForProduction(three.namespace, three.production)), ..Name("F1")_","_..Name("F2"), "and is in the one it moved to")
	Do ..Remove(ref3)
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).ForProduction(one.namespace, one.production).%Size(), 0, "a removed contact is gone at once")
	Do $$$AssertEquals(##class(OcuTalon.Data.PartnerContact).ForProduction(one.namespace, one.production).%ToJSON(), "[]", "as an empty array")
}

Method TestTableStates()
{
	Set ops = "OcuTalon.Core.SettingsOps"
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Core.SettingsPartners", "TABLE"), "1", "this class declares TABLE = 1")
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Web.PartnerSettingsProbe", "TABLE"), "0", "the web probe is compiled and declares TABLE = 0, so its case is the 0 state and not a missing class")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Test.Core.SettingsOnCall"), "the class with no TABLE is compiled")
	Do $$$AssertEquals($ClassMethod(ops, "PartnersShown", "OcuTalon.Test.Core.SettingsPartners"), 1, "a class with TABLE = 1 shows the section")
	Do $$$AssertEquals($ClassMethod(ops, "PartnersShown", "OcuTalon.Test.Web.PartnerSettingsProbe"), 0, "a class with TABLE = 0 does not")
	Do $$$AssertEquals($ClassMethod(ops, "PartnersShown", "OcuTalon.Test.Core.SettingsOnCall"), 0, "a class with no TABLE does not")
	Do $$$AssertEquals($ClassMethod(ops, "PartnersShown", "OcuTalon.Test.Core.NoSuchClassZz"), 0, "a class that does not exist does not, and nothing is thrown")
	Do $$$AssertEquals($ClassMethod(ops, "PartnersShown", ""), 0, "nor does an empty class name")
	Set real = $ClassMethod(ops, "PartnersShown")
	Do $$$AssertEquals(real, +($Parameter("OcuTalon.Fix.PartnerContacts", "TABLE") ? 1"1"), "the real answer is the TABLE of OcuTalon.Fix.PartnerContacts, exactly 1 or not")
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("partner-contacts"), real, "Values has the member exactly when PartnersShown is 1")
	Set ^OcuTalonTest("SettingsOpsProbe", "table") = 0
	Do $$$AssertEquals(..Page().sections.%IsDefined("partner-contacts"), 0, "and not when the switch is off")
}

Method TestListOrder()
{
	Set a = ..Entry(1)
	For suffix = "b", "A", "C", "D", "D" {
		Do ..Save("", ..Name(suffix), ..Email($Case(suffix, "D": "d"_$Increment(n), : $ZConvert(suffix, "L"))), [(a)])
	}
	Set mine = "", refs = ""
	Set iterator = ##class(OcuTalon.Data.PartnerContact).List().%GetIterator()
	While iterator.%GetNext(, .one) {
		If $Extract(one.name, 1, $Length(..Name(""))) '= ..Name("") Continue
		Set mine = mine_$Select(mine = "": "", 1: ",")_$Piece(one.name, " ", 2)
		If $Piece(one.name, " ", 2) = "D" Set refs = refs_$ListBuild(one.ref)
	}
	Do $$$AssertEquals(mine, "A,b,C,D,D", "List orders by the upper-cased name, not by ID or by the exact case")
	Do $$$AssertTrue($List(refs, 1) ']] $List(refs, 2), "and two contacts of one name by their Ref")
}

Method TestSectionShownAtTableOne()
{
	Set a = ..Entry(1), b = ..Entry(2)
	Do ..Save("", ..Name("S"), ..Email("s"), [(a), (b)])
	Set ^OcuTalonTest("SettingsOpsProbe", "table") = 1
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("partner-contacts"), 1, "with the switch on, Values has the member")
	Set member = values.sections.%Get("partner-contacts")
	Set names = ""
	Set iterator = member.%GetIterator()
	While iterator.%GetNext(.name) {
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "contacts,productions", "it is {contacts, productions}")
	Set contact = ""
	Set iterator = member.contacts.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.name = ..Name("S") Set contact = one
	}
	Do $$$AssertTrue($IsObject(contact), "the stored contact is in contacts")
	If $IsObject(contact) {
		Do $$$AssertEquals(contact.%Size()_"|"_contact.email_"|"_contact.productions.%ToJSON(), "4|"_..Email("s")_"|"_[(a), (b)].%ToJSON(), "as {ref, name, email, productions}")
	}
	Do $$$AssertEquals(member.productions.%ToJSON(), ..Rows().%ToJSON(), "the productions are the roster, each {namespace, production, displayName}")
	Set ^OcuTalonTest("SettingsOpsProbe", "table") = 0
	Do $$$AssertEquals(..Page().sections.%IsDefined("partner-contacts"), 0, "with the switch off, it has none")
}

Method TestListProductionsVerb()
{
	Set command = ##class(OcuTalon.Msg.Command.ListProductions).%New()
	Set command.Origin = "web_admin"
	Set ^OcuTalonTest("SettingsOpsProbe", "rows") = "[{""namespace"": ""zzns1"", ""production"": ""zzp1"", ""displayName"": ""Zz One""}, {""namespace"": ""zzns2"", ""production"": ""zzp2"", ""displayName"": ""Zz Two""}]"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|listed", "scripted: a ListProductions is listed")
	Do $$$AssertEquals(result.Data, "{""productions"":[{""namespace"":""zzns1"",""production"":""zzp1"",""displayName"":""Zz One""},{""namespace"":""zzns2"",""production"":""zzp2"",""displayName"":""Zz Two""}]}", "scripted: Data is exactly the two productions as {namespace, production, displayName}")
	Do $$$AssertEquals({}.%FromJSON(result.Data).productions.%Size(), 2, "scripted: an empty answer would fail, the two productions are listed")
	Kill ^OcuTalonTest("SettingsOpsProbe", "rows")
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|listed", "a ListProductions is listed")
	Set list = {}.%FromJSON(result.Data).productions
	Set real = ##class(OcuTalon.Watch.Reader).Productions()
	Do $$$AssertEquals(list.%Size(), real.%Size(), "it lists each production that Watch.Reader gives")
	Set bad = 0
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(.i, .one) {
		Set entry = real.%Get(i)
		If (one.%Size() '= 3) || (one.namespace '= entry.namespace) || (one.production '= entry.production) || (one.displayName '= entry.displayName) Set bad = bad + 1
	}
	Do $$$AssertEquals(bad, 0, "each as {namespace, production, displayName} and nothing else")
	Do $$$AssertEquals($Piece(result.Data, "[", 1), "{""productions"":", "Data is exactly {""productions"": [...]}")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "productions") = "readerthrows"
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a reader that throws gives failed")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Kill ^OcuTalonTest("SettingsOpsProbe", "answer", "productions")
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "and the online demo gives not_available")
}

Method TestProductionsRosterFailureIsEmpty()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "table") = 1
	Do $$$AssertEquals(..Page().sections.%Get("partner-contacts").productions.%Size(), 3, "the roster has the scripted productions")
	For answer = "error", "throw", "busy", "garbled", "notlist", "badrow" {
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "productions") = answer
		Set member = ..Page().sections.%Get("partner-contacts")
		Do $$$AssertEquals(member.productions.%ToJSON()_"|"_member.%GetTypeOf("contacts"), "[]|array", answer_": productions [] and the contacts are kept")
	}
}

Method TestTextOffOnDemo()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Core.SettingsOps", "MESSAGEPARTNERSOFF"), "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.", "the off-on-demo text is the accepted one")
}

/// QA (the deferred item of Story 24.2's review; DW-1392): the row write comes first and the audit write after it, in one transaction. A row write that fails must write no
/// audit entry at all, leave no transaction open and leave the row as it was. The failure is real: productions whose JSON is over the 4000-character MAXLEN of the row make
/// %Save fail. The real audit log is read back for the test's own session, and a control add of the same session shows that the query does find an entry when there is one.
Method TestRowWriteFailureRollsBack()
{
	Set a = ..Entry(1)
	Set big = []
	For n = 1:1:60 {
		Do big.%Push({"namespace": "zzns1", "production": ("zzbig"_$Justify(n, 3)_$Translate($Justify("", 80), " ", "x"))})
	}
	Set rows = ..Rows()
	Set iterator = big.%GetIterator()
	While iterator.%GetNext(, .one) {
		Do rows.%Push({"namespace": (one.namespace), "production": (one.production), "displayName": "zz big"})
	}
	Set ^OcuTalonTest("SettingsOpsProbe", "rows") = rows.%ToJSON()
	Do $$$AssertTrue($Length(big.%ToJSON()) > 4000, "the scripted productions are over the 4000 characters of the row's Productions")
	Do $$$AssertEquals($TLevel, 0, "no transaction is open before")
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set name = ..Name("T"), email = ..Email("t")
	Set result = ..Save("", name, email, [(a)], session)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "control: an add that fits is done")
	Do $$$AssertEquals(..Audits(), 1, "control: and its audit write was recorded")
	Set ref = ..Find(name).ref
	Do $$$AssertEquals(..AuditData(1).setting, "partnerContact."_ref, "control: the record of a committed write stays")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Settings", "Settings", session)
	Do $$$AssertEquals(entries.%Size()_"|"_entries.%Get(0).data.setting, "1|partnerContact."_ref, "control: the real audit log has its one entry")
	Hang 0.02
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Save("", ..Name("U"), ..Email("u"), big, session)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an add whose row write fails is failed")
	Do $$$AssertEquals(result.Message, ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "with the generic failed text")
	Do $$$AssertEquals(..Audits(), 0, "no audit write was attempted: the failure came first")
	Do $$$AssertEquals($TLevel, 0, "the transaction is closed")
	If $TLevel > 0 TROLLBACK
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Settings", "Settings", session).%Size(), 0, "and the real audit log has no entry for the session")
	Do $$$AssertEquals(..Count(), 1, "no row was added: the one contact is the control's")
	Do $$$AssertEquals(..Find(..Name("U")), "", "the failed contact is not in the list")
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set before = ##class(OcuTalon.Data.PartnerContact).RefOpen(ref)
	Set row = before.Name_"|"_before.Email_"|"_before.Productions_"|"_before.UpdatedAt
	Kill before
	Set result = ..Save(ref, name, email, big, session)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an edit whose row write fails is failed")
	Do $$$AssertEquals(..Audits(), 0, "no audit write was attempted")
	Do $$$AssertEquals($TLevel, 0, "the transaction is closed")
	If $TLevel > 0 TROLLBACK
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Settings", "Settings", session).%Size(), 0, "the real audit log has no entry of the edit")
	Set after = ##class(OcuTalon.Data.PartnerContact).RefOpen(ref)
	Do $$$AssertEquals(after.Productions, [(a)].%ToJSON(), "and the row is as it was, read afresh: the productions are the stored ones")
	Do $$$AssertEquals(after.Name_"|"_after.Email_"|"_after.Productions_"|"_after.UpdatedAt, row, "and the row is as it was")
	Kill after
	Do ..Reset()
	Set result = ..Save(ref, name, ..Email("t2"), [(a)])
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Audits(), "1|done|1", "after the failures a save that fits is done and audited once")
}

/// --- helpers ---
/// The nth scripted production, {namespace, production}: 1 and 2 share a namespace, 1 and 3 share a production name.
ClassMethod Entry(n As %Integer) As %DynamicObject [ Private ]
{
	Quit $Case(n, 1: {"namespace": "zzns1", "production": "zzp1"}, 2: {"namespace": "zzns1", "production": "zzp2"}, : {"namespace": "zzns2", "production": "zzp1"})
}

/// The scripted list of productions as the reader gives them: the three entries with a display name each.
ClassMethod Rows() As %DynamicArray [ Private ]
{
	Set rows = []
	For n = 1:1:3 {
		Set entry = ..Entry(n)
		Do rows.%Push({"namespace": (entry.namespace), "production": (entry.production), "displayName": ("Zz "_entry.production)})
	}
	Quit rows
}

Method Name(suffix As %String) As %String [ Private ]
{
	Quit "zzpc"_..Tag_" "_suffix
}

Method Email(suffix As %String) As %String [ Private ]
{
	Quit "zzpc"_..Tag_suffix_"@example.com"
}

/// A body of a save or a remove.
ClassMethod Body(action As %String, ref As %String, name As %String, email As %String, productions As %DynamicArray) As %DynamicObject [ Private ]
{
	Quit {"action": (action), "ref": (ref), "name": (name), "email": (email), "productions": (productions)}
}

/// A copy of the body without the member.
ClassMethod Without(body As %DynamicObject, name As %String) As %DynamicObject [ Private ]
{
	Set copy = {}.%FromJSON(body.%ToJSON())
	Do copy.%Remove(name)
	Quit copy
}

/// A copy of the body with the member set (a new one is added at the end), as the JSON type given (null for a JSON null).
ClassMethod With(body As %DynamicObject, name As %String, value, type As %String = "") As %DynamicObject [ Private ]
{
	Set copy = {}.%FromJSON(body.%ToJSON())
	If type = "" {
		Do copy.%Set(name, value)
	} Else {
		Do copy.%Set(name, value, type)
	}
	Quit copy
}

/// Puts the body into a handoff of its own and returns the uri.
Method Handoff(body As %DynamicObject) As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(body.%ToJSON(), .uri), "the body is put into a handoff")
	Quit uri
}

/// A SaveSettings of the partner-contacts section with the text as its Changes, from web_admin for zzadmin.
Method Command(changes As %String, session As %String = {..#REF}) As OcuTalon.Msg.Command.SaveSettings [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "partner-contacts"
	Set command.Changes = changes
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = session
	Set command.Origin = "web_admin"
	Quit command
}

/// Saves a contact as the route does: through a handoff, with {"handoff": uri} as the command's Changes, for the session (REF by default).
Method Save(ref As %String, name As %String, email As %String, productions As %DynamicArray, session As %String = {..#REF}) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText(..Body("save", ref, name, email, productions).%ToJSON(), session)
}

/// Removes a contact the same way.
Method Remove(ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText({"action": "remove", "ref": (ref)}.%ToJSON())
}

/// Saves the text as the body of the handoff.
Method SaveText(text As %String, session As %String = {..#REF}) As OcuTalon.Msg.CommandResult [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(text, .uri), "the text is put into a handoff")
	Quit ..Carry(..Command({"handoff": (uri)}.%ToJSON(), session))
}

Method Carry(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The refused fields of a result, comma-separated.
Method Fields(result As OcuTalon.Msg.CommandResult) As %String [ Private ]
{
	Set text = ""
	If result.Data = "" Quit ""
	Set fields = {}.%FromJSON(result.Data).fields
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set text = text_$Select(text = "": "", 1: ",")_name
	}
	Quit text
}

/// The page's values as the web process reads them: Values on the probe, whose submits are handed to the real handlers.
Method Page() As %DynamicObject [ Private ]
{
	Quit $ClassMethod(..#PROBE, "Values")
}

/// The names of the contacts of a ForProduction answer, comma-separated.
ClassMethod Names(found As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	Set iterator = found.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: ",")_one.name
	}
	Quit text
}

/// The contact of the name in PartnerContact.List, or "".
Method Find(name As %String) As %DynamicObject [ Private ]
{
	Set found = ""
	Set iterator = ##class(OcuTalon.Data.PartnerContact).List().%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.name = name Set found = one
	}
	Quit found
}

/// The number of contacts that this class made (names that begin zzpc).
Method Count() As %Integer [ Private ]
{
	Set count = 0
	Set iterator = ##class(OcuTalon.Data.PartnerContact).List().%GetIterator()
	While iterator.%GetNext(, .one) {
		If $Extract(one.name, 1, 4) = "zzpc" Set count = count + 1
	}
	Quit count
}

/// Deletes the contacts that the tests made.
ClassMethod Clear() [ Private ]
{
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.PartnerContactD(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.PartnerContact).%OpenId(id)
		If $IsObject(row) && ($Extract(row.Name, 1, 4) = "zzpc") Do ##class(OcuTalon.Data.PartnerContact).%DeleteId(id)
	}
}

/// Forgets what the probe recorded and the answers that it was told to give, and keeps the scripted productions and the switch.
Method Reset() [ Private ]
{
	Kill ^||OcuTalonSettingsOpsProbe, ^OcuTalonTest("SettingsOpsProbe", "calls"), ^OcuTalonTest("SettingsOpsProbe", "answer"), ^OcuTalonTest("SettingsOpsProbe", "productions"), ^OcuTalonTest("SettingsOpsProbe", "roster")
}

/// The number of audit writes that the probe saw, counted outside the transactions that roll the probe's own record back.
Method Audits() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonSettingsOpsProbe("n", "audit"))
}

/// The data of the nth audit write that the probe saw.
Method AuditData(nth As %Integer) As %DynamicObject [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit" {
			Set count = count + 1
			If count = nth Quit
		}
	}
	Quit {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", n, "data"), "{}"))
}

}
