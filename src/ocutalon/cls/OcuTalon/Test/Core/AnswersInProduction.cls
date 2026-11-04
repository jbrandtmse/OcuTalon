/// Tests of the answer path through the running production and the real approval API (Story 6.2; AD-1, AD-4, AD-11, AD-20, AD-26;
/// DW-98, DW-199). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (InProduction). Each test calls Web.Api.AnswerApproval as the REST
/// surface does: a stand-in request with the body (StubRequest.MakeBody), a CSP session bound to a fixture session of this process's
/// user (Ownership.SessionRef accepts only a session of the signed-in user), and the capture of Test.Web.Api.Written. The fixture rows
/// need a role that this process's user holds (HeldRole: the first of its recursed role set, %All for the container's owner), because
/// the README account that holds OcuTalonUser is not this process. A fixture row has no hold, so each real answer waits the 5 seconds of
/// Approval.CompleteHoldTask for a task that never appears, and logs one warning, which the tests remove.
///   - TestApproveRecordsTheAnswer: 200, the row approved by this process's user on the web channel (a body that names another user
///     and another SessionRef changes nothing, U-113), one approval event on the session's stream, one AnswersIn to AnswerOps header
///     tagged with the session's TraceRef, no Turn and no chat.message event (AC4, AC13, AC14);
///   - TestSecondPressIsAlreadyAnswered, TestExpiredRequestAnswersExpired: 409 with the catalog's text and the request's payload;
///   - TestRoleRefusalsComeBeforeTheOtherChecks: a missing role is 403 with the row unchanged, for a pending, an answered, an expired
///     and a past-expiry request, and the 403 has no approval payload (AC14, AC15);
///   - TestOnlineDemoOtherSessionIsNotFound: with onlineDemo on, another session's answer to a session's own request, to its instance
///     request and to an unknown ref is the same 404; the rows stay pending, no event reaches either stream and no header is made
///     (the required check, AC5);
///   - TestLatePressNamesAnotherUserOnALocalInstall: the 409 of an already answered request names another user's answer on a local
///     install, and names no one for the signed-in user (whatever the case) or on the online demo;
///   - TestOthersAnsweredRequestsAreNotFoundWithNoPayload (QA, AC15): another session's answered, rejected, expired, past-expiry,
///     role-less and unwatched instance requests are all the 404 of an unknown ref, with no approval payload, on a local install and
///     on the online demo;
///   - TestCancelledAndBadBodies: a cancelled request is 404 whatever the body, with nothing sent, a body that is not an answer is
///     400 with nothing sent, and a rejection from the phone (Story 6.3's channel) is answered;
///   - TestMalformedSessionRefIsNotAllowed (DW-199): Approval.Answer given a SessionRef that is not a Ref answers not_allowed and
///     changes nothing, and an empty one answers;
///   - TestGateStepAndHeldCallReachTheStream (DW-98): in a running turn's bridge context the real gate reports a safe built-in's
///     turn.step to the session's stream, and an unclassified call's pending approval event and, once the answer endpoint rejects it,
///     its rejected event reach the stream, through BridgeSink;
///   - TestHeldCallExpiresOnTheStream, TestHeldCallCancelledOnTheStream (Story 2.8): a request that the real gate raised for a held
///     call. Expired: its hold is deleted, the row is aged past its expiry and the approvals area's Reconcile (OcuTalon.Install.Step.Approvals,
///     which the Reconcile step calls) re-arms a hold whose timer expires it, as in Test.Bridge.Approval.TestTimerExpires; only that area
///     reconciles, because Conversation's would run again the fixture turns that HeldCall leaves running; the stream gets an expired
///     approval event and the answer endpoint answers 409 expired. Cancelled by Approval.Cancel with the arguments of
///     SessionOps.EndApprovals: the stream gets a cancelled event and the endpoint answers 404 as for an unknown ref. TestExpiredRequestAnswersExpired also sees the expired event of an answer past the
///     expiry.
Class OcuTalon.Test.Core.AnswersInProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzansprod";

/// The longest to wait for an event, in seconds.
Parameter EVENTSECONDS = 20;

/// The online-demo flag before the run.
Property OnlineWas As %String;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..OnlineWas = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineWas)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner($Piece(..Sessions, ",", i))
	}
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Quit ##super()
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
	Quit $$$OK
}

Method TestApproveRecordsTheAnswer()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set request = ..Request(mine)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(mine).TraceRef
	Set other = ..WebSession("b")
	Set body = ..Post(mine, request, "{""action"":""approve"",""channel"":""web"",""irisUser"":""mallory"",""sessionRef"":"""_other_""",""AnsweredBy"":""mallory""}", .status)
	Do $$$AssertEquals(status, "200 OK", "the answer is 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.approval.ref_"|"_answer.approval.state, "done|"_request_"|approved", "with the result and the approved request: "_body)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredAction_"|"_row.AnsweredChannel, "approved|approve|web", "the row is approved from the web")
	Do $$$AssertEquals(row.AnsweredBy, $Username, "by the signed-in session's IRIS user, whatever the body names (U-113)")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(mine, "approval", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 1, "one approval event reaches the session's stream")
	If events.%Size() > 0 Do $$$AssertEquals(events.%Get(0).payload.state, "approved", "and it is the answered request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(other, "approval").%Size(), 0, "none reaches the other session's")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "AnswersIn", "AnswerOps")
	Do $$$AssertEquals(headers.%Size(), 1, "one AnswersIn to AnswerOps header carries the session's TraceRef as its SuperSession")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(mine, .sc).Count(), 0, "the answer made no Turn")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(mine, "chat.message").%Size(), 0, "and no chat.message")
	Do ..RemoveTaskWarnings(request)
}

Method TestSecondPressIsAlreadyAnswered()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set request = ..Request(mine)
	Do ..Post(mine, request, ..Approve(), .status)
	Do $$$AssertEquals(status, "200 OK", "control: the first press is 200")
	Set body = ..Post(mine, request, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "409 Conflict", "a second press is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "already_answered", "already_answered")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("answered.alreadyApproved", {"channel": "web", "time": (row.AnsweredAt)}, "web", .sc)
	Do $$$AssertStatusOK(sc, "control: the catalog renders the text")
	Do $$$AssertEquals(answer.error.message, expected, "with the catalog's text for the winner")
	Do $$$AssertTrue(expected [ "Already answered: approved from the web chat at ", "which names the winner's action and channel: "_expected)
	Do $$$AssertEquals(answer.approval.ref_"|"_answer.approval.state, request_"|approved", "and the request's payload")
	Do $$$AssertEquals(row.State, "approved", "the first answer stands")
	Do ..RemoveTaskWarnings(request)
}

Method TestExpiredRequestAnswersExpired()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set request = ..Request(mine, , , {"ExpiresAt": "2020-01-01T00:00:00Z"})
	Set body = ..Post(mine, request, ..Approve(), .status)
	Do $$$AssertEquals(status, "409 Conflict", "a pending request past its expiry is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "expired", "expired")
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("answered.expired", {"time": "2020-01-01T00:00:00Z"}, "web", .sc)
	Do $$$AssertEquals(answer.error.message, expected, "with the catalog's text at the row's ExpiresAt")
	Do $$$AssertEquals(answer.approval.ref_"|"_answer.approval.state, request_"|expired", "and the expired request's payload: "_body)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(row.State, "expired", "the row is expired")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(mine, "approval", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 1, "one approval event reaches the session's stream")
	If events.%Size() > 0 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, request_"|expired", "and it is the expired request")
}

Method TestRoleRefusalsComeBeforeTheOtherChecks()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set missing = {"RequiredRole": "ZzNoSuchRole"}
	Set pending = ..Request(mine, , , missing)
	Set body = ..Post(mine, pending, ..Approve(), .status)
	Do $$$AssertEquals(status, "403 Forbidden", "a user without the row's role gets 403")
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_allowed"",""message"":""Only an approver for resends can answer this request.""}}", "with the approver text of a fix and no payload")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending).State, "pending", "the request is still pending")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(mine, "approval").%Size(), 0, "and no event was published")
	Set answered = ..Request(mine, "approved", , {"RequiredRole": "ZzNoSuchRole", "AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredBy": "ocutalon", "AnsweredAt": "2030-01-01T14:15:00Z"})
	Set pastExpiry = ..Request(mine, , , {"RequiredRole": "ZzNoSuchRole", "ExpiresAt": "2020-01-01T00:00:00Z"})
	Set expired = ..Request(mine, "expired", , {"RequiredRole": "ZzNoSuchRole"})
	For ref = answered, pastExpiry, expired {
		Set state = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State
		Set body = ..Post(mine, ref, ..Approve(), .status)
		Do $$$AssertEquals(status, "403 Forbidden", "a "_state_" request is 403 too, never 409")
		Do $$$AssertEquals($Piece(body, ",", 1), "{""error"":{""code"":""not_allowed""", "with not_allowed")
		Do $$$AssertEquals({}.%FromJSON(body).%IsDefined("approval"), 0, "and no approval payload")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, state, "the row is as it was")
	}
	Set tool = ..Request(mine, , "tool_call", {"RequiredRole": "ZzNoSuchRole", "ToolName": "zz_tool", "ToolArguments": "{}", "DryRun": ""})
	Set body = ..Post(mine, tool, ..Approve(), .status)
	Do $$$AssertEquals(status, "403 Forbidden", "a tool_call request is 403")
	Do $$$AssertEquals(body, "{""error"":{""code"":""not_allowed"",""message"":""Only an approver can answer this request.""}}", "with the approver text of any other kind")
}

Method TestLatePressNamesAnotherUserOnALocalInstall()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set at = "2030-01-01T14:15:00Z"
	Set approved = ..Request(mine, "approved", , {"AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredBy": "zzsam", "AnsweredAt": (at)})
	Set rejected = ..Request(mine, "rejected", , {"AnsweredAction": "reject", "AnsweredChannel": "phone", "AnsweredBy": "zzsam", "AnsweredAt": (at)})
	Set same = $Select($ZConvert($Username, "U") = $Username: $ZConvert($Username, "L"), 1: $ZConvert($Username, "U"))
	Set self = ..Request(mine, "approved", , {"AnsweredAction": "approve", "AnsweredChannel": "web", "AnsweredBy": (same), "AnsweredAt": (at)})
	Set slots = {"channel": "phone", "time": (at), "user": "zzsam"}
	Set plain = {"channel": "phone", "time": (at)}
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("answered.alreadyApprovedBy", slots, "web", .sc)
	Do $$$AssertStatusOK(sc, "control: the catalog renders the named text")
	Do ..AssertLate(mine, approved, expected, "another user's approval names the user")
	Do ..AssertLate(mine, rejected, ##class(OcuTalon.Msg.Catalog).Render("answered.alreadyRejectedBy", slots, "web"), "and so does another user's rejection")
	Do ..AssertLate(mine, self, ##class(OcuTalon.Msg.Catalog).Render("answered.alreadyApproved", {"channel": "web", "time": (at)}, "web"), "the signed-in user's own answer is not named, whatever the case of the name")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..AssertLate(mine, approved, ##class(OcuTalon.Msg.Catalog).Render("answered.alreadyApproved", plain, "web"), "on the online demo nobody is named")
}

/// The 409 for the already answered request names the catalog's text.
Method AssertLate(session As %String, ref As %String, expected As %String, what As %String) [ Private ]
{
	Set body = ..Post(session, ref, ..Approve(), .status)
	Do $$$AssertEquals(status, "409 Conflict", what_": 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "already_answered|"_expected, what_": "_body)
}

Method TestOnlineDemoOtherSessionIsNotFound()
{
	If '..Guard() Quit
	Set a = ..WebSession("a"), b = ..WebSession("b")
	Set production = "Zz.Answers"_..Number_".Watched"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set own = ..Request(a)
	Set instance = ..Request("instance", , , , incident)
	Set ..Refs = ..Refs_","_incident
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.Ownership).Approval(instance, b)), "control: on a local install session B, which watches the production, sees the instance request")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set unknown = ..Post(b, "zzmissing"_..Number, ..Approve(), .status)
	Do $$$AssertEquals(status, "404 Not Found", "control: an unknown ref is 404")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef, traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(traceA).%Size() + ##class(OcuTalon.Test.Data.Fixture).Headers(traceB).%Size()
	For ref = own, instance {
		Set body = ..Post(b, ref, ..Approve(), .status)
		Do $$$AssertEquals(status, "404 Not Found", "session B answering "_ref_" is 404")
		Do $$$AssertEquals(body, unknown, "with the body of an unknown ref")
		Set body = ..Post(b, ref, "not json", .status)
		Do $$$AssertEquals(body, unknown, "whatever the body")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, "pending", "the request stays pending")
		Set result = ..FromPageAs(b, ref)
		Do $$$AssertEquals(result, "not_found", "AnswersIn.FromPage for session B's page is not_found too")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "approval").%Size()_"|"_##class(OcuTalon.Test.Core.Observe).Events(b, "approval").%Size(), "0|0", "no event reached either stream")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Headers(traceA).%Size() + ##class(OcuTalon.Test.Data.Fixture).Headers(traceB).%Size(), headers, "and the answers made no message in either session's trace")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(own)
	Do $$$AssertEquals(row.AnsweredBy_row.AnsweredChannel_row.AnsweredAt, "", "the request has no answerer")
}

/// QA (AC15 with AC5): a request that the session can't see is 404 with the body of an unknown ref whatever its state, so a caller who
/// may not answer never gets the approval payload of an answered or expired request in a 409 (and never a 403 either).
Method TestOthersAnsweredRequestsAreNotFoundWithNoPayload()
{
	If '..Guard() Quit
	Set a = ..WebSession("a"), b = ..WebSession("b")
	Set at = "2030-01-01T14:15:00Z"
	Set unknown = ..Post(b, "zzmissing"_..Number, ..Approve(), .status)
	Do $$$AssertEquals(status, "404 Not Found", "control: an unknown ref is 404")
	Set answered = {"AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredBy": "zzsam", "AnsweredAt": (at)}
	Set noRole = {"RequiredRole": "ZzNoSuchRole"}
	Set refs = ""
	Set refs = refs_$ListBuild(..Request(a, "approved", , answered))
	Set refs = refs_$ListBuild(..Request(a, "rejected", , answered))
	Set refs = refs_$ListBuild(..Request(a, "expired"))
	Set refs = refs_$ListBuild(..Request(a, , , {"ExpiresAt": "2020-01-01T00:00:00Z"}))
	Set refs = refs_$ListBuild(..Request(a, "approved", , {"RequiredRole": "ZzNoSuchRole", "AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredBy": "zzsam", "AnsweredAt": (at)}))
	Set refs = refs_$ListBuild(..Request(a, "expired", , noRole))
	Set unwatched = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", "Zz.Answers"_..Number_".Unwatched")
	Set ..Refs = ..Refs_","_unwatched
	Set refs = refs_$ListBuild(..Request("instance", "approved", , answered, unwatched))
	For online = 0, 1 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online)
		Set position = 0
		While $ListNext(refs, position, ref) {
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
			Set state = row.State, by = row.AnsweredBy
			Set body = ..Post(b, ref, ..Approve(), .status)
			Do $$$AssertEquals(status, "404 Not Found", "onlineDemo "_online_": session B pressing a "_state_" request of A is 404, not 409 or 403")
			Do $$$AssertEquals(body, unknown, "with the body of an unknown ref")
			Do $$$AssertEquals({}.%FromJSON(body).%IsDefined("approval"), 0, "and no approval payload")
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
			Do $$$AssertEquals(row.State_"|"_row.AnsweredBy, state_"|"_by, "the row is as it was")
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "approval").%Size()_"|"_##class(OcuTalon.Test.Core.Observe).Events(b, "approval").%Size(), "0|0", "no event reached either stream")
}

Method TestCancelledAndBadBodies()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set unknown = ..Post(mine, "zzmissing"_..Number, ..Approve(), .status)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(mine).TraceRef
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace).%Size()
	Set cancelled = ..Request(mine, "cancelled")
	For json = ..Approve(), "not json" {
		Set body = ..Post(mine, cancelled, json, .status)
		Do $$$AssertEquals(status, "404 Not Found", "a cancelled request is 404 for the body '"_json_"'")
		Do $$$AssertEquals(body, unknown, "with the body of an unknown ref")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Headers(trace).%Size(), headers, "nothing was sent for it")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(cancelled).State, "cancelled", "and it stays cancelled")
	Set pending = ..Request(mine)
	Set error = "{""error"":{""code"":""bad_answer"",""message"":""An answer needs an action, approve or reject, and a channel, web or phone.""}}"
	For bad = "", "[]", "not json", "{}", "{""action"":""approve""}", "{""channel"":""web""}", "{""action"":""delete"",""channel"":""web""}", "{""action"":""approve"",""channel"":""telegram""}", "{""action"":""approve"",""channel"":""email""}", "{""action"":1,""channel"":""web""}", "{""action"":""Approve"",""channel"":""web""}" {
		Set body = ..Post(mine, pending, bad, .status)
		Do $$$AssertEquals(status, "400 Bad Request", "the body '"_bad_"' is 400")
		Do $$$AssertEquals(body, error, "bad_answer")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Headers(trace).%Size(), headers, "nothing was sent")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(pending).State, "pending", "and the request is pending")
	Set body = ..Post(mine, "zzmissing"_..Number, "not json", .status)
	Do $$$AssertEquals(body, unknown, "an unknown ref is 404 whatever the body")
	Set phone = ..Request(mine)
	Set body = ..Post(mine, phone, "{""action"":""reject"",""channel"":""phone""}", .status)
	Do $$$AssertEquals(status, "200 OK", "a rejection from the phone is answered")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(phone)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredChannel, "rejected|phone", "and the request is rejected from the phone")
	Do ..RemoveTaskWarnings(phone)
}

Method TestMalformedSessionRefIsNotAllowed()
{
	If '..Guard() Quit
	Set mine = ..WebSession("a")
	Set request = ..Request(mine)
	Set user = $Username
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(request, "approve", "web", user, "not-a-session-ref", .winner)
	Do $$$AssertEquals(result, "not_allowed", "a SessionRef that is not a Ref is not_allowed")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", "and changes nothing")
	Set result = ##class(OcuTalon.Bridge.Approval).Answer(request, "approve", "web", user, "", .winner)
	Do $$$AssertEquals(result, "done", "control: an empty SessionRef answers")
	Do ..RemoveTaskWarnings(request)
}

Method TestGateStepAndHeldCallReachTheStream()
{
	If '..Guard() Quit
	Set session = ..WebSession("gate")
	Set ref = ..HeldCall(session)
	If ref = "" Quit
	Set body = ..Post(session, ref, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "rejecting it through the answer endpoint is 200")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 2, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 2, "a second approval event reaches the stream")
	If events.%Size() > 1 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.state, ref_"|rejected", "and it is the rejected request")
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
}

Method TestHeldCallExpiresOnTheStream()
{
	If '..Guard() Quit
	Set session = ..WebSession("hexp")
	Set ref = ..HeldCall(session)
	If ref = "" Quit
	Set hold = ..WaitLiveHold(ref)
	Do $$$AssertTrue(hold '= "", "the raised request has a live hold")
	If hold = "" Quit
	Do ##class(OcuTalon.Test.Bridge.Approval).Age(ref, 86460, -60)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(hold), "its hold is deleted, as a restart leaves a request without one")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Approvals).Reconcile(), "the approvals area's Reconcile re-arms a hold, whose timer finds the request past its expiry")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 2, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 2, "a second approval event reaches the stream")
	If events.%Size() > 1 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.state, ref_"|expired", "and it is the expired request")
	Set body = ..Post(session, ref, ..Approve(), .status)
	Do $$$AssertEquals(status, "409 Conflict", "an answer to the expired request is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code_"|"_answer.approval.state, "expired|expired", "expired, with the request's payload: "_body)
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
}

Method TestHeldCallCancelledOnTheStream()
{
	If '..Guard() Quit
	Set session = ..WebSession("hcan")
	Set ref = ..HeldCall(session)
	If ref = "" Quit
	Set unknown = ..Post(session, "zzmissing"_..Number, ..Approve(), .status)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(ref, "", "web", $Username, session), "Approval.Cancel cancels it as SessionOps ends a session's requests")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 2, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 2, "a second approval event reaches the stream")
	If events.%Size() > 1 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.state, ref_"|cancelled", "and it is the cancelled request")
	Set body = ..Post(session, ref, ..Approve(), .status)
	Do $$$AssertEquals(status, "404 Not Found", "an answer to the cancelled request is 404")
	Do $$$AssertEquals(body, unknown, "with the body of an unknown ref")
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
}

/// --- helpers ---
/// In a running turn's bridge context, the real gate reports a safe built-in's step to the session's stream (asserted), and holds an unclassified
/// call: the pending tool_call request reaches the stream (asserted) and needs a role that this user holds. Answers the request's Ref, or "" when
/// no pending event arrived. The session's requests are tracked for Test.Bridge.Approval.Clean.
Method HeldCall(session As %String) As %String [ Private ]
{
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, , "running")
	Set ..Refs = ..Refs_","_turn
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(turn)
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.Kind = "turn"
	Set begin.Provenance = "user"
	Set begin.ItemId = row.ItemId
	Set begin.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set begin.OwnerRef = session
	Set begin.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set begin.Channel = "web"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(begin), "a running turn's bridge context begins")
	Set gate = "OcuTalon.Bridge.Policy.Gate"
	Set sc = $ClassMethod(gate, "Check", "set_reminder", {"id": "call_id", "name": "set_reminder", "arguments": {}}, {"origin_class": "OcuTalon.Tools.ReminderTools", "requires_auth": false}, "")
	Do $$$AssertStatusOK(sc, "the real gate allows a safe built-in")
	Set steps = ##class(OcuTalon.Test.Core.Observe).Events(session, "turn.step", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(steps.%Size(), 1, "one turn.step reaches the session's stream through BridgeSink")
	If steps.%Size() > 0 Do $$$AssertEquals(steps.%Get(0).payload.turnRef_"|"_steps.%Get(0).payload.label, turn_"|Setting a reminder", "with the running turn's Ref and the step's label")
	Set sc = $ClassMethod(gate, "Check", "zz_mcp_other", {"id": "call_id", "name": "zz_mcp_other", "arguments": {}}, {}, "")
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "an unclassified call is held")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner(session)
	Set held = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(held.%Size(), 1, "its pending approval event reaches the stream")
	If held.%Size() < 1 Quit ""
	Set payload = held.%Get(0).payload
	Do $$$AssertEquals(payload.kind_"|"_payload.state, "tool_call|pending", "as a pending tool_call request")
	Set ref = payload.ref
	Set approval = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set approval.RequiredRole = ..HeldRole()
	Do $$$AssertStatusOK(approval.%Save(), "the held request needs a role that this user holds")
	Quit ref
}

/// A fixture session of this process's user (Ownership.SessionRef accepts only a session of the signed-in user).
Method WebSession(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session "_name_" belongs to "_$Username)
	Quit ref
}

/// The id of the request's live hold once it has one (the hold starts after the request is raised); after EVENTSECONDS seconds, "".
Method WaitLiveHold(ref As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#EVENTSECONDS
	For {
		Set hold = ##class(OcuTalon.Bridge.Approval).LiveHold(ref)
		If (hold '= "") || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit hold
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// A fixture request of the owner: a pending fix of the incident (when given) that this process's user may answer. state, kind and
/// fields change the defaults; its Ref is kept for the clean-up.
Method Request(owner As %String, state As %String = "pending", kind As %String = "fix", fields As %DynamicObject = "", incident As %String = "") As %String [ Private ]
{
	Set all = {"RequiredRole": (..HeldRole()), "Kind": (kind)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The body of an approval from the web.
ClassMethod Approve() As %String [ Private ]
{
	Quit "{""action"":""approve"",""channel"":""web""}"
}

/// Calls Web.Api.AnswerApproval for the ref as the session's user with the body, and returns what it wrote; status is the response's.
Method Post(session As %String, ref As %String, json As %String, Output status As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzAnswers"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "AnswerApproval", ref)
	Do $$$AssertStatusOK(sc, "AnswerApproval returns OK")
	Set status = %response.Status
	Quit body
}

/// Calls AnswersIn.FromPage for the ref with approve and web, as the session's page does, and returns the AnswerResult's Result (or the status text).
Method FromPageAs(session As %String, ref As %String) As %String [ Private ]
{
	New %session
	Set %session = ##class(%CSP.Session).%New("ZzAnswersPage"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set sc = ##class(OcuTalon.Core.AnswersIn).FromPage(ref, "approve", "web", .result, .answeringRef)
	Quit $Select($SYSTEM.Status.IsError(sc): $SYSTEM.Status.GetErrorText(sc), 1: result.Result)
}

/// Removes the warning that Approval.CompleteHoldTask logged for the request's missing task.
Method RemoveTaskWarnings(ref As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_ref)
}

}
