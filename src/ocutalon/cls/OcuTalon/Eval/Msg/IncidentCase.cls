/// An incident case of an evaluation run, from EvalIn to IncidentManager (AD-22, AD-30). Lane A. EvalIn sends it for a case of kind incident: the
/// case's fresh Ref, its name and the text of its recorded reader snapshot (ocutalon.readerSnapshot/1). IncidentManager's evaluation branch builds the
/// evidence pack from the snapshot, asks Decide for the diagnosis with owner eval, and sends EvalSink one OcuTalon.Msg.ItemDecision whose ItemId is
/// IncidentRef. It carries the snapshot's text, never a path, so that the diagnosis reads no file named by a message.
///   - The one writer is OcuTalon.Eval.In (SendIncident). It saves the message by sending it, once for each case of a run.
///   - The readers are IncidentManager (EvalCase) and OcuTalon.Watch.EvidencePack.EvalSnapshot, which finds the newest message of the
///     IncidentRef that the Diagnosis agent's read tools are called for and answers its recorded failures.
///   - It holds no secret: the snapshot is a recorded file that passed the redactor.
Class OcuTalon.Eval.Msg.IncidentCase Extends Ens.Request
{

/// The Ref that EvalIn minted for the case: the incident's Ref for the diagnosis, the ItemId of its Decision and of its CaseResult row.
Property IncidentRef As %String(MAXLEN = 22);

/// The case's name, its folder in eval/: the SourceItemId of the case's row.
Property SourceItemId As %String(MAXLEN = 128);

/// The text of the case's recorded reader snapshot, a JSON object of the format ocutalon.readerSnapshot/1.
Property Snapshot As %String(MAXLEN = "");

Storage Default
{
<Data name="IncidentCaseDefaultData">
<Subscript>"IncidentCase"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>SourceItemId</Value>
</Value>
<Value name="3">
<Value>Snapshot</Value>
</Value>
</Data>
<DefaultData>IncidentCaseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
