/// Tests of the Pairing row methods and the Telegram status mark that Stories 12.1, 12.4, 12.5 and 30.2 call (Story 10.3; AD-4, AD-5, AD-14,
/// AD-18, AD-27, AD-33). No production is needed, but TestPurge deletes every old row without a session, so the class runs in throwaways and CI. The chat ids are made from the run's number n, from
/// ^OcuTalonTest("PairingRows","n") (never reset), so that a rerun never meets a row of an earlier run; every row the tests make is
/// recorded with Test.Data.Fixture and removed with Fixture.Clean, and the telegramState mark is put back.
///   - TestHashCodeVectors: the SHA-256 base64url form of three codes, 43 characters, and "" for "";
///   - TestHashCodeIsSessionHash: HashCode equals Session.Hash for the sample codes, answers "" for "" and for no argument (where Session.Hash
///     of "" is not ""), and its source is the empty-code guard and Session.Hash of the code, and nothing else;
///   - TestRecordChatNewAndKnown: a new chat row (Ref, ChatId, name, no session, CreatedAt = SeenAt), then the same chat id gives the same
///     Ref and a new name and SeenAt; the name is stripped of control characters, trimmed and cut to 128; a negative id is a chat id;
///   - TestRecordChatRefusesABadId: "", letters and 21 digits give "" and an error status that never holds the value, and no row;
///   - TestChatLookupsAreExact: Chat finds a chat row by its exact Ref only, never by a case-changed Ref, a code row or "";
///   - TestTakeReplySlot: 1 and ReplySlotAt = now, then 0 for 59 seconds, then 1 again; 0 for an unknown ref and a code row's Ref;
///   - TestStoreCodeReplaces: one code row per session, replaced in place with its used mark cleared and SeenAt renewed; no ChatId and no SessionRef, so
///     Ownership.Pairing sees no pairing; an empty session, hash or an expiry that is no UTC time is an error and no row; ForCode is exact;
///   - TestPurge: the unpaired chat and code rows that no writer touched for 30 days go (an hour outside the cutoff goes, an hour inside
///     stays), with the fallback to CreatedAt, and the paired
///     and the recent rows stay; the Core area does the same and the registry lists it (a purge deletes every old unpaired row, so the
///     test is for throwaways and CI); a day count that is not a whole number of at
///     least 1 is an error naming the class and deletes nothing;
///   - TestRecordTelegram: the state and bot name round trip, rejected values leave the mark as it was, and no mark is the state off;
///   - TestDeliveryRowForTelegram: Delivery.Record with channel telegram and a <ChatRef>:<message id>, found for its owner only.
Class OcuTalon.Test.Data.PairingRows Extends %UnitTest.TestCase
{

/// The three vectors of HashCode.
Parameter VECTORABC = "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0";

Parameter VECTORCODE = "6f9GcqltZ27RM9XPj-t2niXmYo5dK6Pj--zHN-ak6oM";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The telegramState mark as it was before the tests: "" for none.
Property MarkBefore As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("PairingRows", "n"))
	Set ..Refs = ""
	Set ..MarkBefore = ##class(OcuTalon.Data.StatusMark).Get("telegramState")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", ..MarkBefore)
	Quit $SYSTEM.Status.OK()
}

/// The hash of "abc", of a 24-character code and of "" are the vectors of the spec: SHA-256 of the UTF-8 bytes, base64url, 43 characters,
/// no padding. A code with a non-ASCII character hashes its UTF-8 bytes.
Method TestHashCodeVectors()
{
	Set pairing = "OcuTalon.Data.Pairing"
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode", "abc"), ..#VECTORABC, "abc")
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode", "Zz-ChatCode_0123456789AB"), ..#VECTORCODE, "a 24-character code")
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode", ""), "", "an empty code has an empty hash")
	Do $$$AssertEquals($Length($ClassMethod(pairing, "HashCode", "abc")), 43, "43 characters, no padding")
	Set bytes = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, "caf"_$Char(195, 169)), 1), "+/=", "-_")
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode", "caf"_$Char(233)), bytes, "a code with a non-ASCII character hashes its UTF-8 bytes")
	Do $$$AssertTrue($ClassMethod(pairing, "HashCode", "abc") '= $ClassMethod(pairing, "HashCode", "ABC"), "the hash is case-sensitive")
}

/// HashCode is Session.Hash of the code: equal for the sample codes, and "" (not the hash of the empty string) for "" and for no
/// argument. Equal outputs cannot tell a delegate from a copy, so the source of the method is read: it is the empty-code guard and
/// Session.Hash of the code, and nothing else (no SHAHash, no other statement, no changed argument).
Method TestHashCodeIsSessionHash()
{
	Set pairing = "OcuTalon.Data.Pairing"
	Set session = "OcuTalon.Data.Session"
	For text = "abc", "Zz-ChatCode_0123456789AB", "caf"_$Char(233) {
		Do $$$AssertEquals($ClassMethod(pairing, "HashCode", text), $ClassMethod(session, "Hash", text), "HashCode equals Session.Hash of "_$Length(text)_" characters")
	}
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode", ""), "", "an empty code has an empty hash")
	Do $$$AssertEquals($ClassMethod(pairing, "HashCode"), "", "no code has an empty hash")
	Do $$$AssertTrue($ClassMethod(session, "Hash", "") '= "", "Session.Hash of the empty string is not empty, so the guard belongs to HashCode")
	Set method = ##class(%Dictionary.MethodDefinition).%OpenId(pairing_"||HashCode")
	If '$IsObject(method) {
		Do $$$AssertTrue(0, "Pairing has the method HashCode")
		Quit
	}
	Set code = ""
	Do method.Implementation.Rewind()
	While 'method.Implementation.AtEnd {
		Set code = code_method.Implementation.Read(30000)
	}
	Do $$$AssertEquals($ZStrip(code, "*WC"), "If$Get(code)=""""Quit""""Quit##class(OcuTalon.Data.Session).Hash(code)", "HashCode is the empty-code guard and Session.Hash of the code, with no hashing of its own")
}

/// A new chat id gets a chat row with a 22-character Ref, the chat id, the name, no session and CreatedAt = SeenAt = now; the same chat
/// id again returns the same Ref and updates the name and SeenAt, and keeps SessionRef and CreatedAt. The name is stripped of control
/// characters, trimmed and cut to 128 characters.
Method TestRecordChatNewAndKnown()
{
	Set chatId = ..ChatId(1)
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(sc, "the chat is recorded")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(ref), "the ChatRef is a 22-character Ref")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(ref)
	Do $$$AssertTrue($IsObject(row), "Chat finds the row")
	If '$IsObject(row) Quit
	Do ..Keep(row)
	Do $$$AssertEquals(row.Ref_"|"_row.ChatId_"|"_row.DisplayName_"|"_row.SessionRef, ref_"|"_chatId_"|Dana|", "the Ref, chat id and name, and no session")
	Do $$$AssertTrue((before '] row.CreatedAt) && (row.CreatedAt '] after), "CreatedAt is the time of the call")
	Do $$$AssertEquals(row.SeenAt, row.CreatedAt, "SeenAt = CreatedAt")
	Do $$$AssertEquals(row.CodeSessionRef_row.CodeHash_row.CodeExpiresAt_row.CodeUsedAt_row.ReplySlotAt, "", "none of the code or reply columns is set")
	Set created = row.CreatedAt

	Set row.SeenAt = "2020-01-01T00:00:00Z"
	Set row.SessionRef = "ZzSession"_..Number
	Do row.%Save()
	Set row = ""
	Set again = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana B", .sc)
	Do $$$AssertStatusOK(sc, "the known chat is recorded again")
	Do $$$AssertEquals(again, ref, "the same Ref")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(ref)
	Do $$$AssertEquals(row.DisplayName_"|"_row.SessionRef_"|"_row.CreatedAt, "Dana B|ZzSession"_..Number_"|"_created, "the name is updated and the session and CreatedAt are kept")
	Do $$$AssertTrue(row.SeenAt ] "2020-01-01T00:00:00Z", "SeenAt is updated: "_row.SeenAt)
	Do $$$AssertEquals(..CountRows("ChatId", chatId), 1, "one row for the chat id")
	Set row.SessionRef = ""
	Do row.%Save()
	Set row = ""

	Do ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "  "_$Char(9)_"Da"_$Char(10, 13)_"na "_$Char(7)_"  ", .sc)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(ref).DisplayName, "Dana", "control characters are stripped and the name is trimmed")
	Do ##class(OcuTalon.Data.Pairing).RecordChat(chatId, $Translate($Justify("", 200), " ", "x"), .sc)
	Do $$$AssertEquals($Length(##class(OcuTalon.Data.Pairing).Chat(ref).DisplayName), 128, "the name is cut to 128 characters")
	Do ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "", .sc)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(ref).DisplayName, "", "an empty name is recorded as empty")

	Set group = ##class(OcuTalon.Data.Pairing).RecordChat("-100"_..Number_"4455", "Team", .sc)
	Do $$$AssertStatusOK(sc, "a negative chat id (a group) is a chat id")
	Do ..Keep(##class(OcuTalon.Data.Pairing).Chat(group))
}

/// An empty chat id, one with a letter and one with 21 digits give "" and an error status that names the rule and never the value; no
/// row is made.
Method TestRecordChatRefusesABadId()
{
	Set rows = ..CountAll()
	For bad = "", "12a", "123456789012345678901", "1-2", "--5", " 12", "12 " {
		Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(bad, "Zz", .sc)
		Do $$$AssertEquals(ref, "", "the Ref for '"_bad_"' is empty")
		Do $$$AssertStatusNotOK(sc, "'"_bad_"' is refused")
		If (bad '= "") && ($Length(bad) > 2) Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ bad, "the error never holds the value")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "chat id", "it names the rule")
	}
	Do $$$AssertEquals(..CountAll(), rows, "no row was made")
	Set max = ##class(OcuTalon.Data.Pairing).RecordChat("12345678901234567890", "Zz", .sc)
	Do $$$AssertStatusOK(sc, "20 digits are a chat id")
	Do ..Keep(##class(OcuTalon.Data.Pairing).Chat(max))
}

/// Chat finds a chat row by its exact Ref: a case-changed Ref, a code row's Ref, "" and an unknown Ref find nothing.
Method TestChatLookupsAreExact()
{
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(..ChatId(2), "Zz", .sc)
	Do ..Keep(##class(OcuTalon.Data.Pairing).Chat(ref))
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.Pairing).Chat(ref)), "the exact Ref")
	Set changed = $Select($ZConvert(ref, "U") '= ref: $ZConvert(ref, "U"), 1: $ZConvert(ref, "L"))
	Do $$$AssertTrue(changed '= ref, "control: the changed Ref differs")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(changed), "", "a case-changed Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(""), "", "an empty Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(##class(OcuTalon.Bridge.Ids).NewRef()), "", "an unknown Ref finds nothing")
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, ##class(OcuTalon.Data.Pairing).HashCode("zz"_..Number), "2030-01-01T00:00:00Z"), "control: a code row is stored")
	Set code = ##class(OcuTalon.Data.Pairing).ForCode(##class(OcuTalon.Data.Pairing).HashCode("zz"_..Number))
	Do ..Keep(code)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(code.Ref), "", "a code row's Ref is no chat")
}

/// The first call takes the slot: 1 and ReplySlotAt = now; the calls inside the next 60 seconds get 0; the call after them takes it
/// again. An unknown ref, a code row's Ref, a case-changed Ref and "" get 0 and write nothing.
Method TestTakeReplySlot()
{
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(..ChatId(3), "Zz", .sc)
	Set chat = ##class(OcuTalon.Data.Pairing).Chat(ref)
	Do ..Keep(chat)
	Set id = chat.%Id()
	Set chat = ""
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(ref), 1, "the first call takes the slot")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set at = ##class(OcuTalon.Data.Pairing).%OpenId(id).ReplySlotAt
	Do $$$AssertTrue((before '] at) && (at '] after), "ReplySlotAt is now: "_at)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(ref), 0, "a call at once gets 0")
	Do ..SetColumn(id, "ReplySlotAt", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30))
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(ref), 0, "a call 30 seconds later gets 0")
	Do ..SetColumn(id, "ReplySlotAt", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -59))
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(ref), 0, "a call 59 seconds later gets 0")
	Do ..SetColumn(id, "ReplySlotAt", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -61))
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(ref), 1, "a call 61 seconds later takes it again")
	Set at = ##class(OcuTalon.Data.Pairing).%OpenId(id).ReplySlotAt
	Do $$$AssertTrue(at '] ##class(OcuTalon.Data.Time).NowUtc(), "and ReplySlotAt is now again: "_at)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(##class(OcuTalon.Bridge.Ids).NewRef()), 0, "an unknown ref gets 0")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(""), 0, "an empty ref gets 0")
	Set changed = $Select($ZConvert(ref, "U") '= ref: $ZConvert(ref, "U"), 1: $ZConvert(ref, "L"))
	Do ..SetColumn(id, "ReplySlotAt", "")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(changed), 0, "a case-changed ref gets 0")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).%OpenId(id).ReplySlotAt, "", "and writes nothing")
	Do ##class(OcuTalon.Data.Pairing).StoreCode(##class(OcuTalon.Bridge.Ids).NewRef(), ##class(OcuTalon.Data.Pairing).HashCode("zy"_..Number), "2030-01-01T00:00:00Z")
	Set code = ##class(OcuTalon.Data.Pairing).ForCode(##class(OcuTalon.Data.Pairing).HashCode("zy"_..Number))
	Do ..Keep(code)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).TakeReplySlot(code.Ref), 0, "a code row's Ref gets 0")
	Do $$$AssertEquals(code.ReplySlotAt, "", "and its row is unchanged")
}

/// StoreCode makes the session's one code row, and a second call replaces its hash and expiry in place and clears the used mark. The row
/// has neither a ChatId nor a SessionRef, so the session is not paired (Ownership.Pairing). An empty session or hash and an expiry that is
/// no UTC time are an error status and leave the row as it was. ForCode finds the row by its exact hash only.
Method TestStoreCodeReplaces()
{
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set h1 = ##class(OcuTalon.Data.Pairing).HashCode("one"_..Number)
	Set h2 = ##class(OcuTalon.Data.Pairing).HashCode("two"_..Number)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, h1, "2030-01-01T00:00:00Z"), "the first code is stored")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(h1)
	Do $$$AssertTrue($IsObject(row), "ForCode finds it by its hash")
	If '$IsObject(row) Quit
	Do ..Keep(row)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(row.Ref), "the row has its own Ref")
	Do $$$AssertEquals(row.CodeSessionRef_"|"_row.CodeHash_"|"_row.CodeExpiresAt_"|"_row.CodeUsedAt, session_"|"_h1_"|2030-01-01T00:00:00Z|", "the session, hash and expiry, unused")
	Do $$$AssertEquals(row.ChatId_"|"_row.SessionRef_"|"_row.DisplayName, "||", "no chat id, session or name")
	Do $$$AssertEquals(row.SeenAt, row.CreatedAt, "a new code row is seen as it is created")
	Do $$$AssertTrue(row.SeenAt '= "", "with a time")
	Set id = row.%Id(), ref = row.Ref
	Set row = ""
	Do ..SetColumn(id, "CodeUsedAt", "2030-01-01T00:00:00Z")
	Do ..SetColumn(id, "SeenAt", "2020-01-01T00:00:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc), "", "a code row is no pairing")
	Do $$$AssertStatusOK(sc, "and the read is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, h2, "2031-02-03T04:05:06Z"), "a second code is stored")
	Do $$$AssertEquals(..CountRows("CodeSessionRef", session), 1, "still one code row of the session")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(h2)
	Do $$$AssertEquals(row.%Id()_"|"_row.Ref_"|"_row.CodeHash_"|"_row.CodeExpiresAt_"|"_row.CodeUsedAt, id_"|"_ref_"|"_h2_"|2031-02-03T04:05:06Z|", "the same row has the new hash and expiry and the used mark is cleared")
	Do $$$AssertTrue(row.SeenAt ] "2020-01-01T00:00:00Z", "and the replaced row is seen now, so that the purge keeps a code that was just stored: "_row.SeenAt)
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(h1), "", "the old hash finds nothing")
	Set changed = $Select($ZConvert(h2, "U") '= h2: $ZConvert(h2, "U"), 1: $ZConvert(h2, "L"))
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(changed), "", "a case-changed hash finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(""), "", "an empty hash finds nothing")
	Set row = ""
	Set rows = ..CountAll()
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Pairing).StoreCode("", h1, "2030-01-01T00:00:00Z"), "an empty session is refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Pairing).StoreCode(session, "", "2030-01-01T00:00:00Z"), "an empty hash is refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Pairing).StoreCode(session, h1, "tomorrow"), "an expiry that is no UTC time is refused")
	Do $$$AssertEquals(..CountAll(), rows, "no row was made")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(h2).CodeExpiresAt, "2031-02-03T04:05:06Z", "and the row is as it was")
}

/// Purge(30) deletes the rows without a session (chat and code rows) whose SeenAt is before the cutoff, or whose CreatedAt is when SeenAt
/// is empty, and keeps the recent ones and every paired row; the Core area does the same through the registry; Purge(0), Purge("x") and
/// Purge("") are an error that names the class and delete nothing.
Method TestPurge()
{
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -40 * 86400)
	Set recent = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -10 * 86400)
	Set veryOld = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -400 * 86400)
	Set oldChat = ..AgedChat(10, old, "SeenAt")
	Set oldCode = ..AgedCode("pa", old)
	Set recentChat = ..AgedChat(11, recent, "SeenAt")
	Set pairedChat = ..AgedChat(12, veryOld, "SeenAt", ##class(OcuTalon.Bridge.Ids).NewRef())
	Set createdOnly = ..AgedChat(13, old, "CreatedAt")
	Set recentCreated = ..AgedChat(14, recent, "CreatedAt")
	Set justInside = ..AgedChat(16, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30 * 86400 + 3600), "SeenAt")
	Set justOutside = ..AgedChat(17, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30 * 86400 - 3600), "SeenAt")
	Set justInsideCreated = ..AgedChat(18, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30 * 86400 + 3600), "CreatedAt")
	Set justOutsideCreated = ..AgedChat(19, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30 * 86400 - 3600), "CreatedAt")
	Do $$$AssertTrue(..Exists(oldChat) && ..Exists(oldCode) && ..Exists(recentChat) && ..Exists(pairedChat) && ..Exists(createdOnly) && ..Exists(recentCreated), "control: the six rows exist")
	Do $$$AssertTrue(..Exists(justInside) && ..Exists(justOutside) && ..Exists(justInsideCreated) && ..Exists(justOutsideCreated), "control: the four rows an hour either side of the cutoff exist")

	For days = 0, "x", "", -3, "1.5" {
		Set sc = ##class(OcuTalon.Data.Pairing).Purge(days)
		Do $$$AssertStatusNotOK(sc, "Purge('"_days_"') is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Pairing.Purge", "and names the class")
	}
	Do $$$AssertTrue(..Exists(oldChat) && ..Exists(oldCode) && ..Exists(createdOnly), "a refused call deleted nothing")

	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).Purge(30), "Purge(30)")
	Do $$$AssertTrue('..Exists(oldChat), "the unpaired chat that was seen 40 days ago is deleted")
	Do $$$AssertTrue('..Exists(oldCode), "the code row that was touched 40 days ago is deleted")
	Do $$$AssertTrue('..Exists(createdOnly), "a row with no SeenAt is old by its CreatedAt")
	Do $$$AssertTrue(..Exists(recentChat), "the chat seen 10 days ago stays")
	Do $$$AssertTrue(..Exists(recentCreated), "so does a row of 10 days by CreatedAt")
	Do $$$AssertTrue(..Exists(pairedChat), "the paired chat row of 400 days stays")
	Do $$$AssertTrue(..Exists(justInside) && ..Exists(justInsideCreated), "a row an hour inside the 30 days stays, by SeenAt and by CreatedAt")
	Do $$$AssertTrue('..Exists(justOutside) && '..Exists(justOutsideCreated), "a row an hour outside the 30 days is deleted, by SeenAt and by CreatedAt")

	Do $$$AssertTrue($ListFind(##class(OcuTalon.Install.Registry).Areas(), "OcuTalon.Install.Step.Core") > 0, "the registry lists the Core area")
	Set again = ..AgedChat(15, old, "SeenAt")
	Set againCode = ..AgedCode("pb", old)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Core).Purge(30), "the Core area's Purge(30)")
	Do $$$AssertTrue('..Exists(again) && '..Exists(againCode), "it deletes the same rows")
	Do $$$AssertTrue(..Exists(recentChat) && ..Exists(pairedChat), "and keeps the others")
	Set sc = ##class(OcuTalon.Install.Step.Core).Purge("x")
	Do $$$AssertStatusNotOK(sc, "the Core area refuses a day count that is no number")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Pairing.Purge", "and the error names the class")
}

/// RecordTelegram writes the one mark telegramState with the state and the bot name, TelegramState reads both back, a state or a bot name
/// that is not allowed is an error and leaves the mark as it was, and no mark is the state off.
Method TestRecordTelegram()
{
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", "")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot), "off", "no mark is off")
	Do $$$AssertEquals(bot, "", "with no bot name")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot"), "on")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "on|ocutalon_ci_bot", "on with its bot")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("telegramState"), {"state": "on", "botUserName": "ocutalon_ci_bot"}.%ToJSON(), "the mark holds the JSON of both")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("rejected", ""), "rejected")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "rejected|", "rejected, no bot")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("off", ""), "off")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "off")
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
	Set before = ##class(OcuTalon.Data.StatusMark).Get("telegramState")
	For state = "paused", "", "ON" {
		Do $$$AssertStatusNotOK(##class(OcuTalon.Data.StatusMark).RecordTelegram(state, "x"), "the state '"_state_"' is refused")
	}
	For name = "bad name", "bad-name", "a@b", $Translate($Justify("", 65), " ", "a") {
		Do $$$AssertStatusNotOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("on", name), "the bot name '"_$Extract(name, 1, 12)_"' is refused")
	}
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "caf"_$Char(233)), "a bot name with a non-ASCII letter is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("telegramState"), before, "the refused calls left the mark as it was")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).RecordTelegram("on", $Translate($Justify("", 64), " ", "a")), "64 characters are allowed")
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", "not json")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "a mark that is not RecordTelegram's is off")
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", {"state": "paused", "botUserName": "x"}.%ToJSON())
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "and so is one with a state outside the three")
}

/// Delivery.Record accepts channel telegram and a ChannelMessageId of the form <ChatRef>:<message id>; FindByApproval finds it for its
/// owner only, and not for another session.
Method TestDeliveryRowForTelegram()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzpairrows"_..Number_"a")
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session("zzpairrows"_..Number_"b")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session_","_other
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(..ChatId(4), "Zz", .sc)
	Do ..Keep(##class(OcuTalon.Data.Pairing).Chat(chat))
	Set approval = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", chat_":42", approval), "the delivery is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", session), chat_":42", "it is found for its owner by the approval and channel")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "telegram", other), "", "not for another session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(approval, "web", session), "", "not for another channel")
	Do $$$AssertEquals($Length(chat_":42"), 25, "the id is 25 characters, inside MAXLEN 128")
}

/// A chat id of this run: 70, the run's number and the test's number, so that a rerun never meets an earlier run's row.
Method ChatId(n As %Integer) As %String [ Private ]
{
	Quit "70"_..Number_"0"_n
}

/// Records the row for the clean-up.
Method Keep(row As OcuTalon.Data.Pairing) [ Private ]
{
	If '$IsObject(row) Quit
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
}

/// The number of Pairing rows whose column holds exactly the value.
Method CountRows(column As %String, value As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE "_column_" = ?", value)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of Pairing rows.
Method CountAll() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Sets one column of the row with the ID and saves it.
Method SetColumn(id As %String, column As %String, value As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Pairing).%OpenId(id)
	Set $Property(row, column) = value
	Do row.%Save()
}

/// 1 when the row with the ID exists.
Method Exists(id As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Pairing).%ExistsId(id)
}

/// A chat row aged by the column: SeenAt or CreatedAt (then SeenAt is empty) is the time. session makes it a paired row. The row is
/// recorded for the clean-up. Returns the ID.
Method AgedChat(n As %Integer, time As %String, column As %String, session As %String = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(..ChatId(n), "Zz", .sc)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(ref)
	Do ..Keep(row)
	Set row.CreatedAt = $Select(column = "CreatedAt": time, 1: "2000-01-01T00:00:00Z")
	Set row.SeenAt = $Select(column = "SeenAt": time, 1: "")
	Set row.SessionRef = session
	Do row.%Save()
	Quit row.%Id()
}

/// A code row aged by its SeenAt. Returns the ID.
Method AgedCode(name As %String, time As %String) As %String [ Private ]
{
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(name_..Number)
	Do ##class(OcuTalon.Data.Pairing).StoreCode(##class(OcuTalon.Bridge.Ids).NewRef(), hash, "2030-01-01T00:00:00Z")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(hash)
	Do ..Keep(row)
	Set row.SeenAt = time
	Set row.CreatedAt = time
	Do row.%Save()
	Quit row.%Id()
}

}
