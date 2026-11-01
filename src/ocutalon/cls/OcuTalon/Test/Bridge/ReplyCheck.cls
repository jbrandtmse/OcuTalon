/// Tests of OcuTalon.Bridge.ReplyCheck and of how Decide.Interpret uses it (Story 7.1; AD-7, AD-8, AD-16; owner U-125). They need no production, so they run anywhere, a slot
/// included; Decide records its Decision rows in the namespace, and the tests remove the ones they made.
///   - TestBegin: Begin refuses anything that is not an OcuTalon.Bridge.Msg.Request and clears every earlier value (also when it refuses); Value is "" with no check
///     begun and for a name that is not one of FIELDS; the values are the request's Kind, ItemId, OwnerRef and Input;
///   - TestBothChecksSeeTheRequest: Decide.Conclude with the probe reply class (ProbeReplyCheck, which Decide checks twice) shows both checks the request's four
///     values, and Active is 0 after Conclude returns, also for an invalid reply and for a check that throws;
///   - TestErrorPath (U-125): a check that throws inside Interpret leaves Active 0 and every value empty, and the exception reaches the caller;
///   - TestSecondDecision (U-125): Conclude for a request A and then for a request B (another item, owner and input) in the same process: the checks of B see only B's
///     values, never A's; and Begin for B after a Begin for A with no End between holds only B's;
///   - TestRefusalNamesTheLimitNotTheReply: a reply that fails its check on a length or a value (the first check, and the check after the reply filter) gives
///     the fallback invalid and one Type 3 warning of Decide.Conclude whose whole text is the fixed words, the reply class, the failing property, the element and the limit
///     ("Note: 105 > 100", "Reasons element 2: 1005 > 1000", "Confidence: value > 1"), with at most five parts and "and <k> more", and none of the marker that the
///     failing value carries, not even a part of it;
///   - TestOtherRefusalsNameTheCode: a reply that is not JSON, one with an unknown field, one whose class check quotes a value, one of the wrong JSON type and a check that throws
///     give a warning of the error code only ("ERROR #5035", "ERROR #9404", "ERROR #5001", "ERROR #9406 on Reasons"), with no marker and no IRIS message text;
///   - TestRefusalTextForms: Decide.RefusalText for statuses built with the forms of IRIS's own (the length and value forms, the position, a property that the class lacks, a limit that
///     is not a number, a code that is not a number, a repeated error, the cap of five, and no error).
/// Each test removes its Decision rows and its REFUSED warnings, and kills ^||ZzProbeFilter and ^||ZzProbeReplyCheck, also after a failure (OnAfterOneTest).
Class OcuTalon.Test.Bridge.ReplyCheck Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Bridge.ProbeReplyCheck";

Parameter CHECK = "OcuTalon.Bridge.ReplyCheck";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

/// The start of the warning that Decide.Conclude logs for the reply check of an invalid decide or diagnose reply (the decision's Ref follows).
Parameter REFUSED = "The reply check refused the reply of the decision ";

/// The reply filter that puts "[f] " in front of each text and counts its calls.
Parameter FILTER = "OcuTalon.Test.Bridge.ProbeFilter";

/// The ItemIds of the requests that the test made, for the clean-up of their Decision rows.
Property ItemIds As %List;

/// The number of the newest row of the event log before the test, for its warnings.
Property Mark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzProbeReplyCheck, ^||ZzProbeFilter
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||ZzProbeReplyCheck, ^||ZzProbeFilter
	If ..Mark '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Conclude", ..#REFUSED)
	Set ..Mark = ""
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

/// Decide.Conclude for the request with the probe class, the filter (the do-nothing one unless given) and the host sink. Returns the Ref that it passed; sc is the status.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, Output response, Output sc As %Status, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ref, reply, ..#PROBE, filter, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Quit ref
}

/// A unique marker: a value that no warning may hold, not even a part of it.
ClassMethod Marker() As %String [ Private ]
{
	Quit "zzmark"_##class(OcuTalon.Bridge.Ids).NewRef()
}

/// The text padded with x to the length.
ClassMethod Pad(text As %String, length As %Integer) As %String [ Private ]
{
	Quit text_$Translate($Justify("", length - $Length(text)), " ", "x")
}

/// The number of warnings that name the decision, and the newest one's text.
Method Warning(ref As %String, Output text As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .text, "Conclude", ..#REFUSED_ref)
}

/// The text of a warning on the first check: the fixed words, the class and what the check refused.
ClassMethod W1(ref As %String, refused As %String) As %String [ Private ]
{
	Quit ..#REFUSED_ref_": The reply check failed: the reply is not one JSON object that "_..#PROBE_" accepts: "_refused
}

/// The text of a warning on the check after the reply filter.
ClassMethod W2(ref As %String, refused As %String) As %String [ Private ]
{
	Quit ..#REFUSED_ref_": After the reply filter ran: "_..#PROBE_" refused the filtered payload: "_refused
}

/// A usable reply as a dynamic object.
ClassMethod Usable() As %DynamicObject [ Private ]
{
	Quit {"outcome": "act", "reasons": ["A reason."], "confidence": 0.5, "note": "A note."}
}

/// Concludes the reply (text) and asserts the invalid fallback and that the one warning is the expected text (kind 1: the first check, 2: after the filter) and holds no marker.
Method Refuse(label As %String, text As %String, refused As %String, marker As %String, kind As %Integer = 1, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter")
{
	Set request = ..NewRequest("refuse")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set ref = ..Conclude(request, reply, .response, .sc, filter)
	Do $$$AssertStatusOK(sc, label_": the reply is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|invalid", label_": the fallback invalid")
	Set count = ..Warning(ref, .warning)
	Do $$$AssertEquals(count, 1, label_": one warning names the decision")
	Do $$$AssertEquals(warning, $Select(kind = 1: ..W1(ref, refused), 1: ..W2(ref, refused)), label_": the warning names what failed")
	Do $$$AssertTrue(warning '[ marker, label_": and holds none of the marker")
	Do $$$AssertTrue(warning '[ $Extract(marker, 7, 16), label_": nor a part of it")
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
	Do ..Conclude(request, ..Reply(), .response, .sc)
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
	Do ..Conclude(request, reply, .response, .sc)
	Do $$$AssertStatusOK(sc, "an invalid reply is concluded")
	Do $$$AssertEquals($Get(^||ZzProbeReplyCheck), 1, "its one check ran")
	Do $$$AssertEquals(..Seen(1), ..ValuesOf(request), "with the request's values")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|invalid", "and the reply is a fallback with the reason invalid")
	Do $$$AssertTrue(..Empty(), "no check is begun after an invalid reply")

	Kill ^||ZzProbeReplyCheck
	Set ^||ZzProbeReplyCheck("throwAt") = 1
	Set request = ..NewRequest("throwfirst")
	Do ..Conclude(request, ..Reply(), .response, .sc)
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
		Do ..Conclude(request, ..Reply(), .response, .sc)
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
	Do ..Conclude(first, ..Reply(), .response, .sc)
	Do $$$AssertStatusOK(sc, "request A is concluded")
	Do $$$AssertEquals(..Seen(1), ..ValuesOf(first), "A's checks saw A's values")
	Do $$$AssertEquals(..Seen(2), ..ValuesOf(first), "both of them")
	Do ..Conclude(second, ..Reply(), .response, .sc)
	Do $$$AssertStatusOK(sc, "request B is concluded after it in the same process")
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

Method TestRefusalNamesTheLimitNotTheReply()
{
	Set marker = ..Marker()
	Set reply = ..Usable()
	Set reply.note = ..Pad(marker, 105)
	Do ..Refuse("row 1: a text over its limit", reply.%ToJSON(), "Note: 105 > 100", marker)

	Set reply = ..Usable()
	Do reply.reasons.%Push(..Pad(marker, 1005))
	Do ..Refuse("row 2: a list element over its limit", reply.%ToJSON(), "Reasons element 2: 1005 > 1000", marker)

	Set reply = ..Usable()
	Set reply.confidence = 2
	Do ..Refuse("row 3: a value above its limit", reply.%ToJSON(), "Confidence: value > 1", marker)
	Set reply.confidence = -3
	Do ..Refuse("row 3: a value below its limit", reply.%ToJSON(), "Confidence: value < 0", marker)

	Set reply = ..Usable()
	Set reply.note = ..Pad(marker, 105)
	Do ..Refuse("row 1: a text over its limit in a Markdown code fence", "```json"_$Char(10)_reply.%ToJSON()_$Char(10)_"```", "Note: 105 > 100", marker)

	Set reply = ..Usable()
	Set reply.note = ..Pad(marker, 98)
	Do ..Refuse("row 5: a text over its limit after the filter", reply.%ToJSON(), "Note: 102 > 100", marker, 2, ..#FILTER)

	Set reply = ..Usable()
	Set reasons = []
	Set markers = ""
	For i = 1:1:6 {
		Set one = ..Marker()
		Set markers = markers _ $ListBuild(one)
		Do reasons.%Push(..Pad(one, 998))
	}
	Set reply.reasons = reasons
	Kill ^||ZzProbeFilter
	Set expected = ""
	For i = 1:1:5 Set expected = expected _ $Select(i > 1: "; ", 1: "") _ "Reasons element "_i_": 1002 > 1000"
	Set expected = expected_"; and 1 more"
	Set request = ..NewRequest("cap")
	Set replyMsg = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set replyMsg.Text = reply.%ToJSON()
	Set ref = ..Conclude(request, replyMsg, .response, .sc, ..#FILTER)
	Do $$$AssertStatusOK(sc, "row 6: the reply is concluded")
	Do $$$AssertEquals(..Warning(ref, .warning), 1, "row 6: one warning names the decision")
	Do $$$AssertEquals(warning, ..W2(ref, expected), "row 6: five elements, then the count of the rest")
	Set position = 0
	While $ListNext(markers, position, one) {
		Do $$$AssertTrue(warning '[ $Extract(one, 7, 16), "row 6: and no marker of any reason")
	}
}

Method TestOtherRefusalsNameTheCode()
{
	Set marker = ..Marker()
	Do ..Refuse("row 7: not JSON", marker_" is not JSON", "ERROR #5035", marker)

	Set reply = ..Usable()
	Do reply.%Set(marker, 1)
	Do ..Refuse("row 8: an unknown field", reply.%ToJSON(), "ERROR #9404", marker)

	Set reply = ..Usable()
	Set reply.outcome = marker
	Do ..Refuse("row 9: the class's own check", reply.%ToJSON(), "ERROR #5001", marker)

	Set reply = ..Usable()
	Set reply.reasons = marker
	Do ..Refuse("row 10: a string for the list", reply.%ToJSON(), "ERROR #9406 on Reasons", marker)
	Set reply = ..Usable()
	Set reply.reasons = [{"a": (marker)}]
	Do ..Refuse("row 10: an object for a list element", reply.%ToJSON(), "ERROR #9406 on Reasons element 1", marker)
	Set reply = ..Usable()
	Set reply.confidence = marker
	Do ..Refuse("row 10: a string for the number", reply.%ToJSON(), "ERROR #7207 on Confidence", marker)

	Kill ^||ZzProbeReplyCheck
	Set ^||ZzProbeReplyCheck("throwAt") = 1
	Set request = ..NewRequest("throws")
	Set replyMsg = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set replyMsg.Text = ..Usable().%ToJSON()
	Set ref = ..Conclude(request, replyMsg, .response, .sc)
	Do $$$AssertStatusOK(sc, "row 11: the reply is concluded")
	Do $$$AssertEquals(..Warning(ref, .warning), 1, "row 11: one warning names the decision")
	Do $$$AssertEquals(warning, ..W1(ref, "ERROR #5035"), "row 11: a check that throws gives its code")
	Do $$$AssertTrue(warning '[ "The probe check throws", "row 11: and not the exception's text")
}

Method TestRefusalTextForms()
{
	Set marker = ..Marker()
	Set long = ..Pad(marker, 42)
	Set decide = ..#DECIDE
	Set sc = $SYSTEM.Status.EmbedStatus($SYSTEM.Status.Error(7201, long, 32), $SYSTEM.Status.Error(5802, ..#PROBE_":Reasons(6)", long))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "Reasons element 6: 42 > 32", "a: a list element over its limit")
	Set sc = $SYSTEM.Status.EmbedStatus($SYSTEM.Status.Error(7202, "ab", 3), $SYSTEM.Status.Error(5802, ..#PROBE_":Note", "ab"))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "Note: 2 < 3", "b: a text under its limit")
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", $SYSTEM.Status.Error(5659, ..#PROBE_":Outcome"), ..#PROBE), "ERROR #5659 on Outcome", "c: a required property")
	Set sc = $SYSTEM.Status.EmbedStatus($SYSTEM.Status.Error(7201, long, 32), $SYSTEM.Status.Error(5802, ..#PROBE_":NoSuchProperty", long))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "ERROR #7201", "d: a property that the class lacks is not named")
	Set sc = $SYSTEM.Status.EmbedStatus($SYSTEM.Status.Error(7201, long, "abc"), $SYSTEM.Status.Error(5802, ..#PROBE_":Note", long))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "ERROR #7201 on Note", "e: a limit that is not a number")
	Set text = $ClassMethod(decide, "RefusalText", $SYSTEM.Status.Error("<Ens>ErrGeneral", marker), ..#PROBE)
	Do $$$AssertEquals(text, "ERROR <Ens>ErrGeneral", "f: a code that is not a number")
	Do $$$AssertTrue(text '[ marker, "f: and none of the marker")
	Set sc = $SYSTEM.Status.AppendStatus($SYSTEM.Status.Error(5001, "same"), $SYSTEM.Status.Error(5001, "same"))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "ERROR #5001", "g: an error that repeats is named once")
	Set sc = $$$OK
	For code = 5011:1:5017 Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(code, marker))
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", sc, ..#PROBE), "ERROR #5011; ERROR #5012; ERROR #5013; ERROR #5014; ERROR #5015; and 2 more", "h: five parts, then the count of the rest")
	Do $$$AssertEquals($ClassMethod(decide, "RefusalText", $$$OK, ..#PROBE), "an error", "i: no error")
}

}
