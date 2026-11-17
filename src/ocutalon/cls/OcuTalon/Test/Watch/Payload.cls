/// Tests of the pure parts of Story 5.4's diagnosis: the checked payload OcuTalon.Watch.Msg.DiagnosisPayload (as Decide checks a diagnose reply with it,
/// Decide.CheckReply) and the item noun of OcuTalon.Watch.ItemNoun. They need no production and no namespace of their own, so they run anywhere, a slot included.
/// Each test runs with a ReplyCheck begun (OcuTalon.Bridge.ReplyCheck, as Decide begins it) for a diagnose request whose input is an evidence pack with the sample
/// body of an order (OrderNumber, OrderDate 10/16/2026, Sku, Quantity), so that the fix kind can check the usable reply's field and formats (Story 7.1); OnAfterOneTest ends it.
///   - TestPayloadAccepted (row Payload check): a usable data-format reply with its fix and noun, a usable partner_outage without a fix or a noun, an
///     unknown, and a connection_failure whose cause names an address with a port (10.0.0.5:1972, no time of day), are accepted and keep their values; so is a
///     data-format diagnosis with no fix at all (no fixKind, fixParameters or fixSummary, or those empty: a reply that cannot tell which way a date reads, Story 7.7);
///   - TestPayloadRefused (row Payload check): outcome tellnow, an unlisted category, a fixKind on partner_outage, a data-format change without fixKind,
///     fixSummary, fixParameters.field or elementAtFault, a blank cause, a noun with a blank form, an unknown field, a confidence of 2, no reasons, more than 20
///     evidence references, an elementAtFault of 129 characters, a fixSummary on partner_outage and a cause that holds "since 14:12" (or a fixSummary that holds a time) are refused, each with an
///     error that names the reply check; so is a fix-less data-format diagnosis without its elementAtFault, and one with only one of the three fix fields;
///   - TestHostReplies (rows Host reply 11:45:50Z and 12:01:54Z): the two recorded replies of the online demo host, whose evidence references are longer than 32
///     characters (42 and 33), go through Decide.Conclude with DiagnosisPayload and the production's filter ReplyGuard and give no fallback, and the answer's payload holds
///     the evidence, cause, category, element, fix kind, fix parameters, fix summary and noun of the reply;
///   - TestRefusalTrace (rows Over the limit and Key in a refused value): a diagnose reply that fails its check, or that the filter leaves with no reason or makes invalid,
///     gives the fallback invalid, with no reasons and no payload on the row and the response, and one Type 3 warning of Decide.Conclude that starts with REFUSED and the
///     decision's Ref and is exactly the words of what failed, never the reply: "The reply check failed: the reply is not one JSON object that <class> accepts: ElementAtFault:
///     rule element-at-fault-too-long" (a text over its limit, DW-1421 round 3); "... ERROR #5001" for a key in a refused value (the class's own check), with neither the key nor [redacted];
///     "No reason is left once the reply filter has run"; "After the reply filter ran: <class> refused the filtered payload: ERROR #5001 rule cause-blank". The class's own rules are named
///     by their tag (DW-1421): "... ERROR #5001 rule cause-category-unlisted" for the key in a refused value, again with neither the key nor [redacted]. Decide.Recheck, run with the same request, class and
///     filter, returns 0 with the problem that the warning holds (and 1 with no problem for a usable reply);
///   - TestRuleTags (DW-1421, AC 1): a reply that breaks exactly one rule is refused with RefusalText "ERROR #5001 rule <tag>" for each of the 21 rules that a diagnosis can meet (the 22 rules of the class and its parent less
///     confidence-missing, which a diagnosis never meets: it is accepted, C5), and the tag's field in REFUSALRULES is the rule's; the class's list holds 31 pairs: without its length and range tags it is RuleTags(), and its length tags are LengthTags();
///   - TestEveryRuleTagged (DW-1421, AC 3 and 5): each REFUSALRULES lists distinct tag:field pairs of the tag form (lower-case letters and hyphens, no digit) whose field (its first part) is the JSON name of a property of the class, the class's list
///     starts with its parent's whole list (which lists three rules, outcome-too-long:outcome, reasons-too-long:reasons and one range tag), and the %OnValidateObject of each class has exactly one $$$ERROR (or $SYSTEM.Status.Error) for each of its own
///     tags that does not end in -too-long or -out-of-range, each tag written once; each -too-long pair names the JSON field of a property with a numeric MAXLEN, is the only one of its field, and is written in no %OnValidateObject, and every
///     top-level field with a numeric MAXLEN has one; each -out-of-range pair names a top-level field with a numeric MINVAL or MAXVAL, is written in no %OnValidateObject, and each class has exactly one, for confidence;
///   - TestLengthTags (DW-1421 round 3, AC 2 and 3): a text over the limit of any of the eight limited fields is "ERROR #7201 rule <field>-too-long" with no digit after the code, for the diagnosis class, for the triage class and after the reply filter;
///   - TestRangeTag (Option R): a confidence over 1 or under 0 is "ERROR #7203 rule confidence-out-of-range" or "ERROR #7204 rule ..." for both reply classes;
///   - TestConfidenceAbsent (DW-1421 C5, AC 6 and 7): a diagnosis with no confidence (or a null one) is accepted and stored with none, never 0, with no confidence key in its payload or its live payload; a confidence of 0 is kept as 0; a triage reply with none is accepted only to tell now or act (the attention floor), and refused to ignore or digest;
///   - TestEvidenceCut (DW-1421 C2' and round 3): an evidence reference over 128 characters is cut (at most 128 characters, ending in U+2026, at the last word boundary when that keeps at least EVIDENCEFLOOR = 64 characters, else mid-word), never refused, and a reference of 128 or fewer is
///     unchanged; each row of the cut (the limit, a space at 128, no boundary, a blank head, a surrogate pair, several, the count cap, a reference that is not a string, a reply that names evidenceCut, a dynamic
///     object as input, text that is not JSON, and the floor: an early space, a head of 64, of 63, and of 63 once two spaces are removed) is pinned, and no other field is cut;
///   - TestEvidenceCutRecorded (DW-1421 C2'): Decide.Conclude of a reply with cut references gives no fallback and a payload whose evidenceCut is the number of cuts, and no text of a reference and no log row of the
///     import is left anywhere, and the conclusion writes no event log or trace row of its job; with no cut, the payload has no evidenceCut;
///   - TestEvidenceTooLongTag (DW-1421 C1): an Evidence reference over 128 characters that is still there at validation (a filter that lengthens one) is "ERROR #7201 rule evidence-too-long", with no number;
///   - TestOtherFallbacksLogNothing (row Other fallbacks): a cut_off and a refusal whose text fails the check, and a turn that the filter empties (invalid with no check error),
///     are fallbacks of their own reason and log no warning of the reply check (Story 5.12, QA);
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

/// A request (a diagnose one of an untrusted item, unless the kind and provenance say otherwise) whose input is the evidence pack of Pack(); its ItemId is kept for the clean-up.
Method NewRequest(kind As %String = "diagnose", provenance As %String = "untrusted") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(..Pack())
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// Decide.Conclude for the reply text (with the finishReason, when given) with DiagnosisPayload, the production's filter ReplyGuard and the host sink. Returns the decisionRef it passed; sc is the status.
Method Conclude(request As OcuTalon.Bridge.Msg.Request, text As %String, Output response As %Persistent, Output sc As %Status, finishReason As %String = "") As %String [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.FinishReason = finishReason
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(..#DECIDE, "Conclude", request, ref, reply, ..#CLASS, "OcuTalon.Checks.ReplyGuard", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Quit ref
}

/// The text of the XData block with only the white space and line ends around it removed.
ClassMethod Fixture(name As %String) As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_name)
	If '$IsObject(xdata) Quit ""
	Quit $ZStrip(xdata.Data.Read(1000000), "<>WC")
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
	Set fixless = ..Usable()
	Do fixless.%Remove("fixKind")
	Do fixless.%Remove("fixParameters")
	Do fixless.%Remove("fixSummary")
	Set sc = ..Check(fixless, .payload)
	Do $$$AssertStatusOK(sc, "a data-format diagnosis with no fix kind, no parameters and no fix summary is accepted")
	If $IsObject(payload) Do $$$AssertEquals(payload.CauseCategory_"|"_payload.ElementAtFault_"|"_payload.FixKind_"|"_$IsObject(payload.FixParameters)_"|"_payload.FixSummary, "data_format_change|OrderDate||0|", "and keeps its category and element, with no fix")
	Set fixless.fixSummary = ""
	Set fixless.fixKind = ""
	Do $$$AssertStatusOK(..Check(fixless), "also when the fix fields are empty")
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
	Do reply.%Remove("fixKind")
	Do reply.%Remove("fixParameters")
	Do reply.%Remove("fixSummary")
	Do reply.%Remove("elementAtFault")
	Do ..AssertRefused(reply, "a data-format change with no fix and no elementAtFault")
	For name = "fixKind", "fixParameters", "fixSummary" {
		Set reply = ..Usable()
		For other = "fixKind", "fixParameters", "fixSummary" {
			If other '= name Do reply.%Remove(other)
		}
		Do ..AssertRefused(reply, "a data-format change with only "_name_" of the fix fields")
	}
	For kind = "reroute", "suspend_item", "resume_item", "zz_kind" {
		Set reply = ..Usable()
		Set reply.fixKind = kind
		Do ..AssertRefused(reply, "a diagnosis that names the fixKind "_kind_", which only the chat can ask for (Story 23.2)")
		Set text = $SYSTEM.Status.GetErrorText(..Check(reply))
		Do $$$AssertTrue(text '[ "reroute,", "and the error lists only the kinds a diagnosis may name")
		Do $$$AssertTrue(text [ ("A data_format_change has a fixKind of "_$ListToString(##class(OcuTalon.Fix.Kind).DiagnosedFor("data_format_change"), ",")), "and it is the refusal of the kind itself, not of its parameters: "_text)
	}
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
	Set reply.elementAtFault = $Translate($Justify("", 129), " ", "e")
	Do ..AssertRefused(reply, "an elementAtFault of 129 characters")
	Set reply = ..Usable()
	Set reply.cause = "The orders failed since 14:12."
	Do ..AssertRefused(reply, "a cause that holds a time")
	Set reply = ..Usable()
	Set reply.fixSummary = "resend them at 9:05"
	Do ..AssertRefused(reply, "a fixSummary that holds a time")
}

/// A setting_change diagnosis that names a listed setting and offers the rollback (Story 23.3).
ClassMethod Rollback() As %DynamicObject
{
	Quit {"outcome": "act", "causeCategory": "setting_change", "elementAtFault": "TargetConfigName", "evidence": ["settingChanges"], "fixKind": "rollback_setting", "cause": "A setting of the failing item changed just before the failures began.", "fixSummary": "", "reasons": ["The pack lists the change."], "confidence": 0.8}
}

/// Story 23.3 (AC3, AC13): a setting_change may name rollback_setting, with no fixParameters and no fixSummary, and an elementAtFault that the pack's settingChanges lists; any
/// other category, a setting the pack does not list, a pack with no settingChanges and a data_format_change that names it are refused.
Method TestRollbackFix()
{
	Set pack = ..Pack()
	Set pack.settingChanges = [{"item": "OrdersFromPartner", "target": "Host", "setting": "TargetConfigName", "oldValue": "OrdersToWarehouse", "newValue": "OrdersToWarehous", "source": "production", "credential": false, "detectedAt": "2026-11-10T11:56:00Z"}]
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.ItemId = "zzpayload"
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(pack)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(request), "a check begins over a pack that lists a setting change")
	Set sc = ..Check(..Rollback(), .payload)
	Do $$$AssertStatusOK(sc, "a setting_change that names rollback_setting and a listed setting is accepted: "_$SYSTEM.Status.GetErrorText(sc))
	Set reply = ..Rollback()
	Set reply.elementAtFault = "Unlisted"
	Do ..AssertRefused(reply, "a setting that the pack does not list")
	Set reply = ..Rollback()
	Set reply.fixParameters = {"field": "TargetConfigName"}
	Do ..AssertRefused(reply, "fixParameters with rollback_setting")
	Set reply = ..Rollback()
	Set reply.fixSummary = "put the setting back"
	Do ..AssertRefused(reply, "a fixSummary with rollback_setting")
	Set reply = ..Rollback()
	Set reply.causeCategory = "connection_failure"
	Do ..AssertRefused(reply, "rollback_setting for a connection_failure")
	Set reply = ..Usable()
	Set reply.fixKind = "rollback_setting"
	Do ..AssertRefused(reply, "rollback_setting for a data_format_change")
	Set reply = ..Rollback()
	Set reply.fixKind = "repair_resend"
	Do ..AssertRefused(reply, "repair_resend for a setting_change")
	Set reply = ..Rollback()
	Do reply.%Remove("fixKind")
	Do $$$AssertStatusOK(..Check(reply, .payload), "a setting_change with no fix is accepted, as before")
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(..Pack())
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(request), "a check begins over a pack with no setting change")
	Do ..AssertRefused(..Rollback(), "rollback_setting when the pack lists no setting change (no fix is accepted without its evidence)")
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
	Set long.elementAtFault = $Translate($Justify("", 129), " ", "e")
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
		Set start = ..#REFUSED_ref_": "
		Set first = start_"The reply check failed: the reply is not one JSON object that "_..#CLASS_" accepts: "
		If label = "over the limit" {
			Set expected = first_"ERROR #7201 rule element-at-fault-too-long"
		} ElseIf label = "key in a refused value" {
			Set expected = first_"ERROR #5001 rule cause-category-unlisted"
		} ElseIf label = "no reason left after the filter" {
			Set expected = start_"No reason is left once the reply filter has run"
		} Else {
			Set expected = start_"After the reply filter ran: "_..#CLASS_" refused the filtered payload: ERROR #5001 rule cause-blank"
		}
		Do $$$AssertEquals(text, expected, label_": the warning names what failed")
		Set valid = $ClassMethod(..#DECIDE, "Recheck", request, reply.%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard", .problem)
		Do $$$AssertEquals(valid, 0, label_": Recheck refuses the reply too")
		Do $$$AssertEquals(..#REFUSED_ref_": "_problem, text, label_": and its problem is the warning's words")
		Do $$$AssertTrue((text '[ secret) && (text '[ "[redacted]"), label_": and holds neither the key nor [redacted]")
	}
	Set valid = $ClassMethod(..#DECIDE, "Recheck", ..NewRequest(), ..Usable().%ToJSON(), ..#CLASS, "OcuTalon.Checks.ReplyGuard", .problem)
	Do $$$AssertEquals(valid_"|"_problem, "1|", "Recheck passes a usable reply, with no problem")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Conclude", ..#REFUSED)
	Set ..Mark = ""
}

/// A reply that falls back for another reason logs no warning of the reply check, even when its text fails the check (cut_off, refusal), and a turn that the filter
/// empties, whose invalid has no check error, logs none either.
Method TestOtherFallbacksLogNothing()
{
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	For label = "cut_off", "refusal", "invalid" {
		Set request = $Case(label, "invalid": ..NewRequest("turn", "user"), : ..NewRequest())
		Set text = $Case(label, "cut_off": "{""outcome"":""act"",""causeCategory"":""data_for", "refusal": "I cannot help with that.", : "Everything I checked passed.")
		Set finish = $Case(label, "cut_off": "max_tokens", "refusal": "refusal", : "")
		Set ref = ..Conclude(request, text, .response, .sc, finish)
		Do $$$AssertStatusOK(sc, label_": the reply is concluded")
		Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|"_label, label_": the fallback is "_label_$Select(label = "invalid": " (a turn that the filter empties)", 1: " (a text that fails its check)"))
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..Mark, .warning, "Conclude", ..#REFUSED_ref), 0, label_": no warning of the reply check names the decision")
	}
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..Mark, "Conclude", ..#REFUSED)
	Set ..Mark = ""
}

/// Ends the check that OnBeforeOneTest began and begins one over RollbackPack().
Method BeginRollbackPack() [ Private ]
{
	Do ##class(OcuTalon.Bridge.ReplyCheck).End()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.ItemId = "zzpayload"
	Set request.OwnerRef = "instance"
	Set request.Input = ##class(OcuTalon.Watch.EvidencePack).Input(..RollbackPack())
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ReplyCheck).Begin(request), "a check begins over a pack that lists a setting change")
}

/// Asserts that a reply that breaks one rule gives RefusalText "ERROR #5001 rule <tag>", and that the tag's field in REFUSALRULES is the given one.
Method AssertRule(tag As %String, field As %String, reply As %DynamicObject) [ Private ]
{
	Set text = reply.%ToJSON()
	Set checked = $ClassMethod(..#DECIDE, "CheckReply", text, ..#CLASS, .payload, .cause)
	Do $$$AssertStatusNotOK(checked, tag_": the reply is refused")
	Do $$$AssertEquals($ClassMethod(..#DECIDE, "RefusalText", cause, ..#CLASS, text), "ERROR #5001 rule "_tag, tag_": the refusal names the rule")
	Set pairs = ","_$Parameter(..#CLASS, "REFUSALRULES")
	Do $$$AssertEquals($Piece($Piece(pairs, ","_tag_":", 2), ",", 1), field, tag_": the field of the tag is "_field)
}

/// The 22 rules of the class and its parent, in rule order, each as "tag:field" (the pairs of REFUSALRULES that the test pins).
ClassMethod RuleTags() As %String
{
	Quit "outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence,outcome-not-act:outcome,cause-category-unlisted:causeCategory,evidence-over-max:evidence,cause-blank:cause,format-no-fix-element-blank:elementAtFault,format-fix-kind-unlisted:fixKind,format-fix-element-blank:elementAtFault,format-fix-summary-blank:fixSummary,format-fix-field-blank:fixParameters.field,rollback-fix-parameters:fixParameters,rollback-fix-summary:fixSummary,rollback-element-unlisted:elementAtFault,fix-kind-not-for-category:fixKind,fix-parameters-not-for-category:fixParameters,fix-summary-not-for-category:fixSummary,item-noun-blank:itemNoun,time-of-day-in-cause:cause,time-of-day-in-fix-summary:fixSummary,fix-parameters-check:fixParameters"
}

/// A diagnose reply that breaks exactly the rule of the tag (checked against RollbackPack's pack, or a pack with the sample of Pack()).
ClassMethod RuleReply(tag As %String) As %DynamicObject
{
	Set reply = $Case(tag, "outcome-unlisted": ..Usable(), "reasons-blank": ..Usable(), "confidence-missing": ..Usable(), "outcome-not-act": ..Usable(), "cause-category-unlisted": ..Usable(), "evidence-over-max": ..Usable(), "cause-blank": ..Usable(), "format-no-fix-element-blank": ..Usable(), "format-fix-kind-unlisted": ..Usable(), "format-fix-element-blank": ..Usable(), "format-fix-summary-blank": ..Usable(), "format-fix-field-blank": ..Usable(), "rollback-fix-parameters": ..Rollback(), "rollback-fix-summary": ..Rollback(), "rollback-element-unlisted": ..Rollback(), "fix-kind-not-for-category": ..Outage(), "fix-parameters-not-for-category": ..Outage(), "fix-summary-not-for-category": ..Outage(), "item-noun-blank": ..Usable(), "time-of-day-in-cause": ..Usable(), "time-of-day-in-fix-summary": ..Usable(), "fix-parameters-check": ..Usable(), : {})
	If tag = "outcome-unlisted" Set reply.outcome = "zz"
	If tag = "reasons-blank" Set reply.reasons = []
	If tag = "confidence-missing" Do reply.%Remove("confidence")
	If tag = "outcome-not-act" Set reply.outcome = "tellnow"
	If tag = "cause-category-unlisted" Set reply.causeCategory = "weather"
	If tag = "evidence-over-max" For i = 1:1:21 Do reply.evidence.%Push("h"_i)
	If tag = "cause-blank" Set reply.cause = "  "
	If tag = "format-no-fix-element-blank" For name = "fixKind", "fixParameters", "fixSummary", "elementAtFault" Do reply.%Remove(name)
	If tag = "format-fix-kind-unlisted" Set reply.fixKind = "zz_kind"
	If tag = "format-fix-element-blank" Do reply.%Remove("elementAtFault")
	If tag = "format-fix-summary-blank" Do reply.%Remove("fixSummary")
	If tag = "format-fix-field-blank" Set reply.fixParameters.field = ""
	If tag = "rollback-fix-parameters" Set reply.fixParameters = {"field": "TargetConfigName"}
	If tag = "rollback-fix-summary" Set reply.fixSummary = "put the setting back"
	If tag = "rollback-element-unlisted" Set reply.elementAtFault = "Unlisted"
	If tag = "fix-kind-not-for-category" Set reply.fixKind = "repair_resend"
	If tag = "fix-parameters-not-for-category" Set reply.fixParameters = {"field": "OrderDate"}
	If tag = "fix-summary-not-for-category" Set reply.fixSummary = "retry the orders later"
	If tag = "item-noun-blank" Set reply.itemNoun.other = ""
	If tag = "time-of-day-in-cause" Set reply.cause = "The orders failed since 14:12."
	If tag = "time-of-day-in-fix-summary" Set reply.fixSummary = "resend them at 9:05"
	If tag = "fix-parameters-check" Set reply.fixParameters.field = "NoSuchField"
	Quit reply
}

/// The evidence pack that the rules of the rollback kind need: Pack() with the setting change of TestRollbackFix.
ClassMethod RollbackPack() As %DynamicObject
{
	Set pack = ..Pack()
	Set pack.settingChanges = [{"item": "OrdersFromPartner", "target": "Host", "setting": "TargetConfigName", "oldValue": "OrdersToWarehouse", "newValue": "OrdersToWarehous", "source": "production", "credential": false, "detectedAt": "2026-11-10T11:56:00Z"}]
	Quit pack
}

/// The length tags, in order, as "tag:field" (the -too-long pairs of REFUSALRULES that the test pins): the parent's two, then the class's six.
ClassMethod LengthTags() As %String
{
	Quit "outcome-too-long:outcome,reasons-too-long:reasons,evidence-too-long:evidence,cause-category-too-long:causeCategory,element-at-fault-too-long:elementAtFault,fix-kind-too-long:fixKind,cause-too-long:cause,fix-summary-too-long:fixSummary"
}

/// The pairs of a REFUSALRULES list (a $ListBuild list) whose tag ends in the suffix, as a $ListBuild list.
ClassMethod TagsEnding(pairs As %List, suffix As %String) As %List [ Private ]
{
	Set result = ""
	Set position = 0
	While $ListNext(pairs, position, pair) {
		Set tag = $Piece(pair, ":", 1)
		If ($Length(tag) > $Length(suffix)) && ($Extract(tag, *-($Length(suffix) - 1), *) = suffix) Set result = result _ $ListBuild(pair)
	}
	Quit result
}

/// DW-1421 (AC 1, AC 5, AC 6): one reply for each of the 21 rules that a diagnosis can meet (the parent's three less confidence-missing, and the class's nineteen); the rule that fails is the one named.
/// confidence-missing is the parent's rule that the class does not meet: a reply without a confidence is accepted.
Method TestRuleTags()
{
	Do ..BeginRollbackPack()
	Set pairs = $ListFromString(..RuleTags(), ",")
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If $Piece(pair, ":", 1) = "confidence-missing" {
			Set reply = ..RuleReply("confidence-missing")
			Do $$$AssertStatusOK(..Check(reply, .payload), "confidence-missing: a diagnosis without a confidence is accepted, not refused")
			If $IsObject(payload) Do $$$AssertEquals(payload.Confidence, "", "confidence-missing: and it has no confidence")
			Continue
		}
		Do ..AssertRule($Piece(pair, ":", 1), $Piece(pair, ":", 2), ..RuleReply($Piece(pair, ":", 1)))
	}
	Set actual = $ListFromString($Parameter(..#CLASS, "REFUSALRULES"), ",")
	Do $$$AssertEquals($ListLength(actual), 31, "the list holds 22 rules, 8 length tags and the range tag of the confidence")
	Set rules = ""
	Set position = 0
	While $ListNext(actual, position, pair) {
		Set tag = $Piece(pair, ":", 1)
		If ($ListLength(..TagsEnding($ListBuild(pair), "-too-long")) = 0) && ($ListLength(..TagsEnding($ListBuild(pair), "-out-of-range")) = 0) Set rules = rules _ $ListBuild(pair)
	}
	Do $$$AssertEquals($ListToString(rules, ","), ..RuleTags(), "the list without its length and range tags is the rules of the class, in order")
	Do $$$AssertEquals($ListToString(..TagsEnding(actual, "-too-long"), ","), ..LengthTags(), "its length tags, in order, are the eight of LengthTags")
	Do $$$AssertEquals($ListToString(..TagsEnding(actual, "-out-of-range"), ","), "confidence-out-of-range:confidence", "and its range tag is confidence-out-of-range")
}

/// DW-1421 (AC 3, AC 5): the tag lists, and one tag literal for each $$$ERROR of each class's own %OnValidateObject.
Method TestEveryRuleTagged()
{
	Set parent = "OcuTalon.Bridge.Msg.DecisionPayload"
	Set parentPairs = $ListFromString($Parameter(parent, "REFUSALRULES"), ",")
	Set pairs = $ListFromString($Parameter(..#CLASS, "REFUSALRULES"), ",")
	Set parentRules = 0
	Set position = 0
	While $ListNext(parentPairs, position, pair) {
		If ($ListLength(..TagsEnding($ListBuild(pair), "-too-long")) = 0) && ($ListLength(..TagsEnding($ListBuild(pair), "-out-of-range")) = 0) Set parentRules = parentRules + 1
	}
	Do $$$AssertEquals(parentRules, 3, "the parent lists its three rules")
	Do $$$AssertEquals($ListLength(..TagsEnding(parentPairs, "-too-long")), 2, "and two length tags")
	Do $$$AssertEquals($ListLength(..TagsEnding(parentPairs, "-out-of-range")), 1, "and one range tag")
	Do $$$AssertEquals($ListToString($List(pairs, 1, $ListLength(parentPairs)), ","), $ListToString(parentPairs, ","), "the class's list starts with its parent's whole list")
	For class = parent, ..#CLASS {
		Set list = ""
		Set lengthTags = ""
		Set rangeTags = ""
		Kill seen, lengthFields, rangeFields
		Set index = 0
		Set position = 0
		While $ListNext($Select(class = parent: parentPairs, 1: pairs), position, pair) {
			Set index = index + 1
			Set tag = $Piece(pair, ":", 1)
			Do $$$AssertTrue(tag ? 1L.(1L,1"-"), tag_": a tag is lower-case letters and hyphens, with no digit")
			Do $$$AssertTrue($Piece(pair, ":", 2) '= "", tag_": the pair names a field")
			Do $$$AssertTrue(..JsonField(class, $Piece($Piece(pair, ":", 2), ".", 1)), tag_": and its field is the JSON name of a property of the class")
			Do $$$AssertTrue('$Data(seen(tag)), tag_": and the tag is listed once")
			Set seen(tag) = ""
			If $ListLength(..TagsEnding($ListBuild(pair), "-too-long")) {
				Set lengthTags = lengthTags _ $ListBuild(pair)
				Do $$$AssertTrue(..MaxLen(class, $Piece(pair, ":", 2)) ? 1.N, tag_": a length tag names the JSON field of a property with a numeric MAXLEN")
				Do $$$AssertTrue('$Data(lengthFields($Piece(pair, ":", 2))), tag_": and is the only length tag of its field")
				Set lengthFields($Piece(pair, ":", 2)) = ""
			} ElseIf $ListLength(..TagsEnding($ListBuild(pair), "-out-of-range")) {
				Set rangeTags = rangeTags _ $ListBuild(pair)
				Do $$$AssertTrue($Piece(pair, ":", 2) '[ ".", tag_": a range tag names a top-level field")
				Do $$$AssertTrue($IsValidNum(..Param(class, $Piece(pair, ":", 2), "MINVAL")) || $IsValidNum(..Param(class, $Piece(pair, ":", 2), "MAXVAL")), tag_": and a field with a numeric MINVAL or MAXVAL")
			} ElseIf (class = parent) || (index > $ListLength(parentPairs)) {
				Set list = list _ $ListBuild(pair)
			}
		}
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(class, .text), class_" has source")
		Set body = ..ValidateBody(text)
		Do $$$AssertTrue(body '= "", class_": its %OnValidateObject is found")
		Set errors = ($Length(body, "$$$ERROR(") - 1) + ($Length(body, "$SYSTEM.Status.Error(") - 1)
		Do $$$AssertEquals(errors, $ListLength(list), class_": one $$$ERROR for each of its own rules that is not a length or range tag")
		Set position = 0
		While $ListNext(list, position, pair) {
			Set tag = $Piece(pair, ":", 1)
			Do $$$AssertEquals($Length(body, ", """_tag_""")") - 1, 1, class_": the tag "_tag_" is written once")
		}
		Set position = 0
		While $ListNext(lengthTags _ rangeTags, position, pair) {
			Do $$$AssertTrue(body '[ $Piece(pair, ":", 1), class_": the length or range tag "_$Piece(pair, ":", 1)_" is written in no %OnValidateObject")
		}
		// every top-level field with a numeric MAXLEN has exactly one length tag
		Set limited = 0
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ?", class)
		While rows.%Next() {
			Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_rows.%Get("Name"))
			If '$IsObject(property) Continue
			Set field = property.Parameters.GetAt("%JSONFIELDNAME")
			If (field = "") || '(property.Parameters.GetAt("MAXLEN") ? 1.N) Continue
			Set limited = limited + 1
			Do $$$AssertTrue($Data(lengthFields(field)), class_": the limited field "_field_" has a length tag")
		}
		Do $$$AssertEquals(limited, $ListLength(lengthTags), class_": there is one length tag for each limited field, and no other")
		Do $$$AssertEquals($ListToString(rangeTags, ","), "confidence-out-of-range:confidence", class_": its one range tag is the confidence's")
	}
	Do $$$AssertEquals($ListToString(..TagsEnding(parentPairs, "-too-long"), ","), "outcome-too-long:outcome,reasons-too-long:reasons", "the parent lists outcome-too-long:outcome and reasons-too-long:reasons")
}

/// The MAXLEN of the compiled property of the class whose JSON field name is the field, or "".
ClassMethod MaxLen(class As %String, field As %String) As %String [ Private ]
{
	Quit ..Param(class, field, "MAXLEN")
}

/// The parameter (MAXLEN, MINVAL, MAXVAL) of the compiled property of the class whose JSON field name is the field, or "".
ClassMethod Param(class As %String, field As %String, name As %String) As %String [ Private ]
{
	Set property = ""
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ?", class)
	While rows.%Next() {
		Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_rows.%Get("Name"))
		If $IsObject(property) && (property.Parameters.GetAt("%JSONFIELDNAME") = field) Quit
		Set property = ""
	}
	Quit $Select($IsObject(property): property.Parameters.GetAt(name), 1: "")
}

/// 1 when a compiled property of the class has the JSON field name.
ClassMethod JsonField(class As %String, field As %String) As %Boolean [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ?", class)
	While rows.%Next() {
		Set property = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_rows.%Get("Name"))
		If $IsObject(property) && (property.Parameters.GetAt("%JSONFIELDNAME") = field) Return 1
	}
	Quit 0
}

/// The code lines of the class's %OnValidateObject, from its Method line to its closing brace.
ClassMethod ValidateBody(text As %String) As %String [ Private ]
{
	Set inside = 0
	Set body = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $Piece(text, $Char(10), i)
		If 'inside {
			If $Extract(line, 1, 26) = "Method %OnValidateObject()" Set inside = 1
			Continue
		}
		If line = "}" Quit
		Set start = $Extract($ZStrip(line, "<W"), 1, 2)
		If (start = "//") || ($Extract(start, 1) = ";") || (start = "#;") Continue
		Set body = body _ line _ $Char(10)
	}
	Quit body
}

/// An Outage() reply whose evidence list is the elements, one array element each.
ClassMethod EvidenceReply(elements As %DynamicArray) As %DynamicObject [ Private ]
{
	Set reply = ..Outage()
	Set reply.evidence = elements
	Quit reply
}

/// Asserts that a reply whose only evidence element is the input is accepted with the element as expected, at most 128 characters, and EvidenceCut as given ("" for no cut).
Method AssertCut(label As %String, input As %String, expected As %String, cuts As %String = "") [ Private ]
{
	Set sc = ..Check(..EvidenceReply([(input)]), .payload)
	Do $$$AssertStatusOK(sc, label_": the reply is accepted")
	If '$IsObject(payload) Quit
	Do $$$AssertEquals(payload.Evidence.Count(), 1, label_": it keeps its one reference")
	Set element = payload.Evidence.GetAt(1)
	Do $$$AssertEquals(element, expected, label_": the reference is as expected")
	Do $$$AssertTrue($Length(element) '> 128, label_": and holds at most 128 characters")
	Do $$$AssertEquals(payload.EvidenceCut, cuts, label_": EvidenceCut is "_$Select(cuts = "": "empty", 1: cuts))
	If cuts '= "" Do $$$AssertEquals($Extract(element, $Length(element)), $Char(8230), label_": a cut reference ends in U+2026")
}

/// DW-1421 C2' (rows 1 to 15) and round 3 (rows 16 to 19, the floor): an evidence reference over 128 characters is cut, never refused.
Method TestEvidenceCut()
{
	Do $$$AssertEquals($Parameter(..#CLASS, "EVIDENCEMAX"), ##class(%Dictionary.CompiledProperty).%OpenId(..#CLASS_"||Evidence").Parameters.GetAt("MAXLEN"), "the limit of the cut is the MAXLEN of Evidence")
	Do $$$AssertEquals($Parameter(..#CLASS, "EVIDENCEFLOOR"), 64, "the floor of a cut at a word boundary is 64 characters")
	Set ellipsis = $Char(8230)
	Set e128 = $Translate($Justify("", 128), " ", "e")
	Do ..AssertCut("row 1, 128 characters", e128, e128)
	Do ..AssertCut("row 2, 129 characters", e128_"e", $Extract(e128, 1, 127)_ellipsis, 1)
	Set letters = $Translate($Justify("", 127), " ", "e")
	Do ..AssertCut("row 3, a space at 128", letters_" e", letters_ellipsis, 1)
	Set spaced = "ab cd"_$Extract(e128, 1, 122)
	Do ..AssertCut("row 3, a space at 128 after an earlier one", spaced_" e", spaced_ellipsis, 1)
	Set words = ""
	For i = 1:1:30 Set words = words_"abcdefghi "
	Do $$$AssertEquals($Length(words), 300, "row 4: the text holds 300 characters")
	Do $$$AssertEquals($Extract(words, 120), " ", "row 4: and the next character after the cut is a space")
	Do ..AssertCut("row 4, 300 characters of words", words, $Extract(words, 1, 119)_ellipsis, 1)
	Set double = ""
	For i = 1:1:30 Set double = double_"abcdefghi  "
	Do ..AssertCut("row 4, a boundary after two spaces", double, $Extract(double, 1, 119)_ellipsis, 1)
	Set e300 = $Translate($Justify("", 300), " ", "e")
	Do ..AssertCut("row 5, one word of 300 characters", e300, $Extract(e300, 1, 127)_ellipsis, 1)
	Set blank = "   "_$Extract(e300, 1, 200)
	Do ..AssertCut("row 6, a blank head", blank, $Extract(blank, 1, 127)_ellipsis, 1)
	Set pair = $Char(55357, 56832)
	Set split = $Extract(e300, 1, 126)_pair_$Extract(e300, 1, 20)
	Do $$$AssertEquals($Length(pair), 2, "row 7: a surrogate pair counts 2 characters")
	Do ..AssertCut("row 7, a surrogate pair at 127 and 128", split, $Extract(e300, 1, 126)_ellipsis, 1)
	// row 8, several
	Set long1 = $Extract(e300, 1, 129)
	Set long3 = $Extract(e300, 1, 200)
	Set sc = ..Check(..EvidenceReply([(long1), "h3", (long3)]), .payload)
	Do $$$AssertStatusOK(sc, "row 8: three references, two of them long, are accepted")
	If $IsObject(payload) {
		Do $$$AssertEquals(payload.Evidence.Count()_"|"_payload.Evidence.GetAt(1)_"|"_payload.Evidence.GetAt(2)_"|"_payload.Evidence.GetAt(3)_"|"_payload.EvidenceCut, "3|"_$Extract(e300, 1, 127)_ellipsis_"|h3|"_$Extract(e300, 1, 127)_ellipsis_"|2", "row 8: the long ones are cut, h3 is not, in order, and two were cut")
		Do payload.%JSONExportToString(.json)
		Do $$$AssertTrue(json [ """evidenceCut"":2", "row 8: the payload exports evidenceCut 2: "_json)
	}
	// row 9, the other fields
	Set reply = ..Outage()
	Set reply.elementAtFault = $Extract(e300, 1, 129)
	Do ..AssertRefusal(reply, "ERROR #7201 rule element-at-fault-too-long", "row 9, an elementAtFault of 129")
	Set reply = ..Outage()
	Set reply.reasons = [($Extract(e300, 1, 100)_$Translate($Justify("", 901), " ", "r"))]
	Do ..AssertRefusal(reply, "ERROR #7201 rule reasons-too-long", "row 9, a reason of 1001")
	// rows 10 and 11, the count cap
	Set elements = []
	For i = 1:1:20 Do elements.%Push("h"_i)
	Do elements.%Set(4, e300)
	Set sc = ..Check(..EvidenceReply(elements), .payload)
	Do $$$AssertStatusOK(sc, "row 11: 20 references, one of them long, are accepted")
	If $IsObject(payload) Do $$$AssertEquals(payload.Evidence.Count()_"|"_payload.EvidenceCut, "20|1", "row 11: and one was cut")
	Do elements.%Push("h21")
	Do ..AssertRefusal(..EvidenceReply(elements), "ERROR #5001 rule evidence-over-max", "row 10, 21 references, one of them long")
	// row 12, an element that is not a string
	Do ..AssertRefusal(..EvidenceReply([12345]), "ERROR #9406 on Evidence", "row 12, a number")
	Do ..AssertRefusal(..EvidenceReply([{"a": 1}]), "ERROR #9406 on Evidence element 1", "row 12, an object")
	Set digits = $Translate($Justify("", 129), " ", "7")
	Set text = $Replace(..EvidenceReply(["x"]).%ToJSON(), """evidence"":[""x""]", """evidence"":["_digits_"]")
	Do ..AssertRefusal("", "ERROR #7201 rule evidence-too-long", "row 12, a number of 129 digits", text)
	// row 13, the model sends the count
	Set reply = ..Outage()
	Set reply.evidenceCut = 3
	Do ..AssertRefusal(reply, "ERROR #9404: an unexpected property", "row 13, a reply that names evidenceCut")
	Do reply.%Set("evidenceCut", "", "null")
	Do ..AssertRefusal(reply, "ERROR #9404: an unexpected property", "row 13, a reply that names evidenceCut with null")
	// row 14, a dynamic object as input is not changed
	Set reply = ..EvidenceReply([(e300)])
	Set object = $ClassMethod(..#CLASS, "%New")
	Do $$$AssertStatusOK(object.%JSONImport(reply), "row 14: a dynamic object is imported")
	Do $$$AssertEquals(object.Evidence.GetAt(1)_"|"_object.EvidenceCut, $Extract(e300, 1, 127)_ellipsis_"|1", "row 14: the payload is cut")
	Do $$$AssertEquals(reply.evidence.%Get(0), e300, "row 14: and the caller's object is not")
	// row 15, text that is not JSON gives the inherited status
	Set parent = $ClassMethod("OcuTalon.Bridge.Msg.DecisionPayload", "%New")
	Set own = $ClassMethod(..#CLASS, "%New")
	For text = "this is not JSON", "[1,2]", "{" {
		Set expected = parent.%JSONImport(text)
		Set actual = own.%JSONImport(text)
		Do $$$AssertStatusNotOK(actual, "row 15: "_text_" is not imported")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorText(actual), $SYSTEM.Status.GetErrorText(expected), "row 15: with the status of the inherited import")
	}
	// rows 16 to 19, the floor of the cut at a word boundary
	Set early = "TargetConfigNames: "_$Translate($Justify("", 140), " ", "e")
	Do $$$AssertEquals($Find(early, " ") - 1, 19, "row 16: the only space is at 19")
	Do ..AssertCut("row 16, a reference whose only space is early", early, $Extract(early, 1, 127)_ellipsis, 1)
	Set kept64 = $Translate($Justify("", 64), " ", "a")_" "_$Translate($Justify("", 100), " ", "b")
	Do ..AssertCut("row 17, a word boundary that keeps 64", kept64, $Extract(kept64, 1, 64)_ellipsis, 1)
	Set kept63 = $Translate($Justify("", 63), " ", "a")_" "_$Translate($Justify("", 100), " ", "b")
	Do ..AssertCut("row 18, a word boundary that keeps 63", kept63, $Extract(kept63, 1, 127)_ellipsis, 1)
	Set twice = $Translate($Justify("", 63), " ", "a")_"  "_$Translate($Justify("", 100), " ", "b")
	Do ..AssertCut("row 19, 63 kept once two spaces are removed", twice, $Extract(twice, 1, 127)_ellipsis, 1)
}

/// Asserts that the reply is refused and RefusalText of the cause is the text.
Method AssertRefusal(reply As %DynamicObject, expected As %String, label As %String, text As %String = "") [ Private ]
{
	If text = "" Set text = reply.%ToJSON()
	Set checked = $ClassMethod(..#DECIDE, "CheckReply", text, ..#CLASS, .payload, .cause)
	Do $$$AssertStatusNotOK(checked, label_": the reply is refused")
	Do $$$AssertEquals($ClassMethod(..#DECIDE, "RefusalText", cause, ..#CLASS, text), expected, label_": the refusal is "_expected)
	Do $$$AssertEquals(payload, "", label_": and gives no payload")
}

/// DW-1421 C2' (AC 5): the cut is counted in the stored payload and nowhere else.
Method TestEvidenceCutRecorded()
{
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set markerA = "zzmarka"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set markerB = "zzmarkb"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set filler = $Translate($Justify("", 130), " ", "e")
	Set request = ..NewRequest()
	// Trace logging is on for this job during the conclusion, as in a host with Log Trace Events, so that a $$$TRACE writes an Ens_Util.Log row that the checks below see.
	Merge ensemble = %Ensemble
	Set hadQuiet = $Data(%QUIET) # 2
	Set quiet = $Get(%QUIET)
	Set %Ensemble("DoTrace") = 1
	Set %Ensemble("LogSystemTrace") = 1
	Set %QUIET = 1
	Try {
		Do ..Conclude(request, ..EvidenceReply([(filler_markerA), "h3", (filler_markerB)]).%ToJSON(), .response, .sc)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Kill %Ensemble
	Merge %Ensemble = ensemble
	If hadQuiet { Set %QUIET = quiet } Else { Kill %QUIET }
	Do $$$AssertStatusOK(sc, "a reply with two long references is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "0|", "it gives no fallback")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
	Do $$$AssertTrue($IsObject(row) && (row.Payload '= ""), "the Decision row holds a payload")
	If '$IsObject(row) || (row.Payload = "") Quit
	Set answer = {}.%FromJSON(row.Payload)
	Set cut = $Extract(filler, 1, 127)_$Char(8230)
	Do $$$AssertEquals(answer.evidenceCut, 2, "its evidenceCut is the number of references cut")
	Do $$$AssertEquals(answer.evidence.%Get(0)_"|"_answer.evidence.%Get(1)_"|"_answer.evidence.%Get(2), cut_"|h3|"_cut, "and its evidence holds the cut references")
	Set all = row.Payload_"|"_row.Reasons_"|"_$Select($IsObject(response): response.Payload_"|"_response.Reasons, 1: "")
	Do $$$AssertTrue((all '[ markerA) && (all '[ markerB), "no text beyond the cut is in the row or the response")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND (Text [ ? OR Text [ ? OR SourceMethod = '%JSONImport')", mark, markerA, markerB)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "no event log row holds a marker or comes from the import")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Job = ?", mark, $Job)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "and the conclusion writes no event log or trace row at all: the count is in the payload only")
	Do $$$AssertTrue($IsObject(response), "the conclusion gives a response")
	Do $$$AssertEquals(($Length(row.Payload, "evidenceCut") - 1)_"|"_(row.Reasons [ "evidenceCut")_"|"_($Select($IsObject(response): response.Reasons, 1: "") [ "evidenceCut"), "1|0|0", "the count is named once, in the payload, and in no reason")
	Set request = ..NewRequest()
	Do ..Conclude(request, ..Outage().%ToJSON(), .response, .sc)
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
	Do $$$AssertTrue($IsObject(row) && (row.Payload '= "") && (row.Payload '[ "evidenceCut"), "a reply with no long reference has no evidenceCut in its payload")
	Do $$$AssertEquals($ClassMethod(..#CLASS, "%New").EvidenceCut, "", "and a new payload has no count")
}

/// DW-1421 C1 (AC 6): the length refusal of an Evidence reference has a fixed tag.
Method TestEvidenceTooLongTag()
{
	Set payload = $ClassMethod(..#CLASS, "%New")
	Set payload.Outcome = "act"
	Set payload.CauseCategory = "partner_outage"
	Set payload.Cause = "The partner did not answer."
	Do payload.Reasons.Insert("The failures show no data problem.")
	Set payload.Confidence = 0.7
	Do payload.Evidence.Insert($Translate($Justify("", 129), " ", "e"))
	Set sc = payload.%ValidateObject()
	Do $$$AssertStatusNotOK(sc, "an Evidence reference of 129 characters inserted directly is refused")
	Set text = $ClassMethod(..#DECIDE, "RefusalText", sc, ..#CLASS)
	Do $$$AssertEquals(text, "ERROR #7201 rule evidence-too-long", "its refusal is the length tag")
	Do $$$AssertEquals($Translate($Piece(text, " rule ", 2), "0123456789"), $Piece(text, " rule ", 2), "and holds no digit after rule")
	Set reply = ..Outage()
	Set reply.elementAtFault = $Translate($Justify("", 129), " ", "e")
	Do ..AssertRefusal(reply, "ERROR #7201 rule element-at-fault-too-long", "an elementAtFault of 129 has its own length tag")
	Set reply = ..EvidenceReply([($Translate($Justify("", 128), " ", "e"))])
	Set valid = $ClassMethod(..#DECIDE, "Recheck", ..NewRequest(), reply.%ToJSON(), ..#CLASS, "OcuTalon.Test.Bridge.ProbeFilter", .problem)
	Kill ^||ZzProbeFilter
	Do $$$AssertEquals(valid, 0, "a reference of 128 characters that the filter lengthens is refused")
	Do $$$AssertEquals(problem, "After the reply filter ran: "_..#CLASS_" refused the filtered payload: ERROR #7201 rule evidence-too-long", "with the length tag in the words of the check")
}

/// A text of n copies of the letter.
ClassMethod Of(n As %Integer, letter As %String = "e") As %String [ Private ]
{
	Quit $Translate($Justify("", n), " ", letter)
}

/// Asserts that the text is refused by CheckReply of the reply class with RefusalText exactly "ERROR #<code> rule <tag>" (no digit after the code), and that the capture harness reads
/// the tag as the rule and the field as the field.
Method AssertTag(class As %String, text As %String, tag As %String, field As %String, label As %String, code As %Integer = 7201) [ Private ]
{
	Set checked = $ClassMethod(..#DECIDE, "CheckReply", text, class, .payload, .cause)
	Do $$$AssertStatusNotOK(checked, label_": the reply is refused")
	Set shown = $ClassMethod(..#DECIDE, "RefusalText", cause, class, text)
	Do $$$AssertEquals(shown, "ERROR #"_code_" rule "_tag, label_": the refusal is the tag")
	Do $$$AssertEquals($Translate($Piece(shown, " rule ", 2), "0123456789"), $Piece(shown, " rule ", 2), label_": and holds no digit after rule")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Test.Eval.CaptureTool", "RuleOf", shown), tag, label_": the capture reads the tag as the rule")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Test.Eval.CaptureTool", "FieldOf", shown, tag, class), field, label_": and "_field_" as the field")
}

/// DW-1421 round 3 (AC 2, AC 3): each limited field has its own length tag, with no position, length or limit.
Method TestLengthTags()
{
	Set triage = "OcuTalon.Bridge.Msg.DecisionPayload"
	Set reply = ..Usable()
	Set reply.outcome = ..Of(33)
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "outcome-too-long", "outcome", "L1, an outcome of 33")
	Set reply = ..Outage()
	Set reply.reasons = [(..Of(1001, "r"))]
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "reasons-too-long", "reasons", "L2, a reason of 1001")
	Set reply = ..Outage()
	Set reply.causeCategory = ..Of(33)
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "cause-category-too-long", "causeCategory", "L3, a causeCategory of 33")
	Set reply = ..Outage()
	Set reply.elementAtFault = ..Of(129)
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "element-at-fault-too-long", "elementAtFault", "L4, an elementAtFault of 129")
	Set reply = ..Usable()
	Set reply.fixKind = ..Of(33)
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "fix-kind-too-long", "fixKind", "L5, a fixKind of 33")
	Set reply = ..Outage()
	Set reply.cause = ..Of(1001, "c")
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "cause-too-long", "cause", "L6, a cause of 1001")
	Set reply = ..Usable()
	Set reply.fixSummary = ..Of(1001, "s")
	Do ..AssertTag(..#CLASS, reply.%ToJSON(), "fix-summary-too-long", "fixSummary", "L7, a fixSummary of 1001")
	Set text = $Replace(..EvidenceReply(["x"]).%ToJSON(), """evidence"":[""x""]", """evidence"":["_..Of(129, "7")_"]")
	Do ..AssertTag(..#CLASS, text, "evidence-too-long", "evidence", "L8, a number of 129 digits")
	Set reply = ..EvidenceReply([(..Of(128))])
	Set valid = $ClassMethod(..#DECIDE, "Recheck", ..NewRequest(), reply.%ToJSON(), ..#CLASS, "OcuTalon.Test.Bridge.ProbeFilter", .problem)
	Kill ^||ZzProbeFilter
	Do $$$AssertEquals(valid_"|"_problem, "0|After the reply filter ran: "_..#CLASS_" refused the filtered payload: ERROR #7201 rule evidence-too-long", "L8, a 128 element that the filter lengthens")
	Set reply = {"outcome": "ignore", "reasons": ["r"], "confidence": 0.9}
	Set reply.outcome = ..Of(33)
	Do ..AssertTag(triage, reply.%ToJSON(), "outcome-too-long", "outcome", "L9, a triage outcome of 33")
	Set reply = {"outcome": "ignore", "reasons": ["r"], "confidence": 0.9}
	Set reply.reasons = [(..Of(1001, "r"))]
	Do ..AssertTag(triage, reply.%ToJSON(), "reasons-too-long", "reasons", "L9, a triage reason of 1001")
	Set reply = ..Outage()
	Set reply.cause = ..Of(997, "c")
	Set valid = $ClassMethod(..#DECIDE, "Recheck", ..NewRequest(), reply.%ToJSON(), ..#CLASS, "OcuTalon.Test.Bridge.ProbeFilter", .problem)
	Kill ^||ZzProbeFilter
	Do $$$AssertEquals(valid_"|"_problem, "0|After the reply filter ran: "_..#CLASS_" refused the filtered payload: ERROR #7201 rule cause-too-long", "L10, a cause of 997 that the filter makes 1001")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Test.Eval.CaptureTool", "FieldOf", "ERROR #7201 rule element-at-fault-too-long", "element-at-fault-too-long", ..#CLASS), "elementAtFault", "L12, the harness reads the field of the tag")
}

/// Option R (DW-1421 round 3): a confidence over 1 or under 0 has the fixed tag confidence-out-of-range, with no value or limit, for both reply classes.
Method TestRangeTag()
{
	Set triage = "OcuTalon.Bridge.Msg.DecisionPayload"
	For value = 85, -1 {
		Set code = $Select(value > 1: 7203, 1: 7204)
		Set reply = {"outcome": "ignore", "reasons": ["r"]}
		Set reply.confidence = value
		Do ..AssertTag(triage, reply.%ToJSON(), "confidence-out-of-range", "confidence", "decide, a confidence of "_value, code)
		Set reply = ..Outage()
		Set reply.confidence = value
		Do ..AssertTag(..#CLASS, reply.%ToJSON(), "confidence-out-of-range", "confidence", "diagnose, a confidence of "_value, code)
	}
	Set reply = ..Outage()
	Set reply.confidence = 1
	Do $$$AssertStatusOK(..Check(reply, .payload), "a confidence of 1 is accepted")
}

/// Asserts the stored and the live form of a diagnose reply: the Decision row, its payload, the answer and the live payload, for the confidence as given ("" for none).
Method AssertStored(label As %String, reply As %DynamicObject, confidence As %String) [ Private ]
{
	Set request = ..NewRequest()
	Do ..Conclude(request, reply.%ToJSON(), .response, .sc)
	Do $$$AssertStatusOK(sc, label_": the reply is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "0|", label_": no fallback")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "diagnose")
	Do $$$AssertTrue($IsObject(row) && (row.Payload '= ""), label_": the row holds a payload")
	If '$IsObject(row) || '$IsObject(response) || (row.Payload = "") Quit
	Set type = $Select(confidence = "": "unassigned", 1: "number")
	Do $$$AssertEquals($Length(row.Confidence)_"|"_row.Confidence, $Length(confidence)_"|"_confidence, label_": the row's confidence is "_$Select(confidence = "": "empty", 1: confidence))
	Set stored = {}.%FromJSON(row.Payload)
	Do $$$AssertEquals(stored.%GetTypeOf("confidence"), type, label_": the payload's confidence is "_type)
	If confidence '= "" Do $$$AssertEquals(stored.confidence, confidence, label_": and the payload's confidence is "_confidence)
	Do $$$AssertEquals($Length(response.Confidence)_"|"_response.Confidence, $Length(confidence)_"|"_confidence, label_": the answer's confidence is the row's")
	Set live = ##class(OcuTalon.Live.Payload.Decision).FromRow(row)
	Do live.%JSONExportToString(.json)
	Set exported = {}.%FromJSON(json)
	Do $$$AssertEquals(exported.%GetTypeOf("confidence"), type, label_": the live payload's confidence is "_type)
	If confidence '= "" Do $$$AssertEquals(exported.confidence, confidence, label_": and it is "_confidence)
}

/// DW-1421 C5 (AC 6, AC 7): a diagnosis with no confidence is accepted, stored with none (never 0) and shown with none; the triage class still refuses one.
Method TestConfidenceAbsent()
{
	Set ..Mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Msg.DecisionPayload", "CONFIDENCEREQUIRED")_"|"_$Parameter("OcuTalon.Bridge.Msg.DecisionPayload", "CONFIDENCEOPTIONAL"), "1|tellnow,act", "DecisionPayload requires a confidence except for the outcomes tellnow and act (the attention floor)")
	Do $$$AssertEquals($Parameter(..#CLASS, "CONFIDENCEREQUIRED"), 0, "DiagnosisPayload does not")
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Bridge.ProbeReplyCheck", "CONFIDENCEREQUIRED"), 1, "and the test probe does")
	// C1
	Set usable = ..Usable()
	Do usable.%Remove("confidence")
	Set outage = ..Outage()
	Do outage.%Remove("confidence")
	Do $$$AssertStatusOK(..Check(usable, .payload), "C1: a usable diagnosis with no confidence is accepted")
	If $IsObject(payload) Do $$$AssertEquals($Length(payload.Confidence), 0, "C1: and its confidence is empty")
	Do $$$AssertStatusOK(..Check(outage, .payload), "C1: an outage with no confidence is accepted")
	If $IsObject(payload) Do $$$AssertEquals($Length(payload.Confidence), 0, "C1: and its confidence is empty")
	// C3 (a check, so before the conclusions, which end the test's ReplyCheck)
	Set nulled = ..Usable()
	Do nulled.%Set("confidence", "", "null")
	Do $$$AssertStatusOK(..Check(nulled, .payload), "C3: a null confidence is accepted")
	If $IsObject(payload) Do $$$AssertEquals($Length(payload.Confidence), 0, "C3: and it is absent")
	// C6 (a check too)
	// C6 and the attention floor (the triage-accept ruling): a decide reply to ignore with no confidence is refused; one to tell now is accepted, with none
	Do ..AssertTag("OcuTalon.Bridge.Msg.DecisionPayload", {"outcome": "ignore", "reasons": ["r"]}.%ToJSON(), "confidence-missing", "confidence", "C6, a decide reply to ignore with no confidence", 5001)
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).CheckReply({"outcome": "tellnow", "reasons": ["r"]}.%ToJSON(), "OcuTalon.Bridge.Msg.DecisionPayload", .decided)
	Do $$$AssertStatusOK(sc, "C6: a decide reply to tell now with no confidence is accepted")
	If $IsObject(decided) Do $$$AssertEquals(decided.Outcome_"|"_$Length(decided.Confidence), "tellnow|0", "C6: with its outcome and no confidence")
	// C2
	Do ..AssertStored("C2, a usable diagnosis", usable, "")
	Do ..AssertStored("C2, an outage", outage, "")
	Do ..AssertStored("C3, a null confidence", nulled, "")
	// C4
	Set zero = ..Usable()
	Set zero.confidence = 0
	Do ..AssertStored("C4, a confidence of 0", zero, 0)
	Set kept = ..Usable()
	Set kept.confidence = 0.94
	Do ..AssertStored("a confidence of 0.94", kept, 0.94)
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
