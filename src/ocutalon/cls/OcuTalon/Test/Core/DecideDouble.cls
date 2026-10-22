/// The stand-in for the Decide process in the tests of the turn pipeline (Story 2.4; reused by Stories 2.7 and 2.9). It has no
/// Test methods, and the product never refers to it. It extends Ens.BusinessProcess so that a test production can also
/// carry it under the name Decide; Test.Core.ConversationProbe hands it a request directly, with no production.
/// OnRequest records each request under ^OcuTalonTest("DecideDouble", OwnerRef, "seen", n), with n counted in
/// ^OcuTalonTest("DecideDouble", OwnerRef, "seen"): kind, provenance, input, itemId, summary, ownerRef, traceRef, channel,
/// threadSessionId, sessionMode, seedText, systemNote, and the sessionId and superSession of the double itself. It then
/// answers with the next scripted answer for the request's OwnerRef and Kind (Script); with none scripted, tellnow for a
/// decide request and reply for a turn request. Every DecisionResponse and Reply it makes, except busy, carries a new DecisionRef.
///   - decide: tellnow, act, ignore or digest (a DecisionResponse with that Outcome), fallback:<reason> (a DecisionResponse
///     with Fallback 1 and the reason), error (an error status);
///   - turn: reply (a Reply with text), tainted (a Reply with Tainted 1, ToolsRun 1 and HostData {"zz":"tool result"}), busy
///     (Reply.NewBusy()), broken (SessionBroken 1 and Fallback 1 with the reason error), fallback:<reason> (a Reply with
///     Fallback 1 and the reason), error (an error status), wrong (an Ens.StringResponse, which is not a Reply).
Class OcuTalon.Test.Core.DecideDouble Extends Ens.BusinessProcess
{

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
	Set answer = ..Next(owner, request.Kind)
	If answer = "" Set answer = $Select(request.Kind = "turn": "reply", 1: "tellnow")
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz decide double failed")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	If request.Kind = "turn" {
		If answer = "busy" {
			Set response = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
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
			} ElseIf answer = "broken" {
				Set response.SessionBroken = 1
				Set response.Fallback = 1
				Set response.FallbackReason = "error"
				Set response.Text = ""
			} ElseIf $Piece(answer, ":", 1) = "fallback" {
				Set response.Fallback = 1
				Set response.FallbackReason = $Piece(answer, ":", 2, *)
				Set response.Text = ""
			}
		}
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
	Quit $SYSTEM.Status.OK()
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

/// Removes the owner's scripts and records.
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
