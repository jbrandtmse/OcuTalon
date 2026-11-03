Include (Ensemble, EnsErrors)

/// Tests of the re-check of an approved repair (Story 7.3; AD-3, AD-4, AD-16). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh, with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS and the real Watch.Reader. They fail with the reason where the production, OCUORDERS or demo mode is missing.
/// The messages a test made in OCUORDERS (the copy of the hand resend included) and its incident rows are removed after it.
///   - TestChangedTargetsAreSkipped (AC 6; the matrix row "Changed targets"): session S's incident holds six failed orders as the targets of a request (five of S's
///     scope and one failed without S's trace Ref, which is of the instance's scope). Since the dry run one of S's has been completed, one has an OrderDate already in
///     the target format, one has a description of its own and has been resent by hand twice (its copy was resent again, so its session holds the descriptions
///     "Resent <id>: note" and "Resent <copy>,<id>: note"), and one has lost its header and its body. Only the unchanged one passes; the other five are skipped, each
///     with a plain reason of its own that names it, and nothing in OCUORDERS changes. The test also reads the targets with the resent flag off and on, to show that
///     only the flag gives the ids that resent a message, in both description forms; reads a production that is not the namespace's own, which is an error with no target
///     passed; and shows that Execute, which reads the targets again, resends none of the five, and that the resend itself skips a plan entry whose header, status,
///     field or value has gone stale;
///   - TestResendStopsWhereItErrs (DW-419, U-182; the matrix row "Resend stops where it errs"): with Orders stopped a plan of a gone header and two valid ones makes no copy, skips the gone
///     one and leaves the others unreached (stopped, after), and OCUORDERS is unchanged; with Orders running and the second header's target set to a name that is no item, the first
///     valid entry is resent and the refused one and the one after it are unreached (refused, after); and with a namespace that cannot be entered the first copy throws and every entry is unreached (error, after);
///   - TestUnreadableNamespaceIsAnError (AC 6; the matrix row "Unreadable"): the same read passes a failed order while the service role holds Read on the Orders data
///     database, and once the role no longer holds it the Reader's outcome is unreadable, which Recheck and Execute turn into an error that says the service user
///     cannot read the namespace: no target passes, none is skipped as gone, no copy is made and nothing in OCUORDERS changes.
Class OcuTalon.Test.Fix.Recheck Extends OcuTalon.Test.Watch.Case
{

Parameter KIND = "OcuTalon.Fix.Kind.RepairResend";

Method TestChangedTargetsAreSkipped()
{
	If '..Ready() Quit
	Set a = ..Session("recheck")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(5, trace) Quit
	If '..Fail(1, "") Quit
	Set failed = ..WaitFailed(6)
	If failed.%Size() '= 6 Quit
	Set tagged = ""
	Set untagged = ""
	For i = 0:1:failed.%Size() - 1 {
		If failed.%Get(i).superSession = trace {
			Set tagged = tagged _ $Select(tagged = "": "", 1: ",") _ failed.%Get(i).id
		} Else {
			Set untagged = failed.%Get(i).id
		}
	}
	Do $$$AssertEquals($Length(tagged, ",")_"|"_(untagged '= ""), "5|1", "five failed orders carry S's trace Ref and one does not")
	If ($Length(tagged, ",") '= 5) || (untagged = "") Quit
	Set unchanged = $Piece(tagged, ",", 1)
	Set completed = $Piece(tagged, ",", 2)
	Set repaired = $Piece(tagged, ",", 3)
	Set resent = $Piece(tagged, ",", 4)
	Set lost = $Piece(tagged, ",", 5)
	Set targets = ..Ascending(tagged _ "," _ untagged)

	// the changes since the dry run
	Do $$$AssertStatusOK(..Complete(completed), "one order has been completed")
	Do $$$AssertStatusOK(..SetOrderDate(repaired, "2026-10-16"), "one has an OrderDate in the target format")
	Do $$$AssertStatusOK(..Describe(resent, "note"), "one has a description of its own")
	Do $$$AssertStatusOK(..ResendByHand(resent, .firstCopy), "and has been resent by hand")
	Do $$$AssertStatusOK(..ResendByHand(firstCopy), "and so has its copy")
	Do $$$AssertStatusOK(..Lose(lost), "and one has lost its header and its body")
	Set incident = ..Fixture(a, targets)
	Set parameters = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}
	Set namespaces = $ListBuild(..#ORDERS)
	Set sessions = ""
	For i = 0:1:failed.%Size() - 1 {
		Set sessions = sessions _ $Select(sessions = "": "", 1: ",") _ failed.%Get(i).sessionId
	}
	Do $$$AssertTrue(..WaitSettled(..#ORDERS, sessions), "the copies resent by hand have settled")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)

	Set sc = $ClassMethod(..#KIND, "Recheck", incident, parameters, targets, .passed, .skipped)
	Do $$$AssertStatusOK(sc, "the re-check reads the production")
	Do $$$AssertEquals(passed, unchanged, "only the unchanged order passes")
	Do $$$AssertEquals(skipped.%Size(), 5, "the other five are skipped")
	Kill reasons
	Set iterator = skipped.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set reasons(entry.id) = entry.reason
		Do $$$AssertTrue($Find(entry.reason, "message "_entry.id) > 0, "the reason of "_entry.id_" names it: "_entry.reason)
	}
	Do $$$AssertTrue($Find($Get(reasons(completed)), "no longer in the error status") > 0, "the completed order: no longer in the error status")
	Do $$$AssertTrue($Find($Get(reasons(repaired)), "no longer reads as MM/DD/YYYY") > 0, "the order in the target format: no longer reads as MM/DD/YYYY")
	Do $$$AssertTrue($Find($Get(reasons(resent)), "has been resent already") > 0, "the order resent by hand: has been resent already")
	Do $$$AssertTrue($Find($Get(reasons(lost)), "no longer in the production") > 0, "the order that lost its header: no longer in the production")
	Do $$$AssertTrue($Find($Get(reasons(untagged)), "not one of this request's failed messages") > 0, "the order of another scope: not one of this request's failed messages")
	Kill unique
	Set id = ""
	For {
		Set id = $Order(reasons(id), 1, reason)
		Quit:id=""
		Set unique(reason) = ""
	}
	Set count = 0
	Set reason = ""
	For {
		Set reason = $Order(unique(reason))
		Quit:reason=""
		Set count = count + 1
	}
	Do $$$AssertEquals(count, 5, "and each reason is its own")

	// the resent flag is what shows a resend by hand
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "h"_resent, .plain)
	Set found = plain.failures.%Get(0)
	Do $$$AssertEquals(outcome_"|"_found.headerId_"|"_found.%IsDefined("resentBy"), "read|"_resent_"|0", "without the flag the failure has no resentBy member")
	Set outcome = ##class(OcuTalon.Watch.Reader).Evidence(..#ORDERS, ..#ORDERSPRODUCTION, "OrdersFromPartner", "h"_resent_",h"_unchanged, .flagged, 1)
	Do $$$AssertEquals(outcome, "read", "with the flag the same read succeeds")
	Set by = ""
	For i = 0:1:flagged.failures.%Size() - 1 {
		Set by = by _ $Select(by = "": "", 1: ",") _ flagged.failures.%Get(i).headerId _ "=" _ $Select($IsObject(flagged.failures.%Get(i).resentBy): flagged.failures.%Get(i).resentBy.%Size(), 1: "<none>")
	}
	Do $$$AssertEquals(by, resent_"=2,"_unchanged_"=0", "the resent order has two headers that resent it (one named 'Resent <id>: note', one 'Resent <copy>,<id>: note') and the unchanged one none")

	// a production that is not the namespace's own cannot be read: an error, and no target passes
	Set production = incident.Production
	Set incident.Production = "Zz.NotTheRunningProduction"
	Set sc = $ClassMethod(..#KIND, "Recheck", incident, parameters, targets, .passedNone, .skippedNone)
	Set incident.Production = production
	Do $$$AssertStatusNotOK(sc, "a re-check of a production that is not the namespace's own is an error")
	Do $$$AssertEquals(passedNone, "", "and no target passes")

	// Execute reads the targets again: none of the five that changed is resent
	Set changed = ..Ascending(completed _ "," _ repaired _ "," _ resent _ "," _ lost _ "," _ untagged)
	Set sc = $ClassMethod(..#KIND, "Execute", incident, parameters, changed, .result)
	Do $$$AssertStatusOK(sc, "Execute reads the production")
	Do $$$AssertEquals(result.resent_"|"_result.skipped.%Size(), "0|5", "and resends none of the five that changed: each is skipped")

	// the guards at the switch: an entry of the plan that is stale is not resent either
	Set plan = []
	Do plan.%Push({"id": (completed), "field": "OrderDate", "value": "10/16/2026", "repaired": "2026-10-16"})
	Do plan.%Push({"id": (repaired), "field": "OrderDate", "value": "10/16/2026", "repaired": "2026-10-16"})
	Do plan.%Push({"id": (lost), "field": "OrderDate", "value": "10/16/2026", "repaired": "2026-10-16"})
	Do plan.%Push({"id": (unchanged), "field": "NoSuchField", "value": "10/16/2026", "repaired": "2026-10-16"})
	Do ##class(OcuTalon.Fix.Executor).Resend(..#ORDERS, plan, "", .copies, .refused)
	Do $$$AssertEquals(copies_"|"_refused.%Size(), "0|4", "a plan whose entries went stale resends none: each is skipped")
	Kill why
	Set iterator = refused.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set why(+entry.id) = entry.reason
	}
	Do $$$AssertTrue($Find($Get(why(+completed)), "message "_completed_" is no longer in the error status") > 0, "the completed order: "_$Get(why(+completed)))
	Do $$$AssertTrue($Find($Get(why(+repaired)), "changed while the run was starting") > 0, "the order whose value moved: "_$Get(why(+repaired)))
	Do $$$AssertTrue($Find($Get(why(+lost)), "message "_lost_" is no longer in the production") > 0, "the order that lost its header: "_$Get(why(+lost)))
	Do $$$AssertTrue($Find($Get(why(+unchanged)), "no longer a stored field") > 0, "the field that is no stored field: "_$Get(why(+unchanged)))
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "nothing in OCUORDERS changed during the re-check: "_lines.%ToJSON())
}

Method TestUnreadableNamespaceIsAnError()
{
	If '..Ready() Quit
	Set a = ..Session("recheckread")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(1, trace) Quit
	Set failed = ..WaitFailed(1)
	If failed.%Size() '= 1 Quit
	Set id = failed.%Get(0).id
	Set incident = ..Fixture(a, id)
	Set parameters = {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}
	Set namespaces = $ListBuild(..#ORDERS)

	Set sc = $ClassMethod(..#KIND, "Recheck", incident, parameters, id, .passed, .skipped)
	Do $$$AssertStatusOK(sc, "control: the re-check reads the production while the service role holds Read on the Orders data")
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), id_"|0", "and the failed order passes")

	Do ..RevokeRole(..#ORDERSDATA)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set sc = $ClassMethod(..#KIND, "Recheck", incident, parameters, id, .passedNone, .skippedNone)
	Do $$$AssertStatusNotOK(sc, "with no Read on "_..#ORDERSDATA_" the re-check is an error")
	Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "the service user cannot read the namespace") > 0, "which says that the service user cannot read the namespace: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(passedNone_"|"_skippedNone.%Size(), "|0", "no target passes and none is skipped as gone")

	Set sc = $ClassMethod(..#KIND, "Execute", incident, parameters, id, .result)
	Do $$$AssertStatusNotOK(sc, "Execute is an error too")
	Do $$$AssertEquals(result.resent_"|"_result.skipped.%Size(), "0|0", "and resends and skips nothing")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "nothing in OCUORDERS changed: "_lines.%ToJSON())
}

/// A resend stops at the first copy that errs (DW-419, U-182; the matrix row "Resend stops where it errs"): with the Orders production stopped, a plan of a header that is gone and two
/// valid ones resends nothing, skips the gone header (a real skip) and reaches neither valid one, which come back as unreached: the first as stopped, the second as after (it is never
/// tried), and no header is made, so OCUORDERS is unchanged. With Orders running again, a plan of a valid entry, one whose header's target is no item of the production (Ens refuses
/// that copy with an error and makes no header) and another valid entry resends the first, and the refused one and the one after it are unreached: refused and after. The test
/// shows first what Ens gives: ErrProductionNotRunning with no new id for a stopped production, and an error with no new id for a target that is no item.
Method TestResendStopsWhereItErrs()
{
	If '..Ready() Quit
	Set a = ..Session("recheckstops")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(4, trace) Quit
	Set failed = ..WaitFailed(4)
	If failed.%Size() '= 4 Quit
	Set ids = ..Ascending(..HeaderIds(failed))
	Set gone = $Piece(ids, ",", 1), second = $Piece(ids, ",", 2), third = $Piece(ids, ",", 3), fourth = $Piece(ids, ",", 4)
	Do $$$AssertStatusOK(..Lose(gone), "one order has lost its header and its body")
	Set namespaces = $ListBuild(..#ORDERS)
	Set plan = []
	For id = gone, second, third {
		Do plan.%Push({"id": (id), "field": "OrderDate", "value": "10/16/2026", "repaired": "2026-10-16"})
	}

	// Orders stopped: what Ens gives, then what Resend does with it
	If '..StopOrders() Quit
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set sc = ..Ens(second, .newId)
	Do $$$AssertEquals($SYSTEM.Status.Equals(sc, $$$EnsErrProductionNotRunning)_"|"_newId, "1|", "Ens answers ErrProductionNotRunning for a copy while the production is stopped, with no new id")
	Do ##class(OcuTalon.Fix.Executor).Resend(..#ORDERS, plan, "", .resent, .skipped, .unreached)
	Do $$$AssertEquals(resent, 0, "no copy is made")
	Do $$$AssertEquals(skipped.%Size()_"|"_skipped.%Get(0).id, "1|"_gone, "the order that is gone is skipped, and it is the only skip")
	Do $$$AssertEquals(unreached.%Size()_"|"_unreached.%Get(0).id_"|"_unreached.%Get(0).code_"|"_unreached.%Get(1).id_"|"_unreached.%Get(1).code, "2|"_second_"|stopped|"_third_"|after", "the first valid entry is unreached as stopped, and the next one as after: it is never tried")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "nothing in OCUORDERS changed: "_lines.%ToJSON())
	If '..StartOrders() Quit

	// Orders running, one entry whose target is no item: the production refuses that copy
	Do $$$AssertStatusOK(..Retarget(third, "ZzNoSuchItem"), "the target of one header is set to a name that is no item")
	Set sc = ..Ens(third, .newId)
	Do $$$AssertEquals($$$ISERR(sc)_"|"_$SYSTEM.Status.Equals(sc, $$$EnsErrProductionNotRunning)_"|"_newId, "1|0|", "Ens refuses a copy to a target that is no item with an error that is not ErrProductionNotRunning, and no new id")
	Set plan = []
	For id = second, third, fourth {
		Do plan.%Push({"id": (id), "field": "OrderDate", "value": "10/16/2026", "repaired": "2026-10-16"})
	}
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Fix.Executor).Resend(..#ORDERS, plan, "", .resent, .skipped, .unreached)
	Do $$$AssertEquals(resent, 1, "the first valid entry is resent")
	Do $$$AssertEquals(skipped.%Size(), 0, "and nothing is skipped")
	Do $$$AssertEquals(unreached.%Size()_"|"_unreached.%Get(0).id_"|"_unreached.%Get(0).code_"|"_unreached.%Get(1).id_"|"_unreached.%Get(1).code, "2|"_third_"|refused|"_fourth_"|after", "the refused entry is unreached as refused, and the entry after it as after")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "Resend", $Parameter("OcuTalon.Fix.Executor", "LOGCOPY")), 1, "and the refusal logs one Type 3 warning")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Resend", $Parameter("OcuTalon.Fix.Executor", "LOGCOPY"))

	// a copy that throws: the namespace of the production cannot be entered
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Fix.Executor).Resend("ZZNOSUCHNAMESPACE", plan, "", .resent, .skipped, .unreached)
	Do $$$AssertEquals(resent_"|"_skipped.%Size(), "0|0", "nothing is resent and nothing is skipped when the first copy throws")
	Do $$$AssertEquals(unreached.%Size()_"|"_unreached.%Get(0).id_"|"_unreached.%Get(0).code_"|"_unreached.%Get(2).id_"|"_unreached.%Get(2).code, "3|"_second_"|error|"_fourth_"|after", "the entry that threw is unreached as error, and every entry after it as after")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "Resend", $Parameter("OcuTalon.Fix.Executor", "LOGCOPY")), 1, "and the error logs one Type 3 warning")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Resend", $Parameter("OcuTalon.Fix.Executor", "LOGCOPY"))
}

/// --- helpers ---
/// The ids (comma-separated) in ascending order.
ClassMethod Ascending(ids As %String) As %String [ Private ]
{
	For i = 1:1:$Length(ids, ",") {
		Set sorted($Piece(ids, ",", i)) = ""
	}
	Set text = ""
	Set id = ""
	For {
		Set id = $Order(sorted(id))
		Quit:id=""
		Set text = text _ $Select(text = "": "", 1: ",") _ id
	}
	Quit text
}

/// Moves the header in OCUORDERS to the status Completed, as the production would have it after a hand repair.
ClassMethod Complete(id As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Do header.SetStatus($$$eMessageStatusCompleted)
	Quit $$$OK
}

/// Resends the header's message in OCUORDERS as the portal's resend does, with the same body: the copy (newId) has the description "Resent <id>" (then ",<earlier
/// ids>" or ": <description>" of the header that is resent) and fails again like the original. The test removes it with the other messages of the run.
ClassMethod ResendByHand(id As %String, Output newId As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(id, .newId)
}

/// Sets the description of the header in OCUORDERS (a header that the test made).
ClassMethod Describe(id As %String, text As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Set header.Description = text
	Quit header.%Save()
}

/// Asks Ens for a copy of the header's message, with its body cloned, to the header's own target, in OCUORDERS: the status, and newId is the new header's id ("" when none).
ClassMethod Ens(id As %String, Output newId As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set newId = ""
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Set body = $ClassMethod(header.MessageBodyClassName, "%OpenId", header.MessageBodyId)
	Quit ##class(Ens.MessageHeader).ResendDuplicatedMessage(id, .newId, header.TargetConfigName, body.%ConstructClone(0))
}

/// Sets the target of the header in OCUORDERS (a header that the test made).
ClassMethod Retarget(id As %String, target As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens.MessageHeader SET TargetConfigName = ? WHERE ID = ?", target, id)
	Quit $Select(rs.%SQLCODE < 0: $SYSTEM.Status.Error(5001, rs.%Message), 1: $$$OK)
}

/// Deletes the header and its body in OCUORDERS.
ClassMethod Lose(id As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Set bodyClass = header.MessageBodyClassName
	Set bodyId = header.MessageBodyId
	Kill header
	Set sc = ##class(Ens.MessageHeader).%DeleteId(id)
	If $$$ISOK(sc) && (bodyClass '= "") && (bodyId '= "") Set sc = $ClassMethod(bodyClass, "%DeleteId", bodyId)
	Quit sc
}

}
