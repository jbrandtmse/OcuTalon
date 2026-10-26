Include Ensemble

/// Tests of the incident notice and of the Show-details view of a noticed incident (Story 5.8; AD-8, AD-12, AD-13, AD-15, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, over the RUNNING production: IncidentManager, Notify, WebChatOut, Decide and DiagnosisAgent are
/// items of it, so the class runs fresh (a warm stack's running job keeps its old code). The model is the CI mock: a failure whose text holds a [[mock:<name>]] marker
/// picks the scenario. They fail with the reason where OCUORDERS or demo mode is missing. A test waits at most 90 seconds for a diagnosis and 20 for the rest,
/// polling every half second (test bounds, not NFR-7). The rows, events and notifications of a test are removed after it.
///   - TestNoticeVariants: session A, which does not watch Orders (so the poller makes no incident of its own), has one batch with a real failed order of OCUORDERS
///     (diagnosis-nofix, with the header id, as Test.Watch.Diagnose does) and one with three ZZNS failures (diagnosis-unknown, invalid-reply, refusal). Each of the four
///     incidents is noticed with its catalog key and open variant (No fix: incident.noFix and no_fix; Unknown: incident.noFixUnknown, no_fix and no cause slot; Fallback:
///     incident.fallback, fallback and the reason), A has one kind-incident Notification for each, with the slots of Watch.Notice, the row's DecisionRef and no ApprovalRef, and
///     WebChatOut records one incident Delivery row for each. A's stream shows, for each incident and in Seq order, noticed, settling, diagnosing and then one incident event
///     (open, the variant, groups, evidence items and the diagnosis trace target). For the real order, evidence.sampleHeaderId is that header's id and sampleError is
///     ErrorText.Text of its real error, traceTargets.sample and firstFailure are that id in OCUORDERS and diagnosis is the incident's TraceHeaderId in OCUTALON; the
///     incidents of ZZNS, where nothing can be read, have no sample and no sample trace target but keep their evidence items;
///     and Web.Api.StateBody(A) shows each incident with the same groups, evidence and traceTargets as its event;
///   - TestInstanceNotice (U-86): sessions A and B watch Orders and C does not; an untagged no-fix failure of Orders makes one instance incident, and A and B each get one
///     Notification and one incident event, C gets neither.
Class OcuTalon.Test.Watch.Notices Extends OcuTalon.Test.Watch.Case
{

/// The namespace and the production of the incidents that SendBatch makes: nothing runs there, so the pack has no sample.
Parameter SYNTHNS = "ZZNS";

Parameter SYNTH = "Zz.Notices";

Method TestNoticeVariants()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("variants")
	If '..Fail(1) Quit
	Set failed = ..WaitFailed(1)
	Do $$$AssertEquals(failed.%Size(), 1, "one real failed order of OCUORDERS")
	If failed.%Size() < 1 Quit
	Set header = $Piece(..HeaderIds(failed), ",", 1)
	Set order = [{"item": "OrdersFromPartner", "text": "[[mock:diagnosis-nofix]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1)), "id": (header)}]
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a, order), "a failure of that order is sent")
	Set failures = []
	For marker = "diagnosis-unknown", "invalid-reply", "refusal" {
		Do failures.%Push({"item": (..Item(marker)), "text": ("[[mock:"_marker_"]] Field 'Qty' was empty"), "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))})
	}
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, failures), "one batch of three failures is sent")
	Set synth = ..WaitIncident(a, ..#SYNTH, 3)
	Set orders = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(synth.%Size()_"|"_orders.%Size(), "3|1", "four incidents: three of ZZNS and the real order's")
	If (synth.%Size() '= 3) || (orders.%Size() '= 1) Quit
	Set refs = orders.%Get(0).ref
	For i = 0:1:2 {
		Set refs = refs_","_synth.%Get(i).ref
	}
	For i = 1:1:4 {
		Set ref = $Piece(refs, ",", i)
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
		Do $$$AssertTrue(..WaitDiagnosed(ref), "incident "_i_" holds its diagnosis")
		Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and is noticed")
		Do ..WaitNotices(ref, 1)
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 4, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 4, "A's stream holds four incident events")
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(a, 4, ..#WAITINCIDENT)
	Set deliveries = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(a)
	Set kinds = ""
	For i = 1:1:deliveries.Count() {
		Set kinds = kinds_$Select(kinds = "": "", 1: ",")_deliveries.GetAt(i).Kind
	}
	Do $$$AssertEquals(kinds, "incident,incident,incident,incident", "WebChatOut recorded one incident Delivery row for each")
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(a)
	Set state = ##class(OcuTalon.Web.Api).StateBody(session)
	Set stream = ..Stream(a)
	For i = 1:1:4 {
		Set ref = $Piece(refs, ",", i)
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
		Set marker = $Select(i = 1: "diagnosis-nofix", 1: $Extract(..Group(ref).itemName, $Length(..Item("")) + 1, *))
		Set label = marker_": "
		If '$IsObject(row) {
			Do $$$AssertTrue(0, label_"the row exists")
			Continue
		}
		Set key = $Select(marker = "diagnosis-nofix": "incident.noFix", marker = "diagnosis-unknown": "incident.noFixUnknown", 1: "incident.fallback")
		Set variant = $Select(key = "incident.fallback": "fallback", 1: "no_fix")
		Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= ""), "open|"_variant_"|1", label_"noticed, open, "_variant)
		Set group = ..Group(ref).groups.%Get(0)
		Set bodies = ..NoticeBodies(ref)
		Do $$$AssertEquals(bodies.%Size(), 1, label_"A has one Notification of the incident")
		If bodies.%Size() = 1 {
			Set note = bodies.%Get(0)
			Set slots = note.slots
			Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.decisionRef_"|"_note.approvalRef, a_"|incident|"_key_"|"_row.DecisionRef_"|", label_"to A, kind incident, the key, the row's DecisionRef and no ApprovalRef")
			Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.itemNoun.one_"|"_slots.itemNoun.other, "1|"_row.FirstAt_"|"_$Select(i = 1: "order|orders", marker = "diagnosis-unknown": "invoice|invoices", 1: "message|messages"), label_"count, time and noun")
			Do $$$AssertEquals(slots.groups.%Size()_"|"_slots.groups.%Get(0).itemName_"|"_slots.groups.%Get(0).count_"|"_slots.groups.%Get(0).firstAt, "1|"_group.itemName_"|1|"_group.firstAt, label_"one group line")
			Do $$$AssertTrue(slots.groups.%Get(0).errorSummary '= "", label_"with an error summary: "_slots.groups.%Get(0).errorSummary)
			If key = "incident.noFix" Do $$$AssertEquals(slots.cause, row.Cause, label_"the cause is the row's")
			If key = "incident.noFixUnknown" Do $$$AssertEquals(slots.%IsDefined("cause"), 0, label_"an unknown cause has no cause slot")
			If key = "incident.fallback" Do $$$AssertEquals(slots.fallbackReason, row.FallbackReason, label_"the fallback reason is the row's")
			Set text = ##class(OcuTalon.Msg.Catalog).Render(key, note.slots.%ToJSON(), "phone", .sc)
			Do $$$AssertStatusOK(sc, label_"the slots render")
		}
		Set seen = ""
		Set sentEvent = ""
		Set iterator = stream.%GetIterator()
		While iterator.%GetNext(, .event) {
			If event.payload.ref '= ref Continue
			If event.type = "watch.progress" Set seen = seen_$Select(seen = "": "", 1: "|")_event.payload.stage
			If event.type = "incident" {
				Set seen = seen_$Select(seen = "": "", 1: "|")_"incident"
				Set sentEvent = event.payload
			}
		}
		Do $$$AssertEquals(seen, "noticed|settling|diagnosing|incident", label_"A's stream, in Seq order, for the incident")
		If '$IsObject(sentEvent) Continue
		Do $$$AssertEquals(sentEvent.state_"|"_sentEvent.openVariant_"|"_sentEvent.groups.%Size()_"|"_sentEvent.evidence.items.%Size(), "open|"_variant_"|1|1", label_"the event: open, the variant, one group and one evidence item")
		Do $$$AssertEquals(sentEvent.traceTargets.diagnosis.traceHeaderId_"|"_sentEvent.traceTargets.diagnosis.traceNamespace, row.TraceHeaderId_"|"_$Namespace, label_"the diagnosis trace target is the incident's own session")
		If i = 1 {
			Do $$$AssertEquals(row.SampleHeaderId_"|"_row.FirstHeaderId, header_"|"_header, label_"the row holds the real order's header id as sample and first failure")
			Do $$$AssertEquals(row.SampleError, ..#ORDERDATETEXT, label_"and the sample's error is ErrorText.Text of its real error")
			Do $$$AssertEquals(sentEvent.evidence.sampleHeaderId_"|"_sentEvent.evidence.sampleError, header_"|"_..#ORDERDATETEXT, label_"the event's evidence has them")
			Do $$$AssertEquals(sentEvent.traceTargets.sample.traceHeaderId_"|"_sentEvent.traceTargets.sample.traceNamespace, header_"|"_..#ORDERS, label_"traceTargets.sample is that id in OCUORDERS")
			Do $$$AssertEquals(sentEvent.traceTargets.firstFailure.traceHeaderId_"|"_sentEvent.traceTargets.firstFailure.traceNamespace, header_"|"_..#ORDERS, label_"and so is firstFailure")
		} Else {
			Do $$$AssertEquals(sentEvent.evidence.%IsDefined("sampleHeaderId")_"|"_sentEvent.traceTargets.%IsDefined("sample"), "0|0", label_"where nothing could be read there is no sample and no sample trace target")
			Do $$$AssertEquals(sentEvent.evidence.items.%Size(), 1, label_"but the items stay")
		}
		Set found = ""
		Set iterator = state.chat.%GetIterator()
		While iterator.%GetNext(, .item) {
			If (item.type = "incident") && (item.payload.ref = ref) Set found = item.payload
		}
		Do $$$AssertTrue($IsObject(found), label_"/state shows the incident")
		If $IsObject(found) {
			Do $$$AssertEquals(found.groups.%ToJSON()_"|"_found.evidence.%ToJSON(), sentEvent.groups.%ToJSON()_"|"_sentEvent.evidence.%ToJSON(), label_"/state has the same groups and evidence as the event")
			Do $$$AssertEquals(..Targets(found.traceTargets), ..Targets(sentEvent.traceTargets), label_"and the same trace targets (the snapshot adds each one's link)")
		}
	}
}

/// The trace targets as "<name>=<id>@<namespace>" for each of diagnosis, sample and firstFailure that is there, comma-separated. The snapshot's
/// targets also carry a link, which the event's do not.
ClassMethod Targets(targets As %DynamicObject) As %String
{
	Set text = ""
	For name = "diagnosis", "sample", "firstFailure" {
		If targets.%IsDefined(name) Set text = text_$Select(text = "": "", 1: ",")_name_"="_targets.%Get(name).traceHeaderId_"@"_targets.%Get(name).traceNamespace
	}
	Quit text
}

Method TestInstanceNotice()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("inst1")
	Set b = ..Session("inst2")
	Set c = ..Session("inst3")
	Do ..Watch(a)
	Do ..Watch(b)
	Set item = ..Item("i")
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, "instance", [{"item": (item), "text": "[[mock:diagnosis-nofix]] Field 'Qty' was empty in order 1", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))}]), "an untagged failure of Orders is sent")
	Set rows = ..WaitIncident("instance", ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one instance incident")
	If rows.%Size() '= 1 Quit
	Set ref = rows.%Get(0).ref
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and is noticed")
	Do ..WaitNotices(ref, 2)
	Set bodies = ..NoticeBodies(ref)
	Do $$$AssertEquals(bodies.%Size(), 2, "two Notifications carry its Ref")
	Set sessions = ""
	For i = 0:1:bodies.%Size() - 1 {
		Set sessions = sessions_","_bodies.%Get(i).sessionRef_","
		Do $$$AssertEquals(bodies.%Get(i).kind_"|"_bodies.%Get(i).catalogKey, "incident|incident.noFix", "Notification "_(i + 1)_" is the no-fix notice")
	}
	Do $$$AssertEquals((sessions [ (","_a_","))_(sessions [ (","_b_","))_(sessions [ (","_c_",")), "110", "to A and B, and not to C")
	For each = a, b {
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(each, "incident", 1, ..#WAITINCIDENT)
		Do $$$AssertEquals(events.%Size(), 1, "the stream of a watching session holds one incident event")
		If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.openVariant, ref_"|no_fix", "for the incident, as no_fix")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(c, "incident").%Size(), 0, "C, which does not watch Orders, gets no event")
	Hang 1
	Do $$$AssertEquals(..NoticeBodies(ref).%Size(), 2, "and no further Notification")
}

}
