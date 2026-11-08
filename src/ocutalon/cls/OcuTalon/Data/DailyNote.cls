/// A person's daily note, built by code when it is read, with no model call, no storage and no cache (FR-71, AD-21; Epic 41). Lane B. Its readers are
/// Web.Api.Notes, which lists the lines, and Agent.Input, which renders the notes of today and yesterday at a session start.
/// The note of a session for one local day of the instance zone (Data.Time, AD-18) is one line for each of these records of the day, in time order:
///   - each of the session's own messages that was not refused (Turn, by CreatedAt);
///   - each decide decision of the session (Decision, by RecordedAt);
///   - each incident that the session sees (Incident, by NoticedAt);
///   - each approval request that the session sees (ApprovalRequest, by AnsweredAt, else RaisedAt);
///   - each reminder of the session, in every state (Reminder, by DueAt).
/// Entries at the same second follow the order above, then the row ID. Every read goes through Data.Ownership (AD-4), which is the only place that
/// prepares SQL; a failed read throws.
/// A line holds only code-held machine values (times, channels, outcomes, states, kinds, answers, fix kinds, counts, the names of a namespace and
/// a production), the opening of the person's own message (Conversation.Summary of Turn.Text) and a reminder's Text, which comes from a person's
/// untainted turn, because the gate denies set_reminder in an untrusted or tainted turn (AD-10 3a, AD-21). A note never holds an item's Sender,
/// Subject or body, a decision's Summary, Reasons or Payload, a turn's ReplyText, an incident's Cause, FixSummary, SampleError or ItemNoun, an approval
/// request's ToolArguments, DryRun, Result or ToolName, or any event-log text. Control characters are stripped from every value, so a value never
/// breaks a line.
/// The text is cut at MAXCHARS characters, line feeds included: whole lines from the earliest, then the line MORE as the last line, and only when an
/// entry was left out.
Class OcuTalon.Data.DailyNote
{

/// The most characters a note holds, line feeds included.
Parameter MAXCHARS = 2000;

/// The last line of a note that was cut: it is added only when an entry was left out.
Parameter MORE = "(more not shown)";

/// A decide decision whose channel is known. The slots are {time}, hh:mm in the instance zone, {channel} and {outcome}.
Parameter LINEDECISION = "{time} decision ({channel}): {outcome}";

/// A decide decision with no channel: no turn made it and no model call served it.
Parameter LINEDECISIONBARE = "{time} decision: {outcome}";

/// A message of the person. The slots are {time}, {channel} and {text}, the opening of the message.
Parameter LINEMESSAGE = "{time} message ({channel}): {text}";

/// An incident. The slots are {time}, {namespace}, {production}, {state} and {count}.
Parameter LINEINCIDENT = "{time} incident {namespace}/{production}: {state}, {count} failures";

/// The end of an incident line whose newest fix request has a fix kind. The slot is {fixKind}.
Parameter LINEINCIDENTFIX = ", fix {fixKind}";

/// An approval request that was answered on a channel. The slots are {time}, {kind}, {channel} and {answer}.
Parameter LINEAPPROVAL = "{time} approval {kind} ({channel}): {answer}";

/// An approval request that has no answering channel.
Parameter LINEAPPROVALBARE = "{time} approval {kind}: {answer}";

/// A reminder. The slots are {time}, {text} and {state}.
Parameter LINEREMINDER = "{time} reminder due: {text} ({state})";

/// The state word of a reminder that fired late.
Parameter STATEFIREDLATE = "fired late";

/// The note of the session for one local day of the instance zone, as one text with its lines separated by line feeds; "" when there is none. day is a
/// local date, YYYY-MM-DD. "" too for an empty sessionRef, for the owners eval and instance (in any case, as the SQL equality takes them) and for a
/// day that is not a date; no read is made then. A failed read throws.
ClassMethod Build(sessionRef As %String, day As %String) As %String
{
	If ..Literal($Get(sessionRef)) Quit ""
	Set from = ..DayStart($Get(day))
	If from = "" Quit ""
	Try {
		Set next = $ZDate($ZDateH(day, 3) + 1, 3)
	} Catch {
		Set next = ""
	}
	Set to = ..DayStart(next)
	If to = "" Quit ""
	Kill entries
	Do ..Messages(sessionRef, from, to, .entries)
	Do ..Decisions(sessionRef, from, to, .entries)
	Do ..Incidents(sessionRef, from, to, .entries)
	Do ..Approvals(sessionRef, from, to, .entries)
	Do ..Reminders(sessionRef, from, to, .entries)
	Quit ..Cut(.entries)
}

/// 1 for an empty owner and for the owners eval and instance, which no session is.
ClassMethod Literal(ref As %String) As %Boolean [ Private ]
{
	Set collated = $SYSTEM.Util.Collation(ref, 7)
	Quit (ref = "") || (collated = $SYSTEM.Util.Collation(##class(OcuTalon.Data.Ownership).#INSTANCE, 7)) || (collated = $SYSTEM.Util.Collation(##class(OcuTalon.Data.Ownership).#EVAL, 7))
}

/// The UTC time of the first instant of the local day (YYYY-MM-DD), "" when it is not a date.
ClassMethod DayStart(day As %String) As %String [ Private ]
{
	If day '? 4N1"-"2N1"-"2N Quit ""
	Quit ##class(OcuTalon.Data.Time).FromLocal(day_"T00:00:00")
}

/// The text of the entries, which are entries(utc, rank, id) = line, cut at MAXCHARS.
ClassMethod Cut(ByRef entries) As %String [ Private ]
{
	Set lines = "", size = 0, total = 0
	Set utc = ""
	For {
		Set utc = $Order(entries(utc))
		Quit:utc=""
		Set rank = ""
		For {
			Set rank = $Order(entries(utc, rank))
			Quit:rank=""
			Set id = ""
			For {
				Set id = $Order(entries(utc, rank, id), 1, line)
				Quit:id=""
				Set lines = lines_$ListBuild(line)
				Set size = size + 1
				Set total = total + $Length(line) + $Select(size > 1: 1, 1: 0)
			}
		}
	}
	If total <= ..#MAXCHARS Quit $ListToString(lines, $Char(10))
	Set text = ""
	Set position = 0
	While $ListNext(lines, position, line) {
		Set next = text_$Select(text = "": "", 1: $Char(10))_line
		If $Length(next_$Char(10)_..#MORE) > ..#MAXCHARS Quit
		Set text = next
	}
	Quit text_$Select(text = "": "", 1: $Char(10))_..#MORE
}

/// The session's own messages of the window.
ClassMethod Messages(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).NoteTurns(sessionRef, from, to, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set time = ..Time(row.CreatedAt)
		If time = "" Continue
		Set entries(row.CreatedAt, 1, row.%Id()) = ..Fill(..#LINEMESSAGE, $ListBuild("time", "channel", "text"), $ListBuild(time, row.Channel, ##class(OcuTalon.Core.Conversation).Summary(row.Text)))
	}
}

/// The session's decide decisions of the window. The channel of a decision that a turn of the session made is the turn's; any other decision's is the
/// channel of its own usage rows, and a decision with none has no channel.
ClassMethod Decisions(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).NoteDecisions(sessionRef, from, to, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set time = ..Time(row.RecordedAt)
		If (time = "") || (row.Outcome = "") Continue
		Set turn = ..TurnOf(row.ItemId, sessionRef, .sc)
		Do ..Check(sc)
		If $IsObject(turn) {
			Set channel = turn.Channel
		} Else {
			Set channel = ..UsageChannel(row.Ref, sessionRef, .sc)
			Do ..Check(sc)
		}
		Set names = $ListBuild("time", "channel", "outcome"), values = $ListBuild(time, channel, row.Outcome)
		Set entries(row.RecordedAt, 2, row.%Id()) = ..Fill($Select(..Clean(channel) = "": ..#LINEDECISIONBARE, 1: ..#LINEDECISION), names, values)
	}
}

/// The incidents of the window that the session sees, with the fix kind of the incident's newest fix request that has one.
ClassMethod Incidents(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).NoteIncidents(sessionRef, from, to, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set time = ..Time(row.NoticedAt)
		If time = "" Continue
		Set line = ..Fill(..#LINEINCIDENT, $ListBuild("time", "namespace", "production", "state", "count"), $ListBuild(time, row.Namespace, row.Production, row.State, row.Count))
		Set requests = ..FixRequests(row.Ref, sessionRef, .sc)
		Do ..Check(sc)
		Set fixKind = ""
		For j = requests.Count():-1:1 {
			Set request = requests.GetAt(j)
			If (request.Kind = "fix") && (request.FixKind '= "") {
				Set fixKind = request.FixKind
				Quit
			}
		}
		If fixKind '= "" Set line = line_..Fill(..#LINEINCIDENTFIX, $ListBuild("fixKind"), $ListBuild(fixKind))
		Set entries(row.NoticedAt, 3, row.%Id()) = line
	}
}

/// The session's turn made from the Item with the ItemId (Ownership.TurnOfItem), or ""; sc is the status of the read.
ClassMethod TurnOf(itemId As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).TurnOfItem(itemId, sessionRef, .sc)
}

/// The channel of the decision's own usage rows (Ownership.DecisionChannel), or ""; sc is the status of the read.
ClassMethod UsageChannel(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).DecisionChannel(decisionRef, sessionRef, .sc)
}

/// The approval requests of the incident that the session sees (Ownership.IncidentApprovals), by RaisedAt; sc is the status of the read.
ClassMethod FixRequests(incidentRef As %String, sessionRef As %String, Output sc As %Status) As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).IncidentApprovals(incidentRef, sessionRef, .sc)
}

/// The approval requests of the window that the session sees. The answer is approved or rejected when the request was answered with approve or reject,
/// and otherwise the request's State.
ClassMethod Approvals(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).NoteApprovals(sessionRef, from, to, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set at = $Select(row.AnsweredAt '= "": row.AnsweredAt, 1: row.RaisedAt)
		Set time = ..Time(at)
		If time = "" Continue
		Set answer = $Case(row.AnsweredAction, "approve": "approved", "reject": "rejected", : row.State)
		Set names = $ListBuild("time", "kind", "channel", "answer"), values = $ListBuild(time, row.Kind, row.AnsweredChannel, answer)
		Set entries(at, 4, row.%Id()) = ..Fill($Select(..Clean(row.AnsweredChannel) = "": ..#LINEAPPROVALBARE, 1: ..#LINEAPPROVAL), names, values)
	}
}

/// The session's reminders of the window, in every state.
ClassMethod Reminders(sessionRef As %String, from As %String, to As %String, ByRef entries) [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).NoteReminders(sessionRef, from, to, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set time = ..Time(row.DueAt)
		If time = "" Continue
		Set state = $Select((row.State = "fired") && row.Late: ..#STATEFIREDLATE, 1: row.State)
		Set entries(row.DueAt, 5, row.%Id()) = ..Fill(..#LINEREMINDER, $ListBuild("time", "text", "state"), $ListBuild(time, row.Text, state))
	}
}

/// hh:mm of a UTC time on its own local day, "" when the time is unreadable.
ClassMethod Time(utc As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).ForMessage(utc, utc)
}

/// Throws the status when it is an error: a failed read is never an empty note.
ClassMethod Check(sc As %Status) [ Private ]
{
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
}

/// The value without control characters.
ClassMethod Clean(value As %String) As %String [ Private ]
{
	Quit $ZStrip(value, "*C")
}

/// The template with each {name} replaced, in one pass, by the value at its position in names (the values with control characters stripped); a value is never
/// searched for slots.
ClassMethod Fill(template As %String, names As %List, values As %List) As %String [ Private ]
{
	Set text = ""
	Set rest = template
	While rest '= "" {
		Set open = $Find(rest, "{")
		If open = 0 {
			Set text = text_rest
			Quit
		}
		Set close = $Find(rest, "}", open)
		If close = 0 {
			Set text = text_rest
			Quit
		}
		Set slot = $Extract(rest, open, close - 2)
		Set at = $ListFind(names, slot)
		Set text = text_$Extract(rest, 1, open - 2)_$Select(at > 0: ..Clean($List(values, at)), 1: "{"_slot_"}")
		Set rest = $Extract(rest, close, *)
	}
	Quit text
}

}
