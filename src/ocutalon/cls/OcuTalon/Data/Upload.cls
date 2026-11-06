/// The bytes of one file that a person has just added, held for DocumentOps between the documents route and the AddDocument command (AD-1,
/// AD-21, AD-29; Story 34.2). Lane B. The command carries the row's Ref (UploadRef), never the bytes: a message body holds no global stream
/// (the key proof of DW-448). The only writer is the documents route (OcuTalon.Web.Documents, its Add), which stores the row just before it submits
/// the command and deletes it when the submit fails; the only reader is DocumentOps (Story 19.4), which calls Take with the command's UploadRef
/// and SessionRef, and a session's sign-out deletes what is left (DropSession). Take and Drop find the row through
/// OcuTalon.Data.Ownership.Upload (AD-4), so a Ref of another session answers like a missing one. A row that nobody took is deleted by
/// Purge once it is more than KEEP seconds old: the Web area's purge (OcuTalon.Install.Step.Web.Purge, the daily task, AD-27) and every
/// call of the documents routes run it. Purge reads the class's own data global and deletes with %DeleteId, with no SQL, because the routes run
/// as the signed-in user, who holds no SQL privilege (AD-13). Row ids never leave the server.
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

/// The seconds that an upload that nobody took is kept: Purge deletes older ones (AD-27). The route drops its row when no Ok answer comes
/// within CommandsIn's timeout, 120 seconds, so no upload that a command in flight still needs is that old.
Parameter KEEP [ Final ] = 3600;

/// The status code of %DeleteId for an id that has no row (the row was deleted meanwhile): $$$DeleteObjectNotFound of %occErrors.inc.
Parameter NOTFOUND [ Final ] = 5810;

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

/// The bytes of the upload as a temporary binary stream, positioned at its start; the row is deleted. Returns "" when the session has no
/// row with the Ref (an unknown Ref, an upload already taken, or the upload of another session: the answers are alike, and that row stays).
/// DocumentOps takes an upload once, when it handles the AddDocument that names it.
ClassMethod Take(ref As %String, sessionRef As %String) As %Stream.Object
{
	Set row = ..Owned($Get(ref), $Get(sessionRef))
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

/// Deletes the session's upload with the Ref, if there is one. Returns OK when it is gone or when the session has no such upload (an
/// upload of another session is left alone, and a row deleted meanwhile is not an error).
ClassMethod Drop(ref As %String, sessionRef As %String) As %Status
{
	Set row = ..Owned($Get(ref), $Get(sessionRef))
	If '$IsObject(row) Quit $$$OK
	Set ids(1) = row.%Id()
	Kill row
	Quit ..DeleteAll(.ids)
}

/// Deletes every upload of the session (its sign-out; AD-4) and no other. Returns OK when none is left, else the first error.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If $Get(sessionRef) = "" Quit $$$OK
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Upload WHERE SessionRef = ?", sessionRef)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
	}
	Quit ..DeleteAll(.ids)
}

/// Deletes every upload made before now minus KEEP seconds (now is the current time unless a test gives one), whatever daysToKeep says
/// (AD-27, like AddressCounter.Purge); an upload exactly KEEP seconds old, and every younger one, is kept. A row with no CreatedAt counts as
/// old. It walks the class's own data global and uses no SQL, so the documents routes can call it. A row deleted meanwhile is not an
/// error; the result is OK, or the first error.
ClassMethod Purge(daysToKeep As %Integer, now As %String = "") As %Status
{
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set cutoff = ##class(OcuTalon.Data.Time).AddSeconds(now, -..#KEEP)
	If cutoff = "" Quit $$$ERROR($$$GeneralError, "The uploads could not be purged: the time "_now_" is unreadable")
	Set count = 0
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.UploadD(id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If '$IsObject(row) Continue
		If cutoff ] row.CreatedAt Set ids($Increment(count)) = id
	}
	Quit ..DeleteAll(.ids)
}

/// The row with the Ref when the session owns it (OcuTalon.Data.Ownership.Upload), else "".
ClassMethod Owned(ref As %String, sessionRef As %String) As OcuTalon.Data.Upload [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).Upload(ref, sessionRef)
}

/// Deletes the rows whose ids are the values of ids (for Drop, DropSession and Purge), each with %DeleteId, which deletes its stream. A row already gone is not an error.
/// Returns OK, or the first error.
ClassMethod DeleteAll(ByRef ids) As %Status [ Private ]
{
	Set sc = $$$OK
	Set n = ""
	For {
		Set n = $Order(ids(n), 1, id)
		Quit:n=""
		Set one = ..%DeleteId(id)
		If $$$ISERR(one) && '$SYSTEM.Status.Equals(one, ..#NOTFOUND) && $$$ISOK(sc) Set sc = one
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
