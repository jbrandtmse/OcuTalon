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
///   - TestRealRaiseThenExpireEditsInPlace (QA): the request is raised through the REAL path, Fix.Kind.Email Raise (the mailbox's address saved, the session's user an admin) and
///     Bridge.Approval Raise, which fires approval.raised through Decide into the running production's sink, with no direct OnEvent call: the phone and the web chat get the same text and
///     buttons, then Bridge.Approval Expire edits the phone message in place to the render of answered.expired {time = ExpiresAt} with no second message, and the web chat gets the answered
///     notice's row (no message id, no text), and no trace global holds a marker;
///   - TestRealApproveWithNoMailServerIsReportedNotSent (QA): the real request is approved through Approval Answer with EmailOut stopped (nothing can be sent), the real FixExecutor
///     ends it failed with the plain reason of CommandsIn (FixRun Reason, MESSAGENOTCONNECTED), the phone message is edited to answered.approved, and a new phone message and a web result card
///     are the render of fix.emailNotSent {reason = that sentence}, with no buttons, and no marker is in the trace;
///   - TestResultsReachThePhoneAndTheWebChat (QA): a real request made executing by hand and closed through Approval FinishExecution done sends fix.emailSent ("The email was sent.") as a
///     new phone message with no buttons and a web result card; a closed failed run whose FixRun Reason is a raw error text (it names an address) shows MESSAGEFAILED and none of the raw text.
/// The test makes its own session and rows and removes them (Fixture Clean).
Class OcuTalon.Test.Core.EmailRequestNotices Extends OcuTalon.Test.Core.InProduction
{

/// Seconds to wait for a message of the phone or a row of the web chat.
Parameter WAIT = 40;

/// The IRIS user who answers: it holds OcuTalonUser.
Parameter ANSWERER = "ocutalon";

/// The mailbox address setting as found: $ListBuild(exists, value, owner), or "" when it was not read.
Property Found As %List;

/// 1 while a test has stopped EmailOut.
Property MailOutStopped As %Boolean [ InitialExpression = 0 ];

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

/// QA, the real raise path (Story 22.7's Fix.Kind.Email Raise, then Bridge.Approval Raise and the production's sink), and the real expiry.
///     mutation: BridgeSink.ToolNotice gating on Replayable only (no standalone email) -> no phone message arrives and this test is red.
Method TestRealRaiseThenExpireEditsInPlace()
{
	If '..Guard() Quit
	If '..Mailbox() Quit
	Set session = ..Owner("realexpire")
	Set mark = "zzqx"_..Number
	Set first = mark_"a@example.test", second = mark_"b@example.test"
	Set subject = mark_"subject marker  twice"
	Set text = mark_"text marker,"_$Char(13, 10)_$Char(9)_"and a tab."
	Set sc = ##class(OcuTalon.Fix.Kind.Email).Raise({"recipients": [(first), (second)], "subject": (subject), "text": (text)}, session, ##class(OcuTalon.Bridge.Ids).NewRef(), "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(ref '= "")_"|"_refusal, "1|1|", "the real Fix.Kind.Email Raise raises the request")
	If ref = "" Quit
	Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner(session)
	Set expected = ..Expected(first, second, subject, mark_"text marker,\u000D\u000A\u0009and a tab.")
	Set message = ..WaitMessage(session, ref)
	Do $$$AssertTrue($IsObject(message), "the phone gets the request's message within "_..#WAIT_" seconds, through the production's own sink")
	If '$IsObject(message) Quit
	Do $$$AssertEquals(message.Text, expected, "its text is the dry run's exact lines")
	Do $$$AssertEquals(message.ApprovalRef_"|"_message.Answer, ref_"|", "with the request's Ref and no answer")
	Set web = ..WaitWebRow(session, "approval", 1)
	Do $$$AssertTrue($IsObject(web), "the web chat gets the request's card")
	If $IsObject(web) Do $$$AssertEquals(web.ApprovalRef_"|"_web.Text, ref_"|"_expected, "with the request's Ref and the same lines")

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Expire(ref), "the request expires")
	Set row = ..Request(ref)
	Set expired = ..Render("answered.expired", {"time": (row.ExpiresAt)}, "phone")
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertEquals(answered.Answer, expired, "the request's message has the render of answered.expired as its Answer")
	Do $$$AssertEquals(answered.Text_"|"_answered.ApprovalRef, expected_"|"_ref, "and keeps its text and request")
	Hang 2
	Do $$$AssertEquals(..PhoneCount(session), 1, "and the phone has no second message")
	Set webAnswered = ..WaitWebRow(session, "answered", 0)
	Do $$$AssertTrue($IsObject(webAnswered), "the web chat has the answered notice's row")
	If $IsObject(webAnswered) Do $$$AssertEquals(webAnswered.ChannelMessageId_"|"_webAnswered.Text, "|", "with no message id and no text")
	Do ..AssertNoTrace($ListBuild(first, second, mark_"subject", mark_"text"))
}

/// QA, the real approval of a request that cannot be sent: EmailOut is stopped, so the real FixExecutor ends the request failed with the plain reason of CommandsIn, and nothing is sent.
///     mutation: BridgeSink.EmailReason passing no reason (always MESSAGEFAILED) -> the result is not the render of fix.emailNotSent with MESSAGENOTCONNECTED and this test is red.
Method TestRealApproveWithNoMailServerIsReportedNotSent()
{
	If '..Guard() Quit
	If '..Mailbox() Quit
	Set user = ..#ANSWERER
	Set session = ..Owner("realapprove")
	Set mark = "zzqy"_..Number
	Set first = mark_"a@example.test"
	Set subject = mark_"subject marker"
	Set text = mark_"text marker."
	Set sc = ##class(OcuTalon.Fix.Kind.Email).Raise({"recipients": [(first)], "subject": (subject), "text": (text)}, session, ##class(OcuTalon.Bridge.Ids).NewRef(), "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(ref '= "")_"|"_refusal, "1|1|", "the real Fix.Kind.Email Raise raises the request")
	If ref = "" Quit
	Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner(session)
	Set message = ..WaitMessage(session, ref)
	Do $$$AssertTrue($IsObject(message), "the phone gets the request")
	If '$IsObject(message) Quit
	Do $$$AssertStatusOK(..StopMailOut(), "EmailOut is stopped, so that nothing can be sent")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "phone", user, session, .winner), "done", "Approve is accepted")
	Do $$$AssertEquals(..WaitState(ref, "failed"), "failed", "the real FixExecutor ends the request failed")
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(ref)
	Do $$$AssertTrue($IsObject(run), "it has a FixRun")
	If '$IsObject(run) Quit
	Set sentence = $Parameter("OcuTalon.Channel.Email.Out", "MESSAGENOTCONNECTED")
	Do $$$AssertEquals(run.Reason, sentence, "whose Reason is the plain reason of CommandsIn")
	Set row = ..Request(ref)
	Set approved = ..Render("answered.approved", {"channel": "phone", "time": (row.AnsweredAt)}, "phone")
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertEquals(answered.Answer, approved, "the request's message has the render of answered.approved as its Answer")
	Set plain = ..WaitPlain(session)
	Do $$$AssertTrue($IsObject(plain), "a new phone message arrives")
	If $IsObject(plain) Do $$$AssertEquals(plain.Text_"|"_plain.ApprovalRef_"|"_plain.Answer, ..Render("fix.emailNotSent", {"reason": (sentence)}, "phone")_"||", "it is the phone render of fix.emailNotSent with that sentence and has no buttons")
	Set webResult = ..WaitWebRow(session, "result", 1)
	Do $$$AssertTrue($IsObject(webResult), "the web chat gets a result card")
	If $IsObject(webResult) Do $$$AssertEquals(webResult.ApprovalRef_"|"_webResult.Text, ref_"|"_..Render("fix.emailNotSent", {"reason": (sentence)}, "web"), "with the web render of fix.emailNotSent")
	Do $$$AssertEquals(..PhoneCount(session), 2, "the phone holds the two messages")
	Do ..AssertNoTrace($ListBuild(first, mark_"subject", mark_"text"))
}

/// QA, the results through the real FinishExecution: done is "The email was sent."; a failed run with a raw reason shows only MESSAGEFAILED.
///     mutation: BridgeSink.ToolNoticeOf giving a done standalone email no fix.emailSent -> no result message arrives and this test is red.
Method TestResultsReachThePhoneAndTheWebChat()
{
	If '..Guard() Quit
	Set session = ..Session("results")
	Set dry = {"to": ["zzqr@example.test"], "subject": "Zzqr subject", "text": "Zzqr text."}.%ToJSON()
	Set done = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "executing", , {"Kind": "fix", "FixKind": "email", "DryRun": (dry), "RequiredRole": "OcuTalonUser"})
	Set ..Refs = ..Refs_","_done
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).FinishExecution(done, "done"), "the run ends done")
	Set plain = ..WaitPlain(session)
	Do $$$AssertTrue($IsObject(plain), "the phone gets a message")
	If $IsObject(plain) Do $$$AssertEquals(plain.Text_"|"_plain.ApprovalRef_"|"_plain.Answer, "The email was sent.||", "it is The email was sent., with no buttons")
	Set web = ..WaitWebRow(session, "result", 1)
	Do $$$AssertTrue($IsObject(web), "the web chat gets a result card")
	If $IsObject(web) Do $$$AssertEquals(web.ApprovalRef_"|"_web.Text, done_"|The email was sent.", "with the same sentence")

	Set raw = "java.lang.Exception: boom for zzqr@example.test"
	Set failed = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "executing", , {"Kind": "fix", "FixKind": "email", "DryRun": (dry), "RequiredRole": "OcuTalonUser"})
	Set ..Refs = ..Refs_","_failed
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Set run.ApprovalRef = failed
	Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set run.EndedAt = run.StartedAt
	Set run.Reason = raw
	Do $$$AssertStatusOK(run.%Save(), "its FixRun holds the raw reason")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).FinishExecution(failed, "failed"), "a run with a raw reason ends failed")
	Set sentence = $Parameter("OcuTalon.Channel.Email.Out", "MESSAGEFAILED")
	Set end = $ZHorolog + ..#WAIT
	Set count = 0
	For {
		Set count = ..PhoneCount(session)
		If (count '< 2) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(count, 2, "the phone gets the second message")
	Set found = ""
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	For i = 1:1:rows.Count() {
		Set message = ..Message(rows.GetAt(i).Ref)
		If message.Text '= "The email was sent." Set found = message
	}
	Do $$$AssertTrue($IsObject(found), "it is the not-sent message")
	If $IsObject(found) {
		Do $$$AssertEquals(found.Text, ..Render("fix.emailNotSent", {"reason": (sentence)}, "phone"), "it is the render of fix.emailNotSent with MESSAGEFAILED")
		Do $$$AssertEquals($Find(found.Text, "boom")_"|"_$Find(found.Text, "zzqr")_"|"_$Find(found.Text, "java"), "0|0|0", "and holds none of the raw reason")
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

/// The newest web Delivery row of the session of the kind that is a card (it has a ChannelMessageId; with card 0, one that has none), polled up to WAIT seconds; "" when none arrives.
Method WaitWebRow(session As %String, kind As %String, card As %Boolean = 1) As OcuTalon.Data.Delivery [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		For i = rows.Count():-1:1 {
			Set candidate = rows.GetAt(i)
			If (candidate.Channel = "web") && (candidate.Kind = kind) && ((candidate.ChannelMessageId '= "") = card) {
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


/// The render of the key with the slots (an object) for the channel at the current time, with the online-demo flag as it is.
Method Render(key As %String, slots As %DynamicObject, channel As %String) As %String [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), channel, ##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), .sc)
	Do $$$AssertStatusOK(sc, key_" renders")
	Quit text
}

/// The request text for the markers: the catalog's N1 lines, the dry-run lines with the recipients, the subject and the already escaped text line body.
Method Expected(first As %String, second As %String, subject As %String, escapedText As %String) As %String [ Private ]
{
	Set lf = $Char(10)
	Set expected = "Send an email"_lf_"Why: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval."_lf_"Dry run:"_lf
	Quit expected_"to: [""" _first_""","""_second_"""]"_lf_"subject: """_subject_""""_lf_"text: """_escapedText_""""_lf_"Approving sends exactly this email once."
}

/// A fixture session whose user is the answerer (an OcuTalon admin, so that Fix.Kind.Email Raise may raise an email to another address).
Method Owner(name As %String) As %String [ Private ]
{
	Set session = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.IrisUser = ..#ANSWERER
	Do $$$AssertStatusOK(row.%Save(), "the session's user is "_..#ANSWERER)
	Quit session
}

/// Saves the mailbox's own address (a setting that Fix.Kind.Email Raise reads, with no credential and no server, so that nothing is polled or sent) and keeps what was there for OnAfterAllTests.
/// Online demo is off. 1 when the preconditions hold.
Method Mailbox() As %Boolean [ Private ]
{
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ##class(OcuTalon.Core.Admin).Held(roles) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser and is an OcuTalon admin")
	If 'holds Quit 0
	Do $$$AssertEquals(##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), 0, "the online demo is off")
	If ..Found = "" {
		Set key = ##class(OcuTalon.Channel.Email.Out).#ADDRESSKEY
		Set ..Found = $ListBuild(##class(OcuTalon.Data.Setting).KeyIndexExists(key), ##class(OcuTalon.Data.Setting).Get(key), ##class(OcuTalon.Data.Setting).Fresh(##class(OcuTalon.Channel.Email.Out).#OWNERKEY))
		Do $$$AssertEquals($List(..Found, 3), "", "no mailbox has an owner on this stack")
		Do $$$AssertNotEquals($Extract($List(..Found, 2), 1, 4), "zzqa", "and no earlier run of this class left its address (zzqa...) saved")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(key, "zzqa"_..Number_"own@example.test"), "the mailbox's address is saved")
	}
	Quit 1
}

/// Stops EmailOut for this run (OnAfterAllTests starts it again; it keeps a disabled item disabled).
Method StopMailOut() As %Status [ Private ]
{
	Set ..MailOutStopped = 1
	Set sc = ##class(Ens.Director).TempStopConfigItem("OcuTalon.Production||EmailOut", 1)
	If $$$ISOK(sc) Do $$$AssertTrue(##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 0), "EmailOut has no job")
	Quit sc
}

/// The request's state, once it is the state or after WAIT seconds.
Method WaitState(ref As %String, state As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set row = ..Request(ref)
		Set found = $Select($IsObject(row): row.State, 1: "")
		If (found = state) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The request's row as the table holds it (reloaded).
Method Request(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The phone message of the session that carries no ApprovalRef (a result), polled up to WAIT seconds; "" when none arrives.
Method WaitPlain(session As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
		For i = 1:1:rows.Count() {
			Set message = ..Message(rows.GetAt(i).Ref)
			If message.ApprovalRef = "" {
				Set found = message
				Quit
			}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// Asserts that no trace global holds any of the markers.
Method AssertNoTrace(markers As %List) [ Private ]
{
	Set position = 0
	While $ListNext(markers, position, marker) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(marker), "", "no trace global holds "_marker)
	}
}

/// Starts EmailOut again after the test that stopped it, so that the next test runs with the production as it found it.
Method OnAfterOneTest(testname As %String) As %Status
{
	If ..MailOutStopped {
		Do ##class(Ens.Director).TempStopConfigItem("OcuTalon.Production||EmailOut", 0)
		Set ..MailOutStopped = 0
	}
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	If ..MailOutStopped {
		Do ##class(Ens.Director).TempStopConfigItem("OcuTalon.Production||EmailOut", 0)
		Set ..MailOutStopped = 0
	}
	If ..Found '= "" {
		Set key = ##class(OcuTalon.Channel.Email.Out).#ADDRESSKEY
		If $List(..Found, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(key, $List(..Found, 2))
		} Else {
			Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
		}
		Set ..Found = ""
	}
	Set refs = ..Refs
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonTest("Approval", "refs", ref))
		Quit:ref=""
		Set refs = refs_","_ref
	}
	For i = 1:1:$Length(refs, ",") {
		If $Piece(refs, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE ApprovalRef = ?", $Piece(refs, ",", i))
	}
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Quit ##super()
}
}
