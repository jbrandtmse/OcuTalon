/// The ask for a dry run (AD-16): IncidentManager sends it to FixExecutor, synchronously, in the incident's trace session, at the notice of a diagnosis with a fix
/// (Story 7.2). It names the incident and the fix: the kind (FixKind, one of OcuTalon.Fix.Kind Names) and its parameters (Parameters, one JSON object).
/// FixExecutor answers with an OcuTalon.Fix.Msg.DryRunResult and changes nothing. Lane A.
Class OcuTalon.Fix.Msg.DryRun Extends Ens.Request
{

/// The Ref of the incident whose failure groups the dry run reads.
Property IncidentRef As %String(MAXLEN = 22);

/// The kind of the fix: the NAME of a class of OcuTalon.Fix.Kind.
Property FixKind As %String(MAXLEN = 32);

/// The kind's parameters, as one JSON object.
Property Parameters As %String(MAXLEN = "");

Storage Default
{
<Data name="DryRunDefaultData">
<Subscript>"DryRun"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>FixKind</Value>
</Value>
<Value name="3">
<Value>Parameters</Value>
</Value>
</Data>
<DefaultData>DryRunDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
