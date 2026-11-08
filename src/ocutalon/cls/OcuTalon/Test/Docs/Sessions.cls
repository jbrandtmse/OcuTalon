/// Tests of the per-session knowledge bases of the online demo (Story 19.5; AD-3, AD-4, AD-21, AD-25, AD-33; FR-14, FR-15, DW-892). THEY RUN IN THROWAWAY STACKS AND
/// IN CI ONLY (Rule 21), on OcuTalon's Docker image: the real CommandsIn, DocumentOps, Embedder worker and tables, with no double. With the public setting onlineDemo
/// on, every command goes through Commands.Submit as web_user, as the documents route sends it, for two fixture sessions (zz-doc-sessions) that stand for two
/// visitors; the document events are read back from each session's stream. Each test makes its own sessions, documents, uploads, tables and events and removes them.
///   - TestFirstAdd: the first AddDocument of a session makes OcuTalonKB.S<id> and OcuTalonKB.S<id>_Config with AI Hub's columns and the DEFAULTGLOBAL
///     ^OcuTalonP.KBS<id>[Config], which resolve to OCUTALON_PRIVATE, with no global of the tables in OCUTALON_DATA and nothing in ^IRIS.KNNIndex, before any
///     knowledge base is built; the row has OwnerRef the session and KnowledgeBase its table; the document becomes ready; the events go to the session's stream;
///     the other session has no table and no row (DW-892: the demo route reaches ready);
///   - TestRemove: another session's RemoveDocument for the Ref is not_found and leaves it; the session's own removes its rows from its table and sends the last event;
///   - TestDropSession: Docs.DropSession of one visitor drops its tables, their classes and globals and its Document rows and leaves the other's, a second
///     DropSession is OK and changes nothing, and a Ref with no Session row, instance and eval drop nothing;
///   - TestDropWhileIndexing: DropSession right after AddDocument, while DocumentOps indexes a long document, leaves no table, no class, no global and no row,
///     and no later batch makes the table again;
///   - TestIndexingError: a batch that fails while a session's document is indexed makes the document failed with the reason failed, takes the rows its first
///     batch wrote out of the session's own table (not the install's), and sends one failed event to the session's stream and none to the instance's;
///   - TestDocumentsFeature (DW-892): the documents id is in Demo.Features Present() on this build, with the online demo on;
///   - TestDropLockHeld: while another job holds the owner's lock, DropSession returns an error status after 5 seconds and drops nothing; once it is free it
///     drops;
///   - TestBatchYieldsToDrop: a batch of DocumentOps (IndexBatch) for a session that is being dropped (Store Drain) writes no passage and stops as gone, a
///     batch while another job holds the owner's lock exclusively (as a drop does) returns an error status and writes nothing, and the same batch with the lock
///     free and no mark writes one batch.
Class OcuTalon.Test.Docs.Sessions Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zz-doc-sessions";

Parameter STORE = "OcuTalon.Docs.Store";

Parameter LIVE = "OcuTalon.Test.Docs.SessionLive";

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
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropAll()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..DropAll()
	Kill ^IRIS.Temp.ZzDocSessions
	Quit ##super()
}

/// Drops the documents and tables of the sessions of the run (Docs.DropSession), with their uploads and events.
Method DropAll() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Do ##class(OcuTalon.Data.Upload).DropSession(session)
		Do ##class(OcuTalon.Docs).DropSession(session)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = 'document'", session)
	}
}

/// 1 on the image and with the production running; otherwise records the skip or fails with the reason, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit 0
	}
	Quit 1
}

/// The table of the session's Session row: OcuTalonKB.S<id>.
ClassMethod TableOf(session As %String) As %String [ Private ]
{
	Quit "OcuTalonKB.S" _ ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
}

/// Adds a Markdown document as web_user through Commands.Submit; result is the CommandResult. Its Ref, or "".
Method Add(session As %String, name As %String, text As %String, Output result As OcuTalon.Msg.CommandResult) As %String [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Do stream.Write($ZConvert(text, "O", "UTF8"))
	Do stream.Rewind()
	Set up = ##class(OcuTalon.Data.Upload).Put(session, stream, .sc)
	Set command = ##class(OcuTalon.Msg.Command.AddDocument).%New()
	Set command.SessionRef = session
	Set command.Name = name
	Set command.ContentType = "markdown"
	Set command.UploadRef = up
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Quit $Select($IsObject(result): result.Ref, 1: "")
}

Method Remove(session As %String, ref As %String, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveDocument).%New()
	Set command.SessionRef = session
	Set command.DocumentRef = ref
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
}

/// The State of the document read from the table, or "".
ClassMethod State(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
	If rs.%Next() Quit rs.%Get("State")
	Quit ""
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

/// The states of the document's events on the stream, oldest first, comma-separated, with + after one whose removed is true.
ClassMethod Events(stream As %String, ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Payload FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = 'document' AND Payload [ ? ORDER BY Seq", stream, """ref"":""" _ ref _ """")
	Set states = ""
	While rs.%Next() {
		Set payload = {}.%FromJSON(rs.%Get("Payload"))
		Set states = states _ $Select(states '= "": ",", 1: "") _ payload.state _ $Select(payload.removed: "+", 1: "")
	}
	Quit states
}

/// The runbook of the story as Markdown: an intro and two sections, with a distinctive word in each.
ClassMethod Runbook(word As %String) As %String [ Private ]
{
	Set lf = $Char(10)
	Quit "# " _ word _ " runbook" _ lf _ "This runbook covers the " _ word _ " production." _ lf _ lf _ "## Rotating the certificate" _ lf _ "1. Stop the item named " _ word _ ".Sender." _ lf _ "2. Install the new certificate, then restart the item." _ lf _ lf _ "## Clearing the queue" _ lf _ "Read why the message at the head of the " _ word _ " queue fails, fix the cause and resend it."
}

/// Adds the runbook for the session and waits until it is ready; its Ref, or "" with an assertion failed.
Method AddReady(session As %String, name As %String, word As %String) As %String [ Private ]
{
	Set ref = ..Add(session, name, ..Runbook(word), .result)
	Do $$$AssertEquals($Select($IsObject(result): result.Ok _ "|" _ result.Outcome, 1: "none"), "1|added", name _ " is added")
	If ref = "" Quit ""
	Do $$$AssertTrue(..WaitState(ref, "ready"), name _ " becomes ready")
	Quit ref
}

Method TestFirstAdd()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set b = ..Session("b")
	Set table = ..TableOf(a)
	Set id = $Piece(table, ".S", 2)
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "control: the session has no table, class, global, document or memory before its first document")
	Set ref = ..AddReady(a, "Results runbook.md", "Results")
	If ref = "" Quit
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table) _ "|" _ $SYSTEM.SQL.Schema.TableExists(table _ "_Config"), "1|1", "the first AddDocument made the session's table and its _Config table")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'OcuTalonKB' AND TABLE_NAME = ? ORDER BY COLUMN_NAME", "S" _ id)
	Set columns = ""
	While rs.%Next() {
		Set columns = columns _ $Select(columns '= "": ",", 1: "") _ rs.%Get("COLUMN_NAME")
	}
	Do $$$AssertEquals(columns, "id,metadata,source,text,vector", "with AI Hub's columns")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'OcuTalonKB' AND TABLE_NAME = ? ORDER BY COLUMN_NAME", "S" _ id _ "_Config")
	Set columns = ""
	While rs.%Next() {
		Set columns = columns _ $Select(columns '= "": ",", 1: "") _ rs.%Get("COLUMN_NAME")
	}
	Do $$$AssertEquals(columns, "dimensions,model_name", "and its _Config table's two")
	Do $$$AssertEquals($Parameter(table, "DEFAULTGLOBAL") _ "|" _ $Parameter(table _ "Config", "DEFAULTGLOBAL"), "^OcuTalonP.KBS" _ id _ "|^OcuTalonP.KBS" _ id _ "Config", "their DEFAULTGLOBAL is under ^OcuTalonP.")
	Set private = ##class(%File).NormalizeDirectory($Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.MemoryD"), "^", 2))
	For global = "^OcuTalonP.KBS" _ id, "^OcuTalonP.KBS" _ id _ "Config" {
		Do $$$AssertEquals(##class(%File).NormalizeDirectory($Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, global), "^", 2)), private, global _ " resolves to OCUTALON_PRIVATE")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.TurnTools).DataDatabase("OcuTalonP.KBS" _ id), "", "no global of the tables is in OCUTALON_DATA")
	Do $$$AssertEquals($Data(^IRIS.KNNIndex), 0, "and ^IRIS.KNNIndex holds nothing")
	Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
	Do $$$AssertEquals(row.OwnerRef _ "|" _ row.AddedBy _ "|" _ row.KnowledgeBase _ "|" _ row.State, a _ "|" _ a _ "|" _ table _ "|ready", "the row has the session as its owner and its table as its KnowledgeBase")
	Set row = ""
	Do $$$AssertTrue($ClassMethod(..#STORE, "Count", ref, table) > 0, "its passages are in the session's table")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "and none in the table of the install")
	Do $$$AssertEquals(..Events(a, ref), "indexing,ready", "the events went to the session's stream")
	Do $$$AssertEquals(..Events("instance", ref) _ "|" _ ..Events(b, ref), "|", "and to no other")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(b), "0|0|0|0|0", "the other session has nothing")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE OwnerRef = ?", b)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "and no row")
}

Method TestRemove()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set b = ..Session("b")
	Set ref = ..AddReady(a, "Results runbook.md", "Results")
	If ref = "" Quit
	Set table = ..TableOf(a)
	Set sc = ..Remove(b, ref, .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "0|not_found", "another session's RemoveDocument for the Ref is not_found")
	Do $$$AssertEquals(..State(ref) _ "|" _ ($ClassMethod(..#STORE, "Count", ref, table) > 0), "ready|1", "and the document and its passages stay")
	Set sc = ..Remove(a, ref, .result)
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "the session's own RemoveDocument is removed")
	Do $$$AssertEquals(..State(ref) _ "|" _ $ClassMethod(..#STORE, "Count", ref, table), "|0", "the row and the passages are gone")
	Do $$$AssertEquals(..Events(a, ref), "indexing,ready,ready+", "the last event on the session's stream has removed true")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table), 1, "the table stays for the session's next document")
}

Method TestDropSession()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set b = ..Session("b")
	Set refA = ..AddReady(a, "Results runbook.md", "Results")
	Set refB = ..AddReady(b, "Partner runbook.md", "Partner")
	If (refA = "") || (refB = "") Quit
	Set live = ..#LIVE
	Set factsB = $ClassMethod(live, "Facts", b)
	Do $$$AssertEquals($Piece(factsB, "|", 1, 2) _ "|" _ $Piece(factsB, "|", 4), "2|2|1", "B has two tables, two classes and one document")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "DropSession(A) is OK")
	Do $$$AssertEquals($ClassMethod(live, "Facts", a), "0|0|0|0|0", "A has no table, class, global or document")
	Do $$$AssertEquals($ClassMethod(live, "Facts", b), factsB, "B's are as they were")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(refA)) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(refB)), "0|1", "A's Document row is gone and B's stays")
	Do $$$AssertTrue($ClassMethod(..#STORE, "Count", refB, ..TableOf(b)) > 0, "and B's passages")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "a second DropSession(A) is OK")
	Do $$$AssertEquals($ClassMethod(live, "Facts", a) _ "~" _ $ClassMethod(live, "Facts", b), "0|0|0|0|0~" _ factsB, "and changes nothing")
	Set instance = $ClassMethod(..#STORE, "Count")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(b), "the drop does not depend on the onlineDemo setting")
	Do $$$AssertEquals($ClassMethod(live, "Facts", b), "0|0|0|0|0", "B's are gone as well")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession("instance"), "DropSession(instance) is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession("eval"), "and so is DropSession(eval)")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession("zzNoSuchSession0000003"), "and a Ref with no Session row")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(""), "and the empty one")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") _ "|" _ $ClassMethod(..#STORE, "Count"), "1|" _ instance, "none of them touches the table of the install")
}

Method TestDropWhileIndexing()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set table = ..TableOf(a)
	Set text = ""
	For i = 1:1:60 Set text = text _ "## Step " _ i _ $Char(10) _ "The Results runbook step " _ i _ " describes how to handle the certificate, the queue and the lab number " _ i _ "." _ $Char(10, 10)
	Set ref = ..Add(a, "Long runbook.md", text, .result)
	Do $$$AssertEquals($Select($IsObject(result): result.Ok _ "|" _ result.Outcome, 1: "none"), "1|added", "a long document is added")
	If ref = "" Quit
	Do $$$AssertEquals(##class(OcuTalon.Data.Document).RefIndexOpen(ref).State, "indexing", "the document is still being indexed")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "DropSession while DocumentOps indexes it is OK")
	Hang 8
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "no table, class, global or row is left")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table) _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId(table) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(ref)), "0|0|0", "and a later batch made none again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.TurnTools).DataDatabase("OcuTalonP.KB"), "", "nothing of it is in OCUTALON_DATA")
}

Method TestIndexingError()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set table = ..TableOf(a)
	Set lf = $Char(10)
	Set text = ""
	For i = 1:1:10 Set text = text _ "## Step " _ i _ lf _ "The Results runbook step " _ i _ " says how to handle the certificate of lab " _ i _ "." _ lf _ lf
	Do $$$AssertStatusOK(##class(OcuTalon.Docs.Store).EnsureTable(table), "the session's table is made")
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = a, row.AddedBy = a, row.Name = "Broken.md", row.ContentType = "markdown", row.Size = $Length(text)
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc(), row.State = "indexing", row.KnowledgeBase = table
	Do row.Text.Write(text)
	Do $$$AssertStatusOK(row.%Save(), "the row of a session's document whose first batch is written is made")
	Set ref = row.Ref
	Set row = ""
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Set batch = $Parameter("OcuTalon.Docs.Ops", "BATCH")
	Do $$$AssertTrue(passages.%Size() > batch, "the document has more passages than one batch: " _ passages.%Size())
	Do $$$AssertStatusOK(##class(OcuTalon.Docs.Store).Write(ref, "Broken", passages, 0, batch, table, a), "its first batch is written to the session's table")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Store).Count(ref, table) _ "|" _ ##class(OcuTalon.Docs.Store).Count(ref), batch _ "|0", "as " _ batch _ " rows there and none in the table of the install")
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
	Do $$$AssertEquals(..State(ref), "failed", "the session's document is failed")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Store).Count(ref, table), 0, "the rows its first batch wrote are deleted from the session's table")
	Do $$$AssertEquals(..Events(a, ref) _ "|" _ ..Events("instance", ref), "failed|", "the session's stream got the failed event and the instance's got none")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table), 1, "the table stays for the session's next document")
}

Method TestDocumentsFeature()
{
	Set present = ##class(OcuTalon.Demo.Features).Present()
	Do $$$AssertEquals(##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"), "1", "control: the online demo is on")
	Do $$$AssertEquals($ListFind(present, "documents") > 0, 1, "the documents feature is listed on this build, so the demo offers it")
	Do $$$AssertEquals(+$Parameter("OcuTalon.Docs.Ops", "STUB"), 0, "because DocumentOps is no stub")
}

Method TestDropLockHeld()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set ref = ..AddReady(a, "Results runbook.md", "Results")
	If ref = "" Quit
	Kill ^IRIS.Temp.ZzDocSessions
	Job ##class(OcuTalon.Test.Docs.Sessions).Hold(a, 12)
	Set deadline = $ZHorolog + 20
	While '$Data(^IRIS.Temp.ZzDocSessions("held")) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^IRIS.Temp.ZzDocSessions("held")), 1, "another job holds the owner's lock")
	Set began = $ZHorolog
	Set sc = ##class(OcuTalon.Docs).DropSession(a)
	Set waited = $ZHorolog - began
	Do $$$AssertStatusNotOK(sc, "DropSession returns an error status")
	Do $$$AssertTrue(waited '< 4.5, "after the 5 seconds of the lock: " _ waited)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "busy", "that says the documents are busy: " _ $SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($Piece(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "|", 1, 2) _ "|" _ $Piece(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "|", 4), "2|2|1", "and drops nothing")
	Set deadline = $ZHorolog + 30
	While '$Data(^IRIS.Temp.ZzDocSessions("done")) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "once the lock is free DropSession is OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.SessionLive).Facts(a), "0|0|0|0|0", "and drops everything")
}

/// The job body of TestDropLockHeld and TestBatchYieldsToDrop: holds the owner's lock (shared, as a writer holds it, or exclusive, as a drop holds it) for the
/// seconds, and notes it.
ClassMethod Hold(owner As %String, seconds As %Integer, exclusive As %Boolean = 0)
{
	Set sc = ##class(OcuTalon.Docs.Store).LockOwner(owner, exclusive)
	Set ^IRIS.Temp.ZzDocSessions("held") = $$$ISOK(sc)
	Hang seconds
	Do ##class(OcuTalon.Docs.Store).UnlockOwner(owner, exclusive)
	Set ^IRIS.Temp.ZzDocSessions("done") = 1
}

Method TestBatchYieldsToDrop()
{
	If '..Ready() Quit
	Set a = ..Session("a")
	Set table = ..TableOf(a)
	Set lf = $Char(10)
	Set text = ""
	For i = 1:1:10 Set text = text _ "## Step " _ i _ lf _ "The Results runbook step " _ i _ " says how to handle the certificate of lab " _ i _ "." _ lf _ lf
	Do $$$AssertStatusOK(##class(OcuTalon.Docs.Store).EnsureTable(table), "the session's table is made")
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = a, row.AddedBy = a, row.Name = "Batch.md", row.ContentType = "markdown", row.Size = $Length(text)
	Set row.AddedAt = ##class(OcuTalon.Data.Time).NowUtc(), row.State = "indexing", row.KnowledgeBase = table
	Do row.Text.Write(text)
	Do $$$AssertStatusOK(row.%Save(), "the row of a session's document that is being indexed is made")
	Set ref = row.Ref
	Set row = ""
	Set ops = "OcuTalon.Docs.Ops"

	// The owner is marked as being dropped: the batch writes nothing and finds the document gone.
	Do ##class(OcuTalon.Docs.Store).Drain(a, 1)
	Set sc = $ClassMethod(ops, "IndexBatch", ref, 0, .state, .done)
	Do ##class(OcuTalon.Docs.Store).Drain(a, 0)
	Do $$$AssertStatusOK(sc, "a batch while the owner is being dropped is OK")
	Do $$$AssertEquals(state _ "|" _ ##class(OcuTalon.Docs.Store).Count(ref, table) _ "|" _ ..State(ref), "gone|0|indexing", "it stops as gone, writes no passage and leaves the row to the drop")

	// Another job holds the owner's lock as a drop does: the batch waits, fails and writes nothing.
	Kill ^IRIS.Temp.ZzDocSessions
	Job ##class(OcuTalon.Test.Docs.Sessions).Hold(a, 8, 1)
	Set deadline = $ZHorolog + 20
	While '$Data(^IRIS.Temp.ZzDocSessions("held")) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^IRIS.Temp.ZzDocSessions("held")), 1, "another job holds the owner's lock exclusively")
	Set sc = $ClassMethod(ops, "IndexBatch", ref, 0, .state, .done)
	Do $$$AssertStatusNotOK(sc, "a batch under a drop's lock returns an error status")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Store).Count(ref, table), 0, "and writes no passage")
	Set deadline = $ZHorolog + 30
	While '$Data(^IRIS.Temp.ZzDocSessions("done")) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Do $$$AssertEquals($Get(^IRIS.Temp.ZzDocSessions("done")), 1, "the job let the lock go")

	// Control: with the lock free and no mark, the batch writes.
	Set sc = $ClassMethod(ops, "IndexBatch", ref, 0, .state, .done)
	Do $$$AssertStatusOK(sc, "then the batch is OK")
	Do $$$AssertEquals(state _ "|" _ ##class(OcuTalon.Docs.Store).Count(ref, table), "more|" _ $Parameter(ops, "BATCH"), "and writes one batch of passages")
}

}
