/// Tests of Data.Webhook (Story 35.3; AD-3, AD-13, AD-17, AD-19, AD-27): the salted hash, its constant-time comparison, the table's helpers, the hook's
/// counters and the purge of them. The rows are fixtures (Test.Data.Fixture) and the counters are those of fresh Refs, removed after every test. Safe on a slot,
/// except that PurgeCounters writes real audit entries. Flush and PurgeCounters walk every slot, so TestFlushAndPurge holds every counter it did not make aside
/// while it runs and puts them back after, so that no real slot is stamped with the test's 2030 clock and no real window is deleted.
///   - TestHashFormat: HashSecret gives 66 characters, a 22-character salt, a dot and a 43-character hash, all base64url; the same secret hashes differently
///     each time (a new salt), the secret itself is not in the value, and the value matches its secret, a secret with non-ASCII characters included;
///   - TestMatches: a wrong, empty, longer or shorter secret, and every malformed stored value, do not match and never throw; DUMMYHASH is well formed and
///     matches nothing that is tried; the malformed values are tried against a random hash and against one made from a fixed salt that starts with "x", and
///     FirstChanged changes only the first character of a salt, so that the result is never the real salt, an "x" included;
///   - TestMatchesHasNoEarlyExit: the source of Matches has no Quit or Return inside its comparison loop, which runs over all 43 characters;
///   - TestFieldProblems: NameProblem and SecretProblem give the catalog key of each refusal, at the boundaries;
///   - TestTable: Lookup finds a Ref and nothing for a malformed or unknown one, ForSession lists a session's Refs in creation order, a name is taken without
///     regard to case, and a second row of the name is refused by the index;
///   - TestObjectAccess: the readers and the counters use no SQL;
///   - TestAcceptWindows: Accept counts per UTC hour, the 121st is refused with the seconds to the next hour and is not counted, and another Ref or hour is free;
///   - TestRejectSlots: Reject is due at once for a quiet slot, not again within 60 seconds, due at 60 seconds with the count since, and slots are separate;
///     a slot stamped later than now (the clock was set back) is due at once;
///   - TestFlushAndPurge: Flush hands over a pending count older than 60 seconds once, PurgeCounters writes it as an audit entry and deletes the accepted
///     windows older than two hours only; Flush also hands over a pending count stamped later than now.
Class OcuTalon.Test.Data.Webhook Extends %UnitTest.TestCase
{

/// The Refs of the counters that the tests made.
Property Refs As %String(MAXLEN = "");

Method OnBeforeOneTest() As %Status
{
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref = "" Continue
		Kill ^OcuTalonP.WebhookC("a", ref)
		Kill ^OcuTalonP.WebhookC("r", ref)
	}
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $$$OK
}

Method TestHashFormat()
{
	Set secret = "zz-hash-secret-0123456789"
	Set hash = ##class(OcuTalon.Data.Webhook).HashSecret(secret)
	Do $$$AssertEquals($Length(hash), 66, "66 characters")
	Do $$$AssertEquals($Length(hash, "."), 2, "one dot")
	Do $$$AssertEquals($Length($Piece(hash, ".", 1)), 22, "a 22-character salt")
	Do $$$AssertEquals($Length($Piece(hash, ".", 2)), 43, "and a 43-character hash")
	Do $$$AssertEquals($Translate(hash, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_."), "", "base64url characters only")
	Do $$$AssertEquals(hash [ secret, 0, "the secret is not in it")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).HashSecret(secret) '= hash, "a new salt each time")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(hash, secret), "the value matches its secret")
	Set salt = $SYSTEM.Encryption.Base64Decode($Translate($Piece(hash, ".", 1), "-_", "+/")_"==")
	Set expected = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, salt_secret), 1), "+/=", "-_")
	Do $$$AssertEquals($Piece(hash, ".", 2), expected, "the hash is SHA-256 of the salt followed by the secret")
	Set wide = "zz-"_$Char(233)_$Char(8364)_"-secret-0123456789"
	Set wideHash = ##class(OcuTalon.Data.Webhook).HashSecret(wide)
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(wideHash, wide), "a secret with non-ASCII characters matches")
	Set expectedWide = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, $SYSTEM.Encryption.Base64Decode($Translate($Piece(wideHash, ".", 1), "-_", "+/")_"==")_$ZConvert(wide, "O", "UTF8")), 1), "+/=", "-_")
	Do $$$AssertEquals($Piece(wideHash, ".", 2), expectedWide, "as UTF-8 bytes")
}

Method TestMatches()
{
	Set secret = "zz-match-secret-0123456789"
	Set hash = ##class(OcuTalon.Data.Webhook).HashSecret(secret)
	For other = secret_"x", $Extract(secret, 1, *-1), "", "ZZ-MATCH-SECRET-0123456789", " "_secret, "nope" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Matches(hash, other), 0, "'"_other_"' does not match")
	}
	Set xSalt = "xAbCdEfGhIjKlMnOpQrStQ"
	Set xHash = xSalt_"."_$Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, $SYSTEM.Encryption.Base64Decode($Translate(xSalt, "-_", "+/")_"==")_$ZConvert(secret, "O", "UTF8")), 1), "+/=", "-_")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Matches(xHash, secret), 1, "a stored value whose salt starts with x matches its secret")
	For real = hash, xHash {
		Set salt = $Piece(real, ".", 1), digest = $Piece(real, ".", 2)
		Set lastChanged = $Extract(digest, 1, 42)_$Select($Extract(digest, 43) = "A": "B", 1: "A")
		Set firstChanged = ..FirstChanged(salt)
		For stored = "", "x", ".", "a.b", salt, salt_".", "."_digest, salt_"."_$Extract(digest, 1, 42), salt_"."_digest_"x", salt_"."_lastChanged, firstChanged_"."_digest, salt_"."_digest_".x", digest_"."_salt {
			Set matched = ##class(OcuTalon.Data.Webhook).Matches(stored, secret)
			Do $$$AssertEquals(matched, 0, "'"_$Extract(stored, 1, 20)_"' is not a stored value of the secret")
		}
		Do $$$AssertTrue(firstChanged '= salt, "the changed-first salt '"_firstChanged_"' is not the real salt")
	}
	Set xChanged = ..FirstChanged(xSalt)
	Do $$$AssertTrue(xChanged '= xSalt, "a salt starting with x is changed")
	Do $$$AssertEquals($Length(xChanged), $Length(xSalt), "with the same length")
	Do $$$AssertTrue($Extract(xChanged) '= $Extract(xSalt), "in its first character")
	Do $$$AssertEquals($Extract(xChanged, 2, *), $Extract(xSalt, 2, *), "and in that character only")
	Do $$$AssertEquals(..FirstChanged("zAbCdEfGhIjKlMnOpQrStU"), "xAbCdEfGhIjKlMnOpQrStU", "a salt starting with another character gets an x")
	Set dummy = ##class(OcuTalon.Data.Webhook).#DUMMYHASH
	Do $$$AssertEquals($Length(dummy), 66, "DUMMYHASH has 66 characters")
	Do $$$AssertEquals($Length($Piece(dummy, ".", 1)), 22, "a 22-character salt")
	Do $$$AssertEquals($Length($Piece(dummy, ".", 2)), 43, "and a 43-character hash")
	For other = secret, "", "x", "zz-hook-secret-0123456789" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Matches(dummy, other), 0, "DUMMYHASH matches '"_other_"' no more than a wrong secret")
	}
}

/// The value with its first character replaced by one that is not its own ("y" for a value that starts with "x", otherwise "x"), so that the result
/// never equals the value.
ClassMethod FirstChanged(value As %String) As %String
{
	Quit $Select($Extract(value) = "x": "y", 1: "x")_$Extract(value, 2, *)
}

Method TestMatchesHasNoEarlyExit()
{
	Set source = ##class(OcuTalon.Test.Web.WebhookTools).Source("OcuTalon.Data.Webhook", "Matches")
	Do $$$AssertTrue(source [ "For i = 1:1:43", "the comparison is a loop over all 43 characters")
	Set inLoop = 0, exits = 0, loopLines = 0
	For i = 1:1:$Length(source, $Char(10)) {
		Set line = $Piece(source, $Char(10), i)
		If $ZStrip(line, "<W") ? 1"For i = 1:1:43".E Set inLoop = 1 Continue
		If inLoop && ($ZStrip(line, "<W") = "}") Set inLoop = 0
		If inLoop {
			Set loopLines = loopLines + 1
			If (line [ "Quit") || (line [ "Return") || (line [ "Throw") || (line [ "Goto") Set exits = exits + 1
		}
	}
	Do $$$AssertTrue(loopLines > 0, "the loop has a body")
	Do $$$AssertEquals(exits, 0, "and no exit inside it")
}

Method TestFieldProblems()
{
	Set class = "OcuTalon.Data.Webhook"
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "Orders"), "", "a name is acceptable")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "  Orders  "), "", "with spaces around it")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", $Translate($Justify("", 64), " ", "n")), "", "of 64 characters")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", " "_$Translate($Justify("", 64), " ", "n")_" "), "", "of 64 characters after trimming")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", $Translate($Justify("", 65), " ", "n")), "settings.webhookBadName", "65 characters are refused")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", ""), "settings.webhookBadName", "an empty name")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "   "), "settings.webhookBadName", "a blank name")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "a"_$Char(9)_"b"), "settings.webhookBadName", "a control character")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "a"_$Char(127)_"b"), "settings.webhookBadName", "DEL")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "a@{b"), "settings.refusedExpansion", "@{ in a name")
	Do $$$AssertEquals($ClassMethod(class, "NameProblem", "a@b{"), "", "@ and { apart are fine")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", $Translate($Justify("", 16), " ", "s")), "", "16 characters are acceptable")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", $Translate($Justify("", 256), " ", "s")), "", "so are 256")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", $Translate($Justify("", 15), " ", "s")), "settings.webhookBadSecret", "15 are not")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", $Translate($Justify("", 257), " ", "s")), "settings.webhookBadSecret", "nor 257")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "abcdefgh ijklmnop"), "settings.webhookBadSecret", "a space")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "abcdefghijklmnop"_$Char(9)), "settings.webhookBadSecret", "a control character")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "abcdefghijklmnop"_$Char(127)), "settings.webhookBadSecret", "DEL")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "abcdefghijklmnop"_$Char(233)), "settings.webhookBadSecret", "a non-ASCII character")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "!~abcdefghijklmnop"), "", "0x21 and 0x7E are acceptable")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", "abcdefghijklmnop@{"), "settings.refusedExpansion", "@{ in a secret")
	Do $$$AssertEquals($ClassMethod(class, "SecretProblem", ""), "settings.webhookBadSecret", "an empty secret")
}

Method TestTable()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzwebhooka")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzwebhookb")
	Set one = ##class(OcuTalon.Test.Data.Fixture).Webhook(a, "zz Alpha "_$Random(1000000))
	Set two = ##class(OcuTalon.Test.Data.Fixture).Webhook(a, "zz Beta "_$Random(1000000))
	Set three = ##class(OcuTalon.Test.Data.Fixture).Webhook(b, "zz Gamma "_$Random(1000000))
	Set row = ##class(OcuTalon.Data.Webhook).Lookup(one)
	Do $$$AssertTrue($IsObject(row), "Lookup finds a Ref")
	Do $$$AssertEquals(row.Ref, one, "the row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(##class(OcuTalon.Bridge.Ids).NewRef()), "", "an unknown Ref is nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup("abc"), "", "so is a malformed one")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(""), "", "and an empty one")
	Set lower = $ZConvert(one, "L")
	If lower '= one Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Lookup(lower), "", "Refs are case-sensitive")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Data.Webhook).ForSession(a)), one_","_two, "ForSession lists a session's Refs in creation order")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Data.Webhook).ForSession(b)), three, "and only its own")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Data.Webhook).ForSession(##class(OcuTalon.Bridge.Ids).NewRef())), "", "an unknown session has none")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Data.Webhook).ForSession("")), "", "and an empty one")
	Set name = row.Name
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken(name), 1, "the name is taken")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken($ZConvert(name, "U")), 1, "in any case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).NameTaken(name_"x"), 0, "another name is free")
	Set clash = ##class(OcuTalon.Data.Webhook).%New()
	Set clash.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set clash.Name = $ZConvert(name, "L")
	Set clash.SessionRef = b
	Set clash.SecretHash = ##class(OcuTalon.Data.Webhook).HashSecret("zz-clash-secret-0123456789")
	Do $$$AssertStatusNotOK(clash.%Save(), "the index refuses a second row of the name in another case")
}

Method TestObjectAccess()
{
	For method = "Lookup", "ForSession", "NameTaken", "Accept", "Reject", "Flush", "PurgeCounters", "IsRef" {
		Set source = ##class(OcuTalon.Test.Web.WebhookTools).Source("OcuTalon.Data.Webhook", method)
		Do $$$AssertTrue(source '= "", method_" has source")
		Do $$$AssertTrue(($ZConvert(source, "U") '[ "%SQL") && ($ZConvert(source, "U") '[ "SELECT ") && ($ZConvert(source, "U") '[ "EXECDIRECT"), method_" uses no SQL")
	}
}

Method TestAcceptWindows()
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef(), other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ref_","_other
	Set max = ##class(OcuTalon.Data.Webhook).#ACCEPTEDMAX
	Do $$$AssertEquals(max, 120, "120 events an hour")
	Set now = "2030-03-04T10:15:30Z"
	Set allowed = 0
	For i = 1:1:max {
		Set allowed = allowed + ##class(OcuTalon.Data.Webhook).Accept(ref, now, .retry)
	}
	Do $$$AssertEquals(allowed, max, "the first "_max_" are accepted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(ref, now, .retry), 0, "the next is refused")
	Do $$$AssertEquals(retry, 2670, "with the seconds to the next hour")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(ref, now, .retry), 0, "and so is the one after")
	Do $$$AssertEquals(^OcuTalonP.WebhookC("a", ref, "2030-03-04T10"), max, "the count stays at the limit")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(ref, "2030-03-04T10:59:59Z", .retry), 0, "the same hour at its last second is refused")
	Do $$$AssertEquals(retry, 1, "with one second to go")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(ref, "2030-03-04T11:00:00Z", .retry), 1, "the next hour is free")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(other, now, .retry), 1, "another Ref has its own count")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Accept(ref, "2030-03-05T10:00:00Z", .retry), 1, "and so has the same hour of another day")
}

Method TestRejectSlots()
{
	Set slot = ##class(OcuTalon.Bridge.Ids).NewRef(), other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = slot_","_other
	Set t0 = "2030-03-04T10:00:00Z"
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(slot, t0, .count), 1, "a quiet slot is due at once")
	Do $$$AssertEquals(count, 1, "with the one rejection")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 10), .count), 0, "not again within 60 seconds")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 59), .count), 0, "not at 59 seconds")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(other, ##class(OcuTalon.Data.Time).AddSeconds(t0, 20), .count), 1, "another slot is due at once")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 60), .count), 1, "due again at 60 seconds")
	Do $$$AssertEquals(count, 3, "with the rejections since the previous entry, this one included")
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 61), .count), 0, "and then quiet for another 60 seconds")
	Set ahead = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs_","_ahead
	Set ^OcuTalonP.WebhookC("r", ahead) = $ListBuild("2031-01-01T00:00:00Z", 2)
	Do $$$AssertEquals(##class(OcuTalon.Data.Webhook).Reject(ahead, t0, .count), 1, "a slot stamped later than now is due at once")
	Do $$$AssertEquals(count, 3, "with its pending rejections and this one")
}

Method TestFlushAndPurge()
{
	Merge held = ^OcuTalonP.WebhookC
	Kill ^OcuTalonP.WebhookC
	Try {
		Do ..FlushAndPurge()
	} Catch ex {
		Do $$$AssertTrue(0, "FlushAndPurge threw "_ex.DisplayString())
	}
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Kill ^OcuTalonP.WebhookC("a", $Piece(..Refs, ",", i)), ^OcuTalonP.WebhookC("r", $Piece(..Refs, ",", i))
	}
	Merge ^OcuTalonP.WebhookC = held
}

/// The body of TestFlushAndPurge, run while the counters it did not make are held aside.
Method FlushAndPurge()
{
	Set slot = ##class(OcuTalon.Bridge.Ids).NewRef(), young = ##class(OcuTalon.Bridge.Ids).NewRef(), settled = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = slot_","_young_","_settled
	Set t0 = "2030-03-04T10:00:00Z"
	Do ##class(OcuTalon.Data.Webhook).Reject(slot, t0, .count)
	Do ##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 5), .count)
	Do ##class(OcuTalon.Data.Webhook).Reject(slot, ##class(OcuTalon.Data.Time).AddSeconds(t0, 6), .count)
	Do ##class(OcuTalon.Data.Webhook).Reject(settled, t0, .count)
	Set early = ##class(OcuTalon.Data.Webhook).Flush(##class(OcuTalon.Data.Time).AddSeconds(t0, 30), .pending)
	For i = 1:1:early {
		Do $$$AssertTrue($Case($ListGet(pending(i), 1), slot: 0, settled: 0, young: 0, : 1), "nothing of this test is pending for more than 60 seconds at 30 seconds")
	}
	Do ##class(OcuTalon.Data.Webhook).Reject(young, ##class(OcuTalon.Data.Time).AddSeconds(t0, 50), .count)
	Do ##class(OcuTalon.Data.Webhook).Reject(young, ##class(OcuTalon.Data.Time).AddSeconds(t0, 51), .count)
	Set total = ##class(OcuTalon.Data.Webhook).Flush(##class(OcuTalon.Data.Time).AddSeconds(t0, 61), .pending)
	Set found = ""
	For i = 1:1:total {
		If $ListGet(pending(i), 1) = slot Set found = found_$ListGet(pending(i), 2)
		If $ListGet(pending(i), 1) = settled Do $$$AssertTrue(0, "a slot with nothing pending is not flushed")
		If $ListGet(pending(i), 1) = young Do $$$AssertTrue(0, "a count younger than 60 seconds is not flushed")
	}
	Do $$$AssertEquals(found, 2, "a pending count of two older than 60 seconds is flushed once")
	Set again = ##class(OcuTalon.Data.Webhook).Flush(##class(OcuTalon.Data.Time).AddSeconds(t0, 62), .pending)
	For i = 1:1:again {
		Do $$$AssertTrue($ListGet(pending(i), 1) '= slot, "the flushed slot is not flushed twice")
	}
	Set ahead = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs_","_ahead
	Set ^OcuTalonP.WebhookC("r", ahead) = $ListBuild("2031-01-01T00:00:00Z", 2)
	Set total = ##class(OcuTalon.Data.Webhook).Flush(##class(OcuTalon.Data.Time).AddSeconds(t0, 63), .pending), found = ""
	For i = 1:1:total {
		If $ListGet(pending(i), 1) = ahead Set found = $ListGet(pending(i), 2)
	}
	Do $$$AssertEquals(found, 2, "Flush hands over a pending count stamped later than now")
	Kill ^OcuTalonP.WebhookC("r", slot)
	Set ^OcuTalonP.WebhookC("r", slot) = $ListBuild(t0, 4)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set ^OcuTalonP.WebhookC("a", slot, "2030-03-04T07") = 5
	Set ^OcuTalonP.WebhookC("a", slot, "2030-03-04T08") = 6
	Set ^OcuTalonP.WebhookC("a", slot, "2030-03-04T09") = 7
	Set ^OcuTalonP.WebhookC("a", slot, "2030-03-04T10") = 8
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Webhook).PurgeCounters(##class(OcuTalon.Data.Time).AddSeconds(t0, 3601)), "PurgeCounters")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", slot)
	Do $$$AssertEquals(entries.%Size(), 1, "a pending count older than 60 seconds is written as an audit entry")
	Do $$$AssertEquals(entries.%Get(0).data.counts.rejected, 4, "with its count")
	Do $$$AssertEquals(entries.%Get(0).data.target, slot, "for its Ref")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", slot, "2030-03-04T07")), 0, "a window three hours old is deleted")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", slot, "2030-03-04T08")), 0, "so is one two hours and a bit old")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", slot, "2030-03-04T09")), 1, "one inside two hours is kept")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", slot, "2030-03-04T10")), 1, "and the current one")
	Do $$$AssertEquals($ListGet(^OcuTalonP.WebhookC("r", slot), 2), 0, "the flushed slot has nothing pending")
}

}
