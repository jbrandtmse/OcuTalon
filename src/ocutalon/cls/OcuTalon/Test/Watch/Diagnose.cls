Include Ensemble

/// Tests of the diagnosis that IncidentManager starts at the settle end (Story 5.4; AD-5, AD-6, AD-8, AD-12, AD-15, AD-26, AD-30, AD-31). THEY RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, over the RUNNING production: IncidentManager, Decide and DiagnosisAgent are items of it, so the class
/// runs fresh (a warm stack's running job keeps its old code). The model is the CI mock: a failure that carries a [[mock:<name>]] marker in its error text reaches the
/// mock in the pack's errorPattern, so the text picks the scenario. They fail with the reason where OCUORDERS or demo mode is missing. A test waits at most 90 seconds
/// for a diagnosis, polling every half second (a test bound, not NFR-7). The rows, events and decisions of a test are removed after it.
///   - TestDemoDiagnosis (rows Demo and What the model saw): session A watches Orders and 50 failing orders tagged with A become an incident whose stream gets
///     noticed, settling and diagnosing in that order; Decide records one diagnose decision for the incident in the incident's own trace session; the row holds the
///     scenario's diagnosis, the noun order/orders, no fallback and the decision's Ref, and NoticedAt is still empty with no Notification and no incident event;
///     the first model request holds the pack, the second the result of read_failed_messages built from the real failed orders;
///   - TestDiagnosisVariants (rows No fix, Unknown, Invalid / refusal): one batch of four failures whose texts hold the markers diagnosis-nofix,
///     diagnosis-unknown, invalid-reply and refusal gives four incidents that settle together: partner_outage without a fix and with the noun message/messages,
///     unknown without a fix and with the diagnosis's own noun (invoice/invoices), and two fallbacks (invalid, refusal) with no cause, category, element or fix, the code noun and the fallback decision's Ref;
///     beside them, a failure of a real failed order of OCUORDERS whose text holds invalid-reply gives a fallback whose code noun is that of the sample's body
///     class, order/orders;
///   - TestGoneBeforeTheAnswer: an incident deleted after `diagnosing` while the delayed reply (diagnosis-late) is on its way gets no row back and no error;
///   - TestRefusedRequest: the error handler of the diagnose request (through Test.Watch.IncidentProbe, a shadow instance in the test process) stores the fallback
///     error with one Type 3 warning and leaves the row otherwise as it was; an incident that is noticed, closed or gone is not written. The answer handler
///     (the probe's Answer) writes a usable answer to an open incident, and neither to a noticed nor to a closed one, and the empty answer that follows an
///     error writes nothing.
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
		Do $$$AssertEquals(row.NoticedAt_"|"_row.State_"|"_row.OpenVariant, "|open|", "NoticedAt is empty and the state is as the waiter left it")
		Do $$$AssertEquals(row.NoticeCount, 50, "NoticeCount is the 50 failures")
	}
	Do $$$AssertEquals(..Notifications(ref), 0, "no notification carries the incident's Ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size(), 0, "and no incident event was published")
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).Headers(rows.%Get(0).traceHeaderId, "IncidentManager")
	Do $$$AssertTrue(steps.%Size() > 0, "the waiter's session holds the messages it sent")
	Set sent = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set sent = sent _ $ListBuild(header.target)
	}
	Do $$$AssertEquals($ListFind(sent, "Decide") > 0, 1, "among them the request to Decide")
	Do $$$AssertEquals($ListFind(sent, "OutcomeRouter"), 0, "and none to OutcomeRouter")

	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = []
	Set firstAt = $Select($IsObject(row): row.FirstAt, 1: "")
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && $Find(entry.%ToJSON(), "ocutalon.evidencePack/1") && (firstAt '= "") && $Find(entry.%ToJSON(), firstAt) Do requests.%Push(entry)
	}
	Do $$$AssertEquals(requests.%Size(), 2, "the diagnosis made two model requests")
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

Method TestDiagnosisVariants()
{
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
		Do $$$AssertEquals(row.NoticedAt, "", marker_": NoticedAt is empty")
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
	If $IsObject(decision) {
		Set end = $ZHorolog + 40
		For {
			Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(decision.TraceSessionId), 2, "Decide", ..#MANAGER)
			Set handled = 0
			For i = 0:1:answers.%Size() - 1 {
				If answers.%Get(i).status = $$$eMessageStatusCompleted Set handled = handled + 1
			}
			If handled || ($ZHorolog > end) Quit
			Hang 0.5
		}
		Do $$$AssertTrue(handled, "and IncidentManager handled the answer")
	}
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
	Do $$$AssertEquals(row.State_"|"_row.NoticedAt_"|"_row.NoticeCount_"|"_row.ItemNoun, "open||7|"_..#MESSAGENOUN, "the row stands as it was")
	Kill row
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
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Refused", log)

	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Fallback = 0
	Set answer.Payload = {"outcome": "act", "causeCategory": "unknown", "cause": "zz late cause", "reasons": ["zz"], "confidence": 0.5}.%ToJSON()
	Set open = ..Row(a, "")
	Do $$$AssertStatusOK(host.Answer(open, answer), "the answer handler answers OK")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(open)
	Do $$$AssertEquals(row.Cause_"|"_row.CauseCategory_"|"_row.DecisionRef, "zz late cause|unknown|"_answer.DecisionRef, "a usable answer is written to an open incident")
	Kill row
	For each = $ListBuild(noticed, "a noticed incident"), $ListBuild(closed, "a closed one") {
		Do $$$AssertStatusOK(host.Answer($List(each, 1), answer), "the answer handler answers OK for "_$List(each, 2))
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen($List(each, 1))
		Do $$$AssertEquals(row.Cause_"|"_row.DecisionRef_"|"_row.Fallback, "||0", "and a late answer does not write "_$List(each, 2))
		Kill row
	}
	Set blank = ..Row(a, "")
	Do $$$AssertStatusOK(host.Answer(blank, ""), "the empty answer that follows an error answers OK")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(blank)
	Do $$$AssertEquals(row.DecisionRef_"|"_row.Fallback_"|"_row.Cause, "|0|", "and writes nothing")
}

/// The Ref of an incident row of the owner (a fixture): count 7, the code noun, NoticedAt and the state as given. The row is not kept open, so that
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
	Set incident.NoticedAt = noticedAt
	Set incident.ItemNoun = ..#MESSAGENOUN
	Do $$$AssertStatusOK(incident.%Save(), "a fixture incident is saved")
	Quit incident.Ref
}

}
