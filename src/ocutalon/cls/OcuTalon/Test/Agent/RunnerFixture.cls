/// What the tests that drive the agent runners share (Story 1.2; AD-6, AD-7, AD-19). THESE HELPERS RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21): they act on the running OcuTalon.Production and read the CI mock's log.
///   - Running, RunningReason, Restart and Jobs: the state of the production and of the jobs of its items;
///   - Send: a message to a production item through the adapterless service ApprovalStartIn, as a caller of the runners will;
///   - PointKeys and RestoreKeys: CI starts with no model key on purpose, so the live tests point the entry of each runner at
///     OCUTALON_MOCK_KEY_HEADER, a non-secret CI-only variable (value 1), through ConfigStore.Merge, and put the entries back to
///     the placeholder of the Provider step afterwards. Both restart the runners, because a runner builds its agent once;
///   - GuardReason: "" only when the environment is the CI override's (the mock's base URL and the mock-key switch), so that no
///     test can send a request to a real model API;
///   - FindRequest, FindRequests, Effort, CacheMark and Has: read the entries of the mock's log (Test.Contract.Mock.LogSince).
/// No literal key is written anywhere.
Class OcuTalon.Test.Agent.RunnerFixture
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The runners of the production, in the order of the production.
Parameter RUNNERS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// The longest to wait for every item to run, in seconds.
Parameter WAITSECONDS = 30;

/// The longest a sent message waits for its answer, in seconds.
Parameter SENDSECONDS = 90;

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

/// "" only when OCUTALON_MODEL_BASE_URL is the mock's base URL and OCUTALON_MOCK_KEY_HEADER is 1 (Test.Contract.Mock checks
/// both). Otherwise the reason.
ClassMethod GuardReason() As %String
{
	Set sc = ##class(OcuTalon.Test.Contract.Mock).CheckBaseUrl($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"))
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Set sc = ##class(OcuTalon.Test.Contract.Mock).CheckMockKeyFlag($SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"))
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
	Quit ""
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

/// Sends a Request of the kind and provenance to the target, with the text and a fresh reference of its own in the input, and
/// reads the mock's log for it. reply is the answer (a Reply), or ""; requests holds the entries of the mock's log, since the
/// send, for the requests that carry the reference (a turn with a tool call makes more than one); ref is the reference. The
/// status is the one Send gives.
ClassMethod Ask(target As %String, kind As %String, provenance As %String, text As %String, Output reply As %Persistent, Output requests As %DynamicArray, Output ref As %String) As %Status
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.Input = text_" (test "_ref_")"
	Set requests = []
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = ..Send(target, request, .reply)
	If $$$ISOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Set requests = ..FindRequests(entries, ref)
	Quit sc
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

/// Merges the api_key into the entry of each runner, then restarts the runners one after the other.
ClassMethod SetKeys(placeholder As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "ProviderConfig", .status)
		If $$$ISERR(status) {
			Set sc = $$$ADDSC(sc, status)
			Continue
		}
		Set entry = $Piece($Piece(config, "@{config:", 2), "}", 1)
		If entry = "" {
			Set sc = $$$ADDSC(sc, $SYSTEM.Status.Error(5001, item_"'s ProviderConfig does not name a Config Store entry"))
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

/// The first entry of the mock's log (Test.Contract.Mock.LogSince) that is a POST to /v1/messages and holds the reference in its
/// text, or "".
ClassMethod FindRequest(entries As %DynamicArray, ref As %String) As %DynamicObject
{
	Set request = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && $Find(entry.%ToJSON(), ref) {
			Set request = entry
			Quit
		}
	}
	Quit request
}

/// Every such entry, in the order of the log, as a dynamic array.
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

}
