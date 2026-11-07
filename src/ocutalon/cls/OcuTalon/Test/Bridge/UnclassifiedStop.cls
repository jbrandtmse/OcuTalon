/// Tests of Decide's unclassified-stop rule at Conclude (Story 17.3; AD-8, NFR-5): a reply with text and a finish reason that the bridge cannot classify
/// is recorded as an unusable fallback and never answers. In process: no production, no mock and no model request; Conclude records one Decision row for each
/// request, which the test removes.
///   - TestUnclassifiedStopFallsBack: for a decide, a diagnose and a turn, a reply with text and the finish reason pause_turn, content_filter, length or
///     SAFETY is a tellnow fallback with the reason unusable: the row and the answer say so, and no text of the model is in the answer;
///   - TestNormalEndsAnswer: the same text with end_turn, tool_use, stop, STOP and stop_sequence is answered with no fallback.
Class OcuTalon.Test.Bridge.UnclassifiedStop Extends %UnitTest.TestCase
{

/// The class that checks the reply of a decide or diagnose request (Decide's own tests check a diagnose reply against it too).
Parameter REPLYCLASS = "OcuTalon.Bridge.Msg.DecisionPayload";

/// The text of a decide reply that passes its check.
Parameter DECISION = "{""outcome"":""digest"",""reasons"":[""zzunclassified keeps this item for the digest.""],""confidence"":0.5}";

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

/// A reply with a text and a finish reason that the bridge cannot classify is an unusable fallback, for every kind of request.
Method TestUnclassifiedStopFallsBack()
{
	For kind = "decide", "diagnose", "turn" {
		For reason = "pause_turn", "content_filter", "length", "SAFETY" {
			Set label = kind_" with "_reason_": "
			Set request = ..NewRequest(kind)
			Set reply = ..NewReply(kind, reason)
			Set sc = ..Conclude(request, reply, .response)
			Do $$$AssertStatusOK(sc, label_"Conclude records a fallback")
			Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, kind)
			Do $$$AssertTrue($IsObject(row) && $IsObject(response), label_"a row is recorded and an answer is given")
			If '$IsObject(row) || '$IsObject(response) Continue
			Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason, "tellnow|1|unusable", label_"the row is a tellnow fallback with the reason unusable")
			Do $$$AssertEquals(row.Reasons_"|"_row.Confidence_"|"_row.Payload, "||", label_"it holds no reasons, confidence or payload")
			Do $$$AssertEquals(response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, "tellnow|1|unusable", label_"and so does the answer")
			Do $$$AssertStatusOK(response.XMLExportToString(.xml), label_"the answer is exported as XML")
			Do $$$AssertTrue(xml '[ "zzunclassified", label_"the model's text is in no field of the answer")
			If kind = "turn" Do $$$AssertEquals(response.Text_"|"_response.FinishReason, "|", label_"a turn's answer has no text and no finish reason")
		}
	}
}

/// The same reply with a finish reason that ends a reply normally is an answer.
Method TestNormalEndsAnswer()
{
	For kind = "decide", "turn" {
		For reason = "end_turn", "tool_use", "stop", "STOP", "stop_sequence" {
			Set label = kind_" with "_reason_": "
			Set request = ..NewRequest(kind)
			Set sc = ..Conclude(request, ..NewReply(kind, reason), .response)
			Do $$$AssertStatusOK(sc, label_"Conclude answers")
			Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, kind)
			Do $$$AssertTrue($IsObject(row) && $IsObject(response), label_"a row is recorded and an answer is given")
			If '$IsObject(row) || '$IsObject(response) Continue
			Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", label_"the row is no fallback")
			Do $$$AssertEquals(+response.Fallback, 0, label_"and neither is the answer")
		}
	}
}

/// A request of the kind with a fresh ItemId, which OnAfterOneTest deletes the row of.
Method NewRequest(kind As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = $Select(kind = "turn": "user", 1: "untrusted")
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = $Select(kind = "turn": ##class(OcuTalon.Bridge.Ids).NewRef(), 1: "instance")
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Triage this item."
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// The runner's reply: a text that passes the check of its kind, and the finish reason.
ClassMethod NewReply(kind As %String, finishReason As %String) As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = $Select(kind = "turn": "zzunclassified a reply to the turn.", 1: ..#DECISION)
	Set reply.FinishReason = finishReason
	Quit reply
}

/// Conclude for the request and reply, with a DecisionRef of its own, the do-nothing filter and sink and a trace session.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, Output response) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, ..#REPLYCLASS, "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
}

}
