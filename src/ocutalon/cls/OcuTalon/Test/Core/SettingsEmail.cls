/// Tests of the email section of SaveSettings in OcuTalon.Core.SettingsOps (Stories 21.2 and 21.6; AD-1, AD-17, AD-19), driven through a shadow instance of
/// OcuTalon.Test.Core.SettingsEmailProbe: the credential, the settings rows of EmailIn and EmailOut and the production update are stand-ins, the audit write is a
/// recording seam, and the hand-off is the real OcuTalon.Core.SecretHandoff. Safe on a slot: the product keys email.address and email.owner and the public
/// setting onlineDemo are saved before the tests and put back after them, and every reference a test offers is discarded. Every text is written out here.
///   - TestFirstSave (matrix row 1): a valid first save answers done; the credential holds the user and the password, the keys hold the address and the
///     saving session, the rows hold server, port, credential name, SSLConfig OcuTalonClient and Enabled 1, EmailIn is updated once, and the five audit
///     entries have the forms of the contract (address and user "set", server as given, credential "set", owner from "" to the session) and no value;
///   - TestTlsFollowsThePort: port 110 gives OcuTalonClient*, any other port OcuTalonClient, none gives port 995; there is no plain choice;
///   - TestPasswordKept (row 2): an omitted or empty password keeps the stored one and applies the other changes (address "changed"); with no credential
///     yet it is refused naming password and nothing changes; TestUserChangeKeepsPassword: a new user name alone changes the user only;
///   - TestRefusedValues, TestRefusedPasswords (row 3): every refused kind of value is refused naming the field, every refused field is named, and no key,
///     credential, row, update or audit entry is written; TestRefusedBodies: a body that is not an object, an array or an unknown field is refused;
///   - TestOnlineDemo (row 5): on the online demo the save answers not_available with the accepted sentence, takes nothing from the hand-off and writes
///     nothing, and the page's values have no channels;
///   - TestOtherAdminSaves (row 6): a second admin's save moves email.owner to that session and audits the two Refs;
///   - TestHandOffLost (row 7): a reference that names no secret is refused naming password and nothing is written;
///   - TestNothingChanged (DW-1139): the same save again writes no audit entry, no row and no credential and still updates the production, so that an item
///     whose earlier update never ran starts; a refused save updates nothing;
///   - TestOutgoingFirstSave, TestSmtpTlsFollowsThePort, TestOutgoingCleared, TestOutgoingAudit (Story 21.6): the rows of EmailOut (SMTPServer, SMTPPort 587 by
///     default, Credentials, SSLConfig OcuTalonClient on port 465 and OcuTalonClient* on any other, SSLCheckServerIdentity 1, Enabled 1), the rows of
///     EmailIn untouched by an outgoing change, a cleared or absent outgoing server (Enabled 0, the server rows deleted, nothing written when none was saved),
///     and the email.outgoing audit entry in the form host or host:port off 587;
///   - TestAllOrNothing: a failed audit write at each position or a failed key write changes nothing; a failed credential write, a failed settings row
///     write and a failed update put back the keys (with an audit entry of each), the credential and the rows, also over an earlier mailbox;
///   - TestValues: the page's channels hold address, incoming, outgoing, user and passwordSet, never the password;
///   - TestNoSecretAnywhere: after a save the password is in no audit entry, no ^OcuTalon* global and no Ens.Util.Log row.
Class OcuTalon.Test.Core.SettingsEmail Extends %UnitTest.TestCase
{

/// The probe under test.
Parameter PROBE = "OcuTalon.Test.Core.SettingsEmailProbe";

/// The Refs of the sessions of the saves.
Parameter REF = "zzsession0123456789abc";

Parameter OTHERREF = "zzsession9876543210cba";

Parameter ADDRESS = "zzowner@example.com";

Parameter USER = "zzowner@example.com";

Parameter HOST = "pop.example.com";

Parameter SMTPHOST = "smtp.example.com";

/// The sentence of the online demo's refusal (Public text P2).
Parameter UNAVAILABLE = "Email can't be connected on the online demo. Nothing was changed.";

/// The references offered since the last Reset, as a list; Reset discards them.
Property Uris As %List [ Private ];

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsEmail")
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("SettingsEmail", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Set ^OcuTalonTest("SettingsEmail", "online") = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ..Reset()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Reset()
	For key = "email.address", "email.owner" {
		If $Data(^OcuTalonTest("SettingsEmail", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Get(^OcuTalonTest("SettingsEmail", "online")))
	Kill ^OcuTalonTest("SettingsEmail")
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Kill ^OcuTalonTest("SettingsEmailProbe")
	Kill ^||OcuTalonSettingsEmailProbe
	Quit $$$OK
}

/// A first save with every field valid: matrix row 1.
Method TestFirstSave()
{
	Set secret = ..Secret("first")
	Set uri = ..Offer(secret)
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST_":1995", ..#USER, uri))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a valid first save is done")
	Do $$$AssertEquals(..Row("email.address")_"|"_..Row("email.owner"), ..#ADDRESS_"|"_..#REF, "the keys hold the address and the saving session")
	Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("cred"), $ListBuild(..#USER, secret), "the credential holds the user name and the password")
	Do $$$AssertEquals(..Rows(), "POP3Server=pop.example.com;POP3Port=1995;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;Enabled=1", "the rows of EmailIn")
	Do $$$AssertEquals(..Count("start"), 1, "EmailIn is updated once")
	Set audits = ..Audits()
	Do $$$AssertEquals(audits.%Size(), 5, "five audit entries")
	Set forms = ""
	For i = 0:1:audits.%Size() - 1 {
		Set one = audits.%Get(i)
		Set forms = forms_$Select(forms = "": "", 1: ";")_one.setting_"|"_one.from_"|"_one.to
	}
	Do $$$AssertEquals(forms, "email.address||set;email.owner||"_..#REF_";email.incoming||"_..#HOST_":1995;email.user||set;email.credential||set", "address and user are set, the server is as given, the credential is set, the owner is the Ref")
	Do $$$AssertEquals(audits.%Get(0).irisUser_"|"_audits.%Get(0).sessionRef_"|"_audits.%Get(0).channel, "zzadmin|"_..#REF_"|web", "each entry names the acting user, the session and the channel web")
	Do $$$AssertEquals(..AuditText() [ ..#ADDRESS, 0, "no audit entry holds the address")
	Do $$$AssertEquals(..AuditText() [ secret, 0, "or the password")
	Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(uri, .again, 0)
	Do $$$AssertStatusNotOK(sc, "the hand-off was taken: nothing is left to take")
}

/// The SSLConfig follows the port; there is no plain choice.
Method TestTlsFollowsThePort()
{
	Set cases = $ListBuild("pop.example.com|pop.example.com|995|OcuTalonClient", "pop.example.com:110|pop.example.com|110|OcuTalonClient*", "pop.example.com:995|pop.example.com|995|OcuTalonClient", "POP.Example.COM:2995|pop.example.com|2995|OcuTalonClient", "pop.example.com:65535|pop.example.com|65535|OcuTalonClient")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Reset()
		Set result = ..Save(..Body(..#ADDRESS, $Piece(case, "|", 1), ..#USER, ..Offer(..Secret("tls"))))
		Do $$$AssertEquals(result.Outcome, "done", $Piece(case, "|", 1)_" is saved")
		Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "POP3Server")_"|"_^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "POP3Port")_"|"_^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "SSLConfig"), $Piece(case, "|", 2, 4), $Piece(case, "|", 1)_": server, port and SSLConfig")
	}
}

/// Matrix row 2: an omitted or empty password keeps the stored one.
Method TestPasswordKept()
{
	Set secret = ..Secret("kept")
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(secret)))
	For shape = "omitted", "empty" {
		Do ..Clear()
		Set body = {"address": "zznew@example.com", "incoming": "pop.example.com", "user": "zzowner@example.com"}
		If shape = "empty" Do body.%Set("password", "", "string")
		Set result = ..Save(body)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a save with the password "_shape_" is done")
		Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("cred"), $ListBuild(..#USER, secret), "the stored password is kept")
		Do $$$AssertEquals(..Row("email.address"), "zznew@example.com", "the other change is applied")
		Set audits = ..Audits()
		Do $$$AssertEquals(audits.%Size(), 1, "one audit entry")
		Do $$$AssertEquals(audits.%Get(0).setting_"|"_audits.%Get(0).from_"|"_audits.%Get(0).to, "email.address|set|changed", "the address is changed")
		Do $$$AssertEquals(..Count("credential"), 0, "the credential is not written")
		Do ..Save({"address": (..#ADDRESS), "incoming": (..#HOST), "user": (..#USER)})
	}
	Do ..Clear()
	Kill ^||OcuTalonSettingsEmailProbe("cred")
	Set result = ..Save({"address": "zznew@example.com", "incoming": "pop.example.com", "user": "zzowner@example.com"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""password""]}", "with no credential yet an omitted password is refused naming password")
	Do $$$AssertEquals(..Row("email.address"), ..#ADDRESS, "nothing is changed")
	Do $$$AssertEquals(..Audits().%Size(), 0, "nothing is audited")
	Do $$$AssertEquals(..Count("start"), 0, "and EmailIn is not updated")
}

/// A new user name with no password changes the user only.
Method TestUserChangeKeepsPassword()
{
	Set secret = ..Secret("user")
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(secret)))
	Do ..Clear()
	Set result = ..Save({"address": (..#ADDRESS), "incoming": (..#HOST), "user": "zzother"})
	Do $$$AssertEquals(result.Outcome, "done", "a new user name is saved")
	Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("cred"), $ListBuild("zzother", secret), "the user changes and the password stays")
	Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("calls", 1), "credential|zzother|0", "the credential is written without a password")
	Set audits = ..Audits()
	Do $$$AssertEquals(audits.%Size()_"|"_audits.%Get(0).setting_"|"_audits.%Get(0).from_"|"_audits.%Get(0).to, "1|email.user|set|changed", "and audited as changed")
}

/// Matrix row 3: each refused kind of value names its field; nothing is written.
Method TestRefusedValues()
{
	Set cases = $ListBuild(
		$ListBuild("address with @{", "address", """a@{b}@example.com""", "address"),
		$ListBuild("bad address", "address", """not an address""", "address"),
		$ListBuild("address without a domain dot", "address", """me@localhost""", "address"),
		$ListBuild("two addresses", "address", """a@example.com, b@example.com""", "address"),
		$ListBuild("address with a line feed", "address", """a@example.com\nb""", "address"),
		$ListBuild("address as a number", "address", "5", "address"),
		$ListBuild("empty address", "address", """""", "address"),
		$ListBuild("missing address", "address", "<missing>", "address"),
		$ListBuild("server with a space", "incoming", """pop example.com""", "incoming"),
		$ListBuild("server with port 0", "incoming", """pop.example.com:0""", "incoming"),
		$ListBuild("server with port 65536", "incoming", """pop.example.com:65536""", "incoming"),
		$ListBuild("server with a bad port", "incoming", """pop.example.com:abc""", "incoming"),
		$ListBuild("server with two ports", "incoming", """pop.example.com:1:2""", "incoming"),
		$ListBuild("empty server", "incoming", """""", "incoming"),
		$ListBuild("server with @{", "incoming", """@{env:HOST}""", "incoming"),
		$ListBuild("server with a scheme", "incoming", """pop3://pop.example.com""", "incoming"),
		$ListBuild("missing server", "incoming", "<missing>", "incoming"),
		$ListBuild("outgoing with @{", "outgoing", """@{env:SMTP}""", "outgoing"),
		$ListBuild("outgoing with a space", "outgoing", """smtp example.com""", "outgoing"),
		$ListBuild("outgoing with port 0", "outgoing", """smtp.example.com:0""", "outgoing"),
		$ListBuild("outgoing with port 65536", "outgoing", """smtp.example.com:65536""", "outgoing"),
		$ListBuild("outgoing with a bad port", "outgoing", """smtp.example.com:abc""", "outgoing"),
		$ListBuild("outgoing with two ports", "outgoing", """smtp.example.com:1:2""", "outgoing"),
		$ListBuild("outgoing with a scheme", "outgoing", """smtp://smtp.example.com""", "outgoing"),
		$ListBuild("outgoing with a line feed", "outgoing", """smtp.example.com\n""", "outgoing"),
		$ListBuild("outgoing as a number", "outgoing", "587", "outgoing"),
		$ListBuild("outgoing as null", "outgoing", "null", "outgoing"),
		$ListBuild("empty user", "user", """""", "user"),
		$ListBuild("blank user", "user", """   """, "user"),
		$ListBuild("user with a line feed", "user", """a\nb""", "user"),
		$ListBuild("user with @{", "user", """x@{y""", "user"),
		$ListBuild("user over 256 characters", "user", """"_$Translate($Justify("", 257), " ", "u")_"""", "user"),
		$ListBuild("missing user", "user", "<missing>", "user"),
		$ListBuild("password that is not a reference", "password", """plain text""", "password"),
		$ListBuild("password as a number", "password", "7", "password"),
		$ListBuild("password as null", "password", "null", "password"),
		$ListBuild("password reference with a bad form", "password", """secret://handoff/xyz""", "password"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Reset()
		Do ..SeedEarlier()
		Set body = ..Body(..#ADDRESS, ..#HOST, ..#USER, "")
		Do ..Put(body, $List(case, 2), $List(case, 3))
		Set result = ..SaveText(body.%ToJSON())
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":["""_$List(case, 4)_"""]}", $List(case, 1)_" is refused, naming "_$List(case, 4))
		Do ..AssertUntouched($List(case, 1))
	}
	Do ..Reset()
	Do ..SeedEarlier()
	Set result = ..Save({"address": "bad", "incoming": "bad host", "outgoing": "@{x}", "user": "", "password": 5})
	Do $$$AssertEquals(result.Data, "{""fields"":[""address"",""incoming"",""outgoing"",""user"",""password""]}", "every refused field is named, in the order of the form")
	Do ..AssertUntouched("a save with four refused fields")
}

/// A password that is refused after it is taken: a control character, over 256 characters, "@{".
Method TestRefusedPasswords()
{
	Set cases = $ListBuild("with a carriage return|zz"_$Char(13)_"pw", "with a tab|zz"_$Char(9)_"pw", "over 256 characters|"_$Translate($Justify("", 257), " ", "p"), "with @{|zz@{pw")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Reset()
		Do ..SeedEarlier()
		Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer($Piece(case, "|", 2, *))))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""password""]}", "a password "_$Piece(case, "|", 1)_" is refused, naming password")
		Do ..AssertUntouched("a password "_$Piece(case, "|", 1))
	}
	Do ..Reset()
	Do ..SeedEarlier()
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer($Translate($Justify("", 256), " ", "p"))))
	Do $$$AssertEquals(result.Outcome, "done", "a password of exactly 256 characters is accepted")
}

/// A body that is not an object, an array, or a field that the form does not have is refused and changes nothing.
Method TestRefusedBodies()
{
	Set cases = $ListBuild("[]", "[1]", """text""", "5", "null", "{}", "{""address"": ""zzowner@example.com"", ""incoming"": ""pop.example.com"", ""user"": ""u"", ""extra"": 1}", "not json")
	Set position = 0
	While $ListNext(cases, position, text) {
		Do ..Reset()
		Do ..SeedEarlier()
		Set result = ..SaveText(text)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", text_" is refused")
		Do ..AssertUntouched(text)
	}
}

/// Matrix row 5: the online demo refuses with the accepted sentence, takes nothing and writes nothing.
Method TestOnlineDemo()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set secret = ..Secret("demo")
	Set uri = ..Offer(secret)
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, uri))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|"_..#UNAVAILABLE, "the save is not available, with the accepted sentence")
	Do $$$AssertEquals(..Row("email.address")_"|"_..Row("email.owner"), "|", "no key is written")
	Do $$$AssertEquals($Data(^||OcuTalonSettingsEmailProbe("cred"))_"|"_$Data(^||OcuTalonSettingsEmailProbe("sds"))_"|"_$Get(^||OcuTalonSettingsEmailProbe("calls"), 0), "0|0|0", "no credential, row or update")
	Do $$$AssertEquals(..Audits().%Size(), 0, "nothing is audited")
	Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(left = secret), "1|1", "the hand-off was not touched")
	Kill left
	Set channels = ..Values().sections.%IsDefined("channels")
	Do $$$AssertEquals(channels, 0, "the page's values have no channels section")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do $$$AssertEquals(..Values().sections.%IsDefined("channels"), 1, "and have one on a local install")
}

/// Matrix row 6: a second admin's save moves the mailbox to that session.
Method TestOtherAdminSaves()
{
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("first"))))
	Do ..Clear()
	Set result = ..SaveText(..Body(..#ADDRESS, ..#HOST, ..#USER, "").%ToJSON(), ..#OTHERREF)
	Do $$$AssertEquals(result.Outcome, "done", "the second admin's save is done")
	Do $$$AssertEquals(..Row("email.owner"), ..#OTHERREF, "email.owner is the second admin's session")
	Set audits = ..Audits()
	Do $$$AssertEquals(audits.%Size(), 1, "one audit entry")
	Do $$$AssertEquals(audits.%Get(0).setting_"|"_audits.%Get(0).from_"|"_audits.%Get(0).to_"|"_audits.%Get(0).sessionRef, "email.owner|"_..#REF_"|"_..#OTHERREF_"|"_..#OTHERREF, "the owner moves from the first Ref to the second")
}

/// Matrix row 7: a reference that names no offered secret is refused.
Method TestHandOffLost()
{
	Do ..SeedEarlier()
	Set none = "secret://handoff/00000000000000000000000000000000"
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, none))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""password""]}", "a reference that was never offered is refused naming password")
	Do ..AssertUntouched("a reference that was never offered")
	Set uri = ..Offer(..Secret("lost"))
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .taken)
	Kill taken
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, uri))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""password""]}", "so is one that was taken already")
	Do ..AssertUntouched("a reference that was taken already")
}

/// The same save again changes nothing but still runs the production update (DW-1139): the items start when an earlier update never ran.
Method TestNothingChanged()
{
	Do ..Save(..Body(..#ADDRESS, ..#HOST_":1995", ..#USER, ..Offer(..Secret("same")), ..#SMTPHOST))
	Do ..Clear()
	Set result = ..Save({"address": (..#ADDRESS), "incoming": (..#HOST_":1995"), "outgoing": (..#SMTPHOST), "user": (..#USER)})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the same values again are done")
	Do $$$AssertEquals(..Audits().%Size(), 0, "no audit entry")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsEmailProbe("calls"), 0), 1, "one call: no credential and no row is written")
	Do $$$AssertEquals(..Count("start"), 1, "and it is the production update, which starts an item that is not running")
	Do ..Reset()
	Set result = ..Save({"address": "bad", "incoming": (..#HOST), "user": (..#USER)})
	Do $$$AssertEquals(result.Outcome, "refused", "a refused save")
	Do $$$AssertEquals(..Count("start"), 0, "updates nothing")
}

/// Story 21.6, matrix row 1: the first save with an outgoing server writes the rows of EmailOut and audits email.outgoing.
Method TestOutgoingFirstSave()
{
	Set secret = ..Secret("out")
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST_":1995", ..#USER, ..Offer(secret), ..#SMTPHOST))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a first save with an outgoing server is done")
	Do $$$AssertEquals(..Rows("EmailOut"), "SMTPServer=smtp.example.com;SMTPPort=587;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient*;SSLCheckServerIdentity=1;Enabled=1", "the rows of EmailOut: port 587, the same credential, STARTTLS, the identity checked")
	Do $$$AssertEquals(..Rows(), "POP3Server=pop.example.com;POP3Port=1995;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;Enabled=1", "the rows of EmailIn are written as before")
	Do $$$AssertEquals(..Count("start"), 1, "the production is updated once")
	Set audits = ..Audits()
	Set forms = ""
	For i = 0:1:audits.%Size() - 1 {
		Set one = audits.%Get(i)
		Set forms = forms_$Select(forms = "": "", 1: ";")_one.setting_"|"_one.from_"|"_one.to
	}
	Do $$$AssertEquals(forms [ ";email.outgoing||smtp.example.com;", 1, "email.outgoing is audited from nothing to the host (port 587 is not shown)")
	Do $$$AssertEquals(..AuditText() [ secret, 0, "no audit entry holds the password")
	Do ..Clear()
	Set result = ..Save({"address": (..#ADDRESS), "incoming": (..#HOST_":1995"), "outgoing": (..#SMTPHOST), "user": (..#USER)})
	Do $$$AssertEquals(..Audits().%Size()_"|"_..Count("sds"), "0|0", "the same save again writes no row and no audit entry")
}

/// Story 21.6: the SSLConfig of EmailOut follows the port: 465 implicit TLS, any other port STARTTLS; there is no plain choice.
Method TestSmtpTlsFollowsThePort()
{
	Set cases = $ListBuild("smtp.example.com|smtp.example.com|587|OcuTalonClient*", "smtp.example.com:465|smtp.example.com|465|OcuTalonClient", "SMTP.Example.COM:25|smtp.example.com|25|OcuTalonClient*", "smtp.example.com:587|smtp.example.com|587|OcuTalonClient*", "smtp.example.com:2525|smtp.example.com|2525|OcuTalonClient*", "smtp.example.com:65535|smtp.example.com|65535|OcuTalonClient*")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Reset()
		Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("smtptls")), $Piece(case, "|", 1)))
		Do $$$AssertEquals(result.Outcome, "done", $Piece(case, "|", 1)_" is saved")
		Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SMTPServer")_"|"_^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SMTPPort")_"|"_^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SSLConfig"), $Piece(case, "|", 2, 4), $Piece(case, "|", 1)_": server, port and SSLConfig")
		Do $$$AssertEquals(^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SSLCheckServerIdentity"), 1, $Piece(case, "|", 1)_": the server identity is checked")
	}
}

/// Story 21.6, matrix row 3: a cleared or absent outgoing server disables EmailOut and deletes the server rows; the mailbox stays.
Method TestOutgoingCleared()
{
	For shape = "omitted", "empty" {
		Do ..Reset()
		Set secret = ..Secret("clear")
		Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(secret), ..#SMTPHOST_":465"))
		Do ..Clear()
		Set body = ..Body(..#ADDRESS, ..#HOST, ..#USER, "")
		If shape = "empty" Do body.%Set("outgoing", "", "string")
		Set result = ..Save(body)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a save with the outgoing server "_shape_" is done")
		Do $$$AssertEquals(..Rows("EmailOut"), "Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;SSLCheckServerIdentity=1;Enabled=0", "outgoing "_shape_": EmailOut is disabled and the server rows are deleted")
		Do $$$AssertEquals(..Rows(), "POP3Server=pop.example.com;POP3Port=995;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;Enabled=1", "outgoing "_shape_": the mailbox rows are untouched")
		Set audits = ..Audits()
		Do $$$AssertEquals(audits.%Size()_"|"_audits.%Get(0).setting_"|"_audits.%Get(0).from_"|"_audits.%Get(0).to, "1|email.outgoing|smtp.example.com:465|", "outgoing "_shape_": audited from the host to nothing")
		Do $$$AssertEquals(..Count("start"), 1, "outgoing "_shape_": the production is updated")
		Do ..Clear()
		Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ""))
		Do $$$AssertEquals(..Audits().%Size()_"|"_..Count("sds")_"|"_..Count("deleteSds"), "0|0|0", "outgoing "_shape_": cleared again, nothing is written")
	}
	Do ..Reset()
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("none"))))
	Do $$$AssertEquals(..Rows("EmailOut"), "", "with no SMTP server ever saved, no row of EmailOut is written")
}

/// Story 21.6: the outgoing audit entry names host or host:port off 587, from and to.
Method TestOutgoingAudit()
{
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("audit")), ..#SMTPHOST))
	Do ..Clear()
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, "", "mail.example.org:465"))
	Set audits = ..Audits()
	Do $$$AssertEquals(audits.%Size()_"|"_audits.%Get(0).setting_"|"_audits.%Get(0).from_"|"_audits.%Get(0).to, "1|email.outgoing|smtp.example.com|mail.example.org:465", "a changed outgoing server is one entry, from the host to host:port")
	Do $$$AssertEquals(..Rows("EmailOut"), "SMTPServer=mail.example.org;SMTPPort=465;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;SSLCheckServerIdentity=1;Enabled=1", "and the rows follow, with implicit TLS on 465")
	Do ..Clear()
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, "", "mail.example.org:587"))
	Set audits = ..Audits()
	Do $$$AssertEquals(audits.%Get(0).from_"|"_audits.%Get(0).to, "mail.example.org:465|mail.example.org", "back on port 587 the entry shows the host alone")
}

/// A failed audit write or key write changes nothing; a failure after the keys puts everything back.
Method TestAllOrNothing()
{
	For at = 1:1:5 {
		Do ..Reset()
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt") = at
		Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("audit"))))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "audit write "_at_" fails: not_audited")
		Do $$$AssertEquals(..Row("email.address")_"|"_..Row("email.owner"), "|", "audit write "_at_": the keys are rolled back")
		Do $$$AssertEquals($Data(^||OcuTalonSettingsEmailProbe("cred"))_"|"_$Get(^||OcuTalonSettingsEmailProbe("calls"), 0), "0|0", "audit write "_at_": no credential, row or update")
	}
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "apply") = "error"
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ..Offer(..Secret("apply"))))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a failed key write is failed")
	Do $$$AssertEquals(..Row("email.address")_"|"_..Row("email.owner")_"|"_$Get(^||OcuTalonSettingsEmailProbe("calls"), 0), "||0", "and changes nothing")
	Set stages = $ListBuild("credential|credential|error", "row|sds|error", "third row|sdsAt|3", "outgoing row|sdsAt|6", "update|start|error")
	Set position = 0
	While $ListNext(stages, position, stage) {
		For earlier = 0, 1 {
			Do ..Reset()
			If earlier Do ..SeedEarlier()
			Set ^OcuTalonTest("SettingsEmailProbe", "answer", $Piece(stage, "|", 2)) = $Piece(stage, "|", 3)
			Set was = ..State()
			Set result = ..Save(..Body("zznew@example.com", "new.example.com:110", "zznewuser", ..Offer(..Secret("fail")), "new.smtp.example.com:465"))
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a failed "_$Piece(stage, "|", 1)_" (earlier mailbox "_earlier_") is failed")
			Kill ^OcuTalonTest("SettingsEmailProbe", "answer")
			Do $$$AssertEquals(..State(), was, "a failed "_$Piece(stage, "|", 1)_" (earlier mailbox "_earlier_"): keys, credential and rows are as they were")
			Do $$$AssertEquals(..Audits().%Size() > 5, 1, "a failed "_$Piece(stage, "|", 1)_": the keys put back are audited too")
		}
	}
}

/// The page's channels: address, incoming, user and passwordSet, never the password.
Method TestValues()
{
	Set before = ..Values().sections.channels
	Do $$$AssertEquals(before.%ToJSON(), "{""address"":"""",""incoming"":"""",""outgoing"":"""",""user"":"""",""passwordSet"":false}", "before a save the channels are empty")
	Set secret = ..Secret("values")
	Do ..Save(..Body(..#ADDRESS, ..#HOST_":1995", ..#USER, ..Offer(secret), ..#SMTPHOST_":465"))
	Set values = ..Values()
	Do $$$AssertEquals(values.sections.channels.%ToJSON(), "{""address"":"""_..#ADDRESS_""",""incoming"":""pop.example.com:1995"",""outgoing"":""smtp.example.com:465"",""user"":"""_..#USER_""",""passwordSet"":true}", "after a save they show the saved values and that a password is set")
	Do $$$AssertEquals(values.%ToJSON() [ secret, 0, "and never the password")
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, ""))
	Do $$$AssertEquals(..Values().sections.channels.incoming_"|"_..Values().sections.channels.outgoing, ..#HOST_"|", "a server on the default port is shown without it, and a cleared outgoing server is empty")
	Do ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, "", ..#SMTPHOST_":587"))
	Do $$$AssertEquals(..Values().sections.channels.outgoing, ..#SMTPHOST, "an outgoing server on port 587 is shown without it")
}

/// After a save the password is in no audit entry, no ^OcuTalon* global and no Ens.Util.Log row.
Method TestNoSecretAnywhere()
{
	Set secret = ..Secret("nowhere")
	Set uri = ..Offer(secret)
	Do $$$AssertEquals(uri [ secret, 0, "the reference does not hold the password")
	Set result = ..Save(..Body(..#ADDRESS, ..#HOST, ..#USER, uri))
	Do $$$AssertEquals(result.Outcome, "done", "the save is done")
	Do $$$AssertEquals(..AuditText() [ secret, 0, "no audit entry holds the password")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(secret), "", "no ^OcuTalon* global holds it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", secret), 0, "no Ens.Util.Log row holds it")
	Do $$$AssertEquals(result.Message_result.Data [ secret, 0, "and the answer does not")
}

/// --- helpers ---

/// A password that no other text holds.
ClassMethod Secret(tag As %String) As %String
{
	Quit "zzsecretemail"_tag_$Job_$Random(1000000)
}

/// Offers the secret to the hand-off and answers its reference, kept for Reset to discard.
Method Offer(secret As %String) As %String [ Private ]
{
	Set sc = ##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri)
	Do $$$AssertStatusOK(sc, "the secret is offered")
	Set ..Uris = ..Uris_$ListBuild(uri)
	Quit uri
}

/// The body of a valid save; the password member is the reference, or left out when it is "".
ClassMethod Body(address As %String, incoming As %String, user As %String, uri As %String, outgoing As %String = "") As %DynamicObject [ Private ]
{
	Set body = {"address": (address), "incoming": (incoming), "user": (user)}
	If outgoing '= "" Do body.%Set("outgoing", outgoing, "string")
	If uri '= "" Do body.%Set("password", uri, "string")
	Quit body
}

/// Sets, in the body, the member from the JSON text of its value; "<missing>" removes it.
ClassMethod Put(body As %DynamicObject, name As %String, json As %String) [ Private ]
{
	If json = "<missing>" {
		Do body.%Remove(name)
		Quit
	}
	Set holder = {}.%FromJSON("{""v"": "_json_"}")
	Do body.%Set(name, holder.v, holder.%GetTypeOf("v"))
}

/// The page's body as the probe reads it.
ClassMethod Values() As %DynamicObject [ Private ]
{
	Quit $ClassMethod(..#PROBE, "Values")
}

/// A SaveSettings of the channels section from the body (a dynamic object).
Method Save(body As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText(body.%ToJSON())
}

/// A SaveSettings of the channels section with the text as its changes, from web_admin for zzadmin and the session, sent to the probe.
Method SaveText(text As %String, ref As %String = {..#REF}) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "channels"
	Set command.Changes = text
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ref
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The value of the product key, from its row.
ClassMethod Row(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The settings rows of the item (EmailIn, or EmailOut) that the probe holds, as "name=value;..." in the order of the item's rows, the absent ones left out.
ClassMethod Rows(item As %String = "EmailIn") As %String [ Private ]
{
	Set out = ""
	For name = "POP3Server", "POP3Port", "SMTPServer", "SMTPPort", "Credentials", "SSLConfig", "SSLCheckServerIdentity", "Enabled" {
		If $Data(^||OcuTalonSettingsEmailProbe("sds", item, name)) Set out = out_$Select(out = "": "", 1: ";")_name_"="_^||OcuTalonSettingsEmailProbe("sds", item, name)
	}
	Quit out
}

/// The number of recorded calls of the probe whose text starts with the word.
ClassMethod Count(word As %String) As %Integer [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonSettingsEmailProbe("calls", n), 1, text)
		Quit:n=""
		If $Piece(text, "|", 1) = word Set count = count + 1
	}
	Quit count
}

/// The data of the audit writes that the probe saw, in order, as a dynamic array.
ClassMethod Audits() As %DynamicArray [ Private ]
{
	Set audits = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit" Do audits.%Push({}.%FromJSON(^OcuTalonTest("SettingsOpsProbe", "calls", n, "data")))
	}
	Quit audits
}

/// All the audit data as one text.
ClassMethod AuditText() As %String [ Private ]
{
	Quit ..Audits().%ToJSON()
}

/// The state that a failed save must leave as it was: the two keys, the credential and the rows, as one text.
ClassMethod State() As %String [ Private ]
{
	Quit ..Row("email.address")_"|"_..Row("email.owner")_"|"_$Get(^||OcuTalonSettingsEmailProbe("cred"))_"|"_..Rows()_"|"_..Rows("EmailOut")
}

/// An earlier mailbox: the keys, the credential and the rows of a save by another session.
Method SeedEarlier() [ Private ]
{
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "zzearlier@example.com")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", ..#OTHERREF)
	Do $ClassMethod(..#PROBE, "Seed", "zzearlier", "zzearlierpw", "old.example.com", 995, "old.smtp.example.com", 587)
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "Credentials") = "OcuTalonMail"
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "SSLConfig") = "OcuTalonClient"
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "Credentials") = "OcuTalonMail"
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SSLConfig") = "OcuTalonClient*"
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SSLCheckServerIdentity") = 1
}

/// Asserts that a refused save left the earlier mailbox as it was: the keys, the credential, the rows, no update and no audit entry.
Method AssertUntouched(what As %String) [ Private ]
{
	Do $$$AssertEquals(..Row("email.address")_"|"_..Row("email.owner"), "zzearlier@example.com|"_..#OTHERREF, what_": the keys are as they were")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsEmailProbe("cred")), $ListBuild("zzearlier", "zzearlierpw"), what_": the credential is as it was")
	Do $$$AssertEquals(..Rows(), "POP3Server=old.example.com;POP3Port=995;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient;Enabled=1", what_": the rows are as they were")
	Do $$$AssertEquals(..Rows("EmailOut"), "SMTPServer=old.smtp.example.com;SMTPPort=587;Credentials=OcuTalonMail;SSLConfig=OcuTalonClient*;SSLCheckServerIdentity=1;Enabled=1", what_": the rows of EmailOut are as they were")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsEmailProbe("calls"), 0), 0, what_": nothing is written and EmailIn is not updated")
	Do $$$AssertEquals(..Audits().%Size(), 0, what_": nothing is audited")
}

/// Clears what the probe recorded, not the state it holds.
Method Clear() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe", "calls")
	Kill ^||OcuTalonSettingsEmailProbe("calls")
	Kill ^||OcuTalonSettingsEmailProbe("writes")
	Kill ^||OcuTalonSettingsOpsProbe
}

/// Discards the references still offered and puts everything back to a mailbox-less start.
Method Reset() [ Private ]
{
	Set position = 0
	While $ListNext(..Uris, position, uri) {
		Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .discard, 0)
		Kill discard
	}
	Set ..Uris = ""
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Kill ^OcuTalonTest("SettingsEmailProbe")
	Kill ^||OcuTalonSettingsEmailProbe
	Kill ^||OcuTalonSettingsOpsProbe
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
}

}
