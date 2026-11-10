/// The chat turn of the recent_activity tool (Story 5.13, the Integration AC; AD-7, AD-10, AD-28). THIS TEST RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with
/// demo mode on, through Test.Watch.Case, and fresh: the running ChatAgent keeps the toolset it started with. The message goes through WebChatIn to the real
/// Conversation, the real Decide and the real ChatAgent, against the CI mock (PointKeys). The scenario recent-activity, with its countdown armed at 1, answers the
/// triage request with tellnow, the Chat agent's first request with a call of recent_activity and its second with a reply that says that everything is fine.
///   - TestEarlierFailureInTheChat: session S has the records of the demo path (Test.Tools.RecentActivity.Demo, poisoned, last active two minutes ago so that the
///     quiet close leaves the incident alone) and asks "What was that failure earlier?". The Turn is done with no fallback and untainted; its one tool step is
///     "Reading recent activity", ok; the Chat agent's second request carries the tool result with the count 50, the element OrderDate, the approval answered on
///     web, 50 that went through, the state resolved and no ZZPOISON; and the reply holds no all-clear while the rest of it is kept.
///   - TestIncidentSummaryInTheChat (Story 23.6; AC 6): the scenario incident-summary, armed at 1: S's closed incident (its summary built by IncidentManager's close path) is asked
///     for with "Show me the incident summary"; the Turn is done and tainted, its one tool step is "Reading the incident summary", the second Chat request carries the rendered summary
///     as outcome summary, and the reply is the scenario's.
///   - TestIncidentSummaryAnotherSessionInTheChat (QA; AC 7): session A's closed incident has a summary (built by IncidentManager's close path); session B, who watches the same
///     production, asks "Show me the incident summary" through the same turn: the tool result of B's turn is {"outcome": "none"} and holds nothing of A's summary, while A's own turn
///     (control) gets it.
/// After the test the countdown is cleared, and the turns of the run's sessions are removed with their decisions.
Class OcuTalon.Test.Tools.RecentActivityTurn Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzrecturn";

/// The marker of the scenario, and the message that carries it.
Parameter MARKER = "recent-activity";

Parameter ASK = "What was that failure earlier? [[mock:recent-activity]]";

/// The first two sentences of the scenario's last reply; the third, "Everything is fine now.", is the all-clear, of which the guard removes the phrase and keeps " now.".
Parameter KEPT = "Earlier, 50 orders failed on the OrdersFromPartner item because of OrderDate. You approved the fix on the web, and all 50 went through.";

/// The marker of the incident-summary scenario (Story 23.6), the message that carries it, and the scenario's last reply, which no guard changes.
Parameter SUMMARYMARKER = "incident-summary";

Parameter SUMMARYASK = "Show me the incident summary [[mock:incident-summary]]";

Parameter SUMMARYREPLY = "The incident closed. Its summary lists 50 orders that failed on the OrdersFromPartner item because of OrderDate, and one fix that you approved on the web.";

/// The longest to wait for a turn through the mock, in seconds.
Parameter WAIT = 90;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, "")
	Do ##class(OcuTalon.Test.Contract.Mock).Arm(..#SUMMARYMARKER, "")
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

Method TestEarlierFailureInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("earlier")
	Do ..Watch(session)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Tools.RecentActivity).Demo(session, 1, 120, .incident, .request, .times)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, 1), "the countdown of "_..#MARKER_" is armed at 1")
	Set clientId = "zzr"_..Number_"earlier"
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertStatusOK(..Send(session, clientId, ..#ASK, .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey_"|"_row.Tainted, "done|||0", "the Turn is done, with no fallback, and untainted")
	#; The guard deletes only the phrase "Everything is fine" (no punctuation follows it directly) and folds the spaces, so the rest of the reply is kept as it is.
	Do $$$AssertEquals(row.ReplyText, ..#KEPT_" now.", "the reply keeps the sentences about the incident, and only the all-clear is removed")
	Do ..AssertNoAllClear(row.ReplyText)
	Do ..AssertToolStep(row)
	Do ..AssertToolResult(mark)
}

/// Story 23.6 (AC 6, the Integration AC): session S has a closed incident whose summary IncidentManager built when it closed (a Dismiss over the demo path's records,
/// whose free text is poisoned) and asks "Show me the incident summary". The Chat agent's first request carries the tool incident_summary and the scenario calls it:
/// the Turn is done with no fallback and TAINTED (the tool's output is not trusted: the summary holds the model-written cause); its one tool step is "Reading the
/// incident summary", ok; the second request carries the tool result, outcome summary, whose text is the rendered summary built by code from the catalog keys (the title
/// line, the poisoned cause as data, the messages line and the cost line); and the reply is the scenario's, stored on the Turn for the channel asked on and the web chat.
Method TestIncidentSummaryInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("summary")
	Do ..Watch(session)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Tools.RecentActivity).Demo(session, 1, 120, .incident, .request, .times)
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Watch.IncidentProbe", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the incident manager is made")
	If '$IsObject(host) Quit
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = "dismiss"
	Set command.IncidentRef = incident
	Set command.SessionRef = session
	Set command.Origin = "web_user"
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "the Dismiss is handled")
	Do $$$AssertEquals($IsObject(response) && (response.Ok_"|"_response.Outcome = "1|closed"), 1, "the incident is closed")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(..#SUMMARYMARKER, 1), "the countdown of "_..#SUMMARYMARKER_" is armed at 1")
	Set clientId = "zzr"_..Number_"summary"
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertStatusOK(..Send(session, clientId, ..#SUMMARYASK, .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey_"|"_row.Tainted, "done|||1", "the Turn is done, with no fallback, and tainted")
	Do $$$AssertEquals(row.ReplyText, ..#SUMMARYREPLY, "the reply is the scenario's, for the channel asked on and the web chat")
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(row.TurnDecisionRef)
	Set tools = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set tools = tools + 1
		Do $$$AssertEquals(step.label_"|"_step.status, "Reading the incident summary|ok", "the tool step is Reading the incident summary, ok")
		Do $$$AssertTrue(step.summary [ "incident_summary", "and its summary names incident_summary: "_$Extract(step.summary, 1, 120))
	}
	Do $$$AssertEquals(tools, 1, "the turn decision has exactly one tool step")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set chat = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.path = "/v1/messages") && ((","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_",") [ ",incident_summary,") Do chat.%Push(entry)
	}
	Do $$$AssertEquals(chat.%Size(), 2, "the Chat agent made two requests, and both offer incident_summary")
	If chat.%Size() '= 2 Quit
	Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(1))
	Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
	If $ListLength(results) '= 1 Quit
	Set answer = ""
	Try {
		Set answer = {}.%FromJSON($List(results, 1))
	} Catch exception {
		Set answer = ""
	}
	Do $$$AssertTrue($IsObject(answer), "the tool result is a JSON object: "_$Extract($List(results, 1), 1, 200))
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.outcome, "summary", "its outcome is summary")
	Do $$$AssertEquals(answer.text, ##class(OcuTalon.Watch.Summary).Text(incident, "web"), "its text is the summary that code built and the catalog renders")
	Do $$$AssertTrue($Piece(answer.text, $Char(10), 1) [ "Incident summary: 50 ", "which starts with the title line: "_$Piece(answer.text, $Char(10), 1))
	Do $$$AssertTrue(answer.text [ "ZZPOISON", "and holds the cause as data, which is why the turn is tainted")
	Do $$$AssertTrue(answer.text [ "Messages: 50 failed, 50 resent, 50 completed, 0 failed again, 0 skipped.", "with the messages line")
}

/// Story 23.6 (AC 7, QA): the second-session isolation through the real turn, not only through the tool method. Session A has a closed incident with its summary (a Dismiss over
/// the demo path's records, whose free text is poisoned). Session B, who watches the same production and has no incident, asks "Show me the incident summary": the Turn is
/// done, the tool result in the Chat agent's second request is {"outcome": "none"}, and neither it nor anything B's turn sent holds A's title line or the poisoned text. A's own
/// turn (the control) gets outcome summary, so that the silence of B's is not a broken path.
Method TestIncidentSummaryAnotherSessionInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Session("sumowner")
	Set b = ..Session("sumother")
	Do ..Watch(a)
	Do ..Watch(b)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Tools.RecentActivity).Demo(a, 1, 120, .incident, .request, .times)
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Watch.IncidentProbe", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the incident manager is made")
	If '$IsObject(host) Quit
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = "dismiss"
	Set command.IncidentRef = incident
	Set command.SessionRef = a
	Set command.Origin = "web_user"
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "A's Dismiss is handled")
	Do $$$AssertEquals($IsObject(response) && (response.Ok_"|"_response.Outcome = "1|closed"), 1, "A's incident is closed")
	Set title = $Piece(##class(OcuTalon.Watch.Summary).Text(incident, "web"), $Char(10), 1)
	Do $$$AssertTrue(title [ "Incident summary: 50 ", "and has a summary: "_title)
	For turn = "b", "a" {
		Set session = $Select(turn = "b": b, 1: a)
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(..#SUMMARYMARKER, 1), "the countdown of "_..#SUMMARYMARKER_" is armed at 1 for "_turn)
		Set clientId = "zzr"_..Number_"sumiso"_turn
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Do $$$AssertStatusOK(..Send(session, clientId, ..#SUMMARYASK, .output), turn_": the message is accepted by WebChatIn")
		Set row = ..WaitDone(session, clientId)
		If '$IsObject(row) || (row.State '= "done") {
			Do $$$AssertTrue(0, turn_": the Turn is done within "_..#WAIT_" seconds")
			Continue
		}
		Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), turn_": the mock's log is read")
		Set chat = []
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If (entry.path = "/v1/messages") && ((","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_",") [ ",incident_summary,") Do chat.%Push(entry)
		}
		Do $$$AssertEquals(chat.%Size(), 2, turn_": the Chat agent made two requests")
		If chat.%Size() '= 2 Continue
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, turn_": the second request carries one tool result")
		If $ListLength(results) '= 1 Continue
		Set raw = $List(results, 1)
		If turn = "b" {
			Do $$$AssertEquals({}.%FromJSON(raw).%ToJSON(), {"outcome": "none"}.%ToJSON(), "B's tool result is none: "_$Extract(raw, 1, 200))
			Do $$$AssertNotTrue((raw [ "Incident summary") || (raw [ "ZZPOISON") || (raw [ title), "and holds nothing of A's summary")
			Do $$$AssertNotTrue(chat.%Get(0).%ToJSON() [ "ZZPOISON", "nor does B's first request")
		} Else {
			Do $$$AssertEquals({}.%FromJSON(raw).outcome, "summary", "A's own turn gets its summary (the control)")
		}
	}
}

/// Asserts that the text holds no phrase of the guard's two lists, ignoring case.
Method AssertNoAllClear(text As %String) [ Private ]
{
	Set phrases = $ListFromString($Parameter("OcuTalon.Checks.ReplyGuard", "RESERVED")_","_$Parameter("OcuTalon.Checks.ReplyGuard", "BANNED"))
	Set position = 0
	While $ListNext(phrases, position, phrase) {
		Do $$$AssertNotTrue($ZConvert(text, "L") [ $ZConvert(phrase, "L"), "the reply does not say '"_phrase_"'")
	}
}

/// Asserts that the turn decision has exactly one tool step, "Reading recent activity", ok.
Method AssertToolStep(row As OcuTalon.Data.Turn) [ Private ]
{
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(row.TurnDecisionRef)
	Set tools = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set tools = tools + 1
		Do $$$AssertEquals(step.label_"|"_step.status, "Reading recent activity|ok", "the tool step is Reading recent activity, ok")
		Do $$$AssertTrue(step.summary [ "recent_activity", "and its summary names recent_activity: "_$Extract(step.summary, 1, 120))
	}
	Do $$$AssertEquals(tools, 1, "the turn decision has exactly one tool step")
}

/// Asserts that the Chat agent made two requests since the mark and that the second carries the tool result of the demo path's records.
Method AssertToolResult(mark As %Integer) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set chat = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.path = "/v1/messages") && ((","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_",") [ ",recent_activity,") Do chat.%Push(entry)
	}
	Do $$$AssertEquals(chat.%Size(), 2, "the Chat agent made two requests, and both offer recent_activity")
	If chat.%Size() '= 2 Quit
	Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(1))
	Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
	If $ListLength(results) '= 1 Quit
	Set text = $List(results, 1)
	Do $$$AssertTrue(text '[ "ZZPOISON", "the tool result holds no ZZPOISON")
	Set answer = ""
	Try {
		Set answer = {}.%FromJSON(text)
	} Catch exception {
		Set answer = ""
	}
	Do $$$AssertTrue($IsObject(answer), "the tool result is a JSON object: "_$Extract(text, 1, 200))
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.incidents.%Size(), 1, "with one incident")
	If answer.incidents.%Size() '= 1 Quit
	Set one = answer.incidents.%Get(0)
	Do $$$AssertEquals(one.count_"|"_one.element_"|"_one.state_"|"_one.item, "50|OrderDate|resolved|OrdersFromPartner", "the count, the element, the state and the item")
	Set approval = one.approvals.%Get(0)
	Do $$$AssertEquals(approval.answer_"|"_approval.channel_"|"_approval.fix.wentThrough_"|"_approval.fix.finished, "approved|web|50|1", "the approval answered on web, and the 50 that went through")
}

}
