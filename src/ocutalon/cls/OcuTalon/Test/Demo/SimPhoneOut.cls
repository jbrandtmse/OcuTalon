/// Tests of SimPhoneOut (Story 4.5; AD-4, AD-12, AD-14, AD-32, AD-33). The handler tests are safe on a slot: no production runs
/// there, so they call the handlers on a shadow instance of OcuTalon.Channel.SimPhone.Out, with fixture sessions from
/// Test.Data.Fixture. TestThroughNotify needs the running OcuTalon.Production with demo mode on and runs in throwaways and CI only
/// (Rule 21); where no production runs it is skipped. Every expected text is rendered here through Msg.Catalog.RenderAt, with
/// the channel written out and the clock and the online-demo flag fixed.
///   - TestTellNow, TestReminder: a card-kind Notification becomes one SimMessage (kind phone, direction out, the text of the
///     telegram render, which is the phone render), one phone Delivery row (the SimMessage's Ref as ChannelMessageId, the kind and
///     the Refs, no text) and one phone event whose payload is the message's;
///   - TestTextIsTheTelegramWording: for a key that words the web differently, the phone carries the telegram wording;
///   - TestOnlineDemoTimesNameTheZone: a late reminder's time ends with " ET" on the online demo and has no suffix otherwise;
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
		Set expectedPayload = ##class(%DynamicObject).%FromJSON(..Json(##class(OcuTalon.Live.Payload.Phone).FromRow(row)))
		Do $$$AssertEquals(payload.%ToJSON(), expectedPayload.%ToJSON(), "its payload is the one that FromRow makes of the message")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(other, 10).Count(), 0, "another session has no message")
	Do $$$AssertEquals(..Phones(other).%Size(), 0, "and no event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and the phone's Delivery row is not a card of the web chat")
}

/// A reminder (reminder.due) is a phone message with the rendered text. A reminder with no due slot is rendered the same way.
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

/// Any other kind records its phone Delivery row only: the kind, the DecisionRef and the ApprovalRef, with no text and no
/// ChannelMessageId, no SimMessage and no event.
Method TestOtherKindsRecordOnly()
{
	Set session = ..Session("other")
	Set kinds = $ListFromString("incident,approval,answered,result,fallback,allowance,pairing,status,digest")
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
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "no kind makes a phone message")
	Do $$$AssertEquals(..Phones(session).%Size(), 0, "and none publishes an event")
}

/// A message for an owner that is not a session (instance, eval, an empty Ref, a Ref with no Session row, the control owner of the
/// demo-switch test) records no row and publishes no event, for a card kind with a slot set that cannot be rendered too (the owner
/// check comes first), and each logs one warning; the status is OK, so that the operation does not retry.
Method TestNotASession()
{
	Set mark = ..LastLog()
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
		Set other = ..Notification(owner, "incident", "zz.notRendered", {"zz": "slot"})
		Do $$$AssertStatusOK(..Out().OnNotification(other, .response), "'"_owner_"': so is an incident notification")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner), before, "'"_owner_"': no row is recorded")
		Do $$$AssertEquals(..Warnings(mark) - warned, 2, "'"_owner_"': one warning each")
		Do $$$AssertEquals(..PhoneCount(owner), 0, "'"_owner_"': and no phone message")
	}
	Do $$$AssertEquals(..Phones(unknown).%Size()_"|"_..Phones("instance").%Size(), "0|0", "and no event is published")
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
/// the target differs (AC3, the Visual Trace clause). The SimMessage is there within WAIT seconds of the send.
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
