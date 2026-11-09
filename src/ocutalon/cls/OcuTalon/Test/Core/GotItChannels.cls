/// Tests that a Notification of kind handled (the one SessionOps' GotIt branch sends, with a DecisionRef, no catalog key and no slots) reaches the web chat
/// and the Simulated phone as their "Marked as handled" copy (Story 12.12 made the notification; Story 18.4 the copies; AD-14, AD-32). Notify's generic
/// route delivers it to both Out operations; each finds its copy of the notice by the DecisionRef.
///   - TestWebRepublishesTheCard: WebChatOut publishes the tell-now card again with its own ref and handledAt (one more notification event) and records one
///     bare Delivery row {web, handled, the DecisionRef} with no text, no message id and no due time;
///   - TestPhoneEditsTheMessage: SimPhoneOut sets the Answer of the tell-now message to the rendered handled.marked line (one more phone event) and records
///     one Delivery row {phone, handled, the DecisionRef} that names the message;
///   - TestSecondHandledChangesNothing: a second handled Notification on either channel (a repeat press) records its Delivery row only, with no event
///     and no edit.
/// Safe on a slot: shadow instances over fixture sessions, no production. Each test makes its own session; OnAfterAllTests removes every
/// session of the run, with its Delivery rows, through Fixture.Clean, and the Handled rows by session.
Class OcuTalon.Test.Core.GotItChannels Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("GotItChannels", "n"))
	Set ..Refs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Refs, ",") Do ##class(OcuTalon.Data.Handled).DropSession($Piece(..Refs, ",", i))
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

/// A handled Notification reaches WebChatOut: the tell-now card is published again with handledAt, and one bare Delivery row is recorded.
Method TestWebRepublishesTheCard()
{
	Set session = ..Session("web")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of WebChatOut is made")
	Do $$$AssertStatusOK(out.OnNotification(..TellNow(session, ref), .response), "the tell-now card is delivered")
	Set card = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).GetAt(1)
	Set cardRef = card.ChannelMessageId
	Kill card
	Set marked = ..Mark(session, ref, "web")
	Do $$$AssertStatusOK(out.OnNotification(..Handled(session, ref), .response), "the handled Notification is delivered")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 2, "the card's row and one bare Delivery row")
	If rows.Count() = 2 {
		Set row = rows.GetAt(2)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef, "web|handled|"_ref, "its channel, kind and the Decision's Ref")
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId_"|"_row.ApprovalRef_"|"_row.DueAt_"|"_row.FallbackReason, "||||", "no text, no message id, no approval, no due time and no reason")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "notification")
	Do $$$AssertEquals(events.%Size(), 2, "the card's event and one more")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.handledAt, cardRef_"|"_marked, "the second is the card's own ref with handledAt")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "and the chat still shows the one card")
}

/// A handled Notification reaches SimPhoneOut: the Answer of the tell-now message becomes the handled line, and one Delivery row names the message.
Method TestPhoneEditsTheMessage()
{
	Set session = ..Session("phone")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of SimPhoneOut is made")
	Do $$$AssertStatusOK(out.OnNotification(..TellNow(session, ref), .response), "the tell-now message is delivered")
	Set messageRef = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).GetAt(1).Ref
	Set marked = ..Mark(session, ref, "phone")
	Do $$$AssertStatusOK(out.OnNotification(..Handled(session, ref), .response), "the handled Notification is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (marked)}, "phone")
	Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen(messageRef)
	Do $$$AssertEquals(message.Answer, expected, "the Answer is the rendered handled line")
	Do $$$AssertTrue($Extract(expected, 1, 21) = "Marked as handled at ", "which reads: "_expected)
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 2, "the message's row and one more")
	If rows.Count() = 2 {
		Set row = rows.GetAt(2)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.ChannelMessageId, "phone|handled|"_ref_"|"_messageRef, "its channel, kind and the Decision's Ref, naming the message")
		Do $$$AssertEquals(row.Text_"|"_row.ApprovalRef_"|"_row.DueAt_"|"_row.FallbackReason, "|||", "no text, no approval, no due time and no reason")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "phone")
	Do $$$AssertEquals(events.%Size(), 2, "the message's event and one more")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.answer, messageRef_"|"_expected, "the second carries the answer")
}

/// A repeat of the handled Notification (a second press) changes nothing on either channel: its Delivery row only, with no new event and the first copy kept.
Method TestSecondHandledChangesNothing()
{
	Set session = ..Session("second")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set web = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Set phone = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
	Do $$$AssertStatusOK(web.OnNotification(..TellNow(session, ref), .response), "the web card is delivered")
	Do $$$AssertStatusOK(phone.OnNotification(..TellNow(session, ref), .response), "and the phone message")
	Do ..Mark(session, ref, "web")
	Do $$$AssertStatusOK(web.OnNotification(..Handled(session, ref), .response), "the first handled Notification reaches the web chat")
	Do $$$AssertStatusOK(phone.OnNotification(..Handled(session, ref), .response), "and the phone")
	Set answer = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).GetAt(1).Answer
	Set webEvents = ##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size()
	Set phoneEvents = ##class(OcuTalon.Test.Core.Observe).Events(session, "phone").%Size()
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(session)
	Do $$$AssertStatusOK(web.OnNotification(..Handled(session, ref), .response), "the second reaches the web chat")
	Do $$$AssertStatusOK(phone.OnNotification(..Handled(session, ref), .response), "and the phone")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size(), webEvents, "no new notification event")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "phone").%Size(), phoneEvents, "and no new phone event")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), rows + 2, "only the two Delivery rows")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).GetAt(1).Answer, answer, "and the phone's answer is the first one")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzgotitch"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The Notification that GotIt sends: kind handled for the session, with the Decision's Ref, no catalog key and no slots.
Method Handled(session As %String, decisionRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "handled"
	Set notification.DecisionRef = decisionRef
	Set notification.CatalogKey = ""
	Set notification.Slots = "{}"
	Quit notification
}

/// A tell-now Notification for the Decision's Ref.
Method TellNow(session As %String, decisionRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "tellnow"
	Set notification.DecisionRef = decisionRef
	Set notification.CatalogKey = "notice.tellNow"
	Set notification.Slots = {"whatHappened": "zz notice", "reason": "zz reason."}.%ToJSON()
	Quit notification
}

/// Marks the notice as handled, as SessionOps does: one Handled row. Returns when.
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

}
