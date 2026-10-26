/// A per-address counter of the online demo's new sessions (AD-13, FR-15). Lane B. A row is the SHA-256 of one client address
/// (Session.Hash, never the address) and the time a new session was created for it; resumes write none. Recent counts an
/// address's rows of the past hour, and the sign-in hook (Web.SessionEvents) refuses a creation at the limit, counting,
/// creating and adding the row under one Lock per address, so that two sign-ins never both take the last place.
/// OnLogin runs as the demo account, which holds no SQL privilege, so Recent walks this class's own index and opens rows
/// by id, with no SQL. Purge keeps one hour (AD-27), whatever its argument says.
Class OcuTalon.Data.AddressCounter Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.AddrCount";

/// The hash of the client address, never the address.
Property AddressHash As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index AddressHashIndex On AddressHash;

/// The seconds of the counting window: the past hour.
Parameter WINDOW [ Final ] = 3600;

/// The number of rows of the address created in the past hour, and in oldest the earliest CreatedAt among them ("" when
/// there are none). The rows are the ones under the address's hash in AddressHashIndex (collated as SQLUPPER, collation 7),
/// each opened and compared on its hash exactly, so a hash that differs only in case is never counted.
ClassMethod Recent(address As %String, Output oldest As %String) As %Integer
{
	Set oldest = ""
	Set hash = ##class(OcuTalon.Data.Session).Hash(address)
	Set cutoff = ..Shift(##class(OcuTalon.Data.Time).NowUtc(), -..#WINDOW)
	Set key = $SYSTEM.Util.Collation(hash, 7)
	Set count = 0
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.AddrCountI("AddressHashIndex", key, id))
		Quit:id=""
		Set row = ..%OpenId(id)
		If '$IsObject(row) || (row.AddressHash '= hash) || (cutoff ] row.CreatedAt) Continue
		Set count = count + 1
		If (oldest = "") || (oldest ] row.CreatedAt) Set oldest = row.CreatedAt
	}
	Quit count
}

/// Records one new session for the address, now.
ClassMethod Add(address As %String) As %Status
{
	Set row = ..%New()
	Set row.AddressHash = ##class(OcuTalon.Data.Session).Hash(address)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// Takes the address's lock, waiting at most 5 seconds: 1 when it is held, 0 otherwise. The lock name is the address's hash.
ClassMethod Lock(address As %String) As %Boolean
{
	Lock +^OcuTalon.Data.AddressCounter(##class(OcuTalon.Data.Session).Hash(address)):5
	Quit $Test
}

/// Releases the address's lock.
ClassMethod Unlock(address As %String)
{
	Lock -^OcuTalon.Data.AddressCounter(##class(OcuTalon.Data.Session).Hash(address))
}

/// Deletes every row created more than one hour ago (AD-27), whatever daysToKeep is, and keeps the newer ones. The statement
/// is prepared with the privilege check, because it runs as the purge task.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set cutoff = ..Shift(##class(OcuTalon.Data.Time).NowUtc(), -..#WINDOW)
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Data.AddressCounter WHERE CreatedAt < ?")
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set result = statement.%Execute(cutoff)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The address counter could not be purged: "_result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// A UTC time, YYYY-MM-DDThh:mm:ssZ, moved by a number of seconds; "" for an unreadable time.
ClassMethod Shift(utc As %String, seconds As %Integer) As %String
{
	If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Set horolog = $ZDateTimeH($Translate($Extract(utc, 1, 19), "T", " "), 3, 1, , , , , , , "")
	If horolog = "" Quit ""
	Set total = ($Piece(horolog, ",", 1) * 86400) + $Piece(horolog, ",", 2) + seconds
	Quit $Translate($ZDateTime((total \ 86400)_","_(total # 86400), 3, 1), " ", "T")_"Z"
}

Storage Default
{
<Data name="AddressCounterDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>AddressHash</Value>
</Value>
<Value name="3">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.AddrCountD</DataLocation>
<DefaultData>AddressCounterDefaultData</DefaultData>
<IdLocation>^OcuTalonP.AddrCountD</IdLocation>
<IndexLocation>^OcuTalonP.AddrCountI</IndexLocation>
<StreamLocation>^OcuTalonP.AddrCountS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
