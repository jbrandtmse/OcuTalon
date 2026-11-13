/// The fixtures that the tests of the governed proxy inside the production's own runner job share (Story 22.3 QA, extended by Story 22.4; AD-6, AD-10, AD-19, AD-21). It is no test
/// case (it has no Test method): OcuTalon.Test.Mcp.ProxyJob and OcuTalon.Test.Mcp.Approval extend it. THE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need the running
/// production and the CI mock (RunnerFixture ReadyReason), they point the key entry of ChatAgent at the CI mock key variable (PointKeys) and put it back, and they make the fixtures of
/// one MCP server named zzmcp, the name that the mock's scenarios use: the row, the Use permission on its resource, the loopback MCP mock that checks a header, a wallet collection
/// and secret (a random value of the run), the Config Store entry AI.MCP.OcuTalon_zzmcp whose header is a secret:// reference to it, and the two tool rows (zz_lookup read-only,
/// zz_delete_ticket risky). OnAfterOneTest removes them whether the test passed or failed, asserts that none is left and that the secret shows in no event-log row, key-scan store or
/// audit entry.
Class OcuTalon.Test.Mcp.JobFixture Extends %UnitTest.TestCase [ Abstract ]
{

Parameter RUNNER = "ChatAgent";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Mcp.Mock";

Parameter HEADER = "X-Zz-Key";

/// The name of the server that the scenarios name.
Parameter SERVER = "zzmcp";

Property Port As %Integer [ InitialExpression = 0 ];

Property UsedPort As %Integer [ InitialExpression = 0 ];

Property Secret As %String(MAXLEN = "") [ Transient ];

/// 1 when the test pointed the key entry of the runner at the mock key variable and has to put it back.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test sent, whose steps, Decision rows and Usage rows OnAfterOneTest deletes.
Property ItemIds As %List;

Property LogMark As %Integer;

Property AuditMark As %String;

Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Port = 0
	Set ..UsedPort = 0
	Set ..Pointed = 0
	Set ..ItemIds = ""
	Set ..Secret = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "AAA")
	Set ..LogMark = $ClassMethod(..#FIXTURE, "EventMark")
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Pointed {
		Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "RestoreKeys", ..#RUNNER), "the key entry of " _ ..#RUNNER _ " is put back to the placeholder of the Provider step")
		Set ..Pointed = 0
	}
	Do ..Remove()
	Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no fixture behind")
	Do $$$AssertEquals(..Places(..Secret), "", "the secret shows in no log row, no audit entry and no store of the key scan")
	Set ..Secret = ""
	Quit $$$OK
}

/// The ID of the newest row of Ens.MessageHeader, 0 when there is none: the mark of TraceHolds.
ClassMethod HeaderMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	If result.%Next() Quit +result.%GetData(1)
	Quit 0
}

/// Whether the Visual Trace since the mark holds each of the values: one 1 or 0 for each value, in order. The trace is the body of every Ens.MessageHeader row after the mark,
/// read as its XML export (scanned counts the bodies that were read); no value is ever part of an answer or a message.
ClassMethod TraceHolds(mark As %Integer, values As %List, Output scanned As %Integer) As %List [ Private ]
{
	Set scanned = 0
	Set holds = ""
	For i = 1:1:$ListLength(values) Set $List(holds, i) = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? ORDER BY ID", mark)
	While result.%Next() {
		Set class = result.%GetData(1)
		Set id = result.%GetData(2)
		If (class = "") || (id = "") Continue
		Set text = ""
		Try {
			Set body = $ClassMethod(class, "%OpenId", id)
			If $IsObject(body) && body.%Extends("%XML.Adaptor") && $$$ISOK(body.XMLExportToString(.text)) Set scanned = scanned + 1
		} Catch {
			Set text = ""
		}
		For i = 1:1:$ListLength(values) {
			If text [ $List(values, i) Set $List(holds, i) = 1
		}
	}
	Quit holds
}

/// The tool steps of a Reply's steps, as a dynamic array.
Method ToolSteps(steps As %DynamicArray) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind = "tool" Do found.%Push(step)
	}
	Quit found
}

/// The fixtures of the server zzmcp: the mock (that checks the header and the secret), the wallet collection and secret, the entry AI.MCP.OcuTalon_zzmcp whose header names the secret,
/// the row, the Use permission on its resource and the two tool rows (zz_lookup read-only, zz_delete_ticket risky) with the fingerprints of the mock's definitions.
Method Setup() [ Private ]
{
	Do ..Ok($ClassMethod(..#MOCK, "Start", .port, , ..#HEADER, ..Secret), "the mock starts")
	Set ..Port = port
	Set ..UsedPort = port
	Set collection = ..Collection()
	Do ..Ok(##class(%Wallet.Collection).Create(collection, {"EditResource": "%DB_%DEFAULT", "UseResource": "%DB_%DEFAULT"}), "the fixture wallet collection is made")
	Do ..Ok(##class(%Wallet.KeyValue).Create(collection _ ".Key", {"Secret": {"token": (..Secret)}, "RequireTLS": 0, "Usage": "CUSTOM"}), "the fixture wallet secret is made")
	Do ..Ok(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is rebuilt")
	Do ..Ok(##class(%ConfigStore.Configuration).Create("AI", "MCP", "", "OcuTalon_" _ ..#SERVER, {"transport": "remote", "url": ("http://127.0.0.1:" _ port _ "/mcp"), "auth": {"type": "header", "name": (..#HEADER), "value": ("secret://" _ collection _ ".Key#token")}}), "the fixture entry is made")
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = ..#SERVER
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Ok(row.%Save(), "the fixture row " _ ..#SERVER _ " is saved")
	Do ..Ok(##class(OcuTalon.Install.Step.Mcp).Grant(..#SERVER), "and the service role holds the Use permission on its resource")
	Set spec = "mcp:remote:@{config:AI.MCP.OcuTalon_" _ ..#SERVER _ "}"
	Set schema = {"type": "object", "properties": {"id": {"type": "string"}}}
	Do ..Row("zz_lookup", "read-only", ##class(OcuTalon.Bridge.Context).ToolFingerprint(spec, "zz_lookup", "Looks up a ticket.", schema))
	Do ..Row("zz_delete_ticket", "risky", ##class(OcuTalon.Bridge.Context).ToolFingerprint(spec, "zz_delete_ticket", "Deletes a ticket.", schema))
}

/// A tool row of the fixture server with the classification and the fingerprint.
Method Row(tool As %String, classification As %String, fingerprint As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = ..#SERVER
	Set row.Tool = tool
	Set row.Classification = classification
	Set row.Fingerprint = fingerprint
	Do ..Ok(row.%Save(), "the tool row " _ tool _ " is saved")
}

/// Where the value shows ("" when nowhere): the event log after the mark of the test, the stores of the key scan, the audit entries since the mark and the trace.
Method Places(value As %String) As %String [ Private ]
{
	Set places = ""
	If value = "" Quit places
	If ..LogMark = "" Quit "the test set no log mark"
	If $ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, value) Set places = places _ $ListBuild("the event log")
	If $ClassMethod("OcuTalon.Test.Agent.KeyScan", "Find", value) '= "" Set places = places _ $ListBuild("a store of the key scan")
	If ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , value).%Size() Set places = places _ $ListBuild("the audit log")
	If ##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(value) '= "" Set places = places _ $ListBuild("the trace")
	Quit $ListToString(places, ", ")
}

/// The user that the job of the production item runs as, or "" when it has no alive job or the process cannot be read.
ClassMethod JobUser(item As %String) As %String [ Private ]
{
	Set user = ""
	Try {
		Set jobs = ##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)
		If $ListLength(jobs) '= 0 {
			Set process = ##class(%SYS.ProcessQuery).%OpenId($List(jobs, 1))
			If $IsObject(process) Set user = process.UserName
		}
	} Catch {
		Set user = ""
	}
	Quit user
}

Method Collection() As %String [ Private ]
{
	Quit "OcuTalonZzMcpJob"
}

Method Ok(sc As %Status, label As %String) [ Private ]
{
	Do $$$AssertTrue($$$ISOK(sc), label)
}

/// Removes every fixture that this test may have made. Each removal is attempted whatever happened before.
Method Remove() [ Private ]
{
	If ..Port Do $ClassMethod(..#MOCK, "Stop", ..Port), $ClassMethod(..#MOCK, "Forget", ..Port)
	Set ..Port = 0
	Set entry = "AI.MCP.OcuTalon_" _ ..#SERVER
	If ##class(%ConfigStore.Configuration).Exists(entry) Do ##class(%ConfigStore.Configuration).Delete(entry)
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Do ##class(%Wallet.KeyValue).Delete(..Collection() _ ".Key")
	If ##class(%Wallet.Collection).Exists(..Collection()) Do ##class(%Wallet.Collection).Delete(..Collection())
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
	Do ##class(OcuTalon.Install.Step.Mcp).Revoke(..#SERVER)
}

/// What is left of the fixtures, as a text of places ("" when nothing).
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER) Set places = places _ $ListBuild("the row")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
	Do result.%Next()
	If result.%GetData(1) Set places = places _ $ListBuild("the tool rows")
	If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ ..#SERVER) Set places = places _ $ListBuild("the Config Store entry")
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Set places = places _ $ListBuild("the wallet secret")
	If ##class(%Wallet.Collection).Exists(..Collection()) Set places = places _ $ListBuild("the wallet collection")
	If ..UsedPort, $Data(^IRIS.Temp.OcuTalonMcpMock(..UsedPort)) || $ClassMethod(..#MOCK, "Running", ..UsedPort) Set places = places _ $ListBuild("a mock node or job")
	Quit $ListToString(places, ", ")
}

}
