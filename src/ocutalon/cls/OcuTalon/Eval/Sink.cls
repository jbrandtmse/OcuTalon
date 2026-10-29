/// EvalSink, the business operation that receives the decisions of evaluation runs (AD-22, AD-30). Lane A. Intake sends it the
/// OcuTalon.Msg.ItemDecision of an Item that EvalIn sent (owner eval), EvalIn sends it the OcuTalon.Eval.Msg.TurnResult of a turn case,
/// and it completes that case's OcuTalon.Eval.Data.CaseResult row.
/// It sends nothing, calls no model, and only reads the bridge's Decision and Usage rows. It never throws: a failure is logged and the
/// call answers OK, with no response.
///   - A message that is neither an ItemDecision nor a TurnResult, or an ItemDecision whose OwnerRef is not eval, is refused with a
///     warning and stores nothing.
///   - The row is the one in state sent for the message's ItemId (CaseResult.Pending). With none, which is an Item EvalIn did not send
///     or a second decision for a row already decided, a warning names the ItemId and SourceItemId and nothing is stored or changed.
///   - DecisionRef, Outcome, Fallback and FallbackReason come from the message. When the Decision row of DecisionRef is a diagnose, the
///     cause category, element at fault, fix kind and fix parameters (the text of a JSON object) come from its Payload; a payload that
///     names no fix leaves the fix empty, and one that is not a JSON object is logged as an error and leaves all four empty.
///   - CostUSD is the cost of the DecisionRef's Usage rows (Usage.Totals), empty when any row is unpriced, never 0. When the item has a
///     turn Decision (an act's untrusted turn), TurnDecisionRef and TurnCostUSD come from it. LargestRequestTokens is the largest over
///     the Usage rows of both decisions. A fallback with no DecisionRef leaves the cost and size fields empty.
///   - A TurnResult completes the row of its ItemId in the same way: DecisionRef, Fallback and FallbackReason come from the message (the
///     DecisionRef is the turn's Decision, and the Outcome stays empty), CostUSD is the cost of the DecisionRef's Usage rows and
///     LargestRequestTokens their largest request. A turn case has no act turn, so TurnDecisionRef and TurnCostUSD stay empty. Report
///     scores the case from the row and from the TurnResult.
///   - The row ends in state decided with DecidedAt now.
Class OcuTalon.Eval.Sink Extends Ens.BusinessOperation
{

/// The start of the warning for a refused message; its reason follows.
Parameter LOGREFUSED = "EvalSink refused a message: ";

/// The start of the warning for a decision that has no open row.
Parameter LOGNOROW = "EvalSink has no open case row for the decision";

/// The start of the error for a diagnose payload that cannot be read.
Parameter LOGPAYLOAD = "EvalSink could not read the diagnose payload of the decision ";

/// The start of the error for a failure while completing a row.
Parameter LOGFAILED = "EvalSink could not complete the case row: ";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Try {
		Do ..Complete($Get(pRequest))
	} Catch exception {
		$$$LOGERROR(..#LOGFAILED_exception.DisplayString())
	}
	Quit $$$OK
}

/// Completes the row of the ItemDecision, or logs why it does not.
Method Complete(request As %RegisteredObject) [ Private ]
{
	Set refusal = ..Refusal(request)
	If refusal '= "" {
		$$$LOGWARNING(..#LOGREFUSED_refusal_..Describe(request))
		Quit
	}
	Set row = ##class(OcuTalon.Eval.Data.CaseResult).Pending(request.ItemId)
	If '$IsObject(row) {
		$$$LOGWARNING(..#LOGNOROW_..Describe(request))
		Quit
	}
	Set turn = request.%IsA("OcuTalon.Eval.Msg.TurnResult")
	Set row.DecisionRef = request.DecisionRef
	Set row.Outcome = $Select(turn: "", 1: request.Outcome)
	Set row.Fallback = +request.Fallback
	Set row.FallbackReason = request.FallbackReason
	If request.DecisionRef '= "" {
		Set decision = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(request.DecisionRef)
		If $IsObject(decision) && (decision.Kind = "diagnose") Do ..ReadDiagnosis(row, decision)
		Set row.CostUSD = ##class(OcuTalon.Bridge.Data.Usage).Totals(request.DecisionRef).costUSD
		If 'turn {
			Set actTurn = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(request.ItemId, "turn")
			If $IsObject(actTurn) {
				Set row.TurnDecisionRef = actTurn.Ref
				Set row.TurnCostUSD = actTurn.CostUSD
			}
		}
		Set row.LargestRequestTokens = ..Largest(request.DecisionRef, row.TurnDecisionRef)
	}
	Set row.State = ##class(OcuTalon.Eval.Data.CaseResult).#DECIDED
	Set row.DecidedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set sc = row.%Save()
	If $$$ISERR(sc) $$$LOGERROR(..#LOGFAILED_$SYSTEM.Status.GetOneStatusText(sc))
}

/// Why the message is not taken, "" when it is: neither an ItemDecision nor a TurnResult, or an ItemDecision of an owner other than eval.
Method Refusal(request As %RegisteredObject) As %String [ Private ]
{
	If '..Known(request) Quit "it is neither an ItemDecision nor a TurnResult"
	If request.%IsA("OcuTalon.Msg.ItemDecision") && (request.OwnerRef '= ##class(OcuTalon.Data.Ownership).#EVAL) Quit "its owner is '"_$Extract(request.OwnerRef, 1, 40)_"', not eval"
	Quit ""
}

/// 1 when the message is an ItemDecision or a TurnResult.
Method Known(request As %RegisteredObject) As %Boolean [ Private ]
{
	Quit $IsObject(request) && (request.%IsA("OcuTalon.Msg.ItemDecision") || request.%IsA("OcuTalon.Eval.Msg.TurnResult"))
}

/// The ItemId and SourceItemId of the message when it is an ItemDecision or a TurnResult, as the end of a log text, each cut at 40
/// characters; empty for any other message.
Method Describe(request As %RegisteredObject) As %String [ Private ]
{
	If '..Known(request) Quit ""
	Quit " (ItemId "_$Extract(request.ItemId, 1, 40)_", SourceItemId "_$Extract(request.SourceItemId, 1, 40)_")"
}

/// Puts the cause category, element at fault, fix kind and fix parameters of the diagnose Decision's payload on the row. A payload that is
/// empty (a fallback has none) leaves them empty; one that cannot be read as a JSON object is logged and leaves them empty.
Method ReadDiagnosis(row As OcuTalon.Eval.Data.CaseResult, decision As OcuTalon.Bridge.Data.Decision) [ Private ]
{
	If decision.Payload = "" Quit
	Try {
		Set diagnosis = ##class(%DynamicObject).%FromJSON(decision.Payload)
		If '$IsObject(diagnosis) || 'diagnosis.%IsA("%Library.DynamicObject") Throw ##class(%Exception.General).%New("PayloadNotObject", 5001, , "the payload is not a JSON object")
		Set parameters = diagnosis.%Get("fixParameters")
		Set row.CauseCategory = $Extract(##class(OcuTalon.Eval.In).Scalar(diagnosis, "causeCategory"), 1, 64)
		Set row.ElementAtFault = $Extract(##class(OcuTalon.Eval.In).Scalar(diagnosis, "elementAtFault"), 1, 128)
		Set row.FixKind = $Extract(##class(OcuTalon.Eval.In).Scalar(diagnosis, "fixKind"), 1, 32)
		Set row.FixParameters = $Select($IsObject(parameters) && parameters.%IsA("%Library.DynamicObject"): parameters.%ToJSON(), 1: "")
	} Catch exception {
		Set row.CauseCategory = "", row.ElementAtFault = "", row.FixKind = "", row.FixParameters = ""
		$$$LOGERROR(..#LOGPAYLOAD_decision.Ref_": "_exception.DisplayString())
	}
}

/// The largest LargestRequestTokens over the Usage rows of the decision and of the turn decision (which may be empty), or "" when they
/// have none.
Method Largest(decisionRef As %String, turnRef As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(LargestRequestTokens) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef IN (?, ?)", decisionRef, $Select(turnRef '= "": turnRef, 1: decisionRef))
	If result.%SQLCODE < 0 {
		$$$LOGERROR(..#LOGFAILED_"the Usage rows of the decision cannot be read: "_result.%Message)
		Quit ""
	}
	If 'result.%Next() Quit ""
	Quit result.%GetData(1)
}

}
