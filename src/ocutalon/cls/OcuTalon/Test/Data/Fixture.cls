/// The one helper for the fixture rows of the tests that read through Ownership or the snapshot. It has no Test
/// methods. Each creating method saves one row of the table it is named for and returns the row's Ref; every row it
/// creates is recorded under ^OcuTalonTest("Fixture", <class>, <id>), and Clean deletes exactly the recorded rows,
/// with the live events and counters of the fixture sessions' streams, so that an interrupted run is cleaned by the
/// next. A row that a test makes another way (Session.ForUser, Ownership.Attach) is recorded with Adopt. A fixture
/// Session row is made here directly, never by ForUser, so a user name can have several rows (the online demo's case).
/// RemoveMessages is the one clean-up of the production messages that the tests of a running production leave; Headers and
/// Between read them.
Class OcuTalon.Test.Data.Fixture
{

/// A session row of the IRIS user, with its own Ref, TraceRef and Epoch.
ClassMethod Session(user As %String) As %String
{
	Set row = ##class(OcuTalon.Data.Session).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.IrisUser = user
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(row)
}

/// A turn of the session; createdAt defaults to now and state to done. It always has a new ItemId (the ItemId index is
/// unique); text, clientId and attempt are set when given.
ClassMethod Turn(sessionRef As %String, createdAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}, state As %String = "done", text As %String = "", clientId As %String = "", attempt As %Integer = 0) As %String
{
	Set row = ##class(OcuTalon.Data.Turn).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.State = state
	Set row.Channel = "web"
	Set row.FromGuide = 0
	Set row.CreatedAt = createdAt
	Set row.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Text = text
	Set row.ClientId = clientId
	Set row.Attempt = attempt
	Quit ..Keep(row)
}

/// A reminder of the session; dueAt defaults to a fixed time in 2030 and state to pending.
ClassMethod Reminder(sessionRef As %String, dueAt As %String = "2030-01-01T10:00:00Z", state As %String = "pending") As %String
{
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Text = "zz reminder "_row.Ref
	Set row.DueAt = dueAt
	Set row.State = state
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(row)
}

/// A production check of the session on a production; the namespace and the production default to a pair of
/// fixture names that no real check uses.
ClassMethod Check(sessionRef As %String, namespace As %String = "ZZNS", production As %String = "Zz.Production") As %String
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Kind = "production"
	Set row.Namespace = namespace
	Set row.Production = production
	Set row.DisplayName = "Zz "_production
	Set row.AskedBy = "zzfixture"
	Quit ..Keep(row)
}

/// An incident of the owner (a session's Ref, instance or eval) on a production. noticedAt defaults to now; "" is an
/// incident that has not been noticed yet.
ClassMethod Incident(ownerRef As %String, noticedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}, namespace As %String = "ZZNS", production As %String = "Zz.Production") As %String
{
	Set row = ##class(OcuTalon.Data.Incident).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ownerRef
	Set row.Namespace = namespace
	Set row.Production = production
	Set row.State = "open"
	Set row.OpenVariant = "fix"
	Set row.NoticedAt = noticedAt
	Set row.Count = 3
	Set row.NoticeCount = 3
	Set row.FirstAt = "2030-01-01T09:00:00Z"
	Set row.LastAt = "2030-01-01T09:30:00Z"
	Set row.Cause = "zz cause"
	Quit ..Keep(row)
}

/// An approval request of the owner (a session's Ref, instance or eval), for the incident when incidentRef is set.
/// raisedAt defaults to now.
ClassMethod Approval(ownerRef As %String, incidentRef As %String = "", state As %String = "pending", raisedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}) As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = "fix"
	Set row.IncidentRef = incidentRef
	Set row.OwnerRef = ownerRef
	Set row.State = state
	Set row.DryRun = "{""affected"":4,""resend"":3,""leftOut"":1,""field"":""OrderDate"",""before"":""16/10/2026"",""after"":""2026-10-16"",""itemNoun"":{""one"":""order"",""other"":""orders""}}"
	Set row.RaisedAt = raisedAt
	Set row.ExpiresAt = "2030-01-02T09:00:00Z"
	Quit ..Keep(row)
}

/// A decision of the owner. kind defaults to decide, the attention decision; recordedAt to now. Its item is new, so the
/// (item, kind) key stays unique.
ClassMethod Decision(ownerRef As %String, kind As %String = "decide", recordedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}) As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = kind
	Set row.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ownerRef
	Set row.Summary = "zz summary "_row.Ref
	Set row.Outcome = "notify"
	Set row.Model = "claude-haiku-5-5"
	Set row.TraceSessionId = 42
	Set row.RecordedAt = recordedAt
	Quit ..Keep(row)
}

/// The session's Telegram pairing.
ClassMethod Pairing(sessionRef As %String, displayName As %String = "Zz chat") As %String
{
	Set row = ##class(OcuTalon.Data.Pairing).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.ChatId = "zz"_$Random(1000000)
	Set row.DisplayName = displayName
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(row)
}

/// The UTC time that many hours before now, in the form of a live event's Ts.
ClassMethod HoursAgo(hours As %Integer) As %String
{
	Set now = $ZTimeStamp
	Set seconds = ($Piece(now, ",", 1) * 86400) + $Piece(now, ",", 2) - (hours * 3600)
	Quit $Translate($ZDateTime((seconds \ 86400)_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
}

/// Sets the Ts of one event of a stream.
ClassMethod SetEventTs(stream As %String, seq As %Integer, ts As %String)
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("UPDATE OcuTalon_Live.Event SET Ts = ? WHERE Stream = ? AND Seq = ?")
	Do statement.%Execute(ts, stream, seq)
}

/// The Seq of each event of the stream, comma-separated, in order.
ClassMethod EventSeqs(stream As %String) As %String
{
	Set seqs = ""
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Seq FROM OcuTalon_Live.Event WHERE Stream = ? ORDER BY Seq")
	Set result = statement.%Execute(stream)
	While result.%Next() {
		Set seqs = seqs_$Select(seqs = "": "", 1: ",")_result.%Get("Seq")
	}
	Quit seqs
}

/// Records a row that the caller saved some other way, so that Clean deletes it. Returns the row's Ref.
ClassMethod Adopt(row As %Persistent) As %String
{
	Do ..Record(row)
	Quit row.Ref
}

/// The number of session rows of an IRIS user, matched without regard to case, as IRIS matches user names.
ClassMethod SessionCount(user As %String) As %Integer
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Session WHERE IrisUser = ?")
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set result = statement.%Execute(user)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes recorded rows, with the live events and counters of the streams of the recorded sessions it deletes: every
/// recorded row, or with refs (a comma-separated list of Refs) only the recorded rows with those Refs, so that a test that
/// shares the stack with others removes its own rows and nobody else's.
ClassMethod Clean(refs As %String = "")
{
	Kill only
	For i = 1:1:$Length(refs, ",") {
		Set one = $Piece(refs, ",", i)
		If one '= "" Set only(one) = ""
	}
	Set class = ""
	For {
		Set class = $Order(^OcuTalonTest("Fixture", class))
		Quit:class=""
		Set id = ""
		For {
			Set id = $Order(^OcuTalonTest("Fixture", class, id), 1, ref)
			Quit:id=""
			If refs '= "", '$Data(only(ref)) Continue
			If class = "OcuTalon.Data.Session" Do ..DropStream(ref)
			Do $ClassMethod(class, "%DeleteId", id)
			Kill ^OcuTalonTest("Fixture", class, id)
		}
	}
	If refs = "" Kill ^OcuTalonTest("Fixture")
}

/// Deletes the headers, the bodies and the event-log rows of the sessions whose messages carry one of the SuperSessions
/// (a dynamic array of strings), in the namespace (the current one by default). It switches to the namespace itself and
/// calls only classes that resolve in both namespaces while it is there (Ens, EnsLib and % classes, and the body classes
/// of the messages it deletes), and it returns to the namespace it was called in.
ClassMethod RemoveMessages(superSessions As %DynamicArray, namespace As %String = {$Namespace}) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	For i = 0:1:superSessions.%Size() - 1 {
		Kill ids, sessions
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SuperSession = ?", superSessions.%Get(i))
		While rs.%Next() {
			Set ids(rs.%Get("ID")) = $ListBuild(rs.%Get("MessageBodyClassName"), rs.%Get("MessageBodyId"))
			Set sessions(rs.%Get("SessionId")) = ""
		}
		Set id = ""
		For {
			Set id = $Order(ids(id), 1, body)
			Quit:id=""
			If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
			Do ##class(Ens.MessageHeader).%DeleteId(id)
		}
		Set session = ""
		For {
			Set session = $Order(sessions(session))
			Quit:session=""
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
		}
	}
	Quit $$$OK
}

/// The headers of the SuperSession, in order, as an array of objects ({id, sessionId, superSession, type, source, target,
/// bodyClass, bodyId, status, isError}).
ClassMethod Headers(superSession As %String) As %DynamicArray
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, SuperSession, Type, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId, Status, IsError FROM Ens.MessageHeader WHERE SuperSession = ? ORDER BY ID", superSession)
	While result.%Next() {
		Do headers.%Push({"id": (result.%Get("ID")), "sessionId": (result.%Get("SessionId")), "superSession": (result.%Get("SuperSession")), "type": (result.%Get("Type")), "source": (result.%Get("SourceConfigName")), "target": (result.%Get("TargetConfigName")), "bodyClass": (result.%Get("MessageBodyClassName")), "bodyId": (result.%Get("MessageBodyId")), "status": (result.%Get("Status")), "isError": (result.%Get("IsError"))})
	}
	Quit headers
}

/// The headers of the type (1 request, 2 response) from the source item to the target item among the headers.
ClassMethod Between(headers As %DynamicArray, type As %Integer, source As %String, target As %String) As %DynamicArray
{
	Set found = []
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If (header.type = type) && (header.source = source) && (header.target = target) Do found.%Push(header)
	}
	Quit found
}

/// Saves the row and records it.
ClassMethod Keep(row As %Persistent) As %String [ Private ]
{
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Do ..Record(row)
	Quit row.Ref
}

ClassMethod Record(row As %Persistent) [ Private ]
{
	Set ^OcuTalonTest("Fixture", $ClassName(row), row.%Id()) = row.Ref
}

/// Removes the live events of a stream and its counter.
ClassMethod DropStream(stream As %String) [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Live.Event WHERE Stream = ?")
	Do statement.%Execute(stream)
	Kill ^OcuTalonP.LiveEventC(stream)
}

}
