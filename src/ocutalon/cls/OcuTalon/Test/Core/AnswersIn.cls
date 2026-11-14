/// Tests of AnswersIn's rules and AnswerOps' hand-off with no production (Story 6.2; AD-1, AD-4, AD-11): the shadow instance of
/// AnswersInProbe runs the real OnProcessInput and passes the answer to a shadow AnswerOpsProbe, whose approval API is the
/// ApprovalDouble, so the double records what Approval.Answer would have received. Every test uses two fixture sessions and removes
/// its rows; the online-demo flag is saved and restored.
///   - TestResultsPassThrough: each result of the double (done, already_answered with its winner, expired, not_found, not_allowed)
///     reaches the caller as the AnswerResult;
///   - TestBadActionAndChannel: an action other than approve or reject and a channel other than web, phone or telegram are
///     bad_answer, and the double is not called;
///   - TestUnseenRequestsAreNotFound: another session's request (on a local install and online), an eval request, an unwatched
///     instance request, a cancelled request, a missing ref and an instance request on the online demo are not_found, whatever the
///     action and channel, and the double is not called;
///   - TestWatcherReachesInstanceRequest: on a local install a session that watches the production reaches the double for an
///     instance request, and the answer names that session's Ref and IRIS user (DW-199);
///   - TestMalformedSessionRefNeverReaches: a SessionRef that is not a 22-character Ref is not_found and never reaches the double;
///   - TestBridgeContextRefuses: inside a bridge context the answer is not_allowed and nothing is sent;
///   - TestTelegramChannelReaches: the rules are entry-independent, so a phone and a telegram answer reach the double;
///   - TestHandOffIsTracedToTheSession: the hand-off is sent in a trace session of its own (whatever session the service held
///     before), tagged with the session's TraceRef;
///   - TestRequestRefIsTheRowsOwn: a ref that names the request in another letter case reaches the double as the row's own Ref;
///   - TestAnswerOpsRefusesOtherSenders: a request whose header names another item, or none, is an error status and answers nothing;
///   - TestAnswerOpsUnknownSession: a SessionRef with no Session row is not_found and never reaches the double;
///   - TestRoleRefusalReachesCaller: the double's not_allowed for a session whose IRIS user lacks the role reaches the caller, with the refusal {"kind": ""};
///   - TestRoleCheckBeforeHandOver (Story 25.5): rule 6 asks MayAnswer for the session's IRIS user after the ownership and answer-shape checks and before the hand-over: a 0 is not_allowed with
///     {"kind"}, sends nothing and leaves the row pending, a 1 hands over, and a request that is not the session's, a bad answer, a bridge context and a session with no row never ask;
///   - TestRefusalKey: the catalog key and the sentence of each approver kind, of no kind, of an unknown kind and of the admin refusal;
///   - TestPayloadAnswerable: the approval payload's answerable and approverKind for a pending request that the session may and may not answer, and 1 for every other payload;
///   - TestEmailAdminRefusal: an approve of an email request to another address by a user who passes the role check but is no admin is not_allowed with {"kind": "email", "admin": true}, and a reject is handed over;
///   - TestAnswersInIsTheOnlySender (QA, AC14): no class of the product but AnswersIn names "AnswerOps" as a send target (method
///     code, parameter defaults, the production's XData settings), and AnswersIn makes exactly one send;
///   - TestNoAllowanceOrConversation: the code of AnswersIn and AnswerOps names neither Allowance nor Conversation (an answer is not
///     a turn, AD-20).
Class OcuTalon.Test.Core.AnswersIn Extends %UnitTest.TestCase
{

/// The fixture owner of the two sessions, and the instance rows' production prefix.
Parameter USER = "zzanswers";

/// The Refs of the run's fixture rows, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The online-demo flag before the run.
Property OnlineWas As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Refs = ""
	Set ..OnlineWas = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineWas)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineWas)
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

Method TestResultsPassThrough()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	For result = "done", "already_answered", "expired", "not_found", "not_allowed" {
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin(result)
		Set sc = ..Answer(probe, request, "approve", "web", mine, .output)
		Do $$$AssertStatusOK(sc, result_": OnProcessInput returns OK")
		Do $$$AssertEquals(output.Result, result, result_": the result reaches the caller")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, result_": the double was called once")
		If result = "already_answered" {
			Do $$$AssertEquals(output.WinnerAction, "approve", "the winner's action")
			Do $$$AssertEquals(output.WinnerChannel, "phone", "the winner's channel")
			Do $$$AssertEquals(output.WinnerAt, "2030-01-01T14:15:00Z", "the winner's time")
		} Else {
			Do $$$AssertEquals(output.WinnerAction_output.WinnerChannel_output.WinnerAt, "", result_": no winner")
		}
	}
}

Method TestBadActionAndChannel()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	For action = "", "delete", "Approve", "APPROVE", "approve,reject" {
		Do ..Answer(probe, request, action, "web", mine, .output)
		Do $$$AssertEquals(output.Result, "bad_answer", "action '"_action_"' is bad_answer")
	}
	For channel = "", "email", "mailbox", "Web", "system", "slack" {
		Do ..Answer(probe, request, "approve", channel, mine, .output)
		Do $$$AssertEquals(output.Result, "bad_answer", "channel '"_channel_"' is bad_answer")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "the double was never called")
	Do $$$AssertEquals(probe.Sends, 0, "and nothing was sent")
}

Method TestUnseenRequestsAreNotFound()
{
	Set mine = ..Session("a"), theirs = ..Session("b")
	Set production = "Zz.Answers.Unwatched"
	Set instanceIncident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", production)
	Set ..Refs = ..Refs_","_instanceIncident
	Set cancelled = ##class(OcuTalon.Test.Data.Fixture).Approval(mine, "", "cancelled")
	Set ..Refs = ..Refs_","_cancelled
	Set unseen = $ListBuild(..Approval(theirs), ..Approval("eval"), ..Approval("instance", instanceIncident), cancelled, "zzmissing")
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	For online = 0, 1 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Select(online: 1, 1: ""))
		Set position = 0
		While $ListNext(unseen, position, ref) {
			Do ..Answer(probe, ref, "approve", "web", mine, .output)
			Do $$$AssertEquals(output.Result, "not_found", "request "_ref_" (online "_online_") is not_found")
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "the double was never called")
	Do $$$AssertEquals(probe.Sends, 0, "and nothing was sent")
	Do ..Answer(probe, ..Approval(theirs), "bogus", "bogus", mine, .output)
	Do $$$AssertEquals(output.Result, "not_found", "an unseen request is not_found whatever the action and channel")
	Do ..Answer(probe, cancelled, "bogus", "bogus", mine, .output)
	Do $$$AssertEquals(output.Result, "not_found", "and so is a cancelled one")
	Do $$$AssertEquals(probe.Sends, 0, "and nothing was sent")
}

Method TestWatcherReachesInstanceRequest()
{
	Set mine = ..Session("a")
	Set production = "Zz.Answers.Watched"
	Set check = ##class(OcuTalon.Test.Data.Fixture).Check(mine, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", production)
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set ..Refs = ..Refs_","_check_","_incident_","_request
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "a local watcher answers an instance request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "the double was called")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "sessionRef"), mine, "with the watcher's Ref (DW-199)")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "not_found", "with onlineDemo on the same instance request is not_found")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "and the double was not called again")
}

Method TestMalformedSessionRefNeverReaches()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "control: the session's own Ref answers")
	Do $$$AssertEquals($Length(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "sessionRef")), 22, "and the double saw a 22-character Ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "irisUser"), ##class(OcuTalon.Data.Session).RefIndexOpen(mine).IrisUser, "and the session's IRIS user")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "channel"), "web", "and the channel as sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "action"), "approve", "and the action as sent")
	For bad = "", "instance", "eval", "short", mine_"x", $Extract(mine, 1, 21), mine_" " {
		Do ..Answer(probe, request, "approve", "web", bad, .output)
		Do $$$AssertEquals(output.Result, "not_found", "SessionRef '"_bad_"' is not_found")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 1, "no malformed SessionRef reached the double")
}

Method TestBridgeContextRefuses()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), "zzss"), "a bridge context begins")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(output.Result, "not_allowed", "inside a bridge context the answer is not_allowed")
	Do $$$AssertEquals(probe.Sends, 0, "nothing was sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "and the double was not called")
	Do $$$AssertEquals(..LogRows(mark, 3, "OcuTalon.Test.Core.AnswersInProbe"), 1, "and one warning was logged")
	Do ..RemoveLogRows(mark, "OcuTalon.Test.Core.AnswersInProbe")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "control: with no context the same answer is done")
}

Method TestTelegramChannelReaches()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	For channel = "phone", "telegram" {
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
		Do ..Answer(probe, request, "reject", channel, mine, .output)
		Do $$$AssertEquals(output.Result, "done", "a "_channel_" answer is done")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "channel"), channel, "and the double saw the channel")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "action"), "reject", "and the action")
	}
}

Method TestHandOffIsTracedToTheSession()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Set probe.%SessionId = 1
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(probe.Sends, 1, "one send")
	Do $$$AssertEquals(probe.SeenSuperSession, ##class(OcuTalon.Data.Session).RefIndexOpen(mine).TraceRef, "the send is tagged with the session's TraceRef")
	Do $$$AssertEquals(probe.SeenSessionId, "", "in a trace session of its own")
	Do $$$AssertEquals(probe.LastRequest.SessionRef, mine, "and the message names the session's Ref")
	Do $$$AssertEquals(##class(%Dictionary.CompiledProperty).%ExistsId("OcuTalon.Core.Msg.Answer||IrisUser"), 0, "and the message class has no user-name property")
}

Method TestAnswerOpsRefusesOtherSenders()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = request
	Set answer.Action = "approve"
	Set answer.Channel = "web"
	Set answer.SessionRef = mine
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	For source = "CommandsIn", "WebChatIn", "", "answersin" {
		Set operation = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswerOpsProbe", .sc)
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.SourceConfigName = source
		Set operation.%RequestHeader = header
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set sc = operation.OnMessage(answer, .response)
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a request from '"_source_"' is an error status")
		Do $$$AssertEquals(response, "", "with no response")
		Do $$$AssertEquals(..LogRows(mark, 2, "OcuTalon.Test.Core.AnswerOpsProbe"), 1, "and one error is logged")
		Do ..RemoveLogRows(mark, "OcuTalon.Test.Core.AnswerOpsProbe")
	}
	Set operation = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswerOpsProbe", .sc)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sc = operation.OnMessage(answer, .response)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a request with no header is an error status")
	Do $$$AssertEquals(..LogRows(mark, 2, "OcuTalon.Test.Core.AnswerOpsProbe"), 1, "and one error is logged")
	Do ..RemoveLogRows(mark, "OcuTalon.Test.Core.AnswerOpsProbe")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "the double was never called")
}

Method TestRequestRefIsTheRowsOwn()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set variant = $ZConvert(request, "L")
	If variant = request Set variant = $ZConvert(request, "U")
	Do $$$AssertNotEquals(variant, request, "control: the ref in another letter case differs from the row's")
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Do ..Answer(probe, variant, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "the ref in another letter case names the session's request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "ref"), request, "and the answer names the row's own Ref")
}

Method TestAnswerOpsUnknownSession()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = request
	Set answer.Action = "approve"
	Set answer.Channel = "web"
	Set answer.SessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin()
	Set operation = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswerOpsProbe", .sc)
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = "AnswersIn"
	Set operation.%RequestHeader = header
	Set sc = operation.OnMessage(answer, .response)
	Do $$$AssertStatusOK(sc, "OnMessage returns OK")
	Do $$$AssertEquals(response.Result, "not_found", "a SessionRef with no Session row is not_found")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), 0, "and the double was not called")
}

Method TestRoleRefusalReachesCaller()
{
	Set mine = ..Session("a"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("not_allowed")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "not_allowed", "the not_allowed of a session without the role reaches the caller")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.ApprovalDouble).Arg(1, "irisUser"), ##class(OcuTalon.Data.Session).RefIndexOpen(mine).IrisUser, "after the double saw the session's IRIS user")
	Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{""kind"":""""}", "and a not_allowed that is not the email rule's carries the refusal with no kind")
}

/// Story 25.5, rule 6: MayAnswer is asked for the session's IRIS user and the request's Ref after rules 1 to 5 and before the hand-over.
Method TestRoleCheckBeforeHandOver()
{
	Set mine = ..Session("a"), theirs = ..Session("b"), request = ..Approval(mine)
	Set probe = ..NewProbe()
	Set double = "OcuTalon.Test.Core.ApprovalDouble"
	Do $CLASSMETHOD(double, "Begin")
	Do $CLASSMETHOD(double, "May", request, 0, "resend")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "not_allowed", "a scripted refusal is not_allowed")
	Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{""kind"":""resend""}", "with the kind that the role check named")
	Do $$$AssertEquals(probe.Sends, 0, "nothing was sent")
	Do $$$AssertEquals($CLASSMETHOD(double, "Calls"), 0, "so Approval.Answer was not called")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", "and the row is as it was")
	Do $$$AssertEquals($CLASSMETHOD(double, "MayCalls"), 1, "MayAnswer was asked once")
	Do $$$AssertEquals($CLASSMETHOD(double, "MayArg", 1, "ref")_"|"_$CLASSMETHOD(double, "MayArg", 1, "irisUser"), request_"|"_##class(OcuTalon.Data.Session).RefIndexOpen(mine).IrisUser, "for the request's Ref and the IRIS user of the session's row")
	Do $CLASSMETHOD(double, "May", request, 1, "")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "a scripted 1 hands the answer over")
	Do $$$AssertEquals(probe.Sends_"|"_$CLASSMETHOD(double, "Calls"), "1|1", "which reaches Approval.Answer once")
	Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{}", "with no refusal")
	Do $CLASSMETHOD(double, "Begin")
	Set other = ..Approval(theirs), noSession = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set orphan = ##class(OcuTalon.Test.Data.Fixture).Approval(noSession)
	Set ..Refs = ..Refs_","_orphan
	For ref = request, other, orphan {
		Do $CLASSMETHOD(double, "May", ref, 0, "resend")
	}
	Do ..Answer(probe, other, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "not_found", "another session's request is not_found")
	Do ..Answer(probe, request, "delete", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "bad_answer", "a bad action is bad_answer")
	Do ..Answer(probe, request, "approve", "mailbox", mine, .output)
	Do $$$AssertEquals(output.Result, "bad_answer", "and a bad channel")
	Do ..Answer(probe, request, "approve", "web", "short", .output)
	Do $$$AssertEquals(output.Result, "not_found", "a SessionRef that is no Ref is not_found")
	Do ..Answer(probe, orphan, "approve", "web", noSession, .output)
	Do $$$AssertEquals(output.Result, "not_found", "a Ref-shaped SessionRef with no Session row is not_found")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), "zzss"), "a bridge context begins")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..RemoveLogRows(mark, "OcuTalon.Test.Core.AnswersInProbe")
	Do $$$AssertEquals(output.Result_"|"_probe.Refusal.%ToJSON(), "not_allowed|{""kind"":""""}", "and a bridge context is not_allowed with no kind")
	Do $$$AssertEquals($CLASSMETHOD(double, "MayCalls"), 0, "none of them asked the role check")
	Do $$$AssertEquals(probe.Sends_"|"_$CLASSMETHOD(double, "Calls"), "1|0", "and none of them sent or answered anything (the one send is the allowed answer above)")
}

/// Story 25.5: the catalog key and the sentence of a refusal. The seven kinds each have their sentence, an empty or unknown kind and a kind that is not 1 to 32 lower-case letters or _ have the fallback, and admin has its own.
Method TestRefusalKey()
{
	Set wanted = "resend|Only an approver for resends can answer this request.;reroute|Only an approver for reroutes can answer this request.;suspend|Only an approver for suspending and resuming items can answer this request.;"
	Set wanted = wanted_"rollback|Only an approver for rollbacks can answer this request.;partner|Only an approver for partner notices can answer this request.;email|Only an approver for emails can answer this request.;tool|Only an approver for tool calls can answer this request."
	For i = 1:1:$Length(wanted, ";") {
		Set kind = $Piece($Piece(wanted, ";", i), "|", 1), text = $Piece($Piece(wanted, ";", i), "|", 2)
		Set key = ##class(OcuTalon.Live.Payload.Approval).RefusalKey(kind)
		Do $$$AssertEquals(key, "answered.notApprover"_$ZConvert($Extract(kind), "U")_$Extract(kind, 2, *), kind_": the key is the kind with its first letter in upper case")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(key, {}, "web", .sc), text, kind_": the sentence is the approved text")
		Do $$$AssertStatusOK(sc, kind_": it renders")
	}
	Set fallback = "Only an approver can answer this request."
	For kind = "", "zz_new", "Bad", "resend ", "RESEND", "resend1", "re-send", $Translate($Justify("", 33), " ", "a"), $Translate($Justify("", 40), " ", "a"), "setting", "fix", "_" {
		Set key = ##class(OcuTalon.Live.Payload.Approval).RefusalKey(kind)
		Do $$$AssertEquals(key, "answered.notApprover", "'"_kind_"' has the fallback key")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(key, {}, "web"), fallback, "'"_kind_"' has the fallback sentence")
	}
	For kind = "", "resend", "zz_new" {
		Set key = ##class(OcuTalon.Live.Payload.Approval).RefusalKey(kind, 1)
		Do $$$AssertEquals(key, "answered.notAdmin", "admin gives answered.notAdmin for '"_kind_"'")
	}
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("answered.notAdmin", {}, "web"), "Only an OcuTalon admin can approve this email.", "whose sentence is the approved text")
	Do $$$AssertEquals(##class(OcuTalon.Live.Payload.Approval).RefusalKey(), "answered.notApprover", "no argument is the fallback")
}

/// Story 25.5: FromRow sets answerable and approverKind only for a pending request and a session; every other payload is answerable with no kind.
Method TestPayloadAnswerable()
{
	Set mine = ..Session("a")
	Set pending = ..Approval(mine), allowed = ..Approval(mine), answered = ##class(OcuTalon.Test.Data.Fixture).Approval(mine, "", "approved")
	Set ..Refs = ..Refs_","_answered
	Set double = "OcuTalon.Test.Core.ApprovalDouble"
	Do $CLASSMETHOD(double, "Begin")
	Do $CLASSMETHOD(double, "May", pending, 0, "reroute")
	Do $CLASSMETHOD(double, "May", allowed, 1, "")
	Do $CLASSMETHOD(double, "May", answered, 0, "reroute")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending), mine, double)
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "0|reroute", "a pending request that the session may not answer: not answerable, with the kind")
	Do payload.%JSONExportToString(.json)
	Set object = {}.%FromJSON(json)
	Do $$$AssertEquals(object.%GetTypeOf("answerable")_"|"_object.answerable_"|"_object.approverKind, "boolean|0|reroute", "as the payload's JSON members answerable (a boolean) and approverKind")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(allowed), mine, double)
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "1|", "a pending request that it may answer: answerable, with no kind")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(answered), mine, double)
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "1|", "an answered request is answerable whatever the check says")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending), "", double)
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "1|", "a payload for no session is answerable")
	Do $$$AssertEquals($CLASSMETHOD(double, "MayCalls"), 2, "and only the two pending payloads for a session asked the role check")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending), ##class(OcuTalon.Bridge.Ids).NewRef(), double)
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "0|", "a Ref-shaped session with no row may not answer, with no kind")
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending), mine, "OcuTalon.Test.Core.NoSuchApprovalApi")
	Do $$$AssertEquals(payload.Answerable_"|"_payload.ApproverKind, "0|", "an error of the role check is not answerable")
}

/// Story 25.5, AC 7 (Story 22.7's rule composed with rule 6): a user who passes the role check but is no admin gets {"kind": "email", "admin": true} for an approve of an email request to another address,
/// by AnswerOps' real rule, and a reject is handed over.
Method TestEmailAdminRefusal()
{
	Set mine = ..Session("a")
	Set recipients = ["partner@example.test"]
	Set parameters = {"recipients": (recipients), "subject": "zz subject", "text": "zz text"}
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(mine, "", "pending", , {"FixKind": "email", "FixParameters": (parameters.%ToJSON()), "DryRun": ({"to": (recipients), "subject": "zz subject", "text": "zz text"}.%ToJSON())})
	Set ..Refs = ..Refs_","_request
	Set probe = ..NewProbe()
	Set double = "OcuTalon.Test.Core.ApprovalDouble"
	Do $CLASSMETHOD(double, "Begin")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "not_allowed", "an approve by a user who is no admin is not_allowed")
	Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{""kind"":""email"",""admin"":true}", "with the email kind and the admin mark")
	Do $$$AssertEquals($CLASSMETHOD(double, "MayCalls"), 1, "after the role check passed")
	Do $$$AssertEquals($CLASSMETHOD(double, "Calls"), 0, "and Approval.Answer was not called")
	Do ..Answer(probe, request, "reject", "web", mine, .output)
	Do $$$AssertEquals(output.Result, "done", "a reject of the same request is handed over")
	Do $$$AssertEquals($CLASSMETHOD(double, "Calls")_"|"_$CLASSMETHOD(double, "Arg", 1, "action"), "1|reject", "and reaches Approval.Answer")
	Do $$$AssertEquals(probe.Refusal.%ToJSON(), "{}", "with no refusal")
	Do $CLASSMETHOD(double, "Begin")
	Do $CLASSMETHOD(double, "May", request, 0, "email")
	Do ..Answer(probe, request, "approve", "web", mine, .output)
	Do $$$AssertEquals(output.Result_"|"_probe.Refusal.%ToJSON(), "not_allowed|{""kind"":""email""}", "a refusal by the role check keeps the kind and has no admin mark")
}

Method TestNoAllowanceOrConversation()
{
	For class = "OcuTalon.Core.AnswersIn", "OcuTalon.Core.AnswerOps" {
		Set code = ""
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = ?", class)
		While result.%Next() {
			Set stream = ##class(%Dictionary.MethodDefinition).%OpenId(class_"||"_result.%Get("Name")).Implementation
			Set code = code_stream.Read(1000000)
		}
		Do $$$AssertTrue(code [ "Msg.Answer", "control: the code of "_class_" was read")
		Do $$$AssertEquals(code [ "Allowance", 0, class_" does not name Allowance")
		Do $$$AssertEquals(code [ "Conversation", 0, class_" does not name Conversation")
	}
}

/// QA (AC14, owner condition U-113): AnswersIn is AnswerOps' only sender. Run time refuses any other source (TestAnswerOpsRefusesOtherSenders);
/// this reads the compiled product and finds no other class that names the item as a target, and one send in AnswersIn.
Method TestAnswersInIsTheOnlySender()
{
	Set target = """AnswerOps"""
	Set seen = 0, others = ""
	Set classes = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name LIKE 'OcuTalon.%' AND Name NOT LIKE 'OcuTalon.Test.%'")
	Do $$$AssertEquals(classes.%SQLCODE, 0, "control: the class list is read")
	While classes.%Next() {
		Set class = classes.%Get("Name")
		Set found = 0
		Set methods = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = ?", class)
		While methods.%Next() {
			Set stream = ##class(%Dictionary.MethodDefinition).%OpenId(class_"||"_methods.%Get("Name")).Implementation
			If stream.Size '= 0, stream.Read(stream.Size) [ target Set found = 1
		}
		Set params = ##class(%SQL.Statement).%ExecDirect(, "SELECT Default FROM %Dictionary.ParameterDefinition WHERE parent = ?", class)
		While params.%Next() {
			If params.%Get("Default") [ "AnswerOps" Set found = 1
		}
		Set seen = seen + 1
		If found, class '= "OcuTalon.Core.AnswersIn", class '= "OcuTalon.Core.AnswerOps" Set others = others_" "_class
	}
	Do $$$AssertTrue(seen > 100, "control: the product's classes were read ("_seen_")")
	Do $$$AssertEquals(others, "", "no other class names AnswerOps as a target")
	Set sends = 0, code = ""
	Set methods = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = 'OcuTalon.Core.AnswersIn'")
	While methods.%Next() {
		Set stream = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Core.AnswersIn||"_methods.%Get("Name")).Implementation
		If stream.Size = 0 Continue
		Set text = stream.Read(stream.Size)
		Set sends = sends + $Length(text, "SendRequest") - 1
		If text [ target Set code = methods.%Get("Name")
	}
	Do $$$AssertEquals(sends, 1, "AnswersIn makes exactly one send")
	Do $$$AssertEquals(code, "Send", "and it is the private Send method, which names AnswerOps")
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Production||ProductionDefinition")
	Do $$$AssertTrue($IsObject(xdata), "control: the production's definition is read")
	If $IsObject(xdata) {
		Set text = xdata.Data.Read(xdata.Data.Size)
		Do $$$AssertEquals($Length(text, "AnswerOps") - 1, 2, "the production names AnswerOps only in its own item (its name and its class): no item or setting targets it")
	}
}

/// --- helpers ---
/// A fixture session of its own IRIS user; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..#USER_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture fix request of the owner, for the incident when given; its Ref is kept for the clean-up.
Method Approval(owner As %String, incidentRef As %String = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incidentRef)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The number of event-log rows of the type (2 error, 3 warning) that the running class (the probe) logged after the row mark.
ClassMethod LogRows(mark As %Integer, type As %Integer, class As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = ? AND SourceClass = ?", mark, type, class)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Removes the event-log rows that the class logged after the row mark.
ClassMethod RemoveLogRows(mark As %Integer, class As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", mark, class)
}

/// A shadow instance of the probe.
Method NewProbe() As OcuTalon.Test.Core.AnswersInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswersInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Quit probe
}

/// Hands the answer to the probe's OnProcessInput; output is the AnswerResult.
Method Answer(probe As OcuTalon.Test.Core.AnswersInProbe, ref As %String, action As %String, channel As %String, sessionRef As %String, Output output As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = ref
	Set answer.Action = action
	Set answer.Channel = channel
	Set answer.SessionRef = sessionRef
	Quit probe.OnProcessInput(answer, .output)
}

}
