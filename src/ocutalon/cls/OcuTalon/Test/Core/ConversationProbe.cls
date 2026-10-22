/// A subclass of OcuTalon.Core.Conversation for the tests, which overrides its private send seam and the framework's SetTimer so
/// that the unit tests run on a slot with no production (Story 2.4; AD-22). It has no Test methods and the product never refers
/// to it. It adds only transient properties.
///   - Send records each call under ^OcuTalonTest("ConversationProbe", RunNumber, n), with n counted in
///     ^OcuTalonTest("ConversationProbe", RunNumber): target, class, key, required and the trace session the instance had set
///     (sessionId, superSession); for a Bridge.Msg.Request kind, provenance, input, itemId, summary, ownerRef, traceRef,
///     channel, threadSessionId, sessionMode and seedText; for an Outbound sessionRef, originChannel, text, catalogKey and
///     slots; for a RunTurns sessionRef. Every call also records the state of the instance's Turn at that moment (turnState)
///     and how many done chat.message events of that Turn the session's stream already holds (doneEvents), which tell the order
///     of saving, publishing and sending. A request to Decide goes to a shadow instance of Test.Core.DecideDouble and its answer
///     is kept; a send to Conversation or Notify is recorded only. FailTarget names a target whose send fails;
///   - SetTimer, which Conversation's own Wait calls, records a call with target wait, key and seconds, and keeps the end of the
///     wait instead of asking Ens.Alarm for it;
///   - Deliver hands the kept answers, and the ends of the waits, in the order they were sent, to OnError and OnResponse as the
///     framework does: an answer that is an error status goes to OnError and then to OnResponse with no answer; any other answer,
///     and the Ens.AlarmResponse of a wait, goes to OnResponse.
///   - ThrowIn makes Join (join) or Decided (decided) throw, for the tests of a failure inside the class;
///   - ItemFor and FreshAfter expose the private ItemOf and AfterTaint to the tests.
Class OcuTalon.Test.Core.ConversationProbe Extends OcuTalon.Core.Conversation
{

/// The subscript of the run under ^OcuTalonTest("ConversationProbe").
Property RunNumber As %String [ Transient ];

/// The target whose send fails with an error status.
Property FailTarget As %String [ Transient ];

/// The method that throws: join (Begin's trace step), decided (the decide answer), or empty for none.
Property ThrowIn As %String [ Transient ];

/// The kept answers: Pending(n) = $ListBuild(key, status), Pending(n, "response") = the answer object.
Property Pending [ MultiDimensional, Transient ];

Method Send(target As %String, request As %Library.Persistent, responseRequired As %Boolean, key As %String) As %Status [ Private ]
{
	Set call = ..Record(target, $ClassName(request), key, responseRequired)
	If request.%Extends("OcuTalon.Bridge.Msg.Request") {
		Set @call@("kind") = request.Kind
		Set @call@("provenance") = request.Provenance
		Set @call@("input") = request.Input
		Set @call@("itemId") = request.ItemId
		Set @call@("summary") = request.Summary
		Set @call@("ownerRef") = request.OwnerRef
		Set @call@("traceRef") = request.TraceRef
		Set @call@("channel") = request.Channel
		Set @call@("threadSessionId") = request.ThreadSessionId
		Set @call@("sessionMode") = request.SessionMode
		Set @call@("seedText") = request.SeedText
	} ElseIf request.%Extends("OcuTalon.Msg.Outbound") {
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("originChannel") = request.OriginChannel
		Set @call@("text") = request.Text
		Set @call@("catalogKey") = request.CatalogKey
		Set @call@("slots") = request.Slots
	} ElseIf request.%Extends("OcuTalon.Core.Msg.RunTurns") {
		Set @call@("sessionRef") = request.SessionRef
	}
	If (..FailTarget '= "") && (target = ..FailTarget) Quit $SYSTEM.Status.Error(5001, "zz send to "_target_" failed")
	If target '= ..#DECIDE Quit $SYSTEM.Status.OK()
	Set double = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.DecideDouble", .sc)
	If '$IsObject(double) Quit sc
	Set sc = double.OnRequest(request, .response)
	Set n = $Increment(..Pending)
	Set ..Pending(n) = $ListBuild(key, sc)
	If $IsObject($Get(response)) Set ..Pending(n, "response") = response
	Quit $SYSTEM.Status.OK()
}

Method SetTimer(pTimeout As %String, pCompletionKey As %String = "", pControlledCompletionKeys As %String = "*", Output pAlarmHandle As %String, pDescription As %String = "", pIsTimer = 1) As %Status
{
	Set pAlarmHandle = ""
	Set call = ..Record("wait", "", pCompletionKey, 1)
	Set @call@("seconds") = pTimeout
	Set n = $Increment(..Pending)
	Set ..Pending(n) = $ListBuild(pCompletionKey, $SYSTEM.Status.OK(), 1)
	Quit $SYSTEM.Status.OK()
}

Method Join(turn As OcuTalon.Data.Turn) [ Private ]
{
	If ..ThrowIn = "join" Throw ##class(%Exception.General).%New("zz join threw", 5001, , "zz join threw")
	Do ##super(turn)
}

Method Decided(answer As %RegisteredObject) As %Status [ Private ]
{
	If ..ThrowIn = "decided" Throw ##class(%Exception.General).%New("zz decided threw", 5001, , "zz decided threw")
	Quit ##super(answer)
}

/// The Item that Conversation builds from the row for Agent.Input.Render.
Method ItemFor(turn As OcuTalon.Data.Turn) As OcuTalon.Msg.Item
{
	Quit ..ItemOf(turn)
}

/// 1 when the next turn of the session starts fresh because of the last replied turn.
Method FreshAfter(sessionRef As %String) As %Boolean
{
	Quit ..AfterTaint(sessionRef)
}

/// Hands the kept answers to the callbacks, oldest first, until none is left or max have been handed (0 for all); answers that
/// the callbacks send in turn are handed too. Returns the number handed.
Method Deliver(max As %Integer = 0) As %Integer
{
	Set count = 0
	While (max = 0) || (count < max) {
		Set n = $Order(..Pending(""))
		If n = "" Quit
		Set entry = ..Pending(n)
		Set response = $Get(..Pending(n, "response"))
		Kill ..Pending(n)
		Set count = count + 1
		Set key = $List(entry, 1)
		Set sc = $List(entry, 2)
		If $ListLength(entry) > 2 {
			Do ..OnResponse("", , "", ##class(Ens.AlarmResponse).%New(), key)
		} ElseIf $SYSTEM.Status.IsError(sc) {
			Do ..OnError("", , "", sc, key)
			Do ..OnResponse("", , "", "", key)
		} Else {
			Do ..OnResponse("", , "", response, key)
		}
	}
	Quit count
}

/// The number of answers kept and not yet handed.
Method PendingCount() As %Integer
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(..Pending(n))
		Quit:n=""
		Set count = count + 1
	}
	Quit count
}

/// Records a call and returns the global reference of its record.
Method Record(target As %String, class As %String, key As %String, required As %Boolean) As %String [ Private ]
{
	Set n = $Increment(^OcuTalonTest("ConversationProbe", ..RunNumber))
	Set call = $Name(^OcuTalonTest("ConversationProbe", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = class
	Set @call@("key") = key
	Set @call@("required") = required
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	Set @call@("turnState") = ""
	Set @call@("doneEvents") = 0
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(..TurnRef)
	If $IsObject(turn) {
		Set @call@("turnState") = turn.State
		Set @call@("doneEvents") = ..DoneEvents(turn)
	}
	Quit call
}

/// How many chat.message events of the Turn with the state done the session's stream holds.
Method DoneEvents(turn As OcuTalon.Data.Turn) As %Integer [ Private ]
{
	Set count = 0
	Set events = ##class(OcuTalon.Live.Event).Since(turn.SessionRef, 0, 200, "session")
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "chat.message") && (event.payload.ref = turn.Ref) && (event.payload.state = "done") Set count = count + 1
	}
	Quit count
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
