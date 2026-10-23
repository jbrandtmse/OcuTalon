/// What the tests that drive the agent runners share (Story 1.2; AD-6, AD-7, AD-19). THESE HELPERS RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21): they act on the running OcuTalon.Production and read the CI mock's log.
///   - Running, RunningReason, Restart and Jobs: the state of the production and of the jobs of its items;
///   - Send: a message to a production item through the adapterless service ApprovalStartIn, as a caller of the runners will;
///   - NewRequest and Ask: a Request of a kind and provenance with an ItemId of its own, and a send of it to a runner;
///   - ReadyReason: "" only when the production runs with every item, in the CI override's environment;
///   - DecisionOf, Headers, SessionOf, HeaderMark and SessionSince (Story 1.3): the Decision row of an item, and the message
///     headers of a session (the target, body class and body id of each header that a source item sent);
///   - PointKeys and RestoreKeys: CI starts with no model key on purpose, so the live tests point the entry of each runner at
///     OCUTALON_MOCK_KEY_HEADER, a non-secret CI-only variable (value 1), through ConfigStore.Merge, and put the entries back to
///     the placeholder of the Provider step afterwards. Both restart the runners, because a runner builds its agent once;
///     KeysAre reads the api_key placeholder of each runner's entry, so that a test can tell whether the entries are as the
///     Provider step left them;
///   - GuardReason: "" only when the environment is the CI override's (the mock's base URL and the mock-key switch), so that no
///     test can send a request to a real model API;
///   - FindRequest, FindRequests, Effort, CacheMark and Has: read the entries of the mock's log (Test.Contract.Mock.LogSince);
///   - EventMark, EventRows, LogRowsHolding and Warnings: the rows of the event log after a mark, the number of them that hold a value,
///     and the warnings that one method logged after it;
///   - UsageIds, AddUsage and Totals (Story 1.4): the Usage rows of an item or a decision, a fixture Usage row, and the total fields
///     of a Decision row or an answer, which the tests of Test.Agent and Test.Bridge share.
///   - UseAgent and RestoreAgent (Story 1.5): put a test agent behind a runner item, and put the item back, by changing the item's
///     AgentClass and AgentAllowList settings in the stored configuration of the production and updating the running production;
///     StepsOf: the AgentStep rows of a decision, by Position; Headers also gives the id of each header; Run, Targets, HeaderTo and
///     CountTo are the send to Decide and the readings of its headers, which Test.Agent.Decide and Test.Agent.Steps share (Run returns
///     the session of the header that carries its request, SessionOf, never the first header to Decide after a mark: a message that
///     Decide discards, such as an earlier decision's timer, can come first);
///     DeleteSteps (QA): the AgentStep messages of an item's requests are deleted once AgentSteps has handled them; LeakPlaces: where a
///     fake secret shows after a call (the steps, the runner's Reply, the event log and the stores of the key scan), which the redaction
///     tests of Test.Agent.Steps and Test.Bridge.Runner share, with TextControlsMissing, the controls of the scenario steps-secrets-text.
///   - UseItemSetting and RestoreItemSetting (Story 1.6): the same swap for one setting of any target (Adapter or Host) of an item, such
///     as Decide's HostSinkClass (both swaps go through ChangeSettings); SnapshotDefault, PutDefault and RestoreDefault: a System Default
///     Settings row of an item put in place and put back, with RememberDefault and RestoreDefaults for the list of rows a test wrote
///     (Test.Bridge.Budget, Test.Bridge.Decide and Test.Agent.Decide delegate to them); ErrorRows: the event-log rows of Type 2 or 6 after a mark
///     (a start with no key writes none); SinkCalls: the calls that the shared mode of Test.Bridge.ProbeSink recorded in the production's
///     own jobs.
///   - Drain and FallbackProblems (QA, Story 1.6): Drain waits until a runner has handled every message sent to it before the call, so that
///     a test that asserts that nothing reached the mock reads the log after a request of Decide's could have arrived; FallbackProblems
///     names whatever is missing from the guarantees of a fallback (the answer, its XML and the Decision row), for every live test of a fallback.
///   - UseTimer and RestoreTimer (Story 1.7): change the bridge timer for a test the way the product does, through Timeouts.Apply (the row of
///     TimerSeconds, the block of every runner's entry and the restarts of Decide and the runners), and put it back through Apply with the
///     earlier timer and then RestoreDefaults for the row as it was.
/// No literal key is written anywhere.
Class OcuTalon.Test.Agent.RunnerFixture
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The runners of the production, in the order of the production.
Parameter RUNNERS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// The longest to wait for every item to run, in seconds. A ceiling, not a delay: the wait polls once a second and returns as soon
/// as the items run, so a slow machine takes longer and does not fail.
Parameter WAITSECONDS = 120;

/// The longest a sent message waits for its answer, in seconds. A ceiling too: the first request of a runner builds its agent.
Parameter SENDSECONDS = 240;

/// The variable whose value is the placeholder of the pointed entries: a non-secret CI-only variable.
Parameter MOCKKEYVARIABLE = "OCUTALON_MOCK_KEY_HEADER";

/// The reply of Triage's default script, from ci/mock/scenarios/A/triage.json.
Parameter TRIAGETEXT = "{""outcome"":""digest"",""reasons"":[""The CI mock keeps this item for the digest.""],""confidence"":0.5}";

/// The final reply of Diagnosis's default script, from ci/mock/scenarios/A/diagnosis.json.
Parameter DIAGNOSISTEXT = "{""causeCategory"":""data_format_change"",""elementAtFault"":""OrderDate"",""fixKind"":""repair_resend"",""reasons"":[""The CI mock read the failed messages.""],""confidence"":0.8}";

/// "" when the production runs. Otherwise the reason, which a test reports as a failure.
ClassMethod RunningReason() As %String
{
	If ##class(Ens.Director).IsProductionRunning(.running), running = ..#PRODUCTION Quit ""
	Quit ..#PRODUCTION_" does not run: this class runs in throwaways and CI only, after the Production step has started it (Rule 21)"
}

/// 1 when OcuTalon.Production runs.
ClassMethod Running() As %Boolean
{
	Quit ..RunningReason() = ""
}

/// "" only when OCUTALON_MODEL_BASE_URL is the mock's base URL and OCUTALON_MOCK_KEY_HEADER is 1. Otherwise the reason. This is
/// Test.Contract.Mock.MissingReason for the environment of this process.
ClassMethod GuardReason() As %String
{
	Quit ##class(OcuTalon.Test.Contract.Mock).MissingReason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"))
}

/// Stops the item temporarily and starts it again, each through the director, and (when wait is 1) waits until every item runs.
/// The status is the first error of the two calls, or an error when some item still does not run after WAITSECONDS. An item that
/// is refused at start does not run, so a test that expects a refusal passes wait 0.
ClassMethod Restart(name As %String, wait As %Boolean = 1) As %Status
{
	Set sc = ##class(Ens.Director).TempStopConfigItem(name, 1)
	If $$$ISOK(sc) Set sc = ##class(Ens.Director).TempStopConfigItem(name, 0)
	If $$$ISOK(sc) && wait && '..WaitAllRun() Set sc = $SYSTEM.Status.Error(5001, "Not every item of "_..#PRODUCTION_" runs "_..#WAITSECONDS_" seconds after "_name_" was started again: "_##class(OcuTalon.Install.Step.Production).NotRunning())
	Quit sc
}

/// Waits, up to WAITSECONDS, until every item of the production runs. 1 when they do.
ClassMethod WaitAllRun() As %Boolean
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While (##class(OcuTalon.Install.Step.Production).NotRunning() '= "") && ($ZHorolog < deadline) {
		Hang 1
	}
	Quit ##class(OcuTalon.Install.Step.Production).NotRunning() = ""
}

/// The alive jobs of an item, as a list of job ids.
ClassMethod Jobs(item As %String) As %List
{
	Set jobs = ""
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	If $$$ISERR(result.Execute()) Quit jobs
	While result.Next() {
		If (result.Get("ConfigName") = item) && (result.Get("State") = "Alive") Set jobs = jobs _ $ListBuild(result.Get("Job"))
	}
	Quit jobs
}

/// The highest id of the event log: the mark that LogRows reads from.
ClassMethod EventMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of event-log rows after the mark (EventMark) whose text holds the value.
ClassMethod LogRowsHolding(mark As %Integer, value As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text [ ?", mark, value)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Where the value shows after a call, as a text that names each place ("" when it shows nowhere): the label or summary of a step of
/// steps (step records or AgentStep rows, each an object with label and summary), the Steps and the XML of the runner's reply (when it
/// is an object), the rows of the event log after the mark (EventMark), and the stores that the key scan names (Test.Agent.KeyScan.Find).
ClassMethod LeakPlaces(value As %String, steps As %DynamicArray, reply As %RegisteredObject, mark As %Integer) As %String
{
	Set places = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(.index, .step) {
		If (step.label [ value) || (step.summary [ value) Set places = places _ $ListBuild("step " _ (index + 1))
	}
	If $IsObject(reply) {
		If reply.Steps [ value Set places = places _ $ListBuild("the Steps of the runner's Reply")
		Set xml = ""
		If $$$ISERR(reply.XMLExportToString(.xml)) Set places = places _ $ListBuild("the runner's Reply, whose XML cannot be exported")
		If xml [ value Set places = places _ $ListBuild("the XML of the runner's Reply")
	}
	Set rows = ..LogRowsHolding(mark, value)
	If rows Set places = places _ $ListBuild(rows _ " event-log rows")
	Set stores = ##class(OcuTalon.Test.Agent.KeyScan).Find(value)
	If stores '= "" Set places = places _ $ListBuild("the key scan: " _ $ListToString(stores, ", "))
	Quit $ListToString(places, "; ")
}

/// The controls of the scenario steps-secrets-text, as a text that names each one that fails ("" when all hold): the fixtures hold the 14
/// fake secrets that the redaction tests look for (OcuTalon.Test.Bridge.StepsNote.TextValues). The report of StepsText for the topic keys
/// is text that holds JSON with the five kinds under their keys and four of them in a line of free text, and the error that StepsCard
/// throws for the owner refused holds all five.
ClassMethod TextControlsMissing() As %String
{
	Set missing = ""
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	If $ListLength($ClassMethod(note, "TextValues")) '= 14 Set missing = missing _ $ListBuild("TextValues does not list 14 values")
	Set report = $ClassMethod("OcuTalon.Test.Bridge.StepsText", "Read", "keys")
	If $Extract(report) '= "{" Set missing = missing _ $ListBuild("the report is not text that holds JSON")
	Set thrown = ""
	Try {
		Do $ClassMethod("OcuTalon.Test.Bridge.StepsCard", "Read", "refused")
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	For kind = "apiKey", "accessToken", "password", "chatId", "displayName" {
		If report '[ $ClassMethod(note, "Secret", kind, "text") Set missing = missing _ $ListBuild("the report lacks the " _ kind _ " under its key")
		If thrown '[ $ClassMethod(note, "Secret", kind, "error") Set missing = missing _ $ListBuild("the error of the refused card lacks the " _ kind)
	}
	For kind = "apiKey", "accessToken", "password", "chatId" {
		If report '[ $ClassMethod(note, "Secret", kind, "line") Set missing = missing _ $ListBuild("the line of free text lacks the " _ kind)
	}
	Quit $ListToString(missing, "; ")
}

/// The rows of the event log after the mark that belong to the item, as a list of "<type>: <text>", oldest first. The type is
/// the number of Ens.Util.Log (1 assert, 2 error, 3 warning, 4 info, 5 trace, 6 alert).
ClassMethod EventRows(mark As %Integer, item As %String) As %List
{
	Set rows = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Type, Text FROM Ens_Util.Log WHERE ID > ? AND ConfigName = ? ORDER BY ID", mark, item)
	While result.%Next() {
		Set rows = rows _ $ListBuild(result.%GetData(1)_": "_result.%GetData(2))
	}
	Quit rows
}

/// Sends the message to the target item through ApprovalStartIn, the adapterless service of the production, and waits for the
/// answer. The status is the one the sender gets, the error of a runner included. response is the answer, or "". A super session, when
/// given, is the SuperSession that the service's messages carry, as those of a channel service do (AD-26).
ClassMethod Send(target As %String, message As %Persistent, Output response As %Persistent, superSession As %String = "") As %Status
{
	Set response = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("ApprovalStartIn", .service)
	If $$$ISERR(sc) Quit sc
	If superSession '= "" Set service.%SuperSession = superSession
	Quit service.SendRequestSync(target, message, .response, ..#SENDSECONDS)
}

/// A Request of the kind and provenance for a new item: ref is a fresh reference, which is the request's ItemId, OwnerRef is
/// instance, Channel is system, Summary is "Test <ref>", and Input is the input with " (test <ref>)" appended, so that the
/// request can be found in the mock's log by its reference.
ClassMethod NewRequest(kind As %String, provenance As %String, input As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ref
	Set request.OwnerRef = "instance"
	Set request.Channel = "system"
	Set request.Summary = "Test "_ref
	Set request.Input = input_" (test "_ref_")"
	Quit request
}

/// Sends a Request of the kind and provenance to the target (NewRequest: the text with a fresh reference of its own in the
/// input), and reads the mock's log for it. reply is the answer (a Reply), or ""; requests holds the entries of the mock's log,
/// since the send, for the requests that carry the reference (a turn with a tool call makes more than one); ref is the
/// reference. The status is the one Send gives.
ClassMethod Ask(target As %String, kind As %String, provenance As %String, text As %String, Output reply As %Persistent, Output requests As %DynamicArray, Output ref As %String) As %Status
{
	Set request = ..NewRequest(kind, provenance, text, .ref)
	Set requests = []
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = ..Send(target, request, .reply)
	If $$$ISOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Set requests = ..FindRequests(entries, ref)
	Quit sc
}

/// "" only when OcuTalon.Production runs, every item of it has its job (the wait is a poll, up to WAITSECONDS), and the environment
/// is the CI override's (GuardReason). Otherwise the reason, which a test reports as a failure.
ClassMethod ReadyReason() As %String
{
	Set reason = ..RunningReason()
	If reason = "" Set reason = ..GuardReason()
	If (reason = "") && '..WaitAllRun() Set reason = "not every item of "_..#PRODUCTION_" runs "_..#WAITSECONDS_" seconds after the test began: "_##class(OcuTalon.Install.Step.Production).NotRunning()
	Quit reason
}

/// The Decision row of the item and kind, or "".
ClassMethod DecisionOf(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision
{
	If '##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(itemId, kind, .id) Quit ""
	Quit ##class(OcuTalon.Bridge.Data.Decision).%OpenId(id)
}

/// The headers of the session that the item named source sent, oldest first, as a dynamic array of
/// {"id","target","bodyClass","bodyId"}: the id of the header and the target, body class and body id of its message.
ClassMethod Headers(sessionId As %Integer, source As %String) As %DynamicArray
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName, MessageBodyClassName, MessageBodyId, ID FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID", sessionId, source)
	While result.%Next() {
		Do headers.%Push({"id": (result.%GetData(4)), "target": (result.%GetData(1)), "bodyClass": (result.%GetData(2)), "bodyId": (result.%GetData(3))})
	}
	Quit headers
}

/// The AgentStep rows of the decision, by Position, as a dynamic array of {"id","position","kind","label","summary","durationMs",
/// "status","estimatedTokens"}: the message bodies that Decide sent to AgentSteps.
ClassMethod StepsOf(decisionRef As %String) As %DynamicArray
{
	Set steps = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Position, StepKind, Label, Summary, DurationMs, Status, EstimatedTokens FROM OcuTalon_Bridge_Msg.AgentStep WHERE DecisionRef = ? ORDER BY Position, ID", decisionRef)
	While result.%Next() {
		Do steps.%Push({"id": (result.%GetData(1)), "position": (result.%GetData(2)), "kind": (result.%GetData(3)), "label": (result.%GetData(4)), "summary": (result.%GetData(5)), "durationMs": (result.%GetData(6)), "status": (result.%GetData(7)), "estimatedTokens": (result.%GetData(8))})
	}
	Quit steps
}

/// Deletes the AgentStep messages of the requests of the item (the DecisionRef of each Request message with its ItemId: the runner
/// requests that Decide sent, so also those of a reply that Conclude refused, which has no Decision row), for the tests that make steps.
/// It first waits, polling up to WAITSECONDS, until the AgentSteps operation has handled each message (its header is no longer Created,
/// Queued or Delivered), so that the operation never opens a message that is gone.
ClassMethod DeleteSteps(itemId As %String)
{
	Set refs = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT DecisionRef FROM OcuTalon_Bridge_Msg.Request WHERE ItemId = ? AND DecisionRef IS NOT NULL", itemId)
	While result.%Next() {
		Set refs = refs _ $ListBuild(result.%GetData(1))
	}
	Set position = 0
	While $ListNext(refs, position, ref) {
		Set steps = ..StepsOf(ref)
		Set iterator = steps.%GetIterator()
		While iterator.%GetNext(, .step) {
			Set deadline = $ZHorolog + ..#WAITSECONDS
			While 1 {
				Set pending = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? AND Status < 4", "OcuTalon.Bridge.Msg.AgentStep", step.id)
				Do pending.%Next()
				If (pending.%GetData(1) = 0) || ($ZHorolog > deadline) Quit
				Hang 0.5
			}
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Msg.AgentStep WHERE DecisionRef = ?", ref)
	}
}

/// Sends the request to Decide and waits for the answer. response is the answer (or ""), and session is the session of the request,
/// which holds every header of the call: the session of the header whose body is the request (SessionOf), never that of the first
/// header addressed to Decide after a mark, which can be another message's (the discarded response of an earlier decision's timer).
/// The status is the one Send gives (superSession as there). mark is the header id (HeaderMark) from which the lookup reads, by
/// default the highest id when Run begins; a test gives an earlier one to put another message to Decide between the mark and the send.
ClassMethod Run(request As OcuTalon.Bridge.Msg.Request, Output response As %Persistent, Output session As %Integer, superSession As %String = "", mark As %Integer = "") As %Status
{
	If mark = "" Set mark = ..HeaderMark()
	Set sc = ..Send("Decide", request, .response, superSession)
	Set session = ..SessionOf(request, mark)
	Quit sc
}

/// The targets of the headers (Headers), sorted and comma-separated.
ClassMethod Targets(headers As %DynamicArray) As %String
{
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set targets(header.target) = ""
	}
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(targets(name))
		Quit:name=""
		Set names = names _ $Select(names = "": "", 1: ",") _ name
	}
	Quit names
}

/// The first header of the array (Headers) that is addressed to the target, or "".
ClassMethod HeaderTo(headers As %DynamicArray, target As %String) As %DynamicObject
{
	Set found = ""
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If (found = "") && (header.target = target) Set found = header
	}
	Quit found
}

/// The number of headers in the array (Headers) that are addressed to the target.
ClassMethod CountTo(headers As %DynamicArray, target As %String) As %Integer
{
	Set count = 0
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.target = target Set count = count + 1
	}
	Quit count
}

/// The session of the first header that carries the message body, or "": the session that holds a response, as Visual Trace shows
/// it. With after (a header id, as HeaderMark gives), only the headers after it count, so the send that followed a mark is found
/// even for a body that was sent before as well.
ClassMethod SessionOf(body As %Persistent, after As %Integer = 0) As %Integer
{
	If '$IsObject(body) || (body.%Id() = "") Quit ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = ? AND MessageBodyId = ? ORDER BY ID", +after, $ClassName(body), body.%Id())
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

/// The highest id of the message headers: the mark that SessionOf (after) and SessionSince read from.
ClassMethod HeaderMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The session of the first header after the mark that is addressed to the item, or "". It answers whether anything was sent to an
/// item since the mark (a test that nothing reached a runner); it is never the way to find a call's own session, because the first
/// header to an item after a mark can be another message's: that is SessionOf of the message the call sent.
ClassMethod SessionSince(mark As %Integer, target As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = ? ORDER BY ID", mark, target)
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

/// Points the Config Store entry of each runner at the placeholder of OCUTALON_MOCK_KEY_HEADER and restarts the runners. The
/// status is the first error.
ClassMethod PointKeys() As %Status
{
	Quit ..SetKeys("@{env:"_..#MOCKKEYVARIABLE_"}")
}

/// Puts the entry of each runner back to the placeholder of the Provider step and restarts the runners. The status is the first
/// error.
ClassMethod RestoreKeys() As %Status
{
	Quit ..SetKeys(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER)
}

/// 1 when the api_key of the Config Store entry of every runner is exactly the placeholder. The entries hold a placeholder only
/// (ConfigStore.Merge refuses anything else), so no key is read.
ClassMethod KeysAre(placeholder As %String) As %Boolean
{
	Set are = 1
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set entry = ..EntryOf(item, .sc)
		If entry '= "" Set sc = ##class(%ConfigStore.Configuration).GetDetails(##class(OcuTalon.Bridge.ConfigStore).FullName(entry), .details, 0, 0)
		If (entry = "") || $$$ISERR(sc) {
			Set are = 0
			Continue
		}
		If details.%Get("api_key") '= placeholder Set are = 0
	}
	Quit are
}

/// The name of the Config Store entry that the item's ProviderConfig names (@{config:<entry>}), or "" with the error in sc.
ClassMethod EntryOf(item As %String, Output sc As %Status) As %String [ Private ]
{
	Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "ProviderConfig", .sc)
	If $$$ISERR(sc) Quit ""
	Set entry = $Piece($Piece(config, "@{config:", 2), "}", 1)
	If entry = "" Set sc = $SYSTEM.Status.Error(5001, item_"'s ProviderConfig does not name a Config Store entry")
	Quit entry
}

/// Merges the api_key into the entry of each runner, then restarts the runners one after the other.
ClassMethod SetKeys(placeholder As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set entry = ..EntryOf(item, .status)
		If entry = "" {
			Set sc = $$$ADDSC(sc, status)
			Continue
		}
		Set sc = $$$ADDSC(sc, ##class(OcuTalon.Bridge.ConfigStore).Merge(entry, {"api_key": (placeholder)}))
	}
	Set position = 0
	While $ListNext(runners, position, item) {
		Set sc = $$$ADDSC(sc, ..Restart(..#PRODUCTION_"||"_item))
	}
	Quit sc
}

/// Puts the agent class behind the runner item for a test: sets the AgentClass and the AgentAllowList settings (target Adapter) of the
/// item in the stored configuration of the production (Ens.Config.Production, which UpdateProduction applies; an item setting of the
/// class definition cannot be overridden from anywhere else), updates the running production, and waits until every item runs. The
/// class definition of the production is not touched. saved holds what the item had ({"agentClassSet","agentClass","allowListSet",
/// "allowList"}), for RestoreAgent; it is "" when the item's settings were not read, so that there is nothing to restore.
/// THIS CHANGES THE RUNNING PRODUCTION: throwaways and CI only (Rule 21).
ClassMethod UseAgent(item As %String, agentClass As %String, Output saved As %DynamicObject) As %Status
{
	Set saved = ""
	Set record = {}
	Set sc = ..ChangeAgent(item, 1, agentClass, 1, agentClass, record)
	If record.%IsDefined("allowListSet") Set saved = record
	Quit sc
}

/// Puts the item back as saved says (UseAgent): each of the two settings gets its value back, or is removed from the item when it had
/// none, and the running production is updated. A saved value that is not what UseAgent gives is an error and changes nothing.
ClassMethod RestoreAgent(item As %String, saved As %DynamicObject) As %Status
{
	If '$IsObject(saved) || 'saved.%IsDefined("allowListSet") Quit $SYSTEM.Status.Error(5001, "There is nothing to restore: UseAgent saved no settings of "_item)
	Quit ..ChangeAgent(item, saved.agentClassSet, saved.agentClass, saved.allowListSet, saved.allowList)
}

/// Sets (when has is 1) or removes (when 0) the AgentClass and the AgentAllowList setting of the item in the stored configuration
/// (ChangeSettings). When saved is an object, it first holds what the item had of the two settings.
ClassMethod ChangeAgent(item As %String, hasClass As %Boolean, agentClass As %String, hasAllow As %Boolean, allowList As %String, saved As %DynamicObject = "") As %Status [ Private ]
{
	Quit ..ChangeSettings(item, $ListBuild($ListBuild("Adapter", "AgentClass", hasClass, agentClass, "agentClass"), $ListBuild("Adapter", "AgentAllowList", hasAllow, allowList, "allowList")), saved)
}

/// Changes settings of the item in the stored configuration, saves the production, updates the running one and waits for every item
/// to run. changes is a list of $ListBuild(target, name, has, value, key): the setting is set to the value when has is 1 and removed
/// when it is 0. When saved is an object, it first holds what the item had of each setting, under its key (ReadSetting).
ClassMethod ChangeSettings(item As %String, changes As %List, saved As %DynamicObject = "") As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
		If '$IsObject(production) {
			Set sc = $SYSTEM.Status.Error(5001, "The stored configuration of "_..#PRODUCTION_" cannot be opened")
		} Else {
			Set config = production.FindItemByConfigName(item, .sc)
		}
		If $$$ISOK(sc) && '$IsObject(config) Set sc = $SYSTEM.Status.Error(5001, ..#PRODUCTION_" has no item "_item)
		If $$$ISOK(sc) {
			If $IsObject(saved) {
				Set position = 0
				While $ListNext(changes, position, change) {
					Do ..ReadSetting(config, $List(change, 2), saved, $List(change, 5), $List(change, 1))
				}
			}
			Set position = 0
			While $ListNext(changes, position, change) {
				Do ..PutSetting(config, $List(change, 2), $List(change, 3), $List(change, 4), $List(change, 1))
			}
			Set sc = production.%Save()
		}
		If $$$ISOK(sc) Set sc = ##class(Ens.Director).UpdateProduction(60)
		If $$$ISOK(sc) && '..WaitAllRun() Set sc = $SYSTEM.Status.Error(5001, "Not every item of "_..#PRODUCTION_" runs "_..#WAITSECONDS_" seconds after "_item_" was changed: "_##class(OcuTalon.Install.Step.Production).NotRunning())
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Records in saved whether the item has the setting of the target (key with "Set" added) and its value (key).
ClassMethod ReadSetting(config As Ens.Config.Item, name As %String, saved As %DynamicObject, key As %String, target As %String = "Adapter") [ Private ]
{
	Set setting = config.FindSettingByName(name, target)
	Do saved.%Set(key _ "Set", $IsObject(setting), "boolean")
	Do saved.%Set(key, $Select($IsObject(setting): setting.Value, 1: ""))
}

/// Sets the setting of the target on the item to the value, or removes the setting when has is 0.
ClassMethod PutSetting(config As Ens.Config.Item, name As %String, has As %Boolean, value As %String, target As %String = "Adapter") [ Private ]
{
	Set setting = config.FindSettingByName(name, target)
	If has {
		If '$IsObject(setting) {
			Set setting = ##class(Ens.Config.Setting).%New()
			Set setting.Target = target
			Set setting.Name = name
			Do config.Settings.Insert(setting)
		}
		Set setting.Value = value
	} ElseIf $IsObject(setting) {
		For i = config.Settings.Count():-1:1 {
			If (config.Settings.GetAt(i).Name = name) && (config.Settings.GetAt(i).Target = target) Do config.Settings.RemoveAt(i)
		}
	}
}

/// Puts one setting of an item for a test: sets the setting of the target (Adapter or Host) on the item in the stored configuration of the
/// production (as UseAgent does), updates the running production and waits until every item runs. saved holds what the item had
/// ({"target","name","valueSet","value"}), for RestoreItemSetting; it is "" when the item's setting was not read, so that there is nothing
/// to restore. THIS CHANGES THE RUNNING PRODUCTION: throwaways and CI only (Rule 21).
ClassMethod UseItemSetting(item As %String, target As %String, name As %String, value As %String, Output saved As %DynamicObject) As %Status
{
	Set saved = ""
	Set record = {"target": (target), "name": (name)}
	Set sc = ..ChangeSetting(item, target, name, 1, value, record)
	If record.%IsDefined("valueSet") Set saved = record
	Quit sc
}

/// Puts the item's setting back as saved says (UseItemSetting): the setting gets its value back, or is removed from the item when it had
/// none, and the running production is updated. A saved value that UseItemSetting did not give is an error and changes nothing.
ClassMethod RestoreItemSetting(item As %String, saved As %DynamicObject) As %Status
{
	If '$IsObject(saved) || 'saved.%IsDefined("valueSet") Quit $SYSTEM.Status.Error(5001, "There is nothing to restore: UseItemSetting saved no setting of "_item)
	Quit ..ChangeSetting(item, saved.target, saved.name, saved.valueSet, saved.value)
}

/// Sets (when has is 1) or removes (when 0) one setting of the target on the item in the stored configuration (ChangeSettings). When
/// saved is an object, it first holds what the item had of the setting.
ClassMethod ChangeSetting(item As %String, target As %String, name As %String, has As %Boolean, value As %String, saved As %DynamicObject = "") As %Status [ Private ]
{
	Quit ..ChangeSettings(item, $ListBuild($ListBuild(target, name, has, value, "value")), saved)
}

/// The id of the System Default Settings row of a setting of an item of the active production.
ClassMethod DefaultId(item As %String, setting As %String) As %String
{
	Quit ##class(Ens.Director).GetActiveProductionName()_"||"_item_"||*||"_setting
}

/// What the System Default Settings row of the setting of the item (a host or adapter setting of the active production) holds now,
/// for RestoreDefault: $ListBuild(item, setting, existed, value, description) ($ListBuild(item, setting, 0) when there is no row).
ClassMethod SnapshotDefault(item As %String, setting As %String) As %List
{
	Set id = ..DefaultId(item, setting)
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit $ListBuild(item, setting, 0)
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Quit $ListBuild(item, setting, 1, row.SettingValue, row.Description)
}

/// Writes the System Default Settings row of the setting of the item of the active production. Saving a row checks the value against
/// the datatype of the setting and, for a provider configuration, expands it, so a value that is none (x, 1,5, $5, text that is not JSON or
/// a placeholder of an unset variable) cannot be saved: SQL then writes the row, and checks nothing. That is how such a value can reach the
/// item (a hand-edited global, an import). The status is the first error. Call SnapshotDefault first.
ClassMethod PutDefault(item As %String, setting As %String, value As %String) As %Status
{
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Set description = "Written by a test; the test deletes it."
	Set sc = ##class(OcuTalon.Install.Step.Production).WriteDefault(production, item, setting, value, description)
	If $$$ISERR(sc) {
		Set id = ..DefaultId(item, setting)
		If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens_Config.DefaultSettings SET SettingValue = ?, Description = ? WHERE ID = ?", value, description, id)
		} Else {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Config.DefaultSettings (ProductionName, ItemName, HostClassName, SettingName, SettingValue, Description) VALUES (?, ?, '*', ?, ?, ?)", production, item, setting, value, description)
		}
		If result.%SQLCODE < 0 {
			Set sc = $$$ERROR($$$GeneralError, "The row of "_setting_" cannot be set to '"_value_"': "_result.%Message)
		} Else {
			Set sc = $$$OK
		}
	}
	Quit sc
}

/// Puts the row of a snapshot back: the row is deleted, and written again when it existed. The status is the error of the write.
ClassMethod RestoreDefault(saved As %List) As %Status
{
	Set item = $List(saved, 1)
	Set setting = $List(saved, 2)
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..DefaultId(item, setting))
	If '$List(saved, 3) Quit $$$OK
	Quit ##class(OcuTalon.Install.Step.Production).WriteDefault(##class(Ens.Director).GetActiveProductionName(), item, setting, $List(saved, 4), $List(saved, 5))
}

/// Adds the snapshot of the System Default Settings row of the setting of the item (SnapshotDefault) to saved, a list of snapshots, unless
/// saved already holds one of the same row, so that RestoreDefaults puts the row back as it was before a test first wrote it.
ClassMethod RememberDefault(ByRef saved As %List, item As %String, setting As %String)
{
	Set saved = $Get(saved)
	Set known = 0
	Set position = 0
	While $ListNext(saved, position, one) {
		If ($List(one, 1) = item) && ($List(one, 2) = setting) Set known = 1
	}
	If 'known Set saved = saved _ $ListBuild(..SnapshotDefault(item, setting))
}

/// Puts back every row of saved, a list of snapshots (RememberDefault), with RestoreDefault, in order. The status is the first error.
ClassMethod RestoreDefaults(saved As %List) As %Status
{
	Set first = $$$OK
	Set position = 0
	While $ListNext(saved, position, one) {
		Set sc = ..RestoreDefault(one)
		If $$$ISERR(sc) && $$$ISOK(first) Set first = sc
	}
	Quit first
}

/// Changes the bridge timer for a test through Timeouts.Apply of OcuTalon.Production, as the product does: the TimerSeconds row of Decide, the
/// timeouts of every runner's entry, and new jobs for Decide and the runners (the status is Apply's, so the error of a restart that did not
/// finish too). saved says what RestoreTimer needs: $ListBuild(the rows before, the timer before). It is set before Apply is called, so that
/// RestoreTimer puts back whatever Apply did. THIS CHANGES THE RUNNING PRODUCTION: throwaways and CI only (Rule 21).
ClassMethod UseTimer(timer As %Integer, Output saved As %List) As %Status
{
	Set saved = ""
	Set rows = ""
	Do ..RememberDefault(.rows, "Decide", "TimerSeconds")
	Set previous = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide", .sc)
	If $$$ISERR(sc) Quit sc
	Set saved = $ListBuild(rows, previous)
	Quit ##class(OcuTalon.Bridge.Timeouts).Apply(timer, ..#PRODUCTION)
}

/// Puts the timer back as UseTimer found it: Timeouts.Apply with the earlier timer (the entries and the jobs again), and then the TimerSeconds row as it
/// was, deleted when there was none (RestoreDefaults). The status is the first error. Nothing to restore (saved is "") is OK.
ClassMethod RestoreTimer(saved As %List) As %Status
{
	If $Get(saved) = "" Quit $$$OK
	Set sc = ##class(OcuTalon.Bridge.Timeouts).Apply($List(saved, 2), ..#PRODUCTION)
	Set restored = ..RestoreDefaults($List(saved, 1))
	Quit $Select($$$ISERR(sc): sc, 1: restored)
}

/// The rows of the event log after the mark (EventMark) of Type 2 (error) or 6 (alert), as a list of "<type>: <item>: <text>" (the text
/// cut to 200 characters), oldest first. A start with no key writes none (FR-38). A statement that fails gives one row that says so,
/// never an empty list.
ClassMethod ErrorRows(mark As %Integer) As %List
{
	Set rows = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Type, ConfigName, SUBSTRING(Text, 1, 200) FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 6) ORDER BY ID", mark)
	If result.%SQLCODE < 0 Quit $ListBuild("SQL "_result.%SQLCODE_": "_result.%Message)
	While result.%Next() {
		Set rows = rows _ $ListBuild(result.%GetData(1)_": "_result.%GetData(2)_": "_result.%GetData(3))
	}
	Quit rows
}

/// The calls that the shared mode of OcuTalon.Test.Bridge.ProbeSink recorded in ^OcuTalonTest("ProbeSink","calls") (the mode is on while
/// ^OcuTalonTest("ProbeSink","shared") is 1, and a sink class that runs in a production job is the only way to see its calls), oldest
/// first, as a dynamic array of {"type","ownerRef","payload","rowExists","markExists"}; payload is the JSON text. A type, when given, keeps
/// the calls of that event type.
ClassMethod SinkCalls(type As %String = "") As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("ProbeSink", "calls", n))
		Quit:n=""
		Set call = ^OcuTalonTest("ProbeSink", "calls", n)
		If (type '= "") && ($List(call, 1) '= type) Continue
		Do calls.%Push({"type": ($List(call, 1)), "ownerRef": ($List(call, 2)), "payload": ($List(call, 3)), "rowExists": ($List(call, 4)), "markExists": ($List(call, 5))})
	}
	Quit calls
}

/// Waits until the runner item has taken up every message that was sent to it and has answered one of its own (QA, Story 1.6): the queue of
/// the item is empty (a poll, up to SENDSECONDS, because a request of Decide's that is still in the queue has not been sent to the model yet),
/// then a ToolInventory request, which makes no model request and writes no row, is answered. A runner has a pool of 1, so its one job
/// handles the messages one after the other: when the answer is back, the job has finished any request that it took before, and that
/// request has reached the mock (its log) or failed. A test that asserts that nothing reached the mock calls this first; without it the
/// read of the log can come before a request that Decide sent could have arrived. The status is that of the ToolInventory request: an
/// error for a runner with no key, whose answer still shows that the job is free; or an error when the queue stays full.
ClassMethod Drain(item As %String) As %Status
{
	Set deadline = $ZHorolog + ..#SENDSECONDS
	While (##class(Ens.Queue).GetCount(item) > 0) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	If ##class(Ens.Queue).GetCount(item) > 0 Quit $SYSTEM.Status.Error(5001, "The queue of "_item_" still held messages "_..#SENDSECONDS_" seconds later")
	Quit ..Send(item, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .response)
}

/// What is wrong with the answer of a fallback and the Decision row that records it, as a text of problems joined by "; ", or "" when
/// nothing is (QA, Story 1.6; AD-8, AD-26, AD-28, AD-30): the guarantees of every fallback in one place, so that no test leaves one out.
///   - the answer is a DecisionResponse for a decide or diagnose request and a Reply for a turn, with the outcome tellnow, Fallback true and
///     the reason, and no reasons, confidence or payload; a Reply also has no text, host data, steps, failure text or finish reason, and no
///     flag of the runner's set that Decide does not carry (SessionRotated, SessionBroken, Busy; Tainted and ToolsRun are the runner's own and
///     are not judged here: a fallback after a tool ran says so);
///   - the XML of the answer, which Visual Trace shows, holds all three of <Outcome>tellnow</Outcome>, <Fallback>true</Fallback> and
///     <FallbackReason>the reason</FallbackReason>;
///   - the row exists, is of the kind, and holds the outcome tellnow, Fallback 1, the reason, no reasons, confidence or payload, and the
///     DecisionRef of the answer.
ClassMethod FallbackProblems(answer As %RegisteredObject, row As %RegisteredObject, kind As %String, reason As %String) As %String
{
	Set problems = ""
	Set class = $Select(kind = "turn": "OcuTalon.Bridge.Msg.Reply", 1: "OcuTalon.Bridge.Msg.DecisionResponse")
	If '$IsObject(answer) || (answer.%ClassName(1) '= class) {
		Set problems = problems _ $ListBuild("the answer is not a "_class_": "_$Select($IsObject(answer): answer.%ClassName(1), 1: "none"))
	} Else {
		If answer.Outcome '= "tellnow" Set problems = problems _ $ListBuild("the outcome of the answer is '"_answer.Outcome_"', not tellnow")
		If 'answer.Fallback Set problems = problems _ $ListBuild("Fallback of the answer is not true")
		If answer.FallbackReason '= reason Set problems = problems _ $ListBuild("the reason of the answer is '"_answer.FallbackReason_"', not "_reason)
		If (answer.Reasons '= "") || (answer.Confidence '= "") Set problems = problems _ $ListBuild("the answer has reasons or a confidence")
		If kind = "turn" {
			If (answer.Text _ answer.HostData _ answer.Steps _ answer.FailureText _ answer.FinishReason) '= "" Set problems = problems _ $ListBuild("the Reply has a text, host data, steps, a failure text or a finish reason")
			If (answer.SessionRotated _ answer.SessionBroken _ answer.Busy) '= "000" Set problems = problems _ $ListBuild("the Reply has a flag of the runner's set")
		} Else {
			If answer.Payload '= "" Set problems = problems _ $ListBuild("the DecisionResponse has a payload")
		}
		If $$$ISERR(answer.XMLExportToString(.xml)) {
			Set problems = problems _ $ListBuild("the answer cannot be exported as XML")
		} Else {
			For piece = "<Outcome>tellnow</Outcome>", "<Fallback>true</Fallback>", ("<FallbackReason>"_reason_"</FallbackReason>") {
				If xml '[ piece Set problems = problems _ $ListBuild("the XML of the answer lacks "_piece)
			}
		}
	}
	If '$IsObject(row) {
		Set problems = problems _ $ListBuild("no Decision row is recorded")
	} Else {
		If row.Kind '= kind Set problems = problems _ $ListBuild("the row is of kind '"_row.Kind_"'")
		If row.Outcome '= "tellnow" Set problems = problems _ $ListBuild("the outcome of the row is '"_row.Outcome_"', not tellnow")
		If row.Fallback '= 1 Set problems = problems _ $ListBuild("Fallback of the row is not 1")
		If row.FallbackReason '= reason Set problems = problems _ $ListBuild("the reason of the row is '"_row.FallbackReason_"', not "_reason)
		If (row.Reasons _ row.Confidence _ row.Payload) '= "" Set problems = problems _ $ListBuild("the row keeps reasons, a confidence or a payload")
		If $IsObject(answer) && (row.Ref '= answer.DecisionRef) Set problems = problems _ $ListBuild("the Ref of the row is not the DecisionRef of the answer")
	}
	Quit $ListToString(problems, "; ")
}

/// The first entry of FindRequests, or "".
ClassMethod FindRequest(entries As %DynamicArray, ref As %String) As %DynamicObject
{
	Quit ..FindRequests(entries, ref).%Get(0)
}

/// Every entry of the mock's log (Test.Contract.Mock.LogSince) that is a POST to /v1/messages and holds the reference in its text,
/// in the order of the log, as a dynamic array.
ClassMethod FindRequests(entries As %DynamicArray, ref As %String) As %DynamicArray
{
	Set found = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && $Find(entry.%ToJSON(), ref) Do found.%Push(entry)
	}
	Quit found
}

/// The effort of a logged request: request.output_config.effort, or "" when the request has none.
ClassMethod Effort(logged As %DynamicObject) As %String
{
	If logged.request.%GetTypeOf("output_config") '= "object" Quit ""
	Quit logged.request."output_config".effort
}

/// The cache marker of a logged block (the system block or a tool): its cacheControl as JSON, such as {"type":"ephemeral"}, or ""
/// when the block carries none.
ClassMethod CacheMark(block As %DynamicObject) As %String
{
	If block.%GetTypeOf("cacheControl") '= "object" Quit ""
	Quit block.cacheControl.%ToJSON()
}

/// 1 when the dynamic array of names holds the name.
ClassMethod Has(names As %DynamicArray, name As %String) As %Boolean
{
	Set has = 0
	Set iterator = names.%GetIterator()
	While iterator.%GetNext(, .value) {
		If value = name {
			Set has = 1
			Quit
		}
	}
	Quit has
}

/// The number of warnings (type 3) that the method of the class logged after the event-log mark (EventMark) whose text holds every
/// string of needles, a $ListBuild; an empty list counts every warning of that method.
ClassMethod Warnings(mark As %Integer, class As %String, method As %String, needles As %List = "") As %Integer
{
	Set found = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ? AND SourceMethod = ?", mark, class, method)
	While result.%Next() {
		Set text = result.%GetData(1)
		Set all = 1
		Set position = 0
		While $ListNext(needles, position, needle) {
			If '(text [ needle) Set all = 0
		}
		Set found = found + all
	}
	Quit found
}

/// The ids of the Usage rows whose ItemId or DecisionRef (the column) is the value, oldest first, as a dynamic array.
ClassMethod UsageIds(column As %String, value As %String) As %DynamicArray
{
	Set ids = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE "_$Select(column = "ItemId": "ItemId", 1: "DecisionRef")_" = ? ORDER BY ID", value)
	While result.%Next() {
		Do ids.%Push(result.%GetData(1))
	}
	Quit ids
}

/// Saves a fixture Usage row of the DecisionRef with the model, the token counts, the cost ("" for an unknown cost), the UTC time
/// it was recorded at ("" for none) and the owner, and returns the status of the save.
ClassMethod AddUsage(ref As %String, model As %String, input As %Integer, completion As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String, recordedAt As %String = "", owner As %String = "instance") As %Status
{
	Set row = ##class(OcuTalon.Bridge.Data.Usage).%New()
	Set row.DecisionRef = ref
	Set row.OwnerRef = owner
	Set row.Model = model
	Set row.InputTokens = input
	Set row.OutputTokens = completion
	Set row.CacheReadTokens = cacheRead
	Set row.CacheWriteTokens = cacheWrite
	Set row.CostUSD = cost
	Set row.RecordedAt = recordedAt
	Quit row.%Save()
}

/// The total fields of a Decision row, a DecisionResponse or a Reply, in the order of Result and joined by |: InputTokens,
/// OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD, Model, AgentStepCount and, when withDuration is 1 or not given,
/// DurationMs.
ClassMethod Totals(object As %RegisteredObject, withDuration As %Boolean = 1) As %String
{
	Set text = object.InputTokens_"|"_object.OutputTokens_"|"_object.CacheReadTokens_"|"_object.CacheWriteTokens_"|"_object.CostUSD_"|"_object.Model_"|"_object.AgentStepCount
	Quit text_$Select(withDuration: "|"_object.DurationMs, 1: "")
}

}
