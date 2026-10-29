/// One run of an approved fix (AD-16): one row per approved request that FixExecutor takes up, a run that could not start included. Lane A.
///   - Copies holds the header ids of the copies that the run resent, in resend order, each registered right after its resend, so that a run that was cut off still
///     shows how far it got. CopiesIndex finds the run of a copy (CopyOf), so that IncidentManager does not take a copy's failure for a new one (AD-15).
///   - ResentAt is the time (UTC to the second) of the run's last registration: the 60 seconds that FixExecutor waits for the copies run from it, and a run with
///     ResentAt set and EndedAt empty is a run that waits or was given up on. EndedAt is the time the run ended, and is set together with the counts, which are
///     the run's final FixResult: Total, Resent, Completed, FailedAgain, Skipped, Interrupted and Reason (Story 7.4). A run without EndedAt has no result. FixExecutor
///     is the only writer of these properties.
///   - OfRequest gives the run of a request and CopyOf the request of a copy, both through the indexes (AD-13).
Class OcuTalon.Data.FixRun Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.FixRun";

/// The Ref of the approval request (AD-11).
Property ApprovalRef As %String(MAXLEN = 22);

/// The Ref of the incident (AD-15).
Property IncidentRef As %String(MAXLEN = 22);

/// When the run started, UTC to the second.
Property StartedAt As %String(MAXLEN = 20);

/// The header ids of the copies the run resent, in resend order (the production's header ids, as text).
Property Copies As list Of %String(MAXLEN = 20);

/// When the run registered its last copy, UTC to the second; empty for a run that resent no copy.
Property ResentAt As %String(MAXLEN = 20);

/// When the run ended, UTC to the second; empty while it has no final result.
Property EndedAt As %String(MAXLEN = 20);

/// The counts of the run's final FixResult: the targets of the request, the copies resent, the copies that completed, the copies that failed again, the targets
/// left out and the targets the run did not reach.
Property Total As %Integer;

Property Resent As %Integer;

Property Completed As %Integer;

Property FailedAgain As %Integer;

Property Skipped As %Integer;

Property Interrupted As %Integer;

/// Why the run ended as it did, when it did not complete (redacted, as the FixResult carries it).
Property Reason As %String(MAXLEN = 1000);

Index ApprovalRefIndex On ApprovalRef;

Index CopiesIndex On Copies(ELEMENTS);

Index IncidentRefIndex On IncidentRef;

/// The run of the request, or "" when there is none: the run whose ApprovalRef is the Ref exactly (the index compares without regard to case). Object access only
/// (ApprovalRefIndexExists and %OpenId), so that a REST request may call it (AD-13).
ClassMethod OfRequest(ref As %String) As OcuTalon.Data.FixRun
{
	If $Get(ref) = "" Quit ""
	If '..ApprovalRefIndexExists(ref, .id) Quit ""
	Set run = ..%OpenId(id)
	If '$IsObject(run) || (run.ApprovalRef '= ref) Quit ""
	Quit run
}

/// The Ref of the request whose run registered the copy (the header id) in the namespace, "" when no run did. A header id is the production's own, so the run's
/// incident must watch the namespace. Reads CopiesIndex (SQL), so IncidentManager, which has the grant, calls it, not a REST request. A read that fails gives "":
/// the failure then is taken for a new one.
ClassMethod CopyOf(namespace As %String, headerId As %String) As %String
{
	If ($Get(namespace) = "") || ($Get(headerId) = "") Quit ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT r.ApprovalRef FROM OcuTalon_Data.FixRun r, OcuTalon_Data.Incident i WHERE FOR SOME %ELEMENT(r.Copies) (%VALUE = ?) AND i.Ref = r.IncidentRef AND i.Namespace = ?", headerId, namespace)
	If rs.%SQLCODE < 0 Quit ""
	If rs.%Next() Quit rs.%Get("ApprovalRef")
	Quit ""
}

Storage Default
{
<Data name="FixRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ApprovalRef</Value>
</Value>
<Value name="3">
<Value>IncidentRef</Value>
</Value>
<Value name="4">
<Value>StartedAt</Value>
</Value>
<Value name="5">
<Value>Copies</Value>
</Value>
<Value name="6">
<Value>ResentAt</Value>
</Value>
<Value name="7">
<Value>EndedAt</Value>
</Value>
<Value name="8">
<Value>Total</Value>
</Value>
<Value name="9">
<Value>Resent</Value>
</Value>
<Value name="10">
<Value>Completed</Value>
</Value>
<Value name="11">
<Value>FailedAgain</Value>
</Value>
<Value name="12">
<Value>Skipped</Value>
</Value>
<Value name="13">
<Value>Interrupted</Value>
</Value>
<Value name="14">
<Value>Reason</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.FixRunD</DataLocation>
<DefaultData>FixRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.FixRunD</IdLocation>
<IndexLocation>^OcuTalonP.FixRunI</IndexLocation>
<StreamLocation>^OcuTalonP.FixRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
