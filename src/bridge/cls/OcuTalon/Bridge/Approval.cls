/// The approval API (AD-11): the only way an approval request changes state. Epic 0 fixes the signatures with stub
/// bodies so that callers compile against them; Lane A implements the methods in Epic 3, and Story 7.3 completes the
/// execution methods. A status method returns an error that says it is not implemented yet, so that no caller can
/// mistake a stub for a change that happened; Answer answers not_found.
Class OcuTalon.Bridge.Approval
{

/// Raises one approval request from the unsaved row, and returns its public Ref in ref. Not implemented yet: Story 3.4.
ClassMethod Raise(request As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String) As %Status
{
	Set ref = ""
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Raise is not implemented yet (Story 3.4)")
}

/// Answers the request. action is approve or reject, channel one of Msg.Enum CHANNEL, irisUser the answering IRIS user
/// and sessionRef the answering session. The result is one of done, already_answered, expired, not_found and
/// not_allowed; winner describes the answer that won when the result is already_answered. Not implemented yet: it
/// answers not_found with an empty winner. Story 3.5.
ClassMethod Answer(ref As %String, action As %String, channel As %String, irisUser As %String, sessionRef As %String, Output winner As %DynamicObject) As %String
{
	Set winner = {}
	Quit "not_found"
}

/// Expires a pending request that is past its expiry. Not implemented yet: Story 3.5.
ClassMethod Expire(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Expire is not implemented yet (Story 3.5)")
}

/// Cancels a pending request. Not implemented yet: Story 3.5.
ClassMethod Cancel(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.Cancel is not implemented yet (Story 3.5)")
}

/// Moves an approved, unexpired request that is not yet executing to executing, atomically. Not implemented yet:
/// Story 3.6.
ClassMethod StartExecution(ref As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.StartExecution is not implemented yet (Story 3.6)")
}

/// Closes an executing request as done or failed, with the result of the run. Not implemented yet: Story 3.6.
ClassMethod FinishExecution(ref As %String, result As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.Approval.FinishExecution is not implemented yet (Story 3.6)")
}

}
