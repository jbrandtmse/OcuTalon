/// The result of a turn case of an evaluation run, from EvalIn to EvalSink (AD-22, AD-30). Lane A. A turn case is an all-clear or a command
/// case: EvalIn sends it to Decide as a user turn of owner eval, keeps the case's recorded check rows here, and, when Decide has answered,
/// sends this message to EvalSink, which completes the case's OcuTalon.Eval.Data.CaseResult row from it. It never reaches OutcomeRouter,
/// Notify or Conversation, and it holds no secret: the rows are the case's own, and the reply is the filtered text of Decide.
///   - The one writer is OcuTalon.Eval.In (SendTurn). It saves the message before the send with ItemId, SourceItemId (the case's name) and
///     RecordedChecks, and saves it again, and sends it, once the reply is in.
///   - The two readers are the eval branch of check_status (OcuTalon.Tools.WatchAnswers.EvalCheckResults, which finds the message by the
///     ItemId of the call's bridge context and reads RecordedChecks) and OcuTalon.Eval.Report (which scores a turn case from the reply and the rendered key).
///   - Fallback is true when Decide answered with a fallback, or when Decide was busy at every ask (EvalIn then sets the reason rate_limited),
///     and FallbackReason is then one of Msg.Enum FALLBACKREASON; such a message has no reply text and no rendered key.
Class OcuTalon.Eval.Msg.TurnResult Extends Ens.Request
{

/// The ItemId that EvalIn minted for the turn request: the key of the case's row and of its Decision rows.
Property ItemId As %String(MAXLEN = 22);

/// The case's recorded item id for the row: the case's name.
Property SourceItemId As %String(MAXLEN = 128);

/// The case's recorded check rows as the text of a JSON array, for an all-clear case; empty for a command case. check_status answers
/// these rows for the turn's ItemId when the call's owner is eval.
Property RecordedChecks As %String(MAXLEN = "");

/// The Ref of the turn's Decision row; empty when the turn was a fallback with no decision.
Property DecisionRef As %String(MAXLEN = 22);

/// True when a tool was called in the turn (the Reply's ToolsRun).
Property ToolsRun As %Boolean [ InitialExpression = 0 ];

/// The reply text, as Decide filtered it.
Property ReplyText As %String(MAXLEN = "");

/// The catalog key that Checks.Render gave the rows that check_status put in the Reply's HostData; empty when the reply held none.
Property CatalogKey As %String(MAXLEN = 128);

/// The rendered rows as the text of a JSON array; empty when the reply held none.
Property CheckRows As %String(MAXLEN = "");

/// True when Decide answered with a fallback, or was busy at every ask.
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

Storage Default
{
<Data name="TurnResultDefaultData">
<Subscript>"TurnResult"</Subscript>
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
<Value>DecisionRef</Value>
</Value>
<Value name="5">
<Value>ToolsRun</Value>
</Value>
<Value name="6">
<Value>ReplyText</Value>
</Value>
<Value name="7">
<Value>CatalogKey</Value>
</Value>
<Value name="8">
<Value>CheckRows</Value>
</Value>
<Value name="9">
<Value>Fallback</Value>
</Value>
<Value name="10">
<Value>FallbackReason</Value>
</Value>
</Data>
<DefaultData>TurnResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
