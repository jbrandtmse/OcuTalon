/// Tests of the documents setup of the evaluation (Stories 19.4 and 19.5; AD-22, AD-1, AD-33). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), on OcuTalon's Docker
/// image: the passages are embedded by the Embedder worker. They skip elsewhere. Every file, row and setting they write is removed or put back.
/// AD-22 says an evaluation run writes no Notification, Delivery or live event; the documents kind adds documents before its turn, so these tests run its setup
/// (the real EvalIn.DocumentsUp and DocumentsDown, and Finish) and read what it wrote:
///   - TestIsolation: a documents case's files become ready documents of the owner eval (OwnerRef and AddedBy eval, passages in the table, sections kept), and the
///     setup wrote and deleted no Session row, no Upload row, no Delivery row and no live event, sent no Notification and no message to DocumentOps; no row of the documents is owned by
///     the instance or a session, which is all that the documents routes list; DocumentsDown and Finish take the passages and the rows away;
///   - TestLongDocument: AddEval indexes a document of more passages than one batch to the end: every passage is a row of the table, the document is ready and
///     owned by eval, and RemoveEval takes it away;
///   - TestEmbedFailure: AddEval for a document whose passages cannot be embedded (the worker's model folder made wrong in the test process) answers failed, gives no
///     ref and leaves no row and no passage;
///   - TestSecondFileFails: DocumentsUp for a case whose second file is unreadable answers the reason and takes the first file's document and passages away again;
///   - TestRefusals: RemoveEval refuses a document of the instance and leaves it; AddEval with no time left, a blank file and the online demo return their reasons and
///     leave no row and no passage;
///   - TestSweep (DW-900, Story 19.5): the documents of an earlier run that was killed before its Finish, one in OcuTalonKB.Eval and one in OcuTalonKB.Docs (where
///     Story 19.4's code put them), are removed with their passages when a run starts (Eval.In Start), and a document of the instance and its passages stay.
///   - TestSweepFails (DW-900, Story 19.5): a leftover document whose removal fails (its row names a table that is no knowledge-base table) is one warning
///     that names it, and the sweep goes on: a second leftover document, in OcuTalonKB.Eval, is removed with its passages.
/// The passages of the evaluation documents are in OcuTalonKB.Eval (Story 19.5, DW-901), which every count here reads unless it names another table.
Class OcuTalon.Test.Eval.Documents Extends %UnitTest.TestCase
{

Parameter STORE = "OcuTalon.Docs.Store";

Parameter OPS = "OcuTalon.Docs.Ops";

/// The table of the evaluation documents' passages.
Parameter EVAL = "OcuTalonKB.Eval";

Parameter GUARD = "zz-doc-evalguard";

/// The Ref of the document that a killed run left in OcuTalonKB.Docs (TestSweep).
Parameter LEFT = "zz-doc-evalleft";

/// The Ref of the leftover eval document whose removal fails (TestSweepFails).
Parameter BAD = "zz-doc-evalbad";

/// What Fixture.Prepare changed (the worker category and the embedding config), put back in OnAfterAllTests.
Property State As %String [ MultiDimensional ];

/// The public setting onlineDemo before the tests.
Property SavedOnline As %String;

/// The folder of the case files that the test made, removed afterwards.
Property Temp As %String(MAXLEN = 500);

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

/// Removes the case folder and the guard document of the tests, and every eval document they left.
Method Clean() [ Private ]
{
	If ..Temp '= "" {
		Do ##class(%File).RemoveDirectoryTree(..Temp)
		Set ..Temp = ""
	}
	Do ..DeleteRow(..#GUARD)
	Do ..DeleteRow(..#LEFT)
	Do ..DeleteRow(..#BAD)
	If '$SYSTEM.SQL.Schema.TableExists("OcuTalonKB.Docs") Quit
	Do $ClassMethod(..#STORE, "Remove", ..#GUARD)
	Do $ClassMethod(..#STORE, "Remove", ..#LEFT)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Document WHERE OwnerRef = 'eval' AND Name %STARTSWITH 'Zz eval'")
	While rs.%Next() {
		Do $ClassMethod(..#OPS, "RemoveEval", rs.%Get("Ref"))
	}
}

/// Deletes the document row of the Ref, if there is one.
ClassMethod DeleteRow(ref As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
	If '$IsObject(row) Quit
	Set id = row.%Id()
	Set row = ""
	Do ##class(OcuTalon.Data.Document).%DeleteId(id)
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// A folder of cases with one case folder that holds runbook.md, as {"cases", "folder"}; the root is removed by Clean.
Method MakeCase() As %DynamicObject [ Private ]
{
	Set unique = ##class(%File).TempFilename("tmp")
	Do ##class(%File).Delete(unique)
	Set ..Temp = ##class(%File).NormalizeDirectory(unique)
	Set cases = ##class(%File).NormalizeDirectory(..Temp _ "cases")
	Set folder = ##class(%File).NormalizeDirectory(cases _ "zz-eval-documents")
	Do ##class(%File).CreateDirectoryChain(folder)
	Set file = ##class(%Stream.FileCharacter).%New()
	Do file.LinkToFile(folder _ "runbook.md")
	Do file.WriteLine("# Zz runbook")
	Do file.WriteLine("")
	Do file.WriteLine("## Rotating the certificate")
	Do file.WriteLine("Stop the item named Results.Sender, install the new certificate, then start the item again.")
	Do file.WriteLine("")
	Do file.WriteLine("## Queue is stuck")
	Do file.WriteLine("Restart the Results.Router item and check the queue depth after a minute.")
	Do file.%Save()
	Quit {"cases": (cases), "folder": (folder)}
}

/// The counts and marks that an evaluation must not move, as one text: the Session, Upload and Delivery rows (number and highest id), the message headers
/// from or to DocumentOps and the message headers of a Notification (AD-22).
ClassMethod Marks() As %String [ Private ]
{
	Set text = ""
	For sql = "SELECT COUNT(*), MAX(ID) FROM OcuTalon_Data.Session", "SELECT COUNT(*), MAX(ID) FROM OcuTalon_Data.Upload", "SELECT COUNT(*), MAX(ID) FROM OcuTalon_Data.Delivery", "SELECT COUNT(*), MAX(ID) FROM Ens.MessageHeader WHERE TargetConfigName = 'DocumentOps' OR SourceConfigName = 'DocumentOps'", "SELECT COUNT(*), MAX(ID) FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Msg.Notification'" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
		Do rs.%Next()
		Set text = text _ $Select(text = "": "", 1: ";") _ rs.%GetData(1) _ "/" _ rs.%GetData(2)
	}
	Quit text
}

/// The highest id of a table, for the rows written since.
ClassMethod Max(table As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM " _ table)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of live events since the mark, of every type but the ones that the production's monitors publish on their own clock (status, guide.state, heartbeat, reset).
ClassMethod Events(mark As %Integer) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE ID > ? AND Type NOT IN ('status', 'guide.state', 'heartbeat', 'reset')", mark)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// A documents case's setup is isolated (AD-22, AD-1, AD-33): see the class description.
Method TestIsolation()
{
	If '..OnImage() Quit
	Set made = ..MakeCase()
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Eval.In", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of EvalIn is made")
	Set case = {"name": "zz-eval-documents", "kind": "documents", "documents": [{"name": "Zz eval runbook.md", "file": "runbook.md"}]}
	Set before = ..Marks()
	Set eventMark = ..Max("OcuTalon_Live.Event")
	Set reason = service.DocumentsUp(case, made.folder, .documents)
	Do $$$AssertEquals(reason, "", "the case's document is indexed")
	If reason '= "" Quit
	Do $$$AssertEquals(documents.refs.%Size() _ "|" _ documents.%IsDefined("session"), "1|0", "the setup record holds one ref and no session")
	Set ref = documents.refs.%Get(0)
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State, Name, OwnerRef, AddedBy, Sections FROM OcuTalon_Data.Document WHERE Ref = ?", ref)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%Get("State") _ "|" _ rs.%Get("Name") _ "|" _ rs.%Get("OwnerRef") _ "|" _ rs.%Get("AddedBy"), "ready|Zz eval runbook.md|eval|eval", "it is ready and owned by the literal eval")
	Set sections = {}.%FromJSON(rs.%Get("Sections"))
	Do $$$AssertEquals(sections.%Size(), $ClassMethod(..#STORE, "Count", ref, ..#EVAL), "the section of every passage is kept, one for each row of the table")
	Do $$$AssertTrue($ClassMethod(..#STORE, "Count", ref, ..#EVAL) >= 2, "the passages are in OcuTalonKB.Eval: " _ $ClassMethod(..#STORE, "Count", ref, ..#EVAL))
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref), 0, "and none in OcuTalonKB.Docs, which every person's turn searches (DW-901)")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE Ref = ? AND (OwnerRef = 'instance' OR OwnerRef IN (SELECT Ref FROM OcuTalon_Data.Session))", ref)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "no route lists it: the documents routes list the documents of the instance and of a session")
	Do $$$AssertEquals(..Marks(), before, "the setup wrote no Session, Upload or Delivery row and sent no Notification and no message to DocumentOps")
	Do $$$AssertEquals(..Events(eventMark), 0, "and published no live event")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.In).Finish([{"case": "zz-eval-documents", "documents": (documents)}]), "Finish answers OK")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref, ..#EVAL) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(ref)), "0|0", "and takes the passages and the document away")
	Do $$$AssertEquals(..Marks(), before, "the whole run left the Session, Upload and Delivery rows, the Notifications and the messages to DocumentOps as they were")
	Do $$$AssertEquals(..Events(eventMark), 0, "with no live event at all")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.In).Finish([{"case": "zz-eval-documents", "documents": (documents)}]), "a second Finish of the same record is no error")
}

/// The text of a Markdown document of ten sections, which are more passages than one batch.
ClassMethod LongText() As %String [ Private ]
{
	Set lf = $Char(10)
	Set text = ""
	For i = 1:1:10 Set text = text _ "## Step " _ i _ lf _ "The Results runbook step " _ i _ " says how to handle the certificate of lab " _ i _ "." _ lf _ lf
	Quit text
}

/// A temporary binary stream, rewound, holding the text.
ClassMethod Stream(text As %String) As %Stream.TmpBinary [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write(text)
	Do bytes.Rewind()
	Quit bytes
}

/// A document of more passages than one batch is indexed to the end by AddEval.
Method TestLongDocument()
{
	If '..OnImage() Quit
	Set text = ..LongText()
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", text, "markdown", .passages)
	Do $$$AssertTrue(passages.%Size() > $Parameter(..#OPS, "BATCH"), "the document has more passages than one batch: " _ passages.%Size())
	Set outcome = $ClassMethod(..#OPS, "AddEval", ..Stream(text), "Zz eval long.md", "markdown", 60, .ref)
	Do $$$AssertEquals(outcome, "", "a document of more passages than one batch is indexed to the end")
	If outcome '= "" Quit
	Set row = ##class(OcuTalon.Data.Document).RefIndexOpen(ref)
	Do $$$AssertEquals($Select($IsObject(row): row.State _ "|" _ row.OwnerRef, 1: "none"), "ready|eval", "it is ready and owned by eval")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref, ..#EVAL), passages.%Size(), "and every passage is a row of OcuTalonKB.Eval")
	Set row = ""
	Do $$$AssertStatusOK($ClassMethod(..#OPS, "RemoveEval", ref), "RemoveEval takes it away")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", ref, ..#EVAL) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(ref)), "0|0", "with its passages")
}

/// A document whose passages cannot be embedded is not left behind by AddEval.
Method TestEmbedFailure()
{
	If '..OnImage() Quit
	Set before = ..Left()
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Set environ = ##class(%SYS.Python).Import("os").environ
	Do environ."__setitem__"(variable, "/dev/null/zz-docs-no-model/")
	Set outcome = $ClassMethod(..#OPS, "AddEval", ..Stream(..LongText()), "Zz eval broken.md", "markdown", 60, .ref)
	Do ##class(OcuTalon.Test.Memory.Fixture).PutVariable(environ, previous)
	Do $$$AssertEquals(outcome, "failed", "a document whose passages cannot be embedded answers failed")
	Do $$$AssertEquals(ref, "", "and gives no ref")
	Do $$$AssertEquals(..Left(), before, "and leaves no row and no passage")
}

/// A case whose second file cannot be read leaves the first file's document nowhere.
Method TestSecondFileFails()
{
	If '..OnImage() Quit
	Set made = ..MakeCase()
	Set file = ##class(%Stream.FileCharacter).%New()
	Do file.LinkToFile(made.folder _ "blank.md")
	Do file.WriteLine("   ")
	Do file.%Save()
	Set file = ""
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Eval.In", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of EvalIn is made")
	Set case = {"name": "zz-eval-documents", "kind": "documents", "documents": [{"name": "Zz eval runbook.md", "file": "runbook.md"}, {"name": "Zz eval blank.md", "file": "blank.md"}]}
	Set before = ..Left()
	Set reason = service.DocumentsUp(case, made.folder, .documents)
	Do $$$AssertTrue(reason [ "Zz eval blank.md was not added (unreadable)", "the case is not sent, with the reason of the second file: " _ reason)
	Do $$$AssertEquals(documents, "", "and there is no setup record")
	Do $$$AssertEquals(..Left(), before, "the first file's document and passages are taken away again")
}

/// RemoveEval refuses a document that is not an eval document, and AddEval leaves nothing behind when it does not index.
Method TestRefusals()
{
	If '..OnImage() Quit
	Set sc = $ClassMethod(..#STORE, "EnsureTable")
	Do $$$AssertStatusOK(sc, "the table is there")
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ..#GUARD
	Set row.OwnerRef = "instance"
	Set row.AddedBy = "zz-doc-evalguard-s"
	Set row.Name = "Zz eval guard.md"
	Set row.ContentType = "markdown"
	Set row.State = "ready"
	Do $$$AssertStatusOK(row.%Save(), "a document of the instance is made")
	Set row = ""
	Do $$$AssertStatusNotOK($ClassMethod(..#OPS, "RemoveEval", ..#GUARD), "RemoveEval refuses it")
	Do $$$AssertTrue($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(..#GUARD)), "and the document is still there")
	Do $$$AssertStatusOK($ClassMethod(..#OPS, "RemoveEval", "zz-doc-evalnone"), "a document that is not there is no error")
	Do $$$AssertStatusOK($ClassMethod(..#OPS, "RemoveEval", ""), "and neither is no ref")

	Set before = ..Left()
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write("# Zz eval" _ $Char(10) _ "## One" _ $Char(10) _ "Text of the first section." _ $Char(10))
	Do bytes.Rewind()
	Do $$$AssertEquals($ClassMethod(..#OPS, "AddEval", bytes, "Zz eval late.md", "markdown", 0, .ref), "timeout", "with no time left AddEval answers timeout")
	Do $$$AssertEquals(ref, "", "and gives no ref")
	Do $$$AssertEquals(..Left(), before, "and leaves no row and no passage")
	Set blank = ##class(%Stream.TmpBinary).%New()
	Do blank.Write("   " _ $Char(10))
	Do blank.Rewind()
	Do $$$AssertEquals($ClassMethod(..#OPS, "AddEval", blank, "Zz eval blank.md", "markdown", 60, .ref), "unreadable", "a blank file is unreadable")
	Do $$$AssertEquals(..Left(), before, "and leaves nothing")
	Do bytes.Rewind()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do $$$AssertEquals($ClassMethod(..#OPS, "AddEval", bytes, "Zz eval demo.md", "markdown", 60, .ref), "not_built", "on the online demo AddEval answers not_built")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(..Left(), before, "and leaves nothing")
}

/// A run starts by sweeping what an earlier run left (DW-900): an evaluation document in OcuTalonKB.Eval and one in OcuTalonKB.Docs (as Story 19.4's code
/// left it), both of the owner eval, go with their passages when EvalIn Start runs, and a document of the instance in OcuTalonKB.Docs stays with its passages.
Method TestSweep()
{
	If '..OnImage() Quit
	Set made = ..MakeCase()
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "EnsureTable"), "the table of the install is there")
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", ..LongText(), "markdown", .passages)
	Do $$$AssertEquals($ClassMethod(..#OPS, "AddEval", ..Stream(..LongText()), "Zz eval left.md", "markdown", 60, .left), "", "a run's document is indexed and left (it was killed before its Finish)")
	If left = "" Quit
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ..#LEFT
	Set row.OwnerRef = "eval"
	Set row.AddedBy = "eval"
	Set row.Name = "Zz eval left in docs.md"
	Set row.ContentType = "markdown"
	Set row.State = "ready"
	Set row.KnowledgeBase = "OcuTalonKB.Docs"
	Do $$$AssertStatusOK(row.%Save(), "and one that Story 19.4's code left in OcuTalonKB.Docs")
	Set row = ""
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#LEFT, "Zz eval left in docs", passages, 0, 100), "with its passages")
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ..#GUARD
	Set row.OwnerRef = "instance"
	Set row.AddedBy = "zz-doc-evalguard-s"
	Set row.Name = "Zz eval guard.md"
	Set row.ContentType = "markdown"
	Set row.State = "ready"
	Set row.KnowledgeBase = "OcuTalonKB.Docs"
	Do $$$AssertStatusOK(row.%Save(), "a document of the instance is made")
	Set row = ""
	Do $$$AssertStatusOK($ClassMethod(..#STORE, "Write", ..#GUARD, "Zz eval guard", passages, 0, 100), "with its passages")
	Do $$$AssertEquals(($ClassMethod(..#STORE, "Count", left, ..#EVAL) > 0) _ "|" _ ($ClassMethod(..#STORE, "Count", ..#LEFT) > 0) _ "|" _ ($ClassMethod(..#STORE, "Count", ..#GUARD) > 0), "1|1|1", "control: every passage is in its table")
	Set sc = ##class(OcuTalon.Eval.In).Start(made.cases, , .runRef, .sent)
	Do $$$AssertEquals(sent, 0, "a run sends no case: the folder holds none, and EvalIn is disabled on a stack unless an evaluation enables it")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(left)) _ "|" _ $IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(..#LEFT)), "0|0", "both documents of the earlier run are gone")
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", left, ..#EVAL) _ "|" _ $ClassMethod(..#STORE, "Count", ..#LEFT), "0|0", "with their passages")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(..#GUARD)) _ "|" _ ($ClassMethod(..#STORE, "Count", ..#GUARD) > 0), "1|1", "and the instance's document and its passages stay")
}

/// A leftover whose removal fails is one warning and does not stop the sweep (DW-900): the other leftover goes.
Method TestSweepFails()
{
	If '..OnImage() Quit
	Set made = ..MakeCase()
	Do $$$AssertEquals($ClassMethod(..#OPS, "AddEval", ..Stream(..LongText()), "Zz eval left.md", "markdown", 60, .left), "", "a run's document is indexed and left")
	If left = "" Quit
	Set row = ##class(OcuTalon.Data.Document).%New()
	Set row.Ref = ..#BAD
	Set row.OwnerRef = "eval"
	Set row.AddedBy = "eval"
	Set row.Name = "Zz eval left bad.md"
	Set row.ContentType = "markdown"
	Set row.State = "ready"
	Set row.KnowledgeBase = "Other.Docs"
	Do $$$AssertStatusOK(row.%Save(), "and one whose row names a table that is no knowledge-base table")
	Set row = ""
	Set warning = $Parameter("OcuTalon.Eval.In", "LOGSWEEP") _ ..#BAD
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", warning)
	Do $$$AssertEquals($ClassMethod(..#STORE, "Count", left, ..#EVAL) > 0, 1, "control: the first leftover's passages are in OcuTalonKB.Eval")
	Set sc = ##class(OcuTalon.Eval.In).Start(made.cases, , .runRef, .sent)
	Do $$$AssertEquals(sent, 0, "a run sends no case: the folder holds none, and EvalIn is disabled on a stack unless an evaluation enables it")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", warning)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 1, "the failed removal is one warning that names the document")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Document).RefIndexOpen(left)) _ "|" _ $ClassMethod(..#STORE, "Count", left, ..#EVAL), "0|0", "and the other leftover and its passages are removed")
}

/// What the documents of these tests (each named Zz eval) have left, as "<rows>|<passages in OcuTalonKB.Eval>|<passages in OcuTalonKB.Docs>": the Document
/// rows of that name and the passages whose metadata names such a document. A table that is not there holds none (0), so the reading is the same before
/// and after the call that makes it, and no other test's or job's documents move it.
ClassMethod Left() As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document WHERE Name %STARTSWITH 'Zz eval'")
	Do rs.%Next()
	Set text = rs.%GetData(1)
	For table = ..#EVAL, "OcuTalonKB.Docs" {
		Set count = 0
		If $SYSTEM.SQL.Schema.TableExists(table) {
			Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table _ " WHERE metadata LIKE ?", "%""document"":""Zz eval%")
			If rs.%SQLCODE < 0 {
				Set count = "unreadable: " _ rs.%Message
			} Else {
				Do rs.%Next()
				Set count = rs.%GetData(1)
			}
		}
		Set text = text _ "|" _ count
	}
	Quit text
}

}
