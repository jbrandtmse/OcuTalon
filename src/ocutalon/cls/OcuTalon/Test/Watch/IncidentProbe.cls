/// An IncidentManager that a test can call Tell and the diagnose handlers on (test only; Story 5.3, ledger entry DW-241, Story 5.4, Story 5.8 and Story 5.5). Tell is private to IncidentManager, and its error
/// branches (a failed Session.Recipients read, a failed publish while other recipients still get the event, a failed send of a notice) have no seam in the product, so
/// Test.Watch.Tell makes a shadow instance of this class in its own process and calls Say, which is Tell and nothing else; Refuse is OnError with the
/// diagnose key and nothing else, and Answer is OnResponse with the diagnose key and nothing else. It overrides SendNotice only: a shadow instance
/// cannot SendRequestAsync (its primary request header is not there), so the override records each Notification in Sent, as a dynamic object of the
/// fields the tests check, and answers OK, or an error for a SessionRef that FailFor names. It overrides SendExecute for the same reason (Story 5.5): it records each
/// order in Executed, as {approvalRef, sessionId} (the session that the order would go in), and answers OK, or an error when FailExecute is set, and DemoMode, so that a test sets the
/// mode without writing the setting: it gives DemoModeIs when that is set (0 or 1), else the product's own reading; QuietNow gives QuietNowIs when that is set, else the clock, so that a test fixes the time that closeQuiet's quiet check reads. Move sets the state on the object and gives an error when FailMove is set (QA). The handlers of Story 5.5 are reached through
/// OnRequest, as the framework calls them. It is not an item of any production.
Class OcuTalon.Test.Watch.IncidentProbe Extends OcuTalon.Watch.IncidentManager
{

/// The Notifications that SendNotice recorded, in order, each {sessionRef, kind, catalogKey, slots, approvalRef, incidentRef, decisionRef}.
Property Sent As %DynamicArray [ Transient ];

/// The SessionRefs, comma-separated, whose send answers an error.
Property FailFor As %String(MAXLEN = "") [ Transient ];

/// The orders that SendExecute recorded, in order, each {approvalRef, sessionId}.
Property Executed As %DynamicArray [ Transient ];

/// 1 to make SendExecute answer an error.
Property FailExecute As %Boolean [ InitialExpression = 0, Transient ];

/// 0 or 1 to fix the demo mode that DemoMode gives; empty for the product's own reading.
Property DemoModeIs As %String [ Transient ];

/// A UTC stamp to fix the time that QuietNow gives; empty for the clock's now.
Property QuietNowIs As %String [ Transient ];

/// 1 to make Move answer an error instead of saving (the failed save of QA, Story 5.5: a real %Save failure needs a row that another process locks).
Property FailMove As %Boolean [ InitialExpression = 0, Transient ];

/// With FailMove set, a save that failed after the move was made on the object, as a failed %Save leaves it: the state and the open variant are set on the
/// object, nothing is saved and nothing is published, and the result is the error. Else the product's Move.
Method Move(incident As OcuTalon.Data.Incident, to As %String, variant As %String, notification As OcuTalon.Msg.Notification = "") As %Status [ Private ]
{
	If ..FailMove {
		Set incident.State = to
		Set incident.OpenVariant = variant
		Quit $SYSTEM.Status.Error(5001, "The save of "_incident.Ref_" is refused")
	}
	Quit ##super(incident, to, variant, notification)
}

/// Records the order instead of sending it, with the session that the order would go in.
Method SendExecute(order As OcuTalon.Fix.Msg.Execute) As %Status [ Private ]
{
	If '$IsObject(..Executed) Set ..Executed = []
	Do ..Executed.%Push({"approvalRef": (order.ApprovalRef), "sessionId": (..%SessionId)})
	If ..FailExecute Quit $SYSTEM.Status.Error(5001, "The execute order of "_order.ApprovalRef_" is refused")
	Quit $$$OK
}

/// The fixed demo mode when DemoModeIs is set.
Method DemoMode() As %Boolean [ Private ]
{
	If ..DemoModeIs '= "" Quit ''..DemoModeIs
	Quit ##super()
}

/// The fixed time when QuietNowIs is set.
Method QuietNow() As %String [ Private ]
{
	If ..QuietNowIs '= "" Quit ..QuietNowIs
	Quit ##super()
}

/// Records the Notification instead of sending it.
Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	If '$IsObject(..Sent) Set ..Sent = []
	Do ..Sent.%Push({"sessionRef": (notification.SessionRef), "kind": (notification.Kind), "catalogKey": (notification.CatalogKey), "slots": (notification.Slots), "approvalRef": (notification.ApprovalRef), "incidentRef": (notification.IncidentRef), "decisionRef": (notification.DecisionRef)})
	If $ListFind($ListFromString(..FailFor), notification.SessionRef) Quit $SYSTEM.Status.Error(5001, "The send to "_notification.SessionRef_" is refused")
	Quit $$$OK
}

/// Tell of the incident: payload as an event of the type on each recipient's stream, with the warnings that Tell logs.
Method Say(incident As OcuTalon.Data.Incident, type As %String, payload As %RegisteredObject)
{
	Do ..Tell(incident, type, payload)
}

/// The error handler of the diagnose request, as the framework calls it when Decide refuses the request: the incident of the Ref is stored as refused.
Method Refuse(ref As %String, error As %Status) As %Status
{
	Set request = ##class(OcuTalon.Watch.Msg.Settle).%New()
	Set request.IncidentRef = ref
	Quit ..OnError(request, , "", error, ..#DIAGNOSEKEY)
}

/// The answer handler of the diagnose request, as the framework calls it when Decide answers: response is the DecisionResponse, or "" for the empty
/// answer that follows an error.
Method Answer(ref As %String, response As %RegisteredObject) As %Status
{
	Set request = ##class(OcuTalon.Watch.Msg.Settle).%New()
	Set request.IncidentRef = ref
	Quit ..OnResponse(request, , "", response, ..#DIAGNOSEKEY)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
