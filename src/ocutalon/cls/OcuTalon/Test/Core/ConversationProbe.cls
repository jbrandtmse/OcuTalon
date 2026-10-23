/// A subclass of OcuTalon.Core.Conversation for the tests, which overrides its private send seam and the framework's SetTimer so
/// that the unit tests run on a slot with no production (Story 2.4; AD-22). It has no Test methods and the product never refers
/// to it. It adds only transient properties. The recording of each call under ^OcuTalonTest("ConversationProbe", RunNumber, n),
/// the answers of the Decide double and Deliver, which hands the kept answers to OnError and OnResponse, are those of
/// Test.Core.ProbeSeam.
///   - Send records each call (target, class, key, required and the trace session the instance had set); for a Bridge.Msg.Request
///     the request's fields; for an Outbound sessionRef, originChannel, text, catalogKey, slots, decisionRef, checkKey and
///     checkRows; for a RunTurns sessionRef. Every call also records the state of the instance's Turn at that moment (turnState)
///     and how many done chat.message events of that Turn the session's stream already holds (doneEvents), which tell the order
///     of saving, publishing and sending. A request to Decide goes to a shadow instance of Test.Core.DecideDouble and its answer
///     is kept; a send to Conversation or Notify is recorded only. FailTarget names a target whose send fails;
///   - SetTimer, which Conversation's own Wait calls, records a call with target wait, key and seconds, and keeps the end of the
///     wait instead of asking Ens.Alarm for it, so that Deliver hands the end of the wait to OnResponse as an Ens.AlarmResponse;
///   - RenderChecks, the seam of Checks.Render: when ^OcuTalonTest("ConversationProbe", RunNumber, "render") holds
///     $ListBuild(key, rowsJSON), it records the results it was given under ^OcuTalonTest("ConversationProbe", RunNumber,
///     "rendered", n) as JSON and returns that key and those rows; otherwise it calls the class it extends, the real stub;
///   - ThrowIn makes Join (join), Decided (decided) or RenderChecks (render) throw, for the tests of a failure inside the class;
///   - ItemFor and FreshAfter expose the private ItemOf and AfterTaint to the tests.
Class OcuTalon.Test.Core.ConversationProbe Extends (OcuTalon.Core.Conversation, OcuTalon.Test.Core.ProbeSeam)
{

/// The first subscript of the probe's records.
Parameter ROOT = "ConversationProbe";

/// The method that throws: join (Begin's trace step), decided (the decide answer), render (the call of Checks.Render), or empty for none.
Property ThrowIn As %String [ Transient ];

Method Send(target As %String, request As %Library.Persistent, responseRequired As %Boolean, key As %String) As %Status [ Private ]
{
	Set call = ..Record(target, $ClassName(request), key, responseRequired)
	If request.%Extends("OcuTalon.Bridge.Msg.Request") {
		Do ..RecordRequest(call, request)
	} ElseIf request.%Extends("OcuTalon.Msg.Outbound") {
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("originChannel") = request.OriginChannel
		Set @call@("text") = request.Text
		Set @call@("catalogKey") = request.CatalogKey
		Set @call@("slots") = request.Slots
		Set @call@("decisionRef") = request.DecisionRef
		Set @call@("checkKey") = request.CheckKey
		Set @call@("checkRows") = request.CheckRows
	} ElseIf request.%Extends("OcuTalon.Core.Msg.RunTurns") {
		Set @call@("sessionRef") = request.SessionRef
	}
	If (..FailTarget '= "") && (target = ..FailTarget) Quit $SYSTEM.Status.Error(5001, "zz send to "_target_" failed")
	If target '= ..#DECIDE Quit $SYSTEM.Status.OK()
	Quit ..AskDecide(request, key)
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

Method RenderChecks(results As %DynamicArray, Output rows As %DynamicArray) As %String [ Private ]
{
	If ..ThrowIn = "render" Throw ##class(%Exception.General).%New("zz render threw", 5001, , "zz render threw")
	Set render = $Get(^OcuTalonTest("ConversationProbe", ..RunNumber, "render"))
	If render = "" Quit ##super(results, .rows)
	Set n = $Increment(^OcuTalonTest("ConversationProbe", ..RunNumber, "rendered"))
	Set ^OcuTalonTest("ConversationProbe", ..RunNumber, "rendered", n) = results.%ToJSON()
	Set rows = ##class(%DynamicAbstractObject).%FromJSON($List(render, 2))
	Quit $List(render, 1)
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

/// Records a call with the state of the instance's Turn at that moment: turnState, and doneEvents, how many done chat.message
/// events of that Turn the session's stream already holds.
Method Record(target As %String, class As %String, key As %String, required As %Boolean) As %String [ Private ]
{
	Set call = ##super(target, class, key, required)
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
