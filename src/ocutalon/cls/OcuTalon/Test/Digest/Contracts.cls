/// The contracts of the two Digest tables that step 2 adds (Story 33.1; AD-3, AD-18, AD-33), and the Digest stub item.
///   - TestContracts: OcuTalon.Digest.Data.CheckRun and OcuTalon.Digest.Data.Sent have exactly the properties, types and indexes of XData
///     Contracts (the compared type parameters included), and project no SQL reserved word as a table or field name;
///   - TestRefCollation: the reference columns of both tables carry COLLATION EXACT;
///   - TestRegistry: each table sets the DEFAULTGLOBAL of its src/short-names.tsv row (copied into XData Registry), stores its data in that global plus D, and has its data and
///     index globals in the private database (the check of Test.Data.Tables TestPrivateRecords, whose registry covers OcuTalon.Data, OcuTalon.Live and
///     OcuTalon.Bridge.Data only);
///   - TestDigestStub: OcuTalon.Digest.Process carries STUB 1 and a shadow instance answers "not implemented" (code 5003), with no response.
Class OcuTalon.Test.Digest.Contracts Extends OcuTalon.Test.Contract
{

Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertSqlNames("OcuTalon.Digest.Data.CheckRun")
	Do ..AssertSqlNames("OcuTalon.Digest.Data.Sent")
}

/// The reference columns compare exactly (refs are case-sensitive), which the compared type parameters of XData Contracts do not include.
Method TestRefCollation()
{
	For ref = "OcuTalon.Digest.Data.CheckRun||CheckRef", "OcuTalon.Digest.Data.CheckRun||SessionRef", "OcuTalon.Digest.Data.Sent||Ref", "OcuTalon.Digest.Data.Sent||SessionRef", "OcuTalon.Digest.Data.Sent||ItemId", "OcuTalon.Digest.Data.Sent||DecisionRef" {
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
	Do $$$AssertEquals(rows.%Size(), 2, "the oracle holds the two registry rows of the Digest tables")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set class = row.class
		Set global = row.global
		Set name = $Extract(global, 2, *)
		Do $$$AssertEquals($Parameter(class, "DEFAULTGLOBAL"), global, class_" sets DEFAULTGLOBAL "_global)
		Do $$$AssertEquals(global, "^OcuTalonP."_row.short, class_": the registry global is ^OcuTalonP. plus the short name")
		Set compiled = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
		Set dataLocation = $Select($IsObject(compiled): compiled.DataLocation, 1: "")
		Set indexLocation = $Select($IsObject(compiled): compiled.IndexLocation, 1: "")
		Do $$$AssertEquals(dataLocation, global_"D", class_" stores its data in "_global_"D")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, dataLocation), private, class_" data global "_dataLocation_" resolves to the private database")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, indexLocation), private, class_" index global "_indexLocation_" resolves to the private database")
		Do $$$AssertTrue($Data(storage(name_"D")), "StorageGlobals lists "_name_"D")
		Do $$$AssertTrue($Data(storage(name_"I")), "StorageGlobals lists "_name_"I")
	}
}

/// The Digest item is a stub until Story 17.6: it carries STUB and answers 5003 with no response.
Method TestDigestStub()
{
	Set class = "OcuTalon.Digest.Process"
	Do $$$AssertEquals(+$Parameter(class, "STUB"), 1, class_" carries STUB")
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
	If '$IsObject(host) {
		Do $$$AssertTrue(0, "a shadow instance is made: "_$SYSTEM.Status.GetErrorText(sc))
		Quit
	}
	Kill response
	Set sc = host.OnRequest(##class(Ens.StringRequest).%New("x"), .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "the Digest item answers code 5003")
	Do $$$AssertTrue('$IsObject($Get(response)), "and gives no response")
}

/// The registry rows of src/short-names.tsv for the two tables, as a copy of the file's rows (docker/tests/test-storage.sh checks the file).
XData Registry [ MimeType = application/json ]
{
[
 {"short": "CheckRun", "global": "^OcuTalonP.CheckRun", "class": "OcuTalon.Digest.Data.CheckRun"},
 {"short": "DigestSent", "global": "^OcuTalonP.DigestSent", "class": "OcuTalon.Digest.Data.Sent"}
]
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Digest.Data.CheckRun": {
  "super": "%Persistent",
  "props": {
   "CheckRef": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "RanAt": "%String(MAXLEN=20)",
   "Result": "%String(MAXLEN=32)",
   "Reason": "%String(MAXLEN=32)",
   "Finding": "%String(MAXLEN=1000)",
   "HeaderId": "%Integer"
  },
  "indexes": {
   "CheckRefRanAtIndex": "CheckRef,RanAt",
   "SessionRefRanAtIndex": "SessionRef,RanAt"
  }
 },
 "OcuTalon.Digest.Data.Sent": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "ItemId": "%String(MAXLEN=22)",
   "DecisionRef": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "DueAt": "%String(MAXLEN=20)",
   "WindowStart": "%String(MAXLEN=20)",
   "SentAt": "%String(MAXLEN=20)",
   "CatalogKey": "%String(MAXLEN=128)",
   "Slots": "%String(MAXLEN=)",
   "AllClear": "%Boolean"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefSentAtIndex": "SessionRef,SentAt",
   "SessionRefDueAtIndex": "SessionRef,DueAt"
  }
 }
}
}

}
