/// The outcomes of a beat, end to end on the real production (Story 39.4; AC 6 to 8, AC 10; Integration AC; AD-6, AD-10, AD-14, AD-18, AD-26, AD-28, AD-30, AD-32).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Checks.BeatCase (Test.Watch.Case), and fresh: a real Tick acts on every
/// check row of the namespace, so each test asserts only on its own rows. Each test makes a person whose checklist holds a heartbeat-* marker of the CI mock (named
/// with the person's Ref, so that the mock's log tells the requests apart) and whose beat is due at a time that no real Tick reaches, then sends the Tick at that time
/// as HeartbeatIn does. The real Checks builds the snapshot, Intake asks the real Decide, and OutcomeRouter, Notify and DigestStore (real instances) route it.
///   - TestIgnore (AC 6, AC 7, AC 8): heartbeat-ignore, whose reply has a fixed usage: the Decision is an ignore, and no Notification, Delivery or chat message follows.
///     The DecisionResponse from Decide to Intake carries the fixed tokens and the cost of the Decision row, whose trace session is the Item's own (the Item's
///     SuperSession is the person's TraceRef). The next Tick records the decision and sets LastQuietKey. The mock's request carries the status line;
///   - TestTellNow (AC 6): heartbeat-tellnow: one web-chat notice whose what-happened is the beat's subject and whose reason is the first reason. The person also
///     holds a mail decision with a Usage row, whose channel is in the mock's request: the Usage read works in the production's own job;
///   - TestDigest (AC 6): heartbeat-digest: one Digest.Data.Item (channel heartbeat, the beat's subject), and no notice;
///   - TestAct (AC 6, AC 10; NFR-14): heartbeat-act, armed once, whose turn asks for recent_activity and stop_watch: a turn Decision, untrusted, the stop_watch step
///     is denied (UNTRUSTED), the read-only step runs, no approval request exists, nothing reaches WatchOps or CommandsIn, and the watch is still there;
///   - TestAllClearIsGuarded (AC 8): heartbeat-all-clear: the reserved wording is gone from the Decision's reasons and from the notice, whose reason is the second one;
///   - TestWatchRunsAgain (AC 4): a person with a real watch and heartbeat-ignore: the watch runs again between the beats with the same result, and the beat due one
///     interval later is skipped as unchanged, with no request.
/// Every test also asserts that the person's BackgroundCheck rows are unchanged and that the beat made no check event (a beat is no background check, AD-28).
Class OcuTalon.Test.Checks.BeatOutcomes Extends OcuTalon.Test.Checks.BeatCase
{

Parameter SESSIONPREFIX = "zzbeatout";

/// Seconds to wait, after the decision reached OutcomeRouter, to be sure that a route left nothing.
Parameter QUIETWAIT = 4;

/// The markers that the test armed in the mock, comma-separated.
Property Armed As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Armed, ",") {
		If $Piece(..Armed, ",", i) '= "" Do ##class(OcuTalon.Test.Contract.Mock).Arm($Piece(..Armed, ",", i), "")
	}
	Set ..Armed = ""
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE ItemId = ?", itemId)
	}
	Quit ##super(testname)
}

Method TestIgnore()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set case = ..Start("ignore", "heartbeat-ignore")
	If '$IsObject(case) Quit
	Set item = case.item
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback, "ignore|0", "the Decision is the scenario's ignore")
	Do ..AssertRequest(case, 1)
	Do ..Quiet(item)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(case.session), 0, "no Delivery row is recorded")
	Do $$$AssertEquals(..NoticesIn(item.sessionId), 0, "no Notification is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(case.session, "chat.message").%Size(), 0, "and no chat message is published")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(case.session).Count(), 0, "or made")

	// AC 7: the answer of Decide, the Decision row and the trace
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(item.sessionId), 2, "Decide", "Intake")
	Do $$$AssertEquals(answers.%Size(), 1, "Decide answers Intake once, in the Item's trace session")
	If answers.%Size() = 1 {
		Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%OpenId(answers.%Get(0).bodyId)
		Do $$$AssertTrue($IsObject(answer), "with a DecisionResponse")
		If $IsObject(answer) {
			Set totals = ##class(OcuTalon.Test.Agent.RunnerFixture).Totals(answer, 0)
			Do $$$AssertEquals(totals, "3800|300|2000|600|.000365|claude-haiku-5-5|1", "which carries the fixed tokens of the scenario's usage")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(decision, 0), totals, "and the Decision row holds the same totals")
			Do $$$AssertEquals(answer.CostUSD, decision.CostUSD, "so the cost is the Decision row's")
		}
	}
	Do $$$AssertEquals(decision.TraceSessionId, item.sessionId, "the Decision's trace session is the Item's own")
	Do $$$AssertEquals(item.superSession, case.trace, "whose SuperSession is the person's TraceRef")

	// the next Tick records the decision, and the ignore is the quiet reading
	If ..Tick(##class(OcuTalon.Data.Time).AddSeconds(case.t0, 60)) = "" Quit
	Set row = ..Beat(case.session)
	Do $$$AssertEquals(row.LastOutcome_"|"_row.LastDecisionRef, "ignore|"_decision.Ref, "the next Tick records the ignore on the row")
	Do $$$AssertTrue((row.LastSnapshotKey '= "") && (row.LastQuietKey = row.LastSnapshotKey), "and sets LastQuietKey to the beat's snapshot key")
	Do ..AssertNoCheck(case, 0)
}

Method TestTellNow()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set session = ..Session("tellnow")
	Set decisionRef = $ClassMethod(fixture, "Decision", session, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Summary": "Ana: Invoice run", "Outcome": "digest"})
	Set ..Refs = ..Refs_","_decisionRef
	Do $ClassMethod(fixture, "Usage", decisionRef, session, {"Channel": "mailbox"})
	Set case = ..Start("tellnow", "heartbeat-tellnow", session)
	If '$IsObject(case) Quit
	Set item = case.item
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback, "tellnow|0", "the Decision is the scenario's tell now")
	Do ..AssertRequest(case, 1)
	Set requests = ..MockRequests(case)
	Set json = $Select(requests.%Size() = 1: requests.%Get(0).%ToJSON(), 1: "")
	Set line = " | mailbox | digest | Ana: Invoice run"
	Do $$$AssertTrue($Find(json, line), "the mock's request lists the mail decision with the channel of its Usage row, read in the production's job")
	Set channel = ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(case.session, 1, ..#WAITDIAGNOSIS)
	Do ..Quiet(item)
	Set rows = ..WebNotices(case.session)
	Do $$$AssertEquals(rows.Count(), 1, "the session's web chat got one notice")
	If rows.Count() '= 1 Quit
	Set slots = {"whatHappened": (##class(OcuTalon.Checks.Beat).#SUBJECT), "reason": "The CI mock finds something in the snapshot that cannot wait."}.%ToJSON()
	Do $$$AssertEquals(rows.GetAt(1).Channel_"|"_rows.GetAt(1).Kind, channel_"|tellnow", "a tell-now notice on the web channel")
	Do $$$AssertEquals(rows.GetAt(1).Text, ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", slots, channel), "whose what-happened is the beat's subject and whose reason is the first reason")
	Do ..AssertNoCheck(case, 0)
}

Method TestDigest()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set case = ..Start("digest", "heartbeat-digest")
	If '$IsObject(case) Quit
	Set item = case.item
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback, "digest|0", "the Decision is the scenario's digest")
	Do ..AssertRequest(case, 1)
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionRef, DecisionRef, Channel, Summary FROM OcuTalon_Digest_Data.Item WHERE ItemId = ?", item.itemId)
		Set found = rs.%Next()
		If found || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertTrue(found, "DigestStore keeps one Digest.Data.Item for the Item")
	If found Do $$$AssertEquals(rs.%Get("SessionRef")_"|"_rs.%Get("DecisionRef")_"|"_rs.%Get("Channel")_"|"_rs.%Get("Summary"), case.session_"|"_decision.Ref_"|heartbeat|Heartbeat check-in", "of the person, with the decision, the channel heartbeat and the beat's subject")
	Do ..Quiet(item)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Item WHERE ItemId = ?", item.itemId)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 1, "and only one")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(case.session), 0, "no notice is made")
	Do $$$AssertEquals(..NoticesIn(item.sessionId), 0, "and no Notification is sent")
	Do ..AssertNoCheck(case, 0)
}

Method TestAct()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set session = ..Session("act")
	Set ref = ..Watch(session)
	Set marker = "heartbeat-act:"_session
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, 1), "the scenario is armed once, so that only the decision gets its first reply")
	Set ..Armed = ..Armed_$Select(..Armed = "": "", 1: ",")_marker
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set case = ..Start("act", "heartbeat-act", session)
	If '$IsObject(case) Quit
	Set item = case.item
	Do ..AssertItem(item)
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback, "act|0", "the Decision is the scenario's act")

	// the turn: a Decision of its own, from an untrusted request
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set turn = $ClassMethod(fixture, "DecisionOf", item.itemId, "turn")
		If $IsObject(turn) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue($IsObject(turn), "Intake's act runs a turn, which records a Decision of Kind turn for the Item")
	If '$IsObject(turn) Quit
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(item.sessionId), 1, "Intake", "Decide")
	Set kinds = ""
	For i = 0:1:requests.%Size() - 1 {
		Set request = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(requests.%Get(i).bodyId)
		If $IsObject(request) Set kinds = kinds_$ListBuild(request.Kind_":"_request.Provenance)
	}
	Do $$$AssertTrue($ListFind(kinds, "turn:untrusted"), "the turn's request is untrusted: "_$ListToString(kinds))
	Set steps = ..WaitSteps(turn.Ref, 2)
	Set denied = 0
	Set read = 0
	Set untrusted = $Parameter("OcuTalon.Bridge.Policy.Gate", "UNTRUSTED")
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		If $Find(step.summary, "stop_watch") {
			Set denied = denied + 1
			Do $$$AssertEquals(step.status, "denied", "the stop_watch step is denied")
			Do $$$AssertTrue(step.summary [ (". Denied: Tool access denied: "_$Extract(untrusted, 1, *-1)_". About "), "with UNTRUSTED: "_$Extract(step.summary, 1, 200))
		} ElseIf $Find(step.summary, "recent_activity") {
			Set read = read + 1
			Do $$$AssertEquals(step.status, "ok", "the read-only recent_activity step runs")
		}
	}
	Do $$$AssertEquals(denied_"|"_read, "1|1", "one denied step and one read-only step")
	Set approvals = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ?", session)
	Do approvals.%Next()
	Do $$$AssertEquals(approvals.%GetData(1), 0, "no approval request is raised for the person")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionSince(mark, "WatchOps")_"|"_##class(OcuTalon.Test.Agent.RunnerFixture).SessionSince(mark, "CommandsIn"), "|", "and nothing reaches WatchOps or CommandsIn")
	Set rows = ..Rows(session, 0)
	Do $$$AssertEquals(rows.%Size(), 1, "the person still has one watch")
	If rows.%Size() = 1 Do $$$AssertEquals(rows.%Get(0).ref, ref, "which is the one that the model asked to stop")
	Do ..AssertNoCheck(case, 1)
}

Method TestAllClearIsGuarded()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set case = ..Start("allclear", "heartbeat-all-clear")
	If '$IsObject(case) Quit
	Set item = case.item
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome_"|"_decision.Fallback, "tellnow|0", "the Decision is a tell now, not a fallback")
	Set reasons = $ZConvert(decision.Reasons, "L")
	Do $$$AssertEquals($Find(reasons, "everything is fine"), 0, "the reserved wording is gone from the Decision's reasons")
	Set second = "The CI mock names what it found: nothing past the checklist."
	Do $$$AssertEquals($Piece($Translate(decision.Reasons, $Char(13)), $Char(10), 1), second, "the second reason is the first one left")
	Set channel = ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(case.session, 1, ..#WAITDIAGNOSIS)
	Do ..Quiet(item)
	Set rows = ..WebNotices(case.session)
	Do $$$AssertEquals(rows.Count(), 1, "the session's web chat got one notice")
	If rows.Count() '= 1 Quit
	Do $$$AssertEquals($Find($ZConvert(rows.GetAt(1).Text, "L"), "everything is fine"), 0, "the reserved wording is gone from the notice")
	Set slots = {"whatHappened": (##class(OcuTalon.Checks.Beat).#SUBJECT), "reason": (second)}.%ToJSON()
	Do $$$AssertEquals(rows.GetAt(1).Text, ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", slots, channel), "whose reason is the second reason")
	Do ..AssertNoCheck(case, 0)
}

Method TestWatchRunsAgain()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set session = ..Session("watchruns")
	Set watch = ..Watch(session)
	Set case = ..Start("watchruns", "heartbeat-ignore", session)
	If '$IsObject(case) Quit
	Set item = case.item
	Set decision = ..WaitDecision(item.itemId, case.session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	If '$IsObject(decision) Quit
	Do $$$AssertEquals(decision.Outcome, "ignore", "the first beat is ignored")
	Set firstRun = ..Check(watch).LastRunAt
	Set firstResult = ..Check(watch).Result
	Do $$$AssertEquals(firstResult, "passed", "the Tick of the beat ran the watch first, and it passed")
	Do $$$AssertTrue($Find(item.text, "Watch: Orders | passed"), "so the beat's snapshot has the watch's line, without a time")
	Hang 1.1
	If ..Tick(##class(OcuTalon.Data.Time).AddSeconds(case.t0, 60)) = "" Quit
	Set secondRun = ..Check(watch).LastRunAt
	Do $$$AssertTrue(secondRun ] firstRun, "the watch ran again between the beats: "_firstRun_" then "_secondRun)
	Do $$$AssertEquals(..Check(watch).Result, firstResult, "with the same result")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	If ..Tick(##class(OcuTalon.Data.Time).AddSeconds(case.t0, 1800)) = "" Quit
	Set row = ..Beat(session)
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason, ##class(OcuTalon.Data.Time).AddSeconds(case.t0, 1800)_"|unchanged", "the beat due one interval later is skipped as unchanged")
	Do $$$AssertEquals(..Marked(mark, session), 0, "and makes no request")
	Do $$$AssertEquals(row.LastItemId, item.itemId, "no further Item was made")
}

/// A person with a beat due at a time no real Tick reaches, whose checklist holds the scenario's marker (named with the person's Ref): the Tick at that time is sent
/// and the one Item that Checks sent to Intake for the person is awaited. session is the person (made here when empty). It answers {session, trace, t0, text, mark,
/// floor, item, checks}, item being {itemId, sessionId, superSession, provenance, channel, subject, text}, or "" with a failed assertion.
Method Start(name As %String, scenario As %String, session As %String = "") As %DynamicObject [ Private ]
{
	If session = "" Set session = ..Session(name)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set t0 = ..Due()
	Set text = "zz "_name_" [[mock:"_scenario_":"_session_"]]"
	Do ..SeedBeat(session, t0, text, "")
	Set checks = ..Rows(session, 0).%ToJSON()
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	If ..Tick(t0) = "" Quit ""
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 1, "the Tick at T0 sends one Item from Checks to Intake for the person")
	If items.%Size() '= 1 Quit ""
	Set item = items.%Get(0)
	Do ..AssertItem(item)
	Do $$$AssertEquals($Piece(item.text, $Char(10, 10), 1), text, "whose text starts with the checklist")
	Set status = $Piece($Piece(item.text, $Char(10, 10), 2), $Char(10), 1)
	Do $$$AssertTrue(status ? 1"Status at "4N1"-"2N1"-"2N1" "2N1":"2N1" (built by OcuTalon):", "and has the status line next: "_status)
	Quit {"session": (session), "trace": (trace), "t0": (t0), "text": (text), "mark": (mark), "floor": (floor), "item": (item), "checks": (checks)}
}

/// A beat's Item is untrusted and on the heartbeat channel with the beat's subject (AC 10).
Method AssertItem(item As %DynamicObject) [ Private ]
{
	Do $$$AssertEquals(item.provenance_"|"_item.channel_"|"_item.subject, "untrusted|heartbeat|Heartbeat check-in", "the beat's Item is untrusted, on the heartbeat channel, with the beat's subject")
}

/// The entries of the mock's log, after the case's mark, that carry the person's marker.
Method MockRequests(case As %DynamicObject) As %DynamicArray [ Private ]
{
	Set found = []
	If $$$ISERR(##class(OcuTalon.Test.Contract.Mock).LogSince(case.mark, .entries)) Quit found
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.marker '= "") && $Find(entry.marker, case.session) Do found.%Push(entry)
	}
	Quit found
}

/// The mock logged count requests with the person's marker, and the first one carries the status line.
Method AssertRequest(case As %DynamicObject, count As %Integer) [ Private ]
{
	Set requests = ..MockRequests(case)
	Do $$$AssertEquals(requests.%Size(), count, "the CI mock's log holds "_count_" request with the marker")
	If requests.%Size() '= count Quit
	Set json = requests.%Get(0).%ToJSON()
	Do $$$AssertTrue($Find(json, "Status at ") && $Find(json, "(built by OcuTalon):"), "and it carries the status line")
}

/// Waits until the Item's decision has reached OutcomeRouter, then QUIETWAIT seconds, so that anything it would route has been routed.
Method Quiet(item As %DynamicObject) [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(item.sessionId), 1, "Intake", "OutcomeRouter")
		If sent.%Size() || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(sent.%Size(), 1, "Intake sent the ItemDecision to OutcomeRouter")
	Hang ..#QUIETWAIT
}

/// The Delivery rows of the person on the web channel, in order.
Method WebNotices(session As %String) As %ListOfObjects [ Private ]
{
	Set found = ##class(%ListOfObjects).%New()
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).Channel = ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL Do found.Insert(rows.GetAt(i))
	}
	Quit found
}

/// The number of Notification messages in the trace session.
ClassMethod NoticesIn(sessionId As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'OcuTalon.Msg.Notification'", sessionId)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The AgentStep rows of the decision once at least count are there, or after WAITDIAGNOSIS seconds.
Method WaitSteps(decisionRef As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(decisionRef)
		Set tools = 0
		Set iterator = steps.%GetIterator()
		While iterator.%GetNext(, .step) {
			If step.kind = "tool" Set tools = tools + 1
		}
		If (tools >= count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit steps
}

/// A beat is no background check (AD-28): the person's BackgroundCheck rows are as they were before the Tick (the fields that Checks does not own), and,
/// for a person with no watch, the beat made no check event.
Method AssertNoCheck(case As %DynamicObject, watched As %Boolean) [ Private ]
{
	Do $$$AssertEquals(..Rows(case.session, 0).%ToJSON(), case.checks, "the person's BackgroundCheck rows are unchanged by the beat")
	If 'watched Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(case.session, "check").%Size(), 0, "and the beat made no check event")
}

}
