/// The webhook endpoint's 503 with the REAL hand-over (Story 35.3 QA, DW-1132): Test.Web.Hook drives the 503 through the probe's own failing Hand, and this class
/// stops the production and lets Web.Hook.Hand run as the product has it (Ens.Director CreateBusinessService of WebhookIn), through Test.Web.HookProbe mode "real".
/// THIS CLASS STOPS THE PRODUCTION AND STARTS IT AGAIN, SO IT RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like Test.Web.Hook, whose rejections write real
/// audit entries. The production is started again after every test, also after a failure (OnAfterOneTest).
///   - TestProductionStopped: with OcuTalon.Production stopped, a valid event (right secret, JSON body) answers 503 with no body, nothing is written to
///     WebhookIn's message headers, the hour's accepted count is given back, the console line names the Ref and "WebhookIn unavailable" and holds neither the
///     secret nor the body, no rejection is counted and no audit entry is written; and the production runs again at the end.
Class OcuTalon.Test.Web.HookProductionStopped Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.HookProbe";

/// The secret of the fixture webhook.
Parameter SECRET = "zz-hook-stopped-0123456789";

/// The saved online-demo flag.
Property SavedOnline As %String;

/// The Ref of the fixture session, and of its webhook.
Property Session As %String;

Property Ref As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..Session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..Session, "zz stopped "_$Random(1000000), ..#SECRET)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If '##class(Ens.Director).IsProductionRunning() Do ##class(OcuTalon.Install.Step.Production).Start()
	Kill ^OcuTalonP.WebhookC("a", ..Ref)
	Kill ^OcuTalonP.WebhookC("r", ..Ref)
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

/// A valid event while the production is stopped is 503 through the real Hand, with nothing handed over and nothing kept.
Method TestProductionStopped()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set ^OcuTalonTest("HookProbe", "mode") = "real"
	If '##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Start(), "the production runs to begin with")
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.Heartbeat).SettleScheduler(), "the scheduler is settled before the production stops (DW-28)")
	Set sc = ##class(Ens.Director).StopProduction(10, 0)
	Do $$$AssertStatusOK(sc, "the production stops")
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 0, "it does not run")
	If $$$ISERR(sc) Quit
	Set headers = ..WebhookInHeaders()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set written = ..Post(..Ref, ..#SECRET, "{""secret-body"":1}", .response)
	Do $$$AssertEquals(response.Status, "503 Service Unavailable", "the real hand-over answers 503 while the production is stopped")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "the probe's own hand-over was not used")
	Do $$$AssertEquals(..WebhookInHeaders(), headers, "nothing became a WebhookIn message")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 0, "the hour's accepted count is given back")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("r", ..Ref)), 0, "a 503 is not counted as a rejection")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", ..Ref).%Size(), 0, "and writes no audit entry")
	Set logs = ..Logs()
	Do $$$AssertTrue((logs [ ..Ref) && (logs [ "WebhookIn unavailable"), "the console line names the Ref and the service")
	Do $$$AssertTrue((logs '[ ..#SECRET) && (logs '[ "secret-body"), "and holds neither the secret nor the body")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Start(), "the Production step starts the production again")
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 1, "and it runs")
}

/// --- helpers ---
/// The number of message headers that WebhookIn has sent.
Method WebhookInHeaders() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) c FROM Ens.MessageHeader WHERE SourceConfigName = ?", "WebhookIn")
	Do rs.%Next()
	Quit +rs.%Get("c")
}

/// Calls Receive of the probe with the secret and body; response is the %response.
Method Post(ref As %String, secret As %String, body As %String, Output response) As %String [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "secret") = secret
	Set ^OcuTalonTest("HookProbe", "body") = body
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/hook/", "POST")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.Status = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "Receive", ref)
	Do $$$AssertStatusOK(sc, "Receive returns OK")
	Set response = %response
	Quit written
}

/// The console lines of the probe, joined with line feeds.
Method Logs() As %String [ Private ]
{
	Set text = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("HookProbe", "logs", n), 1, line)
		Quit:n=""
		Set text = text_line_$Char(10)
	}
	Quit text
}

}
