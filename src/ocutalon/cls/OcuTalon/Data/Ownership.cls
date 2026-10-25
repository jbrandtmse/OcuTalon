/// The ownership API (AD-4): the one way the REST surface and the production's jobs resolve the caller's session and
/// read what a session owns. Lane B.
///   - SessionRef resolves the caller's session from the CSP session, never from the client and never from the user
///     name; Attach records the user's durable session in the CSP session.
///   - Every read takes the session's Ref and returns only that session's records: its turns (and, for Conversation's
///     queue, the turn of a page's clientId, the queued and running turns, and the newest turn with a reply decision;
///     for a decision's trace target, the turn of an Item, TurnOfItem),
///     pending reminders, background checks, decisions (and one decision by its Ref), the usage rows of a turn's two
///     decisions or since a time, noticed incidents, pending approval requests, pairing, and the web copies of the notice
///     cards (RecentNotices) and the delivery of an approval message (DeliveryFor).
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
///   - Watchers and ApprovalIncident read across owners, so they prepare with the privilege check, report a failed read
///     in sc, and run only in production jobs and tests.
Class OcuTalon.Data.Ownership
{

/// The key of the CSP session's data that holds the durable session's Ref.
Parameter SESSIONKEY = "OcuTalon.SessionRef";

/// The owner literal of an instance-wide record.
Parameter INSTANCE [ Final ] = "instance";

/// The owner literal of an evaluation record, which no session sees.
Parameter EVAL [ Final ] = "eval";

/// The condition on an incident row i that the incident statements share: it is noticed, and it is the owner's or, on a
/// local install, an instance incident of a production the owner's checks watch. Three ?: the owner, the local flag and
/// the owner again (o, a, o).
Parameter INCIDENTVISIBLE [ Final ] = "i.NoticedAt <> '' AND (i.OwnerRef = ? OR (? = 1 AND i.OwnerRef = 'instance' AND EXISTS (SELECT 1 FROM OcuTalon_Data.BackgroundCheck c WHERE c.SessionRef = ? AND c.Kind = 'production' AND c.Namespace = i.Namespace AND c.Production = i.Production)))";

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
/// and belongs to the signed-in user (matched without regard to case); otherwise the user's durable session is
/// attached first. With no CSP session the result is "" and sc an error. This is the one resolution method: the online
/// demo's session choice (Story 16.3) extends it here.
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
	Set sc = ..Attach()
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit $Get(%session.Data(..#SESSIONKEY))
}

/// Finds or creates the IRIS user's one durable session (Session.ForUser) and records its Ref in the CSP session.
ClassMethod Attach(irisUser As %String = {$Username}) As %Status
{
	If '$IsObject($Get(%session)) Quit $SYSTEM.Status.Error(5001, "There is no CSP session to attach the OcuTalon session to")
	Set row = ##class(OcuTalon.Data.Session).ForUser(irisUser, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set %session.Data(..#SESSIONKEY) = row.Ref
	Quit $SYSTEM.Status.OK()
}

/// The session's turns, by CreatedAt and then ID. sc is an error status when the read failed.
ClassMethod Turns(sessionRef As %String, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("turns", sessionRef, .sc)
}

/// The session's newest turns, newest CreatedAt first and then newest ID first, at most max. sc is an error status when
/// the read failed.
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

/// The session's newest web notice cards: the Delivery rows of channel web and kind tellnow or reminder, newest RecordedAt
/// first and then newest ID first, at most max. sc is an error status when the read failed.
ClassMethod RecentNotices(sessionRef As %String, max As %Integer = 100, Output sc As %Status) As %ListOfObjects
{
	Quit ..Rows("recentNotices", sessionRef, .sc, +max)
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

/// The fixed statement of a row kind, with the class of its rows and its bind pattern: one letter per ? of the text,
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
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.Turn WHERE SessionRef = ? ORDER BY CreatedAt DESC, ID DESC"
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
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.State = 'pending' AND (a.OwnerRef = ? OR (? = 1 AND a.OwnerRef = 'instance' AND EXISTS (SELECT 1 FROM OcuTalon_Data.Incident i WHERE i.Ref = a.IncidentRef AND i.OwnerRef = 'instance' AND i.NoticedAt <> '' AND EXISTS (SELECT 1 FROM OcuTalon_Data.BackgroundCheck c WHERE c.SessionRef = ? AND c.Kind = 'production' AND c.Namespace = i.Namespace AND c.Production = i.Production)))) ORDER BY a.RaisedAt, a.ID"
	}
	If kind = "approval" {
		Set class = "OcuTalon.Bridge.Data.ApprovalRequest", binds = "aoao"
		Quit "SELECT a.ID FROM OcuTalon_Bridge_Data.ApprovalRequest a WHERE a.Ref = ? AND (a.OwnerRef = ? OR (? = 1 AND a.OwnerRef = 'instance' AND EXISTS (SELECT 1 FROM OcuTalon_Data.Incident i WHERE i.Ref = a.IncidentRef AND i.OwnerRef = 'instance' AND i.NoticedAt <> '' AND EXISTS (SELECT 1 FROM OcuTalon_Data.BackgroundCheck c WHERE c.SessionRef = ? AND c.Kind = 'production' AND c.Namespace = i.Namespace AND c.Production = i.Production))))"
	}
	If kind = "pairing" {
		Set class = "OcuTalon.Data.Pairing", binds = "o"
		Quit "SELECT TOP 1 ID FROM OcuTalon_Data.Pairing WHERE SessionRef = ? ORDER BY ID"
	}
	If kind = "recentNotices" {
		Set class = "OcuTalon.Data.Delivery", binds = "ao"
		Quit "SELECT TOP ? ID FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND Kind IN ('tellnow', 'reminder') ORDER BY RecordedAt DESC, ID DESC"
	}
	If kind = "deliveryByApproval" {
		Set class = "OcuTalon.Data.Delivery", binds = "aao"
		Quit "SELECT ID FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ? AND Channel = ? AND OwnerRef = ? ORDER BY ID DESC"
	}
	Quit ""
}

}
