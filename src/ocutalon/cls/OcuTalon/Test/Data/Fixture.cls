/// The one helper for the fixture rows of the tests that read through Ownership or the snapshot. It has no Test
/// methods. Each creating method saves one row of the table it is named for and returns the row's Ref (Usage, whose rows have
/// no Ref, returns and is recorded under the Ref of its decision; Delivery, whose rows have none either, under its
/// ChannelMessageId); every row it
/// creates is recorded under ^OcuTalonTest("Fixture", <class>, <id>), and Clean deletes exactly the recorded rows,
/// with the live events and counters of the fixture sessions' streams and every Delivery row of a fixture session it deletes
/// (the rows that the production made included), so that an interrupted run is cleaned by the
/// next. A row that a test makes another way (Session.ForUser, Ownership.Attach) is recorded with Adopt. A fixture
/// Session row is made here directly, never by ForUser, so a user name can have several rows (the online demo's case).
/// RemoveMessages is the one clean-up of the production messages that the tests of a running production leave; Headers and
/// Between read them. AdoptTurns records the turns that Conversation made for fixture sessions, and States lists the states
/// of a stream's chat.message events.
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

/// A reminder of the session; dueAt defaults to a fixed time in 2030 and state to pending. fields, an object of property
/// names and values, is set after the defaults.
ClassMethod Reminder(sessionRef As %String, dueAt As %String = "2030-01-01T10:00:00Z", state As %String = "pending", fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Text = "zz reminder "_row.Ref
	Set row.DueAt = dueAt
	Set row.State = state
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..SetFields(row, fields)
	Quit ..Keep(row)
}

/// A production check of the session on a production; the namespace and the production default to a pair of
/// fixture names that no real check uses. fields, an object of property names and values, is set after the defaults.
ClassMethod Check(sessionRef As %String, namespace As %String = "ZZNS", production As %String = "Zz.Production", fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Kind = "production"
	Set row.Namespace = namespace
	Set row.Production = production
	Set row.DisplayName = "Zz "_production
	Set row.AskedBy = "zzfixture"
	Do ..SetFields(row, fields)
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
/// raisedAt defaults to now. fields, an object of property names and values, is set after the defaults.
ClassMethod Approval(ownerRef As %String, incidentRef As %String = "", state As %String = "pending", raisedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}, fields As %DynamicObject = "") As %String
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
	Do ..SetFields(row, fields)
	Quit ..Keep(row)
}

/// A decision of the owner. kind defaults to decide, the attention decision; recordedAt to now; the outcome is tellnow. Its
/// item is new, so the (item, kind) key stays unique. fields, an object of property names and values (Ref and ItemId
/// included), is set after the defaults.
ClassMethod Decision(ownerRef As %String, kind As %String = "decide", recordedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}, fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = kind
	Set row.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ownerRef
	Set row.Summary = "zz summary "_row.Ref
	Set row.Outcome = "tellnow"
	Set row.Model = "claude-haiku-5-5"
	Set row.TraceSessionId = 42
	Set row.RecordedAt = recordedAt
	Do ..SetFields(row, fields)
	Quit ..Keep(row)
}

/// A usage row of the owner for the decision (the Ref of a Decision row, or any Ref). fields, an object of property names
/// and values, is set after the defaults (the model is claude-haiku-5-5 and the time now). The row has no Ref of its own, so
/// it is recorded under decisionRef: Clean(decisionRef) removes it with the decision. Returns decisionRef.
ClassMethod Usage(decisionRef As %String, ownerRef As %String, fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.Usage).%New()
	Set row.DecisionRef = decisionRef
	Set row.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = "decide"
	Set row.Agent = "zz"
	Set row.Channel = "web"
	Set row.OwnerRef = ownerRef
	Set row.Model = "claude-haiku-5-5"
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..SetFields(row, fields)
	Quit ..Keep(row, decisionRef)
}

/// Sets the test seam that says whether this release includes Telegram (what Channel.Telegram.In's Included() reads) to
/// value, 1 or 0, and returns the value it had, 0 when it was not set, so that a test can put it back.
ClassMethod SetTelegramIncluded(value As %Boolean) As %Boolean
{
	Set was = +$Get(^OcuTalonTest("TelegramIncluded"))
	Set ^OcuTalonTest("TelegramIncluded") = +value
	Quit was
}

/// Sets each member of fields, an object of property names and values, on the row. Nothing for an empty fields.
ClassMethod SetFields(row As %Persistent, fields As %DynamicObject) [ Private ]
{
	If '$IsObject(fields) Quit
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set $Property(row, name) = value
	}
}

/// A web notice card of the owner, a Delivery row of channel web: its kind is tellnow, its text "zz card <ref>" and its
/// RecordedAt now unless fields, an object of property names and values, sets others. The row is recorded under its
/// ChannelMessageId, a new Ref unless fields gives one (a row that fields leaves with no ChannelMessageId is recorded under a new
/// Ref, which is returned). Clean removes it with the others, and with its owner when the owner is a fixture session.
ClassMethod Delivery(ownerRef As %String, fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Data.Delivery).%New()
	Set row.OwnerRef = ownerRef
	Set row.Channel = "web"
	Set row.ChannelMessageId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = "tellnow"
	Set row.Text = "zz card "_row.ChannelMessageId
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..SetFields(row, fields)
	Quit ..Keep(row, $Select(row.ChannelMessageId '= "": row.ChannelMessageId, 1: ##class(OcuTalon.Bridge.Ids).NewRef()))
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

/// Records every turn of the sessions (comma-separated Refs) with Adopt, the turns that Conversation made included, and returns
/// refs (comma-separated) with the Refs of those turns added once each.
ClassMethod AdoptTurns(sessions As %String, refs As %String) As %String
{
	For i = 1:1:$Length(sessions, ",") {
		Set session = $Piece(sessions, ",", i)
		If session = "" Continue
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
		For j = 1:1:turns.Count() {
			Set ref = ..Adopt(turns.GetAt(j))
			If '$Find(","_refs_",", ","_ref_",") Set refs = refs_$Select(refs = "": "", 1: ",")_ref
		}
	}
	Quit refs
}

/// The states of chat.message events (a dynamic array of events as Live.Event.Since gives them), comma-separated, in order.
ClassMethod States(events As %DynamicArray) As %String
{
	Set states = ""
	For i = 0:1:events.%Size() - 1 {
		Set states = states_$Select(states = "": "", 1: ",")_events.%Get(i).payload.state
	}
	Quit states
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
			If class = "OcuTalon.Data.Session" {
				Do ..DropStream(ref)
				Do ..DropDeliveries(ref)
			}
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

/// Saves the row and records it under ref, which is the row's Ref by default, and returns ref.
ClassMethod Keep(row As %Persistent, ref As %String = "") As %String [ Private ]
{
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set ref = $Select(ref '= "": ref, 1: row.Ref)
	Do ..Record(row, ref)
	Quit ref
}

/// Records the row under ref, which is the row's Ref by default: Clean deletes the row with the others of that ref.
ClassMethod Record(row As %Persistent, ref As %String = "") [ Private ]
{
	Set ^OcuTalonTest("Fixture", $ClassName(row), row.%Id()) = $Select(ref '= "": ref, 1: row.Ref)
}

/// Removes the Delivery rows of an owner, the rows that the production made for a fixture session included.
ClassMethod DropDeliveries(ownerRef As %String) [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?")
	Do statement.%Execute(ownerRef)
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
