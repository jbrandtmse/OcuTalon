/// The contract of OcuTalon.Data.Upload, the table that holds a file's bytes between the documents route and DocumentOps (Story 34.2; AD-3, AD-21,
/// AD-29; DW-448's key proof forbids a global stream in a message body).
///   - TestContracts: the table has exactly the properties, types and indexes of XData Contracts, projects no SQL reserved word, and AddDocument
///     carries UploadRef and no stream;
///   - TestRefCollation: Ref, SessionRef and AddDocument.UploadRef carry COLLATION EXACT;
///   - TestRegistry: the table sets the DEFAULTGLOBAL of its src/short-names.tsv row (copied into XData Registry), stores its data in that
///     global plus D, and has its data, index and stream globals in the private database;
///   - TestPutAndTake: Put stores the bytes and returns a Ref, Take returns exactly those bytes and deletes the row, a second Take and an unknown
///     or empty Ref return nothing, and Drop deletes one row;
///   - TestDropSession: DropSession deletes every upload of the session and no other session's, and a call with no SessionRef deletes nothing.
/// The rows are made for the SessionRefs ZzUploadA and ZzUploadB and are deleted before each test and after the tests.
Class OcuTalon.Test.Core.UploadContract Extends OcuTalon.Test.Contract
{

Method OnBeforeAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertSqlNames("OcuTalon.Data.Upload")
	Set property = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Msg.Command.AddDocument||UploadRef")
	Do $$$AssertEquals($Select($IsObject(property): property.Type, 1: "(missing)"), "%Library.String", "AddDocument carries UploadRef as a string")
	Set stream = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Msg.Command.AddDocument||Content")
	Do $$$AssertTrue('$IsObject(stream), "AddDocument has no Content stream")
}

/// The reference columns compare exactly (refs are case-sensitive), which the compared type parameters of XData Contracts do not include.
Method TestRefCollation()
{
	For ref = "OcuTalon.Data.Upload||Ref", "OcuTalon.Data.Upload||SessionRef", "OcuTalon.Msg.Command.AddDocument||UploadRef" {
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
	Do $$$AssertEquals(rows.%Size(), 1, "the oracle holds the registry row of the table")
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

/// Put keeps the bytes, Take gives them back once and deletes the row.
Method TestPutAndTake()
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("hello"_$Char(0, 255)_"world")
	Do source.Rewind()
	Set ref = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "Put is OK")
	Do $$$AssertEquals($Length(ref), 22, "Put returns a 22-character Ref")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "one row is stored for the session")
	Set row = ##class(OcuTalon.Data.Upload).RefIndexOpen(ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Content.Size, "ZzUploadA|12", "the row holds the session and all the bytes")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the time it was made")
	Kill row
	Set taken = ##class(OcuTalon.Data.Upload).Take(ref)
	Do $$$AssertTrue($IsObject(taken), "Take returns a stream")
	Do $$$AssertEquals(taken.Size, 12, "of all the bytes")
	Do $$$AssertEquals(taken.Read(12), "hello"_$Char(0, 255)_"world", "which are the bytes that Put was given")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "Take deleted the row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take(ref), "", "a second Take returns nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take("ZzNoSuchUpload"), "", "an unknown Ref returns nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take(""), "", "an empty Ref returns nothing")
	Do source.Rewind()
	Set second = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "a second Put is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "and stores a row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Drop(second), 1, "Drop is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "and deleted the row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Drop("ZzNoSuchUpload"), 1, "Drop of an unknown Ref is OK too")
}

/// A session's sign-out deletes its uploads and nobody else's.
Method TestDropSession()
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("abc")
	For session = "ZzUploadA", "ZzUploadA", "ZzUploadB" {
		Do source.Rewind()
		Do ##class(OcuTalon.Data.Upload).Put(session, source, .sc)
		Do $$$AssertStatusOK(sc, "an upload of "_session_" is stored")
	}
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload'"), 3, "three uploads are there")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).DropSession(""), "DropSession of no session is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload'"), 3, "and deletes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).DropSession("zzuploada"), "DropSession of a Ref that differs in case is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload'"), 3, "and deletes no upload of the session with that Ref in another case")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).DropSession("ZzUploadA"), "DropSession is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "the session's uploads are gone")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadB'"), 1, "another session's upload is still there")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).DropSession("ZzUploadB"), "DropSession of the last session is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload'"), 0, "none is left")
}

/// Deletes the rows that the tests make.
ClassMethod DeleteFixtures() [ Private ]
{
	Do ##class(OcuTalon.Data.Upload).DropSession("ZzUploadA")
	Do ##class(OcuTalon.Data.Upload).DropSession("ZzUploadB")
}

/// The number of upload rows that meet a condition, or -1 when the count fails.
ClassMethod Count(where As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Upload WHERE "_where)
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The registry row of src/short-names.tsv for the table, as a copy of the file's row (docker/tests/test-storage.sh checks the file).
XData Registry [ MimeType = application/json ]
{
[
 {"short": "Upload", "global": "^OcuTalonP.Upload", "class": "OcuTalon.Data.Upload"}
]
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Data.Upload": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "Content": "%Stream.GlobalBinary",
   "CreatedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef"
  }
 },
 "OcuTalon.Msg.Command.AddDocument": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Name": "%String(MAXLEN=255)",
   "ContentType": "%String(MAXLEN=16)",
   "UploadRef": "%String(MAXLEN=22)"
  }
 }
}
}

}
