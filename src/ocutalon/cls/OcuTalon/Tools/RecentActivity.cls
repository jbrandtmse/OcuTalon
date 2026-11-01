/// The Chat agent's recent_activity tool (AD-4, AD-10, AD-13, AD-28): what happened earlier in this conversation's incidents, from OcuTalon's own records. It is
/// in the Watching toolset, which names Tools.Names RECENTACTIVITY. The tool is read-only and writes and submits nothing. The session comes from the bridge context
/// of the call, never from an argument, and every row is read through the ownership API (OcuTalon.Data.Ownership: RecentIncidents, IncidentApprovals and Checks),
/// plus the Lane A row readers FailureGroup.OfIncident and FixRun.OfRequest.
/// The answer is {"ok": true, "hours": 24, "incidents": [...]}: at most MAX incidents of the session, newest noticed first, whose latest of NoticedAt, LastAt and
/// ClosedAt falls within the last HOURS hours; with none, "incidents" is empty and "message" is NONE. An incident is {"production", "item", "count", "firstFailure",
/// "lastFailure", "element", "causeCategory", "fixKind", "state", "approvals"}, and an approval is {"answer", "channel", "answered", "fix"} where fix is null or
/// {"resent", "wentThrough", "failedAgain", "finished"}.
/// Trusted output: every string of the answer is one of
///   - a value of a fixed list (the incident state, the cause category, the fix kind, the approval answer, the channel);
///   - a time formatted by OcuTalon.Data.Time.ForMessage, with " ET" on the online demo, as the catalog shows a time;
///   - a name that the instance defines (the display name of a production, the name of an item, or the element at fault when it equals the approved fix's field or
///     an item's name, which the fix check verified against the compiled properties of the message body);
///   - a constant that the code wrote.
/// The cause sentence, the fix summary, the sample error, a group's error pattern and summary, a fix run's reason, a request's dry run, tool arguments and answerer,
/// and any message text are never read, so no content from outside the instance reaches the model through this tool. A call that is not a session's turn answers
/// OcuTalon.Tools.CommandCall NOSESSION before anything is read, and rows that cannot be read answer NOTREAD.
/// It extends OcuTalon.Tools.Result and returns only through Return. A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no
/// Python call (AD-6). The description of the tool is its method's doc comment: text for the model, never shown to the user as written.
Class OcuTalon.Tools.RecentActivity Extends OcuTalon.Tools.Result
{

Parameter STEPLABELRECENTACTIVITY = "Reading recent activity";

Parameter CLASSIFICATIONRECENTACTIVITY = "safe";

Parameter READONLYRECENTACTIVITY = 1;

Parameter TRUSTEDOUTPUTRECENTACTIVITY = 1;

/// The message of an empty list. It says only that no incident is recorded in the window.
Parameter NONE = "No incident is recorded for this conversation in the last 24 hours. This says nothing about what is happening now.";

/// The message when the records cannot be read.
Parameter NOTREAD = "The incidents of this conversation could not be read, so nothing is known about what happened earlier.";

/// The window in hours, the most incidents in the answer, and the most incidents that are read before the window cuts them.
Parameter HOURS = 24;

Parameter MAX = 5;

Parameter READMAX = 100;

/// The kind of a watch row of a production (the Kind of its BackgroundCheck).
Parameter KIND = "production";

/// The request states of an approved fix, comma-separated: the states whose answer is approved. Only their fix field can confirm the element at fault.
Parameter APPROVED = "approved,executing,done,failed";

/// Tells what happened earlier in this conversation: the user's recent incidents (the last 24 hours, at most 5, newest first), each with its approvals and the
/// result of its fix. Call it when the user asks about earlier failures, incidents, approvals, fixes or what happened, for example "what was that failure
/// earlier?" or "did the fix work?". The answer is ok with hours (the window) and incidents. An incident has production: the name to say; item: the production
/// item that failed; count: how many failures; firstFailure and lastFailure: when, in the instance's time; element: the field at fault, empty when it is not
/// known; causeCategory: the kind of cause, such as data_format_change; fixKind: the kind of fix that was proposed, empty when none was; state: open,
/// awaiting_approval, fixing, resolved or closed; and approvals. An approval has answer: waiting, approved, rejected, expired or cancelled; channel: where it was
/// answered, empty when nobody answered it; answered: when it was answered, or when it expired, and empty while it waits; and fix, which is null when no fix
/// ran, otherwise resent (the failed messages sent again), wentThrough (how many of them went through), failedAgain and finished (false while the fix is still
/// running). When incidents is empty, the answer has a message: say plainly that nothing is recorded for the last 24 hours, and never say that everything is
/// fine or that nothing is wrong, because an empty list says nothing about now. When ok is false, the answer has only a message: say that the records could not
/// be read, and say nothing about what happened.
ClassMethod RecentActivity() As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set owner = context.OwnerRef
	Do ..ReadIncidents(owner, .rows, .sc)
	If $$$ISERR(sc) || '$IsObject(rows) Quit ..Return({"ok": false, "message": (..#NOTREAD)})
	Set cutoff = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -(..#HOURS * 3600))
	Do ..WatchNames(owner, .names)
	Set online = ##class(OcuTalon.Watch.Reader).OnlineDemo()
	Set incidents = []
	Set unread = 0
	For i = 1:1:rows.Count() {
		If incidents.%Size() '< ..#MAX Quit
		Set row = rows.GetAt(i)
		Do ..Latest(row, .latest)
		If (cutoff = "") || (latest = "") Continue
		If '((latest = cutoff) || (latest ] cutoff)) Continue
		Do ..Entry(row, owner, $Get(names(row.Namespace, row.Production)), online, .entry)
		If '$IsObject(entry) {
			Set unread = 1
			Quit
		}
		Do incidents.%Push(entry)
	}
	If unread Quit ..Return({"ok": false, "message": (..#NOTREAD)})
	Set answer = {"ok": true, "hours": (..#HOURS), "incidents": (incidents)}
	If incidents.%Size() = 0 Set answer.message = ..#NONE
	Quit ..Return(answer)
}

/// The session's newest noticed incidents in rows (Ownership.RecentIncidents), and the status of the read in sc.
ClassMethod ReadIncidents(owner As %String, Output rows As %ListOfObjects, Output sc As %Status) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).RecentIncidents(owner, ..#READMAX, .sc)
}

/// The approval requests of one incident in requests (Ownership.IncidentApprovals), and the status of the read in sc.
ClassMethod ReadApprovals(incidentRef As %String, owner As %String, Output requests As %ListOfObjects, Output sc As %Status) [ Private ]
{
	Set requests = ##class(OcuTalon.Data.Ownership).IncidentApprovals(incidentRef, owner, .sc)
}

/// The latest of the incident's NoticedAt, LastAt and ClosedAt that is a UTC time, or "".
ClassMethod Latest(row As OcuTalon.Data.Incident, Output latest As %String) [ Private ]
{
	Set latest = ""
	For time = row.NoticedAt, row.LastAt, row.ClosedAt {
		If (time ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z") && (time ] latest) Set latest = time
	}
}

/// The entry of one incident (see the class description) in entry, or "" when its approvals cannot be read. display is the display name of the session's own
/// watch of the production, "" when it has none.
ClassMethod Entry(row As OcuTalon.Data.Incident, owner As %String, display As %String, online As %Boolean, Output entry As %DynamicObject) [ Private ]
{
	Set entry = ""
	Do ..ReadApprovals(row.Ref, owner, .requests, .sc)
	If $$$ISERR(sc) || '$IsObject(requests) Quit
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(row.Ref)
	Set item = $Select(groups.Count() > 0: groups.GetAt(1).ItemName, 1: "")
	Set approvals = []
	Set fixKind = ""
	For i = 1:1:requests.Count() {
		Set request = requests.GetAt(i)
		Do ..Approval(request, online, .approval)
		If $IsObject(approval) Do approvals.%Push(approval)
		If (fixKind = "") && (request.FixKind '= "") && (##class(OcuTalon.Fix.Kind).ForName(request.FixKind) '= "") Set fixKind = request.FixKind
	}
	Do ..Element(row.Element, groups, requests, .element)
	Do ..Listed(##class(OcuTalon.Watch.Msg.DiagnosisPayload).#CAUSECATEGORIES, row.CauseCategory, .category)
	Do ..Listed(##class(OcuTalon.Msg.Enum).#INCIDENTSTATE, row.State, .state)
	Do ..Shown(row.FirstAt, online, .firstFailure)
	Do ..Shown(row.LastAt, online, .lastFailure)
	Set entry = {}
	Set entry.production = $Select(display '= "": display, 1: row.Production)
	Set entry.item = item
	Set entry.count = +row.Count
	Set entry.firstFailure = firstFailure
	Set entry.lastFailure = lastFailure
	Set entry.element = element
	Set entry.causeCategory = category
	Set entry.fixKind = fixKind
	Set entry.state = state
	Set entry.approvals = approvals
}

/// The approval of one request in approval: {"answer", "channel", "answered", "fix"}, or "" for a request whose state is not one of Msg.Enum APPROVALSTATE. The
/// answer is waiting for pending; approved for approved, executing, done and failed; and rejected, expired and cancelled as they are. The time is the request's
/// ExpiresAt when it expired, its AnsweredAt when it was answered, and empty while it waits. The channel is the request's AnsweredChannel when it is one of
/// Msg.Enum CHANNEL, else empty.
ClassMethod Approval(request As %Persistent, online As %Boolean, Output approval As %DynamicObject) [ Private ]
{
	Set approval = ""
	Set state = request.State
	Set answer = $Case(state, "pending": "waiting", "approved": "approved", "executing": "approved", "done": "approved", "failed": "approved", "rejected": "rejected", "expired": "expired", "cancelled": "cancelled", : "")
	If answer = "" Quit
	Set time = $Case(state, "pending": "", "expired": request.ExpiresAt, : request.AnsweredAt)
	Do ..Listed(##class(OcuTalon.Msg.Enum).#CHANNEL, request.AnsweredChannel, .channel)
	Do ..Shown(time, online, .answered)
	Set approval = {}
	Set approval.answer = answer
	Set approval.channel = channel
	Set approval.answered = answered
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request.Ref)
	If $IsObject(run) {
		Set fix = {}
		Set fix.resent = +run.Resent
		Set fix.wentThrough = +run.Completed
		Set fix.failedAgain = +run.FailedAgain
		Do fix.%Set("finished", (run.EndedAt '= ""), "boolean")
		Do approval.%Set("fix", fix)
	} Else {
		Do approval.%Set("fix", "", "null")
	}
}

/// The element at fault in element: the text when it equals the name of one of the incident's items or the field of the fix of one of its approved requests (a
/// state of APPROVED), otherwise "".
ClassMethod Element(text As %String, groups As %ListOfObjects, requests As %ListOfObjects, Output element As %String) [ Private ]
{
	Set element = ""
	If text = "" Quit
	For i = 1:1:groups.Count() {
		If groups.GetAt(i).ItemName = text Set element = text
	}
	For i = 1:1:requests.Count() {
		If '$ListFind($ListFromString(..#APPROVED), requests.GetAt(i).State) Continue
		Do ..FixField(requests.GetAt(i), .field)
		If field = text Set element = text
	}
}

/// The field of the request's fix parameters in field, or "" when there is none.
ClassMethod FixField(request As %Persistent, Output field As %String) [ Private ]
{
	Set field = ""
	Try {
		Set parameters = {}.%FromJSON(request.FixParameters)
		If $IsObject(parameters) && (parameters.%GetTypeOf("field") = "string") Set field = parameters.field
	} Catch exception {
		Set field = ""
	}
}

/// The value in out when it is one of the comma list, otherwise "".
ClassMethod Listed(list As %String, value As %String, Output out As %String) [ Private ]
{
	Set out = $Select((value '= "") && $ListFind($ListFromString(list), value): value, 1: "")
}

/// The time as message text in text (Data.Time.ForMessage), with " ET" on the online demo as the catalog shows a time; "" for an empty or unreadable time.
ClassMethod Shown(utc As %String, online As %Boolean, Output text As %String) [ Private ]
{
	Set text = ##class(OcuTalon.Data.Time).ForMessage(utc)
	If (text '= "") && online Set text = text_" ET"
}

/// The display names of the session's own watches of productions: names(namespace, production) is the display name. A read that fails gives none.
ClassMethod WatchNames(sessionRef As %String, ByRef names) [ Private ]
{
	Kill names
	Set checks = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	If $$$ISERR(sc) || '$IsObject(checks) Quit
	For i = 1:1:checks.Count() {
		Set check = checks.GetAt(i)
		If (check.Kind = ..#KIND) && (check.DisplayName '= "") && '$Data(names(check.Namespace, check.Production)) Set names(check.Namespace, check.Production) = check.DisplayName
	}
}

}
