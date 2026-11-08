/// Tests of the knowledge-base tables of the documents (Stories 19.4 and 19.5; AD-3, AD-5, AD-6, AD-21; the Contest Planner's ruling Q2). THEY RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21), on OcuTalon's Docker image: the passages are embedded by the Embedder worker. They skip elsewhere. Every row and every setting they write is
/// put back, and the table is left as it was found.
///   - TestEnsureTable: EnsureTable is idempotent; the table and its _Config table exist with AI Hub's columns;
///   - TestGlobals: the DDL's DEFAULTGLOBAL is ^OcuTalonP.KBDocs and ^OcuTalonP.KBDocsConfig, every global of both classes is under those names, each resolves to
///     OCUTALON_PRIVATE (GetGlobalDest), no ^IRIS.KNNIndex node is written, and the installer's private-data check passes;
///   - TestRowsAndSearch: Write puts one row for each passage (id <Ref>:<n>, source the Ref, text the passage, metadata {source, chunk_index, document, section},
///     a 384-value vector); a search through a bare %AI.ToolMgr and AI Hub's knowledge base, built by Knowledge, finds the passage that answers the question first
///     with a score over the floor and its metadata, and Remove makes the next search return none of its rows (AD-21);
///   - TestWriteTwice: the same batch written twice leaves one row for each passage (a message redelivered after a restart);
///   - TestEmptyTable: with no row, a search returns the empty list;
///   - TestOtherDocumentsStay (Q2 c): re-indexing X (Remove, then Write) leaves Y's rows, and two documents of the same name are two documents;
///   - TestKnowledge (Story 19.5): Knowledge of the table of the install gives the holder, which adds the tool documents to a bare tool manager; a table that does
///     not exist, a name that is no knowledge-base table and a table whose build fails give no holder and an OK status, the first two with nothing made (no table,
///     class or global) and the last with one Type 3 warning;
///   - TestTableArgument (Story 19.5): EnsureTable, Write, Count and Remove of another table (OcuTalonKB.S<digits>) change that table and no other; a name whose
///     suffix is not Docs, Eval or S and digits is refused before any SQL;
///   - TestDrain (Story 19.5): while an owner is marked as being dropped (Drain), Write with that owner writes no passage and answers OK, and once the mark is
///     cleared it writes them;
///   - TestDrop (Story 19.5): Drop removes the table and its _Config table with their classes and their globals, and a second Drop and the drop of a table that was
///     never made are OK; a bad name is refused and nothing is dropped; a search through a knowledge base built before the drop makes no table.
Class OcuTalon.Test.Docs.Store Extends %UnitTest.TestCase
{

Parameter STORE = "OcuTalon.Docs.Store";

Parameter A = "zz-doc-store-a";

Parameter B = "zz-doc-store-b";

/// What Fixture.Prepare changed (the worker category and the embedding config), put back in OnAfterAllTests.
Property State As %String [ MultiDimensional ];

/// The public setting onlineDemo before the tests.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
	Merge ..State = state
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Merge state = ..State
	If $Data(state) Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Quit $$$OK
}

/// A table that the tests make besides the install's, and another whose build fails.
Parameter OTHER = "OcuTalonKB.S9098";

Parameter BROKEN = "OcuTalonKB.S9099";

/// Deletes the rows of the test's documents and the tables that the tests made.
ClassMethod Clean() [ Private ]
{
	For table = ..#OTHER, ..#BROKEN {
		Do ##class(OcuTalon.Test.Memory.Fixture).DropTable(table, $Piece(table, ".", 2))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
	If '$SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") Quit
	For ref = ..#A, ..#B, ..#A _ "-2" {
		Do $ClassMethod(..#STORE, "Remove", ref)
	}
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// The passages of a small runbook: an intro, the rotation steps and the queue.
ClassMethod Runbook() As %DynamicArray [ Private ]
{
	Set lf = $Char(10)
	Set text = "# Results runbook" _ lf _ "This runbook covers the Results production, the lab results feed that the clinic reads every morning." _ lf _ lf _ "## Rotating the certificate" _ lf _ "1. Stop the item named Results.Sender." _ lf _ "2. Install the new certificate in the SSL configuration named ResultsClient, then restart the item." _ lf _ "3. Send one test result and write the new expiry date in the on-call log." _ lf _ lf _ "## Clearing the queue" _ lf _ "When the Results queue keeps growing, read why the message at its head fails, fix the cause and resend it."
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Quit passages
}

/// A bare agent whose tool manager has the knowledge base of the table (Knowledge, then the holder's AddToManager); holder keeps the AI Hub objects alive.
ClassMethod Agent(Output holder, table As %String = "OcuTalonKB.Docs") As %AI.Agent [ Private ]
{
	Set agent = ##class(%AI.Agent).%New()
	Do $ClassMethod(..#STORE, "Knowledge", table, .holder)
	If $IsObject(holder) Do holder.AddToManager(agent.ToolManager)
	Quit agent
}

/// The result of a search of the documents tool as a dynamic array of items.
ClassMethod Search(agent As %AI.Agent, query As %String, top As %Integer = 5) As %DynamicArray [ Private ]
{
	Set result = agent.ToolManager.ExecuteTool("documents", {"query": (query), "top_k": (top)})
	Quit result.value
}

/// The ids of the items, comma-separated.
ClassMethod Ids(items As %DynamicArray) As %String [ Private ]
{
	Set result = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set result = result _ $Select(result '= "": ",", 1: "") _ item.id
	}
	Quit result
}

/// The first item of the search (the best score) whose source is the Ref, or "" when there is none; another document's rows never decide it.
ClassMethod FirstOf(items As %DynamicArray, ref As %String) As %DynamicObject [ Private ]
{
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		If item.metadata.source = ref Return item
	}
	Quit ""
}

/// The number of items of the search whose source is the Ref.
ClassMethod Holds(items As %DynamicArray, ref As %String) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .item) {
		If item.metadata.source = ref Set count = count + 1
	}
	Quit count
}

Method TestWriteTwice()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Set passages = ..Runbook()
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 2), "a batch is written")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 2), "and the same batch again, as a redelivered message would")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A), 2, "leaves one row for each passage")
}

Method TestEnsureTable()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "EnsureTable answers OK")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "and again, with nothing to do")
	Do $$$AssertTrue($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs"), "the table OcuTalonKB.Docs exists")
	Do $$$AssertTrue($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs_Config"), "and so does OcuTalonKB.Docs_Config")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'OcuTalonKB' AND TABLE_NAME = 'Docs' ORDER BY COLUMN_NAME")
	Set columns = ""
	While result.%Next() {
		Set columns = columns _ $Select(columns '= "": ",", 1: "") _ result.%Get("COLUMN_NAME")
	}
	Do $$$AssertEquals(columns, "id,metadata,source,text,vector", "the table has AI Hub's columns, and no other")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'OcuTalonKB' AND TABLE_NAME = 'Docs_Config' ORDER BY COLUMN_NAME")
	Set columns = ""
	While result.%Next() {
		Set columns = columns _ $Select(columns '= "": ",", 1: "") _ result.%Get("COLUMN_NAME")
	}
	Do $$$AssertEquals(columns, "dimensions,model_name", "and the _Config table has its two")
}

Method TestGlobals()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", ..Runbook(), 0, 100), "passages are written")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Set listed = 0, outside = ""
	Set global = ""
	For {
		Set global = $Order(storage(global))
		Quit:global=""
		If $Extract(storage(global), 1, 15) '= "OcuTalonKB.Docs" Continue
		Set listed = listed + 1
		If $Extract(global, 1, 16) '= "OcuTalonP.KBDocs" Set outside = outside _ " " _ global
	}
	Do $$$AssertTrue(listed '< 4, "the two tables list their data, index and id globals: " _ listed)
	Do $$$AssertEquals(outside, "", "every one of them is under ^OcuTalonP.KBDocs")
	Set private = ##class(%File).NormalizeDirectory($Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.MemoryD"), "^", 2))
	Do $$$AssertTrue(private '= "", "the private database is found: " _ private)
	For global = "^OcuTalonP.KBDocs", "^OcuTalonP.KBDocsConfig" {
		Set resolved = ##class(%SYS.Namespace).GetGlobalDest($Namespace, global)
		Do $$$AssertEquals(##class(%File).NormalizeDirectory($Piece(resolved, "^", 2)), private, global _ " resolves to the private database")
	}
	Do $$$AssertTrue($Data(^OcuTalonP.KBDocs.1) > 0, "the rows are in ^OcuTalonP.KBDocs.1, under the DEFAULTGLOBAL")
	Do $$$AssertEquals($Data(^IRIS.KNNIndex), 0, "^IRIS.KNNIndex holds nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "and the private-data check of the installer passes")
	Set xdata = $Parameter("OcuTalonKB.Docs", "DEFAULTGLOBAL") _ "|" _ $Parameter("OcuTalonKB.DocsConfig", "DEFAULTGLOBAL")
	Do $$$AssertEquals(xdata, "^OcuTalonP.KBDocs|^OcuTalonP.KBDocsConfig", "the compiled classes carry the DEFAULTGLOBAL of the DDL")
}

Method TestRowsAndSearch()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Set passages = ..Runbook()
	Do $$$AssertEquals(passages.%Size(), 3, "the runbook has three passages")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 2), "the first two passages are written")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A), 2, "two rows")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 2, 8), "the rest, from chunk_index 2, in a batch that runs past the end")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A), 3, "three rows in all")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT id, text, source, metadata, vector FROM OcuTalonKB.Docs WHERE source = ? ORDER BY id", ..#A)
	Set n = 0
	While result.%Next() {
		Set meta = {}.%FromJSON(result.%Get("metadata"))
		Set passage = passages.%Get(n)
		Do $$$AssertEquals(result.%Get("id") _ "|" _ result.%Get("source"), ..#A _ ":" _ n _ "|" _ ..#A, "row " _ n _ " has the id <Ref>:<n> and the Ref as its source")
		Do $$$AssertEquals(result.%Get("text"), passage.text, "its text is the passage, without the heading")
		Do $$$AssertEquals(meta.%ToJSON(), {"source": (..#A), "chunk_index": (n), "document": "Runbook", "section": (passage.section)}.%ToJSON(), "its metadata is {source, chunk_index, document, section}")
		Set vector = ##class(OcuTalon.Test.Memory.Fixture).ToVector(result.%Get("vector"))
		Do $$$AssertEquals($Select($IsVector(vector): $VOP("length", vector), 1: 0), 384, "and a vector of 384 values")
		Set n = n + 1
	}
	Do $$$AssertEquals(n, 3, "the table holds three rows of the document")
	Set agent = ..Agent(.holder)
	Do $$$AssertTrue($IsObject(holder), "Knowledge gives a holder")
	Set items = ..Search(agent, "how do I rotate the Results certificate?")
	Set first = ..FirstOf(items, ..#A)
	Do $$$AssertEquals($Select($IsObject(first): first.metadata.document _ "|" _ first.metadata.section _ "|" _ first.metadata."chunk_index", 1: "none"), "Runbook|Rotating the certificate|1", "the passage about the certificate is the document's first result, with its document and section")
	Do $$$AssertTrue($IsObject(first) && (first.score '< $Parameter("OcuTalon.Bridge.Citations", "CITEFLOOR")), "and its score is over the floor: " _ $Select($IsObject(first): first.score, 1: "none"))
	Set items = ..Search(agent, "what is the capital of France?")
	Set first = ..FirstOf(items, ..#A)
	Do $$$AssertTrue($IsObject(first), "an unrelated question still gets passages of the document from AI Hub")
	Do $$$AssertTrue($IsObject(first) && (first.score < $Parameter("OcuTalon.Bridge.Citations", "CITEFLOOR")), "all below the floor: the document's best is " _ $Select($IsObject(first): first.score, 1: "none"))
	Set items = ..Search(agent, "how do I rotate the Results certificate?", 2)
	Do $$$AssertEquals(items.%Size(), 2, "a top_k of 2 gives two")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Remove", ..#A), "Remove deletes the document's rows")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A), 0, "none is left")
	Set items = ..Search(agent, "how do I rotate the Results certificate?")
	Do $$$AssertEquals(..Holds(items, ..#A), 0, "and the next search, on the same knowledge base, returns none of its passages")
}

Method TestEmptyTable()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count"), 0, "the table holds no row: every test removes its own")
	Set agent = ..Agent(.holder)
	Set items = ..Search(agent, "how do I rotate the Results certificate?")
	Do $$$AssertEquals(items.%Size(), 0, "a search of the empty table returns the empty list")
}

Method TestOtherDocumentsStay()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Set passages = ..Runbook()
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 100), "document X is written")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#B, "Other", passages, 0, 1), "and document Y")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A _ "-2", "Runbook", passages, 0, 100), "and document Z, the same file added again under its own Ref")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A) _ "|" _ $ClassMethod(..#STORE, "Count", ..#B) _ "|" _ $ClassMethod(..#STORE, "Count", ..#A _ "-2"), "3|1|3", "each has its own rows")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Remove", ..#A), "X is re-indexed: its rows are removed")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A) _ "|" _ $ClassMethod(..#STORE, "Count", ..#B) _ "|" _ $ClassMethod(..#STORE, "Count", ..#A _ "-2"), "0|1|3", "only X's rows went")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 100), "and written again")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A) _ "|" _ $ClassMethod(..#STORE, "Count", ..#B) _ "|" _ $ClassMethod(..#STORE, "Count", ..#A _ "-2"), "3|1|3", "Y's and Z's rows are as they were")
}

Method TestKnowledge()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Set agent = ##class(%AI.Agent).%New()
	Set sc = $ClassMethod(..#STORE, "Knowledge", "OcuTalonKB.Docs", .holder)
	Do $$$AssertStatusOK(sc, "Knowledge answers OK for the table of the install")
	Do $$$AssertTrue($IsObject(holder), "with a holder")
	If '$IsObject(holder) Quit
	Do $$$AssertStatusOK(holder.AddToManager(agent.ToolManager), "which adds its knowledge base to a tool manager")
	Set names = ""
	Try {
		Set result = agent.ToolManager.ExecuteTool("documents", {"query": "x"})
		Set names = $Select($IsObject(result.value): "documents", 1: "")
	} Catch exception {
		Set names = exception.DisplayString()
	}
	Do $$$AssertEquals(names, "documents", "and the tool documents answers")

	// A table that does not exist is never made, opened or built over.
	Set before = $Data(^OcuTalonP.KBS9097)
	Set sc = $ClassMethod(..#STORE, "Knowledge", "OcuTalonKB.S9097", .holder)
	Do $$$AssertStatusOK(sc, "Knowledge answers OK for a table that does not exist")
	Do $$$AssertEquals($IsObject(holder), 0, "with no holder")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.S9097") _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId("OcuTalonKB.S9097") _ "|" _ $Data(^OcuTalonP.KBS9097) _ "|" _ $Data(^OcuTalonP.KBS9097Config), "0|0|0|0", "and makes no table, no class and no global")
	Set sc = $ClassMethod(..#STORE, "Knowledge", "OcuTalonKB.Evil", .holder)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ $IsObject(holder), "1|0", "a name that is no knowledge-base table gives no holder either")

	// A build that fails is one warning.
	Do ##class(OcuTalon.Test.Memory.Fixture).CreateTable(..#BROKEN, "S9099")
	Do ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO " _ ..#BROKEN _ "_Config (model_name, dimensions) VALUES ('Other', 99)")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
	Set sc = $ClassMethod(..#STORE, "Knowledge", ..#BROKEN, .holder)
	Do $$$AssertStatusOK(sc, "a knowledge base that fails to build still answers OK")
	Do $$$AssertEquals($IsObject(holder), 0, "with no holder")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and logs one warning")
}

Method TestTableArgument()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table of the install exists")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", ..#OTHER), "the other table is made")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", ..#OTHER), "and again, with nothing to do")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(..#OTHER) _ "|" _ $SYSTEM.SQL.Schema.TableExists(..#OTHER _ "_Config"), "1|1", "the table and its _Config table exist")
	Do $$$AssertEquals($Parameter(..#OTHER _ "", "DEFAULTGLOBAL") _ "|" _ $Parameter(..#OTHER _ "Config", "DEFAULTGLOBAL"), "^OcuTalonP.KBS9098|^OcuTalonP.KBS9098Config", "with the DEFAULTGLOBAL of its own suffix")
	Set passages = ..Runbook()
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 100, ..#OTHER), "passages are written to the other table")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A, ..#OTHER) _ "|" _ $ClassMethod(..#STORE, "Count", ..#A) _ "|" _ $ClassMethod(..#STORE, "Count", "", ..#OTHER), "3|0|3", "they are in that table only")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#B, "Other", passages, 0, 1), "a document is written to the table of the install")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Remove", ..#A), "Remove of the first document on the table of the install")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A, ..#OTHER) _ "|" _ $ClassMethod(..#STORE, "Count", ..#B), "3|1", "leaves the other table and the other document")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Remove", ..#A, ..#OTHER), "Remove on the other table")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A, ..#OTHER), 0, "takes the rows of the other table")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Remove", ..#A, "OcuTalonKB.S9096"), "Remove on a table that does not exist is no error")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.S9096"), 0, "and makes none")
	For bad = "OcuTalonKB.Docs2", "OcuTalonKB.S", "OcuTalonKB.S12x", "OcuTalonKB.Docs WHERE 1=1", "Other.Docs", "OcuTalonKB", "OcuTalonKB.Evil.Docs", "OcuTalonKB.s9098", "OcuTalonKB.eval" {
		Set outcome = $$$ISERR($ClassMethod(..#STORE, "EnsureTable", bad)) _ $$$ISERR($ClassMethod(..#STORE, "Write", ..#A, "Runbook", passages, 0, 1, bad)) _ $$$ISERR($ClassMethod(..#STORE, "Remove", ..#A, bad)) _ $$$ISERR($ClassMethod(..#STORE, "Drop", bad)) _ ($ClassMethod(..#STORE, "Count", ..#A, bad) = -1) _ ($ClassMethod(..#STORE, "SuffixOf", bad) = "")
		Do $$$AssertEquals(outcome, "111111", "the name '" _ bad _ "' is refused by every method, before any SQL")
	}
	Do $$$AssertEquals($ClassMethod(..#STORE, "SuffixOf", "OcuTalonKB.Docs") _ "|" _ $ClassMethod(..#STORE, "SuffixOf", "OcuTalonKB.Eval") _ "|" _ $ClassMethod(..#STORE, "SuffixOf", "OcuTalonKB.S42"), "Docs|Eval|S42", "Docs, Eval and S with digits are the three suffixes")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") _ "|" _ $ClassMethod(..#STORE, "Count", ..#B), "1|1", "and the table of the install is as it was")
}

Method TestDrain()
{
	If '..OnImage() Quit
	Set owner = "zz-doc-store-owner"
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", ..#OTHER), "the other table is made")
	Try {
		Do $ClassMethod(..#STORE, "Drain", owner, 1)
		Do $$$AssertEquals($ClassMethod(..#STORE, "Draining", owner), 1, "the owner is marked as being dropped")
		Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", ..Runbook(), 0, 2, ..#OTHER, owner), "Write answers OK")
		Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A, ..#OTHER), 0, "and writes no passage")
		Do $ClassMethod(..#STORE, "Drain", owner, 0)
		Do $$$AssertEquals($ClassMethod(..#STORE, "Draining", owner), 0, "the mark is cleared")
		Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", ..Runbook(), 0, 2, ..#OTHER, owner), "Write answers OK")
		Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ..#A, ..#OTHER), 2, "and writes the passages")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the drain test ends without an exception")
	}
	Do $ClassMethod(..#STORE, "Drain", owner, 0)
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Drop", ..#OTHER), "the other table is dropped")
}

Method TestDrop()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", ..#OTHER), "the other table is made")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Runbook", ..Runbook(), 0, 100, ..#OTHER), "passages are written to it")
	Set agent = ..Agent(.holder, ..#OTHER)
	Do $$$AssertTrue($IsObject(holder), "a knowledge base is built over it")
	Do $$$AssertEquals($Data(^OcuTalonP.KBS9098.1) > 0, 1, "its rows are in ^OcuTalonP.KBS9098.1")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Drop", ..#OTHER), "Drop answers OK")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(..#OTHER) _ "|" _ $SYSTEM.SQL.Schema.TableExists(..#OTHER _ "_Config"), "0|0", "the table and its _Config table are gone")
	Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId(..#OTHER) _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId(..#OTHER _ "Config") _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId(..#OTHER _ "_Config"), "0|0|0", "with their classes")
	Do $$$AssertEquals($Data(^OcuTalonP.KBS9098) _ "|" _ $Data(^OcuTalonP.KBS9098Config), "0|0", "and their globals")
	Set result = ""
	Try {
		Set result = agent.ToolManager.ExecuteTool("documents", {"query": "how do I rotate the Results certificate?"})
	} Catch exception {
		Set result = ""
	}
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(..#OTHER) _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId(..#OTHER) _ "|" _ $Data(^OcuTalonP.KBS9098), "0|0|0", "a search through the knowledge base built before the drop makes no table, class or global")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Drop", ..#OTHER), "a second Drop is OK")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Drop", "OcuTalonKB.S9096"), "and so is the drop of a table that was never made")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.S9096") _ "|" _ ##class(%Dictionary.CompiledClass).%ExistsId("OcuTalonKB.S9096"), "0|0", "which makes nothing")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table of the install exists")
	Do $$$AssertStatusNotOK($ClassMethod(..#STORE, "Drop", "OcuTalonKB.Docs x"), "a name that is no table is refused")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs"), 1, "and the table of the install is still there")
}

}
