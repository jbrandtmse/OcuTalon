/// End-to-end tests of the documents tool through the Chat agent (Story 19.4; AD-1, AD-6, AD-10, AD-21, FR-7, NFR-3, NFR-14; DW-720, DW-739, DW-782). THEY RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), on OcuTalon's Docker image, through the CI environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1).
/// Each test adds its documents through Commands.Submit -> CommandsIn -> DocumentOps as web_user, waits for them to be ready, and drives real turns of the Chat
/// agent through Decide (RunnerFixture.Run) against the CI mock, with the REAL gate, AI Hub's knowledge base over OcuTalonKB.Docs and the Embedder worker (no
/// double), then reads the Reply's HostData and Tainted, the steps of Visual Trace, the Decision rows and the mock's log. The ChatAgent job that runs the first
/// turn of a test is the job that runs every later one (DW-782: a query embedded from inside AI Hub's tool execution does not crash or recycle the runner).
///   - TestCovered (Integration AC, matrix "Covered question"): documents-runbook asks the runbook how to rotate the certificate: at most 5 passages come back,
///     HostData.citations names the document, the section "Rotating the certificate" and the passage of each passage at or above the floor, the first being the
///     steps' passage, the turn is tainted, the step is the generic "Running a tool" step of documents, and the runner's job is the same across two documents
///     turns and a search_memories turn;
///   - TestClamp: documents-topk asks for a top_k of 9 on a document of 12 passages: the model reads 5 passages, not 9 (the gate set the member again);
///   - TestNotCovered (Q2 b, DW-720 a): an unrelated question gets passages from AI Hub, all below the floor, so there is no citation; the reply may say "None of
///     your documents cover that." and the turn is still tainted because the search ran; the same on an empty table;
///   - TestNoneConflict (DW-720 b): a covered search whose reply also says the sentence leaves Decide without the sentence and with its citations;
///   - TestNoneOnly (DW-720 b): a covered search whose reply is only the sentence takes Decide's invalid path: no outbound text holds the sentence;
///   - TestRemoved (AD-21): after RemoveDocument the next documents call returns none of its passages and the reply cites none;
///   - TestThenSave (FR-7, AD-10): documents, then save_memory in the same turn: the save is denied with the gate's sentence, and nothing is stored.
/// Every test checks the steps of its turns (RunnerFixture.StepProblems), except TestNoneOnly, whose turn ends in Decide's fallback, and TestThenSave, which reads
/// the statuses of its two tool steps itself because the second is denied; every test removes its documents, KB rows, events, uploads, sessions and rows. A
/// search result is judged by the items of the test's own document (their source), so another document's rows never decide it.
Class OcuTalon.Test.Docs.Turns Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-doc-turns";

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

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state))
		Merge ^||OcuTalonTestDocsTurns = state
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
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
	Do ..DropDocuments()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	Do ..DropDocuments()
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
		Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
		If '$ClassMethod(..#FIXTURE, "KeysAre", placeholder) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
	}
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestDocsTurns
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestDocsTurns
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// Deletes the documents of the sessions of the run with their KB rows, events and uploads, and the memories of the sessions.
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
	}
	Set position = 0
	While $ListNext(..DocRefs, position, ref) {
		Do $ClassMethod(..#STORE, "Remove", ref)
		Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
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

/// The text of the runbook's passage at chunk_index n.
ClassMethod Passage(n As %Integer) As %String [ Private ]
{
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", ..Runbook(), "markdown", .passages)
	Quit passages.%Get(n).text
}

/// The number of memories of the session.
ClassMethod Memories(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Memory WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The session of the first header after the mark from CommandsIn to the item, or "": a command reaches its owner only through CommandsIn.
ClassMethod CommandSince(mark As %Integer, owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'CommandsIn' AND TargetConfigName = ? ORDER BY ID", mark, owner)
	If result.%Next() Quit result.%GetData(1)
	Quit ""
}

Method TestCovered()
{
	If '..Ready() Quit
	Set session = ..Session("covered")
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set jobs = $ClassMethod(..#FIXTURE, "Jobs", ..#RUNNER)
	Do $$$AssertTrue($ListLength(jobs) '< 1, "the " _ ..#RUNNER _ " item has a job")
	Set job = $ListGet(jobs, 1)
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-runbook]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, "The CI mock answered from the Results runbook: Rotating the certificate.", "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Fallback _ "|" _ answer.ToolsRun, "0|1", "no fallback, and one tool ran")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted: the passages are not trusted output")
	Set data = ..Data(answer)
	Set citations = data.citations
	Do $$$AssertTrue($IsObject(citations) && (citations.%Size() '< 1) && (citations.%Size() '> 5), "HostData.citations holds one to five entries")
	If $IsObject(citations) && (citations.%Size() > 0) {
		Do $$$AssertEquals(citations.%Get(0).%ToJSON(), {"documentRef": (ref), "document": "Results runbook", "section": "Rotating the certificate", "passage": (..Passage(1)), "chunkIndex": 1}.%ToJSON(), "the first is the passage of the steps: documentRef, document, section, passage and chunkIndex")
		Set bad = ""
		Set iterator = citations.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If entry.documentRef '= ref Set bad = bad _ " " _ entry.chunkIndex
		}
		Do $$$AssertEquals(bad, "", "and every entry names the document")
	}
	Set result = ..ToolResult(requests)
	If $IsObject(result) {
		Do $$$AssertTrue(result.%Size() '> 5, "the model read at most five passages: " _ result.%Size())
		Do $$$AssertEquals(result.%Get(0).metadata."chunk_index" _ "|" _ result.%Get(0).metadata.section _ "|" _ result.%Get(0).metadata.source, "1|Rotating the certificate|" _ ref, "the steps' passage is the first it read")
	}
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
	Do ..SameJob(job, "after the first documents turn")
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-runbook]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(answer.Text, "The CI mock answered from the Results runbook: Rotating the certificate.", "a second documents turn answers alike")
	Set again = ..Data(answer).citations
	Do $$$AssertEquals($Select($IsObject(again): again.%Get(0).chunkIndex, 1: "none"), 1, "with the same first citation")
	Do ..SameJob(job, "after the second")
	Set sc = ..Turn("Who is the contact? [[mock:memory-recall-meaning]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(answer.Text, "The CI mock found the memory.", "a search_memories turn after them answers")
	Do $$$AssertEquals(..Data(answer).%IsDefined("citations"), 0, "with no citation of the earlier turns")
	Do ..SameJob(job, "after a search_memories turn")
}

Method TestClamp()
{
	If '..Ready() Quit
	Set session = ..Session("clamp")
	Set text = ""
	For i = 1:1:12 Set text = text _ "## Section " _ i _ $Char(10) _ "The Results runbook step " _ i _ " describes how to handle the certificate, the queue and the lab number " _ i _ "." _ $Char(10, 10)
	Set ref = ..AddDocument(session, "Many sections.md", text)
	If ref = "" Quit
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 12, "the document has 12 passages")
	Set sc = ..Turn("Search. [[mock:documents-topk]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, "The CI mock searched with a top_k of nine.", "the reply is the text of the scenario")
	Set result = ..ToolResult(requests)
	If $IsObject(result) Do $$$AssertEquals(result.%Size(), 5, "the model read 5 passages although it asked for 9")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

Method TestNotCovered()
{
	If '..Ready() Quit
	Set session = ..Session("notcovered")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count"), 0, "the table is empty to begin with")
	Set sc = ..Turn("How do I reset my password? [[mock:documents-none]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn on an empty table")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, ..#NONE, "the reply is the sentence, shown as it is")
	Do $$$AssertEquals(..Data(answer).%IsDefined("citations"), 0, "with no citation")
	Do $$$AssertEquals(answer.Tainted, 1, "and the turn is still tainted: the search ran")
	Set result = ..ToolResult(requests)
	If $IsObject(result) Do $$$AssertEquals(result.%Size(), 0, "the table is empty, so the search found nothing")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set sc = ..Turn("How do I reset my password? [[mock:documents-none]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(answer.Text, ..#NONE, "with a document added the reply is the sentence")
	Do $$$AssertEquals(..Data(answer).%IsDefined("citations"), 0, "and no passage is cited: every score is below the floor")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted: the search ran")
	Set result = ..ToolResult(requests)
	If $IsObject(result) {
		Do $$$AssertTrue(..Holds(result, ref) > 0, "AI Hub still returned passages of the document (no hook can hold them back): " _ ..Holds(result, ref))
		Set above = 0
		Set iterator = result.%GetIterator()
		While iterator.%GetNext(, .item) {
			If (item.metadata.source = ref) && (item.score '< $Parameter("OcuTalon.Bridge.Citations", "CITEFLOOR")) Set above = above + 1
		}
		Do $$$AssertEquals(above, 0, "all of them score below the floor")
	}
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

Method TestNoneConflict()
{
	If '..Ready() Quit
	Set session = ..Session("conflict")
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-none-conflict]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, "Stop the sender, install the new certificate and send a test result.", "the sentence is gone from the reply that leaves Decide")
	Do $$$AssertEquals(answer.Fallback, 0, "and it is no fallback")
	Set citations = ..Data(answer).citations
	Do $$$AssertEquals($Select($IsObject(citations): citations.%Get(0).documentRef _ "|" _ citations.%Get(0).section, 1: "none"), ref _ "|Rotating the certificate", "and the citations stay")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", request.ItemId, "turn")
	Do $$$AssertEquals($Select($IsObject(row): row.Outcome _ "|" _ row.Fallback, 1: "none"), "tellnow|0", "the Decision row is a normal one")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

Method TestNoneOnly()
{
	If '..Ready() Quit
	Set session = ..Session("noneonly")
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-none-only]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertTrue(answer.Text '[ ..#NONE, "no outbound text holds the sentence")
	Do $$$AssertEquals(answer.Fallback _ "|" _ answer.FallbackReason, "1|invalid", "Decide took its invalid path: a fallback with the reason invalid")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", request.ItemId, "turn")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback _ "|" _ row.FallbackReason, 1: "none"), "1|invalid", "recorded as such")
	If $IsObject(row) Do $$$AssertTrue((row.Reasons _ row.Payload) '[ ..#NONE, "and the row holds no sentence")
}

Method TestRemoved()
{
	If '..Ready() Quit
	Set session = ..Session("removed")
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-runbook]]", session, .request, .answer, .turnSession, .requests)
	Set citations = ..Data(answer).citations
	Do $$$AssertEquals($Select($IsObject(citations): citations.%Get(0).documentRef, 1: "none"), ref, "while the document is there the reply cites it")
	Set command = ##class(OcuTalon.Msg.Command.RemoveDocument).%New()
	Set command.SessionRef = session
	Set command.DocumentRef = ref
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "RemoveDocument is Ok 1 removed")
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-removed]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(answer.Text, "The CI mock searched the documents.", "the next turn is answered")
	Do $$$AssertEquals(..Data(answer).%IsDefined("citations"), 0, "and cites nothing")
	Set result = ..ToolResult(requests)
	If $IsObject(result) Do $$$AssertEquals(..Holds(result, ref), 0, "the search returned none of its passages")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted: the search ran")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

/// The number of items of a documents result whose source is the Ref; another document's rows never count.
ClassMethod Holds(result As %DynamicArray, ref As %String) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = result.%GetIterator()
	While iterator.%GetNext(, .item) {
		If $IsObject(item) && $IsObject(item.metadata) && (item.metadata.source = ref) Set count = count + 1
	}
	Quit count
}

/// The documents kind of the evaluation set (Story 19.4, Q5; AD-22): EvalIn's DocumentsUp indexes the files of a documents case as documents of the owner eval through
/// Docs.Ops (the second case names the file of the first with ../), in its own process, and waits until they are ready; DocumentsDown takes the passages and the rows away;
/// a case with a file that is not there adds nothing and leaves nothing. No Session row is written or deleted (Test.Eval.Documents proves the rest of the isolation).
Method TestEvalDocuments()
{
	If '..Ready() Quit
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	If '##class(%File).DirectoryExists(folder _ "documents-runbook-rotate") {
		Do $$$AssertTrue(0, "the repository's eval/ is mounted at " _ folder _ " (a throwaway or CI stack)")
		Quit
	}
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Eval.In", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of EvalIn is made")
	Set sessions = ..SessionState()
	Set documentRows = ..Count("OcuTalon_Data.Document")
	For name = "documents-runbook-rotate", "documents-none-cover" {
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name)))
		Set reason = service.DocumentsUp(case, ##class(%File).SubDirectoryName(folder, name), .documents)
		Do $$$AssertEquals(reason, "", name _ ": its documents are added")
		If reason '= "" Continue
		Do $$$AssertEquals(documents.refs.%Size(), 1, "one document")
		Set ref = documents.refs.%Get(0)
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State, Name, OwnerRef, AddedBy FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
		Do rs.%Next()
		Do $$$AssertEquals(rs.%Get("State") _ "|" _ rs.%Get("Name") _ "|" _ rs.%Get("OwnerRef") _ "|" _ rs.%Get("AddedBy"), "ready|Results runbook.md|eval|eval", "it is ready, named as the case says and the owner eval's")
		Do $$$AssertTrue($ClassMethod(..#STORE, "Count", ref) > 0, "and its passages are in the table")
		Do $$$AssertStatusOK(service.DocumentsDown(documents), "DocumentsDown answers OK")
		Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "the passages are gone")
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
		Do rs.%Next()
		Do $$$AssertEquals(rs.%GetData(1), 0, "and so is the document")
	}
	Set name = "documents-runbook-rotate"
	Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name)))
	Set reason = service.DocumentsUp(case, ##class(%File).SubDirectoryName(folder, name), .documents)
	Do $$$AssertEquals(reason, "", "a case's documents are added again")
	Set ref = documents.refs.%Get(0)
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.In).Finish([{"documents": (documents)}]), "Finish answers OK for a record that holds the documents")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(ref)), "0|0", "and Finish took the passages and the document away")
	Set bad = {"documents": [{"name": "Gone.md", "file": "nothing-here.md"}]}
	Set reason = service.DocumentsUp(bad, ##class(%File).SubDirectoryName(folder, "documents-runbook-rotate"), .documents)
	Do $$$AssertEquals(reason, $Replace($Parameter("OcuTalon.Eval.In", "REASONDOCUMENTS"), "{why}", "each document needs a name, and a file of the cases' folder that is Markdown or plain text"), "a file that is not there skips the case with the reason")
	Set bad = {"documents": [{"name": "Out.md", "file": "../../README.md"}]}
	Set reason = service.DocumentsUp(bad, ##class(%File).SubDirectoryName(folder, "documents-runbook-rotate"), .documents)
	Do $$$AssertTrue(reason [ "each document needs a name", "and a file outside the folder of the cases is refused too")
	Set bad = {"documents": []}
	Do $$$AssertTrue(service.DocumentsUp(bad, folder, .documents) [ "not a non-empty array", "an empty list is refused")
	Do $$$AssertEquals(..SessionState(), sessions, "no Session row was written or deleted")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Document"), documentRows, "and nothing was left behind: the document rows are as they were")
}

/// The number and the highest id of the Session rows, as one text.
ClassMethod SessionState() As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), MAX(ID) FROM OcuTalon_Data.Session")
	Do rs.%Next()
	Quit rs.%GetData(1) _ "|" _ rs.%GetData(2)
}

/// The number of rows of a table.
ClassMethod Count(table As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

Method TestThenSave()
{
	If '..Ready() Quit
	Set session = ..Session("thensave")
	Set ref = ..AddDocument(session, "Results runbook.md", ..Runbook())
	If ref = "" Quit
	Set before = ..Memories(session)
	Set mark = $ClassMethod(..#FIXTURE, "HeaderMark")
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-then-save]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted")
	Set steps = $ClassMethod(..#FIXTURE, "StepsOf", answer.DecisionRef)
	Set statuses = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind = "tool" Set statuses = statuses _ $Select(statuses '= "": ",", 1: "") _ step.status
	}
	Do $$$AssertEquals(statuses, "ok,denied", "the documents step is ok and the save step is denied")
	Do $$$AssertEquals(requests.%Size(), 3, "the mock logged three requests")
	If requests.%Size() = 3 {
		Set results = $ClassMethod(..#FIXTURE, "ToolResults", requests.%Get(2))
		Do $$$AssertEquals($ListLength(results), 2, "the last carries two tool results")
		If $ListLength(results) = 2 Do $$$AssertTrue($List(results, 2) [ $Parameter("OcuTalon.Bridge.Policy.Gate", "UNTRUSTED"), "the second holds the sentence of the gate's denial")
	}
	Do $$$AssertEquals(..CommandSince(mark, "MemoryOps"), "", "no command reached MemoryOps")
	Do $$$AssertEquals(..Memories(session), before, "and nothing was stored")
}

}
