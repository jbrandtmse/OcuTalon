/// Conversation, the business process that owns the turn queue of every session (AD-1, AD-6, AD-8, AD-14, AD-30, AD-32). It
/// takes an OcuTalon.Msg.Item from WebChatIn and runs each session's turns one at a time, in CreatedAt and ID order. Every hop
/// is a production message and Conversation never waits for one (no SendRequestSync):
///   - Item: dropped, with a warning, when it is not user provenance or has no ItemId, no text or no Session row (NFR-14), and
///     dropped silently when its ItemId or its ClientId already has a turn of the session. Otherwise it is saved as a queued
///     Turn, chat.message is published, and the session's next turn starts;
///   - an Item that carries a file (FileRef, Story 25.3; Core.Files) is the one exception to the user-provenance rule: it is taken only with provenance
///     untrusted, only when its FileRef is a file of the Item's own session (Core.Files.Describe), and it may have no text; every other drop stands.
///     The Turn keeps the file as SentFile, {ref, name, mediaType, size} from the stored row and never from the Item, which marks the turn untrusted:
///     ItemOf rebuilds the Item with provenance untrusted and the file fields, so that every decide and turn request of the Turn carries provenance
///     untrusted, in which the gate lets only safe read-only tools run (AD-10, AD-14). When nothing reads a sent file (Reader, Core.Files.Readable),
///     Begin concludes the turn with the fixed reply Core.Files.NoReaderText and sends neither request, so no model is called and no Decision is made;
///   - Core.Msg.RunTurns with a SessionRef starts that session's next turn; with an empty SessionRef (the sweep) it puts every
///     running turn back in its queue and sends itself one RunTurns for each session that has queued turns;
///   - starting a turn: under the session's queue lock, when no turn of the session is running, the head of the queue becomes
///     running and its Attempt grows by one. The instance that starts a turn runs it and keeps its TurnRef and Attempt;
///   - a turn sends Decide the request twice, asynchronously and with an answer: Kind decide, then Kind turn whatever the
///     decide answer was (an error status and a wrong class included). The request carries the ids and one code-written
///     Summary, never the text of another turn. The decision landing stores the DecisionRef and publishes chat.message
///     (running); a turn request is fresh with a code-written recap (Recap) when the session's last replied turn was Tainted,
///     and continues otherwise. The turn request of a session start also carries the context {"sessionStart": 1} for Agent.Input.Render
///     (AD-21): a session start is the session's first turn of its local day in the instance zone (a day's earlier turn counts only when its request reached a model: it did not
///     fall back, or its decision has a Usage row), a turn that is fresh, and the turn after a
///     reply with SessionRotated, which the Turn keeps (StartsSession). No other request carries a context: not the decide request, and not Intake's;
///   - the turn's answer: Busy waits BUSYWAIT seconds (a timer) and sends the request again, at most BUSYMAX times, and the next
///     Busy is the fallback rate_limited; SessionBroken sends the request once more as a new Decide call under a new ItemId
///     (RetryItemId), fresh with the recap, and a second SessionBroken is the fallback with the reply's reason (the broken
///     attempt keeps its row, the Turn keeps its own ItemId, and its TurnDecisionRef ends as the retry's); a Reply with
///     Fallback is the fallback with its reason; any other Reply is the reply
///     as sent; an error status, no answer or an answer that is not a Reply is the fallback unusable. A reason outside Msg.Enum
///     FALLBACKREASON is unusable. Conversation never classifies a reply and never renders text: the fallback is the catalog key
///     FALLBACKKEY with the slot fallbackReason;
///   - a usable reply's HostData (AD-6) is read before the turn is saved done: when it is a JSON object with an array checks,
///     Checks.Render makes the catalog key and the rows (AD-28), which the Turn keeps as CheckKey and CheckRows (JSON). Bad JSON,
///     no checks or a failing Render add nothing. The guard has already run in Decide; a fallback, a busy and a broken reply
///     are never read;
///   - the same HostData's arrays citations and memories (at most 5 each, built by code from tool results, after the guard) are
///     kept on the Turn as Citations and Memories (JSON) when they hold an entry of the documented shape; a malformed entry is
///     dropped, and bad JSON or a wrong shape adds nothing. They are read only from a usable reply, like the checks, and go with
///     the turn on chat.message and on the Outbound to Notify;
///   - the same HostData's array learned (Story 41.15; at most MAXLEARNED, {memoryRef, text} entries that MemoryTools put there for a learned save,
///     AD-21) is kept the same way on the Turn as Learned (JSON) and goes on the Outbound and, as the entries to show, on chat.message (the channels render the line under the reply):
///     Conversation renders no text, and the reply text is never changed;
///   - finishing: the Turn is done and saved, then chat.message is published (it carries the turn's shown decision, cost and
///     check rows), an Outbound goes to Notify with the shown decision's Ref (Turn.ShownDecisionRef) and the check key and
///     rows, and RunTurns goes to Conversation itself when the session has a queued turn. A failed publish or send is logged
///     and never stops the turn;
///   - the turn request carries a code-written SystemNote (ToolNote, AD-30): one line for each approved tool call of the session that
///     finished in the turn's window, (the CreatedAt of the previous Turn that was answered, this Turn's CreatedAt] on FinishedAt, so
///     that every finished call is named in the note of exactly one answered turn and the note is the same each time the turn is
///     asked. A line holds the tool's name, done or failed, and the time in the instance zone, from the request row's ToolName, State
///     and FinishedAt only: never its arguments, a result or any model-written text. A read that fails is logged and the note is empty;
///   - an answer whose instance Attempt differs from the Turn's, or whose Turn is not running, changes nothing, so that a turn
///     that a sweep started again gives exactly one reply.
/// The trace: before any send a turn sets %SessionId to the SessionId of the Item's header (the Turn's TraceHeaderId; without
/// that header the instance's own session stays) and %SuperSession to the session's TraceRef (AD-26). The Items of a session
/// share its day's thread (Core.Trace), so the turns of a day are one trace session. When it takes the Item, Conversation also
/// keeps the Item header's position in Visual Trace's item list on the Turn, with and without the event-log rows
/// (Core.Trace.Position, AD-26); a position that cannot be worked out is logged as a warning and left empty, and never stops
/// the turn. The sweep sends its RunTurns requests with no SuperSession, so that the sweep itself stays outside every
/// session's trace; each one takes the session's TraceRef from the instance that runs the turn, because the framework fills a
/// request header's empty SuperSession from the instance that handled it when that instance ends.
/// Reconcile is the way in for code outside the production. OnResponse and OnError read only the instance's own properties and
/// the answer, never the request. Conversation needs the one job that the production gives it (PoolSize 1): Take checks an
/// Item's ItemId and ClientId outside the session's queue lock.
Class OcuTalon.Core.Conversation Extends Ens.BusinessProcess
{

/// The item that takes the decide and turn requests.
Parameter DECIDE = "Decide";

/// The item that routes the Outbound.
Parameter NOTIFY = "Notify";

/// This item: it takes the Items and the RunTurns requests.
Parameter SELF = "Conversation";

/// The item that Reconcile enters through.
Parameter WEBCHATIN = "WebChatIn";

/// Seconds to wait before a Busy turn is sent again.
Parameter BUSYWAIT = 3;

/// How many times a Busy turn is sent again before the fallback.
Parameter BUSYMAX = 5;

/// The catalog key of the fallback reply (AD-32).
Parameter FALLBACKKEY = "conversation.turnFallback";

/// How many of the session's latest done turns the recap holds.
Parameter RECAPTURNS = 20;

/// The longest text of one side of a turn in the recap, the cut mark included.
Parameter RECAPCHARS = 2000;

/// The longest Summary of a request.
Parameter SUMMARYCHARS = 80;

/// Seconds to wait for a session's queue lock.
Parameter LOCKWAIT = 5;

/// The first line of the recap.
Parameter RECAPHEAD = "This conversation so far, as OcuTalon recorded it (the user's messages and OcuTalon's replies as sent):";

/// The start of the user's side of a turn in the recap.
Parameter RECAPUSER = "User: ";

/// The start of OcuTalon's side of a turn in the recap.
Parameter RECAPREPLY = "OcuTalon: ";

/// The first line of the note about finished tool calls.
Parameter TOOLNOTEHEAD = "Approved tool calls that finished since the last message, as OcuTalon recorded them (not their output):";

/// The line of a tool call that finished well; {tool} and {time} are filled by $Replace.
Parameter TOOLNOTEDONE = "- {tool}: done at {time}";

/// The line of a tool call that failed or was interrupted.
Parameter TOOLNOTEFAILED = "- {tool}: failed at {time}";

/// OcuTalon's side of a turn that ended in a fallback.
Parameter RECAPNOANSWER = "(OcuTalon couldn't answer this message.)";

Parameter ERRORREQUEST = "Conversation takes an Item or a RunTurns request, and nothing else.";

Parameter ERRORBUSY = "The turn queue of the session is busy: its lock wasn't free in the time allowed.";

Parameter ERRORSWEEP = "The sweep could not read the turns: ";

Parameter LOGCHECKS = "Conversation added no check results: ";

Parameter LOGSOURCES = "Conversation added no citations or memories: ";

/// The most citations and the most memories a reply carries.
Parameter MAXSOURCES = 5;

/// The most learned saves a reply carries.
Parameter MAXLEARNED = 3;

/// The start of the warning when StartsSession could not read what it needs; the reason follows it.
Parameter LOGSTART = "Conversation could not tell whether the turn starts a session, so it does: ";

Parameter LOGPOSITION = "Conversation could not work out where the Item is in the trace: ";

/// The start of the warning for a dropped Item; one of the DROP texts follows it.
Parameter LOGDROPPED = "Conversation dropped an item: ";

Parameter DROPPROVENANCE = "its provenance is '{provenance}', not user";

Parameter DROPNOITEMID = "it has no ItemId";

Parameter DROPNOTEXT = "it has no text";

Parameter DROPNOSESSION = "it has no session";

Parameter DROPFILEPROVENANCE = "its file is not marked untrusted";

Parameter DROPNOFILE = "its file is not one of the session's files";

/// The Ref of the Turn this instance runs.
Property TurnRef As %String(MAXLEN = 22);

/// The Attempt of the Turn when this instance started it.
Property Attempt As %Integer [ InitialExpression = 0 ];

/// How many times the turn request was sent again because Decide was busy.
Property BusyRequeues As %Integer [ InitialExpression = 0 ];

/// 1 once the turn request was sent again after a broken session.
Property BrokenRetried As %Boolean [ InitialExpression = 0 ];

/// The error status of the last answer, kept by OnError for the OnResponse call that follows it.
Property CallError As %Status [ InitialExpression = {$$$OK} ];

/// An Item or a RunTurns request; anything else is an error and changes nothing.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If '$IsObject($Get(request)) Quit $SYSTEM.Status.Error(5001, ..#ERRORREQUEST)
	If request.%IsA("OcuTalon.Msg.Item") Quit ..Take(request)
	If request.%IsA("OcuTalon.Core.Msg.RunTurns") Quit ..Run(request.SessionRef)
	Quit $SYSTEM.Status.Error(5001, ..#ERRORREQUEST)
}

/// An answer error (the call's key is set): kept for the OnResponse call that follows, which handles it with the key. An error
/// with no key (OnRequest or the framework failed) stays an error, so that the framework logs it and ends the instance.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If pCompletionKey = "" Quit pErrorStatus
	Set ..CallError = pErrorStatus
	Quit $$$OK
}

/// An answer, or the end of a wait, by the key of the call: decide, turn or busy. It never throws: an exception inside is
/// logged and ends the turn with the fallback unusable, and an error status that the handling returns is logged.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set answer = $Get(callresponse)
	Try {
		Set sc = $Case(pCompletionKey, "decide": ..Decided(answer), "turn": ..Replied(answer), "busy": ..Resend(), : $$$OK)
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Do ..Abandon()
	}
	Quit $$$OK
}

/// The Item: queues it as a Turn when it is trusted and new, then starts the session's next turn.
Method Take(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set refusal = ..Untrusted(item)
	If refusal '= "" {
		$$$LOGWARNING(..#LOGDROPPED_refusal)
		Quit $$$OK
	}
	If $IsObject(##class(OcuTalon.Data.Turn).ItemIdIndexOpen(item.ItemId)) Quit $$$OK
	Set found = ##class(OcuTalon.Data.Ownership).TurnByClient(item.SessionRef, item.ClientId, .sc)
	If $$$ISERR(sc) Quit sc
	If $IsObject(found) Quit $$$OK
	Set turn = ##class(OcuTalon.Data.Turn).%New()
	Set turn.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn.SessionRef = item.SessionRef
	Set turn.State = "queued"
	Set turn.Channel = item.Channel
	Set turn.FromGuide = item.FromGuide
	Set turn.ItemId = item.ItemId
	Set turn.ClientId = item.ClientId
	Set turn.Text = item.Text
	If item.FileRef '= "" {
		Set file = ##class(OcuTalon.Core.Files).Describe(item.FileRef, item.SessionRef, .sc)
		If $$$ISERR(sc) Quit sc
		If '$IsObject(file) Quit $$$OK
		Set turn.SentFile = file.%ToJSON()
	}
	Set turn.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	If $IsObject(..%PrimaryRequestHeader) {
		Set turn.TraceHeaderId = ..%PrimaryRequestHeader.%Id()
		Do ..Locate(turn)
	}
	Set sc = turn.%Save()
	If $$$ISERR(sc) Quit sc
	Do ..Announce(turn)
	Quit ..Start(item.SessionRef)
}

/// Keeps the position of the turn's Item header in the trace on the turn (both indexes). A failed read is logged as one warning
/// and leaves both empty.
Method Locate(turn As OcuTalon.Data.Turn) [ Private ]
{
	Set sc = ##class(OcuTalon.Core.Trace).Position(turn.TraceHeaderId, .withEvents, .withoutEvents)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGPOSITION_$SYSTEM.Status.GetErrorText(sc))
		Quit
	}
	Set turn.TraceItemIndex = withEvents
	Set turn.TraceItemIndexNoEvents = withoutEvents
}

/// Why the Item is not taken, "" when it is: untrusted provenance, no ItemId, no text or no Session row. An Item that carries a file is the one exception:
/// it needs provenance untrusted and a file of its own session, and may have no text.
Method Untrusted(item As OcuTalon.Msg.Item) As %String [ Private ]
{
	If item.FileRef '= "" Quit ..UntrustedFile(item)
	If item.Provenance '= "user" Quit $Replace(..#DROPPROVENANCE, "{provenance}", item.Provenance)
	If item.ItemId = "" Quit ..#DROPNOITEMID
	If $ZStrip(item.Text, "<>WC") = "" Quit ..#DROPNOTEXT
	If (item.SessionRef = "") || '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(item.SessionRef)) Quit ..#DROPNOSESSION
	Quit ""
}

/// Why an Item that carries a file is not taken, "" when it is: provenance other than untrusted, no ItemId, no Session row, or a FileRef that is not a
/// file of the Item's session. No text is needed, and the reason names no file.
Method UntrustedFile(item As OcuTalon.Msg.Item) As %String [ Private ]
{
	If item.Provenance '= "untrusted" Quit ..#DROPFILEPROVENANCE
	If item.ItemId = "" Quit ..#DROPNOITEMID
	If (item.SessionRef = "") || '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(item.SessionRef)) Quit ..#DROPNOSESSION
	If '$IsObject(##class(OcuTalon.Core.Files).Describe(item.FileRef, item.SessionRef)) Quit ..#DROPNOFILE
	Quit ""
}

/// A RunTurns request: the sweep for an empty SessionRef, otherwise the session's next turn.
Method Run(sessionRef As %String) As %Status [ Private ]
{
	If sessionRef = "" Quit ..Sweep()
	Quit ..Start(sessionRef)
}

/// The sweep: every running turn goes back to its queue, and each session with queued turns gets a RunTurns request from
/// this item to itself, in SessionRef order. The one read across sessions, so it is not an Ownership row kind.
Method Sweep() As %Status [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT DISTINCT %EXACT(SessionRef) AS Owner FROM OcuTalon_Data.Turn WHERE State IN ('queued', 'running')")
	If $$$ISERR(sc) Quit sc
	Set result = statement.%Execute()
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, ..#ERRORSWEEP_result.%Message)
	Kill owners
	While result.%Next() {
		Set owners(result.%Get("Owner")) = ""
	}
	Set owner = ""
	For {
		Set owner = $Order(owners(owner))
		Quit:owner=""
		Set queued = ..Requeue(owner)
		If queued < 0 Continue
		If queued > 0 Do ..Again(owner)
	}
	Quit $$$OK
}

/// Puts the session's running turns back in its queue under its lock; returns the number of turns now queued, -1 when the
/// session could not be read or locked (it is logged).
Method Requeue(sessionRef As %String) As %Integer [ Private ]
{
	Set count = -1
	Lock +^OcuTalon.Core.TurnQueue(sessionRef):..#LOCKWAIT
	If '$Test {
		$$$LOGERROR(..#ERRORBUSY)
		Quit count
	}
	Try {
		Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(sessionRef, .sc)
		If $$$ISOK(sc) {
			For i = 1:1:queue.Count() {
				Set turn = queue.GetAt(i)
				If turn.State = "running" {
					Set turn.State = "queued"
					Set sc = turn.%Save()
					If $$$ISERR(sc) Quit
				}
			}
		}
		If $$$ISOK(sc) Set count = queue.Count()
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
	Lock -^OcuTalon.Core.TurnQueue(sessionRef)
	Quit count
}

/// Starts the session's next turn: under the queue lock, when none of its turns is running, the head of the queue becomes
/// running with Attempt one higher, and this instance runs it.
Method Start(sessionRef As %String) As %Status [ Private ]
{
	Lock +^OcuTalon.Core.TurnQueue(sessionRef):..#LOCKWAIT
	If '$Test Quit $SYSTEM.Status.Error(5001, ..#ERRORBUSY)
	Set turn = ""
	Try {
		Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(sessionRef, .sc)
		If $$$ISOK(sc) {
			Set running = 0
			For i = 1:1:queue.Count() {
				If queue.GetAt(i).State = "running" Set running = 1
			}
			If 'running && (queue.Count() > 0) {
				Set turn = queue.GetAt(1)
				Set turn.State = "running"
				Set turn.Attempt = turn.Attempt + 1
				Set sc = turn.%Save()
				If $$$ISERR(sc) Set turn = ""
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set turn = ""
	}
	Lock -^OcuTalon.Core.TurnQueue(sessionRef)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(turn) Quit $$$OK
	Quit ..Begin(turn)
}

/// Runs the turn it was given: this instance keeps its Ref and Attempt, joins the turn's trace and sends the decide request.
/// An exception inside is logged and ends the turn with the fallback unusable, so that no exception leaves a started turn
/// running; a decide send that fails is handled as an error answer.
Method Begin(turn As OcuTalon.Data.Turn) As %Status [ Private ]
{
	Set ..TurnRef = turn.Ref
	Set ..Attempt = turn.Attempt
	Set ..BusyRequeues = 0
	Set ..BrokenRetried = 0
	Set ..CallError = $$$OK
	Set sc = $$$OK
	Try {
		Do ..Join(turn)
		If (turn.SentFile '= "") && '..Reader() {
			Set sc = ..Conclude(turn, ##class(OcuTalon.Core.Files).NoReaderText(##class(%DynamicAbstractObject).%FromJSON(turn.SentFile).name), "")
		} Else {
			Set sc = ..Send(..#DECIDE, ..Request(turn, "decide"), 1, "decide")
			If $$$ISERR(sc) {
				$$$LOGSTATUS(sc)
				Set ..CallError = sc
				Set sc = ..Decided("")
			}
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Do ..Abandon()
		Set sc = $$$OK
	}
	Quit sc
}

/// The trace of a turn (AD-26): %SessionId is the session of the Item's header, which stays as it is when the turn has no
/// header, and %SuperSession is the session's TraceRef.
Method Join(turn As OcuTalon.Data.Turn) [ Private ]
{
	If turn.TraceHeaderId '= "" {
		Set header = ##class(Ens.MessageHeader).%OpenId(turn.TraceHeaderId)
		If $IsObject(header) && (header.SessionId '= "") Set ..%SessionId = header.SessionId
	}
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(turn.SessionRef)
	Set ..%SuperSession = $Select($IsObject(session): session.TraceRef, 1: "")
}

/// The request to Decide for the turn (AD-6): rendered input and code-written fields only. context is the optional context of Agent.Input.Render.
Method Request(turn As OcuTalon.Data.Turn, kind As %String, context As %DynamicObject = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Quit ##class(OcuTalon.Core.Intake).RequestFor(..ItemOf(turn), kind, ..%SuperSession, ..%SessionId, context)
}

/// The Item that the turn's row stands for, built for Agent.Input.Render.
ClassMethod ItemOf(turn As OcuTalon.Data.Turn) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = turn.ItemId
	Set item.SessionRef = turn.SessionRef
	Set item.Channel = turn.Channel
	Set item.Provenance = $Select(turn.SentFile '= "": "untrusted", 1: "user")
	Set item.Text = turn.Text
	Set item.FromGuide = turn.FromGuide
	Set item.ClientId = turn.ClientId
	If turn.SentFile '= "" Do ##class(OcuTalon.Core.Files).SetItem(item, ##class(%DynamicAbstractObject).%FromJSON(turn.SentFile))
	Quit item
}

/// The first line of the text, without its leading white space, at most SUMMARYCHARS characters long; a longer line is cut
/// and ends with the cut mark.
ClassMethod Summary(text As %String) As %String
{
	Set line = $Piece($Piece($ZStrip(text, "<WC"), $Char(10), 1), $Char(13), 1)
	If $Length(line) > ..#SUMMARYCHARS Set line = $Extract(line, 1, ..#SUMMARYCHARS - 1)_$Char(8230)
	Quit line
}

/// The decide request is answered, by any outcome: the DecisionRef of a DecisionResponse is kept, chat.message is published
/// (running) and the turn request is sent.
Method Decided(answer As %RegisteredObject) As %Status [ Private ]
{
	Set ..CallError = $$$OK
	Set turn = ..Current()
	If '$IsObject(turn) Quit $$$OK
	If $IsObject(answer) && answer.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Set turn.TriageDecisionRef = answer.DecisionRef
		Set sc = turn.%Save()
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	}
	Do ..Announce(turn)
	Quit ..Ask(turn)
}

/// Sends the turn request: fresh with the recap when the session's history was rejected (BrokenRetried) or its last replied
/// turn was Tainted, otherwise continue. After a broken session the request is a new Decide call, so it carries RetryItemId of
/// the turn's ItemId instead of the ItemId itself (AD-20: one decision per ItemId and Kind); a Busy answer that is asked again
/// after the retry carries the same one. A turn that starts a session (StartsSession) sends the context {"sessionStart": 1} with the request. A send that
/// fails ends the turn with the fallback unusable.
Method Ask(turn As OcuTalon.Data.Turn) As %Status [ Private ]
{
	Set fresh = ..BrokenRetried || ..AfterTaint(turn.SessionRef)
	Set context = ""
	If ..StartsSession(turn, fresh) Set context = {"sessionStart": 1}
	Set request = ..Request(turn, "turn", context)
	Set request.SystemNote = ..ToolNote(turn)
	If fresh {
		Set request.SessionMode = "fresh"
		Set request.SeedText = ..Recap(turn.SessionRef, turn.Ref)
		If ..BrokenRetried Set request.ItemId = ..RetryItemId(turn.ItemId)
	} Else {
		Set request.SessionMode = "continue"
	}
	Set sc = ..Send(..#DECIDE, request, 1, "turn")
	If $$$ISERR(sc) {
		$$$LOGSTATUS(sc)
		Set ..CallError = sc
		Quit ..Replied("")
	}
	Quit $$$OK
}

/// 1 when the turn starts a session (AD-21), so that its turn request carries the context {"sessionStart": 1}: fresh (the turn request is fresh, whether
/// because of a taint or a broken session), or the first turn of its local day in the instance zone (no earlier turn of the session that is not refused and reached a model was
/// created on the same local date as this turn's CreatedAt; an earlier turn reached a model when it did not fall back, or when the decision of its fallback has a usage row of the session,
/// Ownership.DecisionServed, so a day's first turn that fell back before any model call leaves the next turn a start, DW-967), or the session's last replied turn has SessionRotated. turn is the session's newest turn, the one
/// that Conversation is sending: the rotation half reads the session's last replied turn, not the last one before turn. It reads the Turn rows and, for an earlier turn that fell back, the Usage
/// rows of its decision, and the answer is the same each time the turn is asked, a Busy resend included. A read that fails, and a CreatedAt that can't be read, count as a session start,
/// with one warning, so that a failure adds a block of the code-written notes and never loses it.
ClassMethod StartsSession(turn As OcuTalon.Data.Turn, fresh As %Boolean) As %Boolean
{
	If fresh Quit 1
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(turn.SessionRef, .sc)
	Set date = $Piece(##class(OcuTalon.Data.Time).ToLocal(turn.CreatedAt), "T", 1)
	If $$$ISERR(sc) || (date = "") {
		$$$LOGWARNING(..#LOGSTART_$Select($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "the turn has no readable time"))
		Quit 1
	}
	Set first = 1
	For i = 1:1:turns.Count() {
		Set other = turns.GetAt(i)
		If other.Ref = turn.Ref Quit
		If (other.State '= "refused") && ($Piece(##class(OcuTalon.Data.Time).ToLocal(other.CreatedAt), "T", 1) = date) {
			Set reached = 1
			If other.FallbackReason '= "" {
				Set reached = ..Served(other.TurnDecisionRef, turn.SessionRef, .served)
				If $$$ISERR(served) {
					$$$LOGWARNING(..#LOGSTART_$SYSTEM.Status.GetErrorText(served))
					Quit
				}
			}
			If reached {
				Set first = 0
				Quit
			}
		}
	}
	If first Quit 1
	Set last = ..LastReplied(turn.SessionRef, .sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING(..#LOGSTART_$SYSTEM.Status.GetErrorText(sc))
		Quit 1
	}
	Quit $IsObject(last) && last.SessionRotated
}

/// 1 when something reads a sent file (Core.Files.Readable): a file turn runs through Decide; without a reader it is answered with a fixed reply and no model
/// request. A seam for the tests.
Method Reader() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Core.Files).Readable()
}

/// 1 when the decision has a usage row of the session (Ownership.DecisionServed): the turn's request reached a model; sc is the status of the read. A seam for the tests.
ClassMethod Served(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).DecisionServed(decisionRef, sessionRef, .sc)
}

/// The session's last replied turn (Ownership.LastRepliedTurn), or ""; sc is the status of the read.
ClassMethod LastReplied(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).LastRepliedTurn(sessionRef, .sc)
}

/// 1 when the session's last replied turn was Tainted: the next turn then starts a fresh AI session (AD-10). A read that
/// fails counts as Tainted, so that a failure never continues a session that may hold untrusted content.
Method AfterTaint(sessionRef As %String) As %Boolean [ Private ]
{
	Set last = ##class(OcuTalon.Data.Ownership).LastRepliedTurn(sessionRef, .sc)
	If $$$ISERR(sc) Quit 1
	Quit $IsObject(last) && last.Tainted
}

/// The turn request is answered: Busy, SessionBroken, a fallback, the reply, or the fallback unusable for an error, no answer
/// or an answer that is not a Reply.
Method Replied(answer As %RegisteredObject) As %Status [ Private ]
{
	Set error = ..CallError
	Set ..CallError = $$$OK
	Set turn = ..Current()
	If '$IsObject(turn) Quit $$$OK
	If $$$ISERR(error) || '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") Quit ..Conclude(turn, "", "unusable")
	Set turn.Tainted = answer.Tainted
	Set turn.SessionRotated = answer.SessionRotated
	If answer.DecisionRef '= "" Set turn.TurnDecisionRef = answer.DecisionRef
	If answer.Busy Quit ..Delay(turn)
	If answer.SessionBroken Quit ..Rebuild(turn, answer)
	If answer.Fallback Quit ..Conclude(turn, "", ..Reason(answer.FallbackReason))
	Do ..Checked(turn, answer.HostData)
	Do ..Sourced(turn, answer.HostData)
	Quit ..Conclude(turn, answer.Text, "")
}

/// The check results of a usable reply (AD-28): HostData, when it is a JSON object with an array checks, goes to Checks.Render
/// through RenderChecks, and a catalog key or rows that come back are kept on the turn as CheckKey and CheckRows (JSON). Bad
/// JSON, HostData with no checks or an error in Render add nothing; the turn ends normally in every case.
Method Checked(turn As OcuTalon.Data.Turn, hostData As %String) [ Private ]
{
	If hostData = "" Quit
	Try {
		Set data = ##class(%DynamicAbstractObject).%FromJSON(hostData)
		If ($ClassName(data) '= "%Library.DynamicObject") || (data.%GetTypeOf("checks") '= "array") Quit
		Set key = ..RenderChecks(data.checks, .rows)
		Set size = $Select($IsObject($Get(rows)): rows.%Size(), 1: 0)
		If (key = "") && (size = 0) Quit
		Set turn.CheckKey = key
		Set turn.CheckRows = $Select(size > 0: rows.%ToJSON(), 1: "")
	} Catch exception {
		$$$LOGWARNING(..#LOGCHECKS_exception.DisplayString())
	}
}

/// The one call of Checks.Render (AD-28): the catalog key of the results, with the rows to show in rows.
Method RenderChecks(results As %DynamicArray, Output rows As %DynamicArray) As %String [ Private ]
{
	Quit ##class(OcuTalon.Checks.Render).Render(results, .rows)
}

/// The citations, memories and learned saves of a usable reply: the arrays citations, memories and learned of HostData, when it is a JSON object, are kept
/// on the turn as Citations, Memories and Learned (JSON arrays) with the entries of the documented shape only, at most MAXSOURCES (MAXLEARNED for learned) each. A
/// field is set only when an entry is kept. Bad JSON, a wrong shape or an error add nothing; the turn ends normally in every case.
Method Sourced(turn As OcuTalon.Data.Turn, hostData As %String) [ Private ]
{
	If hostData = "" Quit
	Try {
		Set data = ##class(%DynamicAbstractObject).%FromJSON(hostData)
		If $ClassName(data) '= "%Library.DynamicObject" Quit
		Set citations = ..Kept(data, "citations", $ListBuild("documentRef", "document", "section", "passage"), "chunkIndex")
		Set memories = ..Kept(data, "memories", $ListBuild("memoryRef", "text", "savedAt"), "")
		Set learned = ..Kept(data, "learned", $ListBuild("memoryRef", "text"), "", ..#MAXLEARNED)
		If citations '= "" Set turn.Citations = citations
		If memories '= "" Set turn.Memories = memories
		If learned '= "" Set turn.Learned = learned
	} Catch exception {
		$$$LOGWARNING(..#LOGSOURCES_exception.DisplayString())
	}
}

/// The entries of the array member of data as a JSON array: an entry is kept when it is an object whose strings (a list of
/// names) are strings and whose number (a name, or "" for none) is a number; it is cut down to those members, in that order.
/// At most cap entries are kept (MAXSOURCES when no cap is given). "" when the member is not an array or no entry is kept.
Method Kept(data As %DynamicObject, member As %String, strings As %List, number As %String, cap As %Integer = "") As %String [ Private ]
{
	If cap = "" Set cap = ..#MAXSOURCES
	If data.%GetTypeOf(member) '= "array" Quit ""
	Set array = data.%Get(member)
	Set kept = []
	For i = 0:1:array.%Size() - 1 {
		If kept.%Size() >= cap Quit
		If array.%GetTypeOf(i) '= "object" Continue
		Set element = array.%Get(i)
		Set entry = {}, valid = 1
		For j = 1:1:$ListLength(strings) {
			Set name = $List(strings, j)
			If element.%GetTypeOf(name) '= "string" Set valid = 0 Quit
			Do entry.%Set(name, element.%Get(name))
		}
		If valid && (number '= "") {
			If element.%GetTypeOf(number) '= "number" Continue
			Do entry.%Set(number, element.%Get(number), "number")
		}
		If valid Do kept.%Push(entry)
	}
	Quit $Select(kept.%Size(): kept.%ToJSON(), 1: "")
}

/// Decide was busy: waits BUSYWAIT seconds and sends the request again, BUSYMAX times at most; then the fallback rate_limited.
Method Delay(turn As OcuTalon.Data.Turn) As %Status [ Private ]
{
	If ..BusyRequeues >= ..#BUSYMAX Quit ..Conclude(turn, "", "rate_limited")
	Set ..BusyRequeues = ..BusyRequeues + 1
	Set sc = ..Wait(..#BUSYWAIT, "busy")
	If $$$ISERR(sc) {
		$$$LOGSTATUS(sc)
		Quit ..Conclude(turn, "", "unusable")
	}
	Quit $$$OK
}

/// The wait is over: the turn request is sent again.
Method Resend() As %Status [ Private ]
{
	Set ..CallError = $$$OK
	Set turn = ..Current()
	If '$IsObject(turn) Quit $$$OK
	Quit ..Ask(turn)
}

/// The ItemId of the retry of a turn whose session the provider broke: the first 22 characters of the base64url form (+/ become
/// -_, no =) of the SHA-256 of the turn's ItemId followed by /retry. It is the same on every run, is never the turn's own, and
/// keeps the form of an ItemId (AD-6).
ClassMethod RetryItemId(itemId As %String) As %String
{
	Quit $Extract($Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, itemId_"/retry"), 1), "+/=", "-_"), 1, 22)
}

/// The provider rejected the stored history: the first time the request is sent again as a new Decide call, fresh with the recap
/// (Ask); the second time is the fallback with the reply's reason.
Method Rebuild(turn As OcuTalon.Data.Turn, answer As OcuTalon.Bridge.Msg.Reply) As %Status [ Private ]
{
	If ..BrokenRetried Quit ..Conclude(turn, "", ..Reason(answer.FallbackReason))
	Set ..BrokenRetried = 1
	Quit ..Ask(turn)
}

/// The reason if it is one of Msg.Enum FALLBACKREASON, otherwise unusable.
ClassMethod Reason(reason As %String) As %String [ Private ]
{
	Quit $Select($ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), reason): reason, 1: "unusable")
}

/// The Turn of this instance when it may still answer: it is running and its Attempt is the one this instance started. "" for a
/// stale instance, whose answer changes nothing.
Method Current() As OcuTalon.Data.Turn [ Private ]
{
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(..TurnRef)
	If '$IsObject(turn) || (turn.State '= "running") || (turn.Attempt '= ..Attempt) Quit ""
	Quit turn
}

/// Ends the turn with the fallback unusable when this instance failed inside a callback, if it may still answer.
Method Abandon() [ Private ]
{
	Try {
		Set turn = ..Current()
		If $IsObject(turn) Do ..Conclude(turn, "", "unusable")
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// Finishes the turn (AD-30's order): done and saved, then chat.message, the Outbound to Notify, and RunTurns to this item
/// when the session has a queued turn. reason is "" for a reply (replyText as sent) and a fallback reason otherwise.
Method Conclude(turn As OcuTalon.Data.Turn, replyText As %String, reason As %String) As %Status [ Private ]
{
	Set turn.State = "done"
	If reason = "" {
		Set turn.ReplyText = replyText
	} Else {
		Set turn.ReplyCatalogKey = ..#FALLBACKKEY
		Set turn.FallbackReason = reason
	}
	Set sc = turn.%Save()
	If $$$ISERR(sc) Quit sc
	Do ..Announce(turn)
	Do ..Tell(turn)
	Do ..Next(turn.SessionRef)
	Quit $$$OK
}

/// Publishes chat.message for the row, the full current view of the turn. A failure is logged and goes no further.
Method Announce(turn As OcuTalon.Data.Turn) [ Private ]
{
	Try {
		Set sc = ##class(OcuTalon.Live.Publish).Publish(turn.SessionRef, "chat.message", ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn), .seq)
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// Sends the Outbound of the done turn to Notify: the reply text, or for a fallback the catalog key with its slot, the Ref of
/// the decision the turn shows, and the check key and rows. A failure is logged and goes no further.
Method Tell(turn As OcuTalon.Data.Turn) [ Private ]
{
	Try {
		Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
		Set outbound.SessionRef = turn.SessionRef
		Set outbound.OriginChannel = turn.Channel
		Set outbound.Text = turn.ReplyText
		Set outbound.DecisionRef = turn.ShownDecisionRef()
		Set outbound.CheckKey = turn.CheckKey
		Set outbound.CheckRows = turn.CheckRows
		Set outbound.Citations = turn.Citations
		Set outbound.Memories = turn.Memories
		Set outbound.Learned = turn.Learned
		If turn.ReplyCatalogKey '= "" {
			Set outbound.CatalogKey = turn.ReplyCatalogKey
			Set outbound.Slots = {"fallbackReason": (turn.FallbackReason)}.%ToJSON()
		}
		Set sc = ..Send(..#NOTIFY, outbound, 0, "")
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// Sends this item a RunTurns request for the session when it has a queued turn. A failure is logged and goes no further.
Method Next(sessionRef As %String) [ Private ]
{
	Try {
		Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(sessionRef, .sc)
		If $$$ISERR(sc) {
			$$$LOGSTATUS(sc)
			Quit
		}
		For i = 1:1:queue.Count() {
			If queue.GetAt(i).State = "queued" {
				Do ..Again(sessionRef)
				Quit
			}
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// Sends this item a RunTurns request for the session. A failure is logged and goes no further.
Method Again(sessionRef As %String) [ Private ]
{
	Try {
		Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
		Set run.SessionRef = sessionRef
		Set sc = ..Send(..#SELF, run, 0, "")
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// The recap of a conversation for a fresh AI session (AD-10): the session's done turns before the turn, the latest RECAPTURNS
/// of them, each as the user's text and the reply as it was sent (RECAPNOANSWER for a fallback), each side cut at RECAPCHARS
/// characters. It is written by code from the Turn rows, never from a tool result or HostData. "" when there is no earlier turn.
ClassMethod Recap(sessionRef As %String, turnRef As %String) As %String
{
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(sessionRef, .sc)
	If $$$ISERR(sc) Quit ""
	Kill done
	Set count = 0
	For i = 1:1:turns.Count() {
		Set turn = turns.GetAt(i)
		If turn.Ref = turnRef Quit
		If turn.State = "done" {
			Set count = count + 1
			Set done(count) = turn
		}
	}
	If count = 0 Quit ""
	Set first = count - ..#RECAPTURNS + 1
	If first < 1 Set first = 1
	Set recap = ..#RECAPHEAD
	For i = first:1:count {
		Set turn = done(i)
		Set reply = $Select((turn.ReplyCatalogKey '= "") || (turn.ReplyText = ""): ..#RECAPNOANSWER, 1: ..Cut(turn.ReplyText))
		Set recap = recap_$Char(10)_..#RECAPUSER_..Cut(turn.Text)_$Char(10)_..#RECAPREPLY_reply
	}
	Quit recap
}

/// The note about the approved tool calls of the turn's session that finished in the turn's window (AD-30): TOOLNOTEHEAD, then one
/// line for each call, oldest first, with its tool's name, done (the row's State done) or failed (any other), and its FinishedAt as
/// Time.ForMessage gives it relative to the turn's CreatedAt, so that the text is the same each time the turn is asked. The window is
/// (the CreatedAt of the session's previous Turn that was answered, the CreatedAt of this Turn], with no lower bound for the session's
/// first turn. A refused turn is never asked, and a turn that ended in a fallback (FallbackReason set) got no answer from the model,
/// so neither closes a window: the calls of its window are named again in the next turn's note. It is written by code from the
/// request rows' ToolName, State and FinishedAt, never from their arguments or results. "" when no call finished in the window, and
/// when a read fails (the failure is logged).
ClassMethod ToolNote(turn As OcuTalon.Data.Turn) As %String
{
	Set note = ""
	Try {
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(turn.SessionRef, .sc)
		If $$$ISOK(sc) {
			Set after = ""
			Set found = 0
			For i = 1:1:turns.Count() {
				Set one = turns.GetAt(i)
				If one.Ref = turn.Ref {
					Set found = 1
					Quit
				}
				If (one.State '= "refused") && (one.FallbackReason = "") Set after = one.CreatedAt
			}
			If 'found Set sc = $SYSTEM.Status.Error(5001, "The turn "_turn.Ref_" is not among the turns of its session")
		}
		If $$$ISOK(sc) Set calls = ##class(OcuTalon.Data.Ownership).FinishedToolCalls(turn.SessionRef, after, turn.CreatedAt, .sc)
		If $$$ISERR(sc) {
			$$$LOGSTATUS(sc)
		} Else {
			For i = 1:1:calls.Count() {
				Set call = calls.GetAt(i)
				Set line = $Select(call.State = "done": ..#TOOLNOTEDONE, 1: ..#TOOLNOTEFAILED)
				Set line = $Replace($Replace(line, "{time}", ##class(OcuTalon.Data.Time).ForMessage(call.FinishedAt, turn.CreatedAt)), "{tool}", $ZStrip(call.ToolName, "*C"))
				Set note = note_$Select(note = "": ..#TOOLNOTEHEAD, 1: "")_$Char(10)_line
			}
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set note = ""
	}
	Quit note
}

/// The text cut to RECAPCHARS characters; a longer text ends with the cut mark.
ClassMethod Cut(text As %String) As %String [ Private ]
{
	If $Length(text) > ..#RECAPCHARS Quit $Extract(text, 1, ..#RECAPCHARS - 1)_$Char(8230)
	Quit text
}

/// The restart: with the production running, one RunTurns request with an empty SessionRef goes through WebChatIn (AD-1), which
/// makes the sweep. With no production running it answers OK and does nothing: the next start reconciles.
ClassMethod Reconcile() As %Status
{
	If '##class(Ens.Director).IsProductionRunning() Quit $$$OK
	Set sc = ##class(Ens.Director).CreateBusinessService(..#WEBCHATIN, .service)
	If $$$ISERR(sc) Quit sc
	Quit service.ProcessInput(##class(OcuTalon.Core.Msg.RunTurns).%New(), .output)
}

/// The one send of the class: the request to the item, asynchronously, with an answer when responseRequired is 1.
Method Send(target As %String, request As %Library.Persistent, responseRequired As %Boolean, key As %String) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request, responseRequired, key)
}

/// The one timer of the class: its end arrives at OnResponse with the key.
Method Wait(seconds As %Numeric, key As %String) As %Status [ Private ]
{
	Quit ..SetTimer(seconds, key)
}

Storage Default
{
<Data name="ConversationDefaultData">
<Subscript>"Conversation"</Subscript>
<Value name="1">
<Value>TurnRef</Value>
</Value>
<Value name="2">
<Value>Attempt</Value>
</Value>
<Value name="3">
<Value>BusyRequeues</Value>
</Value>
<Value name="4">
<Value>BrokenRetried</Value>
</Value>
<Value name="5">
<Value>CallError</Value>
</Value>
</Data>
<DefaultData>ConversationDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
