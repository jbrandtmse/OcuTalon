/// FixExecutor, the business operation that carries out an approved fix (AD-16). A stub until Story 7.3 builds Execute: it answers a Fix.Msg.DryRun (Story 7.1)
/// and nothing else.
///   - A Fix.Msg.DryRun is answered with a Fix.Msg.DryRunResult (DryRun): the incident is opened by its Ref, the kind by its name, and the kind's DryRun works out
///     the targets and the dry run's JSON. It changes nothing and calls no model. A dry run that cannot be worked out (an unknown or closed incident, an unknown kind, parameters
///     that are not a JSON object or that the kind refuses, a production that cannot be read) is still answered with OK: Reason holds one plain sentence (redacted),
///     and Targets and DryRun are empty.
///   - Every other request is answered "not implemented" (error 5003) with no response; the handler writes no log row itself (the business operation's host logs
///     the error status, as it does for any error).
Class OcuTalon.Fix.Executor Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	If $IsObject(pRequest) && pRequest.%IsA("OcuTalon.Fix.Msg.DryRun") Quit ..DryRun(pRequest, .pResponse)
	Quit $$$ERROR($$$NotImplemented)
}

/// Answers the request with its DryRunResult. Always OK: a dry run that cannot be worked out is the response's Reason.
Method DryRun(request As OcuTalon.Fix.Msg.DryRun, Output response As OcuTalon.Fix.Msg.DryRunResult) As %Status
{
	Set response = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set response.IncidentRef = request.IncidentRef
	Set reason = ""
	Try {
		Set sc = ..Work(request, .targets, .dryRun)
		If $$$ISERR(sc) {
			Set reason = $SYSTEM.Status.GetOneErrorText(sc)
		} Else {
			Set response.Targets = targets
			Set response.DryRun = dryRun.%ToJSON()
		}
	} Catch exception {
		Set reason = "The dry run could not be worked out because of an internal error."
	}
	If reason '= "" {
		Set response.Targets = ""
		Set response.DryRun = ""
		If $Extract(reason, 1, 7) = "ERROR #" Set reason = $ZStrip($Piece(reason, ":", 2, *), "<W")
		Set response.Reason = $Extract(##class(OcuTalon.Bridge.Redact).Text(reason), 1, 1000)
	}
	Quit $$$OK
}

/// The targets and the dry run of the request, or an error status that says why not.
Method Work(request As OcuTalon.Fix.Msg.DryRun, Output targets As %String, Output dryRun As %DynamicObject) As %Status [ Private ]
{
	Set targets = ""
	Set dryRun = ""
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If '$IsObject(incident) Quit $$$ERROR($$$GeneralError, "There is no incident "_request.IncidentRef)
	If incident.State = ##class(OcuTalon.Watch.Transitions).#CLOSED Quit $$$ERROR($$$GeneralError, "The incident "_request.IncidentRef_" is closed")
	Set class = ##class(OcuTalon.Fix.Kind).ForName(request.FixKind)
	If class = "" Quit $$$ERROR($$$GeneralError, "The fix kind '"_request.FixKind_"' is not one of "_$ListToString(##class(OcuTalon.Fix.Kind).Names(), ","))
	Set parameters = ""
	Try {
		Set parameters = {}.%FromJSON(request.Parameters)
	} Catch {
		Set parameters = ""
	}
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") Quit $$$ERROR($$$GeneralError, "The parameters are not one JSON object")
	Quit $ClassMethod(class, "DryRun", incident, parameters, .targets, .dryRun)
}

}
