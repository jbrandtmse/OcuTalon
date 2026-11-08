/// Tests that a Notification of kind handled (the one SessionOps' GotIt branch sends, with a DecisionRef, no catalog key and no slots) shows nothing
/// new on the web chat or on the Simulated phone (Story 12.12; AD-14, AD-32). Both Out operations record a bare Delivery row for it, because Notify's
/// generic route reaches them for every kind, and make no card, no phone message and no event; the web Got it control and the phone's are Story 18.4's.
///   - TestWebRecordsOnly: WebChatOut records one Delivery row {web, handled, the DecisionRef} with no text, no message id and no due time, publishes no
///     notification event and makes no card (RecentNotices);
///   - TestPhoneRecordsOnly: SimPhoneOut records one Delivery row {phone, handled, the DecisionRef} with no text and no message id, makes no SimMessage
///     and no phone message (RecentPhone) and publishes no phone event.
/// Safe on a slot: shadow instances over fixture sessions, no production. Each test makes its own session; OnAfterAllTests removes every
/// session of the run, with its Delivery rows, through Fixture.Clean.
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
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

/// A handled Notification reaches WebChatOut: one bare Delivery row, no event, no card.
Method TestWebRecordsOnly()
{
	Set session = ..Session("web")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of WebChatOut is made")
	Do $$$AssertStatusOK(out.OnNotification(..Handled(session, ref), .response), "the handled Notification is delivered")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row is recorded")
	If rows.Count() '= 1 Quit
	Set row = rows.GetAt(1)
	Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef, "web|handled|"_ref, "its channel, kind and the Decision's Ref")
	Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId_"|"_row.ApprovalRef_"|"_row.DueAt_"|"_row.FallbackReason, "||||", "no text, no message id, no approval, no due time and no reason")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size(), 0, "no notification event is published")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "and the chat shows no card")
}

/// A handled Notification reaches SimPhoneOut: one bare Delivery row, no message, no event.
Method TestPhoneRecordsOnly()
{
	Set session = ..Session("phone")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of SimPhoneOut is made")
	Do $$$AssertStatusOK(out.OnNotification(..Handled(session, ref), .response), "the handled Notification is delivered")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row is recorded")
	If rows.Count() = 1 {
		Set row = rows.GetAt(1)
		Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.DecisionRef, "phone|handled|"_ref, "its channel, kind and the Decision's Ref")
		Do $$$AssertEquals(row.Text_"|"_row.ChannelMessageId_"|"_row.ApprovalRef_"|"_row.DueAt_"|"_row.FallbackReason, "||||", "no text, no message id, no approval, no due time and no reason")
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", session)
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 0, "no phone message is stored")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "and the phone shows none")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "phone").%Size(), 0, "no phone event is published")
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

}
