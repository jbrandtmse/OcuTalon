Include Ensemble

/// Tests of a date repair whose values could be read either way, over the whole path (Story 7.7, DW-644; U-249 Conditions 1 and 2; Q1 ruled (a)). THEY RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (IncidentManager and FixExecutor are code of the running production), with demo mode on, through Test.Watch.Case:
/// real failed orders of OCUORDERS written MM/DD/YYYY, the CI mock as the model (its default diagnosis, a repair_resend from MM/DD/YYYY to YYYY-MM-DD), the real
/// FixExecutor dry run, the real Approval.Raise and the real notice. The CI stacks run in UTC, so a test sets the arrival of the failed headers (their TimeCreated,
/// UTC) to the value an evening press in the Americas makes; a test waits at most 90 seconds for a diagnosis and 20 for the rest (test bounds, not NFR-7). The
/// incidents, requests, holds and orders of a test are removed after it (Case).
///   - TestDemoRepairWhenInstanceDateIsNotUtcDate (Integration AC; U-249 Condition 2): 3 orders dated 11/03/2026 whose headers arrived at 02:00 UTC on November 4 (the
///     instance-local date of the press is the 3rd, the UTC date the 4th) still get their repair request: one pending repair_resend request over the three ids, and
///     one incident Notification with the key incident.withFixEitherWay, the slots reading "month first" and item "order", and the phone message that SimPhoneOut kept
///     holds the line "All 3 dates are valid whether read month first or day first. Read month first, they match the day each order arrived."; the mock logged only
///     the diagnosis requests;
///   - TestNoEvidenceNoRequest (DW-644): 3 orders dated 03/05/2026 that arrived on November 4 read both ways with nothing to choose between them: the dry run is
///     refused, no request is raised, the incident is open with the variant no_fix and its notice is incident.noFix with the cause, with one Type 3 warning;
///   - TestBothReadingsMatch (Condition 1; Q1): 3 orders dated 11/11/2026 that arrived on November 11 read as one date whichever way: the request is raised with
///     incident.withFix, no reading and no item slot, and no line in the phone message;
///   - TestBothReadingsMatchMixedWithTolerance (U-250, Condition 1): two orders dated 11/11/2026 that arrived on November 11 and one dated 11/03/2026 that arrived at 02:00 UTC on
///     November 4 (it matches month first through the one-day tolerance only): the request is raised with incident.withFixEitherWay, the slots reading "month first", item
///     "order" and resendCount 3, and the phone message holds the line as worded, after the example of the value whose readings differ;
///   - TestLaterRoundKeepsTheLine: after a first request over 3 orders dated 11/03/2026, 2 more such orders fail and arrive on November 4: the later request is raised over
///     the two alone, and its approval Notification has the key incident.laterRequestEitherWay, the slots reading "month first", item "order" and resendCount 2, and
///     the phone message holds "All 2 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.";
///   - TestPressWritesTheLocalDate: the partner writes the date of the process's own zone: under a zone whose date differs from the UTC date, Partner.Orders with
///     an empty date gives the MM/DD/YYYY of the local date, not of the UTC date.
/// The tests that raise a request also read the approval payload that the web card is drawn from (Story 7.8; DW-645): AssertCardFields opens the request's row and asserts that
/// Live.Payload.Approval FromRow gives the dry run eitherWay 1, the notice's reading slot as its reading, the notice's item slot as the item noun's singular and the notice's
/// resendCount slot as resend, and TestBothReadingsMatch that it gives eitherWay 0. The stored dry run keeps its keys.
/// Every test that sets arrivals asserts that the DryRun header it depends on was created after the arrivals were set (LogMargin), so a dry run that read the real
/// arrivals is red on any date.
Class OcuTalon.Test.Fix.EitherWay Extends OcuTalon.Test.Watch.Case
{

/// The line of U-249 for the many form, as the phone message holds it.
Parameter LINE = "All 3 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.";

/// The beginning of the sentence that every line starts with, which a message without the line must not hold.
Parameter LINESTART = "whether read month first or day first";

/// The start of the reason of a refused dry run, as the warning holds it.
Parameter NOEVIDENCE = "The dates read as valid dates both month first and day first";

/// The newest row of the event log before TestNoEvidenceNoRequest made its warning, or "": OnAfterOneTest removes the warning after it.
Property WarningMark As %Integer;

/// The time (UTC, as Ens.MessageHeader stores TimeCreated: YYYY-MM-DD hh:mm:ss.sss) at which the arrival of the failed headers was set.
Property ArrivalSetAt As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..WarningMark '= "" {
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..WarningMark, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
	}
	Set ..WarningMark = ""
	Quit ##super(testname)
}

Method TestDemoRepairWhenInstanceDateIsNotUtcDate()
{
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set mark = $ClassMethod(mock, "LogMark")
	If '..Press("late", "2026-11-03", "2026-11-04T02:00:00Z", .a, .ref, .failed) Quit
	If '..Noticed(ref, 1) Quit
	Do ..LogMargin(ref)
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.state_"|"_request.fixKind, "fix|pending|repair_resend", "it is a pending repair_resend fix")
	Do $$$AssertEquals(request.fixTargets, ..SortedIds(failed), "over the three failed orders, ascending")
	Set dryRun = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut_"|"_dryRun.before_"|"_dryRun.after, "3|3|0|11/03/2026|2026-11-03", "the stored dry run is the three orders, with the first one's change")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of the incident")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.approvalRef, a_"|incident|incident.withFixEitherWay|"_request.ref, "of kind incident, with the either-way key and the request's Ref")
		Set slots = note.slots
		Do $$$AssertEquals(slots.reading_"|"_slots.item_"|"_slots.resendCount_"|"_slots.before_"|"_slots.after, "month first|order|3|11/03/2026|2026-11-03", "its slots: the reading, the noun of one item, the count and the example")
		Do ..AssertCardFields(request, slots)
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "the slots render")
		Do $$$AssertTrue(text [ ("Example: order date 11/03/2026 becomes 2026-11-03. "_..#LINE_" I'll resend 3 repaired copies;"), "the Dry run paragraph holds the line: "_text)
		Set phone = ..PhoneText(a, request.ref)
		Do $$$AssertTrue(phone [ ("Example: order date 11/03/2026 becomes 2026-11-03. "_..#LINE_" I'll resend 3 repaired copies;"), "and so does the phone message that was kept: "_phone)
		Do $$$AssertTrue(phone [ "Nothing has changed yet.", "which still ends with the dry run's last sentence")
	}
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Diagnose).ModelRequests(entries), 2, "the mock logged only the two diagnosis requests: the dry run calls no model")
}

Method TestNoEvidenceNoRequest()
{
	Set ..WarningMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	If '..Press("noevidence", "2026-03-05", "2026-11-04T02:00:00Z", .a, .ref, .failed) Quit
	If '..Noticed(ref, 1) Quit
	Do ..LogMargin(ref)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.RequestRefs_"|"_row.CauseCategory, "open|no_fix||data_format_change", "the incident is open with the variant no_fix and lists no request")
	Do $$$AssertEquals(..Requests(ref).%Size(), 0, "no request names it")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of it")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.slots.cause, "incident|incident.noFix||"_row.Cause, "the no-fix notice, with the cause and no request")
		Do $$$AssertEquals(note.slots.%IsDefined("reading"), 0, "and no reading slot")
	}
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 1, "the dry run was asked")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(..WarningMark, .text, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the incident: "_text)
	If warned {
		Do $$$AssertTrue($Find(text, ref) > 0, "the incident is in the warning")
		Do $$$AssertTrue($Find(text, ..#NOEVIDENCE) > 0, "with the dry run's reason")
	}
}

Method TestBothReadingsMatch()
{
	If '..Press("same", "2026-11-11", "2026-11-11T15:00:00Z", .a, .ref, .failed) Quit
	If '..Noticed(ref, 1) Quit
	Do ..LogMargin(ref)
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.state_"|"_request.fixKind, "fix|pending|repair_resend", "it is a pending repair_resend fix: the two readings are one date, so nothing is chosen")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of the incident")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.slots.%IsDefined("reading")_"|"_note.slots.%IsDefined("item"), "incident.withFix|0|0", "the key is incident.withFix, with no reading and no item slot")
		Set card = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref))
		Do $$$AssertEquals($IsObject(card.DryRun) && (card.DryRun.EitherWay = 0) && (card.DryRun.Reading = ""), 1, "and the approval payload has no either-way flag and no reading")
		Set phone = ..PhoneText(a, request.ref)
		Do $$$AssertTrue(phone [ "Dry run: 3 orders affected. Example: order date 11/11/2026 becomes 2026-11-11. I'll resend 3 repaired copies;", "the phone message holds the dry run without the line: "_phone)
		Do $$$AssertTrue(phone '[ ..#LINESTART, "and nothing of the line")
	}
}

Method TestBothReadingsMatchMixedWithTolerance()
{
	If '..Press("mixed", "2026-11-11", "2026-11-11T15:00:00Z", .a, .ref, .failed, "11/03/2026", "2026-11-04T02:00:00Z") Quit
	If '..Noticed(ref, 1) Quit
	Do ..LogMargin(ref)
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.state_"|"_request.fixKind, "fix|pending|repair_resend", "it is a pending repair_resend fix: the tolerance match is the evidence")
	Do $$$AssertEquals(request.fixTargets, ..SortedIds(failed), "over the three failed orders, ascending")
	Set dryRun = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(dryRun.resend_"|"_dryRun.before_"|"_dryRun.after, "3|11/03/2026|2026-11-03", "the example is the value whose readings differ")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of the incident")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.slots.reading_"|"_note.slots.item_"|"_note.slots.resendCount, "incident.withFixEitherWay|month first|order|3", "the either-way key, with the reading, the noun of one item and the count")
		Do ..AssertCardFields(request, note.slots)
		Set phone = ..PhoneText(a, request.ref)
		Do $$$AssertTrue(phone [ ("Example: order date 11/03/2026 becomes 2026-11-03. "_..#LINE_" I'll resend 3 repaired copies;"), "the phone message holds the line as worded: "_phone)
	}
}

Method TestLaterRoundKeepsTheLine()
{
	If '..Press("laterround", "2026-11-03", "2026-11-04T02:00:00Z", .a, .ref, .failed) Quit
	If '..Noticed(ref, 1) Quit
	Do ..LogMargin(ref)
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident before the later round")
	If requests.%Size() '= 1 Quit
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(2, trace, "2026-11-03") Quit
	Set all = ..WaitFailed(5)
	If all.%Size() '= 5 Quit
	Set ids = ..HeaderIds(all)
	For i = 4:1:5 {
		Do $$$AssertStatusOK(..SetArrival($Piece(ids, ",", i), "2026-11-04T02:00:00Z"), "the arrival of the later order "_$Piece(ids, ",", i)_" is November 4")
	}
	Set ..ArrivalSetAt = $ZDateTime($ZTimeStamp, 3, , 3)
	Set end = $ZHorolog + ..#WAITLATER
	For {
		Set requests = ..Requests(ref)
		If (requests.%Size() '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(requests.%Size(), 2, "a second request names the incident")
	If requests.%Size() '= 2 Quit
	Do ..WaitNotices(ref, 2)
	Do ..LogMargin(ref, 2)
	Set second = requests.%Get(1)
	Do $$$AssertEquals(second.fixTargets, $Piece(ids, ",", 4, 5), "over the two later orders alone")
	Set notes = ..NoticeBodies(ref, "approval")
	Do $$$AssertEquals(notes.%Size(), 1, "S has one approval Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef, "approval|incident.laterRequestEitherWay|"_second.ref, "of kind approval, with the later either-way key and the second request's Ref")
		Set slots = note.slots
		Do $$$AssertEquals(slots.reading_"|"_slots.item_"|"_slots.resendCount, "month first|order|2", "its slots: the reading, the noun of one item and the count of the later round")
		Do ..AssertCardFields(second, slots)
		Set phone = ..PhoneText(a, second.ref)
		Do $$$AssertTrue(phone [ "All 2 dates are valid whether read month first or day first. Read month first, they match the day each order arrived. I'll resend 2 repaired copies;", "the phone message holds the line for the two later orders: "_phone)
	}
}

Method TestPressWritesTheLocalDate()
{
	New $NAMESPACE
	If '..Ready() Quit
	Set $NAMESPACE = ..#ORDERS
	Set saved = $ZTimeZone
	Try {
		// A zone far enough from UTC that its date is the other one: the UTC hour decides the direction.
		Set $ZTimeZone = $Select((($Piece($ZTimeStamp, ",", 2) \ 3600) '< 12): -840, 1: 720)
		Set batch = ##class(OcuTalon.Demo.Orders.Batch).%New()
		Set batch.Count = 1
		Set batch.DateFormat = "MM/DD/YYYY"
		Set sc = ##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders)
		Set local = $ZDate($Horolog, 3)
		Set utc = $ZDate($Piece($ZTimeStamp, ",", 1), 3)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set $ZTimeZone = saved
	Do $$$AssertStatusOK(sc, "the partner builds an order with no date")
	If $$$ISERR(sc) Quit
	Do $$$AssertNotEquals(local, utc, "under the zone the local date is not the UTC date")
	Set written = orders(1).OrderDate
	Do $$$AssertEquals(written, $Piece(local, "-", 2)_"/"_$Piece(local, "-", 3)_"/"_$Piece(local, "-", 1), "the order is dated with the local date, month first")
	Do $$$AssertNotEquals(written, $Piece(utc, "-", 2)_"/"_$Piece(utc, "-", 3)_"/"_$Piece(utc, "-", 1), "not the UTC date")
}

/// The set-up of a test with a press: the production is ready, the mock is pointed to, the approval role is ready, S watches Orders, 3 orders dated orderDate (YYYY-MM-DD,
/// written MM/DD/YYYY) tagged with S's trace Ref fail, the arrival of their headers is set to arrival (UTC, YYYY-MM-DDThh:mm:ssZ) as soon as they are in the error status,
/// and the burst becomes one incident of S. a is S, ref the incident and failed the failed headers. 1 when the set-up is done. Given lastValue (MM/DD/YYYY), the third order's date
/// is set to it and its arrival to lastArrival, before the incident forms (U-250's mixed set).
Method Press(name As %String, orderDate As %String, arrival As %String, Output a As %String, Output ref As %String, Output failed As %DynamicArray, lastValue As %String = "", lastArrival As %String = "") As %Boolean [ Private ]
{
	Set (a, ref, failed) = ""
	If '..Ready() Quit 0
	If '..PointKeys() Quit 0
	If '..ApprovalReady() Quit 0
	Set a = ..Session(name)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	If '..Fail(3, trace, orderDate) Quit 0
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit 0
	For i = 0:1:2 {
		Set when = $Select((i = 2) && (lastValue '= ""): lastArrival, 1: arrival)
		If (i = 2) && (lastValue '= "") Do $$$AssertStatusOK(..SetOrderDate(failed.%Get(i).id, lastValue), "the order of header "_failed.%Get(i).id_" is dated "_lastValue)
		Do $$$AssertStatusOK(..SetArrival(failed.%Get(i).id, when), "the arrival of header "_failed.%Get(i).id_" is "_when)
	}
	Set ..ArrivalSetAt = $ZDateTime($ZTimeStamp, 3, , 3)
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of S")
	If rows.%Size() < 1 Quit 0
	Set ref = rows.%Get(0).ref
	Quit 1
}

/// Asserts that the approval payload of the request (an object with its Ref) has the dry run's either-way fields of the notice that was sent (its slots): eitherWay 1, the
/// reading slot as reading, the item slot as the item noun's singular and the resendCount slot as resend; and that the stored dry run holds no key of the payload's own.
Method AssertCardFields(request As %DynamicObject, slots As %DynamicObject) [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref)
	Do $$$AssertTrue($IsObject(row), "the request's row opens: "_request.ref)
	If '$IsObject(row) Quit
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row)
	Do $$$AssertTrue($IsObject(payload.DryRun), "the approval payload has a dry run")
	If '$IsObject(payload.DryRun) Quit
	Do $$$AssertEquals(payload.DryRun.EitherWay_"|"_payload.DryRun.Reading, "1|"_slots.reading, "the payload carries the flag and the notice's reading")
	Do $$$AssertEquals(payload.DryRun.ItemNoun.One_"|"_payload.DryRun.Resend, slots.item_"|"_slots.resendCount, "and the card's item and count are the notice's item and resendCount slots")
	Set stored = {}.%FromJSON(row.DryRun)
	Do $$$AssertEquals(stored.%IsDefined("eitherWay")_"|"_stored.%IsDefined("reading"), "0|0", "and the stored dry run holds neither")
}

/// Asserts that the nth DryRun header of the incident's trace session (in the order of their ids) exists and was created after ArrivalSetAt, so that the dry run
/// read the arrivals that the test set, and logs the margin in seconds.
Method LogMargin(ref As %String, nth As %Integer = 1) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TimeCreated FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'OcuTalon.Fix.Msg.DryRun' ORDER BY ID", row.TraceHeaderId)
	Set asked = ""
	For i = 1:1:nth {
		If 'rs.%Next() Set asked = "" Quit
		Set asked = rs.%GetData(1)
	}
	Do $$$AssertTrue(asked '= "", "the incident's trace session holds DryRun header "_nth)
	If asked = "" Quit
	If $Length(asked) = 19 Set asked = asked_".000"
	Set seconds = ##class(OcuTalon.Watch.Settle).Seconds($Translate($Extract(asked, 1, 19), " ", "T")_"Z") - ##class(OcuTalon.Watch.Settle).Seconds($Translate($Extract(..ArrivalSetAt, 1, 19), " ", "T")_"Z")
	Do $$$LogMessage("DryRun header "_nth_" was created about "_seconds_" seconds after the arrival was set ("_asked_" against "_..ArrivalSetAt_")")
	Do $$$AssertTrue(asked ] ..ArrivalSetAt, "the arrival was set before the dry run asked ("_asked_" after "_..ArrivalSetAt_"), so the dry run read the arrival that the test set")
}

ClassMethod SortedIds(failed As %DynamicArray) As %String [ Private ]
{
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set ids(failure.id) = ""
	}
	Set text = ""
	Set id = ""
	For {
		Set id = $Order(ids(id))
		Quit:id=""
		Set text = text _ $Select(text = "": "", 1: ",") _ id
	}
	Quit text
}

}
