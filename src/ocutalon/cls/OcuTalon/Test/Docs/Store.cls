/// Tests of the local documents' knowledge base (Story 19.4; AD-3, AD-5, AD-6, AD-21; the Contest Planner's ruling Q2). THEY RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21), on OcuTalon's Docker image: the passages are embedded by the Embedder worker. They skip elsewhere. Every row and every setting they write is
/// put back, and the table is left as it was found.
///   - TestEnsureTable: EnsureTable is idempotent; the table and its _Config table exist with AI Hub's columns;
///   - TestGlobals: the DDL's DEFAULTGLOBAL is ^OcuTalonP.KBDocs and ^OcuTalonP.KBDocsConfig, every global of both classes is under those names, each resolves to
///     OCUTALON_PRIVATE (GetGlobalDest), no ^IRIS.KNNIndex node is written, and the installer's private-data check passes;
///   - TestRowsAndSearch: Write puts one row for each passage (id <Ref>:<n>, source the Ref, text the passage, metadata {source, chunk_index, document, section},
///     a 384-value vector); a search through a bare %AI.ToolMgr and AI Hub's knowledge base, built by Attach, finds the passage that answers the question first
///     with a score over the floor and its metadata, and Remove makes the next search return none of its rows (AD-21);
///   - TestWriteTwice: the same batch written twice leaves one row for each passage (a message redelivered after a restart);
///   - TestEmptyTable: with no row, a search returns the empty list;
///   - TestOtherDocumentsStay (Q2 c): re-indexing X (Remove, then Write) leaves Y's rows, and two documents of the same name are two documents;
///   - TestAttach: on the online demo Attach gives no holder and the agent has no documents tool; on a local install it gives the holder and the tool; a
///     failure is one Type 3 warning, no holder and no exception.
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

/// Deletes the rows of the test's documents.
ClassMethod Clean() [ Private ]
{
	If '$SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") Quit
	For ref = ..#A, ..#B, ..#A _ "-2" {
		Do $ClassMethod(..#STORE, "Remove", ref)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
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

/// Attaches the knowledge base to a bare agent and returns the agent; holder keeps the AI Hub objects alive.
ClassMethod Agent(Output holder) As %AI.Agent [ Private ]
{
	Set agent = ##class(%AI.Agent).%New()
	Do $ClassMethod(..#STORE, "Attach", agent, .holder)
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
	Do $$$AssertTrue($IsObject(holder), "Attach gives a holder")
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

Method TestAttach()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table exists")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set agent = ##class(%AI.Agent).%New()
	Set sc = $ClassMethod(..#STORE, "Attach", agent, .holder)
	Do $$$AssertStatusOK(sc, "Attach answers OK on the online demo")
	Do $$$AssertEquals($IsObject(holder), 0, "with no holder")
	Set tools = agent.ToolManager.%Discover()
	Do $$$AssertEquals(tools.%Size(), 0, "and the agent has no tool")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set agent = ##class(%AI.Agent).%New()
	Set sc = $ClassMethod(..#STORE, "Attach", agent, .holder)
	Do $$$AssertStatusOK(sc, "Attach answers OK on a local install")
	Do $$$AssertTrue($IsObject(holder), "with a holder")
	Set names = ""
	Try {
		Set result = agent.ToolManager.ExecuteTool("documents", {"query": "x"})
		Set names = $Select($IsObject(result.value): "documents", 1: "")
	} Catch exception {
		Set names = exception.DisplayString()
	}
	Do $$$AssertEquals(names, "documents", "and the tool documents answers")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
	Set sc = $ClassMethod(..#STORE, "Attach", "", .holder)
	Do $$$AssertStatusOK(sc, "an attach that fails (no agent) still answers OK")
	Do $$$AssertEquals($IsObject(holder), 0, "with no holder")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and logs one warning")
}

}
