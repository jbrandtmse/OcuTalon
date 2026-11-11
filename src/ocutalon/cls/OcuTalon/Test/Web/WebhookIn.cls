/// Tests of WebhookIn, the service through which a webhook's event enters the production (Story 35.3; AD-14, AD-26, AD-30). The Item's fields and the
/// refusals are tested on a shadow instance of Test.Web.WebhookInProbe, which records its sends and needs no production; TestOwnTraceSession is the one test
/// that runs through the real production (throwaway stacks and CI only, Rule 21).
///   - TestItem: an Event becomes one Item sent to Intake with a new ItemId, the Event's session, channel webhook, provenance untrusted, the webhook's name as
///     subject, the body as text, no sender and no guide flag, the service's SuperSession is the session's TraceRef, and the output is {"itemId"};
///   - TestRefusals: an input that is not an Event, an Event with no session, with blank text, and one whose session has no row each answer an error status
///     and send nothing; a failing send is the answer;
///   - TestOwnTraceSession: through the production, the Item's message has a trace session of its own whose SuperSession is the owner's TraceRef, and a session
///     with no row sends no message; the test waits until the event is decided and routed before it removes its messages and the event's Decision rows, and
///     afterwards the event's trace session stays empty and no Decision row of the event is left.
Class OcuTalon.Test.Web.WebhookIn Extends %UnitTest.TestCase
{

Parameter PROBE = "class||OcuTalon.Test.Web.WebhookInProbe";

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("WebhookIn")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("WebhookIn")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $$$OK
}

Method TestItem()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set event = ..Event(session, "zz hook", "{""a"":1}")
	Set service = ##class(Ens.Host).GetShadowInstance(..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the shadow instance")
	Set sc = service.OnProcessInput(event, .output)
	Do $$$AssertStatusOK(sc, "an Event is accepted")
	Do $$$AssertEquals($Get(^OcuTalonTest("WebhookIn")), 1, "one send")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "target"), "Intake", "to Intake")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "class"), "OcuTalon.Msg.Item", "an Item")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "sessionRef"), session, "of the Event's session")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "channel"), "webhook", "on the channel webhook")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "provenance"), "untrusted", "untrusted")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "subject"), "zz hook", "with the webhook's name as subject")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "text"), "{""a"":1}", "and the body as text")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "sender"), "", "with no sender")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "fromGuide"), 0, "and not from the guide")
	Do $$$AssertEquals(^OcuTalonTest("WebhookIn", 1, "superSession"), trace, "the service's SuperSession is the session's TraceRef")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).IsRef(^OcuTalonTest("WebhookIn", 1, "itemId")), "the ItemId is a new Ref")
	Do $$$AssertEquals(output, {"itemId": (^OcuTalonTest("WebhookIn", 1, "itemId"))}.%ToJSON(), "the output is {itemId}")
	Do service.OnProcessInput(event, .output2)
	Do $$$AssertTrue(^OcuTalonTest("WebhookIn", 2, "itemId") '= ^OcuTalonTest("WebhookIn", 1, "itemId"), "every event has its own ItemId")
}

Method TestRefusals()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set service = ##class(Ens.Host).GetShadowInstance(..#PROBE, .sc)
	Set sc = service.OnProcessInput("text", .output)
	Do $$$AssertStatusNotOK(sc, "an input that is not an Event is refused")
	Set sc = service.OnProcessInput(##class(OcuTalon.Channel.SimMailbox.Mail).%New(), .output)
	Do $$$AssertStatusNotOK(sc, "so is another object")
	Set sc = service.OnProcessInput(..Event("", "zz hook", "{}"), .output)
	Do $$$AssertStatusNotOK(sc, "an Event with no session is refused")
	Set sc = service.OnProcessInput(..Event(session, "zz hook", "  "), .output)
	Do $$$AssertStatusNotOK(sc, "an Event with blank text is refused")
	Set sc = service.OnProcessInput(..Event(##class(OcuTalon.Bridge.Ids).NewRef(), "zz hook", "{}"), .output)
	Do $$$AssertStatusNotOK(sc, "an Event whose session has no row is refused")
	Do $$$AssertEquals(output, "", "with no output")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("WebhookIn")), 0, "nothing is sent")
	Set ^OcuTalonTest("WebhookIn", "mode") = "fail"
	Set sc = service.OnProcessInput(..Event(session, "zz hook", "{}"), .output)
	Do $$$AssertStatusNotOK(sc, "a send that fails is the answer")
	Do $$$AssertEquals(output, "", "with no output")
}

Method TestOwnTraceSession()
{
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Do $$$AssertTrue(0, "OcuTalon.Production does not run in OCUTALON: this test runs in throwaways and CI only (Rule 21)")
		Quit
	}
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set mark = ##class(OcuTalon.Test.Web.WebhookTools).LastHeader()
	Set sc = ##class(Ens.Director).CreateBusinessService("WebhookIn", .service)
	Do $$$AssertStatusOK(sc, "the production creates WebhookIn")
	Set sc = service.ProcessInput(..Event(session, "zz hook", "{""zz"":1}"), .output)
	Do $$$AssertStatusOK(sc, "the event is accepted")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set found = 0, own = ""
	For i = 0:1:headers.%Size() - 1 {
		If headers.%Get(i).source = "WebhookIn" Set found = found + 1, own = headers.%Get(i).sessionId
	}
	Do $$$AssertEquals(found, 1, "one message from WebhookIn is under the owner's TraceRef")
	Do $$$AssertTrue(own '= "", "and it has a session of its own")
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.WebhookTools).HeadersSince(mark, "WebhookIn"), 1, "and no other")
	Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).WaitSettled(own, 60), "the event is decided and routed")
	Set itemId = {}.%FromJSON(output).itemId
	Set orphan = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Web.WebhookTools).LastHeader()
	Set sc = service.ProcessInput(..Event(orphan, "zz hook", "{}"), .output)
	Do $$$AssertStatusNotOK(sc, "an event whose session has no row is an error")
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.WebhookTools).HeadersSince(mark, "WebhookIn"), 0, "and sends no message")
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages([(trace)])
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef IN (SELECT Ref FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?)", itemId)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	Hang 1
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(own).%Size(), 0, "no late writer adds to the event's trace session after the clean-up")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	Do $$$AssertEquals($Select(result.%Next(): +result.%GetData(1), 1: -1), 0, "and no Decision row of the event is left")
}

/// An Event of the session with the name and the text.
ClassMethod Event(session As %String, name As %String, text As %String) As OcuTalon.Channel.Webhook.Event [ Private ]
{
	Set event = ##class(OcuTalon.Channel.Webhook.Event).%New()
	Set event.SessionRef = session
	Set event.Name = name
	Set event.Text = text
	Quit event
}

}
