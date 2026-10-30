/// FixExecutor's answer to an OcuTalon.Fix.Msg.DryRun (AD-16). When the dry run was worked out, Reason is empty, Targets holds the header ids that a repair would
/// resend (comma-separated, ascending; empty when none reads in the source format) and DryRun the dry run as JSON with exactly the keys of
/// OcuTalon.Bridge.Data.ApprovalRequest DRYRUNKEYS. When it could not be worked out, Reason holds one plain sentence (redacted) and Targets and DryRun are empty.
/// Lane A.
Class OcuTalon.Fix.Msg.DryRunResult Extends Ens.Response
{

/// The Ref of the incident that was asked about.
Property IncidentRef As %String(MAXLEN = 22);

/// The header ids to resend, comma-separated and ascending.
Property Targets As %String(MAXLEN = "");

/// The dry run, as JSON.
Property DryRun As %String(MAXLEN = "");

/// Why the dry run could not be worked out, or empty.
Property Reason As %String(MAXLEN = 1000);

Storage Default
{
<Data name="DryRunResultDefaultData">
<Subscript>"DryRunResult"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>Targets</Value>
</Value>
<Value name="3">
<Value>DryRun</Value>
</Value>
<Value name="4">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>DryRunResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
