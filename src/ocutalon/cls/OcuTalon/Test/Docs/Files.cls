/// End-to-end tests of PDF and Word documents (Story 19.7; AD-1, AD-6, AD-10, AD-21, AD-33; FR-42). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on
/// OcuTalon's Docker image, through the CI environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1). Each test adds its files through Commands.Submit ->
/// CommandsIn -> DocumentOps as web_user, with the real Extractor worker, the Embedder worker, OcuTalonKB.Docs and (for the turns) Decide -> ChatAgent against the CI
/// mock with the REAL gate and AI Hub's knowledge base: no double. The helpers that read a turn are those of Test.Docs.Turns, copied because they are Private there
/// and that class is Story 19.5's file; the Epic 19 burn-down can lift them into one fixture.
///   - TestAddPdf, TestAddWord (matrix "Add PDF" and "Add Word"): the answer is Ok 1 added with the Ref, the row keeps the extracted text, becomes ready, its
///     Sections are the pages or the Heading 1 sections, the knowledge-base rows carry the same source, chunk_index, document and section as a Markdown document's,
///     and the events are indexing and then ready;
///   - TestFileFailures (matrix "File cannot be read"): an encrypted, a damaged, a text-less, a legacy .doc and a too large Word file are failed rows with the
///     reason encrypted, damaged, no_text, legacy_doc and contents_too_large, one failed event, Ok 1 added with MESSAGENOTINDEXED, no knowledge-base row and no file
///     in the extraction folder;
///   - TestSeamTimeout (matrix "Read times out at the seam"): Docs.Ops.Text with a wait of 2 seconds while a job holds the extraction lock answers timed_out, no text
///     and one warning that starts with LOGEXTRACT and holds the code;
///   - TestCited, TestNotCovered, TestRemoved (matrix "Cited", "Not covered", "Removed"): turns through Decide -> ChatAgent on the CI mock cite the right document and
///     section, cite nothing when no passage is covered, and cite a removed PDF no more; the turns are tainted, their steps are right and the runner job is the same;
///   - TestOnlineDemoParity (matrix "Online demo parity"): on the online demo a Markdown file and a PDF get the same Ok and Outcome (not_built until Story 19.5), and
///     once documents are added there they get the same OwnerRef and KnowledgeBase, with the PDF's passages in that table.
/// Every test removes its documents, KB rows, events, uploads, sessions, rows and log rows, and puts back the setting onlineDemo and the runners' keys.
Class OcuTalon.Test.Docs.Files Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-docs-files";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter RUNNER = "ChatAgent";

Parameter STORE = "OcuTalon.Docs.Store";

Parameter SAMPLES = "OcuTalon.Test.Docs.Samples";

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
		Merge ^||OcuTalonTestDocsFiles = state
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	If $ClassMethod(..#FIXTURE, "Running") Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
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
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropDocuments()
	Kill ^OcuTalonTest("ExtractMore", "seam")
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
		Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
		If '$ClassMethod(..#FIXTURE, "KeysAre", placeholder) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
	}
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestDocsFiles
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestDocsFiles
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// Deletes the documents of the sessions of the run with their KB rows, events and uploads.
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

/// 1 when this is OcuTalon's image and the production runs. Otherwise the test fails with the reason or records the skip, and quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Quit 1
}

/// 1 when Ready, the runner side is ready, and the entries of the runners point at the CI mock key variable. Otherwise the test fails with the reason or records the
/// skip, and quits.
Method ReadyTurns() As %Boolean [ Private ]
{
	If '..Ready() Quit 0
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

/// Adds the file (a binary stream) as web_user through Commands.Submit; result is the CommandResult. The Ref is kept for the clean-up.
Method AddFile(session As %String, name As %String, type As %String, stream As %Stream.Object, Output result As OcuTalon.Msg.CommandResult, Output seconds As %Numeric) As %Status [ Private ]
{
	Do stream.Rewind()
	Set up = ##class(OcuTalon.Data.Upload).Put(session, stream, .put)
	Do $$$AssertStatusOK(put, "the upload of " _ name _ " is stored")
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.SessionRef = session
	Set command.Name = name
	Set command.ContentType = type
	Set command.UploadRef = up
	Set began = $ZHorolog
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Set seconds = $ZHorolog - began
	If $IsObject(result) && (result.Ref '= "") Set ..DocRefs = ..DocRefs _ $ListBuild(result.Ref)
	Quit sc
}

/// Adds the file and waits (up to 120 s) for it to be ready; its Ref, or "" with the assertions failed.
Method AddReady(session As %String, name As %String, type As %String, stream As %Stream.Object) As %String [ Private ]
{
	Set sc = ..AddFile(session, name, type, stream, .result, .seconds)
	Do $$$AssertEquals($Select($IsObject(result): result.Ok _ "|" _ result.Outcome, 1: "none"), "1|added", name _ " is added through CommandsIn and DocumentOps")
	If '$IsObject(result) || (result.Ref = "") Quit ""
	Set ready = ..WaitState(result.Ref, "ready")
	Do $$$AssertEquals(ready, 1, name _ " is ready")
	Quit $Select(ready: result.Ref, 1: "")
}

Method Remove(session As %String, ref As %String, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveDocument).%New()
	Set command.SessionRef = session
	Set command.DocumentRef = ref
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
}

/// The row of the document, or "".
ClassMethod Row(ref As %String) As OcuTalon.Data.Document [ Private ]
{
	Quit ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
}

/// The State of the document read from the table (an open object of the row would be this process' cached one), or "".
ClassMethod State(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
	If rs.%Next() Quit rs.%Get("State")
	Quit ""
}

/// Waits up to seconds for the document's State to be state; 1 when it is. A failed document ends the wait.
ClassMethod WaitState(ref As %String, state As %String, seconds As %Integer = 120) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While $ZHorolog < deadline {
		Set now = ..State(ref)
		If (now = state) || (now = "failed") Quit
		Hang 0.5
	}
	Quit ..State(ref) = state
}

/// The states of the document's events on the instance stream, oldest first, comma-separated, with + after one whose removed is true.
ClassMethod Events(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Payload FROM OcuTalon_Live.Event WHERE Stream = 'instance' AND Type = 'document' AND Payload [ ? ORDER BY Seq", """ref"":""" _ ref _ """")
	Set states = ""
	While rs.%Next() {
		Set payload = {}.%FromJSON(rs.%Get("Payload"))
		Set states = states _ $Select(states '= "": ",", 1: "") _ payload.state _ $Select(payload.removed: "+", 1: "")
	}
	Quit states
}

/// Waits up to seconds for the document's events to read states.
ClassMethod WaitEvents(ref As %String, states As %String, seconds As %Integer = 20) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While $ZHorolog < deadline {
		If ..Events(ref) = states Quit
		Hang 0.2
	}
}

/// The text of the passage at chunk_index n of the extracted text of the content type.
ClassMethod Passage(text As %String, type As %String, n As %Integer) As %String [ Private ]
{
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, type, .passages)
	Quit passages.%Get(n).text
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

/// The number of citations of the Reply's HostData whose documentRef is the Ref.
ClassMethod Cites(answer As %Persistent, ref As %String) As %Integer [ Private ]
{
	Set citations = ..Data(answer).citations
	If '$IsObject(citations) Quit 0
	Set count = 0
	Set iterator = citations.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.documentRef = ref Set count = count + 1
	}
	Quit count
}

/// The first citation as JSON, or "none".
ClassMethod FirstCitation(answer As %Persistent) As %String [ Private ]
{
	Set citations = ..Data(answer).citations
	Quit $Select($IsObject(citations) && (citations.%Size() > 0): citations.%Get(0).%ToJSON(), 1: "none")
}

Method TestAddPdf()
{
	If '..Ready() Quit
	Set session = ..Session("addpdf")
	Set sc = ..AddFile(session, "Results runbook.pdf", "pdf", ##class(OcuTalon.Test.Docs.Samples).PdfRunbook(), .result, .seconds)
	Do $$$AssertStatusOK(sc, "AddDocument is answered")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", "with Ok 1, added and the Ref")
	Do $$$AssertTrue(seconds < 60, "inside CommandsIn's limit: " _ seconds)
	Do $$$AssertEquals(result.Message, $Parameter("OcuTalon.Docs.Ops", "MESSAGEADDED"), "and the message of DocumentOps")
	Set ref = result.Ref
	Set row = ..Row(ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.OwnerRef _ "|" _ row.AddedBy _ "|" _ row.Name _ "|" _ row.ContentType _ "|" _ row.KnowledgeBase, "instance|" _ session _ "|Results runbook.pdf|pdf|OcuTalonKB.Docs", "OwnerRef instance, AddedBy the session, the name, the type and the table")
	Do $$$AssertEquals($Extract(row.Text.Read(9), 1, 9), "## Page 1", "the text is the extraction's and starts with the first page line")
	Do $$$AssertTrue(row.State = "indexing" || (row.State = "ready"), "the row is indexing, or ready already: " _ row.State)
	Set row = ""
	Do $$$AssertTrue(..WaitState(ref, "ready"), "the document becomes ready")
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Text.Read($$$MaxLocalLength), ##class(OcuTalon.Test.Docs.Samples).ExpectedPdfRunbook(), "the row keeps the extracted text")
	Do $$$AssertEquals(row.Sections, "[""Page 1"",""Page 2""]", "Sections is Page 1 and Page 2")
	Do $$$AssertEquals(row.Size, ##class(OcuTalon.Test.Docs.Samples).PdfRunbook().Size, "the size is the bytes of the file")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 2, "the table holds one row for each page")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT metadata FROM OcuTalonKB.Docs WHERE source = ? ORDER BY id", ref)
	Set n = 0
	Set sections = $ListBuild("Page 1", "Page 2")
	While rs.%Next() {
		Set meta = {}.%FromJSON(rs.%Get("metadata"))
		Do $$$AssertEquals(meta.%ToJSON(), {"source": (ref), "chunk_index": (n), "document": "Results runbook", "section": ($List(sections, n + 1))}.%ToJSON(), "row " _ n _ ": source, chunk_index, document (the name without .pdf) and section")
		Set n = n + 1
	}
	Do ..WaitEvents(ref, "indexing,ready")
	Do $$$AssertEquals(..Events(ref), "indexing,ready", "the instance stream got an indexing event and then a ready event")
}

Method TestAddWord()
{
	If '..Ready() Quit
	Set session = ..Session("addword")
	Set sc = ..AddFile(session, "Lab feed runbook.docx", "docx", ##class(OcuTalon.Test.Docs.Samples).DocxRunbook(), .result, .seconds)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", "AddDocument is Ok 1, added, with the Ref")
	Do $$$AssertTrue(seconds < 60, "inside CommandsIn's limit: " _ seconds)
	Set ref = result.Ref
	Do $$$AssertTrue(..WaitState(ref, "ready"), "the document becomes ready")
	Set row = ..Row(ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.Text.Read($$$MaxLocalLength), ##class(OcuTalon.Test.Docs.Samples).ExpectedDocxRunbook(), "the row keeps the extracted text")
	Do $$$AssertEquals(row.Sections, "["""",""Restarting the lab feed"",""Checking the lab numbers""]", "Sections is the title's (empty) and the two Heading 1 sections")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 3, "the table holds one row for each passage")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT text, metadata FROM OcuTalonKB.Docs WHERE source = ? ORDER BY id", ref)
	Set n = 0
	Set sections = $ListBuild("", "Restarting the lab feed", "Checking the lab numbers")
	While rs.%Next() {
		Set meta = {}.%FromJSON(rs.%Get("metadata"))
		Do $$$AssertEquals(meta.%ToJSON(), {"source": (ref), "chunk_index": (n), "document": "Lab feed runbook", "section": ($List(sections, n + 1))}.%ToJSON(), "row " _ n _ ": source, chunk_index, document (the name without .docx) and section")
		If n = 0 Do $$$AssertTrue(rs.%Get("text") [ "# Lab feed runbook", "the Title line is passage text")
		If n = 2 {
			Set rows = "Counter | Expected" _ $Char(10) _ "Queue length | zero"
			Do $$$AssertTrue(rs.%Get("text") [ rows, "and the table rows (cells joined by a bar) are passage text")
		}
		Set n = n + 1
	}
	Do ..WaitEvents(ref, "indexing,ready")
	Do $$$AssertEquals(..Events(ref), "indexing,ready", "the instance stream got an indexing event and then a ready event")
}

Method TestFileFailures()
{
	If '..Ready() Quit
	Set session = ..Session("failures")
	Set samples = ..#SAMPLES
	Set max = ##class(OcuTalon.Docs.Extract).#MAXUNPACKED
	Set cases = $ListBuild("encrypted|pdf|PdfEncrypted", "damaged|pdf|PdfJunk", "no_text|pdf|PdfDrawing", "legacy_doc|docx|Ole", "contents_too_large|docx|DocxDeclaring")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set code = $Piece(case, "|", 1), type = $Piece(case, "|", 2), method = $Piece(case, "|", 3)
		Set stream = $Case(method, "Ole": $ClassMethod(samples, "Ole", "WordDocument"), "DocxDeclaring": $ClassMethod(samples, "DocxDeclaring", max + 1), : $ClassMethod(samples, method))
		Set files = ##class(OcuTalon.Test.Docs.Extract).Files()
		Set sc = ..AddFile(session, code _ "." _ type, type, stream, .result, .seconds)
		Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", code _ ": the answer is Ok 1 added with the Ref")
		Do $$$AssertEquals(result.Message, $Parameter("OcuTalon.Docs.Ops", "MESSAGENOTINDEXED"), code _ ": with MESSAGENOTINDEXED")
		Set row = ..Row(result.Ref)
		Do $$$AssertEquals($Select($IsObject(row): row.State _ "|" _ row.Reason _ "|" _ row.ContentType, 1: "no row"), "failed|" _ code _ "|" _ type, code _ ": a failed row with the extraction's code")
		Do ..WaitEvents(result.Ref, "failed")
		Do $$$AssertEquals(..Events(result.Ref), "failed", code _ ": one failed event")
		Do $$$AssertEquals($ClassMethod(..#STORE, "Count", result.Ref), 0, code _ ": no knowledge-base row")
		Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, code _ ": no file left in the extraction folder")
	}
}

Method TestSeamTimeout()
{
	If '..Ready() Quit
	Kill ^OcuTalonTest("ExtractMore", "seam")
	Set mark = ..LogMark()
	Job ##class(OcuTalon.Test.Docs.ExtractMore).HoldLock("seam")
	Set job = $ZChild
	Do $$$AssertTrue(##class(OcuTalon.Test.Docs.ExtractMore).WaitNode("seam", "held") && $Get(^OcuTalonTest("ExtractMore", "seam", "held")), "a job holds the extraction lock")
	Set files = ##class(OcuTalon.Test.Docs.Extract).Files()
	Set began = $ZHorolog
	Set ok = ##class(OcuTalon.Docs.Ops).Text(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf", .text, .reason, 2)
	Set elapsed = $ZHorolog - began
	Do $$$AssertEquals(ok _ "|" _ reason _ "|" _ text, "0|timed_out|", "Text answers timed_out and no text while the lock is held")
	Do $$$AssertTrue((elapsed > 1.5) && (elapsed < 6), "after about 2 seconds (" _ $FNumber(elapsed, "", 2) _ ")")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, "and writes no file")
	Set start = ##class(OcuTalon.Docs.Ops).#LOGEXTRACT
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Set count = 0
	Set text = ""
	While rs.%Next() {
		Set count = count + 1
		Set text = rs.%Get("Text")
	}
	Do $$$AssertEquals(count, 1, "one warning starts with LOGEXTRACT")
	Do $$$AssertTrue(text [ "timed_out", "and holds the code: " _ text)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Set ^OcuTalonTest("ExtractMore", "seam", "release") = 1
	Do $$$AssertTrue(##class(OcuTalon.Test.Docs.ExtractMore).WaitEnd(job), "the holding job ended")
	Kill ^OcuTalonTest("ExtractMore", "seam")
	Set ok = ##class(OcuTalon.Docs.Ops).Text(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf", .text, .reason)
	Do $$$AssertEquals(ok _ "|" _ reason, "1|", "control: with the lock free the same call reads the file")
	Do $$$AssertEquals(text, ##class(OcuTalon.Test.Docs.Samples).ExpectedPdf3(), "and answers its text")
	Set ok = ##class(OcuTalon.Docs.Ops).Text(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "html", .text, .reason)
	Do $$$AssertEquals(ok _ "|" _ reason, "0|wrong_type", "a content type that is none of the four is wrong_type")
}

/// The id of the last row of the log.
ClassMethod LogMark() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

Method TestCited()
{
	If '..ReadyTurns() Quit
	Set session = ..Session("cited")
	Set pdf = ..AddReady(session, "Results runbook.pdf", "pdf", ##class(OcuTalon.Test.Docs.Samples).PdfRunbook())
	Set word = ..AddReady(session, "Lab feed runbook.docx", "docx", ##class(OcuTalon.Test.Docs.Samples).DocxRunbook())
	If (pdf = "") || (word = "") Quit
	Set jobs = $ClassMethod(..#FIXTURE, "Jobs", ..#RUNNER)
	Do $$$AssertTrue($ListLength(jobs) '< 1, "the " _ ..#RUNNER _ " item has a job")
	Set job = $ListGet(jobs, 1)
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-pdf]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the PDF turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, "The CI mock answered from the PDF runbook.", "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Fallback _ "|" _ answer.ToolsRun, "0|1", "no fallback, and one tool ran")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted: the passages are not trusted output")
	Set citations = ..Data(answer).citations
	Do $$$AssertTrue($IsObject(citations) && (citations.%Size() '< 1) && (citations.%Size() '> 5), "HostData.citations holds one to five entries")
	Set expected = {"documentRef": (pdf), "document": "Results runbook", "section": "Page 2", "passage": (..Passage(##class(OcuTalon.Test.Docs.Samples).ExpectedPdfRunbook(), "pdf", 1)), "chunkIndex": 1}
	Do $$$AssertEquals(..FirstCitation(answer), expected.%ToJSON(), "the first is page 2 of the PDF: documentRef, document, section, passage and chunkIndex")
	Do $$$AssertEquals(..Cites(answer, pdf), $Select($IsObject(citations): citations.%Size(), 1: 0), "and every entry names the PDF")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
	Do ..SameJob(job, "after the PDF turn")
	Set sc = ..Turn("How do I restart the lab feed? [[mock:documents-word]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the Word turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, "The CI mock answered from the Word runbook.", "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted")
	Set citations = ..Data(answer).citations
	Do $$$AssertTrue($IsObject(citations) && (citations.%Size() '< 1) && (citations.%Size() '> 5), "HostData.citations holds one to five entries")
	Set expected = {"documentRef": (word), "document": "Lab feed runbook", "section": "Restarting the lab feed", "passage": (..Passage(##class(OcuTalon.Test.Docs.Samples).ExpectedDocxRunbook(), "docx", 1)), "chunkIndex": 1}
	Do $$$AssertEquals(..FirstCitation(answer), expected.%ToJSON(), "the first is the section Restarting the lab feed of the Word file")
	Do $$$AssertEquals(..Cites(answer, word), $Select($IsObject(citations): citations.%Size(), 1: 0), "and every entry names the Word file")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
	Do ..SameJob(job, "after the Word turn")
}

Method TestNotCovered()
{
	If '..ReadyTurns() Quit
	Set session = ..Session("none")
	Set pdf = ..AddReady(session, "Results runbook.pdf", "pdf", ##class(OcuTalon.Test.Docs.Samples).PdfRunbook())
	Set word = ..AddReady(session, "Lab feed runbook.docx", "docx", ##class(OcuTalon.Test.Docs.Samples).DocxRunbook())
	If (pdf = "") || (word = "") Quit
	Set sc = ..Turn("How do I reset my password? [[mock:documents-none]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text, ..#NONE, "the reply is the sentence, shown as it is")
	Do $$$AssertEquals(..Data(answer).%IsDefined("citations"), 0, "with no citation member")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is still tainted: the search ran")
	Set result = ..ToolResult(requests)
	If $IsObject(result) {
		Set above = 0
		Set iterator = result.%GetIterator()
		While iterator.%GetNext(, .item) {
			If ((item.metadata.source = pdf) || (item.metadata.source = word)) && (item.score '< $Parameter("OcuTalon.Bridge.Citations", "CITEFLOOR")) Set above = above + 1
		}
		Do $$$AssertEquals(above, 0, "every passage of the two files scores below the floor")
	}
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

Method TestRemoved()
{
	If '..ReadyTurns() Quit
	Set session = ..Session("removed")
	Set pdf = ..AddReady(session, "Results runbook.pdf", "pdf", ##class(OcuTalon.Test.Docs.Samples).PdfRunbook())
	Set word = ..AddReady(session, "Lab feed runbook.docx", "docx", ##class(OcuTalon.Test.Docs.Samples).DocxRunbook())
	If (pdf = "") || (word = "") Quit
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-pdf]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(..Cites(answer, pdf) > 0, 1, "while the PDF is there the reply cites it")
	Set sc = ..Remove(session, pdf, .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "RemoveDocument is Ok 1 removed")
	Set sc = ..Turn("How do I rotate the Results certificate? [[mock:documents-pdf]]", session, .request, .answer, .turnSession, .requests)
	Do $$$AssertEquals(answer.Text, "The CI mock answered from the PDF runbook.", "the next turn is answered")
	Do $$$AssertEquals(..Cites(answer, pdf), 0, "and no citation names the PDF")
	Set result = ..ToolResult(requests)
	If $IsObject(result) Do $$$AssertEquals(..Holds(result, pdf), 0, "the search returned none of its passages")
	Do $$$AssertEquals(answer.Tainted, 1, "the turn is tainted: the search ran")
	Do ..AssertSteps(answer, turnSession, $ListBuild("Running a tool"), $ListBuild("documents"))
}

Method TestOnlineDemoParity()
{
	If '..Ready() Quit
	Set session = ..Session("demo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set sc = ..AddFile(session, "notes.md", "markdown", ##class(OcuTalon.Test.Docs.Samples).Stream($ZConvert("# Notes" _ $Char(10) _ "Some text.", "O", "UTF8")), .md, .seconds)
	Set sc = ..AddFile(session, "Results runbook.pdf", "pdf", ##class(OcuTalon.Test.Docs.Samples).PdfRunbook(), .pdf, .seconds)
	Do $$$AssertEquals(pdf.Ok _ "|" _ pdf.Outcome, md.Ok _ "|" _ md.Outcome, "on the online demo a PDF and a Markdown file get the same Ok and Outcome: " _ md.Ok _ "|" _ md.Outcome)
	If 'md.Ok {
		Do $$$AssertEquals(pdf.Message, md.Message, "and the same message")
		Quit
	}
	Do $$$AssertTrue(..WaitState(md.Ref, "ready") && ..WaitState(pdf.Ref, "ready"), "both are ready")
	Set mdRow = ..Row(md.Ref)
	Set pdfRow = ..Row(pdf.Ref)
	Do $$$AssertTrue($IsObject(mdRow) && $IsObject(pdfRow), "both rows exist")
	If '$IsObject(mdRow) || '$IsObject(pdfRow) Quit
	Do $$$AssertEquals(pdfRow.OwnerRef _ "|" _ pdfRow.KnowledgeBase, mdRow.OwnerRef _ "|" _ mdRow.KnowledgeBase, "they have the same OwnerRef and KnowledgeBase")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ pdfRow.KnowledgeBase _ " WHERE source = ?", pdf.Ref)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 2, "and the PDF's passages are in that table")
}

}
