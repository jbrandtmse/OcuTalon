/// Tests of DocumentOps through the running production (Story 19.4; AD-1, AD-4, AD-5, AD-12, AD-21, AD-33; DW-739, DW-747). THEY RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), on OcuTalon's Docker image: the real CommandsIn, DocumentOps, Embedder worker and OcuTalonKB.Docs, with no double. Every command goes
/// through Commands.Submit as web_user, as the documents route sends it; the document events are read back from the instance stream. Each test makes its own
/// sessions (zz-doc-ops), documents, uploads, KB rows and events, and removes them.
///   - TestAddMarkdown: the matrix row "Add Markdown": the answer is Ok 1 added with the Ref in under 10 s, the row has State indexing then ready, OwnerRef
///     instance, AddedBy the session, the text and KnowledgeBase OcuTalonKB.Docs, the rows of OcuTalonKB.Docs carry the Ref, chunk_index, document and
///     section, Sections is the section of each chunk_index, and the instance stream gets an indexing event and then a ready event;
///   - TestTooLong: a text of more bytes than a string holds is a failed row with the reason failed, not a document indexed in part;
///   - TestIndexingError: a batch whose passages cannot be embedded (the worker's model folder made wrong in the test process, as Test.Memory.Ops TestEmbedFailure
///     does, for a shadow DocumentOps that runs the batch after the first was written) makes the document failed with the reason failed, deletes the rows
///     already written and sends a failed event;
///   - TestPlainText: 5,000 characters of text become passages of at most 1,000 characters with no section;
///   - TestUnreadable: bytes that are not UTF-8, hold a NUL or are blank after a BOM give a failed row with the reason unreadable, an event and Ok 1, and no KB row;
///   - TestUploadGone (DW-747): an upload already taken, one that never was, and another session's give Ok 0 failed with a failed row (reason failed) and its event,
///     and another session's upload stays;
///   - TestNoSession: either verb for an unknown session gives Ok 0 no_session, writes no row and takes nothing;
///   - TestOnlineDemo: with onlineDemo on, AddDocument gives Ok 0 not_built, writes no row and takes nothing;
///   - TestToolRefused: AddDocument from the origin tool is refused by CommandsIn and writes nothing;
///   - TestRemove: Remove deletes the KB rows and the row, sends a last event with removed true and answers Ok 1 removed; a second one, an unknown Ref and a
///     Ref of a document of another owner answer not_found and leave it;
///   - TestRemoveWhileIndexing: a Remove queued behind an indexing batch leaves no KB row of the document and no row, whatever batch was running;
///   - TestSecondAddKeepsOthers (Q2 c): adding the same file twice makes two documents with their own passages, and removing one leaves the other and a third.
Class OcuTalon.Test.Docs.Ops Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-doc-ops";

Parameter STORE = "OcuTalon.Docs.Store";

/// The Refs of the documents that the test made.
Property DocRefs As %List;

/// The public setting onlineDemo before the tests.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropDocuments()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropDocuments()
	Quit ##super()
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

/// 1 on the image; otherwise records the skip. Also guards on the production.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Quit 1
}

/// An upload row of the session with the bytes; its Ref.
ClassMethod Upload(session As %String, bytes As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Do stream.Write(bytes)
	Do stream.Rewind()
	Quit ##class(OcuTalon.Data.Upload).Put(session, stream, .sc)
}

/// The UTF-8 bytes of the text.
ClassMethod Utf8(text As %String) As %String [ Private ]
{
	Quit $ZConvert(text, "O", "UTF8")
}

/// Submits AddDocument as web_user for the upload (made here from the bytes unless uploadRef is given); result is the CommandResult and seconds how long it took.
Method Add(session As %String, name As %String, type As %String, bytes As %String, Output result As OcuTalon.Msg.CommandResult, Output seconds As %Numeric, uploadRef As %String = "") As %Status [ Private ]
{
	If uploadRef = "" Set uploadRef = ..Upload(session, bytes)
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.SessionRef = session
	Set command.Name = name
	Set command.ContentType = type
	Set command.UploadRef = uploadRef
	Set began = $ZHorolog
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Set seconds = $ZHorolog - began
	If $IsObject(result) && (result.Ref '= "") Set ..DocRefs = ..DocRefs _ $ListBuild(result.Ref)
	Quit sc
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

/// Waits up to seconds for the document's State to be state; 1 when it is.
ClassMethod WaitState(ref As %String, state As %String, seconds As %Integer = 90) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While $ZHorolog < deadline {
		If ..State(ref) = state Quit
		Hang 0.5
	}
	Quit ..State(ref) = state
}

/// The State of the document read from the table (an open object of the row would be this process' cached one, with the State it had when it was opened), or "".
ClassMethod State(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
	If rs.%Next() Quit rs.%Get("State")
	Quit ""
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

/// The number of rows of OcuTalon_Data.Document of the session.
ClassMethod Rows(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE AddedBy = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The number of upload rows of the session.
ClassMethod Uploads(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Upload WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// A Markdown runbook of an intro and two sections.
ClassMethod Runbook() As %String [ Private ]
{
	Set lf = $Char(10)
	Quit "# Results runbook" _ lf _ "This runbook covers the Results production, the lab results feed that the clinic reads every morning." _ lf _ lf _ "## Rotating the certificate" _ lf _ "1. Stop the item named Results.Sender." _ lf _ "2. Install the new certificate in the SSL configuration named ResultsClient, then restart the item." _ lf _ "3. Send one test result and write the new expiry date in the on-call log." _ lf _ lf _ "## Clearing the queue" _ lf _ "When the Results queue keeps growing, read why the message at its head fails, fix the cause and resend it." _ lf
}

Method TestAddMarkdown()
{
	If '..Ready() Quit
	Set session = ..Session("add")
	Set text = ..Runbook()
	Set sc = ..Add(session, "Results runbook.md", "markdown", ..Utf8(text), .result, .seconds)
	Do $$$AssertStatusOK(sc, "AddDocument is answered")
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", "with Ok 1, added and the Ref")
	Do $$$AssertTrue(seconds < 10, "in under 10 seconds: " _ seconds)
	Do $$$AssertEquals(result.Message, $Parameter("OcuTalon.Docs.Ops", "MESSAGEADDED"), "and the message of DocumentOps")
	Set ref = result.Ref
	Set row = ..Row(ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.OwnerRef _ "|" _ row.AddedBy _ "|" _ row.Name _ "|" _ row.ContentType _ "|" _ row.KnowledgeBase, "instance|" _ session _ "|Results runbook.md|markdown|OcuTalonKB.Docs", "OwnerRef instance, AddedBy the session, the name, the type and the table")
	Do $$$AssertEquals(row.Size, $Length(..Utf8(text)), "the size is the bytes of the file")
	Do $$$AssertEquals(..Uploads(session), 0, "the upload was taken, so nothing is left of it")
	Set row = ""
	Do $$$AssertTrue(..WaitState(ref, "ready"), "the document becomes ready")
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.Text.Read($$$MaxLocalLength), text, "the row keeps the text")
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Do $$$AssertEquals(row.Sections, "[""""," _ """Rotating the certificate"",""Clearing the queue""]", "Sections is the section of each chunk_index")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), passages.%Size(), "the table holds one row for each passage: " _ passages.%Size())
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT metadata, id FROM OcuTalonKB.Docs WHERE source = ? ORDER BY id", ref)
	Set n = 0
	While rs.%Next() {
		Set meta = {}.%FromJSON(rs.%Get("metadata"))
		Do $$$AssertEquals(meta.%ToJSON(), {"source": (ref), "chunk_index": (n), "document": "Results runbook", "section": (passages.%Get(n).section)}.%ToJSON(), "row " _ n _ ": source, chunk_index, document (the name without .md) and section")
		Set n = n + 1
	}
	Do ..WaitEvents(ref, "indexing,ready")
	Do $$$AssertEquals(..Events(ref), "indexing,ready", "the instance stream got an indexing event and then a ready event")
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

Method TestTooLong()
{
	If '..Ready() Quit
	Set session = ..Session("long")
	Set stream = ##class(%Stream.TmpBinary).%New()
	Set chunk = $Translate($Justify("", 100000), " ", "a")
	For i = 1:1:37 Do stream.Write(chunk)
	Do stream.Rewind()
	Set uploadRef = ##class(OcuTalon.Data.Upload).Put(session, stream, .put)
	Set sc = ..Add(session, "Huge.txt", "text", "", .result, .seconds, uploadRef)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", "a text of more bytes than a string holds is added as a row, with Ok 1 and the Ref")
	Set ref = result.Ref
	Do $$$AssertEquals(..State(ref) _ "|" _ ..Row(ref).Reason, "failed|failed", "which is failed with the reason failed, not indexed in part")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "and no KB row is written")
	Do $$$AssertEquals(..Events(ref), "failed", "with one failed event")
}

Method TestIndexingError()
{
	If '..Ready() Quit
	Set session = ..Session("broken")
	Set lf = $Char(10)
	Set text = ""
	For i = 1:1:10 Set text = text _ "## Step " _ i _ lf _ "The Results runbook step " _ i _ " says how to handle the certificate of lab " _ i _ "." _ lf _ lf
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = "instance", row.AddedBy = session, row.Name = "Broken.md", row.ContentType = "markdown", row.Size = $Length(text)
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc(), row.State = "indexing", row.KnowledgeBase = $Parameter(..#STORE, "TABLE")
	Do row.Text.Write(text)
	Do $$$AssertStatusOK(row.%Save(), "the row of a document whose first batch is written is made")
	Set ref = row.Ref
	Set row = ""
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Set batch = $Parameter("OcuTalon.Docs.Ops", "BATCH")
	Do $$$AssertTrue(passages.%Size() > batch, "the document has more passages than one batch: " _ passages.%Size())
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ref, "Broken", passages, 0, batch), "its first batch is written")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), batch, "as " _ batch _ " rows")
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Docs.Ops", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of DocumentOps is made")
	If '$IsObject(host) Quit
	Set index = ##class(OcuTalon.Docs.Msg.Index).%New()
	Set index.Ref = ref
	Set index.ChunkFrom = batch
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Set environ = ##class(%SYS.Python).Import("os").environ
	Do environ."__setitem__"(variable, "/dev/null/zz-docs-no-model/")
	Set sc = host.OnIndex(index, .response)
	Do ##class(OcuTalon.Test.Memory.Fixture).PutVariable(environ, previous)
	Do $$$AssertStatusOK(sc, "the next batch is handled although its passages cannot be embedded")
	Set row = ..Row(ref)
	Do $$$AssertEquals($Select($IsObject(row): row.State _ "|" _ row.Reason, 1: "none"), "failed|failed", "an error while a batch is written makes the document failed, with the reason failed")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "the rows that were written before the error are deleted")
	Do $$$AssertEquals(..Events(ref), "failed", "and the instance stream got a failed event")
}

Method TestPlainText()
{
	If '..Ready() Quit
	Set session = ..Session("plain")
	Set text = ""
	For i = 1:1:1000 Set text = text _ "word "
	Set sc = ..Add(session, "Words.TXT", "text", ..Utf8(text), .result, .seconds)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|added", "a plain-text document is added")
	Set ref = result.Ref
	Do $$$AssertTrue(..WaitState(ref, "ready"), "and becomes ready")
	Do $$$AssertTrue($ClassMethod(..#STORE, "Count", ref) '< 5, "with at least five passages: " _ $ClassMethod(..#STORE, "Count", ref))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT metadata, text FROM OcuTalonKB.Docs WHERE source = ?", ref)
	Set bad = ""
	While rs.%Next() {
		Set meta = {}.%FromJSON(rs.%Get("metadata"))
		If (meta.section '= "") || (meta.document '= "Words") || ($Length(rs.%Get("text")) > 1000) Set bad = bad _ " " _ meta."chunk_index"
	}
	Do $$$AssertEquals(bad, "", "each passage has no section, the name without .TXT and at most 1,000 characters")
	Set row = ..Row(ref)
	Set sections = {}.%FromJSON(row.Sections)
	Set filled = 0
	Set iterator = sections.%GetIterator()
	While iterator.%GetNext(, .value) {
		If value '= "" Set filled = filled + 1
	}
	Do $$$AssertEquals(sections.%Size() _ "|" _ filled, $ClassMethod(..#STORE, "Count", ref) _ "|0", "Sections holds an empty section for every passage")
}

Method TestUnreadable()
{
	If '..Ready() Quit
	Set session = ..Session("unreadable")
	Set cases = $ListBuild($ListBuild("not UTF-8", $Char(255, 254, 65)), $ListBuild("a NUL", "text" _ $Char(0) _ "more"), $ListBuild("blank after a BOM", $Char(239, 187, 191) _ "   " _ $Char(10, 13)), $ListBuild("empty", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		For type = "markdown", "text" {
			Set sc = ..Add(session, "bad.md", type, $List(case, 2), .result, .seconds)
			Set label = $List(case, 1) _ " as " _ type
			Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ (result.Ref '= ""), "1|added|1", label _ " is answered Ok 1 with the Ref")
			Set row = ..Row(result.Ref)
			Do $$$AssertEquals($Select($IsObject(row): row.State _ "|" _ row.Reason, 1: "no row"), "failed|unreadable", label _ " is a failed row with the reason unreadable")
			Do $$$AssertEquals(..Events(result.Ref), "failed", label _ " has the one event")
			Do $$$AssertEquals($ClassMethod(..#STORE, "Count", result.Ref), 0, label _ " writes no KB row")
		}
	}
	Set sc = ..Add(session, "bom.md", "markdown", $Char(239, 187, 191) _ ..Utf8("# Title" _ $Char(10) _ "Body text."), .result, .seconds)
	Do $$$AssertTrue(..WaitState(result.Ref, "ready"), "control: a file that starts with a BOM and has text is read")
	Set row = ..Row(result.Ref)
	Do $$$AssertEquals(row.Text.Read($$$MaxLocalLength), "# Title" _ $Char(10) _ "Body text.", "with the BOM stripped from its text")
}

Method TestUploadGone()
{
	If '..Ready() Quit
	Set session = ..Session("gone")
	Set other = ..Session("goneother")
	Set up = ..Upload(session, ..Utf8("some text"))
	Set sc = ..Add(session, "first.txt", "text", "", .first, .seconds, up)
	Do $$$AssertEquals(first.Ok _ "|" _ first.Outcome, "1|added", "the first add of an upload takes it")
	Set sc = ..Add(session, "second.txt", "text", "", .second, .seconds, up)
	Do $$$AssertEquals(second.Ok _ "|" _ second.Outcome _ "|" _ (second.Ref '= ""), "0|failed|1", "a second add of the same upload is Ok 0 failed with the Ref of a failed row")
	Set row = ..Row(second.Ref)
	Do $$$AssertEquals($Select($IsObject(row): row.State _ "|" _ row.Reason _ "|" _ row.Name, 1: "no row"), "failed|failed|second.txt", "the row is failed with the reason failed")
	Do $$$AssertEquals(..Events(second.Ref), "failed", "and has its event")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", second.Ref), 0, "and no KB row")
	Set sc = ..Add(session, "never.txt", "text", "", .never, .seconds, "zzNoSuchUpload00000001")
	Do $$$AssertEquals(never.Ok _ "|" _ never.Outcome, "0|failed", "an upload that never was gives the same")
	Set theirs = ..Upload(other, ..Utf8("their text"))
	Set sc = ..Add(session, "theirs.txt", "text", "", .stolen, .seconds, theirs)
	Do $$$AssertEquals(stolen.Ok _ "|" _ stolen.Outcome, "0|failed", "another session's upload gives the same")
	Do $$$AssertEquals(..Uploads(other), 1, "and the other session's upload is still there")
	Do $$$AssertTrue(..WaitState(first.Ref, "ready"), "control: the first document is indexed")
}

Method TestNoSession()
{
	If '..Ready() Quit
	Set session = ..Session("nosession")
	Set up = ..Upload(session, ..Utf8("text"))
	Set sc = ..Add("zzNoSuchSession0000001", "x.txt", "text", "", .result, .seconds, up)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|no_session|" _ $Parameter("OcuTalon.Docs.Ops", "MESSAGENOSESSION"), "AddDocument for an unknown session is Ok 0 no_session")
	Do $$$AssertEquals(..Uploads(session), 1, "and takes nothing")
	Set sc = ..Remove("zzNoSuchSession0000001", "zzNoSuchDocument000001", .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "0|no_session", "RemoveDocument for an unknown session is Ok 0 no_session")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE AddedBy = ?", "zzNoSuchSession0000001")
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "and no row was written")
}

Method TestOnlineDemo()
{
	If '..Ready() Quit
	Set session = ..Session("demo")
	Set up = ..Upload(session, ..Utf8("text"))
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set sc = ..Add(session, "x.txt", "text", "", .result, .seconds, up)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "0|not_built|" _ $Parameter("OcuTalon.Docs.Ops", "MESSAGENOTBUILT"), "on the online demo AddDocument is Ok 0 not_built")
	Do $$$AssertEquals(..Rows(session) _ "|" _ ..Uploads(session), "0|1", "it writes no row and takes nothing")
}

Method TestToolRefused()
{
	If '..Ready() Quit
	Set session = ..Session("tool")
	Set up = ..Upload(session, ..Utf8("text"))
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.SessionRef = session
	Set command.Name = "x.txt"
	Set command.ContentType = "text"
	Set command.UploadRef = up
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "0|not_allowed", "AddDocument from the origin tool is refused by CommandsIn")
	Do $$$AssertEquals(..Rows(session) _ "|" _ ..Uploads(session), "0|1", "and nothing is written or taken")
}

Method TestRemove()
{
	If '..Ready() Quit
	Set session = ..Session("remove")
	Set sc = ..Add(session, "Results runbook.md", "markdown", ..Utf8(..Runbook()), .added, .seconds)
	Set ref = added.Ref
	Do $$$AssertTrue(..WaitState(ref, "ready"), "a document is ready")
	Do $$$AssertTrue($ClassMethod(..#STORE, "Count", ref) > 0, "and has its rows")
	Set mine = ..Session("mine")
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = mine
	Set row.AddedBy = mine
	Set row.Name = "demo.md"
	Set row.ContentType = "markdown"
	Set row.State = "ready"
	Do row.%Save()
	Set foreign = row.Ref
	Set ..DocRefs = ..DocRefs _ $ListBuild(foreign)
	Set row = ""
	Set sc = ..Remove(session, ref, .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome _ "|" _ result.Message, "1|removed|" _ $Parameter("OcuTalon.Docs.Ops", "MESSAGEREMOVED"), "RemoveDocument is Ok 1 removed")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "the KB rows are gone")
	Do $$$AssertEquals($IsObject(..Row(ref)), 0, "and so is the row")
	Do $$$AssertEquals(..Events(ref), "indexing,ready,ready+", "the last event is the document with removed true")
	Set sc = ..Remove(session, ref, .again)
	Do $$$AssertEquals(again.Ok _ "|" _ again.Outcome, "0|not_found", "a second Remove is not_found")
	Set sc = ..Remove(session, "zzNoSuchDocument000001", .unknown)
	Do $$$AssertEquals(unknown.Ok _ "|" _ unknown.Outcome, "0|not_found", "an unknown Ref is not_found")
	Set sc = ..Remove(session, foreign, .theirs)
	Do $$$AssertEquals(theirs.Ok _ "|" _ theirs.Outcome, "0|not_found", "a document of another owner is not_found")
	Do $$$AssertEquals($IsObject(..Row(foreign)), 1, "and stays")
}

Method TestRemoveWhileIndexing()
{
	If '..Ready() Quit
	Set session = ..Session("racing")
	Set text = ""
	For i = 1:1:40 Set text = text _ "## Part " _ i _ $Char(10) _ "Paragraph " _ i _ " of the long runbook describes one more thing to check." _ $Char(10, 10)
	Set sc = ..Add(session, "Long.md", "markdown", ..Utf8(text), .added, .seconds)
	Set ref = added.Ref
	Do $$$AssertEquals(added.Ok, 1, "a long document is added")
	Set row = ..Row(ref)
	Do $$$AssertEquals($IsObject(row) && (row.State = "indexing"), 1, "and is still indexing: 40 passages take several batches")
	Set row = ""
	Set sc = ..Remove(session, ref, .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "RemoveDocument queued behind the batches is Ok 1 removed")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "no KB row of the document is left")
	Hang 5
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref) _ "|" _ $IsObject(..Row(ref)), "0|0", "and the batches that were queued behind the Remove wrote none, and made no row")
	Set events = ..Events(ref)
	Do $$$AssertEquals($Piece(events, ",", $Length(events, ",")), "indexing+", "the last event is the document with removed true: " _ events)
}

Method TestSecondAddKeepsOthers()
{
	If '..Ready() Quit
	Set session = ..Session("again")
	Set text = ..Utf8(..Runbook())
	Set sc = ..Add(session, "Results runbook.md", "markdown", text, .x, .seconds)
	Set sc = ..Add(session, "Results runbook.md", "markdown", text, .y, .seconds)
	Set sc = ..Add(session, "Other.md", "markdown", ..Utf8("## Other" _ $Char(10) _ "Something else entirely."), .z, .seconds)
	Do $$$AssertTrue(x.Ref '= y.Ref, "adding the same file again makes a new document with its own Ref")
	For ref = x.Ref, y.Ref, z.Ref {
		Do $$$AssertTrue(..WaitState(ref, "ready"), ref _ " becomes ready")
	}
	Set nx = $ClassMethod(..#STORE, "Count", x.Ref), ny = $ClassMethod(..#STORE, "Count", y.Ref), nz = $ClassMethod(..#STORE, "Count", z.Ref)
	Do $$$AssertEquals(nx _ "|" _ nz, ny _ "|1", "the first two have the same number of passages of their own, the third one")
	Set sc = ..Remove(session, x.Ref, .result)
	Do $$$AssertEquals(result.Outcome, "removed", "the first is removed")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", x.Ref) _ "|" _ $ClassMethod(..#STORE, "Count", y.Ref) _ "|" _ $ClassMethod(..#STORE, "Count", z.Ref), "0|" _ ny _ "|" _ nz, "and only its passages went: the second's and the third's stay")
}

}
