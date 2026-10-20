/// Integration tests of the CI model mock through AI Hub's Anthropic provider (Story 0.11; AD-22). THIS CLASS RUNS IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21): the CI override points OCUTALON_MODEL_BASE_URL at the mock service, and the mock's request
/// log is mounted read-only at /opt/ocutalon/mock-log. Where the variable holds anything but the mock's base URL, every test
/// except the three that check values fails with that reason and no provider is built, so that this class can never send a
/// request to a real model API. The same override sets the CI-only switch OCUTALON_MOCK_KEY_HEADER to 1 (owner decision 5);
/// where it is anything else, those tests fail with that reason. It uses the dummy key DUMMYKEY and never a real one.
///   - TestBaseUrlGuard: CheckBaseUrl accepts the mock's base URL and nothing else (it checks values, not the environment, so it
///     passes under any value of the variable);
///   - TestGuardRefusesOtherEnvironments: MissingReason gives the reason why every test fails for each pair of values of the two
///     variables, and ProviderFor throws, building nothing, for any base URL but the mock's (values again, so it passes anywhere);
///   - TestMockKeyHeaderSwitch: CheckMockKeyFlag accepts the string 1 and nothing else, and CustomHeaders, and with it the
///     provider's settings, add the mock key header only when the switch is 1 and a mock key is given (it checks values, not the
///     environment);
///   - TestDefaultScriptByMockKey: a provider with the Triage agent's MOCKKEY in x-ocutalon-mockkey and a chat with no marker
///     get Triage's default script, and the mock logged the model lookup and the request without the key;
///   - TestMarker: a [[mock:refusal:<key>]] marker picks the refusal scenario, whatever the mock key;
///   - TestSamplingAndCapRefused: a sampling parameter in extra_params and a max_tokens of 3999 are refused as "Invalid input";
///   - TestCountdownAndRetryAfterCap: an armed countdown makes the first request a 429 with Retry-After 30, and the retry block's
///     max_backoff_ms caps the wait (S18).
/// The helpers are class methods that either lane's tests may call (read, do not copy):
///   - Provider(mockKey, httpConfig): the Anthropic provider for the mock. It throws unless the environment variable is the mock's
///     base URL. httpConfig defaults to request_timeout_secs 10 and the retry block {max_retries 1, attempt_timeout_secs 10,
///     initial_backoff_ms 500, max_backoff_ms 2000}; a given one is copied. mockKey (an agent class's MOCKKEY) is added to its
///     custom_headers as MOCKKEYHEADER, unless it is empty or OCUTALON_MOCK_KEY_HEADER is not 1 (CustomHeaders);
///   - Arm(marker, remaining) and Remaining(marker, .remaining): the countdown of the marker "<name>[:<key>]" without brackets;
///     remaining "" clears it;
///   - LogMark(): the number of lines in the mock's request log; LogSince(mark, .entries): the lines after the first mark
///     lines, each parsed, in a dynamic array. Other clients may call the mock meanwhile, so a test picks, among the lines after
///     its own mark, those that carry its own marker (the mock logs a refused request with its marker too) or, in a request with
///     no marker, a reference of its own in the text (the file's line holds the messages).
/// Marker keys come from OcuTalon.Bridge.Ids.NewRef(). Sessions are never saved, and nothing is written to IRIS.
Class OcuTalon.Test.Contract.Mock Extends %UnitTest.TestCase
{

/// The mock's base URL: the only value of OCUTALON_MODEL_BASE_URL that this class runs under.
Parameter BASEURL = "http://mock:8080/v1/";

/// The key of the provider: a dummy that the mock only counts.
Parameter DUMMYKEY = "ocutalon-ci-mock-key";

/// The mock's request log, as the CI override mounts it.
Parameter LOGFILE = "/opt/ocutalon/mock-log/requests.jsonl";

/// The request header that carries an agent's MOCKKEY.
Parameter MOCKKEYHEADER = "x-ocutalon-mockkey";

/// The environment variable that switches the mock-key header on: only the CI override sets it, to 1 (owner decision 5).
Parameter MOCKKEYFLAG = "OCUTALON_MOCK_KEY_HEADER";

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 300);

/// The mock's log mark when the run of this class began.
Property ClassMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Missing = ..MissingReason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron(..#MOCKKEYFLAG))
	If ..Missing = "" Set ..ClassMark = ..LogMark()
	Quit $$$OK
}

/// Row 23: CheckBaseUrl accepts the mock's base URL, with its trailing slash, and nothing else.
Method TestBaseUrlGuard()
{
	Do $$$AssertStatusOK(..CheckBaseUrl("http://mock:8080/v1/"), "http://mock:8080/v1/ is the mock's base URL")
	For url = "", "https://api.anthropic.com/v1/", "http://mock:8080/v1", "http://mock:8080/v1/ ", "http://mock:8080/", "HTTP://MOCK:8080/V1/" {
		Set status = ..CheckBaseUrl(url)
		Do $$$AssertTrue($$$ISERR(status), "'"_url_"' is refused")
		Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(status), ..NotMockText()), "the refusal says why: "_..NotMockText())
	}
	Do $$$AssertEquals(..NotMockText(), "OCUTALON_MODEL_BASE_URL is not http://mock:8080/v1/: this class runs in throwaways and CI only (Rule 21)", "the reason is the one of the spec")
}

/// Owner decision 5: the mock-key header is added only when the switch is the string 1 and a mock key is given.
Method TestMockKeyHeaderSwitch()
{
	Do $$$AssertStatusOK(..CheckMockKeyFlag("1"), "1 is the setting of the CI override")
	For value = "", "0", "true", "yes", "11", "01", "1 ", " 1" {
		Set status = ..CheckMockKeyFlag(value)
		Do $$$AssertTrue($$$ISERR(status), "'"_value_"' is refused")
		Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(status), ..NotFlagText()), "the refusal says why: "_..NotFlagText())
	}
	Set on = ..CustomHeaders("triage", "1")
	Do $$$AssertEquals(on.%Get(..#MOCKKEYHEADER), "triage", "with the switch on, the header carries the mock key")
	Do $$$AssertEquals(on.%Size(), 1, "and it is the only header")
	For value = "", "0", "true", "yes", "11", "01", "1 " {
		Do $$$AssertEquals(..CustomHeaders("triage", value).%Size(), 0, "with the switch '"_value_"', no header is added")
	}
	Do $$$AssertEquals(..CustomHeaders("", "1").%Size(), 0, "with the switch on and no mock key, no header is added")
	Set settings = ..ProviderSettings("1", "triage")
	Do $$$AssertEquals(settings."http_config"."custom_headers".%Get(..#MOCKKEYHEADER), "triage", "with the switch on, the provider's settings carry the header")
	Do $$$AssertEquals(settings."api_key", ..#DUMMYKEY, "and the dummy key")
	Do $$$AssertEquals(settings."base_url", ..#BASEURL, "and the mock's base URL")
	Do $$$AssertEquals(settings."http_config"."retry"."max_backoff_ms", 2000, "and the default retry block")
	For value = "", "0" {
		Do $$$AssertEquals(..ProviderSettings(value, "triage")."http_config"."custom_headers".%Size(), 0, "with the switch '"_value_"', the provider's settings carry no header")
	}
	Set given = {"request_timeout_secs": 5, "custom_headers": {"x-other": "kept"}}
	Set settings = ..ProviderSettings("1", "triage", given)
	Do $$$AssertEquals(settings."http_config"."request_timeout_secs", 5, "a given http_config is used")
	Do $$$AssertEquals(settings."http_config"."custom_headers"."x-other", "kept", "with its own headers kept")
	Do $$$AssertEquals(settings."http_config"."custom_headers".%Get(..#MOCKKEYHEADER), "triage", "and the mock key header added")
	Do $$$AssertEquals(given."custom_headers".%Size(), 1, "to a copy: the given object is unchanged")
	Do $$$AssertEquals(..#MOCKKEYFLAG, "OCUTALON_MOCK_KEY_HEADER", "the switch is the variable of the CI override")
	Do $$$AssertEquals(..NotFlagText(), "OCUTALON_MOCK_KEY_HEADER is not 1: this class runs in throwaways and CI only, where ci/compose.ci.yml sets it (owner decision 5)", "the reason is the one of the task")
}

/// AC7: off the CI override's environment, every test fails with the reason, and no provider is built.
Method TestGuardRefusesOtherEnvironments()
{
	Do $$$AssertEquals(..MissingReason("http://mock:8080/v1/", "1"), "", "the CI override's environment passes")
	For url = "", "https://api.anthropic.com/v1/", "http://mock:8080/v1" {
		Do $$$AssertEquals(..MissingReason(url, "1"), ..NotMockText(), "'"_url_"' fails every test with the base URL reason")
		Do $$$AssertEquals(..MissingReason(url, ""), ..NotMockText(), "and the base URL is named before the switch")
		Set threw = 0
		Try {
			Set provider = ..ProviderFor(url, "1", "triage")
		} Catch ex {
			Set threw = 1
		}
		Do $$$AssertTrue(threw, "no provider is built for '"_url_"'")
	}
	For switch = "", "0", "true" {
		Do $$$AssertEquals(..MissingReason("http://mock:8080/v1/", switch), ..NotFlagText(), "the switch '"_switch_"' fails every test with its own reason")
	}
}

/// Row 19: the default script of the Triage agent, through the Anthropic provider and the mock key header.
Method TestDefaultScriptByMockKey()
{
	If '..Guard() Quit
	Set model = $Parameter("OcuTalon.Agent.Triage", "MODEL")
	Set mockKey = $Parameter("OcuTalon.Agent.Triage", "MOCKKEY")
	Do $$$AssertEquals(model, "claude-haiku-5-5", "the Triage agent's model")
	Do $$$AssertEquals(mockKey, "triage", "the Triage agent's mock key")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ..LogMark()
	Set agent = ##class(%AI.Agent).%New(..Provider(mockKey))
	Set agent.Model = model
	Set status = agent.%Init()
	Do $$$AssertStatusOK(status, "the agent initializes")
	Set session = agent.CreateSession({"max_tokens": 8000})
	Set response = agent.Chat(session, "A new email arrived in the Orders inbox (test "_ref_"). Should the user hear about it now?")
	Set reply = {}.%FromJSON(response.Content)
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#OUTCOME), reply.outcome), "the reply's outcome is an OUTCOME value: "_reply.outcome)
	Do $$$AssertTrue((reply.confidence >= 0) && (reply.confidence <= 1), "the reply's confidence is from 0 to 1: "_reply.confidence)
	Do $$$AssertEquals(response.Extra."finish_reason", "end_turn", "the reply ends its turn")
	Do $$$AssertEquals(session.GetStats()."model_context_size", 1000000, "the model lookup gave the context size of the mock's model object")

	Set status = ..LogSince(mark, .entries)
	Do $$$AssertStatusOK(status, "the log is read")
	Set status = ..LogSince(..ClassMark, .sinceClass)
	Do $$$AssertStatusOK(status, "the log since the class began is read")
	Set lookup = ..Find(sinceClass, "GET", "/v1/models/"_model)
	Set post = ..Find(entries, "POST", "/v1/messages", ref)
	Do $$$AssertTrue($IsObject(lookup), "since the class began, the log holds the model lookup (AI Hub makes it at the first chat of a process for a model)")
	If $IsObject(lookup) Do $$$AssertEquals(lookup.status, 200, "the model lookup was answered with 200")
	Do $$$AssertTrue($IsObject(post), "the log holds the request")
	If $IsObject(post) {
		Do $$$AssertEquals(post.scenario, "triage", "the request ran the scenario triage")
		Do $$$AssertEquals(post.selectedBy, "mockkey", "picked by the mock key")
		Do $$$AssertEquals(post.status, 200, "and was answered with 200")
		Do $$$AssertEquals(post.model, model, "the request names the agent's model")
		Do $$$AssertEquals(post.maxTokens, 8000, "the request's cap is 8000")
		Do $$$AssertEquals(post.keyLength, $Length(..#DUMMYKEY), "the key's length is logged")
		Do $$$AssertTrue(..Has(post.headerNames, "x-api-key"), "the key traveled in x-api-key")
		Do $$$AssertTrue(..Has(post.headerNames, ..#MOCKKEYHEADER), "the mock key traveled in "_..#MOCKKEYHEADER)
	}
	Do $$$AssertTrue('..LogHolds(..#DUMMYKEY), "the log file never holds the key")
}

/// Row 20: a marker picks its scenario, with a test key that no other test shares.
Method TestMarker()
{
	If '..Guard() Quit
	Set marker = "refusal:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ..LogMark()
	Set agent = ##class(%AI.Agent).%New(..Provider("triage"))
	Set agent.Model = $Parameter("OcuTalon.Agent.Triage", "MODEL")
	Set status = agent.%Init()
	Do $$$AssertStatusOK(status, "the agent initializes")
	Set session = agent.CreateSession({"max_tokens": 8000})
	Set response = agent.Chat(session, "Please answer this. [[mock:"_marker_"]]")
	Do $$$AssertEquals(response.Extra."finish_reason", "refusal", "the refusal scenario ended the turn with a refusal")
	Set status = ..LogSince(mark, .entries)
	Do $$$AssertStatusOK(status, "the log is read")
	Set count = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.marker = marker) {
			Set count = count + 1
			Do $$$AssertEquals(entry.selectedBy, "marker", "the marker picked the scenario, not the mock key")
			Do $$$AssertEquals(entry.scenario, "refusal", "the scenario is refusal")
		}
	}
	Do $$$AssertEquals(count, 1, "exactly one request carries the marker")
}

/// Row 21: the mock refuses what AD-7 forbids, and AI Hub raises it as a provider error.
Method TestSamplingAndCapRefused()
{
	If '..Guard() Quit
	Set marker = "refusal:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set input = "Hello. [[mock:"_marker_"]]"
	Set mark = ..LogMark()
	Set agent = ##class(%AI.Agent).%New(..Provider("triage"))
	Set agent.Model = $Parameter("OcuTalon.Agent.Triage", "MODEL")
	Set status = agent.%Init()
	Do $$$AssertStatusOK(status, "the agent initializes")
	Set text = ..ChatError(agent, {"max_tokens": 8000, "extra_params": {"temperature": 0.5}}, input)
	Do $$$AssertTrue($Find(text, "<%AICore>ProviderError"), "a sampling parameter raises a provider error: "_text)
	Do $$$AssertTrue($Find(text, "Invalid input"), "which says Invalid input")
	Do $$$AssertTrue($Find(text, "temperature"), "and names temperature")
	Set text = ..ChatError(agent, {"max_tokens": 3999}, input)
	Do $$$AssertTrue($Find(text, "<%AICore>ProviderError"), "a cap of 3999 raises a provider error: "_text)
	Do $$$AssertTrue($Find(text, "Invalid input"), "which says Invalid input")
	Do $$$AssertTrue($Find(text, "max_tokens"), "and names max_tokens")
	Set status = ..LogSince(mark, .entries)
	Do $$$AssertStatusOK(status, "the log is read")
	Set rejected = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.marker = marker) Set rejected = rejected_$ListBuild(entry.status_"/"_entry.rejected)
	}
	Do $$$AssertEquals($ListToString(rejected), "400/sampling,400/max_tokens", "the log shows both requests as rejected with 400, and neither was retried")
}

/// Row 22 (S18): an armed countdown answers the first request with 429 and Retry-After 30; AI Hub waits the retry block's
/// max_backoff_ms (2 s), not 30 s, and then gets the 200.
Method TestCountdownAndRetryAfterCap()
{
	If '..Guard() Quit
	Set marker = "long-retry-after:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ..LogMark()
	Set status = ..Arm(marker, 1)
	Do $$$AssertStatusOK(status, "the countdown is armed with 1")
	Set status = ..Remaining(marker, .before)
	Do $$$AssertStatusOK(status, "the countdown is read")
	Do $$$AssertEquals(before, 1, "one failure is left")
	Set agent = ##class(%AI.Agent).%New(..Provider("triage"))
	Set agent.Model = $Parameter("OcuTalon.Agent.Triage", "MODEL")
	Set status = agent.%Init()
	Do $$$AssertStatusOK(status, "the agent initializes")
	Set session = agent.CreateSession({"max_tokens": 8000})
	Set started = $ZHorolog
	Set response = agent.Chat(session, "Wait for it. [[mock:"_marker_"]]")
	Set elapsed = $ZHorolog - started
	Do $$$AssertEquals(response.Content, "Answered after a capped wait.", "the second request got the 200 text")
	Do $$$AssertTrue((elapsed >= 1.5) && (elapsed <= 10), "the wait was capped by max_backoff_ms (2000), not Retry-After (30): "_elapsed_" s")
	Set status = ..Remaining(marker, .after)
	Do $$$AssertStatusOK(status, "the countdown is read again")
	Do $$$AssertEquals(after, 0, "no failure is left")
	Set status = ..LogSince(mark, .entries)
	Do $$$AssertStatusOK(status, "the log is read")
	Set statuses = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.marker = marker) Set statuses = statuses_$ListBuild(entry.status)
	}
	Do $$$AssertEquals($ListToString(statuses), "429,200", "the log shows the 429 and then the 200 for the marker")
	Set status = ..Arm(marker, "")
	Do $$$AssertStatusOK(status, "the countdown is cleared")
}

/// OK only for the mock's base URL; otherwise the status says why.
ClassMethod CheckBaseUrl(url As %String) As %Status
{
	If url = ..#BASEURL Quit $$$OK
	Quit $$$ERROR($$$GeneralError, ..NotMockText())
}

/// OK only for the string 1, the setting of the CI override; otherwise the status says why.
ClassMethod CheckMockKeyFlag(value As %String) As %Status
{
	If value = "1" Quit $$$OK
	Quit $$$ERROR($$$GeneralError, ..NotFlagText())
}

/// The custom_headers that carry an agent's mock key: MOCKKEYHEADER with the mock key when the switch is the string 1 and the
/// mock key is not empty, otherwise an empty object. OCUTALON_MODEL_BASE_URL alone never adds the header (owner decision 5).
ClassMethod CustomHeaders(mockKey As %String, switch As %String) As %DynamicObject
{
	Set headers = {}
	If (switch = "1") && ($Get(mockKey) '= "") Do headers.%Set(..#MOCKKEYHEADER, mockKey)
	Quit headers
}

/// The reason why every test fails for these values of OCUTALON_MODEL_BASE_URL and OCUTALON_MOCK_KEY_HEADER, or "" when both
/// are the CI override's. The base URL is checked first.
ClassMethod MissingReason(baseUrl As %String, switch As %String) As %String
{
	If $$$ISERR(..CheckBaseUrl(baseUrl)) Quit ..NotMockText()
	If $$$ISERR(..CheckMockKeyFlag(switch)) Quit ..NotFlagText()
	Quit ""
}

/// The Anthropic provider for the mock (see the class comment). It throws unless OCUTALON_MODEL_BASE_URL is the mock's base URL.
ClassMethod Provider(mockKey As %String, httpConfig As %DynamicObject = "") As %AI.Provider
{
	Quit ..ProviderFor($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron(..#MOCKKEYFLAG), $Get(mockKey), httpConfig)
}

/// Provider for the given values of OCUTALON_MODEL_BASE_URL and OCUTALON_MOCK_KEY_HEADER: it throws, building nothing, unless
/// baseUrl is the mock's base URL, and then builds the provider for BASEURL.
ClassMethod ProviderFor(baseUrl As %String, switch As %String, mockKey As %String, httpConfig As %DynamicObject = "") As %AI.Provider
{
	Set status = ..CheckBaseUrl(baseUrl)
	If $$$ISERR(status) $$$ThrowStatus(status)
	Quit ##class(%AI.Provider).Create("anthropic", ..ProviderSettings(switch, $Get(mockKey), httpConfig))
}

/// The settings of the Anthropic provider for the mock: DUMMYKEY, BASEURL, and a copy of httpConfig (by default the one of the
/// class comment) whose custom_headers gain the header of CustomHeaders(mockKey, switch). It builds no provider.
ClassMethod ProviderSettings(switch As %String, mockKey As %String, httpConfig As %DynamicObject = "") As %DynamicObject [ Private ]
{
	If $IsObject(httpConfig) {
		Set config = {}.%FromJSON(httpConfig.%ToJSON())
	} Else {
		Set config = {"request_timeout_secs": 10, "retry": {"max_retries": 1, "attempt_timeout_secs": 10, "initial_backoff_ms": 500, "max_backoff_ms": 2000}}
	}
	If '$IsObject(config."custom_headers") Do config.%Set("custom_headers", {})
	Set headers = ..CustomHeaders($Get(mockKey), switch)
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Do config."custom_headers".%Set(name, value)
	}
	Quit {"api_key": (..#DUMMYKEY), "base_url": (..#BASEURL), "http_config": (config)}
}

/// Arms the countdown of a marker ("<name>[:<key>]", without brackets) with the number of requests that get its first reply;
/// "" clears it.
ClassMethod Arm(marker As %String, remaining As %Integer) As %Status
{
	Set request = ..NewRequest()
	Set request.ContentType = "application/json"
	Set body = {"marker": (marker)}
	If remaining = "" {
		Do body.%Set("remaining", "", "null")
	} Else {
		Do body.%Set("remaining", remaining, "number")
	}
	Do request.EntityBody.Write(body.%ToJSON())
	Set status = request.Post("/_mock/countdown")
	If $$$ISERR(status) Quit status
	If request.HttpResponse.StatusCode '= 200 Quit $$$ERROR($$$GeneralError, "the mock answered "_request.HttpResponse.StatusCode_" to the countdown")
	Quit $$$OK
}

/// The countdown of a marker: remaining is the number of requests that still get its first reply, or "" when none is armed.
ClassMethod Remaining(marker As %String, Output remaining As %Integer) As %Status
{
	Set remaining = ""
	Set request = ..NewRequest()
	Do request.SetParam("marker", marker)
	Set status = request.Get("/_mock/countdown")
	If $$$ISERR(status) Quit status
	If request.HttpResponse.StatusCode '= 200 Quit $$$ERROR($$$GeneralError, "the mock answered "_request.HttpResponse.StatusCode_" to the countdown")
	Set answer = {}.%FromJSON(request.HttpResponse.Data)
	Set remaining = answer.remaining
	Quit $$$OK
}

/// The number of lines in the mock's request log: 0 when there is none.
ClassMethod LogMark() As %Integer
{
	Set count = 0
	If '##class(%File).Exists(..#LOGFILE) Quit 0
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(..#LOGFILE)) Quit 0
	While 'stream.AtEnd {
		If stream.ReadLine($$$MaxLocalLength) '= "" Set count = count + 1
	}
	Quit count
}

/// The lines of the mock's request log after the first mark ones, each read whole and parsed, in a dynamic array.
ClassMethod LogSince(mark As %Integer, Output entries As %DynamicArray) As %Status
{
	Set entries = []
	If '##class(%File).Exists(..#LOGFILE) Quit $$$OK
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set status = stream.LinkToFile(..#LOGFILE)
	If $$$ISERR(status) Quit status
	Set line = 0
	Try {
		While 'stream.AtEnd {
			Set text = stream.ReadLine($$$MaxLocalLength)
			If text = "" Continue
			Set line = line + 1
			If line > mark Do entries.%Push({}.%FromJSON(text))
		}
	} Catch ex {
		Set entries = []
		Set status = ex.AsStatus()
	}
	Quit status
}

/// The reason why the base URL is refused.
ClassMethod NotMockText() As %String [ Private ]
{
	Quit "OCUTALON_MODEL_BASE_URL is not "_..#BASEURL_": this class runs in throwaways and CI only (Rule 21)"
}

/// The reason why the mock-key switch is refused.
ClassMethod NotFlagText() As %String [ Private ]
{
	Quit ..#MOCKKEYFLAG_" is not 1: this class runs in throwaways and CI only, where ci/compose.ci.yml sets it (owner decision 5)"
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The text of the error that a chat of input raises with this session config ("" when it raises none).
Method ChatError(agent As %AI.Agent, config As %DynamicObject, input As %String) As %String [ Private ]
{
	Set text = ""
	Try {
		Set session = agent.CreateSession(config)
		Do agent.Chat(session, input)
	} Catch ex {
		Set text = $Translate(ex.DisplayString(), $Char(13, 10), "  ")
	}
	Quit text
}

/// The first entry with this method and path whose line holds text (any line when text is ""), or "".
ClassMethod Find(entries As %DynamicArray, method As %String, path As %String, text As %String = "") As %DynamicObject [ Private ]
{
	Set found = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = method) && (entry.path = path) && ((text = "") || $Find(entry.%ToJSON(), text)) {
			Set found = entry
			Quit
		}
	}
	Quit found
}

/// 1 when the dynamic array of names holds the name.
ClassMethod Has(names As %DynamicArray, name As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = names.%GetIterator()
	While iterator.%GetNext(, .value) {
		If value = name {
			Set found = 1
			Quit
		}
	}
	Quit found
}

/// 1 when any line of the mock's request log holds the text.
ClassMethod LogHolds(text As %String) As %Boolean [ Private ]
{
	Set found = 0
	If '##class(%File).Exists(..#LOGFILE) Quit 0
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(..#LOGFILE)) Quit 0
	While 'stream.AtEnd {
		If $Find(stream.ReadLine($$$MaxLocalLength), text) {
			Set found = 1
			Quit
		}
	}
	Quit found
}

/// The HTTP request to the mock's host and port, which are those of BASEURL.
ClassMethod NewRequest() As %Net.HttpRequest [ Private ]
{
	Set hostPort = $Piece($Piece(..#BASEURL, "//", 2), "/", 1)
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = $Piece(hostPort, ":", 1)
	Set request.Port = +$Piece(hostPort, ":", 2)
	Set request.Timeout = 10
	Quit request
}

}
