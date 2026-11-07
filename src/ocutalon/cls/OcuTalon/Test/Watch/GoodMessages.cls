Include Ensemble

/// Tests of the dry run's check against good messages (Story 7.9; FR-25; AD-3, AD-16): before a repair is offered, RepairResend.DryRun reads the newest 20 messages from the
/// same source as its targets that went through (Reader.Good) and tries the repair on each in memory. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (IncidentManager and FixExecutor are code of the running production), with demo mode on, through Test.Watch.Case: real orders of OCUORDERS, the CI mock as the model (its
/// default diagnosis, a repair_resend from MM/DD/YYYY to YYYY-MM-DD), the real FixExecutor dry run, the real Approval.Raise and the real notice. The orders that go through are
/// sent in YYYY-MM-DD with the failures' own trace reference (Case.SendGood); the failed orders are written MM/DD/YYYY. A test waits at most 90 seconds for a diagnosis or the end of a
/// request, 60 for a later round's notice or warning and Case's bounds (WAITBATCH and the like) for the rest (test bounds, not NFR-7). The incidents, requests, holds, orders and warnings of a test are removed after it (Case; OnAfterOneTest).
///   - TestFewerThanTwentyGood (Integration AC; the read-only proof): 5 orders that went through and 3 that failed in S's reference: one pending request; the Notification
///     has the key incident.withFixChecked and the slots goodChecked 5, goodChanged 0 and goodNoun orders; the phone message that SimPhoneOut kept holds the ruled line with
///     5 and 0; the stored dry run has exactly the keys of DRYRUNKEYS; a dry run asked again gives the notice's counts in its goodCheck, and changes nothing in either
///     namespace but its own session (Test.Fix.Snapshot), leaves the good orders' bodies and statuses as they were, writes no event-log row and calls no model. Task 0
///     (Story 7.9) records the Status, IsError and Type of the good headers that Reader.Good returns;
///   - TestOnlyTheNewestTwenty: 23 good orders and 2 failed: goodChecked is 20, and Reader.Good reads the 20 newest by header id, 23 when it is given a larger limit;
///   - TestOneGood: 1 good order and 3 failed: goodChecked 1, goodNoun order, and the line says "the last 1 order";
///   - TestNoGoodMessages: 3 failed orders and none that went through: the key is incident.withFix, there is no line and no good slot, and the dry run's goodCheck is {0, 0}
///     and is not stored (Z1 of Story 7.9's ruling);
///   - TestOneChangedGoodWithholdsTheFix (the owner's demonstrated mutation): 3 good orders, one of them dated 11/05/2026 (it reads in the source format), then 3 failed: the
///     dry run is refused with the reason that the repair would also change 1 of the 3, no request is raised, the incident is open with the variant no_fix and its notice is
///     incident.noFix with the cause, with one Type 3 warning that holds the reason;
///   - TestOtherSourcesAndSessions: good orders of two references and untagged ones, failed orders: Reader.Good gives, for a reference, the good orders of its source and
///     SuperSession only, newest first, at most limit, no failed header and none of the other reference or of the warehouse leg, and no header twice for two references of one
///     source; a production that is not current gives not_current, and an empty list of references or a limit of 0 gives nothing;
///   - TestTwoSourcesInOneIncident: failed orders of two sources (two SuperSessions that belong to no session, so both are of the instance scope) in one incident: the dry run checks the good orders of both (4 and 3, goodCheck 7 and 0),
///     and one good order of the second source dated 11/05/2026 refuses it, with the reason that the repair would also change 1 of the 7;
///   - TestApprovalRunsTheDryRunOnly: the request of the first test is approved and run to result.allThrough: its row holds the kind, parameters and targets that the dry run
///     gave, the copies are repaired copies of the targets only ("Resent <id>"), no good header has a copy and every good body and status is as it was, and the stored dry run has
///     exactly DRYRUNKEYS; then 2 more failed orders: the later request's Notification has the key incident.laterRequestChecked with goodChecked 8 (the 5 good orders and the 3
///     copies);
///   - TestLaterRoundRefused: after a first request over 3 failed orders (5 good orders), one good order is dated 11/05/2026 and 2 more orders fail: nothing is sent for the
///     round, one Type 3 warning holds the reason, and the first request is untouched;
///   - TestUntaggedOrders: untagged good and failed orders (an empty SuperSession): the dry run of an instance incident checks the untagged good orders, so its key is incident.withFixChecked, and Reader.Good
///     for the untagged reference reads the test's own two first (newest first) and only untagged headers of that source.
Class OcuTalon.Test.Watch.GoodMessages Extends OcuTalon.Test.Watch.Case
{

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

/// The ruled line of the notice (many form), with the counts of the test filled in by Line.
Parameter LINE = "Checked against the last {checked} {noun} from the same source that went through: {changed} would change.";

/// The start of the reason of a dry run that would change good messages.
Parameter CHANGED = "The repair would also change ";

/// The newest row of the event log before the test made its warning, or "": OnAfterOneTest removes the warnings after it.
Property WarningMark As %Integer;

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..WarningMark '= "" {
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..WarningMark, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..WarningMark, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGLATER"))
	}
	Set ..WarningMark = ""
	Quit ##super(testname)
}

/// The line of the notice for the counts, as the ruled text words it.
ClassMethod Line(checked As %Integer, changed As %Integer) As %String [ Private ]
{
	Quit $Replace($Replace($Replace(..#LINE, "{checked}", checked), "{noun}", $Select(checked = 1: "order", 1: "orders")), "{changed}", changed)
}

/// The set-up of a test with good orders: the production is ready, the mock is pointed to, the approval role is ready, S watches Orders, good orders (that went through)
/// tagged with S's trace Ref are sent and waited for, the first of them gets the date firstDate when it is given (MM/DD/YYYY, set before anything fails), then failing
/// orders tagged with S's trace Ref become one incident of S. a is S, trace its reference, ref the incident and goodIds the ids of the good headers, ascending.
/// 1 when the set-up is done.
Method Press(name As %String, good As %Integer, failed As %Integer, Output a As %String, Output trace As %String, Output ref As %String, Output goodIds As %String, firstDate As %String = "") As %Boolean [ Private ]
{
	Set (a, trace, ref, goodIds) = ""
	If '..Ready() Quit 0
	If '..PointKeys() Quit 0
	If '..ApprovalReady() Quit 0
	Set a = ..Session(name)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	If good > 0 {
		If '..SendGood(good, trace) Quit 0
		Set goodIds = ..WaitGood(trace, good)
		If $Length(goodIds, ",") '= good Quit 0
		Do ..SettleGood(goodIds)
	}
	If firstDate '= "" Do $$$AssertStatusOK(..SetOrderDate($Piece(goodIds, ",", 1), firstDate), "the first good order is dated "_firstDate)
	If '..Fail(failed, trace) Quit 0
	Set all = ..WaitFailed(failed)
	If all.%Size() '= failed Quit 0
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of S")
	If rows.%Size() < 1 Quit 0
	Set ref = rows.%Get(0).ref
	Quit 1
}

/// Waits until the sessions of the good headers (ids, comma-separated) have settled, so that nothing of the good orders is still on its way.
Method SettleGood(ids As %String) [ Private ]
{
	Set sessions = ""
	For i = 1:1:$Length(ids, ",") {
		Set header = ..Header(..#ORDERS, $Piece(ids, ",", i))
		If $IsObject(header) Set sessions = sessions _ $Select(sessions = "": "", 1: ",") _ header.sessionId
	}
	Do $$$AssertTrue(..WaitSettled(..#ORDERS, sessions), "the good orders have settled")
}

/// The single request of the incident, once the notice is there, with the assertions that it is pending and the one request; "" when there is not exactly one.
Method OneRequest(ref As %String) As %DynamicObject [ Private ]
{
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit ""
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.state_"|"_request.fixKind, "fix|pending|repair_resend", "it is a pending repair_resend fix")
	Quit request
}

/// Asserts that the stored dry run of the request has exactly the keys of DRYRUNKEYS (no goodCheck).
Method AssertStoredKeys(request As %DynamicObject) [ Private ]
{
	Set stored = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(..SortedKeys(stored), ..SortedNames($Parameter("OcuTalon.Bridge.Data.ApprovalRequest", "DRYRUNKEYS")), "the stored dry run has exactly the keys of DRYRUNKEYS: "_..SortedKeys(stored))
}

/// The one Notification of the incident (its kind, catalog key and approval Ref asserted as given); "" when there is not exactly one of that kind.
Method OneNotice(ref As %String, kind As %String, key As %String, approvalRef As %String) As %DynamicObject [ Private ]
{
	Set notes = ..NoticeBodies(ref, kind)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of kind "_kind)
	If notes.%Size() '= 1 Quit ""
	Set note = notes.%Get(0)
	Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, key_"|"_approvalRef, "it has the key "_key_" and the request's Ref")
	Quit note
}

/// Asserts the good slots of a Checked notice and that the phone message of the request holds the ruled line with the counts.
Method AssertGoodLine(a As %String, note As %DynamicObject, request As %DynamicObject, checked As %Integer, changed As %Integer) [ Private ]
{
	Set slots = note.slots
	Do $$$AssertEquals(slots.goodChecked_"|"_slots.goodChanged_"|"_slots.goodNoun, checked_"|"_changed_"|"_$Select(checked = 1: "order", 1: "orders"), "the slots goodChecked, goodChanged and goodNoun")
	Set phone = ..PhoneText(a, request.ref)
	Do $$$AssertTrue(phone [ ("unchanged. "_..Line(checked, changed)_" Nothing has changed yet."), "the phone message holds the line between 'unchanged.' and 'Nothing has changed yet.': "_phone)
}

/// Task 0 of Story 7.9: the Status, IsError and Type of the good headers (ids), logged and asserted (9 Completed, no error, 1 Request).
Method RecordGood(ids As %String) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Kill shapes
	Set seen = ""
	For i = 1:1:$Length(ids, ",") {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, IsError, Type, SuperSession FROM Ens.MessageHeader WHERE ID = ?", $Piece(ids, ",", i))
		If rs.%Next() {
			Set shape = rs.%GetData(1)_"|"_+rs.%GetData(2)_"|"_rs.%GetData(3)
			If '$Data(shapes(shape)) {
				Set shapes(shape) = ""
				Set seen = seen _ shape _ ","
			}
		}
	}
	Do $$$LogMessage("Task 0 (a): Status|IsError|Type of the good headers: "_seen)
	Do $$$AssertEquals(seen, "9|0|1,", "the good headers are Completed (9), not in error (0) and requests (1)")
}

Method TestFewerThanTwentyGood()
{
	If '..Press("fewer", 5, 3, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Do ..RecordGood(goodIds)
	Set request = ..OneRequest(ref)
	If '$IsObject(request) Quit
	Do ..AssertStoredKeys(request)
	Set note = ..OneNotice(ref, "incident", "incident.withFixChecked", request.ref)
	If $IsObject(note) Do ..AssertGoodLine(a, note, request, 5, 0)
	Do ..AssertDelivered(a, "incident", request.ref)

	// the read-only proof: a dry run asked again changes nothing but its own session
	Set sessions = ""
	Set failed = ..Failed(..OrdersFloor)
	For i = 0:1:failed.%Size() - 1 {
		Set sessions = sessions _ $Select(sessions = "": "", 1: ",") _ failed.%Get(i).sessionId
	}
	Do $$$AssertTrue(..WaitSettled(..#ORDERS, sessions), "the failed orders have settled")
	Set goodBefore = ..GoodState(goodIds)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ..#ORDERS), .before)
	Set response = ..AskDryRun(ref, request.fixKind, request.fixParameters, trace, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ..#ORDERS), .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after, session)
	Do $$$AssertEquals(lines.%Size(), 0, "nothing in OCUTALON or OCUORDERS changed but the dry run's own session (and a timer that was already running): "_lines.%ToJSON())
	Do $$$AssertEquals(..GoodState(goodIds), goodBefore, "the good orders' bodies and statuses are as they were")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE SessionId = ?", session)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "FixExecutor wrote no event-log row in the dry run's session")
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", mark, .entries), "the mock's request log is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Diagnose).ModelRequests(entries), 0, "the dry run called no model")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(response.Targets, request.fixTargets, "its targets are the request's")
	Do $$$AssertEquals(dryRun.goodCheck.checked_"|"_dryRun.goodCheck.changed, note.slots.goodChecked_"|"_note.slots.goodChanged, "and its goodCheck holds the counts that the notice shows")
}

/// The bodies and statuses of the headers (ids) as JSON text, to compare before and after.
Method GoodState(ids As %String) As %String [ Private ]
{
	Set state = ""
	For i = 1:1:$Length(ids, ",") {
		Set header = ..Header(..#ORDERS, $Piece(ids, ",", i))
		Set state = state _ $Select($IsObject(header): header.%ToJSON(), 1: "none") _ $Char(30)
	}
	Quit state
}

Method TestOnlyTheNewestTwenty()
{
	If '..Press("newest", 23, 2, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Set request = ..OneRequest(ref)
	If '$IsObject(request) Quit
	Set note = ..OneNotice(ref, "incident", "incident.withFixChecked", request.ref)
	If $IsObject(note) Do ..AssertGoodLine(a, note, request, 20, 0)
	Set newest = ""
	For i = $Length(goodIds, ","):-1:4 {
		Set newest = newest _ $Select(newest = "": "", 1: ",") _ $Piece(goodIds, ",", i)
	}
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", $Piece(request.fixTargets, ",", 1), 20, .good)
	Do $$$AssertEquals(outcome, "read", "Reader.Good reads")
	Do $$$AssertEquals(..IdsOf(good), newest, "the 20 newest good orders by header id, newest first")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", $Piece(request.fixTargets, ",", 1), 25, .good)
	Do $$$AssertEquals(good.%Size(), 23, "and all 23 when the limit is higher")
}

/// The ids of the good headers (a dynamic array of failures as Reader.Good gives them), comma-separated, in the order given.
ClassMethod IdsOf(good As %DynamicArray) As %String [ Private ]
{
	Set ids = ""
	For i = 0:1:good.%Size() - 1 {
		Set ids = ids _ $Select(ids = "": "", 1: ",") _ good.%Get(i).headerId
	}
	Quit ids
}

Method TestOneGood()
{
	If '..Press("onegood", 1, 3, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Set request = ..OneRequest(ref)
	If '$IsObject(request) Quit
	Set note = ..OneNotice(ref, "incident", "incident.withFixChecked", request.ref)
	If $IsObject(note) Do ..AssertGoodLine(a, note, request, 1, 0)
}

Method TestNoGoodMessages()
{
	If '..Press("nogood", 0, 3, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Set request = ..OneRequest(ref)
	If '$IsObject(request) Quit
	Do ..AssertStoredKeys(request)
	Set note = ..OneNotice(ref, "incident", "incident.withFix", request.ref)
	If $IsObject(note) {
		Do $$$AssertEquals(note.slots.%IsDefined("goodChecked")_note.slots.%IsDefined("goodChanged")_note.slots.%IsDefined("goodNoun"), "000", "the slots hold no good-message slot")
		Set phone = ..PhoneText(a, request.ref)
		Do $$$AssertTrue(phone '[ "Checked against", "and the phone message has no good-message line: "_phone)
	}
	Set response = ..AskDryRun(ref, request.fixKind, request.fixParameters, trace, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.goodCheck.%ToJSON(), "{""checked"":0,""changed"":0}", "the dry run's goodCheck is {0, 0}")
}

Method TestOneChangedGoodWithholdsTheFix()
{
	Set ..WarningMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	If '..Press("changed", 3, 3, .a, .trace, .ref, .goodIds, "11/05/2026") Quit
	If '..Noticed(ref, 1) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.RequestRefs_"|"_row.CauseCategory, "open|no_fix||data_format_change", "the incident is open with the variant no_fix and lists no request")
	Do $$$AssertEquals(..Requests(ref).%Size(), 0, "no request names it")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of it")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.slots.cause, "incident|incident.noFix||"_row.Cause, "the no-fix notice, with the cause and no request")
	}
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 1, "the dry run was asked")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(..WarningMark, .text, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the incident: "_text)
	If warned {
		Do $$$AssertTrue($Find(text, ref) > 0, "the incident is in the warning")
		Do $$$AssertTrue($Find(text, ..#CHANGED_"1 of the 3 messages from the same source that went through") > 0, "with the reason: the repair would also change 1 of the 3")
	}
	Set response = ..AskDryRun(ref, "repair_resend", ..FixParameters(), trace, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If $IsObject(response) Do $$$AssertEquals($Extract(response.Reason, 1, $Length(..#CHANGED)), ..#CHANGED, "and a dry run asked again is refused with that reason, no targets: "_response.Reason_"|"_response.Targets)
}

/// The parameters of the mock's default diagnosis.
ClassMethod FixParameters() As %String [ Private ]
{
	Quit {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}.%ToJSON()
}

Method TestOtherSourcesAndSessions()
{
	If '..Ready() Quit
	Set b = ..Session("othersb")
	Set traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	Set a = ..Session("othersa")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..SendGood(4, traceA) Quit
	If '..SendGood(3, traceB) Quit
	If '..SendGood(2, "") Quit
	Set goodA = ..WaitGood(traceA, 4)
	Set goodB = ..WaitGood(traceB, 3)
	Set untaggedGood = ..WaitGood("", 2)
	If ($Length(goodA, ",") '= 4) || ($Length(goodB, ",") '= 3) || ($Length(untaggedGood, ",") '= 2) Quit
	If '..Fail(2, traceA) Quit
	If '..Fail(1, traceB) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set failedA = ..SuperIds(failed, traceA)
	Set failedB = ..SuperIds(failed, traceB)
	Do $$$AssertEquals($Length(failedA, ",")_"|"_$Length(failedB, ","), "2|1", "two failed orders of A and one of B")
	Set referenceA = $Piece(failedA, ",", 1)
	Set referenceB = failedB
	Set newestA = ..Reversed(goodA)
	Set newestB = ..Reversed(goodB)
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", referenceA, 20, .good)
	Do $$$AssertEquals(outcome_"|"_..IdsOf(good), "read|"_newestA, "the good orders of A's source, newest first, and none of B's, of the untagged orders, of the failed headers or of the warehouse leg")
	Set other = ..OtherShape(good, traceA)
	Do $$$AssertEquals(other, "", "each is a Completed PartnerOrdersIn to OrdersFromPartner header of A: "_other)
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", referenceA, 2, .good)
	Do $$$AssertEquals(outcome_"|"_..IdsOf(good), "read|"_$Piece(newestA, ",", 1, 2), "at most limit: the 2 newest")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", referenceA_","_referenceB, 20, .good)
	Do $$$AssertEquals(outcome_"|"_..IdsOf(good), "read|"_newestA_","_newestB, "two references of two sources: each one's good orders in turn")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", referenceA_","_$Piece(failedA, ",", 2)_","_referenceA, 20, .good)
	Do $$$AssertEquals(outcome_"|"_..IdsOf(good), "read|"_newestA, "and two references of one source, or one twice, give no header twice")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, "No.Such.Production", "OrdersFromPartner", referenceA, 20, .good)
	Do $$$AssertEquals(outcome_"|"_good.%Size(), "not_current|0", "a production that is not current gives not_current and nothing")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "", 20, .good)
	Do $$$AssertEquals(outcome_"|"_good.%Size(), "read|0", "no reference gives nothing")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", referenceA, 0, .good)
	Do $$$AssertEquals(outcome_"|"_good.%Size(), "read|0", "and so does a limit of 0")
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "999999999", 20, .good)
	Do $$$AssertEquals(outcome_"|"_good.%Size(), "read|0", "and a reference that is no header")
}

Method TestTwoSourcesInOneIncident()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set unique = $Extract("0000000000000000"_$Translate($ZHorolog, ".", ""), *-15, *)
	Set traceA = "zz7s9a"_unique
	Set traceB = "zz7s9b"_unique
	If '..SendGood(4, traceA) Quit
	If '..SendGood(3, traceB) Quit
	Set goodA = ..WaitGood(traceA, 4)
	Set goodB = ..WaitGood(traceB, 3)
	If ($Length(goodA, ",") '= 4) || ($Length(goodB, ",") '= 3) Quit
	If '..Fail(2, traceA) Quit
	If '..Fail(1, traceB) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Set incident = ..Fixture("instance", ids, , , , {"ItemNoun": (..#NOUN), "LastAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set response = ..AskDryRun(incident.Ref, "repair_resend", ..FixParameters(), traceA, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason_"|"_response.Targets, "|"_ids, "the dry run is worked out, with the failed orders of both sources as targets: "_response.Reason)
	If response.DryRun = "" Quit
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.goodCheck.%ToJSON(), "{""checked"":7,""changed"":0}", "the good orders of both sources are checked, 4 and 3")

	// a good order of the second source that the repair would change withholds the fix
	Do $$$AssertStatusOK(..SetOrderDate($Piece(goodB, ",", 2), "11/05/2026"), "a good order of the second source is dated 11/05/2026")
	Set response = ..AskDryRun(incident.Ref, "repair_resend", ..FixParameters(), traceA, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult again")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Targets_"|"_response.DryRun, "|", "the dry run is refused: no targets and no dry run")
	Do $$$AssertEquals($Extract(response.Reason, 1, $Length(..#CHANGED_"1 of the 7")), ..#CHANGED_"1 of the 7", "and the reason says that the repair would also change 1 of the 7: "_response.Reason)
}

/// The ids reversed (the newest first).
ClassMethod Reversed(ids As %String) As %String [ Private ]
{
	Set reversed = ""
	For i = $Length(ids, ","):-1:1 {
		Set reversed = reversed _ $Select(reversed = "": "", 1: ",") _ $Piece(ids, ",", i)
	}
	Quit reversed
}

/// "" when every good header read (as Reader.Good gives them) is Completed, from PartnerOrdersIn to OrdersFromPartner, of the PartnerOrder class and of the SuperSession;
/// else the shape of the first that is not.
ClassMethod OtherShape(good As %DynamicArray, super As %String) As %String [ Private ]
{
	Set wanted = "Completed|PartnerOrdersIn|OrdersFromPartner|OcuTalon.Demo.Orders.PartnerOrder|"_super
	For i = 0:1:good.%Size() - 1 {
		Set one = good.%Get(i)
		Set shape = one.status_"|"_one.sourceConfigName_"|"_one.targetConfigName_"|"_one.bodyClass_"|"_one.superSession
		If shape '= wanted Return shape_" instead of "_wanted
	}
	Quit ""
}

Method TestApprovalRunsTheDryRunOnly()
{
	If '..Press("approval", 5, 3, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Set request = ..OneRequest(ref)
	If '$IsObject(request) Quit
	Do ..AssertStoredKeys(request)
	Set note = ..OneNotice(ref, "incident", "incident.withFixChecked", request.ref)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set traceHeader = row.TraceHeaderId
	Kill row
	Set originals = ..Failed(..OrdersFloor)
	Set ids = ..HeaderIds(originals)
	Set response = ..AskDryRun(ref, request.fixKind, request.fixParameters, trace, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If $IsObject(response) {
		Do $$$AssertEquals(request.fixKind_"|"_request.fixParameters_"|"_request.fixTargets, "repair_resend|"_..FixParameters()_"|"_response.Targets, "the row holds the kind, the parameters and the targets that the dry run gave")
		Do $$$AssertEquals(response.Targets, ids, "and the targets are the three failed orders")
	}
	Set goodBefore = ..GoodState(goodIds)
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the approval is accepted")
	Set run = ..WaitRun(ref, request.ref, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3), "the FixRun holds three copies")
	If '$IsObject(run) || (run.copies.%Size() '= 3) Quit
	Set copies = ..Joined(run.copies)
	Do $$$AssertTrue(..WaitCompleted(..#ORDERS, copies), "the three copies complete")
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", 90), "done", "the request is done")
	Set after = ..Requests(ref).%Get(0)
	Do $$$AssertEquals(after.fixKind_"|"_after.fixParameters_"|"_after.fixTargets, request.fixKind_"|"_request.fixParameters_"|"_request.fixTargets, "the row's kind, parameters and targets are as they were")
	Do $$$AssertEquals(..Originals(run.copies), ids, "the copies are repaired copies of the targets, and of nothing else")
	Do $$$AssertEquals(..GoodState(goodIds), goodBefore, "no good order was changed: its body and status are as they were")
	Do $$$AssertEquals(..ResentCount(..OrdersFloor), 3, "and the production holds three resent copies in all")
	Set results = ..WaitResultNotices(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one result Notification")
	If results.%Size() = 1 Do $$$AssertEquals(results.%Get(0).catalogKey, "result.allThrough", "all three went through")

	// a later round: the three copies and the five good orders are the good messages of the same source
	If '..Fail(2, trace) Quit
	Set all = ..WaitFailed(5)
	If all.%Size() '= 5 Quit
	Set end = $ZHorolog + 60
	For {
		Set notes = ..NoticeBodies(ref, "approval")
		If (notes.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 1, "the later round has one approval Notification")
	If notes.%Size() '= 1 Quit
	Set later = notes.%Get(0)
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 2, "a second request names the incident")
	If requests.%Size() '= 2 Quit
	Set second = requests.%Get(1)
	Do $$$AssertEquals(later.catalogKey_"|"_later.approvalRef, "incident.laterRequestChecked|"_second.ref, "the later notice has the key incident.laterRequestChecked and the second request's Ref")
	Do $$$AssertEquals(later.slots.goodChecked_"|"_later.slots.goodChanged_"|"_later.slots.goodNoun_"|"_later.slots.resendCount, "8|0|orders|2", "it checked 8 good messages: the 5 good orders and the 3 copies")
	Do $$$AssertEquals(second.fixTargets, $Piece(..HeaderIds(all), ",", 4, 5), "over the two later orders alone")
	Do ..AssertStoredKeys(second)
	Set phone = ..PhoneText(a, second.ref)
	Do $$$AssertTrue(phone [ ("unchanged. "_..Line(8, 0)_" Nothing has changed yet."), "and the phone message holds the line with 8 and 0: "_phone)
}

/// The number of headers of OCUORDERS after the floor whose Description starts "Resent " (the repaired copies).
ClassMethod ResentCount(floor As %Integer) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND Description %STARTSWITH 'Resent '", floor)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

Method TestLaterRoundRefused()
{
	Set ..WarningMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	If '..Press("laterrefused", 5, 3, .a, .trace, .ref, .goodIds) Quit
	If '..Noticed(ref, 1) Quit
	Set first = ..OneRequest(ref)
	If '$IsObject(first) Quit
	Do $$$AssertStatusOK(..SetOrderDate($Piece(goodIds, ",", 5), "11/05/2026"), "a good order is dated 11/05/2026 before the later round")
	If '..Fail(2, trace) Quit
	Set all = ..WaitFailed(5)
	If all.%Size() '= 5 Quit
	Set end = $ZHorolog + 60
	For {
		Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(..WarningMark, .text, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGLATER"))
		If warned || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the later round: "_text)
	If warned {
		Do $$$AssertTrue($Find(text, ref) > 0, "the incident is in the warning")
		Do $$$AssertTrue($Find(text, ..#CHANGED_"1 of the 5 messages from the same source that went through") > 0, "with the reason: the repair would also change 1 of the 5 good orders: "_text)
	}
	Hang 3
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "no second request was raised")
	Do $$$AssertEquals(..Notifications(ref), 1, "and nothing was sent for the round")
	Set now = ..Requests(ref).%Get(0)
	Do $$$AssertEquals(now.ref_"|"_now.state_"|"_now.fixTargets_"|"_now.dryRun, first.ref_"|pending|"_first.fixTargets_"|"_first.dryRun, "the first request is untouched")
}

Method TestUntaggedOrders()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set owner = ..Session("untagged")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(owner).TraceRef
	If '..SendGood(2, "") Quit
	Set untagged = ..WaitGood("", 2)
	If '..Fail(2, "") Quit
	Set failed = ..WaitFailed(2)
	If failed.%Size() '= 2 Quit
	Set ids = ..HeaderIds(failed)
	Do $$$AssertEquals(failed.%Get(0).superSession, "", "an untagged order reads back with an empty SuperSession")
	Do $$$AssertEquals($Length(untagged, ","), 2, "and so do the two untagged good orders sent, which the empty-SuperSession read finds: "_untagged)
	Set incident = ..Fixture("instance", ids, , , , {"ItemNoun": (..#NOUN), "LastAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set response = ..AskDryRun(incident.Ref, "repair_resend", ..FixParameters(), trace, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason_"|"_response.Targets, "|"_ids, "the dry run is worked out, with the two untagged failed orders as targets: "_response.Reason)
	If response.DryRun = "" Quit
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertTrue(dryRun.goodCheck.checked '< 2, "the untagged good orders are checked (at least the 2 sent): "_dryRun.goodCheck.%ToJSON())
	Set outcome = ##class(OcuTalon.Watch.Reader).Good(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", $Piece(ids, ",", 1), 20, .good)
	Do $$$AssertEquals(outcome_"|"_$Piece(..IdsOf(good), ",", 1, 2), "read|"_..Reversed(untagged), "the untagged reference reads the test's own two good orders first, newest first")
	Do $$$AssertEquals(..OtherShape(good, ""), "", "and only untagged Completed PartnerOrdersIn to OrdersFromPartner headers: "_..OtherShape(good, ""))
	Do $$$AssertEquals(dryRun.goodCheck.changed, 0, "and none would change")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).WithFixKey(dryRun, ..FixParameters()), "incident.withFixChecked", "so the key is the ...Checked one")
}

}
