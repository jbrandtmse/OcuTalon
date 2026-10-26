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
/// The failed Recipients read has no test: Session.Recipients is called by name, so a probe cannot replace it, and the only way it answers an error is the
/// privilege check of its watchers' statement, which needs a process without %All (SET $ROLES can only add roles) and so an IRIS user made for the purpose.
/// The fixture rows are removed after each test, with their streams, and so are the warnings that these tests made.
Class OcuTalon.Test.Watch.Tell Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

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

/// A usable answer of Decide with a diagnosis of the category and cause, and no fix.
ClassMethod Diagnosis(category As %String, cause As %String) As OcuTalon.Bridge.Msg.DecisionResponse
{
	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set answer.Fallback = 0
	Set answer.Payload = {"outcome": "act", "causeCategory": (category), "cause": (cause), "reasons": ["zz"], "confidence": 0.5}.%ToJSON()
	Quit answer
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
