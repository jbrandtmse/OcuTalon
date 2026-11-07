/// The result of a digest case of an evaluation run, from Digest to EvalSink (AD-22, AD-28, AD-32). Lane A. Digest sends it once for each
/// OcuTalon.Eval.Msg.DigestCase, in place of the Notification of a session's digest, and EvalSink completes the case's OcuTalon.Eval.Data.CaseResult row
/// from it. It never reaches Notify, a channel item or a session, and it holds no secret.
///   - The one writer is OcuTalon.Digest.Process (FinishCase). It saves the message by sending it.
///   - The readers are OcuTalon.Eval.Sink, which completes the row, and OcuTalon.Eval.Report, which scores the case from it (DigestOf).
///   - CatalogKey and AllClear are the verdict of the case's rows (Checks.Render and the vital signs), Named the entries that did not pass in the order
///     Digest names them, and Checked the entries of the watched rows that are a result (Checks.Render's rule), in the order they were recorded.
///   - Fallback is true when the saved-for-later summary came back as a fallback or not at all; FallbackReason is then one of Msg.Enum FALLBACKREASON.
Class OcuTalon.Eval.Msg.DigestResult Extends Ens.Request
{

/// The ItemId of the DigestCase: the key of the case's row.
Property ItemId As %String(MAXLEN = 22);

/// The case's name: the SourceItemId of the case's row.
Property SourceItemId As %String(MAXLEN = 128);

/// The catalog key of the digest: Checks.Render's key over the watched rows.
Property CatalogKey As %String(MAXLEN = 128);

/// True when the digest gives an all-clear.
Property AllClear As %Boolean [ InitialExpression = 0 ];

/// The entries of the watched rows that did not pass, as the text of a JSON array, failed rows first and then the rows not checked.
Property Named As %String(MAXLEN = "");

/// The entries of the watched rows that are a result (an object with a non-blank string entry), as the text of a JSON array, in the order recorded.
Property Checked As %String(MAXLEN = "");

/// The Ref of the Decision of the summary request; empty when the case made none or it fell back with no decision.
Property DecisionRef As %String(MAXLEN = 22);

/// True when the summary request came back as a fallback or unusable.
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

Storage Default
{
<Data name="DigestResultDefaultData">
<Subscript>"DigestResult"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>SourceItemId</Value>
</Value>
<Value name="3">
<Value>CatalogKey</Value>
</Value>
<Value name="4">
<Value>AllClear</Value>
</Value>
<Value name="5">
<Value>Named</Value>
</Value>
<Value name="6">
<Value>Checked</Value>
</Value>
<Value name="7">
<Value>DecisionRef</Value>
</Value>
<Value name="8">
<Value>Fallback</Value>
</Value>
<Value name="9">
<Value>FallbackReason</Value>
</Value>
</Data>
<DefaultData>DigestResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
