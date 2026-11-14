/// The ownership API (AD-4): the one way the REST surface and the production's jobs resolve the caller's session and
/// read what a session owns. Lane B.
///   - SessionRef resolves the caller's session from the CSP session, never from the client and never from the user
///     name; Attach records the user's durable session in the CSP session.
///   - On the online demo (onlineDemo on) the session is a visitor's, not the user's (DW-16, Story 16.3): the shared demo
///     account signs in many times, so SessionRef resolves only a Ref that the sign-in recorded in the CSP session
///     (Resume of the visitor's cookie, or StartVisitor), and a CSP session without one gets "" and an error. It never
///     attaches by user name there.
///   - Every read takes the session's Ref and returns only that session's records: its turns (and, for Conversation's
///     queue, the turn of a page's clientId, the queued and running turns, and the newest turn with a reply decision;
///     for a decision's trace target, the turn of an Item, TurnOfItem),
///     pending reminders, background checks, decisions (and one decision by its Ref), the usage rows of a turn's two
///     decisions or since a time, the session's heartbeat check-ins and cost in the cap's day (HeartbeatToday), noticed incidents, pending approval requests, pairing, the heartbeat row (Heartbeat), and the web copies of the notice
///     cards (RecentNotices), the messages of the simulated phone (RecentPhone), the emails of the simulated mailbox
///     (RecentMail), the session's own decide decision of an Item (DecisionOfItem) and the delivery of an approval message
///     (DeliveryFor), and the delivery of a notice by the notice's Ref (DeliveryByRef).
///     On a local install (onlineDemo off) a session also sees the noticed incidents of owner instance, and their
///     pending approval requests, for the productions its own checks watch. A record of owner eval is never visible.
///   - The snapshot's chat reads only the newest turns, the newest noticed incidents and the newest notice cards
///     (RecentTurns, RecentIncidents, RecentNotices), so that a long session's snapshot does not open and serialize every
///     row (DW-65).
///   - A find (Incident, Approval, Decision) answers "" for a record the session can't see, exactly as for a missing one,
///     so the REST surface answers both with 404.
///   - TurnCost and RunCost (AD-20) total the usage rows of one owner: the turn's own session, or the session given. A row
///     of owner eval, instance or another session is never counted, and neither total reads a record that has no owner.
///   - The reads run as the signed-in user, who holds no SQL privilege on the tables, so Rows prepares its statements
///     without the privilege check (AD-13 as amended, inbox U-15). Rows is the one such method of this class: its
///     statements are fixed texts, one per row kind; each has the owner check in its WHERE clause, bound to the owner's
///     Ref that the caller holds: SessionRef()'s value, or the session Ref of a record the product itself wrote (a row read
///     through this class, a Turn row, the owner of a bridge event), never request input.
///   - Epic 4's guide reads (ReminderSetOrFired, NewestIncident, IncidentInProgress, IncidentApprovals, LatestBreakFeedRun,
///     LastEvent) are Rows kinds like the others: the session's newest pending or fired reminder, the newest visible incident
///     of a production (noticed since a time, or open), the visible approval requests of an incident, the newest Break the
///     feed run and the newest live event of a type on the session's stream. ResolvedIncidents, which Break the feed's press
///     reads, is the session's own noticed resolved incidents of a production, oldest first, and never an instance incident.
///   - PendingToolCalls (Story 21.4) counts the pending tool_call approval requests of an MCP server's toolref across owners, with Approval CancelPending's own predicate, for
///     the removal dialog: it reads across owners, so it prepares with the privilege check and runs only in production jobs and tests.
///   - Watchers, ActiveVisitors, AllowanceHeld, AdminSessions and ApprovalIncident read across owners, so they prepare with the privilege
///     check, report a failed read in sc, and run only in production jobs and tests.
///   - The online demo's allowances (Story 16.9) read through three more: IncomingMail, the session's own count of incoming
///     simulated emails since a time (a Rows kind), and ActiveVisitors and AllowanceHeld above. PartnerNotices (Story 23.5) is the session's own count of the delay notices
///     it sent since a time (outgoing mailbox rows that carry an ApprovalRef), the other part of the email limit. RecentTurns leaves out a refused
///     turn, and RecentNotices includes the allowance cards and the digest cards (Story 17.10) and the summary cards (Story 23.6).
///   - The Documents page's reads (Story 34.2) are Rows kinds too: Documents, the session's own documents (and on a local install those of
///     owner instance, which every user shares), newest first, and Document, one by its Ref; a document the session can't see answers "".
///   - Upload (Story 34.3) is the session's own upload by its Ref, a Rows kind too; Data.Upload's Take and Drop read through it, and an upload of
///     another session answers "", exactly as for a missing one.
///   - SentFile (Story 25.3) is the session's own sent file by its Ref, a Rows kind too; Core.Files reads through it (Open for the bytes, Describe for the rest), and a file of
///     another session answers "", exactly as for a missing one.
///   - FinishedToolCalls (Story 31.2) is the session's own tool_call approval requests that finished in a window of FinishedAt, oldest
///     first: Conversation's code-written note to the next turn reads it (AD-30). It is a Rows kind like the others.
///   - Precedents and Precedent (Story 41.2) are the session's own precedents (Data.Precedent), newest answer first, and one by its Ref; Rows kinds too. A row of
///     another session or of owner eval, and a row that has an EvalRunRef, answers like a missing one.
///   - Memories, Memory and MemoryTotal (Story 41.9) are the session's own memories (Data.Memory), newest SavedAt first and then newest ID first, one by its Ref, and the session's
///     count of them; Rows kinds too, so that the Memory card's list is read as the signed-in user, who has no SQL privilege (and no search service). A row of another session answers
///     like a missing one, and the count is the session's own. The search is not here: it is the SearchMemory verb's, which MemoryOps answers.
///   - PhoneDecision (Story 41.5) is the DecisionRef of the session's own phone tell-now Delivery row for a simulated phone message's Ref; a Rows kind too.
///   - The daily note's reads (Story 41.3) are Rows kinds too, each owner-scoped and each in a window [from, to) of UTC times: NoteTurns (the session's turns that are not
///     refused, by CreatedAt), NoteDecisions (its decide decisions, by RecordedAt), NoteIncidents (the incidents it sees, as Incidents does, by NoticedAt), NoteApprovals (the
///     requests it sees, as Approvals does, placed by AnsweredAt, else RaisedAt) and NoteReminders (its reminders of every state, by DueAt). DecisionChannel is the Channel of a
///     decision's own usage rows. A window with an empty bound gives an empty list and an error status in sc.
///   - DecisionServed (Story 41.12) is whether a decision has any usage row of the session.
///   - Usage (Story 37.2) is the session's own Usage rows of the last 1, 7 or 30 instance-zone local days, summed into buckets of local date, agent, channel, model and
///     Estimated, for the Usage page; it is a Rows kind (usage) summed by Sum, and a row of owner eval, instance or another session is never read.
///   - HistoryDecisions and HistoryIncidents (Story 25.2) are one page of HISTORYPAGE rows of the History page, newest first, with the page count: the session's own decide
///     decisions filtered by outcome, channel (through the session's own usage rows), local day and fallback, and the incidents it sees, as Incidents does. They are Rows kinds
///     (historyDecisions, historyDecisionTotal, historyIncidents, historyIncidentTotal), and a row of owner eval, instance or another session is never read.
Class OcuTalon.Data.Ownership
{

/// The key of the CSP session's data that holds the durable session's Ref.
Parameter SESSIONKEY = "OcuTalon.SessionRef";

/// The owner literal of an instance-wide record.
Parameter INSTANCE [ Final ] = "instance";

/// The owner literal of an evaluation record, which no session sees.
Parameter EVAL [ Final ] = "eval";

/// The rows of one page of the History page's lists.
Parameter HISTORYPAGE = 25;

/// The highest page number of the History page's lists.
Parameter HISTORYPAGEMAX = 9999;

/// The WHERE text of the History page's decisions, with its owner check and its ten bound filter values (outcome three times, the fallback flag and value, the day marker and
/// its window, the channel twice). A filter is applied only when its first value is empty: an empty bound value is NULL in dynamic SQL, so the test is IS NULL. A fallback decision
/// is a Tell now one, as the chip shows it. The channel is that of a usage row of the same owner and decision (DecisionChannel's source).
Parameter HISTORYDECISIONS [ Final ] = "d.OwnerRef = ? AND d.Kind = 'decide' AND (? IS NULL OR (d.Fallback = 1 AND ? = 'tellnow') OR (d.Fallback = 0 AND d.Outcome = ?)) AND (? IS NULL OR d.Fallback = ?) AND (? IS NULL OR (d.RecordedAt >= ? AND d.RecordedAt < ?)) AND (? IS NULL OR EXISTS (SELECT 1 FROM OcuTalon_Bridge_Data.Usage u WHERE u.OwnerRef = d.OwnerRef AND u.DecisionRef = d.Ref AND u.Channel = ?))";

/// The condition on an incident row i that the incident statements share: it is noticed, and it is the owner's or, on a
/// local install, an instance incident of a production the owner's checks watch. Three ?: the owner, the local flag and
/// the owner again (o, a, o).
Parameter INCIDENTVISIBLE [ Final ] = "i.NoticedAt <> '' AND (i.OwnerRef = ? OR (? = 1 AND i.OwnerRef = 'instance' AND EXISTS (SELECT 1 FROM OcuTalon_Data.BackgroundCheck c WHERE c.SessionRef = ? AND c.Kind = 'production' AND c.Namespace = i.Namespace AND c.Production = i.Production)))";

/// The condition on an approval request row a that the approval statements share: it is the owner's or, on a local
/// install, an instance request of a visible incident of a production the owner's checks watch. Three ?: the owner, the
/// local flag and the owner again (o, a, o).
Parameter APPROVALVISIBLE [ Final ] = "(a.OwnerRef = ? OR (? = 1 AND a.OwnerRef = 'instance' AND EXISTS (SELECT 1 FROM OcuTalon_Data.Incident i WHERE i.Ref = a.IncidentRef AND i.OwnerRef = 'instance' AND i.NoticedAt <> '' AND EXISTS (SELECT 1 FROM OcuTalon_Data.BackgroundCheck c WHERE c.SessionRef = ? AND c.Kind = 'production' AND c.Namespace = i.Namespace AND c.Production = i.Production))))";

/// The cost of one turn (AD-20), as an object: the sums of the Usage rows of the turn's two decisions (TriageDecisionRef
/// and TurnDecisionRef) that belong to the turn's own session, {"inputTokens", "outputTokens", "cacheReadTokens",
/// "cacheWriteTokens", "costUSD"}, each 0 when the turn has no usage rows. An unknown turn gives {} and an error status
/// in sc, and so does a failed read. turnRef comes from a row read through this class or held by Conversation, never from
/// request input.
ClassMethod TurnCost(turnRef As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $SYSTEM.Status.OK()
	Set turn = $Select(turnRef = "": "", 1: ##class(OcuTalon.Data.Turn).RefIndexOpen(turnRef))
	If '$IsObject(turn) {
		Set sc = $SYSTEM.Status.Error(5001, "There is no turn to total")
		Quit {}
	}
	Set triage = turn.TriageDecisionRef
	Set reply = turn.TurnDecisionRef
	If triage = "" Set triage = reply
	If reply = "" Set reply = triage
	Set rows = ""
	If triage '= "" {
		Set rows = ..Rows("turnUsage", turn.SessionRef, .sc, triage, reply)
		If $SYSTEM.Status.IsError(sc) Quit {}
	}
	Set cost = {}
	Do ..Sum(rows, cost)
	Quit cost
}

/// The cost of the session's runs since a UTC time (an empty since counts all), as an object: {"decisions", "inputTokens",
/// "outputTokens", "cacheReadTokens", "cacheWriteTokens", "costUSD", "models"}. decisions counts the session's Decision rows
/// recorded since then, the totals sum its Usage rows recorded since then, and models holds the model ids of those Usage
/// rows in the order of first use. A record of owner eval, instance or another session is never counted. A failed read
/// gives {} and an error status in sc.
ClassMethod RunCost(sessionRef As %String, since As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $SYSTEM.Status.OK()
	If $Get(since) = "" Set since = "0000-01-01T00:00:00Z"
	Set usage = ..Rows("runUsage", sessionRef, .sc, since)
	If $SYSTEM.Status.IsError(sc) Quit {}
	Set decisions = ..Rows("runDecisions", sessionRef, .sc, since)
	If $SYSTEM.Status.IsError(sc) Quit {}
	Set cost = {"decisions": (decisions.Count())}
	Do ..Sum(usage, cost, .models)
	Set cost.models = models
	Quit cost
}

/// The session's heartbeat activity in the daily cap's day (Story 39.5; AD-20), as an object: {"checkIns", "costUSD"}, both numbers. The
/// rows are the session's own Usage rows of Channel heartbeat recorded from the first instant of the instance-zone local date of now up to
/// the first instant of the next date (the day of Bridge.Budget, from Data.Time, AD-18). checkIns is the count of their distinct non-empty
/// ItemIds (the beats that reached the model; an Act's read-only turn shares the beat's Item), costUSD the sum of their CostUSD. A row of
/// owner eval, instance or another session, of another channel or of another day is never counted. CheckInCost sums the same rows of one
/// ItemId with no day bound, so a check-in whose rows all fall in this day costs the same in both. A failed read gives {} and an error status in sc.
ClassMethod HeartbeatToday(sessionRef As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $SYSTEM.Status.OK()
	Set date = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Set from = ##class(OcuTalon.Data.Time).FromLocal(date_"T00:00:00")
	Set next = $ZDate($ZDateH(date, 3) + 1, 3)
	Set to = ##class(OcuTalon.Data.Time).FromLocal(next_"T00:00:00")
	If (from = "") || (to = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The day of the heartbeat check-ins could not be worked out")
		Quit {}
	}
	Set usage = ..Rows("heartbeatUsage", sessionRef, .sc, from, to)
	If $SYSTEM.Status.IsError(sc) Quit {}
	Kill seen
	Set items = 0, usd = 0
	For i = 1:1:usage.Count() {
		Set row = usage.GetAt(i)
		Set usd = usd + row.CostUSD
		If (row.ItemId '= "") && '$Data(seen(row.ItemId)) {
			Set seen(row.ItemId) = ""
			Set items = items + 1
		}
	}
	Set today = {}
	Do today.%Set("checkIns", items, "number")
	Do today.%Set("costUSD", usd, "number")
	Quit today
}

/// The cost of one heartbeat check-in (Story 39.9; AD-20), as an object shaped like TurnCost's: the sums of the session's own Usage rows of
/// Channel heartbeat that carry the check-in's ItemId, {"inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "costUSD"}.
/// They are the rows HeartbeatToday counts for that Item, of any day (no day bound): the decision and, on an Act, its read-only turn. A row of
/// another session, of another channel or of another Item is never counted. An empty itemId or a failed read gives {} and an error status in sc. itemId comes
/// from a HeartbeatBeat row read through this class, never from request input.
ClassMethod CheckInCost(sessionRef As %String, itemId As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $SYSTEM.Status.OK()
	If itemId = "" {
		Set sc = $SYSTEM.Status.Error(5001, "There is no check-in to total")
		Quit {}
	}
	Set rows = ..Rows("checkInUsage", sessionRef, .sc, itemId)
	If $SYSTEM.Status.IsError(sc) Quit {}
	Set cost = {}
	Do ..Sum(rows, cost)
	Quit cost
}

/// The session's own Usage rows of the last days instance-zone local days (1, 7 or 30), today included (Story 37.2; AD-20, AD-18), as an object
/// {"days", "buckets"}. days lists the local dates YYYY-MM-DD, oldest first and today last. The rows are those recorded from the first instant of the
/// first date up to the first instant of the day after today (Data.Time). buckets holds one object for each distinct (local date of RecordedAt,
/// Agent, Channel, Model, Estimated), ordered by that key: {"day", "agent", "channel", "model", "estimated", "inputTokens", "outputTokens",
/// "cacheReadTokens", "cacheWriteTokens", "costUSD", "largestRequestTokens"}. The five totals are Sum's (a NULL cost counts 0), so the buckets add
/// up to what RunCost totals for the same rows; largestRequestTokens is the largest of the bucket's rows. No row id, Ref or owner is in the result.
/// A row of owner eval, instance or another session is never counted. A days that is not a whole number from 1 to 30, a row whose time cannot be read
/// and a failed read give {} and an error status in sc.
ClassMethod Usage(sessionRef As %String, days As %Integer, Output sc As %Status) As %DynamicObject
{
	Set sc = $SYSTEM.Status.OK()
	Set days = $Get(days)
	If (days '? 1.2N) || (days < 1) || (days > 30) {
		Set sc = $SYSTEM.Status.Error(5001, "The range of the usage read is 1 to 30 days")
		Quit {}
	}
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Set first = $ZDate($ZDateH(today, 3) - (days - 1), 3)
	Set next = $ZDate($ZDateH(today, 3) + 1, 3)
	Set from = ##class(OcuTalon.Data.Time).FromLocal(first_"T00:00:00")
	Set to = ##class(OcuTalon.Data.Time).FromLocal(next_"T00:00:00")
	If (from = "") || (to = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The days of the usage read could not be worked out")
		Quit {}
	}
	Set rows = ..Rows("usage", sessionRef, .sc, from, to)
	If $SYSTEM.Status.IsError(sc) Quit {}
	Kill group
	Set unreadable = 0
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set day = $Piece(##class(OcuTalon.Data.Time).ToLocal(row.RecordedAt), "T", 1)
		If day = "" Set unreadable = 1 Quit
		Set key = day_$Char(1)_row.Agent_$Char(1)_row.Channel_$Char(1)_row.Model_$Char(1)_(+row.Estimated)
		If '$Data(group(key)) Set group(key) = ##class(%ListOfObjects).%New()
		Do group(key).Insert(row)
	}
	If unreadable {
		Set sc = $SYSTEM.Status.Error(5001, "A usage row has a time that cannot be read")
		Quit {}
	}
	Set dates = []
	For i = (days - 1):-1:0 Do dates.%Push($ZDate($ZDateH(today, 3) - i, 3))
	Set buckets = []
	Set key = ""
	For {
		Set key = $Order(group(key))
		If key = "" Quit
		Set list = group(key)
		Set bucket = {}
		Do bucket.%Set("day", $Piece(key, $Char(1), 1))
		Do bucket.%Set("agent", $Piece(key, $Char(1), 2))
		Do bucket.%Set("channel", $Piece(key, $Char(1), 3))
		Do bucket.%Set("model", $Piece(key, $Char(1), 4))
		Do bucket.%Set("estimated", +$Piece(key, $Char(1), 5), "boolean")
		Do ..Sum(list, bucket)
		Set largest = 0
		For i = 1:1:list.Count() {
			If list.GetAt(i).LargestRequestTokens > largest Set largest = list.GetAt(i).LargestRequestTokens
		}
		Do bucket.%Set("largestRequestTokens", largest, "number")
		Do buckets.%Push(bucket)
	}
	Quit {"days": (dates), "buckets": (buckets)}
}

/// Sets the four token totals and the cost of the Usage rows (none when rows is not a list) in cost, 0 for a total with no
/// rows, and returns the model ids of the rows in the order of first use in models.
ClassMethod Sum(rows As %ListOfObjects, cost As %DynamicObject, Output models As %DynamicArray) [ Private ]
{
	Set models = []
	Kill seen
	Set input = 0, output = 0, cacheRead = 0, cacheWrite = 0, usd = 0
	For i = 1:1:$Select($IsObject(rows): rows.Count(), 1: 0) {
		Set row = rows.GetAt(i)
		Set input = input + row.InputTokens
		Set output = output + row.OutputTokens
		Set cacheRead = cacheRead + row.CacheReadTokens
		Set cacheWrite = cacheWrite + row.CacheWriteTokens
		Set usd = usd + row.CostUSD
		If (row.Model '= "") && '$Data(seen(row.Model)) {
			Set seen(row.Model) = ""
			Do models.%Push(row.Model)
		}
	}
	Set cost.inputTokens = input
	Set cost.outputTokens = output
	Set cost.cacheReadTokens = cacheRead
	Set cost.cacheWriteTokens = cacheWrite
	Set cost.costUSD = usd
}

/// The Ref of the caller's durable session. It is the Ref recorded in the CSP session when that session row exists
/// and belongs to the signed-in user (matched without regard to case); otherwise, on a local install, the user's durable
/// session is attached first, and on the online demo (onlineDemo on) the result is "" and sc an error, with nothing attached
/// or created. With no CSP session the result is "" and sc an error. This is the one resolution method.
ClassMethod SessionRef(Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If '$IsObject($Get(%session)) {
		Set sc = $SYSTEM.Status.Error(5001, "There is no CSP session to take the OcuTalon session from")
		Quit ""
	}
	Set ref = $Get(%session.Data(..#SESSIONKEY))
	If ref '= "" {
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		If $IsObject(row), $ZConvert(row.IrisUser, "U") = $ZConvert($Username, "U") Quit ref
	}
	If ..LocalFlag() = 0 {
		Set sc = $SYSTEM.Status.Error(5001, "This CSP session has no OcuTalon session of the signed-in user")
		Quit ""
	}
	Set sc = ..Attach()
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit $Get(%session.Data(..#SESSIONKEY))
}

/// The online demo's resume (AD-4): the row that the resume reference opens (Session.ForResume), when it belongs to the
/// signed-in user (matched without regard to case, as SessionRef matches it). The row's CspSessionId becomes the CSP
/// session's id, whatever it was, and its Ref is recorded in the CSP session. Returns the Ref, or "" with sc OK when the
/// reference opens no row of the user (the caller then starts a visitor), or "" with an error status when the row can't be
/// saved or there is no CSP session. The reference is never written anywhere.
ClassMethod Resume(reference As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If '$IsObject($Get(%session)) {
		Set sc = $SYSTEM.Status.Error(5001, "There is no CSP session to attach the OcuTalon session to")
		Quit ""
	}
	Set row = ##class(OcuTalon.Data.Session).ForResume(reference)
	If '$IsObject(row) || ($ZConvert(row.IrisUser, "U") '= $ZConvert($Username, "U")) Quit ""
	Set row.CspSessionId = %session.SessionId
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set %session.Data(..#SESSIONKEY) = row.Ref
	Quit row.Ref
}

/// The online demo's first sign-in of a browser: a new row for the signed-in user (Session.NewVisitor) that records the
/// CSP session's id, and its Ref in the CSP session. reference is the new resume reference, for the caller's cookie alone.
/// Returns the Ref, or "" with an error status.
ClassMethod StartVisitor(Output reference As %String, Output sc As %Status) As %String
{
	Set reference = ""
	If '$IsObject($Get(%session)) {
		Set sc = $SYSTEM.Status.Error(5001, "There is no CSP session to attach the OcuTalon session to")
		Quit ""
	}
	Set row = ##class(OcuTalon.Data.Session).NewVisitor($Username, %session.SessionId, .reference, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set %session.Data(..#SESSIONKEY) = row.Ref
	Quit row.Ref
}

/// Finds or creates the IRIS user's one durable session (Session.ForUser) and records its Ref in the CSP session. admin is the sign-in's
/// answer to "does the user hold OcuTalonAdmin" (0 or 1, AD-21): when it is 0 or 1 and differs from the row's AdminAtSignIn, the row takes it
/// and is saved. The attach holds even when that save fails, and the failed save is the answer. "" (an attach on a first API call) leaves the
/// flag as the latest sign-in set it.
ClassMethod Attach(irisUser As %String = {$Username}, admin As %String = "") As %Status
{
	If '$IsObject($Get(%session)) Quit $SYSTEM.Status.Error(5001, "There is no CSP session to attach the OcuTalon session to")
	Set row = ##class(OcuTalon.Data.Session).ForUser(irisUser, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set %session.Data(..#SESSIONKEY) = row.Ref
	If ((admin = 0) || (admin = 1)) && (admin '= row.AdminAtSignIn) {
		Set row.AdminAtSignIn = admin
		Quit row.%Save()
	}
	Quit $SYSTEM.Status.OK()
}

/// The session's turns, by CreatedAt and then ID. sc is an error status when the read failed.
ClassMethod Turns(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("turns", sessionRef, .sc)
}

/// The session's newest turns, newest CreatedAt first and then newest ID first, at most max. A refused turn (State refused,
/// the record of a message the allowance turned away, AD-20) is not one of them: the chat never shows it. sc is an error
/// status when the read failed.
ClassMethod RecentTurns(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentTurns", sessionRef, .sc, +max)
}

/// The session's turn that came from the page's message with this clientId, or "" when it has none or clientId is empty.
/// clientId may come from request input; it is only ever a bound value.
ClassMethod TurnByClient(sessionRef As %String, clientId As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	Set sc = $SYSTEM.Status.OK()
	If clientId = "" Quit ""
	Set rows = ..Rows("turnByClient", sessionRef, .sc, clientId)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's turn that was made from the Item message with this ItemId, or "": a turn of another session, an unknown
/// ItemId, an empty one, and one that differs only in case all answer like a missing one. The statement narrows the rows by
/// the collated index; the value is then compared exactly. itemId comes from a decision row the product wrote; it is only
/// ever a bound value, and sessionRef is that row's owner, never request input. sc is an error status when the read failed.
ClassMethod TurnOfItem(itemId As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	Set sc = $SYSTEM.Status.OK()
	If itemId = "" Quit ""
	Set rows = ..Rows("turnOfItem", sessionRef, .sc, itemId)
	Set found = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If row.ItemId = itemId {
			Set found = row
			Quit
		}
	}
	Quit found
}

/// The session's queued and running turns, by CreatedAt and then ID: the order in which Conversation starts them.
ClassMethod TurnQueue(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("turnQueue", sessionRef, .sc)
}

/// The session's newest done turn that has a reply decision, or "": the turn whose Tainted flag decides how the next
/// turn starts. A done turn with no reply decision (an error-status fallback) is skipped.
ClassMethod LastRepliedTurn(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn
{
	Set rows = ..Rows("lastReplied", sessionRef, .sc)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's pending reminders, by DueAt.
ClassMethod Reminders(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("reminders", sessionRef, .sc)
}

/// The session's background checks, by ID.
ClassMethod Checks(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("checks", sessionRef, .sc)
}

/// The session's documents, newest AddedAt first and then newest ID first: its own on the online demo, and on a local install the
/// documents of owner instance, which every session shares (AD-4, AD-21). sc is an error status when the read failed.
ClassMethod Documents(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("documents", sessionRef, .sc, ..LocalFlag())
}

/// The upload with this Ref when it is the session's own, otherwise "": an upload of another session answers like a missing one. Ref and
/// SessionRef compare exactly (EXACT collation). ref may come from a command or request input; it is only ever a bound value.
ClassMethod Upload(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Upload
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("upload", sessionRef, .sc, ref)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The sent file with this Ref when it is the session's own, otherwise "": a file of another session answers like a missing one (Story 25.3). Ref and
/// SessionRef compare exactly (EXACT collation). ref may come from a request or an Item; it is only ever a bound value. OcuTalon.Core.Files is the only caller.
ClassMethod SentFile(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.SentFile
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("sentFile", sessionRef, .sc, ref)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The document with this Ref when the session can see it (its own, or on a local install one of owner instance), otherwise "": a
/// document of another session answers like a missing one. ref may come from request input; it is only ever a bound value.
ClassMethod Document(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Document
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("document", sessionRef, .sc, ref, ..LocalFlag())
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's newest decisions of Kind decide (the attention decision), newest RecordedAt first, at most max.
ClassMethod Decisions(sessionRef As %String, max As %Integer = 20, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("decisions", sessionRef, .sc, +max)
}

/// The session's noticed incidents, by NoticedAt: its own, and on a local install those of owner instance for the
/// productions its checks watch.
ClassMethod Incidents(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("incidents", sessionRef, .sc, ..LocalFlag())
}

/// The session's newest noticed incidents, as Incidents sees them, newest NoticedAt first and then newest ID first, at most
/// max.
ClassMethod RecentIncidents(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentIncidents", sessionRef, .sc, +max, ..LocalFlag())
}

/// One page (page, from 1) of the session's decide decisions that match the filters, newest RecordedAt first and then newest ID first, HISTORYPAGE to a page (Story 25.2;
/// AD-4, AD-13), and the number of pages (1 when there is no row) in pages. A filter that is "" is not applied: outcome is one of ignore, digest, tellnow and act (tellnow also
/// matches every fallback decision, as the chip shows it); channel is a Msg.Enum CHANNEL, matched through the session's own usage rows of the decision (a decision no model call
/// served has none, and matches only when channel is ""); day is an instance-zone local date YYYY-MM-DD (Data.Time.FromLocal); fallback is yes or no. A page past the last gives
/// an empty list. A filter or page that is not one of these, and a failed read, give an empty list and an error status in sc, and nothing is read for the first.
ClassMethod HistoryDecisions(sessionRef As %String, outcome As %String = "", channel As %String = "", day As %String = "", fallback As %String = "", page As %Integer = 1, Output pages As %Integer, Output sc As %Status) As %ListOfObjects
{
	Set sc = $SYSTEM.Status.OK()
	Set pages = 1
	Set outcome = $Get(outcome), channel = $Get(channel), day = $Get(day), fallback = $Get(fallback)
	Kill filter
	Set from = "", to = ""
	If day '= "" {
		Try {
			Set from = ##class(OcuTalon.Data.Time).FromLocal(day_"T00:00:00")
			If from '= "" Set to = ##class(OcuTalon.Data.Time).FromLocal($ZDate($ZDateH(day, 3) + 1, 3)_"T00:00:00")
		} Catch {
			Set from = "", to = ""
		}
	}
	If ((outcome '= "") && '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#OUTCOME), outcome)) || ((channel '= "") && '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), channel)) || ((fallback '= "") && (fallback '= "yes") && (fallback '= "no")) || ((day '= "") && ((from = "") || (to = ""))) {
		Set sc = $SYSTEM.Status.Error(5001, "A filter of the history read is not one of its values")
		Quit ##class(%ListOfObjects).%New()
	}
	Set filter = 10
	Set filter(1) = outcome, filter(2) = outcome, filter(3) = outcome
	Set filter(4) = fallback, filter(5) = (fallback = "yes")
	Set filter(6) = day, filter(7) = from, filter(8) = to
	Set filter(9) = channel, filter(10) = channel
	Quit ..HistoryPageOf("historyDecisionTotal", "historyDecisions", sessionRef, page, .filter, .pages, .sc)
}

/// One page (page, from 1) of the incidents the session sees, as Incidents does, newest NoticedAt first and then newest ID first, HISTORYPAGE to a page (Story 25.2), and the number
/// of pages (1 when there is no row) in pages. A page past the last gives an empty list. A page that is not a whole number from 1 to HISTORYPAGEMAX with no leading zero, and a
/// failed read, give an empty list and an error status in sc.
ClassMethod HistoryIncidents(sessionRef As %String, page As %Integer = 1, Output pages As %Integer, Output sc As %Status) As %ListOfObjects
{
	Kill filter
	Set filter = 1
	Set filter(1) = ..LocalFlag()
	Quit ..HistoryPageOf("historyIncidentTotal", "historyIncidents", sessionRef, page, .filter, .pages, .sc)
}

/// The page of a History read: the count of the rows that match (totalKind, bound by filter(1..filter)), the page count, and then the page (pageKind, bound by the same values and
/// the page's limit and offset). filter is changed.
ClassMethod HistoryPageOf(totalKind As %String, pageKind As %String, sessionRef As %String, page As %Integer, ByRef filter, Output pages As %Integer, Output sc As %Status) As %ListOfObjects [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Set pages = 1
	Set page = $Get(page)
	If (page '? 1.4N) || (+page '= page) || (page < 1) || (page > ..#HISTORYPAGEMAX) {
		Set sc = $SYSTEM.Status.Error(5001, "The page of the history read is a whole number from 1 to "_..#HISTORYPAGEMAX)
		Quit ##class(%ListOfObjects).%New()
	}
	Set total = ..Rows(totalKind, sessionRef, .sc, filter...)
	If $SYSTEM.Status.IsError(sc) Quit ##class(%ListOfObjects).%New()
	Set count = $Select(total.Count() = 0: 0, 1: +total.GetAt(1).total)
	Set pages = $Select(count < 1: 1, 1: (count - 1) \ ..#HISTORYPAGE + 1)
	If page > pages Quit ##class(%ListOfObjects).%New()
	Set filter = filter + 2
	Set filter(filter - 1) = ..#HISTORYPAGE
	Set filter(filter) = (page - 1) * ..#HISTORYPAGE
	Quit ..Rows(pageKind, sessionRef, .sc, filter...)
}

/// The session's pending approval requests, by RaisedAt: its own, and on a local install those of the visible
/// incidents of owner instance.
ClassMethod Approvals(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("approvals", sessionRef, .sc, ..LocalFlag())
}

/// The session's Telegram pairing, or "".
ClassMethod Pairing(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Pairing
{
	Set rows = ..Rows("pairing", sessionRef, .sc)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's own HeartbeatBeat row, or "". The SessionRef is compared exactly (the property has the default collation, which ignores
/// case), so a row of a Ref that differs only in case is not the session's. sc is an error status when the read failed.
ClassMethod Heartbeat(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.HeartbeatBeat
{
	Set rows = ..Rows("heartbeat", sessionRef, .sc)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's newest web notice cards: the Delivery rows of channel web and kind tellnow, reminder or allowance, and those of
/// kind approval, result, digest or summary that have a ChannelMessageId (only WebChatOut's tool-call cards, digest cards and summary cards have one; a digest row
/// of the time before the digest card, which records no text, has none), newest
/// RecordedAt first and then newest ID first, at most max. sc is an error status when the read failed.
ClassMethod RecentNotices(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentNotices", sessionRef, .sc, +max)
}

/// The session's newest simulated-phone messages: the SimMessage rows of Kind phone, newest CreatedAt first and then newest ID
/// first, at most max. sc is an error status when the read failed.
ClassMethod RecentPhone(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentPhone", sessionRef, .sc, +max)
}

/// The session's newest simulated-mailbox emails: the SimMessage rows of Kind mailbox (incoming and sent), newest CreatedAt
/// first and then newest ID first, at most max. sc is an error status when the read failed.
ClassMethod RecentMail(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentMail", sessionRef, .sc, +max)
}

/// The session's own decision of Kind decide for the Item with this ItemId, or "": a decision of another owner, a decision of
/// another kind, an unknown ItemId, an empty one, and one that differs only in case all answer like a missing one. The
/// statement narrows the rows by the collated index; the value is then compared exactly. itemId comes from a mailbox row the
/// product wrote; it is only ever a bound value. sc is an error status when the read failed.
ClassMethod DecisionOfItem(itemId As %String, ownerRef As %String, Output sc As %Status) As OcuTalon.Bridge.Data.Decision
{
	Set sc = $SYSTEM.Status.OK()
	If itemId = "" Quit ""
	Set rows = ..Rows("decisionOfItem", ownerRef, .sc, itemId)
	Set found = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.ItemId = itemId) && (row.OwnerRef = ownerRef) {
			Set found = row
			Quit
		}
	}
	Quit found
}

/// The session's newest Delivery row for the approval request and channel, or "": a row of owner eval, instance or another
/// session, a row with another approval Ref or channel, and one whose Ref differs only in case all answer like a missing
/// one. The statement narrows the rows by the collated index; the values are then compared exactly. The values may come
/// from a bridge event or request input; they are only ever bound values.
ClassMethod DeliveryFor(approvalRef As %String, channel As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Delivery
{
	Set sc = $SYSTEM.Status.OK()
	If (approvalRef = "") || (channel = "") Quit ""
	Set rows = ..Rows("deliveryByApproval", sessionRef, .sc, approvalRef, channel)
	Set found = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.ApprovalRef = approvalRef) && (row.Channel = channel) && (row.OwnerRef = sessionRef) {
			Set found = row
			Quit
		}
	}
	Quit found
}

/// The session's newest Delivery row for the notice's Ref (the DecisionRef of its rows) and channel, or "": a row of owner eval, instance
/// or another session, a row with another Ref or channel, and one whose Ref differs only in case all answer like a missing one. The
/// statement narrows the rows by OwnerRefChannelIndex; the values are then compared exactly. The values are only ever bound values.
ClassMethod DeliveryByRef(ref As %String, channel As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Delivery
{
	Set sc = $SYSTEM.Status.OK()
	If (ref = "") || (channel = "") Quit ""
	Set rows = ..Rows("deliveryByRef", sessionRef, .sc, ref, channel)
	Set found = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.DecisionRef = ref) && (row.Channel = channel) && (row.OwnerRef = sessionRef) {
			Set found = row
			Quit
		}
	}
	Quit found
}

/// The DecisionRef of the session's newest phone Delivery row of kind tellnow whose ChannelMessageId is exactly the simulated phone message's Ref, or "": a row of
/// owner eval, instance or another session, of another channel or kind, and one whose Ref differs only in case all answer like a missing one. The statement
/// narrows the rows by OwnerRefChannelIndex; the values are then compared exactly.
ClassMethod PhoneDecision(messageRef As %String, sessionRef As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If messageRef = "" Quit ""
	Set rows = ..Rows("phoneDecision", sessionRef, .sc, messageRef)
	Set found = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.ChannelMessageId = messageRef) && (row.Channel = "phone") && (row.Kind = "tellnow") && (row.OwnerRef = sessionRef) {
			Set found = row.DecisionRef
			Quit
		}
	}
	Quit found
}

/// The incident with this Ref when the session can see it (noticed; its own, or an instance incident of a watched
/// production on a local install), otherwise "": a record the session can't see answers like a missing one. ref may
/// come from request input; it is only ever a bound value.
ClassMethod Incident(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Incident
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("incident", sessionRef, .sc, ref, ..LocalFlag())
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The decision with this Ref when it is the session's own, otherwise "": a decision of owner eval, instance or another
/// session answers like a missing one. ref may come from a bridge event or request input; it is only ever a bound value.
ClassMethod Decision(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Bridge.Data.Decision
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("decision", sessionRef, .sc, ref)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The approval request with this Ref when the session can see it (its own, or one of a visible instance incident on
/// a local install), whatever its state, otherwise "". ref may come from request input; it is only ever a bound value.
ClassMethod Approval(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Bridge.Data.ApprovalRequest
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("approval", sessionRef, .sc, ref, ..LocalFlag())
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The distinct SessionRefs with a production check on the production, in SessionRef order (case-sensitive, as read
/// from the rows); empty when onlineDemo is on. It reads across sessions and has no owner, so it is not a Rows
/// statement: it is prepared with the privilege check and runs only in production jobs and tests, through
/// Session.Recipients. No request path calls it. sc is OK unless the read failed; then the result is "" and means
/// nothing, and it never means that nobody watches.
ClassMethod Watchers(namespace As %String, production As %String, Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	If '..LocalFlag() Quit ""
	If (namespace = "") || (production = "") Quit ""
	Kill found
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT SessionRef FROM OcuTalon_Data.BackgroundCheck WHERE Kind = 'production' AND Namespace = ? AND Production = ?")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(namespace, production)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the watchers failed: "_result.%Message)
			} Else {
				While result.%Next() {
					Set ref = result.%Get("SessionRef")
					If ref '= "" Set found(ref) = ""
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set watchers = ""
	Set ref = ""
	For {
		Set ref = $Order(found(ref))
		Quit:ref=""
		Set watchers = watchers_$ListBuild(ref)
	}
	Quit watchers
}

/// The Refs of the open sessions that have activity, in Ref order, as a list (AD-20): every Session row that still has its
/// ResumeHash (SessionOps.End clears it) and has a Turn (a refused one too), a Break the feed run, or an approval request of
/// its own that its user answered (AnsweredAt set, and the action approve or reject). It reads across owners and has no owner
/// check, so, like Watchers, it prepares with the privilege check and runs only in production jobs and tests (BridgeSink); no
/// request path calls it. sc is OK unless the read failed; the result is then "" and means nothing, never that nobody is active.
ClassMethod ActiveVisitors(Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	Kill found
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT %EXACT(s.Ref) AS Ref FROM OcuTalon_Data.Session s WHERE s.ResumeHash <> '' AND (EXISTS (SELECT 1 FROM OcuTalon_Data.Turn t WHERE t.SessionRef = s.Ref) OR EXISTS (SELECT 1 FROM OcuTalon_Data.BreakFeedRun b WHERE b.SessionRef = s.Ref) OR EXISTS (SELECT 1 FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.OwnerRef = s.Ref AND a.AnsweredAt <> '' AND a.AnsweredAction IN ('approve', 'reject')))")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute()
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the active sessions failed: "_result.%Message)
			} Else {
				While result.%Next() {
					Set ref = result.%Get("Ref")
					If ref '= "" Set found(ref) = ""
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit ..RefList(.found)
}

/// The Refs of the sessions whose allowance window is open at now (UTC): AllowanceUntil is later than now, in Ref order, as a
/// list (StatusMonitor). Like ActiveVisitors it reads across owners, prepares with the privilege check and runs only in
/// production jobs and tests. sc is OK unless the read failed; the result is then "" and means nothing.
ClassMethod AllowanceHeld(now As %String, Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	Kill found
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT %EXACT(Ref) AS Ref FROM OcuTalon_Data.Session WHERE AllowanceUntil > ?")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute($Get(now))
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the sessions with an allowance window failed: "_result.%Message)
			} Else {
				While result.%Next() {
					Set ref = result.%Get("Ref")
					If ref '= "" Set found(ref) = ""
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit ..RefList(.found)
}

/// The Refs of the sessions whose user held OcuTalonAdmin, by its whole name and never %All, at the session's latest sign-in
/// (Session.AdminAtSignIn, AD-21), in Ref order, as a list. It reads across owners, so it prepares with the privilege check and runs only in
/// production jobs and tests (Story 22.2's McpOps reads it). sc is OK unless the read failed; the result is then "" and means nothing.
ClassMethod AdminSessions(Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	Kill found
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT %EXACT(Ref) AS Ref FROM OcuTalon_Data.Session WHERE AdminAtSignIn = 1")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute()
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the admins' sessions failed: "_result.%Message)
			} Else {
				While result.%Next() {
					Set ref = result.%Get("Ref")
					If ref '= "" Set found(ref) = ""
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit ..RefList(.found)
}

/// The number of pending tool_call approval requests that removing the MCP server cancels (Story 21.4): the rows of OcuTalon_Bridge_Data.ApprovalRequest, of every owner, with
/// Kind tool_call, State pending and ToolSource equal to the server's toolref (Mcp.Attach Toolref), under the column's own collation, exactly as Bridge.Approval CancelPending selects
/// them. A name that Toolref refuses gives 0 and an error in sc, and so does a failed read. It reads across owners, so it prepares with the privilege check and runs only in
/// production jobs and tests.
ClassMethod PendingToolCalls(server As %String, Output sc As %Status) As %Integer
{
	Set sc = $SYSTEM.Status.OK()
	Set count = 0
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref($Get(server))
	If toolref = "" {
		Set sc = $SYSTEM.Status.Error(5001, "The name is not an MCP server name")
		Quit 0
	}
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Kind = 'tool_call' AND State = 'pending' AND ToolSource = ?")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(toolref)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the pending tool calls failed: "_result.%Message)
			} ElseIf result.%Next() {
				Set count = +result.%GetData(1)
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit 0
	Quit count
}

/// The subscripts of the array as a list, in order.
ClassMethod RefList(ByRef found) As %List [ Private ]
{
	Set refs = ""
	Set ref = ""
	For {
		Set ref = $Order(found(ref))
		Quit:ref=""
		Set refs = refs_$ListBuild(ref)
	}
	Quit refs
}

/// The number of incoming emails of the simulated mailbox that the session has after since (UTC; SimMessage rows of Kind
/// mailbox, Direction in, samples included, outgoing rows never), and, as oldest, the CreatedAt of the oldest of them ("" when
/// there is none): the count behind the online demo's email limit (Allowance.MailAllowed). sc is an error status when the read
/// failed, and the count is then 0.
ClassMethod IncomingMail(sessionRef As %String, since As %String, Output oldest As %String, Output sc As %Status) As %Integer
{
	Set oldest = ""
	Set rows = ..Rows("incomingMail", sessionRef, .sc, $Get(since))
	If $SYSTEM.Status.IsError(sc) Quit 0
	If rows.Count() > 0 Set oldest = rows.GetAt(1).CreatedAt
	Quit rows.Count()
}

/// The number of delay notices that the session has sent after since (UTC; SimMessage rows of Kind mailbox, Direction out, with an ApprovalRef: the sent mail of an approved
/// partner notice, Story 23.5; a reply has none), and, as oldest, the CreatedAt of the oldest of them ("" when there is none): the other count behind the online demo's email
/// limit (Allowance.MailAllowed). sc is an error status when the read failed, and the count is then 0.
ClassMethod PartnerNotices(sessionRef As %String, since As %String, Output oldest As %String, Output sc As %Status) As %Integer
{
	Set oldest = ""
	Set rows = ..Rows("partnerNotices", sessionRef, .sc, $Get(since))
	If $SYSTEM.Status.IsError(sc) Quit 0
	If rows.Count() > 0 Set oldest = rows.GetAt(1).CreatedAt
	Quit rows.Count()
}

/// The session's own approval requests of Kind tool_call that finished after the time after and at or before the time through (UTC
/// strings, as FinishedAt is; after "" is the start of time, bound as "0" because an empty bind is a NULL that no comparison
/// matches), by FinishedAt and then ID: a request with no FinishedAt (pending, approved or executing) is never one of them. An empty
/// through gives an empty list and an error status in sc, and so does a failed read. A request of another session or of owner
/// instance is never one of them.
ClassMethod FinishedToolCalls(sessionRef As %String, after As %String, through As %String, Output sc As %Status) As %ListOfObjects
{
	If $Get(through) = "" {
		Set sc = $SYSTEM.Status.Error(5001, "A read of finished tool calls needs the end of its window")
		Quit ##class(%ListOfObjects).%New()
	}
	Quit ..Rows("finishedToolCalls", sessionRef, .sc, $Select($Get(after) = "": "0", 1: after), through)
}

/// The session's own precedents (Data.Precedent), newest AnsweredAt first and then newest ID first, at most max. A seeded row, one with an EvalRunRef, is never
/// one of them. sc is an error status when the read failed.
ClassMethod Precedents(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("precedents", sessionRef, .sc, +max)
}

/// The precedent with this Ref when it is the session's own and not a seeded one, otherwise "": a row of another session or of owner eval answers like a
/// missing one. ref may come from request input; it is only ever a bound value.
ClassMethod Precedent(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Precedent
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("precedent", sessionRef, .sc, ref)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's own memories (Data.Memory), newest SavedAt first and then newest ID first, at most max. sc is an error status when the read failed.
ClassMethod Memories(sessionRef As %String, max As %Integer = 20, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("memories", sessionRef, .sc, +max)
}

/// The number of memories (Data.Memory) the session has; 0, with an error status in sc, when the read failed.
ClassMethod MemoryTotal(sessionRef As %String, Output sc As %Status) As %Integer
{
	Set rows = ..Rows("memoryTotal", sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) || (rows.Count() = 0) Quit 0
	Quit rows.GetAt(1).total
}

/// The memory with this Ref when it is the session's own, otherwise "": a row of another session answers like a missing one. ref may come from request input; it is only
/// ever a bound value.
ClassMethod Memory(ref As %String, sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Memory
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set rows = ..Rows("memory", sessionRef, .sc, ref)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's turns that are not refused and were created in the window [from, to) (UTC strings, as CreatedAt is), by CreatedAt and then ID. An empty bound gives an empty
/// list and an error status in sc, and so does a failed read.
ClassMethod NoteTurns(sessionRef As %String, from As %String, to As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Window("noteTurns", sessionRef, $Get(from), $Get(to), .sc)
}

/// The session's own decide decisions recorded in the window [from, to), by RecordedAt and then ID; the bounds and sc are those of NoteTurns.
ClassMethod NoteDecisions(sessionRef As %String, from As %String, to As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Window("noteDecisions", sessionRef, $Get(from), $Get(to), .sc)
}

/// The incidents that the session sees (as Incidents does) and that were noticed in the window [from, to), by NoticedAt and then ID; the bounds and sc are those of NoteTurns.
ClassMethod NoteIncidents(sessionRef As %String, from As %String, to As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Window("noteIncidents", sessionRef, $Get(from), $Get(to), .sc, ..LocalFlag())
}

/// The approval requests that the session sees (as Approvals does, in any state) whose time is in the window [from, to), by that time and then ID. A request's time is its
/// AnsweredAt when it has one, otherwise its RaisedAt. The bounds and sc are those of NoteTurns.
ClassMethod NoteApprovals(sessionRef As %String, from As %String, to As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Window("noteApprovals", sessionRef, $Get(from), $Get(to), .sc, ..LocalFlag())
}

/// The session's own reminders, in every state, that are due in the window [from, to), by DueAt and then ID; the bounds and sc are those of NoteTurns.
ClassMethod NoteReminders(sessionRef As %String, from As %String, to As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Window("noteReminders", sessionRef, $Get(from), $Get(to), .sc)
}

/// The Channel of the decision's own usage rows: the first that is not empty, by ID, or "" when there is none (a decision that no model call served has no usage row). decisionRef
/// comes from a row read through this class, never from request input. sc is an error status when the read failed.
ClassMethod DecisionChannel(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If $Get(decisionRef) = "" Quit ""
	Set rows = ..Rows("turnUsage", sessionRef, .sc, decisionRef, decisionRef)
	If $SYSTEM.Status.IsError(sc) Quit ""
	For i = 1:1:rows.Count() {
		Set channel = rows.GetAt(i).Channel
		If channel '= "" Quit
	}
	Quit $Get(channel)
}

/// 1 when the decision has at least one usage row of the session (a model call served it), else 0: the sign that a turn's request reached a model (Story 41.12, DW-967). A decision that a
/// precheck refused, or whose call threw without spending, has none. decisionRef comes from a row read through this class, never from request input. sc is an error status when the read failed;
/// the answer is then 0.
ClassMethod DecisionServed(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %Boolean
{
	Set sc = $SYSTEM.Status.OK()
	If $Get(decisionRef) = "" Quit 0
	Set rows = ..Rows("turnUsage", sessionRef, .sc, decisionRef, decisionRef)
	If $SYSTEM.Status.IsError(sc) Quit 0
	Quit rows.Count() > 0
}

/// The rows of a note kind in the window [from, to): an empty bound gives an empty list and an error status in sc, as FinishedToolCalls does for an empty end; extra is the bound
/// that the kind takes before the window (the local flag of the incident kinds), "" for none.
ClassMethod Window(kind As %String, sessionRef As %String, from As %String, to As %String, Output sc As %Status, extra As %String = "") As %ListOfObjects [ Private ]
{
	If (from = "") || (to = "") {
		Set sc = $SYSTEM.Status.Error(5001, "A read of the note needs both ends of its window")
		Quit ##class(%ListOfObjects).%New()
	}
	If extra '= "" Quit ..Rows(kind, sessionRef, .sc, extra, from, to)
	Quit ..Rows(kind, sessionRef, .sc, from, to)
}

/// The IncidentRef of the approval request whose Ref is exactly ref (case-sensitive) when its owner is instance, "" for
/// every other request, an unknown Ref and an empty one. One fixed statement narrows the rows by the collated index and
/// the Ref is then compared exactly. It reads across owners and has no session, so it is prepared with the privilege
/// check and runs only in production jobs and tests, through BridgeSink. No request path calls it. ref may come from a
/// bridge event; it is only ever a bound value. sc is OK unless the read failed; then the result is "".
ClassMethod ApprovalIncident(ref As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If ref = "" Quit ""
	Set incidentRef = ""
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT Ref, IncidentRef FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ? AND OwnerRef = 'instance'")
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(ref)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of the approval request's incident failed: "_result.%Message)
			} Else {
				While result.%Next() {
					If result.%Get("Ref") = ref {
						Set incidentRef = result.%Get("IncidentRef")
						Quit
					}
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit incidentRef
}

/// The session's newest reminder that is pending or fired (one it set, whether or not it has gone off), or "".
ClassMethod ReminderSetOrFired(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Reminder
{
	Set rows = ..Rows("reminderSetOrFired", sessionRef, .sc)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The newest incident of the production that the session sees (as Incidents does) and that was noticed at or after
/// since (an empty since counts all, as RunCost's does), or "".
ClassMethod NewestIncident(sessionRef As %String, namespace As %String, production As %String, since As %String, Output sc As %Status) As OcuTalon.Data.Incident
{
	If $Get(since) = "" Set since = "0000-01-01T00:00:00Z"
	Set rows = ..Rows("newestIncident", sessionRef, .sc, namespace, production, since, ..LocalFlag())
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The newest incident of the production that the session sees and that is open, awaiting approval or fixing, or "".
ClassMethod IncidentInProgress(sessionRef As %String, namespace As %String, production As %String, Output sc As %Status) As OcuTalon.Data.Incident
{
	Set rows = ..Rows("incidentInProgress", sessionRef, .sc, namespace, production, ..LocalFlag())
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The approval requests of the incident that the session can see (as Approval does), in any state, by RaisedAt. incidentRef
/// comes from a row read through this class, never from request input.
ClassMethod IncidentApprovals(incidentRef As %String, sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("incidentApprovals", sessionRef, .sc, incidentRef, ..LocalFlag())
}

/// The session's latest Break the feed run by StartedAt and then ID, or "".
ClassMethod LatestBreakFeedRun(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.BreakFeedRun
{
	Set rows = ..Rows("latestBreakFeedRun", sessionRef, .sc)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// The session's own noticed incidents of the production that are resolved, oldest first (an incident of owner instance is
/// shared with other watchers and is never one of them); an empty, instance or eval sessionRef gives an empty list and an
/// error status in sc.
ClassMethod ResolvedIncidents(sessionRef As %String, namespace As %String, production As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("resolvedIncidents", sessionRef, .sc, namespace, production)
}

/// The newest live event of the type on the session's own stream, by Seq, or "".
ClassMethod LastEvent(sessionRef As %String, type As %String, Output sc As %Status) As OcuTalon.Live.Event
{
	Set rows = ..Rows("lastEvent", sessionRef, .sc, type)
	If rows.Count() = 0 Quit ""
	Quit rows.GetAt(1)
}

/// 1 on a local install, where instance records are visible to the sessions that watch their production; 0 when
/// onlineDemo is on (AD-19).
ClassMethod LocalFlag() As %Integer [ Private ]
{
	Quit +(##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1)
}

/// The rows of one kind that the owner can see, opened, in the statement's order. kind names one fixed statement
/// (Statement); ownerRef is required and is bound into the statement's owner check. Each further argument is bound
/// where the statement's bind pattern says. An empty ownerRef, an ownerRef that the SQL equality takes for the literal
/// instance or eval (the default collation, SQLUPPER: any case, trailing blanks ignored), or an unknown kind gives an error
/// status in sc and an empty list, and no statement is prepared. This is the one unchecked prepare of the class: the
/// callers pass only SessionRef()'s value or the session Ref of a record the product itself wrote (a row read through this
/// class, a Turn row, the owner of a bridge event), never request input. Final, with Statement and the owner literals,
/// so that no subclass can change what it prepares.
ClassMethod Rows(kind As %String, ownerRef As %String, Output sc As %Status, args...) As %ListOfObjects [ Final, Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Set list = ##class(%ListOfObjects).%New()
	Set literal = $SYSTEM.Util.Collation(ownerRef, 7)
	If (ownerRef = "") || (literal = $SYSTEM.Util.Collation(..#INSTANCE, 7)) || (literal = $SYSTEM.Util.Collation(..#EVAL, 7)) {
		Set sc = $SYSTEM.Status.Error(5001, "A read needs the Ref of a session")
		Quit list
	}
	Set sql = ..Statement(kind, .class, .binds)
	If sql = "" {
		Set sc = $SYSTEM.Status.Error(5001, "'"_kind_"' is not a kind of row")
		Quit list
	}
	Kill bind
	Set bind = 0
	Set next = 0
	For i = 1:1:$Length(binds) {
		If $Extract(binds, i) = "o" {
			Set bind($Increment(bind)) = ownerRef
		} Else {
			Set next = next + 1
			Set bind($Increment(bind)) = $Get(args(next))
		}
	}
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare(sql, 0)
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(bind...)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The read of '"_kind_"' failed: "_result.%Message)
			} Else {
				While result.%Next() {
					If class = "" {
						Do list.Insert({"total": (+result.%GetData(1))})
						Continue
					}
					Set row = $ClassMethod(class, "%OpenId", result.%Get("ID"))
					If $IsObject(row) Do list.Insert(row)
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit list
}

/// The fixed statement of a row kind, with the class of its rows (empty for a count, whose rows are not opened) and its bind pattern: one letter per ? of the text,
/// in order, o for the owner's Ref and a for the next further argument of Rows. An unknown kind gives "". The texts
/// are constants of this class; nothing is built from an argument. Every one has the owner check in its WHERE clause.
ClassMethod Statement(kind As %String, Output class As %String, Output binds As %String) As %String [ Final, Private ]
{
	Set class = "", binds = ""
	If kind = "turns" {
		Set class = "OcuTalon.Data.Turn", binds = "o"
		Quit "SELECT ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? ORDER BY CreatedAt, ID"
	}
	If kind = "recentTurns" {
		Set class = "OcuTalon.Data.Turn", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State <> 'refused' ORDER BY CreatedAt DESC, ID DESC"
	}
	If kind = "turnByClient" {
		Set class = "OcuTalon.Data.Turn", binds = "oa"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ClientId = ? ORDER BY ID"
	}
	If kind = "turnOfItem" {
		Set class = "OcuTalon.Data.Turn", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ItemId = ?"
	}
	If kind = "turnQueue" {
		Set class = "OcuTalon.Data.Turn", binds = "o"
		Quit "SELECT ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State IN ('queued', 'running') ORDER BY CreatedAt, ID"
	}
	If kind = "lastReplied" {
		Set class = "OcuTalon.Data.Turn", binds = "o"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State = 'done' AND TurnDecisionRef IS NOT NULL ORDER BY CreatedAt DESC, ID DESC"
	}
	If kind = "reminders" {
		Set class = "OcuTalon.Data.Reminder", binds = "o"
		Quit "SELECT ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State = 'pending' ORDER BY DueAt, ID"
	}
	If kind = "checks" {
		Set class = "OcuTalon.Data.BackgroundCheck", binds = "o"
		Quit "SELECT ID FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? ORDER BY ID"
	}
	If kind = "decisions" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND Kind = 'decide' ORDER BY RecordedAt DESC, ID DESC"
	}
	If kind = "decision" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "ao"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE Ref = ? AND OwnerRef = ?"
	}
	If kind = "turnUsage" {
		Set class = "OcuTalon.Bridge.Data.Usage", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND (DecisionRef = ? OR DecisionRef = ?) ORDER BY ID"
	}
	If kind = "runUsage" {
		Set class = "OcuTalon.Bridge.Data.Usage", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND RecordedAt >= ? ORDER BY ID"
	}
	If kind = "heartbeatUsage" {
		Set class = "OcuTalon.Bridge.Data.Usage", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat' AND RecordedAt >= ? AND RecordedAt < ?"
	}
	If kind = "checkInUsage" {
		Set class = "OcuTalon.Bridge.Data.Usage", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND Channel = 'heartbeat' AND ItemId = ?"
	}
	If kind = "usage" {
		Set class = "OcuTalon.Bridge.Data.Usage", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ? AND RecordedAt >= ? AND RecordedAt < ? ORDER BY RecordedAt, ID"
	}
	If kind = "historyDecisions" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "oaaaaaaaaaaaa"
		Quit "SELECT d.ID FROM OcuTalon_Bridge_Data.Decision d WHERE "_..#HISTORYDECISIONS_" ORDER BY d.RecordedAt DESC, d.ID DESC LIMIT ? OFFSET ?"
	}
	If kind = "historyDecisionTotal" {
		// A count: no row is opened (class is empty), and each result row is {"total": the first column}.
		Set binds = "oaaaaaaaaaa"
		Quit "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision d WHERE "_..#HISTORYDECISIONS
	}
	If kind = "historyIncidents" {
		Set class = "OcuTalon.Data.Incident", binds = "oaoaa"
		Quit "SELECT i.ID FROM OcuTalon_Data.Incident i WHERE "_..#INCIDENTVISIBLE_" ORDER BY i.NoticedAt DESC, i.ID DESC LIMIT ? OFFSET ?"
	}
	If kind = "historyIncidentTotal" {
		Set binds = "oao"
		Quit "SELECT COUNT(*) FROM OcuTalon_Data.Incident i WHERE "_..#INCIDENTVISIBLE
	}
	If kind = "runDecisions" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND RecordedAt >= ? ORDER BY ID"
	}
	If kind = "incidents" {
		Set class = "OcuTalon.Data.Incident", binds = "oao"
		Quit "SELECT i.ID FROM OcuTalon_Data.Incident i WHERE "_..#INCIDENTVISIBLE_" ORDER BY i.NoticedAt, i.ID"
	}
	If kind = "recentIncidents" {
		Set class = "OcuTalon.Data.Incident", binds = "aoao"
		Quit "SELECT TOP ? i.ID FROM OcuTalon_Data.Incident i WHERE "_..#INCIDENTVISIBLE_" ORDER BY i.NoticedAt DESC, i.ID DESC"
	}
	If kind = "incident" {
		Set class = "OcuTalon.Data.Incident", binds = "aoao"
		Quit "SELECT i.ID FROM OcuTalon_Data.Incident i WHERE i.Ref = ? AND "_..#INCIDENTVISIBLE
	}
	If kind = "approvals" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "oao"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.State = 'pending' AND "_..#APPROVALVISIBLE_" ORDER BY a.RaisedAt, a.ID"
	}
	If kind = "approval" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "aoao"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.Ref = ? AND "_..#APPROVALVISIBLE
	}
	If kind = "pairing" {
		Set class = "OcuTalon.Data.Pairing", binds = "o"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.Pairing WHERE SessionRef = ? ORDER BY ID"
	}
	If kind = "heartbeat" {
		Set class = "OcuTalon.Data.HeartbeatBeat", binds = "o"
		Quit "SELECT TOP 1 h.ID FROM OcuTalon_Data.HeartbeatBeat h WHERE %EXACT(h.SessionRef) = ?"
	}
	If kind = "recentNotices" {
		Set class = "OcuTalon.Data.Delivery", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND (Kind IN ('tellnow', 'reminder', 'allowance') OR (Kind IN ('approval', 'result', 'digest', 'summary') AND ChannelMessageId IS NOT NULL)) ORDER BY RecordedAt DESC, ID DESC"
	}
	If kind = "recentPhone" {
		Set class = "OcuTalon.Data.SimMessage", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone' ORDER BY CreatedAt DESC, ID DESC"
	}
	If kind = "recentMail" {
		Set class = "OcuTalon.Data.SimMessage", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'mailbox' ORDER BY CreatedAt DESC, ID DESC"
	}
	If kind = "incomingMail" {
		Set class = "OcuTalon.Data.SimMessage", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'mailbox' AND Direction = 'in' AND CreatedAt > ? ORDER BY CreatedAt, ID"
	}
	If kind = "partnerNotices" {
		Set class = "OcuTalon.Data.SimMessage", binds = "oa"
		Quit "SELECT ID FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'mailbox' AND Direction = 'out' AND ApprovalRef IS NOT NULL AND ApprovalRef <> '' AND CreatedAt > ? ORDER BY CreatedAt, ID"
	}
	If kind = "finishedToolCalls" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "oaa"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.OwnerRef = ? AND a.Kind = 'tool_call' AND a.FinishedAt IS NOT NULL AND a.FinishedAt > ? AND a.FinishedAt <= ? ORDER BY a.FinishedAt, a.ID"
	}
	If kind = "decisionOfItem" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "ao"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ? AND OwnerRef = ? AND Kind = 'decide'"
	}
	If kind = "deliveryByApproval" {
		Set class = "OcuTalon.Data.Delivery", binds = "aao"
		Quit "SELECT ID FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ? AND Channel = ? AND OwnerRef = ? ORDER BY ID DESC"
	}
	If kind = "deliveryByRef" {
		Set class = "OcuTalon.Data.Delivery", binds = "aao"
		Quit "SELECT ID FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = ? AND OwnerRef = ? ORDER BY ID DESC"
	}
	If kind = "phoneDecision" {
		Set class = "OcuTalon.Data.Delivery", binds = "ao"
		Quit "SELECT ID FROM OcuTalon_Data.Delivery WHERE ChannelMessageId = ? AND Channel = 'phone' AND Kind = 'tellnow' AND OwnerRef = ? ORDER BY ID DESC"
	}
	If kind = "reminderSetOrFired" {
		Set class = "OcuTalon.Data.Reminder", binds = "o"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State IN ('pending', 'fired') ORDER BY CreatedAt DESC, ID DESC"
	}
	If kind = "newestIncident" {
		Set class = "OcuTalon.Data.Incident", binds = "aaaoao"
		Quit "SELECT TOP 1 i.ID FROM OcuTalon_Data.Incident i WHERE i.Namespace = ? AND i.Production = ? AND i.NoticedAt >= ? AND "_..#INCIDENTVISIBLE_" ORDER BY i.NoticedAt DESC, i.ID DESC"
	}
	If kind = "incidentInProgress" {
		Set class = "OcuTalon.Data.Incident", binds = "aaoao"
		Quit "SELECT TOP 1 i.ID FROM OcuTalon_Data.Incident i WHERE i.Namespace = ? AND i.Production = ? AND i.State IN ('open', 'awaiting_approval', 'fixing') AND "_..#INCIDENTVISIBLE_" ORDER BY i.NoticedAt DESC, i.ID DESC"
	}
	If kind = "incidentApprovals" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "aoao"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.IncidentRef = ? AND "_..#APPROVALVISIBLE_" ORDER BY a.RaisedAt, a.ID"
	}
	If kind = "latestBreakFeedRun" {
		Set class = "OcuTalon.Data.BreakFeedRun", binds = "o"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ? ORDER BY StartedAt DESC, ID DESC"
	}
	If kind = "resolvedIncidents" {
		Set class = "OcuTalon.Data.Incident", binds = "oaa"
		Quit "SELECT i.ID FROM OcuTalon_Data.Incident i WHERE i.OwnerRef = ? AND i.Namespace = ? AND i.Production = ? AND i.State = 'resolved' AND i.NoticedAt <> '' ORDER BY i.NoticedAt, i.ID"
	}
	If kind = "lastEvent" {
		Set class = "OcuTalon.Live.Event", binds = "oa"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = ? ORDER BY Seq DESC"
	}
	If kind = "documents" {
		Set class = "OcuTalon.Data.Document", binds = "oa"
		Quit "SELECT d.ID FROM OcuTalon_Data.Document d WHERE (d.OwnerRef = ? OR (? = 1 AND d.OwnerRef = 'instance')) ORDER BY d.AddedAt DESC, d.ID DESC"
	}
	If kind = "document" {
		Set class = "OcuTalon.Data.Document", binds = "aoa"
		Quit "SELECT d.ID FROM OcuTalon_Data.Document d WHERE d.Ref = ? AND (d.OwnerRef = ? OR (? = 1 AND d.OwnerRef = 'instance'))"
	}
	If kind = "upload" {
		Set class = "OcuTalon.Data.Upload", binds = "ao"
		Quit "SELECT u.ID FROM OcuTalon_Data.Upload u WHERE u.Ref = ? AND u.SessionRef = ?"
	}
	If kind = "sentFile" {
		Set class = "OcuTalon.Data.SentFile", binds = "ao"
		Quit "SELECT f.ID FROM OcuTalon_Data.SentFile f WHERE f.Ref = ? AND f.SessionRef = ?"
	}
	If kind = "precedents" {
		Set class = "OcuTalon.Data.Precedent", binds = "ao"
		Quit "SELECT TOP ? p.ID FROM OcuTalon_Data.Precedent p WHERE p.OwnerRef = ? AND p.EvalRunRef IS NULL ORDER BY p.AnsweredAt DESC, p.ID DESC"
	}
	If kind = "precedent" {
		Set class = "OcuTalon.Data.Precedent", binds = "ao"
		Quit "SELECT p.ID FROM OcuTalon_Data.Precedent p WHERE p.Ref = ? AND p.OwnerRef = ? AND p.EvalRunRef IS NULL"
	}
	If kind = "memories" {
		Set class = "OcuTalon.Data.Memory", binds = "ao"
		Quit "SELECT TOP ? m.ID FROM OcuTalon_Data.Memory m WHERE m.SessionRef = ? ORDER BY m.SavedAt DESC, m.ID DESC"
	}
	If kind = "memory" {
		Set class = "OcuTalon.Data.Memory", binds = "ao"
		Quit "SELECT m.ID FROM OcuTalon_Data.Memory m WHERE m.Ref = ? AND m.SessionRef = ?"
	}
	If kind = "memoryTotal" {
		// A count: no row is opened (class is empty), and each result row is {"total": the first column}.
		Set binds = "o"
		Quit "SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?"
	}
	If kind = "noteTurns" {
		Set class = "OcuTalon.Data.Turn", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State <> 'refused' AND CreatedAt >= ? AND CreatedAt < ? ORDER BY CreatedAt, ID"
	}
	If kind = "noteDecisions" {
		Set class = "OcuTalon.Bridge.Data.Decision", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND Kind = 'decide' AND RecordedAt >= ? AND RecordedAt < ? ORDER BY RecordedAt, ID"
	}
	If kind = "noteIncidents" {
		Set class = "OcuTalon.Data.Incident", binds = "oaoaa"
		Quit "SELECT i.ID FROM OcuTalon_Data.Incident i WHERE "_..#INCIDENTVISIBLE_" AND i.NoticedAt >= ? AND i.NoticedAt < ? ORDER BY i.NoticedAt, i.ID"
	}
	If kind = "noteApprovals" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "oaoaa"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE "_..#APPROVALVISIBLE_" AND COALESCE(NULLIF(a.AnsweredAt, ''), a.RaisedAt) >= ? AND COALESCE(NULLIF(a.AnsweredAt, ''), a.RaisedAt) < ? ORDER BY COALESCE(NULLIF(a.AnsweredAt, ''), a.RaisedAt), a.ID"
	}
	If kind = "noteReminders" {
		Set class = "OcuTalon.Data.Reminder", binds = "oaa"
		Quit "SELECT ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND DueAt >= ? AND DueAt < ? ORDER BY DueAt, ID"
	}
	Quit ""
}

/// 1 when an approval request with exactly this Ref exists in a state other than cancelled, whoever owns it. It answers only whether
/// the request is known: it returns no row and no field, and it is no way to see a request (AD-31). The index ignores case, so the Ref
/// is compared exactly after the open. sc is OK unless the read failed; the answer is then 0.
ClassMethod ApprovalKnown(ref As %String, Output sc As %Status) As %Boolean
{
	Set sc = $SYSTEM.Status.OK()
	If $Get(ref) = "" Quit 0
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref, , .sc)
	If '$IsObject(row) {
		If $SYSTEM.Status.Equals(sc, 5770) Set sc = $SYSTEM.Status.OK()
		Quit 0
	}
	Quit (row.Ref = ref) && (row.State '= "cancelled")
}

}
