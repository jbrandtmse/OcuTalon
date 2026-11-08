/// End-to-end tests of the GotIt command over the running production (Story 12.12; AD-1, AD-4, AD-14, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (InProduction). A fixture caller submits GotIt through Commands.Submit as TelegramIn does (origin telegram), CommandsIn sends it to the real
/// SessionOps, and the tests read what the real consumers see: the Handled table, the hops from SessionOps to Notify, and
/// the Delivery rows that Notify's generic route makes for kind handled (WebChatOut; SimPhoneOut when demo mode is on).
///   - TestPressThroughTheProduction: a press of the session's own tell-now Decision (origin telegram, channel telegram) is Ok 1, handled; it writes one
///     Handled row {Ref, session, telegram} and sends one Notification of kind handled with the Ref and no text to Notify, which routes it to the web
///     chat (and the phone in demo mode), where it is a bare Delivery row, with no card, no phone message and no event; a second press from the page (origin web_user, channel web) is Ok 1,
///     already_handled and changes nothing, sends nothing and leaves the first row's channel;
///   - TestRefusalsThroughTheProduction: another session's tell-now Ref, a Decision that is not tell-now and a Ref that names nothing are Ok 0,
///     not_found; an origin that CommandsIn does not route to SessionOps for GotIt (timer) is Ok 0, not_allowed; none writes a row or sends a Notification.
/// The Handled rows are removed in OnAfterAllTests, and the sessions, their Decisions and Delivery rows are removed with the fixture rows.
Class OcuTalon.Test.Core.GotItProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzgotitprod";

/// The Refs whose Handled rows the run may have made, comma-separated.
Property HandledRefs As %String(MAXLEN = "");

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..HandledRefs, ",") {
		Set ref = $Piece(..HandledRefs, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Handled).%DeleteId(row.%Id())
		}
	}
	Quit ##super()
}

/// The press of Got it for the session's own tell-now Decision, then a second press from the page.
Method TestPressThroughTheProduction()
{
	If '..Guard() Quit
	Set session = ..Session("a")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ..Decision(session, "tellnow")
	Set result = ..Press("telegram", session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "the press is Ok 1, handled: "_result.Message)
	Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "a Handled row exists")
	If $IsObject(row) Do $$$AssertEquals(row.Ref_"|"_row.SessionRef_"|"_row.Channel, ref_"|"_session_"|telegram", "it holds the Ref, the session and the channel telegram")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "SessionOps", "Notify", 1, ..#WAIT), "Notify has handled the Notification of SessionOps")
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "SessionOps", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one Notification goes from SessionOps to Notify")
	If sent.%Size() = 1 {
		Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
		Do $$$AssertEquals(notification.SessionRef_"|"_notification.Kind_"|"_notification.DecisionRef_"|"_notification.CatalogKey_"|"_notification.Slots, session_"|handled|"_ref_"||{}", "of kind handled, with the Ref and no text")
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Notification of Notify")
	If ##class(OcuTalon.Core.Rule.Functions).DemoOn() Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "SimPhoneOut", 1, ..#WAIT), "in demo mode, SimPhoneOut has handled it too")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Set channels = ""
	For i = 1:1:rows.Count() {
		Set delivery = rows.GetAt(i)
		Set channels = channels_$Select(channels = "": "", 1: ",")_delivery.Channel
		Do $$$AssertEquals(delivery.Kind_"|"_delivery.DecisionRef_"|"_delivery.Text_"|"_delivery.ChannelMessageId, "handled|"_ref_"||", delivery.Channel_": a bare row: handled, the Ref, no text and no message id")
	}
	Set web = 0
	For i = 1:1:rows.Count() If rows.GetAt(i).Channel = "web" Set web = web + 1
	Do $$$AssertEquals(web, 1, "the web chat recorded exactly one Delivery row (rows: "_channels_")")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "the chat shows no card")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size(), 0, "and no notification event is published")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 0, "and the phone shows nothing")

	Set at = $Select($IsObject(row): row.HandledAt, 1: "")
	Set result = ..Press("web_user", session, ref, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_handled", "a second press from the page is Ok 1, already_handled")
	Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
	Do $$$AssertEquals(row.Channel_"|"_row.HandledAt, "telegram|"_at, "the first row is unchanged")
	Do $$$AssertEquals(..Sent(trace), 1, "and no second Notification was sent")
}

/// Refusals change nothing: another session's tell-now Ref, a Decision that is not tell-now and a Ref that names nothing are not_found; a timer origin
/// is not_allowed.
Method TestRefusalsThroughTheProduction()
{
	If '..Guard() Quit
	Set a = ..Session("ra")
	Set b = ..Session("rb")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	Set ownB = ..Decision(b, "tellnow")
	Set actA = ..Decision(a, "act")
	Set ownA = ..Decision(a, "tellnow")
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..HandledRefs = ..HandledRefs_","_unknown
	For case = $ListBuild("telegram", a, ownB, "not_found", "another session's tell-now"), $ListBuild("telegram", a, actA, "not_found", "an act Decision"), $ListBuild("web_user", a, unknown, "not_found", "a Ref that names nothing"), $ListBuild("timer", a, ownA, "not_allowed", "a timer origin") {
		Set result = ..Press($List(case, 1), $List(case, 2), $List(case, 3), "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|"_$List(case, 4), $List(case, 5)_": Ok 0, "_$List(case, 4))
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(ownB) + ##class(OcuTalon.Data.Handled).RefIndexExists(actA) + ##class(OcuTalon.Data.Handled).RefIndexExists(unknown) + ##class(OcuTalon.Data.Handled).RefIndexExists(ownA), 0, "no Handled row was written")
	Do $$$AssertEquals(..Sent(traceA) + ..Sent(traceB), 0, "and no Notification was sent")
	Set result = ..Press("telegram", a, ownA, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "control: the session's own tell-now Decision is handled")
}

/// --- helpers ---
/// A decide Decision of the owner with the outcome, recorded for the clean-up (and its Handled row, if any). Returns its Ref.
Method Decision(owner As %String, outcome As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Outcome": (outcome)})
	Set ..Refs = ..Refs_","_ref
	Set ..HandledRefs = ..HandledRefs_","_ref
	Quit ref
}

/// Submits a GotIt through Commands.Submit with the origin and returns the CommandResult.
Method Press(origin As %String, session As %String, ref As %String, channel As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.GotIt).%New()
	Set command.SessionRef = session
	Set command.Ref = ref
	Set command.Channel = channel
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
	Do $$$AssertStatusOK(sc, "Submit returns OK")
	Quit result
}

/// The number of Notifications that SessionOps has sent Notify in the SuperSession.
Method Sent(trace As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "SessionOps", "Notify").%Size()
}

}
