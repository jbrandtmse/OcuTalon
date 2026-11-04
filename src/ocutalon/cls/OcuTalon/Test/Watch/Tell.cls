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
///   - Later requests (Story 7.6; AC 1 to AC 3, AC 6), on the probe's Batch, Wake, LaterDried and LaterUndried over a noticed incident with its first request R1
///     (Noticed: Seen h101 to h103, AskedTo h103, failure times two minutes ago, so the settle rule has ended):
///     TestLaterRequestToEachWatcher (two later failures: the count and the event at once, one waiter in the trace session, one ask of R1's kind and parameters
///     with the later key and the moved marks saved before the send, one request over its window with an approval Notification for each watcher), TestLaterRequestStates (resolved
///     becomes awaiting_approval, fixing stays, every open variant only counts), TestOneAskAtATime (a round that settles during another's ask re-checks after the
///     quiet time and then asks only its own window, with its own time), TestStragglersOfTheFirstAsk (failures after the first ask: no waiter until the raise
///     route starts one; the no-fix route clears LaterSince), TestStillGathering (one waiter for a round and an alarm of the seconds that are left after the newest
///     failure), TestLaterWakeEnds (a wake that ends the waiter: an incident that went open, one that is gone, a window with no new key), TestLaterNoRequestRoutes
///     (V2: every refused, failed, dropped and gone row), TestSaveFailureCancelsTheLaterRequest and TestFailedLaterRoundRejoinsTheNextRound (a round that fails
///     after its marks moved sends and raises nothing and puts the marks back, so its failures are in the next round's window; a judged dry run keeps them).
/// The failed Recipients read has no test: Session.Recipients is called by name, so a probe cannot replace it, and the only way it answers an error is the
/// privilege check of its watchers' statement, which needs a process without %All (SET $ROLES can only add roles) and so an IRIS user made for the purpose.
/// The fixture rows are removed after each test, with their streams, and so are the warnings that these tests made.
Class OcuTalon.Test.Watch.Tell Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The parameters of the fix in the diagnosis that Diagnosis makes, and the dry run that Result gives.
Parameter PARAMETERS = "{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""YYYY-MM-DD""}";

Parameter DRYRUN = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":{""one"":""order"",""other"":""orders""}}";

/// The dry run that LaterResult gives: the two failures of a later round.
Parameter LATERDRYRUN = "{""affected"":2,""resend"":2,""leftOut"":0,""field"":""OrderDate"",""before"":""10/25/2026"",""after"":""2026-10-25"",""itemNoun"":{""one"":""order"",""other"":""orders""}}";

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

/// A later round of an incident that awaits approval, on the probe (Story 7.6; AC 1, AC 2, AC 3; the matrix row "Later request, awaiting"): two same-cause failures
/// join an incident whose request R1 holds three targets. At once the count and the event move (R1, NoticeCount and the state do not), LaterSince is the first new
/// failure's time and one later waiter is started in the incident's trace session. When the waiter wakes after the settle, the marks move, AskingSince takes the
/// round's time and one dry run goes out with the later key, for the kind and the parameters of R1. The answer raises one request of its own, over its window only,
/// appended to RequestRefs, and each watcher gets one approval Notification (incident.laterRequest, the request's Ref, the round's count and time) and one more
/// incident event; NoticedAt and the state stand, LaterSince and AskingSince are empty, and nothing is logged.
Method TestLaterRequestToEachWatcher()
{
	Do ..Setup("later", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Kill row
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set level = $TLevel
	Set r1 = ..Noticed(incident)
	Set first = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
	Set second = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-118)
	Set noticedAt = ..Row(incident).noticedAt
	Do $$$AssertStatusOK(..Join(host, incident, "104,105", first_","_second), "the batch of two later failures is handled")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.count_"|"_now.noticeCount_"|"_now.state_"|"_now.requestRefs_"|"_now.laterSince_"|"_now.askingSince, "5|3|awaiting_approval|"_r1_"|"_first_"|", "the count moves; NoticeCount, the state and the requests do not; LaterSince is the first new failure's time")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", "each watcher gets the one incident event with the new count")
	Do $$$AssertEquals(..Started(host), incident_"@4242", "one later waiter is started, in the incident's trace session")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), "0|0", "and nothing is asked or sent yet")
	Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(r1)
	Do $$$AssertEquals(request.FixTargets_"|"_request.State_"|"_(request.DryRun = ..#DRYRUN), "101,102,103|pending|1", "R1 is as it was")
	Kill request

	Do $$$AssertStatusOK(host.Wake(incident), "the waiter wakes, the settle is over")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "one dry run is asked")
	If '$IsObject(host.DryRuns) || (host.DryRuns.%Size() '= 1) Quit
	Set ask = host.DryRuns.%Get(0)
	Do $$$AssertEquals(ask.incidentRef_"|"_ask.fixKind_"|"_ask.parameters_"|"_ask.key, incident_"|repair_resend|"_..#PARAMETERS_"|laterDryRun", "for the incident, the kind and the parameters of R1, with the later key")
	Do $$$AssertEquals(ask.level_"|"_ask.marks, level_"|h103>h105", "the marks were saved and the transaction was over when the ask was sent")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.laterSince_"|"_now.askingSince, "|"_first, "AskingSince takes the round's time and LaterSince is empty")
	Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).GetAt(1)
	Do $$$AssertEquals(group.AskedFrom_"|"_group.AskedTo_"|"_group.AskedKeys(), "h103|h105|h104,h105", "the marks moved: the window is the two new failures")
	Kill group
	Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), 0, "and nothing is raised before the answer")

	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(ask), ..LaterResult(incident, "104,105")), "the answer is handled")
	Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), 1, "one request is raised")
	If '$IsObject(host.Raised) || (host.Raised.%Size() '= 1) Quit
	Set raised = host.Raised.%Get(0)
	Do $$$AssertEquals(raised.kind_"|"_raised.incidentRef_"|"_raised.ownerRef_"|"_raised.resultTarget_"|"_raised.traceRef, "fix|"_incident_"|instance|IncidentManager|", "its kind, incident, owner and result target")
	Do $$$AssertEquals(raised.fixKind_"|"_raised.fixParameters_"|"_raised.fixTargets_"|"_raised.dryRun, "repair_resend|"_..#PARAMETERS_"|104,105|"_..#LATERDRYRUN, "the kind and the parameters of R1, with its own targets and dry run")
	Do $$$AssertEquals(raised.sessionId, 4242, "in the incident's trace session")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 2, "two Notifications are sent")
	If $IsObject(host.Sent) && (host.Sent.%Size() = 2) {
		Set sessions = ""
		For i = 0:1:1 {
			Set note = host.Sent.%Get(i)
			Set sessions = sessions_$Select(sessions = "": "", 1: ",")_note.sessionRef
			Set slots = {}.%FromJSON(note.slots)
			Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.incidentRef_"|"_note.approvalRef_"|"_note.decisionRef, "approval|incident.laterRequest|"_incident_"|"_host.RaiseRef_"|"_..Row(incident).decisionRef, "Notification "_(i + 1)_": kind, key, incident, the new request's Ref and the incident's decision")
			Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Case).SortedKeys(slots), "after,before,cause,count,field,fixSummary,itemNoun,resendCount,time", "its slots")
			Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.field_"|"_slots.before_"|"_slots.after_"|"_slots.resendCount_"|"_slots.itemNoun.other, "2|"_first_"|OrderDate|10/25/2026|2026-10-25|2|orders", "with the round's count and first time, and its own dry run")
		}
		Do $$$AssertEquals(sessions, $ListToString(##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)), "one to each watcher")
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(note.catalogKey, note.slots, "phone", ##class(OcuTalon.Data.Time).NowUtc(), 0, .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertEquals($Extract(text, 1, 27), "2 more orders failed since ", "as the later request: "_text)
	}
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.state_"|"_now.noticedAt_"|"_now.requestRefs_"|"_now.laterSince_"|"_now.askingSince, "awaiting_approval|"_noticedAt_"|"_r1_","_host.RaiseRef_"||", "the incident is still awaiting approval, noticed as before, lists both requests and has no round open")
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "2|2", "each watcher gets one more incident event")
	Do $$$AssertEquals(..Logged(.text), 0, "and nothing was logged: "_text)
	Do $$$AssertEquals(..Started(host), incident_"@4242", "and no further waiter was started")
	Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(r1)
	Do $$$AssertEquals(request.FixTargets_"|"_request.State_"|"_(request.DryRun = ..#DRYRUN), "101,102,103|pending|1", "and R1 is still as it was after the round")
	Kill request
}

/// A later round in each state (AC 3, AC 6): a resolved incident becomes awaiting_approval and a fixing one stays fixing when the later request is raised, while an
/// open incident (fallback, no_fix, rejected, expired) only counts: the count and the event move, LaterSince stays empty, no waiter is started, and a wake asks for
/// nothing.
Method TestLaterRequestStates()
{
	Set cases = $ListBuild("resolved|awaiting_approval", "fixing|fixing", "open|open")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set state = $Piece(case, "|", 1)
		Set variants = $Select(state = "open": $ListBuild("fallback", "no_fix", "rejected", "expired"), 1: $ListBuild(""))
		Set at = 0
		While $ListNext(variants, at, variant) {
			Set label = state_$Select(variant '= "": " "_variant, 1: "")
			Do ..Setup("state"_state_$Translate(variant, "_"), .a, .b, .incident, .row)
			If '$IsObject($Get(row)) Quit
			Kill row
			Set host = ..Host()
			If '$IsObject(host) Quit
			Set r1 = ..Noticed(incident, state, variant)
			Set first = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
			Do $$$AssertStatusOK(..Join(host, incident, "104,105", first_","_first), label_": the later failures are handled")
			Set now = ..Row(incident)
			Do $$$AssertEquals(now.count_"|"_now.state, "5|"_state, label_": the count moves, the state does not")
			Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", label_": each watcher gets the one incident event")
			If state = "open" {
				Do $$$AssertEquals(now.laterSince_"|"_..Started(host), "|", label_": an open incident only counts: no LaterSince and no waiter")
				Do $$$AssertStatusOK(host.Wake(incident), label_": a wake is handled")
				Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)_"|"_$Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), "0|0|0", label_": it asks, waits and sends nothing")
			} Else {
				Do $$$AssertEquals(now.laterSince_"|"_..Started(host), first_"|"_incident_"@4242", label_": the round starts")
				Do $$$AssertStatusOK(host.Wake(incident), label_": the waiter wakes")
				Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, label_": one dry run is asked")
				If $IsObject(host.DryRuns) && (host.DryRuns.%Size() = 1) {
					Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
					Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(host.DryRuns.%Get(0)), ..LaterResult(incident, "104,105")), label_": the answer is handled")
					Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), "1|2", label_": one request is raised and two Notifications are sent")
					Set now = ..Row(incident)
					Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.askingSince, $Piece(case, "|", 2)_"|"_r1_","_host.RaiseRef_"|", label_": the state is "_$Piece(case, "|", 2)_" and the request is listed")
				}
			}
			Do $$$AssertEquals(..Logged(.text), 0, label_": nothing was logged: "_text)
			Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
			Do ..DropAll()
		}
	}
}

/// One ask at a time (the matrix row "One ask at a time"): round 2 settles while round 1's ask is on its way, so the waiter re-checks after the quiet time and
/// asks nothing. After round 1's answer round 2 asks only its own window, and its request carries its own count and first failure's time.
Method TestOneAskAtATime()
{
	Do ..Setup("one", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Kill row
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set r1 = ..Noticed(incident)
	Set one = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
	Set two = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-100)
	Do ##class(OcuTalon.Watch.Settle).Values(.quiet, .max)
	Do $$$AssertStatusOK(..Join(host, incident, "104,105", one_","_one), "round 1 joins")
	Do $$$AssertStatusOK(host.Wake(incident), "round 1 settles and asks")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)_"|"_..Row(incident).askingSince, "1|"_one, "one ask is on its way, with round 1's time")
	Do $$$AssertStatusOK(..Join(host, incident, "106,107", two_","_two), "round 2 joins while the ask is on its way")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.laterSince_"|"_now.askingSince, two_"|"_one, "round 2 has its own time and round 1's stays")
	Do $$$AssertEquals(..Started(host), incident_"@4242,"_incident_"@4242", "and round 2 has its own waiter")
	Do $$$AssertStatusOK(host.Wake(incident), "round 2's waiter wakes")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "it asks nothing")
	Do $$$AssertEquals($Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0)_"|"_$Select($IsObject(host.Alarms): host.Alarms.%Get(0), 1: ""), "1|"_quiet, "it re-checks after the quiet time")
	If ($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0) '= 1) || ($Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0) '= 1) Quit

	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set r2 = host.RaiseRef
	Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(host.DryRuns.%Get(0)), ..LaterResult(incident, "104,105")), "round 1's answer is handled")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.requestRefs_"|"_now.laterSince_"|"_now.askingSince, r1_","_r2_"|"_two_"|", "R2 is listed, round 2 still waits and no ask is on its way")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 2, "R2's two Notifications are sent")
	If $Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0) '= 2 Quit
	Set slots = {}.%FromJSON(host.Sent.%Get(0).slots)
	Do $$$AssertEquals(slots.count_"|"_slots.time, "2|"_one, "R2 carries round 1's count and time")
	Do $$$AssertStatusOK(host.Wake(incident), "round 2's waiter wakes again")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 2, "and asks")
	If $Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0) '= 2 Quit
	Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).GetAt(1)
	Do $$$AssertEquals(group.AskedFrom_"|"_group.AskedTo_"|"_group.AskedKeys(), "h105|h107|h106,h107", "for its own window only")
	Kill group
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.laterSince_"|"_now.askingSince, "|"_two, "round 2's time moved to AskingSince")
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set r3 = host.RaiseRef
	Set result = ..LaterResult(incident, "106,107")
	Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(host.DryRuns.%Get(1)), result), "round 2's answer is handled")
	Set raised = host.Raised.%Get(1)
	Do $$$AssertEquals(raised.fixTargets, "106,107", "R3 holds the targets of round 2's dry run (the window is pinned by the marks above)")
	Set slots = {}.%FromJSON(host.Sent.%Get(host.Sent.%Size() - 1).slots)
	Do $$$AssertEquals(slots.count_"|"_slots.time, "2|"_two, "R3 carries round 2's count and its own first failure's time")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.requestRefs_"|"_now.laterSince_"|"_now.askingSince, r1_","_r2_","_r3_"||", "all three requests are listed and no round is open")
	Do $$$AssertEquals(..Logged(.text), 0, "nothing was logged: "_text)
}

/// Failures that join after the first ask and before its answer (the matrix row "After the first ask"): LaterSince is set and no waiter starts. The raise route
/// starts the later waiter after the notice, in the incident's trace session; the no-fix route clears LaterSince.
Method TestStragglersOfTheFirstAsk()
{
	For route = "raise", "nofix" {
		Do ..Setup("stragglers"_route, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Group(incident, 1, "h101,h102,h103")
		Set row.TraceHeaderId = 4242
		Set row.FirstAt = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-300)
		Set row.LastAt = row.FirstAt
		Do $$$AssertStatusOK(row.%Save(), route_": the incident has a trace session")
		Kill row
		Do $$$AssertStatusOK(host.Answer(incident, ..Diagnosis("data_format_change", "zz cause", 1)), route_": the answer is handled")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, route_": the first ask is made")
		If '$IsObject(host.DryRuns) Quit
		Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).GetAt(1)
		Do $$$AssertEquals(group.AskedFrom_"|"_group.AskedTo_"|"_host.DryRuns.%Get(0).key, "|h103|dryrun", route_": the first ask marked its window: everything up to the last key")
		Kill group
		Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
		Do $$$AssertStatusOK(..Join(host, incident, "104,105", at_","_at), route_": the stragglers are handled")
		Set now = ..Row(incident)
		Do $$$AssertEquals(now.laterSince_"|"_now.noticedAt_"|"_..Started(host), at_"||", route_": LaterSince is set, the incident is unnoticed and no waiter is started")
		Set result = ..Result(incident)
		If route = "nofix" {
			Set result.Reason = "The failed orders are of another scope."
			Set result.Targets = ""
			Set result.DryRun = ""
		}
		Do $$$AssertStatusOK(host.Dried(incident, ..Ask(host.DryRuns.%Get(0)), result), route_": the answer to the dry run is handled")
		Set now = ..Row(incident)
		If route = "raise" {
			Do $$$AssertEquals(now.state_"|"_(now.noticedAt '= "")_"|"_now.laterSince_"|"_..Started(host), "awaiting_approval|1|"_at_"|"_incident_"@4242", "raise: the incident is noticed and the later waiter starts, in the trace session")
			Set raised = host.Raised.%Get(0)
			Do $$$AssertEquals(raised.fixTargets, "101,102,103", "raise: the first request holds the targets of its dry run (its window is pinned by the marks above)")
		} Else {
			Do $$$AssertEquals(now.state_"|"_now.openVariant_"|"_(now.noticedAt '= "")_"|"_now.laterSince_"|"_..Started(host), "open|no_fix|1||", "no fix: the no-fix notice clears LaterSince and no waiter starts")
		}
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
		Do ..DropAll()
		Do ..RemoveWarnings()
	}
}

/// A wake while the settle rule still runs (the matrix row "Still gathering"): two failures join, nine seconds old, and a third two seconds old in another batch.
/// The second batch starts no waiter (one waiter for a round) and LaterSince stays the first failure's time. The waiter sets an alarm of the seconds that are left
/// for the quiet time after the newest failure (Settle.Wait of LaterSince and LastAt), not after the first, and asks nothing. The stamps have whole seconds and the
/// rule reads the clock when the waiter wakes, so the alarm is the quiet time less two seconds less the whole seconds that passed since the stamps were made: the
/// test measures the time that passed (a slow machine cannot fail it) and bounds the alarm by it, far above the one second that the alarm would be if it counted
/// from the first failure.
Method TestStillGathering()
{
	Do ..Setup("gathering", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Kill row
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Noticed(incident)
	Set began = $ZHorolog
	Set old = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-9)
	Set new = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-2)
	Do ##class(OcuTalon.Watch.Settle).Values(.quiet, .max)
	Do $$$AssertStatusOK(..Join(host, incident, "104,105", old_","_old), "two later failures, nine seconds old")
	Do $$$AssertStatusOK(..Join(host, incident, "106", new), "and a third, two seconds old, in another batch")
	Do $$$AssertEquals(..Started(host)_"|"_..Row(incident).laterSince, incident_"@4242|"_old, "one waiter for the round, and LaterSince is the first failure's time")
	Do $$$AssertStatusOK(host.Wake(incident), "the waiter wakes")
	Set elapsed = $ZHorolog - began
	Do $$$AssertEquals($Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0), 1, "it sets one alarm")
	If $IsObject(host.Alarms) && (host.Alarms.%Size() = 1) {
		Set seconds = host.Alarms.%Get(0)
		Do $$$AssertTrue(((seconds + elapsed) '< (quiet - 3)) && (seconds '> (quiet - 2)), "of the seconds that are left after the newest failure, "_(quiet - 3)_" less the "_$Justify(elapsed, 0, 2)_" seconds that passed to "_(quiet - 2)_": "_seconds)
	}
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)_"|"_..Row(incident).laterSince_"|"_..Row(incident).askingSince, "0|"_old_"|", "nothing is asked and LaterSince stands")
	Do $$$AssertEquals(..Logged(.text), 0, "nothing was logged: "_text)
}

/// A wake that ends the later waiter without an ask: an incident that went open after the round began clears LaterSince, one that is gone is left alone, and one
/// whose groups hold no key after their AskedTo clears LaterSince. Nothing is asked, waited for, sent or logged.
Method TestLaterWakeEnds()
{
	For case = "open", "gone", "nonewer" {
		Do ..Setup("wakeends"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Kill row
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set r1 = ..Noticed(incident)
		Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
		Do $$$AssertStatusOK(..Join(host, incident, "104,105", at_","_at), case_": the later failures are handled")
		Do $$$AssertEquals(..Row(incident).laterSince_"|"_..Started(host), at_"|"_incident_"@4242", case_": the round began")
		If case = "open" {
			Do ..Change(incident, "State", "open")
			Do ..Change(incident, "OpenVariant", "rejected")
		}
		If case = "gone" {
			Set id = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident).%Id()
			Do ..DropGroups(incident)
			Do $$$AssertStatusOK(##class(OcuTalon.Data.Incident).%DeleteId(id), case_": the row is deleted")
		}
		If case = "nonewer" {
			Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).GetAt(1)
			Set group.AskedTo = "h105"
			Do $$$AssertStatusOK(group.%Save(), case_": the groups' marks cover every key")
			Kill group
		}
		Do $$$AssertStatusOK(host.Wake(incident), case_": the waiter wakes")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)_"|"_$Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0)_"|"_..Logged(.text), "0|0|0|0", case_": nothing is asked, waited for, sent or logged: "_text)
		If case '= "gone" {
			Set now = ..Row(incident)
			Do $$$AssertEquals(now.laterSince_"|"_now.askingSince_"|"_now.requestRefs, "||"_r1, case_": LaterSince is cleared, no ask is on its way and only R1 is listed")
		}
		Do ..Clear()
	}
}

/// A later round that cannot raise a request (V2; the matrix rows "Later dry run refused", "Nothing to resend", "Raise fails / ask not sent / error answer / slots
/// unbuildable", "Opened during the ask", "Gone" and "No first request row"): nothing is raised or sent, AskingSince is cleared (for an incident that is closed or
/// gone, nothing is written), the state stands, and each error is one Type 3 warning (LOGLATER, naming the incident) while an empty Targets, an open incident, a
/// closed or deleted one and a stale answer are none. A waiter that cannot be started clears LaterSince with one warning.
Method TestLaterNoRequestRoutes()
{
	Set cases = $ListBuild("reason", "targets", "raise", "ask", "error", "field", "resend", "object", "open", "closed", "deleted", "stale", "closedwake", "norow", "nokind", "start")
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..Setup("norequest"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Kill row
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set r1 = ..Noticed(incident)
		Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
		If case = "norow" Do ..Change(incident, "RequestRefs", ##class(OcuTalon.Bridge.Ids).NewRef())
		If case = "nokind" Do ..ChangeRequest(r1, "FixKind", "")
		Set host.FailStart = (case = "start")
		Set host.FailDryRun = (case = "ask")
		Do $$$AssertStatusOK(..Join(host, incident, "104,105", at_","_at), case_": the later failures are handled")
		If case = "start" {
			Set now = ..Row(incident)
			Do $$$AssertEquals(..Started(host)_"|"_now.laterSince_"|"_..Logged(.text), incident_"@4242||1", case_": the waiter could not be sent: LaterSince is cleared and one warning is logged: "_text)
			Do ..Clear()
			Continue
		}
		If case = "closedwake" Do ..Change(incident, "State", "closed")
		Do $$$AssertStatusOK(host.Wake(incident), case_": the waiter wakes")
		Set now = ..Row(incident)
		Set asked = $Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0)
		If case = "closedwake" {
			Do $$$AssertEquals(asked_"|"_$Select($IsObject(host.Alarms): host.Alarms.%Size(), 1: 0)_"|"_now.laterSince_"|"_..Logged(.text), "0|0|"_at_"|0", case_": a closed incident is left as it is: nothing is asked or waited for, nothing is written, nothing is logged")
			Do ..Clear()
			Continue
		}
		If (case = "norow") || (case = "nokind") {
			Do $$$AssertEquals(asked_"|"_now.laterSince_"|"_now.askingSince_"|"_..Logged(.text), "0|||1", case_": the first request cannot be read: nothing is asked, LaterSince is cleared and one warning is logged: "_text)
			Do ..Clear()
			Continue
		}
		Do $$$AssertEquals(asked, 1, case_": the dry run is asked")
		If asked '= 1 Quit
		If case = "ask" {
			Do $$$AssertEquals(..Logged(.text)_"|"_now.laterSince_"|"_now.askingSince_"|"_$Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0)_"|"_$Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), "1|||0|0", case_": the ask could not be sent: one warning, no round open, nothing raised or sent: "_text)
			Do ..Clear()
			Continue
		}
		Set ask = ..Ask(host.DryRuns.%Get(0))
		Set result = ..LaterResult(incident, "104,105")
		If case = "reason" Set result.Reason = "The failed orders are of another scope."
		If case = "targets" Set result.Targets = ""
		If case = "raise" Set host.FailRaise = 1
		If case = "field" Set result.DryRun = ..WithoutKey(result.DryRun, "field")
		If case = "resend" Set result.DryRun = ..WithKey(result.DryRun, "resend", 0)
		If case = "object" Set result.DryRun = "[1]"
		If case = "open" {
			Do ..Change(incident, "State", "open")
			Do ..Change(incident, "OpenVariant", "rejected")
			Do ..ChangeRequest(r1, "State", "rejected")
		}
		If case = "closed" Do ..Change(incident, "State", "closed")
		If case = "stale" Do ..Change(incident, "AskingSince", "")
		If case = "deleted" {
			Set id = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident).%Id()
			Do ..DropGroups(incident)
			Do $$$AssertStatusOK(##class(OcuTalon.Data.Incident).%DeleteId(id), case_": the row is deleted")
		}
		If case = "error" {
			Do $$$AssertStatusOK(host.LaterUndried(incident, $SYSTEM.Status.Error(5001, "The executor refused the dry run")), case_": the error answer is handled")
		} Else {
			Do $$$AssertStatusOK(host.LaterDried(incident, ask, result), case_": the answer is handled")
		}
		Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), $Select(case = "raise": 1, 1: 0), case_": a request is only attempted when the dry run was usable")
		Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0)_"|"_$Select($IsObject(host.Cancelled): host.Cancelled.%Size(), 1: 0), "0|0", case_": nothing is sent or cancelled")
		Set warned = ..Logged(.text)
		If (case = "targets") || (case = "open") || (case = "closed") || (case = "deleted") || (case = "stale") {
			Do $$$AssertEquals(warned, 0, case_": no warning: "_text)
		} Else {
			Do $$$AssertEquals(warned, 1, case_": one Type 3 warning: "_text)
			Set start = $Parameter(..#PROBE, "LOGLATER")
			Do $$$AssertTrue(($Extract(text, 1, $Length(start)) = start) && ($Find(text, incident) > 0), case_": which starts with LOGLATER and names the incident: "_text)
		}
		If case = "reason" Do $$$AssertTrue($Find(text, "another scope") > 0, "which holds the reason: "_text)
		If case = "deleted" {
			Do ..Clear()
			Continue
		}
		Set now = ..Row(incident)
		If case = "closed" {
			Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.askingSince, "closed|"_r1_"|"_at, case_": a closed incident is not written")
		} ElseIf case = "stale" {
			Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.askingSince, "awaiting_approval|"_r1_"|", case_": the answer is dropped and the row stands")
		} ElseIf case = "open" {
			Do $$$AssertEquals(now.state_"|"_now.openVariant_"|"_now.requestRefs_"|"_now.askingSince, "open|rejected|"_r1_"|", case_": the incident is open, lists only R1 and has no ask on its way")
		} Else {
			Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.laterSince_"|"_now.askingSince, "awaiting_approval|"_r1_"||", case_": the state stands, only R1 is listed and no round is open")
		}
		Do ..Clear()
	}
}

/// A save that fails after Raise cancels the later request (the matrix row "Save fails after Raise"): the request that was raised is cancelled, nothing is sent,
/// the row is as it was with no ask on its way, and one warning is logged.
Method TestSaveFailureCancelsTheLaterRequest()
{
	Do ..Setup("latercancel", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Kill row
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set r1 = ..Noticed(incident)
	Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
	Do $$$AssertStatusOK(..Join(host, incident, "104,105", at_","_at), "the later failures are handled")
	Do $$$AssertStatusOK(host.Wake(incident), "the waiter wakes")
	Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, "the dry run is asked")
	If '$IsObject(host.DryRuns) Quit
	Set host.FailMove = 1
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(host.DryRuns.%Get(0)), ..LaterResult(incident, "104,105")), "the answer is handled")
	Do $$$AssertEquals($Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0), 1, "the request was raised")
	Do $$$AssertEquals($Select($IsObject(host.Cancelled): host.Cancelled.%Size(), 1: 0), 1, "and one request is cancelled")
	If $IsObject(host.Cancelled) && (host.Cancelled.%Size() = 1) Do $$$AssertEquals(host.Cancelled.%Get(0), host.RaiseRef, "the one that was raised")
	Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0), 0, "nothing is sent")
	Set now = ..Row(incident)
	Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.askingSince, "awaiting_approval|"_r1_"|", "the incident stands with only R1, and no ask is on its way")
	Do $$$AssertEquals(..Logged(.text), 1, "one Type 3 warning: "_text)
	Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), "1|1", "and only the batch's incident event was published")
}

/// A later round whose dry run raises nothing after its marks moved (the matrix rows "Raise fails / ask not sent / error answer / slots unbuildable", "Save fails
/// after Raise", "Later dry run refused" and "Nothing to resend"; V2): the waiter asks, so the groups' marks move and are saved before the ask goes out (h103>h105).
/// Then the ask cannot be sent (ask), FixExecutor answers an error while a failure h106 joins (error), the dry run has no field (slots), the request cannot be
/// raised (raise) or is cancelled after a failed save (save), FixExecutor refuses the dry run (reason) or has nothing to resend (targets), or the save fails and
/// the raised request cannot be cancelled (uncancelled). Each way sends no Notification, lists no request and clears AskingSince; the state, NoticeCount, the
/// count and one incident event per batch stand, and each logs one Type 3 warning (two for uncancelled: the save and the cancel) but targets. An error puts the
/// marks back (AskedTo := AskedFrom, h103), so the next round's ask covers h104 and h105 with h106 (h103>h106), and the round that gathered during the failed
/// ask takes the failed round's earlier time; a judged dry run keeps them, and so does a request that could not be cancelled, which still holds the window, so
/// the next round's ask covers h106 only (h105>h106).
Method TestFailedLaterRoundRejoinsTheNextRound()
{
	For case = "ask", "error", "slots", "raise", "save", "reason", "targets", "uncancelled" {
		Set restored = '((case = "reason") || (case = "targets") || (case = "uncancelled"))
		Do ..Setup("failedround"_case, .a, .b, .incident, .row)
		If '$IsObject($Get(row)) Quit
		Kill row
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set r1 = ..Noticed(incident)
		Set first = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-120)
		Set second = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-118)
		Set third = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-110)
		Set host.FailDryRun = (case = "ask")
		Do $$$AssertStatusOK(..Join(host, incident, "104,105", first_","_second), case_": the two later failures are handled")
		Set now = ..Row(incident)
		Do $$$AssertEquals(now.count_"|"_now.noticeCount_"|"_now.laterSince, "5|3|"_first, case_": the count moves to 5 and a round gathers")
		Do $$$AssertStatusOK(host.Wake(incident), case_": the waiter wakes")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 1, case_": the dry run is asked")
		If '$IsObject(host.DryRuns) || (host.DryRuns.%Size() '= 1) Quit
		Do $$$AssertEquals(host.DryRuns.%Get(0).marks, "h103>h105", case_": with the round's window saved first")
		If case = "error" {
			Do $$$AssertStatusOK(..Join(host, incident, "106", third), case_": a failure joins while the ask is on its way")
			Set now = ..Row(incident)
			Do $$$AssertEquals(now.laterSince_"|"_now.askingSince, third_"|"_first, case_": a round gathers beside the ask")
			Do $$$AssertStatusOK(host.LaterUndried(incident, $SYSTEM.Status.Error(5001, "The executor refused the dry run")), case_": the error answer is handled")
		}
		If (case '= "ask") && (case '= "error") {
			Set result = ..LaterResult(incident, "104,105")
			If case = "slots" Set result.DryRun = ..WithoutKey(result.DryRun, "field")
			If case = "reason" Set result.Reason = "The failed orders are of another scope."
			If case = "targets" Set result.Targets = ""
			Set host.FailRaise = (case = "raise")
			Set host.FailMove = (case = "save") || (case = "uncancelled")
			Set host.FailCancel = (case = "uncancelled")
			Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			Do $$$AssertStatusOK(host.LaterDried(incident, ..Ask(host.DryRuns.%Get(0)), result), case_": the answer is handled")
		}
		Set host.FailDryRun = 0
		Set host.FailRaise = 0
		Set host.FailMove = 0
		Set host.FailCancel = 0

		Do $$$AssertEquals(..Logged(.text), $Select(case = "targets": 0, case = "uncancelled": 2, 1: 1), case_": "_$Select(case = "targets": "no warning", case = "uncancelled": "two Type 3 warnings", 1: "one Type 3 warning")_": "_text)
		Do $$$AssertEquals($Select($IsObject(host.Sent): host.Sent.%Size(), 1: 0)_"|"_$Select($IsObject(host.Raised): host.Raised.%Size(), 1: 0)_"|"_$Select($IsObject(host.Cancelled): host.Cancelled.%Size(), 1: 0), "0|"_((case = "raise") || (case = "save") || (case = "uncancelled"))_"|"_((case = "save") || (case = "uncancelled")), case_": no Notification is sent; a request was raised only for the raise (refused), the save (cancelled) and uncancelled (its cancel refused)")
		Set now = ..Row(incident)
		Do $$$AssertEquals(now.state_"|"_now.requestRefs_"|"_now.count_"|"_now.noticeCount_"|"_now.askingSince, "awaiting_approval|"_r1_"|"_$Select(case = "error": 6, 1: 5)_"|3|", case_": the state and R1 stand, the count stays and no ask is on its way")
		Do $$$AssertEquals(..Events(a, "incident")_"|"_..Events(b, "incident"), $Select(case = "error": "2|2", 1: "1|1"), case_": one incident event per batch and no other")
		Set group = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident).GetAt(1)
		Do $$$AssertEquals(group.AskedFrom_"|"_group.AskedTo, $Select(restored: "h103|h103", 1: "h103|h105"), case_": "_$Select(restored: "an error puts the marks back, so the round's failures are newer than every mark again", 1: "a judged dry run, or a request that could not be cancelled, keeps the marks"))
		Kill group
		If case = "error" {
			Do $$$AssertEquals(..Row(incident).laterSince, first, case_": the round that gathered during the ask takes the failed round's earlier time")
		} Else {
			Do $$$AssertEquals(..Row(incident).laterSince, "", case_": no round gathers")
			Do $$$AssertStatusOK(..Join(host, incident, "106", third), case_": the next round's failure is handled")
			Do $$$AssertEquals(..Row(incident).laterSince, third, case_": the next round gathers")
		}

		// the next round asks for the failures that no mark covers
		Do $$$AssertStatusOK(host.Wake(incident), case_": the next round's waiter wakes")
		Do $$$AssertEquals($Select($IsObject(host.DryRuns): host.DryRuns.%Size(), 1: 0), 2, case_": and asks")
		If $IsObject(host.DryRuns) && (host.DryRuns.%Size() = 2) {
			Set again = host.DryRuns.%Get(1)
			Do $$$AssertEquals(again.key_"|"_again.marks_"|"_..Row(incident).askingSince, "laterDryRun|"_$Select(restored: "h103>h106", 1: "h105>h106")_"|"_$Select(case = "error": first, 1: third), case_": "_$Select(restored: "its window holds the failed round's h104 and h105 with h106", 1: "its window is h106 only")_", with the round's time")
		}
		Do ..Clear()
	}
}

/// --- helpers ---
/// A failure group (Seq, one failure group that settled with the incident's NoticeCount) of the incident, saved, holding the keys given as its Seen set (none by
/// default) with the key given as its AskedTo mark. The tests delete it in OnAfterOneTest.
Method Group(incident As %String, seq As %Integer, seen As %String = "", askedTo As %String = "")
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = seq
	Set group.Seen = seen
	Set group.AskedTo = askedTo
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

/// The incident of Setup made a noticed one with its first request R1 (Story 7.6): the state and the variant given (awaiting_approval by default), noticed five
/// minutes ago with the trace session 4242, a group whose Seen is h101 to h103 and whose first ask ended at h103, and R1 (a fix of repair_resend over 101, 102 and 103
/// with the dry run of DRYRUN) in the state that goes with the incident's. R1's Ref.
Method Noticed(incident As %String, state As %String = "awaiting_approval", variant As %String = "") As %String
{
	Do ..Group(incident, 1, "h101,h102,h103", "h103")
	Set requestState = $Case(state, "awaiting_approval": "pending", "fixing": "executing", "resolved": "done", : "rejected")
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident, requestState, , {"FixKind": "repair_resend", "FixParameters": (..#PARAMETERS), "FixTargets": "101,102,103", "DryRun": (..#DRYRUN)})
	Set ..Refs = ..Refs_","_request
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.State = state
	Set row.OpenVariant = variant
	Set row.NoticedAt = ##class(OcuTalon.Test.Watch.Incidents).Stamp(-300)
	Set row.FirstAt = row.NoticedAt
	Set row.LastAt = row.NoticedAt
	Set row.FixSummary = "rewrite the order date"
	Set row.ItemNoun = "{""one"":""order"",""other"":""orders""}"
	Set row.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceHeaderId = 4242
	Set row.RequestRefs = request
	Do $$$AssertStatusOK(row.%Save(), "the incident is noticed and lists its first request")
	Quit request
}

/// The probe handles a FailureBatch of the incident's production and owner with failures of the header ids (comma-separated) at the stamps (comma-separated, in
/// the same order), all of the cause of Group; the status.
Method Join(host As OcuTalon.Test.Watch.IncidentProbe, incident As %String, ids As %String, stamps As %String) As %Status
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set batch = ##class(OcuTalon.Watch.Msg.FailureBatch).%New()
	Set batch.Namespace = row.Namespace
	Set batch.Production = row.Production
	Set batch.OwnerRef = row.OwnerRef
	Set batch.PolledAt = ##class(OcuTalon.Data.Time).NowUtc()
	Kill row
	For i = 1:1:$Length(ids, ",") {
		Set failure = ##class(OcuTalon.Watch.Msg.Failure).%New()
		Set failure.Kind = "header"
		Set failure.HeaderId = $Piece(ids, ",", i)
		Set failure.SessionId = failure.HeaderId
		Set failure.SourceName = "ZzSource"
		Set failure.ItemName = "ZzItem"
		Set failure.ErrorText = "Field 'Qty' was empty"
		Set failure.FailedAt = $Piece(stamps, ",", i)
		Do batch.Failures.Insert(failure)
	}
	Set response = ""
	Quit host.OnRequest(batch, .response)
}

/// The incident row as {state, openVariant, noticedAt, count, noticeCount, requestRefs, laterSince, askingSince, decisionRef}, read afresh ("<gone>" for a state when
/// there is no row).
ClassMethod Row(incident As %String) As %DynamicObject
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	If '$IsObject(row) Quit {"state": "<gone>", "openVariant": "", "noticedAt": "", "count": "", "noticeCount": "", "requestRefs": "", "laterSince": "", "askingSince": "", "decisionRef": ""}
	Quit {"state": (row.State), "openVariant": (row.OpenVariant), "noticedAt": (row.NoticedAt), "count": (row.Count), "noticeCount": (row.NoticeCount), "requestRefs": (row.RequestRefs), "laterSince": (row.LaterSince), "askingSince": (row.AskingSince), "decisionRef": (row.DecisionRef)}
}

/// The waiters that the probe started, as "ref@session,..." in order.
ClassMethod Started(host As OcuTalon.Test.Watch.IncidentProbe) As %String
{
	Set text = ""
	If '$IsObject(host.Started) Quit text
	For i = 0:1:host.Started.%Size() - 1 {
		Set each = host.Started.%Get(i)
		Set text = text_$Select(text = "": "", 1: ",")_each.ref_"@"_each.sessionId
	}
	Quit text
}

/// A usable answer of FixExecutor to a later round's dry run: the targets given and the dry run of LATERDRYRUN.
ClassMethod LaterResult(incident As %String, targets As %String) As OcuTalon.Fix.Msg.DryRunResult
{
	Set result = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set result.IncidentRef = incident
	Set result.Targets = targets
	Set result.DryRun = ..#LATERDRYRUN
	Quit result
}

/// The dry run (JSON text) without the key.
ClassMethod WithoutKey(json As %String, key As %String) As %String
{
	Set object = {}.%FromJSON(json)
	Do object.%Remove(key)
	Quit object.%ToJSON()
}

/// The dry run (JSON text) with the number as the key's value.
ClassMethod WithKey(json As %String, key As %String, value As %Integer) As %String
{
	Set object = {}.%FromJSON(json)
	Do object.%Set(key, value, "number")
	Quit object.%ToJSON()
}

/// Sets the property of the incident row and saves it; a save that fails is thrown, so the test fails there.
ClassMethod Change(incident As %String, property As %String, value As %String)
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set $Property(row, property) = value
	$$$ThrowOnError(row.%Save())
}

/// Sets the property of the approval request row and saves it; a save that fails is thrown.
ClassMethod ChangeRequest(ref As %String, property As %String, value As %String)
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set $Property(row, property) = value
	$$$ThrowOnError(row.%Save())
}

/// Removes what a case of a loop made: the warnings, the fixture rows and the groups, so that the next case starts clean.
Method Clear()
{
	Do ..RemoveWarnings()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ..DropAll()
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
