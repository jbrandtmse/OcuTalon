/// The decisions of paging and the writes of OcuTalon.Data.Page (Story 23.4; AD-1, AD-5, AD-14, AD-15, AD-17, AD-19, AD-25; Lane A). Every method that writes or decides
/// is called from IncidentManager's job only, which sends what these methods give back (the Notification, the timer's ask) and publishes the incident.
///   - OnlineDemo is checked first by Notice, Escalate, Acknowledge, PagePayload and Text, the methods through which an on-call key is read: on the online demo nothing is
///     read, written, sent or audited, whatever the keys hold.
///   - Notice records the on-call page of an incident's first notice, once: the person is the primary user, else the primary address, and the page has the
///     session of that user (the paired one, else the first), else the session instance for an address. Nothing is recorded when no on-call person is
///     configured, a backup alone included. A person never gets a second page of an incident (IncidentRoleIndex is unique, and every method re-reads the rows).
///   - Escalate records the backup's page for an escalation message, only while the on-call page is unacknowledged, the incident is not closed, no backup page
///     exists, and a backup other than the on-call person is configured. The backup's page never has an escalation of its own.
///   - Acknowledge records the first acknowledgement, from the session of the paged person only, and answers with the sentences of Core.SessionOps.
///   - Closing gives the escalation timers of the incident's unacknowledged pages, which the close cancels.
///   - PagePayload gives the incident payload's page member, and Text renders a page notification for a channel. The person is in no Ens message body or header, log line, audit
///     entry or payload: Text reads the backup's name and the paged person's name from the rows and the keys when it renders, so the rendered text of a channel's copy, and
///     that copy's Delivery row, name the backup or the person.
///   - Audit is the one writer of the page's two audit entries (Bridge.Audit, type Action): the target is the page's Ref and no person is in the entry.
Class OcuTalon.Watch.Paging
{

/// The roles.
Parameter ONCALL = "oncall";

Parameter BACKUP = "backup";

/// The setting keys of the on-call section (Core.SettingsOps), read from their rows.
Parameter KEYPRIMARYUSER = "oncall.primary.user";

Parameter KEYPRIMARYEMAIL = "oncall.primary.email";

Parameter KEYPRIMARYCHANNELS = "oncall.primary.channels";

Parameter KEYBACKUPUSER = "oncall.backup.user";

Parameter KEYBACKUPEMAIL = "oncall.backup.email";

Parameter KEYBACKUPCHANNELS = "oncall.backup.channels";

Parameter KEYMINUTES = "oncall.escalationMinutes";

/// The channels that an acknowledgement may name.
Parameter ACKCHANNELS = "web,phone,telegram";

/// The notification kind of a page, and the catalog keys of its texts and of the cause of an incident whose cause is not known.
Parameter KIND = "page";

Parameter KEYONCALL = "page.onCall";

Parameter KEYALONE = "page.onCallAlone";

Parameter KEYBACKUP = "page.backup";

Parameter KEYONCALLEMAIL = "page.onCallEmail";

Parameter KEYALONEEMAIL = "page.onCallEmailAlone";

Parameter KEYPAGEBACKUPEMAIL = "page.backupEmail";

Parameter KEYSUBJECT = "page.subject";

Parameter KEYCAUSEUNKNOWN = "page.causeUnknown";

/// The audit actions.
Parameter AUDITPAGE = "page";

Parameter AUDITACK = "page_acknowledged";

/// The page states of the incident payload.
Parameter PAGED = "paged";

Parameter ACKNOWLEDGED = "acknowledged";

Parameter ESCALATED = "escalated";

/// The escalation delay when the setting is missing or not a whole number of 1 to 1440 minutes.
Parameter DEFAULTMINUTES = 15;

/// The channels of a role whose setting is empty.
Parameter DEFAULTCHANNELS = "telegram,email";

/// The log texts (the incident's Ref follows; no on-call value is ever in a log line).
Parameter LOGPAGE = "IncidentManager could not page for incident ";

Parameter LOGESCALATE = "IncidentManager could not escalate the page of incident ";

Parameter LOGACK = "IncidentManager could not acknowledge a page of incident ";

Parameter LOGUNPAGE = "IncidentManager could not cancel the escalation of incident ";

/// 1 on the online demo, where nothing is paged (Reader.OnlineDemo).
ClassMethod OnlineDemo() As %Boolean
{
	Quit ##class(OcuTalon.Watch.Reader).OnlineDemo()
}

/// The configured person of the role (primary or backup) and the role's channels: the user when one is set, else the address; "" when neither is. Read from the rows,
/// never from a cache. The values are not logged or sent anywhere by this method.
ClassMethod Configured(role As %String, Output channels As %String) As %String
{
	Set backup = (role = ..#BACKUP)
	Set user = ##class(OcuTalon.Data.Setting).Fresh($Select(backup: ..#KEYBACKUPUSER, 1: ..#KEYPRIMARYUSER))
	Set email = ##class(OcuTalon.Data.Setting).Fresh($Select(backup: ..#KEYBACKUPEMAIL, 1: ..#KEYPRIMARYEMAIL))
	Set channels = $ZStrip(##class(OcuTalon.Data.Setting).Fresh($Select(backup: ..#KEYBACKUPCHANNELS, 1: ..#KEYPRIMARYCHANNELS)), "<>W")
	If channels = "" Set channels = ..#DEFAULTCHANNELS
	Set user = $ZStrip(user, "<>W")
	Quit $Select(user '= "": user, 1: $ZStrip(email, "<>W"))
}

/// The escalation delay in seconds: oncall.escalationMinutes (a whole number of 1 to 1440, else DEFAULTMINUTES) times 60.
ClassMethod Seconds() As %Integer
{
	Quit ..Minutes() * 60
}

/// oncall.escalationMinutes: a whole number of 1 to 1440, else DEFAULTMINUTES.
ClassMethod Minutes() As %Integer
{
	Set value = ##class(OcuTalon.Data.Setting).Fresh(..#KEYMINUTES, ..#DEFAULTMINUTES)
	If (value '? 1.N) || (+value < 1) || (+value > 1440) Quit ..#DEFAULTMINUTES
	Quit +value
}

/// 1 when the two persons are the same one: equal without regard to case.
ClassMethod Same(first As %String, second As %String) As %Boolean
{
	Quit $ZConvert(first, "L") = $ZConvert(second, "L")
}

/// The Ref of the session that a person's page goes to: the session of the user (the first session row whose IRIS user is the person, with a Telegram pairing when one of
/// them has it), and "instance" for a person with no session (an address, or a user who never signed in). Never creates a session row (Session.ForUser would).
ClassMethod SessionOf(person As %String) As %String
{
	If person = "" Quit "instance"
	Set first = ""
	Set statement = ##class(%SQL.Statement).%New()
	If $$$ISERR(statement.%Prepare("SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser = ? ORDER BY ID")) Quit "instance"
	Set result = statement.%Execute(person)
	If result.%SQLCODE < 0 Quit "instance"
	While result.%Next() {
		Set ref = result.%Get("Ref")
		If first = "" Set first = ref
		If $IsObject(##class(OcuTalon.Data.Ownership).Pairing(ref, .sc)) Quit
		Set ref = ""
	}
	Quit $Select($Get(ref) '= "": ref, first '= "": first, 1: "instance")
}

/// Records the on-call page of the incident's first notice: the page row, and the Notification to send (SessionRef set) in notification, and the delay of the escalation
/// timer to ask for in seconds in delay (0 when no timer is to be asked: no usable backup). The result is the page's Ref, or "" when nothing is paged: the online demo (checked
/// before any key is read), an evaluation incident, no on-call person, or a page of this incident already recorded. slots is the notice's slots, of which only cause is read.
ClassMethod Notice(incident As OcuTalon.Data.Incident, slots As %DynamicObject, Output notification As OcuTalon.Msg.Notification, Output delay As %Integer) As %String
{
	Set notification = ""
	Set delay = 0
	If ..OnlineDemo() Quit ""
	If incident.OwnerRef = ##class(OcuTalon.Data.Ownership).#EVAL Quit ""
	Set person = ..Configured("primary", .channels)
	If person = "" Quit ""
	If ##class(OcuTalon.Data.Page).IncidentRoleIndexExists(incident.Ref, ..#ONCALL) Quit ""
	Set backup = ..Configured(..#BACKUP)
	Set usable = (backup '= "") && '..Same(backup, person)
	Set page = ..Record(incident.Ref, ..#ONCALL, person, channels)
	If page = "" Quit ""
	Set notification = ..PageNotice(incident, page, $Select(usable: ..#KEYONCALL, 1: ..#KEYALONE), slots, ..SessionOf(person))
	If usable Set delay = ..Seconds()
	Quit page.Ref
}

/// Records the backup's page for an escalation, and the Notification to send in notification. The result is the page's Ref, or "" and nothing recorded when: the online demo,
/// an unknown incident or on-call page (the message must name both, and the page must be the incident's on-call page), a closed incident, an acknowledged on-call page, a backup
/// page that exists, or no backup that is another person than the on-call one.
ClassMethod Escalate(message As OcuTalon.Msg.Escalation, Output notification As OcuTalon.Msg.Notification) As %String
{
	Set notification = ""
	If ..OnlineDemo() Quit ""
	If (message.IncidentRef = "") || (message.PageRef = "") Quit ""
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(message.IncidentRef)
	If '$IsObject(incident) || (incident.State = ##class(OcuTalon.Watch.IncidentManager).#CLOSED) Quit ""
	Set first = ##class(OcuTalon.Data.Page).RefIndexOpen(message.PageRef)
	If '$IsObject(first) || (first.IncidentRef '= incident.Ref) || (first.Role '= ..#ONCALL) || (first.AcknowledgedAt '= "") Quit ""
	If ##class(OcuTalon.Data.Page).IncidentRoleIndexExists(incident.Ref, ..#BACKUP) Quit ""
	Set backup = ..Configured(..#BACKUP, .channels)
	If (backup = "") || ..Same(backup, first.Person) Quit ""
	Set page = ..Record(incident.Ref, ..#BACKUP, backup, channels)
	If page = "" Quit ""
	Set notification = ..PageNotice(incident, page, ..#KEYBACKUP, "", ..SessionOf(backup))
	Quit page.Ref
}

/// Saves the page row of the incident and the role for the person, with a new Ref and now as SentAt; the row, or "" when the save failed (a row of the role exists).
ClassMethod Record(incidentRef As %String, role As %String, person As %String, channels As %String) As OcuTalon.Data.Page [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set page.IncidentRef = incidentRef
	Set page.Role = role
	Set page.Person = person
	Set page.Channels = channels
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	If $$$ISERR(page.%Save()) Quit ""
	Quit page
}

/// The page Notification: kind page, the catalog key, the slots (count, itemNoun, production, time, cause when it is known, and the escalation minutes), the incident's Ref, the page's
/// Ref as DecisionRef and the session. The slots hold no person.
ClassMethod PageNotice(incident As OcuTalon.Data.Incident, page As OcuTalon.Data.Page, key As %String, slots As %DynamicObject, session As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.Kind = ..#KIND
	Set notification.CatalogKey = key
	Set notification.Slots = ..Slots(incident, slots).%ToJSON()
	Set notification.IncidentRef = incident.Ref
	Set notification.DecisionRef = page.Ref
	Set notification.SessionRef = session
	Quit notification
}

/// The slots of a page: the incident's count, item noun and first failure time, its production's name, the cause (the notice's own when slots give one, else the setting
/// change that the diagnosis named, else the diagnosed cause; absent for a fallback incident or an unknown cause, which Text fills) and the escalation minutes.
ClassMethod Slots(incident As OcuTalon.Data.Incident, notice As %DynamicObject = "") As %DynamicObject
{
	Set common = ##class(OcuTalon.Watch.Notice).Common(incident, .sc)
	If $$$ISERR(sc) || '$IsObject(common) Set common = {"count": (+incident.Count), "time": (incident.FirstAt), "itemNoun": {"one": "message", "other": "messages"}}
	Set slots = {"count": (common.count), "itemNoun": (common.itemNoun), "production": (##class(OcuTalon.Fix.Kind).ProductionName(incident)), "time": (common.time), "minutes": (..Minutes())}
	Set cause = ""
	If $IsObject(notice) {
		Set type = notice.%GetTypeOf("cause")
		If type = "object" Set cause = notice.cause
		If type = "string" Set cause = $ZStrip(notice.cause, "<>W")
	}
	If (cause = "") && '..UnknownCause(incident) {
		If ##class(OcuTalon.Watch.SettingCause).CauseSlot(incident, .setting) {
			Set cause = setting
		} Else {
			Set cause = $ZStrip(incident.Cause, "<>W")
		}
	}
	If cause '= "" Do slots.%Set("cause", cause)
	Quit slots
}

/// 1 when the incident's cause is not known: a fallback incident, or one whose diagnosis is the unknown category.
ClassMethod UnknownCause(incident As OcuTalon.Data.Incident) As %Boolean [ Private ]
{
	Quit +incident.Fallback || (incident.CauseCategory = ##class(OcuTalon.Watch.Notice).#UNKNOWNCATEGORY)
}

/// Records the first acknowledgement of a page and gives the answer as {"ok", "outcome", "message", "page"}: page is the Ref when this command made the acknowledgement, and
/// empty for every other answer. handled (ok 1) is the first acknowledgement from the session of the paged person; already_handled (ok 1) changes nothing; not_found (ok 0)
/// is a channel that is not web, phone or telegram, a Ref that is not a reference, an unknown page, a session that is not the paged person's (an address has none), and
/// any acknowledgement on the online demo. failed (ok 0) is a row that could not be saved. The sentences are those of Core.SessionOps.
ClassMethod Acknowledge(command As OcuTalon.Msg.Command.AckPage) As %DynamicObject
{
	Set notFound = {"ok": 0, "outcome": "not_found", "message": (##class(OcuTalon.Core.SessionOps).#MESSAGENOTICENOTFOUND), "page": ""}
	If ..OnlineDemo() Quit notFound
	If '$ListFind($ListFromString(..#ACKCHANNELS), command.Channel) || '##class(OcuTalon.Bridge.Approval).IsRef(command.Ref) Quit notFound
	Set page = ##class(OcuTalon.Data.Page).RefIndexOpen(command.Ref)
	If '$IsObject(page) || (page.Ref '= command.Ref) Quit notFound
	If (command.SessionRef = "") || (command.SessionRef = "instance") || (..SessionOf(page.Person) '= command.SessionRef) Quit notFound
	If page.AcknowledgedAt '= "" Quit {"ok": 1, "outcome": "already_handled", "message": (##class(OcuTalon.Core.SessionOps).#MESSAGEALREADYHANDLED), "page": ""}
	Set page.AcknowledgedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set page.AcknowledgedChannel = command.Channel
	If $$$ISERR(page.%Save()) Quit {"ok": 0, "outcome": "failed", "message": (##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED), "page": ""}
	Quit {"ok": 1, "outcome": "handled", "message": (##class(OcuTalon.Core.SessionOps).#MESSAGEHANDLED), "page": (page.Ref)}
}

/// The handled Notification for the acknowledged page, as SessionOps sends it (kind handled, the page's Ref as DecisionRef, no key, no slots), for the session.
ClassMethod Handled(page As OcuTalon.Data.Page, session As %String) As OcuTalon.Msg.Notification
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "handled"
	Set notification.DecisionRef = page.Ref
	Set notification.IncidentRef = page.IncidentRef
	Set notification.CatalogKey = ""
	Set notification.Slots = "{}"
	Quit notification
}

/// The escalation timers that closing the incident cancels: the EscalationRefs of its unacknowledged pages that have one, as a list; none once the backup has a page (the timer has fired).
ClassMethod Closing(incident As OcuTalon.Data.Incident) As %List
{
	If ##class(OcuTalon.Data.Page).IncidentRoleIndexExists(incident.Ref, ..#BACKUP) Quit ""
	Set refs = ""
	Set pages = ##class(OcuTalon.Data.Page).OfIncident(incident.Ref)
	For i = 1:1:pages.Count() {
		Set page = pages.GetAt(i)
		If (page.AcknowledgedAt = "") && (page.EscalationRef '= "") Set refs = refs_$ListBuild(page.EscalationRef)
	}
	Quit refs
}

/// Records the escalation timer that was asked for the page; OK, or the error of the save. A page that is not there is an error.
ClassMethod Armed(pageRef As %String, escalationRef As %String) As %Status
{
	Set page = ##class(OcuTalon.Data.Page).RefIndexOpen(pageRef)
	If '$IsObject(page) Quit $SYSTEM.Status.Error(5001, "The page is not there, so its escalation was not recorded")
	Set page.EscalationRef = escalationRef
	Quit page.%Save()
}

/// The page member of the incident payload as {"state", "pagedAt", "acknowledgedAt", "channel"}, or "" when the incident has no page and on the online demo. state is acknowledged
/// once any page of the incident is (with the time and channel of the first acknowledgement), else escalated when the backup has a page, else paged; pagedAt is the on-call
/// page's SentAt. It holds no person. Rows are read by object access only (AD-13).
ClassMethod PagePayload(incidentRef As %String) As %DynamicObject
{
	If ..OnlineDemo() Quit ""
	Set pages = ##class(OcuTalon.Data.Page).OfIncident(incidentRef)
	If 'pages.Count() Quit ""
	Set first = pages.GetAt(1)
	Set state = ..#PAGED
	Set at = ""
	Set channel = ""
	If pages.Count() > 1 Set state = ..#ESCALATED
	For i = 1:1:pages.Count() {
		Set when = pages.GetAt(i).AcknowledgedAt
		If (when '= "") && ((at = "") || (when ']] at)) {
			Set state = ..#ACKNOWLEDGED
			Set at = when
			Set channel = pages.GetAt(i).AcknowledgedChannel
		}
	}
	Quit {"state": (state), "pagedAt": (first.SentAt), "acknowledgedAt": (at), "channel": (channel)}
}

/// The text of a page Notification for the channel: its catalog key's entry rendered with its slots, plus the backup's name ({backup}, the backup role's current user, else
/// address, of the on-call key's text) or the paged person's name ({person}, the on-call page's Person, of the backup's text), read when this renders, and the cause of an unknown
/// cause rendered from page.causeUnknown. An on-call page whose backup is no longer another person is rendered without one (page.onCallAlone). The channel email takes the
/// Email variant of the key. The text, or "" with the status in sc.
ClassMethod Text(notification As OcuTalon.Msg.Notification, channel As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	If ..OnlineDemo() {
		Set sc = $SYSTEM.Status.Error(5001, "Nothing is paged on the online demo")
		Quit ""
	}
	Set key = notification.CatalogKey
	Set slots = ""
	Try {
		Set slots = {}.%FromJSON(notification.Slots)
	} Catch {
		Set slots = ""
	}
	If '$IsObject(slots) || '$ListFind($ListBuild(..#KEYONCALL, ..#KEYALONE, ..#KEYBACKUP), key) {
		Set sc = $SYSTEM.Status.Error(5001, "The page notification has no page text to render")
		Quit ""
	}
	If key = ..#KEYONCALL {
		Set on = ##class(OcuTalon.Data.Page).IncidentRoleIndexOpen(notification.IncidentRef, ..#ONCALL)
		Set backup = ..Configured(..#BACKUP)
		If (backup = "") || ($IsObject(on) && ..Same(backup, on.Person)) {
			Set key = ..#KEYALONE
		} Else {
			Do slots.%Set("backup", backup, "string")
		}
	}
	If key = ..#KEYBACKUP {
		Set on = ##class(OcuTalon.Data.Page).IncidentRoleIndexOpen(notification.IncidentRef, ..#ONCALL)
		If '$IsObject(on) {
			Set sc = $SYSTEM.Status.Error(5001, "The page of the incident that this backup page follows is not there")
			Quit ""
		}
		Do slots.%Set("person", on.Person, "string")
	}
	Set cause = $Select(slots.%GetTypeOf("cause") = "string": $ZStrip(slots.cause, "<>W"), slots.%GetTypeOf("cause") = "object": "object", 1: "")
	If cause = "" {
		Do slots.%Set("cause", ##class(OcuTalon.Msg.Catalog).Render(..#KEYCAUSEUNKNOWN, "", channel, .sc), "string")
		If $$$ISERR(sc) Quit ""
	}
	If channel = "email" Set key = $Case(key, ..#KEYONCALL: ..#KEYONCALLEMAIL, ..#KEYALONE: ..#KEYALONEEMAIL, : ..#KEYPAGEBACKUPEMAIL)
	Quit ##class(OcuTalon.Msg.Catalog).Render(key, slots, channel, .sc)
}

/// Writes the audit entry of a page (action page) or of an acknowledgement (page_acknowledged) through Bridge.Audit: the target is the page's Ref, the result a fixed word,
/// and no person or address is in it. channel is the acknowledgement's channel (system for a page), and session the acknowledging session's Ref (AD-17; none for a page,
/// which the system sends). OK or the error of the write.
ClassMethod Audit(action As %String, pageRef As %String, result As %String, channel As %String = "system", session As %String = "") As %Status
{
	Set data = {}
	Do data.%Set("action", action, "string")
	Do data.%Set("target", pageRef, "string")
	Do data.%Set("result", result, "string")
	Do data.%Set("counts", {})
	Do data.%Set("approvalRef", "", "string")
	Do data.%Set("irisUser", $Username, "string")
	Do data.%Set("sessionRef", session, "string")
	Do data.%Set("channel", $Select($ListFind($ListFromString(..#ACKCHANNELS), channel): channel, 1: "system"), "string")
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

}
