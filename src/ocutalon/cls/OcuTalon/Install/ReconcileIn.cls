Include Ensemble

/// ReconcileIn, the item that reconciles every production start that the Production installer step did not make (AD-5, AD-23). Every
/// production start is reconciled exactly once:
///   - a start made by OcuTalon.Install.Step.Production holds its start lock (Step.Production STARTLOCK) while it waits for the items, so
///     OnInit finds the lock taken and the item does nothing: the installer's Reconcile step, which follows that step, reconciles it;
///   - any other start (instance autostart, the portal, Ens.Director from a session) finds the lock free, so once every enabled item runs
///     (Step.Production NotRunning is empty) the item calls the installer's Reconcile step (OcuTalon.Install.Step.Reconcile Run) once, under
///     the start lock, logs one Info row (LOGTEXT) and does nothing more until the item starts again.
/// The item polls every CallInterval seconds (5 in the production). If the items still do not run after WAITWARNSECONDS it logs one warning
/// that names them and keeps waiting. A reconcile that fails is one Error row and is not repeated until the item starts again, and each
/// warning of a reconcile is one Warning row. The
/// reconcile runs in the job of this item, so the job's session id and current header id are put back afterwards, as Bridge.Approval
/// StartHold does, defined or killed. OnProcessInput always returns OK.
Class OcuTalon.Install.ReconcileIn Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

/// The Info row of a finished reconcile.
Parameter LOGTEXT = "ReconcileIn reconciled the areas of OcuTalon after a production start that the Production step did not make";

/// The seconds of waiting for the items after which one warning is logged.
Parameter WAITWARNSECONDS = 60;

/// The seconds to wait for the start lock before leaving the reconcile to the next poll.
Parameter LOCKSECONDS = 30;

/// 1 when OnInit found the start of the Production step under way: this item then never reconciles.
Property ByStep As %Boolean [ InitialExpression = 0 ];

/// 1 once the reconcile ran.
Property Done As %Boolean [ InitialExpression = 0 ];

/// 1 once the warning about items that do not run was logged.
Property Warned As %Boolean [ InitialExpression = 0 ];

/// $ZHorolog at OnInit.
Property Started As %Numeric;

Method OnInit() As %Status
{
	Set ..ByStep = ##class(OcuTalon.Install.Step.Production).Starting()
	Set ..Started = $ZHorolog
	Quit $$$OK
}

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Set missing = ""
		If '..ByStep && '..Done Set missing = ##class(OcuTalon.Install.Step.Production).NotRunning()
		Set action = ..Next(..ByStep, ..Done, missing, $ZHorolog - ..Started, ..Warned)
		If action = "warn" {
			Set ..Warned = 1
			$$$LOGWARNING("ReconcileIn is waiting for these items to run: "_missing)
		} ElseIf action = "run" {
			Do ..Reconcile()
		}
	} Catch exception {
		$$$LOGERROR("ReconcileIn failed: "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// What one poll does: "skip" when the Production step made the start (byStep) or the reconcile ran (done), "wait" while items are missing
/// (the comma list of Step.Production NotRunning) and fewer than WAITWARNSECONDS seconds have passed, "warn" once the wait reaches them and
/// no warning was logged yet, "wait" again after it, and "run" when no item is missing.
ClassMethod Next(byStep As %Boolean, done As %Boolean, missing As %String, waited As %Numeric, warned As %Boolean) As %String
{
	If byStep || done Quit "skip"
	If missing = "" Quit "run"
	If (waited >= ..#WAITWARNSECONDS) && 'warned Quit "warn"
	Quit "wait"
}

/// The reconcile of one poll, under the start lock. Without the lock within LOCKSECONDS it does nothing and the next poll tries again.
Method Reconcile() [ Private ]
{
	Set lock = ##class(OcuTalon.Install.Step.Production).#STARTLOCK
	Lock +@lock:..#LOCKSECONDS
	If '$Test Quit
	Set hadSession = $Data($$$JobSessionId) # 2
	Set session = $Get($$$JobSessionId)
	Set hadHeader = $Data($$$JobCurrentHeaderId) # 2
	Set header = $Get($$$JobCurrentHeaderId)
	Set thrown = ""
	Set sc = $$$OK
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Try {
		Set sc = ##class(OcuTalon.Install.Step.Reconcile).Run()
	} Catch exception {
		Set thrown = exception
	}
	Set warnings = ##class(OcuTalon.Install.Step).TakeWarnings()
	If hadSession {
		Set $$$JobSessionId = session
	} Else {
		Kill $$$JobSessionId
	}
	If hadHeader {
		Set $$$JobCurrentHeaderId = header
	} Else {
		Kill $$$JobCurrentHeaderId
	}
	Lock -@lock
	Set ..Done = 1
	Set position = 0
	While $ListNext(warnings, position, line) {
		$$$LOGWARNING("ReconcileIn: "_line)
	}
	If $IsObject(thrown) Set sc = thrown.AsStatus()
	If $$$ISERR(sc) {
		$$$LOGERROR("ReconcileIn: the reconcile failed: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	$$$LOGINFO(..#LOGTEXT)
}

}
