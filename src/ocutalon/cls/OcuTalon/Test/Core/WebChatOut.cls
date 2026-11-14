/// Tests of WebChatOut (Story 2.7; AD-12, AD-14, AD-32, AD-33). Safe on a slot: no production runs there, so the tests call the
/// handlers on a shadow instance of OcuTalon.Channel.WebChat.Out, with fixture sessions from Test.Data.Fixture. The real
/// Interoperability path is the job of OcuTalon.Test.Core.RoutingProduction. Every text is written out here, never read from the
/// catalog.
///   - TestTellNowCard: a tell-now Notification becomes a Delivery row, the card, and one notification event whose payload is the
///     row's, with the text split from the Why now line and the decision embedded;
///   - TestFallbackCard, TestReminderCard: the fallback reason comes from the slot that the key declares as fallbackReason, and a
///     reminder keeps its due time from the slot dueAt;
///   - TestOnlineDemoTimesNameTheZone: the times in a card's text come from Render, with " ET" on the online demo, and the row keeps
///     that text;
///   - TestIncidentKindsRecordOnly: the incident kinds (INCIDENTKINDS) record their Delivery row, with no text and no event, because
///     the incident card is their web form;
///   - TestAllowanceCards (Story 16.9): the kind allowance is a card: the session allowance notice and the daily-cap message are
///     rendered for the web, with " ET" on the online demo, recorded with no fallback reason and published as one notification event;
///   - TestToolCallCards (Story 31.6): a tool call's request, result and held-call reason (the five Core.BridgeSink keys, kind approval or
///     result, with an ApprovalRef) are cards: rendered for the web, recorded with a ChannelMessageId and the ApprovalRef, published as
///     one notification event and in RecentNotices; a toolCall key with no ApprovalRef, the kind answered, a fix's request
///     (incident.laterRequest) and a fix's result (result.allThrough) record their Delivery row only;
///   - TestPartnerNotDraftedCard (Story 23.5; AC-NOTDRAFTED-WEB): result.partnerNotDrafted (kind result, no ApprovalRef) is a card of the web chat: rendered for the web, recorded with a ChannelMessageId, no ApprovalRef and
///     the kind result, published as one notification event and in RecentNotices; any other result with no ApprovalRef (result.allThrough, a tool call's) and a result.partnerSent with an ApprovalRef
///     that is not a tool call's keep their Delivery row only;
///   - TestPersonaCards (Story 40.6): the persona notices of Core.SettingsOps (approval.persona with kind approval, persona.applied and
///     persona.stale with kind result), with an ApprovalRef, are cards as a tool call's are; without an ApprovalRef, or with the kind
///     answered, they record their Delivery row only;
///   - TestDigestCard (Story 17.10): a digest Notification is a card: its text is the pieces of OcuTalon.Channel.DigestText rendered for the web, one on
///     each line (the parts up to the after-lines parts, the lines, then the rest; the lines last when no part is an after-lines part), recorded with the
///     kind digest, a new message id, the DecisionRef as sent, no due time and no reason, published as one notification event with the whole text and
///     an empty whyNow, and listed in RecentNotices; Slots with no parts or no lines, and a part or line with an unknown key, are an error with no row and
///     no event;
///   - TestDigestCard also (Story 18.4): the Slots' rows are kept on the row as CheckRows (the rows JSON, "[]" for an empty rows) and the payload
///     carries them as checks;
///   - TestHandledRepublishesTheCard (Story 18.4): a handled Notification publishes the tell-now card again, with its own ref and handledAt, and
///     records the bare Delivery row; a second one (the newest row is then the handled row) records the row only;
///   - TestSummaryCard (Story 23.6; AC 5, AC 14): a summary Notification is a card of kind summary whose text is the stored summary's lines, with the markup of the
///     cause, the evidence and the sample error left as it is; one event; another session gets no row; a missing summary records nothing;
///   - TestSummaryBuilt (QA; AC 14): the summary that Watch.Summary.Build makes of an incident whose cause, fix and sample error hold markup (the sample error longer than a notice's error summary)
///     is a web card whose text shows the markup as it came and the sample error cut to the notice's length;
///   - TestHandledWithNoCardRecordsOnly: with no tell-now card for the DecisionRef (none at all, or a digest) it records the bare row and no event;
///   - TestReloadShowsHandled: Notification.FromRow of the card's row carries handledAt once the notice is marked (tell-now only), and the checks;
///   - TestOlderDigestRowRenders (U-313): a digest row written without CheckRows reads as a card with no check rows, in RecentNotices and in the payload;
///   - TestOtherKindsRecordOnly: any other kind records its Delivery row, with no text and no event;
///   - TestReplyRecordsItsDeliveryOnly: a reply records its Delivery row for the web, with its DecisionRef and no event;
///   - TestRenderErrorRecordsNothing: a text that cannot be rendered is an error with no row and no event;
///   - TestNotASession: an owner that is not a session records nothing and logs a warning;
///   - TestPublishFailureKeepsTheRow: a notification event that cannot be published is logged and the row stays.
/// The public setting onlineDemo is off during the run and put back after it. The run's number is n from
/// ^OcuTalonTest("WebChatOut","n") (never reset).
Class OcuTalon.Test.Core.WebChatOut Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("WebChatOut", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Refs, ",") Do ##class(OcuTalon.Data.Handled).DropSession($Piece(..Refs, ",", i))
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// A tell-now Notification (notice.tellNow, the summary and the reason) records one card: channel web, a new Ref as the
/// ChannelMessageId, the kind, the whole rendered text, the DecisionRef, no fallback reason and no due time, even with a dueAt
/// slot (the due time is a reminder's). After the save one
/// notification event goes to the session's stream, with the payload FromRow makes: ref, kind, decisionRef, createdAt, text and
/// whyNow split at the last line, and the owner's decision embedded. Another session's stream and rows are untouched.
Method TestTellNowCard()
{
	Set session = ..Session("tellnow")
	Set other = ..Session("tellnowother")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": "tellnow", "Reasons": ("zz first."_$Char(10)_"zz second."), "Confidence": 0.9, "CostUSD": 0.0003})
	Set ..Refs = ..Refs_","_decision
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz Dana: Invoice", "reason": "zz first.", "dueAt": "2030-01-01T12:00:00Z"})
	Set notification.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the notification is delivered")
	Do $$$AssertEquals($IsObject($Get(response)), 0, "with no response")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "the session has one card")
	If rows.Count() '= 1 Quit
	Set row = rows.GetAt(1)
	Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.Kind_"|"_row.DecisionRef, session_"|web|tellnow|"_decision, "its Delivery row: the owner, the web, the kind and the DecisionRef")
	Do $$$AssertEquals(row.Text, "zz Dana: Invoice"_$Char(10)_"Why now: zz first.", "the whole rendered text")
	Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), "the ChannelMessageId is a new Ref: "_row.ChannelMessageId)
	Do $$$AssertEquals(row.DueAt_"|"_row.FallbackReason_"|"_row.ApprovalRef, "||", "with no due time, fallback reason or approval")
	Do $$$AssertEquals(row.RecordedAt, $Extract(row.RecordedAt, 1, 19)_"Z", "recorded to the second, in UTC")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event is published")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Set expected = ##class(%DynamicObject).%FromJSON(..Json(##class(OcuTalon.Live.Payload.Notification).FromRow(row)))
		Do $$$AssertEquals(payload.%ToJSON(), expected.%ToJSON(), "its payload is the one that FromRow makes of the row")
		Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.decisionRef_"|"_payload.createdAt, row.ChannelMessageId_"|tellnow|"_decision_"|"_row.RecordedAt, "ref, kind, decisionRef and createdAt")
		Do $$$AssertEquals(payload.text_"|"_payload.whyNow, "zz Dana: Invoice|Why now: zz first.", "the text without the Why now line, and the line")
		Do $$$AssertEquals(payload.decision.ref_"|"_payload.decision.reasons_"|"_payload.decision.confidence_"|"_payload.decision.costUSD, decision_"|zz first."_$Char(10)_"zz second.|.9|.0003", "and the owner's decision, with its cost")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(other, 10).Count(), 0, "another session has no card")
	Do $$$AssertEquals(..Notifications(other).%Size(), 0, "and no event")
}

/// A fallback tell now (notice.tellNowFallback) keeps the fallback reason, read from the slot that the catalog entry declares as
/// type fallbackReason, in the row and the payload, and has no decision when it has no DecisionRef. A code-written key (a
/// production state change) has no such slot, so the reason is empty.
Method TestFallbackCard()
{
	Set session = ..Session("fallback")
	Set notification = ..Notification(session, "tellnow", "notice.tellNowFallback", {"whatHappened": "zz Dana: Invoice", "reason": "refusal"})
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the fallback notification is delivered")
	Set row = ..Newest(session)
	Do $$$AssertEquals(row.Text, "zz Dana: Invoice"_$Char(10)_"Why now: the model declined to answer", "the text carries the words of the reason")
	Do $$$AssertEquals(row.FallbackReason_"|"_row.DecisionRef, "refusal|", "the row keeps the reason, and has no decision")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.fallbackReason_"|"_payload.whyNow_"|"_payload.text, "refusal|Why now: the model declined to answer|zz Dana: Invoice", "the payload keeps the reason and splits the text")
		Do $$$AssertEquals(payload.%IsDefined("decision"), 0, "and embeds no decision")
	}

	Set coded = ..Notification(session, "tellnow", "watch.productionStopped", {"production": "Orders", "time": "2026-10-16T18:12:00Z"})
	Do $$$AssertStatusOK(..Out().OnNotification(coded, .response), "a code-written notice is delivered")
	Set row = ..Newest(session)
	Do $$$AssertEquals(row.FallbackReason, "", "a key with no fallbackReason slot has no reason")
	Do $$$AssertEquals($Piece(row.Text, $Char(10), 2), "Why now: you asked me to watch the Orders production.", "and keeps its own two lines")
	Do $$$AssertEquals($Length(row.Text, $Char(10)), 2, "exactly two")
}

/// A reminder (reminder.due) keeps its due time from the slot dueAt, which the text does not declare; its text is whole in the
/// payload, with no whyNow. A late reminder (reminder.late) keeps the dueAt slot too.
Method TestReminderCard()
{
	Set session = ..Session("reminder")
	Set notification = ..Notification(session, "reminder", "reminder.due", {"text": "stretch", "dueAt": "2030-01-01T12:00:00Z"})
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the reminder is delivered")
	Set row = ..Newest(session)
	Do $$$AssertEquals(row.Kind_"|"_row.Text_"|"_row.DueAt_"|"_row.FallbackReason, "reminder|Reminder: stretch.|2030-01-01T12:00:00Z|", "the kind, the text, the due time and no reason")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.kind_"|"_payload.text_"|"_payload.dueAt, "reminder|Reminder: stretch.|2030-01-01T12:00:00Z", "the payload: the kind, the text and the due time")
		Do $$$AssertEquals(payload.whyNow, "", "with an empty whyNow")
	}
	Set late = ..Notification(session, "reminder", "reminder.late", {"text": "stretch", "time": "2030-01-01T12:00:00Z", "dueAt": "2030-01-01T12:00:00Z"})
	Do $$$AssertStatusOK(..Out().OnNotification(late, .response), "a late reminder is delivered")
	Set row = ..Newest(session)
	Do $$$AssertEquals($Extract(row.Text, 1, 27)_"|"_$Extract(row.Text, $Length(row.Text) - 10, *)_"|"_row.DueAt, "Reminder (late; it was due |): stretch.|2030-01-01T12:00:00Z", "its text (the time in the instance's zone) and due time")
	Set noDue = ..Notification(session, "reminder", "reminder.due", {"text": "no due slot"})
	Do $$$AssertStatusOK(..Out().OnNotification(noDue, .response), "a reminder with no dueAt slot is delivered")
	Do $$$AssertEquals(..Newest(session).DueAt, "", "with no due time")
}

/// The times inside a card's text are rendered through Msg.Catalog.Render (AD-18, AD-32): on the online demo they read in the
/// instance's zone with " ET" after them, and on a local install they have no zone name. The row keeps the text as it was shown,
/// so the zone name stays on a card after the demo switch goes off, and the live event carries the same text. The time is a
/// fixed date of 2030, so that the date form ("Jan 1, 2030 at 07:00") and not the clock of the day is rendered, and the
/// hour is matched as two digits whatever the zone of the process.
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
	Do $$$AssertEquals(..Rows(session), 2, "two cards")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 2, "two events")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.text, row.Text, "the online demo's event carries the text of its row")
	Do $$$AssertEquals(..Newest(session).Text, row.Text, "and the card keeps that text after the demo switch is off again")
}

/// The incident kinds (the parameter INCIDENTKINDS) record their Delivery row only: the kind, the DecisionRef and the ApprovalRef,
/// with no text, no ChannelMessageId and no event, and the row is not one of the chat's cards. The incident card carries the notice.
Method TestIncidentKindsRecordOnly()
{
	Do $$$AssertEquals(##class(OcuTalon.Channel.WebChat.Out).#INCIDENTKINDS, "incident,approval,answered,result", "the kinds whose web form is the incident card")
	Do ..AssertRecordOnly(..Session("incident"), $ListFromString(##class(OcuTalon.Channel.WebChat.Out).#INCIDENTKINDS), "the incident kinds")
}

/// A tool call's notices (Story 31.6) are cards of the web chat: each of the six keys of Core.BridgeSink (the sixth, mcp.replayToolChanged, is the card of an approved MCP call that was refused because its tool changed, DW-1232), sent with its kind
/// (approval for the two request keys, result for the others), an ApprovalRef and its slots (and a DecisionRef for the held-call
/// reason), is rendered for the web, recorded with a new ChannelMessageId, the ApprovalRef, the kind and the DecisionRef, published
/// as one notification event whose payload carries the approvalRef and the text, and listed in RecentNotices. These record their
/// Delivery row only, with no text, no message id and no event, and are not in RecentNotices: a toolCall.request with no
/// ApprovalRef, the kind answered with answered.approved and an ApprovalRef, a fix's request (kind approval, incident.laterRequest,
/// an ApprovalRef), a toolCall.done with no ApprovalRef, and a fix's result (kind result, result.allThrough, an ApprovalRef). The
/// times are the catalog's HH:MM on the local date, with the online demo off.
Method TestToolCallCards()
{
	Set session = ..Session("toolcall")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(now, now)
	Set inputs = [{"name": "to", "value": ("""ops""")}]
	Set why = "Why: zz_send counts as risky, so it runs only after an approval."
	Set cases = $ListBuild($ListBuild("approval", "toolCall.request", ({"tool": "zz_send", "inputs": (inputs)}).%ToJSON(), "Run zz_send"_$Char(10)_why_$Char(10)_"Inputs:"_$Char(10)_"to: ""ops"""_$Char(10)_"No dry run is available for this tool. Approving runs exactly this call once.", ""))
	Set cases = cases_$ListBuild($ListBuild("approval", "toolCall.requestOnServer", ({"tool": "zz_send", "server": "ops-mcp", "inputs": (inputs)}).%ToJSON(), "Run zz_send on ops-mcp"_$Char(10)_why_$Char(10)_"Inputs:"_$Char(10)_"to: ""ops"""_$Char(10)_"No dry run is available for this tool. Approving runs exactly this call once.", ""))
	Set cases = cases_$ListBuild($ListBuild("result", "toolCall.done", ({"tool": "zz_send", "time": (now)}).%ToJSON(), "zz_send ran once at "_clock_".", ""))
	Set cases = cases_$ListBuild($ListBuild("result", "toolCall.failed", ({"tool": "zz_send", "time": (now)}).%ToJSON(), "zz_send failed at "_clock_". I won't run it again without a new approval.", ""))
	Set cases = cases_$ListBuild($ListBuild("result", "toolCall.failedWithReason", ({"tool": "zz_send", "reason": "This request was held before an update and cannot be run again safely, so please ask again."}).%ToJSON(), "zz_send didn't run. This request was held before an update and cannot be run again safely, so please ask again.", "ZzToolDecision"))
	Set cases = cases_$ListBuild($ListBuild("result", "mcp.replayToolChanged", ({"tool": "zz_send", "server": "ops-mcp"}).%ToJSON(), "zz_send on ops-mcp didn't run: the tool changed after this request was made, so it needs a new approval. Nothing was changed.", ""))
	Set position = 0, n = 0
	While $ListNext(cases, position, case) {
		Set n = n + 1
		Set kind = $List(case, 1), key = $List(case, 2), expected = $List(case, 4), decisionRef = $List(case, 5)
		Set notification = ..Notification(session, kind, key, {}.%FromJSON($List(case, 3)))
		Set notification.ApprovalRef = "ZzToolApproval"_n
		Set notification.DecisionRef = decisionRef
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), key_": the notification is delivered")
		Set row = ..Newest(session)
		Do $$$AssertEquals(..Rows(session), n, key_": one row more")
		Do $$$AssertTrue($IsObject(row), key_": the newest card of the session exists")
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ApprovalRef_"|"_row.DecisionRef, "web|"_kind_"|ZzToolApproval"_n_"|"_decisionRef, key_": its channel, kind, ApprovalRef and DecisionRef")
		Do $$$AssertEquals(row.Text, expected, key_": the text rendered for the web")
		Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), key_": a new message id: "_row.ChannelMessageId)
		Do $$$AssertEquals(row.DueAt_"|"_row.FallbackReason, "|", key_": no due time and no reason")
		Set events = ..Notifications(session)
		Do $$$AssertEquals(events.%Size(), n, key_": one more notification event")
		If events.%Size() = n {
			Set payload = events.%Get(n - 1).payload
			Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.approvalRef_"|"_payload.decisionRef_"|"_payload.text, row.ChannelMessageId_"|"_kind_"|ZzToolApproval"_n_"|"_decisionRef_"|"_expected, key_": the payload carries the Ref, kind, approvalRef, decisionRef and text")
		}
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), n, key_": and the card is in RecentNotices")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 6, "six cards")

	Set quiet = ..Session("toolcallquiet")
	Set noRef = ..Notification(quiet, "approval", "toolCall.request", {"tool": "zz_send", "inputs": (inputs)})
	Set answered = ..Notification(quiet, "answered", "answered.approved", {"channel": "web", "time": (now)})
	Set answered.ApprovalRef = "ZzToolAnswered"
	Set fix = ..Notification(quiet, "approval", "incident.laterRequest", {"zz": "slot"})
	Set fix.ApprovalRef = "ZzToolFix"
	Set resultNoRef = ..Notification(quiet, "result", "toolCall.done", {"tool": "zz_send", "time": (now)})
	Set fixResult = ..Notification(quiet, "result", "result.allThrough", {"zz": "slot"})
	Set fixResult.ApprovalRef = "ZzToolFixResult"
	For notification = noRef, answered, fix, resultNoRef, fixResult {
		Set before = ..Rows(quiet)
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), notification.CatalogKey_" (kind "_notification.Kind_"): delivered")
		Do $$$AssertEquals(..Rows(quiet), before + 1, notification.CatalogKey_": one row is recorded")
		Set row = ..LastRow(quiet)
		Do $$$AssertEquals(row.Kind_"|"_row.ApprovalRef, notification.Kind_"|"_notification.ApprovalRef, notification.CatalogKey_": its kind and ApprovalRef")
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId, "|", notification.CatalogKey_": no text and no message id")
	}
	Do $$$AssertEquals(..Notifications(quiet).%Size(), 0, "none publishes an event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(quiet, 10).Count(), 0, "and none is a card of the chat")
}

/// The notice that a delay notice could not be drafted is a card of the web chat although it has no ApprovalRef (Story 23.5): the rendered text, a new ChannelMessageId, one notification event and a place in RecentNotices.
/// The other results with no ApprovalRef, and a fix's result with an ApprovalRef, stay Delivery rows only.
Method TestPartnerNotDraftedCard()
{
	Set session = ..Session("notdrafted")
	Set notification = ..Notification(session, "result", "result.partnerNotDrafted", {})
	Set notification.IncidentRef = "ZzIncidentRef0000000001"
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the notification is delivered")
	Set row = ..Newest(session)
	Do $$$AssertTrue($IsObject(row), "the session has a card")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ApprovalRef_"|"_row.DecisionRef, "web|result||", "its channel and kind, and no ApprovalRef or DecisionRef")
	Do $$$AssertEquals(row.Text, "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again.", "the text rendered for the web")
	Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), "a new message id: "_row.ChannelMessageId)
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.approvalRef_"|"_payload.text, row.ChannelMessageId_"|result||"_row.Text, "its payload carries the Ref, the kind and the text, and no approvalRef")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "and the card is in RecentNotices")
	Set quiet = ..Session("notdraftedquiet")
	Set plain = ..Notification(quiet, "result", "result.allThrough", {"count": 3, "itemNoun": {"one": "order", "other": "orders"}})
	Set sent = ..Notification(quiet, "result", "result.partnerSent", {"count": 1})
	Set sent.ApprovalRef = "ZzPartnerSentRef"
	For each = plain, sent {
		Set before = ..Rows(quiet)
		Do $$$AssertStatusOK(..Out().OnNotification(each, .response), each.CatalogKey_": delivered")
		Do $$$AssertEquals(..Rows(quiet), before + 1, each.CatalogKey_": one row is recorded")
		Set row = ..LastRow(quiet)
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId, "|", each.CatalogKey_": no text and no message id: the incident card is its web form")
	}
	Do $$$AssertEquals(..Notifications(quiet).%Size()_"|"_##class(OcuTalon.Data.Ownership).RecentNotices(quiet, 10).Count(), "0|0", "and neither is published or a card")
}

/// The persona notices (Story 40.6) are cards of the web chat: approval.persona (kind approval) and persona.applied and persona.stale
/// (kind result), with an ApprovalRef, are rendered for the web, recorded with a ChannelMessageId and the ApprovalRef, and published as
/// one notification event with the text. The same keys with no ApprovalRef, and any of them with the kind answered, record their
/// Delivery row only, with no text and no event.
Method TestPersonaCards()
{
	Set session = ..Session("persona")
	Set cases = $ListBuild($ListBuild("approval", "approval.persona", "{""old"":""Professional (default)"",""new"":""Pirate""}", "OcuTalon suggests a new persona for you. Now: Professional (default). Proposed: Pirate. Nothing changes unless you approve."))
	Set cases = cases_$ListBuild($ListBuild("result", "persona.applied", "{}", "Persona updated. It applies from your next message."))
	Set cases = cases_$ListBuild($ListBuild("result", "persona.stale", "{}", "Your persona changed after this was suggested. Nothing was changed."))
	Set position = 0, n = 0
	While $ListNext(cases, position, case) {
		Set n = n + 1
		Set kind = $List(case, 1), key = $List(case, 2), expected = $List(case, 4)
		Set notification = ..Notification(session, kind, key, {}.%FromJSON($List(case, 3)))
		Set notification.ApprovalRef = "ZzPersonaApproval"_n
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), key_": the notification is delivered")
		Set row = ..Newest(session)
		Do $$$AssertEquals(..Rows(session), n, key_": one row more")
		Do $$$AssertTrue($IsObject(row), key_": the newest card of the session exists")
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ApprovalRef, "web|"_kind_"|ZzPersonaApproval"_n, key_": its channel, kind and ApprovalRef")
		Do $$$AssertEquals(row.Text, expected, key_": the text rendered for the web")
		Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), key_": a new message id")
		Set events = ..Notifications(session)
		Do $$$AssertEquals(events.%Size(), n, key_": one more notification event")
		If events.%Size() = n {
			Set payload = events.%Get(n - 1).payload
			Do $$$AssertEquals(payload.approvalRef_"|"_payload.kind_"|"_payload.text, "ZzPersonaApproval"_n_"|"_kind_"|"_expected, key_": the payload carries the approvalRef, kind and text")
		}
	}
	Set quiet = ..Session("personaquiet")
	Set noRef = ..Notification(quiet, "approval", "approval.persona", {"old": "A", "new": "B"})
	Set answered = ..Notification(quiet, "answered", "persona.applied", {})
	Set answered.ApprovalRef = "ZzPersonaAnswered"
	Set resultNoRef = ..Notification(quiet, "result", "persona.stale", {})
	For notification = noRef, answered, resultNoRef {
		Set before = ..Rows(quiet)
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), notification.CatalogKey_" (kind "_notification.Kind_"): delivered")
		Do $$$AssertEquals(..Rows(quiet), before + 1, notification.CatalogKey_": one row is recorded")
		Set row = ..LastRow(quiet)
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId, "|", notification.CatalogKey_": no text and no message id")
	}
	Do $$$AssertEquals(..Notifications(quiet).%Size(), 0, "none publishes an event")
}

/// Any other kind records its Delivery row only: the kind, the DecisionRef and the ApprovalRef, with no text, no ChannelMessageId
/// and no event, and the row is not one of the chat's cards.
Method TestOtherKindsRecordOnly()
{
	Do ..AssertRecordOnly(..Session("other"), $ListFromString("fallback,pairing,status"), "the other kinds")
	Do $$$AssertEquals(##class(OcuTalon.Channel.WebChat.Out).#CARDKINDS, "tellnow,reminder,allowance,digest,summary", "allowance, digest and summary are card kinds, so they are not one of them")
}

/// A digest (Story 17.10) is a card of kind digest. Its text is the rendering for the web of the parts and the lines of its Slots, one piece on each line,
/// with the lines before the first after-lines part (here digest.saved), or last when there is none. The row keeps the DecisionRef as sent, no due time and
/// no reason, and the one notification event carries the whole text, with an empty whyNow. Slots that cannot be read or rendered record nothing.
Method TestDigestCard()
{
	Set session = ..Session("digest")
	Set slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.checked", "slots": {"checked": "the Chat agent and the Orders service"}}, {"key": "checks.notEverythingRestPassed", "slots": {"whatFailed": "the Orders service"}}, {"key": "digest.saved", "slots": {"count": 1, "summary": "One alert was handled."}}, {"key": "digest.cost", "slots": {"cost": 0.042}}], "lines": [{"key": "digest.notCheckedSizeLimit", "slots": {"entry": "the Billing database"}}, {"key": "digest.notCheckedSizeLimit", "slots": {"entry": "the Orders database"}}], "rows": [{"result": "passed", "entry": "the Chat agent", "finding": "", "checkedAt": "2030-01-01T02:10:00Z"}, {"result": "failed", "entry": "the Orders service", "finding": "It has not answered since 02:10.", "checkedAt": "2030-01-01T02:11:00Z"}]}
	Set expected = "Good morning."
		_$Char(10)_"I checked the Chat agent and the Orders service."
		_$Char(10)_"Not everything: the Orders service. Everything else I checked passed."
		_$Char(10)_"Not checked: the Billing database (OcuTalon can't read this database's size limit)."
		_$Char(10)_"Not checked: the Orders database (OcuTalon can't read this database's size limit)."
		_$Char(10)_"Saved for later (1): One alert was handled."
		_$Char(10)_"Yesterday's cost: $0.04."
	Set notification = ..Notification(session, "digest", "checks.notEverythingRestPassed", slots)
	Set notification.DecisionRef = "ZzDigestDecision"
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the digest is delivered")
	Do $$$AssertEquals(..Rows(session), 1, "one row is recorded")
	Set row = ..Newest(session)
	Do $$$AssertTrue($IsObject(row), "the digest is a card in RecentNotices")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.DueAt_"|"_row.FallbackReason_"|"_row.ApprovalRef, "web|digest|ZzDigestDecision|||", "its channel, kind and decision, and nothing else")
		Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), "a new message id")
		Do $$$AssertEquals(row.Text, expected, "the text is the pieces in order, one on each line")
		Do $$$AssertEquals(row.Text, ##class(OcuTalon.Channel.DigestText).Text(slots.%ToJSON(), "web"), "and the text of the shared helper for the web")
		Do $$$AssertEquals(row.CheckRows, slots.rows.%ToJSON(), "the row keeps the Slots' rows as CheckRows")
	}
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.kind_"|"_payload.whyNow_"|"_payload.dueAt_"|"_payload.fallbackReason, "digest|||", "the payload: kind digest, no whyNow, no due time and no reason")
		Do $$$AssertEquals(payload.text, expected, "and the whole text")
		Do $$$AssertEquals(payload.%ToJSON() [ """kind"":""digest""", 1, "and its JSON names the kind")
		Do $$$AssertEquals(payload.checks.%Size(), 2, "the payload carries the two check rows")
		Do $$$AssertEquals(payload.checks.%Get(1).result_"|"_payload.checks.%Get(1).entry_"|"_payload.checks.%Get(1).finding, "failed|the Orders service|It has not answered since 02:10.", "the second is the failed one")
	}

	Set quiet = ..Session("digestlast")
	Set noAfter = {"parts": [{"key": "digest.greetingEvening", "slots": {}}, {"key": "digest.checkedQuiet", "slots": {"checked": "the Chat agent"}}, {"key": "checks.allPassed", "slots": {}}], "lines": [{"key": "digest.notCheckedSizeLimit", "slots": {"entry": "the Billing database"}}], "rows": []}
	Do $$$AssertStatusOK(..Out().OnNotification(..Notification(quiet, "digest", "checks.allPassed", noAfter), .response), "a digest with no after-lines part is delivered")
	Set row = ..Newest(quiet)
	Do $$$AssertTrue($IsObject(row), "the digest with no after-lines part is a card in RecentNotices")
	If $IsObject(row) Do $$$AssertEquals(row.Text, "Good evening."_$Char(10)_"I checked the Chat agent (all running, no errors, no backlog)."_$Char(10)_"Everything I checked passed."_$Char(10)_"Not checked: the Billing database (OcuTalon can't read this database's size limit).", "the lines come last")
	If $IsObject(row) Do $$$AssertEquals(row.CheckRows, "[]", "an empty rows is kept as []")
	Set events = ..Notifications(quiet)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event for the digest with no rows")
	If events.%Size() = 1 Do $$$AssertEquals($Select(events.%Get(0).payload.%IsDefined("checks"): events.%Get(0).payload.checks.%Size(), 1: 0), 0, "and the payload has no check rows")

	Set broken = ..Session("digestbad")
	Set unknownPart = {"parts": [{"key": "digest.noSuchKey", "slots": {}}], "lines": [], "rows": []}
	Set unknownLine = {"parts": [{"key": "digest.greetingMorning", "slots": {}}], "lines": [{"key": "digest.noSuchKey", "slots": {}}], "rows": []}
	Set noParts = {"lines": [], "rows": []}
	Set noLines = {"parts": [{"key": "digest.greetingMorning", "slots": {}}], "rows": []}
	For bad = unknownPart, unknownLine, noParts, noLines {
		Do $$$AssertStatusNotOK(..Out().OnNotification(..Notification(broken, "digest", "checks.allPassed", bad), .response), "a digest that cannot be rendered is an error: "_bad.%ToJSON())
	}
	Do $$$AssertEquals(..Rows(broken), 0, "and records no row")
	Do $$$AssertEquals(..Notifications(broken).%Size(), 0, "and publishes no event")
}

/// A handled Notification (Story 18.4) for a notice whose tell-now card is the newest web row of its DecisionRef publishes that card again: one more
/// notification event of the card's own ref, now with handledAt, and then the bare Delivery row of kind handled (no text, no message id). The card stays
/// the only entry of RecentNotices. A second handled Notification finds the handled row as the newest and records its row only, with no event.
Method TestHandledRepublishesTheCard()
{
	Set session = ..Session("handled")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": "tellnow", "Reasons": "zz first.", "Confidence": 0.9, "CostUSD": 0.0003})
	Set ..Refs = ..Refs_","_decision
	Set card = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz Dana: Invoice", "reason": "zz first."})
	Set card.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(card, .response), "the tell-now card is delivered")
	Set row = ..Newest(session)
	Do $$$AssertTrue($IsObject(row), "the card exists")
	If '$IsObject(row) Quit
	Set ref = row.ChannelMessageId
	Do $$$AssertEquals(..Notifications(session).%Size(), 1, "one notification event so far")
	Do $$$AssertEquals(..Notifications(session).%Get(0).payload.handledAt, "", "the card is not handled yet")
	Set marked = ..Mark(session, decision, "web")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "the handled Notification is delivered")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 2, "one more notification event")
	If events.%Size() = 2 {
		Set payload = events.%Get(1).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.decisionRef_"|"_payload.handledAt, ref_"|tellnow|"_decision_"|"_marked, "the card's own ref, with handledAt")
		Do $$$AssertEquals(payload.text, "zz Dana: Invoice", "and its text as it was")
	}
	Do $$$AssertEquals(..Rows(session), 2, "the card and the bare handled row")
	Set last = ..LastRow(session)
	Do $$$AssertEquals(last.Channel_"|"_last.Kind_"|"_last.DecisionRef_"|"_last.Text_"|"_last.ChannelMessageId, "web|handled|"_decision_"||", "the bare row: no text, no message id")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "the card is still the only entry of RecentNotices")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "a second handled Notification is delivered")
	Do $$$AssertEquals(..Notifications(session).%Size(), 2, "no event for the second")
	Do $$$AssertEquals(..Rows(session), 3, "only its row")
}

/// A handled Notification with no tell-now card for its DecisionRef records the bare Delivery row only, with no event: none at all, and a digest card
/// that carries the Ref (a digest has no Got it).
Method TestHandledWithNoCardRecordsOnly()
{
	Set session = ..Session("handlednocard")
	Set decision = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mark(session, decision, "web")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(session, decision), .response), "the handled Notification is delivered")
	Do $$$AssertEquals(..Rows(session)_"|"_..Notifications(session).%Size(), "1|0", "one row and no event")
	Set last = ..LastRow(session)
	Do $$$AssertEquals(last.Channel_"|"_last.Kind_"|"_last.DecisionRef_"|"_last.Text_"|"_last.ChannelMessageId, "web|handled|"_decision_"||", "the bare row")
	Set other = ..Session("handleddigest")
	Set digest = ..Notification(other, "digest", "checks.allPassed", {"parts": [{"key": "digest.greetingMorning", "slots": {}}], "lines": [], "rows": []})
	Set digestRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set digest.DecisionRef = digestRef
	Do $$$AssertStatusOK(..Out().OnNotification(digest, .response), "a digest card with the Ref is delivered")
	Do ..Mark(other, digestRef, "web")
	Do $$$AssertStatusOK(..Out().OnNotification(..HandledNotification(other, digestRef), .response), "and its handled Notification")
	Do $$$AssertEquals(..Notifications(other).%Size(), 1, "publishes nothing more: the digest is no tell-now card")
	Do $$$AssertEquals(..Rows(other), 2, "and records its row")
}

/// A reload shows the handled card: Notification.FromRow of the card's row (the snapshot's payload) carries handledAt as soon as the notice is marked,
/// for a tell-now card only, and the check rows of a digest row.
Method TestReloadShowsHandled()
{
	Set session = ..Session("reload")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": "tellnow", "Reasons": "zz first.", "Confidence": 0.9, "CostUSD": 0.0003})
	Set ..Refs = ..Refs_","_decision
	Set card = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz Dana: Invoice", "reason": "zz first."})
	Set card.DecisionRef = decision
	Do $$$AssertStatusOK(..Out().OnNotification(card, .response), "the tell-now card is delivered")
	Set row = ..Newest(session)
	If '$IsObject(row) Do $$$AssertTrue(0, "the card exists") Quit
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Notification).FromRow(row).HandledAt, "", "before the mark: no handledAt")
	Set marked = ..Mark(session, decision, "web")
	Set payload = ##class(OcuTalon.Live.Payload.Notification).FromRow(##class(OcuTalon.Data.Ownership).RecentNotices(session, 1).GetAt(1))
	Do $$$AssertEquals(payload.HandledAt, marked, "after the mark: the reloaded payload has handledAt")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "and exports")
	Do $$$AssertTrue(json [ ("""handledAt"":"""_marked_""""), "its JSON names handledAt")
	Do ##class(OcuTalon.Data.Delivery).Record(session, "web", ##class(OcuTalon.Bridge.Ids).NewRef(), "", "digest", "zz digest", decision, "", "", .digestRow, "[{""result"":""not_checked"",""entry"":""zz entry"",""finding"":""zz why"",""checkedAt"":""2030-01-01T02:10:00Z""}]")
	Set digestPayload = ##class(OcuTalon.Live.Payload.Notification).FromRow(digestRow)
	Do $$$AssertEquals(digestPayload.HandledAt, "", "a digest row with the marked Ref has no handledAt")
	Do $$$AssertEquals(digestPayload.Checks.Count(), 1, "and its check row is read from CheckRows")
	Do $$$AssertEquals(digestPayload.Checks.GetAt(1).Result_"|"_digestPayload.Checks.GetAt(1).Entry, "not_checked|zz entry", "with its result and entry")
}

/// U-313: a digest row written before CheckRows existed (the column empty) is a card in RecentNotices and a payload with no check rows, and its JSON
/// and the page's reading of it have no error.
Method TestOlderDigestRowRenders()
{
	Set session = ..Session("older")
	Set sc = ##class(OcuTalon.Data.Delivery).Record(session, "web", ##class(OcuTalon.Bridge.Ids).NewRef(), "", "digest", "Good morning."_$Char(10)_"Yesterday's cost: $0.04.", "", "", "", .row)
	Do $$$AssertStatusOK(sc, "an older digest row is recorded without CheckRows")
	Do $$$AssertEquals(row.CheckRows, "", "its CheckRows is empty")
	Set card = ..Newest(session)
	Do $$$AssertTrue($IsObject(card), "it is a card in RecentNotices")
	If '$IsObject(card) Quit
	Set payload = ##class(OcuTalon.Live.Payload.Notification).FromRow(card)
	Do $$$AssertEquals(payload.Checks.Count()_"|"_payload.HandledAt, "0|", "a payload with no check rows and no handledAt")
	Do $$$AssertStatusOK(payload.%JSONExportToString(.json), "and it exports")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(json).text, row.Text, "with the stored text")
}

/// The kind allowance (Story 16.9) is a card, as tellnow and reminder are: the session allowance notice and the daily-cap message
/// are rendered with Msg.Catalog.Render for the web, with " ET" after the time on the online demo, recorded as a Delivery row with
/// the kind, the whole text, no decision, no due time and no fallback reason, and published as one notification event whose payload
/// is the row's (kind allowance, the whole text, no whyNow). The cards are in RecentNotices, which is what the snapshot's chat reads.
Method TestAllowanceCards()
{
	Set session = ..Session("allowance")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set link = ##class(OcuTalon.Core.Allowance).#INSTALLLINK
	Set notice = ##class(OcuTalon.Core.Allowance).Notice(session, "2030-06-15T10:00:00Z")
	Set capped = ##class(OcuTalon.Core.Allowance).DailyCapNotice(session, "2030-06-16T04:00:00Z")
	Set sc1 = ..Out().OnNotification(notice, .response)
	Set sc2 = ..Out().OnNotification(capped, .response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertStatusOK(sc1, "the session allowance notice is delivered")
	Do $$$AssertStatusOK(sc2, "and so is the daily-cap message")
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10)
	Do $$$AssertEquals(cards.Count(), 2, "two cards")
	Set limit = ##class(OcuTalon.Core.Allowance).Limit()
	Set head1 = "You've used this session's "_limit_" messages for the hour. You can send more "
	Set tail1 = " ET, or install OcuTalon yourself to keep going: "_link
	Set head2 = "The online demo has used today's model allowance. Decisions use fixed rules until "
	Set tail2 = " ET. You can install OcuTalon yourself to keep going: "_link
	Set found1 = 0, found2 = 0
	For i = 1:1:cards.Count() {
		Set row = cards.GetAt(i)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.DueAt_"|"_row.FallbackReason_"|"_row.ApprovalRef, "web|allowance||||", "card "_i_": the web, kind allowance, and nothing else but the text")
		Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), "card "_i_": a new message id")
		Set text = row.Text
		If ($Extract(text, 1, $Length(head1)) = head1) && ($Extract(text, $Length(text) - $Length(tail1) + 1, *) = tail1) Set found1 = 1
		If ($Extract(text, 1, $Length(head2)) = head2) && ($Extract(text, $Length(text) - $Length(tail2) + 1, *) = tail2) Set found2 = 1
	}
	Do $$$AssertEquals(found1, 1, "the session allowance text of the catalog, its time in instance time and followed by ET, with the install link")
	Do $$$AssertEquals(found2, 1, "the daily-cap text of the catalog, its time in instance time and followed by ET, with the install link")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 2, "two notification events are published")
	If events.%Size() = 2 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.kind_"|"_payload.whyNow_"|"_payload.fallbackReason_"|"_payload.%IsDefined("decision"), "allowance|||0", "the payload: kind allowance, no whyNow, no reason, no decision")
		Do $$$AssertEquals(payload.text, cards.GetAt(2).Text, "and the text of its row (the newest card is the first one listed)")
	}
	Do $$$AssertEquals(..Rows(session), 2, "and only the two rows are recorded")
}

/// A reply records its Delivery row for the web, with its DecisionRef and no ChannelMessageId, no kind and no text; it publishes
/// no notification event and is not a card.
Method TestReplyRecordsItsDeliveryOnly()
{
	Set session = ..Session("reply")
	Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
	Set outbound.SessionRef = session
	Set outbound.OriginChannel = "web"
	Set outbound.Text = "zz a reply"
	Set outbound.DecisionRef = "ZzReplyDecision"
	Do $$$AssertStatusOK(..Out().OnOutbound(outbound, .response), "the reply is delivered")
	Do $$$AssertEquals(..Rows(session), 1, "one row is recorded")
	Set row = ..LastRow(session)
	Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.DecisionRef, session_"|web|ZzReplyDecision", "its owner, channel and DecisionRef")
	Do $$$AssertEquals(row.ChannelMessageId_"|"_row.Kind_"|"_row.Text_"|"_row.ApprovalRef, "|||", "no message id, kind, text or approval")
	Do $$$AssertEquals(..Notifications(session).%Size(), 0, "no notification event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and the row is not a card")
}

/// A text that cannot be rendered is an error status with no row and no event: an unknown key, a missing slot, an empty text
/// slot, a slot of the wrong type and an empty key.
Method TestRenderErrorRecordsNothing()
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
		Do $$$AssertEquals(..Rows(session), 0, $List(case, 1)_": no row is recorded")
		Do $$$AssertEquals(..Notifications(session).%Size(), 0, $List(case, 1)_": and no event is published")
	}
}

/// A message for an owner that is not a session (instance, eval, an empty Ref, a Ref with no Session row) records no row and
/// publishes no event, for a notification of a card kind, of another kind and for a reply, and each logs one warning; the status
/// is OK, so that the operation does not retry.
Method TestNotASession()
{
	Set mark = ..LastLog()
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set owners = $ListBuild("instance", "eval", "", unknown, "Instance")
	Set position = 0
	While $ListNext(owners, position, owner) {
		Set before = ..Rows(owner)
		Set warned = ..Warnings(mark)
		Set notification = ..Notification(owner, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "'"_owner_"': a card notification is dropped with an OK status")
		Set other = ..Notification(owner, "incident", "zz.notRendered", {"zz": "slot"})
		Do $$$AssertStatusOK(..Out().OnNotification(other, .response), "'"_owner_"': so is an incident notification")
		Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
		Set outbound.SessionRef = owner
		Set outbound.OriginChannel = "web"
		Do $$$AssertStatusOK(..Out().OnOutbound(outbound, .response), "'"_owner_"': and a reply")
		Do $$$AssertEquals(..Rows(owner), before, "'"_owner_"': no row is recorded")
		Do $$$AssertEquals(..Warnings(mark) - warned, 3, "'"_owner_"': one warning each")
	}
	Do $$$AssertEquals(..Notifications(unknown).%Size()_"|"_..Notifications("instance").%Size(), "0|0", "and no event is published")
	Do ..RemoveWarnings(mark)
}

/// A notification event that cannot be published (Publish refuses inside an open transaction) is logged as one warning, and the
/// row stays; the delivery is still OK.
Method TestPublishFailureKeepsTheRow()
{
	Set session = ..Session("publish")
	Set mark = ..LastLog()
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz summary", "reason": "zz reason."})
	TSTART
	Set sc = ..Out().OnNotification(notification, .response)
	TCOMMIT
	Do $$$AssertStatusOK(sc, "the delivery is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "the card's row is saved")
	Do $$$AssertEquals(..Notifications(session).%Size(), 0, "no event is published")
	Do $$$AssertEquals(..Warnings(mark, .text, "Announce", "WebChatOut could not publish"), 1, "one warning is logged")
	Do $$$AssertTrue(text [ "transaction", "and says why: "_text)
	Do ..RemoveWarnings(mark, "Announce", "WebChatOut could not publish")
}

/// --- helpers ---
/// Sends the session one Notification of each kind, with an ApprovalRef and a DecisionRef, and asserts that each records its
/// Delivery row only (channel web, the kind, the approval and the decision; no text, no ChannelMessageId, no due time and no
/// reason), that none publishes an event and that none is a card of the chat.
Method AssertRecordOnly(session As %String, kinds As %List, what As %String) [ Private ]
{
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set notification = ..Notification(session, kind, "zz.notRendered", {"zz": "slot"})
		Set notification.ApprovalRef = "ZzApproval"_kind
		Set notification.DecisionRef = "ZzDecision"_kind
		Set before = ..Rows(session)
		Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), kind_": the notification is delivered")
		Do $$$AssertEquals(..Rows(session), before + 1, kind_": one row is recorded")
		Set row = ..LastRow(session)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.ApprovalRef_"|"_row.DecisionRef, "web|"_kind_"|ZzApproval"_kind_"|ZzDecision"_kind, kind_": its channel, kind, approval and decision")
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId_"|"_row.DueAt_"|"_row.FallbackReason, "|||", kind_": no text, no message id, no due time and no reason")
	}
	Do $$$AssertEquals(..Notifications(session).%Size(), 0, what_": none publishes an event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, what_": and none is a card of the chat")
}

/// An incident summary (Story 23.6; AC 5, AC 14) is a card of kind summary. Its text is OcuTalon.Watch.Summary.Text of the notification's incident for the web: the
/// stored summary, one catalog line per part, with its line breaks, and the cause, the evidence and the sample error exactly as stored, with their markup characters
/// (the page shows them as text). The row keeps the DecisionRef as sent and no due time and no reason, and the one notification event carries the whole text.
/// Another session gets no row, and a summary that is missing records nothing.
Method TestSummaryCard()
{
	Set session = ..Session("summary")
	Set other = ..Session("summaryother")
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
	Do $$$AssertEquals(..Rows(session), 1, "one row is recorded")
	Do $$$AssertEquals(..Rows(other), 0, "and another session gets none")
	Do $$$AssertEquals(..Notifications(other).%Size(), 0, "nor an event")
	Set row = ..Newest(session)
	Do $$$AssertTrue($IsObject(row), "the summary is a card in RecentNotices")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.DueAt_"|"_row.FallbackReason_"|"_row.ApprovalRef, "web|summary|ZzSummaryDecision|||", "its channel, kind and decision, and nothing else")
		Do $$$AssertTrue(row.ChannelMessageId ? 22(1AN,1"-",1"_"), "a new message id")
		Do $$$AssertEquals(row.Text, expected, "the text is the stored summary's lines, with the markup characters as they are")
		Do $$$AssertEquals(row.Text, ##class(OcuTalon.Watch.Summary).Text(incident, "web"), "and the text of Watch.Summary.Text for the web")
	}
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.kind_"|"_payload.whyNow_"|"_payload.dueAt_"|"_payload.fallbackReason, "summary|||", "the payload: kind summary, no whyNow, no due time and no reason")
		Do $$$AssertEquals(payload.text, expected, "and the whole text, with its line breaks")
	}
	Set bare = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "closed"})
	Set ..Refs = ..Refs_","_bare
	Set missing = ..Notification(session, "summary", "summary.title", {})
	Set missing.IncidentRef = bare
	Do $$$AssertStatusNotOK(..Out().OnNotification(missing, .response), "an incident with no summary is an error")
	Set unknown = ..Notification(session, "summary", "summary.title", {})
	Do $$$AssertStatusNotOK(..Out().OnNotification(unknown, .response), "and so is a notification with no incident")
	Do $$$AssertEquals(..Rows(session), 1, "neither records a row")
	Do $$$AssertEquals(..Notifications(session).%Size(), 1, "or an event")
}

/// AC 14 (QA), the web chat: an incident whose rows hold markup is summarized by Watch.Summary.Build (Test.Watch.Summary.Built), and the card that WebChatOut records
/// shows the cause and the sample error as they came: the markup literally, the sample error cut to an incident notice's length, one line each. The page binds the text
/// as text (N20 and page-safety.test.mjs), so that it is shown, not taken as markup.
Method TestSummaryBuilt()
{
	Set session = ..Session("built")
	Set incident = ##class(OcuTalon.Test.Watch.Summary).Built(session)
	Set ..Refs = ..Refs_","_incident
	Set notification = ..Notification(session, "summary", "summary.title", {})
	Set notification.IncidentRef = incident
	Do $$$AssertStatusOK(..Out().OnNotification(notification, .response), "the built summary is delivered")
	Set row = ..Newest(session)
	Do $$$AssertTrue($IsObject(row), "it is a card")
	If '$IsObject(row) Quit
	Set cut = ##class(OcuTalon.Test.Watch.Summary).CutLine()
	Do $$$AssertTrue($Length(cut) '> $Parameter("OcuTalon.Watch.ErrorText", "SUMMARYMAX"), "the cut is no longer than a notice's error summary")
	Do $$$AssertTrue(row.Text [ ($Char(10)_"Cause: The partner sent <b>x</b> and *y*."_$Char(10)), "the cause shows its markup literally")
	Do $$$AssertTrue(row.Text [ ($Char(10)_"Sample error: "_cut_$Char(10)), "and the sample error is the cut, with its markup: "_cut)
	Do $$$AssertTrue(row.Text '[ ##class(OcuTalon.Test.Watch.Summary).#LONGMARKUP, "the whole sample error is not in the card")
	Set events = ..Notifications(session)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.text, row.Text, "which carries the same text")
}

/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzweb"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The Notification that GotIt sends: kind handled for the session, with the Decision's Ref, no catalog key and no slots.
Method HandledNotification(session As %String, decisionRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ..Notification(session, "handled", "", {})
	Set notification.DecisionRef = decisionRef
	Quit notification
}

/// Marks the notice as handled, as SessionOps does: one Handled row {the Ref, the session, now, the channel}. Returns when.
Method Mark(session As %String, decisionRef As %String, channel As %String) As %String [ Private ]
{
	Set handled = ##class(OcuTalon.Data.Handled).%New()
	Set handled.Ref = decisionRef
	Set handled.SessionRef = session
	Set handled.Channel = channel
	Set handled.HandledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(handled.%Save(), "the notice is marked handled")
	Quit handled.HandledAt
}

/// A shadow instance of the operation.
Method Out() As OcuTalon.Channel.WebChat.Out [ Private ]
{
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the operation is made")
	Quit out
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

/// The notification events of the session's stream, in order.
Method Notifications(session As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "notification")
}

/// The newest card of the session, as Ownership reads it.
Method Newest(session As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 1, .sc)
	Quit $Select(rows.Count() = 1: rows.GetAt(1), 1: "")
}

/// The number of Delivery rows of the owner, whatever their kind (the test reads the table directly, as a test may).
Method Rows(owner As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner)
}

/// The newest Delivery row of the owner, whatever its kind.
Method LastRow(owner As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(owner)
	Quit $Select(rows.Count() > 0: rows.GetAt(rows.Count()), 1: "")
}

/// The number of the newest row of the event log.
Method LastLog() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).LastLog()
}

/// The number of warnings after the row mark that the method of WebChatOut logged, with the text starting as given; text is the
/// newest one's text. By default the warnings for a message dropped because its owner is not a session.
Method Warnings(mark As %Integer, Output text As %String, method As %String = "IsSession", start As %String = "WebChatOut dropped a message") As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, method, start)
}

/// Removes those warnings.
Method RemoveWarnings(mark As %Integer, method As %String = "IsSession", start As %String = "WebChatOut dropped a message") [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, method, start)
}

}
