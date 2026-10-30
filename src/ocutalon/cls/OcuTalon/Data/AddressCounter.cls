/// A per-address counter of the online demo's new sessions (AD-13, FR-15). Lane B. A row is the keyed hash of one client address
/// (AddressHash, never the address) and the time a new session was created for it; resumes write none. Recent counts an
/// address's rows of the past hour, and the sign-in hook (Web.SessionEvents) refuses a creation at the limit, counting,
/// creating and adding the row under one Lock per address, so that two sign-ins never both take the last place.
/// OnLogin runs as the demo account, which holds no SQL privilege, so Recent walks this class's own index and opens rows
/// by id, with no SQL. Purge keeps one hour (AD-27), whatever its argument says.
///
/// AddressHash is the HMAC-SHA-256 of the address, base64url without padding (43 characters), keyed by a per-instance secret of
/// 32 random bytes. The secret lives only in ^OcuTalonP.AddrCountK (KEYGLOBAL), in the private database (AD-3), as
/// $ListBuild(marker, key); only the private method Key reaches it. The marker is the public lastReset, which the start writes
/// from the reset schedule's last reset (AD-25). Key makes the key at its first use after a start whose marker differs from the
/// node's, and keeps it across restarts with the same marker (AD-5). A start itself never makes a key, and the only caller with
/// an address is a counted sign-in, so a golden copy (captured after a start with no visitor data) holds none; a key that a copy
/// did hold would carry an older marker and be replaced at the first use after the next reset. With no key to be had, AddressHash
/// is "" and the counter fails closed: Lock answers 0, Add an error, Recent 0.
Class OcuTalon.Data.AddressCounter Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.AddrCount";

/// The private global of the address key: $ListBuild(marker, key), with no subscript.
Parameter KEYGLOBAL = "^OcuTalonP.AddrCountK";

/// The seconds that Key waits for the key lock, and the seconds that Lock waits for an address's lock.
Parameter WAIT [ Final ] = 5;

/// The keyed hash of the client address (AddressHash), never the address.
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
	Set hash = ..AddressHash(address)
	If hash = "" Quit 0
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
	Set hash = ..AddressHash(address)
	If hash = "" Quit $SYSTEM.Status.Error(5001, "The address counter has no key")
	Set row = ..%New()
	Set row.AddressHash = hash
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// Takes the address's lock, waiting at most 5 seconds: 1 when it is held, 0 otherwise (also when there is no key). The lock
/// name is the address's AddressHash.
ClassMethod Lock(address As %String) As %Boolean
{
	Set hash = ..AddressHash(address)
	If hash = "" Quit 0
	Lock +^OcuTalon.Data.AddressCounter(hash):(..#WAIT)
	Quit $Test
}

/// Releases the address's lock.
ClassMethod Unlock(address As %String)
{
	Set hash = ..AddressHash(address)
	If hash = "" Quit
	Lock -^OcuTalon.Data.AddressCounter(hash)
}

/// The HMAC-SHA-256 of the UTF-8 address under the instance's key, base64url without padding (43 characters), or "" when there
/// is no key to be had (Key).
ClassMethod AddressHash(address As %String) As %String
{
	Set key = ..Key()
	If key = "" Quit ""
	Quit $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.HMACSHA(256, $ZConvert(address, "O", "UTF8"), key), 1), "+/=", "-_")
}

/// The key of the current reset: the node's key when its marker is the public lastReset, else a new one of 32 random bytes made
/// under the key lock (waiting at most 5 seconds) and stored with that marker. "" when lastReset cannot be read or the lock was
/// not taken in time; nothing is stored then. The only reader and writer of KEYGLOBAL, and its value never leaves this method.
ClassMethod Key() As %String [ Private ]
{
	Set marker = ##class(OcuTalon.Data.Public.Settings).Get("lastReset", .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set node = ..#KEYGLOBAL
	Set value = $Get(@node)
	If $ListValid(value) && ($ListLength(value) = 2) && ($List(value, 1) = marker) && ($Length($List(value, 2)) = 32) Quit $List(value, 2)
	Lock +@node:(..#WAIT)
	If '$Test Quit ""
	Try {
		Set value = $Get(@node)
		If '($ListValid(value) && ($ListLength(value) = 2) && ($List(value, 1) = marker) && ($Length($List(value, 2)) = 32)) {
			Set value = $ListBuild(marker, $SYSTEM.Encryption.GenCryptRand(32))
			Set @node = value
		}
		Set key = $List(value, 2)
	} Catch {
		Set key = ""
	}
	Lock -@node
	Quit key
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
	Quit ##class(OcuTalon.Data.Public.Settings).Shift(utc, seconds)
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
