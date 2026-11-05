/// The bytes of one file that a person has just added, held for DocumentOps between the documents route and the AddDocument command (AD-1,
/// AD-21, AD-29; Story 34.2). Lane B. The command carries the row's Ref (UploadRef), never the bytes: a message body holds no global stream
/// (the key proof of DW-448). The only writer is the documents route (OcuTalon.Web.Documents, its Add), which stores the row just before it submits
/// the command and deletes it when the submit fails; the only reader is DocumentOps (Story 19.4), which calls Take, and a session's sign-out deletes what is
/// left (DropSession). Row ids never leave the server.
Class OcuTalon.Data.Upload Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Upload";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session that added the file.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The file's bytes.
Property Content As %Stream.GlobalBinary;

/// When the row was made, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

/// Stores the bytes of a file for the session and returns the new row's Ref, or "" with the status in sc.
ClassMethod Put(sessionRef As %String, bytes As %Stream.Object, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Set row = ..%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.Content.CopyFrom(bytes)
	If $$$ISOK(sc) Set sc = row.%Save()
	Quit $Select($$$ISOK(sc): row.Ref, 1: "")
}

/// The bytes of the upload as a temporary binary stream, positioned at its start; the row is deleted. Returns "" when no row has the Ref
/// (an unknown Ref, or an upload already taken). DocumentOps takes an upload once, when it handles the AddDocument that names it.
ClassMethod Take(ref As %String) As %Stream.Object
{
	If $Get(ref) = "" Quit ""
	Set row = ..RefIndexOpen(ref)
	If '$IsObject(row) Quit ""
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Set sc = bytes.CopyFrom(row.Content)
	If $$$ISERR(sc) Quit ""
	Do bytes.Rewind()
	Set id = row.%Id()
	Kill row
	If $$$ISERR(..%DeleteId(id)) Quit ""
	Quit bytes
}

/// Deletes the upload with the Ref, if there is one. Returns OK when it is gone.
ClassMethod Drop(ref As %String) As %Status
{
	If $Get(ref) = "" Quit $$$OK
	Set id = ""
	If '..RefIndexExists(ref, .id) Quit $$$OK
	Quit ..%DeleteId(id)
}

/// Deletes every upload of the session (its sign-out; AD-4) and no other. Returns OK when none is left, else the first error.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If $Get(sessionRef) = "" Quit $$$OK
	Set sc = $$$OK
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Upload WHERE SessionRef = ?", sessionRef)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	While result.%Next() {
		Set one = ..%DeleteId(result.%GetData(1))
		If $$$ISERR(one) && $$$ISOK(sc) Set sc = one
	}
	Quit sc
}

Storage Default
{
<Data name="UploadDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>Content</Value>
</Value>
<Value name="5">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.UploadD</DataLocation>
<DefaultData>UploadDefaultData</DefaultData>
<IdLocation>^OcuTalonP.UploadD</IdLocation>
<IndexLocation>^OcuTalonP.UploadI</IndexLocation>
<StreamLocation>^OcuTalonP.UploadS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
