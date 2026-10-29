/// A signed-in session (AD-4). Lane B. Each IRIS user has one durable row on a local install; ForUser finds or
/// creates it. Only Ownership.Attach calls ForUser: the REST surface resolves the caller through Ownership.SessionRef.
/// On the online demo every sign-in is a visitor of its own (Story 16.3): NewVisitor creates a row and a resume reference,
/// and ForResume opens the row of a reference. Two stored fields serve that:
///   - ResumeHash is the SHA-256 of the resume reference (Hash), the only form of the reference that any row keeps; the
///     reference is a bearer secret that lives in the visitor's cookie alone (AD-4);
///   - CspSessionId is the CSP session last attached to the row.
/// Recipients says which sessions an owner's records go to. The row also keeps the session's trace thread for the day
/// (AD-26): ThreadSessionId and ThreadDay, which Core.Trace reads and writes under the row's own lock.
/// Three more fields serve the online demo's allowances (Story 16.9, AD-20), and Core.Allowance and Core.BridgeSink write them
/// under that same row lock: AllowanceTimes, AllowanceUntil and DailyCapDay. A row that predates them reads as empty.
Class OcuTalon.Data.Session Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Session";

/// The session Ref: the SessionRef of its messages and rows.
Property Ref As %String(MAXLEN = 22);

/// The trace reference of the session; unique.
Property TraceRef As %String(MAXLEN = 22);

/// The IRIS user of the session.
Property IrisUser As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

/// The opaque epoch of the session (AD-13): it is not secret, and it changes only when the OcuTalon session itself
/// ended. /state returns it, and the page compares it after a sign-in.
Property Epoch As %String(MAXLEN = 22);

/// The session id of today's trace thread (AD-26): the SessionId of the first Item header of ThreadDay, which every later
/// Item of that day is sent in. Empty until the session's first message.
Property ThreadSessionId As %Integer;

/// The instance-zone local date, YYYY-MM-DD, of the thread in ThreadSessionId.
Property ThreadDay As %String(MAXLEN = 10);

/// The SHA-256 of the row's resume reference (Hash), base64url without padding; empty for a row that has no resume
/// reference (a local user's durable row). The collation is exact because base64url is case-sensitive.
Property ResumeHash As %String(COLLATION = "EXACT", MAXLEN = 43);

/// The id of the CSP session last attached to the row (Ownership.Resume, Ownership.StartVisitor).
Property CspSessionId As %String(MAXLEN = 64);

/// The UTC times (to the second) of the session's accepted messages in the rolling hour, oldest first, as a list of at most
/// Allowance.Limit() entries (AD-20). Empty off the online demo.
Property AllowanceTimes As %List;

/// The retryAt (UTC to the second) of the allowance window that has had a refusal: from the window's first refusal until that
/// time the session's allowance condition holds. Empty when no window is open.
Property AllowanceUntil As %String(MAXLEN = 20);

/// The instance-zone local date (YYYY-MM-DD) on which the session was sent the online demo's daily-cap message (AD-20); empty
/// until it was.
Property DailyCapDay As %String(MAXLEN = 10);

Index RefIndex On Ref [ Unique ];

Index TraceRefIndex On TraceRef [ Unique ];

Index IrisUserIndex On IrisUser;

Index ResumeHashIndex On ResumeHash [ Unique ];

/// The IRIS user's one session row, created at the first call. The user name is matched without regard to case,
/// as IRIS matches user names. The lookup is OcuTalon's own query, with the user name as a parameter, and runs for
/// signed-in users who hold no SQL privilege on the table, so it is prepared without the privilege check. sc holds
/// the error status when the user name is empty or the row can't be opened or saved, and the result is then "".
ClassMethod ForUser(irisUser As %String, Output sc As %Status) As OcuTalon.Data.Session
{
	Set sc = $SYSTEM.Status.OK()
	If irisUser = "" {
		Set sc = $SYSTEM.Status.Error(5001, "A session needs an IRIS user name")
		Quit ""
	}
	Set session = ""
	Lock +^OcuTalon.Data.Session($ZConvert(irisUser, "U")):5
	If '$Test {
		Set sc = $SYSTEM.Status.Error(5001, "The session of '"_irisUser_"' is busy: its lock wasn't free in 5 seconds")
		Quit ""
	}
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT TOP 1 ID FROM OcuTalon_Data.Session WHERE IrisUser = ? ORDER BY ID", 0)
		If $SYSTEM.Status.IsOK(sc) {
			Set result = statement.%Execute(irisUser)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The session lookup failed: "_result.%Message)
			} ElseIf result.%Next() {
				Set session = ..%OpenId(result.%Get("ID"), , .sc)
				If $SYSTEM.Status.IsOK(sc), '$IsObject(session) Set sc = $SYSTEM.Status.Error(5001, "The session row of '"_irisUser_"' could not be opened")
			} Else {
				Set session = ..NewRow(irisUser)
				Set sc = session.%Save()
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Data.Session($ZConvert(irisUser, "U"))
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit session
}

/// A new, unsaved row for an IRIS user: a new Ref, TraceRef and Epoch, and the creation time.
ClassMethod NewRow(irisUser As %String) As OcuTalon.Data.Session [ Private ]
{
	Set session = ..%New()
	Set session.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set session.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set session.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set session.IrisUser = irisUser
	Set session.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit session
}

/// The SHA-256 of the UTF-8 text, base64url without padding (43 characters): the form in which the resume reference and
/// a client address are stored.
ClassMethod Hash(text As %String) As %String
{
	Quit $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, $ZConvert(text, "O", "UTF8")), 1), "+/=", "-_")
}

/// A new row for a visitor of the online demo, always created (never found): a new Ref, TraceRef and Epoch, the IRIS user,
/// the CSP session id and a new resume reference (Bridge.Ids.NewRef), of which the row keeps only the hash. reference is the
/// plaintext, for the caller's cookie alone. sc holds the error status when the user name is empty or the row can't be
/// saved, and the result and reference are then "".
ClassMethod NewVisitor(irisUser As %String, cspSessionId As %String, Output reference As %String, Output sc As %Status) As OcuTalon.Data.Session
{
	Set reference = ""
	Set sc = $SYSTEM.Status.OK()
	If irisUser = "" {
		Set sc = $SYSTEM.Status.Error(5001, "A session needs an IRIS user name")
		Quit ""
	}
	Try {
		Set session = ..NewRow(irisUser)
		Set reference = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set session.ResumeHash = ..Hash(reference)
		Set session.CspSessionId = cspSessionId
		Set sc = session.%Save()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) {
		Set reference = ""
		Quit ""
	}
	Quit session
}

/// The row of a resume reference, or "" when the reference is not 22 characters of A-Z, a-z, 0-9, - and _ or no row has
/// its hash. It opens by the hash index, with no SQL: the caller may hold no SQL privilege.
ClassMethod ForResume(reference As %String) As OcuTalon.Data.Session
{
	If '$Match(reference, "^[A-Za-z0-9_-]{22}$") Quit ""
	Quit ..ResumeHashIndexOpen(..Hash(reference))
}

/// The SessionRefs that receive what the owner owns, as a list:
///   - a session's Ref that has a Session row: that Ref alone;
///   - instance with the Ref of an instance incident: the sessions that watch the incident's production, in
///     SessionRef order (Ownership.Watchers), none when onlineDemo is on;
///   - eval, an empty owner, an unknown Ref, instance without an instance incident: none, the empty list.
/// sc is OK unless the watcher read failed (DW-68). Then the result is "" and means nothing: it never means that nobody
/// watches. That read prepares with the privilege check, so it runs only in production jobs and tests; a caller in a
/// REST request gets the error.
ClassMethod Recipients(ownerRef As %String, incidentRef As %String = "", Output sc As %Status) As %List
{
	Set sc = $SYSTEM.Status.OK()
	If (ownerRef = "") || (ownerRef = ##class(OcuTalon.Data.Ownership).#EVAL) Quit ""
	If ownerRef = ##class(OcuTalon.Data.Ownership).#INSTANCE {
		If incidentRef = "" Quit ""
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(incidentRef)
		If '$IsObject(incident) || (incident.OwnerRef '= ownerRef) Quit ""
		Quit ##class(OcuTalon.Data.Ownership).Watchers(incident.Namespace, incident.Production, .sc)
	}
	If ..RefIndexExists(ownerRef) Quit $ListBuild(ownerRef)
	Quit ""
}

Storage Default
{
<Data name="SessionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>TraceRef</Value>
</Value>
<Value name="4">
<Value>IrisUser</Value>
</Value>
<Value name="5">
<Value>CreatedAt</Value>
</Value>
<Value name="6">
<Value>Epoch</Value>
</Value>
<Value name="7">
<Value>ThreadSessionId</Value>
</Value>
<Value name="8">
<Value>ThreadDay</Value>
</Value>
<Value name="9">
<Value>ResumeHash</Value>
</Value>
<Value name="10">
<Value>CspSessionId</Value>
</Value>
<Value name="11">
<Value>AllowanceTimes</Value>
</Value>
<Value name="12">
<Value>AllowanceUntil</Value>
</Value>
<Value name="13">
<Value>DailyCapDay</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SessionD</DataLocation>
<DefaultData>SessionDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SessionD</IdLocation>
<IndexLocation>^OcuTalonP.SessionI</IndexLocation>
<StreamLocation>^OcuTalonP.SessionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
