/// A FixExecutor that a test can call Execute on (test only; Story 7.3). A shadow instance cannot SendRequestAsync (its primary request header is not there), and
/// the kind's Recheck and Execute need a running Orders production, so this class overrides the four seams of Fix.Executor and its refusal check: SendResult records each FixResult in Results,
/// as a dynamic object of the fields the tests check, and answers OK, or an error when FailSend is set; Missing gives MissingIs when it is set (none is no pair missing,
/// throw is a check that throws), else the product's own check of the service user's resources; Check and Carry record each call (Checked and Carried: {class, incident, parameters, targets}) and give the canned answer
/// of CheckIs or CarryIs when one is set, else the kind's own Recheck or Execute. A canned CheckIs is the text error (an error status), throw (an exception) or JSON
/// {"passed": the ids, "skipped": [{"id", "reason"}]}; a canned CarryIs is error, throw or JSON {"copies": [header ids that the run registers on its FixRun, as the
/// kind does], "skipped": [{"id", "reason"}]}. RefusalIs none makes the refusal check pass for any row, so that a request that is not approved reaches
/// StartExecution. SaveFails makes the save of a run's FixRun fail: 1 for the first save only (the run's own, in Run), 2 for the second as well (the one of
/// CouldNotStart); SavedWas holds the saved argument that CouldNotStart was given. Everything else is the product's: the handler, the FixRun row, StartExecution
/// and FinishExecution. It is no item of any production.
Class OcuTalon.Test.Fix.ExecutorProbe Extends OcuTalon.Fix.Executor
{

/// The FixResults that SendResult recorded, in order, each {approvalRef, incidentRef, final, interrupted, total, resent, completed, failedAgain, skipped, reason}.
Property Results As %DynamicArray [ Transient ];

/// 1 to make SendResult answer an error (after it recorded the result).
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

/// The pair that Missing gives: empty for the product's own check, none for no pair missing, throw for a check that throws.
Property MissingIs As %String [ Transient ];

/// none to let any row past the refusal check; empty for the product's own check.
Property RefusalIs As %String [ Transient ];

/// The canned answers of Check and Carry (see the class description); empty for the kind's own.
Property CheckIs As %String(MAXLEN = "") [ Transient ];

Property CarryIs As %String(MAXLEN = "") [ Transient ];

/// The calls of Check and Carry, in order, each {class, incident (its Ref), parameters (as JSON text), targets}.
Property Checked As %DynamicArray [ Transient ];

Property Carried As %DynamicArray [ Transient ];

/// 1 to make the first FixRun save of a run fail and the save of CouldNotStart work, 2 to make both fail, empty for neither. A save fails because Run gives
/// the request's row (in memory only) an IncidentRef that is longer than a FixRun holds; CouldNotStart (for 1) or Close (for 2) puts the real IncidentRef back
/// after the save it is meant to fail.
Property SaveFails As %Integer [ Transient ];

/// The saved argument of the latest call of CouldNotStart, empty before one.
Property SavedWas As %String [ Transient ];

/// The row whose IncidentRef SaveFails changed, and the IncidentRef it had.
Property Corrupted As OcuTalon.Bridge.Data.ApprovalRequest [ Transient ];

Property TrueIncidentRef As %String [ Transient ];

/// Records the result instead of sending it.
Method SendResult(result As OcuTalon.Fix.Msg.FixResult) As %Status [ Private ]
{
	If '$IsObject(..Results) Set ..Results = []
	Do ..Results.%Push({"approvalRef": (result.ApprovalRef), "incidentRef": (result.IncidentRef), "final": (+result.Final), "interrupted": (+result.Interrupted), "total": (+result.Total), "resent": (+result.Resent), "completed": (+result.Completed), "failedAgain": (+result.FailedAgain), "skipped": (+result.Skipped), "reason": (result.Reason)})
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "The send of the result of "_result.ApprovalRef_" is refused")
	Quit $$$OK
}

/// "" for any row when RefusalIs is none, else the product's check.
Method Refusal(row As OcuTalon.Bridge.Data.ApprovalRequest) As %String [ Private ]
{
	If ..RefusalIs = "none" Quit ""
	Quit ##super(row)
}

/// The product's run; with SaveFails, the row (in memory) first gets an IncidentRef that no FixRun can hold. It is set after StartExecution, which reloads the row.
Method Run(row As OcuTalon.Bridge.Data.ApprovalRequest, incident As OcuTalon.Data.Incident, class As %String, parameters As %DynamicObject, total As %Integer) [ Private ]
{
	If ..SaveFails {
		Set ..Corrupted = row
		Set ..TrueIncidentRef = row.IncidentRef
		Set row.IncidentRef = row.IncidentRef_"-too-long-for-a-run"
	}
	Do ##super(row, incident, class, parameters, total)
}

/// Records the saved argument; with SaveFails 1 the real IncidentRef is back before the run is saved again.
Method CouldNotStart(row As OcuTalon.Bridge.Data.ApprovalRequest, total As %Integer, reason As %String, saved As %Boolean) [ Private ]
{
	Set ..SavedWas = saved
	If ..SaveFails = 1 Do ..PutBackRef()
	Do ##super(row, total, reason, saved)
}

/// The real IncidentRef is back before the request is closed and its result is sent.
Method Close(ref As %String, result As %String) [ Private ]
{
	Do ..PutBackRef()
	Do ##super(ref, result)
}

/// Gives the row that SaveFails changed its IncidentRef again.
Method PutBackRef() [ Private ]
{
	If '$IsObject(..Corrupted) Quit
	Set ..Corrupted.IncidentRef = ..TrueIncidentRef
	Set ..Corrupted = ""
}

/// MissingIs when it is set, else the product's check.
Method Missing(class As %String) As %String [ Private ]
{
	If ..MissingIs = "" Quit ##super(class)
	If ..MissingIs = "throw" Throw ##class(%Exception.General).%New("Probe", 5001, , "The check threw")
	Quit $Select(..MissingIs = "none": "", 1: ..MissingIs)
}

/// Records the call; the canned answer of CheckIs when it is set, else the kind's Recheck.
Method Check(class As %String, incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status [ Private ]
{
	If '$IsObject(..Checked) Set ..Checked = []
	Do ..Checked.%Push({"class": (class), "incident": (incident.Ref), "parameters": (parameters.%ToJSON()), "targets": (targets)})
	If ..CheckIs = "" Quit ##super(class, incident, parameters, targets, .passed, .skipped)
	Set passed = ""
	Set skipped = []
	If ..CheckIs = "error" Quit $SYSTEM.Status.Error(5001, "The failed messages could not be read")
	If ..CheckIs = "throw" Throw ##class(%Exception.General).%New("Probe", 5001, , "The read threw")
	Set canned = {}.%FromJSON(..CheckIs)
	Set passed = canned.passed
	Set skipped = canned.skipped
	Quit $$$OK
}

/// Records the call; the canned answer of CarryIs when it is set (its copies are registered on the run), else the kind's Execute.
Method Carry(class As %String, incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun) As %Status [ Private ]
{
	If '$IsObject(..Carried) Set ..Carried = []
	Do ..Carried.%Push({"class": (class), "incident": (incident.Ref), "parameters": (parameters.%ToJSON()), "targets": (targets)})
	If ..CarryIs = "" Quit ##super(class, incident, parameters, targets, .result, run)
	Set result = {"resent": 0, "skipped": []}
	If ..CarryIs = "error" Quit $SYSTEM.Status.Error(5001, "The copies could not be made")
	If ..CarryIs = "throw" Throw ##class(%Exception.General).%New("Probe", 5001, , "The resend threw")
	Set canned = {}.%FromJSON(..CarryIs)
	Set iterator = canned.copies.%GetIterator()
	While iterator.%GetNext(, .id) {
		Do run.Copies.Insert(id)
		Set result.resent = result.resent + 1
	}
	$$$ThrowOnError(run.%Save())
	Set result.skipped = canned.skipped
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
