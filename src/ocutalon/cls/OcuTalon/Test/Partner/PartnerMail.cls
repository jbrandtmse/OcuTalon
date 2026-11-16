Include Ensemble

/// Tests of the mail method of the partner warning of a Settings contact, through EmailOut's system send (Story 23.13; AD-14 as amended, AD-16, AD-25). They need no production, so they run warm: a shadow
/// instance of Test.Channel.EmailOutProbe takes a SendEmail command with origin system and the approval's Ref, as FixExecutor sends it, and records the message that it would deliver. The rows are an executing
/// partner_warning request of a ZZNS/ZZPROD incident and two Settings contacts (names that begin zzpc); the mailbox, its owner and the online-demo flag are saved before the class and put back after it.
///   - TestSameAddressIsSent (AC5): both contacts are as approved: one email from the mailbox to exactly the two stored addresses, the approved notice byte for byte, the subject Delay notice (never the Simulated one) and one Delivery row;
///   - TestRemovedContactIsSkipped (AC7): a contact that was removed, or that no longer lists the production, is skipped with the code removed and gets nothing;
///   - TestChangedAddressIsSkipped (AC7): a contact whose address was changed is skipped with the code changed; neither its old nor its new address ever appears in a send;
///   - TestQuitStageIsSent (DW-1422): a send that failed only on the answer to QUIT is sent, with its claim marked sent;
///   - TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan (DW-1429): a partner send that times out at the greeting or EHLO answers MESSAGEUNREACHABLE, its claim is failed and the one classifier (SendOutcome) and the chat (Notice ResultKey)
///     read it as not sent; one that times out after the message data began answers MESSAGEMAYHAVESENT, its claim is maysent and both read it as may have been sent;
///   - TestAllSkippedSendsNothing (AC7): with every contact gone the mail method has no recipient and EmailOut refuses the send: nothing is delivered and no claim is made;
///   - TestOnlineDemoRefusesPartnerWarning (AC8): with the online-demo flag on EmailOut answers not_available first: nothing is delivered, no claim row;
///   - TestFixtureIsNeverMailed (AC8): an executing row of the demo's Orders production, whose contact is fictional, gets no mail method: EmailOut refuses it and sends nothing;
///   - TestOneSendPerApproval (AC5): a second send of the same approval answers already_sent after a sent one and failed after a failed one: nothing is sent again, and there is one Delivery row;
///   - TestTamperedRowIsRefused (AC5): a row whose to is an address, whose ids are not its targets or whose text is not the stored notice has no mail method: EmailOut refuses it;
///   - TestLogHoldsNoContact (AC3): after sends, skips and a failure the event log holds no contact's name or address.
Class OcuTalon.Test.Partner.PartnerMail Extends %UnitTest.TestCase
{

/// The operation under test: EmailOut with its delivery replaced.
Parameter PROBE = "OcuTalon.Test.Channel.EmailOutProbe";

Parameter MAILBOX = "zzpartnermail@example.com";

Parameter OWNERKEY = "email.owner";

Parameter NOTICE = "Orders from your feed failed for three minutes.";

Parameter KIND = "OcuTalon.Fix.Kind";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, and the IDs of its contacts, comma-separated.
Property Refs As %String(MAXLEN = "");

Property Contacts As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PartnerMail", "n"))
	Kill ^OcuTalonTest("PartnerMail", "saved")
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("PartnerMail", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Set ^OcuTalonTest("PartnerMail", "online") = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Reset()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Reset()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Reset()
	For key = "email.address", "email.owner" {
		If $Data(^OcuTalonTest("PartnerMail", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Get(^OcuTalonTest("PartnerMail", "online")))
	Kill ^OcuTalonTest("PartnerMail", "saved"), ^OcuTalonTest("PartnerMail", "online")
	Quit $$$OK
}

Method TestSameAddressIsSent()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "the approved addresses are sent to")
	Do $$$AssertEquals(..Delivered(), 1, "one email was delivered")
	Set sent = $Get(^||OcuTalonEmailOutProbe("sent", 1))
	Do $$$AssertEquals($ListGet(sent, 1)_"|"_$ListGet(sent, 2), ..#MAILBOX_"|"_addressA_","_addressB, "from the mailbox, to exactly the two stored addresses in the order of to")
	Do $$$AssertEquals($ListGet(sent, 4), ..#NOTICE, "with the approved notice byte for byte")
	Do $$$AssertEquals($ListGet(sent, 3), "Delay notice", "and the subject Delay notice")
	Do $$$AssertEquals($Find($ListGet(sent, 3), "Simulated"), 0, "which is never the Simulated subject of the demo's notice")
	Do $$$AssertEquals(..Claims(approval), 1, "and one Delivery row records it, with the approval's Ref")
}

Method TestRemovedContactIsSkipped()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Remove(b)
	Do ..Mailed(approval, .recipients, , , .skipped)
	Do $$$AssertEquals(recipients.%ToJSON()_"|"_skipped.%ToJSON(), "["""_addressA_"""]|[{""id"":"_b_",""code"":""removed"",""reason"":"""_$Parameter("OcuTalon.Fix.Kind.PartnerWarning", "NOSTART")_"""}]", "the mail method keeps the first address and skips the removed contact, with no name or address")
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "the send goes out")
	Set sent = $Get(^||OcuTalonEmailOutProbe("sent", 1))
	Do $$$AssertEquals(..Delivered()_"|"_$ListGet(sent, 2), "1|"_addressA, "to the first address only")
	Set unlisted = ..Approval(.owner2, .a2, .b2, .addressA2, .addressB2)
	Set row = ##class(OcuTalon.Data.PartnerContact).%OpenId(b2)
	Set row.Productions = [{"namespace": "ZZNS", "production": "ZZOTHER"}].%ToJSON()
	Do row.%Save()
	Do ..Mailed(unlisted, .recipients, , , .skipped)
	Do $$$AssertEquals(recipients.%Size()_"|"_skipped.%Get(0).code, "1|removed", "a contact that no longer lists the production is skipped as removed")
}

Method TestChangedAddressIsSkipped()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Set changed = "zzpcchanged"_..Number_"@example.com"
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Readdress(b, changed)
	Do ..Mailed(approval, .recipients, , , .skipped)
	Do $$$AssertEquals(skipped.%ToJSON(), "[{""id"":"_b_",""code"":""changed"",""reason"":"""_$Parameter("OcuTalon.Fix.Kind.PartnerWarning", "NOSTART")_"""}]", "the mail method skips the contact whose address changed")
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|sent", "the send goes out")
	Set all = ""
	For n = 1:1:..Delivered() Set all = all_$ListToString($Get(^||OcuTalonEmailOutProbe("sent", n)), "|")_"|"
	Do $$$AssertEquals(..Delivered()_"|"_$ListGet(^||OcuTalonEmailOutProbe("sent", 1), 2), "1|"_addressA, "to the first address only")
	Do $$$AssertEquals($Find(all, changed), 0, "the new address is in no send")
	Do $$$AssertEquals($Find(all, addressB), 0, "and neither is the old one")
}

Method TestAllSkippedSendsNothing()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Remove(a)
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Readdress(b, "zzpcchanged"_..Number_"@example.com")
	Set mailed = ..Mailed(approval, .recipients, , , .skipped)
	Do $$$AssertEquals(mailed_"|"_recipients.%Size()_"|"_skipped.%Size(), "1|0|2", "the mail method is as approved and has no recipient left, with both skipped")
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|refused|"_$Parameter(..#PROBE, "MESSAGEREFUSED"), "EmailOut refuses a send with no recipient")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "0|0", "nothing is delivered and no claim is made")
}

Method TestOnlineDemoRefusesPartnerWarning()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|not_available|"_$Parameter(..#PROBE, "MESSAGEUNAVAILABLE"), "the online demo answers not_available")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "0|0", "nothing is delivered and no claim row is written")
}

Method TestFixtureIsNeverMailed()
{
	Do ..Mailbox()
	Set owner = ##class(OcuTalon.Test.Data.Fixture).Session("zzpmailfix"_..Number)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_owner
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", "OcuTalon.Demo.Orders.Production")
	Set ..Refs = ..Refs_","_incident
	Set fields = {"FixKind": "partner_warning", "FixTargets": "1", "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Do fields.%Set("FixParameters", {"text": (..#NOTICE), "to": "1"}.%ToJSON())
	Do fields.%Set("DryRun", {"notice": (..#NOTICE), "recipients": [{"id": 1, "name": "Orders Partner IT", "address": "it@orders-partner.example"}], "simulated": 1}.%ToJSON())
	Set approval = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "executing", , fields)
	Set ..Refs = ..Refs_","_approval
	Set mailed = ..Mailed(approval, .recipients, , , .skipped)
	Do $$$AssertEquals(mailed_"|"_recipients.%Size(), "0|0", "the fixture's contact has no mail method")
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "EmailOut refuses it")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "0|0", "and nothing is sent")
}

Method TestOneSendPerApproval()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Set first = ..Send(approval, owner)
	Set second = ..Send(approval, owner)
	Do $$$AssertEquals(first.Outcome_"|"_second.Ok_"|"_second.Outcome_"|"_second.Message, "sent|1|already_sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "a second send of a sent approval answers already_sent")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "1|1", "nothing is sent again and there is one Delivery row")
	Set approval2 = ..Approval(.owner2, .a2, .b2, .addressA2, .addressB2)
	Set ^||OcuTalonEmailOutProbe("answer") = "unreachable"
	Set failed = ..Send(approval2, owner2)
	Kill ^||OcuTalonEmailOutProbe("answer")
	Set again = ..Send(approval2, owner2)
	Do $$$AssertEquals(failed.Ok_"|"_again.Ok_"|"_again.Outcome_"|"_again.Message, "0|0|failed|"_$Parameter(..#PROBE, "MESSAGEFAILED"), "a send that failed is not tried again")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval2), "2|1", "the second approval was handed to the server once only, and has one Delivery row")
}

/// DW-1422: a partner send whose only failure is the answer to QUIT (the server took the message) is sent: the answer is sent, the claim is marked sent and the same approval again answers already_sent.
Method TestQuitStageIsSent()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Set ^||OcuTalonEmailOutProbe("answer") = "quit"
	Set result = ..Send(approval, owner)
	Kill ^||OcuTalonEmailOutProbe("answer")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|sent|"_$Parameter(..#PROBE, "MESSAGESENT"), "a partner send that failed only on QUIT is sent")
	Do $$$AssertEquals(..Delivered()_"|"_..Claims(approval), "1|1", "it was handed over once and has one Delivery row")
	Set claim = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval))
	Do $$$AssertEquals("["_claim.FallbackReason_"]", "[]", "whose claim is marked sent")
	Set again = ..Send(approval, owner)
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "1|already_sent", "the same approval again is already sent")
	Do $$$AssertEquals(..Delivered(), 1, "and nothing more is delivered")
}

/// DW-1429: a partner send that stops answering is "may have been sent" only once the message data began. A timeout at the greeting or EHLO (the likeliest cause is an implicit-TLS port used without TLS) never
/// handed the message over: it answers MESSAGEUNREACHABLE, marks the claim failed, and the classifier and the chat say not sent. A timeout after the data began answers MESSAGEMAYHAVESENT, marks the claim maysent, and both say may have been sent.
Method TestTimeoutIsMayHaveSentOnlyOnceTheDataBegan()
{
	Do ..Mailbox()
	For answer = "timeoutearly", "timeout" {
		Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB, "zzpctm"_answer)
		Set ^||OcuTalonEmailOutProbe("answer") = answer
		Set result = ..Send(approval, owner)
		Kill ^||OcuTalonEmailOutProbe("answer")
		Set maySent = (answer = "timeout")
		Set expected = $Parameter(..#PROBE, $Select(maySent: "MESSAGEMAYHAVESENT", 1: "MESSAGEUNREACHABLE"))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|failed|"_expected, answer_": the partner send answers "_$Select(maySent: "MESSAGEMAYHAVESENT", 1: "MESSAGEUNREACHABLE"))
		Set claim = ##class(OcuTalon.Data.Delivery).%OpenId(..ClaimId(approval))
		Do $$$AssertEquals(claim.FallbackReason, $Select(maySent: "maysent", 1: "failed"), answer_": and its claim is marked "_$Select(maySent: "maysent", 1: "failed"))
		Set outcome = ##class(OcuTalon.Fix.Kind.PartnerWarning).SendOutcome(approval, "failed", 0, 0, 0, result.Message)
		Do $$$AssertEquals(outcome, $Select(maySent: "maysent", 1: "notsent"), answer_": the classifier reads the answer as "_$Select(maySent: "maysent", 1: "notsent"))
		Set fixResult = ##class(OcuTalon.Fix.Msg.FixResult).%New()
		Set fixResult.ApprovalRef = approval
		Set fixResult.Final = 1
		Set fixResult.Total = 2
		Set fixResult.Reason = result.Message
		Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("failed", fixResult, "partner_warning", 0), $Select(maySent: "result.partnerMaySent", 1: "fix.emailNotSent"), answer_": and the chat reads "_$Select(maySent: "result.partnerMaySent", 1: "fix.emailNotSent"))
	}
}

Method TestTamperedRowIsRefused()
{
	Do ..Mailbox()
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(approval)
	Set row.FixParameters = {"text": (..#NOTICE), "to": (addressA_","_addressB)}.%ToJSON()
	Do row.%Save()
	Do $$$AssertEquals(..Mailed(approval), 0, "a to that holds addresses has no mail method")
	Set row.FixParameters = {"text": (..#NOTICE), "to": (b_","_a)}.%ToJSON()
	Do row.%Save()
	Do $$$AssertEquals(..Mailed(approval), 0, "ids that are not the targets, in that order, have none")
	Set row.FixParameters = {"text": "Another notice.", "to": (a_","_b)}.%ToJSON()
	Do row.%Save()
	Do $$$AssertEquals(..Mailed(approval), 0, "a text that is not the stored notice has none")
	Set result = ..Send(approval, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "EmailOut refuses the row")
	Do $$$AssertEquals(..Delivered(), 0, "and sends nothing")
	Set row.State = "approved"
	Set row.FixParameters = {"text": (..#NOTICE), "to": (a_","_b)}.%ToJSON()
	Do row.%Save()
	Do $$$AssertEquals(..Mailed(approval), 0, "a row that is not executing has none")
}

Method TestLogHoldsNoContact()
{
	Do ..Mailbox()
	Set last = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do last.%Next()
	Set start = +last.%GetData(1)
	Set tag = $Translate($ZHorolog, ".", "")_$Job
	Set approval = ..Approval(.owner, .a, .b, .addressA, .addressB, "zzpclog"_tag)
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Remove(b)
	Do ..Send(approval, owner)
	Do ..Send(approval, owner)
	Set approval2 = ..Approval(.owner2, .a2, .b2, .addressA2, .addressB2, "zzpclog2"_tag)
	Set ^||OcuTalonEmailOutProbe("answer") = "rejected"
	Do ..Send(approval2, owner2)
	Kill ^||OcuTalonEmailOutProbe("answer")
	For word = "zzpclog"_tag, "zzpclog2"_tag, addressA, addressB, addressA2, addressB2, ..#NOTICE {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", word), 0, "no Ens.Util.Log row holds '"_word_"'")
	}
	Set own = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text [ ?", start, "EmailOut sent one email")
	Do own.%Next()
	Do $$$AssertTrue(+own.%GetData(1) > 0, "the operation does log its outcomes in this test's own rows (so the check above can fail)")
}

/// --- helpers ---
/// Makes a session, an incident of ZZNS/ZZPROD and two contacts (names that begin zzpc, addresses of their own), and an executing partner_warning request that holds both approved addresses;
/// its Ref. owner, a, b, addressA and addressB are the session's Ref, the two contacts' IDs and addresses. tag is part of the contacts' names and addresses.
Method Approval(Output owner As %String, Output a As %Integer, Output b As %Integer, Output addressA As %String, Output addressB As %String, tag As %String = "") As %String [ Private ]
{
	Set tag = $Select(tag '= "": tag, 1: "zzpc"_..Number_$Increment(^OcuTalonTest("PartnerMail", "k")))
	Set addressA = tag_"a@example.com"
	Set addressB = tag_"b@example.com"
	Set owner = ##class(OcuTalon.Test.Data.Fixture).Session("zzpmail"_..Number_$Increment(^OcuTalonTest("PartnerMail", "s")))
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_owner
	Set a = ##class(OcuTalon.Test.Fix.PartnerSupport).Contact("zzpc"_tag_" A", addressA)
	Set b = ##class(OcuTalon.Test.Fix.PartnerSupport).Contact("zzpc"_tag_" B", addressB)
	Set ..Contacts = ..Contacts_$Select(..Contacts = "": "", 1: ",")_a_","_b
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", "ZZPROD")
	Set ..Refs = ..Refs_","_incident
	Set fields = {"FixKind": "partner_warning", "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Do fields.%Set("FixTargets", a_","_b)
	Do fields.%Set("FixParameters", {"text": (..#NOTICE), "to": (a_","_b)}.%ToJSON())
	Do fields.%Set("DryRun", {"notice": (..#NOTICE), "recipients": [{"id": (+a), "name": ("zzpc"_tag_" A"), "address": (addressA)}, {"id": (+b), "name": ("zzpc"_tag_" B"), "address": (addressB)}], "simulated": 0}.%ToJSON())
	Set approval = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "executing", , fields)
	Set ..Refs = ..Refs_","_approval
	Quit approval
}

/// The mailbox: an address and its owner session (the product keys that EmailOut reads).
Method Mailbox() [ Private ]
{
	Kill ^||OcuTalonEmailOutProbe
	Do ##class(OcuTalon.Data.Setting).Set("email.address", ..#MAILBOX)
	Do ##class(OcuTalon.Data.Setting).Set(..#OWNERKEY, "zzpmailowner"_..Number)
}

/// Sends the command that FixExecutor sends (origin system, the approval's Ref and the owner's session, nothing else) through a new shadow instance of the probe; the CommandResult.
Method Send(approval As %String, owner As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set command = ##class(OcuTalon.Msg.Command.SendEmail).%New()
	Set command.Origin = "system"
	Set command.SessionRef = owner
	Set command.ApprovalRef = approval
	Set sc = probe.OnSendEmail(command, .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertTrue($IsObject(response), "and the answer is a CommandResult")
	Quit response
}

/// The mail method of the approval's row (Fix.Kind Mailed): 1 or 0, with its outputs.
Method Mailed(approval As %String, Output recipients, Output subject, Output text, Output skipped) As %Boolean [ Private ]
{
	Quit $ClassMethod(..#KIND, "Mailed", ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(approval), .recipients, .subject, .text, .skipped)
}

/// The number of messages that Deliver has seen.
ClassMethod Delivered() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonEmailOutProbe("calls"))
}

/// The id of the Delivery row of channel email with the approval's Ref. A copy of Test.Channel.EmailOut's private ClaimId, kept for DW-1417 (Story 23.14), which moves the shared EmailOut test helpers into one class.
ClassMethod ClaimId(approval As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND ApprovalRef = ?", approval)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of Delivery rows of channel email with the approval's Ref.
ClassMethod Claims(approval As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND ApprovalRef = ?", approval)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Puts everything back to a clean start: the probe's records, the mailbox keys, the online-demo flag, the contacts and the fixture rows of the test.
Method Reset() [ Private ]
{
	Kill ^||OcuTalonEmailOutProbe, ^||OcuTalonEmailOutSender
	For key = "email.address", "email.owner" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Test.Fix.PartnerSupport).Remove(..Contacts)
	Set ..Contacts = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
}

}
