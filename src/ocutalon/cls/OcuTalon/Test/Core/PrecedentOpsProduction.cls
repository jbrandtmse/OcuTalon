/// End-to-end test of the precedent path over the running production (Story 41.2; AD-1, AD-4, AD-21; FR-72). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (InProduction). A tell-now email goes through the real mail path (a SimMailboxIn host created as Web.Api creates it, then Intake and the real Decide),
/// and the test reads what the real consumers see. A throwaway has no model key, so the real Decide answers with its fallback no_key, a decide Decision with the
/// outcome tellnow (the marker [[mock:mail-tell-now]] in the body makes the CI mock answer tellnow where a key is set).
///   - TestNoiseThroughTheProduction: the session's decide Decision of the email, outcome tellnow, leaves no Precedent row (a decision writes none); Commands.Submit of a
///     MarkNoise (origin web_user, through CommandsIn to the real PrecedentOps) is marked, and the row is keyed by the sender's address with channel mailbox, which
///     proves ItemOf on the real TraceSessionId; Precedent.Similar and Ownership.Precedents return the row; a repeat is already_marked; and Commands.Submit of an
///     EndSession (the real SessionOps.End) leaves the session with no row.
/// The sessions, their messages and the Decisions that the test adopts are removed with the fixture rows; the Precedent rows of the sessions are removed in OnAfterAllTests.
Class OcuTalon.Test.Core.PrecedentOpsProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzprecprod";

/// Seconds to wait for the real Decide to record its Decision.
Parameter DECIDEWAIT = 60;

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Data.Precedent).DropSession($Piece(..Sessions, ",", i))
	}
	Quit ##super()
}

/// A tell-now email through the real mail path, then MarkNoise, a repeat and the sign-out through the real production.
Method TestNoiseThroughTheProduction()
{
	If '..Guard() Quit
	Set session = ..Session("noise")
	Set mail = ##class(OcuTalon.Channel.SimMailbox.Mail).%New()
	Set mail.SessionRef = session
	Set mail.Sender = "Zz Prec <Zz.Prec@Example.com>"
	Set mail.Subject = "Zz Prec subject"
	Set mail.Text = "Zz Prec body [[mock:mail-tell-now]]"
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	Do $$$AssertStatusOK(sc, "SimMailboxIn is created in this process")
	If $SYSTEM.Status.IsError(sc) Quit
	Set sc = service.ProcessInput(mail, .output)
	Do $$$AssertStatusOK(sc, "the email is accepted")
	If $SYSTEM.Status.IsError(sc) Quit
	Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen({}.%FromJSON(output).ref)
	Do $$$AssertTrue($IsObject(message), "the email is recorded")
	If '$IsObject(message) Quit
	Set decision = ..WaitDecision(session, message.ItemId)
	Do $$$AssertTrue($IsObject(decision), "the real Decide recorded a decide Decision of the Item within "_..#DECIDEWAIT_" seconds")
	If '$IsObject(decision) Quit
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Adopt(decision)
	Set ..Refs = ..Refs_","_ref
	Do $$$AssertEquals(decision.OwnerRef_"|"_decision.Outcome, session_"|tellnow", "the Decision is the session's own tell-now")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 1, ..#WAIT)
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session) >= 1, "the notice of the tell-now decision was delivered before the absence is checked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has(session)_"|"_##class(OcuTalon.Data.Precedent).SourceRefIndexExists(decision.Ref), "0|0", "the real decision wrote no Precedent row")

	Set command = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
	Set command.SessionRef = session
	Set command.DecisionRef = decision.Ref
	Set command.Channel = "web"
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertStatusOK(sc, "Submit returns OK")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "MarkNoise is marked: "_result.Message)
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(decision.Ref)
	Do $$$AssertTrue($IsObject(row), "the real PrecedentOps wrote one row under the DecisionRef")
	If $IsObject(row) {
		Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.MatchKey_"|"_row.Answer, session_"|mailbox|zz.prec@example.com|noise", "keyed by the sender's address, which proves ItemOf on the real TraceSessionId")
		Do $$$AssertEquals(row.Summary_"|"_row.Outcome_"|"_row.AnsweredChannel, decision.Summary_"|tellnow|web", "with the Decision's summary and outcome, answered on the web")
	}
	Set similar = ##class(OcuTalon.Data.Precedent).Similar(session, "mailbox", "zz.prec@example.com")
	Do $$$AssertEquals(similar.%Size(), 1, "Precedent.Similar returns it")
	Set list = ##class(OcuTalon.Data.Ownership).Precedents(session)
	Do $$$AssertEquals(list.Count(), 1, "Ownership.Precedents returns it")

	Set again = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
	Set again.SessionRef = session
	Set again.DecisionRef = decision.Ref
	Set again.Channel = "phone"
	Set sc = ##class(OcuTalon.Core.Commands).Submit(again, "web_user", .result)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_marked", "a repeat is already_marked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedents(session).Count(), 1, "and there is still one row")

	Set end = ##class(OcuTalon.Msg.Command.EndSession).%New()
	Set end.SessionRef = session
	Set sc = ##class(OcuTalon.Core.Commands).Submit(end, "web_user", .result)
	Do $$$AssertStatusOK(sc, "Submit of the EndSession returns OK")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "the real SessionOps.End answers ended: "_result.Message)
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Has(session)_"|"_##class(OcuTalon.Data.Ownership).Precedents(session).Count(), "0|0", "the session has no row any more")
}

/// The session's own decide Decision of the Item once it is there, opened afresh; after DECIDEWAIT seconds, "".
Method WaitDecision(session As %String, itemId As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set end = $ZHorolog + ..#DECIDEWAIT
	Set row = ""
	For {
		Set row = ##class(OcuTalon.Data.Ownership).DecisionOfItem(itemId, session)
		If $IsObject(row) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit row
}

}
