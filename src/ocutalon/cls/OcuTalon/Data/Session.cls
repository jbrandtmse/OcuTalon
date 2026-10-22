/// A signed-in session (AD-4). Lane B. Each IRIS user has one durable row on a local install; ForUser finds or
/// creates it. Only Ownership.Attach calls ForUser: the REST surface resolves the caller through Ownership.SessionRef.
/// Recipients says which sessions an owner's records go to.
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

Index RefIndex On Ref [ Unique ];

Index TraceRefIndex On TraceRef [ Unique ];

Index IrisUserIndex On IrisUser;

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
				Set session = ..%New()
				Set session.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set session.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set session.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set session.IrisUser = irisUser
				Set session.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
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

/// The SessionRefs that receive what the owner owns, as a list:
///   - a session's Ref that has a Session row: that Ref alone;
///   - instance with the Ref of an instance incident: the sessions that watch the incident's production, in
///     SessionRef order (Ownership.Watchers), none when onlineDemo is on;
///   - eval, an empty owner, an unknown Ref, instance without an instance incident: none, the empty list.
ClassMethod Recipients(ownerRef As %String, incidentRef As %String = "") As %List
{
	If (ownerRef = "") || (ownerRef = ##class(OcuTalon.Data.Ownership).#EVAL) Quit ""
	If ownerRef = ##class(OcuTalon.Data.Ownership).#INSTANCE {
		If incidentRef = "" Quit ""
		Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(incidentRef)
		If '$IsObject(incident) || (incident.OwnerRef '= ownerRef) Quit ""
		Quit ##class(OcuTalon.Data.Ownership).Watchers(incident.Namespace, incident.Production)
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
</Data>
<DataLocation>^OcuTalonP.SessionD</DataLocation>
<DefaultData>SessionDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SessionD</IdLocation>
<IndexLocation>^OcuTalonP.SessionI</IndexLocation>
<StreamLocation>^OcuTalonP.SessionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
