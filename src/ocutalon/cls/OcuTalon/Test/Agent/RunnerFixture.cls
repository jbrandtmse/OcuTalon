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
///   - EventMark, EventRows and Warnings: the rows of the event log after a mark, and the warnings that one method logged after it;
///   - UsageIds, AddUsage and Totals (Story 1.4): the Usage rows of an item or a decision, a fixture Usage row, and the total fields
///     of a Decision row or an answer, which the tests of Test.Agent and Test.Bridge share.
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
/// answer. The status is the one the sender gets, the error of a runner included. response is the answer, or "".
ClassMethod Send(target As %String, message As %Persistent, Output response As %Persistent) As %Status
{
	Set response = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("ApprovalStartIn", .service)
	If $$$ISERR(sc) Quit sc
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

/// The headers of the session that the item named source sent, oldest first, as a dynamic array of {"target","bodyClass","bodyId"}.
ClassMethod Headers(sessionId As %Integer, source As %String) As %DynamicArray
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID", sessionId, source)
	While result.%Next() {
		Do headers.%Push({"target": (result.%GetData(1)), "bodyClass": (result.%GetData(2)), "bodyId": (result.%GetData(3))})
	}
	Quit headers
}

/// The session of the header that carries the message body, or "": the session that holds a response, as Visual Trace shows it.
ClassMethod SessionOf(body As %Persistent) As %Integer
{
	If '$IsObject(body) Quit ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? ORDER BY ID", $ClassName(body), body.%Id())
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

/// The highest id of the message headers: the mark that SessionSince reads from.
ClassMethod HeaderMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The session of the first header after the mark that is addressed to the item, or "".
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
