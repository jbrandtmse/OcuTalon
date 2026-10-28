/// Tests of the dry run of a repair (Story 7.1; AD-3, AD-4, AD-16, AD-22): a Fix.Msg.DryRun sent to the item FixExecutor by name, as IncidentManager will send it,
/// and the diagnosis that the kind checks. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: they need the
/// running OcuTalon.Production and the Orders demo production in OCUORDERS, make real failing orders there and fail with the reason where they do not have them.
/// A test sends the request from the SimMailboxIn service (an adapterless host, in the owner's trace session), waits up to SENDWAIT seconds for the answer, and
/// removes the headers of the request's session in the end; the orders and the incident rows are removed by Case.
///   - TestFiftyOrdersChangeNothing (AC 3, AC 4): 50 failed orders of one session, with a snapshot (Test.Fix.Snapshot) of OCUTALON and OCUORDERS before and after: the
///     snapshot before holds the 50 orders with their bodies, the Orders production and its queues; the targets are the 50 header ids, ascending; the dry run has exactly the
///     keys of DRYRUNKEYS and the values of the matrix's row; nothing in either namespace changed but the request's own session, the incident's row and its group's
///     rows are unchanged, FixExecutor wrote no event-log row in the request's session; and the mock logged no request;
///   - TestLeftOutAndScope: of six failed orders of the scope, two do not read in the source format and are left out; a failed order of another scope and a header that
///     was delivered are not counted; the example is the lowest target;
///   - TestTargetsAscendAcrossGroups: the keys of the incident's groups are descending and overlap, and one order is only in the second group: every group is read,
///     the targets are still ascending, and an order of two groups is counted once;
///   - TestAskedWindow (Story 7.6; AC 1): 5 failed orders in one group's Seen with the marks of an ask: a window from the 2nd key to the 4th holds the 3rd and 4th
///     orders only (2 affected); an empty from mark and the 2nd as the to mark hold the first two; a from mark equal to the to mark holds none, and the dry run is
///     refused with the reason that the incident has no failed message of its scope;
///   - TestNothingReadable: in-scope failed orders, none of which reads in the source format: the dry run is worked out, with no target;
///   - TestRefusals: an unknown or closed incident, an unknown kind, parameters that are not a JSON object or that the kind refuses, a production that cannot be read
///     or is not current, and no failed message of the scope are each answered OK with no targets and no dry run, and a plain Reason that says why (never the
///     internal-error sentence);
///   - TestReasonIsRedactedAndBounded (QA): the Reason of a refusal that quotes the model's field holds no key (it is redacted) and is cut at 1000 characters;
///   - TestItemNounFallback (QA): an incident noun that is no JSON, no object, or lacks a form is not used; the noun of the orders' body class is;
///   - TestMissingBodyIsLeftOut (QA): a failed message whose body can no longer be read, the lowest one included, is counted as affected and left out, never as a
///     target and never dropped;
///   - TestOtherRequest: a request that is not a DryRun gets error 5003 from FixExecutor;
///   - TestServiceUserMayResend (AC 1): the service user may use %Ens_MessageResend and not %Ens_MessageEditResend;
///   - TestInvalidRepairTakesTheFallbackRoute (AC 2): a repair that the kind refuses ends in Epic 5's fallback notice of reason invalid; a valid one is stored and its dry run is asked (Story 7.2).
Class OcuTalon.Test.Fix.DryRun Extends OcuTalon.Test.Watch.Case
{

Parameter EXECUTOR = "FixExecutor";

Parameter SENDER = "SimMailboxIn";

Parameter SENDWAIT = 60;

Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

Parameter OTHERNOUN = "{""one"":""purchase order"",""other"":""purchase orders""}";

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The sessions of the requests that the test sent, comma-separated, for the clean-up.
Property DrySessions As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	For i = 1:1:$Length(..DrySessions, ",") {
		If $Piece(..DrySessions, ",", i) '= "" Do ..DropSession($Piece(..DrySessions, ",", i))
	}
	Set ..DrySessions = ""
	Quit sc
}

/// Removes the headers and the bodies of a session of the home namespace, and its log rows.
ClassMethod DropSession(session As %String) [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", session)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = $ListBuild(rs.%GetData(2), rs.%GetData(3))
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
}

/// The parameters of a repair as JSON text.
ClassMethod Params(field As %String = "OrderDate", source As %String = "MM/DD/YYYY", target As %String = "YYYY-MM-DD") As %String [ Private ]
{
	Quit {"field": (field), "sourceFormat": (source), "targetFormat": (target)}.%ToJSON()
}

/// Sends a Fix.Msg.DryRun from the SimMailboxIn service, in the trace session of the super session, to the item FixExecutor by name, and waits for the answer.
/// The answer (a DryRunResult, or "") is given back; the session of the request is kept for the clean-up and given in session.
Method Ask(incidentRef As %String, kind As %String, parameters As %String, super As %String, Output session As %Integer, Output sc As %Status) As OcuTalon.Fix.Msg.DryRunResult [ Private ]
{
	Set session = ""
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	If $$$ISERR(sc) Quit ""
	Set service.%SuperSession = super
	Set request = ##class(OcuTalon.Fix.Msg.DryRun).%New()
	Set request.IncidentRef = incidentRef
	Set request.FixKind = kind
	Set request.Parameters = parameters
	Set sc = service.SendRequestSync(..#EXECUTOR, request, .response, ..#SENDWAIT)
	Set session = service.%SessionId
	Set ..DrySessions = ..DrySessions _ $Select(..DrySessions = "": "", 1: ",") _ session
	Quit $Select($$$ISOK(sc) && $IsObject($Get(response)): response, 1: "")
}

/// The incident's row and its groups' rows as text (every column), to compare before and after.
ClassMethod RowsOf(ref As %String) As %String [ Private ]
{
	Set text = ""
	For sql = "SELECT * FROM OcuTalon_Data.Incident WHERE Ref = ?", "SELECT * FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ? ORDER BY ID" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, ref)
		While rs.%Next() {
			For i = 1:1:rs.%ResultColumnCount Set text = text _ rs.%GetData(i) _ $Char(31)
			Set text = text _ $Char(30)
		}
	}
	Quit text
}

/// The trace reference of the session.
ClassMethod TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// The names of the comma-separated list, sorted, comma-separated (the same order as SortedKeys).
ClassMethod SortedNames(names As %String) As %String [ Private ]
{
	For i = 1:1:$Length(names, ",") {
		Set keys($Piece(names, ",", i)) = ""
	}
	Set text = ""
	Set key = ""
	For {
		Set key = $Order(keys(key))
		Quit:key=""
		Set text = text _ $Select(text = "": "", 1: ",") _ key
	}
	Quit text
}

/// Sets the OrderDate of the order that the header holds, in OCUORDERS. The test edits only the orders it made.
ClassMethod SetOrderDate(headerId As %Integer, value As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_headerId)
	Set order = ##class(OcuTalon.Demo.Orders.PartnerOrder).%OpenId(header.MessageBodyId)
	If '$IsObject(order) Quit $SYSTEM.Status.Error(5001, "No order for header "_headerId)
	Set order.OrderDate = value
	Quit order.%Save()
}

/// The ids of the failed headers whose super session is the given one, in order, as a comma-separated list.
ClassMethod IdsOf(failed As %DynamicArray, super As %String) As %String [ Private ]
{
	Set ids = ""
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		If failure.superSession = super Set ids = ids _ $Select(ids = "": "", 1: ",") _ failure.id
	}
	Quit ids
}

Method TestFiftyOrdersChangeNothing()
{
	If '..Ready() Quit
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ?", ..#ORDERS)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "no BackgroundCheck row watches Orders, so no poller or check writes there")
	Set owner = ..Session("fifty")
	Set super = ..TraceOf(owner)
	If '..Fail(50, super) Quit
	Set failed = ..WaitFailed(50)
	If failed.%Size() < 50 Quit
	Set ids = ..HeaderIds(failed)
	// LastAt is now, so that a heartbeat's quiet sweep (QUIETSECONDS) does not close the incident while its row is compared.
	Set incident = ..Fixture(owner, ids, , , , {"ItemNoun": (..#NOUN), "LastAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Do $$$AssertTrue(##class(%File).Exists($Parameter(..#MOCK, "LOGFILE")), "the mock's request log exists")
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set started = $ZHorolog
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ..#ORDERS), .before)
	Do $$$LogMessage("Snapshot.Take took "_$Justify($ZHorolog - started, 0, 2)_" seconds")
	Set orders = before.%Get(..#ORDERS)
	Set held = 0
	For i = 1:1:$Length(ids, ",") {
		If $IsObject(orders) && ($Piece(orders.headers.%Get($Piece(ids, ",", i)), $Char(30), 2) [ ("OrderDate=10/16/2026"_$Char(31))) Set held = held + 1
	}
	Do $$$AssertEquals(held, 50, "the snapshot before holds the 50 failed orders with their bodies")
	Do $$$AssertTrue($IsObject(orders) && (orders.productions.%Get(..#ORDERSPRODUCTION) [ "<Item ") && (orders.queues.%Size() > 0), "and the Orders production's definition with its items, and its queues")
	Set rows = ..RowsOf(incident.Ref)
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take($ListBuild($Namespace, ..#ORDERS), .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after, session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session).%Size(), 2, "the request's session holds the request and its answer, and nothing else")
	Do $$$AssertEquals(lines.%Size(), 0, "nothing in OCUTALON or OCUORDERS changed but the request's own session: "_lines.%ToJSON())
	Do $$$AssertTrue($Length(rows, $Char(30)) = 3, "the incident and its one group are read")
	Do $$$AssertEquals(..RowsOf(incident.Ref), rows, "and the incident's row and its group's rows are unchanged")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE SessionId = ?", session)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "FixExecutor wrote no event-log row in the request's session")
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", mark, .entries), "the mock's request log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "the mock logged no request")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.IncidentRef_"|"_response.Reason, incident.Ref_"|", "the answer is for the incident and holds no reason")
	Do $$$AssertEquals(response.Targets, ids, "Targets holds the 50 header ids, ascending")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(..SortedKeys(dryRun), ..SortedNames($Parameter("OcuTalon.Bridge.Data.ApprovalRequest", "DRYRUNKEYS")), "the dry run has exactly the keys of DRYRUNKEYS")
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "50|50|0", "50 affected, 50 resent, none left out")
	Do $$$AssertEquals(dryRun.field_"|"_dryRun.before_"|"_dryRun.after, "order date|10/16/2026|2026-10-16", "the field in words, and the first target's value before and after")
	Do $$$AssertEquals(dryRun.itemNoun.%ToJSON(), ..#NOUN, "and the noun of the incident")
	Do $$$AssertEquals(dryRun.%GetTypeOf("affected")_"|"_dryRun.%GetTypeOf("field"), "number|string", "the counts are numbers")
}

Method TestLeftOutAndScope()
{
	If '..Ready() Quit
	Set owner = ..Session("scope")
	Set super = ..TraceOf(owner)
	If '..Fail(6, super) Quit
	If '..Fail(1, "") Quit
	Set failed = ..WaitFailed(7)
	If failed.%Size() < 7 Quit
	Set scoped = ..IdsOf(failed, super)
	Set other = ..IdsOf(failed, "")
	Do $$$AssertEquals($Length(scoped, ",")_"|"_$Length(other, ","), "6|1", "six failed orders are of the owner's scope, one of the instance's")
	Set delivered = ..LateHeader(super)
	Set first = $Piece(scoped, ",", 1)
	Set second = $Piece(scoped, ",", 2)
	Set fourth = $Piece(scoped, ",", 4)
	Do $$$AssertStatusOK(..SetOrderDate(first, "2026/10/16"), "the first order's date is in another format")
	Do $$$AssertStatusOK(..SetOrderDate(second, "01/02/2027"), "the second order's date is another date, in the source format")
	Do $$$AssertStatusOK(..SetOrderDate(fourth, ""), "the fourth order has no date")
	Set incident = ..Fixture(owner, scoped_","_other_","_delivered)
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason, "", "the dry run is worked out")
	Set expected = $Piece(scoped, ",", 2) _ "," _ $Piece(scoped, ",", 3) _ "," _ $Piece(scoped, ",", 5) _ "," _ $Piece(scoped, ",", 6)
	Do $$$AssertEquals(response.Targets, expected, "the targets are the orders of the scope that read, ascending")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "6|4|2", "six affected, four resent, two left out; the order of another scope and the delivered header are not counted")
	Do $$$AssertEquals(dryRun.before_"|"_dryRun.after, "01/02/2027|2027-01-02", "the example is the lowest target, not the lowest order")
	Do $$$AssertEquals(dryRun.itemNoun.%ToJSON(), ..#NOUN, "the noun is that of the orders' body class when the incident has none")
}

Method TestTargetsAscendAcrossGroups()
{
	If '..Ready() Quit
	Set owner = ..Session("groups")
	Set super = ..TraceOf(owner)
	If '..Fail(4, super) Quit
	Set failed = ..WaitFailed(4)
	If failed.%Size() < 4 Quit
	Set ids = ..HeaderIds(failed)
	Set incident = ..Fixture(owner, $Piece(ids, ",", 4)_","_$Piece(ids, ",", 3)_","_$Piece(ids, ",", 2))
	Set second = ##class(OcuTalon.Data.FailureGroup).%New()
	Set second.IncidentRef = incident.Ref
	Set second.Seq = 2
	Set second.ItemName = "OrdersFromPartner"
	Set second.ErrorPattern = "zzSecondGroup"
	Set second.Seen = "h"_$Piece(ids, ",", 2)_",h"_$Piece(ids, ",", 1)
	Do $$$AssertStatusOK(second.%Save(), "a second group of the incident holds one order of the first group and the lowest order, which only it holds")
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Targets, ids, "every group is read, the targets are ascending though the groups hold them descending, and each is listed once")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "4|4|0", "an order of two groups is counted once")
}

Method TestAskedWindow()
{
	If '..Ready() Quit
	Set owner = ..Session("window")
	Set super = ..TraceOf(owner)
	If '..Fail(5, super) Quit
	Set failed = ..WaitFailed(5)
	If failed.%Size() < 5 Quit
	Set ids = ..HeaderIds(failed)
	Set incident = ..Fixture(owner, ids)
	Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref).GetAt(1)
	Set group.AskedFrom = "h"_$Piece(ids, ",", 2)
	Set group.AskedTo = "h"_$Piece(ids, ",", 4)
	Do $$$AssertStatusOK(group.%Save(), "the group's window runs from the 2nd key to the 4th")
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason_"|"_response.Targets, "|"_$Piece(ids, ",", 3)_","_$Piece(ids, ",", 4), "the targets are the 3rd and 4th orders only")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "2|2|0", "two affected, two resent")
	Set group.AskedFrom = ""
	Set group.AskedTo = "h"_$Piece(ids, ",", 2)
	Do $$$AssertStatusOK(group.%Save(), "the first ask has no from mark and ends at the 2nd key")
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If $IsObject(response) Do $$$AssertEquals(response.Targets, $Piece(ids, ",", 1)_","_$Piece(ids, ",", 2), "the targets are the first two orders")
	Set group.AskedFrom = "h"_$Piece(ids, ",", 3)
	Set group.AskedTo = "h"_$Piece(ids, ",", 3)
	Do $$$AssertStatusOK(group.%Save(), "a window whose marks are one key is empty")
	Do ..AssertRefused(incident.Ref, "repair_resend", ..Params(), super, "an empty window", "has no failed message of its scope")
}

Method TestNothingReadable()
{
	If '..Ready() Quit
	Set owner = ..Session("unreadable")
	Set super = ..TraceOf(owner)
	If '..Fail(3, super) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() < 3 Quit
	Set ids = ..HeaderIds(failed)
	For i = 1:1:3 Do $$$AssertStatusOK(..SetOrderDate($Piece(ids, ",", i), "2026/10/1"_i), "order "_i_" has another format")
	Set incident = ..Fixture(owner, ids, , , , {"ItemNoun": (..#OTHERNOUN)})
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason, "", "the dry run is worked out")
	Do $$$AssertEquals({}.%FromJSON(response.DryRun).itemNoun.%ToJSON(), ..#OTHERNOUN, "the noun is the incident's own when it has one, not that of the orders' body class")
	Do $$$AssertEquals(response.Targets, "", "with no target")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut_"|"_dryRun.before_"|"_dryRun.after, "3|0|3||", "three affected, none resent, three left out, and no example")
	Do $$$AssertEquals(dryRun.field, "order date", "and the field is named")
}

Method TestRefusals()
{
	If '..Ready() Quit
	Set owner = ..Session("refused")
	Set super = ..TraceOf(owner)
	If '..Fail(2, super) Quit
	If '..Fail(1, "") Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() < 3 Quit
	Set scoped = ..IdsOf(failed, super)
	Set other = ..IdsOf(failed, "")
	Set incident = ..Fixture(owner, scoped)
	Set ref = incident.Ref
	Do ..AssertRefused(ref, "repair_resend", ..Params("ShipDate"), super, "a field that the failed messages do not have", "is not a field of the sample message")
	Do ..AssertRefused(ref, "repair_resend", ..Params("OrderDate", "MM-DD-YY"), super, "a format that is not registered", "is not a registered format")
	Do ..AssertRefused(ref, "repair_resend", ..Params("OrderDate", "MM/DD/YYYY", "1234.56"), super, "formats of two families", "are not of one family")
	Do ..AssertRefused(ref, "repair_resend", {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD", "rounding": "2"}.%ToJSON(), super, "an extra parameter", "The parameter 'rounding' is not one of")
	Do ..AssertRefused(ref, "rollback", ..Params(), super, "a fix kind that does not exist", "The fix kind 'rollback' is not one of")
	Do ..AssertRefused(ref, "", ..Params(), super, "no fix kind", "The fix kind '' is not one of")
	Do ..AssertRefused(ref, "repair_resend", "[1,2]", super, "parameters that are an array", "are not one JSON object")
	Do ..AssertRefused(ref, "repair_resend", "not json", super, "parameters that are no JSON", "are not one JSON object")
	Do ..AssertRefused(ref, "repair_resend", "", super, "no parameters", "are not one JSON object")
	Do ..AssertRefused("zznosuchincident", "repair_resend", ..Params(), super, "an incident that does not exist", "There is no incident zznosuchincident")
	Set closed = ..Fixture(owner, scoped)
	Set closed.State = "closed"
	Do $$$AssertStatusOK(closed.%Save(), "an incident is closed")
	Do ..AssertRefused(closed.Ref, "repair_resend", ..Params(), super, "a closed incident", "is closed")
	Set nowhere = ..Fixture(owner, scoped, "ZZNONE")
	Do ..AssertRefused(nowhere.Ref, "repair_resend", ..Params(), super, "a namespace that the service user cannot read", "could not be read")
	Set foreign = ..Fixture(owner, scoped, , "Zz.Other")
	Do ..AssertRefused(foreign.Ref, "repair_resend", ..Params(), super, "a production that is not the namespace's own", "could not be read")
	Set instance = ..Fixture(owner, other)
	Do ..AssertRefused(instance.Ref, "repair_resend", ..Params(), super, "no failed message of the owner's scope", "has no failed message of its scope")
	Set delivered = ..Fixture(owner, ..LateHeader(super))
	Do ..AssertRefused(delivered.Ref, "repair_resend", ..Params(), super, "no failed message at all", "has no failed message of its scope")
	Set logs = ..Fixture(owner, "1", , , "l")
	Do ..AssertRefused(logs.Ref, "repair_resend", ..Params(), super, "a group that holds only event-log keys", "has no failed message of its scope")
}

/// Sends the DryRun and asserts that FixExecutor answers OK with no targets and no dry run, and a plain Reason that holds the phrase (the guard's own sentence,
/// never the internal-error sentence).
Method AssertRefused(ref As %String, kind As %String, parameters As %String, super As %String, label As %String, phrase As %String) [ Private ]
{
	Set response = ..Ask(ref, kind, parameters, super, .session, .sc)
	Do $$$AssertStatusOK(sc, label_": FixExecutor answers OK")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, label_": there is an answer")
		Quit
	}
	Do $$$AssertTrue((response.Reason [ phrase) && (response.Reason '[ "internal error"), label_": the Reason says why ("_phrase_"): "_response.Reason)
	Do $$$AssertTrue($Length(response.Reason) '> 1000 && (response.Reason '[ "ERROR #"), label_": as one plain sentence: "_response.Reason)
	Do $$$AssertEquals(response.Targets_"|"_response.DryRun, "|", label_": with no targets and no dry run")
	Do $$$AssertEquals(response.IncidentRef, ref, label_": for the incident that was asked about")
}

/// Deletes the body of the order that the header holds, in OCUORDERS (the header stays). The test removes only the orders it made.
ClassMethod DeleteOrderBody(headerId As %Integer) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_headerId)
	Quit ##class(OcuTalon.Demo.Orders.PartnerOrder).%DeleteId(header.MessageBodyId)
}

Method TestReasonIsRedactedAndBounded()
{
	If '..Ready() Quit
	Set owner = ..Session("reason")
	Set super = ..TraceOf(owner)
	Set id = ..SampleOrder(super)
	If id = "" Quit
	Set incident = ..Fixture(owner, id)
	// Built from parts, so that no key-shaped literal is committed (the boundaries check).
	Set key = "sk"_"-ant-"_"api03-ZQXJVKWBNMLPDRTYUHGF"
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(key), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertTrue(response.Reason [ "is not a field of the sample message", "a field that the orders do not have is refused: "_response.Reason)
	Do $$$AssertTrue(response.Reason [ "[redacted]", "and the key-shaped field in the sentence is redacted: "_response.Reason)
	Do $$$AssertTrue(response.Reason '[ "ZQXJVKWBNMLPDRTYUHGF", "so the sentence holds no part of the key")
	Set long = $Translate($Justify("", 3000), " ", "a")
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(long), super, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult for a field of 3000 characters")
	If '$IsObject(response) Quit
	Do $$$AssertTrue(($Length(response.Reason) > 0) && ($Length(response.Reason) '> 1000), "and its Reason is cut at 1000 characters: "_$Length(response.Reason))
	Do $$$AssertEquals(response.Targets_"|"_response.DryRun, "|", "with no targets and no dry run")
}

Method TestItemNounFallback()
{
	If '..Ready() Quit
	Set owner = ..Session("noun")
	Set super = ..TraceOf(owner)
	Set id = ..SampleOrder(super)
	If id = "" Quit
	Set incident = ..Fixture(owner, id)
	For noun = "[1,2]", "not json", "{""one"":""order""}", "{""one"":"""",""other"":""x""}", "{""one"":""x"",""other"":""""}", "{}", """text""" {
		Set incident.ItemNoun = noun
		Do $$$AssertStatusOK(incident.%Save(), "the incident holds the noun "_noun)
		Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
		Do $$$AssertTrue($IsObject(response), noun_": FixExecutor gives a DryRunResult")
		If '$IsObject(response) Continue
		Do $$$AssertEquals(response.Reason, "", noun_": the dry run is worked out")
		Set dryRun = $Select(response.DryRun '= "": {}.%FromJSON(response.DryRun), 1: {})
		Do $$$AssertEquals(dryRun.itemNoun.%ToJSON(), ..#NOUN, noun_": is not used; the noun of the orders' body class is")
	}
	Set incident.ItemNoun = ..#OTHERNOUN
	Do $$$AssertStatusOK(incident.%Save(), "the incident holds a noun of its own")
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals({}.%FromJSON(response.DryRun).itemNoun.%ToJSON(), ..#OTHERNOUN, "and that noun is used")
}

Method TestMissingBodyIsLeftOut()
{
	If '..Ready() Quit
	Set owner = ..Session("nobody")
	Set super = ..TraceOf(owner)
	Set first = ..SampleOrder(super)
	Set second = ..SampleOrder(super)
	Set third = ..SampleOrder(super)
	Set fourth = ..SampleOrder(super)
	If (first = "") || (second = "") || (third = "") || (fourth = "") Quit
	Do $$$AssertStatusOK(..DeleteOrderBody(first), "the first order's body is gone")
	Do $$$AssertStatusOK(..SetOrderDate(third, "2026/10/16"), "the third order's date is in another format")
	Do $$$AssertStatusOK(..DeleteOrderBody(fourth), "the fourth order's body is gone")
	Set incident = ..Fixture(owner, first_","_second_","_third_","_fourth)
	Set response = ..Ask(incident.Ref, "repair_resend", ..Params(), super, .session, .sc)
	Do $$$AssertStatusOK(sc, "FixExecutor answers the DryRun")
	Do $$$AssertTrue($IsObject(response), "FixExecutor gives a DryRunResult")
	If '$IsObject(response) Quit
	Do $$$AssertEquals(response.Reason, "", "the dry run is worked out")
	Do $$$AssertEquals(response.Targets, second, "only the order that reads is a target")
	Set dryRun = {}.%FromJSON(response.DryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "4|1|3", "four failed messages are affected: the two with no body, the lowest included, and the one in another format are left out, not dropped")
	Do $$$AssertEquals(dryRun.before_"|"_dryRun.after, "10/16/2026|2026-10-16", "the example is the order that reads")
}

Method TestOtherRequest()
{
	If '..Ready() Quit
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	Do $$$AssertStatusOK(sc, "the sender service is made")
	If $$$ISERR(sc) Quit
	Set sc = service.SendRequestSync(..#EXECUTOR, ##class(Ens.StringRequest).%New("x"), .response, ..#SENDWAIT)
	Set ..DrySessions = ..DrySessions _ $Select(..DrySessions = "": "", 1: ",") _ service.%SessionId
	Do $$$AssertStatusNotOK(sc, "FixExecutor refuses a request that is not a DryRun")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "with error 5003")
	Do $$$AssertTrue('$IsObject($Get(response)), "and gives no response")
}

Method TestServiceUserMayResend()
{
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	Do $$$AssertStatusOK(sc, "the service user is known")
	Do $$$AssertEquals(+$SYSTEM.Security.CheckUserPermission(user, "%Ens_MessageResend", "U"), 1, user_" may use %Ens_MessageResend")
	Do $$$AssertEquals(+$SYSTEM.Security.CheckUserPermission(user, "%Ens_MessageResend", "W"), 0, "but may not write it")
	Do $$$AssertEquals(+$SYSTEM.Security.CheckUserPermission(user, "%Ens_MessageEditResend", "U"), 0, "and may not use %Ens_MessageEditResend")
	Do $$$AssertTrue(","_..RoleResources()_"," [ ",%Ens_MessageResend:U,", "the service role holds %Ens_MessageResend:U: "_..RoleResources())
}

Method TestInvalidRepairTakesTheFallbackRoute()
{
	If '..Ready() Quit
	Set owner = ..Session("fallback")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set bad = ..Fixture(owner, "1,2,3", , , , {"ItemNoun": (..#NOUN)})
	Set good = ..Fixture(owner, "1,2,3", , , , {"ItemNoun": (..#NOUN)})
	Do ..Summarize(bad)
	Do ..Summarize(good)
	Set ..ItemIds = ..ItemIds _ $ListBuild(bad.Ref, good.Ref)
	Set input = ##class(OcuTalon.Watch.EvidencePack).Input({"format": "ocutalon.evidencePack/1", "sample": {"headerId": 1, "bodyClass": "OcuTalon.Demo.Orders.PartnerOrder", "body": {"OrderNumber": "A-1", "OrderDate": "10/16/2026", "Sku": "S", "Quantity": "1"}}})
	Set reply = {"outcome": "act", "causeCategory": "data_format_change", "elementAtFault": "OrderDate", "evidence": ["h1"], "fixKind": "repair_resend", "fixParameters": {"field": "OrderDate", "sourceFormat": "MM-DD-YY", "targetFormat": "YYYY-MM-DD"}, "cause": "The order date is in another format.", "fixSummary": "rewrite the order date and send the orders again", "itemNoun": {"one": "order", "other": "orders"}, "reasons": ["The sample holds 10/16/2026."], "confidence": 0.9}
	Set response = ..Decide(bad.Ref, owner, input, reply)
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Payload, 1: "none"), "1|invalid|", "Decide answers a repair with a bad format with the fallback invalid and no payload")
	Do $$$AssertStatusOK(host.Answer(bad.Ref, response), "IncidentManager handles the answer")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(bad.Ref)
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Cause_row.CauseCategory_row.Element_row.FixSummary, "1|invalid|", "the incident stores the fallback invalid and no cause or fix")
	Kill row
	Do $$$AssertEquals(host.Sent.%Size(), 1, "one notice is sent")
	If host.Sent.%Size() = 1 {
		Set note = host.Sent.%Get(0)
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(note.sessionRef_"|"_note.catalogKey_"|"_note.incidentRef_"|"_slots.fallbackReason, owner_"|incident.fallback|"_bad.Ref_"|invalid", "Epic 5's fallback notice of the incident, with the reason invalid")
	}
	Set reply.fixParameters.sourceFormat = "MM/DD/YYYY"
	Set response = ..Decide(good.Ref, owner, input, reply)
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback, 1: "none"), 0, "Decide answers a valid repair with a diagnosis")
	Do $$$AssertStatusOK(host.Answer(good.Ref, response), "IncidentManager handles that answer")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(good.Ref)
	Do $$$AssertEquals(row.Fallback_"|"_row.CauseCategory_"|"_row.Element, "0|data_format_change|OrderDate", "the diagnosis is stored")
	Kill row
	Do $$$AssertEquals(host.Sent.%Size(), 1, "and it sends no notice yet: its notice waits for the dry run")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "one dry run is asked, for the valid repair only")
	If $IsObject(host.DryRuns) && (host.DryRuns.%Size() = 1) {
		Set ask = host.DryRuns.%Get(0)
		Set parameters = {}.%FromJSON(ask.parameters)
		Do $$$AssertEquals(ask.incidentRef_"|"_ask.fixKind_"|"_parameters.field_"|"_parameters.sourceFormat_"|"_parameters.targetFormat, good.Ref_"|repair_resend|OrderDate|MM/DD/YYYY|YYYY-MM-DD", "the ask names the incident, repair_resend and the parameters")
	}
}

/// Gives the incident's group what a notice reads from it: the error summary and the counts and times of the incident.
Method Summarize(incident As OcuTalon.Data.Incident) [ Private ]
{
	Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref).GetAt(1)
	Set group.ErrorSummary = "The order date was not in the expected format."
	Set group.Count = incident.Count
	Set group.NoticeCount = incident.NoticeCount
	Set group.FirstAt = incident.FirstAt
	Set group.LastAt = incident.LastAt
	Do $$$AssertStatusOK(group.%Save(), "the group of "_incident.Ref_" holds an error summary and its counts")
}

/// Decide.Conclude for a diagnose request of the incident over the input, with the DiagnosisPayload class and the do-nothing filter and sink; the DecisionResponse.
Method Decide(ref As %String, owner As %String, input As %String, reply As %DynamicObject) As OcuTalon.Bridge.Msg.DecisionResponse [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "diagnose"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ref
	Set request.OwnerRef = owner
	Set request.Summary = "Test "_ref
	Set request.Input = input
	Set text = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set text.Text = reply.%ToJSON()
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), text, "OcuTalon.Watch.Msg.DiagnosisPayload", "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "Decide concludes the reply")
	Quit $Get(response)
}

}
