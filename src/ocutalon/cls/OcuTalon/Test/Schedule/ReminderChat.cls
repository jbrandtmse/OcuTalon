/// End-to-end tests of the reminders through the chat over the running production (Story 8.6; AD-1, AD-4, AD-9, AD-18, AD-20, AD-22, AD-26,
/// AD-33, FR-34, NFR-9). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production and the CI
/// mock, which a slot never has. Where they are missing, every test fails with that reason. A message goes through WebChatIn, the REST
/// surface's own entry, to the real Conversation, Chat, Story 1.10's tools, Commands.Submit, CommandsIn and ReminderOps; the CI mock scripts
/// the model. The runners' keys point at the mock for the whole class and are put back at its end, as are the ReminderOps item's class
/// (Test.Schedule.ReminderOpsFixedRef hands out a fixed Ref once) and the stored values of the swap.
///   - TestGuidePromptSetsReminder (DW-232): "Remind me in 1 minute to stretch." (B/guide-reminder.json, selected by its prompt) makes
///     Chat call set_reminder: one pending row, due 60 seconds after the message with the key <ItemId>:1, a live waiter, one created
///     event, the row in the rail with guide step 2 done, the scenario's reply, and an ok tool step in the turn's trace session;
///   - TestThursdaySetsLocalReminder: "Thursday at 10" with the marker reminder-thursday sets a pending row due at
///     Data.Time.FromLocal("2030-11-07T10:00:00") with a live waiter, the scenario's reply and the row in the rail;
///   - TestCancelThroughChat (AD-4): two sessions each set a reminder with the guide prompt; one asks to cancel it with the marker
///     reminder-cancel-chat. The list gives only its own reminder, the cancel (key <ItemId>:2) cancels that one and ends its waiter at
///     once, its one cancelled event takes the row out of its rail, and the other session's row, waiter and events are untouched.
/// A reminder's created event has the state pending, as Test.Schedule.Reminders reads it. The model's history carries the answer to the
/// earlier set tool call of the session, so the tool_results of a later request start with it.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("ReminderChat","n")), Send, WaitDone and the clean-up are those of
/// Test.Core.InProduction; any turn of the run's sessions still there at the end is adopted for its Clean. OnAfterOneTest removes the
/// reminders of the run's sessions with everything the product made for them (ReminderFixture.RemoveAll), the fixed Ref, the turns with
/// their Decision, AgentStep and Usage rows (ReminderFixture.RemoveTurns) and the AI sessions the turns saved.
Class OcuTalon.Test.Schedule.ReminderChat Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodchat";

/// Seconds to wait for a turn to be done.
Parameter WAIT = 60;

/// The guide's prompt of step 2.
Parameter GUIDEPROMPT = "Remind me in 1 minute to stretch.";

/// The Ref that scenario reminder-cancel-chat cancels.
Parameter FIXEDREF = "zzReminderChatCancel01";

/// The reminder tools that Chat offers its model, comma-separated. Chat offers more tools than these, and Triage offers none, so a request
/// is Chat's when it offers every one of them.
Parameter REMINDERTOOLS = "cancel_reminder,list_reminders,set_reminder";

/// 1 while the runners' keys point at the CI mock.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// 1 while ReminderOpsFixedRef may be behind the ReminderOps item.
Property Swapped As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ..Missing '= "" Quit sc
	Set ..Missing = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If ..Missing '= "" Quit sc
	Set ..Pointed = 1
	Set pointed = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	If $$$ISERR(pointed) {
		Set ..Missing = "The entries of the runners could not be pointed at the CI mock key variable: " _ $SYSTEM.Status.GetErrorText(pointed)
		Quit sc
	}
	Set ..Swapped = 1
	Set swapped = ##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Use()
	If $$$ISERR(swapped) Set ..Missing = "The ReminderOps item could not be given the fixed-Ref class: " _ $SYSTEM.Status.GetErrorText(swapped)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..Swapped {
		Set ..Swapped = 0
		Set sc = ##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Restore()
	}
	If ..Pointed {
		Set ..Pointed = 0
		Set restored = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
		Set sc = $SYSTEM.Status.AppendStatus(sc, restored)
		If '##class(OcuTalon.Test.Agent.RunnerFixture).KeysAre(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
		}
		If '##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords() {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The runners did not record the restored keys"))
		}
	}
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	If ..Missing = "" Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveAll(session)
	}
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(..#FIXEDREF)
	Kill ^OcuTalonTest("ReminderOpsFixedRef", "next")
	If ..Missing = "" {
		For i = 1:1:$Length(..Sessions, ",") {
			Set session = $Piece(..Sessions, ",", i)
			If session = "" Continue
			Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(session)
		}
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	}
	Quit $$$OK
}

/// Sends the text as a typed chat message of the session through WebChatIn (the guide's own Send, with FromGuide, is the page spec's) and
/// waits for its turn. row is the Turn, or "" when none was made; chat is the requests of the mock's log since the send that Chat made (a
/// POST to /v1/messages that offers the three reminder tools, among others; Triage offers none), in order. 1 when the turn is done.
Method Turn(session As %String, clientId As %String, text As %String, Output row As OcuTalon.Data.Turn, Output chat As %DynamicArray) As %Boolean [ Private ]
{
	Set chat = []
	Set row = ""
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = ..Send(session, clientId, text, .output)
	Do $$$AssertStatusOK(sc, "WebChatIn takes "_clientId)
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", clientId_" is a new message")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a Turn was made for "_clientId)
		Quit 0
	}
	Do $$$AssertEquals(row.State, "done", clientId_": the turn reaches done within "_..#WAIT_" seconds")
	Set logged = ##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)
	Do $$$AssertStatusOK(logged, "the mock's log is read")
	If $$$ISERR(logged) Quit 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.path = "/v1/messages") && ..OffersReminderTools(entry) Do chat.%Push(entry)
	}
	Quit row.State = "done"
}

/// 1 when the logged request offers every tool of REMINDERTOOLS (RunnerFixture.ToolNames lists the offered names, sorted and comma-separated).
ClassMethod OffersReminderTools(entry As %DynamicObject) As %Boolean [ Private ]
{
	Set offered = ","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_","
	Set wanted = $ListFromString(..#REMINDERTOOLS)
	Set ptr = 0, all = 1
	While $ListNext(wanted, ptr, tool) {
		If offered '[ (","_tool_",") Set all = 0
	}
	Quit all
}

/// Chat made count requests, each selected by selectedBy, with the scenario of that name when one is given.
Method AssertChat(chat As %DynamicArray, count As %Integer, selectedBy As %String, scenario As %String = "") As %Boolean [ Private ]
{
	Do $$$AssertEquals(chat.%Size(), count, "Chat made "_count_" request(s)")
	For i = 0:1:chat.%Size() - 1 {
		Set entry = chat.%Get(i)
		Do $$$AssertEquals(entry.selectedBy, selectedBy, "request "_(i + 1)_" was selected by the "_selectedBy)
		If scenario '= "" Do $$$AssertEquals(entry.scenario, scenario, "request "_(i + 1)_" got the scenario "_scenario)
	}
	Quit chat.%Size() = count
}

/// The Refs of the Reminder rows of the session, whatever their state, as a list in creation order.
ClassMethod ReminderRefs(session As %String) As %List [ Private ]
{
	Set refs = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Reminder WHERE SessionRef = ? ORDER BY ID", session)
	While result.%Next() {
		Set refs = refs _ $ListBuild(result.%Get("Ref"))
	}
	Quit refs
}

/// The number of ReminderTimer instances of the Ref that are waiting.
ClassMethod Waiting(ref As %String) As %Integer [ Private ]
{
	Set timers = ##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(ref)
	Set waiting = 0
	For i = 0:1:timers.%Size() - 1 {
		If ##class(OcuTalon.Test.Schedule.ReminderFixture).IsWaiting(timers.%Get(i)) Set waiting = waiting + 1
	}
	Quit waiting
}

/// The states of the session's reminder events, comma-separated, in order, once there are count of them or the wait is over.
ClassMethod EventStates(session As %String, count As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).States(##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", count, 10))
}

/// The state body of the session: its rail's reminder Refs, comma-separated, in order, and the guide's step 2 as 1 (done) or 0.
ClassMethod State(session As %String, Output rail As %String, Output stepTwoDone As %Boolean) [ Private ]
{
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Set rail = ""
	For i = 0:1:body.rail.reminders.%Size() - 1 {
		Set rail = rail _ $Select(rail = "": "", 1: ",") _ body.rail.reminders.%Get(i).ref
	}
	Set stepTwoDone = 0
	If body.%GetTypeOf("guide") '= "object" Quit
	For i = 0:1:body.guide.steps.%Size() - 1 {
		If body.guide.steps.%Get(i).step = 2 Set stepTwoDone = +body.guide.steps.%Get(i).done
	}
}

/// The value of a tool_result text as a dynamic object: the text is JSON, and a string result is a JSON string whose content is JSON. ""
/// when it is neither.
ClassMethod Parsed(text As %Any) As %DynamicObject [ Private ]
{
	If $IsObject(text) Quit text
	Set value = ""
	Try {
		Set value = ##class(%Library.DynamicAbstractObject).%FromJSON(text)
		If '$IsObject(value) Set value = ##class(%Library.DynamicAbstractObject).%FromJSON(value)
	} Catch {
		Set value = ""
	}
	Quit $Select($IsObject(value): value, 1: "")
}

/// The Refs that a list tool_result names (its reminders[].ref), comma-separated; "none" when the result is not a list.
ClassMethod ListedRefs(text As %Any) As %String [ Private ]
{
	Set list = ..Parsed(text)
	If '$IsObject(list) || (list.%GetTypeOf("reminders") '= "array") Quit "none"
	Set refs = ""
	For i = 0:1:list.reminders.%Size() - 1 {
		Set refs = refs _ $Select(refs = "": "", 1: ",") _ list.reminders.%Get(i).ref
	}
	Quit refs
}

/// Waits until the decision has count AgentStep rows or the seconds have passed (the AgentSteps operation writes them after the turn), and
/// answers the rows.
ClassMethod WaitSteps(decisionRef As %String, count As %Integer, seconds As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(decisionRef)
		If (steps.%Size() >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit steps
}

/// The steps of Visual Trace (AD-9, AD-26) of the turn's decision: a model step, then a tool step and a model step for each tool call. The
/// tool steps have the labels, their summaries name the tools and their status is ok. Every AgentStep of the decision has a header in the
/// turn's trace session, the session of the header the Turn names, and none has a header outside it.
Method AssertToolSteps(row As OcuTalon.Data.Turn, tools As %List, labels As %List) [ Private ]
{
	Set steps = ..WaitSteps(row.TurnDecisionRef, 1 + (2 * $ListLength(labels)), 10)
	Set kinds = "model"
	For i = 1:1:$ListLength(labels) {
		Set kinds = kinds _ ",tool,model"
	}
	Set actual = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set actual = actual _ $Select(actual = "": "", 1: ",") _ step.kind
	}
	Do $$$AssertEquals(actual, kinds, "the steps are "_kinds)
	Set toolPosition = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set toolPosition = toolPosition + 1
		If toolPosition > $ListLength(labels) Continue
		Do $$$AssertEquals(step.label, $List(labels, toolPosition), "tool step "_toolPosition_" has the label "_$List(labels, toolPosition))
		Do $$$AssertTrue(step.summary [ $List(tools, toolPosition), "and its summary names "_$List(tools, toolPosition)_": "_$Extract(step.summary, 1, 120))
		Do $$$AssertEquals(step.status, "ok", "and its status is ok")
	}
	Set header = ##class(Ens.MessageHeader).%OpenId(row.TraceHeaderId)
	If '$IsObject(header) {
		Do $$$AssertTrue(0, "the turn's trace header "_row.TraceHeaderId_" exists")
		Quit
	}
	Set outside = 0
	Set inside = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? AND SessionId <> ?", "OcuTalon.Bridge.Msg.AgentStep", step.id, header.SessionId)
		Do rows.%Next()
		Set outside = outside + rows.%GetData(1)
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? AND SessionId = ?", "OcuTalon.Bridge.Msg.AgentStep", step.id, header.SessionId)
		Do rows.%Next()
		If rows.%GetData(1) > 0 Set inside = inside + 1
	}
	Do $$$AssertEquals(outside, 0, "no step has a header outside the turn's trace session")
	Do $$$AssertEquals(inside, steps.%Size(), "every step has a header in the turn's trace session: "_inside_" of "_steps.%Size()_" steps")
}

/// "Remind me in 1 minute to stretch." (DW-232): the guide's prompt is answered by B/guide-reminder.json, selected by the prompt. Chat calls
/// set_reminder and the turn ends with the scenario's reply and no fallback. The session has one row: stretch, pending, key <ItemId>:1,
/// due between 60 seconds after the send and 60 seconds after the turn; its waiter is waiting, its events are created, the rail lists it
/// and guide step 2 is done. The tool step is ok in the turn's trace session.
Method TestGuidePromptSetsReminder()
{
	If '..Guard() Quit
	Set session = ..Session("guide")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	If '..Turn(session, "zzc"_..Number_"guide", ..#GUIDEPROMPT, .row, .chat) Quit
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(row.ReplyText_"|"_row.FallbackReason, "The CI mock set the reminder.|", "the reply is the scenario's and the turn is no fallback")
	Do ..AssertChat(chat, 2, "prompt", "guide-reminder")
	Set refs = ..ReminderRefs(session)
	Do $$$AssertEquals($ListLength(refs), 1, "the session has one reminder")
	If $ListLength(refs) '= 1 Quit
	Set reminder = ##class(OcuTalon.Data.Reminder).RefIndexOpen($List(refs, 1))
	Do $$$AssertEquals(reminder.Text_"|"_reminder.State_"|"_reminder.IdempotencyKey, "stretch|pending|"_row.ItemId_":1", "it is stretch, pending, with the key of the first tool call of the turn")
	Set lower = ##class(OcuTalon.Data.Time).AddSeconds(before, 60)
	Set upper = ##class(OcuTalon.Data.Time).AddSeconds(after, 60)
	Set due = ##class(OcuTalon.Data.Time).Seconds(reminder.DueAt)
	Do $$$AssertTrue((due >= ##class(OcuTalon.Data.Time).Seconds(lower)) && (due <= ##class(OcuTalon.Data.Time).Seconds(upper)), "it is due 60 seconds after the message: "_lower_" <= "_reminder.DueAt_" <= "_upper)
	Do $$$AssertEquals(..Waiting(reminder.Ref), 1, "its waiter is waiting")
	Do $$$AssertEquals(..EventStates(session, 1), "pending", "its one event is the created one (state pending)")
	Do ..State(session, .rail, .stepTwoDone)
	Do $$$AssertEquals(rail, reminder.Ref, "the rail lists it")
	Do $$$AssertEquals(stepTwoDone, 1, "and guide step 2 is done")
	Do ..AssertToolSteps(row, $ListBuild("set_reminder"), $ListBuild("Setting a reminder"))
}

/// "Remind me Thursday at 10 to load the new certificate." with the marker reminder-thursday: Chat calls set_reminder with a local time. The
/// reply is the scenario's, selected by the marker; the session has one pending row, load the new certificate, due at
/// Data.Time.FromLocal("2030-11-07T10:00:00") (AD-18), with a waiting waiter; the rail lists it and the tool step is ok.
Method TestThursdaySetsLocalReminder()
{
	If '..Guard() Quit
	Set session = ..Session("thursday")
	If '..Turn(session, "zzc"_..Number_"thursday", "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-thursday]]", .row, .chat) Quit
	Do $$$AssertEquals(row.ReplyText_"|"_row.FallbackReason, "The CI mock set the Thursday reminder.|", "the reply is the scenario's and the turn is no fallback")
	Do ..AssertChat(chat, 2, "marker")
	Set refs = ..ReminderRefs(session)
	Do $$$AssertEquals($ListLength(refs), 1, "the session has one reminder")
	If $ListLength(refs) '= 1 Quit
	Set reminder = ##class(OcuTalon.Data.Reminder).RefIndexOpen($List(refs, 1))
	Do $$$AssertEquals(reminder.Text_"|"_reminder.State, "load the new certificate|pending", "it is the Thursday text, pending")
	Do $$$AssertEquals(reminder.DueAt, ##class(OcuTalon.Data.Time).FromLocal("2030-11-07T10:00:00"), "it is due at 10:00 local time on Thursday 2030-11-07")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(reminder.DueAt), "2030-11-07T10:00:00", "and read back in the instance zone it is 10:00 on that Thursday")
	Do $$$AssertEquals(..Waiting(reminder.Ref), 1, "its waiter is waiting")
	Do ..State(session, .rail, .stepTwoDone)
	Do $$$AssertEquals(rail, reminder.Ref, "the rail lists it")
	Do ..AssertToolSteps(row, $ListBuild("set_reminder"), $ListBuild("Setting a reminder"))
}

/// Two sessions each set a reminder with the guide prompt; A's has the fixed Ref (ReminderOpsFixedRef) and B's another. A sends "Cancel my
/// reminder to stretch." with the marker reminder-cancel-chat. Chat lists, then cancels, in three requests: the list names exactly A's Ref,
/// not B's, and the cancel's answer is ok with that Ref. A's row is cancelled with the key <cancel ItemId>:2, its waiter ends long before
/// its 60-second due time, its events are created and cancelled, and its rail has no reminder. B's row is pending, its waiter is waiting
/// and its events are created. The tool steps are the list, then the cancel.
Method TestCancelThroughChat()
{
	If '..Guard() Quit
	Set fixed = ..#FIXEDREF
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(fixed)
	Set a = ..Session("cancela")
	Set b = ..Session("cancelb")
	Do ##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Next(fixed)
	If '..Turn(a, "zzc"_..Number_"seta", ..#GUIDEPROMPT, .setA, .chatA) Quit
	Set refsA = ..ReminderRefs(a)
	Do $$$AssertEquals($ListLength(refsA)_"|"_$ListGet(refsA, 1), "1|"_fixed, "control: A's reminder has the fixed Ref")
	If '..Turn(b, "zzc"_..Number_"setb", ..#GUIDEPROMPT, .setB, .chatB) Quit
	Set refsB = ..ReminderRefs(b)
	Do $$$AssertEquals($ListLength(refsB), 1, "control: B has one reminder")
	If $ListLength(refsB) '= 1 Quit
	Set refB = $List(refsB, 1)
	Do $$$AssertTrue(refB '= fixed, "and its Ref differs from the fixed one: "_refB)
	Do $$$AssertEquals(..Waiting(fixed)_"|"_..Waiting(refB), "1|1", "both waiters are waiting")

	If '..Turn(a, "zzc"_..Number_"cancela", "Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]", .row, .chat) Quit
	Do $$$AssertEquals(row.ReplyText_"|"_row.FallbackReason, "The CI mock cancelled the reminder.|", "the reply is the scenario's and the turn is no fallback")
	If ..AssertChat(chat, 3, "marker") {
		Set second = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(1))
		Do $$$AssertEquals($ListLength(second), 2, "request 2 carries the history's answer to the set and the list")
		If $ListLength(second) = 2 Do $$$AssertEquals(..ListedRefs($List(second, 2)), fixed, "the list names A's reminder only, not B's")
		Set third = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(2))
		Do $$$AssertEquals($ListLength(third), 3, "request 3 carries the history's answer to the set, the list and the answer to the cancel")
		If $ListLength(third) = 3 {
			Do $$$AssertEquals($List(third, 2), $List(second, 2), "the list is as it was")
			Set answer = ..Parsed($List(third, 3))
			Do $$$AssertTrue($IsObject(answer), "the answer to the cancel is a JSON object")
			If $IsObject(answer) Do $$$AssertEquals(answer.%GetTypeOf("ok")_"|"_answer.ok_"|"_answer.ref, "boolean|1|"_fixed, "the cancel is ok and names A's Ref")
		}
	}
	Set reminderA = ##class(OcuTalon.Data.Reminder).RefIndexOpen(fixed)
	Do $$$AssertEquals(reminderA.State_"|"_reminderA.CancelKey, "cancelled|"_row.ItemId_":2", "A's reminder is cancelled by the second tool call of the cancel turn")
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(fixed, 10), "and its waiter has ended, long before its due time")
	Do $$$AssertEquals(..EventStates(a, 2), "pending,cancelled", "A's events are the created one (state pending), then the cancelled one")
	Do ..State(a, .railA, .stepTwoA)
	Do $$$AssertEquals(railA, "", "A's rail has no reminder")
	Set reminderB = ##class(OcuTalon.Data.Reminder).RefIndexOpen(refB)
	Do $$$AssertEquals(reminderB.State_"|"_..Waiting(refB), "pending|1", "B's reminder is pending and its waiter is waiting")
	Do $$$AssertEquals(..EventStates(b, 1), "pending", "B's one event is the created one (state pending)")
	Do ..State(b, .railB, .stepTwoB)
	Do $$$AssertEquals(railB, refB, "B's rail still lists it")
	Do ..AssertToolSteps(row, $ListBuild("list_reminders", "cancel_reminder"), $ListBuild("Listing your reminders", "Cancelling a reminder"))
}

}
