/// The one helper for the fixture rows of the tests that read through Ownership or the snapshot. It has no Test
/// methods. Each creating method saves one row of the table it is named for and returns the row's Ref (Usage, whose rows have
/// no Ref, returns and is recorded under the Ref of its decision; Delivery, whose rows have none either, under its
/// ChannelMessageId); every row it
/// creates is recorded under ^OcuTalonTest("Fixture", <class>, <id>), and Clean deletes exactly the recorded rows,
/// with the live events and counters of the fixture sessions' streams and every Delivery row of a fixture session it deletes
/// (the rows that the production made included), and the GuideState and BreakFeedRun rows of the session, so that an interrupted run is cleaned by the
/// next. A row that a test makes another way (Session.ForUser, Ownership.Attach) is recorded with Adopt. A fixture
/// Session row is made here directly, never by ForUser, so a user name can have several rows (the online demo's case).
/// RemoveMessages is the one clean-up of the production messages that the tests of a running production leave; Headers,
/// SessionHeaders and Between read them. Header makes a synthetic message header in a SuperSession of the test, which is not
/// recorded for Clean: RemoveMessages removes it with that SuperSession. AdoptTurns records the turns that Conversation made
/// for fixture sessions, with the Decision rows that the real Decide wrote for them, and States lists the states of a stream's
/// chat.message events. ChatSession makes a session row of a REAL IRIS account that holds the roles given (Core.Access MayChat reads it), SetAccount changes that account's
/// state (disabled, expired), and Clean drops every account it made together with the rows: the accounts are recorded under ^OcuTalonTest("Fixture", "users", <name>) BEFORE they are
/// made, so that a test that fails or throws, or a run that dies, leaves nothing behind that the next Clean does not remove. No role is ever granted to the instance's own accounts.
Class OcuTalon.Test.Data.Fixture
{

/// How many seconds ahead of now a fixture check row is first due (Check).
Parameter CHECKAHEAD = 3600;

/// The name that ChatSession makes its account's name from when it is given none.
Parameter CHATUSER = "ZzChat";

/// A session row of a real IRIS account that holds the roles (a comma list, OcuTalonUser by default) and is enabled and unexpired; returns the session's Ref, with user the account's name,
/// which is the letters and digits of name (CHATUSER when it is empty) and a number, so that the prefix of a test's sessions (zztg...) is the prefix of its accounts; ref, when given, is the new row's Ref; with exact the account's name is name as it is (for a test that names its user). The account is recorded for Clean before it is made, and so is any role of the list that the instance does not have
/// (made with no resources, and removed with the last account). Throws when the account cannot be made.
ClassMethod ChatSession(name As %String = "", roles As %String = "OcuTalonUser", Output user As %String, ref As %String = "", exact As %Boolean = 0) As %String
{
	Set user = $Select(exact: name, 1: $Select(name = "": ..#CHATUSER, 1: $ZStrip(name, "*P"))_$Increment(^OcuTalonTest("Fixture", "userSeq")))
	Set ^OcuTalonTest("Fixture", "users", user) = ""
	Set made = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles(roles)
	For i = 1:1:$Length(made, ",") {
		If $Piece(made, ",", i) '= "" Set ^OcuTalonTest("Fixture", "roles", $Piece(made, ",", i)) = ""
	}
	Set sc = ##class(OcuTalon.Test.Install.RolesAssign).CreateUser(user, roles)
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set ref = ..Session(user, ref)
	Set ^OcuTalonTest("Fixture", "users", user) = ref
	Quit ref
}

/// Sets the state of a fixture account (Security.Users.Modify, in %SYS): enabled is 1 or 0, and days is the ExpirationDate as a number of days from today (-2 is two days ago, 30 is a
/// month ahead) or "" for no expiry; never, when it is 0 or 1, sets AccountNeverExpires too (IRIS clears the ExpirationDate of an account that never expires); with a date and no never, the account is set to expire
/// (AccountNeverExpires 0). Returns the status of the change.
ClassMethod SetAccount(user As %String, enabled As %Boolean = 1, days As %String = "", never As %String = "") As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	If never '= "" Set properties("AccountNeverExpires") = never
	If (never = "") && (days '= "") Set properties("AccountNeverExpires") = 0
	Set properties("Enabled") = enabled
	Set properties("ExpirationDate") = $Select(days = "": "", 1: $ZDate(+$Horolog + days, 3))
	Quit ##class(Security.Users).Modify(user, .properties)
}

/// Gives a fixture account the role (Security.Users.AddRoles, in %SYS); returns the status. Never call it with an account that the fixture did not make.
ClassMethod GiveRole(user As %String, role As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set roles = role
	Quit ##class(Security.Users).AddRoles(user, .roles)
}

/// 1 when the IRIS account exists.
ClassMethod AccountExists(user As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Users).Exists(user)
}

/// The fixture accounts that are still recorded, as a comma list.
ClassMethod Accounts() As %String
{
	Set list = ""
	Set name = ""
	For {
		Set name = $Order(^OcuTalonTest("Fixture", "users", name))
		Quit:name=""
		Set list = list_$Select(list = "": "", 1: ",")_name
	}
	Quit list
}

/// A session row of the IRIS user, with its own Ref (or the Ref given, which must be a Ref that no row has), TraceRef and Epoch.
ClassMethod Session(user As %String, ref As %String = "") As %String
{
	Set row = ##class(OcuTalon.Data.Session).%New()
	Set row.Ref = $Select(ref '= "": ref, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Epoch = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.IrisUser = user
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(row)
}

/// Saves a Data.Memory row of the owner (its SessionRef) with the text, the ItemId, origin tool and SavedAt now, and no embedding, as the tests of the evaluation sessions make one
/// (Story 41.14): it stands for a memory to be dropped, never to be searched. Returns its Ref, or "" with sc the error. The caller removes it.
ClassMethod Memory(owner As %String, text As %String, itemId As %String, Output sc As %Status) As %String
{
	Set row = ##class(OcuTalon.Data.Memory).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = owner
	Set row.Text = text
	Set row.SavedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.ItemId = itemId
	Set row.Origin = "tool"
	Set sc = row.%Save()
	Quit $Select($SYSTEM.Status.IsOK(sc): row.Ref, 1: "")
}

/// Sets OCUTALON_EVAL in this process's environment to the value (removes it for ""), as Data.Session.ForEval and the evaluation switch read it, and returns the value it had. A test that
/// calls it puts the returned value back in a Try/Catch or in its teardown.
ClassMethod SetEval(value As %String) As %String
{
	Set environ = ##class(%SYS.Python).Import("os").environ
	Set previous = $SYSTEM.Util.GetEnviron("OCUTALON_EVAL")
	If value '= "" {
		Do environ."__setitem__"("OCUTALON_EVAL", value)
	} Else {
		Do environ.pop("OCUTALON_EVAL", "")
	}
	Quit previous
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
/// fixture names that no real check uses. The row is not due for CHECKAHEAD seconds (NextDueAt), so that the heartbeat's
/// Checks run leaves it alone while a test reads it; a field NextDueAt, even "" (due at once), replaces that default.
/// fields, an object of property names and values, is set after the defaults.
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
	Set row.NextDueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), ..#CHECKAHEAD)
	Do ..SetFields(row, fields)
	Quit ..Keep(row)
}

/// An incident of the owner (a session's Ref, instance or eval) on a production. noticedAt defaults to now; "" is an
/// incident that has not been noticed yet. fields, an object of property names and values, is set after the defaults.
ClassMethod Incident(ownerRef As %String, noticedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}, namespace As %String = "ZZNS", production As %String = "Zz.Production", fields As %DynamicObject = "") As %String
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
	Do ..SetFields(row, fields)
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

/// A saved FixRun of the request (a Ref) for the incident (a Ref), started now and ended now unless fields, an object of property names and
/// values, gives EndedAt ("" is a run that has not ended); fields is set after the defaults. It answers the run's id. The run is recorded under the
/// incident's Ref, so that Clean of that Ref (or of every row) deletes it.
ClassMethod FixRun(incident As %String, request As %String, fields As %DynamicObject = "") As %Integer
{
	Set row = ##class(OcuTalon.Data.FixRun).%New()
	Set row.ApprovalRef = request
	Set row.IncidentRef = incident
	Set row.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
	If '$IsObject(fields) || 'fields.%IsDefined("EndedAt") Set row.EndedAt = row.StartedAt
	Do ..SetFields(row, fields)
	Do ..Keep(row, incident)
	Quit row.%Id()
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

/// A Break the feed run of the session; state defaults to sent and startedAt to now. The row has no Ref of its own, so it is
/// recorded under sessionRef, which is returned: Clean(sessionRef) removes it with the session's other rows.
ClassMethod BreakFeedRun(sessionRef As %String, state As %String = "sent", startedAt As %String = {##class(OcuTalon.Data.Time).NowUtc()}) As %String
{
	Set row = ##class(OcuTalon.Data.BreakFeedRun).%New()
	Set row.SessionRef = sessionRef
	Set row.State = state
	Set row.StartedAt = startedAt
	Quit ..Keep(row, sessionRef)
}

/// The session's guide markers row: epoch runEpoch (1), runStartedAt ("" for the first epoch) and traceOpened (0). Recorded
/// under sessionRef, which is returned, like BreakFeedRun.
ClassMethod GuideState(sessionRef As %String, runEpoch As %Integer = 1, runStartedAt As %String = "", traceOpened As %Boolean = 0) As %String
{
	Set row = ##class(OcuTalon.Data.GuideState).%New()
	Set row.SessionRef = sessionRef
	Set row.RunEpoch = runEpoch
	Set row.RunStartedAt = runStartedAt
	Set row.TraceOpened = traceOpened
	Quit ..Keep(row, sessionRef)
}

/// Sets the test seam that says whether this release includes Telegram (what Channel.Telegram.In's Included() reads) to
/// value, 1 or 0, and returns the value it had, 1 when it was not set (Included() is 1 unless the seam is 0), so that a test can put it back.
ClassMethod SetTelegramIncluded(value As %Boolean) As %Boolean
{
	Set was = +$Get(^OcuTalonTest("TelegramIncluded"), 1)
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

/// A message on the session's simulated phone: a SimMessage of Kind phone, direction out, with the text "zz phone <ref>" and
/// CreatedAt now unless fields, an object of property names and values, sets others. Clean removes it with the others, and with
/// its session. Returns the row's Ref.
ClassMethod SimMessage(sessionRef As %String, fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Data.SimMessage).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Kind = "phone"
	Set row.Direction = "out"
	Set row.Text = "zz phone "_row.Ref
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..SetFields(row, fields)
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

/// A webhook of the session (Data.Webhook) with the name, whose secret is the given one (a fixed test secret by default). Returns its Ref.
ClassMethod Webhook(sessionRef As %String, name As %String, secret As %String = "zz-fixture-secret-0123456789") As %String
{
	Set row = ##class(OcuTalon.Data.Webhook).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Name = name
	Set row.SessionRef = sessionRef
	Set row.SecretHash = ##class(OcuTalon.Data.Webhook).HashSecret(secret)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(row)
}

/// A document of the owner (a session's Ref, or instance); the state defaults to indexing, the type to markdown, the size to the length of the
/// name and AddedAt to now. fields, an object of property names and values, is set after the defaults.
ClassMethod Document(ownerRef As %String, name As %String, fields As %DynamicObject = "") As %String
{
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = ownerRef
	Set row.AddedBy = $Select(ownerRef = "instance": "", 1: ownerRef)
	Set row.Name = name
	Set row.ContentType = "markdown"
	Set row.Size = $Length(name)
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.State = "indexing"
	Do ..SetFields(row, fields)
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

/// Records every turn of the sessions (comma-separated Refs) with Adopt, the turns that Conversation made included, and the two
/// Decision rows each turn names (TriageDecisionRef and TurnDecisionRef) when they exist and the session owns them, which are the
/// rows that the real Decide wrote for it (so that Clean removes them). It returns refs (comma-separated) with the Refs of those
/// turns and rows added once each.
ClassMethod AdoptTurns(sessions As %String, refs As %String) As %String
{
	For i = 1:1:$Length(sessions, ",") {
		Set session = $Piece(sessions, ",", i)
		If session = "" Continue
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
		For j = 1:1:turns.Count() {
			Set turn = turns.GetAt(j)
			Set list = $ListBuild(turn.Ref)
			Do ..Adopt(turn)
			For ref = turn.TriageDecisionRef, turn.TurnDecisionRef {
				If ref = "" Continue
				Set decision = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref)
				If '$IsObject(decision) || (decision.OwnerRef '= session) Continue
				Do ..Adopt(decision)
				Set list = list_$ListBuild(ref)
			}
			Set pointer = 0
			While $ListNext(list, pointer, one) {
				If '$Find(","_refs_",", ","_one_",") Set refs = refs_$Select(refs = "": "", 1: ",")_one
			}
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
	Do ..DropAccounts(.only, refs)
	Set class = ""
	For {
		Set class = $Order(^OcuTalonTest("Fixture", class))
		Quit:class=""
		If ..Registry(class) Continue
		Set id = ""
		For {
			Set id = $Order(^OcuTalonTest("Fixture", class, id), 1, ref)
			Quit:id=""
			If refs '= "", '$Data(only(ref)) Continue
			If class = "OcuTalon.Data.Session" {
				Do ..DropStream(ref)
				Do ..DropDeliveries(ref)
				Do ..DropSimMessages(ref)
				Do ..DropGuide(ref)
			}
			Do $ClassMethod(class, "%DeleteId", id)
			Kill ^OcuTalonTest("Fixture", class, id)
		}
	}
	If refs = "" {
		Set class = ""
		For {
			Set class = $Order(^OcuTalonTest("Fixture", class))
			Quit:class=""
			If '..Registry(class) Kill ^OcuTalonTest("Fixture", class)
		}
	}
}

/// 1 for a first subscript of ^OcuTalonTest("Fixture") that is not a class of recorded rows: the accounts, the roles and the account counter.
ClassMethod Registry(key As %String) As %Boolean [ Private ]
{
	Quit (key = "users") || (key = "roles") || (key = "userSeq")
}

/// Deletes the IRIS account when it exists; 1 when it no longer exists.
ClassMethod DropAccount(user As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
	Quit '##class(Security.Users).Exists(user)
}

/// Drops the recorded accounts: every one, or with refs the accounts of those sessions (and any account that has no session yet, which a failed ChatSession leaves), each in a Try of its
/// own so that one that cannot be dropped does not keep the others; an account stays recorded until it no longer exists. When no account is left it removes the roles that ChatSession made.
ClassMethod DropAccounts(ByRef only, refs As %String) [ Private ]
{
	Set name = ""
	For {
		Set name = $Order(^OcuTalonTest("Fixture", "users", name), 1, ref)
		Quit:name=""
		If (refs '= "") && (ref '= "") && '$Data(only(ref)) Continue
		Try {
			If ..DropAccount(name) Kill ^OcuTalonTest("Fixture", "users", name)
		} Catch exception {
		}
	}
	If $Data(^OcuTalonTest("Fixture", "users")) Quit
	Set role = ""
	For {
		Set role = $Order(^OcuTalonTest("Fixture", "roles", role))
		Quit:role=""
		Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(role)
		Kill ^OcuTalonTest("Fixture", "roles", role)
	}
}

/// Deletes the sessions whose messages carry one of the SuperSessions (a dynamic array of strings), in the namespace (the
/// current one by default): every header of each such session, whatever its SuperSession (a response can carry none), with its
/// body, and the session's event-log, rule-log and I/O-log rows. It switches to the namespace itself and calls only classes that
/// resolve in both namespaces while it is there (Ens, EnsLib and % classes, and the body classes of the messages it deletes), and
/// it returns to the namespace it was called in.
ClassMethod RemoveMessages(superSessions As %DynamicArray, namespace As %String = {$Namespace}) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	For i = 0:1:superSessions.%Size() - 1 {
		Kill ids, sessions
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SuperSession = ?", superSessions.%Get(i))
		While rs.%Next() {
			Set ids(rs.%Get("ID")) = $ListBuild(rs.%Get("MessageBodyClassName"), rs.%Get("MessageBodyId"))
			If rs.%Get("SessionId") '= "" Set sessions(rs.%Get("SessionId")) = ""
		}
		Set session = ""
		For {
			Set session = $Order(sessions(session))
			Quit:session=""
			Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", session)
			While rs.%Next() {
				Set ids(rs.%Get("ID")) = $ListBuild(rs.%Get("MessageBodyClassName"), rs.%Get("MessageBodyId"))
			}
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
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Rule.Log WHERE SessionId = ?", session)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.IOLog WHERE SessionId = ?", session)
		}
	}
	Quit $$$OK
}

/// A synthetic request header from source to target in the SuperSession, created at the time (a UTC time stamp with
/// milliseconds) and processed within the same second, in the session; with no session it starts its own. Its ID, and "" with
/// the error in sc when a save fails.
ClassMethod Header(superSession As %String, sessionId As %String, created As %String, source As %String, target As %String, Output sc As %Status) As %String
{
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SuperSession = superSession
	Set header.TimeCreated = created
	Set header.TimeProcessed = $Extract(created, 1, 20)_"999"
	Set header.SourceConfigName = source
	Set header.TargetConfigName = target
	Set header.Type = 1
	Set header.SessionId = sessionId
	Set sc = header.%Save()
	If $SYSTEM.Status.IsOK(sc) && (sessionId = "") {
		Set header.SessionId = header.%Id()
		Set sc = header.%Save()
	}
	Quit $Select($SYSTEM.Status.IsOK(sc): header.%Id(), 1: "")
}

/// The headers of the SuperSession, in order, as an array of objects ({id, sessionId, superSession, type, source, target,
/// bodyClass, bodyId, status, isError}).
ClassMethod Headers(superSession As %String) As %DynamicArray
{
	Quit ..HeadersWhere("SuperSession", superSession)
}

/// The headers of the trace session, in order, as Headers gives them.
ClassMethod SessionHeaders(sessionId As %String) As %DynamicArray
{
	Quit ..HeadersWhere("SessionId", sessionId)
}

/// The headers whose column (SuperSession or SessionId, written by the two callers) holds the value, in ID order.
ClassMethod HeadersWhere(column As %String, value As %String) As %DynamicArray [ Private ]
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, SuperSession, Type, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId, Status, IsError FROM Ens.MessageHeader WHERE "_column_" = ? ORDER BY ID", value)
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

/// Saves a Data.SentFile row of the session (a small PDF named name, channel web) and records it for Clean; returns its Ref.
ClassMethod SentFile(sessionRef As %String, name As %String = "zz.pdf") As %String
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write("%PDF-1.4 zz")
	Do bytes.Rewind()
	Set ref = ##class(OcuTalon.Data.SentFile).Put(sessionRef, "web", name, "application/pdf", bytes, .sc)
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Do ..Record(##class(OcuTalon.Data.SentFile).RefIndexOpen(ref))
	Quit ref
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

/// Removes the SimMessage rows of a session, the rows that SimPhoneOut made for a fixture session included.
ClassMethod DropSimMessages(sessionRef As %String) [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?")
	Do statement.%Execute(sessionRef)
}

/// Removes the GuideState and BreakFeedRun rows of a session, the rows that the product made for a fixture session included.
ClassMethod DropGuide(sessionRef As %String) [ Private ]
{
	For table = "OcuTalon_Data.GuideState", "OcuTalon_Data.BreakFeedRun" {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("DELETE FROM "_table_" WHERE SessionRef = ?")
		Do statement.%Execute(sessionRef)
	}
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
