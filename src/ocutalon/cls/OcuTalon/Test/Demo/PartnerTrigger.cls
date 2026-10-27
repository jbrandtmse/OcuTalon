/// Tests of Demo.PartnerTrigger (Story 4.3; matrix rows 2, 10 and 11; AD-3, AD-17). The operation runs on a shadow instance of
/// Test.Demo.PartnerTriggerProbe, which answers the audit write and the send from ^OcuTalonTest and records them, so that no production and
/// no OCUORDERS are needed. The real batch and the real audit entry are Test.Demo.BreakFeedProduction's.
///   - TestAuditBeforeSend: the Action audit data is exactly the type's shape with the session's user, session and channel, it passes the
///     redaction unchanged and Bridge.Audit.Record accepts its shape; the audit comes before the send, the send gets the TraceRef, and the
///     answer is an Ens.Response. It enables the Action audit event for its run and puts back the state it found;
///   - TestFailedAuditSendsNothing: a failed audit is an error status and nothing is sent;
///   - TestRefusedSendsNothing: an unknown session, another class and no request are an error status, with no audit and no send;
///   - TestFailedSendIsAnError: a send that fails is an error status, after the audit;
///   - TestBatch: COUNT is 50 and DATEFORMAT is the partner's second format, which its transform rejects, and Send is the one method of
///     the class that switches namespace.
Class OcuTalon.Test.Demo.PartnerTrigger Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("PartnerTrigger", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("PartnerTriggerProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("PartnerTriggerProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// Row 10: the audit data is the Action type's shape, with the session's own user, session and the channel; it comes before the send.
Method TestAuditBeforeSend()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpartner"_..Number)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set event = "OcuTalon/Action/Action"
	Set was = ##class(OcuTalon.Test.Bridge.AuditLog).EventState(event)
	If was = 0 Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(event, 1)
	Set ^OcuTalonTest("PartnerTriggerProbe", "answer", "audit") = "record"
	Set sc = ..Ask(ref, "web", .response)
	If was = 0 Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(event, 0)
	Do $$$AssertStatusOK(sc, "the request is carried out")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("Ens.Response"), "the answer is an Ens.Response, which tells BreakFeedIn the batch was sent")
	Do $$$AssertEquals(..Calls(), "audit,send", "the audit comes before the send, and each happens once")
	Set data = {}.%FromJSON(^OcuTalonTest("PartnerTriggerProbe", "calls", 1, "data"))
	Set expected = {"action": "Break the feed", "target": "OcuTalon.Demo.Orders.Production (MM/DD/YYYY)", "result": "50 orders", "counts": {"orders": 50}, "approvalRef": "", "irisUser": (session.IrisUser), "sessionRef": (ref), "channel": "web"}
	Do $$$AssertEquals(data.%ToJSON(), expected.%ToJSON(), "the data is the Action shape, with the session's user, session and channel")
	Do $$$AssertEquals(data.%GetTypeOf("counts"), "object", "counts is an object")
	Do $$$AssertEquals(data.counts.%GetTypeOf("orders"), "number", "its value is a number")
	Do $$$AssertEquals(^OcuTalonTest("PartnerTriggerProbe", "calls", 1, "description"), "Break the feed: 50 orders", "the description of the entry")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Redact).Text(data.%ToJSON()), data.%ToJSON(), "the redaction leaves the data unchanged: it holds no secret")
	Do $$$AssertEquals(^OcuTalonTest("PartnerTriggerProbe", "calls", 2, "traceRef"), session.TraceRef, "the send gets the session's TraceRef")
	Do $$$AssertEquals(session.IrisUser, "zzpartner"_..Number, "the user is the session row's IrisUser")
	Set record = ##class(OcuTalon.Bridge.Audit).Record("Action", data)
	Do $$$AssertTrue($SYSTEM.Status.IsOK(record) || ($SYSTEM.Status.GetErrorText(record) '[ "refuses"), "Bridge.Audit.Record takes the shape (it does not refuse it)")
	Kill ^OcuTalonTest("PartnerTriggerProbe")
	Do $$$AssertTrue($SYSTEM.Status.IsError(##class(OcuTalon.Bridge.Audit).Record("Action", {"action": "Break the feed"})), "control: Record refuses data of another shape")
}

/// Row 10 (the failure): a failed audit write is an error status and nothing is sent.
Method TestFailedAuditSendsNothing()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpartner"_..Number)
	Set ^OcuTalonTest("PartnerTriggerProbe", "answer", "audit") = "error"
	Set sc = ..Ask(ref, "web")
	Do $$$AssertStatusNotOK(sc, "the request is an error status")
	Do $$$AssertEquals(..Calls(), "audit", "the audit was tried, and nothing was sent")
}

/// An unknown session, another class and no request are an error status: no audit entry and no send.
Method TestRefusedSendsNothing()
{
	Do $$$AssertStatusNotOK(..Ask(##class(OcuTalon.Bridge.Ids).NewRef(), "web"), "a session with no row is refused")
	Do $$$AssertStatusNotOK(..Ask("", "web"), "an empty session is refused")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Demo.PartnerTriggerProbe", .sc)
	Set other = ##class(Ens.StringRequest).%New()
	Set other.StringValue = ##class(OcuTalon.Test.Data.Fixture).Session("zzpartner"_..Number)
	Do $$$AssertStatusNotOK(probe.OnMessage(other, .response), "another class is refused")
	Do $$$AssertStatusNotOK(probe.OnMessage("", .response), "no request is refused")
	Do $$$AssertEquals(..Calls(), "", "no audit and no send")
}

/// Row 9: a send that fails is an error status, after the audit.
Method TestFailedSendIsAnError()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpartner"_..Number)
	Set ^OcuTalonTest("PartnerTriggerProbe", "answer", "send") = "error"
	Do $$$AssertStatusNotOK(..Ask(ref, "web"), "the request is an error status")
	Do $$$AssertEquals(..Calls(), "audit,send", "the audit came first")
}

/// The batch: 50 orders in the partner's second format; Send is the one method that switches namespace, and it reads the constants before.
Method TestBatch()
{
	Do $$$AssertEquals(##class(OcuTalon.Demo.PartnerTrigger).#COUNT, 50, "COUNT is 50")
	Do $$$AssertEquals(##class(OcuTalon.Demo.PartnerTrigger).#DATEFORMAT, $ListGet($ListFromString(##class(OcuTalon.Demo.Orders.Partner).#FORMATS), 2), "DATEFORMAT is the partner's second format")
	Do $$$AssertEquals(##class(OcuTalon.Demo.PartnerTrigger).#DATEFORMAT, "MM/DD/YYYY", "which is MM/DD/YYYY")
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId("OcuTalon.Demo.PartnerTrigger")
	Set switching = ""
	For i = 1:1:definition.Methods.Count() {
		Set method = definition.Methods.GetAt(i)
		Set code = method.Implementation.Read(1000000)
		If code [ "New $NAMESPACE" Set switching = switching_$Select(switching = "": "", 1: ",")_method.Name
		If method.Name = "Send" {
			Set read = $Find(code, "..#COUNT")
			Do $$$AssertTrue(read && (read < $Find(code, "Set $NAMESPACE")), "Send reads COUNT before it switches")
			Do $$$AssertTrue(code [ "Partner).Send(count, format, traceRef, """")", "Send asks the partner for COUNT orders in DATEFORMAT, tagged with the TraceRef and with no order date")
		}
	}
	Do $$$AssertEquals(switching, "Send", "Send is the one method that switches namespace")
}

/// Sends the operation a SendOrders for the session, on a shadow instance of the probe; the status of its answer, and the answer in response.
Method Ask(ref As %String, channel As %String, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set response = ""
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Demo.PartnerTriggerProbe", .sc)
	If '$IsObject(probe) Quit sc
	Set request = ##class(OcuTalon.Demo.Msg.SendOrders).%New()
	Set request.SessionRef = ref
	Set request.Channel = channel
	Quit probe.OnMessage(request, .response)
}

/// The seam calls in order, as "audit,send".
ClassMethod Calls() As %String [ Private ]
{
	Set text = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("PartnerTriggerProbe", "calls", n), 1, call)
		Quit:n=""
		Set text = text_$Select(text = "": "", 1: ",")_call
	}
	Quit text
}

}
