/// Tests of OcuTalon.Core.SecretHandoff, the in-memory handoff of a secret from the REST process to SettingsOps (the shared interface of Stories 35.3 and
/// 21.2). Safe on a slot: it needs no production.
///   - TestRoundTrip: Put returns a uri secret://handoff/<Ref>, Take returns the secret once, and a second Take of the uri fails;
///   - TestFailuresAreAlike: an unknown uri, a malformed uri and an empty uri each fail with the same status text and no secret, a signaled secret is read at once and an event that never existed fails without a long wait;
///   - TestDiscard: Discard deletes an untaken event, so that Take then fails, and Discard of an unknown or empty uri is not an error;
///   - TestNothingPersists: after Put, Take and Discard, no global, event log row or audit entry of the run holds the secret, and no node of the event's
///     name exists in any global.
Class OcuTalon.Test.Core.SecretHandoff Extends %UnitTest.TestCase
{

Method TestRoundTrip()
{
	Set secret = "zz-handoff-secret-"_$Random(100000000)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri), "Put")
	Do $$$AssertEquals($Extract(uri, 1, 17), "secret://handoff/", "the uri has the scheme")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).IsRef($Extract(uri, 18, *)), "and a Ref")
	Do $$$AssertEquals(uri [ secret, 0, "the secret is not in the uri")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .got, 1), "Take")
	Do $$$AssertEquals(got, secret, "returns the secret")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .again, 0), "a second Take fails")
	Do $$$AssertEquals(again, "", "with no secret")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .other), "a second Put")
	Do $$$AssertTrue(other '= uri, "has a uri of its own")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(other, .got2, 1), "and is taken")
	Do $$$AssertEquals(got2, secret, "with its secret")
	Set long = $Translate($Justify("", 256), " ", "s")
	Do ##class(OcuTalon.Core.SecretHandoff).Put(long, .uri3)
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri3, .got3, 1)
	Do $$$AssertEquals(got3, long, "a 256-character secret survives")
}

Method TestFailuresAreAlike()
{
	Set unknown = "secret://handoff/"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set texts = ""
	For uri = unknown, "secret://handoff/abc", "secret://handoff/", "secret://other/"_##class(OcuTalon.Bridge.Ids).NewRef(), "", "plain" {
		Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(uri, .secret, 0)
		Do $$$AssertStatusNotOK(sc, "'"_uri_"' fails")
		Do $$$AssertEquals(secret, "", "with no secret")
		Set texts = texts_$ListBuild($SYSTEM.Status.GetErrorText(sc))
	}
	Set position = 0, first = $ListGet(texts, 1), same = 1
	While $ListNext(texts, position, text) {
		If text '= first Set same = 0
	}
	Do $$$AssertTrue(same, "every failure has the same text")
	Do $$$AssertEquals(first [ ##class(OcuTalon.Core.SecretHandoff).#MESSAGEFAILED, 1, "that says nothing of the cause")
	Do $$$AssertEquals(first [ unknown, 0, "and not the uri")
	Do ##class(OcuTalon.Core.SecretHandoff).Put("zz-signaled-secret-0123456789", .uri)
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .got, 1)
	Do $$$AssertEquals(got, "zz-signaled-secret-0123456789", "a signaled secret is read at once")
	Set unsignaled = "secret://handoff/"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set started = $ZHorolog
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(unsignaled, .none, 1), "an event that never existed fails")
	Do $$$AssertTrue($ZHorolog - started < 3, "without waiting long")
}

Method TestDiscard()
{
	Do ##class(OcuTalon.Core.SecretHandoff).Put("zz-discard-secret-0123456789", .uri)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(uri), "Discard")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .secret, 0), "the event is gone")
	Do $$$AssertEquals(secret, "", "and held nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(uri), "a second Discard is not an error")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard(""), "nor an empty uri")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Discard("junk"), "nor a malformed one")
}

Method TestNothingPersists()
{
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set secret = "zz-persist-secret-"_$Random(100000000)
	Do ##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri)
	Do ##class(OcuTalon.Core.SecretHandoff).Put(secret_"b", .uriB)
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .got, 1)
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(uriB)
	Do $$$AssertEquals($Data(^OcuTalonP.SecretHandoff), 0, "no node of the event's global exists")
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.WebhookTools).GlobalHolds("^OcuTalonP.SecretHandoff", secret), 0, "so none holds the secret")
	For global = "^OcuTalonP.Webhook", "^OcuTalonP.WebhookD", "^OcuTalonP.WebhookC", "^OcuTalonP.Setting", "^OcuTalonP.Session" {
		Do $$$AssertEquals(##class(OcuTalon.Test.Web.WebhookTools).GlobalHolds(global, secret), 0, global_" does not hold it")
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ secret, "no event log row holds it")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon")
	Do $$$AssertEquals(entries.%Size(), 0, "and no audit entry was written")
}

}
