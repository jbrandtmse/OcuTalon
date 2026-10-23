/// Conversation, the business process that owns the turn queue of every session (AD-1, AD-6, AD-8, AD-14, AD-30, AD-32). It
/// takes an OcuTalon.Msg.Item from WebChatIn and runs each session's turns one at a time, in CreatedAt and ID order. Every hop
/// is a production message and Conversation never waits for one (no SendRequestSync):
///   - Item: dropped, with a warning, when it is not user provenance or has no ItemId, no text or no Session row (NFR-14), and
///     dropped silently when its ItemId or its ClientId already has a turn of the session. Otherwise it is saved as a queued
///     Turn, chat.message is published, and the session's next turn starts;
///   - Core.Msg.RunTurns with a SessionRef starts that session's next turn; with an empty SessionRef (the sweep) it puts every
///     running turn back in its queue and sends itself one RunTurns for each session that has queued turns;
///   - starting a turn: under the session's queue lock, when no turn of the session is running, the head of the queue becomes
///     running and its Attempt grows by one. The instance that starts a turn runs it and keeps its TurnRef and Attempt;
///   - a turn sends Decide the request twice, asynchronously and with an answer: Kind decide, then Kind turn whatever the
///     decide answer was (an error status and a wrong class included). The request carries the ids and one code-written
///     Summary, never the text of another turn. The decision landing stores the DecisionRef and publishes chat.message
///     (running); a turn request is fresh with a code-written recap (Recap) when the session's last replied turn was Tainted,
///     and continues otherwise;
///   - the turn's answer: Busy waits BUSYWAIT seconds (a timer) and sends the request again, at most BUSYMAX times, and the next
///     Busy is the fallback rate_limited; SessionBroken sends the request once more, fresh with the recap, and the second one is
///     the fallback with the reply's reason; a Reply with Fallback is the fallback with its reason; any other Reply is the reply
///     as sent; an error status, no answer or an answer that is not a Reply is the fallback unusable. A reason outside Msg.Enum
///     FALLBACKREASON is unusable. Conversation never classifies a reply and never renders text: the fallback is the catalog key
///     FALLBACKKEY with the slot fallbackReason;
///   - a usable reply's HostData (AD-6) is read before the turn is saved done: when it is a JSON object with an array checks,
///     Checks.Render makes the catalog key and the rows (AD-28), which the Turn keeps as CheckKey and CheckRows (JSON). Bad JSON,
///     no checks or a failing Render add nothing. The guard has already run in Decide; a fallback, a busy and a broken reply
///     are never read;
///   - finishing: the Turn is done and saved, then chat.message is published (it carries the turn's shown decision, cost and
///     check rows), an Outbound goes to Notify with the shown decision's Ref (Turn.ShownDecisionRef) and the check key and
///     rows, and RunTurns goes to Conversation itself when the session has a queued turn. A failed publish or send is logged
///     and never stops the turn;
///   - an answer whose instance Attempt differs from the Turn's, or whose Turn is not running, changes nothing, so that a turn
///     that a sweep started again gives exactly one reply.
/// The trace: before any send a turn sets %SessionId to the SessionId of the Item's header (the Turn's TraceHeaderId; without
/// that header the instance's own session stays) and %SuperSession to the session's TraceRef (AD-26). The sweep sends its
/// RunTurns requests with no SuperSession, so that the sweep itself stays outside every session's trace; each one takes the
/// session's TraceRef from the instance that runs the turn, because the framework fills a request header's empty
/// SuperSession from the instance that handled it when that instance ends.
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

/// OcuTalon's side of a turn that ended in a fallback.
Parameter RECAPNOANSWER = "(OcuTalon couldn't answer this message.)";

Parameter ERRORREQUEST = "Conversation takes an Item or a RunTurns request, and nothing else.";

Parameter ERRORBUSY = "The turn queue of the session is busy: its lock wasn't free in the time allowed.";

Parameter ERRORSWEEP = "The sweep could not read the turns: ";

Parameter LOGCHECKS = "Conversation added no check results: ";

/// The start of the warning for a dropped Item; one of the DROP texts follows it.
Parameter LOGDROPPED = "Conversation dropped an item: ";

Parameter DROPPROVENANCE = "its provenance is '{provenance}', not user";

Parameter DROPNOITEMID = "it has no ItemId";

Parameter DROPNOTEXT = "it has no text";

Parameter DROPNOSESSION = "it has no session";

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
	Set turn.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	If $IsObject(..%PrimaryRequestHeader) Set turn.TraceHeaderId = ..%PrimaryRequestHeader.%Id()
	Set sc = turn.%Save()
	If $$$ISERR(sc) Quit sc
	Do ..Announce(turn)
	Quit ..Start(item.SessionRef)
}

/// Why the Item is not taken, "" when it is: untrusted provenance, no ItemId, no text or no Session row.
Method Untrusted(item As OcuTalon.Msg.Item) As %String [ Private ]
{
	If item.Provenance '= "user" Quit $Replace(..#DROPPROVENANCE, "{provenance}", item.Provenance)
	If item.ItemId = "" Quit ..#DROPNOITEMID
	If $ZStrip(item.Text, "<>WC") = "" Quit ..#DROPNOTEXT
	If (item.SessionRef = "") || '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(item.SessionRef)) Quit ..#DROPNOSESSION
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
		Set sc = ..Send(..#DECIDE, ..Request(turn, "decide"), 1, "decide")
		If $$$ISERR(sc) {
			$$$LOGSTATUS(sc)
			Set ..CallError = sc
			Set sc = ..Decided("")
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

/// The request to Decide for the turn (AD-6): rendered input and code-written fields only.
Method Request(turn As OcuTalon.Data.Turn, kind As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = "user"
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(..ItemOf(turn))
	Set request.ItemId = turn.ItemId
	Set request.Summary = ..Summary(turn.Text)
	Set request.OwnerRef = turn.SessionRef
	Set request.TraceRef = ..%SuperSession
	Set request.Channel = turn.Channel
	Set request.ThreadSessionId = ..%SessionId
	Quit request
}

/// The Item that the turn's row stands for, built for Agent.Input.Render.
ClassMethod ItemOf(turn As OcuTalon.Data.Turn) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = turn.ItemId
	Set item.SessionRef = turn.SessionRef
	Set item.Channel = turn.Channel
	Set item.Provenance = "user"
	Set item.Text = turn.Text
	Set item.FromGuide = turn.FromGuide
	Set item.ClientId = turn.ClientId
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
/// turn was Tainted, otherwise continue. A send that fails ends the turn with the fallback unusable.
Method Ask(turn As OcuTalon.Data.Turn) As %Status [ Private ]
{
	Set request = ..Request(turn, "turn")
	If ..BrokenRetried || ..AfterTaint(turn.SessionRef) {
		Set request.SessionMode = "fresh"
		Set request.SeedText = ..Recap(turn.SessionRef, turn.Ref)
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
	If answer.DecisionRef '= "" Set turn.TurnDecisionRef = answer.DecisionRef
	If answer.Busy Quit ..Delay(turn)
	If answer.SessionBroken Quit ..Rebuild(turn, answer)
	If answer.Fallback Quit ..Conclude(turn, "", ..Reason(answer.FallbackReason))
	Do ..Checked(turn, answer.HostData)
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

/// The provider rejected the stored history: the first time the request is sent again, fresh with the recap; the second time
/// is the fallback with the reply's reason.
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
