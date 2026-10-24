/// Tests of the agent runner and its adapter, in this process (Story 1.2; AD-6, AD-7). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21), except TestRefusals, which needs nothing: the others send requests to the CI mock, so they need the CI override's
/// environment (OCUTALON_MODEL_BASE_URL is the mock's base URL and OCUTALON_MOCK_KEY_HEADER is 1) and the mock's request log. Where
/// they do not have them, the test fails with the reason and builds no provider, so that it can never send a request to a real model
/// API. The runner host is a shadow made with %New("ZzRunner"), so no production item is touched; the settings of its adapter are
/// set in memory, and its ProviderConfig names the mock and the non-secret CI variable OCUTALON_MOCK_KEY_HEADER as the key. The
/// requests run through the real AgentRunner.OnMessage.
///   - TestRefusals: each refused setting stops the adapter at start, naming it; a value of white space and a SessionConfigString of {}
///     do not; the agent class must be a compiled %AI.Agent class and an exact entry of the allow-list; a passing start builds nothing;
///   - TestBuildRetried: an unset key variable fails the build twice and keeps no agent, and then a variable that is set builds;
///   - TestChatErrorIsFailureReply (Story 1.6; DW-83): a provider failure inside Chat gives status OK and a failure Reply that holds the
///     provider's text as FailureText, no Text or finish reason, the steps and the usage of the call, one warning that names the runner
///     item, the DecisionRef and the text, and the context is over; the next request on the same runner is answered;
///   - TestContext: a probe agent's tool reads the context during Chat and writes the host data and the taint, which the Reply carries,
///     the context is over afterwards, and the built agent has no Temperature although the probe agent has one before the build;
///   - TestFinishReason: the Reply keeps finish_reason of the normal reply and of the refusal and max_tokens stop reasons;
///   - TestCacheOverThreshold: a probe agent whose system prompt is over min_tokens_for_cache, run through the same runner path, has
///     its system block marked for the cache in the mock's log, so the cache block of the composed config reaches the provider;
///   - TestOpenKeepsConfig: a session that a freshly built adapter opens still has the cap and the effort;
///   - TestUnbuiltKinds: kind tool, an unknown kind and an Input that is empty or white space only send nothing and build nothing; a
///     runner with no model sends nothing;
///   - TestUsageRows (Story 1.4; AD-6, AD-9, AD-20): the runner writes one Usage row for each Chat that returns, with the config name of
///     the runner item as its agent, and puts the same counts, the cost, the model, the steps and the wall time on the Reply; a call
///     that fails before any request writes none; a call that stalls in the tool loop after it spent tokens writes one; and a model with
///     no Price row gets a row with no cost and a warning that names the model, and a row that cannot be saved is a warning and keeps
///     no row, without changing the answer in either case;
///   - TestStatsReadFails (Story 1.4): the stats of an AI session that cannot be read give an empty reading and a warning, and raise
///     nothing.
///   - TestUsageRows also pins, since Story 1.5 (DW-77), that a call that stalls in the tool loop has a largest request: the largest
///     estimate of its model requests, because Chat returned no response to measure;
///   - TestSteps (Story 1.5; AD-6, AD-9): a test agent with two read-only tools through the shadow runner. The Reply holds five step
///     records (model, tool, model, tool, model) with the labels of the tool classes, summaries that hold the tools' names, inputs and
///     results, the status ok, and an estimate for each that grows with the earlier texts and tool results from the base that the runner
///     measured; the first model step lasts at least the mock's 1 s and the note step at least the tool's 0.25 s. The built agent's audit
///     policy is the step audit policy, the step count is 5, and the step buffer and the context are over;
///   - TestStepsRedacted (Story 1.5; AD-4, AD-9, AD-31): the tools of the scenario steps-secrets get a model key, an access token, a
///     password, a Telegram chat id and a display name in their arguments, return them in their results, and the card tool fails naming
///     the password and the key; a second, test-only audit policy shows that the tools got the intended values; none of the ten values is
///     in the Reply (Steps and XML), in the event log or in what Test.Agent.KeyScan.Find names, [redacted] stands in its place, and the
///     failed call is a step with the status error whose summary holds the error text, redacted.
/// Added by the QA stage of Story 1.5 (AD-9, AD-31):
///   - TestStepsRedactedText: the tools of the scenario steps-secrets-text answer TEXT, as the product's tools do (a %String that holds
///     JSON, which AI Hub gives the policy as a JSON string), with the five kinds of secret under their keys and four more in a line of
///     free text, and the card tool fails with a JSON body that holds all five; none of the 14 values is in the Reply (Steps and XML), the
///     event log or what the key scan names, and [redacted] stands in the place of each (counted in the two steps);
///   - TestStepBufferEndsOnEveryPath: the step buffer is over after a call that threw in the tool loop and after a provider failure, as
///     after a call that returned, and a call after them records only its own steps.
/// Added by Story 1.6 (AD-6, AD-9, DW-83):
///   - TestUsageRows and TestStepBufferEndsOnEveryPath now pin that a call whose Chat threw is a failure Reply with status OK, that
///     carries its usage (the Usage row's counts) and its steps, with the buffer and the context over;
///   - TestFailureKeepsContext: a call whose Chat throws after the probe tool tainted the turn and wrote the host data (the scenario
///     context-probe-fail) is a failure Reply that carries the taint and the host data, and the context is over;
///   - TestFailureTextRedacted: the provider's text with a fake Bearer token (the scenario provider-error-secret) shows [redacted] in
///     FailureText, and the token is in no FailureText, Steps, reply XML, event-log row or what the key scan names; a failure text over
///     2,000 characters is cut to Reply.#MAXFAILURE, with its line breaks as spaces; an error before Chat keeps its error status.
/// Added by Story 1.7 (AD-6, AD-7, AD-8, DW-56):
///   - TestSessionTimeout: the session config that the adapter composes carries timeout_ms, which Timeouts.Derive gives for the TimerSeconds
///     setting of Decide as it stands when the config is composed: 55000 with no row (the setting's initial value of 60), 15000 for a row of
///     20, and none for a row that Timeouts.Check refuses (111), the rest of the config unchanged;
///   - TestToolsRun: the Reply says whether a tool ran: 1 for a turn that called two tools and for a call that failed after a tool, 0 for
///     Triage's default script and for a call that failed at its first request; ToolsRan is 1 for an unreadable reading and for a tool
///     counter that went up or a tool step, and 0 otherwise.
/// Added by Story 1.8 (AD-6): a turn with provenance user is linked to a conversation, so the runner now saves an AI session and a link for
/// each such turn that completes untainted (Test.Bridge.Conversation pins that). These tests therefore give each user turn an owner of its own
/// (NewUsageRequest, TestContext, TestFailureKeepsContext), and OnAfterOneTest deletes the sessions saved since the test began and the links
/// that name them. TestStepsRedacted and TestStepsRedactedText drop the session of their turn before they scan: the saved conversation holds what
/// the model was shown, the tools' results with their fake secrets included, and it is not a store of steps, logs or errors.
/// Added by Story 1.13 (AD-6; DW-149):
///   - TestShadowRecordsNothing: the adapter of a shadow host, which is no item in its own job, records no key state in OnInit and forgets
///     none in OnTearDown, even a record that this job wrote.
/// Every AI session that a test saves is deleted again, and so is every Usage row that the shadow runner ZzRunner wrote, and every System
/// Default Settings row that a test put is put back.
Class OcuTalon.Test.Bridge.Runner Extends %UnitTest.TestCase
{

/// The class of the runner, whose host is made in memory.
Parameter RUNNER = "OcuTalon.Bridge.Operation.AgentRunner";

/// The System Default Settings rows before the test touched them (Test.Agent.RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", "ZzRunner")
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	Quit $$$OK
}

/// The agent of the default runner of the tests.
Parameter AGENT = "OcuTalon.Agent.Triage";

/// A key variable that nothing sets.
Parameter UNSETVARIABLE = "OCUTALON_ZZ_UNSET_KEY";

/// The finish_reason of a normal reply of the mock, as the provider reports it (measured in Story 1.2).
Parameter NORMALFINISH = "end_turn";

/// Each refused setting stops the adapter at start, and the error names it. A value of white space and, for SessionConfigString, {}
/// counts as unset. The agent class must be a compiled %AI.Agent class and an exact entry of the allow-list, and an empty list
/// refuses every class. After a start that passes, the adapter has built no agent.
Method TestRefusals()
{
	Set adapter = ..NewRunner(..#AGENT).Adapter
	Do $$$AssertStatusOK(adapter.OnInit(), "an adapter with an allowed agent class and no refused setting starts")
	Do $$$AssertTrue('$IsObject(adapter.Agent), "and has built no agent")
	Do $$$AssertEquals(adapter.SessionConfigString, "{}", "SessionConfigString is {} by default")

	Set names = $ListFromString(##class(OcuTalon.Bridge.Adapter.Agent).#REFUSED)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.Agent).#REFUSED, "AuthPolicy,AuditPolicy,DiscoveryPolicy,IrisTools,AdditionalTools,IrisSkills,AdditionalSkills,SystemPrompt,SessionConfigString", "exactly the nine settings of the start refusal are refused")
	Set position = 0
	While $ListNext(names, position, name) {
		Set adapter = ..NewRunner(..#AGENT).Adapter
		Set $Property(adapter, name) = $Select(name = "SessionConfigString": "{""max_tokens"":1}", 1: "x")
		Set sc = adapter.OnInit()
		Do $$$AssertStatusNotOK(sc, name_" set refuses the start")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("the setting "_name_" is set"), "and the error names it: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertTrue('$IsObject(adapter.Agent), "and nothing is built")

		Set adapter = ..NewRunner(..#AGENT).Adapter
		Set $Property(adapter, name) = $Char(32, 9, 13, 10, 32)
		Do $$$AssertStatusOK(adapter.OnInit(), name_" with white space only is unset")
	}
	For value = "{}", " { } ", $Char(9)_"{}"_$Char(10) {
		Set adapter = ..NewRunner(..#AGENT).Adapter
		Set adapter.SessionConfigString = value
		Do $$$AssertStatusOK(adapter.OnInit(), "SessionConfigString '"_$Translate(value, $Char(9, 10), "TL")_"' is unset")
	}
	Set adapter = ..NewRunner(..#AGENT).Adapter
	Set adapter.SessionConfigString = ""
	Do $$$AssertStatusOK(adapter.OnInit(), "an empty SessionConfigString is unset")
	Set adapter.SessionConfigString = "[]"
	Do $$$AssertStatusNotOK(adapter.OnInit(), "and [] is set")

	Set triage = "OcuTalon.Agent.Triage"
	Set cases = $ListBuild(
		$ListBuild("OcuTalon.Agent.Diagnosis,OcuTalon.Agent.Chat", triage, 0, "a class that is not on the list"),
		$ListBuild("", triage, 0, "an empty list"),
		$ListBuild($Char(32, 9), triage, 0, "a list of white space"),
		$ListBuild("OcuTalon.Agent.Triag,OcuTalon.Agent.Triage2", triage, 0, "classes that only share a prefix with the class"),
		$ListBuild("ocutalon.agent.triage", triage, 0, "the class in another case"),
		$ListBuild(triage, triage, 1, "a list of the class"),
		$ListBuild(" OcuTalon.Agent.Diagnosis , OcuTalon.Agent.Triage ,OcuTalon.Agent.Chat", triage, 1, "a list with spaces around its entries"),
		$ListBuild("Ens.StringRequest", "Ens.StringRequest", 0, "a class that is not an %AI.Agent, though it is on the list"),
		$ListBuild("OcuTalon.Test.Bridge.ZzNoSuchAgent", "OcuTalon.Test.Bridge.ZzNoSuchAgent", 0, "a class that does not exist"),
		$ListBuild("OcuTalon.Agent.Triage", "", 0, "an empty AgentClass"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set adapter = ..NewRunner(..#AGENT).Adapter
		Set adapter.AgentAllowList = $List(case, 1)
		Set adapter.AgentClass = $List(case, 2)
		Set sc = adapter.OnInit()
		If $List(case, 3) {
			Do $$$AssertStatusOK(sc, $List(case, 4)_" starts")
		} Else {
			Do $$$AssertStatusNotOK(sc, $List(case, 4)_" refuses the start")
			If $List(case, 2) '= "" Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("'"_$List(case, 2)_"'"), "and the error names the class: "_$SYSTEM.Status.GetErrorText(sc))
		}
		Do $$$AssertTrue('$IsObject(adapter.Agent), "and nothing is built")
	}
}

/// The adapter of a shadow host (a host made in memory, no item in its own job) records no key state in OnInit and forgets none in
/// OnTearDown: a record under its name is left as it is, and both calls are OK.
Method TestShadowRecordsNothing()
{
	Set host = ..NewRunner(..#AGENT)
	Set name = host.%ConfigName
	Kill ^OcuTalonBP.KeyState(name)
	Do $$$AssertTrue(host.%isShadow, "control: the host is a shadow")
	Do $$$AssertStatusOK(host.Adapter.OnInit(), "OnInit of the adapter of a shadow host starts")
	Do $$$AssertEquals($Data(^OcuTalonBP.KeyState(name)), 0, "and records no key state under "_name)
	Set ^OcuTalonBP.KeyState(name) = $ListBuild("present", $Job)
	Do $$$AssertStatusOK(host.Adapter.OnTearDown(), "OnTearDown of the adapter of a shadow host is OK")
	Do $$$AssertEquals($Data(^OcuTalonBP.KeyState(name)), 1, "and forgets nothing, not even a record that this job wrote")
	Kill ^OcuTalonBP.KeyState(name)
}

/// An unset key variable gives the same error twice and leaves no agent, so each request builds again; when the variable is set,
/// the next build works, and the runner answers a request.
Method TestBuildRetried()
{
	If ..Guard() Quit
	Set variable = ..#UNSETVARIABLE
	Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), "", variable_" is not set")
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("", "@{env:"_variable_"}"))
	Set adapter = host.Adapter
	For attempt = 1, 2 {
		Set sc = adapter.BuildAgent()
		Do $$$AssertStatusNotOK(sc, "build "_attempt_" fails with the key variable unset")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("@{env:"_variable_"}"), "and the error names the placeholder: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertTrue('$IsObject(adapter.Agent), "and no agent is kept")
	}
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("decide", "user", "Triage this item. [[mock:refusal]] (test "_ref_")")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "a request gets an error status, not an exception")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("@{env:"_variable_"}"), "that names the placeholder")
	Do $$$AssertTrue('$IsObject(response), "and no response")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is not set")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "and nothing reached the mock")

	Set adapter.ProviderConfig = ..ProviderConfig()
	Do $$$AssertStatusOK(adapter.BuildAgent(), "the build works once the key variable is set")
	Do $$$AssertTrue($IsObject(adapter.Agent), "and the agent is kept")
	Set agent = adapter.Agent
	Do $$$AssertStatusOK(adapter.BuildAgent(), "a build of a built agent")
	Do $$$AssertTrue(adapter.Agent = agent, "keeps the agent it has")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusOK(sc, "and a request is answered")
	Do $$$AssertEquals(response.FinishReason, "refusal", "with the refusal of the marker")
}

/// A provider failure (the mock's provider-error scenario answers 500) raises inside Chat and comes back as a failure Reply with status
/// OK (DW-83): FailureText holds AI Hub's text, the reply has no Text or finish reason, the steps of the call (none: the failure came at
/// the first request), no Usage row because no request was counted, one warning that names the runner item, the DecisionRef and the text,
/// and the context is over. The same runner then answers the next request.
Method TestChatErrorIsFailureReply()
{
	If ..Guard() Quit
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set request = ..NewUsageRequest("decide", "Fail this. [[mock:provider-error]]")
	Set ref = $Piece($Piece(request.Input, "(test ", 2), ")", 1)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set logMark = ..LogMark()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusOK(sc, "a provider failure gives status OK, not an error and not an exception")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the runner answers with a Reply")
		Quit
	}
	Do $$$AssertTrue(response.FailureText [ "ProviderError", "whose FailureText carries AI Hub's text: "_$Extract(response.FailureText, 1, 300))
	Do $$$AssertTrue(response.FailureText [ "CI mock: the provider failed.", "with the provider's message")
	Do $$$AssertEquals(response.Text_"|"_response.FinishReason, "|", "the Reply has no Text and no finish reason")
	Do $$$AssertEquals(response.Steps, "[]", "no step was taken before the failure, so its Steps is the empty array")
	Do $$$AssertEquals(response.HostData_"|"_response.Tainted, "|0", "the host data and the taint are those of the context")
	Do $$$AssertEquals(response.AgentStepCount, 0, "and no step was counted")
	Do $$$AssertTrue((response.DurationMs '= "") && (response.DurationMs '< 0), "but the wall time of the call: "_response.DurationMs)
	Do $$$AssertEquals(..UsageIds(request.ItemId).%Size(), 0, "no Usage row exists: no request was counted")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(logMark, "OcuTalon.Bridge.Adapter.Agent", "FailureText", $ListBuild("ZzRunner", request.DecisionRef, "CI mock: the provider failed.")), 1, "one warning names the runner item, the DecisionRef and the failure text")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).Active(), 0, "and so is the step buffer")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set requests = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, ref)
	Do $$$AssertTrue(requests.%Size() > 0, "the request reached the mock: "_requests.%Size())
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(.position, .logged) {
		Do $$$AssertEquals(logged.status, 500, "request "_(position + 1)_" was answered with the provider failure")
	}
	Do $$$AssertStatusOK(..Ask(host, "A new email arrived. Should the user hear about it now?", .normal), "the next request on the same runner is answered")
	Do $$$AssertEquals(normal.Text, ##class(OcuTalon.Test.Agent.RunnerFixture).#TRIAGETEXT, "with the text of Triage's script")
	Do $$$AssertEquals(normal.FailureText, "", "and no failure text")
}

/// The provider's text with a fake Bearer token (the scenario provider-error-secret) comes back redacted: [redacted] stands in the place of
/// the token, which is in no FailureText, Steps, reply XML, event-log row or store that the key scan names. A failure text is cut to
/// Reply.#MAXFAILURE after it is redacted, with its line breaks as spaces, and the cut never splits a secret out of its pattern. A failure
/// before Chat (an agent that cannot be built) keeps its error status and has no failure reply.
Method TestFailureTextRedacted()
{
	If ..Guard() Quit
	Set fake = "zzocutalonfakebearer0123456789"
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set request = ..NewUsageRequest("decide", "Fail this. [[mock:provider-error-secret]]")
	Set logMark = ..LogMark()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusOK(sc, "a provider failure whose text holds a Bearer token gives a failure Reply")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "the runner answers with a Reply")
		Quit
	}
	Do $$$AssertTrue(response.FailureText [ "CI mock: the provider failed.", "its FailureText holds the provider's message: "_response.FailureText)
	Do $$$AssertTrue(response.FailureText [ "[redacted]", "and [redacted] in the place of the token")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LeakPlaces(fake, [], response, logMark), "", "the token is in no FailureText, no Steps, no XML of the Reply, no event-log row since the test began and nothing that the key scan names")

	// the cut: redacted first, then cut at the limit, line breaks as spaces
	Set adapter = $ClassMethod("OcuTalon.Test.Bridge.ZzStatsRunner", "%New", "ZzRunner").Adapter
	Set limit = ##class(OcuTalon.Bridge.Msg.Reply).#MAXFAILURE
	Do $$$AssertEquals(limit, 2000, "the limit is 2,000 characters")
	Set long = ##class(%Exception.General).%New("ZzLong", 5001, , "line one"_$Char(10)_"line two "_$Justify("", 3000))
	Set text = adapter.FailureOf(long, request)
	Do $$$AssertEquals($Length(text), limit, "a failure text over the limit is cut to it: "_$Length(text))
	Do $$$AssertEquals($Extract(text, limit - 2, limit), "...", "and ends in an ellipsis")
	Do $$$AssertTrue(text '[ $Char(10), "with no line break")
	Do $$$AssertTrue(text [ "line one line two", "a line break is a space")
	// the raw text puts the token across the limit, and the redacted text fits within it
	Set frame = $Length(adapter.FailureOf(##class(%Exception.General).%New("ZzSecret", 5001, , "x"), request)) - 1
	Set padding = $Justify("", limit - 40 - frame)
	Set spill = ##class(%Exception.General).%New("ZzSecret", 5001, , padding_" Authorization: Bearer "_fake)
	Set text = adapter.FailureOf(spill, request)
	Do $$$AssertTrue((frame + $Length(padding) + $Length(" Authorization: Bearer "_fake)) > limit, "the raw text is over the limit, with the token across it")
	Do $$$AssertTrue(text '[ "zzocutalonfake", "a token that the limit would have cut in two is redacted first, so no piece of it is left: "_$Extract(text, limit - 100, $Length(text)))
	Do $$$AssertTrue(text [ "[redacted]", "and its place shows [redacted]")

	// an error before Chat keeps its status
	Set broken = ..NewRunner(..#AGENT, "low", ..ProviderConfig("", "@{env:"_..#UNSETVARIABLE_"}"))
	Set sc = broken.OnMessage(..NewUsageRequest("decide", "Triage this item."), .response)
	Do $$$AssertStatusNotOK(sc, "an agent that cannot be built keeps its error status")
	Do $$$AssertTrue('$IsObject(response), "and gives no Reply")
}

/// The probe agent's tool reads the context that the runner set before Chat, and writes the host data and the taint. It sees every
/// field of the request and the super session of the host, with the taint 0 and the host data empty. The Reply carries the host data
/// and the taint; the context is over after the call.
Method TestContext()
{
	If ..Guard() Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set superSession = "zzsuper"_ref
	Set host = ..NewRunner("OcuTalon.Test.Bridge.ProbeAgent")
	Set request = ..NewRequest("turn", "user", "Run the probe. [[mock:context-probe]] (test "_ref_")")
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "phone"
	Set request.ThreadSessionId = $Random(1000000000) + 1
	Set host.%SuperSession = superSession
	Try {
		Do $$$AssertEquals(host.%SuperSession, superSession, "the host has the super session")
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Set sc = host.OnMessage(request, .response)
		Do $$$AssertStatusOK(sc, "the probe request is answered")
		Do $$$AssertTrue($IsObject(host.Adapter.Agent), "the adapter built the probe agent")
		If $IsObject(host.Adapter.Agent) Do $$$AssertEquals(host.Adapter.Agent.Temperature, "", "and cleared the Temperature that the probe agent has before the build")
		Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
		If $IsObject(response) {
			Do $$$AssertEquals(response.Text, "The probe ran.", "whose text is the second reply of the scenario")
			Do $$$AssertEquals(response.Tainted, 1, "the Reply is tainted, because the tool tainted the turn")
			Set seen = {}.%FromJSON(response.HostData)
			Do $$$AssertTrue($IsObject(seen), "and its host data is what the tool wrote: "_response.HostData)
			If $IsObject(seen) {
				For field = "Kind", "Provenance", "ItemId", "DecisionRef", "OwnerRef", "TraceRef", "Channel", "ThreadSessionId" {
					Do $$$AssertTrue($Property(request, field) '= "", "the request has a "_field)
					Do $$$AssertEquals(seen.%Get(field), $Property(request, field), "the tool saw the "_field_" of the request")
				}
				Do $$$AssertEquals(seen.%Get("SuperSession"), superSession, "the tool saw the super session of the host")
				Do $$$AssertEquals(seen.%Get("Tainted"), 0, "the taint started at 0")
				Do $$$AssertEquals(seen.%Get("HostData"), "", "and the host data started empty")
			}
		}
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over after the call")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
		Set requests = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, ref)
		Do $$$AssertEquals(requests.%Size(), 2, "the mock logged the request and the one that follows the tool call")
		Set iterator = requests.%GetIterator()
		While iterator.%GetNext(.position, .logged) {
			Do $$$AssertEquals(logged.status, 200, "request "_(position + 1)_" is accepted")
			Do $$$AssertEquals(logged.scenario, "context-probe", "request "_(position + 1)_" ran the scenario of the marker")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Set host.%SuperSession = ""
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// A call whose Chat throws after the probe tool tainted the turn and wrote the host data (the scenario context-probe-fail: the probe
/// tool, then a provider failure) is answered with a failure Reply whose FailureText holds the provider's text and which still carries
/// the taint and the host data of the context; the context is over afterwards.
Method TestFailureKeepsContext()
{
	If ..Guard() Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set host = ..NewRunner("OcuTalon.Test.Bridge.ProbeAgent")
	Set request = ..NewRequest("turn", "user", "Run the probe. [[mock:context-probe-fail]] (test "_ref_")")
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusOK(sc, "a call that fails after the tool ran is answered with status OK")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the runner answers with a Reply")
		Quit
	}
	Do $$$AssertTrue(response.FailureText [ "CI mock: the provider failed after the probe.", "whose FailureText carries the provider's message: "_$Extract(response.FailureText, 1, 300))
	Do $$$AssertEquals(response.Text_"|"_response.FinishReason, "|", "with no Text and no finish reason")
	Do $$$AssertEquals(response.Tainted, 1, "the Reply is tainted, because the tool tainted the turn before the failure")
	Set seen = $Select(response.HostData '= "": {}.%FromJSON(response.HostData), 1: "")
	Do $$$AssertTrue($IsObject(seen), "and it carries the host data that the tool wrote: "_response.HostData)
	If $IsObject(seen) Do $$$AssertEquals(seen.%Get("Kind"), "turn", "which holds the kind of the request")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
}

/// The Reply keeps the provider's finish_reason: the normal reply of Triage's default script, the refusal and max_tokens.
Method TestFinishReason()
{
	If ..Guard() Quit
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Do $$$AssertStatusOK(..Ask(host, "A new email arrived. Should the user hear about it now?", .normal), "a normal request is answered")
	Do $$$AssertEquals(normal.Text, ##class(OcuTalon.Test.Agent.RunnerFixture).#TRIAGETEXT, "with the text of Triage's script")
	Do $$$AssertEquals(normal.FinishReason, ..#NORMALFINISH, "and the finish reason of a normal reply")
	Do $$$AssertStatusOK(..Ask(host, "Refuse this. [[mock:refusal]]", .refusal), "a refusal is answered")
	Do $$$AssertEquals(refusal.FinishReason, "refusal", "with finish_reason refusal")
	Do $$$AssertEquals(refusal.Text, "The CI mock refuses this request.", "and its text")
	Do $$$AssertStatusOK(..Ask(host, "Cut this off. [[mock:max-tokens]]", .cut), "a cut-off reply is answered")
	Do $$$AssertEquals(cut.FinishReason, "max_tokens", "with finish_reason max_tokens")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
}

/// The cache block reaches the provider. The probe agent's system prompt is about 3,300 characters (about 800 tokens), over the
/// min_tokens_for_cache of 512, and the agent has no tool: the logged request has the cache marker on its system block and offers
/// no tool. The composed config holds the exact cache block, and the request has the cap and the effort of every runner request.
/// (The system prompts of the product's agents are below the threshold, so the live runners show no system marker: AI Hub marks
/// a prefix only once it reaches the threshold.)
Method TestCacheOverThreshold()
{
	If ..Guard() Quit
	Set host = ..NewRunner("OcuTalon.Test.Bridge.ProbeLongAgent", "low", ..ProviderConfig("triage"))
	Set adapter = host.Adapter
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("decide", "user", "A new email arrived. Should the user hear about it now? (test "_ref_")")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusOK(sc, "the request to the probe agent with the long prompt is answered")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
	Do $$$AssertStatusOK(adapter.SessionConfigFor(.config), "the session config of the built agent is composed")
	If $IsObject(config) Do $$$AssertEquals($Select(config.%GetTypeOf("cache") = "object": config.cache.%ToJSON(), 1: config.%GetTypeOf("cache")), ##class(OcuTalon.Test.Bridge.SessionConfig).#CACHE, "and holds the exact cache block")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set logged = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequest(entries, ref)
	Do $$$AssertTrue($IsObject(logged), "the log holds the request")
	If '$IsObject(logged) Quit
	Do $$$AssertTrue(logged.request.system.chars > 3000, "its system prompt is long: "_logged.request.system.chars_" characters")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).CacheMark(logged.request.system), "{""type"":""ephemeral""}", "its system block is marked for the cache: the cache block reached the provider")
	Do $$$AssertEquals(logged.request.tools.%Size(), 0, "and it offers no tool, so the system block is the only block that can carry the marker")
	Do $$$AssertEquals(logged.model, "claude-haiku-5-5", "it names claude-haiku-5-5")
	Do $$$AssertEquals(logged.maxTokens, 8000, "it has a cap of 8000")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(logged), "low", "and the effort low")
	Do $$$AssertEquals(logged.status, 200, "and the mock accepts it")
	Do $$$AssertEquals(logged.%GetTypeOf("rejected"), "null", "and does not reject it")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
}

/// A session that is saved, and then opened by a freshly built adapter, is chatted in with the cap and the effort of the config that
/// the open method composed: the logged request has a maxTokens of 8000 and the effort low. The first adapter, its agent and its
/// session are gone before the open (SaveSession), because an open returns the session object that is still open in the process, and
/// AI Hub ignores the config of a session that is already attached to an agent.
Method TestOpenKeepsConfig()
{
	If ..Guard() Quit
	Set id = ""
	Try {
		Set id = ..SaveSession()
		Do $$$AssertTrue(id '= "", "a session is saved by a first adapter, which is then gone")
		Set second = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage")).Adapter
		Do $$$AssertStatusOK(second.BuildAgent(), "a freshly built adapter builds its own agent")
		Set saved = ##class(%AI.Agent.Session).%OpenId(id)
		Do $$$AssertTrue($IsObject(saved) && 'saved.IsAttached(), "the saved session is attached to no agent when it is opened, so the open attaches it with its config")
		Do $$$AssertStatusOK(second.OpenSession(id, .resumed), "and opens the saved session")
		Do $$$AssertTrue(resumed.IsAttached(), "which is attached to its agent")
		Set ref2 = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Set response = second.Agent.Chat(resumed, "And what about the next one? (test "_ref2_")")
		Do $$$AssertTrue(response.Content '= "", "one more chat is answered")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
		Set logged = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequest(entries, ref2)
		Do $$$AssertTrue($IsObject(logged), "the log holds the request of the resumed session")
		If $IsObject(logged) {
			Do $$$AssertEquals(logged.maxTokens, 8000, "it has a cap of 8000")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(logged), "low", "and the effort low")
			Do $$$AssertEquals(logged.status, 200, "and it is accepted")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	If id '= "" Do $$$AssertStatusOK(##class(%AI.Agent.Session).%DeleteId(id), "the saved session is deleted")
}

/// Kind tool is not implemented yet; a kind that is none of the request kinds and an empty Input are refused, naming the kind or the
/// Input. None of them builds the agent or sends anything. A runner whose model is empty fails before it sends.
Method TestUnbuiltKinds()
{
	If ..Guard() Quit
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set adapter = host.Adapter
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()

	Set request = ..NewRequest("tool", "user", "Replay the call. (test "_ref_")")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "kind tool is not implemented")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "#5003: Not implemented", "with the text of the stubs")
	Do $$$AssertTrue('$IsObject(response), "and no response")

	Set request = ..NewRequest("zzkind", "user", "Do something. (test "_ref_")")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "an unknown kind is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "'zzkind'", "naming the kind: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue('$IsObject(response), "with no response")

	Set request = ..NewRequest("", "user", "Do something. (test "_ref_")")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "an empty kind is refused")

	Set request = ..NewRequest("decide", "user", "")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "an empty Input is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "empty Input", "naming the Input: "_$SYSTEM.Status.GetErrorText(sc))

	Set request = ..NewRequest("decide", "user", $Char(32, 9, 13, 10, 32))
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "an Input of white space only is refused too")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "empty Input", "naming the Input")
	Do $$$AssertTrue('$IsObject(response), "with no response")
	Do $$$AssertTrue('$IsObject(adapter.Agent), "none of them built the agent")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and none set the context")

	Set request = ##class(Ens.StringRequest).%New("x")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "a message of another class is not implemented")
	Do $$$AssertTrue('$IsObject(response), "and gets no response")

	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")

	Do $$$AssertStatusOK(adapter.BuildAgent(), "the agent builds")
	Set adapter.Agent.Model = ""
	Set request = ..NewRequest("decide", "user", "Triage this item. (test "_ref_")")
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "a runner with no model fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "No model resolves", "saying that none resolves: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "with the context over")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read again")
	Do $$$AssertEquals(entries.%Size(), 0, "and still nothing reached the mock")
}

/// The Usage row of a call (Story 1.4). A decide request to Triage's default script: one row for its ItemId, written by the runner item
/// (here the shadow ZzRunner), with the model of the agent, one request, the tokens of the mock and the cost of the Price row; the Reply
/// has the same counts, the cost and the model, one step and the wall time of the call. A provider failure that comes before any
/// request is counted writes no row. A turn that stalls in the tool loop after it made requests writes one row with them, and a
/// model with no Price row gets a row with no cost and one warning that names the model.
Method TestUsageRows()
{
	If ..Guard() Quit
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set request = ..NewUsageRequest("decide", "Triage this item.")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the request is answered")
	Set ids = ..UsageIds(request.ItemId)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row exists for the item")
	If (ids.%Size() = 1) && $IsObject(reply) {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertEquals(usage.Agent_"|"_usage.Model_"|"_usage.Kind_"|"_usage.DecisionRef_"|"_usage.OwnerRef_"|"_usage.Channel, "ZzRunner|claude-haiku-5-5|decide|"_request.DecisionRef_"|"_request.OwnerRef_"|"_request.Channel, "its agent is the config name of the runner item, and it has the model and the request's fields")
		Do $$$AssertEquals(usage.RequestCount, 1, "one model request")
		Do $$$AssertTrue((usage.InputTokens > 0) && (usage.OutputTokens > 0), "with the tokens of the mock: "_usage.InputTokens_" in, "_usage.OutputTokens_" out")
		Do $$$AssertEquals(usage.InputTokens, usage.LargestRequestTokens, "the one request is the largest")
		Do $$$AssertEquals(usage.CacheReadTokens_"|"_usage.CacheWriteTokens, "0|0", "no cache tokens")
		Do $$$AssertEquals(usage.CostUSD, $Number((usage.InputTokens * 0.1 + (usage.OutputTokens * 0.5)) / 1000000, 6), "the cost is that of Claude Haiku 5.5 at 0.10 a million input tokens and 0.50 a million output tokens, below the long tier")
		Do $$$AssertTrue(usage.CostUSD > 0, "which is above 0: "_usage.CostUSD)
		Do $$$AssertEquals(reply.InputTokens_"|"_reply.OutputTokens_"|"_reply.CacheReadTokens_"|"_reply.CacheWriteTokens_"|"_reply.CostUSD_"|"_reply.Model, usage.InputTokens_"|"_usage.OutputTokens_"|"_usage.CacheReadTokens_"|"_usage.CacheWriteTokens_"|"_usage.CostUSD_"|"_usage.Model, "the Reply carries the counts, the cost and the model of the row")
		Do $$$AssertEquals(reply.AgentStepCount, 1, "and one step")
		Do $$$AssertTrue((reply.DurationMs '= "") && (reply.DurationMs '< 0), "and the wall time of the call: "_reply.DurationMs)
	}

	Set request = ..NewUsageRequest("decide", "Fail this. [[mock:provider-error]]")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a provider failure gives a failure Reply")
	Do $$$AssertTrue($IsObject(reply) && (reply.FailureText [ "ProviderError"), "that holds the failure text")
	Do $$$AssertEquals(..UsageIds(request.ItemId).%Size(), 0, "and, with no request counted, no Usage row")

	Set chat = ..NewRunner("OcuTalon.Agent.Chat", "", ..ProviderConfig("chat"))
	Set request = ..NewUsageRequest("turn", "Loop on the tool. [[mock:tool-loop]]")
	Set sc = chat.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a turn that stalls in the tool loop gives a failure Reply")
	Do $$$AssertTrue($IsObject(reply) && (reply.FailureText [ "LoopDetected"), "whose failure text is the loop's: "_$Select($IsObject(reply): $Extract(reply.FailureText, 1, 200), 1: "no Reply"))
	Set ids = ..UsageIds(request.ItemId)
	Do $$$AssertEquals(ids.%Size(), 1, "but its requests are counted in one Usage row")
	If ids.%Size() = 1 {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertTrue((usage.RequestCount > 0) && (usage.InputTokens > 0), "with the requests and tokens of the turn: "_usage.RequestCount_" requests, "_usage.InputTokens_" in")
		Do $$$AssertTrue(usage.LargestRequestTokens > 0, "and the largest estimate of its requests as its largest request, because Chat returned no response to measure: " _ usage.LargestRequestTokens)
		Do $$$AssertEquals(usage.Agent_"|"_usage.Kind, "ZzRunner|turn", "for the runner item and the kind")
		If $IsObject(reply) {
			Do $$$AssertEquals(reply.InputTokens_"|"_reply.OutputTokens_"|"_reply.CostUSD_"|"_reply.Model, usage.InputTokens_"|"_usage.OutputTokens_"|"_usage.CostUSD_"|"_usage.Model, "the failure Reply carries the counts, the cost and the model of the row")
			Do $$$AssertTrue(reply.AgentStepCount > 0, "and the step count of the call: "_reply.AgentStepCount)
		}
	}

	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Do $$$AssertStatusOK(host.Adapter.BuildAgent(), "the agent builds")
	Set host.Adapter.Agent.Model = "zz-unpriced"
	Set request = ..NewUsageRequest("decide", "Triage this item.")
	Set mark = ..LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a model with no Price row is answered")
	Set ids = ..UsageIds(request.ItemId)
	Do $$$AssertEquals(ids.%Size(), 1, "and its call is counted")
	If (ids.%Size() = 1) && $IsObject(reply) {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertEquals(usage.Model_"|"_usage.CostUSD, "zz-unpriced|", "with the model and no cost")
		Do $$$AssertTrue(usage.InputTokens > 0, "but with its tokens")
		Do $$$AssertEquals(reply.Model_"|"_reply.CostUSD, "zz-unpriced|", "the Reply has the model and no cost either")
	}
	Do $$$AssertEquals(..WarningsAbout(mark, "zz-unpriced"), 1, "one warning names the model that has no price")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")

	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"), "ZzRunner" _ $Translate($Justify("", 30), " ", "x"))
	Set request = ..NewUsageRequest("decide", "Triage this item.")
	Set mark = ..LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a call whose Usage row cannot be saved (a runner item name over the 32 characters of the Agent column, which the Reply does not carry) is answered all the same")
	Do $$$AssertTrue($IsObject(reply) && (reply.Text '= ""), "with its text")
	Do $$$AssertEquals(..UsageIds(request.ItemId).%Size(), 0, "no row is kept")
	Do $$$AssertEquals(..WarningsAbout(mark, "is not recorded"), 1, "and one warning says that the usage is not recorded")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
}

/// The characters of the arguments and of the results of the two tools of the scenario steps-two-tools, as the policy gets them (measured
/// in Story 1.5): {"topic":"status"} and {"note":"All systems normal.","topic":"status"}, then {"owner":"ops"} and
/// {"card":"On call: ops","owner":"ops"}.
Parameter NOTECHARS = 65;

Parameter CARDCHARS = 52;

/// A test agent with two read-only tools, through the shadow runner and the real AgentRunner.OnMessage. The scenario steps-two-tools
/// makes five steps: model, note, model, card, model. The Reply holds them as records: the labels, summaries, statuses and durations of
/// the steps, and an estimate for each model request that is the base measured before Chat (the agent's system prompt, its tool catalog
/// and the input) plus the model texts and tool arguments and results that the callbacks got before it, in tokens, rounded up.
Method TestSteps()
{
	If ..Guard() Quit
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set host = ..NewRunner("OcuTalon.Test.Bridge.StepsAgent")
	Set request = ..NewUsageRequest("turn", "[[mock:steps-two-tools]] Read the note and the card.")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the request is answered")
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Set agent = host.Adapter.Agent
	Set policy = agent.ToolManager.AuditPolicy
	Do $$$AssertTrue($IsObject(policy) && policy.%IsA("OcuTalon.Bridge.Policy.StepAudit"), "the audit policy of the built agent is the step audit policy")
	Do $$$AssertEquals(reply.Text, "The CI mock read the note and the card.", "the text is the last reply of the scenario")
	Do $$$AssertEquals(reply.AgentStepCount, 5, "the step count is 3 requests and 2 tool calls")
	Set steps = ..StepsOf(reply)
	Do $$$AssertEquals(steps.%Size(), 5, "the Reply holds five step records")
	If steps.%Size() '= 5 Quit
	Set kinds = ""
	For i = 0:1:4 {
		Set kinds = kinds _ $Select(i = 0: "", 1: ",") _ steps.%Get(i).kind
	}
	Do $$$AssertEquals(kinds, "model,tool,model,tool,model", "in the order of the calls: model, tool, model, tool, model")
	Set base = $Length(agent.SystemPrompt) + $Length(agent.ToolManager.%Discover().%ToJSON()) + $Length(request.Input)
	Do $$$AssertTrue(base > 0, "the base of the estimates is measured: " _ base)
	Set model1 = steps.%Get(0)
	Set note = steps.%Get(1)
	Set model2 = steps.%Get(2)
	Set card = steps.%Get(3)
	Set model3 = steps.%Get(4)
	Do $$$AssertEquals(model1.label_"|"_model2.label_"|"_model3.label, "Model request 1|Model request 2|Model request 3", "the model steps are numbered")
	Do $$$AssertEquals(model1.estimatedTokens, $ClassMethod(buffer, "Tokens", base), "the first request is the base")
	Do $$$AssertEquals(model2.estimatedTokens, $ClassMethod(buffer, "Tokens", base + ..#NOTECHARS), "the second adds the note's arguments and result")
	Do $$$AssertEquals(model3.estimatedTokens, $ClassMethod(buffer, "Tokens", base + ..#NOTECHARS + ..#CARDCHARS), "the third adds the card's too")
	Do $$$AssertTrue((model1.estimatedTokens < model2.estimatedTokens) && (model2.estimatedTokens < model3.estimatedTokens), "so the estimates grow: " _ model1.estimatedTokens _ ", " _ model2.estimatedTokens _ ", " _ model3.estimatedTokens)
	Do $$$AssertEquals(model1.summary, "About " _ model1.estimatedTokens _ " tokens sent (an estimate). Reply: 0 characters of text, 1 tool calls.", "the summary of the first model step")
	Do $$$AssertEquals(model3.summary, "About " _ model3.estimatedTokens _ " tokens sent (an estimate). Reply: 39 characters of text, 0 tool calls.", "and of the last, whose reply is 39 characters of text")
	Do $$$AssertTrue(model1.durationMs '< 1000, "the first model step lasts at least the 1 s that the mock waits: " _ model1.durationMs)
	Do $$$AssertEquals(note.label, "Reading the test note", "the note step has the label of its class")
	Do $$$AssertEquals(card.label, "Reading the test card", "and the card step the label of its tool's name")
	Do $$$AssertEquals(note.status_"|"_card.status_"|"_model1.status, "ok|ok|ok", "all the steps are ok")
	Do $$$AssertTrue(note.durationMs '< 200, "the note step lasts at least 200 ms, as the tool hangs 0.25 s: " _ note.durationMs)
	Do $$$AssertEquals(note.summary, "zz_steps_note. Inputs: {""topic"":""status""}. Result: {""note"":""All systems normal."",""topic"":""status""}. About " _ note.estimatedTokens _ " tokens added to the next request (an estimate).", "the note step: the tool's name, its inputs and its result")
	Do $$$AssertEquals(card.summary, "zz_steps_card. Inputs: {""owner"":""ops""}. Result: {""card"":""On call: ops"",""owner"":""ops""}. About " _ card.estimatedTokens _ " tokens added to the next request (an estimate).", "and the card step")
	Do $$$AssertEquals(note.estimatedTokens_"|"_card.estimatedTokens, $ClassMethod(buffer, "Tokens", ..#NOTECHARS)_"|"_$ClassMethod(buffer, "Tokens", ..#CARDCHARS), "a tool step estimates what it adds to the next request")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over")
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "and so is the step buffer")
	Set ids = ..UsageIds(request.ItemId)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row exists")
	If ids.%Size() = 1 {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertTrue(usage.LargestRequestTokens '< model1.estimatedTokens, "its largest request is at least the first estimate: " _ usage.LargestRequestTokens)
	}
}

/// The tools get secrets and fail naming two of them; none of the ten values reaches a step, the Reply, the event log or the scan of the
/// stores, and [redacted] stands in its place. A test-only audit policy, chained after the step audit policy, records the arguments the
/// tools were called with: they are the intended values, so the JSON escapes of the scenario file arrive as written.
Method TestStepsRedacted()
{
	If ..Guard() Quit
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	Set host = ..NewRunner("OcuTalon.Test.Bridge.StepsAgent")
	Do $$$AssertStatusOK(host.Adapter.BuildAgent(), "the agent builds")
	Do $$$AssertStatusOK(host.Adapter.Agent.ToolManager.SetAuditPolicy(##class(OcuTalon.Test.Bridge.StepsSeen).%New()), "a second audit policy is chained after the step audit policy")
	Kill ^||ZzStepsSeen
	Set request = ..NewUsageRequest("turn", "[[mock:steps-secrets]] Read the secret note.")
	Set mark = ..LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do $$$AssertStatusOK(sc, "the request is answered, though a tool failed")
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Set kinds = $ListBuild("apiKey", "accessToken", "password", "chatId", "displayName")
	Set seen = ..SeenArguments(1)
	Do $$$AssertEquals($Get(^||ZzStepsSeen), 2, "both tools were called")
	Do $$$AssertEquals(seen.%Get("topic"), "keys", "the note tool was called for the topic keys")
	Set card = ..SeenArguments(2)
	Do $$$AssertEquals(card.%Get("owner"), "locked", "and the card tool for the owner locked")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set intended = $ClassMethod(note, "Secret", kind, "arg")
		Do $$$AssertEquals(seen.%Get(kind), intended, "the note tool got the intended " _ kind _ ": the escapes of the scenario file arrive as written")
		Do $$$AssertEquals(card.%Get(kind), intended, "and so did the card tool")
	}
	Set steps = ..StepsOf(reply)
	Do $$$AssertEquals(steps.%Size(), 5, "the Reply holds five step records")
	If steps.%Size() '= 5 Quit
	Set noteStep = steps.%Get(1)
	Set cardStep = steps.%Get(3)
	Do $$$AssertEquals(noteStep.status_"|"_cardStep.status, "ok|error", "the note step is ok and the failed card step is an error")
	Do $$$AssertTrue(cardStep.summary [ "is locked", "the failed step's summary holds the error text: " _ cardStep.summary)
	Do $$$AssertTrue(cardStep.summary [ "password=[redacted]", "with the password replaced")
	Do $$$AssertTrue(cardStep.summary [ "apiKey=[redacted]", "and the key replaced")
	Do $$$AssertNotTrue(cardStep.summary [ "ERROR <", "AI Hub's leading ERROR <%AICore>ToolExecutionFailed: is not in the error text")
	Do $$$AssertNotTrue(cardStep.summary [ $Char(8212), "nor its long dash, which is a hyphen")
	Do $$$AssertNotTrue(cardStep.summary [ "  ", "nor a run of spaces where its control characters were")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Do $$$AssertTrue(noteStep.summary [ ("""" _ kind _ """:""[redacted]"""), "the note step shows [redacted] for " _ kind _ " in its inputs and its result")
		Do $$$AssertTrue(cardStep.summary [ ("""" _ kind _ """:""[redacted]"""), "and so does the card step")
	}
	For kind = "apiKey", "accessToken", "password", "chatId", "displayName" {
		For where = "arg", "result" {
			Set value = $ClassMethod(note, "Secret", kind, where)
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LeakPlaces(value, steps, reply, mark), "", "the " _ kind _ " " _ where _ " is in no step record, not in the Reply (its Steps and its XML), in no event-log row since the test began and in nothing that the key scan names")
		}
	}
	Kill ^||ZzStepsSeen
}

/// The tools answer text and fail with a JSON body (the scenario steps-secrets-text). The form matters: the product's tools return a
/// %String, and AI Hub gives the result of such a tool to the audit policy as a JSON string, so the redactor has to look inside the string.
/// Controls first: the fixtures do hold the 14 values that the test looks for. Then none of them reaches the Reply, the event log or the
/// scan of the stores, and each shows as [redacted] in the steps: nine in the text step (five keys and four in a line of free text) and five
/// in the error of the card step.
Method TestStepsRedactedText()
{
	If ..Guard() Quit
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	Set values = $ClassMethod(note, "TextValues")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).TextControlsMissing(), "", "control: the fixtures hold the 14 fake secrets that the test looks for, and the report is text that holds JSON")

	Set host = ..NewRunner("OcuTalon.Test.Bridge.StepsAgent")
	Set request = ..NewUsageRequest("turn", "[[mock:steps-secrets-text]] Read the secret report.")
	Set mark = ..LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do $$$AssertStatusOK(sc, "the request is answered, though a tool failed")
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, "The CI mock read the secret report.", "the text is the last reply of the scenario")
	Set steps = ..StepsOf(reply)
	Do $$$AssertEquals(steps.%Size(), 5, "the Reply holds five step records")
	If steps.%Size() '= 5 Quit
	Set textStep = steps.%Get(1)
	Set cardStep = steps.%Get(3)
	Do $$$AssertEquals(textStep.label_"|"_textStep.status, "Reading the test report|ok", "the text step has the label of its class and is ok")
	Do $$$AssertEquals(cardStep.label_"|"_cardStep.status, "Reading the test card|error", "the card step is an error")
	Do $$$AssertTrue(cardStep.summary [ "was refused", "its summary holds the error text: " _ cardStep.summary)
	Do $$$AssertEquals($Length(textStep.summary, "[redacted]") - 1, 9, "the text step shows [redacted] nine times: the five keys of the report and the four secrets of its line: " _ textStep.summary)
	Do $$$AssertEquals($Length(cardStep.summary, "[redacted]") - 1, 5, "and the card step five times, one for each secret in the JSON body of its error: " _ cardStep.summary)
	Set position = 0
	While $ListNext(values, position, value) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LeakPlaces(value, steps, reply, mark), "", "'" _ $Extract(value, 1, 22) _ "...' is in no step record, not in the Reply (its Steps and its XML), in no event-log row since the test began and in nothing that the key scan names")
	}
}

/// The step buffer is over after every call, also after one that threw: a turn that stalls in the tool loop (the call threw after its
/// requests were counted) and a provider failure end with a failure Reply that carries the steps taken so far and no buffer, and a call
/// after them records only its own steps.
Method TestStepBufferEndsOnEveryPath()
{
	If ..Guard() Quit
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set chat = ..NewRunner("OcuTalon.Agent.Chat", "", ..ProviderConfig("chat"))
	Set request = ..NewUsageRequest("turn", "Loop on the tool. [[mock:tool-loop]]")
	Set sc = chat.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a turn that stalls in the tool loop gives a failure Reply")
	If $IsObject(reply) {
		Set steps = ..StepsOf(reply)
		Do $$$AssertTrue(steps.%Size() > 0, "that carries the steps taken before the failure: "_steps.%Size())
		If steps.%Size() > 0 Do $$$AssertEquals(steps.%Get(0).label, "Model request 1", "the first of them is the first model request")
	} Else {
		Do $$$AssertTrue(0, "the answer is a Reply")
	}
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "the step buffer is over")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and so is the context")

	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set request = ..NewUsageRequest("decide", "Fail this. [[mock:provider-error]]")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a provider failure gives a failure Reply")
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "and the step buffer is over")

	Set request = ..NewUsageRequest("decide", "Triage this item.")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the next request is answered")
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Set steps = ..StepsOf(reply)
	Do $$$AssertEquals(steps.%Size(), 1, "and its Reply holds one step, its own")
	If steps.%Size() = 1 Do $$$AssertEquals(steps.%Get(0).label, "Model request 1", "the first model request of the call")
	Do $$$AssertEquals($ClassMethod(buffer, "Active"), 0, "the step buffer is over after it too")
}

/// The stats of an AI session that cannot be read (the object has no GetStats) give "" and one warning that names GetStats, and raise
/// nothing: the adapter then counts that call as far as the other reading allows, and never changes the answer or its status.
Method TestStatsReadFails()
{
	Set host = $ClassMethod("OcuTalon.Test.Bridge.ZzStatsRunner", "%New", "ZzRunner")
	Set mark = ..LogMark()
	Set stats = ""
	Try {
		Set stats = host.Adapter.StatsOf({})
		Set raised = ""
	} Catch exception {
		Set raised = exception.DisplayString()
	}
	Do $$$AssertEquals(raised, "", "a session whose stats cannot be read raises nothing")
	Do $$$AssertEquals(stats, "", "and gives no reading")
	Do $$$AssertEquals(..WarningsAbout(mark, "GetStats", "ReadStats", "OcuTalon.Test.Bridge.ZzStatsAdapter"), 1, "one warning says that GetStats of the AI session failed")
}

/// The session config carries timeout_ms (AD-7, AD-8): Timeouts.Derive of the TimerSeconds setting of the Decide item of the active production,
/// read each time the config is composed. With no row the setting has its initial value, 60, and the config 55000; a row of 20 gives 15000
/// (the next config, with no restart of the test's adapter: the runners are restarted by Timeouts.Apply for their Config Store entries); a
/// row of 111, which Timeouts.Check refuses, composes no timeout_ms, and the rest of the config is the same in each case.
Method TestSessionTimeout()
{
	If ..Guard() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set adapter = host.Adapter
	Do $$$AssertStatusOK(adapter.BuildAgent(), "the agent is built")
	Set saved = ..SavedRows
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "TimerSeconds")
	Set ..SavedRows = saved
	Do $ClassMethod(fixture, "RestoreDefault", $ListBuild("Decide", "TimerSeconds", 0))
	Set base = "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""cache"":"_##class(OcuTalon.Test.Bridge.SessionConfig).#CACHE
	Do $$$AssertStatusOK(adapter.SessionConfigFor(.config), "with no TimerSeconds row a config is composed")
	If $IsObject(config) Do $$$AssertEquals(config.%ToJSON(), base_",""timeout_ms"":55000}", "with timeout_ms 55000: the timer's initial value of 60 less 5 s")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", 20), "a TimerSeconds row of 20 is written")
	Do $$$AssertStatusOK(adapter.SessionConfigFor(.config), "the next config is composed")
	If $IsObject(config) Do $$$AssertEquals(config.%ToJSON(), base_",""timeout_ms"":15000}", "with timeout_ms 15000")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", 111), "a TimerSeconds row of 111 is written")
	Do $$$AssertStatusOK(adapter.SessionConfigFor(.config), "a config is composed")
	If $IsObject(config) Do $$$AssertEquals(config.%ToJSON(), base_"}", "and has no timeout_ms: a timer that Check refuses gives none, and the rest is unchanged")
	Do $$$AssertEquals(adapter.TimeoutMs(), "", "TimeoutMs gives none for it")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", 12), "a TimerSeconds row of 12 is written")
	Do $$$AssertEquals(adapter.TimeoutMs(), 7000, "TimeoutMs gives 7000 for the shortest timer")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", 110), "a TimerSeconds row of 110 is written")
	Do $$$AssertEquals(adapter.TimeoutMs(), 105000, "and 105000 for the longest")
}

/// The Reply says whether a tool ran (DW-56): ToolsRun is 1 for a turn that called two tools, and for a call that failed with a rate limit after
/// a tool ran (a failure Reply carries it too, with the usage and the steps of the call), and 0 for Triage's default script and for a call
/// that failed at its first request. ToolsRan is pure: an unreadable reading is a tool that may have run, so is a tool counter that went up
/// and a tool step; a model step and a counter that did not move are not.
Method TestToolsRun()
{
	If ..Guard() Quit
	Set agent = "OcuTalon.Bridge.Adapter.Agent"
	Set host = ..NewRunner("OcuTalon.Test.Bridge.StepsAgent")
	Set request = ..NewUsageRequest("turn", "[[mock:steps-two-tools]] Read the note and the card.")
	Do $$$AssertStatusOK(host.OnMessage(request, .tools), "a turn that calls two tools is answered")
	If $IsObject(tools) Do $$$AssertEquals(tools.ToolsRun_"|"_tools.AgentStepCount, "1|5", "its Reply says that tools ran")
	Set request = ..NewUsageRequest("turn", "[[mock:rate-limited-after-tool]] Read the note.")
	Do $$$AssertStatusOK(host.OnMessage(request, .failed), "a turn that fails with a rate limit after a tool is answered with status OK")
	If $IsObject(failed) {
		Do $$$AssertTrue(failed.FailureText [ "Rate limit exceeded", "its failure Reply holds the provider's text: "_$Extract(failed.FailureText, 1, 200))
		Do $$$AssertEquals(failed.ToolsRun_"|"_failed.AgentStepCount, "1|2", "and says that a tool ran, with the two steps of the call")
		Set kinds = ""
		Set iterator = ..StepsOf(failed).%GetIterator()
		While iterator.%GetNext(, .step) {
			Set kinds = kinds _ $Select(kinds = "": "", 1: ",") _ step.kind
		}
		Do $$$AssertEquals(kinds, "model,tool", "the steps are a model step and the tool step")
	}
	Set triage = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Do $$$AssertStatusOK(..Ask(triage, "A new email arrived. Should the user hear about it now?", .normal), "Triage's default script is answered")
	If $IsObject(normal) Do $$$AssertEquals(normal.ToolsRun_"|"_normal.AgentStepCount, "0|1", "its Reply says that no tool ran")
	Set request = ..NewUsageRequest("decide", "Fail this. [[mock:provider-error]]")
	Do $$$AssertStatusOK(triage.OnMessage(request, .failure), "a call that fails at its first request is answered with status OK")
	If $IsObject(failure) Do $$$AssertEquals(failure.ToolsRun_"|"_failure.AgentStepCount_"|"_(failure.FailureText '= ""), "0|0|1", "its failure Reply says that no tool ran")

	// ToolsRan
	Set none = {"total_interactions": 3, "total_tool_calls": 0}
	Set same = {"total_interactions": 4, "total_tool_calls": 0}
	Set up = {"total_interactions": 4, "total_tool_calls": 1}
	Set model = [{"kind": "model", "label": "Model request 1"}]
	Set tool = [{"kind": "model"}, {"kind": "tool", "label": "Reading the test note"}]
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", "", "", []), 1, "readings that cannot be read: a tool may have run")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, "", model), 1, "no reading after the call: a tool may have run")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", "", same, model), 1, "no reading before the call: a tool may have run")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, same, model), 0, "a counter that did not move and a model step: no tool ran")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, same, []), 0, "and no step at all")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, same, tool), 1, "a tool step: a tool ran, whatever the counter says")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, up, []), 1, "a counter that went up: a tool ran, whatever the steps say")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, up, model), 1, "also with a model step")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", up, none, model), 0, "a counter that went down is not a tool call")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, same, ""), 0, "records that cannot be read count for nothing when the counters are readable")
	Do $$$AssertEquals($ClassMethod(agent, "ToolsRan", none, same, [5, "tool", null]), 0, "and so do records that are no objects")
}

/// --- helpers ---
/// The step records of the Reply, as a dynamic array.
ClassMethod StepsOf(reply As OcuTalon.Bridge.Msg.Reply) As %DynamicArray [ Private ]
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(reply.Steps)
}

/// The arguments that the n-th tool call of the test got, from the test-only audit policy: the JSON of the call as an object.
ClassMethod SeenArguments(n As %Integer) As %DynamicObject [ Private ]
{
	Quit ##class(%DynamicAbstractObject).%FromJSON($List($Get(^||ZzStepsSeen(n), $ListBuild("", "{}")), 2))
}

/// A Request with the fields of a Decide request that the Usage row copies: an ItemId and a DecisionRef of its own, the owner instance
/// (a new Ref for a turn, which is linked to a conversation of its own, so that no two turns share a history) and the channel system.
Method NewUsageRequest(kind As %String, input As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ..NewRequest(kind, "user", input_" (test "_##class(OcuTalon.Bridge.Ids).NewRef()_")")
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = $Select(kind = "turn": ##class(OcuTalon.Bridge.Ids).NewRef(), 1: "instance")
	Set request.Channel = "system"
	Quit request
}

/// The number of warnings (type 3) of the adapter's method (RecordUsage unless another is named) after the log mark whose text holds
/// the needle. The log names the class of the object that logged, which is the adapter unless another class is named.
ClassMethod WarningsAbout(mark As %Integer, needle As %String, method As %String = "RecordUsage", class As %String = "OcuTalon.Bridge.Adapter.Agent") As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, class, method, $ListBuild(needle))
}

/// The ids of the Usage rows of the item, as a dynamic array (Test.Agent.RunnerFixture.UsageIds).
ClassMethod UsageIds(itemId As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("ItemId", itemId)
}

/// The highest id of the event log (Test.Agent.RunnerFixture.EventMark).
ClassMethod LogMark() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
}

/// Creates a session through a first adapter, chats once, saves it and returns its id. The adapter, its agent and the session are
/// local, so none of them is open in the process when the method returns.
Method SaveSession() As %String [ Private ]
{
	Set id = ""
	Set first = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage")).Adapter
	Do $$$AssertStatusOK(first.BuildAgent(), "the first adapter builds its agent")
	Do $$$AssertStatusOK(first.NewSession(.session), "and creates a session")
	Set ref1 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response = first.Agent.Chat(session, "A new email arrived. Should the user hear about it now? (test "_ref1_")")
	Do $$$AssertTrue(response.Content '= "", "the first chat is answered")
	Do $$$AssertStatusOK(session.%Save(), "the session is saved")
	Set id = session.%Id()
	Quit id
}

/// A runner host made in memory, a shadow named configName (ZzRunner unless another is given), whose adapter has the agent class, an
/// allow-list of that class, the effort and the provider configuration. The key is the non-secret CI variable. Test.Bridge.Conversation
/// makes its runners with it too, with the runner class it names (an AgentRunner class, RUNNER by default).
ClassMethod NewRunner(agentClass As %String, effort As %String = "", providerConfig As %String = "", configName As %String = "ZzRunner", runnerClass As %String = "") As OcuTalon.Bridge.Operation.AgentRunner
{
	Set host = $ClassMethod($Select(runnerClass '= "": runnerClass, 1: ..#RUNNER), "%New", configName)
	Set adapter = host.Adapter
	Set adapter.AgentClass = agentClass
	Set adapter.AgentAllowList = agentClass
	Set adapter.Effort = effort
	Set adapter.ProviderConfig = $Select(providerConfig '= "": providerConfig, 1: ..ProviderConfig())
	Quit host
}

/// The ProviderConfig JSON of a runner for the mock: the Anthropic provider, the key placeholder (the non-secret CI variable by
/// default), the mock's base URL and, when a mock key is given, the header that picks an agent's default script
/// (Test.Contract.Mock.CustomHeaders, with the mock-key switch of this process).
ClassMethod ProviderConfig(mockKey As %String = "", key As %String = "") As %String
{
	If key = "" Set key = "@{env:"_##class(OcuTalon.Test.Agent.RunnerFixture).#MOCKKEYVARIABLE_"}"
	Set config = {"model_provider": "anthropic", "api_key": (key), "base_url": (##class(OcuTalon.Test.Contract.Mock).#BASEURL)}
	If mockKey '= "" Set config."http_config" = {"custom_headers": (##class(OcuTalon.Test.Contract.Mock).CustomHeaders(mockKey, $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")))}
	Quit config.%ToJSON()
}

/// A request of the kind with the provenance and the input.
ClassMethod NewRequest(kind As %String, provenance As %String, input As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.Input = input
	Quit request
}

/// Sends a decide Request with the text through the host's OnMessage and returns the status; reply is the Reply.
Method Ask(host As OcuTalon.Bridge.Operation.AgentRunner, text As %String, Output reply As OcuTalon.Bridge.Msg.Reply) As %Status [ Private ]
{
	Set sc = host.OnMessage(..NewRequest("decide", "user", text_" (test "_##class(OcuTalon.Bridge.Ids).NewRef()_")"), .reply)
	Quit sc
}

/// 1 when the test must not run: the environment is not the CI override's, and the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason = "" Quit 0
	Do $$$AssertTrue(0, reason)
	Quit 1
}

}
