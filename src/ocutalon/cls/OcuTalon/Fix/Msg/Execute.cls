/// The order to carry out one approved fix (AD-16). IncidentManager sends it to FixExecutor, asynchronously and with no answer wanted, in the incident's trace
/// session, when the incident's table (OcuTalon.Watch.Transitions) says that a fix runs: it carries only the Ref of the approval request, and FixExecutor
/// reads everything else from the request's row (AD-11). FixExecutor handles it in Story 7.3. The SQL table is FixExecute because Execute is an SQL reserved word.
/// Lane A.
Class OcuTalon.Fix.Msg.Execute Extends Ens.Request [ SqlTableName = FixExecute ]
{

/// The Ref of the approval request whose fix is carried out.
Property ApprovalRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="ExecuteDefaultData">
<Subscript>"Execute"</Subscript>
<Value name="1">
<Value>ApprovalRef</Value>
</Value>
</Data>
<DefaultData>ExecuteDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
