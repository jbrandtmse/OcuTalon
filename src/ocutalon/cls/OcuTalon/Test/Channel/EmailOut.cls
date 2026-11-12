Include Ensemble

/// Tests of EmailOut (OcuTalon.Channel.Email.Out) and its adapter Sender (Story 21.6; AD-1, AD-10, AD-14, AD-19, AD-25), through a shadow instance of
/// OcuTalon.Test.Channel.EmailOutProbe, whose Deliver stands in for the adapter, so nothing is opened and no mail is sent. Safe on a slot: the product keys
/// email.address and email.owner and the public setting onlineDemo are put back after the tests, and the approval requests and Delivery rows that a test
/// makes are deleted. Every text is written out here, never read from the product.
///   - TestTexts: the Message of each answer is the accepted public text;
///   - TestBadValues (matrix "Bad values", ruling b): no recipient, over 20, one that is not an address, a recipient or a subject with a carriage return, a
///     line feed or another control character (an injected header included), an empty or over-long subject, an empty or over-long text and a text with a
///     control character other than a tab or a line break are refused (Q2, Data {"fields": [...]}) and nothing is delivered; the edges are accepted;
///   - TestToolRecipients (ruling a): a tool send goes only to exactly one recipient equal, ignoring case, to email.address, from the session that is
///     email.owner; another address, an extra recipient, another or an empty session, and any other origin are refused and nothing is delivered;
///   - TestSystemApproval (ruling a): a system send needs the approval request of an email fix in the state executing whose recipients are, as a set of
///     lower-cased addresses, the command's; no request, no ApprovalRef, a pending, done or other-kind request, another FixKind, an extra, a missing or a
///     different recipient and unreadable parameters are refused, and nothing is delivered;
///   - TestNotConnected (Q3): with no email.address the answer is not_connected and nothing is delivered;
///   - TestOnlineDemo (ruling g): with the flag set every send is not_available (P2) and nothing is delivered;
///   - TestMessageShape (ruling b): the message is from the saved address, to the recipients, one plain part in UTF-8 with no attachment, and keeps
///     non-ASCII text; a tool send records one Delivery row of channel email with the owner and a new Ref, and no approval;
///   - TestFailureClasses (Q4, P1a, P1b): unreachable, refused and rejected sends answer failed with their sentences, once, with no Delivery row;
///   - TestNoDoubleSend (ruling f): a system send is claimed by its approval: the same approval again, after a restart of the operation, answers already_sent and
///     delivers nothing more; the claim is written pending before the send and cleared once the email is sent; after a failed send, an error after the claim,
///     or a claim whose send never finished, it answers failed and delivers nothing; the claim row of a failed send says failed;
///   - TestClaimIsLocked (ruling f): while another process holds the approval's lock a system send of it answers failed, delivers nothing and writes no claim;
///     with the lock free the same approval is sent once;
///   - TestUnexpectedErrorAnswersFailed: an error thrown inside the send is answered as failed, never as an error status;
///   - TestNoPersonalDataInTheLog: after sends and failures whose server words and addresses are known, no Ens.Util.Log row holds an address, a subject, a
///     text or the server's words;
///   - TestRefOnEveryPath (ruling V5): every mail carries the header X-OcuTalon-Ref, on the tool, system and digest paths, equal to the ChannelMessageId of its
///     Delivery row, 22 characters of 128 random bits, different on every send;
///   - TestDigestEmail (Story 21.7, ruling V1): a Notification of kind digest of the owner session is sent once from and to email.address, with the subject of
///     email.digestSubject and the text of DigestText for email, and records one Delivery row (Kind digest, the DecisionRef, a DigestKey, no text, no address);
///   - TestDigestRecipientIsFixed: nothing in the Notification chooses the recipient: addresses in its other properties and in its slots change nothing;
///   - TestDigestNotSent: a session that is not email.owner, an empty one, no owner, no address, an address that is none, the online demo, and every other kind
///     of Notification send nothing and record nothing, the other kinds with one warning;
///   - TestDigestRenderAndCaps: a piece that does not render, Slots that are no JSON and a text over the limit send nothing and record nothing, with one warning;
///   - TestDigestFailures: an unreachable, refusing, rejecting or throwing server is one try, no Delivery row, one warning with the class only, and no words of
///     the server; the operation answers OK;
///   - TestDigestNoDoubleSend (ruling f): the same Notification again sends nothing, also after a restart of the operation, and another digest is sent;
///   - TestDigestDailyCap (ruling V1): the 11th digest to the mailbox in one UTC day is refused, logged without contents and not sent; the rows of an earlier
///     day, of another owner and of other kinds do not count;
///   - TestDigestLock: while another process holds the lock of the digest emails nothing is sent;
///   - TestDigestNoPersonalDataInTheLog: after digests and failures the log holds no address, subject, text, key or server words;
///   - TestSenderInit, TestSenderTransport, TestSenderTlsSettings, TestSenderNoConnection, TestClassify (ruling c, Sender): OnInit forces the identity check on and ContinueAfterBadSend off
///     whatever the settings say; the transport is plain only with the switch on and the host mock, TLS only for OcuTalonClient and OcuTalonClient*, and
///     nothing otherwise; %Net.SMTP is given STARTTLS only for the star, the TLS configuration with the identity checked, and no partial send; a send with an empty or foreign SSLConfig, or with no credential, fails at once, before any connection; Classify tells
///     unreachable, refused and rejected.
Class OcuTalon.Test.Channel.EmailOut Extends %UnitTest.TestCase
{

/// The operation under test.
Parameter PROBE = "OcuTalon.Test.Channel.EmailOutProbe";

Parameter ADDRESS = "zzemailout@example.com";

Parameter OWNER = "zzemailoutowner0001";

Parameter OTHER = "zzemailoutother00002";

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("EmailOut")
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("EmailOut", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Set ^OcuTalonTest("EmailOut", "online") = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
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
		If $Data(^OcuTalonTest("EmailOut", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Get(^OcuTalonTest("EmailOut", "online")))
	Kill ^OcuTalonTest("EmailOut"), ^OcuTalonTest("EmailOutLock")
	Kill ^||OcuTalonEmailOutProbe, ^||OcuTalonEmailOutSender
	Quit $$$OK
}

/// Ruling V5: the header X-OcuTalon-Ref is on every path's mail, is the ChannelMessageId of the mail's Delivery row, is a Ref of 22 characters (128 random bits)
/// and is different on every send.
Method TestRefOnEveryPath()
{
	Do ..Mailbox()
	Set tool = ..Send("tool", ..#OWNER, ..#ADDRESS, "tool", "text")
	Set approval = ..Approval("zzemailoutap0070", ..#ADDRESS)
	Set system = ..Send("system", ..#OWNER, ..#ADDRESS, "system", "text", approval)
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(1))
	Do $$$AssertEquals(..Delivered(), 3, "three mails were delivered")
	Set claim = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval))
	Set digest = ##class(OcuTalon.Data.Delivery).%OpenId(..DigestRowId())
	Set toolRow = ##class(OcuTalon.Data.Delivery).%OpenId(..DeliveryIds(..#OWNER))
	Do $$$AssertEquals($List(^||OcuTalonEmailOutProbe("sent", 1), 9), toolRow.ChannelMessageId, "tool: the header is the Delivery row's message id")
	Do $$$AssertEquals($List(^||OcuTalonEmailOutProbe("sent", 2), 9), claim.ChannelMessageId, "system: the header is the claim row's message id")
	Do $$$AssertEquals($List(^||OcuTalonEmailOutProbe("sent", 3), 9), digest.ChannelMessageId, "digest: the header is the Delivery row's message id")
	Set refs = $ListBuild(toolRow.ChannelMessageId, claim.ChannelMessageId, digest.ChannelMessageId)
	Set position = 0
	While $ListNext(refs, position, ref) {
		Do $$$AssertTrue(ref ? 22(1AN,1"-",1"_"), "the Ref is 22 characters of the Ref alphabet: "_$Length(ref))
	}
	Do $$$AssertEquals($ListLength(refs), 3, "three Refs")
	Do $$$AssertTrue(($List(refs, 1) '= $List(refs, 2)) && ($List(refs, 2) '= $List(refs, 3)) && ($List(refs, 1) '= $List(refs, 3)), "all different")
	Do $$$AssertTrue(($List(refs, 1)_$List(refs, 2)_$List(refs, 3)) '[ "zzemailout", "and none holds the session or the address")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "tool again", "text")
	Do $$$AssertTrue($List(^||OcuTalonEmailOutProbe("sent", 4), 9) '= $List(refs, 1), "a second send has another Ref")
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(2))
	Do $$$AssertTrue(($List(^||OcuTalonEmailOutProbe("sent", 5), 9) '= "") && ($List(^||OcuTalonEmailOutProbe("sent", 5), 9) '= $List(refs, 3)), "a second digest has another Ref")
	Do $$$AssertEquals($Length($SYSTEM.Encryption.Base64Decode($Translate($List(refs, 1), "-_", "+/")_"==")), 16, "to 16 bytes")
}

/// The Id of the newest Delivery row of kind digest.
ClassMethod DigestRowId() As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND Kind = 'digest' ORDER BY ID DESC")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The Slots of a digest: three parts and no coverage line (a line shows a time, which follows the instance zone); n makes the digest differ from another.
ClassMethod DigestSlots(n As %Integer) As %String [ Private ]
{
	Quit {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.savedNone", "slots": {}}, {"key": "digest.cost", "slots": {"cost": (n / 100)}}], "lines": [], "rows": []}.%ToJSON()
}

/// A Notification of the kind to EmailOut's Notification path; the status is OK and the response is empty.
Method Notify(kind As %String, sessionRef As %String, slots As %String, decisionRef As %String = "ZzDigestDecision001") As OcuTalon.Msg.Notification [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = kind
	Set notification.CatalogKey = "digest.cost"
	Set notification.DecisionRef = decisionRef
	Set notification.Slots = slots
	Set sc = probe.OnNotification(notification, .response)
	Do $$$AssertStatusOK(sc, "the Notification is handled with an OK status")
	Do $$$AssertEquals(response, "", "and no response")
	Quit notification
}

/// The texts of the log rows of EmailOut after the row id start, as a list.
ClassMethod LogTexts(start As %Integer) As %List [ Private ]
{
	Set texts = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Text [ 'EmailOut' ORDER BY ID", start)
	While result.%Next() {
		Set texts = texts_$ListBuild(result.%GetData(1))
	}
	Quit texts
}

ClassMethod LastLog() As %Integer [ Private ]
{
	Set last = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do last.%Next()
	Quit +last.%GetData(1)
}

/// Story 21.7, ruling V1: a digest of the mailbox owner goes once to email.address.
Method TestDigestEmail()
{
	Do ..Mailbox()
	Set slots = ..DigestSlots(4)
	Set expected = ##class(OcuTalon.Channel.DigestText).Text(slots, "email", .sc)
	Do $$$AssertStatusOK(sc, "the shared helper renders the digest for email")
	Do $$$AssertEquals(expected, ##class(OcuTalon.Channel.DigestText).Text(slots, "phone"), "the email text is the phone text")
	Do $$$AssertEquals(expected, "Good morning."_$Char(10)_"Nothing was saved for later."_$Char(10)_"Yesterday's cost: $0.04.", "and it is this text")
	Set before = ..LastLog()
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 1, "one mail is delivered")
	Set sent = ^||OcuTalonEmailOutProbe("sent", 1)
	Do $$$AssertEquals($List(sent, 1)_"|"_$List(sent, 2), ..#ADDRESS_"|"_..#ADDRESS, "from and to email.address")
	Do $$$AssertEquals($List(sent, 3), "Your OcuTalon digest", "with the subject of email.digestSubject")
	Do $$$AssertEquals($List(sent, 4), expected, "and the text of the digest for email")
	Do $$$AssertEquals($List(sent, 5)_"|"_$List(sent, 6)_"|"_$List(sent, 7)_"|"_$List(sent, 8), "UTF-8|0|0|0", "one UTF-8 part: not multipart, no attachment, no Cc or Bcc")
	Do $$$AssertEquals(..Deliveries(..#OWNER), 1, "one Delivery row of channel email for the owner")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..DigestRowId())
	Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.ApprovalRef_"|"_row.Text_"|"_row.FallbackReason_"|"_row.CheckRows_"|"_row.DueAt, ..#OWNER_"|email|digest|ZzDigestDecision001|||||", "its owner, channel, kind and decision, and no approval, text, reason, rows or due time")
	Do $$$AssertEquals($List(sent, 9), row.ChannelMessageId, "the header X-OcuTalon-Ref is the row's message id")
	Do $$$AssertEquals($Length(row.DigestKey), 22, "and the row keeps the key of the digest")
	Do $$$AssertEquals(row.DigestKey, ##class(OcuTalon.Channel.Email.Out).DigestKeyOf(..Notification(..#OWNER, slots)), "which is the key of the Notification")
	Do $$$AssertEquals($ListToString(..LogTexts(before), "|"), "EmailOut sent one digest email", "the log holds one line about it")
}

/// A Notification as Notify would route it, for the key.
ClassMethod Notification(sessionRef As %String, slots As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = "digest"
	Set notification.CatalogKey = "digest.cost"
	Set notification.DecisionRef = "ZzDigestDecision001"
	Set notification.Slots = slots
	Quit notification
}

/// Ruling V1: nothing in the Notification names the recipient.
Method TestDigestRecipientIsFixed()
{
	Do ..Mailbox()
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Set notification = ..Notification(..#OWNER, ..DigestSlots(5))
	Set notification.ChatRef = "zzother1@example.com"
	Set notification.ApprovalRef = "zzother2@example.com"
	Set notification.IncidentRef = "zzother3@example.com"
	Set notification.CatalogKey = "zzother4@example.com"
	Set notification.DecisionRef = "zzother5@example.com"
	Do $$$AssertStatusOK(probe.OnNotification(notification, .response), "a Notification that names other addresses in every property is handled")
	Do $$$AssertEquals(..Delivered(), 1, "one mail is delivered")
	Set sent = ^||OcuTalonEmailOutProbe("sent", 1)
	Do $$$AssertEquals($List(sent, 1)_"|"_$List(sent, 2), ..#ADDRESS_"|"_..#ADDRESS, "to email.address alone")
	Do $$$AssertTrue(($List(sent, 3)_$List(sent, 4)) '[ "zzother", "and the subject and text hold none of them")
	Set slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.saved", "slots": {"count": 1, "summary": "Write to zzother6@example.com."}}], "lines": [], "rows": []}.%ToJSON()
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals($List(^||OcuTalonEmailOutProbe("sent", 2), 2), ..#ADDRESS, "an address in the digest's own text is text, not a recipient")
	Do $$$AssertEquals(..Delivered(), 2, "and the second mail is delivered too")
}

/// The Notifications that send nothing.
Method TestDigestNotSent()
{
	Do ..Mailbox()
	Set slots = ..DigestSlots(6)
	Set before = ..LastLog()
	For session = ..#OTHER, "", "instance", "eval", $ZConvert(..#OWNER, "U") {
		Do ..Notify("digest", session, slots)
		Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER)_"|"_..Deliveries(..#OTHER), "0|0|0", "session '"_session_"' is not the mailbox owner: nothing is sent or recorded")
	}
	Do ##class(OcuTalon.Data.Setting).%DeleteId(##class(OcuTalon.Data.Setting).KeyIndexOpen("email.owner").%Id())
	Kill ^||OcuTalon.Setting("email.owner")
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 0, "with no email.owner nothing is sent")
	Do ..Mailbox()
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "not an address")
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 0, "an email.address that is not an address is no recipient")
	Do ##class(OcuTalon.Data.Setting).%DeleteId(##class(OcuTalon.Data.Setting).KeyIndexOpen("email.address").%Id())
	Kill ^||OcuTalon.Setting("email.address")
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 0, "with no email.address nothing is sent")
	Do $$$AssertEquals($ListLength(..LogTexts(before)), 0, "and none of this is logged")
	Do ..Mailbox()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "0|0", "the online demo sends nothing, whatever the rows say")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set kinds = $ListFromString("tellnow,reminder,allowance,incident,approval,result,summary,answered,handled,pairing,status,fallback,")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set before = ..LastLog()
		Do ..Notify(kind, ..#OWNER, slots)
		Do $$$AssertEquals(..Delivered()_"|"_$ListToString(..LogTexts(before), "|"), "0|EmailOut takes a notification of kind digest only, so it sent nothing", "kind '"_kind_"': nothing is sent, one warning")
	}
	Do $$$AssertEquals(..Deliveries(..#OWNER), 0, "no Delivery row was recorded")
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 1, "and the same Notification as a digest is sent once everything is in order")
}

/// A piece that does not render, Slots that are no JSON and a text over the limit.
Method TestDigestRenderAndCaps()
{
	Do ..Mailbox()
	Set cases = $ListBuild(
		$ListBuild("an unknown part key", {"parts": [{"key": "digest.noSuchKey", "slots": {}}], "lines": []}.%ToJSON()),
		$ListBuild("a part with a slot of the wrong type", {"parts": [{"key": "digest.cost", "slots": {"cost": "free"}}], "lines": []}.%ToJSON()),
		$ListBuild("Slots that are no JSON", "{not json"),
		$ListBuild("Slots with no parts", {"lines": []}.%ToJSON()),
		$ListBuild("Slots with no lines", {"parts": []}.%ToJSON()),
		$ListBuild("empty Slots", ""),
		$ListBuild("a text over the limit", {"parts": [{"key": "digest.saved", "slots": {"count": 1, "summary": ($Translate($Justify("", 100001), " ", "s"))}}], "lines": []}.%ToJSON()))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set before = ..LastLog()
		Do ..Notify("digest", ..#OWNER, $List(case, 2))
		Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "0|0", $List(case, 1)_": nothing is sent or recorded")
		Do $$$AssertEquals($ListLength(..LogTexts(before)), 1, $List(case, 1)_": one warning is logged")
	}
}

/// An unreachable, refusing, rejecting or throwing server.
Method TestDigestFailures()
{
	Do ..Mailbox()
	Set expected = "unreachable|refused|rejected|throw"
	For i = 1:1:4 {
		Set answer = $Piece(expected, "|", i)
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Set before = ..LastLog()
		Set calls = ..Delivered()
		Do ..Notify("digest", ..#OWNER, ..DigestSlots(10 + i))
		Do $$$AssertEquals(..Delivered() - calls, 1, answer_": one try")
		Do $$$AssertEquals(..Deliveries(..#OWNER), 0, answer_": no Delivery row")
		Set texts = ..LogTexts(before)
		Do $$$AssertEquals($ListLength(texts), 1, answer_": one log line")
		Set prefix = $Select(answer = "throw": "EmailOut failed: ", 1: "EmailOut did not send the digest email: ")
		Do $$$AssertEquals($Extract($List(texts, 1), 1, $Length(prefix)), prefix, answer_": it says "_$Select(answer = "throw": "the send failed", 1: "a digest email was not sent")_": "_$List(texts, 1))
		Do $$$AssertTrue(($List(texts, 1) '[ "SERVER-WORDS") && ($List(texts, 1) '[ "zz"), answer_": with no server words or address")
	}
	Do $$$AssertEquals(..Delivered(), 4, "four tries in all, none repeated")
	Kill ^||OcuTalonEmailOutProbe("answer")
}

/// Ruling f: a digest is sent once.
Method TestDigestNoDoubleSend()
{
	Do ..Mailbox()
	Set slots = ..DigestSlots(20)
	Do ..Notify("digest", ..#OWNER, slots)
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "1|1", "the same Notification twice is one mail and one row")
	Kill ^||OcuTalonEmailOutProbe("sent")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(probe.OnNotification(..Notification(..#OWNER, slots), .response), "in a new instance of the operation")
	Do $$$AssertEquals($Data(^||OcuTalonEmailOutProbe("sent")), 0, "the Notification again sends nothing (the key is a table row)")
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(21))
	Do $$$AssertEquals(..Deliveries(..#OWNER), 2, "another digest is sent")
	Set other = ..Notification(..#OWNER, slots)
	Set other.DecisionRef = "ZzDigestDecision002"
	Kill ^||OcuTalonEmailOutProbe("sent")
	Do $$$AssertStatusOK(probe.OnNotification(other, .response), "the digest of another decision with the same Slots")
	Do $$$AssertEquals($Data(^||OcuTalonEmailOutProbe("sent")) > 0, 1, "is another digest and is sent")
}

/// Ruling V1: at most MAXDIGESTS digest emails to the mailbox in one UTC day.
Method TestDigestDailyCap()
{
	Do ..Mailbox()
	Do $$$AssertEquals($Parameter(..#PROBE, "MAXDIGESTS"), 10, "the limit is 10 a day")
	Do ..SeedDigestRow(..#OWNER, "digest", "2020-01-01T23:59:59Z")
	Do ..SeedDigestRow(..#OTHER, "digest", ##class(OcuTalon.Data.Time).NowUtc())
	Do ..SeedDigestRow(..#OWNER, "tellnow", ##class(OcuTalon.Data.Time).NowUtc())
	Set before = ..LastLog()
	For n = 1:1:11 {
		Do ..Notify("digest", ..#OWNER, ..DigestSlots(30 + n))
	}
	Do $$$AssertEquals(..Delivered(), 10, "the 11th digest of the day is not sent: 10 mails")
	Do $$$AssertEquals(..DigestRows(..#OWNER), 11, "10 rows of today and the earlier day's row")
	Set texts = ..LogTexts(before)
	Do $$$AssertEquals($ListLength(texts), 11, "10 info lines and one warning")
	Do $$$AssertEquals($List(texts, 11), "EmailOut refused a digest email: the limit of 10 digest emails a day was reached, so it sent nothing", "the refusal is logged, with no contents")
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(50))
	Do $$$AssertEquals(..Delivered(), 10, "and a later one on the same day is refused too")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Delivery SET RecordedAt = '2020-01-02T00:00:00Z' WHERE OwnerRef = ? AND Channel = 'email' AND Kind = 'digest' AND RecordedAt > '2021'", ..#OWNER)
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(51))
	Do $$$AssertEquals(..Delivered(), 11, "once the rows are of an earlier day the digest is sent again")
}

/// A Delivery row of channel email for the owner, kind and time.
Method SeedDigestRow(owner As %String, kind As %String, at As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(owner, "email", ##class(OcuTalon.Bridge.Ids).NewRef(), "", kind, "", "", "", "", .row), "a seeded row")
	Set row.RecordedAt = at
	Do $$$AssertStatusOK(row.%Save(), "with its time")
}

ClassMethod DigestRows(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND Kind = 'digest' AND OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// While another process holds the lock of the owner's digest emails nothing is sent.
Method TestDigestLock()
{
	Do ..Mailbox()
	Kill ^OcuTalonTest("EmailOutLock")
	Job ##class(OcuTalon.Test.Channel.EmailOut).HoldDigestLock(..#OWNER)
	Set held = ..WaitFlag("held")
	Try {
		Do $$$AssertTrue(held, "the other process holds the lock")
		If held {
			Set before = ..LastLog()
			Do ..Notify("digest", ..#OWNER, ..DigestSlots(60))
			Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "0|0", "nothing is sent or recorded while the lock is held")
			Do $$$AssertEquals($ListToString(..LogTexts(before), "|"), "EmailOut could not take the lock of the digest emails, so it sent nothing", "one warning")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Set ^OcuTalonTest("EmailOutLock", "release") = 1
	Do $$$AssertTrue(..WaitFlag("done"), "the other process released the lock")
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(60))
	Do $$$AssertEquals(..Delivered(), 1, "with the lock free the digest is sent")
	Kill ^OcuTalonTest("EmailOutLock")
}

/// Holds the lock of the owner's digest emails until released (a job of TestDigestLock).
ClassMethod HoldDigestLock(owner As %String)
{
	Lock +^OcuTalon.EmailOut.Digest(owner):5
	If '$Test Quit
	Set ^OcuTalonTest("EmailOutLock", "held") = 1
	Set deadline = $ZHorolog + 60
	While ('$Data(^OcuTalonTest("EmailOutLock", "release"))) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -^OcuTalon.EmailOut.Digest(owner)
	Set ^OcuTalonTest("EmailOutLock", "done") = 1
}

/// After digests and failures no log row holds an address, a subject, a text, a key or the server's words.
Method TestDigestNoPersonalDataInTheLog()
{
	Do ..Mailbox()
	Set tag = $Translate($ZHorolog, ".", "")_$Job
	Set address = "zzlogaddr"_tag_"@example.com"
	Do ##class(OcuTalon.Data.Setting).Set("email.address", address)
	Set summary = "zzlogsummary"_tag
	Set slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.saved", "slots": {"count": 1, "summary": (summary)}}], "lines": [], "rows": []}.%ToJSON()
	Do ..Notify("digest", ..#OWNER, slots)
	Set key = ##class(OcuTalon.Data.Delivery).%OpenId(..DigestRowId()).DigestKey
	Set ref = ##class(OcuTalon.Data.Delivery).%OpenId(..DigestRowId()).ChannelMessageId
	For answer = "unreachable", "refused", "rejected", "throw" {
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Do ..Notify("digest", ..#OWNER, {"parts": [{"key": "digest.saved", "slots": {"count": 1, "summary": (summary_answer)}}], "lines": []}.%ToJSON())
	}
	Kill ^||OcuTalonEmailOutProbe("answer")
	For word = address, summary, "Your OcuTalon digest", key, ref, "SERVER-WORDS", "zzrejected@example.com", "zzthrown@example.com", $Piece(address, "@", 1) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", word), 0, "no Ens.Util.Log row holds '"_word_"'")
	}
}

/// The public text of every answer, written out.
Method TestTexts()
{
	Set class = "OcuTalon.Channel.Email.Out"
	Do $$$AssertEquals($Parameter(class, "MESSAGESENT"), "The email was sent.", "Q1")
	Do $$$AssertEquals($Parameter(class, "MESSAGEREFUSED"), "The email wasn't sent because a recipient, the subject or the text wasn't allowed.", "Q2, as edited")
	Do $$$AssertEquals($Parameter(class, "MESSAGENOTCONNECTED"), "No outgoing mail server is connected, so the email wasn't sent.", "Q3")
	Do $$$AssertEquals($Parameter(class, "MESSAGEREJECTED"), "The mail server didn't accept the email, so it wasn't sent.", "Q4")
	Do $$$AssertEquals($Parameter(class, "MESSAGEUNREACHABLE"), "OcuTalon couldn't reach the mail server.", "P1a")
	Do $$$AssertEquals($Parameter(class, "MESSAGEREFUSEDLOGIN"), "The mail server refused the user name or password.", "P1b")
	Do $$$AssertEquals($Parameter(class, "MESSAGEUNAVAILABLE"), "Email can't be connected on the online demo. Nothing was changed.", "P2")
	Do $$$AssertEquals($Parameter("OcuTalon.Core.CommandsIn", "MESSAGENOTCONNECTED"), $Parameter(class, "MESSAGENOTCONNECTED"), "CommandsIn answers Q3 as well")
}

/// Matrix "Bad values" and ruling b: every refused kind of value names its field and delivers nothing; the edges go through.
Method TestBadValues()
{
	Do ..Mailbox()
	Set cr = $Char(13), lf = $Char(10), tab = $Char(9)
	Set many = ""
	For i = 1:1:21 Set many = many_$Select(many = "": "", 1: ",")_"zzr"_i_"@example.com"
	Set cases = $ListBuild(
		$ListBuild("no recipient", "", "ok", "ok", "recipients"),
		$ListBuild("a blank recipient list", "  ", "ok", "ok", "recipients"),
		$ListBuild("an empty recipient between two", ..#ADDRESS_",,"_..#ADDRESS, "ok", "ok", "recipients"),
		$ListBuild("a recipient that is not an address", "not an address", "ok", "ok", "recipients"),
		$ListBuild("an address with two @", "a@b@example.com", "ok", "ok", "recipients"),
		$ListBuild("an injected header after a carriage return", ..#ADDRESS_cr_lf_"Bcc: zzevil@example.com", "ok", "ok", "recipients"),
		$ListBuild("a recipient with a line feed", ..#ADDRESS_lf, "ok", "ok", "recipients"),
		$ListBuild("a recipient with a tab", tab_..#ADDRESS_tab_"x", "ok", "ok", "recipients"),
		$ListBuild("21 recipients", many, "ok", "ok", "recipients"),
		$ListBuild("an empty subject", ..#ADDRESS, "", "ok", "subject"),
		$ListBuild("a blank subject", ..#ADDRESS, "   ", "ok", "subject"),
		$ListBuild("a subject of 201 characters", ..#ADDRESS, $Translate($Justify("", 201), " ", "s"), "ok", "subject"),
		$ListBuild("a subject with a carriage return", ..#ADDRESS, "a"_cr_"Bcc: zzevil@example.com", "ok", "subject"),
		$ListBuild("a subject with a line feed", ..#ADDRESS, "a"_lf_"b", "ok", "subject"),
		$ListBuild("a subject with a tab", ..#ADDRESS, "a"_tab_"b", "ok", "subject"),
		$ListBuild("a subject with a NUL", ..#ADDRESS, "a"_$Char(0)_"b", "ok", "subject"),
		$ListBuild("an empty text", ..#ADDRESS, "ok", "", "text"),
		$ListBuild("a blank text", ..#ADDRESS, "ok", " "_lf, "text"),
		$ListBuild("a text of 100001 characters", ..#ADDRESS, "ok", $Translate($Justify("", 100001), " ", "t"), "text"),
		$ListBuild("a text with a NUL", ..#ADDRESS, "ok", "a"_$Char(0)_"b", "text"),
		$ListBuild("a text with an escape", ..#ADDRESS, "ok", "a"_$Char(27)_"b", "text"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Send("tool", ..#OWNER, $List(case, 2), $List(case, 3), $List(case, 4))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_$Parameter(..#PROBE, "MESSAGEREFUSED"), $List(case, 1)_" is refused")
		Do $$$AssertTrue(result.Data [ ("""fields"":[""" _ $List(case, 5) _ """"), $List(case, 1)_": the refused field is "_$List(case, 5)_" ("_result.Data_")")
		Do $$$AssertEquals(..Delivered(), 0, $List(case, 1)_": nothing is delivered")
	}
	Set n = 0
	For injected = "zzr@example.com"_lf, "zzr@example.com"_cr_lf_"Bcc: zzevil@example.com", "zzr@example.com"_$Char(0), "zzr"_tab_"@example.com", "zzr@example.com"_$Char(11) {
		Set n = n + 1
		Set approval = ..Approval("zzemailoutap01"_$Justify(n, 2, 0), injected)
		Set result = ..Send("system", ..#OWNER, injected, "ok", "ok", approval)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "the system path, whose approval names the very same recipient, refuses a control character in it (case "_n_")")
	}
	For notAddress = "not an address", "a@b@example.com", "zzr@" {
		Set n = n + 1
		Set approval = ..Approval("zzemailoutap01"_$Justify(n, 2, 0), notAddress)
		Set result = ..Send("system", ..#OWNER, notAddress, "ok", "ok", approval)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""recipients""]}", "the system path, whose approval names the very same recipient, refuses one that is not an address ('"_notAddress_"')")
	}
	Do $$$AssertEquals(..Delivered(), 0, "none of them delivered anything")
	Set result = ..Send("tool", ..#OWNER, "bad", "", "")
	Do $$$AssertEquals(result.Data, "{""fields"":[""recipients"",""subject"",""text""]}", "every refused field is named, in the order recipients, subject, text")
	Set longText = $Translate($Justify("", 100000), " ", "t")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, $Translate($Justify("", 200), " ", "s"), longText)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "a subject of 200 characters and a text of 100000 are accepted")
	Set result = ..Send("tool", ..#OWNER, " "_..#ADDRESS_" ", "tab and line breaks", "a"_tab_"b"_cr_lf_"c"_lf_"d")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "a text with a tab and line breaks and a recipient with spaces around it are accepted")
	Set approval = ..Approval("zzemailoutap0001", ..Many(20))
	Set result = ..Send("system", ..#OWNER, ..Many(20), "twenty", "ok", approval)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "20 recipients are accepted on the system path")
	Set approval = ..Approval("zzemailoutap0002", ..Many(21))
	Set result = ..Send("system", ..#OWNER, ..Many(21), "twenty-one", "ok", approval)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""recipients""]}", "21 recipients are refused on the system path, though the approval names all of them")
}

/// Ruling a, origin tool: only the own address, once, from the owner's session.
Method TestToolRecipients()
{
	Do ..Mailbox()
	For recipients = ..#ADDRESS, "ZZEmailOut@Example.com", "  "_..#ADDRESS_"  " {
		Set result = ..Send("tool", ..#OWNER, recipients, "ok", "ok")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "'"_recipients_"' is the own address and is sent")
	}
	Do $$$AssertEquals(..Delivered(), 3, "three mails were delivered")
	Set refused = $Parameter(..#PROBE, "MESSAGEREFUSED")
	Kill ^||OcuTalonEmailOutProbe
	For recipients = "other@example.com", ..#ADDRESS_",other@example.com", ..#ADDRESS_","_..#ADDRESS, "other@example.com,"_..#ADDRESS, ..#ADDRESS_"x" {
		Set result = ..Send("tool", ..#OWNER, recipients, "ok", "ok")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_refused, "'"_recipients_"' is refused")
	}
	Set result = ..Send("tool", ..#OTHER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "refused", "another session than email.owner is refused")
	Set result = ..Send("tool", "", ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "refused", "an empty session is refused")
	For origin = "web_admin", "web_user", "timer", "telegram", "" {
		Set result = ..Send(origin, ..#OWNER, ..#ADDRESS, "ok", "ok")
		Do $$$AssertEquals(result.Outcome, "refused", "origin '"_origin_"' is refused")
	}
	Do $$$AssertEquals(..Delivered(), 0, "nothing was delivered by a refusal")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", ..#OTHER)
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "refused", "when the mailbox has moved to another session the first one is refused")
	Set result = ..Send("tool", ..#OTHER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "sent", "and the new owner is sent")
}

/// Ruling a, origin system: the approval request of an executing email fix names the recipients.
Method TestSystemApproval()
{
	Do ..Mailbox()
	Set refused = $Parameter(..#PROBE, "MESSAGEREFUSED")
	Set list = "zza@example.com,zzb@example.com"
	Set good = ..Approval("zzemailoutap0010", list)
	Set result = ..Send("system", "", "ZZB@example.com, zza@example.com", "fix", "text", good)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "the same recipients as a set, in another order and case, are sent")
	Do $$$AssertEquals($ListGet(^||OcuTalonEmailOutProbe("sent", 1), 2), "ZZB@example.com,zza@example.com", "to the command's recipients")
	Kill ^||OcuTalonEmailOutProbe
	Set cases = $ListBuild(
		$ListBuild("no ApprovalRef", ""),
		$ListBuild("a Ref with no request", "zzemailoutnone0001"),
		$ListBuild("a pending request", ..Approval("zzemailoutap0011", list, "fix", "pending")),
		$ListBuild("a done request", ..Approval("zzemailoutap0012", list, "fix", "done")),
		$ListBuild("a tool_call request", ..Approval("zzemailoutap0013", list, "tool_call")),
		$ListBuild("a setting request", ..Approval("zzemailoutap0014", list, "setting")),
		$ListBuild("another fix kind", ..Approval("zzemailoutap0015", list, "fix", "executing", "repair")),
		$ListBuild("a request with no recipients member", ..Approval("zzemailoutap0016", "", "fix", "executing", "email", "{""x"": 1}")),
		$ListBuild("a request with empty recipients", ..Approval("zzemailoutap0017", "")),
		$ListBuild("a request with parameters that are not JSON", ..Approval("zzemailoutap0018", list, "fix", "executing", "email", "not json")),
		$ListBuild("a request whose recipients are not an array", ..Approval("zzemailoutap0019", list, "fix", "executing", "email", "{""recipients"": ""zza@example.com,zzb@example.com""}")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Send("system", "", list, "fix", "text", $List(case, 2))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_refused, $List(case, 1)_" is refused")
	}
	Set approval = ..Approval("zzemailoutap0020", list)
	For recipients = "zza@example.com", "zza@example.com,zzb@example.com,zzc@example.com", "zza@example.com,zzc@example.com", "zzc@example.com", "zza@example.com,zza@example.com" {
		Set result = ..Send("system", "", recipients, "fix", "text", approval)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "'"_recipients_"' is not the set of the request and is refused")
	}
	Do $$$AssertEquals(..Delivered(), 0, "nothing was delivered by a refusal")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "tool", "text", good)
	Do $$$AssertEquals(result.Outcome, "sent", "a tool send ignores an ApprovalRef and goes by the own address")
}

/// Q3: no outgoing mail server connected (no mailbox address).
Method TestNotConnected()
{
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_connected|No outgoing mail server is connected, so the email wasn't sent.", "with no email.address the answer is not_connected")
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "not an address")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "not_connected", "an address that is not an address is no mailbox either")
	Do $$$AssertEquals(..Delivered(), 0, "nothing was delivered")
}

/// Ruling g: the online demo refuses whatever else is true.
Method TestOnlineDemo()
{
	Do ..Mailbox()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	For origin = "tool", "system" {
		Set result = ..Send(origin, ..#OWNER, ..#ADDRESS, "ok", "ok", ..Approval("zzemailoutap0030"_origin, ..#ADDRESS))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|Email can't be connected on the online demo. Nothing was changed.", "origin "_origin_": not_available on the online demo")
	}
	Do $$$AssertEquals(..Delivered(), 0, "nothing was delivered")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
	Do $$$AssertEquals(result.Outcome, "sent", "and the same send goes through off the online demo")
}

/// Ruling b and the Delivery row: one plain UTF-8 part, from the saved address, no attachment.
Method TestMessageShape()
{
	Do ..Mailbox()
	Set text = "Gr"_$Char(252, 223)_"e "_$Char(8364)_$Char(10)_"second line"
	Set subject = "Subject "_$Char(228)_" "_$Char(8364)
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, subject, text)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|sent|The email was sent.", "the send is sent (Q1)")
	Set sent = ^||OcuTalonEmailOutProbe("sent", 1)
	Do $$$AssertEquals($List(sent, 1)_"|"_$List(sent, 2), ..#ADDRESS_"|"_..#ADDRESS, "from the saved address, to the recipient")
	Do $$$AssertEquals($List(sent, 3), subject, "with the subject as sent (non-ASCII kept)")
	Do $$$AssertEquals($List(sent, 4), text, "and the text as sent (non-ASCII kept)")
	Do $$$AssertEquals($List(sent, 5)_"|"_$List(sent, 6)_"|"_$List(sent, 7)_"|"_$List(sent, 8), "UTF-8|0|0|0", "one UTF-8 part: not multipart, no attachment part, no Cc or Bcc")
	Do $$$AssertEquals(..Deliveries(..#OWNER), 1, "one Delivery row of channel email for the owner")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..DeliveryIds(..#OWNER))
	Do $$$AssertEquals(row.Channel_"|"_row.ApprovalRef_"|"_row.Text_"|"_row.FallbackReason, "email|||", "with no approval, no text and no fallback reason")
	Do $$$AssertTrue($Length(row.ChannelMessageId) >= 16, "and a new Ref as the message id")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "again", "again")
	Do $$$AssertEquals(..Deliveries(..#OWNER), 2, "a second send is a second row")
	Do $$$AssertEquals(..DistinctRefs(..#OWNER), 2, "with another Ref")
	Do ..Mailbox()
	Set approval = ..Approval("zzemailoutap0040", ..#ADDRESS)
	Set result = ..Send("system", "", ..#ADDRESS, "system mail", "text", approval)
	Do $$$AssertEquals(result.Outcome, "sent", "a system send with no session is sent")
	Do $$$AssertEquals(..Claims(approval), 1, "recorded once")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval))
	Do $$$AssertEquals(row.OwnerRef_"|"_row.ApprovalRef, "instance|"_approval, "for the owner instance, with the approval's Ref")
}

/// Q4, P1a, P1b: each failure class answers failed with its sentence, after one try.
Method TestFailureClasses()
{
	Do ..Mailbox()
	Set cases = $ListBuild("unreachable|OcuTalon couldn't reach the mail server.", "refused|The mail server refused the user name or password.", "rejected|The mail server didn't accept the email, so it wasn't sent.")
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^||OcuTalonEmailOutProbe
		Set ^||OcuTalonEmailOutProbe("answer") = $Piece(case, "|", 1)
		Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|failed|"_$Piece(case, "|", 2), $Piece(case, "|", 1)_": failed with its sentence")
		Do $$$AssertEquals(..Delivered(), 1, $Piece(case, "|", 1)_": one try, no retry")
		Do $$$AssertEquals(result.Message_result.Data [ "SERVER-WORDS", 0, $Piece(case, "|", 1)_": the answer holds no server words")
	}
	Do $$$AssertEquals(..Deliveries(..#OWNER), 0, "no failed send leaves a Delivery row")
}

/// Ruling f: a system send is sent once per approval, also after a restart and after a failure.
Method TestNoDoubleSend()
{
	Do ..Mailbox()
	Set approval = ..Approval("zzemailoutap0050", ..#ADDRESS)
	Set first = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
	Do $$$AssertEquals(first.Ok_"|"_first.Outcome, "1|sent", "the first send of the approval is sent")
	Do $$$AssertEquals($Get(^||OcuTalonEmailOutProbe("claim", 1)), "pending", "its claim was written, marked pending, before the send")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval)).FallbackReason, "", "and the claim of the sent email is no longer marked")
	Set again = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Message, "1|already_sent|The email was sent.", "the same approval again is already_sent (Q1)")
	Do $$$AssertEquals(..Delivered(), 1, "and delivers nothing more")
	Do $$$AssertEquals(..Claims(approval), 1, "the claim is one Delivery row of channel email with the approval's Ref")
	Kill ^||OcuTalonEmailOutProbe("sent")
	Set restarted = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
	Do $$$AssertEquals(restarted.Outcome, "already_sent", "in a new instance of the operation the claim still holds (it is a table row)")
	Do $$$AssertEquals($Data(^||OcuTalonEmailOutProbe("sent")), 0, "and nothing is delivered")
	Set failing = ..Approval("zzemailoutap0051", ..#ADDRESS)
	Set ^||OcuTalonEmailOutProbe("answer") = "unreachable"
	Set one = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", failing)
	Do $$$AssertEquals(one.Ok_"|"_one.Outcome, "0|failed", "a failed system send answers failed")
	Do $$$AssertEquals(..Claims(failing), 1, "and keeps its claim row")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(failing))
	Do $$$AssertEquals(row.FallbackReason, "failed", "marked failed")
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set calls = ..Delivered()
	Set two = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", failing)
	Do $$$AssertEquals(two.Ok_"|"_two.Outcome_"|"_two.Message, "0|failed|"_$Parameter("OcuTalon.Core.CommandsIn", "MESSAGEFAILED"), "the same approval after the failure answers failed, never that the email was sent")
	Do $$$AssertEquals(..Delivered(), calls, "and nothing is delivered")
	Set thrown = ..Approval("zzemailoutap0052", ..#ADDRESS)
	Set ^||OcuTalonEmailOutProbe("answer") = "throw"
	Set three = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", thrown)
	Do $$$AssertEquals(three.Ok_"|"_three.Outcome, "0|failed", "an error after the claim answers failed")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(thrown))
	Do $$$AssertEquals(row.FallbackReason, "failed", "and marks the claim failed")
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set four = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", thrown)
	Do $$$AssertEquals(four.Ok_"|"_four.Outcome, "0|failed", "the same approval again answers failed, never that the email was sent")
	Set pending = ..Approval("zzemailoutap0053", ..#ADDRESS)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OWNER, "email", "zzemailoutpending", pending, "", "", "", "", "pending"), "the claim of a send that never finished (its job stopped during the send) is made")
	Set calls = ..Delivered()
	Set five = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", pending)
	Do $$$AssertEquals(five.Ok_"|"_five.Outcome_"|"_five.Message, "0|failed|"_$Parameter("OcuTalon.Core.CommandsIn", "MESSAGEFAILED"), "a claim whose send never finished answers failed, never that the email was sent")
	Do $$$AssertEquals(..Delivered(), calls, "and nothing is delivered")
}

/// Ruling f, the lock: while another process holds the approval's lock, a system send of that approval sends nothing and claims nothing; once the lock is free
/// the same approval is sent. The other process signals when it holds the lock, and again when it has released it.
Method TestClaimIsLocked()
{
	Do ..Mailbox()
	Set approval = ..Approval("zzemailoutlock001", ..#ADDRESS)
	Kill ^OcuTalonTest("EmailOutLock")
	Job ##class(OcuTalon.Test.Channel.EmailOut).HoldLock(approval)
	Set held = ..WaitFlag("held")
	Try {
		Do $$$AssertTrue(held, "the other process holds the approval's lock")
		If held {
			Set locked = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
			Do $$$AssertEquals(locked.Ok_"|"_locked.Outcome_"|"_locked.Message, "0|failed|"_$Parameter(..#PROBE, "MESSAGEFAILED"), "a send of the approval while the lock is held answers failed")
			Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "0|0", "and delivers nothing and writes no claim")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Set ^OcuTalonTest("EmailOutLock", "release") = 1
	Do $$$AssertTrue(..WaitFlag("done"), "the other process released the lock")
	Set sent = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
	Do $$$AssertEquals(sent.Ok_"|"_sent.Outcome, "1|sent", "with the lock free the same approval is sent")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "1|1", "once, with one claim")
	Kill ^OcuTalonTest("EmailOutLock")
}

/// The other process of TestClaimIsLocked: holds the lock of the approval until the test releases it (or 60 seconds pass).
ClassMethod HoldLock(approval As %String)
{
	Lock +^OcuTalon.EmailOut.Approval(approval):5
	If '$Test Quit
	Set ^OcuTalonTest("EmailOutLock", "held") = 1
	Set deadline = $ZHorolog + 60
	While ('$Data(^OcuTalonTest("EmailOutLock", "release"))) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -^OcuTalon.EmailOut.Approval(approval)
	Set ^OcuTalonTest("EmailOutLock", "done") = 1
}

/// 1 when the other process of TestClaimIsLocked has set the flag within 10 seconds.
Method WaitFlag(name As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + 10
	While ('$Data(^OcuTalonTest("EmailOutLock", name))) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Quit ''$Data(^OcuTalonTest("EmailOutLock", name))
}

/// An error thrown inside the send is answered as failed.
Method TestUnexpectedErrorAnswersFailed()
{
	Do ..Mailbox()
	Set ^||OcuTalonEmailOutProbe("answer") = "throw"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Set sc = probe.OnSendEmail(..Command("tool", ..#OWNER, ..#ADDRESS, "ok", "ok"), .response)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_response.Ok_"|"_response.Outcome_"|"_response.Message, "1|0|failed|"_$Parameter("OcuTalon.Core.CommandsIn", "MESSAGEFAILED"), "OnSendEmail answers OK with a failed result")
	Do $$$AssertEquals(response.Message_response.Data [ "SERVER-WORDS", 0, "and the answer holds no words of the error")
}

/// No address, subject, text or server word reaches the log (AD-17).
Method TestNoPersonalDataInTheLog()
{
	Do ..Mailbox()
	Set last = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do last.%Next()
	Set start = +last.%GetData(1)
	Set tag = $Translate($ZHorolog, ".", "")_$Job
	Set address = "zzlogaddr"_tag_"@example.com"
	Do ##class(OcuTalon.Data.Setting).Set("email.address", address)
	Set subject = "zzlogsubject"_tag
	Set text = "zzlogtext"_tag
	Do ..Send("tool", ..#OWNER, address, subject, text)
	For answer = "unreachable", "refused", "rejected", "throw" {
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Do ..Send("tool", ..#OWNER, address, subject, text)
	}
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set approval = ..Approval("zzemailoutap0060", address)
	Do ..Send("system", ..#OWNER, address, subject, text, approval)
	For word = address, subject, text, "SERVER-WORDS", "zzrejected@example.com", "zzthrown@example.com", $Piece(address, "@", 1) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", word), 0, "no Ens.Util.Log row holds '"_word_"'")
	}
	Set own = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text [ ?", start, "EmailOut sent one email")
	Do own.%Next()
	Do $$$AssertTrue(+own.%GetData(1) > 0, "the operation does log its outcomes in this test's own rows (so the check above can fail)")
}

/// OnInit forces the identity check on and ContinueAfterBadSend off, whatever the settings say.
Method TestSenderInit()
{
	Set adapter = ##class(OcuTalon.Channel.Email.Sender).%New()
	Set adapter.SMTPServer = "smtp.example.com", adapter.SMTPPort = 587, adapter.SSLConfig = "OcuTalonClient*"
	Set adapter.SSLCheckServerIdentity = 0, adapter.ContinueAfterBadSend = 1
	Set sc = adapter.OnInit()
	Do $$$AssertStatusOK(sc, "OnInit is OK")
	Do $$$AssertEquals(adapter.SSLCheckServerIdentity_"|"_adapter.SMTP.SSLCheckServerIdentity, "1|1", "the identity check is on, in the setting and in %Net.SMTP")
	Do $$$AssertEquals(adapter.ContinueAfterBadSend_"|"_adapter.SMTP.ContinueAfterBadSend, "0|0", "ContinueAfterBadSend is off, in the setting and in %Net.SMTP")
	Set timeouts = adapter.SMTP
	Do $$$AssertEquals($Get(timeouts.Timeouts("RCPT"))_"|"_$Get(timeouts.Timeouts("DATA"))_"|"_$Get(timeouts.Timeouts("_initial")), "20|20|20", "the commands have short timeouts")
}

/// The transport: plain only with the switch on and the host exactly mock; TLS only for the two names of the client configuration.
Method TestSenderTransport()
{
	Set class = "OcuTalon.Test.Channel.EmailOutSender"
	Set cases = $ListBuild(
		$ListBuild(0, "mock", "OcuTalonClient", "tls"),
		$ListBuild(0, "mock", "OcuTalonClient*", "tls"),
		$ListBuild(0, "mock", "", ""),
		$ListBuild(0, "mock", "Other", ""),
		$ListBuild(0, "mock", "OcuTalonClient**", ""),
		$ListBuild(0, "mock", "ocutalonclient", ""),
		$ListBuild(0, "smtp.example.com", "", ""),
		$ListBuild(0, "smtp.example.com", "OcuTalonClient*", "tls"),
		$ListBuild(1, "mock", "", "plain"),
		$ListBuild(1, "mock", "OcuTalonClient*", "plain"),
		$ListBuild(1, "mock", "OcuTalonClient", "plain"),
		$ListBuild(1, "MOCK", "", ""),
		$ListBuild(1, "mock.example.com", "", ""),
		$ListBuild(1, "smtp.example.com", "", ""),
		$ListBuild(1, "smtp.example.com", "Other", ""),
		$ListBuild(1, "smtp.example.com", "OcuTalonClient*", "tls"),
		$ListBuild(1, "", "", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ^||OcuTalonEmailOutSender("switch") = $List(case, 1)
		Set adapter = $ClassMethod(class, "%New")
		Set adapter.SMTPServer = $List(case, 2), adapter.SSLConfig = $List(case, 3)
		Do $$$AssertEquals(adapter.Transport(), $List(case, 4), "switch "_$List(case, 1)_", host '"_$List(case, 2)_"', SSLConfig '"_$List(case, 3)_"': transport '"_$List(case, 4)_"'")
	}
	Kill ^||OcuTalonEmailOutSender
	Do $$$AssertEquals(##class(OcuTalon.Channel.Email.Sender).#PLAINVARIABLE, "OCUTALON_TEST_PLAIN_SMTP", "the real switch reads the CI-only variable")
	Set values = $ListBuild($ListBuild("", 0), $ListBuild("0", 0), $ListBuild("true", 0), $ListBuild("yes", 0), $ListBuild("10", 0), $ListBuild(" 1", 0), $ListBuild("1", 1))
	Set position = 0
	While $ListNext(values, position, value) {
		Do $$$AssertEquals(##class(OcuTalon.Channel.Email.Sender).IsOn($List(value, 1)), $List(value, 2), "the variable '"_$List(value, 1)_"' turns the switch "_$Select($List(value, 2): "on", 1: "off"))
	}
}

/// Ruling c, what reaches %Net.SMTP: for OcuTalonClient the implicit TLS configuration and no STARTTLS, for OcuTalonClient* the same configuration with
/// STARTTLS, in both the server identity checked and no partial send whatever the SMTP object held before; the plain stub's settings only with the switch
/// and the host mock.
Method TestSenderTlsSettings()
{
	Set cases = $ListBuild(
		$ListBuild(0, "smtp.example.com", "OcuTalonClient", $ListBuild(0, "OcuTalonClient", 1, 0)),
		$ListBuild(0, "smtp.example.com", "OcuTalonClient*", $ListBuild(1, "OcuTalonClient", 1, 0)),
		$ListBuild(1, "smtp.example.com", "OcuTalonClient*", $ListBuild(1, "OcuTalonClient", 1, 0)),
		$ListBuild(1, "mock", "OcuTalonClient*", $ListBuild(0, "", 1, 0)))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^||OcuTalonEmailOutSender
		Set ^||OcuTalonEmailOutSender("switch") = $List(case, 1)
		Set ^||OcuTalonEmailOutSender("user") = "zzuser"
		Set adapter = ##class(OcuTalon.Test.Channel.EmailOutSender).%New()
		Set adapter.SMTP = ##class(OcuTalon.Test.Channel.EmailOutSmtp).%New()
		Set adapter.SMTPServer = $List(case, 2), adapter.SSLConfig = $List(case, 3)
		Set adapter.SMTP.UseSTARTTLS = ($List(case, 3) '[ "*"), adapter.SMTP.SSLConfiguration = "Other", adapter.SMTP.SSLCheckServerIdentity = 0, adapter.SMTP.ContinueAfterBadSend = 1
		Set sc = adapter.SendMail(..Message())
		Set label = "switch "_$List(case, 1)_", host '"_$List(case, 2)_"', SSLConfig '"_$List(case, 3)_"'"
		Do $$$AssertStatusOK(sc, label_": the send goes to %Net.SMTP")
		Do $$$AssertEquals($Get(^||OcuTalonEmailOutSender("sent")), $List(case, 4), label_": %Net.SMTP gets STARTTLS, configuration, identity check and no partial send as expected")
	}
	Kill ^||OcuTalonEmailOutSender
}

/// A send with an empty or foreign SSLConfig, or with no credential, fails at once: the host would take seconds to fail a connection.
Method TestSenderNoConnection()
{
	Set class = "OcuTalon.Test.Channel.EmailOutSender"
	Set ^||OcuTalonEmailOutSender("switch") = 0
	For ssl = "", "Other", "OcuTalonClient**", "ocutalonclient*" {
		Set adapter = $ClassMethod(class, "%New")
		Set adapter.SMTPServer = "no-such-host.invalid", adapter.SMTPPort = 587, adapter.Credentials = "ZzNoSuchCredential", adapter.SSLConfig = ssl
		Do adapter.OnInit()
		Set begun = $ZHorolog
		Set sc = adapter.SendMail(..Message())
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 6099, "SSLConfig '"_ssl_"': the send fails with the TLS-required error")
		Do $$$AssertTrue($ZHorolog - begun < 2, "SSLConfig '"_ssl_"': no connection was tried (it ends at once)")
		Do $$$AssertEquals(##class(OcuTalon.Channel.Email.Sender).Classify(sc), "unreachable", "SSLConfig '"_ssl_"': classified unreachable")
	}
	Set adapter = $ClassMethod(class, "%New")
	Set adapter.SMTPServer = "no-such-host.invalid", adapter.SMTPPort = 587, adapter.Credentials = "ZzNoSuchCredential", adapter.SSLConfig = "OcuTalonClient*"
	Do adapter.OnInit()
	Set begun = $ZHorolog
	Set sc = adapter.SendMail(..Message())
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 6167, "with no credential the send fails with the authentication error")
	Do $$$AssertTrue($ZHorolog - begun < 2, "before any connection")
	Do $$$AssertEquals(##class(OcuTalon.Channel.Email.Sender).Classify(sc), "refused", "classified refused")
	Kill ^||OcuTalonEmailOutSender
}

/// Classify: the status codes of %Net.SMTP that Task 0 measured.
Method TestClassify()
{
	Set class = "OcuTalon.Channel.Email.Sender"
	Do $$$AssertEquals($ClassMethod(class, "Classify", $$$OK), "", "OK is nothing")
	Do $$$AssertEquals($ClassMethod(class, "Classify", $$$ERROR($$$SMTPAUTHFailed)), "refused", "6167 is refused")
	Do $$$AssertEquals($ClassMethod(class, "Classify", $$$ERROR($$$SMTPResponse, "RCPT TO", "550 no")), "rejected", "6033 is rejected")
	Do $$$AssertEquals($ClassMethod(class, "Classify", $$$ERROR($$$SMTPNoSend)), "rejected", "6070 is rejected")
	For code = $$$SMTPOpen, $$$SMTPConnectionFailed, $$$SMTPFirst, $$$SMTPTimeout, $$$HttpRequestSSLError, $$$STARTTLSNotSupported, $$$STARTTLSConfigRequired, $$$SMTPAUTHNotSupported {
		Do $$$AssertEquals($ClassMethod(class, "Classify", $SYSTEM.Status.Error(code, "a", "b")), "unreachable", code_" is unreachable")
	}
	Do $$$AssertEquals($ClassMethod(class, "Classify", $SYSTEM.Status.Error(6156, "a", "b")), "unreachable", "6156 (the server name does not match the certificate) is unreachable")
}

/// --- helpers ---

/// A mail message for the adapter.
ClassMethod Message() As %Net.MailMessage [ Private ]
{
	Set message = ##class(%Net.MailMessage).%New("UTF-8")
	Set message.From = "zzfrom@example.com"
	Set message.Subject = "zz"
	Do message.To.Insert("zzto@example.com")
	Do message.TextData.Write("zz")
	Quit message
}

/// A SendEmail command.
ClassMethod Command(origin As %String, sessionRef As %String, recipients As %String, subject As %String, text As %String, approvalRef As %String = "") As OcuTalon.Msg.Command.SendEmail [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SendEmail).%New()
	Set command.Origin = origin
	Set command.SessionRef = sessionRef
	Set command.Recipients = recipients
	Set command.Subject = subject
	Set command.Text = text
	Set command.ApprovalRef = approvalRef
	Quit command
}

/// Sends the command through a new shadow instance of the probe, and answers the CommandResult.
Method Send(origin As %String, sessionRef As %String, recipients As %String, subject As %String, text As %String, approvalRef As %String = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnSendEmail(..Command(origin, sessionRef, recipients, subject, text, approvalRef), .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertTrue($IsObject(response), "and the answer is a CommandResult")
	Quit response
}

/// The saved mailbox: the address and the owner.
Method Mailbox() [ Private ]
{
	Kill ^||OcuTalonEmailOutProbe
	Do ##class(OcuTalon.Data.Setting).Set("email.address", ..#ADDRESS)
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", ..#OWNER)
}

/// The number of messages that Deliver has seen.
ClassMethod Delivered() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonEmailOutProbe("calls"))
}

/// A comma list of n addresses.
ClassMethod Many(n As %Integer) As %String [ Private ]
{
	Set list = ""
	For i = 1:1:n Set list = list_$Select(list = "": "", 1: ",")_"zzmany"_i_"@example.com"
	Quit list
}

/// Makes an approval request row and answers its Ref. recipients is the comma list for the FixParameters member recipients (an array), unless parameters is
/// given as the whole text of FixParameters.
Method Approval(ref As %String, recipients As %String, kind As %String = "fix", state As %String = "executing", fixKind As %String = "email", parameters As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set row.Ref = ref
	Set row.Kind = kind
	Set row.State = state
	Set row.FixKind = fixKind
	Set row.OwnerRef = ..#OWNER
	If parameters = "" {
		Set array = []
		For i = 1:1:$Length(recipients, ",") {
			If $Piece(recipients, ",", i) '= "" Do array.%Push($Piece(recipients, ",", i))
		}
		Set parameters = {"recipients": (array)}.%ToJSON()
	}
	Set row.FixParameters = parameters
	Set sc = row.%Save()
	Do $$$AssertStatusOK(sc, "the approval request "_ref_" is made")
	Quit ref
}

/// The number of Delivery rows of channel email of the owner.
ClassMethod Deliveries(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The id of the first Delivery row of channel email of the owner.
ClassMethod DeliveryIds(owner As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND OwnerRef = ? ORDER BY ID", owner)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of different message ids among the Delivery rows of channel email of the owner.
ClassMethod DistinctRefs(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(DISTINCT ChannelMessageId) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of Delivery rows of channel email with the approval's Ref.
ClassMethod Claims(approval As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND ApprovalRef = ?", approval)
	Do result.%Next()
	Quit +result.%GetData(1)
}

ClassMethod ClaimId(approval As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND ApprovalRef = ?", approval)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Puts everything back to a clean start: the probe's records, the keys, the flag, and the rows that the tests made.
Method Reset() [ Private ]
{
	Kill ^||OcuTalonEmailOutProbe, ^||OcuTalonEmailOutSender
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND (OwnerRef LIKE 'zzemailout%' OR ApprovalRef LIKE 'zzemailout%')")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref LIKE 'zzemailout%'")
}

}
