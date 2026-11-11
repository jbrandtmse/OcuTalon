/// Tests of the fixes that the user asks for in the chat, in IncidentManager (Story 23.2; AD-1, AD-15, AD-16, AD-32): a ProposeFix handled by a shadow instance of
/// Test.Watch.IncidentProbe over fixture sessions, incidents and requests of Test.Data.Fixture, with the dry run FixExecutor would give set by the test (the probe's DryAnswer)
/// and the request that IncidentManager raises recorded by the probe (Raised). They need no production, so they run warm.
///   - TestRerouteRaised (AC1, AC2): a reroute asked for an open noticed incident asks the dry run once, with no window mark moved; one fix request is raised, fixed to the
///     dry run's targets and kind; the incident is awaiting_approval and saved with the request; the session gets one approval Notification incident.rerouteRequest with the count,
///     both items and the example, which renders as ruled;
///   - TestSuspendAndUndo (AC1, AC2, AC6): a suspend for a resolved incident raises one request with incident.suspendRequest; the same ask again is already_asked; after the suspend
///     is done, resume_item raises one request with incident.resumeRequest and a second resume ask is already_asked;
///   - TestRefusedNothingAndFailed: a dry run's Reason is refused with the reason in the message, a dry run with no Targets is nothing, an error is failed; none raises a request;
///   - TestNotAllowedAndNotFound: a closed or unknown incident and a session that is not a recipient are not_found; a kind the chat may not ask for, an unknown kind, parameters
///     that are no object and an incident that was not noticed are not_allowed; the dry run is not asked for any of them;
///   - TestRejectedAndExpired (AC7): the outcome rejected or expired of such a request returns the incident to open with that variant and tells the session;
///   - TestNoticeKeys: Notice AskedKey, AskedSlots, ResultKey, ResultSlots and NoFixKey (DW-823) for the new kinds.
Class OcuTalon.Test.Fix.Asked Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The noun of the incidents.
Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, comma-separated.
Property Incidents As %String(MAXLEN = "");

/// The log row before the test.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("FixAsked", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Incidents, ",") {
		Set ref = $Piece(..Incidents, ",", i)
		If ref = "" Continue
		Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(ref)
		For g = 1:1:groups.Count() Do ##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(g).%Id())
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Asked", $Parameter(..#PROBE, "LOGASK"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "RaiseAsked", $Parameter(..#PROBE, "LOGASK"))
	Quit $$$OK
}

/// A reroute asked for an open noticed incident (the rejected variant), with 50 failed orders at OrdersFromPartner.
Method TestRerouteRaised()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("reroute")
	Set incident = ..Incident(owner, "open", {"OpenVariant": "rejected"})
	Set host.DryAnswer = ..Answer("1,2,3", ..RerouteDryRun(3))
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response = ..Ask(host, owner, incident, "reroute", {"target": "OrdersForReview"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "1|raised|"_host.RaiseRef, "the answer is raised, with the request's Ref")
	Do $$$AssertEquals(response.Message, "The approval request is raised with its dry run. Nothing changes until it is approved.", "and the ruled message for the model")
	Do $$$AssertEquals(host.Asks.%Size(), 1, "the dry run was asked once")
	Do $$$AssertEquals(host.Asks.%Get(0).fixKind_"|"_host.Asks.%Get(0).parameters, "reroute|{""target"":""OrdersForReview""}", "for the kind and its parameters")
	Do $$$AssertEquals(host.DryRuns.%Size(), 0, "through the synchronous ask, not the window's: no asynchronous dry run was sent")
	Do $$$AssertEquals(..Marks(incident), ">", "and no window mark moved")
	Do $$$AssertEquals(host.Raised.%Size(), 1, "one request is raised")
	Set row = host.Raised.%Get(0)
	Do $$$AssertEquals(row.kind_"|"_row.incidentRef_"|"_row.ownerRef_"|"_row.resultTarget_"|"_row.fixKind_"|"_row.fixParameters_"|"_row.fixTargets, "fix|"_incident_"|"_owner_"|IncidentManager|reroute|{""target"":""OrdersForReview""}|1,2,3", "a fix request of the incident, fixed to the targets")
	Do $$$AssertEquals({}.%FromJSON(row.dryRun).%ToJSON(), ..RerouteDryRun(3).%ToJSON(), "with the dry run stored")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(stored.State_"|"_stored.OpenVariant_"|"_stored.RequestRefs, "awaiting_approval||"_host.RaiseRef, "the incident is awaiting approval and lists the request")
	Do $$$AssertEquals(host.Sent.%Size(), 1, "the session gets one Notification")
	Set note = host.Sent.%Get(0)
	Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef, owner_"|approval|incident.rerouteRequest|"_host.RaiseRef_"|"_incident, "of kind approval with the key incident.rerouteRequest and the request's Ref")
	Set slots = {}.%FromJSON(note.slots)
	Do $$$AssertEquals(slots.count_"|"_slots.from_"|"_slots.to_"|"_slots.example_"|"_slots.resendCount_"|"_slots.itemNoun.other, "3|OrdersFromPartner|OrdersForReview|1|3|orders", "its slots hold the count, both items, the example and the resend count")
	Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots, "phone", .sc)
	Do $$$AssertStatusOK(sc, "it renders")
	Do $$$AssertEquals(text, "I can reroute 3 failed orders from OrdersFromPartner to OrdersForReview. Approve?"_$Char(10, 10)_"Dry run: 3 orders affected. Example: message 1 would go to OrdersForReview instead of OrdersFromPartner. I'll resend 3 copies to OrdersForReview; the originals stay unchanged. Nothing has changed yet."_$Char(10, 10)_"Details and trace: on your OcuTalon page.", "as ruled")
}

/// A suspend asked twice raises one request; after it is done the undo, resume_item, raises exactly one request of its own.
Method TestSuspendAndUndo()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("undo")
	Set incident = ..Incident(owner, "resolved")
	Set host.DryAnswer = ..Answer("5", {"item": "OrdersToWarehouse", "before": "enabled", "after": "disabled"})
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set suspend = host.RaiseRef
	Set response = ..Ask(host, owner, incident, "suspend_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(response.Outcome, "raised", "the suspend is raised")
	Do $$$AssertEquals(host.Raised.%Size(), 1, "one request")
	Set note = host.Sent.%Get(0)
	Do $$$AssertEquals(note.catalogKey_"|"_note.slots, "incident.suspendRequest|{""item"":""OrdersToWarehouse"",""production"":""Zz.Asked"_..Number_"""}", "the Notification has the item and the production")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots, "web", .sc), "I can suspend OrdersToWarehouse in Zz.Asked"_..Number_"."_$Char(10, 10)_"Dry run: OrdersToWarehouse is enabled now and would be disabled. Nothing has changed yet."_$Char(10, 10)_"Details and trace: on your OcuTalon page.", "which reads as ruled on the page")
	// the request's row, as Approval.Raise would have made it
	Do ..Row(owner, incident, suspend, "pending", "suspend_item", "OrdersToWarehouse")
	Set again = ..Ask(host, owner, incident, "suspend_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "0|already_asked", "the same ask again is already_asked")
	Do $$$AssertEquals(again.Message, "That approval request is already waiting, so no second one was raised.", "with the ruled message")
	Do $$$AssertEquals(host.Raised.%Size()_"|"_host.Asks.%Size(), "1|1", "no second request is raised and no second dry run is asked")
	// the suspend is done; the incident resolves again; its undo
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(suspend)
	Set row.State = "done"
	Do $$$AssertStatusOK(row.%Save(), "the suspend is done")
	Kill row
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set stored.State = "resolved"
	Do $$$AssertStatusOK(stored.%Save(), "and the incident is resolved again")
	Kill stored
	Set host.DryAnswer = ..Answer("5", {"item": "OrdersToWarehouse", "before": "disabled", "after": "enabled"})
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set resume = host.RaiseRef
	Set undo = ..Ask(host, owner, incident, "resume_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(undo.Outcome_"|"_undo.Ref, "raised|"_resume, "asking to undo raises a resume request")
	Do $$$AssertEquals(host.Sent.%Get(host.Sent.%Size() - 1).catalogKey, "incident.resumeRequest", "with the resume notice")
	Do ..Row(owner, incident, resume, "pending", "resume_item", "OrdersToWarehouse")
	Set twice = ..Ask(host, owner, incident, "resume_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(twice.Outcome, "already_asked", "and asking to undo again raises nothing")
	Do $$$AssertEquals(host.Raised.%Size(), 2, "exactly one resume request was raised, besides the suspend")
	Set stored = {}.%FromJSON(host.Raised.%Get(1).dryRun)
	Do $$$AssertEquals(host.Raised.%Get(1).fixKind_"|"_host.Raised.%Get(1).fixTargets_"|"_stored.item_"|"_stored.before_"|"_stored.after, "resume_item|5|OrdersToWarehouse|disabled|enabled", "with its own dry run, and nothing changes until it is approved")
}

/// A dry run's Reason, no targets and an error.
Method TestRefusedNothingAndFailed()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("refused")
	Set incident = ..Incident(owner, "resolved")
	Set answer = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set answer.Reason = "OrdersToWarehouse is already disabled"
	Set host.DryAnswer = answer
	Set response = ..Ask(host, owner, incident, "suspend_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|refused|OrdersToWarehouse is already disabled, so no request was raised.", "a Reason is refused, with the reason in the message")
	Set answer.Reason = "The online demo shares the Orders production."
	Set response = ..Ask(host, owner, incident, "suspend_item", {"item": "OrdersToWarehouse"})
	Do $$$AssertEquals(response.Message, "The online demo shares the Orders production, so no request was raised.", "a reason that ends with a full stop loses it")
	Set host.DryAnswer = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set response = ..Ask(host, owner, incident, "reroute", {"target": "OrdersForReview"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|nothing|None of the incident's failed messages can be rerouted now, so no request was raised.", "no targets is nothing")
	Set host.FailAsk = 1
	Set response = ..Ask(host, owner, incident, "reroute", {"target": "OrdersForReview"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "an error is failed")
	Do $$$AssertEquals(host.Raised.%Size()_"|"_host.Sent.%Size(), "0|0", "none of them raises a request or sends a Notification")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(stored.State_"|"_stored.RequestRefs, "resolved|", "and the incident is as it was")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "RaiseAsked", $Parameter(..#PROBE, "LOGASK")), 1, "the failed ask is one Type 3 warning (RaiseAsked, the tail of every asked request, logs it)")
}

Method TestNotAllowedAndNotFound()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("denied")
	Set other = ..Owner("stranger")
	Set host.DryAnswer = ..Answer("5", {"item": "OrdersToWarehouse", "before": "enabled", "after": "disabled"})
	Set incident = ..Incident(owner, "resolved")
	Set closed = ..Incident(owner, "closed")
	Set unnoticed = ..Incident(owner, "open", {"NoticedAt": ""})
	Set response = ..Ask(host, owner, closed, "suspend_item", {"item": "A"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_found", "a closed incident is not found")
	Set response = ..Ask(host, owner, ##class(OcuTalon.Bridge.Ids).NewRef(), "suspend_item", {"item": "A"})
	Do $$$AssertEquals(response.Outcome, "not_found", "so is an unknown one")
	Set response = ..Ask(host, other, incident, "suspend_item", {"item": "A"})
	Do $$$AssertEquals(response.Outcome, "not_found", "and one of another session")
	Set response = ..Ask(host, "", incident, "suspend_item", {"item": "A"})
	Do $$$AssertEquals(response.Outcome, "not_found", "and a command with no session")
	Set response = ..Ask(host, owner, incident, "repair_resend", {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_allowed", "a kind the chat may not ask for is not allowed")
	Do $$$AssertEquals(response.Message, "That fix can't be asked for on this incident now, so nothing was raised.", "with the ruled message")
	Set response = ..Ask(host, owner, incident, "rollback", {"item": "A"})
	Do $$$AssertEquals(response.Outcome, "not_allowed", "an unknown kind is not allowed")
	Set command = ..Command(owner, incident, "suspend_item", {})
	Set command.Parameters = "not json"
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "parameters that are no object are handled")
	Do $$$AssertEquals(response.Outcome, "not_allowed", "and are not allowed")
	Set response = ..Ask(host, owner, unnoticed, "suspend_item", {"item": "A"})
	Do $$$AssertEquals(response.Outcome, "not_allowed", "an incident that was not noticed is not allowed")
	Do $$$AssertEquals(host.Asks.%Size()_"|"_host.Raised.%Size(), "0|0", "no dry run was asked and no request raised")
}

/// The outcome of the request: rejected or expired returns the incident to open with that variant, and tells the session.
Method TestRejectedAndExpired()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("outcome")
	For event = "rejected", "expired" {
		Set incident = ..Incident(owner, "resolved")
		Set host.DryAnswer = ..Answer("5", {"item": "OrdersToWarehouse", "before": "enabled", "after": "disabled"})
		Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set ref = host.RaiseRef
		Set response = ..Ask(host, owner, incident, "suspend_item", {"item": "OrdersToWarehouse"})
		Do $$$AssertEquals(response.Outcome, "raised", event_": the request is raised")
		Do ..Row(owner, incident, ref, event, "suspend_item", "OrdersToWarehouse")
		Set outcome = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
		Set outcome.ApprovalRef = ref
		Set outcome.IncidentRef = incident
		Set outcome.Outcome = event
		Set sent = host.Sent.%Size()
		Do $$$AssertStatusOK(host.OnRequest(outcome, .answer), event_": the outcome is handled")
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(stored.State_"|"_stored.OpenVariant, "open|"_event, event_": the incident is open with that variant")
		Do $$$AssertEquals(host.Sent.%Size(), sent + 1, "and the session is told")
		Set note = host.Sent.%Get(host.Sent.%Size() - 1)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef, "answered|answered."_event_"|"_ref, "with the answered notice of the request")
		Do $$$AssertEquals(host.Executed.%Size(), 0, "nothing runs")
	}
}

/// The keys and slots of the notices of the new kinds, and the key of the good-message refusal.
Method TestNoticeKeys()
{
	Set notice = "OcuTalon.Watch.Notice"
	Do $$$AssertEquals($ClassMethod(notice, "AskedKey", "suspend_item")_"|"_$ClassMethod(notice, "AskedKey", "resume_item")_"|"_$ClassMethod(notice, "AskedKey", "reroute")_"|"_$ClassMethod(notice, "AskedKey", "repair_resend"), "incident.suspendRequest|incident.resumeRequest|incident.rerouteRequest|", "AskedKey by the kind's name, empty for any other")
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident.Namespace = "ZZNS"
	Set incident.Production = "Zz.Asked"
	Set slots = $ClassMethod(notice, "AskedSlots", "reroute", ..RerouteDryRun(3), incident, .sc)
	Do $$$AssertStatusOK(sc, "the reroute slots are built")
	Do $$$AssertEquals(slots.%GetTypeOf("count")_"|"_slots.%GetTypeOf("resendCount")_"|"_slots.example, "number|number|1", "count and resendCount are numbers and the example is the header id")
	For missing = "from", "to", "example", "itemNoun", "affected", "resend" {
		Set dry = ..RerouteDryRun(3)
		Do dry.%Remove(missing)
		Do $ClassMethod(notice, "AskedSlots", "reroute", dry, incident, .sc)
		Do $$$AssertStatusNotOK(sc, "a reroute dry run without "_missing_" gives no slots")
	}
	Do $ClassMethod(notice, "AskedSlots", "suspend_item", {"before": "enabled"}, incident, .sc)
	Do $$$AssertStatusNotOK(sc, "a suspend dry run without its item gives no slots")
	Do $ClassMethod(notice, "AskedSlots", "repair_resend", {}, incident, .sc)
	Do $$$AssertStatusNotOK(sc, "and a kind with no notice of this sort none")
	// the result keys
	Set done = ..Result({"Final": 1, "Total": 1, "Completed": 1})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", done, "suspend_item")_"|"_$ClassMethod(notice, "ResultKey", "done", done, "resume_item"), "result.itemSuspended|result.itemResumed", "a changed item reads suspended or resumed")
	Set skipped = ..Result({"Final": 1, "Total": 1, "Skipped": 1, "Reason": "x"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", skipped, "suspend_item"), "result.itemSkipped", "a skipped item reads skipped")
	Set failed = ..Result({"Final": 1, "Total": 1, "Reason": "x"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "failed", failed, "suspend_item"), "result.itemNotChanged", "a run that could not start reads not changed")
	Set all = ..Result({"Final": 1, "Total": 3, "Resent": 3, "Completed": 3})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", all, "reroute")_"|"_$ClassMethod(notice, "ResultKey", "done", all, "repair_resend")_"|"_$ClassMethod(notice, "ResultKey", "done", all), "result.rerouted|result.allThrough|result.allThrough", "a reroute whose copies all completed reads rerouted; the repair keeps allThrough")
	Set again = ..Result({"Final": 1, "Total": 3, "Resent": 3, "Completed": 2, "FailedAgain": 1, "Reason": "x"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", again, "reroute"), "result.failedAgain", "and a reroute with a failed copy keeps the existing key")
	Set itemSlots = $ClassMethod(notice, "ResultSlots", "result.itemSuspended", done, {"one": "x", "other": "xs"}, .sc, {"item": "A", "production": "Orders"})
	Do $$$AssertEquals(itemSlots.%ToJSON(), "{""item"":""A"",""production"":""Orders""}", "the item slots are the item and the production")
	Do $ClassMethod(notice, "ResultSlots", "result.itemSuspended", done, {"one": "x", "other": "xs"}, .sc, {"item": "A"})
	Do $$$AssertStatusNotOK(sc, "without the production there are none")
	Set routed = $ClassMethod(notice, "ResultSlots", "result.rerouted", all, {"one": "order", "other": "orders"}, .sc, {"to": "OrdersForReview"})
	Do $$$AssertEquals(routed.count_"|"_routed.to, "3|OrdersForReview", "the rerouted slots hold the count and the target")
	// DW-823
	Set lead = $Piece($Parameter("OcuTalon.Fix.Kind.RepairResend", "GOODCHANGED"), "{", 1)
	Do $$$AssertEquals($ClassMethod(notice, "NoFixKey", lead_"2 of the 20 messages")_"|"_$ClassMethod(notice, "NoFixKey", "The incident has no failed message of its scope to repair")_"|"_$ClassMethod(notice, "NoFixKey", ""), "incident.goodChanged|incident.noFix|incident.noFix", "the good-message refusal has its own key (DW-823)")
	// AC-DC: a cause that already ends with a full stop leaves no double stop
	Set text = ##class(OcuTalon.Msg.Catalog).Render("incident.goodChanged", {"count": 3, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "cause": "The date format changed.", "noun": "orders", "groups": [{"itemName": "OrdersFromPartner", "count": 3, "errorSummary": "e", "firstAt": "2026-10-16T18:12:00Z"}]}.%ToJSON(), "phone", .sc)
	Do $$$AssertStatusOK(sc, "incident.goodChanged renders")
	Do $$$AssertTrue(text [ "The date format changed. The fix I would use would also change orders that went through, so I'm not proposing it. Nothing was changed.", "with the Planner's sentence")
	Do $$$AssertTrue(text '[ "..", "and no double full stop")
	// (QA) a cause without a full stop gets exactly one
	Set bare = ##class(OcuTalon.Msg.Catalog).Render("incident.goodChanged", {"count": 1, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "cause": "The date format changed", "noun": "orders", "groups": [{"itemName": "OrdersFromPartner", "count": 1, "errorSummary": "e", "firstAt": "2026-10-16T18:12:00Z"}]}.%ToJSON(), "phone", .sc)
	Do $$$AssertStatusOK(sc, "a cause without a full stop renders")
	Do $$$AssertTrue(bare [ "1 order failed since", "the count and the noun are the single ones")
	Do $$$AssertTrue(bare [ "The date format changed. The fix I would use would also change orders that went through", "and the sentence has its one full stop")
	Do $$$AssertTrue(bare '[ "..", "and no double full stop")
}

/// --- helpers ---
/// A shadow instance of the probe.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture incidents.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzask"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

ClassMethod T(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
}

/// A fixture incident of the owner in the state (noticed unless fields say otherwise) with a failure group of 3 orders at OrdersFromPartner; its Ref.
Method Incident(owner As %String, state As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"State": (state), "OpenVariant": "", "FirstAt": (..T(-7200)), "LastAt": (..T(-3600)), "Count": 3, "NoticeCount": 3, "ItemNoun": (..#NOUN), "Cause": "The partner changed the date format.", "FixSummary": "repair the date and resend the orders"}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set noticed = $Select(all.%IsDefined("NoticedAt"): all.NoticedAt, 1: ..T(-6600))
	Do all.%Remove("NoticedAt")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticed, "ZZNS", "Zz.Asked"_..Number, all)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_","_ref
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = ref
	Set group.Seq = 1
	Set group.ItemName = "OrdersFromPartner"
	Set group.ErrorPattern = "The order date was not in the expected format"
	Set group.ErrorSummary = "The order date was not in the expected format"
	Set group.Seen = "h1,h2,h3"
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = ..T(-7200)
	Set group.LastAt = ..T(-3600)
	$$$ThrowOnError(group.%Save())
	Quit ref
}

/// The marks of the incident's groups, "AskedFrom>AskedTo".
ClassMethod Marks(incident As %String) As %String
{
	Set group = ##class(OcuTalon.Data.FailureGroup).SeqIndexOpen(incident, 1)
	Quit group.AskedFrom_">"_group.AskedTo
}

/// The answer of FixExecutor to the dry run: the targets and the dry run (a dynamic object).
Method Answer(targets As %String, dryRun As %DynamicObject) As OcuTalon.Fix.Msg.DryRunResult
{
	Set answer = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set answer.Targets = targets
	Set answer.DryRun = dryRun.%ToJSON()
	Quit answer
}

/// The dry run of a reroute of count orders.
ClassMethod RerouteDryRun(count As %Integer) As %DynamicObject
{
	Quit {"affected": (count), "resend": (count), "leftOut": 0, "itemNoun": {"one": "order", "other": "orders"}, "from": "OrdersFromPartner", "to": "OrdersForReview", "example": "1"}
}

/// A ProposeFix of the kind for the incident from the session.
Method Command(session As %String, incident As %String, kind As %String, parameters As %DynamicObject) As OcuTalon.Msg.Command.ProposeFix
{
	Set command = ##class(OcuTalon.Msg.Command.ProposeFix).%New()
	Set command.SessionRef = session
	Set command.IncidentRef = incident
	Set command.FixKind = kind
	Set command.Parameters = parameters.%ToJSON()
	Set command.Origin = "tool"
	Quit command
}

/// The CommandResult of a ProposeFix handled by the probe.
Method Ask(host As OcuTalon.Test.Watch.IncidentProbe, session As %String, incident As %String, kind As %String, parameters As %DynamicObject) As OcuTalon.Msg.CommandResult
{
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(..Command(session, incident, kind, parameters), .response), "the "_kind_" ask is handled")
	Quit response
}

/// The row of a request of the incident that IncidentManager raised (the probe raises none), in the state.
Method Row(owner As %String, incident As %String, ref As %String, state As %String, kind As %String, item As %String)
{
	Set parameters = $Select(kind = "reroute": {"target": (item)}, 1: {"item": (item)}).%ToJSON()
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , {"Ref": (ref), "FixKind": (kind), "FixParameters": (parameters), "FixTargets": "5", "ResultTarget": "IncidentManager"})
	Set ..Refs = ..Refs_","_request
}

/// A FixResult with the fields.
ClassMethod Result(fields As %DynamicObject) As OcuTalon.Fix.Msg.FixResult
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set $Property(result, name) = value
	}
	Quit result
}

}
