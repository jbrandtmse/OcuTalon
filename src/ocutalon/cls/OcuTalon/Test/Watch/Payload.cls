/// Tests of the pure parts of Story 5.4's diagnosis: the checked payload OcuTalon.Watch.Msg.DiagnosisPayload (as Decide checks a diagnose reply with it,
/// Decide.CheckReply) and the item noun of OcuTalon.Watch.ItemNoun. They need no production and no namespace, so they run anywhere, a slot included.
/// Each test runs with a ReplyCheck begun (OcuTalon.Bridge.ReplyCheck, as Decide begins it) for a diagnose request whose input is an evidence pack with the sample
/// body of an order (OrderNumber, OrderDate 10/16/2026, Sku, Quantity), so that the fix kind can check the usable reply's field and formats (Story 7.1); OnAfterOneTest ends it.
///   - TestPayloadAccepted (row Payload check): a usable data-format reply with its fix and noun, a usable partner_outage without a fix or a noun, an
///     unknown, and a connection_failure whose cause names an address with a port (10.0.0.5:1972, no time of day), are accepted and keep their values;
///   - TestPayloadRefused (row Payload check): outcome tellnow, an unlisted category, a fixKind on partner_outage, a data-format change without fixKind,
///     fixSummary, fixParameters.field or elementAtFault, a blank cause, a noun with a blank form, an unknown field, a confidence of 2, no reasons, more than 20
///     evidence references, a fixSummary on partner_outage and a cause that holds "since 14:12" (or a fixSummary that holds a time) are refused, each with an
///     error that names the reply check;
///   - TestHostReplies (rows Host reply 11:45:50Z and 12:01:54Z): the two recorded replies of the online demo host, whose evidence references are longer than 32
///     characters (42 and 33), go through Decide.Conclude with DiagnosisPayload and the production's filter ReplyGuard and give no fallback, and the answer's payload holds
///     the evidence, cause, category, element, fix kind, fix parameters, fix summary and noun of the reply;
///   - TestRefusalTrace (rows Over the limit and Key in a refused value): a diagnose reply that fails its check gives the fallback invalid, with no reasons and no payload on the
///     row and the response, and one Type 3 warning of Decide.Conclude that starts with the decision's Ref, holds the check's text ("The reply check failed", the field evidence)
///     and, for a key in a refused value, holds [redacted] and not the key;
///   - TestFilteredParameter: the parameter FILTERED names every text of the model that the payload holds, which Decide filters (AD-31);
///   - TestItemNoun (row Item noun): the Orders body class gives order/orders, any other class and an empty one message/messages, as JSON text.
/// Decide.Conclude records a Decision row for each request and logs the warnings above, and ends the test's ReplyCheck (Interpret begins and ends its own), so a test that
/// calls it calls no Check after it. OnAfterOneTest removes those rows and warnings.
Class OcuTalon.Test.Watch.Payload Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Watch.Msg.DiagnosisPayload";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

/// The start of the warning that Decide.Conclude logs for the reply check of an invalid decide or diagnose reply (the decision's Ref follows).
Parameter REFUSED = "The reply check refused the reply of the decision ";

/// The ItemIds of the requests that the test made, for the clean-up of their Decision rows.
Property ItemIds As %List;

/// The number of the newest row of the event log before the test made warnings, or "".
Property Mark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.ItemId = "zzpayload"
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(..Pack())
	Quit ##class(OcuTalon.Bridge.ReplyCheck).Begin(request)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If ..Mark '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Conclude", ..#REFUSED)
	Set ..Mark = ""
	Quit $$$OK
}

/// An evidence pack whose sample is an order of the Orders demo.
ClassMethod Pack() As %DynamicObject
{
	Quit {"format": "ocutalon.evidencePack/1", "namespace": "OCUORDERS", "production": "OcuTalon.Demo.Orders.Production", "item": "OrdersFromPartner", "count": 50, "sample": {"headerId": 2, "bodyClass": "OcuTalon.Demo.Orders.PartnerOrder", "body": {"OrderNumber": "A-1001", "OrderDate": "10/16/2026", "Sku": "SKU-1", "Quantity": "3"}, "error": "The order date was not in the expected format."}}
}

/// A usable data-format diagnosis, as a dynamic object.
ClassMethod Usable() As %DynamicObject
{
	Quit {"outcome": "act", "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "evidence": ["h2"], "fixKind": "repair_resend", "fixParameters": {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}, "cause": "The order date is in another format.", "fixSummary": "rewrite the order date and send the orders again", "itemNoun": {"one": "order", "other": "orders"}, "reasons": ["The sample holds 10/16/2026."], "confidence": 0.9}
}

/// A usable diagnosis that has no fix.
ClassMethod Outage() As %DynamicObject
{
	Quit {"outcome": "act", "causeCategory": "partner_outage", "elementAtFault": "", "evidence": [], "cause": "The partner did not answer.", "fixSummary": "", "reasons": ["The failures show no data problem."], "confidence": 0.7}
}

/// The status of Decide.CheckReply for the object as the reply text.
ClassMethod Check(reply As %DynamicObject, Output payload As %RegisteredObject) As %Status
{
	Quit $ClassMethod(..#DECIDE, "CheckReply", reply.%ToJSON(), ..#CLASS, .payload)
}

/// A diagnose request of an untrusted item whose input is the evidence pack of Pack(); its ItemId is kept for the clean-up.
Method NewRequest() As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(..Pack())
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// Decide.Conclude for the reply text with DiagnosisPayload, the production's filter ReplyGuard and the host sink. Returns the decisionRef it passed; sc is the status.
Method Conclude(request As OcuTalon.Bridge.Msg.Request, text As %String, Output response As %Persistent, Output sc As %Status) As %String [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(..#DECIDE, "Conclude", request, ref, reply, ..#CLASS, "OcuTalon.Checks.ReplyGuard", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Quit ref
}

/// The text of the XData block with only the white space and line ends around it removed.
ClassMethod Fixture(name As %String) As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_name)
	If '$IsObject(xdata) Quit ""
	Quit $ZStrip(xdata.Data.Read(1000000), "<>W")
}

Method TestPayloadAccepted()
{
	Set sc = ..Check(..Usable(), .payload)
	Do $$$AssertStatusOK(sc, "a usable data-format diagnosis is accepted")
	If $IsObject(payload) {
		Do $$$AssertEquals(payload.CauseCategory_"|"_payload.ElementAtFault_"|"_payload.FixKind_"|"_payload.FixParameters.Field_"|"_payload.ItemNoun.One_"/"_payload.ItemNoun.Other, "data_format_change|OrderDate|repair_resend|OrderDate|order/orders", "and keeps its values")
	}
	Set sc = ..Check(..Outage(), .payload)
	Do $$$AssertStatusOK(sc, "a usable partner_outage with no fix and no noun is accepted")
	If $IsObject(payload) Do $$$AssertEquals(payload.FixKind_"|"_$IsObject(payload.FixParameters)_"|"_$IsObject(payload.ItemNoun), "|0|0", "it has no fix kind, no parameters and no noun")
	Set unknown = {"outcome": "act", "causeCategory": "unknown", "cause": "The messages show no one cause.", "reasons": ["Nothing links them."], "confidence": 0.2}
	Do $$$AssertStatusOK(..Check(unknown), "an unknown diagnosis is accepted")
	Set connection = {"outcome": "act", "causeCategory": "connection_failure", "cause": "The partner at 10.0.0.5:1972 refused the connection.", "reasons": ["The error names the address."], "confidence": 0.8}
	Do $$$AssertStatusOK(..Check(connection), "a cause that names an address with a port, and no time of day, is accepted")
	Set long = ..Usable()
	Do long.evidence.%Push($Translate($Justify("", 128), " ", "e"))
	Do $$$AssertStatusOK(..Check(long), "an evidence reference of 128 characters is accepted")
}

Method TestPayloadRefused()
{
	Set reply = ..Usable()
	Set reply.outcome = "tellnow"
	Do ..AssertRefused(reply, "outcome tellnow")
	Set reply = ..Usable()
	Set reply.causeCategory = "weather"
	Do ..AssertRefused(reply, "an unlisted category")
	Set reply = ..Outage()
	Set reply.fixKind = "repair_resend"
	Do ..AssertRefused(reply, "a fixKind on partner_outage")
	Set reply = ..Outage()
	Set reply.fixParameters = {"field": "OrderDate"}
	Do ..AssertRefused(reply, "fixParameters on partner_outage")
	Set reply = ..Outage()
	Set reply.fixSummary = "retry the orders later"
	Do ..AssertRefused(reply, "a fixSummary on partner_outage")
	For name = "fixKind", "fixSummary", "fixParameters", "elementAtFault" {
		Set reply = ..Usable()
		Do reply.%Remove(name)
		Do ..AssertRefused(reply, "a data-format change without "_name)
	}
	Set reply = ..Usable()
	Set reply.fixParameters.field = ""
	Do ..AssertRefused(reply, "a data-format change without fixParameters.field")
	Set reply = ..Usable()
	Set reply.cause = "  "
	Do ..AssertRefused(reply, "a blank cause")
	Set reply = ..Usable()
	Set reply.itemNoun.other = ""
	Do ..AssertRefused(reply, "a noun with a blank form")
	Set reply = ..Usable()
	Set reply.surprise = "yes"
	Do ..AssertRefused(reply, "an unknown field")
	Set reply = ..Usable()
	Set reply.confidence = 2
	Do ..AssertRefused(reply, "a confidence of 2")
	Set reply = ..Usable()
	Set reply.reasons = []
	Do ..AssertRefused(reply, "no reasons")
	Set reply = ..Usable()
	For i = 1:1:21 Do reply.evidence.%Push("h"_i)
	Do ..AssertRefused(reply, "21 evidence references")
	Set reply = ..Usable()
	Do reply.evidence.%Push($Translate($Justify("", 129), " ", "e"))
	Do ..AssertRefused(reply, "an evidence reference of 129 characters")
	Set reply = ..Usable()
	Set reply.cause = "The orders failed since 14:12."
	Do ..AssertRefused(reply, "a cause that holds a time")
	Set reply = ..Usable()
	Set reply.fixSummary = "resend them at 9:05"
	Do ..AssertRefused(reply, "a fixSummary that holds a time")
}

/// Asserts that the reply is refused with an error that names the reply check.
Method AssertRefused(reply As %DynamicObject, label As %String) [ Private ]
{
	Set sc = ..Check(reply, .payload)
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "The reply check failed", "with an error that names the reply check: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 200))
	Do $$$AssertEquals(payload, "", "and gives no payload")
}

/// The two recorded replies of the online demo host (the evidence references of 42 and 33 characters) are concluded with no fallback.
Method TestHostReplies()
{
	For name = "Reply114550", "Reply120154" {
		Set text = ..Fixture(name)
		Do $$$AssertTrue(text '= "", name_": the fixture is read")
		Set fixture = {}.%FromJSON(text)
		Set request = ..NewRequest()
		Do ..Conclude(request, text, .response, .sc)
		Do $$$AssertStatusOK(sc, name_" is concluded")
		Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "0|", name_" gives no fallback")
		Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
		Do $$$AssertEquals($Select($IsObject(row): row.Fallback, 1: "no row"), 0, name_": the Decision row is no fallback")
		Do $$$AssertTrue($IsObject(response) && (response.Payload '= ""), name_": the answer holds a payload")
		If '$IsObject(response) || (response.Payload = "") Continue
		Set answer = {}.%FromJSON(response.Payload)
		For field = "causeCategory", "elementAtFault", "evidence", "fixKind", "fixParameters", "cause", "fixSummary", "itemNoun" {
			Set expected = fixture.%Get(field)
			Set actual = answer.%Get(field)
			If $IsObject(expected) Set expected = expected.%ToJSON()
			If $IsObject(actual) Set actual = actual.%ToJSON()
			Do $$$AssertEquals(actual, expected, name_": the answer's "_field_" is the reply's")
		}
	}
}

/// A diagnose reply that fails its check is the fallback invalid, and the check's text goes to the trace as one redacted warning (nothing else carries it).
Method TestRefusalTrace()
{
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set secret = "sk-ant-"_$Translate($Justify("", 17), " ", "x")
	Set long = ..Usable()
	Do long.evidence.%Push($Translate($Justify("", 129), " ", "e"))
	Set keyed = ..Usable()
	Set keyed.causeCategory = secret
	Set emptied = ..Usable()
	Do emptied.reasons.%Set(0, "No issues.")
	Set blanked = ..Usable()
	Set blanked.cause = "No problems."
	For label = "over the limit", "key in a refused value", "no reason left after the filter", "invalid after the filter" {
		Set reply = $Case(label, "over the limit": long, "key in a refused value": keyed, "no reason left after the filter": emptied, : blanked)
		Set request = ..NewRequest()
		Set ref = ..Conclude(request, reply.%ToJSON(), .response, .sc)
		Do $$$AssertStatusOK(sc, label_": the reply is concluded")
		Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Payload, 1: "none"), "1|invalid|", label_": the fallback invalid and no payload")
		Do $$$AssertEquals($Select($IsObject(response): response.Reasons, 1: "no response"), "", label_": the answer holds no reasons")
		Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
		Do $$$AssertEquals($IsObject(row) && (row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons_"|"_row.Payload = "1|invalid||"), 1, label_": the row is the fallback with no reasons and no payload")
		Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .text, "Conclude", ..#REFUSED_ref)
		Do $$$AssertEquals(count, 1, label_": one warning names the decision")
		If $Extract(label, 1, 2) = "no" {
			Do $$$AssertTrue(text [ "No reason is left once the reply filter has run", label_": it holds the reason")
		} ElseIf label = "invalid after the filter" {
			Do $$$AssertTrue(text [ "After the reply filter ran: ", label_": it holds the re-validation's text")
		} Else {
			Do $$$AssertTrue(text [ "The reply check failed", label_": it holds the check's text")
		}
		If label = "over the limit" {
			Do $$$AssertTrue(text [ "evidence", label_": it names the field evidence")
		} ElseIf label = "key in a refused value" {
			Do $$$AssertTrue((text [ "[redacted]") && (text '[ secret), label_": it holds [redacted] and not the key")
		}
	}
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Conclude", ..#REFUSED)
	Set ..Mark = ""
}

Method TestFilteredParameter()
{
	Do $$$AssertEquals($Parameter(..#CLASS, "FILTERED"), "Cause,FixSummary,ElementAtFault,Evidence,ItemNoun.One,ItemNoun.Other,FixParameters.Field,FixParameters.SourceFormat,FixParameters.TargetFormat", "Decide filters every text of the model: the cause, the fix summary, the element, the evidence, the noun and the fix parameters")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Msg.DecisionPayload", "FILTERED"), "", "and the parent names none, so a reply class without FILTERED behaves as before")
}

Method TestItemNoun()
{
	Set noun = "OcuTalon.Watch.ItemNoun"
	Do $$$AssertEquals($ClassMethod(noun, "For", "OcuTalon.Demo.Orders.PartnerOrder"), "{""one"":""order"",""other"":""orders""}", "the Orders body class gives order and orders")
	Do $$$AssertEquals($ClassMethod(noun, "For", "Ens.StringRequest"), "{""one"":""message"",""other"":""messages""}", "another class gives message and messages")
	Do $$$AssertEquals($ClassMethod(noun, "For", ""), "{""one"":""message"",""other"":""messages""}", "so does an empty one")
}

/// The recorded reply of the online demo host at 11:45:50Z: six evidence references, the last of 42 characters.
XData Reply114550 [ MimeType = application/json ]
{
{"outcome":"act","causeCategory":"data_format_change","elementAtFault":"OrderDate","evidence":["headerId 203","OrderDate 10/31/2026","expected YYYY-MM-DD","50 failed messages","OrdersFromPartner item","trace PartnerOrdersIn to OrdersFromPartner"],"fixKind":"repair_resend","fixParameters":{"field":"OrderDate","sourceFormat":"MM/DD/YYYY","targetFormat":"YYYY-MM-DD"},"cause":"The partner now sends OrderDate as MM/DD/YYYY, but the OrdersFromPartner item expects YYYY-MM-DD, so every order fails.","fixSummary":"repair the OrderDate field from MM/DD/YYYY to YYYY-MM-DD and resend the 50 failed orders, once you approve","itemNoun":{"one":"order","other":"orders"},"reasons":["The sample's OrderDate is 10/31/2026. Day 31 cannot be a month, so the format is MM/DD/YYYY.","The error names the expected format YYYY-MM-DD and the field value that did not match.","All 50 failures share the same error pattern, which points to a change in the partner's date format rather than a one-off bad message."],"confidence":0.92}
}

/// The recorded reply of the online demo host at 12:01:54Z: five evidence references, the first of 33 characters.
XData Reply120154 [ MimeType = application/json ]
{
{"outcome":"act","causeCategory":"data_format_change","elementAtFault":"OrderDate","evidence":["errorPattern: expected YYYY-MM-DD","sample headerId 3","body.OrderDate 10/31/2026","count 50 failed","trace PartnerOrdersIn"],"fixKind":"repair_resend","fixParameters":{"field":"OrderDate","sourceFormat":"MM/DD/YYYY","targetFormat":"YYYY-MM-DD"},"cause":"The partner now sends OrderDate as MM/DD/YYYY, but OrdersFromPartner expects YYYY-MM-DD, so each order is rejected.","fixSummary":"repair the OrderDate field from MM/DD/YYYY to YYYY-MM-DD and resend the 50 failed orders","itemNoun":{"one":"order","other":"orders"},"reasons":["All 50 failures show the same date error pattern.","The sample body holds OrderDate 10/31/2026 in MM/DD/YYYY, and the error names that value.","The item expects YYYY-MM-DD, so this is a format mismatch in one field.","The sample trace shows the message came in from PartnerOrdersIn with status Error."],"confidence":0.9}
}

}
