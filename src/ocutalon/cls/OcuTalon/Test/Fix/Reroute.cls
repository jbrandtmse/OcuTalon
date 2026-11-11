/// Tests of the fix kind reroute (Story 23.2; AD-3, AD-16, AD-24). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (FixExecutor is code of the running production), with
/// demo mode on, through Test.Watch.Case: real failed orders of OCUORDERS (3 of the session's, tagged with its trace Ref), the real FixExecutor for the dry run and the run, and the
/// Orders item OrdersForReview, which takes a PartnerOrder and answers OK. The incidents, requests, runs and every message the tests make in OCUORDERS (the copies included) are removed
/// after each test, and an item a test disabled is enabled again.
///   - TestValidation (AC1): the dry run refuses a target that is not an item, a business service, a disabled item and the item the messages failed at, with the ruled reasons, and a
///     blank target; it gives no target for those and changes nothing;
///   - TestDryRunAndRun (AC1, AC4, AC8): three failed orders: the dry run gives their ids, {affected 3, resend 3, leftOut 0, itemNoun, from OrdersFromPartner, to OrdersForReview,
///     example the first id} and changes nothing in OCUORDERS; the approved request is carried out by FixExecutor: three copies to OrdersForReview, each registered on the run and
///     completed there, the originals still in the status Error, the FixResult 3/3/3/0/0, the request done, the incident resolved and the session's notice result.rerouted;
///   - TestFailedAgainIsNotRetried (AC4, the matrix row "Rerouted copy fails"): a request whose target is the item the orders failed at (the executor reads the row only): the copies fail
///     again at OrdersFromPartner, the FixResult counts them failed again with the error's first sentence as the reason, the run is not retried (one FixRun, no further Execute), and FixRun CopyOf names the request for each copy, so that
///     IncidentManager takes their failures for no new failure;
///   - TestTargetDisabledAfterDryRun (AC4, AC8): the target item disabled after the dry run: the re-check skips every target with the reason that it is no longer enabled, and the run sends no copy;
///   - TestRowNamingAnotherSessionsMessage (AC-S2): a request row that names a failed message of another session's trace: the re-check skips it with the scope reason, and the run resends nothing;
///   - TestResentAreLeftOut: after a reroute, a second dry run finds nothing to reroute, because the originals are named as resent;
///   - TestOtherSessionsMessages (AC-S2): the failed orders of another session, though the incident's group lists their keys, are not targets: the dry run holds the session's own only.
Class OcuTalon.Test.Fix.Reroute Extends OcuTalon.Test.Watch.Case
{

/// The Orders item that takes the rerouted orders.
Parameter TARGET = "OrdersForReview";

/// The longest the end of a run is waited for, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 90;

Method TestValidation()
{
	If '..Ready() Quit
	Set a = ..Session("rvalid")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set incident = ..Fixture(a, ..HeaderIds(failed))
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set cases = $ListBuild(
		$ListBuild("NoSuchItem", "NoSuchItem is not an item of Orders"),
		$ListBuild("PartnerOrdersIn", "PartnerOrdersIn is a business service, which can't take rerouted messages"),
		$ListBuild("OrdersFromPartner", "The failed messages were already sent to OrdersFromPartner"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": ($List(case, 1))}, .targets, .dryRun)
		Do $$$AssertStatusNotOK(sc, $List(case, 1)_" is refused")
		Do $$$AssertEquals(..Text(sc), $List(case, 2), "with the ruled reason")
		Do $$$AssertEquals(targets_"|"_dryRun, "|", "and no target and no dry run")
	}
	Do $$$AssertStatusOK(..SetItemEnabled(0, ..#TARGET), ..#TARGET_" is disabled")
	Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": (..#TARGET)}, .targets, .dryRun)
	Do $$$AssertEquals(..Text(sc), ..#TARGET_" is disabled", "a disabled target is refused")
	Do $$$AssertStatusOK(..SetItemEnabled(1, ..#TARGET), ..#TARGET_" is enabled again")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": " "}, .targets, .dryRun), "a blank target is refused")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {}, .targets, .dryRun), "so is none")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "and nothing in OCUORDERS changed: "_lines.%ToJSON())
}

Method TestDryRunAndRun()
{
	If '..Ready() Quit
	Set a = ..Session("rrun")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..Watch(a)
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now), "ItemNoun": {"one": "order", "other": "orders"}.%ToJSON()})
	Set incident = row.Ref
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set dry = ..AskDryRun(incident, "reroute", {"target": (..#TARGET)}.%ToJSON(), trace, .dryRunSession, .sc)
	Do $$$AssertTrue($IsObject(dry), "FixExecutor answers the dry run")
	If '$IsObject(dry) Quit
	Do $$$AssertEquals(dry.Reason, "", "without a reason")
	Do $$$AssertEquals(dry.Targets, ids, "its targets are the three failed orders, ascending")
	Set stored = {}.%FromJSON(dry.DryRun)
	Do $$$AssertEquals(stored.affected_"|"_stored.resend_"|"_stored.leftOut_"|"_stored.from_"|"_stored.to_"|"_stored.example_"|"_stored.itemNoun.other, "3|3|0|OrdersFromPartner|"_..#TARGET_"|"_$Piece(ids, ",", 1)_"|orders", "the dry run holds the counts, both items, the first id as the example and the noun")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .afterDry)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, afterDry)
	Do $$$AssertEquals(lines.%Size(), 0, "the dry run changed nothing in OCUORDERS: "_lines.%ToJSON())

	Set ref = ..Request(a, incident, ids, dry.DryRun, {"target": (..#TARGET)}.%ToJSON())
	Set holder = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set holder.RequestRefs = ref
	Do $$$AssertStatusOK(holder.%Save(), "the incident names the request")
	Kill holder
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled by FixExecutor")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.reason, "1|3|3|3|0|0|", "it is final and holds 3/3/3/0/0 and no reason")
	}
	Set run = ..RunOf(incident, ref)
	Do $$$AssertEquals($Select($IsObject(run): run.copies.%Size(), 1: -1), 3, "the run holds three copies")
	If $IsObject(run) {
		Set copies = ..Joined(run.copies)
		Set sent = 0
		For i = 1:1:$Length(copies, ",") {
			Set header = ..Header(..#ORDERS, $Piece(copies, ",", i))
			If header.target = ..#TARGET Set sent = sent + 1
			Do $$$AssertEquals(header.target_"|"_header.status, ..#TARGET_"|9", "copy "_i_" went to "_..#TARGET_" and completed there (status 9)")
			Do $$$AssertEquals(##class(OcuTalon.Data.FixRun).CopyOf(..#ORDERS, $Piece(copies, ",", i)), ref, "and FixRun CopyOf names the request: its failure joins no incident")
		}
		Do $$$AssertEquals(sent, 3, "all three")
	}
	For i = 1:1:$Length(ids, ",") {
		Do $$$AssertEquals(..Header(..#ORDERS, $Piece(ids, ",", i)).status, 8, "original "_i_" is unchanged: still in the status Error (8)")
	}
	Do $$$AssertEquals(..WaitState(incident, ref, "done", ..#WAITEND), "done", "the request is done")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.rerouted|"_ref, "result.rerouted with the request's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .rsc), "All 3 orders were rerouted to "_..#TARGET_" and completed there. The originals stay unchanged.", "which says where the copies went")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", ref, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "one Action entry names the request")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.action_"|"_entries.%Get(0).data.target, "reroute|"_..#ORDERSPRODUCTION_" in "_..#ORDERS_" to "_..#TARGET, "with the kind and the target")
	// the originals are named as resent, so a second dry run finds nothing
	Set again = ..AskDryRun(incident, "reroute", {"target": (..#TARGET)}.%ToJSON(), trace, .secondSession, .sc2)
	Do $$$AssertTrue($IsObject(again), "FixExecutor answers a second dry run")
	If $IsObject(again) Do $$$AssertEquals(again.Targets_"|"_again.DryRun_"|"_again.Reason, "||", "which finds nothing to reroute: the originals are resent already")
}

Method TestFailedAgainIsNotRetried()
{
	If '..Ready() Quit
	Set a = ..Session("rfail")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..Watch(a)
	Set since = ..Since()
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now), "ItemNoun": {"one": "order", "other": "orders"}.%ToJSON()})
	Set incident = row.Ref
	Kill row
	// a request fixed to the three orders whose target is the item they failed at, as a row of an earlier dry run could be: the executor reads the row only, and the copies fail again
	Set ref = ..Request(a, incident, ids, {"affected": 3, "resend": 3, "leftOut": 0, "itemNoun": {"one": "order", "other": "orders"}, "from": "OrdersFromPartner", "to": "OrdersFromPartner", "example": ($Piece(ids, ",", 1))}.%ToJSON(), {"target": "OrdersFromPartner"}.%ToJSON())
	Set holder = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set holder.RequestRefs = ref
	Do $$$AssertStatusOK(holder.%Save(), "the incident names the request")
	Kill holder
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped, "1|3|3|0|3|0", "it holds 3/3/0/3/0: the copies failed again")
		Do $$$AssertTrue((result.reason '= "") && (result.reason '[ "still wasn't accepted"), "with the first sentence of the error as the reason: "_result.reason)
	}
	Set runs = ..Runs(incident)
	Do $$$AssertEquals(runs.%Size(), 1, "there is one FixRun: the copies are never retried")
	If runs.%Size() = 1 {
		Set copies = ..Joined(runs.%Get(0).copies)
		Do $$$AssertEquals($Length(copies, ","), 3, "of three copies")
		For i = 1:1:$Length(copies, ",") {
			Do $$$AssertEquals(..Header(..#ORDERS, $Piece(copies, ",", i)).status, 8, "copy "_i_" is in the status Error (8)")
			Do $$$AssertEquals(##class(OcuTalon.Data.FixRun).CopyOf(..#ORDERS, $Piece(copies, ",", i)), ref, "and FixRun CopyOf names the request, so that IncidentManager takes its failure for no new one")
		}
	}
	// the poller has delivered the copies' failures and IncidentManager has handled them, so that the negatives below can't pass by timing
	Set copyIds = $Select(runs.%Size() = 1: ..Joined(runs.%Get(0).copies), 1: "")
	Do $$$AssertTrue(..WaitHandled(since, copyIds), "the poller delivered the failures of the copies "_copyIds_" and IncidentManager handled them")
	Do $$$AssertEquals(..Runs(incident).%Size(), 1, "and there is still one FixRun")
	Set holder = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(holder.Count_"|"_holder.RequestRefs, "3|"_ref, "the incident's count and requests are as they were: no later request")
}

Method TestTargetDisabledAfterDryRun()
{
	If '..Ready() Quit
	Set a = ..Session("rdisabled")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now), "ItemNoun": {"one": "order", "other": "orders"}.%ToJSON()})
	Set incident = row.Ref
	Set parameters = {"target": (..#TARGET)}
	Set ref = ..Request(a, incident, ids, {"affected": 3, "resend": 3, "leftOut": 0, "itemNoun": {"one": "order", "other": "orders"}, "from": "OrdersFromPartner", "to": (..#TARGET), "example": ($Piece(ids, ",", 1))}.%ToJSON(), parameters.%ToJSON())
	Set holder = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set holder.RequestRefs = ref
	Do $$$AssertStatusOK(holder.%Save(), "the incident names the request")
	Kill holder
	Set sentBefore = ..SentTo(..#TARGET)
	// the target is disabled after the dry run
	Do $$$AssertStatusOK(..SetItemEnabled(0, ..#TARGET), ..#TARGET_" is disabled after the dry run")
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.Reroute).Recheck(row, parameters, ids, .passed, .skipped), "the re-check answers")
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), "|3", "and passes no target")
	Do $$$AssertEquals(skipped.%Get(0).reason, ..#TARGET_" is no longer enabled", "each is skipped with the reason that the target is no longer enabled")
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled")
	Do $$$AssertEquals(..WaitState(incident, ref, "done", ..#WAITEND), "done", "the run ends")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.reason, "1|3|0|0|0|3|"_..#TARGET_" is no longer enabled", "it holds Total 3, Skipped 3 and the reason")
	}
	Set run = ..RunOf(incident, ref)
	Do $$$AssertEquals($Select($IsObject(run): run.copies.%Size(), 1: -1), 0, "the run holds no copy")
	Do $$$AssertEquals(..SentTo(..#TARGET), sentBefore, "and no message went to "_..#TARGET)
	For i = 1:1:$Length(ids, ",") {
		Do $$$AssertEquals(..Header(..#ORDERS, $Piece(ids, ",", i)).status, 8, "original "_i_" is still in the status Error (8)")
	}
}

Method TestRowNamingAnotherSessionsMessage()
{
	If '..Ready() Quit
	Set a = ..Session("rscopea")
	Set b = ..Session("rscopeb")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	If '..Fail(2, traceA) Quit
	Set mineFailed = ..WaitFailed(2)
	If mineFailed.%Size() '= 2 Quit
	If '..Fail(2, traceB) Quit
	Set allFailed = ..WaitFailed(4)
	If allFailed.%Size() '= 4 Quit
	Set theirs = ..SuperIds(allFailed, traceB)
	Do $$$AssertEquals($Length(theirs, ","), 2, "two failed orders of the other session")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, ..HeaderIds(allFailed), ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now), "ItemNoun": {"one": "order", "other": "orders"}.%ToJSON()})
	Set incident = row.Ref
	Set parameters = {"target": (..#TARGET)}
	// a request row of A's incident that names only the other session's messages, as a row that was written wrongly could
	Set ref = ..Request(a, incident, theirs, {"affected": 2, "resend": 2, "leftOut": 0, "itemNoun": {"one": "order", "other": "orders"}, "from": "OrdersFromPartner", "to": (..#TARGET), "example": ($Piece(theirs, ",", 1))}.%ToJSON(), parameters.%ToJSON())
	Set holder = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set holder.RequestRefs = ref
	Do $$$AssertStatusOK(holder.%Save(), "the incident names the request")
	Kill holder
	Set sentBefore = ..SentTo(..#TARGET)
	Set reason = "message "_$Piece(theirs, ",", 1)_" is not one of this request's failed messages any more"
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Kind.Reroute).Recheck(row, parameters, theirs, .passed, .skipped), "the re-check answers")
	Do $$$AssertEquals(passed_"|"_skipped.%Size()_"|"_skipped.%Get(0).reason, "|2|"_reason, "it passes neither message and skips them with the scope reason")
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute is handled")
	Do $$$AssertEquals(..WaitState(incident, ref, "done", ..#WAITEND), "done", "the run ends")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|2|0|0|2|"_reason, "it holds Total 2, Skipped 2 and the scope reason")
	}
	Set run = ..RunOf(incident, ref)
	Do $$$AssertEquals($Select($IsObject(run): run.copies.%Size(), 1: -1), 0, "the run holds no copy")
	Do $$$AssertEquals(..SentTo(..#TARGET), sentBefore, "and nothing was resent to "_..#TARGET)
	For i = 1:1:$Length(theirs, ",") {
		Do $$$AssertEquals(..Header(..#ORDERS, $Piece(theirs, ",", i)).status, 8, "the other session's order "_i_" is unchanged: still in the status Error (8)")
	}
}

Method TestOtherSessionsMessages()
{
	If '..Ready() Quit
	Set a = ..Session("rown")
	Set b = ..Session("rother")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	If '..Fail(2, traceA) Quit
	Set mineFailed = ..WaitFailed(2)
	If mineFailed.%Size() '= 2 Quit
	If '..Fail(2, traceB) Quit
	Set allFailed = ..WaitFailed(4)
	If allFailed.%Size() '= 4 Quit
	Set mine = ..SuperIds(allFailed, traceA)
	Set theirs = ..SuperIds(allFailed, traceB)
	Do $$$AssertEquals($Length(mine, ",")_"|"_$Length(theirs, ","), "2|2", "two failed orders of each session")
	// the incident of A lists the keys of all four, as a group would after a mix-up
	Set incident = ..Fixture(a, ..HeaderIds(allFailed))
	Set sc = ##class(OcuTalon.Fix.Kind.Reroute).DryRun(incident, {"target": (..#TARGET)}, .targets, .dryRun)
	Do $$$AssertStatusOK(sc, "the dry run is worked out")
	Do $$$AssertEquals(targets, mine, "its targets are the session's own failed orders: "_targets)
	Do $$$AssertEquals(dryRun.resend, 2, "it resends two")
}

/// --- helpers ---
/// The number of messages in OCUORDERS addressed to the item.
ClassMethod SentTo(item As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName = ?", item)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Waits up to WAITBATCH seconds, polling every half second, until every header id of ids (comma-separated) is in a FailureBatch after since that IncidentManager has handled
/// (status Completed); 1 when they all are.
Method WaitHandled(since As %Integer, ids As %String) As %Boolean [ Private ]
{
	If ids = "" Quit 0
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Kill handled
		Set batches = ..Batches(since)
		Set iterator = batches.%GetIterator()
		While iterator.%GetNext(, .batch) {
			If batch.status '= 9 Continue
			Set failures = batch.failures.%GetIterator()
			While failures.%GetNext(, .failure) {
				Set handled(failure.headerId) = ""
			}
		}
		Set all = 1
		For i = 1:1:$Length(ids, ",") {
			If '$Data(handled($Piece(ids, ",", i))) Set all = 0
		}
		If all || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit all
}

/// An approved reroute request of the owner for the incident over the targets, with the dry run (JSON text) and the parameters; its Ref.
Method Request(owner As %String, incident As %String, targets As %String, dryRun As %String, parameters As %String) As %String [ Private ]
{
	Set fields = {"FixKind": "reroute", "FixTargets": (targets), "FixParameters": (parameters), "DryRun": (dryRun), "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "approved", , fields)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// The first error text of a status, without its "ERROR #n:" start.
ClassMethod Text(sc As %Status) As %String [ Private ]
{
	Set text = $SYSTEM.Status.GetOneErrorText(sc)
	If $Extract(text, 1, 7) = "ERROR #" Set text = $ZStrip($Piece(text, ":", 2, *), "<W")
	Quit text
}

}
