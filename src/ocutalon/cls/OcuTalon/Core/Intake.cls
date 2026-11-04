/// Intake, the business process that takes in an untrusted item, asks for its attention decision and sends the decision on
/// (AD-6, AD-10, AD-14, AD-26, AD-30). It takes an OcuTalon.Msg.Item from a channel service or a check, and never waits for a
/// call: every send goes through one private seam (Send) that calls SendRequestAsync.
///   - A refused item: a message that is not an Item, an Item whose provenance is not untrusted (user text goes to
///     Conversation, NFR-14), one with no ItemId or no owner (SessionRef), one with no Text, Subject and Sender. Intake logs a
///     warning, naming the Item's ItemId and channel when it is an Item, and sends nothing;
///   - the trace: Intake keeps the session of its inbound header, which is the item's own trace session (AD-26), and sets
///     %SuperSession to the owner session's TraceRef when the header carries none and the owner is a session;
///   - the decide request: Intake sends Decide a request of Kind decide (key decide, an answer required) that RequestFor
///     builds from the Item: Agent.Input.Render of the Item, the item's provenance, ids and channel, the owner and a code-written
///     Summary ("{Sender}: {Subject}", or the one that is set, else the first line of the text, cut at 80 characters);
///   - Decide's answer: a DecisionResponse whose Outcome is in Msg.Enum OUTCOME gives the DecisionRef, the Outcome (tellnow
///     for a fallback), Fallback and FallbackReason (unusable when the reason is not in FALLBACKREASON). Anything else, an
///     error status, no answer, an answer of another class or an unknown outcome, is the fallback: Outcome tellnow, Fallback 1,
///     FallbackReason unusable and no DecisionRef;
///   - act: on an act that is not a fallback Intake first sends Decide a request of Kind turn (key turn, an answer required)
///     with the same fields, provenance untrusted and SessionMode fresh, and no SeedText, so that it never touches the user's
///     conversation (AD-10). Whatever the turn answers, or if its send fails, Intake then sends the ItemDecision. The turn's
///     reply is not delivered: it stays in the turn's Decision row and in the trace;
///   - the ItemDecision: the Item's ItemId, SourceItemId, owner, Channel, CatalogKey and Slots, the request's Summary and
///     Decide's answer as above. It goes asynchronously, with no answer, to OutcomeRouter (a session or instance owner) or
///     to EvalSink (owner eval, AD-22), never to both.
/// Intake never sends to Conversation or Notify, writes no Turn row and publishes no live event. OnResponse and OnError never
/// throw: an exception inside is logged and sends the fallback ItemDecision when none has gone yet.
Class OcuTalon.Core.Intake Extends Ens.BusinessProcess
{

/// The item that takes the decide and turn requests.
Parameter DECIDE = "Decide";

/// The item that routes the ItemDecision of a session or instance owner.
Parameter OUTCOMEROUTER = "OutcomeRouter";

/// The item that takes the ItemDecision of the evaluation owner.
Parameter EVALSINK = "EvalSink";

/// The start of the warning for a refused item; one of the REFUSED texts follows it.
Parameter LOGREFUSED = "Intake refused an item: ";

Parameter REFUSEDCLASS = "it is not an Item";

Parameter REFUSEDPROVENANCE = "its provenance is '{provenance}', not untrusted";

Parameter REFUSEDNOITEMID = "it has no ItemId";

Parameter REFUSEDNOOWNER = "it has no owner";

Parameter REFUSEDNOCONTENT = "it has no text, subject or sender";

/// The end of the warning for a refused Item: which Item it was.
Parameter LOGITEM = " (ItemId {itemId}, channel {channel})";

/// The Ref of the Decision row of Decide's answer; empty for the fallback.
Property DecisionRef As %String(MAXLEN = 22);

/// The outcome of Decide's answer: one of Msg.Enum OUTCOME.
Property Outcome As %String(MAXLEN = 32);

/// 1 when Decide's answer is the fallback route.
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason of the answer: one of Msg.Enum FALLBACKREASON; empty when Fallback is 0.
Property FallbackReason As %String(MAXLEN = 32);

/// 1 once the ItemDecision has been sent.
Property Sent As %Boolean [ InitialExpression = 0 ];

/// The error status of the last answer, kept by OnError for the OnResponse call that follows it.
Property CallError As %Status [ InitialExpression = {$$$OK} ];

/// An untrusted Item; anything else is refused with a warning, and nothing is sent.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	Set refusal = ..Refusal($Get(request))
	If refusal '= "" {
		$$$LOGWARNING(..#LOGREFUSED_refusal_..Describe($Get(request)))
		Quit $$$OK
	}
	Set sc = $$$OK
	Try {
		Do ..Join(request)
		Set sc = ..Send(..#DECIDE, ..RequestFor(request, "decide", ..%SuperSession, ..%SessionId), 1, "decide")
		If $$$ISERR(sc) {
			$$$LOGSTATUS(sc)
			Set ..CallError = sc
			Set sc = ..Decided(request, "")
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Do ..Abandon(request)
		Set sc = $$$OK
	}
	Quit sc
}

/// An answer error (the call's key is set): kept for the OnResponse call that follows, which handles it with the key. An error
/// with no key (OnRequest or the framework failed) stays an error, so that the framework logs it and ends the instance.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	If pCompletionKey = "" Quit pErrorStatus
	Set ..CallError = pErrorStatus
	Quit $$$OK
}

/// An answer by the key of the call: decide or turn. It never throws: an exception inside is logged and sends the fallback
/// ItemDecision, and an error status that the handling returns is logged.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, pCompletionKey As %String) As %Status
{
	Set answer = $Get(callresponse)
	Try {
		Set sc = $Case(pCompletionKey, "decide": ..Decided(request, answer), "turn": ..Finish(request), : $$$OK)
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Do ..Abandon(request)
	}
	Quit $$$OK
}

/// Why the message is not taken, "" when it is: not an Item, provenance other than untrusted, no ItemId, no owner or no content.
Method Refusal(item As %RegisteredObject) As %String [ Private ]
{
	If '$IsObject(item) || 'item.%IsA("OcuTalon.Msg.Item") Quit ..#REFUSEDCLASS
	If item.Provenance '= "untrusted" Quit $Replace(..#REFUSEDPROVENANCE, "{provenance}", item.Provenance)
	If item.ItemId = "" Quit ..#REFUSEDNOITEMID
	If item.SessionRef = "" Quit ..#REFUSEDNOOWNER
	If ($ZStrip(item.Text, "<>WC") = "") && ($ZStrip(item.Subject, "<>WC") = "") && ($ZStrip(item.Sender, "<>WC") = "") Quit ..#REFUSEDNOCONTENT
	Quit ""
}

/// The ItemId and the channel of the message when it is an Item, as the end of a warning, each cut at 40 characters; empty for any
/// other message.
Method Describe(item As %RegisteredObject) As %String [ Private ]
{
	If '$IsObject(item) || 'item.%IsA("OcuTalon.Msg.Item") Quit ""
	Quit $Replace($Replace(..#LOGITEM, "{itemId}", $Extract(item.ItemId, 1, 40)), "{channel}", $Extract(item.Channel, 1, 40))
}

/// The trace of the item (AD-26): the instance keeps the session of its inbound header, and %SuperSession becomes the owner
/// session's TraceRef when the header carried none and the owner is a session.
Method Join(item As OcuTalon.Msg.Item) [ Private ]
{
	If ..%SuperSession '= "" Quit
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(item.SessionRef)
	If $IsObject(session) Set ..%SuperSession = session.TraceRef
}

/// The request to Decide for the item (AD-6): rendered input and code-written fields only. Conversation builds its requests
/// here too, from the Item that stands for a turn.
ClassMethod RequestFor(item As OcuTalon.Msg.Item, kind As %String, traceRef As %String, threadSessionId As %Integer) As OcuTalon.Bridge.Msg.Request
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = item.Provenance
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(item)
	Set request.ItemId = item.ItemId
	Set request.Summary = ..SummaryOf(item)
	Set request.OwnerRef = item.SessionRef
	Set request.TraceRef = traceRef
	Set request.Channel = item.Channel
	Set request.ThreadSessionId = threadSessionId
	Quit request
}

/// The code-written summary of the item: "{Sender}: {Subject}" for mail, the one that is set when only one is, otherwise the
/// first line of the text. Each goes through Conversation.Summary's cut of 80 characters.
ClassMethod SummaryOf(item As OcuTalon.Msg.Item) As %String
{
	Set sender = $ZStrip(item.Sender, "<>WC")
	Set subject = $ZStrip(item.Subject, "<>WC")
	If (sender '= "") && (subject '= "") Quit ##class(OcuTalon.Core.Conversation).Summary(sender_": "_subject)
	If (sender '= "") || (subject '= "") Quit ##class(OcuTalon.Core.Conversation).Summary(sender_subject)
	Quit ##class(OcuTalon.Core.Conversation).Summary(item.Text)
}

/// The decide request is answered, by any outcome: the answer becomes the outcome, then an act that is not a fallback runs
/// its untrusted turn, and anything else sends the ItemDecision.
Method Decided(item As OcuTalon.Msg.Item, answer As %RegisteredObject) As %Status [ Private ]
{
	Set error = ..CallError
	Set ..CallError = $$$OK
	Do ..Take($Select($$$ISERR(error): "", 1: answer))
	If (..Outcome '= "act") || ..Fallback Quit ..Finish(item)
	Set request = ..RequestFor(item, "turn", ..%SuperSession, ..%SessionId)
	Set request.SessionMode = "fresh"
	Set sc = ..Send(..#DECIDE, request, 1, "turn")
	If $$$ISERR(sc) {
		$$$LOGSTATUS(sc)
		Quit ..Finish(item)
	}
	Quit $$$OK
}

/// Keeps the outcome of Decide's answer: a DecisionResponse with an Outcome of Msg.Enum OUTCOME as it is (a fallback is
/// tellnow, and a reason outside FALLBACKREASON is unusable); anything else is the fallback unusable with no DecisionRef.
Method Take(answer As %RegisteredObject) [ Private ]
{
	Set ..DecisionRef = ""
	Set ..Outcome = "tellnow"
	Set ..Fallback = 1
	Set ..FallbackReason = "unusable"
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") Quit
	If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#OUTCOME), answer.Outcome) Quit
	Set ..DecisionRef = answer.DecisionRef
	Set ..Fallback = +answer.Fallback
	If ..Fallback {
		Set ..Outcome = "tellnow"
		Set ..FallbackReason = $Select($ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#FALLBACKREASON), answer.FallbackReason): answer.FallbackReason, 1: "unusable")
	} Else {
		Set ..Outcome = answer.Outcome
		Set ..FallbackReason = ""
	}
}

/// Sends the ItemDecision, once: to EvalSink for the evaluation owner, otherwise to OutcomeRouter.
Method Finish(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	If ..Sent Quit $$$OK
	Set decision = ##class(OcuTalon.Msg.ItemDecision).%New()
	Set decision.ItemId = item.ItemId
	Set decision.SourceItemId = item.SourceItemId
	Set decision.OwnerRef = item.SessionRef
	Set decision.Channel = item.Channel
	Set decision.Summary = ..SummaryOf(item)
	Set decision.DecisionRef = ..DecisionRef
	Set decision.Outcome = ..Outcome
	Set decision.Fallback = ..Fallback
	Set decision.FallbackReason = ..FallbackReason
	Set decision.CatalogKey = item.CatalogKey
	Set decision.Slots = item.Slots
	Set ..Sent = 1
	Quit ..Send($Select(item.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL: ..#EVALSINK, 1: ..#OUTCOMEROUTER), decision, 0, "")
}

/// After an exception: the fallback ItemDecision, if none has gone yet. A failure here is logged and goes no further.
Method Abandon(item As %RegisteredObject) [ Private ]
{
	Try {
		If ..Sent Quit
		Do ..Take("")
		Set sc = ..Finish(item)
		If $$$ISERR(sc) $$$LOGSTATUS(sc)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
	}
}

/// The one send of the class: the request to the item, asynchronously, with an answer when responseRequired is 1.
Method Send(target As %String, request As %Library.Persistent, responseRequired As %Boolean, key As %String) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request, responseRequired, key)
}

Storage Default
{
<Data name="IntakeDefaultData">
<Subscript>"Intake"</Subscript>
<Value name="1">
<Value>DecisionRef</Value>
</Value>
<Value name="2">
<Value>Outcome</Value>
</Value>
<Value name="3">
<Value>Fallback</Value>
</Value>
<Value name="4">
<Value>FallbackReason</Value>
</Value>
<Value name="5">
<Value>Sent</Value>
</Value>
<Value name="6">
<Value>CallError</Value>
</Value>
</Data>
<DefaultData>IntakeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
