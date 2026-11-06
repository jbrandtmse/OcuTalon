/// One digest that was sent (AD-18, AD-30, AD-33): the per-session digest record. Lane A. The only writer is OcuTalon.Digest.Process, one row
/// for each digest sent (Story 17.6); a session's last digest is its newest row. Its window starts at the newest SentAt, and the next scheduled
/// digest is due after the newest scheduled row's DueAt. The rows are purged with the digest area's rows (AD-27). Row ids never leave the server.
Class OcuTalon.Digest.Data.Sent Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.DigestSent";

/// The digest's Ref (AD-14). Refs are case-sensitive.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the session the digest went to.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The ItemId of the digest's model request, when it made one.
Property ItemId As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the Decision row of the model request, when it made one (AD-20).
Property DecisionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// Scheduled, or requested (the SendDigest command).
Property Kind As %String(MAXLEN = 32);

/// The time the digest was due, UTC to the second.
Property DueAt As %String(MAXLEN = 20);

/// The start of the window the digest covers, UTC to the second.
Property WindowStart As %String(MAXLEN = 20);

/// When the digest was sent, UTC to the second.
Property SentAt As %String(MAXLEN = 20);

/// The catalog key of the digest's all-clear or not-watching sentence (AD-28, AD-32).
Property CatalogKey As %String(MAXLEN = 128);

/// The Slots of the digest's Notification as JSON, the summary inside.
Property Slots As %String(MAXLEN = "");

/// 1 when the digest said everything passed.
Property AllClear As %Boolean [ InitialExpression = 0 ];

Index RefIndex On Ref [ Unique ];

Index SessionRefSentAtIndex On (SessionRef, SentAt);

Index SessionRefDueAtIndex On (SessionRef, DueAt);

/// Deletes the digests sent before the cutoff: now in UTC moved back daysToKeep whole days (Bridge.Time.DaysCutoff). A digest sent at the cutoff
/// stays, and so does each session's newest digest whatever its age, because its window starts there. daysToKeep must be a whole number of at
/// least 1; anything else is an error status and nothing is deleted.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff(daysToKeep, "OcuTalon.Digest.Data.Sent.Purge", .cutoff)
	If $$$ISERR(sc) || (cutoff = "") Quit sc
	Try {
		Set old = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionRef FROM OcuTalon_Digest_Data.Sent WHERE SentAt < ?", cutoff)
		If old.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the old digests failed: "_old.%Message))
		While old.%Next() {
			Set candidate(old.%Get("SessionRef"), old.%Get("ID")) = ""
		}
		Set session = ""
		For {
			Set session = $Order(candidate(session))
			Quit:session=""
			Set newest = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", session)
			If newest.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Reading the newest digest failed: "_newest.%Message))
			Set keep = $Select(newest.%Next(): newest.%Get("ID"), 1: "")
			Set id = ""
			For {
				Set id = $Order(candidate(session, id))
				Quit:id=""
				If id = keep Continue
				Set deleted = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE ID = ?", id)
				If deleted.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Deleting an old digest failed: "_deleted.%Message))
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Storage Default
{
<Data name="SentDefaultData">
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
<Value>ItemId</Value>
</Value>
<Value name="5">
<Value>DecisionRef</Value>
</Value>
<Value name="6">
<Value>Kind</Value>
</Value>
<Value name="7">
<Value>DueAt</Value>
</Value>
<Value name="8">
<Value>WindowStart</Value>
</Value>
<Value name="9">
<Value>SentAt</Value>
</Value>
<Value name="10">
<Value>CatalogKey</Value>
</Value>
<Value name="11">
<Value>Slots</Value>
</Value>
<Value name="12">
<Value>AllClear</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.DigestSentD</DataLocation>
<DefaultData>SentDefaultData</DefaultData>
<IdLocation>^OcuTalonP.DigestSentD</IdLocation>
<IndexLocation>^OcuTalonP.DigestSentI</IndexLocation>
<StreamLocation>^OcuTalonP.DigestSentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
