/// One file that a person sent from the chat or, from Story 26.2, from Telegram: the bytes and what the Item names (AD-3, AD-4, AD-21, AD-27;
/// Story 25.3). Lane B. The only writer is OcuTalon.Core.Files.Store, after its size, empty and byte-signature checks; the only reader of a row is
/// OcuTalon.Core.Files, which finds it through OcuTalon.Data.Ownership.SentFile (Ref and SessionRef compared exactly, so a Ref of another session
/// answers like a missing one). No route serves the bytes. An Item and every production message carry the row's Ref, name, media type and size
/// only, never the bytes (the key proof of DW-448). Unlike Data.Upload a row is read many times: it is kept until the session ends (DropSession)
/// or the standard purge deletes it by age (Purge, AD-27). Purge walks the class's own data global and deletes with %DeleteId, with no SQL,
/// because the routes run as the signed-in user, who holds no SQL privilege (AD-13). Row ids never leave the server.
Class OcuTalon.Data.SentFile Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.SentFile";

/// The status code of %DeleteId for an id that has no row (the row was deleted meanwhile): $$$DeleteObjectNotFound of %occErrors.inc.
Parameter NOTFOUND [ Final ] = 5810;

/// The seconds in a day, for Purge.
Parameter DAY [ Final ] = 86400;

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session that sent the file.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The channel the file came by: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The file's name, made safe by Core.Files.SafeName.
Property Name As %String(MAXLEN = 255);

/// The media type, read from the bytes' signature.
Property MediaType As %String(MAXLEN = 128);

/// The size in bytes.
Property Size As %Integer;

/// The file's bytes.
Property Content As %Stream.GlobalBinary;

/// When the row was made, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

/// Stores the file for the session and returns the new row's Ref, or "" with the status in sc. The caller has made the checks.
ClassMethod Put(sessionRef As %String, channel As %String, name As %String, mediaType As %String, bytes As %Stream.Object, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Set row = ..%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = sessionRef
	Set row.Channel = channel
	Set row.Name = name
	Set row.MediaType = mediaType
	Set row.Size = bytes.Size
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.Content.CopyFrom(bytes)
	If $$$ISOK(sc) Set sc = row.%Save()
	Quit $Select($$$ISOK(sc): row.Ref, 1: "")
}

/// Deletes the session's file with the Ref, if there is one. Returns OK when it is gone or when the session has no such file (a file of
/// another session is left alone, and a row deleted meanwhile is not an error).
ClassMethod Drop(ref As %String, sessionRef As %String) As %Status
{
	If '$IsObject(##class(OcuTalon.Core.Files).Describe($Get(ref), $Get(sessionRef))) Quit $$$OK
	If '..RefIndexExists(ref, .id) Quit $$$OK
	Set ids(1) = id
	Quit ..DeleteAll(.ids)
}

/// Deletes every file of the session (its sign-out; AD-4) and no other. Returns OK when none is left, else the first error.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	If $Get(sessionRef) = "" Quit $$$OK
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", sessionRef)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
	}
	Quit ..DeleteAll(.ids)
}

/// Deletes every file made before now minus daysToKeep days (now is the current time unless a test gives one); a file exactly daysToKeep
/// days old, and every younger one, is kept. A row with no CreatedAt counts as old. It walks the class's own data global and uses no SQL.
/// A row deleted meanwhile is not an error; the result is OK, or the first error.
ClassMethod Purge(daysToKeep As %Integer, now As %String = "") As %Status
{
	If now = "" Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set cutoff = ##class(OcuTalon.Data.Time).AddSeconds(now, -(+$Get(daysToKeep) * ..#DAY))
	If cutoff = "" Quit $$$ERROR($$$GeneralError, "The sent files could not be purged: the time "_now_" is unreadable")
	Set count = 0
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.SentFileD(id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If '$IsObject(row) Continue
		If cutoff ] row.CreatedAt Set ids($Increment(count)) = id
	}
	Quit ..DeleteAll(.ids)
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
<Data name="SentFileDefaultData">
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
<Value>Channel</Value>
</Value>
<Value name="5">
<Value>Name</Value>
</Value>
<Value name="6">
<Value>MediaType</Value>
</Value>
<Value name="7">
<Value>Size</Value>
</Value>
<Value name="8">
<Value>Content</Value>
</Value>
<Value name="9">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SentFileD</DataLocation>
<DefaultData>SentFileDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SentFileD</IdLocation>
<IndexLocation>^OcuTalonP.SentFileI</IndexLocation>
<StreamLocation>^OcuTalonP.SentFileS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
