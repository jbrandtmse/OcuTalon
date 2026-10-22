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
///   - TestChatErrorIsStatus: a provider failure inside Chat gives the runner's error status with no Reply, the context is over, and
///     the next request on the same runner is answered;
///   - TestContext: a probe agent's tool reads the context during Chat and writes the host data and the taint, which the Reply carries,
///     the context is over afterwards, and the built agent has no Temperature although the probe agent has one before the build;
///   - TestFinishReason: the Reply keeps finish_reason of the normal reply and of the refusal and max_tokens stop reasons;
///   - TestCacheOverThreshold: a probe agent whose system prompt is over min_tokens_for_cache, run through the same runner path, has
///     its system block marked for the cache in the mock's log, so the cache block of the composed config reaches the provider;
///   - TestOpenKeepsConfig: a session that a freshly built adapter opens still has the cap and the effort;
///   - TestUnbuiltKinds: kind tool, an unknown kind and an Input that is empty or white space only send nothing and build nothing; a
///     runner with no model sends nothing.
/// Every AI session that a test saves is deleted again.
Class OcuTalon.Test.Bridge.Runner Extends %UnitTest.TestCase
{

/// The class of the runner, whose host is made in memory.
Parameter RUNNER = "OcuTalon.Bridge.Operation.AgentRunner";

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

/// A provider failure (the mock's provider-error scenario answers 500) raises inside Chat and comes back as the runner's error status
/// with AI Hub's text, no Reply and no response, with the context over. The same runner then answers the next request.
Method TestChatErrorIsStatus()
{
	If ..Guard() Quit
	Set host = ..NewRunner(..#AGENT, "low", ..ProviderConfig("triage"))
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("decide", "user", "Fail this. [[mock:provider-error]] (test "_ref_")")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertStatusNotOK(sc, "a provider failure gives an error status, not an exception")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ProviderError", "that carries AI Hub's text: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 300))
	Do $$$AssertTrue('$IsObject(response), "and no response")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set requests = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, ref)
	Do $$$AssertTrue(requests.%Size() > 0, "the request reached the mock: "_requests.%Size())
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(.position, .logged) {
		Do $$$AssertEquals(logged.status, 500, "request "_(position + 1)_" was answered with the provider failure")
	}
	Do $$$AssertStatusOK(..Ask(host, "A new email arrived. Should the user hear about it now?", .normal), "the next request on the same runner is answered")
	Do $$$AssertEquals(normal.Text, ##class(OcuTalon.Test.Agent.RunnerFixture).#TRIAGETEXT, "with the text of Triage's script")
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

/// --- helpers ---
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

/// A runner host made in memory, a shadow, whose adapter has the agent class, an allow-list of that class, the effort and the
/// provider configuration. The key is the non-secret CI variable.
Method NewRunner(agentClass As %String, effort As %String = "", providerConfig As %String = "") As OcuTalon.Bridge.Operation.AgentRunner [ Private ]
{
	Set host = $ClassMethod(..#RUNNER, "%New", "ZzRunner")
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
ClassMethod ProviderConfig(mockKey As %String = "", key As %String = "") As %String [ Private ]
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
