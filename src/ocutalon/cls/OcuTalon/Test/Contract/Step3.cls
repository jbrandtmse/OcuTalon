/// The contracts of step 3's two tables and its sign-out stubs (Story 34.1; AD-3, AD-21, AD-33).
///   - TestContracts: OcuTalon.Data.Memory and OcuTalon.Data.Document have exactly the properties, types and indexes of XData
///     Contracts (the compared type parameters included), project no SQL reserved word as a table or field name, and
///     Memory.Embedding is a 384-dimension DOUBLE vector while a new Document starts in state indexing;
///   - TestRefCollation: the reference columns of both tables carry COLLATION EXACT;
///   - TestRegistry: each table sets the DEFAULTGLOBAL of its src/short-names.tsv row (copied into XData Registry), stores its data in that
///     global plus D, and has its data and index globals in the private database, and the Document stream global is private too;
///   - TestDropSession: OcuTalon.Docs.DropSession and OcuTalon.Memory.DropSession return OK for a session reference and change no row of
///     either table, the session's own rows and another session's alike (they are stubs until Story 19.5); the rows it seeds are deleted
///     in the test and again in OnAfterAllTests.
Class OcuTalon.Test.Contract.Step3 Extends OcuTalon.Test.Contract
{

Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertSqlNames("OcuTalon.Data.Memory")
	Do ..AssertSqlNames("OcuTalon.Data.Document")
	Set vector = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Data.Memory||Embedding")
	Do $$$AssertEquals($Select($IsObject(vector): vector.Parameters.GetAt("DATATYPE"), 1: "(missing)"), "DOUBLE", "Memory.Embedding holds DOUBLE values")
	Do $$$AssertEquals($Select($IsObject(vector): vector.Parameters.GetAt("LEN"), 1: "(missing)"), 384, "Memory.Embedding holds 384 dimensions")
	Set state = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Data.Document||State")
	Do $$$AssertEquals($Select($IsObject(state): state.InitialExpression, 1: "(missing)"), """indexing""", "a new Document is in state indexing")
}

/// The reference columns compare exactly (refs are case-sensitive), which the compared type parameters of XData Contracts do not include.
Method TestRefCollation()
{
	For ref = "OcuTalon.Data.Memory||Ref", "OcuTalon.Data.Memory||SessionRef", "OcuTalon.Data.Memory||ItemId", "OcuTalon.Data.Document||Ref", "OcuTalon.Data.Document||OwnerRef", "OcuTalon.Data.Document||AddedBy" {
		Set property = ##class(%Dictionary.CompiledProperty).%OpenId(ref)
		Do $$$AssertEquals($Select($IsObject(property): property.Parameters.GetAt("COLLATION"), 1: "(missing)"), "EXACT", ref_" compares with EXACT collation")
	}
}

Method TestRegistry()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Set data = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonZzUnmapped")
	Do $$$AssertTrue(private '= data, "the private and data databases differ")
	Set rows = ..Read("Registry")
	Do $$$AssertEquals(rows.%Size(), 2, "the oracle holds the two registry rows of the step 3 tables")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set class = row.class
		Set global = row.global
		Set name = $Extract(global, 2, *)
		Do $$$AssertEquals($Parameter(class, "DEFAULTGLOBAL"), global, class_" sets DEFAULTGLOBAL "_global)
		Set compiled = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
		Set dataLocation = $Select($IsObject(compiled): compiled.DataLocation, 1: "")
		Set indexLocation = $Select($IsObject(compiled): compiled.IndexLocation, 1: "")
		Set streamLocation = $Select($IsObject(compiled): compiled.StreamLocation, 1: "")
		Do $$$AssertEquals(dataLocation, global_"D", class_" stores its data in "_global_"D")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, dataLocation), private, class_" data global "_dataLocation_" resolves to the private database")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, indexLocation), private, class_" index global "_indexLocation_" resolves to the private database")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, streamLocation), private, class_" stream global "_streamLocation_" resolves to the private database")
		Do $$$AssertTrue($Data(storage(name_"D")), "StorageGlobals lists "_name_"D")
		Do $$$AssertTrue($Data(storage(name_"I")), "StorageGlobals lists "_name_"I")
		Do $$$AssertTrue($Data(storage(name_"S")), "StorageGlobals lists "_name_"S")
	}
}

/// Both sign-out stubs return OK for a session reference and change no row: a memory and a document of that session and of another
/// one are seeded, and all four are still there, unchanged in number, after both calls. The rows are deleted before and after.
Method TestDropSession()
{
	Set ref = "ZzStep3Fixture"
	Set other = "ZzStep3Other"
	Do ..DeleteFixtures()
	Do $$$AssertStatusOK(..SeedRows(ref, other), "the fixture memories and documents are saved")
	Set memories = ..Count("OcuTalon_Data.Memory", "")
	Set documents = ..Count("OcuTalon_Data.Document", "")
	Do $$$AssertTrue(memories >= 2, "the memory table is read and holds the two seeded rows ("_memories_")")
	Do $$$AssertTrue(documents >= 2, "the document table is read and holds the two seeded rows ("_documents_")")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(ref), "OcuTalon.Docs.DropSession returns OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(ref), "OcuTalon.Memory.DropSession returns OK")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Memory", ""), memories, "no Memory row changed in number")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Document", ""), documents, "no Document row changed in number")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Memory", "SessionRef = '"_ref_"'"), 1, "the dropped session's memory is still there")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Memory", "SessionRef = '"_other_"'"), 1, "the other session's memory is still there")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Document", "OwnerRef = '"_ref_"'"), 1, "the dropped session's document is still there")
	Do $$$AssertEquals(..Count("OcuTalon_Data.Document", "OwnerRef = '"_other_"'"), 1, "the other session's document is still there")
	Do ..DeleteFixtures()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

/// One memory and one document for each of the two sessions, with references that start with ZzStep3; the first failed save's status.
ClassMethod SeedRows(first As %String, second As %String) As %Status [ Private ]
{
	Set owners = $ListBuild(first, second)
	Set sc = $SYSTEM.Status.OK()
	For index = 1:1:2 {
		Set owner = $List(owners, index)
		Set memory = ##class(OcuTalon.Data.Memory).%New()
		Set memory.Ref = "ZzStep3M"_index
		Set memory.SessionRef = owner
		Set memory.Text = "fixture"
		If $$$ISOK(sc) Set sc = memory.%Save()
		Set document = ##class(OcuTalon.Data.Document).%New()
		Set document.Ref = "ZzStep3D"_index
		Set document.OwnerRef = owner
		Set document.AddedBy = owner
		Set document.Name = "fixture.md"
		If $$$ISOK(sc) Set sc = document.%Save()
	}
	Quit sc
}

/// Deletes the rows that SeedRows makes.
ClassMethod DeleteFixtures() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Memory WHERE Ref %STARTSWITH 'ZzStep3'")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Document WHERE Ref %STARTSWITH 'ZzStep3'")
}

/// The number of rows of a table that meet a condition (all rows when it is empty), or -1 when the count fails.
ClassMethod Count(table As %String, where As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_$Select(where = "": "", 1: " WHERE "_where))
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The registry rows of src/short-names.tsv for the two tables, as a copy of the file's rows (docker/tests/test-storage.sh checks the file).
XData Registry [ MimeType = application/json ]
{
[
 {"short": "Memory", "global": "^OcuTalonP.Memory", "class": "OcuTalon.Data.Memory"},
 {"short": "Document", "global": "^OcuTalonP.Document", "class": "OcuTalon.Data.Document"}
]
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Data.Memory": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "Text": "%String(MAXLEN=2000)",
   "SavedAt": "%String(MAXLEN=20)",
   "ItemId": "%String(MAXLEN=22)",
   "Origin": "%String(MAXLEN=16)",
   "Embedding": "%Vector"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefSavedAtIndex": "SessionRef,SavedAt",
   "EmbeddingIdx": "Embedding",
   "TextIdx": "Text",
   "$Memory": ""
  }
 },
 "OcuTalon.Data.Document": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "OwnerRef": "%String(MAXLEN=22)",
   "AddedBy": "%String(MAXLEN=22)",
   "Name": "%String(MAXLEN=255)",
   "ContentType": "%String(MAXLEN=16)",
   "Size": "%Integer",
   "AddedAt": "%String(MAXLEN=20)",
   "State": "%String(MAXLEN=16)",
   "Reason": "%String(MAXLEN=32)",
   "KnowledgeBase": "%String(MAXLEN=128)",
   "Text": "%Stream.GlobalCharacter",
   "Sections": "%String"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "OwnerRefAddedAtIndex": "OwnerRef,AddedAt"
  }
 }
}
}

}
