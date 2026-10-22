/// The ownership API (AD-4): the one way the REST surface and the production's jobs resolve the caller's session and
/// read what a session owns. Lane B.
///   - SessionRef resolves the caller's session from the CSP session, never from the client and never from the user
///     name; Attach records the user's durable session in the CSP session.
///   - Every read takes the session's Ref and returns only that session's records: its turns (and, for Conversation's
///     queue, the turn of a page's clientId, the queued and running turns, and the newest turn with a reply decision),
///     pending reminders, background checks, decisions, noticed incidents, pending approval requests and pairing.
///     On a local install (onlineDemo off) a session also sees the noticed incidents of owner instance, and their
///     pending approval requests, for the productions its own checks watch. A record of owner eval is never visible.
///   - The snapshot's chat reads only the newest turns and the newest noticed incidents (RecentTurns, RecentIncidents), so
///     that a long session's snapshot does not open and serialize every row (DW-65).
///   - A find (Incident, Approval) answers "" for a record the session can't see, exactly as for a missing one, so
///     the REST surface answers both with 404.
///   - The reads run as the signed-in user, who holds no SQL privilege on the tables, so Rows prepares its statements
///     without the privilege check (AD-13 as amended, inbox U-15). Rows is the one such method of this class: its
///     statements are fixed texts, one per row kind; each has the owner check in its WHERE clause, bound to the
///     caller's SessionRef, which comes from SessionRef or from a row this class itself read, never from request input.
///   - Watchers reads across sessions and has no owner, so it prepares with the privilege check and runs only in
///     production jobs and tests.
/// TurnCost and RunCost are Story 2.6's.
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

/// The cost of one turn, as an object. Not implemented yet: it answers an empty object. Story 2.6.
ClassMethod TurnCost(turnRef As %String) As %DynamicObject
{
	Quit {}
}

/// The cost of the session's runs since a UTC time, as an object. Not implemented yet: it answers an empty object.
ClassMethod RunCost(sessionRef As %String, since As %String) As %DynamicObject
{
	Quit {}
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
/// Session.Recipients. No request path calls it.
ClassMethod Watchers(namespace As %String, production As %String) As %List
{
	If '..LocalFlag() Quit ""
	If (namespace = "") || (production = "") Quit ""
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT SessionRef FROM OcuTalon_Data.BackgroundCheck WHERE Kind = 'production' AND Namespace = ? AND Production = ?")
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set result = statement.%Execute(namespace, production)
	If result.%SQLCODE < 0 Quit ""
	Kill found
	While result.%Next() {
		Set ref = result.%Get("SessionRef")
		If ref '= "" Set found(ref) = ""
	}
	Set watchers = ""
	Set ref = ""
	For {
		Set ref = $Order(found(ref))
		Quit:ref=""
		Set watchers = watchers_$ListBuild(ref)
	}
	Quit watchers
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
/// callers pass only SessionRef()'s value or a Ref read through this class. Final, with Statement and the owner literals,
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
	Quit ""
}

}
