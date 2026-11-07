/// A digest case of an evaluation run, from EvalIn to Digest (AD-22, AD-28, AD-32). Lane A. EvalIn sends it for a case of kind digest: the case's fresh
/// ItemId, its name and its recorded rows. Digest composes the digest from those rows in place of Checks.Coverage.Build, as the owner eval, and sends
/// EvalSink one OcuTalon.Eval.Msg.DigestResult instead of a Notification. It has no owner, session, channel or destination property: Digest uses the
/// reserved owner eval for everything it does with a case, so no message can aim a case at a session.
///   - The one writer is OcuTalon.Eval.In (SendDigest). It saves the message by sending it, once for each case of a run.
///   - The one reader is OcuTalon.Digest.Process (Evaluated).
///   - It holds no secret: the rows and the saved summaries are the case's own recorded text.
Class OcuTalon.Eval.Msg.DigestCase Extends Ens.Request
{

/// The ItemId that EvalIn minted for the case: the key of the case's row.
Property ItemId As %String(MAXLEN = 22);

/// The case's name, its folder in eval/: the SourceItemId of the case's row.
Property SourceItemId As %String(MAXLEN = 128);

/// The watched rows as the text of a JSON array of {result, entry, finding, checkedAt}.
Property RecordedChecks As %String(MAXLEN = "");

/// The vital signs as the text of a JSON object {rows, figures}; empty for none.
Property RecordedVitals As %String(MAXLEN = "");

/// The saved-for-later summaries as the text of a JSON array of strings; empty for none.
Property RecordedSaved As %String(MAXLEN = "");

Storage Default
{
<Data name="DigestCaseDefaultData">
<Subscript>"DigestCase"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>SourceItemId</Value>
</Value>
<Value name="3">
<Value>RecordedChecks</Value>
</Value>
<Value name="4">
<Value>RecordedVitals</Value>
</Value>
<Value name="5">
<Value>RecordedSaved</Value>
</Value>
</Data>
<DefaultData>DigestCaseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
