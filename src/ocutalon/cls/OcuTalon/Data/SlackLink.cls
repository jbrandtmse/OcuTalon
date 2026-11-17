/// A Slack member linked to a session (AD-4, AD-14, AD-27; Stories 27.1 and 27.3). Lane B. A row says that direct messages from the member (TeamId and MemberId together:
/// the same member id in another workspace is another person) are the turns of the session. SlackIn reads it with object access only, because it runs in the
/// hook's process; the writers are Link and Unlink, which SettingsOps (LinkSlackMember, UnlinkSlackMember) calls, after Taken has named a clash, and List is the
/// read behind its ListSlackLinks.
///   - A member is linked to one session and a session has one member (both indexes are unique);
///   - the row is deleted with its session by the cascading foreign key SessionFK, so the AD-27 purge's %DeleteId, an eval session's DropEval and any SQL DELETE of
///     the session remove the link with no code of the purge's own (R8). A link to a session that has no row cannot be saved;
///   - the Slack member id and team id are personal identifiers: they are never put in a trace, a log line, an audit entry or a message, and the writers' error
///     texts never hold them.
/// EVENTGLOBAL holds the claims of event ids (ClaimEvent), written only by ClaimEvent: ("e", UTC hour, event id) is the count of claims, and a bucket older than
/// CLAIMSECONDS is deleted at the next claim. It holds no text and no Slack id but the event id.
/// WORKSPACEGLOBAL holds the one workspace team id that SlackIn has seen on a signed event (NoteWorkspace, Workspace): a link is made in that workspace, and an
/// install has one workspace, so a changed value stops every earlier link from matching (R2). It is read by SettingsOps only and never sent anywhere.
Class OcuTalon.Data.SlackLink Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.SlackLink";

/// The global of the event-id claims.
Parameter EVENTGLOBAL = "^OcuTalonP.SlackE";

/// The global of the workspace team id: one value.
Parameter WORKSPACEGLOBAL = "^OcuTalonP.SlackW";

/// The seconds that a claimed event id is kept at least (claims are kept by whole UTC hours, so for two to three hours); a retry after that is processed again.
Parameter CLAIMSECONDS = 7200;

/// The most characters of a Slack member id or team id.
Parameter IDMAX = 32;

/// The link's own public reference, 22 base64url characters. Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Slack workspace (the envelope's team_id).
Property TeamId As %String(COLLATION = "EXACT", MAXLEN = 32);

/// The Slack member (the event's user).
Property MemberId As %String(COLLATION = "EXACT", MAXLEN = 32);

/// The linked session's Ref, typed exactly as Data.Session.Ref so that the foreign key compares both in one collation.
Property SessionRef As %String(MAXLEN = 22);

/// When the link was made, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index MemberIndex On (TeamId, MemberId) [ Unique ];

Index SessionRefIndex On SessionRef [ Unique ];

ForeignKey SessionFK(SessionRef) References OcuTalon.Data.Session(RefIndex) [ OnDelete = cascade ];

/// The Ref of the session that the member of the workspace is linked to, "" unless a row matches BOTH ids and the session's row exists.
ClassMethod SessionFor(teamId As %String, memberId As %String) As %String
{
	Set teamId = $Get(teamId), memberId = $Get(memberId)
	If (teamId = "") || (memberId = "") Quit ""
	Set row = ""
	Try {
		Set row = ..MemberIndexOpen(teamId, memberId, 0)
	} Catch {
		Set row = ""
	}
	If '$IsObject(row) Quit ""
	Set sessionRef = row.SessionRef
	Quit $Select(##class(OcuTalon.Data.Session).RefIndexExists(sessionRef): sessionRef, 1: "")
}

/// Links the member to the session and answers the link's Ref, with reason one of "" (linked, or already linked to this same session: the existing Ref), bad_id (an id
/// is empty, longer than IDMAX or not letters and digits), no_session (the session has no row), member_taken (the member is linked to another session), user_taken
/// (the session has another member) and failed. Every reason but "" comes with an error status and the answer "". ref is the Ref that the caller made with
/// Bridge.Ids.NewRef (a new one is made when it is empty). A failed save looks at the two unique indexes again to name the clash. No status text holds an id.
ClassMethod Link(teamId As %String, memberId As %String, sessionRef As %String, Output sc As %Status, Output reason As %String, ref As %String = "") As %String
{
	Set sc = $SYSTEM.Status.OK(), reason = ""
	Set teamId = $Get(teamId), memberId = $Get(memberId), sessionRef = $Get(sessionRef), ref = $Get(ref)
	If '..IsId(teamId) || '..IsId(memberId) {
		Set reason = "bad_id"
		Set sc = $SYSTEM.Status.Error(5001, "A Slack team id and member id are letters and digits, at most "_..#IDMAX_" characters")
		Quit ""
	}
	If (sessionRef = "") || '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef) {
		Set reason = "no_session"
		Set sc = $SYSTEM.Status.Error(5001, "The session has no session row")
		Quit ""
	}
	Set taken = ..Taken(teamId, memberId, sessionRef)
	If taken = "same" Quit ..MemberIndexOpen(teamId, memberId, 0).Ref
	If taken '= "" {
		Set reason = taken
		Set sc = $SYSTEM.Status.Error(5001, "The Slack member or the session is already linked")
		Quit ""
	}
	Set result = ""
	Try {
		Set row = ..%New()
		Set row.Ref = $Select(ref '= "": ref, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
		Set row.TeamId = teamId
		Set row.MemberId = memberId
		Set row.SessionRef = sessionRef
		Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set saved = row.%Save()
		If $SYSTEM.Status.IsOK(saved) {
			Set result = row.Ref
		} Else {
			Set again = ..Taken(teamId, memberId, sessionRef)
			If again = "same" {
				Set result = ..MemberIndexOpen(teamId, memberId, 0).Ref
			} Else {
				Set reason = $Select(again '= "": again, 1: "failed")
				Set sc = $SYSTEM.Status.Error(5001, "The Slack member or the session is already linked")
			}
		}
	} Catch {
		Set reason = "failed"
		Set sc = $SYSTEM.Status.Error(5001, "The link could not be saved")
		Set result = ""
	}
	Quit result
}

/// What stands in the way of linking the member of the workspace to the session, read from the two unique indexes: "" (nothing), same (the member is already linked
/// to this session), member_taken (the member is linked to another session) or user_taken (the session has another member). The member is checked first.
ClassMethod Taken(teamId As %String, memberId As %String, sessionRef As %String) As %String
{
	Set teamId = $Get(teamId), memberId = $Get(memberId), sessionRef = $Get(sessionRef)
	Set result = ""
	Try {
		Set row = ..MemberIndexOpen(teamId, memberId, 0)
		If $IsObject(row) {
			Set result = $Select(row.SessionRef = sessionRef: "same", 1: "member_taken")
		} ElseIf ..SessionRefIndexExists(sessionRef) {
			Set result = "user_taken"
		}
	} Catch {
		Set result = ""
	}
	Quit result
}

/// Every link as [{ref, sessionRef, member}] in the order of the rows' ids, read by object access. The team id is not in it.
ClassMethod List() As %DynamicArray
{
	Set list = []
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.SlackLinkD(id))
		Quit:id=""
		Set row = ..%OpenId(id, 0)
		If $IsObject(row) Do list.%Push({"ref": (row.Ref), "sessionRef": (row.SessionRef), "member": (row.MemberId)})
	}
	Quit list
}

/// Notes the workspace of a signed event: sets WORKSPACEGLOBAL to the team id when it is a Slack id (IsId) that differs from the value held, and does nothing else.
ClassMethod NoteWorkspace(teamId As %String)
{
	Set teamId = $Get(teamId)
	If '..IsId(teamId) Quit
	Set global = ..#WORKSPACEGLOBAL
	If $Get(@global) '= teamId Set @global = teamId
}

/// The workspace team id that NoteWorkspace holds, or "" when no signed event has been noted.
ClassMethod Workspace() As %String
{
	Set global = ..#WORKSPACEGLOBAL
	Quit $Get(@global)
}

/// Removes the session's link. Answers OK when there was one and when there was none; an error status only when the row could not be deleted.
ClassMethod Unlink(sessionRef As %String) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set row = ..SessionRefIndexOpen($Get(sessionRef), 0)
		If $IsObject(row) {
			Set id = row.%Id()
			Set row = ""
			Set sc = ..%DeleteId(id)
		}
	} Catch {
		Set sc = $SYSTEM.Status.Error(5001, "The link could not be removed")
	}
	Quit sc
}

/// 1 when the value is a Slack id as this class stores one: 1 to IDMAX letters and digits.
ClassMethod IsId(value As %String) As %Boolean
{
	Quit ($Get(value) ? 1.AN) && ($Length(value) <= ..#IDMAX)
}

/// 1 when this is the first claim of the event id within the last CLAIMSECONDS (and the hour bucket that holds them), 0 when it was claimed before (Slack's retry). The claim is one $Increment of the event's
/// node in the bucket of the current UTC hour, so two claims at once in the same hour cannot both win; a claim in an earlier bucket that is still kept makes this one a repeat.
/// Each claim deletes the buckets older than CLAIMSECONDS. An empty or over-long event id is never claimed (0). now is the current UTC time unless a test gives one.
ClassMethod ClaimEvent(eventId As %String, now As %String = "") As %Boolean
{
	Set eventId = $Get(eventId)
	If (eventId = "") || ($Length(eventId) > 64) Quit 0
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set bucket = $Extract(now, 1, 13)
	Set oldest = $Extract(##class(OcuTalon.Data.Time).AddSeconds(now, -..#CLAIMSECONDS), 1, 13)
	If (bucket = "") || (oldest = "") Quit 0
	Set global = ..#EVENTGLOBAL
	Set old = ""
	For {
		Set old = $Order(@global@("e", old))
		Quit:old=""
		If oldest ] old Kill @global@("e", old) Continue
		If (old '= bucket) && $Data(@global@("e", old, eventId)) Quit
	}
	If old '= "" Quit 0
	Quit $Increment(@global@("e", bucket, eventId)) = 1
}

/// Gives a claim back, so that a retry of an event whose hand-over failed is processed. It deletes the event id from every bucket.
ClassMethod UnclaimEvent(eventId As %String)
{
	Set eventId = $Get(eventId)
	If (eventId = "") || ($Length(eventId) > 64) Quit
	Set global = ..#EVENTGLOBAL
	Set bucket = ""
	For {
		Set bucket = $Order(@global@("e", bucket))
		Quit:bucket=""
		Kill @global@("e", bucket, eventId)
	}
}

/// 1 when a row links this member id in a workspace other than teamId (a member of another Slack workspace who has the same id as a linked member). It reads the rows
/// by id with object access, and there is one row per linked person.
ClassMethod LinkedInAnotherTeam(teamId As %String, memberId As %String) As %Boolean
{
	Set teamId = $Get(teamId), memberId = $Get(memberId)
	If memberId = "" Quit 0
	Set found = 0
	Try {
		Set id = ""
		For {
			Set id = $Order(^OcuTalonP.SlackLinkD(id))
			Quit:id=""
			Set row = ..%OpenId(id, 0)
			If $IsObject(row) && (row.MemberId = memberId) && (row.TeamId '= teamId) {
				Set found = 1
				Quit
			}
		}
	} Catch {
		Set found = 0
	}
	Quit found
}

Storage Default
{
<Data name="SlackLinkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>TeamId</Value>
</Value>
<Value name="4">
<Value>MemberId</Value>
</Value>
<Value name="5">
<Value>SessionRef</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SlackLinkD</DataLocation>
<DefaultData>SlackLinkDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SlackLinkD</IdLocation>
<IndexLocation>^OcuTalonP.SlackLinkI</IndexLocation>
<StreamLocation>^OcuTalonP.SlackLinkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
