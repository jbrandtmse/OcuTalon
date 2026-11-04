/// End-to-end tests of NoticesIn over the running production (Story 6.3; AD-1, AD-26, AD-31, AD-32). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production with demo mode on, which a slot never
/// has. Where the production does not run, every test fails with that reason, so that a broken start can never give a green
/// shard. Every test sends through OcuTalon.Core.NoticesIn.Send, as the senders to come do.
///   - TestDeliveredOnEveryChannel: a tell-now Notification gives, within WAIT seconds, the session's web Delivery row, its phone
///     SimMessage and its phone Delivery row, and one asynchronous NoticesIn to Notify header whose SuperSession is the session's TraceRef;
///   - TestIncidentNoticeAsksOnThePhone: an incident Notification with an ApprovalRef gives the phone message that asks for it;
///   - TestJoinsTheThread: inside a context with a ThreadSessionId, the NoticesIn to Notify header is in that trace session.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("NoticesInProduction","n")) and the clean-up are those of
/// Test.Core.InProduction.
Class OcuTalon.Test.Core.NoticesInProduction Extends OcuTalon.Test.Core.InProduction
{

/// A tell-now Notification, a Delivery row on the web chat and on the phone, and one NoticesIn to Notify header in the
/// session's SuperSession; the phone's message has the rendered text.
Method TestDeliveredOnEveryChannel()
{
	If '..Guard() Quit
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on")
	Set session = ..Session("everychannel")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set notification = ..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz Disk almost full", "reason": "you asked to hear about disk space"})
	Do $$$AssertStatusOK(##class(OcuTalon.Core.NoticesIn).Send(notification), "the notification is sent")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 2, ..#WAIT)
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Set channels = ""
	For i = 1:1:deliveries.Count() Set channels = channels_$Select(channels = "": "", 1: ",")_deliveries.GetAt(i).Channel
	Do $$$AssertEquals($ListLength($ListFromString(channels)), 2, "two Delivery rows: "_channels)
	Do $$$AssertTrue($ListFind($ListFromString(channels), "web") && $ListFind($ListFromString(channels), "phone"), "one for the web chat and one for the phone")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
		If (rows.Count() > 0) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(rows.Count(), 1, "the phone has its message")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Text, "zz Disk almost full"_$Char(10)_"Why now: you asked to hear about disk space", "with the rendered text")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "NoticesIn", "Notify", 1, ..#WAIT), "Notify has handled the notification")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "NoticesIn", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one header goes from NoticesIn to Notify")
	If sent.%Size() = 1 {
		Do $$$AssertEquals(sent.%Get(0).superSession, trace, "its SuperSession is the session's TraceRef")
		Do $$$AssertEquals(sent.%Get(0).bodyClass, "OcuTalon.Msg.Notification", "and its body is the Notification")
		Set returnQueue = ##class(%SQL.Statement).%ExecDirect(, "SELECT ReturnQueueName FROM Ens.MessageHeader WHERE ID = ?", sent.%Get(0).id)
		Do $$$AssertTrue(returnQueue.%Next(), "the header is readable")
		Do $$$AssertEquals(returnQueue.%Get("ReturnQueueName"), "", "the send is asynchronous: the header waits for no reply")
	}
}

/// An incident Notification with an ApprovalRef is delivered to the phone as the message that asks for the request; the web
/// chat records its Delivery row only.
Method TestIncidentNoticeAsksOnThePhone()
{
	If '..Guard() Quit
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on")
	Set session = ..Session("incident")
	Set approval = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set slots = {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": (now), "cause": "Data format change", "fixSummary": "repair the order date and resend 50 orders", "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16", "resendCount": 50}
	Set notification = ..Notification(session, "incident", "incident.withFix", slots)
	Set notification.ApprovalRef = approval
	Do $$$AssertStatusOK(##class(OcuTalon.Core.NoticesIn).Send(notification), "the notification is sent")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
		If (rows.Count() > 0) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(rows.Count(), 1, "the phone has its message")
	If rows.Count() = 1 {
		Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen(rows.GetAt(1).Ref)
		Do $$$AssertEquals(message.ApprovalRef, approval, "which asks for the request")
		Do $$$AssertEquals(message.Answer, "", "and has no answer")
	}
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 2, ..#WAIT)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 2, "the web chat and the phone each recorded a Delivery row")
}

/// Inside a bridge context with a ThreadSessionId, the NoticesIn to Notify header is in that trace session: a first send, outside
/// any context, makes a session of its own, and a second send inside a context in that session joins it.
Method TestJoinsTheThread()
{
	If '..Guard() Quit
	Set session = ..Session("thread")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do $$$AssertStatusOK(##class(OcuTalon.Core.NoticesIn).Send(..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz first", "reason": "zz reason."})), "a first notification is sent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "NoticesIn", "Notify", 1, ..#WAIT), "Notify has handled it")
	Set first = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "NoticesIn", "Notify")
	Do $$$AssertEquals(first.%Size(), 1, "one header goes from NoticesIn to Notify")
	If first.%Size() '= 1 Quit
	Set thread = first.%Get(0).sessionId
	Do $$$AssertEquals(thread, first.%Get(0).id, "it has a session of its own, which starts at its header")
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = session
	Set begin.ThreadSessionId = thread
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(begin, trace), "a context in that thread begins")
	Try {
		Set sc = ##class(OcuTalon.Core.NoticesIn).Send(..Notification(session, "tellnow", "notice.tellNow", {"whatHappened": "zz second", "reason": "zz reason."}))
		Do $$$AssertStatusOK(sc, "the second notification is sent inside the context")
	} Catch exception {
		Do $$$AssertTrue(0, "Send inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "NoticesIn", "Notify", 2, ..#WAIT), "Notify has handled both")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "NoticesIn", "Notify")
	Do $$$AssertEquals(sent.%Size(), 2, "two headers go from NoticesIn to Notify")
	If sent.%Size() = 2 {
		Do $$$AssertEquals(sent.%Get(1).sessionId, thread, "the second is in the context's thread session")
		Do $$$AssertEquals(sent.%Get(1).superSession, trace, "with the same SuperSession")
	}
}

/// --- helpers ---
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

}
