/// The integration tests of the tool-call notices (Story 31.5, and Story 31.6 for the web chat; AD-31, AD-32, U-212, DW-601), over the
/// running production and the real replay: a call that the gate holds for a fixture session reaches the simulated phone with Approve
/// and Reject, the answer edits the request's message in place, and the result is a new message with no buttons. The web chat gets the
/// same Notification as cards: the request with the phone's text, and the result. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): they put ZzReplayAgent behind ChatAgent and point the runners' keys at the CI mock's key, and put both back after the
/// run. They read the phone, and the session's web Delivery rows and RecentNotices.
///   - TestApprovedCallReachesThePhone: the request message (the phone render of toolCall.request, the session's ApprovalRef, no
///     answer); after Approve its Answer is the render of answered.approved; a second message is the render of toolCall.done, with no
///     ApprovalRef and no answer;
///   - the same test, for the web chat: a row of kind approval with the same text as the phone's, a row of kind result with the web
///     render of toolCall.done (these two are the chat's cards, in RecentNotices), and the answered notice's row with no
///     ChannelMessageId, which is not a card;
///   - TestChangedResultSendsANotice (Story 22.4, R1; DW-1232): a call that ends with the result changed (an approved MCP call whose tool changed) sends the owner a result notice: the web
///     chat gets a card of kind result for the request with the web render of mcp.replayToolChanged, and the phone a new message with its phone render;
///   - TestCancelledEditsInPlace (Story 21.10): an MCP request whose server has no row, cancelled through Approval Cancel, becomes the phone render of answered.canceled in its own
///     message, with no second message, and the web chat has the answered notice's row only;
///   - TestRejectedAndExpiredEditInPlace: a rejected call gets the render of answered.rejected and an expired one the render of
///     answered.expired in the request's message, and neither adds a message.
///   - TestHeldReasonReachesTheWebChat (DW-454): an old held call closed by Decide with the bridge's sentence reaches the web chat as
///     a result card with the sentence, the Decision's Ref as DecisionRef and no request;
///   - TestHeldRawReasonIsNeverShownInTheWebChat (QA): the same for a Decision whose first line is not the bridge's sentence: the
///     toolCall.failed card with the Decision's Ref, and none of the raw line.
/// Each test makes its own sessions and removes its rows (Test.Bridge.Approval Clean ends the holds and deletes the requests).
Class OcuTalon.Test.Core.ToolCallNotices Extends OcuTalon.Test.Core.InProduction
{

/// Seconds to wait for a message of the phone.
Parameter WAIT = 40;

/// The tool of the held call, and its class.
Parameter TOOL = "zz_replay_send";

Parameter TOOLCLASS = "OcuTalon.Test.Bridge.ZzReplayTool";

/// The IRIS user who answers: it holds OcuTalonUser.
Parameter ANSWERER = "ocutalon";

/// 1 once ZzReplayAgent is behind ChatAgent for this run.
Property Swapped As %Boolean [ InitialExpression = 0 ];

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Do ..Restore()
	Quit ##super()
}

Method TestApprovedCallReachesThePhone()
{
	If '..Guard() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseReplayAgent() Quit
	Set session = ..Session("approved")
	Set ref = ..HeldCall(session)
	If ref = "" Quit

	Set message = ..WaitMessage(session, ref, 1)
	Do $$$AssertTrue($IsObject(message), "the phone gets the request's message within "_..#WAIT_" seconds")
	If '$IsObject(message) Quit
	Set row = ..Request(ref)
	Set expected = ..Render("toolCall.request", {"tool": (..#TOOL), "inputs": (##class(OcuTalon.Core.BridgeSink).InputsOf(row.ToolArguments))})
	Do $$$AssertEquals(message.Text, expected, "its text is the phone render of toolCall.request")
	Do $$$AssertEquals($Piece(message.Text, $Char(10), 1), "Run "_..#TOOL, "which starts with the tool")
	Do $$$AssertEquals(message.ApprovalRef_"|"_message.Answer, ref_"|", "it carries the request's Ref, so that the phone draws Approve and Reject, and no answer")
	Set messageRef = message.Ref
	Set webRequest = ..WaitWebRow(session, "approval", 1)
	Do $$$AssertTrue($IsObject(webRequest), "the web chat gets a row of kind approval")
	If $IsObject(webRequest) {
		Do $$$AssertEquals(webRequest.ApprovalRef, ref, "with the request's Ref as ApprovalRef")
		Do $$$AssertEquals(webRequest.Text, message.Text, "and the phone's text: one Notification, one text (DW-601)")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "it is a card of the web chat")
	}

	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "phone", user, session, .winner), "done", "Approve is accepted")
	Do $$$AssertEquals(..WaitState(ref, "done", 40), "done", "the replay finishes: "_..Facts(ref, session))
	Set row = ..Request(ref)
	Set approved = ..Render("answered.approved", {"channel": "phone", "time": (row.AnsweredAt)})
	Set message = ..WaitAnswer(messageRef)
	Do $$$AssertEquals(message.Answer, approved, "the request's message has the render of answered.approved as its Answer: "_..Facts(ref, session))
	Do $$$AssertEquals(message.Text_"|"_message.ApprovalRef, expected_"|"_ref, "and keeps its text and request")

	Set done = ..WaitMessage(session, "", 2)
	Do $$$AssertTrue($IsObject(done), "a second message arrives")
	If '$IsObject(done) Quit
	Do $$$AssertEquals(done.Text, ..Render("toolCall.done", {"tool": (..#TOOL), "time": (row.FinishedAt)}), "it is the phone render of toolCall.done")
	Do $$$AssertEquals(done.ApprovalRef_"|"_done.Answer, "|", "with no ApprovalRef and no answer, so no buttons")
	Do $$$AssertEquals(..Message(messageRef).Answer, approved, "and the request's message keeps its answer")
	Do $$$AssertEquals(..PhoneCount(session), 2, "the phone holds exactly the two messages")
	Set webResult = ..WaitWebRow(session, "result", 1)
	Do $$$AssertTrue($IsObject(webResult), "the web chat gets a second row, of kind result")
	If $IsObject(webResult) {
		Do $$$AssertEquals(webResult.Text, ..Render("toolCall.done", {"tool": (..#TOOL), "time": (row.FinishedAt)}, "web"), "with the web render of toolCall.done")
		Do $$$AssertEquals(webResult.ApprovalRef, ref, "and the request's Ref")
	}
	Set webAnswered = ..WaitWebRow(session, "answered", 0)
	Do $$$AssertTrue($IsObject(webAnswered), "the answered notice has a row in the web chat")
	If $IsObject(webAnswered) Do $$$AssertEquals(webAnswered.ChannelMessageId_"|"_webAnswered.Text, "|", "with no message id and no text")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 2, "so the request and the result are the web chat's two cards")
}

/// DW-454, the web half: an old held call (failed, with no ToolSource) that Decide closed with the bridge's sentence gets, from its
/// decision.recorded event, one result card in the web chat: the sentence of toolCall.failedWithReason, the Decision's Ref as
/// DecisionRef and the request's Ref as ApprovalRef, with no request before it.
Method TestHeldReasonReachesTheWebChat()
{
	If '..Ready() Quit
	Set session = ..Session("heldweb")
	Set sentence = $Parameter("OcuTalon.Bridge.Process.Decide", "HELDBEFOREUPDATE")
	Set web = ..HeldWebRow(session, sentence, .row, .decision, .finishedAt)
	If '$IsObject(web) Quit
	Do $$$AssertEquals(web.DecisionRef_"|"_web.ApprovalRef, decision_"|"_row, "it carries the Decision's Ref and the request's Ref")
	Do $$$AssertEquals(web.Text, ..Render("toolCall.failedWithReason", {"tool": "zz_send", "reason": (sentence)}, "web"), "and the web render of toolCall.failedWithReason")
	Do $$$AssertEquals(web.Text, "zz_send didn't run. "_sentence, "which is the tool and the bridge's sentence")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "it is the one card of the web chat")
}

/// DW-454, the web half, raw-reason case (QA): an old held call closed with a first Reasons line that is not one of the bridge's
/// sentences gets the one toolCall.failed result card in the web chat, with the Decision's Ref as DecisionRef, and never the raw line.
Method TestHeldRawReasonIsNeverShownInTheWebChat()
{
	If '..Ready() Quit
	Set session = ..Session("heldraw")
	Set raw = "zzraw <UNDEFINED> ^ZzSecret(1) at line 7"
	Set web = ..HeldWebRow(session, raw, .row, .decision, .finishedAt)
	If '$IsObject(web) Quit
	Do $$$AssertEquals(web.DecisionRef_"|"_web.ApprovalRef, decision_"|"_row, "it carries the Decision's Ref and the request's Ref")
	Do $$$AssertEquals(web.Text, ..Render("toolCall.failed", {"tool": "zz_send", "time": (finishedAt)}, "web"), "and the web render of toolCall.failed")
	Do $$$AssertEquals($Find(web.Text, "zzraw")_"|"_$Find(web.Text, "ZzSecret")_"|"_$Find(web.Text, "UNDEFINED"), "0|0|0", "with none of the raw line")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "it is the one card of the web chat")
}

/// Story 22.4 (R1, AD-11): an approved MCP call that the proxy refused because its tool changed after the request was made ends with the result changed, and
/// approval.result then sends a result notice to the owner, where it sent none for an unknown result before (the sink maps changed to mcp.replayToolChanged {tool,
/// server}). The row is made executing by hand, and FinishExecution closes it as the replay does. The web chat gets the row of kind result for the request.
Method TestChangedResultSendsANotice()
{
	If '..Ready() Quit
	Set session = ..Session("changed")
	Set ref = ..HeldCall(session)
	If ref = "" Quit
	Set request = ..WaitWebRow(session, "approval", 1)
	Do $$$AssertTrue($IsObject(request), "the web chat has the request's card first")
	Set row = ..Request(ref)
	Set row.State = "executing"
	Set row.ToolSource = "mcp:remote:@{config:AI.MCP.OcuTalon_zzchanged}"
	Do $$$AssertStatusOK(row.%Save(), "the request is executing, and its source names an MCP server")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).FinishExecution(ref, "changed"), "the run ends with the result changed")
	Set web = ..WaitWebRow(session, "result", 1)
	Do $$$AssertTrue($IsObject(web), "the web chat gets a card of kind result")
	Set slots = {"tool": (..#TOOL), "server": "zzchanged"}
	If $IsObject(web) {
		Do $$$AssertEquals(web.ApprovalRef, ref, "for the request")
		Do $$$AssertEquals(web.Text, ..Render("mcp.replayToolChanged", slots, "web"), "with the web render of mcp.replayToolChanged")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 2, "so the request and the changed result are the web chat's two cards")
	}
	Set phone = ..WaitMessage(session, "", 2)
	Do $$$AssertTrue($IsObject(phone), "the phone gets a new message")
	If $IsObject(phone) Do $$$AssertEquals(phone.Text_"|"_phone.ApprovalRef, ..Render("mcp.replayToolChanged", slots)_"|", "with the phone render of mcp.replayToolChanged and no buttons")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(ref, "State") _ "|" _ ##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(ref, "Result"), "failed|changed", "the request ended failed with the result changed")
}

/// Story 21.10: an MCP request whose server has no Mcp.Server row, cancelled through Approval Cancel (the call of Mcp.Ops Unregister), edits the request's phone message in place
/// to the phone render of answered.canceled {time, server}, adds no second message, and gives the web chat the answered notice's row with no text and no message id.
Method TestCancelledEditsInPlace()
{
	If '..Guard() Quit
	If '..UseReplayAgent() Quit
	Set session = ..Session("cancelled")
	Set ref = ..HeldCall(session)
	If ref = "" Quit
	Set message = ..WaitMessage(session, ref, 1)
	Do $$$AssertTrue($IsObject(message), "the request reaches the phone")
	If '$IsObject(message) Quit
	Set row = ..Request(ref)
	Set row.ToolSource = "mcp:remote:@{config:AI.MCP.OcuTalon_zzcancel}"
	Do $$$AssertStatusOK(row.%Save(), "the request's source names an MCP server that has no row")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Server).NameIndexExists("zzcancel"), 0, "the server is not registered")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(ref), "the request is cancelled")
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertTrue($Extract(answered.Answer, 1, 13) = "Cancelled at ", "the request's message has the render of answered.canceled as its Answer: "_..Facts(ref, session))
	Do $$$AssertTrue(answered.Answer [ "the MCP server zzcancel was removed. Nothing was changed.", "which names the server and says that nothing was changed")
	Do $$$AssertEquals(answered.Text_"|"_answered.ApprovalRef, message.Text_"|"_ref, "and keeps its text and request")
	Hang 2
	Do $$$AssertEquals(..PhoneCount(session), 1, "and the phone has no second message")
	Set webAnswered = ..WaitWebRow(session, "answered", 0)
	Do $$$AssertTrue($IsObject(webAnswered), "the web chat has the answered notice's row")
	If $IsObject(webAnswered) Do $$$AssertEquals(webAnswered.ChannelMessageId_"|"_webAnswered.Text, "|", "with no message id and no text")
}

Method TestRejectedAndExpiredEditInPlace()
{
	If '..Guard() Quit
	Set user = ..Answerer()
	If user = "" Quit
	If '..UseReplayAgent() Quit

	Set rejectedSession = ..Session("rejected")
	Set rejectedRef = ..HeldCall(rejectedSession)
	If rejectedRef = "" Quit
	Set message = ..WaitMessage(rejectedSession, rejectedRef, 1)
	Do $$$AssertTrue($IsObject(message), "the rejected call's request reaches the phone")
	If '$IsObject(message) Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(rejectedRef, "reject", "phone", user, rejectedSession, .winner), "done", "Reject is accepted")
	Set row = ..Request(rejectedRef)
	Set rejected = ..Render("answered.rejected", {"channel": "phone", "time": (row.AnsweredAt)})
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertEquals(answered.Answer, rejected, "the request's message has the render of answered.rejected: "_..Facts(rejectedRef, rejectedSession))
	Hang 2
	Do $$$AssertEquals(..PhoneCount(rejectedSession), 1, "and the phone has no second message")

	Set expiredSession = ..Session("expired")
	Set expiredRef = ..HeldCall(expiredSession)
	If expiredRef = "" Quit
	Set message = ..WaitMessage(expiredSession, expiredRef, 1)
	Do $$$AssertTrue($IsObject(message), "the expired call's request reaches the phone")
	If '$IsObject(message) Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Expire(expiredRef), "the request expires")
	Set row = ..Request(expiredRef)
	Set expired = ..Render("answered.expired", {"time": (row.ExpiresAt)})
	Set answered = ..WaitAnswer(message.Ref)
	Do $$$AssertEquals(answered.Answer, expired, "the request's message has the render of answered.expired")
	Hang 2
	Do $$$AssertEquals(..PhoneCount(expiredSession), 1, "and the phone has no second message")
}

/// --- helpers ---
/// 1 when the production is ready for the replay (Test.Agent.RunnerFixture ReadyReason); otherwise the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" Do $$$AssertEquals(reason, "", "the production is ready")
	Quit reason = ""
}

/// The answerer, or "" (the test fails) when the user does not hold OcuTalonUser. Also checks that the production is ready.
Method Answerer() As %String [ Private ]
{
	If '..Ready() Quit ""
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser")
	Quit $Select(holds: user, 1: "")
}

/// Puts ZzReplayAgent behind ChatAgent and the runners' keys at the CI mock's key, once per run; Restore puts both back. 1 when done.
Method UseReplayAgent() As %Boolean [ Private ]
{
	If ..Swapped Quit 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	Set ^OcuTalonTest("ToolCallNotices", "keys") = 1
	Do $$$AssertStatusOK(sc, "the runners' entries point at the CI mock key")
	If $$$ISERR(sc) Quit 0
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseAgent("ChatAgent", "OcuTalon.Test.Bridge.ZzReplayAgent", .saved)
	If $IsObject(saved) && '$Data(^OcuTalonTest("ToolCallNotices", "agent")) Set ^OcuTalonTest("ToolCallNotices", "agent") = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "ChatAgent runs ZzReplayAgent")
	Set ..Swapped = $$$ISOK(sc)
	Quit ..Swapped
}

/// Puts ChatAgent's agent and the runners' keys back, when UseReplayAgent changed them.
Method Restore() [ Private ]
{
	If $Data(^OcuTalonTest("ToolCallNotices", "agent")) {
		Set saved = {}.%FromJSON(^OcuTalonTest("ToolCallNotices", "agent"))
		Kill ^OcuTalonTest("ToolCallNotices", "agent")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreAgent("ChatAgent", saved), "ChatAgent's agent is put back")
	}
	If $Data(^OcuTalonTest("ToolCallNotices", "keys")) {
		Kill ^OcuTalonTest("ToolCallNotices", "keys")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys(), "the runners' keys are put back")
	}
	Set ..Swapped = 0
}

/// The gate holds a call of the tool for the session in a user's turn of a context begun with the runner ChatAgent, as the runner's job does, and
/// raises its request through the production's own HostSinkClass (the real BridgeSink). Returns the request's Ref once its task exists, with the
/// row tracked for Test.Bridge.Approval Clean; "" when the call is not held.
Method HeldCall(session As %String) As %String [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = session
	Set request.TraceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "", "ChatAgent"), "a user's turn of ChatAgent begins")
	Set arguments = {}.%FromJSON("{""b"":2,""a"":{""y"":1.0,""x"":""ops""}}")
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check(..#TOOL, {"id": "call_id", "name": (..#TOOL), "arguments": (arguments)}, {"origin_class": (..#TOOLCLASS), "requires_auth": false}, "")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ $Parameter("OcuTalon.Bridge.Policy.Gate", "HELD"), "the gate holds the call: "_$SYSTEM.Status.GetErrorText(sc))
	Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner(session)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ? ORDER BY ID DESC", session)
	If 'result.%Next() Quit ""
	Set ref = result.%Get("Ref")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Approval).WaitTask(ref, 10) '= "", "its task exists")
	Quit ref
}

/// The newest phone message of the session once it has count messages, and for a non-empty ref the message that carries that ApprovalRef (for
/// an empty ref, the newest message, which carries none); polled up to WAIT seconds. "" when it does not arrive.
Method WaitMessage(session As %String, ref As %String, count As %Integer) As OcuTalon.Data.SimMessage [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10, .sc)
		If rows.Count() '< count {
			For i = 1:1:rows.Count() {
				Set message = ..Message(rows.GetAt(i).Ref)
				If message.ApprovalRef = ref {
					Set found = message
					Quit
				}
			}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The message once it has an Answer (polled up to WAIT seconds), else as it is.
Method WaitAnswer(messageRef As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set message = ..Message(messageRef)
		If (message.Answer '= "") || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit message
}

/// What the row and the session's Delivery rows hold, for the text of an assertion.
Method Facts(ref As %String, session As %String) As %String [ Private ]
{
	Set row = ..Request(ref)
	Set text = "state="_row.State_" action="_row.AnsweredAction_" result="_row.Result_" deliveries="
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:deliveries.Count() Set text = text_deliveries.GetAt(i).Channel_"/"_deliveries.GetAt(i).Kind_"/"_(deliveries.GetAt(i).ChannelMessageId '= "")_" "
	Quit text
}

/// The SimMessage of the Ref as the table holds it: an instance that this process already has open is reloaded, so that a later change
/// by the production shows.
Method Message(ref As %String) As OcuTalon.Data.SimMessage [ Private ]
{
	Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen(ref)
	If $IsObject(message) Do message.%Reload()
	Quit message
}

/// The request's row as the table holds it (reloaded, like Message).
Method Request(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The number of phone messages of the session.
Method PhoneCount(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// An old held call of the session (a failed tool_call row with no ToolSource) and a fallback Decision of it whose Reasons are reasons,
/// both kept for the clean-up; sends their decision.recorded to the bridge sink and returns the web chat's result card of it, polled
/// up to WAIT seconds, or "" (the test fails) when none arrives. row, decision and finishedAt are the request's Ref, the Decision's
/// Ref and the request's FinishedAt.
Method HeldWebRow(session As %String, reasons As %String, Output row As %String, Output decision As %String, Output finishedAt As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Set finishedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "failed", , {"Kind": "tool_call", "ToolName": "zz_send", "ToolArguments": ("{""to"":""ops""}"), "ToolSource": "", "Runner": "ChatAgent", "DryRun": "", "Result": "failed", "FinishedAt": (finishedAt)})
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "tool", , {"ItemId": (row), "Fallback": 1, "FallbackReason": "error", "Reasons": (reasons)})
	Set ..Refs = ..Refs_","_row_","_decision
	Do $$$AssertStatusOK(##class(OcuTalon.Core.BridgeSink).OnEvent("decision.recorded", session, {"ref": (decision)}), "decision.recorded is handled")
	Set web = ..WaitWebRow(session, "result", 1)
	Do $$$AssertTrue($IsObject(web), "the web chat gets a row of kind result within "_..#WAIT_" seconds: "_..Facts(row, session))
	Quit web
}

/// The newest web Delivery row of the session of the kind that has a ChannelMessageId (card 1) or none (card 0), polled up to WAIT
/// seconds; "" when none arrives.
Method WaitWebRow(session As %String, kind As %String, card As %Boolean) As OcuTalon.Data.Delivery [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set found = ""
	For {
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		For i = rows.Count():-1:1 {
			Set candidate = rows.GetAt(i)
			If (candidate.Channel = "web") && (candidate.Kind = kind) && ((candidate.ChannelMessageId '= "") = card) {
				Set found = candidate
				Quit
			}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The render of the key with the slots (an object) for the channel (the phone by default), at the current time and with the online-demo flag as it is.
Method Render(key As %String, slots As %DynamicObject, channel As %String = "phone") As %String [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), channel, ##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), .sc)
	Do $$$AssertStatusOK(sc, key_" renders")
	Quit text
}

/// The row's State once it is the given one (polled up to the seconds), else the State at the deadline.
Method WaitState(ref As %String, state As %String, seconds As %Integer) As %String [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set row = ..Request(ref)
		If (row.State = state) || ($ZHorolog > deadline) Quit
		Hang 0.1
	}
	Quit row.State
}

}
