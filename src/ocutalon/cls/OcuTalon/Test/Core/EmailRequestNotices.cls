/// The integration test of a standalone email request's notices (Story 21.11; AD-31, AD-32; Story 22.7 P4), over the running production: the real
/// BridgeSink handles the approval.raised event of a fixture email request (kind fix, FixKind email, no incident, a session as its owner), and the Notification it
/// sends reaches the simulated phone and the web chat, where each operation renders the stored dry run. THIS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21).
///   - TestRequestReachesTheChannelsAndLeavesNoTrace: the phone message within WAIT seconds holds the exact dry-run lines (the recipients, the subject and the
///     text, with the line break and the tab as \uXXXX) and the request's ApprovalRef, with no answer; the web chat's Delivery row is a card with the same lines;
///     then Bridge.Approval Answer reject edits the phone message in place to the render of answered.rejected, with no second message; and
///     OcuTalon.Test.Core.SecretHandoff TraceLeaks finds none of the recipients, the subject and the text (each carries a unique marker) in ^Ens.MessageBodyD,
///     ^Ens.MessageBodyS, ^Ens.MessageHeaderD or ^Ens.Util.LogD: the P4 pin. Its control is that the Notification was sent and stored, with the ApprovalRef and Slots {}.
///     mutation: put a recipient, the subject or the text into the notification's Slots (BridgeSink.ToolNoticeOf composing the request with the dry run's inputs) -> TraceLeaks names
///     Ens.MessageBodyD and this test is red.
/// The test makes its own session and rows and removes them (Fixture Clean).
Class OcuTalon.Test.Core.EmailRequestNotices Extends OcuTalon.Test.Core.InProduction
{

/// Seconds to wait for a message of the phone or a row of the web chat.
Parameter WAIT = 40;

/// The IRIS user who answers: it holds OcuTalonUser.
Parameter ANSWERER = "ocutalon";

Method TestRequestReachesTheChannelsAndLeavesNoTrace()
{
	If '..Guard() Quit
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser")
	If 'holds Quit
	Set session = ..Session("email")
	Set mark = "zzer"_..Number
	Set first = mark_"a@example.test", second = mark_"b@example.test"
	Set subject = mark_"subject marker  twice"
	Set text = mark_"text marker,"_$Char(13, 10)_$Char(9)_"and a tab."
	Set markers = $ListBuild(first, second, mark_"subject", mark_"text")
	Set position = 0
	While $ListNext(markers, position, marker) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(marker), "", "before the request no trace global holds "_marker)
	}
	Set dry = {"to": [(first), (second)], "subject": (subject), "text": (text)}.%ToJSON()
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "pending", , {"Kind": "fix", "FixKind": "email", "DryRun": (dry), "RequiredRole": "OcuTalonUser"})
	Set ..Refs = ..Refs_","_ref
	Set lf = $Char(10)
	Set expected = "Send an email"_lf_"Why: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval."_lf_"Dry run:"_lf
	Set expected = expected_"to: [""" _first_""","""_second_"""]"_lf_"subject: """_subject_""""_lf_"text: """_mark_"text marker,\u000D\u000A\u0009and a tab."""_lf_"Approving sends exactly this email once."

	Do $$$AssertStatusOK(##class(OcuTalon.Core.BridgeSink).OnEvent("approval.raised", session, {"ref": (ref)}), "the real sink handles approval.raised")
	Set message = ..WaitMessage(session, ref)
	Do $$$AssertTrue($IsObject(message), "the phone gets the request's message within "_..#WAIT_" seconds")
	If '$IsObject(message) Quit
	Do $$$AssertEquals(message.Text, expected, "its text is the dry run's exact lines")
	Do $$$AssertEquals(message.ApprovalRef_"|"_message.Answer, ref_"|", "it carries the request's Ref, so the phone draws Approve and Reject, and no answer")
	Set web = ..WaitWebRow(session, "approval")
	Do $$$AssertTrue($IsObject(web), "the web chat gets a row of kind approval")
	If $IsObject(web) {
		Do $$$AssertEquals(web.ApprovalRef, ref, "with the request's Ref")
		Do $$$AssertEquals(web.Text, expected, "and the same lines as its text")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "it is a card of the web chat")
	}

	Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT CatalogKey, Slots FROM OcuTalon_Msg.Notification WHERE ApprovalRef = ?", ref)
	Set count = 0, shapes = ""
	While found.%Next() {
		Set count = count + 1
		Set shape = found.%GetData(1)_"|"_found.%GetData(2)
		If $ListFind($ListFromString(shapes, ";"), shape) = 0 Set shapes = shapes_$Select(shapes = "": "", 1: ";")_shape
	}
	Do $$$AssertEquals(found.%SQLCODE < 0, 0, "the stored Notifications are read")
	Do $$$AssertTrue(count > 0, "the Notification was sent and stored (the control of the trace scan)")
	Do $$$AssertEquals(shapes, "fix.emailRequest|{}", "and every one holds the key and empty Slots, with the ApprovalRef")

	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "reject", "phone", user, session, .winner), "done", "Reject is accepted")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do row.%Reload()
	Set rejected = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.rejected", {"channel": "phone", "time": (row.AnsweredAt)}.%ToJSON(), "phone", ##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), .sc)
	Do $$$AssertStatusOK(sc, "answered.rejected renders")
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertEquals(answered.Answer, rejected, "the request's message has the render of answered.rejected as its Answer")
	Do $$$AssertEquals(answered.Text_"|"_answered.ApprovalRef, expected_"|"_ref, "and keeps its text and request")
	Hang 2
	Do $$$AssertEquals(..PhoneCount(session), 1, "and the phone has no second message")

	Set position = 0
	While $ListNext(markers, position, marker) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(marker), "", "no trace global holds "_marker_" (the recipients, the subject and the text are in no message, header or log row)")
	}
}

/// --- helpers ---
/// The newest phone message of the session that carries the ApprovalRef, polled up to WAIT seconds; "" when none arrives.
Method WaitMessage(session As %String, ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
		For i = 1:1:rows.Count() {
			Set message = ..Message(rows.GetAt(i).Ref)
			If message.ApprovalRef = ref {
				Set found = message
				Quit
			}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The message once it has an Answer (polled up to WAIT seconds), else as it is.
Method WaitAnswer(messageRef As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set message = ..Message(messageRef)
		If (message.Answer '= "") || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit message
}

/// The newest web Delivery row of the session of the kind that is a card (it has a ChannelMessageId), polled up to WAIT seconds; "" when none arrives.
Method WaitWebRow(session As %String, kind As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		For i = rows.Count():-1:1 {
			Set candidate = rows.GetAt(i)
			If (candidate.Channel = "web") && (candidate.Kind = kind) && (candidate.ChannelMessageId '= "") {
				Set found = candidate
				Quit
			}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The SimMessage of the Ref as the table holds it: an instance that this process already has open is reloaded, so that a later change by the production shows.
Method Message(ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen(ref)
	If $IsObject(message) Do message.%Reload()
	Quit message
}

/// The number of phone messages of the session.
Method PhoneCount(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
