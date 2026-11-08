/// End-to-end tests of the per-session knowledge bases and memories through the Chat agent (Story 19.5; AD-1, AD-4, AD-6, AD-21, AD-31; FR-15, FR-41, FR-42,
/// DW-892, DW-893). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on OcuTalon's Docker image, through the CI environment (the mock's base URL and
/// OCUTALON_MOCK_KEY_HEADER=1). With the public setting onlineDemo on, each test adds its documents for demo visitors (Session rows) through Commands.Submit ->
/// CommandsIn -> DocumentOps as web_user, waits for them to be ready, and drives real turns of the Chat agent through Decide (RunnerFixture.Run) against the CI
/// mock, with the REAL gate, the knowledge base of the turn owner's own table (Docs.TurnTools, named by the TurnToolsClass setting of Decide) and the Embedder
/// worker (no double). Each test reads the Reply's HostData, the mock's log and the tool results the model was given, and removes its sessions, documents,
/// tables, memories and events.
///   - TestTwoVisitors (Integration AC, matrix "Two concurrent sessions"): two visitors add the same runbook text and save the same memory text; turns in the
///     order A, B, A on one ChatAgent job give each only its own document's passages and citations and its own memory (the tool results the model read, HostData
///     citations and HostData memories name only the visitor's own refs), and the turn's model request offers documents;
///   - TestOfferedByOwner (DW-893): a local turn, then a turn of a demo session that has no table, then a local turn again, on one job: documents is offered, not
///     offered, offered; the same job runs all three;
///   - TestDroppedSession: after Docs.DropSession and Memory.DropSession of a visitor, a turn for it is answered without the documents tool, finds none of its
///     memories, and makes no table, class or global.
Class OcuTalon.Test.Docs.SessionTurns Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-doc-sturns";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter RUNNER = "ChatAgent";

Parameter STORE = "OcuTalon.Docs.Store";

Parameter NONE = "None of your documents cover that.";

/// The ItemIds of the turns that the test made.
Property ItemIds As %List;

/// The Refs of the documents that the test made.
Property DocRefs As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The public setting onlineDemo before the tests.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state))
		Merge ^||OcuTalonTestDocsSessionTurns = state
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ##class(OcuTalon.Bridge.Context).End()
	If $ClassMethod(..#FIXTURE, "Running") Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If $ClassMethod(..#FIXTURE, "Running") Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropDocuments()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropDocuments()
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
		Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
		If '$ClassMethod(..#FIXTURE, "KeysAre", placeholder) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
	}
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestDocsSessionTurns
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestDocsSessionTurns
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// Deletes the documents of the sessions of the run with their KB rows (in the table each row names), events and uploads, and the memories of the sessions.
Method DropDocuments() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Document WHERE AddedBy = ?", session)
		While rs.%Next() {
			Set ..DocRefs = ..DocRefs _ $ListBuild(rs.%Get("Ref"))
		}
		Do ##class(OcuTalon.Data.Upload).DropSession(session)
		Do ##class(OcuTalon.Test.Memory.Fixture).Purge(session)
		Do ##class(OcuTalon.Docs).DropSession(session)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = 'document'", session)
	}
	Set position = 0
	While $ListNext(..DocRefs, position, ref) {
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
		Do $ClassMethod(..#STORE, "Remove", ref, $Select($IsObject(row) && (row.KnowledgeBase '= ""): row.KnowledgeBase, 1: $Parameter(..#STORE, "TABLE")))
		If $IsObject(row) {
			Set id = row.%Id()
			Set row = ""
			Do ##class(OcuTalon.Data.Document).%DeleteId(id)
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = 'instance' AND Type = 'document' AND Payload [ ?", """ref"":""" _ ref _ """")
	}
	Set ..DocRefs = ""
}

/// 1 when the production is ready, this is OcuTalon's image, and the entries of the runners point at the CI mock key variable. Otherwise the test fails with the
/// reason or records the skip, and quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If ..Pointed Quit 1
	Set ..Pointed = 1
	Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	Quit $$$ISOK(sc)
}

/// Adds a Markdown document as web_user through Commands.Submit and waits for it to be ready (up to 120 s); its Ref, or "" with the assertions failed.
Method AddDocument(session As %String, name As %String, text As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Do stream.Write($ZConvert(text, "O", "UTF8"))
	Do stream.Rewind()
	Set up = ##class(OcuTalon.Data.Upload).Put(session, stream, .sc)
	Do $$$AssertStatusOK(sc, "the upload is stored")
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.SessionRef = session
	Set command.Name = name
	Set command.ContentType = "markdown"
	Set command.UploadRef = up
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertEquals($Select($IsObject(result): result.Ok _ "|" _ result.Outcome, 1: "none"), "1|added", name _ " is added through CommandsIn and DocumentOps")
	If '$IsObject(result) || (result.Ref = "") Quit ""
	Set ref = result.Ref
	Set ..DocRefs = ..DocRefs _ $ListBuild(ref)
	Set deadline = $ZHorolog + 120
	Set ready = 0
	While $ZHorolog < deadline {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
		Set state = $Select(rs.%Next(): rs.%Get("State"), 1: "")
		If state = "ready" Set ready = 1 Quit
		If state = "failed" Quit
		Hang 0.5
	}
	Do $$$AssertEquals(ready, 1, name _ " is ready")
	Quit $Select(ready: ref, 1: "")
}

/// Sends a turn of the owner through Decide (RunnerFixture.Run) and reads the mock's log for it: request is the Request, answer the Reply, session the session of
/// the request and requests the entries of the mock's log for the turn, in order.
Method Turn(text As %String, owner As %String, Output request As OcuTalon.Bridge.Msg.Request, Output answer As %Persistent, Output session As %Integer, Output requests As %DynamicArray) As %Status [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", text, .ref, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .answer, .session)
	Set requests = []
	If $$$ISOK($ClassMethod(..#MOCK, "LogSince", mark, .entries)) Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Quit sc
}

/// The members of the Reply's HostData as a dynamic object.
ClassMethod Data(answer As %Persistent) As %DynamicObject [ Private ]
{
	Quit $Select($IsObject(answer) && (answer.HostData '= ""): {}.%FromJSON(answer.HostData), 1: {})
}

/// The newest tool result of the second logged request, as a dynamic value, or "".
Method ToolResult(requests As %DynamicArray) As %DynamicAbstractObject [ Private ]
{
	Do $$$AssertTrue(requests.%Size() '< 2, "the mock logged the model's second request: " _ requests.%Size())
	If requests.%Size() < 2 Quit ""
	Set results = $ClassMethod(..#FIXTURE, "ToolResults", requests.%Get(1))
	Do $$$AssertTrue($ListLength(results) '< 1, "which carries a tool result")
	If $ListLength(results) < 1 Quit ""
	Quit {}.%FromJSON($List(results, $ListLength(results)))
}

/// The steps of Visual Trace: model, then a tool step and a model step for each label and tool, ok, in the session of the decision.
Method AssertSteps(answer As %Persistent, session As %Integer, labels As %List, tools As %List) [ Private ]
{
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "StepProblems", answer.DecisionRef, session, labels, tools, ..#RUNNER), "", "the steps of the turn are right")
}

/// 1 when the runner's job that was alive before the turns is alive now.
Method SameJob(job As %Integer, what As %String) [ Private ]
{
	Do $$$AssertTrue($ListFind($ClassMethod(..#FIXTURE, "Jobs", ..#RUNNER), job) > 0, "the " _ ..#RUNNER _ " job " _ job _ " is alive " _ what)
}

/// The Markdown runbook of the story: an intro, the three steps of the rotation and the queue.
ClassMethod Runbook() As %String [ Private ]
{
	Set lf = $Char(10)
	Quit "# Results runbook" _ lf _ "This runbook covers the Results production, the lab results feed that the clinic reads every morning." _ lf _ lf _ "## Rotating the certificate" _ lf _ "1. Stop the item named Results.Sender." _ lf _ "2. Install the new certificate in the SSL configuration named ResultsClient, then restart the item." _ lf _ "3. Send one test result and write the new expiry date in the on-call log." _ lf _ lf _ "## Clearing the queue" _ lf _ "When the Results queue keeps growing, read why the message at its head fails, fix the cause and resend it." _ lf
}

Method TestTwoVisitors()
{
	If '..Ready() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set a = ..Session("a")
	Set b = ..Session("b")
	Set refA = ..AddDocument(a, "Results runbook.md", ..Runbook())
	Set refB = ..AddDocument(b, "Results runbook.md", ..Runbook())
	If (refA = "") || (refB = "") Quit
	Do $$$AssertTrue(refA '= refB, "each visitor's document has a Ref of its own")
	Set text = "the Results partner's contact is Lee"
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(a, "zzSessMemA00000000001", text, now), "visitor A's memory is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(b, "zzSessMemB00000000001", text, now), "and visitor B's, with the same text")
	Set jobs = $ClassMethod(..#FIXTURE, "Jobs", ..#RUNNER)
	Do $$$AssertTrue($ListLength(jobs) '< 1, "the " _ ..#RUNNER _ " item has a job")
	Set job = $ListGet(jobs, 1)
	For visitor = a, b, a {
		Set own = $Select(visitor = a: refA, 1: refB)
		Set other = $Select(visitor = a: refB, 1: refA)
		Set name = $Select(visitor = a: "A", 1: "B")
		Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-runbook]]", visitor, .request, .answer, .turnSession, .requests)
		Do $$$AssertStatusOK(sc, "Decide answers the documents turn of " _ name)
		If '$IsObject(answer) Quit
		Do $$$AssertEquals(answer.Text, "The CI mock answered from the Results runbook: Rotating the certificate.", name _ ": the reply is the text of the scenario")
		Do $$$AssertEquals(..Offered(requests), 1, name _ ": the model request offers documents")
		Set result = ..ToolResult(requests)
		If $IsObject(result) {
			Do $$$AssertEquals(..Holds(result, own) > 0, 1, name _ ": the passages the model read are the visitor's own document's")
			Do $$$AssertEquals(..Holds(result, other), 0, name _ ": and none is the other visitor's")
		}
		Set citations = ..Data(answer).citations
		Set foreign = 0, cited = 0
		If $IsObject(citations) {
			Set iterator = citations.%GetIterator()
			While iterator.%GetNext(, .entry) {
				Set cited = cited + 1
				If entry.documentRef '= own Set foreign = foreign + 1
			}
		}
		Do $$$AssertEquals((cited > 0) _ "|" _ foreign, "1|0", name _ ": HostData.citations names only the visitor's own document")
		Do ..SameJob(job, "after the documents turn of " _ name)
		Set mine = $Select(visitor = a: "zzSessMemA00000000001", 1: "zzSessMemB00000000001")
		Set sc = ..Turn("Who is the contact? [[mock:memory-recall-meaning]]", visitor, .request, .answer, .turnSession, .requests)
		Do $$$AssertStatusOK(sc, "Decide answers the memory turn of " _ name)
		If '$IsObject(answer) Quit
		Set memories = ..Data(answer).memories
		Set refs = ""
		If $IsObject(memories) {
			Set iterator = memories.%GetIterator()
			While iterator.%GetNext(, .memory) {
				Set refs = refs _ $Select(refs '= "": ",", 1: "") _ memory.memoryRef
			}
		}
		Do $$$AssertEquals(refs, mine, name _ ": HostData.memories holds only the visitor's own memory")
		Set result = ..ToolResult(requests)
		If $IsObject(result) && $IsObject(result.memories) {
			Set found = ""
			Set iterator = result.memories.%GetIterator()
			While iterator.%GetNext(, .memory) {
				Set found = found _ $Select(found '= "": ",", 1: "") _ memory.ref
			}
			Do $$$AssertEquals(found, mine, name _ ": and so does the search_memories result the model read")
		}
	}
}

Method TestOfferedByOwner()
{
	If '..Ready() Quit
	Set jobs = $ClassMethod(..#FIXTURE, "Jobs", ..#RUNNER)
	Set job = $ListGet(jobs, 1)
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table of the install is there")
	Set sc = ..Turn("Where is the build server? [[mock:recall-ask]]", "", .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "a local turn is answered")
	Do $$$AssertEquals(..Offered(requests), 1, "and documents is offered")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set a = ..Session("a")
	Set sc = ..Turn("Where is the build server? [[mock:recall-ask]]", a, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "a turn of a demo session with no table is answered")
	Do $$$AssertTrue(requests.%Size() > 0, "and sends a model request")
	Do $$$AssertEquals(..Offered(requests), 0, "and documents is not offered")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "nothing was made for the session")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set sc = ..Turn("Where is the build server? [[mock:recall-ask]]", "", .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "a local turn again is answered")
	Do $$$AssertEquals(..Offered(requests), 1, "and documents is offered again")
	Do ..SameJob(job, "after the three turns")
}

Method TestDroppedSession()
{
	If '..Ready() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set a = ..Session("a")
	Set ref = ..AddDocument(a, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(a, "zzSessMemA00000000002", "the Results partner's contact is Lee", ##class(OcuTalon.Data.Time).NowUtc()), "the visitor's memory is stored")
	Set sc = ..Turn("Where is the build server? [[mock:recall-ask]]", a, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(..Offered(requests), 1, "control: documents is offered while the visitor has a table")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "the visitor's documents are dropped")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(a), "and its memories")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "nothing of the visitor is left")
	Set sc = ..Turn("Who is the contact? [[mock:memory-recall-meaning]]", a, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "a turn for the dropped visitor is answered")
	Do $$$AssertTrue(requests.%Size() > 0, "and sends a model request")
	Do $$$AssertEquals(..Offered(requests), 0, "without the documents tool")
	Set memories = ..Data(answer).memories
	Do $$$AssertEquals($Select($IsObject(memories): memories.%Size(), 1: 0), 0, "and finds none of the visitor's memories")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "and makes no table, class or global")
}

/// 1 when the first model request of the turn offers the tool documents.
ClassMethod Offered(requests As %DynamicArray) As %Boolean [ Private ]
{
	If requests.%Size() < 1 Quit 0
	Quit $ListFind($ListFromString($ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "ToolNames", requests.%Get(0))), "documents") > 0
}

/// The number of items of the search result whose source is the Ref.
ClassMethod Holds(result As %DynamicArray, ref As %String) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = result.%GetIterator()
	While iterator.%GetNext(, .item) {
		If $IsObject(item) && $IsObject(item.metadata) && (item.metadata.source = ref) Set count = count + 1
	}
	Quit count
}

}
