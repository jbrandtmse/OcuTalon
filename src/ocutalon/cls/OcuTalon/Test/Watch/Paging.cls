/// Tests of paging (Story 23.4; AD-1, AD-5, AD-14, AD-15, AD-17, AD-19, AD-25), through a shadow instance of OcuTalon.Test.Watch.IncidentProbe in this process, fixture sessions and fixture
/// rows: IncidentManager's job pages the on-call person once at an incident's first notice, asks for the escalation timer, pages the backup once for an escalation, records an
/// acknowledgement and cancels the timer at a close, and on the online demo does none of it. The probe records the Notifications (SendNotice) and the commands (SendCommand), so that the
/// escalation timer is a fixture until Story 24.3. Every case sets the on-call keys and the online-demo flag itself, and puts them back, the rows it made and the fixtures. The running
/// production and the real routes are Test.Watch.PagingLive's.
///   - TestPageAtNotice (AC1, AC13): three watching sessions, a first notice, one page row, one page Notification, one escalation ask, one audit entry, and the person in none of them;
///   - TestEveryNotice (AC1): the page of a notice with a fix, a fallback notice and a no-fix notice, and the cause the page renders;
///   - TestAloneAndNotConfigured: no backup, the backup that is the on-call person, an address only, and no on-call person (a backup alone included);
///   - TestOnlineDemoRefusesByCode (AC2): onlineDemo 1 with every key set pages nobody (a session's incident and an incident of the instance), and AckPage and an escalation do nothing;
///   - TestSessionOwnedNeverPages (DW-1396): an incident that one session owns is never paged, and an incident of the instance with the same keys is;
///   - TestEscalation (AC3, AC7): the backup is paged once, and an escalation that repeats, follows a restart, an acknowledgement, a close or the backup's own page pages nobody;
///   - TestAcknowledge (AC4): the first AckPage of the paged person's session, a second, another session, a bad channel and a bad Ref;
///   - TestCloseCancels (AC5): the close cancels the timer of an unacknowledged page, once, and a failed cancel is one warning;
///   - TestFailuresAreWarnings: a failed send and a failed ask are one warning each, with no person in it, and the notice stands;
///   - TestPersonIsInNoRecord (AC13): the paged person's name and address are in no Notification, command, audit entry, payload, event or log line;
///   - TestAcknowledgeSurvivesFollowUp (AC4): a step after a saved acknowledgement that throws is one warning, and the AckPage is still answered handled;
///   - TestSettingChangeCause: a notice whose cause is a setting change gives a page whose slots carry the structured cause and whose text names the change;
///   - TestChannelsAreCopied: each role's channel setting is copied to its page row;
///   - TestEmailVariants: the email text of the on-call page, with a backup and alone.
Class OcuTalon.Test.Watch.Paging Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

Parameter KEYS = "oncall.primary.user,oncall.primary.email,oncall.primary.channels,oncall.backup.user,oncall.backup.email,oncall.backup.channels,oncall.escalationMinutes";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, comma-separated: their Page rows and groups are deleted after it.
Property Incidents As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WatchPaging", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ..SaveKeys()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..PutKeysBack()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Incidents, ",") {
		Set ref = $Piece(..Incidents, ",", i)
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Page WHERE IncidentRef = ?", ref)
		Do ##class(OcuTalon.Test.Watch.Lifecycle).DropGroups(ref)
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..PutKeysBack()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production %STARTSWITH ?", "ZZNS", "Zz.Paging"_..Number_".")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production %STARTSWITH ?", "ZZNS", "Zz.Paging"_..Number_".")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Job = ? AND Type = 3 AND Text %STARTSWITH ?", ..LogMark, $Job, "IncidentManager could not")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutKeysBack()
	Kill ^OcuTalonTest("WatchPaging")
	Quit $$$OK
}

/// Saves the seven on-call rows (value and time) under ^OcuTalonTest("WatchPaging", "saved"), for PutKeysBack. Test.Watch.PagingLive calls it too.
ClassMethod SaveKeys()
{
	Kill ^OcuTalonTest("WatchPaging", "saved")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("WatchPaging", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
}

/// Puts the seven on-call rows back as SaveKeys found them: the saved value and time of each, and no row for a key that had none.
ClassMethod PutKeysBack()
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Kill ^||OcuTalon.Setting(key)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $Data(^OcuTalonTest("WatchPaging", "saved", key), saved) {
			If '$IsObject(row) Set row = ##class(OcuTalon.Data.Setting).%New(), row.Key = key
			Set row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		} ElseIf $IsObject(row) {
			Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		}
	}
}

/// Writes the on-call keys: the primary user and address, the backup user and address and the minutes ("" leaves a key without a row), and leaves both channel keys without a
/// row (their default). The rows are put back after the test.
Method Keys(primaryUser As %String = "", primaryEmail As %String = "", backupUser As %String = "", backupEmail As %String = "", minutes As %String = "")
{
	Do $$$AssertStatusOK(..Write("oncall.primary.channels", ""), "the on-call channels are the default")
	Do $$$AssertStatusOK(..Write("oncall.backup.channels", ""), "the backup's channels are the default")
	Do $$$AssertStatusOK(..Write("oncall.primary.user", primaryUser), "the on-call user is set")
	Do $$$AssertStatusOK(..Write("oncall.primary.email", primaryEmail), "the on-call address is set")
	Do $$$AssertStatusOK(..Write("oncall.backup.user", backupUser), "the backup user is set")
	Do $$$AssertStatusOK(..Write("oncall.backup.email", backupEmail), "the backup address is set")
	Do $$$AssertStatusOK(..Write("oncall.escalationMinutes", minutes), "the minutes are set")
}

/// Writes one setting row, or deletes it for an empty value; the status.
ClassMethod Write(key As %String, value As %String) As %Status
{
	Kill ^||OcuTalon.Setting(key)
	If value = "" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Quit ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Quit $$$OK
	}
	Quit ##class(OcuTalon.Data.Setting).Set(key, value)
}

/// A fixture user's session: its Ref is in session, and the user's name (unique to the run) is the result. The session has a Telegram pairing when paired is 1.
Method User(name As %String, Output session As %String, paired As %Boolean = 1) As %String
{
	Set user = "zzpg"_..Number_name
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session
	If paired Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(session)
	Quit user
}

/// Three fixture sessions a, b and c that watch a production of this test, and an unnoticed instance incident of the production with one failure group (its Ref, and the row).
Method Setup(name As %String, Output a As %String, Output b As %String, Output c As %String, Output incident As %String, Output row As OcuTalon.Data.Incident)
{
	Set production = "Zz.Paging"_..Number_"."_name
	Set a = ..Watcher(name_"a", production)
	Set b = ..Watcher(name_"b", production)
	Set c = ..Watcher(name_"c", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set ..Refs = ..Refs_","_incident
	Set ..Incidents = ..Incidents_$Select(..Incidents = "": "", 1: ",")_incident
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertTrue($IsObject(row), "the fixture incident exists")
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = 1
	Set group.ItemName = "ZzItem"
	Set group.ErrorPattern = "Field 'Qty' was empty"
	Set group.ErrorSummary = "Field 'Qty' was empty."
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = "2030-01-01T09:00:00Z"
	Set group.LastAt = "2030-01-01T09:30:00Z"
	Do $$$AssertStatusOK(group.%Save(), "a group of the incident is saved")
}

/// A fixture session whose check row watches the production; its Ref.
Method Watcher(name As %String, production As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpgw"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref_","_##class(OcuTalon.Test.Data.Fixture).Check(ref, "ZZNS", production)
	Quit ref
}

/// A shadow instance of the probe, in this process.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// The first notice of the incident: kind nofix (a diagnosis with no fix), fallback (the diagnosis was refused) or fix (a diagnosis with a fix and its dry run).
Method Notice(host As OcuTalon.Test.Watch.IncidentProbe, incident As %String, kind As %String = "nofix")
{
	If kind = "fallback" {
		Do $$$AssertStatusOK(host.Refuse(incident, $SYSTEM.Status.Error(5001, "The model refused")), "the refusal is handled")
		Quit
	}
	If kind = "nofix" {
		Do $$$AssertStatusOK(host.Answer(incident, ##class(OcuTalon.Test.Watch.Tell).Diagnosis("partner_outage", "zz outage")), "the answer is handled")
		Quit
	}
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.TraceHeaderId = 4242
	Do $$$AssertStatusOK(row.%Save(), "the incident has a trace session")
	Kill row
	Do $$$AssertStatusOK(host.Answer(incident, ##class(OcuTalon.Test.Watch.Tell).Diagnosis("data_format_change", "zz cause", 1)), "the answer is handled")
	If '$IsObject(host.DryRuns) Quit
	Do $$$AssertStatusOK(host.Dried(incident, ##class(OcuTalon.Test.Watch.Tell).Ask(host.DryRuns.%Get(0)), ##class(OcuTalon.Test.Watch.Tell).Result(incident)), "the answer to the dry run is handled")
}

/// The page row of the incident and the role as it is stored now (an object that this process holds open is reloaded), "" when there is none.
ClassMethod Page(incident As %String, role As %String = "oncall") As OcuTalon.Data.Page
{
	Set page = ##class(OcuTalon.Data.Page).IncidentRoleIndexOpen(incident, role)
	If $IsObject(page) Do page.%Reload()
	Quit page
}

/// The number of page rows of the incident.
ClassMethod Pages(incident As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Page WHERE IncidentRef = ?", incident)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The Notifications that the probe recorded of the kind, as a dynamic array.
ClassMethod Sent(host As OcuTalon.Test.Watch.IncidentProbe, kind As %String) As %DynamicArray
{
	Set found = []
	If '$IsObject(host.Sent) Quit found
	For i = 0:1:host.Sent.%Size() - 1 {
		If host.Sent.%Get(i).kind = kind Do found.%Push(host.Sent.%Get(i))
	}
	Quit found
}

/// The number of commands that the probe recorded.
ClassMethod Asked(host As OcuTalon.Test.Watch.IncidentProbe) As %Integer
{
	Quit $Select($IsObject(host.Commands): host.Commands.%Size(), 1: 0)
}

/// The Action audit entries of the action since the mark that name the target, oldest first.
ClassMethod Audited(mark As %String, action As %String, target As %String = "") As %DynamicArray
{
	Set found = []
	Set iterator = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", $Select(target '= "": target, 1: action_":"), "", 1, 2).%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry.data) && (entry.data.action = action) && ((target = "") || (entry.data.target = target)) Do found.%Push(entry)
	}
	Quit found
}

/// The number of the Type 3 warnings that start "IncidentManager could not" and that this process logged since the test began (text is the newest one's).
Method Warned(Output text As %String) As %Integer
{
	Set text = ""
	Set count = 0
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Job = ? AND Type = 3 AND Text %STARTSWITH ? ORDER BY ID", ..LogMark, $Job, "IncidentManager could not")
	While rs.%Next() {
		Set count = count + 1
		Set text = rs.%Get("Text")
	}
	Quit count
}

/// The recipients' incident events of the session, as a dynamic array of payloads, oldest first.
ClassMethod Payloads(session As %String) As %DynamicArray
{
	Set found = []
	Set iterator = ##class(OcuTalon.Test.Core.Observe).Events(session, "incident").%GetIterator()
	While iterator.%GetNext(, .event) {
		Do found.%Push(event.payload)
	}
	Quit found
}

/// An Escalation message for the incident and the page.
ClassMethod Escalation(incident As %String, page As %String) As OcuTalon.Msg.Escalation
{
	Set message = ##class(OcuTalon.Msg.Escalation).%New()
	Set message.IncidentRef = incident
	Set message.PageRef = page
	Quit message
}

/// An AckPage command of the session for the page, with the channel.
ClassMethod Ack(page As %String, session As %String, channel As %String = "web") As OcuTalon.Msg.Command.AckPage
{
	Set command = ##class(OcuTalon.Msg.Command.AckPage).%New()
	Set command.Ref = page
	Set command.Channel = channel
	Set command.SessionRef = session
	Set command.Origin = "web_user"
	Quit command
}

/// The CommandResult that the probe answers for the command, as "Ok|outcome".
Method Answer(host As OcuTalon.Test.Watch.IncidentProbe, command As OcuTalon.Msg.Command) As %String
{
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "the "_$ClassName(command)_" is handled")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Msg.CommandResult"), "and answered with a CommandResult")
	Quit $Select($IsObject(response): +response.Ok_"|"_response.Outcome, 1: "none")
}

/// The Escalation handled by the probe: its status is OK.
Method Escalate(host As OcuTalon.Test.Watch.IncidentProbe, incident As %String, page As %String)
{
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(..Escalation(incident, page), .response), "the escalation is handled")
}

/// AC1 and AC13: three sessions watch the production, the on-call user U (paired) and the backup B are set, and the incident's first notice makes one page row, one page Notification,
/// one escalation ask and one audit entry, and publishes the page's state; the person is in none of them.
Method TestPageAtNotice()
{
	Do ..Setup("one", .a, .b, .c, .incident, .row)
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Notice(host, incident)
	Do $$$AssertEquals(..Pages(incident), 1, "one page row exists for the incident, whatever the number of watching sessions")
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Do $$$AssertEquals(page.Role_"|"_page.Person_"|"_page.Channels_"|"_page.EscalationRef_"|"_page.AcknowledgedAt, "oncall|"_user_"|telegram,email||", "it is the on-call page of the user, with the default channels, no timer yet and no acknowledgement")
	Do $$$AssertTrue(page.SentAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "SentAt is a UTC time")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(page.Ref), "and its Ref is an unguessable reference")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host), 4, "three incident Notifications and one page Notification are sent")
	Set pages = ..Sent(host, "page")
	Do $$$AssertEquals(pages.%Size(), 1, "one of them is a page")
	If pages.%Size() '= 1 Quit
	Set note = pages.%Get(0)
	Do $$$AssertEquals(note.sessionRef_"|"_note.catalogKey_"|"_note.decisionRef_"|"_note.incidentRef_"|"_note.approvalRef, sessionU_"|page.onCall|"_page.Ref_"|"_incident_"|", "to the user's session, key page.onCall, DecisionRef the page's Ref")
	Set slots = {}.%FromJSON(note.slots)
	Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.cause_"|"_slots.minutes_"|"_slots.production_"|"_slots.itemNoun.other, "3|2030-01-01T09:00:00Z|zz outage|15|Zz.Paging"_..Number_".one|messages", "its slots are the incident's count, time, cause, production and the minutes")
	Do $$$AssertEquals(slots.%IsDefined("backup")_"|"_slots.%IsDefined("person"), "0|0", "and carry no name of a person")
	Do $$$AssertEquals(..Asked(host), 1, "one command is asked")
	Set ask = host.Commands.%Get(0)
	Do $$$AssertEquals(ask.class_"|"_ask.kind_"|"_ask.incidentRef_"|"_ask.pageRef_"|"_ask.delaySeconds_"|"_ask.origin, "OcuTalon.Msg.Command.SetReminder|escalation|"_incident_"|"_page.Ref_"|900|system", "the escalation timer, from origin system, after 15 minutes")
	Set entries = ..Audited(mark, "page", page.Ref)
	Do $$$AssertEquals(entries.%Size(), 1, "one Action audit entry names the page")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.result_"|"_entries.%Get(0).data.target, "sent|"_page.Ref, "with its result and the page's Ref as the target")
	Set payloads = ..Payloads(a)
	Do $$$AssertEquals(payloads.%Size(), 2, "a watching session gets the incident event twice: the notice and the page")
	If payloads.%Size() = 2 {
		Do $$$AssertEquals($Select(payloads.%Get(0).%IsDefined("page"): "page", 1: "none"), "none", "the first has no page")
		Do $$$AssertEquals(payloads.%Get(1).page.state_"|"_payloads.%Get(1).page.pagedAt_"|"_payloads.%Get(1).page.acknowledgedAt_"|"_payloads.%Get(1).page.channel, "paged|"_page.SentAt_"||", "the second says paged, and when")
	}
	Set rendered = ##class(OcuTalon.Msg.Notification).%New()
	Set rendered.Kind = "page"
	Set rendered.CatalogKey = note.catalogKey
	Set rendered.Slots = note.slots
	Set rendered.IncidentRef = incident
	Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc)
	Do $$$AssertStatusOK(sc, "the page renders")
	Do slots.%Set("backup", backup, "string")
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("page.onCall", slots, "telegram", .expectedSc)
	Do $$$AssertEquals(text, expected, "as page.onCall with the backup's name read when it renders")
	Do $$$AssertTrue(text [ ("I'll page "_backup_"."), "and it names the backup: "_text)
}

/// AC1: the first notice of a notice with a fix, a fallback notice and a no-fix notice each pages once; the cause the page renders is the diagnosis's, or the sentence for an unknown cause.
Method TestEveryNotice()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", "")
	For kind = "fix", "fallback", "nofix" {
		Do ..Setup(kind, .a, .b, .c, .incident, .row)
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Notice(host, incident, kind)
		Do $$$AssertEquals(..Pages(incident), 1, kind_": one page row")
		Set pages = ..Sent(host, "page")
		Do $$$AssertEquals(pages.%Size(), 1, kind_": one page Notification")
		If pages.%Size() '= 1 Continue
		Set note = pages.%Get(0)
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(note.catalogKey_"|"_slots.minutes_"|"_..Asked(host), "page.onCall|15|1", kind_": key page.onCall, the default 15 minutes and one ask")
		Set rendered = ##class(OcuTalon.Msg.Notification).%New()
		Set rendered.Kind = "page"
		Set rendered.CatalogKey = note.catalogKey
		Set rendered.Slots = note.slots
		Set rendered.IncidentRef = incident
		Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc)
		Do $$$AssertStatusOK(sc, kind_": the page renders")
		If kind = "fallback" {
			Do $$$AssertEquals(slots.%IsDefined("cause"), 0, kind_": the slots carry no cause")
			Do $$$AssertTrue(text [ "I couldn't work out the cause.", kind_": the text says that the cause is not known")
		} Else {
			Do $$$AssertEquals(slots.cause, $Select(kind = "fix": "zz cause", 1: "zz outage"), kind_": the cause is the diagnosis's")
		}
	}
}

/// No backup, a backup who is the on-call person, an address only, and nobody: the alone variant without a timer, an address's page for the session instance with its timer, and nothing.
Method TestAloneAndNotConfigured()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	For case = "nobackup", "same", "address", "backupalone", "nobody" {
		Do ..Setup(case, .a, .b, .c, .incident, .row)
		Set host = ..Host()
		If '$IsObject(host) Quit
		If case = "nobackup" Do ..Keys(user, "", "", "", "")
		If case = "same" Do ..Keys(user, "", $ZConvert(user, "U"), "", "")
		If case = "address" Do ..Keys("", "zzoncall"_..Number_"@example.test", backup, "", 1)
		If case = "backupalone" Do ..Keys("", "", backup, "", "")
		If case = "nobody" Do ..Keys("", "", "", "", "")
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Do ..Notice(host, incident)
		Set pages = ..Sent(host, "page")
		If (case = "backupalone") || (case = "nobody") {
			Do $$$AssertEquals(..Pages(incident)_"|"_pages.%Size()_"|"_..Asked(host)_"|"_##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host), "0|0|0|3", case_": no row, no page, no ask, and the three incident Notifications as before")
			Do $$$AssertEquals(..Audited(mark, "page").%Size(), 0, case_": no audit entry")
			Do $$$AssertEquals($Select(##class(OcuTalon.Watch.Paging).PagePayload(incident) = "": "none", 1: "page"), "none", case_": and no page in the payload")
			Continue
		}
		Do $$$AssertEquals(..Pages(incident)_"|"_pages.%Size(), "1|1", case_": one row and one page")
		If pages.%Size() '= 1 Continue
		Set note = pages.%Get(0)
		If case = "address" {
			Do $$$AssertEquals(..Page(incident).Person_"|"_..Page(incident).Channels_"|"_note.sessionRef_"|"_note.catalogKey, "zzoncall"_..Number_"@example.test|telegram,email|instance|page.onCall", "the page of an address is for the session instance")
			Do $$$AssertEquals(..Asked(host)_"|"_host.Commands.%Get(0).delaySeconds, "1|60", "and its timer is asked for, after one minute")
			Set slots = {}.%FromJSON(note.slots)
			Do $$$AssertEquals(slots.minutes, 1, "one minute")
			Set rendered = ##class(OcuTalon.Msg.Notification).%New()
			Set rendered.Kind = "page"
			Set rendered.CatalogKey = note.catalogKey
			Set rendered.Slots = note.slots
			Set rendered.IncidentRef = incident
			Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc)
			Do $$$AssertTrue(text [ ("within one minute, I'll page "_backup_"."), "a minute of one renders the one form: "_text)
		} Else {
			Do $$$AssertEquals(note.catalogKey_"|"_..Asked(host)_"|"_note.sessionRef, "page.onCallAlone|0|"_sessionU, case_": the alone key, no timer, and the user's session")
		}
	}
}

/// AC2: with onlineDemo 1 and every on-call key set, a first notice pages nobody (no row, Notification, ask or audit entry), the incident's notices are as before, AckPage answers
/// not_found and an escalation does nothing.
Method TestOnlineDemoRefusesByCode()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Setup("demo", .a, .b, .c, .incident, .row)
	// the online demo shows a session its own incidents only
	Set row.OwnerRef = a
	Do $$$AssertStatusOK(row.%Save(), "the incident is the session's own")
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "zzoncall"_..Number_"@example.test", backup, "zzbackup"_..Number_"@example.test", 5)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Notice(host, incident)
	Do $$$AssertEquals(..Pages(incident)_"|"_..Sent(host, "page").%Size()_"|"_..Asked(host)_"|"_##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host), "0|0|0|1", "no row, no page, no ask, and the incident's one Notification")
	Do $$$AssertEquals(..Audited(mark, "page").%Size(), 0, "no audit entry")
	Do $$$AssertEquals(..Payloads(a).%Size(), 1, "and its session gets the one incident event of the notice")
	// a page row that exists (made as a local install would) is not acknowledged or escalated on the demo
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set page.IncidentRef = incident
	Set page.Role = "oncall"
	Set page.Person = user
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(page.%Save(), "an on-call page row exists")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU)), "0|not_found", "AckPage answers not_found on the demo")
	Do ..Escalate(host, incident, page.Ref)
	Do $$$AssertEquals(..Pages(incident)_"|"_..Sent(host, "page").%Size(), "1|0", "an escalation pages nobody")
	Do $$$AssertEquals($Select(##class(OcuTalon.Watch.Paging).PagePayload(incident) = "": "none", 1: "page"), "none", "and the payload shows no page")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU)), "1|handled", "control: the same AckPage is handled when the flag is off")
	// an incident of the instance (which pages when the flag is off) is not paged on the demo either, so that the flag, not the owner, is what refuses
	Do ..Setup("demoshared", .a2, .b2, .c2, .shared, .sharedRow)
	Set other = ..Host()
	If '$IsObject(other) Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Notice(other, shared)
	Do $$$AssertEquals(..Pages(shared)_"|"_..Sent(other, "page").%Size()_"|"_..Asked(other), "0|0|0", "an incident of the instance is not paged on the demo: no row, no page, no ask")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set again = ..Host()
	If '$IsObject(again) Quit
	Do ..Setup("demoshared2", .a3, .b3, .c3, .shared2, .sharedRow2)
	Do ..Notice(again, shared2)
	Do $$$AssertEquals(..Pages(shared2)_"|"_..Sent(again, "page").%Size(), "1|1", "control: the same keys page an incident of the instance when the flag is off")
}

/// DW-1396: with the on-call and backup users set, an incident that one session owns (that user's own Break the feed) is paged by nobody: no page row, no page Notification, no escalation
/// ask, no audit entry, no page in the payload and no warning, while its notice goes to its session as before. The control: an incident of the instance (a shared, watched production), with the same keys, is paged.
Method TestSessionOwnedNeverPages()
{
	Do ..Setup("owned", .a, .b, .c, .incident, .row)
	Do ..Setup("shared", .a2, .b2, .c2, .shared, .sharedRow)
	Set row.OwnerRef = a
	Do $$$AssertStatusOK(row.%Save(), "the first incident is the session's own")
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "zzoncall"_..Number_"@example.test", backup, "zzbackup"_..Number_"@example.test", 5)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	// the control first: the shared incident is paged, so that the keys are known to page
	Set control = ..Host()
	If '$IsObject(control) Quit
	Do ..Notice(control, shared)
	Do $$$AssertEquals(..Pages(shared)_"|"_..Sent(control, "page").%Size()_"|"_..Asked(control), "1|1|1", "control: an incident of the instance is paged with the same keys: one row, one page, one ask")
	If '$IsObject(..Page(shared)) Quit
	// the session's own incident
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Do $$$AssertEquals(..Pages(incident)_"|"_..Sent(host, "page").%Size()_"|"_..Asked(host)_"|"_##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host), "0|0|0|1", "a session's own incident: no row, no page, no ask, and the incident's one Notification")
	Do $$$AssertEquals(..Audited(mark, "page").%Size(), 1, "no audit entry for it: the only page entry is the control's")
	Do $$$AssertEquals($Select(##class(OcuTalon.Watch.Paging).PagePayload(incident) = "": "none", 1: "page"), "none", "and no page in its payload")
	Do $$$AssertEquals(..Payloads(a).%Size(), 1, "and its session gets the one incident event of the notice")
	Do $$$AssertEquals(..Warned(), 0, "and nothing is warned")
}

/// AC3 and AC7: the escalation pages the backup once, and asks for no timer; repeating it, sending it from a new instance (a restart), after an acknowledgement, after a close, for the
/// backup's own page, for a wrong incident or with no usable backup pages nobody.
Method TestEscalation()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("esc", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Set first = ..Page(incident)
	If '$IsObject(first) Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Escalate(host, incident, first.Ref)
	Set second = ..Page(incident, "backup")
	Do $$$AssertTrue($IsObject(second), "the backup has a page row")
	If '$IsObject(second) Quit
	Do $$$AssertEquals(second.Person_"|"_second.Channels_"|"_second.EscalationRef_"|"_second.AcknowledgedAt, backup_"|telegram,email||", "of the backup, with no timer and no acknowledgement")
	Set pages = ..Sent(host, "page")
	Do $$$AssertEquals(pages.%Size(), 2, "one more page Notification")
	If pages.%Size() = 2 {
		Set note = pages.%Get(1)
		Do $$$AssertEquals(note.sessionRef_"|"_note.catalogKey_"|"_note.decisionRef, sessionB_"|page.backup|"_second.Ref, "to the backup's session, key page.backup, DecisionRef the backup page's Ref")
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(slots.%IsDefined("person")_"|"_slots.%IsDefined("backup"), "0|0", "its slots carry no name")
		Set rendered = ##class(OcuTalon.Msg.Notification).%New()
		Set rendered.Kind = "page"
		Set rendered.CatalogKey = note.catalogKey
		Set rendered.Slots = note.slots
		Set rendered.IncidentRef = incident
		Do $$$AssertTrue(##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc) [ ("nobody pressed Got it on "_user_"'s page within 15 minutes"), "the text names the on-call person's page when it renders")
		Do $$$AssertEquals(##class(OcuTalon.Watch.Paging).Text(rendered, "email", .sc) [ "Replying to this email doesn't count.", 1, "and its email variant says that a reply does not count")
	}
	Do $$$AssertEquals(..Asked(host), 1, "no timer is asked for the backup's page")
	Do $$$AssertEquals(..Audited(mark, "page", second.Ref).%Size(), 1, "and its page is audited")
	Set payloads = ..Payloads(a)
	Do $$$AssertEquals(payloads.%Get(payloads.%Size() - 1).page.state, "escalated", "the last event says escalated")
	// repeated, after a restart (a new instance), for the backup's page, for another incident
	Do ..Escalate(host, incident, first.Ref)
	Set again = ..Host()
	Do ..Escalate(again, incident, first.Ref)
	Do ..Escalate(again, incident, second.Ref)
	Do ..Escalate(again, ##class(OcuTalon.Bridge.Ids).NewRef(), first.Ref)
	Do ..Escalate(again, incident, ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals(..Pages(incident)_"|"_..Sent(host, "page").%Size()_"|"_..Sent(again, "page").%Size(), "2|2|0", "a repeated escalation, one after a restart and one for the backup's page change nothing")
	// after an acknowledgement
	Do ..Setup("ack", .a2, .b2, .c2, .incident2, .row2)
	Do ..Notice(host, incident2)
	Set page2 = ..Page(incident2)
	Do $$$AssertEquals(..Answer(host, ..Ack(page2.Ref, sessionU)), "1|handled", "the page is acknowledged")
	Do ..Escalate(host, incident2, page2.Ref)
	Do $$$AssertEquals(..Pages(incident2), 1, "an escalation after the acknowledgement pages nobody")
	// after a close
	Do ..Setup("closed", .a3, .b3, .c3, .incident3, .row3)
	Do ..Notice(host, incident3)
	Set page3 = ..Page(incident3)
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = "dismiss"
	Set command.IncidentRef = incident3
	Set command.SessionRef = a3
	Set command.Origin = "web_user"
	Do $$$AssertEquals(..Answer(host, command), "1|closed", "the incident is closed")
	Do ..Escalate(host, incident3, page3.Ref)
	Do $$$AssertEquals(..Pages(incident3), 1, "an escalation after the close pages nobody")
	// the Ref of another incident's page
	Do ..Setup("other", .a5, .b5, .c5, .incident5, .row5)
	Do ..Notice(host, incident5)
	Set page5 = ..Page(incident5)
	Do ..Setup("other2", .a6, .b6, .c6, .incident6, .row6)
	Do ..Notice(host, incident6)
	Do ..Escalate(host, incident6, page5.Ref)
	Do $$$AssertEquals(..Pages(incident5)_"|"_..Pages(incident6), "1|1", "an escalation that names another incident's page pages nobody")
	// no usable backup now
	Do ..Setup("gone", .a4, .b4, .c4, .incident4, .row4)
	Do ..Notice(host, incident4)
	Set page4 = ..Page(incident4)
	Do ..Keys(user, "", "", "", 15)
	Do ..Escalate(host, incident4, page4.Ref)
	Do $$$AssertEquals(..Pages(incident4), 1, "an escalation with no backup configured any more pages nobody")
	Do ..Keys(user, "", user, "", 15)
	Do ..Escalate(host, incident4, page4.Ref)
	Do $$$AssertEquals(..Pages(incident4), 1, "nor does one whose backup is the on-call person")
}

/// AC4: the first AckPage of the paged person's session is handled (the time and channel are recorded, the timer is cancelled when it has a Ref, one handled Notification goes to the
/// session, one audit entry is written); a second answers already_handled and changes nothing; another session, a channel that is not one and a Ref that is not one answer not_found.
Method TestAcknowledge()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("ack", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.CommandOk = 1
	Do ..Notice(host, incident)
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Do $$$AssertEquals(page.EscalationRef, "ZzProbeEscalation0001", "the timer's Ref is on the page")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set sent = ##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host)
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionB)), "0|not_found", "another session's AckPage answers not_found")
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU, "sms")), "0|not_found", "a channel that is not web, phone or telegram answers not_found")
	Do $$$AssertEquals(..Answer(host, ..Ack("zz", sessionU)), "0|not_found", "a Ref that is not a reference answers not_found")
	Do $$$AssertEquals(..Answer(host, ..Ack(##class(OcuTalon.Bridge.Ids).NewRef(), sessionU)), "0|not_found", "a page that is not known answers not_found")
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, "")), "0|not_found", "and so does no session")
	Set page = ..Page(incident)
	Do $$$AssertEquals(page.AcknowledgedAt_"|"_page.AcknowledgedChannel_"|"_##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host)_"|"_..Asked(host), "||"_sent_"|1", "none of them changed anything")
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU, "telegram")), "1|handled", "the paged person's session is handled")
	Set page = ..Page(incident)
	Do $$$AssertEquals(page.AcknowledgedChannel_"|"_(page.AcknowledgedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"), "telegram|1", "the time and the channel are recorded")
	Do $$$AssertEquals(..Asked(host), 2, "one more command")
	Set cancel = host.Commands.%Get(1)
	Do $$$AssertEquals(cancel.class_"|"_cancel.reminderRef_"|"_cancel.origin, "OcuTalon.Msg.Command.CancelReminder|ZzProbeEscalation0001|system", "the cancel of the timer, from origin system")
	Set handled = ..Sent(host, "handled")
	Do $$$AssertEquals(handled.%Size(), 1, "one handled Notification")
	If handled.%Size() = 1 Do $$$AssertEquals(handled.%Get(0).sessionRef_"|"_handled.%Get(0).decisionRef, sessionU_"|"_page.Ref, "to the page's session, with the page's Ref")
	Set entries = ..Audited(mark, "page_acknowledged", page.Ref)
	Do $$$AssertEquals(entries.%Size(), 1, "one page_acknowledged audit entry names the page")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.channel_"|"_entries.%Get(0).data.sessionRef, "telegram|"_sessionU, "with the channel and the acknowledging session (AD-17)")
	Set payloads = ..Payloads(a)
	Set last = payloads.%Get(payloads.%Size() - 1).page
	Do $$$AssertEquals(last.state_"|"_last.acknowledgedAt_"|"_last.channel, "acknowledged|"_page.AcknowledgedAt_"|telegram", "the last event says acknowledged, when and where")
	Set at = page.AcknowledgedAt
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU, "web")), "1|already_handled", "a second AckPage answers already_handled")
	Set page = ..Page(incident)
	Do $$$AssertEquals(page.AcknowledgedAt_"|"_page.AcknowledgedChannel_"|"_..Asked(host)_"|"_..Sent(host, "handled").%Size()_"|"_..Audited(mark, "page_acknowledged", page.Ref).%Size(), at_"|telegram|2|1|1", "and changes nothing")
}

/// AC5: the close of an incident whose page is unacknowledged and has a timer asks to cancel it once, and a later escalation changes nothing; a close after an acknowledgement
/// cancels nothing more; a failed cancel is one warning and the close stands.
Method TestCloseCancels()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("close", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.CommandOk = 1
	Do ..Notice(host, incident)
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = "dismiss"
	Set command.IncidentRef = incident
	Set command.SessionRef = a
	Set command.Origin = "web_user"
	Do $$$AssertEquals(..Answer(host, command), "1|closed", "the incident is closed")
	Do $$$AssertEquals(..Asked(host), 2, "one command was asked for the cancel, after the escalation ask")
	Set cancel = host.Commands.%Get(1)
	Do $$$AssertEquals(cancel.class_"|"_cancel.reminderRef, "OcuTalon.Msg.Command.CancelReminder|ZzProbeEscalation0001", "it cancels the page's timer")
	Do ..Escalate(host, incident, page.Ref)
	Do $$$AssertEquals(..Pages(incident), 1, "a later escalation changes nothing")
	// a close after an acknowledgement
	Do ..Setup("closeack", .a2, .b2, .c2, .incident2, .row2)
	Do ..Notice(host, incident2)
	Set page2 = ..Page(incident2)
	Do $$$AssertEquals(..Answer(host, ..Ack(page2.Ref, sessionU)), "1|handled", "a page is acknowledged")
	Set asked = ..Asked(host)
	Set command.IncidentRef = incident2
	Set command.SessionRef = a2
	Do $$$AssertEquals(..Answer(host, command), "1|closed", "and its incident closed")
	Do $$$AssertEquals(..Asked(host), asked, "nothing more is cancelled")
	// a failed cancel
	Do ..Setup("closefail", .a3, .b3, .c3, .incident3, .row3)
	Do ..Notice(host, incident3)
	Set before = ..Warned()
	Set host.FailCommand = 1
	Set command.IncidentRef = incident3
	Set command.SessionRef = a3
	Do $$$AssertEquals(..Answer(host, command), "1|closed", "a close whose cancel fails still closes")
	Set host.FailCommand = 0
	Do $$$AssertEquals(..Warned(.text) - before, 1, "with one warning")
	Do $$$AssertTrue(text '[ user, "that holds no name")
	Do ..Escalate(host, incident3, ..Page(incident3).Ref)
	Do $$$AssertEquals(..Pages(incident3), 1, "and a later escalation still changes nothing")
	// a close after the escalation: the timer has fired, so nothing is cancelled
	Do ..Setup("closeesc", .a4, .b4, .c4, .incident4, .row4)
	Do ..Notice(host, incident4)
	Set page4 = ..Page(incident4)
	Do ..Escalate(host, incident4, page4.Ref)
	Do $$$AssertEquals(..Pages(incident4), 2, "the backup is paged")
	Set asked = ..Asked(host)
	Set command.IncidentRef = incident4
	Set command.SessionRef = a4
	Do $$$AssertEquals(..Answer(host, command), "1|closed", "and its incident closed")
	Do $$$AssertEquals(..Asked(host), asked, "no cancel is asked for the timer that has fired")
}

/// AC4: a step after a saved acknowledgement that throws is one warning with no person in it, and the AckPage is still answered handled, with its row acknowledged.
Method TestAcknowledgeSurvivesFollowUp()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("follow", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Set host.ThrowNotice = 1
	Set before = ..Warned()
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU)), "1|handled", "the AckPage is answered handled although the handled Notification's send throws")
	Set host.ThrowNotice = 0
	Set page = ..Page(incident)
	Do $$$AssertTrue(page.AcknowledgedAt '= "", "the row is acknowledged")
	Do $$$AssertEquals(..Warned(.text) - before, 1, "and the failure is one warning")
	Do $$$AssertTrue(text '[ user, "that holds no name: "_text)
}

/// A first notice whose cause is a setting change: the page's slots carry the structured cause (an object with the setting, the item and the gap in minutes), and the rendered
/// page names the change in the sentence of incident.settingChangeCause.
Method TestSettingChangeCause()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("setting", .a, .b, .c, .incident, .row)
	Set snapshot = ##class(OcuTalon.Data.SettingSnapshot).%New()
	Set snapshot.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set snapshot.Namespace = row.Namespace
	Set snapshot.Production = row.Production
	Set snapshot.TakenAt = "2030-01-01T08:00:00Z"
	Set snapshot.CheckedAt = "2030-01-01T08:00:00Z"
	Do snapshot.Settings.Write("[]")
	Do $$$AssertStatusOK(snapshot.%Save(), "a snapshot of the production is saved")
	Set change = ##class(OcuTalon.Data.SettingChange).%New()
	Set change.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set change.SnapshotRef = snapshot.Ref
	Set change.Namespace = row.Namespace
	Set change.Production = row.Production
	Set change.Item = "ZzItem"
	Set change.Target = "Host"
	Set change.Setting = "Host"
	Set change.OldValue = "alpha"
	Set change.NewValue = "beta"
	Set change.Source = "production"
	Set change.DetectedAt = "2030-01-01T08:50:00Z"
	Do $$$AssertStatusOK(change.%Save(), "a change of the failing item ten minutes before the first failure is saved")
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set answer = ##class(OcuTalon.Test.Watch.Tell).Diagnosis("setting_change", "zz cause")
	Set payload = {}.%FromJSON(answer.Payload)
	Set payload.elementAtFault = "Host"
	Set answer.Payload = payload.%ToJSON()
	Do $$$AssertStatusOK(host.Answer(incident, answer), "the answer is handled")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.SettingChangeRef, change.Ref, "the incident names the change")
	Set pages = ..Sent(host, "page")
	Do $$$AssertEquals(pages.%Size(), 1, "one page Notification")
	If pages.%Size() '= 1 Quit
	Set note = pages.%Get(0)
	Set slots = {}.%FromJSON(note.slots)
	Do $$$AssertEquals(slots.%GetTypeOf("cause"), "object", "the page's cause is the structured cause")
	If slots.%GetTypeOf("cause") = "object" Do $$$AssertEquals(slots.cause.setting_"|"_slots.cause.target_"|"_slots.cause.minutes_"|"_slots.cause.time, "Host|ZzItem|10|2030-01-01T08:50:00Z", "with the setting, the item, the gap and the time of the change")
	Set rendered = ##class(OcuTalon.Msg.Notification).%New()
	Set rendered.Kind = "page"
	Set rendered.CatalogKey = note.catalogKey
	Set rendered.Slots = note.slots
	Set rendered.IncidentRef = incident
	Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc)
	Do $$$AssertStatusOK(sc, "the page renders")
	Set sentence = ##class(OcuTalon.Msg.Catalog).Render("incident.settingChangeCause", {"minutes": 10, "setting": "Host", "target": "ZzItem", "time": "2030-01-01T08:50:00Z"}, "telegram", .sentenceSc)
	Do $$$AssertStatusOK(sentenceSc, "the sentence of the change renders")
	Do $$$AssertTrue(text [ sentence, "the text carries the setting-change sentence: "_text)
	Do $$$AssertTrue(text '[ "I couldn't work out the cause", "and not the sentence for an unknown cause")
}

/// The channel settings of the two roles are copied to their page rows when the pages are made.
Method TestChannelsAreCopied()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do $$$AssertStatusOK(..Write("oncall.primary.channels", "telegram"), "the on-call channels are set")
	Do $$$AssertStatusOK(..Write("oncall.backup.channels", "email"), "the backup's channels are set")
	Do ..Setup("channels", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Set first = ..Page(incident)
	If '$IsObject(first) Quit
	Do $$$AssertEquals(first.Channels, "telegram", "the on-call page has the on-call channels")
	Do ..Escalate(host, incident, first.Ref)
	Set second = ..Page(incident, "backup")
	Do $$$AssertTrue($IsObject(second), "the backup has a page")
	If $IsObject(second) Do $$$AssertEquals(second.Channels, "email", "with the backup's channels")
}

/// The email text of the on-call page, for a page with a backup (page.onCallEmail) and for one without (page.onCallEmailAlone): the catalog's rendering of the key, with the backup's
/// name in the first, and the sentence that a reply does not count in both.
Method TestEmailVariants()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	For case = "backup", "alone" {
		Do ..Keys(user, "", $Select(case = "backup": backup, 1: ""), "", 15)
		Do ..Setup(case, .a, .b, .c, .incident, .row)
		Set host = ..Host()
		If '$IsObject(host) Quit
		Do ..Notice(host, incident)
		Set pages = ..Sent(host, "page")
		Do $$$AssertEquals(pages.%Size(), 1, case_": one page Notification")
		If pages.%Size() '= 1 Continue
		Set note = pages.%Get(0)
		Do $$$AssertEquals(note.catalogKey, $Select(case = "backup": "page.onCall", 1: "page.onCallAlone"), case_": the page's key")
		Set slots = {}.%FromJSON(note.slots)
		Set rendered = ##class(OcuTalon.Msg.Notification).%New()
		Set rendered.Kind = "page"
		Set rendered.CatalogKey = note.catalogKey
		Set rendered.Slots = note.slots
		Set rendered.IncidentRef = incident
		Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "email", .sc)
		Do $$$AssertStatusOK(sc, case_": the email text renders")
		If case = "backup" Do slots.%Set("backup", backup, "string")
		Set expected = ##class(OcuTalon.Msg.Catalog).Render($Select(case = "backup": "page.onCallEmail", 1: "page.onCallEmailAlone"), slots, "email", .expectedSc)
		Do $$$AssertEquals(text, expected, case_": the text is the catalog's email text of the key: "_text)
		If case = "backup" {
			Do $$$AssertTrue(text [ ("I'll page "_backup_". Replying to this email doesn't count."), "it names the backup and says that a reply does not count")
		} Else {
			Do $$$AssertTrue((text [ "To show you're on it, press Got it on your OcuTalon page. Replying to this email doesn't count.") && (text '[ "I'll page"), "it says that a reply does not count and names no backup")
		}
	}
}

/// A page whose send or whose ask fails is one warning for each, with no person in it, and the notice, the row and the event stand.
Method TestFailuresAreWarnings()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("fail", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.FailFor = sessionU
	Set host.FailCommand = 1
	Set before = ..Warned()
	Do ..Notice(host, incident)
	Do $$$AssertEquals(..Warned(.text) - before, 2, "the failed send and the failed ask are one warning each")
	Do $$$AssertTrue(text '[ user, "and the newest holds no name: "_text)
	Do $$$AssertEquals(..Pages(incident)_"|"_##class(OcuTalon.Test.Watch.Lifecycle).SentCount(host)_"|"_..Asked(host), "1|4|1", "the row stands, the notices were sent and the ask was made")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_(row.NoticedAt '= ""), "open|1", "and the incident is noticed")
	Do $$$AssertEquals(..Payloads(a).%Size(), 2, "the watchers got the event again, with the page")
}

/// AC1 and AC4 (Decided in-stage 1 and 2): a user with an older session that has no pairing and a newer one that has is paged in the paired one, and only that one
/// acknowledges; a user whose one session has no pairing is paged in that session, not in instance.
Method TestPagedSessionIsThePairedOne()
{
	Set user = ..User("u", .older, 0)
	Set newer = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Refs = ..Refs_","_newer_","_##class(OcuTalon.Test.Data.Fixture).Pairing(newer)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("paired", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Set pages = ..Sent(host, "page")
	Do $$$AssertEquals(pages.%Size(), 1, "one page Notification")
	If pages.%Size() '= 1 Quit
	Do $$$AssertEquals(pages.%Get(0).sessionRef, newer, "to the user's paired session, not the older one")
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, older)), "0|not_found", "the older session's AckPage answers not_found")
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, newer, "telegram")), "1|handled", "the paired session's is handled")
	Set lone = ..User("v", .only, 0)
	Do ..Keys(lone, "", backup, "", 15)
	Do ..Setup("lone", .a2, .b2, .c2, .incident2, .row2)
	Set host2 = ..Host()
	If '$IsObject(host2) Quit
	Do ..Notice(host2, incident2)
	Set pages = ..Sent(host2, "page")
	Do $$$AssertEquals($Select(pages.%Size() = 1: pages.%Get(0).sessionRef, 1: "none"), only, "a user with one session and no pairing is paged in that session")
}

/// Implement-stage note 5: a recorded page.onCall Notification whose backup is cleared, or made the on-call person, before it renders is rendered as page.onCallAlone.
Method TestAloneAtRender()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("render", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Do ..Notice(host, incident)
	Set pages = ..Sent(host, "page")
	If pages.%Size() '= 1 {
		Do $$$AssertEquals(pages.%Size(), 1, "one page Notification")
		Quit
	}
	Set note = pages.%Get(0)
	Do $$$AssertEquals(note.catalogKey, "page.onCall", "the page was recorded with a backup")
	Set rendered = ##class(OcuTalon.Msg.Notification).%New()
	Set rendered.Kind = "page"
	Set rendered.CatalogKey = note.catalogKey
	Set rendered.Slots = note.slots
	Set rendered.IncidentRef = incident
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("page.onCallAlone", {}.%FromJSON(note.slots), "telegram", .expectedSc)
	Do $$$AssertStatusOK(expectedSc, "the alone text renders from the page's slots")
	For case = "cleared", "same" {
		Do ..Keys(user, "", $Select(case = "same": user, 1: ""), "", 15)
		Set text = ##class(OcuTalon.Watch.Paging).Text(rendered, "telegram", .sc)
		Do $$$AssertStatusOK(sc, case_": the page still renders")
		Do $$$AssertEquals(text, expected, case_": as page.onCallAlone, naming no backup")
	}
}

/// AC4 (and AC5's R2 for the acknowledgement): an on-call page acknowledged after the escalation paged the backup asks no cancel, because its timer has fired.
Method TestAcknowledgeAfterEscalation()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Do ..Keys(user, "", backup, "", 15)
	Do ..Setup("ackesc", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.CommandOk = 1
	Do ..Notice(host, incident)
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Do $$$AssertEquals(page.EscalationRef, "ZzProbeEscalation0001", "the page has a timer")
	Do ..Escalate(host, incident, page.Ref)
	Do $$$AssertEquals(..Pages(incident), 2, "the backup is paged")
	Set asked = ..Asked(host)
	Set before = ..Warned()
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU)), "1|handled", "the on-call page is then acknowledged")
	Do $$$AssertEquals(..Asked(host)_"|"_(..Warned() - before), asked_"|0", "with no cancel asked for the timer that has fired, and no warning")
}

/// AC11: the payload's acknowledgement is the first one: when the backup acknowledged before the on-call person, its time and channel are given.
Method TestPayloadFirstAcknowledgement()
{
	Set incident = "ZzPgPay"_..Number
	Set ..Incidents = ..Incidents_$Select(..Incidents = "": "", 1: ",")_incident
	For role = "oncall", "backup" {
		Set page = ##class(OcuTalon.Data.Page).%New()
		Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set page.IncidentRef = incident
		Set page.Role = role
		Set page.Person = "zzpgpay"_..Number
		Set page.Channels = "telegram,email"
		Set page.SentAt = $Select(role = "oncall": "2030-01-01T09:05:00Z", 1: "2030-01-01T09:20:00Z")
		Set page.AcknowledgedAt = $Select(role = "oncall": "2030-01-01T09:30:00Z", 1: "2030-01-01T09:25:00Z")
		Set page.AcknowledgedChannel = $Select(role = "oncall": "web", 1: "telegram")
		Do $$$AssertStatusOK(page.%Save(), "the "_role_" page is saved")
	}
	Set payload = ##class(OcuTalon.Watch.Paging).PagePayload(incident)
	Do $$$AssertTrue($IsObject(payload), "the incident has a page payload")
	If '$IsObject(payload) Quit
	Do $$$AssertEquals(payload.state_"|"_payload.pagedAt_"|"_payload.acknowledgedAt_"|"_payload.channel, "acknowledged|2030-01-01T09:05:00Z|2030-01-01T09:25:00Z|telegram", "the backup's earlier acknowledgement gives the time and the channel")
}

/// AC13: the paged person's name and address are in none of the five records: the Notifications and commands (the production's messages), the audit entries, the incident payload as the page's
/// state, the incident events and the log lines. Each record is searched for a distinctive user name and address.
Method TestPersonIsInNoRecord()
{
	Set user = ..User("u", .sessionU)
	Set backup = ..User("b", .sessionB)
	Set address = "zzoncall"_..Number_"@example.test"
	Do ..Keys(user, address, backup, "zzbackup"_..Number_"@example.test", 15)
	Do ..Setup("none", .a, .b, .c, .incident, .row)
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set host.FailFor = sessionB
	Do ..Notice(host, incident)
	Set page = ..Page(incident)
	If '$IsObject(page) Quit
	Do ..Escalate(host, incident, page.Ref)
	Do $$$AssertEquals(..Answer(host, ..Ack(page.Ref, sessionU)), "1|handled", "the page is acknowledged")
	Set names = $ListBuild(user, backup, address, "zzbackup"_..Number_"@example.test")
	// the messages: every Notification and every command that the probe recorded
	Set messages = host.Sent.%ToJSON()_host.Commands.%ToJSON()
	Do $$$AssertEquals(..Holds(messages, names), "", "the Notifications and the commands hold no name or address")
	// the audit: every page entry
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action").%ToJSON()
	Do $$$AssertTrue(audit [ page.Ref, "the audit entries name the page")
	Do $$$AssertEquals(..Holds(audit, names), "", "and no name or address")
	// the state: the payload that /state lists
	Set state = ##class(OcuTalon.Live.Payload.Incident).FromRow(##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
	Do state.%JSONExportToString(.stateJson)
	Do $$$AssertTrue(stateJson [ """page""", "the state lists the page")
	Do $$$AssertEquals(..Holds(stateJson, names), "", "and no name or address")
	// the events
	Set events = ""
	For session = a, b, c {
		Set events = events_..Payloads(session).%ToJSON()
	}
	Do $$$AssertEquals(..Holds(events, names), "", "the incident events hold no name or address")
	// the logs
	Set logs = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ?", ..LogMark)
	While rs.%Next() {
		Set logs = logs_rs.%Get("Text")_$Char(10)
	}
	Do $$$AssertEquals(..Holds(logs, names), "", "and the event log holds none")
}

/// The first of the names (a $ListBuild list) that the text holds, "" when it holds none.
ClassMethod Holds(text As %String, names As %List) As %String
{
	Set position = 0
	While $ListNext(names, position, name) {
		If $Find(text, name) Quit
		Set name = ""
	}
	Quit $Get(name)
}

}
