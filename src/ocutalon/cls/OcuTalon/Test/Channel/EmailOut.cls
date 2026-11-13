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
///   - TestSignInMessage (Story 21.8, T2): with a provider sign-in (the stand-in adapter has OAuth2ApplicationName set) a refused send answers failed with
///     MESSAGESIGNIN on the tool and system paths, once, with no Delivery row, and the digest path logs it as a refused send; an unreachable or rejected send keeps
///     its sentence, and in password mode a refused send keeps MESSAGEREFUSEDLOGIN;
///   - TestNoDoubleSend (ruling f): a system send is claimed by its approval: the same approval again, after a restart of the operation, answers already_sent and
///     delivers nothing more; the claim is written pending before the send and cleared once the email is sent; after a failed send, an error after the claim,
///     or a claim whose send never finished, it answers failed and delivers nothing; the claim row of a failed send says failed;
///   - TestToolKeySendsOnce (Story 21.13): a tool send with an IdempotencyKey is sent once per key of its session: the same key again, also with other words and
///     after a restart of the operation, answers sent and delivers nothing more; another key, another session's claim of the same key and a send with no key
///     are sent; a failed send removes its claim and the key can be sent again; a claim that never finished or an error after the claim answers failed and
///     delivers nothing; the claim is pending during the send and keeps no text and no address; a tool command that names an approval makes a claim with no
///     approval and leaves that approval's own send alone;
///   - TestClaimIsLocked (ruling f): while another process holds the approval's lock a system send of it answers failed, delivers nothing and writes no claim;
///     with the lock free the same approval is sent once;
///   - TestToolKeyIsLocked (Story 21.13): the same for a keyed tool send and the lock of its session and key;
///   - TestToolKeyFailureClasses (Story 21.13, QA; Planner ruling K): a failed keyed tool send of each class (unreachable, a connection lost before the greeting,
///     refused, rejected) answers its own class's sentence, leaves no claim and the key is sent on the retry; one that may still have reached the server (a
///     timeout, a connection lost during DATA) answers MESSAGEMAYHAVESENT, which does not say the email was not sent, keeps its claim marked maysent, and the
///     same key again answers the same sentence and sends nothing;
///   - TestToolKeyClaimHoldsNothingOfTheSend (Story 21.13, QA): no column of a keyed tool send's claim row, sent or failed, holds the key, the address, the subject or
///     the text, and the lock of the key is released after a sent, a repeated, a failed and a thrown send;
///   - TestToolKeyClaimIsCaseExact (Story 21.13, QA): a row of the owner whose DigestKey differs from the key's hash only in case is not the key's claim;
///   - TestSystemSendWithAKeyIsStillClaimedByItsApproval (Story 21.13, QA): a system send that carries an IdempotencyKey is still claimed by its approval, not by the
///     key, and the key claims nothing for it;
///   - TestToolKeyNeverEqualsADigestKey (Story 21.13, QA): a tool key built from a digest's key parts does not find the digest's row, and is sent;
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
///   - TestDigestAddressGuard (QA, ruling b): an email.address that is more than one plain address (a second line, a Bcc header, a second recipient, a display name,
///     a control character, an over-long address) sends nothing, records nothing and logs nothing; the control sends to the plain address alone;
///   - TestDigestTextIsClean (QA, ruling b, V6): a summary with line breaks, a lone dot line, SMTP commands and control characters reaches the mail as one clean line;
///   - TestDigestFailures: an unreachable, refusing, rejecting or throwing server is one try, no Delivery row, one warning with the class only, and no words of
///     the server; the operation answers OK;
///   - TestDigestNoDoubleSend (ruling f): the same Notification again sends nothing, also after a restart of the operation, and another digest is sent;
///   - TestDigestDailyCap (ruling V1): the 11th digest to the mailbox in one UTC day is refused, logged without contents and not sent; the digest emails of
///     another owner session of the mailbox count, the rows of an earlier day and of other kinds do not; the count is taken against the rows already there;
///   - TestDigestLock: while another process holds the lock of the mailbox's digest emails nothing is sent;
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND Kind = 'digest' AND OwnerRef LIKE 'zzemailout%' ORDER BY ID DESC")
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Text %STARTSWITH 'EmailOut ' ORDER BY ID", start)
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

/// Ruling b (header injection) on the digest path (QA): the recipient is the product key email.address and nothing else, so a value of that key that is
/// more than one plain address (a second line, a Bcc header, a second recipient, a display name, a control character, an over-long address) sends nothing,
/// records nothing and logs nothing; the control case shows the same Notification going out with a plain address.
Method TestDigestAddressGuard()
{
	Do ..Mailbox()
	Set slots = ..DigestSlots(70)
	Set before = ..LastLog()
	Set cr = $Char(13), lf = $Char(10)
	Set cases = $ListBuild(
		$ListBuild("a Bcc header after CR LF", ..#ADDRESS_cr_lf_"Bcc: zzevil@example.com"),
		$ListBuild("a Bcc header after LF", ..#ADDRESS_lf_"Bcc: zzevil@example.com"),
		$ListBuild("a Bcc header after CR", ..#ADDRESS_cr_"Bcc: zzevil@example.com"),
		$ListBuild("a trailing line feed", ..#ADDRESS_lf),
		$ListBuild("a second recipient after a comma", ..#ADDRESS_",zzevil@example.com"),
		$ListBuild("a second recipient after a semicolon", ..#ADDRESS_";zzevil@example.com"),
		$ListBuild("a second recipient after a space", ..#ADDRESS_" zzevil@example.com"),
		$ListBuild("a display name and angle brackets", "Zz Name <"_..#ADDRESS_">"),
		$ListBuild("a null character", ..#ADDRESS_$Char(0)),
		$ListBuild("a bell character", "zz"_$Char(7)_"emailout@example.com"),
		$ListBuild("a local part over 64 characters", $Translate($Justify("", 65), " ", "a")_"@example.com"),
		$ListBuild("an address over 254 characters", "zz@"_$Translate($Justify("", 250), " ", "a")_".com"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Data.Setting).Set("email.address", $List(case, 2))
		Do ..Notify("digest", ..#OWNER, slots)
		Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "0|0", $List(case, 1)_": nothing is sent or recorded")
	}
	Do $$$AssertEquals($ListLength(..LogTexts(before)), 0, "and none of it is logged")
	Do ##class(OcuTalon.Data.Setting).Set("email.address", ..#ADDRESS)
	Do ..Notify("digest", ..#OWNER, slots)
	Set sent = $Get(^||OcuTalonEmailOutProbe("sent", 1))
	Do $$$AssertEquals(..Delivered()_"|"_$List(sent, 1)_"|"_$List(sent, 2)_"|"_$List(sent, 8), "1|"_..#ADDRESS_"|"_..#ADDRESS_"|0", "control: the same Notification with a plain address goes to it alone, with no Cc or Bcc")
}

/// Ruling b on the digest path (QA): the digest text is model-written (V6), and a summary that holds line breaks, a line with a single dot, SMTP commands,
/// control and bidirectional characters reaches the mail as one clean line of its own: no CR, no control character but the line feeds between the pieces,
/// no line that is a dot, and the commands as plain words on the summary's line.
Method TestDigestTextIsClean()
{
	Do ..Mailbox()
	Set cr = $Char(13), lf = $Char(10)
	Set summary = "one"_cr_lf_"."_cr_lf_"QUIT"_lf_".."_cr_"RCPT TO:<zzevil@example.com>"_$Char(7, 0, 27)_$Char(8238)_"end"
	Set slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.saved", "slots": {"count": 1, "summary": (summary)}}], "lines": [], "rows": []}.%ToJSON()
	Do ..Notify("digest", ..#OWNER, slots)
	Do $$$AssertEquals(..Delivered(), 1, "the digest is sent")
	Set text = $List(^||OcuTalonEmailOutProbe("sent", 1), 4)
	Do $$$AssertEquals($Length(text, lf), 2, "the two pieces are two lines")
	Do $$$AssertEquals($Translate(text, cr), text, "no carriage return")
	Do $$$AssertEquals($ZStrip(text, "*C"), $Translate(text, lf), "and no control character but the line feed")
	Do $$$AssertTrue(text '[ $Char(8238), "and no bidirectional control")
	For i = 1:1:$Length(text, lf) {
		Do $$$AssertTrue($Extract($Piece(text, lf, i), 1) '= ".", "line "_i_" does not begin with a dot")
	}
	Do $$$AssertTrue($Piece(text, lf, 2) [ "one . QUIT .. RCPT TO:<zzevil@example.com>end", "the summary is one line with its words in order: "_$Piece(text, lf, 2))
	Do $$$AssertEquals($List(^||OcuTalonEmailOutProbe("sent", 1), 2), ..#ADDRESS, "and an address inside it is no recipient")
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
	Set room = 10 - ..DigestEmailsToday()
	Do $$$AssertTrue((room > 0) && (room < 10), "today's digest emails of the mailbox, the other owner's included, leave room for "_room)
	Set before = ..LastLog()
	For n = 1:1:(room + 1) {
		Do ..Notify("digest", ..#OWNER, ..DigestSlots(30 + n))
	}
	Do $$$AssertEquals(..Delivered(), room, "the digest after the 10th of the mailbox's day is not sent, the other owner's counting: "_room_" mails")
	Do $$$AssertEquals(..DigestRows(..#OWNER), room + 1, "the rows of today and the earlier day's row")
	Set texts = ..LogTexts(before)
	Do $$$AssertEquals($ListLength(texts), room + 1, "one info line a mail and one warning")
	Do $$$AssertEquals($List(texts, room + 1), "EmailOut refused a digest email: the limit of 10 digest emails a day was reached, so it sent nothing", "the refusal is logged, with no contents")
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(50))
	Do $$$AssertEquals(..Delivered(), room, "and a later one on the same day is refused too")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Delivery SET RecordedAt = '2020-01-02T00:00:00Z' WHERE OwnerRef = ? AND Channel = 'email' AND Kind = 'digest' AND RecordedAt > '2021'", ..#OWNER)
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(51))
	Do $$$AssertEquals(..Delivered(), room + 1, "once the rows are of an earlier day the digest is sent again")
}

/// The digest emails of today (UTC) of every owner, read here by SQL and not through the product's count.
ClassMethod DigestEmailsToday() As %Integer [ Private ]
{
	Set today = $Extract(##class(OcuTalon.Data.Time).NowUtc(), 1, 10)_"T00:00:00Z"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND Kind = 'digest' AND RecordedAt >= ?", today)
	Do result.%Next()
	Quit +result.%GetData(1)
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

/// While another process holds the lock of the mailbox's digest emails nothing is sent.
Method TestDigestLock()
{
	Do ..Mailbox()
	Kill ^OcuTalonTest("EmailOutLock")
	Job ##class(OcuTalon.Test.Channel.EmailOut).HoldDigestLock()
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
ClassMethod HoldDigestLock()
{
	Lock +^OcuTalon.EmailOut.Digest:5
	If '$Test Quit
	Set ^OcuTalonTest("EmailOutLock", "held") = 1
	Set deadline = $ZHorolog + 60
	While ('$Data(^OcuTalonTest("EmailOutLock", "release"))) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -^OcuTalon.EmailOut.Digest
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
	Do $$$AssertEquals(..Delivered(), 5, "the digest and the four failures each reached the send")
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
	Do $$$AssertEquals($Parameter(class, "MESSAGESIGNIN"), "The mail sign-in is no longer valid, so the email wasn't sent. Sign in again in Settings > Channels > Email.", "T2")
	Do $$$AssertEquals($Parameter(class, "MESSAGEMAYHAVESENT"), "The mail server stopped answering while the email was being sent, so it may have gone out. OcuTalon won't send it again.", "Planner ruling K")
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
	Set result = ..Send("tool", ..#OWNER, "other@example.com", "ok", "ok", "", "zzkey-refused-1")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_refused, "a keyed send to another address is refused")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "", "ok", "", "zzkey-refused-2")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_refused, "and a keyed send with no subject is refused")
	Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-refused-1"))_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-refused-2")), "0|0|0", "and neither is delivered or claimed")
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
		Set result = ..Send(origin, ..#OWNER, ..#ADDRESS, "ok", "ok", ..Approval("zzemailoutap0030"_origin, ..#ADDRESS), "zzkey-demo")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|Email can't be connected on the online demo. Nothing was changed.", "origin "_origin_": not_available on the online demo")
	}
	Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-demo")), "0|0", "nothing was delivered and no claim was written")
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
	Set cases = $ListBuild("unreachable|OcuTalon couldn't reach the mail server.", "refused|The mail server refused the user name or password.", "rejected|The mail server didn't accept the email, so it wasn't sent.", "timeout|OcuTalon couldn't reach the mail server.", "dropped|OcuTalon couldn't reach the mail server.")
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

/// Story 21.8, T2: in OAuth2 mode a send whose login is refused answers MESSAGESIGNIN on every path; the other classes and password mode keep their sentences.
Method TestSignInMessage()
{
	Do ..Mailbox()
	Set signIn = "The mail sign-in is no longer valid, so the email wasn't sent. Sign in again in Settings > Channels > Email."
	Set cases = $ListBuild("oauth|refused|"_signIn, "oauth|unreachable|OcuTalon couldn't reach the mail server.", "oauth|rejected|The mail server didn't accept the email, so it wasn't sent.", "password|refused|The mail server refused the user name or password.")
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^||OcuTalonEmailOutProbe
		Set ^||OcuTalonEmailOutProbe("answer") = $Piece(case, "|", 2)
		Set ^||OcuTalonEmailOutProbe("oauth") = ($Piece(case, "|", 1) = "oauth")
		Set label = $Piece(case, "|", 1)_" "_$Piece(case, "|", 2)
		Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "ok", "ok")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|failed|"_$Piece(case, "|", 3), label_": the tool send answers failed with its sentence")
		Set approval = ..Approval("zzemailoutap0210", ..#ADDRESS)
		Set system = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
		Do $$$AssertEquals(system.Ok_"|"_system.Outcome_"|"_system.Message, "0|failed|"_$Piece(case, "|", 3), label_": and so does the system send")
		Do $$$AssertEquals(..Delivered(), 2, label_": one try each, no retry")
		Do $$$AssertEquals(..Deliveries(..#OWNER), 1, label_": the only Delivery row is the claim of the system send, none for the tool send")
		Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval)).FallbackReason, "failed", label_": and it says failed")
		Do ..Reset()
		Do ..Mailbox()
	}
	Kill ^||OcuTalonEmailOutProbe
	Set ^||OcuTalonEmailOutProbe("answer") = "refused"
	Set ^||OcuTalonEmailOutProbe("oauth") = 1
	Set before = ..LastLog()
	Do ..Notify("digest", ..#OWNER, ..DigestSlots(31))
	Set texts = ..LogTexts(before)
	Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER)_"|"_$ListLength(texts), "1|0|1", "the digest path tries once, records nothing and logs one line")
	Do $$$AssertEquals($List(texts, 1), "EmailOut did not send the digest email: refused", "which says refused and nothing of the sign-in or the server")
	Kill ^||OcuTalonEmailOutProbe
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
	For answer = "timeout", "dropped" {
		Set mayHave = ..Approval($Case(answer, "timeout": "zzemailoutap0054", : "zzemailoutap0055"), ..#ADDRESS)
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Set six = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", mayHave)
		Kill ^||OcuTalonEmailOutProbe("answer")
		Do $$$AssertEquals(six.Ok_"|"_six.Outcome_"|"_six.Message, "0|failed|"_$Parameter(..#PROBE, "MESSAGEUNREACHABLE"), answer_": a system send that may have reached the server keeps its class sentence")
		Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(mayHave))
		Do $$$AssertEquals(row.FallbackReason, "failed", answer_": and its claim is marked failed, not maysent")
		Set seven = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", mayHave)
		Do $$$AssertEquals(seven.Ok_"|"_seven.Outcome_"|"_seven.Message, "0|failed|"_$Parameter("OcuTalon.Core.CommandsIn", "MESSAGEFAILED"), answer_": the same approval again answers failed")
	}
	Set pending = ..Approval("zzemailoutap0053", ..#ADDRESS)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OWNER, "email", "zzemailoutpending", pending, "", "", "", "", "pending"), "the claim of a send that never finished (its job stopped during the send) is made")
	Set calls = ..Delivered()
	Set five = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", pending)
	Do $$$AssertEquals(five.Ok_"|"_five.Outcome_"|"_five.Message, "0|failed|"_$Parameter("OcuTalon.Core.CommandsIn", "MESSAGEFAILED"), "a claim whose send never finished answers failed, never that the email was sent")
	Do $$$AssertEquals(..Delivered(), calls, "and nothing is delivered")
}

/// Story 21.13: a tool send is sent once per IdempotencyKey of its session, also after a restart and after a failure.
Method TestToolKeySendsOnce()
{
	Do ..Mailbox()
	Set sent = $Parameter(..#PROBE, "MESSAGESENT")
	Set failed = $Parameter(..#PROBE, "MESSAGEFAILED")
	Set hash = ..Hash("zzkey-1")
	Set first = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-1")
	Do $$$AssertEquals(first.Ok_"|"_first.Outcome_"|"_first.Message, "1|sent|"_sent, "the first send of the key is sent")
	Do $$$AssertEquals($Get(^||OcuTalonEmailOutProbe("claim", 1)), "pending", "its claim was written, marked pending, before the send")
	Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..KeyRowId(..#OWNER, hash))
	Do $$$AssertEquals(row.FallbackReason_"|"_row.ApprovalRef_"|"_row.Text_"|"_row.Kind, "|||", "and the claim of the sent email is no longer marked, and holds no approval and no text")
	Do $$$AssertEquals($Length(row.DigestKey), 22, "its DigestKey is 22 characters")
	Do $$$AssertTrue(row.DigestKey '[ "zzkey", "and holds no part of the key")
	Set again = ..Send("tool", ..#OWNER, ..#ADDRESS, "another subject", "other words", "", "zzkey-1")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Message, "1|sent|"_sent, "the same key again, worded differently, answers as the first send did")
	Do $$$AssertEquals(..Delivered()_"|"_..Deliveries(..#OWNER), "1|1", "and delivers nothing more: one Delivery row")
	Kill ^||OcuTalonEmailOutProbe("sent")
	Set restarted = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-1")
	Do $$$AssertEquals(restarted.Ok_"|"_restarted.Outcome, "1|sent", "in a new instance of the operation the claim still holds (it is a table row)")
	Do $$$AssertEquals($Data(^||OcuTalonEmailOutProbe("sent")), 0, "and nothing is delivered")
	Set other = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-2")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome_"|"_..Delivered()_"|"_..Deliveries(..#OWNER), "1|sent|2|2", "another key is sent: one more mail and one more row")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OTHER, "email", "zzemailoutother", "", "", "", "", "", "", , "", ..Hash("zzkey-3")), "another session's sent claim of the same key is made")
	Do $$$AssertEquals(..KeyRows(..#OTHER, ..Hash("zzkey-3"))_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-3")), "1|0", "and it is the only row of that key")
	Set scoped = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-3")
	Do $$$AssertEquals(scoped.Outcome_"|"_..Delivered(), "sent|3", "a sent claim of the same key in another session does not stop this session's send")
	Set calls = ..Delivered()
	Do ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text")
	Do ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text")
	Do $$$AssertEquals(..Delivered(), calls + 2, "a send with no key is sent every time")
	Set ^||OcuTalonEmailOutProbe("answer") = "unreachable"
	Set calls = ..Delivered()
	Set bad = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-5")
	Do $$$AssertEquals(bad.Ok_"|"_bad.Outcome_"|"_bad.Message, "0|failed|"_$Parameter(..#PROBE, "MESSAGEUNREACHABLE"), "a failed send answers failed with its class's sentence")
	Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-5")), (calls + 1)_"|0", "and leaves no row")
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set retried = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-5")
	Do $$$AssertEquals(retried.Ok_"|"_retried.Outcome, "1|sent", "the retry of the key is sent")
	Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-5")), (calls + 2)_"|1", "once, with one row")
	Set pendingHash = ..Hash("zzkey-6")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OWNER, "email", "zzemailoutpending", "", "", "", "", "", "pending", , "", pendingHash), "the claim of a send that never finished is made")
	Set calls = ..Delivered()
	Set never = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-6")
	Do $$$AssertEquals(never.Ok_"|"_never.Outcome_"|"_never.Message, "0|failed|"_failed, "a claim whose send never finished answers failed")
	Do $$$AssertEquals(..Delivered(), calls, "and nothing is delivered")
	Set ^||OcuTalonEmailOutProbe("answer") = "throw"
	Set thrown = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-7")
	Do $$$AssertEquals(thrown.Ok_"|"_thrown.Outcome_"|"_thrown.Message, "0|failed|"_failed, "an error after the claim answers failed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).%OpenId(..KeyRowId(..#OWNER, ..Hash("zzkey-7"))).FallbackReason, "failed", "and marks the claim failed")
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set calls = ..Delivered()
	Set repeated = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-7")
	Do $$$AssertEquals(repeated.Ok_"|"_repeated.Outcome_"|"_repeated.Message, "0|failed|"_failed, "the same key again answers failed, never that the email was sent")
	Do $$$AssertEquals(..Delivered(), calls, "and nothing is delivered")
	Set approval = ..Approval("zzemailoutap0060", ..#ADDRESS)
	Set viaTool = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", approval, "zzkey-8")
	Do $$$AssertEquals(viaTool.Outcome_"|"_..Claims(approval)_"|"_..KeyRows(..#OWNER, ..Hash("zzkey-8")), "sent|0|1", "a tool command that names an approval makes a claim with no approval")
	Set calls = ..Delivered()
	Set system = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval)
	Do $$$AssertEquals(system.Outcome_"|"_..Delivered()_"|"_..Claims(approval), "sent|"_(calls + 1)_"|1", "and that approval's own system send is still sent once")
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

/// Story 21.13, the lock of a keyed tool send: while another process holds the lock of the session and the key, a send of that key sends nothing and claims
/// nothing; once the lock is free the same key is sent once.
Method TestToolKeyIsLocked()
{
	Do ..Mailbox()
	Set hash = ..Hash("zzkey-lock")
	Kill ^OcuTalonTest("EmailOutLock")
	Job ##class(OcuTalon.Test.Channel.EmailOut).HoldLock("", ..#OWNER, hash)
	Set held = ..WaitFlag("held")
	Try {
		Do $$$AssertTrue(held, "the other process holds the key's lock")
		If held {
			Set locked = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-lock")
			Do $$$AssertEquals(locked.Ok_"|"_locked.Outcome_"|"_locked.Message, "0|failed|"_$Parameter(..#PROBE, "MESSAGEFAILED"), "a send of the key while the lock is held answers failed")
			Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, hash), "0|0", "and delivers nothing and writes no claim")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Set ^OcuTalonTest("EmailOutLock", "release") = 1
	Do $$$AssertTrue(..WaitFlag("done"), "the other process released the lock")
	Set sent = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-lock")
	Do $$$AssertEquals(sent.Ok_"|"_sent.Outcome, "1|sent", "with the lock free the same key is sent")
	Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, hash), "1|1", "once, with one claim")
	Kill ^OcuTalonTest("EmailOutLock")
}

/// Story 21.13 (QA), matrix "Failed, then retried": a failed keyed tool send of each class of Sender.Classify that the server did not take leaves no claim row,
/// and the same key is sent on the retry, once. A send that may still have reached the server (a timeout, a connection lost during DATA) keeps its claim marked maysent and
/// answers MESSAGEMAYHAVESENT, and the same key again answers the same sentence and sends nothing.
Method TestToolKeyFailureClasses()
{
	Do ..Mailbox()
	For answer = "unreachable", "lost", "refused", "rejected" {
		Set expected = $Case(answer, "refused": $Parameter(..#PROBE, "MESSAGEREFUSEDLOGIN"), "rejected": $Parameter(..#PROBE, "MESSAGEREJECTED"), : $Parameter(..#PROBE, "MESSAGEUNREACHABLE"))
		Set key = "zzkey-class-"_answer
		Set hash = ..Hash(key)
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Set calls = ..Delivered()
		Set bad = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
		Do $$$AssertEquals(bad.Ok_"|"_bad.Outcome_"|"_bad.Message, "0|failed|"_expected, answer_": the send fails with the sentence of its class")
		Do $$$AssertEquals(..Delivered()_"|"_..KeyRows(..#OWNER, hash), (calls + 1)_"|0", answer_": it was tried once and left no claim")
		Kill ^||OcuTalonEmailOutProbe("answer")
		Set retried = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
		Do $$$AssertEquals(retried.Ok_"|"_retried.Outcome_"|"_..Delivered()_"|"_..KeyRows(..#OWNER, hash), "1|sent|"_(calls + 2)_"|1", answer_": the retry of the key is sent once")
	}
	For answer = "timeout", "dropped" {
		Set key = "zzkey-class-"_answer
		Set hash = ..Hash(key)
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Set calls = ..Delivered()
		Set bad = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
		Set maySent = $Parameter(..#PROBE, "MESSAGEMAYHAVESENT")
		Do $$$AssertEquals(bad.Ok_"|"_bad.Outcome_"|"_bad.Message, "0|failed|"_maySent, answer_": the send fails with the may-have-gone-out sentence, not one that says it was not sent")
		Set id = ..KeyRowId(..#OWNER, hash)
		Do $$$AssertEquals(..KeyRows(..#OWNER, hash)_"|"_$Select(id = "": "", 1: ##class(OcuTalon.Data.Delivery).%OpenId(id).FallbackReason), "1|maysent", answer_": the email may have reached the server, so its claim is kept, marked maysent")
		Kill ^||OcuTalonEmailOutProbe("answer")
		Set again = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
		Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Message_"|"_..Delivered(), "0|failed|"_maySent_"|"_(calls + 1), answer_": the same key again answers the same sentence and sends nothing (AD-1)")
	}
}

/// Story 21.13 (QA): the claim row of a keyed tool send (sent, and failed after an error) keeps in no column the key, the address, the subject or the text, and
/// the lock of the key is free after every kind of send.
Method TestToolKeyClaimHoldsNothingOfTheSend()
{
	Do ..Mailbox()
	Set subject = "zzshapesubject"
	Set text = "zzshapetext"
	Set names = ""
	Set properties = ##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Data.Delivery").Properties
	For i = 1:1:properties.Count() {
		If $Extract(properties.GetAt(i).Name) '= "%" Set names = names_$ListBuild(properties.GetAt(i).Name)
	}
	Do $$$AssertTrue($ListLength(names) > 10, "the columns of a Delivery row are known")
	Set lockName = $Name(^OcuTalon.EmailOut.Key(..#OWNER, ..Hash("zzshapekey-control")))
	Lock +@lockName
	Do $$$AssertTrue($Data(^$LOCK(lockName)) > 0, "a lock that is held shows in the lock table (so the checks below can fail)")
	Lock -@lockName
	Do $$$AssertEquals($Data(^$LOCK(lockName)), 0, "and a lock that is released does not")
	For case = "sent", "throw" {
		Set key = "zzshapekey-"_case
		Set hash = ..Hash(key)
		Set ^||OcuTalonEmailOutProbe("answer") = $Select(case = "throw": "throw", 1: "")
		Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, subject, text, "", key)
		Do $$$AssertEquals(result.Outcome, $Select(case = "throw": "failed", 1: "sent"), case_": the send is answered")
		Set row = ##class(OcuTalon.Data.Delivery).%OpenId(..KeyRowId(..#OWNER, hash))
		Do $$$AssertTrue($IsObject(row), case_": its claim row is there")
		Set holds = ""
		If $IsObject(row) {
			For i = 1:1:$ListLength(names) {
				Set value = $Property(row, $List(names, i))
				For needle = key, ..#ADDRESS, subject, text {
					If value [ needle Set holds = holds_" "_$List(names, i)
				}
			}
		}
		Do $$$AssertEquals(holds, "", case_": no column of the claim row holds the key, the address, the subject or the text")
		Do $$$AssertEquals($Data(^$LOCK($Name(^OcuTalon.EmailOut.Key(..#OWNER, hash)))), 0, case_": the lock of the key is free")
		Kill ^||OcuTalonEmailOutProbe("answer")
		Set again = ..Send("tool", ..#OWNER, ..#ADDRESS, subject, text, "", key)
		Do $$$AssertEquals($Data(^$LOCK($Name(^OcuTalon.EmailOut.Key(..#OWNER, hash)))), 0, case_": and after the same key again (answer "_again.Outcome_")")
	}
	Set ^||OcuTalonEmailOutProbe("answer") = "unreachable"
	Do ..Send("tool", ..#OWNER, ..#ADDRESS, subject, text, "", "zzshapekey-failed")
	Kill ^||OcuTalonEmailOutProbe("answer")
	Do $$$AssertEquals($Data(^$LOCK($Name(^OcuTalon.EmailOut.Key(..#OWNER, ..Hash("zzshapekey-failed"))))), 0, "and after a failed send")
}

/// Story 21.13 (QA): the DigestKey comparison of a keyed claim is exact. A row of the owner whose DigestKey differs from the key's hash only in case is found by
/// the SQL comparison (the column compares without regard to case) but is not the key's claim, so the key is sent.
Method TestToolKeyClaimIsCaseExact()
{
	Do ..Mailbox()
	Set n = 0
	Set key = "zzkey-case"
	Set other = $ZConvert(..Hash(key), "U")
	While (other = ..Hash(key)) && ($Increment(n) < 20) {
		Set key = "zzkey-case-"_n
		Set other = $ZConvert(..Hash(key), "U")
	}
	Set hash = ..Hash(key)
	Do $$$AssertTrue(other '= hash, "the hash of the key has a lower-case letter")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OWNER, "email", "zzemailoutcase", "", "", "", "", "", "", , "", other), "the row with the upper-cased hash is made")
	Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'email' AND DigestKey = ?", ..#OWNER, hash)
	Do found.%Next()
	Do $$$AssertEquals(found.%GetData(1)_"|"_..KeyRows(..#OWNER, hash), "1|0", "SQL finds that row by the key's hash without regard to case, an exact comparison does not")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Delivered()_"|"_..KeyRows(..#OWNER, hash), "1|sent|1|1", "the key is sent, as that row is not its claim")
}

/// Story 21.13 (QA), matrix "System path": a system send that carries an IdempotencyKey is claimed by its approval (already_sent), never by the key, and it
/// leaves no key claim: the same key then sends as a tool send, and with another approval.
Method TestSystemSendWithAKeyIsStillClaimedByItsApproval()
{
	Do ..Mailbox()
	Set approval = ..Approval("zzemailoutap0072", ..#ADDRESS)
	Set other = ..Approval("zzemailoutap0073", ..#ADDRESS)
	Set hash = ..Hash("zzkey-system")
	Set first = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval, "zzkey-system")
	Do $$$AssertEquals(first.Ok_"|"_first.Outcome_"|"_first.Message, "1|sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "the system send with a key is sent")
	Do $$$AssertEquals(..Claims(approval)_"|"_..KeyRows(..#OWNER, hash)_"|"_..Delivered(), "1|0|1", "its claim is the approval's, with no key claim")
	Set again = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", approval, "zzkey-system")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Message, "1|already_sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "the same approval and key again is already_sent")
	Set second = ..Send("system", ..#OWNER, ..#ADDRESS, "fix", "text", other, "zzkey-system")
	Do $$$AssertEquals(second.Outcome_"|"_..Delivered()_"|"_..Claims(other), "sent|2|1", "another approval with the same key is sent: the key does not claim a system send")
	Set tool = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", "zzkey-system")
	Do $$$AssertEquals(tool.Outcome_"|"_..Delivered()_"|"_..KeyRows(..#OWNER, hash), "sent|3|1", "and the same key as a tool send is sent once, with its own claim")
}

/// Story 21.13 (QA): the key's hash never equals a digest's key. A tool key made of the parts of a digest's key (session, decision, catalog key, slots, the UTC
/// day) would equal it if the word tool were not part of the hash; with it, the digest's row is not the tool send's claim and the tool send is sent.
Method TestToolKeyNeverEqualsADigestKey()
{
	Do ..Mailbox()
	Set lf = $Char(10)
	Set note = ##class(OcuTalon.Msg.Notification).%New()
	Set note.SessionRef = "zzemailoutdig0001"
	Set note.DecisionRef = "zzemailoutdec0001"
	Set note.CatalogKey = "zzcatalog"
	Set note.Slots = "zzslots"
	Set digestKey = ##class(OcuTalon.Channel.Email.Out).DigestKeyOf(note)
	Set key = note.SessionRef_lf_note.DecisionRef_lf_note.CatalogKey_lf_note.Slots_lf_$Extract(##class(OcuTalon.Data.Time).NowUtc(), 1, 10)
	Do $$$AssertTrue(..Hash(key) '= digestKey, "the tool key made of a digest's parts does not hash to the digest's key")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(..#OWNER, "email", "zzemailoutdig", "", "digest", "", note.DecisionRef, "", "", , "", digestKey), "the digest's row is made")
	Set result = ..Send("tool", ..#OWNER, ..#ADDRESS, "one", "text", "", key)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_..Delivered()_"|"_..KeyRows(..#OWNER, ..Hash(key))_"|"_..KeyRows(..#OWNER, digestKey), "1|sent|1|1|1", "the tool send is sent and the digest's row is not its claim")
}

/// The other process of TestClaimIsLocked and TestToolKeyIsLocked: holds the lock of the approval, or of the session and the key of a tool send when key is
/// given, until the test releases it (or 60 seconds pass).
ClassMethod HoldLock(approval As %String, owner As %String = "", key As %String = "")
{
	Set name = $Select(key '= "": $Name(^OcuTalon.EmailOut.Key(owner, key)), 1: $Name(^OcuTalon.EmailOut.Approval(approval)))
	Lock +@name:5
	If '$Test Quit
	Set ^OcuTalonTest("EmailOutLock", "held") = 1
	Set deadline = $ZHorolog + 60
	While ('$Data(^OcuTalonTest("EmailOutLock", "release"))) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -@name
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
	Set keyWord = "zzlogkey"_tag
	Do ..Send("tool", ..#OWNER, address, subject, text, "", keyWord_"-sent")
	Do ..Send("tool", ..#OWNER, address, subject, text, "", keyWord_"-sent")
	For answer = "unreachable", "refused", "rejected", "throw" {
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Do ..Send("tool", ..#OWNER, address, subject, text, "", keyWord_"-"_answer)
		Do ..Send("tool", ..#OWNER, address, subject, text, "", keyWord_"-"_answer)
	}
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set approval = ..Approval("zzemailoutap0060", address)
	Do ..Send("system", ..#OWNER, address, subject, text, approval)
	For word = address, subject, text, keyWord, "SERVER-WORDS", "zzrejected@example.com", "zzthrown@example.com", $Piece(address, "@", 1) {
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

/// With OAuth2ApplicationName set (Story 21.8) the send logs in with the handler's token only: an authorized answer puts the token into the authenticator for the send and
/// the authenticator, and the SASL mechanism that the login made from it, are empty again after it, also when %Net.SMTP raises an exception; a handler error, an OK
/// answer that is not authorized (with an empty token or with a token left behind), an empty token and an exception of the handler each fail the send as SMTPAUTHFailed (classified refused) before %Net.SMTP is called, so that no stored credential is used.
Method TestSenderOAuth2Paths()
{
	For answer = "", "error", "empty", "stale", "throw" {
		Kill ^||OcuTalonEmailOutSender, ^||OcuTalonEmailInHandler
		Set ^||OcuTalonEmailInHandler("answer") = answer
		Set ^||OcuTalonEmailOutSender("switch") = 0
		Set ^||OcuTalonEmailOutSender("user") = "zzuser"
		Set adapter = ##class(OcuTalon.Test.Channel.EmailOutSender).%New()
		Set adapter.SMTP = ##class(OcuTalon.Test.Channel.EmailOutSmtp).%New(), adapter.SMTP.authenticator = ##class(%Net.Authenticator).%New()
		Set adapter.SMTPServer = "smtp.example.com", adapter.SSLConfig = "OcuTalonClient"
		Set adapter.OAuth2ApplicationName = "OcuTalonMail", adapter.OAuth2CallBackHandler = "OcuTalon.Test.Channel.EmailInHandler"
		Set sc = adapter.SendMail(..Message())
		Set label = "handler answer '"_answer_"'"
		If answer = "" {
			Do $$$AssertStatusOK(sc, label_": the send goes to %Net.SMTP")
			Do $$$AssertEquals($Get(^||OcuTalonEmailOutSender("token")), "zz-token-1", label_": the authenticator held the handler's token during the send")
			Do $$$AssertEquals(adapter.SMTP.authenticator.AccessToken, "", label_": and is empty after it")
			Do $$$AssertEquals($Get(^||OcuTalonEmailOutSender("mechanism")), "zz-token-1", label_": the login's SASL mechanism held a copy of it during the send")
			Do $$$AssertNotTrue($IsObject(adapter.SMTP.authenticator.Mechanism), label_": and no mechanism, so no copy of the token, is kept after it")
		} Else {
			Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 6167, label_": the send fails with the authentication error")
			Do $$$AssertEquals(##class(OcuTalon.Channel.Email.Sender).Classify(sc), "refused", label_": classified refused")
			Do $$$AssertNotTrue($Data(^||OcuTalonEmailOutSender("sent")), label_": %Net.SMTP was not called")
			Do $$$AssertEquals(adapter.SMTP.authenticator.AccessToken, "", label_": no token reached the authenticator")
		}
	}
	Kill ^||OcuTalonEmailOutSender, ^||OcuTalonEmailInHandler
	Set ^||OcuTalonEmailInHandler("answer") = ""
	Set ^||OcuTalonEmailOutSender("switch") = 0, ^||OcuTalonEmailOutSender("user") = "zzuser", ^||OcuTalonEmailOutSender("throw") = 1
	Set adapter = ##class(OcuTalon.Test.Channel.EmailOutSender).%New()
	Set adapter.SMTP = ##class(OcuTalon.Test.Channel.EmailOutSmtp).%New(), adapter.SMTP.authenticator = ##class(%Net.Authenticator).%New()
	Set adapter.SMTPServer = "smtp.example.com", adapter.SSLConfig = "OcuTalonClient"
	Set adapter.OAuth2ApplicationName = "OcuTalonMail", adapter.OAuth2CallBackHandler = "OcuTalon.Test.Channel.EmailInHandler"
	Set raised = 0
	Try {
		Do adapter.SendMail(..Message())
	} Catch {
		Set raised = 1
	}
	Do $$$AssertEquals(raised, 1, "an exception of %Net.SMTP reaches the caller")
	Do $$$AssertEquals($Get(^||OcuTalonEmailOutSender("token")), "zz-token-1", "the authenticator held the token when it was raised")
	Do $$$AssertEquals(adapter.SMTP.authenticator.AccessToken, "", "and is empty after it")
	Do $$$AssertEquals($Get(^||OcuTalonEmailOutSender("mechanism")), "zz-token-1", "the login's SASL mechanism held a copy of it")
	Do $$$AssertNotTrue($IsObject(adapter.SMTP.authenticator.Mechanism), "and no mechanism is kept after the exception")
	Kill ^||OcuTalonEmailOutSender, ^||OcuTalonEmailInHandler
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
ClassMethod Command(origin As %String, sessionRef As %String, recipients As %String, subject As %String, text As %String, approvalRef As %String = "", key As %String = "") As OcuTalon.Msg.Command.SendEmail [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SendEmail).%New()
	Set command.Origin = origin
	Set command.SessionRef = sessionRef
	Set command.Recipients = recipients
	Set command.Subject = subject
	Set command.Text = text
	Set command.ApprovalRef = approvalRef
	Set command.IdempotencyKey = key
	Quit command
}

/// Sends the command through a new shadow instance of the probe, and answers the CommandResult.
Method Send(origin As %String, sessionRef As %String, recipients As %String, subject As %String, text As %String, approvalRef As %String = "", key As %String = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnSendEmail(..Command(origin, sessionRef, recipients, subject, text, approvalRef, key), .response)
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

/// The DigestKey that a tool send of the key has (EmailOut.ToolKeyOf).
ClassMethod Hash(key As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.Out).ToolKeyOf(..Command("tool", "", "", "", "", "", key))
}

/// The number of Delivery rows of channel email of the owner with exactly this DigestKey.
ClassMethod KeyRows(owner As %String, hash As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DigestKey FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND OwnerRef = ? AND DigestKey = ?", owner, hash)
	Set count = 0
	While result.%Next() {
		If result.%Get("DigestKey") = hash Set count = count + 1
	}
	Quit count
}

/// The id of the first Delivery row of channel email of the owner with exactly this DigestKey, or "" when there is none.
ClassMethod KeyRowId(owner As %String, hash As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, DigestKey FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND OwnerRef = ? AND DigestKey = ? ORDER BY ID", owner, hash)
	Set id = ""
	While (id = "") && result.%Next() {
		If result.%Get("DigestKey") = hash Set id = result.%Get("ID")
	}
	Quit id
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
