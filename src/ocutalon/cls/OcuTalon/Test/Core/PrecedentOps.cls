/// Tests of OcuTalon.Core.PrecedentOps (Story 41.2; AD-1, AD-21 as amended 2026-11-08, AD-22; FR-72), over a shadow instance of Test.Core.PrecedentOpsProbe, which
/// answers the Item of a Decision from the test and can fail the save. Safe on a slot: no production is needed (the real EvalIn switch row is written and put back
/// by the tests that need it). The sessions, Decisions, approval requests and incidents are fixture rows; every test removes its own sessions' rows, its seeded runs
/// and its fixture rows in OnAfterOneTest. The test gives the probe the header whose SourceConfigName is the sender.
///   - TestMarkNoise: the Noise marked row: one row with the owner, Channel mailbox, the key, the Decision's Summary and Outcome, Answer noise, AnsweredChannel phone,
///     SourceRef the DecisionRef, no EvalRunRef; an act Decision too;
///   - TestNoiseRepeat: a repeat, and a lost race on the unique SourceRef, answer already_marked with the first row's Ref and time, and no second row;
///   - TestNotMarkable: another session's decision, a digest and an ignore decision, a turn decision, the decision of a user Item, an Item with no key, a DecisionRef
///     that is no ref and an empty session are not_found and write nothing;
///   - TestItemPurged: a Decision whose Item is gone is too_old and writes nothing;
///   - TestRealItemOf: the real ItemOf finds the Item of the Decision's trace session by ItemId, and no other;
///   - TestSaveFailure: a failed save is failed, with no row;
///   - TestForget: Forget deletes the session's own row at once (Similar and Ownership lose it); another session's row and a seeded row are not_found and stay;
///   - TestApprovalAnswers: the Approval answers row: a fix and a tool_call, approved and rejected, with the AnsweredAt of the request and the AnsweredChannel;
///   - TestApprovalRefused: a setting request, a bad Action, an unknown request and session, another session's request and a repeat (with the stored Action, or another) record nothing new;
///   - TestAnswerMustMatch: an Action that differs from the request's stored answer, and a request that is pending, expired or cancelled, are not_recorded with no row; an
///     executing and a done request answered as the message says are recorded;
///   - TestEndedSession: on the online demo a session whose ResumeHash is cleared (sign-out) is not_found for a MarkNoise and not_recorded for a RecordPrecedent, with no row; a
///     session that holds its ResumeHash, and any session off the online demo, write as before;
///   - TestSenders: every message class from every other sender, and each verb with every other origin, is not_allowed with one warning and writes nothing;
///   - TestUnknownClass: an Item, an ItemDecision, a GotIt and a message that is not an object answer an error status and write nothing;
///   - TestSeed and TestSeedRefused: SeedPrecedent from EvalIn with EvalOn 1 writes an eval-owned row; every other combination writes nothing;
///   - TestRemoveSeeded: RemoveSeededPrecedents deletes the rows of that run only, under the same guards;
///   - TestPersonBesideRun: seeded rows beside a person's row are invisible to the person's Similar, Ownership.Precedents and Ownership.Precedent;
///   - TestEvalOn: EvalOn follows the System Default Setting row (1, 0, missing);
///   - TestEndSession: EndSession from SessionOps deletes the session's rows and no other session's or seeded row;
///   - TestDecisionRecordedWritesNoRow: BridgeSink.OnEvent for a tell-now decide Decision leaves no row.
Class OcuTalon.Test.Core.PrecedentOps Extends %UnitTest.TestCase
{

/// The probe, a subclass of the operation.
Parameter PROBE = "OcuTalon.Test.Core.PrecedentOpsProbe";

/// The id of the System Default Setting row that EvalOn reads.
Parameter EVALROW = "OcuTalon.Production||EvalIn||*||Enabled";

/// The run's number.
Property Number As %Integer;

/// The count of fixtures made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The owners of Precedent rows that the test may have made (sessions and runs), comma-separated.
Property Owners As %String(MAXLEN = "");

/// The Ens.MessageHeader and Item rows of TestRealItemOf, as ids of the form <header>|<item>, comma-separated.
Property Messages As %String(MAXLEN = "");

/// 1 when the EvalIn setting row existed before the tests, and its value.
Property EvalDefined As %Boolean;

Property EvalValue As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PrecedentOps", "n"))
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(..#EVALROW)
	Set ..EvalDefined = $IsObject(row)
	Set ..EvalValue = $Select($IsObject(row): row.SettingValue, 1: "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutBackEval()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Owners, ",") {
		Set owner = $Piece(..Owners, ",", i)
		If owner = "" Continue
		Do ##class(OcuTalon.Data.Precedent).DropSession(owner)
		Do ##class(OcuTalon.Data.Precedent).RemoveRun(owner)
	}
	Set ..Owners = ""
	For i = 1:1:$Length(..Messages, ",") {
		Set pair = $Piece(..Messages, ",", i)
		If pair = "" Continue
		Do ##class(Ens.MessageHeader).%DeleteId($Piece(pair, "|", 1))
		Do ##class(OcuTalon.Msg.Item).%DeleteId($Piece(pair, "|", 2))
	}
	Set ..Messages = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ..PutBackEval()
	Quit $$$OK
}

/// One row for a MarkNoise of the session's own tell-now Decision from CommandsIn with origin web_user: the owner, the Item's channel, the key (the sender's
/// address), the Decision's Summary and Outcome, the answer noise, where it was pressed, and the Decision's Ref as the source; none for an eval run.
Method TestMarkNoise()
{
	Set session = ..Session("mark")
	Set decision = ..Decision(session, "decide", "tellnow", "Zz mail from a sender")
	Set probe = ..Probe("CommandsIn")
	Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set result = ..Mark(probe, session, decision, "phone")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "Ok 1, marked")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(decision)
	Do $$$AssertTrue($IsObject(row), "the row is saved under the DecisionRef")
	Do $$$AssertEquals(result.Ref, row.Ref, "the result carries the row's Ref")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(result.Data).answeredAt, row.AnsweredAt, "Data holds answeredAt")
	Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.MatchKey, session_"|mailbox|zz.a@example.com", "the owner, the Item's channel and the sender's address")
	Do $$$AssertEquals(row.Summary_"|"_row.Outcome_"|"_row.Answer, "Zz mail from a sender|tellnow|noise", "the Decision's Summary and Outcome, and the answer")
	Do $$$AssertEquals(row.AnsweredChannel_"|"_row.SourceRef_"|"_row.EvalRunRef, "phone|"_decision_"|", "pressed on the phone, the DecisionRef as the source, no run")
	Do $$$AssertTrue((before '] row.AnsweredAt) && (row.AnsweredAt '] ##class(OcuTalon.Data.Time).AddSeconds(before, 5)), "AnsweredAt is now: "_row.AnsweredAt)
	Do $$$AssertEquals(..Owned(session), 1, "and it is the only row of the session")
	Set act = ..Decision(session, "decide", "act")
	Set probe.Item = ..NewItem(session, "webhook", " Src ")
	Set result = ..Mark(probe, session, act, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "an act Decision is markable")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(act)
	Do $$$AssertEquals(row.Channel_"|"_row.MatchKey_"|"_row.Outcome_"|"_row.AnsweredChannel, "webhook|src|act|web", "keyed by the webhook source")
	Set again = ..Decision(session, "decide", "tellnow")
	Set result = ..Mark(probe, session, again, "zz")
	Do $$$AssertEquals(result.Ok_"|"_##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(again).AnsweredChannel, "1|", "a Channel that is no CHANNEL value is kept as empty")
}

/// The same DecisionRef again answers already_marked with the first row's Ref and time and writes no second row; so does a save that lost the race on the unique
/// SourceRef (the row is there, the save said error).
Method TestNoiseRepeat()
{
	Set session = ..Session("repeat")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set probe = ..Probe("CommandsIn")
	Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
	Set first = ..Mark(probe, session, decision, "web")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(decision)
	Set at = row.AnsweredAt
	Set result = ..Mark(probe, session, decision, "phone")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_marked", "a repeat: Ok 1, already_marked")
	Do $$$AssertEquals(result.Ref_"|"_##class(%DynamicAbstractObject).%FromJSON(result.Data).answeredAt, first.Ref_"|"_at, "with the first row's Ref and time")
	Do $$$AssertEquals(..Owned(session)_"|"_probe.Asked, "1|1", "no second row, and the Item was not looked up again")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(decision).AnsweredChannel, "web", "the first row is unchanged")
	Set raced = ..Decision(session, "decide", "tellnow")
	Set probe.FailSave = "raced"
	Set result = ..Mark(probe, session, raced, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_marked", "a lost race: Ok 1, already_marked")
	Do $$$AssertEquals(result.Ref, ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(raced).Ref, "with the row that stands")
	Do $$$AssertEquals(..Owned(session), 2, "and one row for it")
}

/// A decision that cannot be marked answers not_found and writes nothing, and the Item is not looked up for it.
Method TestNotMarkable()
{
	Set session = ..Session("notmark"), other = ..Session("notmarkother")
	Set probe = ..Probe("CommandsIn")
	Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
	Set cases = $ListBuild($ListBuild("another session's decision", other, "decide", "tellnow"), $ListBuild("a digest decision", session, "decide", "digest"), $ListBuild("an ignore decision", session, "decide", "ignore"), $ListBuild("a turn decision", session, "turn", "tellnow"), $ListBuild("a diagnose decision", session, "diagnose", "tellnow"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set decision = ..Decision($List(case, 2), $List(case, 3), $List(case, 4))
		Set result = ..Mark(probe, session, decision, "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", $List(case, 1)_": Ok 0, not_found")
	}
	Set probe.Item = ..NewItem(session, "web", "Zz", "user")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "the decision of a user Item: Ok 0, not_found")
	Set probe.Item = ..NewItem(session, "telegram", "Zz")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "an untrusted Item whose channel has no key: Ok 0, not_found")
	For ref = "", "zz", "not a ref at all", $Translate($Justify("", 22), " ", "a") _ "b", "zzunknown" {
		Set result = ..Mark(probe, session, ref, "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "'"_ref_"': Ok 0, not_found")
	}
	Set decision = ..Decision(session, "decide", "tellnow")
	Set result = ..Mark(probe, "", decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "an empty session: Ok 0, not_found")
	Set result = ..Mark(probe, "eval", decision, "web")
	Do $$$AssertEquals(result.Ok, 0, "the session eval: Ok 0")
	Do $$$AssertEquals(..Owned(session)_"|"_..Owned(other), "0|0", "nothing was written")
}

/// A Decision whose Item is no longer kept is too_old and writes nothing.
Method TestItemPurged()
{
	Set session = ..Session("purged")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set probe = ..Probe("CommandsIn")
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|too_old", "Ok 0, too_old")
	Do $$$AssertEquals(probe.Asked_"|"_..Owned(session), "1|0", "the Item was looked up, and nothing was written")
}

/// The real ItemOf opens the Msg.Item bodies of the Decision's trace session and answers the one with the Decision's ItemId: not another Item of the session, not
/// the same ItemId in another session, and not a Decision with no trace session.
Method TestRealItemOf()
{
	Set session = ..Session("realitem")
	Set sid = 900000000 + $Increment(^OcuTalonTest("PrecedentOps", "sid"))
	Set other = sid + 1000000
	Set mine = ..SaveItem(session, "mailbox", "Zz <Zz.Real@Example.com>", sid)
	Set alike = ..SaveItem(session, "mailbox", "Zz <Zz.Other@Example.com>", sid)
	Set elsewhere = ..SaveItem(session, "mailbox", "Zz <Zz.Elsewhere@Example.com>", other)
	Set probe = ..Probe("CommandsIn")
	Set probe.RealItemOf = 1
	Set decision = ..Decision(session, "decide", "tellnow", , {"ItemId": (mine.ItemId), "TraceSessionId": (sid)})
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "the Item of the trace session is found: Ok 1, marked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(decision).MatchKey, "zz.real@example.com", "and it is the one with the Decision's ItemId")
	Set decision = ..Decision(session, "decide", "tellnow", , {"ItemId": (elsewhere.ItemId), "TraceSessionId": (sid)})
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|too_old", "an Item of another trace session is not found")
	Set decision = ..Decision(session, "decide", "tellnow", , {"ItemId": (alike.ItemId), "TraceSessionId": (other)})
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|too_old", "an ItemId that is not in the trace session is not found")
	Set decision = ..Decision(session, "decide", "tellnow", , {"TraceSessionId": ""})
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|too_old", "a Decision with no trace session is too old")
	Do $$$AssertEquals(..Owned(session), 1, "one row was written in all")
}

/// A save that fails with the Decision still unmarked is failed (Ok 0), with one warning and no row.
Method TestSaveFailure()
{
	Set session = ..Session("savefail")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set probe = ..Probe("CommandsIn")
	Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
	Set probe.FailSave = "error"
	Set warnings = ..Logged("the precedent could not be saved")
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "Ok 0, failed")
	Do $$$AssertEquals(..Owned(session)_"|"_(..Logged("the precedent could not be saved") - warnings), "0|1", "no row, and one warning")
}

/// Forget deletes the session's own row at once: Similar and the ownership reads lose it. Another session's row and a seeded row answer not_found and stay.
Method TestForget()
{
	Set a = ..Session("forgetA"), b = ..Session("forgetB"), run = ..RunRef()
	Set mine = ..Row(a, "mailbox", "zz.forget@example.com", "2030-01-01T10:00:00Z")
	Set theirs = ..Row(b, "mailbox", "zz.forget@example.com", "2030-01-02T10:00:00Z")
	Set seeded = ..Row("eval", "mailbox", "zz.forget@example.com", "2030-01-03T10:00:00Z", run)
	Set probe = ..Probe("CommandsIn")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(a, "mailbox", "zz.forget@example.com").%Size(), 1, "Similar finds A's row")
	For ref = theirs, seeded, "zz", "" {
		Set result = ..ForgetOf(probe, a, ref)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "'"_ref_"' is not A's row: Ok 0, not_found")
	}
	Do $$$AssertEquals(..Exists(theirs)_..Exists(seeded)_..Exists(mine), "111", "no other row was deleted")
	Set result = ..ForgetOf(probe, "", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "an empty session: not_found")
	Set result = ..ForgetOf(probe, a, mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|forgotten", "A's own row: Ok 1, forgotten")
	Do $$$AssertEquals(..Exists(mine), 0, "the row is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar(a, "mailbox", "zz.forget@example.com").%Size()_"|"_##class(OcuTalon.Data.Ownership).Precedents(a).Count(), "0|0", "Similar and the ownership list lose it at once")
	Set result = ..ForgetOf(probe, a, mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "a second Forget: not_found")
	Do $$$AssertEquals(..Exists(theirs)_..Exists(seeded), "11", "B's row and the seeded row stay")
}

/// A fix and a tool_call answer, approved or rejected, from AnswerOps: the fix row is keyed by its incident's production with channel system, the tool_call row by
/// tool:<ToolName> with no channel; both have an empty Outcome, the request's Ref as the source, the request's AnsweredAt (else now) and the message's channel.
Method TestApprovalAnswers()
{
	Set session = ..Session("approval")
	Set diagnose = ..Fixture("Decision", session, "diagnose", , , {"Summary": "Zz order dates are in the wrong format"})
	Set incident = ..Fixture("Incident", session, , "ZZNS", "Zz.Production", {"DecisionRef": (diagnose)})
	Set fix = ..Fixture("Approval", session, incident, "approved", , {"AnsweredAt": "2030-01-05T10:00:00Z", "AnsweredAction": "approve"})
	Set rejected = ..Fixture("Approval", session, incident, "rejected", , {"AnsweredAt": "2030-01-06T10:00:00Z", "AnsweredAction": "reject"})
	Set tool = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool", "AnsweredAction": "approve"})
	Set probe = ..Probe("AnswerOps")
	Set result = ..Record(probe, session, fix, "approve", "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "a fix approved: Ok 1, recorded")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(fix)
	Do $$$AssertEquals(result.Ref, row.Ref, "the result carries the row's Ref")
	Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.MatchKey, session_"|system|production:ZZNS/Zz.Production", "the owner, channel system and the production's key")
	Do $$$AssertEquals(row.Summary_"|"_row.Outcome_"|"_row.Answer, "Zz order dates are in the wrong format||approved", "the incident Decision's summary, no outcome, approved")
	Do $$$AssertEquals(row.AnsweredAt_"|"_row.AnsweredChannel_"|"_row.SourceRef_"|"_row.EvalRunRef, "2030-01-05T10:00:00Z|web|"_fix_"|", "the request's AnsweredAt, the message's channel and the request as the source")
	Set result = ..Record(probe, session, rejected, "reject", "phone")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(rejected)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_row.Answer_"|"_row.AnsweredChannel, "1|recorded|rejected|phone", "a fix rejected from the phone")
	Set result = ..Record(probe, session, tool, "approve", "telegram")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(tool)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "a tool_call approved: Ok 1, recorded")
	Do $$$AssertEquals(row.Channel_"|"_row.MatchKey_"|"_row.Summary_"|"_row.Outcome_"|"_row.Answer_"|"_row.AnsweredChannel, "|tool:Zz.Tool|Zz.Tool||approved|telegram", "no channel, the tool's key and name, approved")
	Do $$$AssertTrue(row.AnsweredAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "a request with no AnsweredAt is answered now: "_row.AnsweredAt)
	Set tool2 = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool2", "AnsweredAction": "approve"})
	Set result = ..Record(probe, session, tool2, "approve", "zz")
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(tool2).AnsweredChannel, "", "a channel that is no CHANNEL value is kept as empty")
	Do $$$AssertEquals(..Owned(session), 4, "four rows in all")
}

/// A setting request, a bad Action, an unknown request or session, another session's request and a repeat add no row.
Method TestApprovalRefused()
{
	Set session = ..Session("refused"), other = ..Session("refusedother")
	Set setting = ..Fixture("Approval", session, , "approved", , {"Kind": "setting", "AnsweredAction": "approve"})
	Set mine = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool", "AnsweredAction": "approve"})
	Set theirs = ..Fixture("Approval", other, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool", "AnsweredAction": "approve"})
	Set probe = ..Probe("AnswerOps")
	Set cases = $ListBuild($ListBuild("a setting request", session, setting, "approve"), $ListBuild("a bad Action", session, mine, "zz"), $ListBuild("an empty Action", session, mine, ""), $ListBuild("an unknown request", session, "zzunknown", "approve"), $ListBuild("an empty request", session, "", "approve"), $ListBuild("an unknown session", "zzunknown", mine, "approve"), $ListBuild("an empty session", "", mine, "approve"), $ListBuild("another session's request", session, theirs, "approve"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Record(probe, $List(case, 2), $List(case, 3), $List(case, 4), "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_recorded", $List(case, 1)_": Ok 0, not_recorded")
	}
	Do $$$AssertEquals(..Owned(session)_"|"_..Owned(other), "0|0", "nothing was written")
	Set result = ..Record(probe, session, mine, "approve", "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "the session's own tool_call is recorded")
	Set result = ..Record(probe, session, mine, "approve", "phone")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_recorded", "a repeat: Ok 1, already_recorded")
	Set result = ..Record(probe, session, mine, "reject", "phone")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_recorded", "a repeat with another Action than the stored answer: Ok 0, not_recorded")
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(mine)
	Do $$$AssertEquals(..Owned(session)_"|"_row.Answer_"|"_row.AnsweredChannel, "1|approved|web", "and the first answer stands")
}

/// DW-933: a RecordPrecedent writes only when the request's stored AnsweredAction equals the message's Action and its State is approved, rejected, executing, done or failed.
Method TestAnswerMustMatch()
{
	Set session = ..Session("match")
	Set probe = ..Probe("AnswerOps")
	Set rejectedAsked = ..Fixture("Approval", session, , "rejected", , {"Kind": "tool_call", "ToolName": "Zz.A", "AnsweredAction": "reject"})
	Set approvedAsked = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.B", "AnsweredAction": "approve"})
	Set pending = ..Fixture("Approval", session, , "pending", , {"Kind": "tool_call", "ToolName": "Zz.C", "AnsweredAction": "approve"})
	Set expired = ..Fixture("Approval", session, , "expired", , {"Kind": "tool_call", "ToolName": "Zz.D", "AnsweredAction": "approve"})
	Set cancelled = ..Fixture("Approval", session, , "cancelled", , {"Kind": "tool_call", "ToolName": "Zz.E", "AnsweredAction": "approve"})
	Set unanswered = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.F"})
	Set cases = $ListBuild($ListBuild("approve for a request answered reject", rejectedAsked, "approve"), $ListBuild("reject for a request answered approve", approvedAsked, "reject"), $ListBuild("approve for a pending request", pending, "approve"), $ListBuild("reject for a pending request", pending, "reject"), $ListBuild("approve for an expired request", expired, "approve"), $ListBuild("approve for a cancelled request", cancelled, "approve"), $ListBuild("approve for an approved request with no stored answer", unanswered, "approve"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Record(probe, session, $List(case, 2), $List(case, 3), "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_recorded", $List(case, 1)_": Ok 0, not_recorded")
	}
	Do $$$AssertEquals(..Owned(session), 0, "nothing was written")
	Set executing = ..Fixture("Approval", session, , "executing", , {"Kind": "tool_call", "ToolName": "Zz.G", "AnsweredAction": "approve"})
	Set done = ..Fixture("Approval", session, , "done", , {"Kind": "tool_call", "ToolName": "Zz.H", "AnsweredAction": "approve"})
	Set failed = ..Fixture("Approval", session, , "failed", , {"Kind": "tool_call", "ToolName": "Zz.I", "AnsweredAction": "approve"})
	For ref = executing, done, failed {
		Set result = ..Record(probe, session, ref, "approve", "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "a matching approve is recorded for a request in state "_##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State)
	}
	Do $$$AssertEquals(..Owned(session), 3, "three rows")
}

/// DW-934: on the online demo, a session whose ResumeHash sign-out cleared is refused by MarkNoise (not_found) and RecordPrecedent (not_recorded), with no row; a session that
/// holds its ResumeHash, and any session off the online demo, write.
Method TestEndedSession()
{
	Set session = ..Session("ended")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash("zzprecops"_..Number_"ended")
	Do $$$AssertStatusOK(row.%Save(), "the session holds a resume hash")
	Set decision = ..Decision(session, "decide", "tellnow")
	Set approval = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool", "AnsweredAction": "approve"})
	Set probe = ..Probe("CommandsIn")
	Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
	Set probe.DemoFlag = 1
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "online demo, resume hash held: marked")
	Set recorder = ..Probe("AnswerOps")
	Set recorder.DemoFlag = 1
	Set result = ..Record(recorder, session, approval, "approve", "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "online demo, resume hash held: recorded")
	Do ##class(OcuTalon.Data.Precedent).DropSession(session)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.ResumeHash = ""
	Do $$$AssertStatusOK(row.%Save(), "sign-out cleared the resume hash")
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "online demo, resume hash cleared: a MarkNoise is not_found")
	Set result = ..Record(recorder, session, approval, "approve", "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_recorded", "online demo, resume hash cleared: a RecordPrecedent is not_recorded")
	Do $$$AssertEquals(..Owned(session), 0, "no row was written")
	Set probe.DemoFlag = 0, recorder.DemoFlag = 0
	Set result = ..Mark(probe, session, decision, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "off the online demo, resume hash empty: marked")
	Set result = ..Record(recorder, session, approval, "approve", "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|recorded", "off the online demo, resume hash empty: recorded")
	Do $$$AssertEquals(..Owned(session), 2, "two rows")
	Do ##class(OcuTalon.Data.Precedent).DropSession(session)
	Set probe.DemoFlag = "", recorder.DemoFlag = ""
	Set savedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Set result = ..Mark(probe, session, decision, "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "the real online-demo setting 1, resume hash cleared: a MarkNoise is not_found")
		Set result = ..Record(recorder, session, approval, "approve", "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_recorded", "the real online-demo setting 1, resume hash cleared: a RecordPrecedent is not_recorded")
		Do $$$AssertEquals(..Owned(session), 0, "the real setting: no row was written")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
		Set result = ..Mark(probe, session, decision, "web")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|marked", "the real online-demo setting empty, resume hash empty: marked")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the real online-demo setting cases run")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", savedDemo)
}

/// Every message from every sender but its own, and each verb with every origin but web_user, is not_allowed with one warning that names the sender, and writes
/// nothing: no row, no deletion.
Method TestSenders()
{
	Set session = ..Session("senders"), run = ..RunRef()
	Set decision = ..Decision(session, "decide", "tellnow")
	Set approval = ..Fixture("Approval", session, , "approved", , {"Kind": "tool_call", "ToolName": "Zz.Tool"})
	Set mine = ..Row(session, "mailbox", "zz.senders@example.com", "2030-01-01T10:00:00Z")
	Set seeded = ..Row("eval", "mailbox", "zz.senders@example.com", "2030-01-02T10:00:00Z", run)
	Do ..SetEval(1)
	Set senders = $ListBuild("", "zz", "CommandsIn", "AnswerOps", "SessionOps", "EvalIn", "Intake", "AnswersIn")
	Set classes = $ListBuild("MarkNoise", "ForgetPrecedent", "RecordPrecedent", "EndSession", "SeedPrecedent", "RemoveSeededPrecedents")
	Set own = $ListBuild("CommandsIn", "CommandsIn", "AnswerOps", "SessionOps", "EvalIn", "EvalIn")
	Set tried = 0
	For c = 1:1:$ListLength(classes) {
		For s = 1:1:$ListLength(senders) {
			Set sender = $List(senders, s), class = $List(classes, c)
			If sender = $List(own, c) Continue
			Set probe = ..Probe(sender)
			Set probe.Item = ..NewItem(session, "mailbox", "Zz <Zz.A@Example.com>")
			Set label = class_" from '"_sender_"'"
			Set warnings = ..Logged("refused OcuTalon."_$Select($Extract(class, 1, 4) = "Mark" || ($Extract(class, 1, 6) = "Forget") || (class = "EndSession"): "Msg.Command.", 1: "Core.Msg.")_class_" from '"_sender_"'")
			Set result = ..Send(probe, ..MessageOf(class, session, decision, approval, mine, run, "web_user"))
			Set tried = tried + 1
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", label_" is not_allowed")
			Do $$$AssertEquals(..Logged("refused OcuTalon."_$Select($Extract(class, 1, 4) = "Mark" || ($Extract(class, 1, 6) = "Forget") || (class = "EndSession"): "Msg.Command.", 1: "Core.Msg.")_class_" from '"_sender_"'") - warnings, 1, label_": one warning")
		}
	}
	Do $$$AssertEquals(tried, 42, "all 42 pairs were tried")
	For verb = "MarkNoise", "ForgetPrecedent" {
		For origin = "tool", "timer", "web_admin", "telegram", "system", "zz", "" {
			Set probe = ..Probe("CommandsIn")
			Set result = ..Send(probe, ..MessageOf(verb, session, decision, approval, mine, run, origin))
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", verb_" with origin '"_origin_"' is not_allowed")
		}
	}
	Do $$$AssertEquals(..Owned(session)_"|"_..Exists(mine)_"|"_..Exists(seeded)_"|"_..Total("eval", run)_"|"_##class(OcuTalon.Data.Precedent).SourceRefIndexExists(decision)_"|"_##class(OcuTalon.Data.Precedent).SourceRefIndexExists(approval), "1|1|1|1|0|0", "no row was written or deleted")
}

/// A class that PrecedentOps does not carry out, and a message that is no object, answer an error status and one error is logged; nothing is written.
Method TestUnknownClass()
{
	Set session = ..Session("unknown")
	Set mine = ..Row(session, "mailbox", "zz.unknown@example.com", "2030-01-01T10:00:00Z")
	Set probe = ..Probe("CommandsIn")
	Set cases(1) = ##class(OcuTalon.Msg.Item).%New()
	Set cases(2) = ##class(OcuTalon.Msg.ItemDecision).%New()
	Set cases(3) = ##class(OcuTalon.Msg.Command.GotIt).%New()
	Set cases(4) = "zz"
	Set cases(5) = ""
	For n = 1:1:5 {
		Set errors = ..Logged("it carries out no", 2)
		Set sc = probe.OnMessage(cases(n), .response)
		Do $$$AssertStatusNotOK(sc, "an unknown message answers an error status")
		Do $$$AssertEquals(response, "", "and no response")
		Do $$$AssertEquals(..Logged("it carries out no", 2) - errors, 1, "and one error is logged")
	}
	Do $$$AssertEquals(..Owned(session), 1, "nothing was written or deleted")
}

/// SeedPrecedent from EvalIn with EvalOn 1: one row with the owner eval, EvalRunRef the run, its own Ref as the source and AnsweredAt as given (else now).
Method TestSeed()
{
	Set run = ..RunRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_run
	Do ..SetEval(1)
	Set probe = ..Probe("EvalIn")
	Set result = ..SeedOf(probe, run, "mailbox", "zz.seed@example.com", "Zz seeded", "tellnow", "noise", "2030-02-01T10:00:00Z")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|seeded", "Ok 1, seeded")
	Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(result.Ref)
	Do $$$AssertTrue($IsObject(row), "the row exists under the result's Ref")
	Do $$$AssertEquals(row.OwnerRef_"|"_row.EvalRunRef_"|"_row.SourceRef, "eval|"_run_"|"_row.Ref, "the owner eval, the run, and its own Ref as the source")
	Do $$$AssertEquals(row.Channel_"|"_row.MatchKey_"|"_row.Summary_"|"_row.Outcome_"|"_row.Answer_"|"_row.AnsweredAt, "mailbox|zz.seed@example.com|Zz seeded|tellnow|noise|2030-02-01T10:00:00Z", "the fields as given")
	Set result = ..SeedOf(probe, run, "", "heartbeat", "Zz beat", "", "approved", "")
	Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(result.Ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|seeded", "an empty Channel, Outcome and time are accepted")
	Do $$$AssertTrue(row.AnsweredAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "an empty time is now: "_row.AnsweredAt)
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).Similar("eval", "mailbox", "zz.seed@example.com").%Size(), 1, "Similar for the owner eval finds the seeded row")
}

/// The guards of SeedPrecedent: another sender, EvalOn 0 and no setting row are not_allowed; an empty RunRef or MatchKey, and a bad Answer, Channel, Outcome or
/// time are not_valid; nothing is written.
Method TestSeedRefused()
{
	Set run = ..RunRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_run
	Do ..SetEval(1)
	Set probe = ..Probe("EvalIn")
	Set cases = $ListBuild($ListBuild("an empty RunRef", "", "mailbox", "zz.k", "noise", "tellnow", ""), $ListBuild("an empty MatchKey", run, "mailbox", "", "noise", "tellnow", ""), $ListBuild("a bad Answer", run, "mailbox", "zz.k", "zz", "tellnow", ""), $ListBuild("an empty Answer", run, "mailbox", "zz.k", "", "tellnow", ""), $ListBuild("a bad Channel", run, "zz", "zz.k", "noise", "tellnow", ""), $ListBuild("a bad Outcome", run, "mailbox", "zz.k", "noise", "zz", ""), $ListBuild("a bad time", run, "mailbox", "zz.k", "noise", "tellnow", "yesterday"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..SeedOf(probe, $List(case, 2), $List(case, 3), $List(case, 4), "Zz", $List(case, 6), $List(case, 5), $List(case, 7))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_valid", $List(case, 1)_": Ok 0, not_valid")
	}
	Do $$$AssertEquals(..Total("eval", run), 0, "nothing was written")
	Do ..SetEval(0)
	Set result = ..SeedOf(probe, run, "mailbox", "zz.k", "Zz", "tellnow", "noise", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "EvalOn 0: not_allowed")
	Do ..DeleteEval()
	Set result = ..SeedOf(probe, run, "mailbox", "zz.k", "Zz", "tellnow", "noise", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "no setting row: not_allowed")
	Do ..SetEval(1)
	Set result = ..SeedOf(..Probe("CommandsIn"), run, "mailbox", "zz.k", "Zz", "tellnow", "noise", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "another sender: not_allowed")
	Do $$$AssertEquals(..Total("eval", run), 0, "still nothing was written")
}

/// RemoveSeededPrecedents deletes the rows of that run and no other row, answers their count, and is not_allowed under the same guards as the seed.
Method TestRemoveSeeded()
{
	Set one = ..RunRef(), two = ..RunRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_one_","_two
	Set session = ..Session("remove")
	Set mine = ..Row(session, "mailbox", "zz.remove@example.com", "2030-01-01T10:00:00Z")
	Do ..SetEval(1)
	Set probe = ..Probe("EvalIn")
	For i = 1:1:3 {
		Do $$$AssertEquals(..SeedOf(probe, one, "mailbox", "zz.remove"_i, "Zz", "tellnow", "noise", "").Outcome, "seeded", "run one's row "_i_" is seeded")
	}
	Do $$$AssertEquals(..SeedOf(probe, two, "mailbox", "zz.remove", "Zz", "tellnow", "noise", "").Outcome, "seeded", "run two's row is seeded")
	Set result = ..RemoveOf(..Probe("CommandsIn"), one)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "another sender: not_allowed")
	Do ..SetEval(0)
	Set result = ..RemoveOf(probe, one)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "EvalOn 0: not_allowed")
	Do $$$AssertEquals(..Total("eval", one)_"|"_..Total("eval", two), "3|1", "nothing was removed")
	Do ..SetEval(1)
	Set result = ..RemoveOf(probe, "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_valid", "an empty RunRef: not_valid")
	Set result = ..RemoveOf(probe, one)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_##class(%DynamicAbstractObject).%FromJSON(result.Data).count, "1|removed|3", "Ok 1, removed, three rows")
	Do $$$AssertEquals(..Total("eval", one)_"|"_..Total("eval", two)_"|"_..Exists(mine), "0|1|1", "run one's rows are gone; run two's and the person's row stay")
	Set result = ..RemoveOf(probe, one)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_##class(%DynamicAbstractObject).%FromJSON(result.Data).count, "1|removed|0", "a second removal removes none")
}

/// Seeded rows with the same channel and key as a person's own row: the person's Similar, Ownership.Precedents and Ownership.Precedent see none of them, and
/// Similar for the owner eval sees only them.
Method TestPersonBesideRun()
{
	Set run = ..RunRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_run
	Set person = ..Session("beside")
	Set mine = ..Row(person, "mailbox", "zz.beside@example.com", "2030-01-01T10:00:00Z")
	Do ..SetEval(1)
	Set probe = ..Probe("EvalIn")
	Set s1 = ..SeedOf(probe, run, "mailbox", "zz.beside@example.com", "Zz", "tellnow", "noise", "2030-01-02T10:00:00Z").Ref
	Set s2 = ..SeedOf(probe, run, "mailbox", "zz.beside@example.com", "Zz", "tellnow", "noise", "2030-01-03T10:00:00Z").Ref
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar(person, "mailbox", "zz.beside@example.com")), "2030-01-01T10:00:00Z", "Similar for the person gives only the person's row")
	Do $$$AssertEquals(..Times(##class(OcuTalon.Data.Precedent).Similar("eval", "mailbox", "zz.beside@example.com")), "2030-01-03T10:00:00Z,2030-01-02T10:00:00Z", "Similar for eval gives only the seeded rows")
	Set list = ##class(OcuTalon.Data.Ownership).Precedents(person)
	Do $$$AssertEquals(list.Count()_"|"_list.GetAt(1).Ref, "1|"_mine, "Ownership.Precedents lists only the person's row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Precedent(s1, person)_##class(OcuTalon.Data.Ownership).Precedent(s2, person), "", "Ownership.Precedent finds no seeded row")
}

/// EvalOn is 1 only when the System Default Setting row (OcuTalon.Production, EvalIn, any class, Enabled) exists and holds 1; the test writes 1 and 0, deletes the
/// row, and puts back what it found.
Method TestEvalOn()
{
	Do ..SetEval(1)
	Do $$$AssertEquals(##class(OcuTalon.Core.PrecedentOps).EvalOn(), 1, "the row at 1: on")
	Do ..SetEval(0)
	Do $$$AssertEquals(##class(OcuTalon.Core.PrecedentOps).EvalOn(), 0, "the row at 0: off")
	Do ..DeleteEval()
	Do $$$AssertEquals(##class(OcuTalon.Core.PrecedentOps).EvalOn(), 0, "no row: off")
	Do ..SetEval(1)
	Do $$$AssertEquals(##class(OcuTalon.Core.PrecedentOps).EvalOn(), 1, "the row at 1 again: on")
	Do ..PutBackEval()
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(..#EVALROW), ..EvalDefined, "the row is as the test found it")
}

/// An EndSession from SessionOps deletes the session's rows, and no other session's and no seeded row.
Method TestEndSession()
{
	Set a = ..Session("endA"), b = ..Session("endB"), run = ..RunRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_run
	Do ..Row(a, "mailbox", "zz.end1@example.com", "2030-01-01T10:00:00Z")
	Do ..Row(a, "mailbox", "zz.end2@example.com", "2030-01-02T10:00:00Z")
	Do ..Row(b, "mailbox", "zz.end1@example.com", "2030-01-03T10:00:00Z")
	Do ..Row("eval", "mailbox", "zz.end1@example.com", "2030-01-04T10:00:00Z", run)
	Set probe = ..Probe("SessionOps")
	Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()
	Set command.SessionRef = a
	Set command.Origin = "web_user"
	Set result = ..Send(probe, command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..Owned(a)_"|"_..Owned(b)_"|"_..Total("eval", run), "0|1|1", "A's rows are gone; B's row and the seeded row stay")
	Set result = ..Send(probe, command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "a second EndSession: ended")
}

/// A decision.recorded event for a tell-now decide Decision of the session, which BridgeSink turns into the notice, writes no precedent.
Method TestDecisionRecordedWritesNoRow()
{
	Set session = ..Session("sink")
	Set decision = ..Decision(session, "decide", "tellnow")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.BridgeSink).OnEvent("decision.recorded", session, {"ref": (decision)}), "OnEvent returns OK")
	Do $$$AssertEquals(..Owned(session)_"|"_##class(OcuTalon.Data.Precedent).SourceRefIndexExists(decision), "0|0", "no row for the session or for the Decision")
}

/// --- helpers ---
/// A shadow instance of the probe whose request header comes from the sender, and which is off the online demo (a test sets DemoFlag for the online demo).
Method Probe(sender As %String) As OcuTalon.Test.Core.PrecedentOpsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = sender
	Set probe.%RequestHeader = header
	Set probe.DemoFlag = 0
	Quit probe
}

/// A fixture session, recorded for the clean-up (its rows are dropped). Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzprecops"_..Number_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_ref
	Quit ref
}

/// A new run Ref, recorded for the clean-up (the rows it seeded are removed).
Method RunRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_ref
	Quit ref
}

/// A decision of the owner, recorded for the clean-up. Returns its Ref.
Method Decision(owner As %String, kind As %String, outcome As %String, summary As %String = "", fields As %DynamicObject = "") As %String [ Private ]
{
	If '$IsObject(fields) Set fields = {}
	Do fields.%Set("Outcome", outcome)
	If summary '= "" Do fields.%Set("Summary", summary)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, kind, ##class(OcuTalon.Data.Time).NowUtc(), fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture row of the Fixture class (Decision, Incident or Approval), recorded for the clean-up. The arguments follow Fixture's, after the owner.
Method Fixture(kind As %String, owner As %String, arg2 As %String = "", arg3 As %String = "", arg4 As %String = "", fields As %DynamicObject = "") As %String [ Private ]
{
	If kind = "Decision" Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, arg2, , fields)
	If kind = "Incident" Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, , arg3, arg4, fields)
	If kind = "Approval" Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, arg2, arg3, , fields)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// An unsaved Item of the channel and sender for the session.
Method NewItem(session As %String, channel As %String, sender As %String, provenance As %String = "untrusted") As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = channel
	Set item.Provenance = provenance
	Set item.Sender = sender
	Set item.Text = "zz text"
	Quit item
}

/// An Item saved as the body of a message header of the trace session, both removed after the test. Returns the Item.
Method SaveItem(session As %String, channel As %String, sender As %String, sessionId As %Integer) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ..NewItem(session, channel, sender)
	Do $$$AssertStatusOK(item.%Save(), "the Item is saved")
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SessionId = sessionId
	Set header.SuperSession = "zzprecops"_..Number
	Set header.SourceConfigName = "ZzSource"
	Set header.TargetConfigName = "Intake"
	Set header.Type = 1
	Set header.MessageBodyClassName = "OcuTalon.Msg.Item"
	Set header.MessageBodyId = item.%Id()
	Do $$$AssertStatusOK(header.%Save(), "the header is saved")
	Set ..Messages = ..Messages_$Select(..Messages = "": "", 1: ",")_header.%Id()_"|"_item.%Id()
	Quit item
}

/// Saves a Precedent row, recorded under its owner for the clean-up. Returns its Ref. A run Ref makes it a seeded row.
Method Row(owner As %String, channel As %String, key As %String, answeredAt As %String, run As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.Channel = channel
	Set row.MatchKey = key
	Set row.Summary = "zz summary"
	Set row.Outcome = "tellnow"
	Set row.Answer = "noise"
	Set row.AnsweredAt = answeredAt
	Set row.SourceRef = row.Ref
	Set row.EvalRunRef = run
	Do $$$AssertStatusOK(row.%Save(), "a fixture row is saved")
	Quit row.Ref
}

/// Sends a MarkNoise to the probe and returns its CommandResult.
Method Mark(probe As OcuTalon.Test.Core.PrecedentOpsProbe, session As %String, decision As %String, channel As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
	Set command.Origin = "web_user"
	Set command.SessionRef = session
	Set command.DecisionRef = decision
	Set command.Channel = channel
	Quit ..Send(probe, command)
}

/// Sends a ForgetPrecedent to the probe and returns its CommandResult.
Method ForgetOf(probe As OcuTalon.Test.Core.PrecedentOpsProbe, session As %String, ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ForgetPrecedent).%New()
	Set command.Origin = "web_user"
	Set command.SessionRef = session
	Set command.PrecedentRef = ref
	Quit ..Send(probe, command)
}

/// Sends a RecordPrecedent to the probe and returns its CommandResult.
Method Record(probe As OcuTalon.Test.Core.PrecedentOpsProbe, session As %String, approval As %String, action As %String, channel As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set message = ##class(OcuTalon.Core.Msg.RecordPrecedent).%New()
	Set message.SessionRef = session
	Set message.ApprovalRef = approval
	Set message.Action = action
	Set message.Channel = channel
	Quit ..Send(probe, message)
}

/// Sends a SeedPrecedent to the probe and returns its CommandResult.
Method SeedOf(probe As OcuTalon.Test.Core.PrecedentOpsProbe, run As %String, channel As %String, key As %String, summary As %String, outcome As %String, answer As %String, at As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set message = ##class(OcuTalon.Core.Msg.SeedPrecedent).%New()
	Set message.RunRef = run
	Set message.Channel = channel
	Set message.MatchKey = key
	Set message.Summary = summary
	Set message.Outcome = outcome
	Set message.Answer = answer
	Set message.AnsweredAt = at
	Quit ..Send(probe, message)
}

/// Sends a RemoveSeededPrecedents to the probe and returns its CommandResult.
Method RemoveOf(probe As OcuTalon.Test.Core.PrecedentOpsProbe, run As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set message = ##class(OcuTalon.Core.Msg.RemoveSeededPrecedents).%New()
	Set message.RunRef = run
	Quit ..Send(probe, message)
}

/// A message of the class name (one of the six) with the session, decision, approval, precedent and run given; a verb carries the origin.
Method MessageOf(class As %String, session As %String, decision As %String, approval As %String, precedent As %String, run As %String, origin As %String) As %RegisteredObject [ Private ]
{
	If class = "MarkNoise" {
		Set message = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
		Set message.DecisionRef = decision
		Set message.Channel = "web"
	} ElseIf class = "ForgetPrecedent" {
		Set message = ##class(OcuTalon.Msg.Command.ForgetPrecedent).%New()
		Set message.PrecedentRef = precedent
	} ElseIf class = "RecordPrecedent" {
		Set message = ##class(OcuTalon.Core.Msg.RecordPrecedent).%New()
		Set message.ApprovalRef = approval
		Set message.Action = "approve"
		Set message.Channel = "web"
		Set message.SessionRef = session
	} ElseIf class = "EndSession" {
		Set message = ##class(OcuTalon.Msg.Command.EndSession).%New()
	} ElseIf class = "SeedPrecedent" {
		Set message = ##class(OcuTalon.Core.Msg.SeedPrecedent).%New()
		Set message.RunRef = run
		Set message.Channel = "mailbox"
		Set message.MatchKey = "zz.senders.seed"
		Set message.Answer = "noise"
	} Else {
		Set message = ##class(OcuTalon.Core.Msg.RemoveSeededPrecedents).%New()
		Set message.RunRef = run
	}
	If message.%IsA("OcuTalon.Msg.Command") {
		Set message.Origin = origin
		Set message.SessionRef = session
	}
	Quit message
}

/// Sends a message to the probe and returns its CommandResult.
Method Send(probe As OcuTalon.Test.Core.PrecedentOpsProbe, message As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sc = probe.OnMessage(message, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The number of Precedent rows of the owner (a session, or eval), or with a run Ref the number of the run's rows.
Method Total(owner As %String, run As %String = "") As %Integer [ Private ]
{
	If run '= "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE OwnerRef = ? AND EvalRunRef = ?", owner, run)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE OwnerRef = ?", owner)
	}
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of Precedent rows of the session.
Method Owned(session As %String) As %Integer [ Private ]
{
	Quit ..Total(session)
}

/// 1 when the Precedent row with the Ref exists.
Method Exists(ref As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Precedent).RefIndexExists(ref)
}

/// The AnsweredAt of each item of a Similar answer, comma-separated.
Method Times(items As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:items.%Size() - 1 {
		Set text = text_$Select(text = "": "", 1: ",")_items.%Get(i).answeredAt
	}
	Quit text
}

/// The number of Event Log entries of the type (3 warnings, 2 errors) whose text contains the text.
Method Logged(text As %String, type As %Integer = 3) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = ? AND Text [ ?", type, text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Writes the EvalIn System Default Setting row with 1 or 0.
Method SetEval(on As %Boolean) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SetEval(on), "the EvalIn setting is written as "_on)
}

/// Deletes the EvalIn System Default Setting row.
Method DeleteEval() [ Private ]
{
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#EVALROW)
}

/// Puts the EvalIn System Default Setting row back as the test found it: its value, or no row.
Method PutBackEval() [ Private ]
{
	If ..EvalDefined {
		Do ##class(OcuTalon.Install.Step.Production).SetEval(..EvalValue = 1)
	} Else {
		Do ..DeleteEval()
	}
}

}
