/// The budget API (AD-20). Epic 0 fixes the signature with a stub body; Lane A implements it in Story 1.4.
Class OcuTalon.Bridge.Budget
{

/// The state of the daily spending cap: {"spent","cap","capped","resetsAt"}, where spent and cap are in US dollars,
/// capped is true once spent reaches cap, and resetsAt is the next reset as a UTC time. Not implemented yet: it
/// answers nothing spent, no cap, not capped and no reset time.
ClassMethod State() As %DynamicObject
{
	Quit {"spent": 0, "cap": 0, "capped": false, "resetsAt": ""}
}

}
