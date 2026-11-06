/// The contract of OcuTalon.Data.Upload, the table that holds a file's bytes between the documents route and DocumentOps (Story 34.2; AD-3, AD-21,
/// AD-29; DW-448's key proof forbids a global stream in a message body).
///   - TestContracts: the table has exactly the properties, types and indexes of XData Contracts, projects no SQL reserved word, and AddDocument
///     carries UploadRef and no stream;
///   - TestRefCollation: Ref, SessionRef and AddDocument.UploadRef carry COLLATION EXACT;
///   - TestRegistry: the table sets the DEFAULTGLOBAL of its src/short-names.tsv row (copied into XData Registry), stores its data in that
///     global plus D, and has its data, index and stream globals in the private database;
///   - TestPutAndTake: Put stores the bytes and returns a Ref, Take returns exactly those bytes and deletes the row, a second Take and an unknown
///     or empty Ref return nothing, and Drop deletes one row (both with the owner's SessionRef);
///   - TestTakeIsOwnerScoped: Take and Drop with another session's Ref, a case variant of the owner's Ref, or no SessionRef return nothing and delete
///     nothing, and with the owner's SessionRef Take returns the bytes and deletes the row and Drop deletes it (DW-754; Ownership.Upload);
///   - TestPurgeBoundary: Purge deletes the rows made before now minus 3,600 seconds and a row with no time, keeps a row exactly that old and every younger one, whatever
///     daysToKeep says, for every session, and never touches a fresh row; a delete of a missing row answers the status that Purge ignores (DW-752; the fixture rows are dated 2001);
///   - TestDropSession: DropSession deletes every upload of the session and no other session's, and a call with no SessionRef deletes nothing;
///   - TestRowAlreadyGone: the delete loop that Drop, DropSession and Purge share counts a row that is already gone as deleted: a session whose
///     index names a row with no data (a row deleted between the read of its id and its delete) is dropped with OK, and its real row is gone;
///   - TestPurgeUsesNoSql: Purge and the delete loop name no SQL (the documents routes run them as the signed-in user, who holds no SQL privilege).
/// The rows are made for the SessionRefs ZzUploadA, ZzUploadB and ZzUploadGone and are deleted before each test and after the tests, with
/// ZzUploadGone's index nodes.
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
	Set taken = ##class(OcuTalon.Data.Upload).Take(ref, "ZzUploadA")
	Do $$$AssertTrue($IsObject(taken), "Take returns a stream")
	Do $$$AssertEquals(taken.Size, 12, "of all the bytes")
	Do $$$AssertEquals(taken.Read(12), "hello"_$Char(0, 255)_"world", "which are the bytes that Put was given")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "Take deleted the row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take(ref, "ZzUploadA"), "", "a second Take returns nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take("ZzNoSuchUpload", "ZzUploadA"), "", "an unknown Ref returns nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take("", "ZzUploadA"), "", "an empty Ref returns nothing")
	Do source.Rewind()
	Set second = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "a second Put is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "and stores a row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Drop(second, "ZzUploadA"), 1, "Drop is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "and deleted the row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Drop("ZzNoSuchUpload", "ZzUploadA"), 1, "Drop of an unknown Ref is OK too")
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

/// Take and Drop answer for the owner only: another session's Ref, a case variant of the owner's and an empty one see nothing and delete nothing.
Method TestTakeIsOwnerScoped()
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("owned")
	Do source.Rewind()
	Set ref = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "an upload of ZzUploadA is stored")
	For other = "ZzUploadB", "zzuploada", "" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take(ref, other), "", "Take with the session Ref '"_other_"' returns nothing")
		Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "and the row stays")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).Drop(ref, other), "Drop with the session Ref '"_other_"' is OK")
		Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "and the row stays")
	}
	Set variant = $ZConvert(ref, "L")
	If variant = ref Set variant = $ZConvert(ref, "U")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Take(variant, "ZzUploadA"), "", "a case variant of the Ref returns nothing for the owner")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 1, "and the row stays")
	Set taken = ##class(OcuTalon.Data.Upload).Take(ref, "ZzUploadA")
	Do $$$AssertTrue($IsObject(taken), "Take with the owner's Ref returns a stream")
	Do $$$AssertEquals($Select($IsObject(taken): taken.Read(5), 1: ""), "owned", "of the bytes")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "and deletes the row")
	Do source.Rewind()
	Set second = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "a second upload is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).Drop(second, "ZzUploadA"), "Drop with the owner's Ref is OK")
	Do $$$AssertEquals(..Count("SessionRef = 'ZzUploadA'"), 0, "and deletes the row")
}

/// Purge keeps a row exactly 3,600 seconds old and deletes an older one, for every session and whatever the days; a call at the same time
/// again changes nothing, and a fresh row is not touched. The rows are dated 2001-01-01, so no other row on the instance is old enough
/// to be taken for them.
Method TestPurgeBoundary()
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("age")
	Set now = "2001-01-01T01:00:01Z"
	For session = "ZzUploadA", "ZzUploadB" {
		For created = "2001-01-01T00:00:00Z", "2001-01-01T00:00:01Z", "2001-01-01T00:00:02Z" {
			Do source.Rewind()
			Set ref = ##class(OcuTalon.Data.Upload).Put(session, source, .sc)
			Do $$$AssertStatusOK(sc, "an upload of "_session_" is stored")
			Set row = ##class(OcuTalon.Data.Upload).RefIndexOpen(ref)
			Set row.CreatedAt = created
			Do $$$AssertStatusOK(row.%Save(), "and dated "_created)
			Kill row
		}
	}
	Do source.Rewind()
	Set fresh = ##class(OcuTalon.Data.Upload).Put("ZzUploadA", source, .sc)
	Do $$$AssertStatusOK(sc, "a fresh upload is stored")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).Purge(90, now), "Purge(90) is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload' AND CreatedAt = '2001-01-01T00:00:00Z'"), 0, "the rows 3,601 seconds old are gone")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload' AND CreatedAt = '2001-01-01T00:00:01Z'"), 2, "the rows exactly 3,600 seconds old are kept")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload' AND CreatedAt = '2001-01-01T00:00:02Z'"), 2, "the rows 3,599 seconds old are kept")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).Purge(0, now), "Purge(0) is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload' AND CreatedAt < '2002'"), 4, "and changes nothing, whatever the days")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).Purge(0, "2001-01-01T01:00:02Z"), 1, "a second later Purge is OK")
	Do $$$AssertEquals(..Count("SessionRef %STARTSWITH 'ZzUpload' AND CreatedAt < '2002'"), 2, "and deletes the rows that are now over the hour")
	Do $$$AssertEquals(..Count("Ref = '"_fresh_"'"), 1, "the fresh row was never touched")
	Do source.Rewind()
	Set undated = ##class(OcuTalon.Data.Upload).Put("ZzUploadB", source, .sc)
	Set row = ##class(OcuTalon.Data.Upload).RefIndexOpen(undated)
	Set row.CreatedAt = ""
	Do $$$AssertStatusOK(row.%Save(), "an upload with no time is stored")
	Kill row
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).Purge(0, now), "Purge is OK")
	Do $$$AssertEquals(..Count("Ref = '"_undated_"'"), 0, "an upload with no time counts as old and is gone")
	Do $$$AssertTrue($SYSTEM.Status.Equals(##class(OcuTalon.Data.Upload).%DeleteId(987654321), ##class(OcuTalon.Data.Upload).#NOTFOUND), "a delete of a row that is gone answers the status that Purge ignores")
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Data.Upload).Purge(0, "not a time")), "an unreadable time is an error")
	Do $$$AssertEquals(..Count("Ref = '"_fresh_"'"), 1, "and deletes nothing")
}

/// A row that is gone when the shared delete loop reaches it is not an error. The index of ZzUploadGone names a row id with no data (the
/// state a Take or a purge leaves when it deletes the row between DropSession's read and its delete); DropSession reads that id from the
/// index and still answers OK, and the session's real row is gone.
Method TestRowAlreadyGone()
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("gone")
	Do source.Rewind()
	Set ref = ##class(OcuTalon.Data.Upload).Put("ZzUploadGone", source, .sc)
	Do $$$AssertStatusOK(sc, "an upload of ZzUploadGone is stored")
	Set missing = $Get(^OcuTalonP.UploadD) + 1000000
	Do $$$AssertEquals($Data(^OcuTalonP.UploadD(missing)), 0, "the id "_missing_" has no row")
	Set ^OcuTalonP.UploadI("SessionRefIndex", "ZzUploadGone", missing) = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Upload WHERE SessionRef = ?", "ZzUploadGone")
	Set read = ""
	While result.%Next() { Set read = read_","_result.%GetData(1) }
	Do $$$AssertTrue((read_",") [ (","_missing_","), "DropSession's query reads the id of the row that is gone ("_read_")")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Upload).DropSession("ZzUploadGone"), "DropSession is OK although one of its rows is already gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Upload).RefIndexExists(ref), 0, "and the session's real row is gone")
	Kill ^OcuTalonP.UploadI("SessionRefIndex", "ZzUploadGone")
}

/// Purge and the delete loop it shares hold no SQL: the documents routes run Purge as the signed-in user, who holds no SQL privilege, and
/// the route ignores a failed sweep, so SQL there would fail on the online demo with nothing red.
Method TestPurgeUsesNoSql()
{
	For name = "Purge", "DeleteAll" {
		Set method = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Data.Upload||"_name)
		Do $$$AssertTrue($IsObject(method), "OcuTalon.Data.Upload has "_name)
		If '$IsObject(method) Continue
		Set code = $ZConvert(method.Implementation.Read(32000), "L")
		For word = "%sql", "&sql(", "%execdirect", "%prepare" {
			Do $$$AssertNotTrue(code [ word, name_" names no "_word)
		}
	}
}

/// Deletes the rows that the tests make, and the index nodes of ZzUploadGone.
ClassMethod DeleteFixtures() [ Private ]
{
	Do ##class(OcuTalon.Data.Upload).DropSession("ZzUploadA")
	Do ##class(OcuTalon.Data.Upload).DropSession("ZzUploadB")
	Do ##class(OcuTalon.Data.Upload).DropSession("ZzUploadGone")
	Kill ^OcuTalonP.UploadI("SessionRefIndex", "ZzUploadGone")
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
