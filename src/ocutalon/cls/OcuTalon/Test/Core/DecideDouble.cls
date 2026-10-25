/// The stand-in for the Decide process in the tests of the turn pipeline (Story 2.4; reused by Stories 2.7 and 2.9). It has no
/// Test methods, and the product never refers to it. It extends Ens.BusinessProcess so that a test production can also
/// carry it under the name Decide (Test.Core.ThreadProduction swaps it in on a throwaway, until Epic 11 removes the swap; the real
/// Decide on a keyless stack answers every turn no_key); Test.Core.ConversationProbe hands it a request directly, with no production.
/// OnRequest records each request under ^OcuTalonTest("DecideDouble", OwnerRef, "seen", n), with n counted in
/// ^OcuTalonTest("DecideDouble", OwnerRef, "seen"): kind, provenance, input, itemId, summary, ownerRef, traceRef, channel,
/// threadSessionId, sessionMode, seedText, systemNote, and the sessionId and superSession of the double itself. It then
/// answers with the next scripted answer for the request's OwnerRef and Kind (Script); with none scripted, tellnow for a
/// decide request and reply for a turn request. Every DecisionResponse and Reply it makes, except busy, carries a new DecisionRef.
/// While Record is on for an owner, each answer that carries a DecisionRef also writes the Decision row of that Ref through
/// Test.Data.Fixture, with one Usage row (Story 2.6): the owner, kind and item of the request, the outcome or fallback as
/// answered, the reasons "zz reason one" and "zz reason two" (one per line), the confidence 0.9, the model claude-haiku-5-5, a
/// usage cost of $0.0003 for a decide request and $0.0005 for a turn request, and, when the double has a session of its own
/// (a production item answering in a trace thread), that session as TraceSessionId. As Decide does (AD-20), a turn request
/// whose item already has a turn row is answered with an error status and writes nothing. Written gives the Refs of the
/// rows written, for the test that removes them with Fixture.Clean.
/// As a production item (its configuration name is a name; a shadow instance of the probes has the name 0) every answer that carries
/// a DecisionRef is preceded by two OcuTalon.Bridge.Msg.AgentStep messages for that DecisionRef, sent asynchronously to AgentSteps
/// with no answer required: positions 1 and 2, step kind model, label "zz step", status ok.
///   - decide: tellnow, act, ignore or digest (a DecisionResponse with that Outcome), fallback:<reason> (a DecisionResponse
///     with Fallback 1 and the reason), error (an error status), wrong (an Ens.StringResponse) or reply (a Reply with a
///     DecisionRef), the last two being answers that are not a DecisionResponse;
///   - turn: reply (a Reply with text), tainted (a Reply with Tainted 1, ToolsRun 1 and HostData {"zz":"tool result"}), busy
///     (Reply.NewBusy()), broken (SessionBroken 1 and Fallback 1 with the reason error), fallback:<reason> (a Reply with
///     Fallback 1 and the reason), taintedfallback:<reason> (the same with Tainted 1 and ToolsRun 1), error (an error
///     status), wrong (an Ens.StringResponse, which is not a Reply), checks (a Reply with the HostData {"checks":[{"zz":"result"}]}),
///     checksfallback:<reason> (a fallback Reply with those HostData), busychecks and brokenchecks (a busy Reply, and a broken one,
///     with those HostData), badjson (a Reply whose HostData is not JSON) and nochecks (a Reply whose HostData is an object with no
///     checks).
Class OcuTalon.Test.Core.DecideDouble Extends Ens.BusinessProcess
{

/// The HostData of the checks answers: one check result.
Parameter CHECKSDATA = "{""checks"":[{""zz"":""result""}]}";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	Set owner = request.OwnerRef
	Set n = $Increment(^OcuTalonTest("DecideDouble", owner, "seen"))
	Set seen = $Name(^OcuTalonTest("DecideDouble", owner, "seen", n))
	Set @seen@("kind") = request.Kind
	Set @seen@("provenance") = request.Provenance
	Set @seen@("input") = request.Input
	Set @seen@("itemId") = request.ItemId
	Set @seen@("summary") = request.Summary
	Set @seen@("ownerRef") = request.OwnerRef
	Set @seen@("traceRef") = request.TraceRef
	Set @seen@("channel") = request.Channel
	Set @seen@("threadSessionId") = request.ThreadSessionId
	Set @seen@("sessionMode") = request.SessionMode
	Set @seen@("seedText") = request.SeedText
	Set @seen@("systemNote") = request.SystemNote
	Set @seen@("sessionId") = ..%SessionId
	Set @seen@("superSession") = ..%SuperSession
	If $Get(^OcuTalonTest("DecideDouble", owner, "record")) && (request.Kind = "turn") && ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, "turn") {
		Quit $SYSTEM.Status.Error(5001, "zz the item already has the turn decision")
	}
	Set answer = ..Next(owner, request.Kind)
	If answer = "" Set answer = $Select(request.Kind = "turn": "reply", 1: "tellnow")
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz decide double failed")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	If request.Kind = "turn" {
		If answer = "busy" {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
		} ElseIf answer = "busychecks" {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
			Set response.HostData = ..#CHECKSDATA
		} ElseIf answer = "wrong" {
			Set response = ##class(Ens.StringResponse).%New("zz")
		} Else {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
			Set response.DecisionRef = ref
			Set response.Text = "zz reply to "_request.Summary
			If answer = "tainted" {
				Set response.Tainted = 1
				Set response.ToolsRun = 1
				Set response.HostData = "{""zz"":""tool result""}"
			} ElseIf (answer = "broken") || (answer = "brokenchecks") {
				Set response.SessionBroken = 1
				Set response.Fallback = 1
				Set response.FallbackReason = "error"
				Set response.Text = ""
				If answer = "brokenchecks" Set response.HostData = ..#CHECKSDATA
			} ElseIf $Piece(answer, ":", 1) = "fallback" {
				Set response.Fallback = 1
				Set response.FallbackReason = $Piece(answer, ":", 2, *)
				Set response.Text = ""
			} ElseIf answer = "checks" {
				Set response.HostData = ..#CHECKSDATA
			} ElseIf answer = "badjson" {
				Set response.HostData = "{""checks"": [{"
			} ElseIf answer = "nochecks" {
				Set response.HostData = "{""zz"":""tool result""}"
			} ElseIf $Piece(answer, ":", 1) = "checksfallback" {
				Set response.Fallback = 1
				Set response.FallbackReason = $Piece(answer, ":", 2, *)
				Set response.HostData = ..#CHECKSDATA
				Set response.Text = ""
			} ElseIf $Piece(answer, ":", 1) = "taintedfallback" {
				Set response.Fallback = 1
				Set response.FallbackReason = $Piece(answer, ":", 2, *)
				Set response.Tainted = 1
				Set response.ToolsRun = 1
				Set response.Text = ""
			}
		}
	} ElseIf answer = "wrong" {
		Set response = ##class(Ens.StringResponse).%New("zz")
	} ElseIf answer = "reply" {
		Set response = ##class(OcuTalon.Bridge.Msg.Reply).%New()
		Set response.DecisionRef = ref
		Set response.Text = "zz a reply is not a decision"
	} Else {
		Set response = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
		Set response.DecisionRef = ref
		Set response.Payload = "{}"
		If $Piece(answer, ":", 1) = "fallback" {
			Set response.Fallback = 1
			Set response.FallbackReason = $Piece(answer, ":", 2, *)
		} Else {
			Set response.Outcome = answer
		}
	}
	If $IsObject(response) && response.%Extends("OcuTalon.Bridge.Msg.Result") && (response.DecisionRef '= "") {
		If (..%ConfigName '= "") && (..%ConfigName '= 0) Do ..Step(response.DecisionRef)
		If $Get(^OcuTalonTest("DecideDouble", owner, "record")) Do ..Write(request, response)
	}
	Quit $SYSTEM.Status.OK()
}

/// The two agent steps of the decision, sent to AgentSteps with no answer required. A send that fails is logged and never
/// changes the answer.
Method Step(decisionRef As %String) [ Private ]
{
	For position = 1, 2 {
		Set step = ##class(OcuTalon.Bridge.Msg.AgentStep).%New()
		Set step.DecisionRef = decisionRef
		Set step.Position = position
		Set step.StepKind = "model"
		Set step.Label = "zz step"
		Set step.Status = "ok"
		Set sc = ..SendRequestAsync("AgentSteps", step, 0)
		If $SYSTEM.Status.IsError(sc) $$$LOGSTATUS(sc)
	}
}

/// The Decision row, and its Usage row, of the answer that carries a DecisionRef. Nothing when the item already has a decision of the
/// kind.
Method Write(request As %Library.Persistent, response As %RegisteredObject) [ Private ]
{
	Set owner = request.OwnerRef
	If ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, request.Kind) Quit
	Set fields = {"Ref": (response.DecisionRef), "ItemId": (request.ItemId), "Summary": (request.Summary), "Reasons": "zz reason one\nzz reason two", "Confidence": 0.9, "Model": "claude-haiku-5-5", "InputTokens": 1084, "OutputTokens": 312, "AgentStepCount": 2, "DurationMs": 3400, "CostUSD": 0.0003}
	If response.Outcome '= "" Set fields.Outcome = response.Outcome
	If response.Fallback {
		Set fields.Fallback = 1
		Set fields.FallbackReason = response.FallbackReason
		Set fields.Confidence = 0
	}
	Set cost = $Select(request.Kind = "turn": 0.0005, 1: 0.0003)
	Set fields.CostUSD = cost
	If ..%SessionId '= "" Set fields.TraceSessionId = ..%SessionId
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, request.Kind, , fields)
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref, owner, {"ItemId": (request.ItemId), "Kind": (request.Kind), "InputTokens": 1084, "OutputTokens": 312, "CostUSD": (cost)})
	Set ^OcuTalonTest("DecideDouble", owner, "written") = $Get(^OcuTalonTest("DecideDouble", owner, "written"))_$Select($Data(^OcuTalonTest("DecideDouble", owner, "written")): ",", 1: "")_ref
}

/// Turns the recording of Decision and Usage rows on or off for the owner's requests.
ClassMethod Record(ownerRef As %String, on As %Boolean)
{
	Set ^OcuTalonTest("DecideDouble", ownerRef, "record") = +on
}

/// The Refs of the Decision rows that the double wrote for the owner, comma-separated, in the order written.
ClassMethod Written(ownerRef As %String) As %String
{
	Quit $Get(^OcuTalonTest("DecideDouble", ownerRef, "written"))
}

/// Scripts the answers for the owner's requests of a kind (decide or turn), as a list in the order they are given. The next
/// request of the kind takes the first, and so on; the script of the kind starts again from this list.
ClassMethod Script(ownerRef As %String, kind As %String, answers As %List)
{
	Kill ^OcuTalonTest("DecideDouble", ownerRef, "script", kind)
	Set position = 0
	Set count = 0
	While $ListNext(answers, position, answer) {
		Set count = count + 1
		Set ^OcuTalonTest("DecideDouble", ownerRef, "script", kind, count) = answer
	}
	Set ^OcuTalonTest("DecideDouble", ownerRef, "script", kind) = 0
}

/// The requests the double has seen for the owner, in order, as an array of objects with the fields OnRequest records.
ClassMethod Seen(ownerRef As %String) As %DynamicArray
{
	Set seen = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("DecideDouble", ownerRef, "seen", n))
		Quit:n=""
		Set one = {}
		Set field = ""
		For {
			Set field = $Order(^OcuTalonTest("DecideDouble", ownerRef, "seen", n, field), 1, value)
			Quit:field=""
			Do one.%Set(field, value)
		}
		Do seen.%Push(one)
	}
	Quit seen
}

/// Removes the owner's scripts and records, the recording flag and the list of the rows written. The rows themselves are the
/// test's to remove with Fixture.Clean.
ClassMethod Clear(ownerRef As %String)
{
	Kill ^OcuTalonTest("DecideDouble", ownerRef)
}

/// Takes the next scripted answer for the owner and kind, "" when the script has no more.
ClassMethod Next(ownerRef As %String, kind As %String) As %String [ Private ]
{
	Set next = $Get(^OcuTalonTest("DecideDouble", ownerRef, "script", kind)) + 1
	If '$Data(^OcuTalonTest("DecideDouble", ownerRef, "script", kind, next), answer) Quit ""
	Set ^OcuTalonTest("DecideDouble", ownerRef, "script", kind) = next
	Quit answer
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
