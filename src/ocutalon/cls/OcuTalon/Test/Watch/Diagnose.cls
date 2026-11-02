Include Ensemble

/// Tests of the diagnosis that IncidentManager starts at the settle end (Story 5.4; AD-5, AD-6, AD-8, AD-12, AD-15, AD-26, AD-30, AD-31). THEY RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, over the RUNNING production: IncidentManager, Decide and DiagnosisAgent are items of it, so the class
/// runs fresh (a warm stack's running job keeps its old code). The model is the CI mock: a failure that carries a [[mock:<name>]] marker in its error text reaches the
/// mock in the pack's errorPattern, so the text picks the scenario. They fail with the reason where OCUORDERS or demo mode is missing. A test waits at most 90 seconds
/// for a diagnosis, polling every half second (a test bound, not NFR-7). The rows, events and decisions of a test are removed after it.
///   - TestDemoDiagnosis (rows Demo and What the model saw): session A watches Orders and 50 failing orders tagged with A become an incident whose stream gets
///     noticed, settling and diagnosing in that order; Decide records one diagnose decision for the incident in the incident's own trace session; the row holds the
///     scenario's diagnosis, the noun order/orders, no fallback and the decision's Ref, the sample's header id (one of the real failed orders) and its error, and once IncidentManager has
///     handled the answer (Case.WaitAnswered) the with-fix notice follows (Story 7.2; DW-270, DW-271): the incident is noticed and awaiting_approval with no variant and lists its one
///     request; that ApprovalRequest is a pending fix of A (result target IncidentManager, A's trace Ref, repair_resend, its parameters, the 50 failed orders' ids ascending as targets and
///     the stored dry run, whose resend is the number of those targets and whose field is the words of the parameters' field, so that the request the user sees is built from what the executor runs: U-126), its hold started in the incident's trace session, which also holds the DryRun to FixExecutor, its answer and the send to Notify; A has one incident
///     Notification (incident.withFix, the request's Ref, the dry run's slots, which render the UJ-1 dry-run paragraph) and no kind approval; WebChatOut recorded its Delivery row; A's
///     stream holds noticed, settling, diagnosing and then the incident event with the request, as /state lists it;
///     the first model request holds the pack, the second the result of read_failed_messages built from the real failed orders, and the mock logged only those two requests;
///   - TestDiagnosisVariants (rows No fix, Unknown, Invalid / refusal): one batch of four failures whose texts hold the markers diagnosis-nofix,
///     diagnosis-unknown, invalid-reply and refusal gives four incidents that settle together: partner_outage without a fix and with the noun message/messages,
///     unknown without a fix and with the diagnosis's own noun (invoice/invoices), and two fallbacks (invalid, refusal) with no cause, category, element or fix, the code noun and the fallback decision's Ref; the invalid one also has one Type 3 warning of Decide.Conclude in its trace session that starts with REFUSED and the decision's Ref and names what the reply check
///     refused, never the reply: it ends with "OcuTalon.Watch.Msg.DiagnosisPayload accepts: ERROR #9406 on Reasons" (the refusal has none), and the notice of the real order's fallback holds none of it; OnAfterOneTest removes those warnings (Story 5.12);
///     beside them, a failure of a real failed order of OCUORDERS whose text holds invalid-reply gives a fallback whose code noun is that of the sample's body
///     class, order/orders. Since Story 5.8 each of the five is noticed: NoticedAt is set, the state is open and the open variant is no_fix (no fix, unknown) or
///     fallback (invalid, refusal), and A has one Notification of the incident;
///   - TestGoneBeforeTheAnswer: an incident deleted after `diagnosing` while the delayed reply (diagnosis-late) is on its way gets no row back and no error;
///   - TestRefusedRequest: the error handler of the diagnose request (through Test.Watch.IncidentProbe, a shadow instance in the test process) stores the fallback
///     error with one Type 3 warning and notices the incident as a fallback (one recorded Notification) and leaves the row otherwise as it was; an incident that is
///     noticed, closed or gone is not written and gets no notice. The answer handler
///     (the probe's Answer) writes a usable answer to an open incident and notices it, and writes and notices neither a noticed nor a closed one, and the empty
///     answer that follows an error writes and notices nothing.
Class OcuTalon.Test.Watch.Diagnose Extends OcuTalon.Test.Watch.Case
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The namespace and the production of the incidents that SendBatch makes: nothing runs there, so the pack has no sample.
Parameter SYNTHNS = "ZZNS";

Parameter SYNTH = "Zz.Diagnose";

/// The cause and the fix summary of ci/mock/scenarios/A/diagnosis.json.
Parameter CAUSE = "The partner now sends the order date as month, day and year with slashes, and the production expects year, month and day with dashes.";

Parameter FIXSUMMARY = "rewrite the order date of the failed orders in the format the production expects and send them again";

Parameter ORDERNOUN = "{""one"":""order"",""other"":""orders""}";

Parameter MESSAGENOUN = "{""one"":""message"",""other"":""messages""}";

/// The start of the warning that Decide.Conclude logs for the reply check of an invalid diagnose reply (the decision's Ref follows).
Parameter REFUSED = "The reply check refused the reply of the decision ";

/// The newest row of the event log before TestDiagnosisVariants made its warnings, or "": OnAfterOneTest removes the REFUSED warnings after it.
Property WarningMark As %Integer;

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..WarningMark '= "" Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..WarningMark, "Conclude", ..#REFUSED)
	Set ..WarningMark = ""
	Quit ##super(testname)
}

Method TestDemoDiagnosis()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set a = ..Session("demo")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set mark = $ClassMethod(mock, "LogMark")
	If '..Fail(50, trace) Quit
	Set failed = ..WaitFailed(50)
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of A")
	If rows.%Size() < 1 Quit
	Set ref = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitAnswered(ref), "and IncidentManager has handled the answer, so the notice step has begun")
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and the with-fix notice follows: NoticedAt is set")
	Do ..WaitNotices(ref, 1)
	Do ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, 5)
	Set progress = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress", 3, 20)
	Do $$$AssertEquals(progress.%Size(), 3, "A's stream holds three watch.progress events")
	If progress.%Size() = 3 Do $$$AssertEquals(progress.%Get(0).payload.stage_"|"_progress.%Get(1).payload.stage_"|"_progress.%Get(2).payload.stage_"|"_progress.%Get(2).payload.ref, "noticed|settling|diagnosing|"_ref, "noticed, settling and diagnosing, in that order, for the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(ref, "diagnose")
	Do $$$AssertTrue($IsObject(decision), "Decide recorded one diagnose decision for the incident")
	If $IsObject(decision) && $IsObject(row) {
		Do $$$AssertEquals(decision.Kind_"|"_decision.ItemId_"|"_decision.OwnerRef, "diagnose|"_ref_"|"_a, "its item is the incident's Ref and its owner the incident's")
		Do $$$AssertTrue(row.TraceHeaderId '= "", "the incident has its trace session")
		Do $$$AssertEquals(decision.TraceSessionId, row.TraceHeaderId, "the decision is in the incident's own trace session")
		Do $$$AssertEquals(row.CauseCategory_"|"_row.Element_"|"_row.Fallback_"|"_row.FallbackReason, "data_format_change|OrderDate|0|", "the row holds the category and the element, and no fallback")
		Do $$$AssertEquals(row.Cause, ..#CAUSE, "the scenario's cause")
		Do $$$AssertEquals(row.FixSummary, ..#FIXSUMMARY, "and its fix summary")
		Do $$$AssertEquals(row.ItemNoun, ..#ORDERNOUN, "the noun is order and orders")
		Do $$$AssertEquals(row.DecisionRef, decision.Ref, "the DecisionRef is the decision's")
		Do $$$AssertEquals((row.NoticedAt '= "")_"|"_row.State_"|"_row.OpenVariant, "1|awaiting_approval|", "the incident is noticed and awaiting approval, with no variant")
		Do $$$AssertTrue((row.SampleHeaderId '= "") && (("," _ ..HeaderIds(failed) _ ",") [ ("," _ row.SampleHeaderId _ ",")), "the sample is one of the real failed orders: header "_row.SampleHeaderId)
		Do $$$AssertEquals(row.SampleError, ..#ORDERDATETEXT, "and its error is the measured sentence")
		Do $$$AssertEquals(row.NoticeCount, 50, "NoticeCount is the 50 failures")
	}
	If $IsObject(row) Do ..AssertWithFix(ref, row, a, trace, failed)
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).Headers($Select($IsObject(row): row.TraceHeaderId, 1: ""), "IncidentManager")
	Do $$$AssertTrue(steps.%Size() > 0, "the waiter's session holds the messages it sent")
	Set sent = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set sent = sent _ $ListBuild(header.target)
	}
	Do $$$AssertEquals($ListFind(sent, "Decide") > 0, 1, "among them the request to Decide")
	Do $$$AssertEquals($ListFind(sent, "OutcomeRouter"), 0, "and none to OutcomeRouter")
	Do $$$AssertEquals($ListFind(sent, "FixExecutor") > 0, 1, "and the dry run to FixExecutor")
	Do $$$AssertEquals($ListFind(sent, "Notify") > 0, 1, "and the notice to Notify")

	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = []
	Set firstAt = $Select($IsObject(row): row.FirstAt, 1: "")
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && $Find(entry.%ToJSON(), "ocutalon.evidencePack/1") && (firstAt '= "") && $Find(entry.%ToJSON(), firstAt) Do requests.%Push(entry)
	}
	Do $$$AssertEquals(requests.%Size(), 2, "the diagnosis made two model requests")
	Do $$$AssertEquals(..ModelRequests(entries), 2, "and the whole run logged only those two POST /v1/messages requests: the dry run calls no model")
	If requests.%Size() = 2 {
		Set text = ##class(OcuTalon.Test.Agent.RunnerFixture).Messages(requests.%Get(0))
		Do $$$AssertTrue((text [ """count"":50") && (text [ """item"":""OrdersFromPartner""") && (text [ ..#ORDERDATETEXT) && (text [ """OrderDate"":""10/16/2026"""), "the first holds the pack: count 50, the item, the measured sentence and a body with the date")
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the second carries the result of one tool call")
		If $ListLength(results) = 1 {
			Set result = {}.%FromJSON($List(results, 1))
			Do $$$AssertEquals(result.count_"|"_result.items.%Size(), "50|5", "read_failed_messages gave the count and five items")
			Set ids = ","_..HeaderIds(failed)_","
			Set real = 1
			Set iterator = result.items.%GetIterator()
			While iterator.%GetNext(, .item) {
				If (ids '[ (","_item.headerId_",")) || (item.error '= ..#ORDERDATETEXT) Set real = 0
			}
			Do $$$AssertEquals(real, 1, "each item is a real failed order, with the measured sentence")
		}
	}
}

/// The with-fix row of the matrix for the incident (Story 7.2; AC 1, AC 3, AC 7; DW-270, DW-271): one pending fix request with the fix's kind, parameters and
/// targets and the dry run, its hold in the incident's trace session, S's stream, the one Notification (never a kind approval) and its render, /state and the
/// Delivery row.
Method AssertWithFix(ref As %String, row As OcuTalon.Data.Incident, a As %String, trace As %String, failed As %DynamicArray) [ Private ]
{
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "exactly one approval request names the incident")
	If requests.%Size() '= 1 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.ownerRef_"|"_request.state_"|"_request.resultTarget_"|"_request.traceRef, "fix|"_a_"|pending|IncidentManager|"_trace, "it is a pending fix of S, with the result target IncidentManager and S's trace Ref")
	Do $$$AssertEquals(request.fixKind, "repair_resend", "its kind")
	Set parameters = {}.%FromJSON(request.fixParameters)
	Do $$$AssertEquals(parameters.field_"|"_parameters.sourceFormat_"|"_parameters.targetFormat, "OrderDate|MM/DD/YYYY|YYYY-MM-DD", "and its parameters, the exact change")
	Set ids = ..HeaderIds(failed)
	For i = 1:1:$Length(ids, ",") {
		If $Piece(ids, ",", i) '= "" Set sorted($Piece(ids, ",", i)) = ""
	}
	Set expected = ""
	Set id = ""
	For {
		Set id = $Order(sorted(id))
		Quit:id=""
		Set expected = expected_$Select(expected = "": "", 1: ",")_id
	}
	Do $$$AssertEquals(request.fixTargets, expected, "its targets are the 50 failed orders' header ids, ascending")
	Set dryRun = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut_"|"_dryRun.field_"|"_dryRun.before_"|"_dryRun.after_"|"_dryRun.itemNoun.one_"|"_dryRun.itemNoun.other, "50|50|0|order date|10/16/2026|2026-10-16|order|orders", "and its stored dry run")
	Set targetCount = $Length(request.fixTargets, ",")
	Set fieldWords = ##class(OcuTalon.Fix.Kind.RepairResend).FieldWords(parameters.field)
	Set resendCount = +dryRun.resend
	Do $$$AssertEquals(resendCount, targetCount, "U-126: the dry run's resend is the number of the row's FixTargets, so the request the user sees is what the executor runs")
	Do $$$AssertEquals(dryRun.field, fieldWords, "U-126: the dry run's field is FieldWords of the row's FixParameters field")
	Do $$$AssertEquals(row.RequestRefs, request.ref, "the incident lists the request")
	Do $$$AssertTrue(..HoldInSession(row.TraceHeaderId, request.ref), "its live hold started in the incident's trace session")
	Set end = $ZHorolog + ..#WAITINCIDENT
	While (##class(OcuTalon.Bridge.Approval).LiveHold(request.ref) = "") && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).LiveHold(request.ref) '= "", "and the hold is live")
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 1, "which holds one DryRun to FixExecutor")
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 2, "FixExecutor", "IncidentManager", "OcuTalon.Fix.Msg.DryRunResult"), 1, "and its answer")
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 1, "IncidentManager", "Notify", "OcuTalon.Msg.Notification"), 1, "and the send to Notify")

	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one Notification of the incident")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.decisionRef, a_"|incident|incident.withFix|"_request.ref_"|"_row.DecisionRef, "of kind incident, incident.withFix, with the request's Ref and the row's DecisionRef (none of kind approval)")
		Set slots = note.slots
		Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.itemNoun.one_"|"_slots.itemNoun.other_"|"_slots.cause_"|"_slots.fixSummary, "50|"_row.FirstAt_"|order|orders|"_..#CAUSE_"|"_..#FIXSUMMARY, "its slots: count, the first failure's time, the noun, the cause and the fix summary")
		Do $$$AssertEquals(slots.field_"|"_slots.before_"|"_slots.after_"|"_slots.resendCount_"|"_slots.%GetTypeOf("resendCount"), "order date|10/16/2026|2026-10-16|50|number", "and the dry run's field, before, after and resendCount")
		Do $$$AssertEquals(slots.resendCount_"|"_slots.field, targetCount_"|"_fieldWords, "U-126: the notice's resendCount and field are those of the row's targets and parameters")
		Set text = ##class(OcuTalon.Msg.Catalog).Render("incident.withFix", slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "the slots render")
		Do $$$AssertTrue(text [ "Dry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.", "to the UJ-1 dry-run paragraph: "_text)
	}
	Do ..AssertDelivered(a, "incident", request.ref)

	Set events = ..Stream(a)
	Set types = ""
	Set last = ""
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.type = "watch.progress" Set types = types_$Select(types = "": "", 1: ",")_event.payload.stage
		If event.type = "incident" {
			Set types = types_$Select(types = "": "", 1: ",")_"incident"
			Set last = event
		}
	}
	Do $$$AssertEquals(types, "noticed,settling,diagnosing,incident", "S's stream holds noticed, settling, diagnosing, then the incident event, in that order")
	If $IsObject(last) {
		Do $$$AssertEquals(last.payload.state_"|"_..Listed(last.payload), "awaiting_approval|1|"_request.ref_"|pending", "the event lists the request with its Ref and state")
	}
	Set found = ..StateIncident(a, ref)
	Do $$$AssertTrue($IsObject(found), "/state lists the incident for S")
	If $IsObject(found) Do $$$AssertEquals(..Listed(found), "1|"_request.ref_"|pending", "with the request, as the event does")
}

/// The number of POST /v1/messages entries in the mock's log entries.
ClassMethod ModelRequests(entries As %DynamicArray) As %Integer
{
	Set count = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") Set count = count + 1
	}
	Quit count
}

Method TestDiagnosisVariants()
{
	Set ..WarningMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("variants")
	If '..Fail(1) Quit
	Set failed = ..WaitFailed(1)
	Do $$$AssertEquals(failed.%Size(), 1, "one real failed order of OCUORDERS")
	If failed.%Size() < 1 Quit
	Set order = [{"item": "OrdersFromPartner", "text": "[[mock:invalid-reply]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1)), "id": ($Piece(..HeaderIds(failed), ",", 1))}]
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a, order), "a failure of that order is sent")
	Set failures = []
	For marker = "diagnosis-nofix", "diagnosis-unknown", "invalid-reply", "refusal" {
		Do failures.%Push({"item": (..Item(marker)), "text": ("[[mock:"_marker_"]] Field 'Qty' was empty"), "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))})
	}
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, failures), "one batch of four failures is sent")
	Set rows = ..WaitIncident(a, ..#SYNTH, 4)
	Do $$$AssertEquals(rows.%Size(), 4, "four incidents")
	If rows.%Size() '= 4 Quit
	For i = 0:1:3 {
		Set ref = rows.%Get(i).ref
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
		Do $$$AssertTrue(..WaitDiagnosed(ref), "incident "_(i + 1)_" holds its diagnosis")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		Set marker = $Extract(..Group(ref).itemName, $Length(..Item("")) + 1, *)
		Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(ref, "diagnose")
		If '$IsObject(row) || '$IsObject(decision) {
			Do $$$AssertTrue(0, marker_": the row and its decision exist")
			Continue
		}
		Do $$$AssertEquals(row.DecisionRef, decision.Ref, marker_": the DecisionRef is the decision's")
		Kill row
		Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", marker_": the incident is noticed")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		Do $$$AssertEquals(row.State_"|"_row.OpenVariant, "open|"_$Select($Piece(marker, "-", 1) = "diagnosis": "no_fix", 1: "fallback"), marker_": open, with the variant of its outcome")
		Do ..WaitNotices(ref, 1)
		Do $$$AssertEquals(..Notifications(ref), 1, marker_": A has one Notification of the incident")
		If marker = "diagnosis-nofix" {
			Do $$$AssertEquals(row.Fallback_"|"_row.CauseCategory_"|"_(row.Cause '= "")_"|"_row.FixSummary_"|"_row.Element, "0|partner_outage|1||", marker_": partner_outage with a cause and no fix")
			Do $$$AssertEquals(row.ItemNoun, ..#MESSAGENOUN, marker_": the scenario gives no noun, so the noun is message and messages")
		} ElseIf marker = "diagnosis-unknown" {
			Do $$$AssertEquals(row.Fallback_"|"_row.CauseCategory_"|"_row.FixSummary, "0|unknown|", marker_": unknown, with no fix")
			Do $$$AssertEquals(row.ItemNoun, "{""one"":""invoice"",""other"":""invoices""}", marker_": the scenario's own noun replaces the code noun")
		} Else {
			Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "1|"_$Select(marker = "refusal": "refusal", 1: "invalid"), marker_": the fallback of the bridge")
			Do $$$AssertEquals(row.Cause_row.CauseCategory_row.Element_row.FixSummary, "", marker_": no cause, category, element or fix")
			Do $$$AssertEquals(row.ItemNoun, ..#MESSAGENOUN, marker_": the code noun")
			Do $$$AssertEquals(decision.Fallback, 1, marker_": the decision is the fallback")
			Do $$$AssertTrue(decision.TraceSessionId '= "", marker_": the decision has a trace session")
			Set warnings = ..DecideWarnings(decision.TraceSessionId, .text)
			If marker = "invalid-reply" {
				Do $$$AssertEquals(warnings, 1, marker_": one warning of Decide.Conclude in the decision's trace session")
				Do $$$AssertTrue(($Extract(text, 1, $Length(..#REFUSED_decision.Ref)) = (..#REFUSED_decision.Ref)) && (text [ "The reply check failed"), marker_": it starts with REFUSED and the decision's Ref and holds the reply check's text")
				Set tail = "OcuTalon.Watch.Msg.DiagnosisPayload accepts: ERROR #9406 on Reasons"
				Do $$$AssertEquals($Extract(text, *-$Length(tail)+1, *), tail, marker_": it ends with what the check refused: the code and the property, not the reply")
			} Else {
				Do $$$AssertEquals(warnings, 0, marker_": no warning of Decide.Conclude in the decision's trace session")
			}
		}
	}
	Set orders = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(orders.%Size(), 1, "one incident of the real order")
	If orders.%Size() '= 1 Quit
	Set ref = orders.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "it holds its diagnosis")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If $IsObject(row) Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.ItemNoun, "1|invalid|"_..#ORDERNOUN, "its fallback keeps the code noun of the sample's body class: order and orders")
	Kill row
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and it is noticed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do ..WaitNotices(ref, 1)
	Set note = ..NoticeBodies(ref)
	Do $$$AssertEquals(row.OpenVariant_"|"_note.%Size(), "fallback|1", "as a fallback, with one Notification")
	If note.%Size() = 1 Do $$$AssertEquals(note.%Get(0).slots.itemNoun.other_"|"_note.%Get(0).slots.fallbackReason, "orders|invalid", "which says orders and the reason")
	If note.%Size() = 1 Do $$$AssertTrue($ZConvert(note.%Get(0).slots.%ToJSON(), "L") '[ "reply check", "and its slots hold nothing of the reply check")
}

/// The number of Type 3 warnings of Decide.Conclude in the trace session; text is the newest one's.
ClassMethod DecideWarnings(sessionId As %Integer, Output text As %String) As %Integer [ Private ]
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 3 AND SourceClass = 'OcuTalon.Bridge.Process.Decide' AND SourceMethod = 'Conclude' ORDER BY ID", sessionId)
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

Method TestGoneBeforeTheAnswer()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("gone")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, [{"item": (..Item("late")), "text": "[[mock:diagnosis-late]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))}]), "a failure whose diagnosis comes late is sent")
	Set rows = ..WaitIncident(a, ..#SYNTH)
	If rows.%Size() '= 1 {
		Do $$$AssertTrue(0, "one incident is made")
		Quit
	}
	Set ref = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set progress = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress", 3, 40)
	Do $$$AssertEquals(progress.%Size(), 3, "the diagnosis has started: diagnosing is published")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Incidents).DeleteIncident(ref), 1, "the incident is deleted while the reply is on its way")
	Set end = $ZHorolog + 40
	For {
		Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(ref, "diagnose")
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue($IsObject(decision), "Decide answered, and recorded its decision")
	If $IsObject(decision) Do $$$AssertTrue(..WaitAnswered(ref, decision.TraceSessionId, 40), "and IncidentManager handled the answer")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexExists(ref), 0, "no row came back")
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Size(), 0, "also by a read of the owner's incidents")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3) AND ConfigName = ?", mark, ..#MANAGER)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and IncidentManager logged no error and no warning")
}

Method TestRefusedRequest()
{
	If '..Ready() Quit
	Set a = ..Session("refused")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set log = $Parameter(..#PROBE, "LOGDIAGNOSE")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Row(a, "")
	Set error = $SYSTEM.Status.Error(5001, "The request is refused: no runner")
	Do $$$AssertStatusOK(host.Refuse(ref, error), "the handler of the diagnose key answers OK")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Cause_row.CauseCategory_row.Element_row.FixSummary_"|"_row.DecisionRef, "1|error||", "the incident holds the fallback error and no diagnosis")
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= "")_"|"_row.NoticeCount_"|"_row.ItemNoun, "open|fallback|1|7|"_..#MESSAGENOUN, "the row is noticed as a fallback and otherwise stands as it was")
	Kill row
	Do $$$AssertEquals(host.Sent.%Size(), 1, "one Notification was recorded")
	If host.Sent.%Size() = 1 {
		Set note = host.Sent.%Get(0)
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.incidentRef_"|"_slots.fallbackReason_"|"_slots.count, a_"|incident|incident.fallback|"_ref_"|error|7", "to A: a fallback notice of the incident, with the reason error")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Refused", log_ref), 1, "one Type 3 warning names the incident")
	Do $$$AssertTrue(text [ "no runner", "and holds the error: "_text)
	Set noticed = ..Row(a, ##class(OcuTalon.Data.Time).NowUtc())
	Do host.Refuse(noticed, error)
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(noticed).Fallback, 0, "a noticed incident is not written")
	Set closed = ..Row(a, "", "closed")
	Do host.Refuse(closed, error)
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(closed).Fallback, 0, "nor a closed one")
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do host.Refuse(gone, error)
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexExists(gone), 0, "and one that is gone is not made again")
	Do $$$AssertEquals(host.Sent.%Size(), 1, "and none of the three got a notice")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Refused", log)

	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Fallback = 0
	Set answer.Payload = {"outcome": "act", "causeCategory": "unknown", "cause": "zz late cause", "reasons": ["zz"], "confidence": 0.5}.%ToJSON()
	Set open = ..Row(a, "")
	Do $$$AssertStatusOK(host.Answer(open, answer), "the answer handler answers OK")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(open)
	Do $$$AssertEquals(row.Cause_"|"_row.CauseCategory_"|"_row.DecisionRef, "zz late cause|unknown|"_answer.DecisionRef, "a usable answer is written to an open incident")
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= ""), "open|no_fix|1", "which is noticed, as no fix")
	Kill row
	Do $$$AssertEquals(host.Sent.%Size() _ "|" _ $Select(host.Sent.%Size() = 2: host.Sent.%Get(1).catalogKey, 1: ""), "2|incident.noFixUnknown", "with the unknown notice")
	For each = $ListBuild(noticed, "a noticed incident"), $ListBuild(closed, "a closed one") {
		Do $$$AssertStatusOK(host.Answer($List(each, 1), answer), "the answer handler answers OK for "_$List(each, 2))
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen($List(each, 1))
		Do $$$AssertEquals(row.Cause_"|"_row.DecisionRef_"|"_row.Fallback, "||0", "and a late answer does not write "_$List(each, 2))
		Kill row
	}
	Do $$$AssertEquals(host.Sent.%Size(), 2, "nor send a notice for them")
	Set blank = ..Row(a, "")
	Do $$$AssertStatusOK(host.Answer(blank, ""), "the empty answer that follows an error answers OK")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(blank)
	Do $$$AssertEquals(row.DecisionRef_"|"_row.Fallback_"|"_row.Cause_"|"_row.NoticedAt, "|0||", "and writes and notices nothing")
	Do $$$AssertEquals(host.Sent.%Size(), 2, "and sends nothing")
}

/// The Ref of an incident row of the owner (a fixture): count 7, the code noun, NoticedAt and the state as given, and its one group (Seq 1, NoticeCount 7). The row is not kept open, so that
/// what a test reads afterwards comes from the database.
Method Row(owner As %String, noticedAt As %String, state As %String = "open") As %String [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident.OwnerRef = owner
	Set incident.Namespace = ..#SYNTHNS
	Set incident.Production = ..#SYNTH
	Set incident.State = state
	Set incident.Count = 7
	Set incident.NoticeCount = 7
	Set incident.FirstAt = "2026-10-26T10:00:00Z"
	Set incident.LastAt = "2026-10-26T10:00:30Z"
	Set incident.NoticedAt = noticedAt
	Set incident.ItemNoun = ..#MESSAGENOUN
	Do $$$AssertStatusOK(incident.%Save(), "a fixture incident is saved")
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident.Ref
	Set group.Seq = 1
	Set group.ItemName = "zzDiagnoseItem"
	Set group.ErrorPattern = "Field 'Qty' was empty"
	Set group.ErrorSummary = "Field 'Qty' was empty."
	Set group.Count = 7
	Set group.NoticeCount = 7
	Set group.FirstAt = incident.FirstAt
	Set group.LastAt = incident.LastAt
	Do $$$AssertStatusOK(group.%Save(), "and its group")
	Quit incident.Ref
}

}
