/// The bridge's host sink (AD-31): the one class through which the bridge tells its host that state changed.
/// Every method does nothing by default, so the bridge runs alone (FR-5). A host extends this class and names the
/// subclass in the HostSinkClass setting of the Decide item; the bridge calls OnEvent after commit, in the job that
/// changed state, for the eight event types of EVENTS, and wraps every call in its own error handling.
///   - decision.* and approval.* carry the record's public Ref: RefPayload(ref);
///   - turn.step carries the step's label and the DecisionRef of the turn, with the session as ownerRef: TurnStepPayload(decisionRef, label).
///     The gate fires it for an allowed tool call from inside AI Hub's authorization callback, before the tool runs, not after a commit, so
///     an OnEvent for turn.step makes no AI Hub call and runs no Python (AD-6), and the classes it calls belong in the
///     callback helpers (CALLBACKHELPERS) of the code-rules test;
///   - budget.capped carries the instance-zone date, with ownerRef "instance": BudgetCappedPayload(day).
Class OcuTalon.Bridge.Ext.HostSink
{

Parameter TURNSTEP = "turn.step";

Parameter DECISIONRECORDED = "decision.recorded";

Parameter APPROVALRAISED = "approval.raised";

Parameter APPROVALANSWERED = "approval.answered";

Parameter APPROVALEXPIRED = "approval.expired";

Parameter APPROVALCANCELLED = "approval.cancelled";

Parameter APPROVALRESULT = "approval.result";

Parameter BUDGETCAPPED = "budget.capped";

/// The event types, comma-separated, in the order of the parameters above.
Parameter EVENTS = {..#TURNSTEP_","_..#DECISIONRECORDED_","_..#APPROVALRAISED_","_..#APPROVALANSWERED_","_..#APPROVALEXPIRED_","_..#APPROVALCANCELLED_","_..#APPROVALRESULT_","_..#BUDGETCAPPED};

/// Receives one event. type is one of EVENTS, ownerRef is a session's Ref, the literal instance or the literal eval,
/// and payload is the object that the matching payload builder makes. Returns OK and does nothing by default.
ClassMethod OnEvent(type As %String, ownerRef As %String, payload As %DynamicObject) As %Status
{
	Quit $$$OK
}

/// The payload of decision.* and approval.*: {"ref"}.
ClassMethod RefPayload(ref As %String) As %DynamicObject
{
	Quit {"ref": (ref)}
}

/// The payload of turn.step: {"decisionRef","label"}.
ClassMethod TurnStepPayload(decisionRef As %String, label As %String) As %DynamicObject
{
	Quit {"decisionRef": (decisionRef), "label": (label)}
}

/// The payload of budget.capped: {"day"}, the date in the instance zone as YYYY-MM-DD.
ClassMethod BudgetCappedPayload(day As %String) As %DynamicObject
{
	Quit {"day": (day)}
}

}
