/// Tests of the hand-off from AnswerOps to PrecedentOps (Story 41.5; AD-21, FR-72), over a shadow instance of Test.Core.AnswerOpsProbe, whose approval API is the
/// ApprovalDouble and whose SendPrecedent records the RecordPrecedent it is given instead of sending it. Safe on a slot: no production is needed. The sessions and
/// requests are fixture rows, removed after each test; the double's run and its record are ended.
///   - TestDoneSendsOne: an approve and a reject that the double answers done each send one RecordPrecedent with the request's Ref, the Action, the Channel and the
///     SessionRef as given, and the AnswerResult is done;
///   - TestNotDoneSendsNone: already_answered, expired, not_found, not_allowed, and a SessionRef with no Session row send nothing;
///   - TestFailedSendKeepsTheAnswer: a send that fails, and one that throws, give the AnswerResult done and one warning each.
Class OcuTalon.Test.Core.AnswerPrecedents Extends %UnitTest.TestCase
{

/// The probe, a subclass of the operation.
Parameter PROBE = "OcuTalon.Test.Core.AnswerOpsProbe";

/// The Refs of the run's fixture rows, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

/// A done answer sends one RecordPrecedent that carries the answer as it was given.
Method TestDoneSendsOne()
{
	Set session = ..Session("done")
	For action = "approve", "reject" {
		Set channel = $Select(action = "approve": "web", 1: "phone")
		Set request = ..Approval(session)
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
		Set probe = ..Probe()
		Set response = ..Answer(probe, request, action, channel, session)
		Do $$$AssertEquals(response.Result, "done", action_": the result is done")
		Do $$$AssertEquals(..Sent(), 1, action_": one RecordPrecedent was sent")
		Do $$$AssertEquals(..Arg(1, "ref")_"|"_..Arg(1, "action")_"|"_..Arg(1, "channel")_"|"_..Arg(1, "sessionRef"), request_"|"_action_"|"_channel_"|"_session, action_": with the request's Ref, the Action, the Channel and the SessionRef")
	}
}

/// An answer that is not done sends nothing, and neither does a session with no row.
Method TestNotDoneSendsNone()
{
	Set session = ..Session("notdone")
	Set request = ..Approval(session)
	For result = "already_answered", "expired", "not_found", "not_allowed" {
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin(result)
		Set probe = ..Probe()
		Set response = ..Answer(probe, request, "approve", "web", session)
		Do $$$AssertEquals(response.Result_"|"_..Sent(), result_"|0", result_": the result reaches the caller and nothing is sent")
	}
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
	Set probe = ..Probe()
	Set response = ..Answer(probe, request, "approve", "web", ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals(response.Result_"|"_..Sent()_"|"_##class(OcuTalon.Test.Core.ApprovalDouble).Calls(), "not_found|0|0", "a session with no row: not_found, nothing sent, the double not called")
}

/// A send that fails or throws is one warning, and the AnswerResult stays done.
Method TestFailedSendKeepsTheAnswer()
{
	Set session = ..Session("failed")
	For how = "error", "throw" {
		Set request = ..Approval(session)
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).Begin("done")
		Set probe = ..Probe()
		Set probe.FailSend = how
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set response = ..Answer(probe, request, "approve", "web", session)
		Do $$$AssertEquals(response.Result, "done", how_": the AnswerResult is done")
		Do $$$AssertEquals(..Sent(), 1, how_": the send was tried once")
		Do $$$AssertEquals(..LogRows(mark, 3), 1, how_": one warning is logged")
		Do $$$AssertEquals(..LogRows(mark, 2), 0, how_": and no error")
		Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", mark, ..#PROBE)
	}
}

/// --- helpers ---
/// A shadow instance of the probe whose request header names AnswersIn.
Method Probe() As OcuTalon.Test.Core.AnswerOpsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SourceConfigName = "AnswersIn"
	Set probe.%RequestHeader = header
	Quit probe
}

/// A fixture session, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzanswerprec"_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture fix request of the owner, recorded for the clean-up. Returns its Ref.
Method Approval(owner As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Hands the answer to the probe's OnMessage and returns the AnswerResult.
Method Answer(probe As OcuTalon.Test.Core.AnswerOpsProbe, ref As %String, action As %String, channel As %String, sessionRef As %String) As OcuTalon.Core.Msg.AnswerResult [ Private ]
{
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = ref
	Set answer.Action = action
	Set answer.Channel = channel
	Set answer.SessionRef = sessionRef
	Set sc = probe.OnMessage(answer, .response)
	Do $$$AssertStatusOK(sc, "OnMessage returns OK")
	Quit response
}

/// The number of RecordPrecedent messages the probe recorded for the current double run.
Method Sent() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("AnswerOpsPrecedent", $Get(^OcuTalonTest("ApprovalDouble", "run"), 0), "calls"))
}

/// A field (ref, action, channel or sessionRef) of the nth recorded RecordPrecedent.
Method Arg(n As %Integer, name As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("AnswerOpsPrecedent", $Get(^OcuTalonTest("ApprovalDouble", "run"), 0), n, name))
}

/// The number of event-log rows of the type (2 error, 3 warning) that the probe logged after the row mark.
Method LogRows(mark As %Integer, type As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = ? AND SourceClass = ?", mark, type, ..#PROBE)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
