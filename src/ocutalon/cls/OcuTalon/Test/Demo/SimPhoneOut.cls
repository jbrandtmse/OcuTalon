/// Tests of SimPhoneOut (Story 4.5, Story 6.3; AD-4, AD-12, AD-14, AD-32, AD-33). The handler tests are safe on a slot: no production runs
/// there, so they call the handlers on a shadow instance of OcuTalon.Channel.SimPhone.Out, with fixture sessions from
/// Test.Data.Fixture. TestThroughNotify needs the running OcuTalon.Production with demo mode on and runs in throwaways and CI only
/// (Rule 21); where no production runs it is skipped. Every expected text is rendered here through Msg.Catalog.RenderAt, with
/// the channel written out and the clock and the online-demo flag fixed.
///   - TestTellNow, TestReminder: a card-kind Notification becomes one SimMessage (kind phone, direction out, the text of the
///     telegram render, which is the phone render), one phone Delivery row (the SimMessage's Ref as ChannelMessageId, the kind and
///     the Refs, no text) and one phone event whose payload is the message's;
///   - TestIncidentNoticeAsksForItsRequest, TestLaterRequestHasItsOwnButtons: a notification of kind incident or approval is a
///     message that keeps its ApprovalRef, with its Delivery row and event; a later request is a message of its own;
///   - TestDecisionRefOnlyForTellNow (Story 41.5): the payload's decisionRef is the DecisionRef of the session's own phone tell-now Delivery row; a reminder, an incident
///     and an approval message have none, and another session's tell-now Delivery row is never read;
///   - TestSummaryMessage (Story 23.6; AC 14): a summary Notification is one plain-text phone message with the stored summary's lines, the markup of the cause, the
///     evidence and the sample error as it is, no ApprovalRef (no buttons) and no DecisionRef, with its Delivery row and one event; a missing summary is an error;
///   - TestSummaryBuiltMessage (QA; AC 14): the summary that Watch.Summary.Build makes of an incident whose cause, fix and sample error hold markup (the sample error longer than a
///     notice's error summary) is one phone message whose text shows the markup as it came and the sample error cut to the notice's length;
///   - TestOnlyRequestKindsCarryARequest: tellnow, reminder, answered and an incident with no request give no message with an
///     ApprovalRef;
///   - TestAnsweredEditsInPlace: an answered notification sets the Answer of the delivered message, keeping its Ref and Text,
///     with one more event and its Delivery row, and a later one leaves the first answer (Delivery row only); TestAnsweredWithNoMessageRecordsOnly, TestAnsweredNeverEditsAnotherSessionsMessage
///     and TestAnsweredRenderErrorChangesNothing are its edges;
///   - TestAnsweredNeverEditsAResult (Story 31.5): an answered notification that arrives after the result message of a tool call edits
///     neither the result message nor the request's: it records its Delivery row only (ChannelMessageId empty), with no new event;
///   - TestDigestMessage (Story 18.4): a digest Notification is one plain-text message whose text is OcuTalon.Channel.DigestText.Text(Slots, "phone"): the
///     greeting first, the coverage lines ("Passed:", "Failed:", "Not checked:"), the cost last with two decimals, no Markdown; one Delivery row of the kind
///     digest, no ApprovalRef or DecisionRef on the message, and one phone event; a piece that cannot be rendered is an error with no row and no event;
///   - TestTellNowKeepsDecisionRef: a tell-now message keeps the DecisionRef (the payload's decisionRef too); no other message kind does;
///   - TestActMessageHasNoGotIt: a tell-now message of an act Decision keeps no DecisionRef (no Got it); one of a tell-now Decision keeps it;
///   - TestHandledEditsInPlace: a handled Notification sets the Answer of the tell-now message to the rendered handled.marked line, keeping its Ref, Text and
///     DecisionRef, with one more phone event and a Delivery row of the kind handled that names the message;
///   - TestHandledFirstAnswerStays: a message that has an Answer (an earlier edit, or a second press) keeps it: the Delivery row only, with no event;
///   - TestHandledNoMessageRecordsOnly: with no message for the DecisionRef, or a notice that is not marked, the Delivery row only, with no edit and no event;
///   - TestHandledNeverEditsAnotherSession: another session's handled Notification, even with a Delivery row of its own that names the owner's message,
///     changes nothing of the owner's message;
///   - TestOlderMessageRenders (U-313): a message written before DecisionRef existed (the column empty) is a phone payload with an empty decisionRef, and a
///     handled Notification for a Delivery row that names it records its row only;
///   - TestTextIsTheTelegramWording: for a key that words the web differently, the phone carries the telegram wording;
///   - TestOnlineDemoTimesNameTheZone: a late reminder's time ends with " ET" on the online demo and has no suffix otherwise;
///   - TestResultIsAMessage (Story 6.4; AD-32): a result notification is one new SimMessage with the phone render of its key, no ApprovalRef
///     (so no buttons), its Delivery row and one phone event; the request's earlier message keeps its Ref and its Answer; a count of one
///     reads as the catalog's count-of-one form;
///   - TestFallbackAndNoFixWording: incident.fallback, incident.noFix and incident.noFixUnknown, each with two groups (one dated), are one
///     message of the phone render with no ApprovalRef;
///   - TestResultRenderError: a result whose key can't be rendered is an error with no message, row or event;
///   - TestOtherKindsRecordOnly: any other kind records its phone Delivery row only, with no message and no event;
///   - TestNotASession: an owner that is not a session records nothing, publishes nothing and logs one warning, before any
///     rendering (the demo-switch stack's control Notification has an unrenderable slot set);
///   - TestRenderError: a text that cannot be rendered is an error with no row and no event;
///   - TestSaveFailureKeepsNothing: a Delivery row that cannot be saved leaves no message and no event;
///   - TestPublishFailure: a phone event that cannot be published is logged and both rows stay;
///   - TestThroughNotify: in the running production, Notify sends one Notification to WebChatOut and to SimPhoneOut as the same
///     message (same body class, body id and session), and the SimMessage is there within 5 seconds.
/// The public setting onlineDemo is off during the run and put back after it. The run's number is n from
/// ^OcuTalonTest("SimPhoneOut","n") (never reset).
Class OcuTalon.Test.Demo.SimPhoneOut Extends %UnitTest.TestCase
{

/// Seconds that TestThroughNotify waits for the message.
Parameter WAIT = 5;

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The SuperSessions of the messages that TestThroughNotify sent.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SimPhoneOut", "n"))
	Set ..Refs = ""
	Set ..Supers = []
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Refs, ",") Do ##class(OcuTalon.Data.Handled).DropSession($Piece(..Refs, ",", i))
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Supers.%Size() > 0 Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// A tell-now Notification (notice.tellNow) records one SimMessage {Kind phone, Direction out, SessionRef, CreatedAt, Text}, one
/// phone Delivery row {ChannelMessageId = the message's Ref, Kind, ApprovalRef, DecisionRef, no text} and, after both are saved,
/// one phone event whose payload is Phone.FromRow of the message. The text is the telegram render and the phone render. Another
/// session's rows and stream are untouched.
Method TestTellNow()
{
	Set session = ..Session("tellnow")
	Set other = ..Session("tellnowother")
	Set slots = {"whatHappened": "Disk almost full", "reason": "you asked to hear about disk space"}
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", slots)
	Set notification.DecisionRef = "ZzDecision"_..Number
	Set notification.ApprovalRef = "ZzApproval"_..Number
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the notification is delivered")
	Do $$$AssertEquals($IsObject($Get(response)), 0, "with no response")
	Set expected = "Disk almost full"_$Char(10)_"Why now: you asked to hear about disk space"
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("notice.tellNow", slots.%ToJSON(), "telegram", "2030-01-01T12:00:00Z", 0), expected, "the telegram render is the expected text")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("notice.tellNow", slots.%ToJSON(), "phone", "2030-01-01T12:00:00Z", 0), expected, "and so is the phone render")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "the session has one phone message")
	If rows.Count() '= 1 Quit
	Set row = rows.GetAt(1)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Kind_"|"_row.Direction_"|"_row.ItemId, session_"|phone|out|", "its session, kind and direction, with no item")
	Do $$$AssertEquals(row.Text, expected, "its text")
	Do $$$AssertTrue(row.Ref ? 22(1AN,1"-",1"_"), "its Ref is a new Ref: "_row.Ref)
	Do $$$AssertEquals(row.CreatedAt, $Extract(row.CreatedAt, 1, 19)_"Z", "created to the second, in UTC")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.ApprovalRef_"|"_delivery.DecisionRef_"|"_delivery.Text, "phone|"_row.Ref_"|tellnow|ZzApproval"_..Number_"|ZzDecision"_..Number_"|", "its channel, the message's Ref, the kind and the Refs, and no text")
	}
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event is published")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.direction_"|"_payload.text_"|"_payload.createdAt, row.Ref_"|out|"_expected_"|"_row.CreatedAt, "its ref, direction, text and time")
		Do $$$AssertEquals(payload.decisionRef, notification.DecisionRef, "its decisionRef is the notification's DecisionRef")
		Set expectedPayload = ##class(%DynamicObject).%FromJSON(..Json(##class(OcuTalon.Live.Payload.Phone).FromRow(row)))
		Do $$$AssertEquals(payload.%ToJSON(), expectedPayload.%ToJSON(), "its payload is the one that FromRow makes of the message")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(other, 10).Count(), 0, "another session has no message")
	Do $$$AssertEquals(..Phones(other).%Size(), 0, "and no event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and the phone's Delivery row is not a card of the web chat")
}

/// A digest (Story 18.4) is one phone message of kind phone, direction out, whose text is OcuTalon.Channel.DigestText.Text(Slots, "phone"): the greeting
/// first, then the pieces in the digest's order with the coverage lines starting "Passed:", "Failed:" and "Not checked:", the previous day's cost last
/// with two decimals, and no Markdown. The message has no ApprovalRef and no DecisionRef; its phone Delivery row (kind digest) names it and has no text;
/// one phone event carries the message. A piece that cannot be rendered is an error with no message, row or event.
Method TestDigestMessage()
{
	Set session = ..Session("digest")
	Set slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.checked", "slots": {"checked": "the Orders production and the Billing source"}}, {"key": "digest.savedNone", "slots": {}}, {"key": "digest.cost", "slots": {"cost": 0.042}}], "lines": [{"key": "digest.passed", "slots": {"entry": "Orders production", "time": "2030-01-01T02:10:00Z"}}, {"key": "digest.failed", "slots": {"entry": "Billing source", "finding": "5 messages queued", "time": "2030-01-01T02:11:00Z"}}, {"key": "digest.notCheckedUnreachable", "slots": {"entry": "Mail source", "time": "2030-01-01T02:12:00Z"}}], "rows": [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": "2030-01-01T02:10:00Z"}]}
	Set notification = ..Notification(session, "digest", "digest.cost", slots)
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the digest is delivered")
	Set expected = ##class(OcuTalon.Channel.DigestText).Text(slots.%ToJSON(), "phone", .sc)
	Do $$$AssertStatusOK(sc, "the shared helper renders the digest for the phone")
	Do $$$AssertEquals(..PhoneCount(session), 1, "one phone message")
	Set message = ..Newest(session)
	If '$IsObject(message) Do $$$AssertTrue(0, "the message exists") Quit
	Set text = message.Text
	Do $$$AssertEquals(text, expected, "its text is DigestText.Text(Slots, ""phone"")")
	Do $$$AssertEquals($Piece(text, $Char(10), 1), "Good morning.", "the first line is the greeting")
	Do $$$AssertEquals($Piece(text, $Char(10), $Length(text, $Char(10))), "Yesterday's cost: $0.04.", "the last line is the cost with two decimals")
	For start = "Passed: Orders production (", "Failed: Billing source (5 messages queued, ", "Not checked: Mail source (" {
		Set found = 0
		For i = 1:1:$Length(text, $Char(10)) If $Extract($Piece(text, $Char(10), i), 1, $Length(start)) = start Set found = 1
		Do $$$AssertTrue(found, "a line starts '"_start_"'")
	}
	Do $$$AssertTrue(text '[ "*", "no asterisk")
	Do $$$AssertTrue(text '[ "_", "no underscore")
	Do $$$AssertTrue(text '[ "`", "no backtick")
	Do $$$AssertTrue(text '[ "#", "no hash")
	Do $$$AssertEquals(message.Kind_"|"_message.Direction_"|"_message.ApprovalRef_"|"_message.DecisionRef_"|"_message.Answer, "phone|out|||", "a phone message out, with no request, no notice and no answer")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 Do $$$AssertEquals(deliveries.GetAt(1).Channel_"|"_deliveries.GetAt(1).ChannelMessageId_"|"_deliveries.GetAt(1).Kind_"|"_deliveries.GetAt(1).Text, "phone|"_message.Ref_"|digest|", "of the kind digest, naming the message, with no text")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.text, message.Ref_"|"_expected, "for the message")
	Set broken = ..Session("digestbad")
	Set bad = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.noSuchKey", "slots": {}}], "lines": [], "rows": []}
	Do $$$AssertStatusNotOK(..Out().OnNotification(..Notification(broken, "digest", "digest.cost", bad), .response), "a digest that cannot be rendered is an error")
	Do $$$AssertEquals(..PhoneCount(broken)_"|"_##class(OcuTalon.Test.Core.Observe).DeliveryCount(broken)_"|"_..Phones(broken).%Size(), "0|0|0", "with no message, row or event")
}

/// An incident summary (Story 23.6; AC 14) is one phone message of kind phone, direction out, whose text is OcuTalon.Watch.Summary.Text(IncidentRef, "phone"): the
/// stored summary's lines, with the markup of the cause, the evidence and the sample error left as it is (the page shows plain text). The message keeps no
/// ApprovalRef (no Approve or Reject) and no DecisionRef; its phone Delivery row (kind summary) names it and has no text; one phone event follows. A summary that is
/// missing is an error with no message, row or event.
Method TestSummaryMessage()
{
	Set session = ..Session("summary")
	Set parts = [{"key": "summary.title", "slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "production": "Orders"}}, {"key": "summary.cause", "slots": {"cause": "The partner sent <b>x</b> and *y* in the date."}}, {"key": "summary.evidence", "slots": {"evidence": "OrderDate was <i>16/10/2026</i> and _z_"}}, {"key": "summary.sampleError", "slots": {"error": "Field <script>alert(1)</script> was not a date."}}, {"key": "summary.messages", "slots": {"failed": 50, "resent": 50, "completed": 50, "failedAgain": 0, "skipped": 0}}]
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "closed", "ClosedAt": (##class(OcuTalon.Data.Time).NowUtc()), "Summary": ({"parts": (parts), "lines": []}.%ToJSON())})
	Set ..Refs = ..Refs_","_incident
	Set expected = "Incident summary: 50 orders failed in Orders."
		_$Char(10)_"Cause: The partner sent <b>x</b> and *y* in the date."
		_$Char(10)_"Evidence: OrderDate was <i>16/10/2026</i> and _z_."
		_$Char(10)_"Sample error: Field <script>alert(1)</script> was not a date."
		_$Char(10)_"Messages: 50 failed, 50 resent, 50 completed, 0 failed again, 0 skipped."
	Set notification = ..Notification(session, "summary", "summary.title", {})
	Set notification.IncidentRef = incident
	Set notification.DecisionRef = "ZzSummaryDecision"
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the summary is delivered")
	Do $$$AssertEquals(..PhoneCount(session), 1, "one phone message")
	Set message = ..Newest(session)
	If '$IsObject(message) Do $$$AssertTrue(0, "the message exists") Quit
	Do $$$AssertEquals(message.Text, expected, "its text is the stored summary's lines, with the markup characters as they are")
	Do $$$AssertEquals(message.Text, ##class(OcuTalon.Watch.Summary).Text(incident, "phone"), "and Watch.Summary.Text for the phone")
	Do $$$AssertEquals(message.Kind_"|"_message.Direction_"|"_message.ApprovalRef_"|"_message.DecisionRef_"|"_message.Answer, "phone|out|||", "a phone message out, with no request, no notice and no answer")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 Do $$$AssertEquals(deliveries.GetAt(1).Channel_"|"_deliveries.GetAt(1).ChannelMessageId_"|"_deliveries.GetAt(1).Kind_"|"_deliveries.GetAt(1).ApprovalRef_"|"_deliveries.GetAt(1).Text, "phone|"_message.Ref_"|summary||", "of the kind summary, naming the message, with no approval and no text")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.text_"|"_events.%Get(0).payload.approvalRef, message.Ref_"|"_expected_"|", "for the message, with no approval Ref")
	Set bare = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "closed"})
	Set ..Refs = ..Refs_","_bare
	Set missing = ..Notification(session, "summary", "summary.title", {})
	Set missing.IncidentRef = bare
	Do $$$AssertStatusNotOK(..Out().OnNotification(missing, .response), "an incident with no summary is an error")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)_"|"_..Phones(session).%Size(), "1|1|1", "with no more message, row or event")
}

/// AC 14 (QA), the Simulated phone: an incident whose rows hold markup is summarized by Watch.Summary.Build (Test.Watch.Summary.Built), and the message that SimPhoneOut
/// records shows the cause and the sample error as they came: the markup literally, the sample error cut to an incident notice's length, one line each, with no button.
Method TestSummaryBuiltMessage()
{
	Set session = ..Session("built")
	Set incident = ##class(OcuTalon.Test.Watch.Summary).Built(session)
	Set ..Refs = ..Refs_","_incident
	Set notification = ..Notification(session, "summary", "summary.title", {})
	Set notification.IncidentRef = incident
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the built summary is delivered")
	Set message = ..Newest(session)
	Do $$$AssertTrue($IsObject(message), "it is a phone message")
	If '$IsObject(message) Quit
	Set cut = ##class(OcuTalon.Test.Watch.Summary).CutLine()
	Do $$$AssertTrue($Length(cut) '> $Parameter("OcuTalon.Watch.ErrorText", "SUMMARYMAX"), "the cut is no longer than a notice's error summary")
	Do $$$AssertTrue(message.Text [ ($Char(10)_"Cause: The partner sent <b>x</b> and *y*."_$Char(10)), "the cause shows its markup literally")
	Do $$$AssertTrue(message.Text [ ($Char(10)_"Sample error: "_cut_$Char(10)), "and the sample error is the cut, with its markup: "_cut)
	Do $$$AssertTrue(message.Text '[ ##class(OcuTalon.Test.Watch.Summary).#LONGMARKUP, "the whole sample error is not in the message")
	Do $$$AssertEquals(message.ApprovalRef, "", "and the message has no request, so no button")
}

/// A tell-now message keeps the notification's DecisionRef (the notice's Ref, which the page's Got it names) and its payload carries it as decisionRef.
/// A reminder, an incident, a result and a digest give a message none, whatever DecisionRef they carry.
Method TestTellNowKeepsDecisionRef()
{
	Set session = ..Session("keepref")
	Set decision = ..NewRef()
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz notice", "reason": "zz reason."})
	Set notification.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the tell-now notification is delivered")
	Set message = ..Newest(session)
	If '$IsObject(message) Do $$$AssertTrue(0, "the message exists") Quit
	Do $$$AssertEquals(message.DecisionRef_"|"_message.ApprovalRef, decision_"|", "the message keeps the DecisionRef and no request")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.decisionRef, decision, "its payload carries decisionRef")
	Set quiet = ..Session("keepnone")
	Set reminder = ..Notification(quiet, "reminder", "reminder.due", {"text": "stretch", "dueAt": "2030-01-01T12:00:00Z"})
	Set reminder.DecisionRef = decision
	Set digest = ..Notification(quiet, "digest", "digest.cost", {"parts": [{"key": "digest.greetingMorning", "slots": {}}], "lines": [], "rows": []})
	Set digest.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(reminder, .response), "a reminder with a DecisionRef is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(digest, .response), "and so is a digest")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(quiet, 10)
	Do $$$AssertEquals(rows.Count(), 2, "two messages")
	For i = 1:1:rows.Count() Do $$$AssertEquals(..Message(rows.GetAt(i).Ref).DecisionRef, "", "message "_i_" has no DecisionRef")
}

/// A tell-now Notification whose DecisionRef names an act Decision of the session (OutcomeRouter sends act items as tell-now notices) is a message
/// with no DecisionRef, so the page shows no Got it, which SessionOps would refuse; the session's own tell-now Decision keeps it.
Method TestActMessageHasNoGotIt()
{
	For outcome = "act", "tellnow" {
		Set session = ..Session("ref"_outcome)
		Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": (outcome)})
		Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": ("zz "_outcome), "reason": "zz reason."})
		Set notification.DecisionRef = decision
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the "_outcome_" notice is delivered")
		Set message = ..Newest(session)
		If '$IsObject(message) Do $$$AssertTrue(0, "the "_outcome_" message exists") Continue
		Do $$$AssertEquals(message.DecisionRef, $Select(outcome = "act": "", 1: decision), "the "_outcome_" message's DecisionRef")
		Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(message).DecisionRef, message.DecisionRef, "and its payload's decisionRef")
	}
}

/// A handled Notification for a tell-now message sets its Answer to the rendered handled.marked line (the phone render, with the time that Handled.Marked
/// gives), in place: the Ref, Text and DecisionRef stay, one more phone event carries the answer, and the Delivery row of the kind handled names the message.
Method TestHandledEditsInPlace()
{
	Set session = ..Session("handled")
	Set decision = ..NewRef()
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz notice", "reason": "zz reason."})
	Set notification.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the tell-now notification is delivered")
	Set before = ..Newest(session)
	Set ref = before.Ref, text = before.Text
	Kill before
	Set marked = ..Mark(session, decision)
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "the handled notification is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (marked)}, "phone")
	Do $$$AssertTrue($Extract(expected, 1, 21) = "Marked as handled at ", "the line: "_expected)
	Set message = ..Message(ref)
	Do $$$AssertEquals(message.Answer, expected, "the Answer is the rendered line")
	Do $$$AssertEquals(message.Text_"|"_message.DecisionRef_"|"_..PhoneCount(session), text_"|"_decision_"|1", "the Text and DecisionRef stay, and there is still one message")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 2, "two phone events")
	If events.%Size() = 2 {
		Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.answer_"|"_events.%Get(1).payload.decisionRef, ref_"|"_expected_"|"_decision, "the second is for the same message, with the answer")
		Do $$$AssertEquals(events.%Get(0).payload.answer, "", "the first had none")
	}
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 2, "two Delivery rows")
	If deliveries.Count() = 2 {
		Set delivery = deliveries.GetAt(2)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.DecisionRef_"|"_delivery.Text, "phone|"_ref_"|handled|"_decision_"|", "the second names the message and the handled kind")
	}
}

/// A message that has an Answer already keeps it: a second press, or an answer that came first, records the Delivery row (the message's Ref as ChannelMessageId)
/// only, with no edit and no event.
Method TestHandledFirstAnswerStays()
{
	Set session = ..Session("first")
	Set decision = ..NewRef()
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz notice", "reason": "zz reason."})
	Set notification.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the tell-now notification is delivered")
	Set message = ..Newest(session)
	Set ref = message.Ref
	Set message.Answer = "zz an earlier answer"
	Do $$$AssertStatusOK(message.%Save(), "the message already has an answer")
	Kill message
	Do ..Mark(session, decision)
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "the handled notification is delivered")
	Do $$$AssertEquals(..Message(ref).Answer, "zz an earlier answer", "the first answer stays")
	Do $$$AssertEquals(..Phones(session).%Size(), 1, "with no new event")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 2, "and its Delivery row")
	If deliveries.Count() = 2 Do $$$AssertEquals(deliveries.GetAt(2).ChannelMessageId_"|"_deliveries.GetAt(2).Kind, ref_"|handled", "which names the message")
}

/// With no phone message for the DecisionRef, or a notice that is not marked, a handled notification records its Delivery row only (ChannelMessageId empty):
/// no edit, no message and no event.
Method TestHandledNoMessageRecordsOnly()
{
	Set session = ..Session("nomessage")
	Set decision = ..NewRef()
	Do ..Mark(session, decision)
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "a handled notification with no message is delivered")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_..Phones(session).%Size(), "0|0", "no message and no event")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 Do $$$AssertEquals(deliveries.GetAt(1).Channel_"|"_deliveries.GetAt(1).Kind_"|"_deliveries.GetAt(1).DecisionRef_"|"_deliveries.GetAt(1).ChannelMessageId, "phone|handled|"_decision_"|", "of the kind handled, with the DecisionRef and no message id")
	Set open = ..Session("unmarked")
	Set notice = ..NewRef()
	Set notification = ..Notification(open, "tellnow", "notice.tellNow", {"whatHappened": "zz notice", "reason": "zz reason."})
	Set notification.DecisionRef = notice
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "a tell-now notification is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(open, notice), .response), "and a handled one, though the notice is not marked")
	Do $$$AssertEquals(..Newest(open).Answer, "", "the message is not edited")
	Do $$$AssertEquals(..Phones(open).%Size(), 1, "and there is no new event")
}

/// Another session's handled notification never edits the owner's message, not even through a Delivery row of its own that names that message.
Method TestHandledNeverEditsAnotherSession()
{
	Set owner = ..Session("handledowner")
	Set other = ..Session("handledother")
	Set decision = ..NewRef()
	Set notification = ..Notification(owner, "tellnow", "notice.tellNow", {"whatHappened": "zz notice", "reason": "zz reason."})
	Set notification.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the owner's message is delivered")
	Set ref = ..Newest(owner).Ref
	Do ..Mark(owner, decision)
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(other, decision), .response), "the other session's handled notification is delivered")
	Do $$$AssertEquals(..Message(ref).Answer, "", "the owner's message is unchanged")
	Do $$$AssertEquals(..Phones(owner).%Size()_"|"_..Phones(other).%Size(), "1|0", "with no new event")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(other, "phone", ref, "", "tellnow", "", decision), "a Delivery row of the other session names the owner's message")
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByRef(decision, "phone", other), ref, "the other session's lookup finds the owner's message")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(other, decision), .response), "and the notification is delivered again")
	Do $$$AssertEquals(..Message(ref).Answer, "", "the owner's message is still unchanged")
	Do $$$AssertEquals(..Phones(owner).%Size()_"|"_..Phones(other).%Size(), "1|0", "with no new event")
}

/// U-313: a message written before DecisionRef existed has the column empty. Its payload reads decisionRef as empty and exports, the phone lists it, and a
/// handled notification for a Delivery row that names it records its row only: the message is not edited.
Method TestOlderMessageRenders()
{
	Set session = ..Session("older")
	Set message = ##class(OcuTalon.Data.SimMessage).%New()
	Set message.Ref = ..NewRef()
	Set message.SessionRef = session
	Set message.Kind = "phone"
	Set message.Direction = "out"
	Set message.Text = "zz an older notice"
	Set message.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(message.%Save(), "a message is written without a DecisionRef")
	Do $$$AssertEquals(message.DecisionRef, "", "its DecisionRef is empty")
	Set listed = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
	Do $$$AssertEquals(listed.Count(), 1, "the phone lists it")
	Set payload = ##class(OcuTalon.Live.Payload.Phone).FromRow(message)
	Do $$$AssertEquals(payload.DecisionRef_"|"_payload.Text, "|zz an older notice", "its payload has no decisionRef")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "and exports")
	Set decision = ..NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "phone", message.Ref, "", "tellnow", "", decision), "a Delivery row names the message")
	Do ..Mark(session, decision)
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "a handled notification is delivered")
	Do $$$AssertEquals(..Message(message.Ref).Answer, "", "the message is not edited")
	Do $$$AssertEquals(..Phones(session).%Size(), 0, "and there is no event")
}

/// A reminder (reminder.due) is a phone message with the rendered text, and its phone Delivery row has no text and no due time.
Method TestReminder()
{
	Set session = ..Session("reminder")
	Set slots = {"text": "stretch", "dueAt": "2030-01-01T12:00:00Z"}
	Do $$$AssertStatusOK(..Out().OnNotification(..Notification(session, "reminder", "reminder.due", slots), .response), "the reminder is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.due", slots.%ToJSON(), "telegram", "", 0)
	Do $$$AssertEquals(expected, "Reminder: stretch.", "the telegram render")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("reminder.due", slots.%ToJSON(), "phone", "", 0), expected, "the phone render is the same")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "one phone message")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Text, expected, "with the rendered text")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 Do $$$AssertEquals(deliveries.GetAt(1).Channel_"|"_deliveries.GetAt(1).Kind_"|"_deliveries.GetAt(1).Text_"|"_deliveries.GetAt(1).DueAt, "phone|reminder||", "for the phone, with the kind, no text and no due time")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.text, expected, "with the text")
}

/// The phone shows the telegram wording, never the web page's (AD-32): for a key whose entry words the web differently
/// (answered.approved ends with a full stop for the phone and Telegram only), the message and its event carry the text of the
/// telegram render, which is not the web render.
Method TestTextIsTheTelegramWording()
{
	Set session = ..Session("wording")
	Set slots = {"channel": "telegram", "time": "2030-01-01T12:00:00Z"}
	Set telegram = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", slots.%ToJSON(), "telegram", "", 0)
	Set web = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", slots.%ToJSON(), "web", "", 0)
	Do $$$AssertTrue((telegram '= "") && (telegram '= web), "the key words the phone and the web differently: '"_telegram_"' and '"_web_"'")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", slots.%ToJSON(), "phone", "", 0), telegram, "and the phone render is the telegram render")
	Do $$$AssertStatusOK(..Out().OnNotification(..Notification(session, "tellnow", "answered.approved", slots), .response), "the notification is delivered")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "one phone message")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Text, telegram, "with the telegram wording")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.text, telegram, "and so has its event")
}

/// The time in a late reminder's text comes from Render: on the online demo it ends with " ET", on a local install it has no
/// suffix, and the message keeps the text as it was shown. The time is a fixed date of 2030, so that the date form and not the
/// clock of the day is rendered.
Method TestOnlineDemoTimesNameTheZone()
{
	Set session = ..Session("online")
	Set slots = {"text": "stretch", "time": "2030-01-01T12:00:00Z", "dueAt": "2030-01-01T12:00:00Z"}
	Do $$$AssertStatusOK(..Out().OnNotification(..Notification(session, "reminder", "reminder.late", slots), .response), "a late reminder is delivered on a local install")
	Set local = ..Newest(session).Text
	Do $$$AssertTrue(local ? 1"Reminder (late; it was due on Jan "1(1"1",1"2")1", 2030 at "2N1":"2N1"): stretch.", "a local install shows no zone name: "_local)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set sc = ..Out().OnNotification(..Notification(session, "reminder", "reminder.late", slots), .response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertStatusOK(sc, "and on the online demo")
	Set row = ..Newest(session)
	Do $$$AssertTrue(row.Text ? 1"Reminder (late; it was due on Jan "1(1"1",1"2")1", 2030 at "2N1":"2N1" ET): stretch.", "the online demo's time is followed by ET: "_row.Text)
	Do $$$AssertEquals($Piece(row.Text, " ET)", 1), $Piece(local, "):", 1), "and is the same time as the local install's, with the zone name added")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 2, "two events")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.text, row.Text, "the online demo's event carries the text of its message")
	Do $$$AssertEquals(..Newest(session).Text, row.Text, "and the message keeps that text after the setting is off again")
}

/// A result notification (kind result, result.allThrough, ApprovalRef of the request and IncidentRef) is one new SimMessage with the
/// phone render of the key and the slots, and an empty ApprovalRef; its phone Delivery row and one phone event. The request's earlier
/// message is not edited: it keeps its Ref, Text, ApprovalRef and Answer. With a count of one the text is "The order went through.".
Method TestResultIsAMessage()
{
	Set session = ..Session("result")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set approval = ..NewRef(), incident = ..NewRef()
	Set request = ..Notification(session, "incident", "incident.withFix", ..IncidentSlots(now))
	Set request.ApprovalRef = approval
	Set request.IncidentRef = incident
	Do $$$AssertStatusOK(..Out().OnNotification(request, .response), "the request's notice is delivered")
	Set answered = ..Notification(session, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set answered.ApprovalRef = approval
	Set answered.IncidentRef = incident
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "and answered")
	Set first = ..Newest(session)
	Set firstRef = first.Ref, firstText = first.Text, firstAnswer = first.Answer
	Do $$$AssertTrue(firstAnswer '= "", "the request's message has its answer line")
	Set slots = {"count": 50, "itemNoun": {"one": "order", "other": "orders"}}
	Set result = ..Notification(session, "result", "result.allThrough", slots)
	Set result.ApprovalRef = approval
	Set result.IncidentRef = incident
	Do $$$AssertStatusOK(..Out().OnNotification(result, .response), "the result is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt("result.allThrough", slots.%ToJSON(), "phone", now, 0)
	Do $$$AssertEquals(expected, "All 50 orders went through.", "the phone text")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 2, "two messages: the request's and the result's")
	Set newest = ..Newest(session)
	Do $$$AssertTrue(newest.Ref '= firstRef, "the result is a new message")
	Do $$$AssertEquals(newest.Text, expected, "with the phone render as its text")
	Do $$$AssertEquals(newest.ApprovalRef_"|"_newest.Answer, "|", "no ApprovalRef and no Answer, so no buttons")
	Set earlier = ..Message(firstRef)
	Do $$$AssertEquals(earlier.Text_"|"_earlier.ApprovalRef_"|"_earlier.Answer, firstText_"|"_approval_"|"_firstAnswer, "the request's message is not edited")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 3, "three Delivery rows")
	If deliveries.Count() = 3 {
		Set delivery = deliveries.GetAt(3)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.ApprovalRef_"|"_delivery.Text, "phone|"_newest.Ref_"|result|"_approval_"|", "the result's: channel, the message's Ref, kind and request, no text")
	}
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 3, "three phone events: the notice, its answer and the result")
	If events.%Size() = 3 {
		Set payload = events.%Get(2).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.approvalRef_"|"_payload.answer_"|"_payload.text, newest.Ref_"|||"_expected, "the last carries the result's ref and text, with no approvalRef or answer")
	}
	Set one = ..Notification(session, "result", "result.allThrough", {"count": 1, "itemNoun": {"one": "order", "other": "orders"}})
	Set one.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(one, .response), "a result of one is delivered")
	Do $$$AssertEquals(..Newest(session).Text, ##class(OcuTalon.Msg.Catalog).RenderAt("result.allThrough", {"count": 1, "itemNoun": {"one": "order", "other": "orders"}}.%ToJSON(), "phone", now, 0), "with the count-of-one form")
	Do $$$AssertEquals(..Newest(session).Text, "The order went through.", "which is the order went through")
}

/// The fallback and no-fix notices (kind incident, no ApprovalRef) are one message each, with the phone render and an empty ApprovalRef;
/// the two groups, one of them dated, are in the text.
Method TestFallbackAndNoFixWording()
{
	Set session = ..Session("notices")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set old = "2020-01-02T10:15:00Z"
	Set keys = $ListBuild("incident.fallback", "incident.noFix", "incident.noFixUnknown")
	Set position = 0
	While $ListNext(keys, position, key) {
		Set slots = ..FallbackSlots(now)
		Set slots.count = 9
		Do slots.groups.%Push({"itemName": "OrdersToWarehouse", "count": 2, "errorSummary": "The warehouse refused the order", "firstAt": (old)})
		If key = "incident.noFix" Set slots.cause = "Data format change"
		If key '= "incident.fallback" Do slots.%Remove("fallbackReason")
		If key = "incident.noFixUnknown" Do slots.%Remove("cause")
		Set before = ..PhoneCount(session)
		Set notification = ..Notification(session, "incident", key, slots)
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), key_" is delivered")
		Do $$$AssertEquals(..PhoneCount(session), before + 1, key_": one message")
		Set message = ..Newest(session)
		Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), "phone", now, 0)
		Do $$$AssertEquals(message.Text, expected, key_": the phone render")
		Do $$$AssertEquals(message.ApprovalRef, "", key_": no ApprovalRef, so no buttons")
		Do $$$AssertTrue(message.Text [ "OrdersToWarehouse", key_": it lists the groups")
	}
	Do $$$AssertEquals(..Phones(session).%Size(), 3, "three events")
}

/// A result whose key can't be rendered is an error with no message, no Delivery row and no event.
Method TestResultRenderError()
{
	Set session = ..Session("resulterror")
	Set notification = ..Notification(session, "result", "result.zzNoSuchKey", {"count": 5})
	Set notification.ApprovalRef = ..NewRef()
	Do $$$AssertStatusNotOK(..Out().OnNotification(notification, .response), "an unknown key is an error")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)_"|"_..Phones(session).%Size(), "0|0|0", "with no message, row or event")
}

/// Any other kind records its phone Delivery row only: the kind, the DecisionRef and the ApprovalRef, with no text and no
/// ChannelMessageId, no SimMessage and no event; the text is not rendered (its key is unknown). An incident notice is not one
/// of them: with a tell-now key and an ApprovalRef-less notification it is a message with no ApprovalRef.
Method TestOtherKindsRecordOnly()
{
	Set session = ..Session("other")
	Set kinds = $ListFromString("fallback,allowance,pairing,status")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set notification = ..Notification(session, kind, "zz.notRendered", {"zz": "slot"})
		Set notification.ApprovalRef = "ZzApproval"_kind
		Set notification.DecisionRef = "ZzDecision"_kind
		Set before = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), kind_": the notification is delivered")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), before + 1, kind_": one row is recorded")
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		Set row = rows.GetAt(rows.Count())
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ApprovalRef_"|"_row.DecisionRef, "phone|"_kind_"|ZzApproval"_kind_"|ZzDecision"_kind, kind_": its channel, kind, approval and decision")
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId_"|"_row.DueAt_"|"_row.FallbackReason, "|||", kind_": no text, no message id, no due time and no reason")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "none of them makes a phone message")
	Do $$$AssertEquals(..Phones(session).%Size(), 0, "and none publishes an event")
	Set before = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)
	Do $$$AssertStatusOK(..Out().OnNotification(..Notification(session, "incident", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."}), .response), "an incident whose text renders is delivered")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), before + 1, "and records its row")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
	Do $$$AssertEquals(rows.Count(), 1, "and makes one phone message")
	If rows.Count() = 1 Do $$$AssertEquals(..Message(rows.GetAt(1).Ref).ApprovalRef, "", "with no ApprovalRef")
	Do $$$AssertEquals(..Phones(session).%Size(), 1, "and one event")
}

/// An incident notice with an ApprovalRef (incident.withFix) is one SimMessage that keeps the ApprovalRef and has no Answer, with
/// the phone render as its text; one phone Delivery row (kind incident, the ApprovalRef, the message's Ref as ChannelMessageId, no
/// text); and one phone event whose payload carries the approvalRef and no answer. A render error is an error with no row and no
/// event.
Method TestIncidentNoticeAsksForItsRequest()
{
	Set session = ..Session("incident")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set slots = ..IncidentSlots(now)
	Set approval = ..NewRef()
	Set notification = ..Notification(session, "incident", "incident.withFix", slots)
	Set notification.ApprovalRef = approval
	Set notification.IncidentRef = ..NewRef()
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the incident notice is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.withFix", slots.%ToJSON(), "phone", now, 0)
	Do $$$AssertTrue(expected [ "Approve?", "the phone text asks Approve?: "_expected)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "one phone message")
	If rows.Count() '= 1 Quit
	Set message = ..Message(rows.GetAt(1).Ref)
	Do $$$AssertEquals(message.Text, expected, "with the phone render as its text")
	Do $$$AssertEquals(message.ApprovalRef_"|"_message.Answer, approval_"|", "it keeps the ApprovalRef and has no Answer")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.ApprovalRef_"|"_delivery.Text, "phone|"_message.Ref_"|incident|"_approval_"|", "its channel, the message's Ref, the kind and the request, with no text")
	}
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 1, "one phone event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.approvalRef_"|"_payload.answer_"|"_payload.text, message.Ref_"|"_approval_"||"_expected, "its ref, approvalRef and text, and an empty answer")
	}
	Set broken = ..Notification(session, "incident", "incident.withFix", {})
	Set broken.ApprovalRef = ..NewRef()
	Do $$$AssertStatusNotOK(..Out().OnNotification(broken, .response), "a notice that cannot be rendered is an error")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)_"|"_..Phones(session).%Size(), "1|1|1", "and adds no message, row or event")
}

/// A later request (kind approval, incident.laterRequest) is a second message with its own ApprovalRef, and the first keeps its own.
Method TestLaterRequestHasItsOwnButtons()
{
	Set session = ..Session("later")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set slots = ..IncidentSlots(now)
	Set first = ..NewRef(), second = ..NewRef()
	Set one = ..Notification(session, "incident", "incident.withFix", slots)
	Set one.ApprovalRef = first
	Set two = ..Notification(session, "approval", "incident.laterRequest", slots)
	Set two.ApprovalRef = second
	Do $$$AssertStatusOK(..Out().OnNotification(one, .response), "the incident notice is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(two, .response), "and so is the later request")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 2, "two messages")
	If rows.Count() '= 2 Quit
	Set refs = ""
	For i = 1:1:2 Set refs = refs_$Select(refs = "": "", 1: ",")_..Message(rows.GetAt(i).Ref).ApprovalRef
	Do $$$AssertTrue(($ListFind($ListFromString(refs), first) > 0) && ($ListFind($ListFromString(refs), second) > 0), "each keeps its own request: "_refs)
	Set later = ""
	For i = 1:1:2 {
		If ..Message(rows.GetAt(i).Ref).ApprovalRef = second Set later = ..Message(rows.GetAt(i).Ref)
	}
	Do $$$AssertEquals(later.Text, ##class(OcuTalon.Msg.Catalog).RenderAt("incident.laterRequest", slots.%ToJSON(), "phone", now, 0), "the later message has the later request's text")
	Do $$$AssertEquals(..Phones(session).%Size(), 2, "and each has its event")
}

/// Only the kinds incident and approval keep an ApprovalRef: a tellnow and a reminder that carry one give a message with none,
/// an answered one gives no message at all, and an incident with no request is a message with none.
Method TestOnlyRequestKindsCarryARequest()
{
	Set session = ..Session("kinds")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set tell = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
	Set tell.ApprovalRef = ..NewRef()
	Set reminder = ..Notification(session, "reminder", "reminder.due", {"text": "stretch", "dueAt": (now)})
	Set reminder.ApprovalRef = ..NewRef()
	Set answered = ..Notification(session, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set answered.ApprovalRef = ..NewRef()
	Set fallback = ..Notification(session, "incident", "incident.fallback", ..FallbackSlots(now))
	Do $$$AssertStatusOK(..Out().OnNotification(tell, .response), "the tell-now is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(reminder, .response), "the reminder is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "the answered notification is delivered")
	Do $$$AssertStatusOK(..Out().OnNotification(fallback, .response), "the incident with no request is delivered")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 3, "three messages: the answered notification made none")
	Set carried = ""
	For i = 1:1:rows.Count() Set carried = carried_..Message(rows.GetAt(i).Ref).ApprovalRef
	Do $$$AssertEquals(carried, "", "and none carries an ApprovalRef")
	Do $$$AssertEquals(..Phones(session).%Size(), 3, "three events")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 4, "and four Delivery rows")
}

/// The phone payload's decisionRef is set for a tell-now message only, from the session's own Delivery row; a reminder, an incident with a request and an approval
/// request give none, and a message Ref read for another session gives none.
Method TestDecisionRefOnlyForTellNow()
{
	Set session = ..Session("decref"), other = ..Session("decrefother")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set tell = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
	Set tell.DecisionRef = ..NewRef()
	Set reminder = ..Notification(session, "reminder", "reminder.due", {"text": "stretch", "dueAt": (now)})
	Set reminder.DecisionRef = ..NewRef()
	Set incident = ..Notification(session, "incident", "incident.withFix", ..IncidentSlots(now))
	Set incident.ApprovalRef = ..NewRef()
	Set incident.IncidentRef = ..NewRef()
	Set incident.DecisionRef = ..NewRef()
	Set approval = ..Notification(session, "approval", "toolCall.request", {"tool": "zz_send", "inputs": "{}"})
	Set approval.ApprovalRef = ..NewRef()
	Set approval.DecisionRef = ..NewRef()
	Do $$$AssertStatusOK(..Out().OnNotification(tell, .response), "the tell-now is delivered")
	Set tellRow = ..Newest(session)
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(tellRow).DecisionRef, tell.DecisionRef, "the tell-now message has the decisionRef")
	Set copy = ##class(OcuTalon.Data.SimMessage).%New()
	Set copy.Ref = tellRow.Ref
	Set copy.SessionRef = other
	Set copy.Text = tellRow.Text
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(copy).DecisionRef, "", "another session's tell-now Delivery row is never read")
	Set copy.SessionRef = session
	Set copy.Ref = $ZConvert(tellRow.Ref, "L")
	If copy.Ref = tellRow.Ref Set copy.Ref = $ZConvert(tellRow.Ref, "U")
	Do $$$AssertTrue(copy.Ref '= tellRow.Ref, "control: the Ref variant differs from the message's Ref")
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(copy).DecisionRef, "", "a Ref that differs only in case is not read")
	Do $$$AssertStatusOK(..Out().OnNotification(reminder, .response), "the reminder is delivered")
	Set reminderRow = ..Newest(session)
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(reminderRow).DecisionRef, "", "a reminder message has none")
	Do $$$AssertStatusOK(..Out().OnNotification(incident, .response), "the incident notice is delivered")
	Set incidentRow = ..Newest(session)
	Do $$$AssertTrue(incidentRow.ApprovalRef '= "", "control: the incident message keeps its request")
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(incidentRow).DecisionRef, "", "an incident message has none")
	Do $$$AssertStatusOK(..Out().OnNotification(approval, .response), "the approval request is delivered")
	Set approvalRow = ..Newest(session)
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(approvalRow).DecisionRef, "", "an approval message has none")
	Set stray = ##class(OcuTalon.Test.Data.Fixture).Delivery(session, {"ChannelMessageId": (approvalRow.Ref), "Channel": "phone", "Kind": "tellnow", "DecisionRef": (..NewRef())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_stray
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Phone).FromRow(approvalRow).DecisionRef, "", "and none even when a tell-now Delivery row names its Ref: the message names a request")
	Set json = ..Json(##class(OcuTalon.Live.Payload.Phone).FromRow(reminderRow))
	Do $$$AssertTrue(json '[ "decisionRef", "and an empty decisionRef is left out of the JSON")
}

/// An answered notification edits the delivered message in place: its Ref and Text stay (compared with the values read before the
/// edit, and the row read again after it), its Answer is the phone render of the notification, there is still one message, a second
/// phone event carries the answer, and a Delivery row (kind answered) names the message's Ref.
Method TestAnsweredEditsInPlace()
{
	Set session = ..Session("edit")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set slots = ..IncidentSlots(now)
	Set approval = ..NewRef()
	Set notice = ..Notification(session, "incident", "incident.withFix", slots)
	Set notice.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(notice, .response), "the incident notice is delivered")
	Set before = ..Newest(session)
	Set beforeRef = before.Ref, beforeText = before.Text
	Kill before
	Set answeredSlots = {"channel": "web", "time": (now)}
	Set answered = ..Notification(session, "answered", "answered.approved", answeredSlots)
	Set answered.ApprovalRef = approval
	Set answered.IncidentRef = ..NewRef()
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "the answered notification is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", answeredSlots.%ToJSON(), "phone", now, 0)
	Do $$$AssertTrue(expected ? 1"Approved from the web chat at "2N1":"2N1".", "the answer line: "_expected)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "still one message")
	If rows.Count() '= 1 Quit
	Set message = ..Message(rows.GetAt(1).Ref)
	Do $$$AssertEquals(message.Ref_"|"_message.Text_"|"_message.ApprovalRef, beforeRef_"|"_beforeText_"|"_approval, "with the same Ref, Text and request")
	Do $$$AssertEquals(message.Answer, expected, "and the answer line")
	Set events = ..Phones(session)
	Do $$$AssertEquals(events.%Size(), 2, "two events")
	If events.%Size() = 2 {
		Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.answer, message.Ref_"|"_expected, "the second is for the same message, with the answer")
		Do $$$AssertEquals(events.%Get(0).payload.answer, "", "the first had none")
	}
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 2, "two Delivery rows")
	If deliveries.Count() = 2 {
		Set delivery = deliveries.GetAt(2)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.ApprovalRef_"|"_delivery.Text, "phone|"_message.Ref_"|answered|"_approval_"|", "the second names the message and the answered kind")
	}
	Set rejected = {"channel": "telegram", "time": (now)}
	Set again = ..Notification(session, "answered", "answered.rejected", rejected)
	Set again.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(again, .response), "a later answered notification is delivered")
	Do $$$AssertEquals(..Message(message.Ref).Answer, expected, "and the first answer stays")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_..Phones(session).%Size(), "1|2", "still one message and no new event")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 3, "with its Delivery row")
	If deliveries.Count() = 3 Do $$$AssertEquals(deliveries.GetAt(3).ChannelMessageId_"|"_deliveries.GetAt(3).Kind, message.Ref_"|answered", "which names the message")
}

/// A result message is newer than the request's message and shares its ApprovalRef in the Delivery rows, so FindByApproval gives the
/// result message. An answered notification for the request then edits neither message: both keep their Answer (empty), no event is
/// published, and one answered Delivery row is recorded with an empty ChannelMessageId.
Method TestAnsweredNeverEditsAResult()
{
	Set session = ..Session("noresultedit")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set approval = ..NewRef()
	Set request = ..Notification(session, "approval", "toolCall.request", {"tool": "zz_send", "inputs": "{}"})
	Set request.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(request, .response), "the request is delivered")
	Set requestMessage = ..Newest(session)
	Set requestRef = requestMessage.Ref, requestText = requestMessage.Text
	Kill requestMessage
	Set result = ..Notification(session, "result", "toolCall.done", {"tool": "zz_send", "time": (now)})
	Set result.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(result, .response), "the result is delivered after it")
	Set resultMessage = ..Newest(session)
	Set resultRef = resultMessage.Ref, resultText = resultMessage.Text
	Kill resultMessage
	Do $$$AssertTrue(resultRef '= requestRef, "the result is a message of its own")
	Do $$$AssertEquals(..Phones(session).%Size(), 2, "two events so far")

	Set answered = ..Notification(session, "answered", "answered.approved", {"channel": "phone", "time": (now)})
	Set answered.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "the answered notification is delivered")
	Set requestMessage = ..Message(requestRef)
	Set resultMessage = ..Message(resultRef)
	Do $$$AssertEquals(resultMessage.Answer_"|"_resultMessage.Text_"|"_resultMessage.ApprovalRef, "|"_resultText_"|", "the result message is unchanged: no answer, no request")
	Do $$$AssertEquals(requestMessage.Answer_"|"_requestMessage.Text_"|"_requestMessage.ApprovalRef, "|"_requestText_"|"_approval, "and so is the request's")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_..Phones(session).%Size(), "2|2", "no message and no event was added")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 3, "three Delivery rows")
	If deliveries.Count() = 3 {
		Set row = deliveries.GetAt(3)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ChannelMessageId_"|"_row.ApprovalRef, "phone|answered||"_approval, "the last is the answered row, naming no message")
	}
}

/// An answered notification for a request whose message was never delivered records its Delivery row only (ChannelMessageId
/// empty): no message is made or changed and no event is published. So does one with an empty key, also once the request's
/// message has been delivered: that message keeps its buttons (no Answer) and gets no event.
Method TestAnsweredWithNoMessageRecordsOnly()
{
	Set session = ..Session("nomessage")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set answered = ..Notification(session, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set answered.ApprovalRef = ..NewRef()
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "the notification is delivered")
	Do $$$AssertEquals(..PhoneCount(session)_"|"_..Phones(session).%Size(), "0|0", "no message and no event")
	Set notice = ..Notification(session, "incident", "incident.withFix", ..IncidentSlots(now))
	Set notice.ApprovalRef = answered.ApprovalRef
	Do $$$AssertStatusOK(..Out().OnNotification(notice, .response), "then the request's notice is delivered")
	Set empty = ..Notification(session, "answered", "", {})
	Set empty.ApprovalRef = answered.ApprovalRef
	Do $$$AssertStatusOK(..Out().OnNotification(empty, .response), "so is an answered notification with no key, although the message exists")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 3, "three Delivery rows")
	If deliveries.Count() = 3 {
		For i = 1, 3 {
			Set row = deliveries.GetAt(i)
			Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ChannelMessageId_"|"_row.ApprovalRef, "phone|answered||"_answered.ApprovalRef, "row "_i_": the kind and the request, no message id")
		}
	}
	Set message = ..Newest(session)
	Do $$$AssertEquals(..PhoneCount(session)_"|"_..Phones(session).%Size()_"|"_$Select($IsObject(message): message.Answer, 1: "none"), "1|1|", "only the notice's message and event, and the message has no answer")
}

/// An answered notification never edits another session's message: the other session's message for the same request keeps its
/// Answer, and the notifying session records its Delivery row only.
Method TestAnsweredNeverEditsAnotherSessionsMessage()
{
	Set owner = ..Session("owner")
	Set other = ..Session("notowner")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set approval = ..NewRef()
	Set notice = ..Notification(owner, "incident", "incident.withFix", ..IncidentSlots(now))
	Set notice.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(notice, .response), "the owner's message is delivered")
	Set answered = ..Notification(other, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set answered.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(answered, .response), "the other session's answered notification is delivered")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(owner, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "the owner has one message")
	If rows.Count() = 1 Do $$$AssertEquals(..Message(rows.GetAt(1).Ref).Answer, "", "which is unchanged")
	Do $$$AssertEquals(..Phones(owner).%Size(), 1, "with no new event")
	Do $$$AssertEquals(..PhoneCount(other)_"|"_..Phones(other).%Size(), "0|0", "the other session has no message and no event")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(other)
	Do $$$AssertEquals(deliveries.Count(), 1, "only its Delivery row")
	If deliveries.Count() = 1 Do $$$AssertEquals(deliveries.GetAt(1).ChannelMessageId, "", "with no message id")
	// A stray Delivery row of the other session that names the owner's message is not followed either.
	Set message = ..Message(##class(OcuTalon.Data.Ownership).RecentPhone(owner, 1).GetAt(1).Ref)
	Set stray = ..NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(other, "phone", message.Ref, stray, "incident"), "a Delivery row of the other session names the owner's message")
	Set crossed = ..Notification(other, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set crossed.ApprovalRef = stray
	Do $$$AssertEquals(##class(OcuTalon.Data.Delivery).FindByApproval(stray, "phone", other), message.Ref, "the other session's lookup finds the owner's message")
	Do $$$AssertStatusOK(..Out().OnNotification(crossed, .response), "the notification is delivered")
	Do $$$AssertEquals(..Message(message.Ref).Answer, "", "and the owner's message is still unchanged")
	Do $$$AssertEquals(..Phones(owner).%Size()_"|"_..Phones(other).%Size(), "1|0", "with no new event")
}

/// An answered notification whose text cannot be rendered, for a message that was delivered, is an error and changes nothing:
/// the message keeps its empty Answer, and there is no new event and no new Delivery row.
Method TestAnsweredRenderErrorChangesNothing()
{
	Set session = ..Session("brokenedit")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set approval = ..NewRef()
	Set notice = ..Notification(session, "incident", "incident.withFix", ..IncidentSlots(now))
	Set notice.ApprovalRef = approval
	Do $$$AssertStatusOK(..Out().OnNotification(notice, .response), "the incident notice is delivered")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)
	Set answered = ..Notification(session, "answered", "answered.approved", {"channel": "web"})
	Set answered.ApprovalRef = approval
	Do $$$AssertStatusNotOK(..Out().OnNotification(answered, .response), "an answered notification with a missing slot is an error")
	Set unknown = ..Notification(session, "answered", "zz.noSuchKey", {"zz": "slot"})
	Set unknown.ApprovalRef = approval
	Do $$$AssertStatusNotOK(..Out().OnNotification(unknown, .response), "so is one with an unknown key")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "still one message")
	If rows.Count() = 1 Do $$$AssertEquals(..Message(rows.GetAt(1).Ref).Answer, "", "with no answer")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), deliveries, "no Delivery row is added")
	Do $$$AssertEquals(..Phones(session).%Size(), 1, "and no event")
}

/// A message for an owner that is not a session (instance, eval, an empty Ref, a Ref with no Session row, the control owner of the
/// demo-switch test) records no row and publishes no event, for a card whose text renders and for a card kind with a slot set that
/// cannot be rendered too (the owner check comes first), and each logs one warning; the status is OK, so that the operation does not
/// retry. The instance stream is read from its Seq before the test.
Method TestNotASession()
{
	Set mark = ..LastLog()
	Set instanceSeq = ##class(OcuTalon.Live.Publish).LastSeq("instance")
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set owners = $ListBuild("instance", "eval", "", unknown, "Instance", "zzswitch")
	Set position = 0
	While $ListNext(owners, position, owner) {
		Set before = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner)
		Set warned = ..Warnings(mark)
		Set notification = ##class(OcuTalon.Msg.Notification).%New()
		Set notification.SessionRef = owner
		Set notification.Kind = "tellnow"
		Set notification.CatalogKey = "notice.tellNow"
		Set notification.Slots = "{}"
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "'"_owner_"': a card notification with unrenderable slots is dropped with an OK status")
		Set renders = ..Notification(owner, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
		Do $$$AssertStatusOK(..Out().OnNotification(renders, .response), "'"_owner_"': so is a card whose text renders")
		Set other = ..Notification(owner, "incident", "zz.notRendered", {"zz": "slot"})
		Do $$$AssertStatusOK(..Out().OnNotification(other, .response), "'"_owner_"': and an incident notification")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner), before, "'"_owner_"': no row is recorded")
		Do $$$AssertEquals(..Warnings(mark) - warned, 3, "'"_owner_"': one warning each")
		Do $$$AssertEquals(..PhoneCount(owner), 0, "'"_owner_"': and no phone message")
	}
	Set instancePhones = 0
	Set events = ##class(OcuTalon.Live.Event).Since("instance", instanceSeq, 1000)
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).type = "phone" Set instancePhones = instancePhones + 1
	}
	Do $$$AssertEquals(..Phones(unknown).%Size()_"|"_instancePhones, "0|0", "and no event is published")
	Do ..RemoveWarnings(mark)
}

/// A text that cannot be rendered is an error status with no message, no Delivery row and no event: an unknown key, a missing
/// slot, an empty text slot, a slot of the wrong type, an empty key and slots that are not JSON.
Method TestRenderError()
{
	Set session = ..Session("render")
	Set cases = $ListBuild($ListBuild("an unknown key", "zz.noSuchKey", "{""zz"":""slot""}"), $ListBuild("a missing slot", "notice.tellNow", "{""whatHappened"":""zz summary""}"), $ListBuild("an empty text slot", "notice.tellNow", "{""whatHappened"":"""",""reason"":""zz reason.""}"))
	Set cases = cases_$ListBuild($ListBuild("a slot of the wrong type", "reminder.due", "{""text"":5}"), $ListBuild("an empty key", "", "{}"), $ListBuild("slots that are not JSON", "notice.tellNow", "not json"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set notification = ##class(OcuTalon.Msg.Notification).%New()
		Set notification.SessionRef = session
		Set notification.Kind = $Select($List(case, 2) = "reminder.due": "reminder", 1: "tellnow")
		Set notification.CatalogKey = $List(case, 2)
		Set notification.Slots = $List(case, 3)
		Do $$$AssertStatusNotOK(..Out().OnNotification(notification, .response), $List(case, 1)_" is an error")
		Do $$$AssertEquals(..PhoneCount(session), 0, $List(case, 1)_": no message is recorded")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, $List(case, 1)_": no Delivery row")
		Do $$$AssertEquals(..Phones(session).%Size(), 0, $List(case, 1)_": and no event is published")
	}
}

/// The phone message and its Delivery row are saved together: when the Delivery row cannot be saved (an ApprovalRef longer than
/// the column allows), the status is an error and the message is not kept either, and no event is published.
Method TestSaveFailureKeepsNothing()
{
	Set session = ..Session("rollback")
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
	Set notification.ApprovalRef = $Translate($Justify("", 30), " ", "A")
	Do $$$AssertStatusNotOK(..Out().OnNotification(notification, .response), "a Delivery row that cannot be saved is an error")
	Do $$$AssertEquals(..PhoneCount(session), 0, "the phone message is not kept")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and there is no Delivery row")
	Do $$$AssertEquals(..Phones(session).%Size(), 0, "and no event is published")
	Do $$$AssertEquals($TLevel, 0, "and no transaction is left open")
}

/// A phone event that cannot be published (Publish refuses inside an open transaction) is logged as one warning, and both rows
/// stay; the delivery is still OK.
Method TestPublishFailure()
{
	Set session = ..Session("publish")
	Set mark = ..LastLog()
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
	TSTART
	Try {
		Set sc = ..Out().OnNotification(notification, .response)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	TCOMMIT
	Do $$$AssertStatusOK(sc, "the delivery is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 1, "the message is saved")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and so is its Delivery row")
	Do $$$AssertEquals(..Phones(session).%Size(), 0, "no event is published")
	Do $$$AssertEquals(..Warnings(mark, .text, "Announce", "SimPhoneOut could not publish"), 1, "one warning is logged")
	Do $$$AssertTrue(text [ "transaction", "and says why: "_text)
	Do ..RemoveWarnings(mark, "Announce", "SimPhoneOut could not publish")
}

/// In the running production with demo mode on, a Notification sent to Notify for a fixture session reaches both WebChatOut and
/// SimPhoneOut as the same message: the Ens.MessageHeaders from Notify to the two have the same body class
/// (OcuTalon.Msg.Notification), body id and session, both are completed with no error and neither has a response header; only
/// the target differs (AC3, the Visual Trace clause). The SimMessage is there within WAIT seconds of the send, with its one phone
/// Delivery row and its one phone event.
Method TestThroughNotify()
{
	If '##class(Ens.Director).IsProductionRunning(.name) {
		Do $$$AssertSkipped("No production runs in "_$Namespace_": this case runs in throwaways and CI only (Rule 21)")
		Quit
	}
	Do $$$AssertEquals(name, "OcuTalon.Production", "the production that runs")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on")
	Set session = ..Session("notify")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do ..Supers.%Push(trace)
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz Disk almost full", "reason": "you asked to hear about disk space"})
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	Do $$$AssertStatusOK(sc, "a business service host is made")
	If $$$ISERR(sc) Quit
	Set service.%SuperSession = trace
	Set end = $ZHorolog + ..#WAIT
	Do $$$AssertStatusOK(service.SendRequestAsync("Notify", notification), "the Notification is sent to Notify")
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
		If (rows.Count() > 0) || ($ZHorolog > end) Quit
		Hang 0.1
	}
	Do $$$AssertEquals(rows.Count(), 1, "the SimMessage is there within "_..#WAIT_" seconds")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Text, "zz Disk almost full"_$Char(10)_"Why now: you asked to hear about disk space", "with the rendered text")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "SimPhoneOut", 1, 20), "SimPhoneOut has handled the Notification")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", 1, 20), "WebChatOut has handled it")
	Set messageRef = $Select(rows.Count() = 1: rows.GetAt(1).Ref, 1: "(none)")
	Set phoneRows = "", deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:deliveries.Count() {
		If deliveries.GetAt(i).Channel = "phone" Set phoneRows = phoneRows_$Select(phoneRows = "": "", 1: ",")_deliveries.GetAt(i).ChannelMessageId
	}
	Do $$$AssertEquals(phoneRows, messageRef, "one phone Delivery row, for the message")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "phone", 1, ..#WAIT)
	Do $$$AssertEquals(events.%Size(), 1, "and one phone event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref, messageRef, "for the message")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set toWeb = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "WebChatOut")
	Set toPhone = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "SimPhoneOut")
	Do $$$AssertEquals(toWeb.%Size()_"|"_toPhone.%Size(), "1|1", "Notify sends one request to each")
	If (toWeb.%Size() = 1) && (toPhone.%Size() = 1) {
		Set web = toWeb.%Get(0), phone = toPhone.%Get(0)
		Do $$$AssertEquals(web.bodyClass_"|"_web.bodyId_"|"_web.sessionId, phone.bodyClass_"|"_phone.bodyId_"|"_phone.sessionId, "the same body class, body id and session")
		Do $$$AssertEquals(phone.bodyClass, "OcuTalon.Msg.Notification", "the body is a Notification")
		Do $$$AssertEquals(web.status_"|"_web.isError_"|"_phone.status_"|"_phone.isError, "9|0|9|0", "both are completed with no error")
		Do $$$AssertEquals(web.superSession_"|"_phone.superSession, trace_"|"_trace, "in the session's SuperSession")
	}
	Set responses = 0
	For i = 0:1:headers.%Size() - 1 {
		If (headers.%Get(i).type = 2) && ((headers.%Get(i).source = "WebChatOut") || (headers.%Get(i).source = "SimPhoneOut")) Set responses = responses + 1
	}
	Do $$$AssertEquals(responses, 0, "neither has a response header")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzphone"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the operation.
Method Out() As OcuTalon.Channel.SimPhone.Out [ Private ]
{
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the operation is made")
	Quit out
}

/// The Notification that GotIt sends: kind handled for the session, with the Decision's Ref, no catalog key and no slots.
Method HandledNotification(session As %String, decisionRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ..Notification(session, "handled", "", {})
	Set notification.DecisionRef = decisionRef
	Quit notification
}

/// Marks the notice as handled, as SessionOps does: one Handled row {the Ref, the session, now, phone}. Returns when.
Method Mark(session As %String, decisionRef As %String) As %String [ Private ]
{
	Set handled = ##class(OcuTalon.Data.Handled).%New()
	Set handled.Ref = decisionRef
	Set handled.SessionRef = session
	Set handled.Channel = "phone"
	Set handled.HandledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(handled.%Save(), "the notice is marked handled")
	Quit handled.HandledAt
}

/// A new Ref for an approval request or an incident.
Method NewRef() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ids).NewRef()
}

/// The slots of an incident.withFix and incident.laterRequest notice; every time is the clock, so that the render is the same
/// on any day.
Method IncidentSlots(now As %String) As %DynamicObject [ Private ]
{
	Quit {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": (now), "cause": "Data format change", "fixSummary": "repair the order date and resend 50 orders", "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16", "resendCount": 50}
}

/// The slots of an incident.fallback notice.
Method FallbackSlots(now As %String) As %DynamicObject [ Private ]
{
	Set slots = {"count": 7, "itemNoun": {"one": "order", "other": "orders"}, "time": (now), "fallbackReason": "empty"}
	Set groups = []
	Do groups.%Push({"itemName": "OrdersFromPartner", "count": 7, "errorSummary": "The order date was not in the expected format", "firstAt": (now)})
	Do slots.%Set("groups", groups)
	Quit slots
}

/// The SimMessage of the Ref, as the table holds it.
Method Message(ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Quit ##class(OcuTalon.Data.SimMessage).RefIndexOpen(ref)
}

/// A Notification of the kind with the catalog key and its slots (an object).
Method Notification(session As %String, kind As %String, key As %String, slots As %DynamicObject) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = kind
	Set notification.CatalogKey = key
	Set notification.Slots = slots.%ToJSON()
	Quit notification
}

/// The JSON text that the payload exports.
Method Json(payload As %RegisteredObject) As %String [ Private ]
{
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "the payload exports")
	Quit json
}

/// The phone events of the session's stream, in order.
Method Phones(session As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "phone")
}

/// The newest phone message of the session, as Ownership reads it.
Method Newest(session As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 1, .sc)
	Quit $Select(rows.Count() = 1: rows.GetAt(1), 1: "")
}

/// The number of SimMessage rows of the owner, whatever their kind (the test reads the table directly, as a test may).
Method PhoneCount(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of the newest row of the event log.
Method LastLog() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).LastLog()
}

/// The number of warnings after the row mark that the method of SimPhoneOut logged, with the text starting as given; text is the
/// newest one's. By default the warnings for a message dropped because its owner is not a session.
Method Warnings(mark As %Integer, Output text As %String, method As %String = "IsSession", start As %String = "SimPhoneOut dropped a message") As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, method, start)
}

/// Removes those warnings.
Method RemoveWarnings(mark As %Integer, method As %String = "IsSession", start As %String = "SimPhoneOut dropped a message") [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, method, start)
}

}
