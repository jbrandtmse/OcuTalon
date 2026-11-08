/// One of a person's own answers, kept as an example for later (AD-21 as amended 2026-11-08; Story 41.2; Lane B). A row says what the item looked
/// like (Channel and MatchKey), what OcuTalon decided then (Outcome) and what the person answered (Answer, when, and from which channel). Only
/// a person's answers become rows: "This was noise" on a notice, and an approval or a rejection of a fix or of a tool call. A row keeps no sender
/// name, subject or body of an item: MatchKey is the normalized address or source that KeyFor reads, and Summary is a line that code wrote.
///   - The only writer is the business operation OcuTalon.Core.PrecedentOps, which inserts a row on MarkNoise and RecordPrecedent, on
///     SeedPrecedent while an evaluation runs, and deletes rows on ForgetPrecedent, RemoveSeededPrecedents and EndSession (through
///     DropSession and RemoveRun). The one other deletion is Purge, which the daily task runs through OcuTalon.Install.Step.Core (AD-27).
///   - The readers are Similar (OcuTalon.Agent.Input, Story 41.4), Ownership.Precedents and Ownership.Precedent (the routes, AD-4), and Has
///     (SessionOps.End).
///   - A seeded row (an evaluation case) has OwnerRef eval and EvalRunRef set to its run. Similar returns it only for the owner eval, and
///     the ownership reads and the routes never return one.
/// SourceRef is the Ref of what the person answered (the Decision or the approval request) and is unique, so the first answer wins; a seeded row's
/// SourceRef is its own Ref.
Class OcuTalon.Data.Precedent Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Precedent";

/// The answers a row holds, in the order of this list.
Parameter ANSWERS [ Final ] = "noise,approved,rejected";

/// The most rows that Similar returns.
Parameter SIMILARMAX [ Final ] = 3;

/// The status code of %DeleteId for an id that has no row ($$$DeleteObjectNotFound of %occErrors.inc).
Parameter NOTFOUND [ Final ] = 5810;

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Compared exactly.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session whose answer it is, or eval for a seeded row. Compared exactly.
Property OwnerRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// What the later item must share: the sender's address, the source, production:<namespace>/<name>, heartbeat or tool:<ToolName>. Compared exactly.
Property MatchKey As %String(COLLATION = "EXACT", MAXLEN = 512);

/// The Ref of the Decision or of the approval request that was answered; unique. Compared exactly.
Property SourceRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the evaluation run that seeded the row; empty for a person's row. Compared exactly.
Property EvalRunRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The channel of the item that was answered: one of Msg.Enum CHANNEL, or empty (a tool call has none).
Property Channel As %String(MAXLEN = 32);

/// A line that code wrote about what was answered.
Property Summary As %String(MAXLEN = 80);

/// What OcuTalon decided then: one of Msg.Enum OUTCOME, or empty (an approval has no decision outcome).
Property Outcome As %String(MAXLEN = 32);

/// One of ANSWERS.
Property Answer As %String(MAXLEN = 32);

/// When the person answered, UTC to the second.
Property AnsweredAt As %String(MAXLEN = 20);

/// The channel that the answer was given from: one of Msg.Enum CHANNEL, or empty.
Property AnsweredChannel As %String(MAXLEN = 32);

Index RefIndex On Ref [ Unique ];

Index SourceRefIndex On SourceRef [ Unique ];

Index OwnerRefIndex On OwnerRef;

Index OwnerKeyIndex On (OwnerRef, Channel, MatchKey);

/// The key that a later item must share with this row, or "" when the item has none: the item is not an object, is not untrusted, or its channel
/// has no key form.
///   - mailbox and email: the sender's address, which is the text inside the last <...> of the Sender, else the whole Sender; trimmed,
///     lowercased and cut at 512 characters. webhook and slack: the Sender in the same form.
///   - heartbeat: heartbeat.
///   - system (a check finding): production:<Namespace>/<Production> of the one production check of the item's session whose DisplayName is the
///     item's Slots.production; "" when no check or more than one check has that name.
/// It reads and writes nothing else, and runs in production jobs.
ClassMethod KeyFor(item As OcuTalon.Msg.Item) As %String
{
	If '$IsObject($Get(item)) || 'item.%IsA("OcuTalon.Msg.Item") Quit ""
	If item.Provenance '= "untrusted" Quit ""
	Set channel = item.Channel
	If $ListFind($ListBuild("mailbox", "email", "webhook", "slack"), channel) Quit ..Normalized(item.Sender)
	If channel = "heartbeat" Quit "heartbeat"
	If channel '= "system" Quit ""
	Set key = ""
	Try {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(item.Slots)
		If $IsObject(slots) && (slots.%GetTypeOf("production") = "string") {
			Set name = slots.production
			Set checks = ##class(OcuTalon.Data.Ownership).Checks(item.SessionRef, .sc)
			If $SYSTEM.Status.IsOK(sc) && (name '= "") {
				Set found = 0
				For i = 1:1:checks.Count() {
					Set check = checks.GetAt(i)
					If (check.Kind = "production") && (check.DisplayName = name) {
						Set found = found + 1
						Set key = "production:" _ check.Namespace _ "/" _ check.Production
					}
				}
				If found '= 1 Set key = ""
			}
		}
	} Catch {
		Set key = ""
	}
	Quit key
}

/// The key of an approval request: for a fix, production:<Namespace>/<Production> of its incident, with channel system and the summary of the
/// incident's Decision (the production's name when the incident has none); for a tool_call, tool:<ToolName>, with no channel and the tool's name as the summary.
/// A request of any other kind, a fix whose incident is unknown and a tool call with no ToolName answer "" and empty channel and summary.
ClassMethod KeyForRequest(request As OcuTalon.Bridge.Data.ApprovalRequest, Output channel As %String, Output summary As %String) As %String
{
	Set (channel, summary) = ""
	If '$IsObject($Get(request)) Quit ""
	If request.Kind = "tool_call" {
		If request.ToolName = "" Quit ""
		Set summary = $Extract(request.ToolName, 1, 80)
		Quit "tool:" _ request.ToolName
	}
	If request.Kind '= "fix" Quit ""
	Set incident = $Select(request.IncidentRef = "": "", 1: ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef))
	If '$IsObject(incident) || (incident.Ref '= request.IncidentRef) Quit ""
	If (incident.Namespace = "") || (incident.Production = "") Quit ""
	Set key = "production:" _ incident.Namespace _ "/" _ incident.Production
	Set decision = $Select(incident.DecisionRef = "": "", 1: ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(incident.DecisionRef))
	Set summary = $Extract($Select($IsObject(decision) && (decision.Summary '= ""): decision.Summary, 1: key), 1, 80)
	Set channel = "system"
	Quit key
}

/// The address or source in the sender text: what stands inside the last <...>, else the whole text; trimmed, lowercased, cut at 512 characters.
ClassMethod Normalized(sender As %String) As %String [ Private ]
{
	Set text = $ZStrip($Get(sender), "<>W")
	Set open = $Length(text, "<")
	If open > 1 {
		Set last = $Piece(text, "<", open)
		If last [ ">" Set text = $Piece(last, ">", 1)
	}
	Quit $Extract($ZConvert($ZStrip(text, "<>W"), "L"), 1, 512)
}

/// The owner's rows with this channel and key, newest answer first, at most min(limit, SIMILARMAX), as a dynamic array of
/// {ref, answeredAt, channel, answeredChannel, summary, outcome, answer}. The rows of the owner eval are the seeded ones, and no other owner
/// is given a row that has an EvalRunRef. An empty owner, channel or key, and a limit under 1, give []. A failed read gives [] too, with the
/// cause logged. It is prepared with the privilege check and runs in production jobs and tests (AD-13).
ClassMethod Similar(ownerRef As %String, channel As %String, matchKey As %String, limit As %Integer = 3) As %DynamicArray
{
	Set found = []
	If ($Get(ownerRef) = "") || ($Get(channel) = "") || ($Get(matchKey) = "") Quit found
	If '$IsValidNum($Get(limit)) || (limit < 1) Quit found
	Set limit = $Select(limit > ..#SIMILARMAX: ..#SIMILARMAX, 1: limit \ 1)
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT TOP ? ID FROM OcuTalon_Data.Precedent WHERE OwnerRef = ? AND Channel = ? AND MatchKey = ? AND (EvalRunRef IS NULL OR OwnerRef = 'eval') ORDER BY AnsweredAt DESC, ID DESC")
		If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
		Set result = statement.%Execute(limit, ownerRef, channel, matchKey)
		If result.%SQLCODE < 0 Throw ##class(%Exception.General).%New("Similar", 5001, , result.%Message)
		While result.%Next() {
			Set row = ..%OpenId(result.%Get("ID"))
			If $IsObject(row) Do found.%Push(..View(row))
		}
	} Catch exception {
		Set found = []
		Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Data.Precedent.Similar: " _ $Translate(exception.DisplayString(), $Char(13, 10), "  "), 0, 1)
	}
	Quit found
}

/// The public view of a row: {ref, answeredAt, channel, answeredChannel, summary, outcome, answer}, each a string.
ClassMethod View(row As OcuTalon.Data.Precedent) As %DynamicObject
{
	Set view = {}
	Do view.%Set("ref", row.Ref, "string")
	Do view.%Set("answeredAt", row.AnsweredAt, "string")
	Do view.%Set("channel", row.Channel, "string")
	Do view.%Set("answeredChannel", row.AnsweredChannel, "string")
	Do view.%Set("summary", row.Summary, "string")
	Do view.%Set("outcome", row.Outcome, "string")
	Do view.%Set("answer", row.Answer, "string")
	Quit view
}

/// 1 when the session has at least one row of its own. An empty session, instance and eval have none. A read that fails throws, so that a caller never takes
/// a failed read for "no rows".
ClassMethod Has(sessionRef As %String) As %Boolean
{
	If '..IsSession($Get(sessionRef)) Quit 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.Precedent WHERE OwnerRef = ? AND EvalRunRef IS NULL", sessionRef)
	If result.%SQLCODE < 0 Throw ##class(%Exception.General).%New("Precedent.Has", 5001, , "the precedents could not be read: " _ result.%Message)
	Quit result.%Next()
}

/// Deletes every row of the session (its sign-out; AD-4) and no other session's, and no seeded row. An empty session, instance and eval are OK
/// and delete nothing. Returns OK when none is left, else the first error.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If '..IsSession($Get(sessionRef)) Quit $$$OK
	Quit ..DeleteWhere("SELECT ID FROM OcuTalon_Data.Precedent WHERE OwnerRef = ? AND EvalRunRef IS NULL", sessionRef)
}

/// Deletes the rows that the evaluation run seeded and no other row. An empty runRef is OK and deletes nothing. count is the number of rows
/// found. Returns OK when none is left, else the first error.
ClassMethod RemoveRun(runRef As %String, Output count As %Integer) As %Status
{
	Set count = 0
	If $Get(runRef) = "" Quit $$$OK
	Quit ..DeleteWhere("SELECT ID FROM OcuTalon_Data.Precedent WHERE EvalRunRef = ?", runRef, .count)
}

/// Deletes the rows answered more than daysToKeep days ago, the seeded rows included: those whose AnsweredAt is before now (Data.Time.NowUtc)
/// moved back daysToKeep whole days, by date arithmetic on the UTC date (AD-27). daysToKeep must be a whole number of at least 1; anything else is an
/// error status and nothing is deleted.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set bad = $SYSTEM.Status.Error(5001, "OcuTalon.Data.Precedent.Purge needs a whole number of days, at least 1, not '"_$Extract($Get(daysToKeep), 1, 40)_"'")
	If $Get(daysToKeep) '? 1.N Quit bad
	If +daysToKeep < 1 Quit bad
	Set sc = $$$OK
	Try {
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set day = $ZDateH($Piece(now, "T", 1), 3) - daysToKeep
		If day >= 0 {
			Set cutoff = $ZDate(day, 3)_"T"_$Piece(now, "T", 2)
			Set sc = ..DeleteWhere("SELECT ID FROM OcuTalon_Data.Precedent WHERE AnsweredAt < ?", cutoff)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 when the text can be a session's Ref for the drop and the count: not empty, and not the owner literal instance or eval.
ClassMethod IsSession(ref As %String) As %Boolean [ Private ]
{
	Quit (ref '= "") && (ref '= "instance") && (ref '= "eval")
}

/// Deletes the rows whose IDs the statement selects (one bound value), each with %DeleteId; count is the number of rows found. A row that is already
/// gone is not an error. Returns OK, or the first error.
ClassMethod DeleteWhere(sql As %String, value As %String, Output count As %Integer) As %Status [ Private ]
{
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, value)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
	}
	Set sc = $$$OK
	Set n = ""
	For {
		Set n = $Order(ids(n), 1, id)
		Quit:n=""
		Set one = ..%DeleteId(id)
		If $$$ISERR(one) && '$SYSTEM.Status.Equals(one, ..#NOTFOUND) && $$$ISOK(sc) Set sc = one
	}
	Quit sc
}

Storage Default
{
<Data name="PrecedentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>OwnerRef</Value>
</Value>
<Value name="4">
<Value>MatchKey</Value>
</Value>
<Value name="5">
<Value>SourceRef</Value>
</Value>
<Value name="6">
<Value>EvalRunRef</Value>
</Value>
<Value name="7">
<Value>Channel</Value>
</Value>
<Value name="8">
<Value>Summary</Value>
</Value>
<Value name="9">
<Value>Outcome</Value>
</Value>
<Value name="10">
<Value>Answer</Value>
</Value>
<Value name="11">
<Value>AnsweredAt</Value>
</Value>
<Value name="12">
<Value>AnsweredChannel</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.PrecedentD</DataLocation>
<DefaultData>PrecedentDefaultData</DefaultData>
<IdLocation>^OcuTalonP.PrecedentD</IdLocation>
<IndexLocation>^OcuTalonP.PrecedentI</IndexLocation>
<StreamLocation>^OcuTalonP.PrecedentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
