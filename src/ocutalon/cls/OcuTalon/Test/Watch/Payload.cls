/// Tests of the pure parts of Story 5.4's diagnosis: the checked payload OcuTalon.Watch.Msg.DiagnosisPayload (as Decide checks a diagnose reply with it,
/// Decide.CheckReply) and the item noun of OcuTalon.Watch.ItemNoun. They need no production and no namespace, so they run anywhere, a slot included.
///   - TestPayloadAccepted (row Payload check): a usable data-format reply with its fix and noun, a usable partner_outage without a fix or a noun, and an
///     unknown, are accepted and keep their values;
///   - TestPayloadRefused (row Payload check): outcome tellnow, an unlisted category, a fixKind on partner_outage, a data-format change without fixKind,
///     fixSummary, fixParameters.field or elementAtFault, a blank cause, a noun with a blank form, an unknown field, a confidence of 2, no reasons, more than 20
///     evidence references and a cause that holds "since 14:12" (or a fixSummary that holds a time) are refused, each with an error that names the reply check;
///   - TestFilteredParameter: the parameter FILTERED names Cause and FixSummary, which Decide filters;
///   - TestItemNoun (row Item noun): the Orders body class gives order/orders, any other class and an empty one message/messages, as JSON text.
Class OcuTalon.Test.Watch.Payload Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Watch.Msg.DiagnosisPayload";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

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

Method TestFilteredParameter()
{
	Do $$$AssertEquals($Parameter(..#CLASS, "FILTERED"), "Cause,FixSummary", "Decide filters the cause and the fix summary")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Msg.DecisionPayload", "FILTERED"), "", "and the parent names none, so a reply class without FILTERED behaves as before")
}

Method TestItemNoun()
{
	Set noun = "OcuTalon.Watch.ItemNoun"
	Do $$$AssertEquals($ClassMethod(noun, "For", "OcuTalon.Demo.Orders.PartnerOrder"), "{""one"":""order"",""other"":""orders""}", "the Orders body class gives order and orders")
	Do $$$AssertEquals($ClassMethod(noun, "For", "Ens.StringRequest"), "{""one"":""message"",""other"":""messages""}", "another class gives message and messages")
	Do $$$AssertEquals($ClassMethod(noun, "For", ""), "{""one"":""message"",""other"":""messages""}", "so does an empty one")
}

}
