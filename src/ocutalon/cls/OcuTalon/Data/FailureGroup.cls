/// A group of same-cause failures within an incident (AD-15). Lane A. IncidentManager is its only writer. The groups of an incident are numbered
/// from 1 by Seq in the order they were made, and OfIncident reads them by that number, with no SQL (AD-13).
Class OcuTalon.Data.FailureGroup Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.FailGroup";

/// The Ref of the incident (AD-15).
Property IncidentRef As %String(MAXLEN = 22);

/// The production item that failed.
Property ItemName As %String(MAXLEN = 128);

/// The normalised error text that groups the failures.
Property ErrorPattern As %String(MAXLEN = 1000);

/// The keys (h<header id> or l<log id>, as OcuTalon.Watch.Mark.KeyOf gives them) of the group's newest failures, comma-separated, newest last, at
/// most OcuTalon.Watch.Settle SEENMAX of them. IncidentManager holds a failure once by this set.
Property Seen As %String(MAXLEN = "");

/// The group's number within its incident: 1 for the first group.
Property Seq As %Integer;

/// The failures held in the group (kept by IncidentManager as the incident's Count is).
Property Count As %Integer [ SqlFieldName = FailureCount ];

/// When the group's first failure arrived, UTC to the second.
Property FirstAt As %String(MAXLEN = 20);

/// When the group's last failure arrived, UTC to the second.
Property LastAt As %String(MAXLEN = 20);

/// The group's failures at the incident's notice: the incident's NoticeCount for the group, set when the settle rule ends.
Property NoticeCount As %Integer;

/// The error of the group's first failure in one plain sentence of at most 80 characters (OcuTalon.Watch.ErrorText.Summary).
Property ErrorSummary As %String(MAXLEN = 1000);

/// The key of Seen where the newest dry-run ask before the current one ended; empty before a second ask. The newest ask's window starts after it
/// (OcuTalon.Watch.Settle.Window). Written by IncidentManager only, before the ask is sent (Story 7.6).
Property AskedFrom As %String(MAXLEN = 32);

/// The key of Seen where the newest dry-run ask ended: the last key of Seen when the ask was made; empty before the first ask. A failed message is in the
/// window of one ask only, so a request's targets never overlap those of another (Story 7.6).
Property AskedTo As %String(MAXLEN = 32);

Index IncidentRefIndex On IncidentRef;

Index SeqIndex On (IncidentRef, Seq) [ Unique ];

/// The most groups that OfIncident reads for one incident.
Parameter MAXGROUPS = 100;

/// The groups of the incident, in Seq order, as a list of objects: SeqIndexOpen(ref, 1), then 2, and so on up to the first Seq that has no row, at most
/// MAXGROUPS. Reads rows by object access only, so that a REST request may call it (AD-13).
ClassMethod OfIncident(ref As %String) As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	If $Get(ref) = "" Quit list
	For seq = 1:1:..#MAXGROUPS {
		Set group = ..SeqIndexOpen(ref, seq)
		If '$IsObject(group) Quit
		Do list.Insert(group)
	}
	Quit list
}

/// The keys of Seen that the newest dry-run ask covers: its window (Settle.Window of AskedFrom and AskedTo), or the whole Seen while the group has no
/// mark, as before the first ask was recorded.
Method AskedKeys() As %String
{
	If (..AskedFrom = "") && (..AskedTo = "") Quit ..Seen
	Quit ##class(OcuTalon.Watch.Settle).Window(..Seen, ..AskedFrom, ..AskedTo)
}

Storage Default
{
<Data name="FailureGroupDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>IncidentRef</Value>
</Value>
<Value name="3">
<Value>ItemName</Value>
</Value>
<Value name="4">
<Value>ErrorPattern</Value>
</Value>
<Value name="5">
<Value>Seen</Value>
</Value>
<Value name="6">
<Value>Seq</Value>
</Value>
<Value name="7">
<Value>Count</Value>
</Value>
<Value name="8">
<Value>FirstAt</Value>
</Value>
<Value name="9">
<Value>LastAt</Value>
</Value>
<Value name="10">
<Value>NoticeCount</Value>
</Value>
<Value name="11">
<Value>ErrorSummary</Value>
</Value>
<Value name="12">
<Value>AskedFrom</Value>
</Value>
<Value name="13">
<Value>AskedTo</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.FailGroupD</DataLocation>
<DefaultData>FailureGroupDefaultData</DefaultData>
<IdLocation>^OcuTalonP.FailGroupD</IdLocation>
<IndexLocation>^OcuTalonP.FailGroupI</IndexLocation>
<StreamLocation>^OcuTalonP.FailGroupS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
