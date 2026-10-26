/// What a fix run reports to IncidentManager (AD-16): FixExecutor sends it to IncidentManager as the run goes (Final 0, progress) and when it ends (Final 1, or
/// Interrupted 1 for a run that was cut short), and Sweep sends one for a run that was interrupted (Stories 7.3 to 7.5). IncidentManager moves the incident
/// by it (OcuTalon.Watch.Transitions): a run that ended moves a fixing incident on, a progress report changes nothing but the incident's published view. The
/// counts are those of the run: Total records in the affected set, Resent the records sent again, Completed those that completed, FailedAgain those that failed
/// again and Skipped those that were left out. Lane A.
Class OcuTalon.Fix.Msg.FixResult Extends Ens.Request
{

/// The Ref of the approval request whose fix ran.
Property ApprovalRef As %String(MAXLEN = 22);

/// The Ref of the incident the request belongs to.
Property IncidentRef As %String(MAXLEN = 22);

/// True when the run has ended.
Property Final As %Boolean [ InitialExpression = 0 ];

/// True when the run was cut short and did not end by itself.
Property Interrupted As %Boolean [ InitialExpression = 0 ];

Property Total As %Integer;

Property Resent As %Integer;

Property Completed As %Integer;

Property FailedAgain As %Integer;

Property Skipped As %Integer;

/// Why the run ended as it did, when it did not complete.
Property Reason As %String(MAXLEN = 1000);

Storage Default
{
<Data name="FixResultDefaultData">
<Subscript>"FixResult"</Subscript>
<Value name="1">
<Value>ApprovalRef</Value>
</Value>
<Value name="2">
<Value>IncidentRef</Value>
</Value>
<Value name="3">
<Value>Final</Value>
</Value>
<Value name="4">
<Value>Interrupted</Value>
</Value>
<Value name="5">
<Value>Total</Value>
</Value>
<Value name="6">
<Value>Resent</Value>
</Value>
<Value name="7">
<Value>Completed</Value>
</Value>
<Value name="8">
<Value>FailedAgain</Value>
</Value>
<Value name="9">
<Value>Skipped</Value>
</Value>
<Value name="10">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>FixResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
