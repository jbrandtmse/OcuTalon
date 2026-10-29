/// One evaluation case's result in one run (AD-22, AD-30, AD-33). Lane A. The two writers are Lane A's and write only through the
/// class methods below:
///   - EvalIn opens the row (Open) as sent when it sends the case's Item to Intake, or, for a turn case (all-clear or command), when it
///     asks Decide for the turn;
///   - EvalSink takes the open row (Pending) by the Item's ItemId and completes it as decided from the ItemDecision, or the TurnResult
///     of a turn case, and from the bridge's Decision and Usage rows.
/// A case that EvalIn does not send has no row. A sent case that is never decided stays visible as a row in state sent.
/// The run is RunRef, the Ref that is also the SuperSession of every message of the run. The case is CaseName, the name of its
/// folder in eval/, and SourceItemId is the case's recorded item id (for a turn case, which records no Item, the case's name). Times are UTC to the second. A cost that is not known is empty,
/// never 0. Rows exist only where EvalIn ran, which is throwaway stacks and CI, so the class has no purge.
Class OcuTalon.Eval.Data.CaseResult Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.EvalCaseResult";

/// The state of a row that EvalIn opened and EvalSink has not completed.
Parameter SENT = "sent";

/// The state of a row that EvalSink completed.
Parameter DECIDED = "decided";

/// The Ref of the run.
Property RunRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The name of the case: its folder in eval/.
Property CaseName As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The item id the case was recorded with, which EvalIn puts on the Item and every hop copies; for a turn case, the case's name.
Property SourceItemId As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The fresh ItemId that EvalIn gave the Item of this run (AD-14), or, for a turn case, its turn request.
Property ItemId As %String(COLLATION = "EXACT", MAXLEN = 22);

/// sent or decided.
Property State As %String(MAXLEN = 32);

/// When EvalIn sent the Item, or opened the row of a turn case before it asked Decide.
Property SentAt As %String(MAXLEN = 20);

/// When EvalSink completed the row.
Property DecidedAt As %String(MAXLEN = 20);

/// The Ref of the Decision row of the attention decision (a decide or, for an incident, a diagnose) or, for a turn case, of its turn; empty for a
/// fallback that has none.
Property DecisionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The outcome of the ItemDecision: one of Msg.Enum OUTCOME; empty for a turn case, which has none.
Property Outcome As %String(MAXLEN = 32);

/// 1 when the decision took the fallback route (AD-8).
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason of the ItemDecision, or of the TurnResult of a turn case: one of Msg.Enum FALLBACKREASON; empty when Fallback is 0.
Property FallbackReason As %String(MAXLEN = 32);

/// The cause category of a diagnose Decision's payload.
Property CauseCategory As %String(MAXLEN = 64);

/// The element at fault of a diagnose Decision's payload.
Property ElementAtFault As %String(MAXLEN = 128);

/// The fix kind of a diagnose Decision's payload; empty when it names no fix.
Property FixKind As %String(MAXLEN = 32);

/// The fix parameters of a diagnose Decision's payload, as the text of a JSON object; empty when it names no fix.
Property FixParameters As %String(MAXLEN = "");

/// The cost of the attention decision, or of a turn case's turn, in US dollars (AD-20); empty when any of its Usage rows is unpriced or it has none.
Property CostUSD As %Numeric(SCALE = 6);

/// The Ref of the Decision row of the untrusted turn that an act ran; empty when there was none.
Property TurnDecisionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The cost of that turn in US dollars; empty when it is not known or there was no turn.
Property TurnCostUSD As %Numeric(SCALE = 6);

/// The largest request in tokens over the Usage rows of the attention decision and the turn; empty when they have none.
Property LargestRequestTokens As %Integer;

Index RunCaseIndex On (RunRef, CaseName) [ Unique ];

Index ItemIdIndex On ItemId;

/// Saves the row of a case that was sent: state sent, SentAt now, with the ids as given. The run and the case are one row, so a second
/// row for the same case of a run is an error status, and so is an empty run, case or ItemId.
ClassMethod Open(runRef As %String, caseName As %String, sourceItemId As %String, itemId As %String) As %Status
{
	If (runRef = "") || (caseName = "") || (itemId = "") Quit $SYSTEM.Status.Error(5001, "OcuTalon.Eval.Data.CaseResult.Open needs a run, a case and an ItemId")
	Set row = ..%New()
	Set row.RunRef = runRef
	Set row.CaseName = caseName
	Set row.SourceItemId = sourceItemId
	Set row.ItemId = itemId
	Set row.State = ..#SENT
	Set row.SentAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Quit row.%Save()
}

/// The row of the ItemId that is still in state sent, or "" when there is none (an ItemId EvalIn did not send, or a row already decided).
ClassMethod Pending(itemId As %String) As OcuTalon.Eval.Data.CaseResult
{
	If itemId = "" Quit ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Eval_Data.CaseResult WHERE ItemId = ? AND State = ? ORDER BY ID", itemId, ..#SENT)
	If (result.%SQLCODE < 0) || 'result.%Next() Quit ""
	Quit ..%OpenId(result.%GetData(1))
}

/// How many rows of the run are still in state sent.
ClassMethod Unanswered(runRef As %String) As %Integer
{
	If runRef = "" Quit 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ? AND State = ?", runRef, ..#SENT)
	If (result.%SQLCODE < 0) || 'result.%Next() Quit 0
	Quit +result.%GetData(1)
}

/// Deletes the rows of the run, or, with a case name, the row of that case only. An empty run is an error status.
ClassMethod Remove(runRef As %String, caseName As %String = "") As %Status
{
	If runRef = "" Quit $SYSTEM.Status.Error(5001, "OcuTalon.Eval.Data.CaseResult.Remove needs a run")
	If caseName = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ?", runRef)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Eval_Data.CaseResult WHERE RunRef = ? AND CaseName = ?", runRef, caseName)
	}
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Removing the results of the run failed: "_result.%Message)
	Quit $SYSTEM.Status.OK()
}

Storage Default
{
<Data name="CaseResultDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunRef</Value>
</Value>
<Value name="3">
<Value>CaseName</Value>
</Value>
<Value name="4">
<Value>SourceItemId</Value>
</Value>
<Value name="5">
<Value>ItemId</Value>
</Value>
<Value name="6">
<Value>State</Value>
</Value>
<Value name="7">
<Value>SentAt</Value>
</Value>
<Value name="8">
<Value>DecidedAt</Value>
</Value>
<Value name="9">
<Value>DecisionRef</Value>
</Value>
<Value name="10">
<Value>Outcome</Value>
</Value>
<Value name="11">
<Value>Fallback</Value>
</Value>
<Value name="12">
<Value>FallbackReason</Value>
</Value>
<Value name="13">
<Value>CauseCategory</Value>
</Value>
<Value name="14">
<Value>ElementAtFault</Value>
</Value>
<Value name="15">
<Value>FixKind</Value>
</Value>
<Value name="16">
<Value>FixParameters</Value>
</Value>
<Value name="17">
<Value>CostUSD</Value>
</Value>
<Value name="18">
<Value>TurnDecisionRef</Value>
</Value>
<Value name="19">
<Value>TurnCostUSD</Value>
</Value>
<Value name="20">
<Value>LargestRequestTokens</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.EvalCaseResultD</DataLocation>
<DefaultData>CaseResultDefaultData</DefaultData>
<IdLocation>^OcuTalonP.EvalCaseResultD</IdLocation>
<IndexLocation>^OcuTalonP.EvalCaseResultI</IndexLocation>
<StreamLocation>^OcuTalonP.EvalCaseResultS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
