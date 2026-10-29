/// Tests of SimMailboxOut (Story 4.6; AD-4, AD-12, AD-14, AD-32, AD-33). The handler tests are safe on a slot: no production runs
/// there, so they call OnOutbound on a shadow instance of OcuTalon.Channel.SimMailbox.Out, with fixture sessions from
/// Test.Data.Fixture. TestThroughProduction needs the running OcuTalon.Production and runs in throwaways and CI only (Rule 21);
/// where no production runs it is skipped.
///   - TestSent: an Outbound becomes one SimMessage (Kind mailbox, direction out, Sender OcuTalon, the first line as Subject, the
///     text, no ItemId), one mailbox Delivery row (the SimMessage's Ref as ChannelMessageId, the DecisionRef, no kind and no
///     text) and one mailbox event whose payload is the message's;
///   - TestCatalogText: an Outbound with a CatalogKey carries the catalog's render for the mailbox;
///   - TestNotASession: an owner that is not a session records nothing, publishes nothing and logs one warning;
///   - TestRenderError: a text that cannot be rendered is an error with no row and no event;
///   - TestSaveFailureKeepsNothing: a Delivery row that cannot be saved leaves no message and no event;
///   - TestPublishFailure: an event that cannot be published is logged and both rows stay;
///   - TestThroughProduction: in the running production an Outbound sent to SimMailboxOut gives the row within 5 seconds, a
///     completed request with body class OcuTalon.Msg.Outbound, and no body property that names the simulation.
/// The run's number is n from ^OcuTalonTest("SimMailboxOut","n") (never reset).
Class OcuTalon.Test.Demo.SimMailboxOut Extends %UnitTest.TestCase
{

/// Seconds that TestThroughProduction waits for the message.
Parameter WAIT = 5;

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The SuperSessions of the messages that TestThroughProduction sent.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SimMailboxOut", "n"))
	Set ..Refs = ""
	Set ..Supers = []
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Supers.%Size() > 0 Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// Sent mail (matrix row 6): the message, its Delivery row and the event.
Method TestSent()
{
	Set session = ..Session("sent")
	Set other = ..Session("sentother")
	Set outbound = ..Outbound(session, "zz Hello"_$Char(10)_"zz second")
	Set outbound.DecisionRef = "ZzDecision"_..Number
	Do $$$AssertStatusOK(..Out().OnOutbound(outbound, .response), "the message is delivered")
	Do $$$AssertEquals($IsObject($Get(response)), 0, "with no response")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentMail(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "the session has one mailbox row")
	If rows.Count() '= 1 Quit
	Set row = rows.GetAt(1)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Kind_"|"_row.Direction_"|"_row.Sender_"|"_row.Subject_"|"_row.Text_"|"_row.ItemId, session_"|mailbox|out|OcuTalon|zz Hello|zz Hello"_$Char(10)_"zz second|", "its session, kind, direction, sender, subject (the first line), text and no item")
	Do $$$AssertTrue(row.Ref ? 22(1AN,1"-",1"_"), "its Ref is a new Ref: "_row.Ref)
	Do $$$AssertEquals(row.CreatedAt, $Extract(row.CreatedAt, 1, 19)_"Z", "created to the second, in UTC")
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "one Delivery row")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.DecisionRef_"|"_delivery.Kind_"|"_delivery.Text_"|"_delivery.ApprovalRef, "mailbox|"_row.Ref_"|ZzDecision"_..Number_"|||", "its channel, the message's Ref, the decision, and no kind, text or approval")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "mailbox")
	Do $$$AssertEquals(events.%Size(), 1, "one mailbox event is published")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.direction_"|"_payload.itemId_"|"_payload.sender_"|"_payload.subject_"|"_payload.text_"|"_payload.unread, row.Ref_"|out||OcuTalon|zz Hello|"_row.Text_"|1", "its ref, direction, sender, subject, text and unread")
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Payload.Mailbox).FromRow(row).%JSONExportToString(.json), "the payload exports")
		Do $$$AssertEquals(payload.%ToJSON(), ##class(%DynamicObject).%FromJSON(json).%ToJSON(), "it is the payload that FromRow makes of the message")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentMail(other, 10).Count()_"|"_##class(OcuTalon.Test.Core.Observe).Events(other, "mailbox").%Size(), "0|0", "another session has no mail and no event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "and the phone has no message")
}

/// A CatalogKey is rendered for the mailbox channel; the Text is ignored then.
Method TestCatalogText()
{
	Set session = ..Session("catalog")
	Set slots = {"whatHappened": "Disk almost full", "reason": "you asked to hear about disk space"}
	Set outbound = ..Outbound(session, "zz ignored")
	Set outbound.CatalogKey = "notice.tellNow"
	Set outbound.Slots = slots.%ToJSON()
	Do $$$AssertStatusOK(..Out().OnOutbound(outbound, .response), "the message is delivered")
	Set expected = ##class(OcuTalon.Msg.Catalog).RenderAt("notice.tellNow", slots.%ToJSON(), "mailbox", "2030-01-01T12:00:00Z", 0)
	Do $$$AssertEquals(expected, "Disk almost full"_$Char(10)_"Why now: you asked to hear about disk space", "the mailbox render")
	Set rows = ##class(OcuTalon.Data.Ownership).RecentMail(session, 10, .sc)
	Do $$$AssertEquals(rows.Count(), 1, "one mailbox row")
	If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).Text_"|"_rows.GetAt(1).Subject, expected_"|Disk almost full", "with the rendered text, and its first line as the subject")
}

/// A message for an owner that is not a session records no row and publishes no event, and logs one warning each; the status is
/// OK, so that the operation does not retry.
Method TestNotASession()
{
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set owners = $ListBuild("instance", "eval", "", unknown, "Instance")
	Set position = 0
	While $ListNext(owners, position, owner) {
		Set before = ##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner)
		Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "IsSession", "SimMailboxOut dropped a message")
		Do $$$AssertStatusOK(..Out().OnOutbound(..Outbound(owner, "zz Hello"), .response), "'"_owner_"': the message is dropped with an OK status")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner), before, "'"_owner_"': no Delivery row")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "IsSession", "SimMailboxOut dropped a message") - warned, 1, "'"_owner_"': one warning")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", owner)
		Do result.%Next()
		Do $$$AssertEquals(+result.%GetData(1), 0, "'"_owner_"': no message")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(unknown, "mailbox").%Size(), 0, "no event is published")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "IsSession", "SimMailboxOut dropped a message")
}

/// A text that cannot be rendered is an error status with no message, no Delivery row and no event.
Method TestRenderError()
{
	Set session = ..Session("render")
	Set cases = $ListBuild($ListBuild("an unknown key", "zz.noSuchKey", "{""zz"":""slot""}"), $ListBuild("a missing slot", "notice.tellNow", "{""whatHappened"":""zz summary""}"), $ListBuild("slots that are not JSON", "notice.tellNow", "not json"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set outbound = ..Outbound(session, "zz text")
		Set outbound.CatalogKey = $List(case, 2)
		Set outbound.Slots = $List(case, 3)
		Do $$$AssertStatusNotOK(..Out().OnOutbound(outbound, .response), $List(case, 1)_" is an error")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentMail(session, 10).Count(), 0, $List(case, 1)_": no message is recorded")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, $List(case, 1)_": no Delivery row")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "mailbox").%Size(), 0, $List(case, 1)_": and no event is published")
	}
}

/// The message and its Delivery row are saved together: when the Delivery row cannot be saved (a DecisionRef longer than the column
/// allows), the status is an error and the message is not kept either, and no event is published.
Method TestSaveFailureKeepsNothing()
{
	Set session = ..Session("rollback")
	Set outbound = ..Outbound(session, "zz Hello")
	Set outbound.DecisionRef = $Translate($Justify("", 30), " ", "A")
	Do $$$AssertStatusNotOK(..Out().OnOutbound(outbound, .response), "a Delivery row that cannot be saved is an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentMail(session, 10).Count(), 0, "the message is not kept")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and there is no Delivery row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "mailbox").%Size(), 0, "and no event is published")
	Do $$$AssertEquals($TLevel, 0, "and no transaction is left open")
}

/// An event that cannot be published (Publish refuses inside an open transaction) is logged as one warning, and both rows stay;
/// the delivery is still OK.
Method TestPublishFailure()
{
	Set session = ..Session("publish")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	TSTART
	Try {
		Set sc = ..Out().OnOutbound(..Outbound(session, "zz Hello"), .response)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	TCOMMIT
	Do $$$AssertStatusOK(sc, "the delivery is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentMail(session, 10).Count(), 1, "the message is saved")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and so is its Delivery row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "mailbox").%Size(), 0, "no event is published")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Announce", "SimMailboxOut could not publish"), 1, "one warning is logged")
	Do $$$AssertTrue(text [ "transaction", "and says why: "_text)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Announce", "SimMailboxOut could not publish")
}

/// In the running production an Outbound sent to SimMailboxOut from a SimMailboxIn host gives the row within WAIT seconds; the
/// request header has body class OcuTalon.Msg.Outbound, is completed with no error, and no body property names the simulation
/// (matrix row 15).
Method TestThroughProduction()
{
	If '##class(Ens.Director).IsProductionRunning(.name) {
		Do $$$AssertSkipped("No production runs in "_$Namespace_": this case runs in throwaways and CI only (Rule 21)")
		Quit
	}
	Set session = ..Session("production")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do ..Supers.%Push(trace)
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	Do $$$AssertStatusOK(sc, "a business service host is made")
	If $$$ISERR(sc) Quit
	Set service.%SuperSession = trace
	Do $$$AssertStatusOK(service.SendRequestAsync("SimMailboxOut", ..Outbound(session, "zz Hello"_$Char(10)_"zz second")), "the Outbound is sent to SimMailboxOut")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentMail(session, 10)
		If (rows.Count() > 0) || ($ZHorolog > end) Quit
		Hang 0.1
	}
	Do $$$AssertEquals(rows.Count(), 1, "the row is there within "_..#WAIT_" seconds")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "SimMailboxIn", "SimMailboxOut", 1, 20), "SimMailboxOut has handled the Outbound")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "SimMailboxIn", "SimMailboxOut")
	Do $$$AssertEquals(sent.%Size(), 1, "one request goes to SimMailboxOut")
	If sent.%Size() = 1 Do $$$AssertEquals(sent.%Get(0).bodyClass_"|"_sent.%Get(0).status_"|"_sent.%Get(0).isError, "OcuTalon.Msg.Outbound|9|0", "its body is an Outbound, and it is completed with no error")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.SimMailboxIn).Reveals(headers), "", "no message body names the simulation")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "mailbox", 1, ..#WAIT).%Size(), 1, "and one mailbox event is published")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzmailout"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the operation.
Method Out() As OcuTalon.Channel.SimMailbox.Out [ Private ]
{
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimMailbox.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the operation is made")
	Quit out
}

/// An Outbound for the owner with the text.
Method Outbound(owner As %String, text As %String) As OcuTalon.Msg.Outbound [ Private ]
{
	Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
	Set outbound.SessionRef = owner
	Set outbound.Text = text
	Quit outbound
}

}
