/// Tests of the owner rule of the documents' tables and of the documents tool of a turn (Story 19.5; AD-3, AD-4, AD-21, AD-31). THEY RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), on OcuTalon's Docker image: the passages are embedded by the Embedder worker. They skip elsewhere. Each test makes its own Session rows
/// (zz-doc-turntools), tables, document rows and passages, and removes them, and puts the public setting onlineDemo back.
///   - TestOwnerAndTable: the owner of a document is the session on the online demo and instance on a local install; the table of instance is OcuTalonKB.Docs, of
///     eval OcuTalonKB.Eval and of a session OcuTalonKB.S<id>, <id> being the Session row's id; a Ref that no row has, a Ref that differs in case and an empty
///     Ref have no table;
///   - TestKinds: Tools gives no tool for the kinds decide and diagnose, one holder over OcuTalonKB.Docs for a local turn, one over OcuTalonKB.Eval for the owner
///     eval, and a holder gives its tool to a bare %AI.ToolMgr;
///   - TestNoTable: a demo session that has no table (no document yet), whose table was dropped, and a Ref with no Session row (after a reset) get no tool, and no
///     table, class or global is made, nothing in OCUTALON_DATA;
///   - TestOwnSourceOnly: with two demo sessions that each added a document, the holder of one searched through a bare %AI.ToolMgr finds only that session's source,
///     and the other's finds only its own.
Class OcuTalon.Test.Docs.TurnTools Extends %UnitTest.TestCase
{

Parameter STORE = "OcuTalon.Docs.Store";

Parameter TURNTOOLS = "OcuTalon.Docs.TurnTools";

Parameter USER = "zz-doc-turntools";

Parameter A = "zz-doc-turntools-a";

Parameter B = "zz-doc-turntools-b";

/// The Refs of the Session rows that the test made, comma-separated.
Property Refs As %String(MAXLEN = "");

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
	Set ..Refs = ""
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

/// Drops the tables of the test's sessions and the rows of the install's table, and deletes the Session rows.
Method Clean() [ Private ]
{
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref '= "" Do ##class(OcuTalon.Docs).DropSession(ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	If $SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") {
		Do $ClassMethod(..#STORE, "Remove", ..#A)
		Do $ClassMethod(..#STORE, "Remove", ..#B)
	}
	If $SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Eval") Do $ClassMethod(..#STORE, "Remove", ..#A, "OcuTalonKB.Eval")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", $Parameter(..#STORE, "LOGATTACH"))
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// A Session row of the test; its Ref.
Method NewSession(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..#USER _ "-" _ name)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// The Session row id of the Ref.
ClassMethod IdOf(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).%Id()
}

/// A small runbook's passages, with a distinctive word.
ClassMethod Passages(word As %String) As %DynamicArray [ Private ]
{
	Set lf = $Char(10)
	Set text = "# " _ word _ " runbook" _ lf _ "This runbook covers the " _ word _ " production." _ lf _ lf _ "## Rotating the certificate" _ lf _ "1. Stop the item named " _ word _ ".Sender." _ lf _ "2. Install the new certificate, then restart the item." _ lf _ "3. Send one test result."
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Quit passages
}

/// Makes the table of the owner (through Docs.Store, as DocumentOps does) and writes the document into it.
Method Index(owner As %String, ref As %String, word As %String) As %String [ Private ]
{
	Set table = $ClassMethod(..#STORE, "TableFor", owner)
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", table), "the table " _ table _ " is made")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ref, word, ..Passages(word), 0, 100, table), "the document " _ ref _ " is written to it")
	Quit table
}

/// The sources of the results that the tool documents of the holder gives for the query, comma-separated and sorted, through a bare %AI.ToolMgr.
ClassMethod Sources(holder As OcuTalon.Docs.Store, query As %String) As %String
{
	Set agent = ##class(%AI.Agent).%New()
	Do holder.AddToManager(agent.ToolManager)
	Set result = agent.ToolManager.ExecuteTool("documents", {"query": (query)})
	Set iterator = result.value.%GetIterator()
	While iterator.%GetNext(, .item) {
		Set found(item.metadata.source) = ""
	}
	Set sources = ""
	Set source = ""
	For {
		Set source = $Order(found(source))
		Quit:source=""
		Set sources = sources _ $Select(sources = "": "", 1: ",") _ source
	}
	Quit sources
}

Method TestOwnerAndTable()
{
	If '..OnImage() Quit
	Set store = ..#STORE
	Set a = ..NewSession("a")
	Set id = ..IdOf(a)
	Do $$$AssertEquals($ClassMethod(store, "OwnerFor", a), "instance", "on a local install the owner of a session's document is instance")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", "instance", .suffix) _ "|" _ suffix, "OcuTalonKB.Docs|Docs", "the table of instance is OcuTalonKB.Docs, suffix Docs")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", "eval", .suffix) _ "|" _ suffix, "OcuTalonKB.Eval|Eval", "of eval OcuTalonKB.Eval, suffix Eval")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", a, .suffix) _ "|" _ suffix, "OcuTalonKB.S" _ id _ "|S" _ id, "of a session OcuTalonKB.S<id>, the Session row's id")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do $$$AssertEquals($ClassMethod(store, "OwnerFor", a), a, "on the online demo the owner is the session itself")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", $ClassMethod(store, "OwnerFor", a)), "OcuTalonKB.S" _ id, "and its table OcuTalonKB.S<id>")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", $ZConvert(a, "U")) _ "|" _ $ClassMethod(store, "TableFor", $ZConvert(a, "L")), "|", "a Ref that differs in case has no table (the Ref index finds it in any case, the rule compares exactly)")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", "zzNoSuchSession0000001", .suffix) _ "|" _ suffix, "|", "a Ref that no Session row has has none")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", "", .suffix) _ "|" _ suffix, "|", "and the empty Ref has none")
	Do $$$AssertEquals($ClassMethod(store, "TableFor", "OcuTalonKB.Docs; DROP TABLE x") _ "|" _ $ClassMethod(store, "TableFor", "Docs"), "|", "nor does a text that is no Ref")
	Do $$$AssertEquals($ClassMethod(store, "OwnerOf", "OcuTalonKB.Docs") _ "|" _ $ClassMethod(store, "OwnerOf", "OcuTalonKB.Eval") _ "|" _ $ClassMethod(store, "OwnerOf", "OcuTalonKB.S" _ id) _ "|" _ $ClassMethod(store, "OwnerOf", "OcuTalonKB.S999999999") _ "|" _ $ClassMethod(store, "OwnerOf", "Other.Docs"), "instance|eval|" _ a _ "|S999999999|", "the owner whose lock orders a table's writers")
}

Method TestKinds()
{
	If '..OnImage() Quit
	Set tools = ..#TURNTOOLS
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table of the install is there")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable", "OcuTalonKB.Eval"), "and so is the evaluation table")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Alpha", ..Passages("Alpha"), 0, 100), "a person's document is written to OcuTalonKB.Docs")
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#A, "Beta", ..Passages("Beta"), 0, 100, "OcuTalonKB.Eval"), "and an evaluation document, with the same Ref, to OcuTalonKB.Eval")
	For kind = "decide", "diagnose" {
		Set sc = $ClassMethod(tools, "Tools", "an-owner", kind, .list)
		Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|0", "the kind " _ kind _ " gets no tool")
	}
	Set sc = $ClassMethod(tools, "Tools", "an-owner", "turn", .list)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|1", "a local turn gets one holder")
	If list.Count() = 1 {
		Do $$$AssertTrue(list.GetAt(1).%IsA(..#STORE), "which is a Docs.Store holder")
		Do $$$AssertEquals(..Sources(list.GetAt(1), "how do I rotate the certificate?"), ..#A, "its tool finds the person's document")
		Do $$$AssertEquals(list.GetAt(1).VectorStore.TableName, "OcuTalonKB.Docs", "over OcuTalonKB.Docs")
	}
	Set sc = $ClassMethod(tools, "Tools", "eval", "turn", .list)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|1", "the owner eval gets one holder")
	If list.Count() = 1 Do $$$AssertEquals(list.GetAt(1).VectorStore.TableName, "OcuTalonKB.Eval", "over OcuTalonKB.Eval")
	Set sc = $ClassMethod(tools, "Tools", "eval", "decide", .list)
	Do $$$AssertEquals(list.Count(), 0, "and no kind but turn gets any")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Ext.TurnTools", "%IsA", tools) _ "|" _ $ClassMethod(tools, "%Extends", "OcuTalon.Bridge.Ext.TurnTools"), "0|1", "Docs.TurnTools extends the bridge's TurnTools")
}

Method TestNoTable()
{
	If '..OnImage() Quit
	Set tools = ..#TURNTOOLS
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set a = ..NewSession("notable")
	Set id = ..IdOf(a)
	Set table = "OcuTalonKB.S" _ id
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table), 0, "control: the session has no table")
	Set sc = $ClassMethod(tools, "Tools", a, "turn", .list)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|0", "a session that added no document gets no tool")
	Do $$$AssertEquals(..Traces(id), "0|0|0|0|", "and nothing is made: no table, no _Config table, no class and no global, nothing in OCUTALON_DATA")
	// A table that was dropped is not made again by a turn.
	Do ..Index(a, ..#A, "Alpha")
	Do $$$AssertEquals($SYSTEM.SQL.Schema.TableExists(table), 1, "control: the session's first document made its table")
	Set sc = $ClassMethod(tools, "Tools", a, "turn", .list)
	Do $$$AssertEquals(list.Count(), 1, "and the turn then gets the tool")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(a), "the session's documents are dropped")
	Set sc = $ClassMethod(tools, "Tools", a, "turn", .list)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|0", "a session whose table is gone gets no tool")
	Do $$$AssertEquals(..Traces(id), "0|0|0|0|", "and the turn made nothing")
	// A Ref that no Session row has (after a reset) has no table to name.
	Set gone = "zzNoSuchSession0000002"
	Set sc = $ClassMethod(tools, "Tools", gone, "turn", .list)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ list.Count(), "1|0", "a Ref with no Session row gets no tool")
	Do $$$AssertEquals($Data(^OcuTalonP.KBS0) _ "|" _ $SYSTEM.SQL.Schema.TableExists("OcuTalonKB.S0"), "0|0", "and no table is made for it")
}

Method TestOwnSourceOnly()
{
	If '..OnImage() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set a = ..NewSession("a")
	Set b = ..NewSession("b")
	Do ..Index(a, ..#A, "Alpha")
	Do ..Index(b, ..#B, "Beta")
	Set query = "how do I rotate the certificate?"
	Set sc = $ClassMethod(..#TURNTOOLS, "Tools", a, "turn", .listA)
	Set sc = $ClassMethod(..#TURNTOOLS, "Tools", b, "turn", .listB)
	Do $$$AssertEquals(listA.Count() _ "|" _ listB.Count(), "1|1", "each session gets a holder")
	If (listA.Count() '= 1) || (listB.Count() '= 1) Quit
	Do $$$AssertEquals(..Sources(listA.GetAt(1), query), ..#A, "the first session's tool finds only its own source")
	Do $$$AssertEquals(..Sources(listB.GetAt(1), query), ..#B, "the second session's tool finds only its own source")
	Do $$$AssertEquals(..Sources(listA.GetAt(1), query), ..#A, "again the first, after the second")
}

/// "table|config|class|global|data" for the session id: whether OcuTalonKB.S<id> and its _Config table exist, whether the class OcuTalonKB.S<id> is compiled, whether
/// ^OcuTalonP.KBS<id> exists, and the OCUTALON_DATA globals that start with OcuTalonKB, OcuTalonP.KBS<id> (their names, "" for none).
ClassMethod Traces(id As %Integer) As %String
{
	Set table = "OcuTalonKB.S" _ id
	Quit ($SYSTEM.SQL.Schema.TableExists(table)) _ "|" _ ($SYSTEM.SQL.Schema.TableExists(table _ "_Config")) _ "|" _ (##class(%Dictionary.CompiledClass).%ExistsId(table)) _ "|" _ ($Data(@("^OcuTalonP.KBS" _ id)) > 0) _ "|" _ ..DataDatabase("OcuTalonP.KBS" _ id)
}

/// The names (without the caret) of the globals of OCUTALON_DATA that start with the prefix or with OcuTalonKB, comma-separated.
ClassMethod DataDatabase(prefix As %String) As %String
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Config.Databases).Get("OCUTALON_DATA", .properties)
	Set reference = "^^" _ ##class(%File).NormalizeDirectory(properties("Directory"))
	Set names = ""
	Set found = $Order(^$|reference|GLOBAL(""))
	While found '= "" {
		// The names of ^$GLOBAL carry the caret.
		Set name = $Extract(found, 2, *)
		If ($Extract(name, 1, $Length(prefix)) = prefix) || ($Extract(name, 1, 10) = "OcuTalonKB") Set names = names _ $Select(names = "": "", 1: ",") _ name
		Set found = $Order(^$|reference|GLOBAL(found))
	}
	Quit names
}

}
