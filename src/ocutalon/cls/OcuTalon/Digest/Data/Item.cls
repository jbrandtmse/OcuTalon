/// One item saved for the digest (AD-30, AD-33): an untrusted item that Triage decided to keep for later. Lane A. The only writer is
/// OcuTalon.Digest.Store, one row for each ItemId. This class holds the read of one session's items (Since) and the purge of the old ones
/// (Purge, declared to the purge task by OcuTalon.Install.Step.Digest, AD-27). Row ids never leave the server.
Class OcuTalon.Digest.Data.Item Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.DigestItem";

/// The owner of the item: the ItemDecision's OwnerRef, a session's Ref or the literal instance (AD-2). Refs are case-sensitive.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The item's Ref (AD-14). Refs are case-sensitive, so two ItemIds that differ in the case of a letter are two items.
Property ItemId As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the item's Decision row (AD-20).
Property DecisionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The item's source: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The one-line summary that the caller wrote in code, never model text (AD-6).
Property Summary As %String(MAXLEN = 80);

/// When the store kept the item, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index ItemIdIndex On ItemId [ Unique ];

Index SessionRefRecordedAtIndex On (SessionRef, RecordedAt);

Index RecordedAtIndex On RecordedAt;

/// The items of one session recorded at or after since, newest first (the ones of one second, the later saved first), as a dynamic array of
/// {"itemId", "decisionRef", "channel", "summary", "recordedAt"}. The session is compared exactly. since is "" for every item of the session,
/// or a UTC time, YYYY-MM-DDThh:mm:ssZ, that Data.Time.ToLocal reads; the time itself is included. An empty sessionRef or an unreadable since
/// is an error status, with items an empty array.
ClassMethod Since(sessionRef As %String, since As %String, Output items As %DynamicArray) As %Status
{
	Set items = []
	If sessionRef = "" Quit $SYSTEM.Status.Error(5001, "OcuTalon.Digest.Data.Item.Since needs the Ref of a session")
	If (since '= "") && (##class(OcuTalon.Data.Time).ToLocal(since) = "") {
		Quit $SYSTEM.Status.Error(5001, "OcuTalon.Digest.Data.Item.Since cannot read the time '"_$Extract(since, 1, 40)_"': it is empty or YYYY-MM-DDThh:mm:ssZ in UTC")
	}
	Set sql = "SELECT ItemId, DecisionRef, Channel, Summary, RecordedAt FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?"
	If since '= "" Set sql = sql_" AND RecordedAt >= ?"
	Set sql = sql_" ORDER BY RecordedAt DESC, %ID DESC"
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare(sql)
	If $$$ISERR(sc) Quit sc
	Set result = $Select(since '= "": statement.%Execute(sessionRef, since), 1: statement.%Execute(sessionRef))
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Reading the digest items failed: "_result.%Message)
	Set found = []
	While result.%Next() {
		Do found.%Push({"itemId": (result.%Get("ItemId")), "decisionRef": (result.%Get("DecisionRef")), "channel": (result.%Get("Channel")), "summary": (result.%Get("Summary")), "recordedAt": (result.%Get("RecordedAt"))})
	}
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Reading the digest items failed: "_result.%Message)
	Set items = found
	Quit $SYSTEM.Status.OK()
}

/// Deletes the items recorded before the cutoff: now in UTC moved back daysToKeep whole days (Bridge.Time.DaysCutoff, by date arithmetic on the UTC date).
/// An item recorded at the cutoff stays. daysToKeep must be a whole number of at least 1; anything else is an error status and nothing is deleted.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff(daysToKeep, "OcuTalon.Digest.Data.Item.Purge", .cutoff)
	If $$$ISERR(sc) || (cutoff = "") Quit sc
	Try {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE RecordedAt < ?", cutoff)
		If result.%SQLCODE < 0 Set sc = $SYSTEM.Status.Error(5001, "Deleting the old digest items failed: "_result.%Message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Storage Default
{
<Data name="ItemDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>ItemId</Value>
</Value>
<Value name="4">
<Value>DecisionRef</Value>
</Value>
<Value name="5">
<Value>Channel</Value>
</Value>
<Value name="6">
<Value>Summary</Value>
</Value>
<Value name="7">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.DigestItemD</DataLocation>
<DefaultData>ItemDefaultData</DefaultData>
<IdLocation>^OcuTalonP.DigestItemD</IdLocation>
<IndexLocation>^OcuTalonP.DigestItemI</IndexLocation>
<StreamLocation>^OcuTalonP.DigestItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
