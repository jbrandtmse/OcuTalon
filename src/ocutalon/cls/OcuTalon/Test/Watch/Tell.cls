/// Tests of IncidentManager.Tell and the notice step that uses it (Story 5.3, ledger entry DW-241, and Story 5.8; AD-12, AD-15, AD-32). Tell publishes an event to
/// each session that Session.Recipients gives (and, with a notification, first sends the session its copy), logs one Type 3 warning per event or per notice when
/// a publish or a send fails, and leaves the rows alone. The tests need no production and no namespace
/// but their own: they call Tell and the answer handler on a shadow instance of Test.Watch.IncidentProbe in the test process (whose SendNotice records the
/// Notifications instead of sending them), with fixture sessions, watch rows, incidents and groups of Test.Data.Fixture and of the test on a production
/// nobody else watches, and read the sessions' streams and the event log. They run warm.
///   - TestFailedPublishLeavesTheOthersTheirEvent: with another job holding the stream of the first of two recipients, the second still gets its event and
///     the first gets none, one warning that starts with LOGPUBLISH names the incident and the event type, and no warning says that the recipients could not
///     be read. With the streams of both recipients held, the event is still logged once, not once for each recipient; with both free again the next event
///     reaches both and nothing is logged. The order of the recipients is Session.Recipients' own, so the first held stream is the first of the list that it
///     gives.
///   - TestNoticeToEachRecipient: an instance incident with a group, watched by two sessions and not by a third, gets a usable answer of the category
///     partner_outage: each watcher gets one recorded Notification (kind incident, incident.noFix, the slots count, time, itemNoun, cause and groups, the row's
///     DecisionRef, no ApprovalRef) and one incident event, the third gets neither, and the row is noticed, open and no_fix;
///   - TestFailedSendLeavesTheOthersTheirNotice: with the send to the first recipient answering an error, the second still gets its Notification and both get
///     the event, one warning that starts with LOGSEND names the incident, and the row stays noticed; with both sends refused, a second incident's notice is
///     still logged once, with the first refused send's error;
///   - TestNobodyToNotice: an eval incident, and an instance incident of a watched production with the online demo on, are noticed (NoticedAt, open, no_fix) with
///     no Notification, no event and no warning.
///   - TestUnbuildableNoticeLeavesTheRowUnnoticed (QA): an answer whose notice cannot be built (an incident with no group, and one whose cause is empty, both of a
///     production that two sessions watch) is stored and then not noticed: NoticedAt stays empty, the state and open variant stay as they were, nothing is sent or published, and one Type 3 warning with
///     LOGNOTICE names the incident.
///   - TestRaisedGetsTheWithFixNotice (Story 7.2; AC 1, AC 3): a usable data-format answer with a fix records one dry run ask (the incident, repair_resend and the
///     parameters) and sends nothing; the dry run's answer (the probe's Dried) raises one request with the recorded row (kind fix, the incident, its owner,
///     IncidentManager, the dry run, the kind, the parameters and the targets as given) in the incident's trace session and sends the two watchers each one
///     incident.withFix Notification with the request's Ref and the nine slots; the row is awaiting_approval, noticed, and lists the Ref;
///   - TestNoFixRoutes (V2): a dry run with a Reason (one warning naming the incident and the reason), with no Targets (no warning), a Raise that fails, an ask
///     that cannot be sent, an error answer to the ask and a payload with no fix kind each give the two watchers incident.noFix, the row open and no_fix and noticed
///     and no RequestRefs, with the warnings of the matrix;
///   - TestSaveFailureCancelsTheRequest: when the save of the noticed row fails after Raise, the request is cancelled, nothing is sent and the row stays unnoticed,
///     with one warning;
///   - TestGoneBeforeTheDryRun: an incident that is closed, noticed or deleted when the dry run answers gets nothing raised, sent or saved and no error;
///   - TestUnbuildableWithFixSlots: a dry run whose slots cannot be built (no field, a resend below 1) raises nothing, sends nothing and leaves the row unnoticed with one
///     warning;
///   - TestAnsweredToEachRecipient (QA; AC 5): a rejected or an expired outcome of an instance incident that two sessions watch sends each watcher one answered
///     Notification (the key, the slots, the request's Ref and the incident's, no decision) and one incident event, and opens the incident with that variant.
/// The failed Recipients read has no test: Session.Recipients is called by name, so a probe cannot replace it, and the only way it answers an error is the
/// privilege check of its watchers' statement, which needs a process without %All (SET $ROLES can only add roles) and so an IRIS user made for the purpose.
/// The fixture rows are removed after each test, with their streams, and so are the warnings that these tests made.
Class OcuTalon.Test.Watch.Tell Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The parameters of the fix in the diagnosis that Diagnosis makes, and the dry run that Result gives.
Parameter PARAMETERS = "{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""YYYY-MM-DD""}";

Parameter DRYRUN = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":{""one"":""order"",""other"":""orders""}}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The streams whose lock a test took with HoldStream and has not released.
Property Held As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WatchTell", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Held = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ..DropGroups($Piece(..Refs, ",", i))
	}
	For i = 1:1:$Length(..Held, ",") {
		If $Piece(..Held, ",", i) '= "" Do ..ReleaseStream($Piece(..Held, ",", i))
	}
	Set ..Held = ""
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ..RemoveWarnings()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("WatchTell", "hold")
	Quit $$$OK
}

Method TestFailedPublishLeavesTheOthersTheirEvent()
{
	Do ..Setup("pub", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertStatusOK(sc, "the recipients of the instance incident are read")
	Do $$$AssertEquals($ListLength(recipients), 2, "two sessions watch its production")
	If $ListLength(recipients) '= 2 Quit
	Set first = $List(recipients, 1)
	Set second = $List(recipients, 2)
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "0|0", "control: neither stream has an event yet")

	Do host.Say(row, "watch.progress", ..Progress(incident, "noticed"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "1|1", "control: with both streams free, each recipient gets the event")
	Do $$$AssertEquals(..Warned(), 0, "and nothing is logged")

	Do ..HoldStream(first)
	Do host.Say(row, "watch.progress", ..Progress(incident, "settling"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "1|2", "with the first recipient's stream held, the second still gets the event and the first does not")
	Do $$$AssertEquals(..Warned(.text), 1, "one warning says that the event could not be published")
	Do $$$AssertTrue($Find(text, incident) && $Find(text, "(watch.progress)"), "naming the incident and the event type: "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, , "Tell", $Parameter(..#PROBE, "LOGTELL")), 0, "and none says that the recipients could not be read")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT FailureCount FROM OcuTalon_Data.Incident WHERE Ref = ?", incident)
	Do $$$AssertEquals($Select(rs.%Next(): rs.%GetData(1), 1: "gone"), 3, "the stored incident row stands as it was (read from the table, as the held row object would show its old values)")

	Do ..HoldStream(second)
	Set before = ..Warned()
	Do host.Say(row, "incident", ##class(OcuTalon.Live.Payload.Incident).FromRow(row))
	Do $$$AssertEquals(..Events(first, "incident")_"|"_..Events(second, "incident"), "0|0", "with both streams held, nobody gets the incident event")
	Do $$$AssertEquals(..Warned() - before, 1, "and it is logged once, not once for each recipient")

	Do ..ReleaseStream(first)
	Do ..ReleaseStream(second)
	Set before = ..Warned()
	Do host.Say(row, "watch.progress", ..Progress(incident, "diagnosing"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "2|3", "with the streams free again, the next event reaches both")
	Do $$$AssertEquals(..Warned() - before, 0, "and logs nothing")
}

Method TestNoticeToEachRecipient()
{
	Do ..Setup("note", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set c = ##class(OcuTalon.Test.Data.Fixture).Session("zztell"_..Number_"notec")
	Set ..Refs = ..Refs_","_c
	Do ..Group(incident, 1)
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertEquals($ListLength(recipients), 2, "two sessions watch the production, and the third does not")
	Set answer = ..Diagnosis("partner_outage", "zz outage")
	Do $$$AssertStatusOK(host.Answer(incident, answer), "the answer is handled")
	Do $$$AssertEquals($IsObject(host.Sent) && (host.Sent.%Size() = 2), 1, "two Notifications are recorded")
	If '$IsObject(host.Sent) Quit
	Set sessions = ""
	For i = 0:1:host.Sent.%Size() - 1 {
		Set note = host.Sent.%Get(i)
		Set sessions = sessions_$Select(sessions = "": "", 1: ",")_note.sessionRef
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.incidentRef_"|"_note.decisionRef_"|"_note.approvalRef, "incident|incident.noFix|"_incident_"|"_answer.DecisionRef_"|", "Notification "_(i + 1)_": kind, key, incident, decision and no approval")
		Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.cause_"|"_slots.itemNoun.other_"|"_slots.groups.%Size()_"|"_slots.groups.%Get(0).itemName_"|"_slots.groups.%Get(0).count, "3|2030-01-01T09:00:00Z|zz outage|messages|1|ZzItem|3", "its slots")
	}
	Do $$$AssertEquals(sessions, $ListToString(recipients), "one to each watcher, in the order of Session.Recipients")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident")_"|"_..Events(c, "incident"), "1|1|0", "each watcher gets one incident event, and the third none")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.state_"|"_payload.openVariant_"|"_payload.groups.%Size()_"|"_payload.evidence.items.%Size(), incident_"|open|no_fix|1|1", "the event is the noticed incident with its groups and evidence")
	}
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= ""), "open|no_fix|1", "the row is noticed, open and no_fix")
	Do $$$AssertEquals(..Warned(), 0, "and nothing was logged")
}

Method TestFailedSendLeavesTheOthersTheirNotice()
{
	Do ..Setup("send", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Group(incident, 1)
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertEquals($ListLength(recipients), 2, "two sessions watch the production")
	If $ListLength(recipients) '= 2 Quit
	Set first = $List(recipients, 1)
	Set second = $List(recipients, 2)
	Set host.FailFor = first
	Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("partner_outage", "zz outage")), "the answer is handled")
	Do $$$AssertEquals($IsObject(host.Sent) && (host.Sent.%Size() = 2), 1, "both sends were tried: the failed one did not stop the loop")
	If $IsObject(host.Sent) && (host.Sent.%Size() = 2) Do $$$AssertEquals(host.Sent.%Get(0).sessionRef_"|"_host.Sent.%Get(1).sessionRef, first_"|"_second, "the first was tried first and the second after it")
	Do $$$AssertEquals(..Events(first, "incident")_"|"_..Events(second, "incident"), "1|1", "both sessions get the event")
	Do $$$AssertEquals(..Warned(.text), 1, "one warning says that the notice could not be sent")
	Do $$$AssertTrue($Find(text, $Parameter(..#PROBE, "LOGSEND")_incident) && $Find(text, first), "naming the incident and the refused send: "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, , "Tell", $Parameter(..#PROBE, "LOGTELL")), 0, "and none says that the recipients could not be read")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= ""), "open|no_fix|1", "the row stays noticed")
	Set again = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", "Zz.Tell"_..Number_".send")
	Set ..Refs = ..Refs_","_again
	Do ..Group(again, 1)
	Set host.FailFor = first_","_second
	Set before = ..Warned()
	Do $$$AssertStatusOK(host.Answer(again, ..Diagnosis("partner_outage", "zz outage")), "a second incident's answer is handled with both sends refused")
	Do $$$AssertEquals(..Warned(.text) - before, 1, "one warning for that notice, not one for each refused send")
	Do $$$AssertTrue($Find(text, again) && $Find(text, first) && '$Find(text, second), "naming the incident and the first refused send only: "_text)
}

Method TestNobodyToNotice()
{
	Do ..Setup("nobody", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set eval = ##class(OcuTalon.Test.Data.Fixture).Incident("eval", "", "ZZNS", "Zz.Tell"_..Number_"nobodyeval")
	Set ..Refs = ..Refs_","_eval
	Do ..Group(eval, 1)
	Do $$$AssertStatusOK(host.Answer(eval, ..Diagnosis("partner_outage", "zz outage")), "the answer for the eval incident is handled")
	Set noticed = ##class(OcuTalon.Data.Incident).RefIndexOpen(eval)
	Do $$$AssertEquals(noticed.State_"|"_noticed.OpenVariant_"|"_(noticed.NoticedAt '= ""), "open|no_fix|1", "the eval incident is noticed")
	Kill noticed
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ..Group(incident, 1)
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)), 0, "with the online demo on, an instance incident has no recipients")
	Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("partner_outage", "zz outage")), "the answer for the instance incident is handled")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= ""), "open|no_fix|1", "the instance incident is noticed")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "nothing was sent")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "0|0", "nothing was published")
	Set warned = 0
	For method = "Tell", "Notice", "Deliver" {
		Set warned = warned + ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, , method, "IncidentManager could not")
	}
	Do $$$AssertEquals(warned, 0, "and nothing was logged")
}

Method TestUnbuildableNoticeLeavesTheRowUnnoticed()
{
	Do ..Setup("unbuilt", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set log = $Parameter(..#PROBE, "LOGNOTICE")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)), 2, "control: two sessions watch the production, so a notice that could be built would be sent")
	Do $$$AssertEquals(##class(OcuTalon.Data.FailureGroup).OfIncident(incident).Count(), 0, "the incident has no group")
	Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("partner_outage", "zz outage")), "the answer is handled")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.Cause_"|"_row.CauseCategory, "zz outage|partner_outage", "the diagnosis is stored")
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.NoticedAt, "open|fix|", "but the incident is not noticed: state and variant stand and NoticedAt is empty")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "nothing was sent")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "0|0", "nothing was published")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Notice", log_incident), 1, "one Type 3 warning names the incident")

	Set other = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", "Zz.Tell"_..Number_".unbuilt")
	Set ..Refs = ..Refs_","_other
	Do ..Group(other, 1)
	Do $$$AssertStatusOK(host.Answer(other, ..Diagnosis("partner_outage", "")), "the answer with an empty cause is handled")
	Set noticed = ##class(OcuTalon.Data.Incident).RefIndexOpen(other)
	Do $$$AssertEquals(noticed.State_"|"_noticed.OpenVariant_"|"_noticed.NoticedAt, "open|fix|", "an empty cause is not noticed either")
	Kill noticed
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Notice", log_other), 1, "with one warning naming that incident")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "and nothing was sent to the two sessions that watch its production")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "0|0", "nor published")
}

Method TestRaisedGetsTheWithFixNotice()
{
	Do ..Setup("raised", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Group(incident, 1)
	Set row.TraceHeaderId = 4242
	Do $$$AssertStatusOK(row.%Save(), "the incident has a trace session")
	Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", 1)), "the answer is handled")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "one dry run is asked")
	If '$IsObject(host.DryRuns) Quit
	Set ask = host.DryRuns.%Get(0)
	Do $$$AssertEquals(ask.incidentRef_"|"_ask.fixKind_"|"_ask.parameters, incident_"|repair_resend|"_..#PARAMETERS, "for the incident, the kind and the parameters of the diagnosis")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0)_"|"_$Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), "0|0", "and nothing is sent or raised before the answer")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.NoticedAt_"|"_row.RequestRefs, "open||", "the incident is still open and unnoticed")
	Do $$$AssertStatusOK(host.Dried(incident, ..Ask(ask), ..Result(incident)), "the answer to the dry run is handled")
	Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), 1, "one request is raised")
	If '$IsObject(host.Raised) Quit
	Set raised = host.Raised.%Get(0)
	Do $$$AssertEquals(raised.kind_"|"_raised.incidentRef_"|"_raised.ownerRef_"|"_raised.resultTarget_"|"_raised.traceRef, "fix|"_incident_"|instance|IncidentManager|", "its kind, incident, owner, result target and no trace Ref (the waiter has no SuperSession)")
	Do $$$AssertEquals(raised.fixKind_"|"_raised.fixParameters_"|"_raised.fixTargets, "repair_resend|"_..#PARAMETERS_"|101,102,103", "the kind, the parameters and the targets as given")
	Do $$$AssertEquals(raised.dryRun, ..#DRYRUN, "and the dry run as given")
	Do $$$AssertEquals(raised.sessionId, 4242, "in the incident's trace session")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 2, "two Notifications are sent")
	If '$IsObject(host.Sent) Quit
	Set sessions = ""
	For i = 0:1:host.Sent.%Size() - 1 {
		Set note = host.Sent.%Get(i)
		Set sessions = sessions_$Select(sessions = "": "", 1: ",")_note.sessionRef
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.incidentRef_"|"_note.approvalRef, "incident|incident.withFix|"_incident_"|"_$Parameter(..#PROBE, "FIXTUREREF"), "Notification "_(i + 1)_": kind, key, incident and the request's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Case).SortedKeys(slots), "after,before,cause,count,field,fixSummary,itemNoun,resendCount,time", "its nine slots")
		Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.cause_"|"_slots.field_"|"_slots.before_"|"_slots.after_"|"_slots.resendCount_"|"_slots.itemNoun.other, "3|2030-01-01T09:00:00Z|zz cause|OrderDate|10/24/2026|2026-10-24|3|orders", "and their values")
	}
	Do $$$AssertEquals(sessions, $ListToString(##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)), "one to each watcher")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= "")_"|"_row.RequestRefs, "awaiting_approval||1|"_$Parameter(..#PROBE, "FIXTUREREF"), "the row is awaiting_approval, noticed and lists the request")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", "each watcher gets one incident event")
	Do $$$AssertEquals(..Logged(.text), 0, "and nothing was logged: "_text)
}

Method TestNoFixRoutes()
{
	Set cases = $ListBuild("reason", "targets", "raise", "ask", "error", "kind")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Setup("nofix"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Group(incident, 1)
		Set host.FailDryRun = (case = "ask")
		Set host.FailRaise = (case = "raise")
		Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", $Select(case = "kind": 2, 1: 1))), case_": the answer is handled")
		Set asked = $Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)
		Do $$$AssertEquals(asked, $Select(case = "kind": 0, 1: 1), case_": the dry run is asked once, unless the diagnosis names no kind")
		Set result = ..Result(incident)
		If case = "reason" {
			Set result.Reason = "The failed orders are of another scope."
			Set result.Targets = ""
			Set result.DryRun = ""
		}
		If case = "targets" Set result.Targets = ""
		If (case = "reason") || (case = "targets") || (case = "raise") {
			Do $$$AssertStatusOK(host.Dried(incident, ..Ask(host.DryRuns.%Get(0)), result), case_": the answer is handled")
		} ElseIf case = "error" {
			Do $$$AssertStatusOK(host.Undried(incident, $SYSTEM.Status.Error(5001, "The executor refused the dry run")), case_": the error answer is handled")
		}
		Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), $Select(case = "raise": 1, 1: 0), case_": a request is only attempted when the dry run was usable")
		Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 2, case_": two Notifications are sent")
		If $IsObject(host.Sent) && (host.Sent.%Size() = 2) {
			Set note = host.Sent.%Get(0)
			Set slots = {}.%FromJSON(note.slots)
			Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_slots.cause_"|"_slots.groups.%Size(), "incident|incident.noFix||zz cause|1", case_": the no-fix notice, with no request")
		}
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_(row.NoticedAt '= "")_"|"_row.RequestRefs, "open|no_fix|1|", case_": the row is open, no_fix and noticed, with no request")
		Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", case_": each watcher gets one incident event")
		Set warned = ..Logged(.text)
		Do $$$AssertEquals(warned, $Select(case = "targets": 0, 1: 1), case_": the Type 3 warnings: "_text)
		If case = "reason" Do $$$AssertTrue($Find(text, incident) && $Find(text, "another scope"), "which names the incident and the reason: "_text)
		Do ..RemoveWarnings()
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
		Do ..DropAll()
	}
}

Method TestSaveFailureCancelsTheRequest()
{
	Do ..Setup("cancel", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Group(incident, 1)
	Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", 1)), "the answer is handled")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "one dry run is asked")
	If '$IsObject(host.DryRuns) Quit
	Set host.FailMove = 1
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(host.Dried(incident, ..Ask(host.DryRuns.%Get(0)), ..Result(incident)), "the answer to the dry run is handled")
	Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), 1, "the request was raised")
	Do $$$AssertEquals($Select($IsObject(host.Cancelled): host.Cancelled.%Size(), 1: 0), 1, "and one request is cancelled")
	If $IsObject(host.Cancelled) && (host.Cancelled.%Size() = 1) Do $$$AssertEquals(host.Cancelled.%Get(0), host.RaiseRef, "the one that was raised")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "nothing is sent")
	Kill row
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.NoticedAt_"|"_row.RequestRefs, "open||", "the incident stays open and unnoticed, with no request listed")
	Do $$$AssertEquals(..Logged(.text), 1, "one Type 3 warning: "_text)
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "0|0", "nothing was published")
}

Method TestGoneBeforeTheDryRun()
{
	For case = "closed", "noticed", "deleted" {
		Do ..Setup("gone"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Group(incident, 1)
		Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", 1)), case_": the answer is handled")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, case_": one dry run is asked")
		If '$IsObject(host.DryRuns) Quit
		Set ask = ..Ask(host.DryRuns.%Get(0))
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		If case = "closed" Set row.State = "closed"
		If case = "noticed" Set row.NoticedAt = "2030-01-01T10:00:00Z"
		If case '= "deleted" Do $$$AssertStatusOK(row.%Save(), case_": the row is changed")
		If case = "deleted" {
			Do ..DropGroups(incident)
			Do $$$AssertStatusOK(##class(OcuTalon.Data.Incident).%DeleteId(row.%Id()), case_": the row is deleted")
		}
		Do $$$AssertStatusOK(host.Dried(incident, ask, ..Result(incident)), case_": the answer to the dry run is handled without an error")
		Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0)_"|"_$Select($IsObject(host.Cancelled): host.Cancelled.%Size(), 1: 0), "0|0|0", case_": nothing is raised, sent or cancelled")
		Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "0|0", case_": nothing was published")
		Do $$$AssertEquals(..Logged(.text), 0, case_": nothing was logged")
		Kill row
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
		Do ..DropAll()
	}
}

Method TestUnbuildableWithFixSlots()
{
	Set cases = $ListBuild("field", "resend")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Setup("slots"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Group(incident, 1)
		Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", 1)), case_": the answer is handled")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, case_": one dry run is asked")
		If '$IsObject(host.DryRuns) Quit
		Set result = ..Result(incident)
		Set dryRun = {}.%FromJSON(result.DryRun)
		If case = "field" Do dryRun.%Remove("field")
		If case = "resend" Do dryRun.%Set("resend", 0, "number")
		Set result.DryRun = dryRun.%ToJSON()
		Do $$$AssertStatusOK(host.Dried(incident, ..Ask(host.DryRuns.%Get(0)), result), case_": the answer to the dry run is handled")
		Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), "0|0", case_": nothing is raised or sent")
		Kill row
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(row.State_"|"_row.NoticedAt_"|"_row.RequestRefs, "open||", case_": the row stays open and unnoticed")
		Do $$$AssertEquals(..Logged(.text), 1, case_": one Type 3 warning: "_text)
		Do ..RemoveWarnings()
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
		Do ..DropAll()
	}
}

/// The answered Notification goes to every recipient of an instance incident, as the incident event does (Story 7.2; AC 5): a rejected or an expired request of
/// an instance incident that two sessions watch sends each watcher one answered Notification with the request's Ref and the incident's, and one incident event,
/// and the row is open with the variant. A session-owned incident has one recipient (Test.Watch.Lifecycle), so only an instance incident shows the copy per recipient.
Method TestAnsweredToEachRecipient()
{
	Set cases = $ListBuild("rejected|answered.rejected|{""channel"":""web"",""time"":""2030-01-01T10:00:00Z""}", "expired|answered.expired|{""time"":""2030-01-02T09:00:00Z""}")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set outcome = $Piece(case, "|", 1)
		Do ..Setup("answered"_outcome, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Group(incident, 1)
		Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident, outcome, , {"AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"})
		Set ..Refs = ..Refs_","_request
		Set row.State = "awaiting_approval"
		Set row.NoticedAt = "2030-01-01T10:00:00Z"
		Set row.RequestRefs = request
		Do $$$AssertStatusOK(row.%Save(), outcome_": the incident is awaiting approval and lists the request")
		Kill row
		Set message = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
		Set message.ApprovalRef = request
		Set message.IncidentRef = incident
		Set message.Outcome = outcome
		Set response = ""
		Do $$$AssertStatusOK(host.OnRequest(message, .response), outcome_": the outcome is handled")
		Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 2, outcome_": two Notifications are sent, one for each watcher")
		If $IsObject(host.Sent) && (host.Sent.%Size() = 2) {
			Set sessions = ""
			For i = 0:1:1 {
				Set note = host.Sent.%Get(i)
				Set sessions = sessions_$Select(sessions = "": "", 1: ",")_note.sessionRef
				Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.decisionRef_"|"_note.slots, "answered|"_$Piece(case, "|", 2)_"|"_request_"|"_incident_"||"_$Piece(case, "|", 3), outcome_": Notification "_(i + 1)_": kind, key, the request's Ref, the incident's, no decision and the slots")
			}
			Do $$$AssertEquals(sessions, $ListToString(##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)), outcome_": one to each watcher")
		}
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(row.State_"|"_row.OpenVariant, "open|"_outcome, outcome_": the incident is open with that variant")
		Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", outcome_": each watcher gets one incident event")
		Do $$$AssertEquals(..Logged(.text), 0, outcome_": nothing was logged: "_text)
		Kill row
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
		Do ..DropAll()
	}
}

/// --- helpers ---
/// A failure group (Seq, one failure group that settled with the incident's NoticeCount) of the incident, saved. The tests delete it in OnAfterOneTest.
Method Group(incident As %String, seq As %Integer)
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = seq
	Set group.ItemName = "ZzItem"
	Set group.ErrorPattern = "Field 'Qty' was empty"
	Set group.ErrorSummary = "Field 'Qty' was empty."
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = "2030-01-01T09:00:00Z"
	Set group.LastAt = "2030-01-01T09:30:00Z"
	Do $$$AssertStatusOK(group.%Save(), "a group of the incident is saved")
}

/// Deletes the failure groups of the incident.
ClassMethod DropGroups(incident As %String)
{
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident)
	For i = 1:1:groups.Count() {
		Do ##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(i).%Id())
	}
}

/// A usable answer of Decide with a diagnosis of the category and cause, and no fix, or, with fix 1, the repair_resend fix of ..#PARAMETERS and a fix summary, or,
/// with fix 2, a data-format diagnosis whose fix kind is empty.
ClassMethod Diagnosis(category As %String, cause As %String, fix As %Integer = 0) As OcuTalon.Bridge.Msg.DecisionResponse
{
	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Fallback = 0
	Set payload = {"outcome": "act", "causeCategory": (category), "cause": (cause), "reasons": ["zz"], "confidence": 0.5}
	If fix {
		Do payload.%Set("fixSummary", "rewrite the order date")
		Do payload.%Set("itemNoun", {"one": "order", "other": "orders"})
		If fix = 1 {
			Do payload.%Set("fixKind", "repair_resend")
			Do payload.%Set("fixParameters", {}.%FromJSON(..#PARAMETERS))
		}
	}
	Set answer.Payload = payload.%ToJSON()
	Quit answer
}

/// The DryRun that the probe recorded (a dynamic object {incidentRef, fixKind, parameters}), as the request message that the framework hands back.
ClassMethod Ask(recorded As %DynamicObject) As OcuTalon.Fix.Msg.DryRun
{
	Set ask = ##class(OcuTalon.Fix.Msg.DryRun).%New()
	Set ask.IncidentRef = recorded.incidentRef
	Set ask.FixKind = recorded.fixKind
	Set ask.Parameters = recorded.parameters
	Quit ask
}

/// A usable answer of FixExecutor for the incident: three targets and the dry run of ..#DRYRUN.
ClassMethod Result(incident As %String) As OcuTalon.Fix.Msg.DryRunResult
{
	Set result = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set result.IncidentRef = incident
	Set result.Targets = "101,102,103"
	Set result.DryRun = ..#DRYRUN
	Quit result
}

/// The number of the Type 3 warnings that start "IncidentManager could not" and that this process (the probe's shadow instance) logged since the test began,
/// whichever method logged them (text is the newest one's).
Method Logged(Output text As %String) As %Integer
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Job = ? AND Text %STARTSWITH ? ORDER BY ID", ..LogMark, $Job, "IncidentManager could not")
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

/// Deletes the failure groups of the test's incidents and forgets its fixture Refs, so that a test that sets up more than once starts clean each time (the caller
/// has removed the fixture rows and their streams with Fixture.Clean first).
Method DropAll()
{
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ..DropGroups($Piece(..Refs, ",", i))
	}
	Set ..Refs = ""
}

/// Two fixture sessions a and b that watch a production of this test, and an unnoticed instance incident of the production (its Ref, and the row as an
/// object). The name keeps the productions of the tests apart.
Method Setup(name As %String, Output a As %String, Output b As %String, Output incident As %String, Output row As OcuTalon.Data.Incident)
{
	Set production = "Zz.Tell"_..Number_"."_name
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zztell"_..Number_name_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zztell"_..Number_name_"b")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_a_","_b
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set ..Refs = ..Refs_","_incident
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertTrue($IsObject(row), "the fixture incident exists")
}

/// A shadow instance of the probe, in this process, as Test.Watch.Poller makes one of its probe.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A watch.progress payload.
ClassMethod Progress(ref As %String, stage As %String) As OcuTalon.Live.Payload.WatchProgress
{
	Set payload = ##class(OcuTalon.Live.Payload.WatchProgress).%New()
	Set payload.Ref = ref
	Set payload.Stage = stage
	Quit payload
}

/// The number of events of the type on the session's stream.
Method Events(session As %String, type As %String = "watch.progress") As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, type).%Size()
}

/// The number of the warnings that Tell logged since the test began (text is the newest one's), of both kinds.
Method Warned(Output text As %String) As %Integer
{
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Tell", "IncidentManager could not")
	Quit count
}

/// Removes the warnings that the tests of this class made.
Method RemoveWarnings()
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Tell", "IncidentManager could not")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Notice", $Parameter(..#PROBE, "LOGNOTICE"))
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Job = ? AND Text %STARTSWITH ?", ..LogMark, $Job, "IncidentManager could not")
}

/// Another job takes the stream's lock and holds it until ReleaseStream; this returns once the job holds it.
Method HoldStream(stream As %String)
{
	Kill ^OcuTalonTest("WatchTell", "hold", stream)
	Job ##class(OcuTalon.Test.Watch.Tell).Hold(stream)
	Do ..WaitFor($Name(^OcuTalonTest("WatchTell", "hold", stream, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("WatchTell", "hold", stream, "ready")), 1, "another job holds the lock of the stream "_stream)
	Set ..Held = ..Held_$Select(..Held = "": "", 1: ",")_stream
}

/// Lets the job that HoldStream started release the stream's lock, and returns once it has.
Method ReleaseStream(stream As %String)
{
	If '$Data(^OcuTalonTest("WatchTell", "hold", stream)) || $Get(^OcuTalonTest("WatchTell", "hold", stream, "done")) Quit
	Set ^OcuTalonTest("WatchTell", "hold", stream, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("WatchTell", "hold", stream, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("WatchTell", "hold", stream, "done")), 1, "the job lets go of the stream "_stream)
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer)
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The job body of HoldStream: holds the stream's lock until released, then ends.
ClassMethod Hold(stream As %String)
{
	Lock +^OcuTalonP.LiveEventC(stream):5
	If '$Test Quit
	Set ^OcuTalonTest("WatchTell", "hold", stream, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("WatchTell", "hold", stream, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Lock -^OcuTalonP.LiveEventC(stream)
	Set ^OcuTalonTest("WatchTell", "hold", stream, "done") = 1
}

}
