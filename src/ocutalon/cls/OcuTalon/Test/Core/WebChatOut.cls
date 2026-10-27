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
	Set session = ..Session("incident")
	Set kinds = $ListFromString(##class(OcuTalon.Channel.WebChat.Out).#INCIDENTKINDS)
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
	Do $$$AssertEquals(..Notifications(session).%Size(), 0, "no incident kind publishes an event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and none is a card of the chat")
}

/// Any other kind records its Delivery row only: the kind, the DecisionRef and the ApprovalRef, with no text, no ChannelMessageId
/// and no event, and the row is not one of the chat's cards.
Method TestOtherKindsRecordOnly()
{
	Set session = ..Session("other")
	Set kinds = $ListFromString("fallback,allowance,pairing,status,digest")
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
	Do $$$AssertEquals(..Notifications(session).%Size(), 0, "no kind publishes an event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and none is a card of the chat")
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
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzweb"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
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
