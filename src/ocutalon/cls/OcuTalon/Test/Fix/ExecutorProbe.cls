/// A FixExecutor that a test can call Execute on (test only; Stories 7.3 and 7.4). A shadow instance cannot SendRequestAsync (its primary request header is not there), and
/// the kind's Recheck and Execute need a running Orders production, so this class overrides the seams of Fix.Executor and its refusal check: SendResult records each FixResult in Results,
/// as a dynamic object of the fields the tests check, and in Sessions (the SessionId and SuperSession the host had at the send), and answers OK, or an error when FailSend is set; Missing gives MissingIs when it is set (none is no pair missing,
/// throw is a check that throws), else the product's own check of the service user's resources; Check and Carry record each call (Checked and Carried: {class, incident, parameters, targets}) and give the canned answer
/// of CheckIs or CarryIs when one is set, else the kind's own Recheck or Execute. A canned CheckIs is the text error (an error status), throw (an exception) or JSON
/// {"passed": the ids, "skipped": [{"id", "reason"}]}; a canned CarryIs is error, throw or JSON {"copies": [header ids that the run registers on its FixRun, as the
/// kind does], "skipped": [{"id", "reason"}], and an optional "fail", an error text: the copies are registered and the call then fails, as a resend that stops partway}.
/// RefusalIs none makes the refusal check pass for any row, so that a request that is not approved reaches
/// StartExecution. StartIs, an error text, makes StartExecution fail with it (the Start seam); otherwise it is the product's. SaveFails makes the save of a run's FixRun fail: 1 for the first save only (the run's own, in Run), 2 for the second as well (the one of
/// CouldNotStart); SavedWas holds the saved argument that CouldNotStart was given.
/// The wait (Story 7.4) reads no production: Statuses gives the canned StatusIs, a JSON object {copy header id: {"status", "error", "target"}}, with the outcome
/// read (StatusOutcome gives another, and throw makes the read throw), and from the read number ThenAfter + 1 on the canned StatusThen when one is set; Reads counts the calls. Waiting is narrowed to the
/// runs of the incidents in Incidents (comma-separated Refs; none when empty), so that a probe never takes a run of the running production, and the probe has a lock of its
/// own and a short wait (WAITLOCK, WAITSECONDS and WAITPAUSE). WaitNow is the public Wait. WriteAudit records the data of each Action entry in Audits and writes nothing,
/// and answers OK, or an error when AuditFails is set. Everything else is the product's: the handler, the FixRun row, StartExecution
/// and FinishExecution. It is no item of any production.
Class OcuTalon.Test.Fix.ExecutorProbe Extends OcuTalon.Fix.Executor
{

/// The probe's own lock, and a wait that a test can sit out.
Parameter WAITLOCK = "^OcuTalon.Test.Fix.Wait";

Parameter WAITSECONDS = 3;

Parameter WAITPAUSE = 0.1;

/// The error text that Start gives, "" for the product's StartExecution.
Property StartIs As %String(MAXLEN = "") [ Transient ];

/// The canned copies of Statuses (see the class description), the outcome it gives, the canned copies from read ThenAfter + 1 on, and the number of reads.
Property StatusIs As %String(MAXLEN = "") [ Transient ];

Property StatusOutcome As %String [ Transient ];

Property StatusThen As %String(MAXLEN = "") [ Transient ];

Property ThenAfter As %Integer [ Transient ];

Property Reads As %Integer [ InitialExpression = 0, Transient ];

/// The Refs of the incidents whose runs Waiting gives, comma-separated.
Property Incidents As %String(MAXLEN = "") [ Transient ];

/// The data of the Action entries that WriteAudit recorded, in order, and 1 to make it answer an error (after it recorded).
Property Audits As %DynamicArray [ Transient ];

Property AuditFails As %Boolean [ InitialExpression = 0, Transient ];

/// The session of the host at each SendResult, in order, each {approvalRef, session, super}.
Property Sessions As %DynamicArray [ Transient ];

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
	If '$IsObject(..Sessions) Set ..Sessions = []
	Do ..Sessions.%Push({"approvalRef": (result.ApprovalRef), "session": (..%SessionId), "super": (..%SuperSession)})
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "The send of the result of "_result.ApprovalRef_" is refused")
	Quit $$$OK
}

/// StartIs as an error when it is set, else the product's StartExecution.
Method Start(ref As %String) As %Status [ Private ]
{
	If ..StartIs '= "" Quit $SYSTEM.Status.Error(5001, ..StartIs)
	Quit ##super(ref)
}

/// The canned copies (see the class description) with the outcome StatusOutcome (read by default); the product's read when none is set.
Method Statuses(incident As OcuTalon.Data.Incident, run As OcuTalon.Data.FixRun, Output statuses As %DynamicObject) As %String [ Private ]
{
	Set ..Reads = ..Reads + 1
	If ..StatusOutcome = "throw" Throw ##class(%Exception.General).%New("Probe", 5001, , "The read threw")
	If ..StatusIs = "" Quit ##super(incident, run, .statuses)
	Set canned = $Select((..StatusThen '= "") && (..Reads > ..ThenAfter): ..StatusThen, 1: ..StatusIs)
	Set statuses = {}.%FromJSON(canned)
	Quit $Select(..StatusOutcome = "": "read", 1: ..StatusOutcome)
}

/// The product's waiting runs, narrowed to those of the incidents in Incidents (none when it is empty).
Method Waiting() As %List [ Private ]
{
	Set all = ##super()
	Set waiting = ""
	Set position = 0
	While $ListNext(all, position, id) {
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
		If $IsObject(run) && (..Incidents '= "") && $ListFind($ListFromString(..Incidents), run.IncidentRef) Set waiting = waiting _ $ListBuild(id)
	}
	Quit waiting
}

/// Records the data of the entry instead of writing it.
Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	If '$IsObject(..Audits) Set ..Audits = []
	Do ..Audits.%Push({}.%FromJSON(data.%ToJSON()))
	If ..AuditFails Quit $SYSTEM.Status.Error(5001, "The audit entry of "_data.approvalRef_" is refused")
	Quit $$$OK
}

/// The wait for the copies of the runs of Incidents (the product's Wait, which is private).
Method WaitNow()
{
	Do ..Wait()
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
	If canned.%IsDefined("fail") Quit $SYSTEM.Status.Error(5001, canned.fail)
	Quit $$$OK
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
