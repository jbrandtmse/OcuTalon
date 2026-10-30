/// Tests of OcuTalon.Bridge.ReplyCheck and of how Decide.Interpret uses it (Story 7.1; AD-7, AD-8, AD-16; owner U-125). They need no production, so they run anywhere, a slot
/// included; Decide records its Decision rows in the namespace, and the tests remove the ones they made.
///   - TestBegin: Begin refuses anything that is not an OcuTalon.Bridge.Msg.Request and clears every earlier value (also when it refuses); Value is "" with no check
///     begun and for a name that is not one of FIELDS; the values are the request's Kind, ItemId, OwnerRef and Input;
///   - TestBothChecksSeeTheRequest: Decide.Conclude with the probe reply class (ProbeReplyCheck, which Decide checks twice) shows both checks the request's four
///     values, and Active is 0 after Conclude returns, also for an invalid reply and for a check that throws;
///   - TestErrorPath (U-125): a check that throws inside Interpret leaves Active 0 and every value empty, and the exception reaches the caller;
///   - TestSecondDecision (U-125): Conclude for a request A and then for a request B (another item, owner and input) in the same process: the checks of B see only B's
///     values, never A's; and Begin for B after a Begin for A with no End between holds only B's.
Class OcuTalon.Test.Bridge.ReplyCheck Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Bridge.ProbeReplyCheck";

Parameter CHECK = "OcuTalon.Bridge.ReplyCheck";

/// The ItemIds of the requests that the test made, for the clean-up of their Decision rows.
Property ItemIds As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzProbeReplyCheck
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||ZzProbeReplyCheck
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

/// A diagnose request with the item, the owner and the input.
Method NewRequest(label As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "zzowner"_label
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Input of "_label
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// A usable reply of the probe class.
ClassMethod Reply() As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "{""outcome"":""act"",""reasons"":[""A reason.""],""confidence"":0.5,""note"":""A note.""}"
	Quit reply
}

/// Decide.Conclude for the request with the probe class, the do-nothing filter and sink. The status.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, Output response) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, ..#PROBE, "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
}

/// The four values of the request, in the order of FIELDS, as the probe keeps them.
ClassMethod ValuesOf(request As OcuTalon.Bridge.Msg.Request) As %List [ Private ]
{
	Quit $ListBuild(1, request.Kind, request.ItemId, request.OwnerRef, request.Input)
}

/// What the check number n saw, as the probe kept it, or "none".
ClassMethod Seen(n As %Integer) As %List [ Private ]
{
	Quit $Get(^||ZzProbeReplyCheck(n), "none")
}

/// 1 when no value of the check is set: it is inactive and every value is empty.
ClassMethod Empty() As %Boolean [ Private ]
{
	Set empty = '##class(OcuTalon.Bridge.ReplyCheck).Active()
	For i = 1:1:$Length($Parameter(..#CHECK, "FIELDS"), ",") {
		If ##class(OcuTalon.Bridge.ReplyCheck).Value($Piece($Parameter(..#CHECK, "FIELDS"), ",", i)) '= "" Set empty = 0
	}
	Quit empty
}

Method TestBegin()
{
	Do $$$AssertEquals($Parameter(..#CHECK, "FIELDS"), "Kind,ItemId,OwnerRef,Input", "the check holds the request's Kind, ItemId, OwnerRef and Input")
	Do $$$AssertNotTrue(##class(OcuTalon.Bridge.ReplyCheck).Active(), "no check is begun at first")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.ReplyCheck).Value("Kind"), "", "and every value is empty")
	Set request = ..NewRequest("a")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(request), "Begin starts the check from a request")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.ReplyCheck).Active(), "which is then active")
	Set seen = ""
	For name = "Kind", "ItemId", "OwnerRef", "Input" Set seen = seen _ $ListBuild(##class(OcuTalon.Bridge.ReplyCheck).Value(name))
	Do $$$AssertEquals(seen, $ListBuild(request.Kind, request.ItemId, request.OwnerRef, request.Input), "and holds the request's four values")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.ReplyCheck).Value("Summary"), "", "a name that is not one of FIELDS is empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.ReplyCheck).Value(""), "", "so is an empty name")
	Set ^||OcuTalonBP.ReplyCheck("ZzStale") = "left over"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(..NewRequest("b")), "Begin starts again")
	Do $$$AssertEquals($Data(^||OcuTalonBP.ReplyCheck("ZzStale")), 0, "and clears every earlier value first")
	Set sc = ##class(OcuTalon.Bridge.ReplyCheck).Begin(##class(Ens.StringRequest).%New("x"))
	Do $$$AssertStatusNotOK(sc, "Begin refuses a message that is not an OcuTalon.Bridge.Msg.Request")
	Do $$$AssertTrue(..Empty(), "and the refusal leaves no value of the earlier check")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(""), "Begin refuses no object")
	Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(request)
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Do $$$AssertTrue(..Empty(), "End clears the check")
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Do $$$AssertTrue(..Empty(), "and does nothing when there is none")
}

Method TestBothChecksSeeTheRequest()
{
	Set request = ..NewRequest("both")
	Set sc = ..Conclude(request, ..Reply(), .response)
	Do $$$AssertStatusOK(sc, "a reply of the probe class is concluded")
	Do $$$AssertEquals($Get(^||ZzProbeReplyCheck), 2, "Decide checked it twice: on import and after filtering")
	Do $$$AssertEquals(..Seen(1), ..ValuesOf(request), "the first check saw the request's values")
	Do $$$AssertEquals(..Seen(2), ..ValuesOf(request), "and so did the second")
	Do $$$AssertTrue(..Empty(), "no check is begun after Conclude returns")
	Do $$$AssertEquals($IsObject(response) && 'response.Fallback, 1, "the reply was usable")

	Kill ^||ZzProbeReplyCheck
	Set request = ..NewRequest("invalid")
	Set reply = ..Reply()
	Set reply.Text = "{""outcome"":""bogus"",""reasons"":[""A reason.""],""confidence"":0.5}"
	Set sc = ..Conclude(request, reply, .response)
	Do $$$AssertStatusOK(sc, "an invalid reply is concluded")
	Do $$$AssertEquals($Get(^||ZzProbeReplyCheck), 1, "its one check ran")
	Do $$$AssertEquals(..Seen(1), ..ValuesOf(request), "with the request's values")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|invalid", "and the reply is a fallback with the reason invalid")
	Do $$$AssertTrue(..Empty(), "no check is begun after an invalid reply")

	Kill ^||ZzProbeReplyCheck
	Set ^||ZzProbeReplyCheck("throwAt") = 1
	Set request = ..NewRequest("throwfirst")
	Set sc = ..Conclude(request, ..Reply(), .response)
	Do $$$AssertStatusOK(sc, "a first check that throws is caught by the reply check")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|invalid", "and the reply is a fallback with the reason invalid")
	Do $$$AssertTrue(..Empty(), "no check is begun after it")
}

Method TestErrorPath()
{
	Set ^||ZzProbeReplyCheck("throwAt") = 2
	Set request = ..NewRequest("throw")
	Set thrown = 0
	Try {
		Set sc = ..Conclude(request, ..Reply(), .response)
	} Catch exception {
		Set thrown = 1
	}
	Do $$$AssertTrue(thrown, "a check that throws after filtering reaches the caller as an exception")
	Do $$$AssertEquals($Get(^||ZzProbeReplyCheck), 2, "after the first check ran")
	Do $$$AssertEquals(..Seen(2), ..ValuesOf(request), "and the failing check saw the request's values")
	Do $$$AssertNotTrue(##class(OcuTalon.Bridge.ReplyCheck).Active(), "afterwards no check is begun")
	Set empty = 1
	For name = "Kind", "ItemId", "OwnerRef", "Input" {
		If ##class(OcuTalon.Bridge.ReplyCheck).Value(name) '= "" Set empty = 0
	}
	Do $$$AssertTrue(empty, "and every value is empty")
}

Method TestSecondDecision()
{
	Set first = ..NewRequest("first")
	Set second = ..NewRequest("second")
	Do $$$AssertStatusOK(..Conclude(first, ..Reply(), .response), "request A is concluded")
	Do $$$AssertEquals(..Seen(1), ..ValuesOf(first), "A's checks saw A's values")
	Do $$$AssertEquals(..Seen(2), ..ValuesOf(first), "both of them")
	Do $$$AssertStatusOK(..Conclude(second, ..Reply(), .response), "request B is concluded after it in the same process")
	Do $$$AssertEquals($Get(^||ZzProbeReplyCheck), 4, "four checks ran")
	Do $$$AssertEquals(..Seen(3), ..ValuesOf(second), "B's first check saw B's values")
	Do $$$AssertEquals(..Seen(4), ..ValuesOf(second), "and its second check too")
	Do $$$AssertTrue($List(..Seen(3), 3) '= $List(..Seen(1), 3), "and none of them is A's")

	Set a = ..NewRequest("a")
	Set b = ..NewRequest("b")
	Set b.Input = ""
	Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(a)
	Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(b)
	Set seen = ""
	For name = "Kind", "ItemId", "OwnerRef", "Input" Set seen = seen _ $ListBuild(##class(OcuTalon.Bridge.ReplyCheck).Value(name))
	Do $$$AssertEquals(seen, $ListBuild(b.Kind, b.ItemId, b.OwnerRef, ""), "Begin for B after Begin for A, with no End between, holds B's values only")
	Do ##class(OcuTalon.Bridge.ReplyCheck).Begin(a)
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(##class(Ens.StringRequest).%New("x")), "a Begin that is refused after Begin for A")
	Do $$$AssertTrue(..Empty(), "leaves nothing of A")
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
}

}
