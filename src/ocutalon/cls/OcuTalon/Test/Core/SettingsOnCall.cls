/// Tests of the on-call section of OcuTalon.Core.SettingsOps (Story 36.4; AD-1, AD-13, AD-19), called on a shadow instance of OcuTalon.Test.Core.SettingsOpsProbe,
/// whose audit write is a recording seam, with the section's body in a real SecretHandoff, as the route offers it. Safe on a slot: no production runs.
/// The rows of the seven oncall.* keys, the online-demo flag and the fixture sessions and pairings are put back after each test.
///   - TestNobody: nobody is stored as "", "" and telegram,email, whatever its other members hold;
///   - TestSavedCases: a user with a paired chat, a user without one by email, a person by email, the by-email address trimmed, and the minutes 1, 1440 and "15"
///     are saved as sent, with the user cleared for a person by email;
///   - TestUserNameKeepsTheRostersSpelling: a user typed in another case is matched and stored as the Data.Session row holds the name;
///   - TestUserNameSpellingIsStableAcrossSaves: the same user typed in another case is "nothing changed" (no row, no audit entry);
///   - TestUserNameOverTheBoundIsRefused: a roster user name over ONCALLUSERMAX is refused as <role>User, one of exactly the bound is saved;
///   - TestAddressLengthBound: an address of 254 characters is saved and one of 255 is refused as <role>Email;
///   - TestTelegramNeedsAPairedChat: telegram is refused for a user whose sessions have no paired chat and for a person by email, and accepted for a paired one;
///   - TestRefusals: each refused value names its field, and nothing is written or audited (the minutes, the user, the address, the channels, the shape);
///   - TestSaveAuditsEachChangeWithItsValues: each changed key has its Settings audit entry with from and to, the admin's user, the session and the web channel,
///     written before its row, and a second save audits only what changed;
///   - TestNothingChanged: the stored values again write no row and no audit entry;
///   - TestOnlineDemo: with the flag set the save is not_available with the accepted text, the handoff is gone and nothing is written; Values has no on-call member;
///   - TestHandoffMissing: a handoff with nothing behind it is failed, and Changes that are not exactly the handoff are refused, so that no body is read from them;
///   - TestValues: the on-call member's shape, defaults, stored values, users (sorted, once, with paired) and pagesBuilt;
///   - TestTextOffOnDemo: the off-on-demo text is the accepted one, verbatim;
///   - TestUsersComeFromTheVerb (DW-1278): Values asks for the users with one ListOnCallUsers of origin web_admin, the production job's handler answers Ok 1 listed with only
///     {"handoff": uri} in Data (no user name in it), the web process takes the handoff once, and the users are the fixture users, once each, sorted, with paired;
///   - TestUsersFailureIsEmpty (DW-1278): a submit that fails, throws, is busy or has no handoff, and a handoff that is not JSON, not an array or holds a bad row, each give
///     users [] with the rest of the member intact, and every handoff that the case made is taken and gone;
///   - TestOnlineDemoAsksNoOne (DW-1278): on the online demo Values submits nothing, and a ListOnCallUsers that reaches the handler is not_available with no handoff;
///   - TestRosterNotReadInTheWebProcess (DW-1278): the source of Values, OnCallValues, OnCallRoster and SubmitRoster holds no walk over the session or pairing storage, no
///     %OpenId and no call of OnCallUsers.
Class OcuTalon.Test.Core.SettingsOnCall Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

Parameter REF = "zzsession0123456789abc";

/// The seven keys, in the order of the section's fields.
Parameter KEYS = "oncall.primary.user,oncall.primary.email,oncall.primary.channels,oncall.backup.user,oncall.backup.email,oncall.backup.channels,oncall.escalationMinutes";

/// The online-demo flag before the test.
Property SavedOnline As %String;

/// The unique part of the fixture user names of the test.
Property Tag As %String;

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsOnCall")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("SettingsOnCall", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ..Clear()
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..Tag = $Random(1000000000)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clear()
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If $Data(^OcuTalonTest("SettingsOnCall", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Kill ^OcuTalonTest("SettingsOnCall")
	Quit $$$OK
}

Method TestNobody()
{
	Set body = ..Body(..Role("nobody", "zz ignored", "not an address", "sms"), ..Role("nobody", "", "", ""), 15)
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "nobody is saved whatever its other members hold")
	Do $$$AssertEquals(..Rows(), 0, "and is stored as the defaults, so that no row is written")
	Do $$$AssertEquals(..Audits(), 0, "or audited")
	Do $$$AssertEquals(..OnCallValue("primaryUser")_"|"_..OnCallValue("primaryEmail")_"|"_..OnCallValue("primaryChannels"), "||telegram,email", "Values reads nobody as '', '' and telegram,email")
	Set user = ..User("a", 1)
	Do ..Save(..Body(..Role("user", user, "a@x.io", "telegram"), ..Role("nobody", "", "", ""), 15))
	Do $$$AssertEquals(..Row("oncall.primary.user")_"|"_..Row("oncall.primary.email")_"|"_..Row("oncall.primary.channels"), user_"|a@x.io|telegram", "a person is stored")
	Set result = ..Save(..Body(..Role("nobody", user, "a@x.io", "telegram"), ..Role("nobody", "", "", ""), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "choosing nobody again is done")
	Do $$$AssertEquals(..Row("oncall.primary.user")_"|"_..Row("oncall.primary.email")_"|"_..Row("oncall.primary.channels"), "||telegram,email", "and puts back '', '' and telegram,email")
}

Method TestSavedCases()
{
	Set paired = ..User("p", 1), unpaired = ..User("u", 0)
	Set result = ..Save(..Body(..Role("user", paired, "a@x.io", "telegram,email"), ..Role("email", "", "b@x.io", "email"), 20))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a user with a paired chat and a person by email are saved")
	Do $$$AssertEquals(..OnCallValue("primaryUser")_"|"_..OnCallValue("primaryEmail")_"|"_..OnCallValue("primaryChannels"), paired_"|a@x.io|telegram,email", "the user is stored as sent")
	Do $$$AssertEquals(..Row("oncall.backup.user")_"|"_..Row("oncall.backup.email")_"|"_..Row("oncall.backup.channels")_"|"_..Row("oncall.escalationMinutes"), "|b@x.io|email|20", "the person by email has no user")
	Set result = ..Save(..Body(..Role("user", paired, "a@x.io", "telegram,email"), ..Role("email", unpaired, "d@x.io", "email"), 20))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a person by email whose user member names a user is saved")
	Do $$$AssertEquals(..Row("oncall.backup.user")_"|"_..Row("oncall.backup.email"), "|d@x.io", "with the user cleared, not stored")
	Do ..Reset()
	Set result = ..Save(..Body(..Role("user", unpaired, "", "email"), ..Role("email", "", "  c@x.io ", "email"), 20))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "a user without an address cannot be paged by email")
	Do $$$AssertEquals(..Fields(result), "primaryChannels", "and the channels are named")
	Set result = ..Save(..Body(..Role("user", unpaired, "a@x.io", "email"), ..Role("email", "", "  c@x.io ", "email"), 20))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an unpaired user with an address, paged by email only, is saved")
	Do $$$AssertEquals(..Row("oncall.backup.email"), "c@x.io", "the address is trimmed")
	For minutes = 1, 1440, "s:15", "s:007" {
		Do ..Reset()
		Set result = ..Save(..Body(..Role("nobody", "", "", ""), ..Role("nobody", "", "", ""), minutes))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", minutes_" minutes are accepted, as a number or as a text")
	}
	Do ..Reset()
	Do ..Save(..Body(..Role("nobody", "", "", ""), ..Role("nobody", "", "", ""), "1440"))
	Do $$$AssertEquals(..Row("oncall.escalationMinutes"), "1440", "a whole number of minutes is stored as a number's text")
	Do ..Save(..Body(..Role("nobody", "", "", ""), ..Role("nobody", "", "", ""), 1))
	Do $$$AssertEquals(..Row("oncall.escalationMinutes"), "1", "and so is the least")
}

Method TestUserNameKeepsTheRostersSpelling()
{
	Set user = "zzOc"_..Tag_"MixedCase"
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set typed = $ZConvert(user, "L")
	Do $$$AssertTrue(typed '= user, "the typed name differs from the roster's spelling")
	Set result = ..Save(..Body(..Role("user", " "_typed_" ", "a@x.io", "email"), ..Role("user", $ZConvert(user, "U"), "b@x.io", "email"), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a user typed in another case is matched")
	Do $$$AssertEquals(..Row("oncall.primary.user")_"|"_..Row("oncall.backup.user"), user_"|"_user, "and stored as the Data.Session row holds the name, for both roles")
	Do $$$AssertEquals(..AuditData(1).to, user, "and the audit entry holds the same spelling")
}

/// (QA) Saving the user again in another case is "nothing changed": the stored spelling is the roster's, so no row is written and no audit entry is made.
Method TestUserNameSpellingIsStableAcrossSaves()
{
	Set user = "zzOc"_..Tag_"Stable"
	Do ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set nobody = ..Role("nobody", "", "", "")
	Set result = ..Save(..Body(..Role("user", $ZConvert(user, "L"), "a@x.io", "email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a user typed in lower case is saved")
	Do $$$AssertEquals(..Row("oncall.primary.user"), user, "with the roster's spelling")
	Do ..Reset()
	Set rows = ..Rows()
	Set stamp = ##class(OcuTalon.Data.Setting).KeyIndexOpen("oncall.primary.user").UpdatedAt
	Set result = ..Save(..Body(..Role("user", $ZConvert(user, "U"), "a@x.io", "email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the same user typed in upper case is done")
	Do $$$AssertEquals(..Audits()_"|"_..Rows(), "0|"_rows, "and changes nothing: no audit entry, no new row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("oncall.primary.user").UpdatedAt, stamp, "and the user row is not written again")
	Do $$$AssertEquals(..Row("oncall.primary.user"), user, "the stored spelling stays the roster's")
}

/// (QA) A user name over ONCALLUSERMAX is refused as <role>User even when a roster row holds it (the guard is a refusal without a lookup), and a name of exactly the
/// bound is accepted. No Data.Session name can exceed its MAXLEN through %Save, so the long row is made with an UPDATE %NOCHECK.
Method TestUserNameOverTheBoundIsRefused()
{
	Set limit = $Parameter("OcuTalon.Core.SettingsOps", "ONCALLUSERMAX")
	Set exact = "zzoc"_..Tag_$Translate($Justify("", limit - $Length("zzoc"_..Tag)), " ", "x")
	Set over = exact_"y"
	Do $$$AssertEquals($Length(exact)_"|"_$Length(over), limit_"|"_(limit + 1), "the two names are the bound and one more")
	Do ##class(OcuTalon.Test.Data.Fixture).Session(exact)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzoc"_..Tag_"short")
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("UPDATE %NOCHECK OcuTalon_Data.Session SET IrisUser = ? WHERE Ref = ?"), "the long row is prepared")
	Set rs = statement.%Execute(over, ref)
	Do $$$AssertEquals(rs.%SQLCODE, 0, "and made: the roster holds a user name over the bound")
	Set found = ""
	Set iterator = ..Page().sections.%Get("on-call").users.%GetIterator()
	While iterator.%GetNext(, .one) {
		If (one.user = exact) || (one.user = over) Set found = found_$ListBuild($Length(one.user))
	}
	Do $$$AssertEquals($ListToString(found), limit_","_(limit + 1), "both names are in the roster")
	Set nobody = ..Role("nobody", "", "", "")
	Set result = ..Save(..Body(..Role("user", over, "a@x.io", "email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|primaryUser", "a roster user over the bound is refused as a primary user")
	Set result = ..Save(..Body(nobody, ..Role("user", over, "a@x.io", "email"), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|backupUser", "and as a backup user")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing was written or audited")
	Set result = ..Save(..Body(..Role("user", exact, "a@x.io", "email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a roster user of exactly the bound is saved")
	Do $$$AssertEquals(..Row("oncall.primary.user"), exact, "and stored")
}

/// (QA) An address of 254 characters is accepted and one of 255 is refused as <role>Email (the matrix's "at most 254 characters"), each with a valid local part and domain.
Method TestAddressLengthBound()
{
	Set local = $Translate($Justify("", 64), " ", "a")
	Set domain = $Translate($Justify("", 63), " ", "b")_"."_$Translate($Justify("", 63), " ", "b")_"."_$Translate($Justify("", 57), " ", "b")_".com"
	Set exact = local_"@"_domain
	Set over = local_"@"_$Piece(domain, ".", 1, 2)_"."_$Translate($Justify("", 58), " ", "b")_".com"
	Do $$$AssertEquals($Length(exact)_"|"_$Length(over), "254|255", "the two addresses are 254 and 255 characters long")
	Set nobody = ..Role("nobody", "", "", "")
	Set result = ..Save(..Body(..Role("email", "", over, "email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|primaryEmail", "an address of 255 characters is refused")
	Set result = ..Save(..Body(nobody, ..Role("email", "", " "_exact_" ", "email"), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "an address of 254 characters is saved, trimmed")
	Do $$$AssertEquals(..Row("oncall.backup.email"), exact, "and stored whole")
}

Method TestTelegramNeedsAPairedChat()
{
	Set paired = ..User("p", 1), unpaired = ..User("u", 0)
	Set both = ..User("b", 0)
	Do ##class(OcuTalon.Test.Data.Fixture).Pairing(##class(OcuTalon.Test.Data.Fixture).Session(both))
	Set nobody = ..Role("nobody", "", "", "")
	Set result = ..Save(..Body(..Role("user", unpaired, "a@x.io", "telegram"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|primaryChannels", "telegram is refused for a user whose session has no paired chat")
	Set result = ..Save(..Body(..Role("user", unpaired, "a@x.io", "telegram,email"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|primaryChannels", "and so is telegram with email")
	Set result = ..Save(..Body(nobody, ..Role("email", "", "a@x.io", "telegram"), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|backupChannels", "telegram is refused for a person by email")
	Set result = ..Save(..Body(nobody, ..Role("email", "", "a@x.io", "telegram,email"), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|backupChannels", "even with email")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing was written or audited")
	Set result = ..Save(..Body(..Role("user", paired, "", "telegram"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "telegram is accepted for a user with a paired chat, with no address")
	Do $$$AssertEquals(..Row("oncall.primary.channels"), "telegram", "and stored")
	Set result = ..Save(..Body(..Role("user", both, "", "telegram"), nobody, 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a user is paired when any one of their sessions is")
}

Method TestRefusals()
{
	Set paired = ..User("p", 1), unpaired = ..User("u", 0)
	Set nobody = ..Role("nobody", "", "", "")
	Set cases = $ListBuild(
		$ListBuild("an unknown user", ..Body(..Role("user", "zzoc-nobody-"_..Tag, "a@x.io", "telegram,email"), nobody, 15).%ToJSON(), "primaryUser"),
		$ListBuild("a user that is blank", ..Body(..Role("user", "", "a@x.io", "email"), nobody, 15).%ToJSON(), "primaryUser"),
		$ListBuild("a backup user that is unknown", ..Body(nobody, ..Role("user", "zzoc-nobody-"_..Tag, "", "email"), 15).%ToJSON(), "backupUser"),
		$ListBuild("a user name of 600 characters", ..Body(..Role("user", $Translate($Justify("", 600), " ", "a"), "a@x.io", "email"), nobody, 15).%ToJSON(), "primaryUser"),
		$ListBuild("a backup user name of 9000 characters", ..Body(nobody, ..Role("user", $Translate($Justify("", 9000), " ", "a"), "", "email"), 15).%ToJSON(), "backupUser"),
		$ListBuild("a by-email person with no address", ..Body(..Role("email", "", "", "email"), nobody, 15).%ToJSON(), "primaryEmail"),
		$ListBuild("a by-email person with a bad address", ..Body(nobody, ..Role("email", "", "nope", "email"), 15).%ToJSON(), "backupEmail"),
		$ListBuild("a user with a bad address", ..Body(..Role("user", paired, "nope@", "telegram"), nobody, 15).%ToJSON(), "primaryEmail"),
		$ListBuild("an address with a space", ..Body(..Role("email", "", "a b@x.io", "email"), nobody, 15).%ToJSON(), "primaryEmail"),
		$ListBuild("an address whose local part is over 64 characters", ..Body(..Role("email", "", $Translate($Justify("", 250), " ", "a")_"@x.io", "email"), nobody, 15).%ToJSON(), "primaryEmail"),
		$ListBuild("email chosen with no address", ..Body(..Role("user", paired, "", "email"), nobody, 15).%ToJSON(), "primaryChannels"),
		$ListBuild("no channel", ..Body(..Role("user", paired, "a@x.io", ""), nobody, 15).%ToJSON(), "primaryChannels"),
		$ListBuild("a channel that is not one", ..Body(..Role("user", paired, "a@x.io", "sms"), nobody, 15).%ToJSON(), "primaryChannels"),
		$ListBuild("a repeated channel", ..Body(nobody, ..Role("email", "", "a@x.io", "email,email"), 15).%ToJSON(), "backupChannels"),
		$ListBuild("channels in white space", ..Body(..Role("user", paired, "a@x.io", "telegram, email"), nobody, 15).%ToJSON(), "primaryChannels"),
		$ListBuild("minutes 0", ..Body(nobody, nobody, 0).%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes 1441", ..Body(nobody, nobody, 1441).%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes 15.5", ..Body(nobody, nobody, 15.5).%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes abc", ..Body(nobody, nobody, "abc").%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes empty", ..Body(nobody, nobody, "").%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes with spaces", ..Body(nobody, nobody, "s: 7 ").%ToJSON(), "escalationMinutes"),
		$ListBuild("minutes negative", ..Body(nobody, nobody, -1).%ToJSON(), "escalationMinutes"),
		$ListBuild("a person outside the three", ..Body(..Role("admin", "", "", ""), nobody, 15).%ToJSON(), "primaryUser"),
		$ListBuild("two refused fields", ..Body(..Role("email", "", "nope", "email"), nobody, 0).%ToJSON(), "primaryEmail,escalationMinutes"),
		$ListBuild("a setting reference in the user", ..Body(..Role("nobody", "@{x}", "", ""), nobody, 15).%ToJSON(), "primaryUser"),
		$ListBuild("a setting reference in the address", ..Body(nobody, ..Role("nobody", "", "a@{x}", ""), 15).%ToJSON(), "backupEmail"),
		$ListBuild("a setting reference in the channels", ..Body(..Role("nobody", "", "", "@{x}"), nobody, 15).%ToJSON(), "primaryChannels"),
		$ListBuild("a setting reference in the minutes", ..Body(nobody, nobody, "1@{x}").%ToJSON(), "escalationMinutes"))
	Set position = 0
	While $ListNext(cases, position, one) {
		Set result = ..SaveText($List(one, 2))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|"_$List(one, 3), $List(one, 1)_" is refused with its field named")
	}
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing was written or audited")
	Set shape = $ListBuild(
		$ListBuild("a missing member", ..Without(..Body(nobody, nobody, 15), "backupEmail").%ToJSON(), "backupEmail"),
		$ListBuild("a missing person", ..Without(..Body(nobody, nobody, 15), "primaryPerson").%ToJSON(), "primaryUser"),
		$ListBuild("a missing minutes member", ..Without(..Body(nobody, nobody, 15), "escalationMinutes").%ToJSON(), "escalationMinutes"),
		$ListBuild("an extra member", ..Extra(..Body(nobody, nobody, 15)).%ToJSON(), ""),
		$ListBuild("a user that is a number", ..Number(..Body(nobody, nobody, 15), "primaryUser").%ToJSON(), "primaryUser"),
		$ListBuild("a channel list that is null", ..Null(..Body(nobody, nobody, 15), "backupChannels").%ToJSON(), "backupChannels"))
	Set position = 0
	While $ListNext(shape, position, one) {
		Set result = ..SaveText($List(one, 2))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Fields(result), "0|refused|"_$List(one, 3), $List(one, 1)_" is refused")
	}
	Do $$$AssertEquals(..SaveText("[1,2]").Outcome_"|"_..SaveText("""text""").Outcome_"|"_..SaveText("").Outcome_"|"_..SaveText("{").Outcome, "refused|refused|refused|refused", "a body that is not an object is refused")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "and nothing was written or audited")
}

Method TestSaveAuditsEachChangeWithItsValues()
{
	Set paired = ..User("p", 1), unpaired = ..User("u", 0)
	Set result = ..Save(..Body(..Role("user", paired, "a@x.io", "telegram"), ..Role("user", unpaired, "b@x.io", "email"), 20))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the save is done")
	Do $$$AssertEquals(..Audits(), 7, "seven keys changed, seven audit entries")
	Set wanted = $ListBuild(
		$ListBuild("oncall.primary.user", "", paired),
		$ListBuild("oncall.primary.email", "", "a@x.io"),
		$ListBuild("oncall.primary.channels", "telegram,email", "telegram"),
		$ListBuild("oncall.backup.user", "", unpaired),
		$ListBuild("oncall.backup.email", "", "b@x.io"),
		$ListBuild("oncall.backup.channels", "telegram,email", "email"),
		$ListBuild("oncall.escalationMinutes", "15", "20"))
	For n = 1:1:7 {
		Set data = ..AuditData(n)
		Set one = $ListGet(wanted, n)
		Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, $List(one, 1)_"|"_$List(one, 2)_"|"_$List(one, 3), "entry "_n_" has the key, its value before and its value now")
		Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, "zzadmin|"_..#REF_"|web", "entry "_n_" names the admin, the session and the web channel")
		Do $$$AssertEquals(data.%Size(), 6, "entry "_n_" has exactly the six members of the Settings shape")
		Do $$$AssertEquals(..Row($List(one, 1)), $List(one, 3), "entry "_n_"'s row holds its value")
	}
	Do $$$AssertEquals(..OnCallValue("backupEmail")_"|"_..OnCallValue("escalationMinutes"), "b@x.io|20", "Values shows the saved values at once")
	Do ..Reset()
	Set result = ..Save(..Body(..Role("user", paired, "a@x.io", "telegram"), ..Role("user", unpaired, "c@x.io", "email"), 20))
	Do $$$AssertEquals(result.Outcome_"|"_..Audits(), "done|1", "a second save audits only what changed")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "oncall.backup.email|b@x.io|c@x.io", "with the stored value as from")
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set result = ..Save(..Body(..Role("nobody", "", "", ""), ..Role("nobody", "", "", ""), 25))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "an audit entry that cannot be written stops the save")
	Do $$$AssertEquals(..Row("oncall.escalationMinutes"), "20", "and the row is as it was")
}

Method TestNothingChanged()
{
	Set result = ..Save(..Body(..Role("nobody", "", "", ""), ..Role("nobody", "", "", ""), 15))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the defaults are done")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "with no row and no audit entry")
	Set user = ..User("p", 1)
	Do ..Save(..Body(..Role("user", user, "a@x.io", "telegram"), ..Role("nobody", "", "", ""), 30))
	Do ..Reset()
	Set result = ..Save(..Body(..Role("user", user, " a@x.io ", "telegram"), ..Role("nobody", "", "", ""), "s:30"))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the stored values again are done")
	Do $$$AssertEquals(..Audits(), 0, "and write no audit entry")
	Do $$$AssertEquals(..Row("oncall.primary.email")_"|"_..Row("oncall.escalationMinutes"), "a@x.io|30", "the stored values stay")
}

Method TestOnlineDemo()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..Body(..Role("email", "", "a@x.io", "email"), ..Role("nobody", "", "", ""), 20)
	Set uri = ..Handoff(body)
	Set result = ..Carry(..Command({"handoff": (uri)}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "on the online demo the save is not_available")
	Do $$$AssertEquals(result.Message, "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.", "with the accepted text")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "the handoff is gone")
	Do $$$AssertEquals(left, "", "and held nothing for anyone")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing was written or audited")
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("on-call"), 0, "Values has no on-call member")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "roster")), 0, "and submitted no ListOnCallUsers")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set values = ..Page()
	Do $$$AssertEquals(values.sections.%IsDefined("on-call"), 1, "and has one when the flag is off")
}

/// Values asks for the users with one ListOnCallUsers of origin web_admin; the handler in the production job answers Ok 1 listed with Data that is exactly {"handoff": uri}, so that
/// no user name is in the result, and the web process takes the list from the handoff, which is then gone. The users are each fixture user once, in the order of the upper-cased
/// names, paired when any one of their sessions has a paired chat.
Method TestUsersComeFromTheVerb()
{
	Set b = ..User("b", 0), a = ..User("a", 1)
	Set values = ..Page().sections.%Get("on-call")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "roster")), 1, "one ListOnCallUsers was submitted for the page")
	Set found = ""
	Set iterator = values.users.%GetIterator()
	While iterator.%GetNext(, .one) {
		Do $$$AssertEquals(one.%Size()_"|"_one.%GetTypeOf("user")_"|"_one.%GetTypeOf("paired"), "2|string|boolean", "each user has a name and a paired flag")
		If $Extract(one.user, 1, $Length("zzoc"_..Tag)) '= ("zzoc"_..Tag) Continue
		Set found = found_$ListBuild(one.user_"="_one.paired)
	}
	Do $$$AssertEquals($ListToString(found), a_"=1,"_b_"=0", "the fixture users come back through the verb, sorted, with paired")
	Set command = ##class(OcuTalon.Msg.Command.ListOnCallUsers).%New()
	Set result = ..Carry(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|listed|", "the handler answers Ok 1, listed")
	Do $$$AssertTrue($Match(result.Data, "^\{""handoff"":""secret://handoff/[0-9A-F]{32}""\}$"), "and its Data is exactly {""handoff"": uri}")
	Do $$$AssertTrue(result.Data '[ a, "no user name is in its Data")
	Do $$$AssertTrue(result.Data '[ b, "of either fixture user")
	Set uri = {}.%FromJSON(result.Data).handoff
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .text, 0), "the list is in the handoff")
	Do $$$AssertTrue(text [ a, "and names the fixture user")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .again, 0), "and is gone once taken")
	Do $$$AssertEquals(again, "", "leaving nothing")
}

/// A page whose users cannot be had is still the whole member: users [] and every other value as stored, and the handoff that a case made is gone.
Method TestUsersFailureIsEmpty()
{
	Set user = ..User("f", 1)
	Do ..Save(..Body(..Role("user", user, "a@x.io", "telegram"), ..Role("nobody", "", "", ""), 40))
	Set answers = $ListBuild("error", "throw", "busy", "nohandoff", "garbled", "notlist", "badrow", "shortrow")
	Set position = 0
	While $ListNext(answers, position, answer) {
		Kill ^OcuTalonTest("SettingsOpsProbe", "roster")
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "roster") = answer
		Set values = ..Page().sections.%Get("on-call")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "roster")), 1, answer_": one ListOnCallUsers was submitted")
		Do $$$AssertEquals(values.%GetTypeOf("users")_"|"_values.users.%Size(), "array|0", answer_": users is []")
		Do $$$AssertEquals(values.primaryUser_"|"_values.primaryChannels_"|"_values.escalationMinutes_"|"_values.pagesBuilt, user_"|telegram|40|"_(##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Data.Page") + 0), answer_": the rest of the member is as stored")
		Set uri = $Get(^OcuTalonTest("SettingsOpsProbe", "roster", "uri", 1))
		If $Case(answer, "garbled": 1, "notlist": 1, "badrow": 1, "shortrow": 1, : 0) {
			Do $$$AssertTrue(uri '= "", answer_": the case made a handoff")
			Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), answer_": and it is gone")
			Do $$$AssertEquals($Get(left), "", answer_": with nothing left in it")
		}
	}
	Kill ^OcuTalonTest("SettingsOpsProbe", "answer", "roster")
	Set listed = ""
	Set iterator = ..Page().sections.%Get("on-call").users.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.user = user Set listed = one.user_"="_one.paired
	}
	Do $$$AssertEquals(listed, user_"=1", "and with no failure the fixture user is listed again, paired")
}

/// On the online demo Values submits nothing, and a ListOnCallUsers that reaches the handler is not_available and offers no handoff.
Method TestOnlineDemoAsksNoOne()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..User("d", 0)
	Do ..Page()
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SettingsOpsProbe", "roster")), 0, "Values submits no ListOnCallUsers")
	Set result = ..Carry(##class(OcuTalon.Msg.Command.ListOnCallUsers).%New())
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|not_available|", "the handler is not_available and offers no handoff")
	Do $$$AssertEquals(result.Message, "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.", "with the accepted text")
}

/// The web-process path of the users holds no read of the sessions' or pairings' storage: the source of Values, OnCallValues, OnCallRoster and SubmitRoster has no $Order over an
/// OcuTalonP global, no %OpenId and no call of OnCallUsers, which only the production job's handler makes. The scan has positive controls: OnCallUsers itself holds the storage walk and the
/// %OpenId, and the handler ListOnCallUsers calls OnCallUsers.
Method TestRosterNotReadInTheWebProcess()
{
	Set bad = ""
	For method = "Values", "OnCallValues", "OnCallRoster", "SubmitRoster" {
		Set source = ..Source(method)
		Do $$$AssertTrue(source '= "", method_" has source to scan")
		For needle = "$Order(^OcuTalonP", "%OpenId", "OnCallUsers(", "^OcuTalonP." {
			If source [ needle Set bad = bad_$ListBuild(method_" holds "_needle)
		}
	}
	Do $$$AssertEquals($ListToString(bad, "; "), "", "no web-process method reads the storage or calls OnCallUsers")
	Set reads = ..Source("OnCallUsers")
	Do $$$AssertTrue((reads [ "$Order(^OcuTalonP") && (reads [ "%OpenId"), "positive control: OnCallUsers does read both")
	Do $$$AssertTrue(..Source("ListOnCallUsers") [ "OnCallUsers(", "and the handler calls it")
}

Method TestHandoffMissing()
{
	Set result = ..Carry(..Command({"handoff": "secret://handoff/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a handoff with nothing behind it is failed")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "and nothing is written or audited")
	Set body = ..Body(..Role("email", "", "a@x.io", "email"), ..Role("nobody", "", "", ""), 20)
	Set result = ..Carry(..Command(body.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "a body in the command's Changes is refused: only a handoff is read")
	Set uri = ..Handoff(body)
	Set result = ..Carry(..Command({"handoff": (uri), "primaryPerson": "email"}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "Changes with a member besides the handoff are refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "and the handoff is discarded")
	Set result = ..Carry(..Command({"handoff": 5}.%ToJSON()))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "a handoff that is not a text is refused")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing is written or audited")
}

Method TestValues()
{
	Set values = ..Page().sections.%Get("on-call")
	Set names = ""
	Set iterator = values.%GetIterator()
	While iterator.%GetNext(.name) {
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "primaryUser,primaryEmail,primaryChannels,backupUser,backupEmail,backupChannels,escalationMinutes,users,pagesBuilt", "the member's keys, in the form's order")
	Do $$$AssertEquals(values.primaryUser_"|"_values.primaryEmail_"|"_values.primaryChannels_"|"_values.backupUser_"|"_values.backupEmail_"|"_values.backupChannels, "||telegram,email|||telegram,email", "an absent row reads as its default")
	Do $$$AssertEquals(values.escalationMinutes_"|"_values.%GetTypeOf("escalationMinutes"), "15|number", "the minutes are the number 15")
	Do $$$AssertEquals(values.%GetTypeOf("users")_"|"_values.%GetTypeOf("pagesBuilt"), "array|boolean", "the users are an array and pagesBuilt a boolean")
	Do $$$AssertEquals(values.pagesBuilt, ##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Data.Page") + 0, "pagesBuilt says whether OcuTalon.Data.Page is compiled")
	Set b = ..User("b", 0), a = ..User("a", 1), c = ..User("c", 0)
	Do ##class(OcuTalon.Test.Data.Fixture).Session(c)
	Do ##class(OcuTalon.Test.Data.Fixture).Pairing(##class(OcuTalon.Test.Data.Fixture).Session(c))
	Set values = ..Page().sections.%Get("on-call")
	Set found = "", seen = ""
	Set iterator = values.users.%GetIterator()
	While iterator.%GetNext(, .one) {
		Do $$$AssertEquals(one.%Size()_"|"_one.%GetTypeOf("paired"), "2|boolean", "each user has a name and a paired flag")
		If $Extract(one.user, 1, $Length("zzoc"_..Tag)) '= ("zzoc"_..Tag) Continue
		Set found = found_$ListBuild(one.user_"="_one.paired)
	}
	Do $$$AssertEquals($ListToString(found), a_"=1,"_b_"=0,"_c_"=1", "the fixture users are listed once each, sorted, and a user is paired when any one of their sessions is")
	Do ..Save(..Body(..Role("user", a, "a@x.io", "telegram"), ..Role("email", "", "b@x.io", "email"), 40))
	Set values = ..Page().sections.%Get("on-call")
	Do $$$AssertEquals(values.primaryUser_"|"_values.primaryEmail_"|"_values.primaryChannels_"|"_values.backupUser_"|"_values.backupEmail_"|"_values.backupChannels_"|"_values.escalationMinutes, a_"|a@x.io|telegram||b@x.io|email|40", "the stored values")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("oncall.escalationMinutes")
	Set row.Value = "abc"
	Do row.%Save()
	Do $$$AssertEquals(..Page().sections.%Get("on-call").escalationMinutes, 15, "a stored value that is not a whole number reads as the default")
}

Method TestTextOffOnDemo()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Core.SettingsOps", "MESSAGEONCALLOFF"), "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.", "the off-on-demo text is the accepted one")
}

/// --- helpers ---
/// A role of a body: its person, user name, address and channels.
ClassMethod Role(person As %String, user As %String, email As %String, channels As %String) As %DynamicObject [ Private ]
{
	Quit {"person": (person), "user": (user), "email": (email), "channels": (channels)}
}

/// The body of a save from two roles and the minutes: a number when the minutes are one, and a string for "s:" and the text.
ClassMethod Body(primary As %DynamicObject, backup As %DynamicObject, minutes) As %DynamicObject [ Private ]
{
	Set body = {}
	For role = "primary", "backup" {
		Set one = $Select(role = "primary": primary, 1: backup)
		Do body.%Set(role_"Person", one.person)
		Do body.%Set(role_"User", one.user)
		Do body.%Set(role_"Email", one.email)
		Do body.%Set(role_"Channels", one.channels)
	}
	If $Extract(minutes, 1, 2) = "s:" {
		Do body.%Set("escalationMinutes", $Extract(minutes, 3, *), "string")
	} ElseIf minutes = +minutes {
		Do body.%Set("escalationMinutes", +minutes, "number")
	} Else {
		Do body.%Set("escalationMinutes", minutes, "string")
	}
	Quit body
}

ClassMethod Without(body As %DynamicObject, name As %String) As %DynamicObject [ Private ]
{
	Do body.%Remove(name)
	Quit body
}

ClassMethod Extra(body As %DynamicObject) As %DynamicObject [ Private ]
{
	Do body.%Set("zzExtra", "x")
	Quit body
}

ClassMethod Number(body As %DynamicObject, name As %String) As %DynamicObject [ Private ]
{
	Do body.%Set(name, 5, "number")
	Quit body
}

ClassMethod Null(body As %DynamicObject, name As %String) As %DynamicObject [ Private ]
{
	Do body.%Set(name, "", "null")
	Quit body
}

/// A fixture session of a new user name that starts with zzoc and the test's tag, with a paired chat when paired is 1. Returns the user name.
Method User(suffix As %String, paired As %Boolean) As %String [ Private ]
{
	Set user = "zzoc"_..Tag_suffix
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	If paired Do ##class(OcuTalon.Test.Data.Fixture).Pairing(ref)
	Quit user
}

/// Puts the body into a handoff of its own and returns the uri.
Method Handoff(body As %DynamicObject) As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(body.%ToJSON(), .uri), "the body is put into a handoff")
	Quit uri
}

/// A SaveSettings of the on-call section with the text as its Changes, from web_admin for zzadmin.
Method Command(changes As %String) As OcuTalon.Msg.Command.SaveSettings [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "on-call"
	Set command.Changes = changes
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..#REF
	Set command.Origin = "web_admin"
	Quit command
}

/// Saves the body as the route does: through a handoff, with {"handoff": uri} as the command's Changes.
Method Save(body As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText(body.%ToJSON())
}

/// Saves the text as the body of the handoff (a blank text for an empty one, which a handoff cannot hold).
Method SaveText(text As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put($Select(text = "": " ", 1: text), .uri), "the text is put into a handoff")
	Quit ..Carry(..Command({"handoff": (uri)}.%ToJSON()))
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
	If result.Data = "" Quit "[no data]"
	Set fields = {}.%FromJSON(result.Data).fields
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set text = text_$Select(text = "": "", 1: ",")_name
	}
	Quit text
}

/// The page's values as the web process reads them: Values on the probe, whose SubmitRoster hands the ListOnCallUsers to the real handler.
Method Page() As %DynamicObject [ Private ]
{
	Quit $ClassMethod(..#PROBE, "Values")
}

/// The source text of a method of OcuTalon.Core.SettingsOps, "" when it has none.
ClassMethod Source(method As %String) As %String [ Private ]
{
	Set definition = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Core.SettingsOps||"_method)
	If '$IsObject(definition) Quit ""
	Set text = ""
	Set stream = definition.Implementation
	Do stream.Rewind()
	While 'stream.AtEnd {
		Set text = text_stream.Read(32000)
	}
	Quit text
}

/// A member of the on-call part of Values.
Method OnCallValue(name As %String) As %String [ Private ]
{
	Quit ..Page().sections.%Get("on-call").%Get(name)
}

Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
}

/// Deletes the rows of the seven keys.
Method Clear() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
	}
}

/// The stored value of the key, "" when there is no row.
Method Row(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The number of rows of the seven keys.
Method Rows() As %Integer [ Private ]
{
	Set count = 0
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(key) Set count = count + 1
	}
	Quit count
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
