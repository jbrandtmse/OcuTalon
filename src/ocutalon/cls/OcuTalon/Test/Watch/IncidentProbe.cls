/// An IncidentManager that a test can call Tell and the diagnose handlers on (test only; Story 5.3, ledger entry DW-241, Story 5.4 and Story 5.8). Tell is private to IncidentManager, and its error
/// branches (a failed Session.Recipients read, a failed publish while other recipients still get the event, a failed send of a notice) have no seam in the product, so
/// Test.Watch.Tell makes a shadow instance of this class in its own process and calls Say, which is Tell and nothing else; Refuse is OnError with the
/// diagnose key and nothing else, and Answer is OnResponse with the diagnose key and nothing else. It overrides SendNotice only: a shadow instance
/// cannot SendRequestAsync (its primary request header is not there), so the override records each Notification in Sent, as a dynamic object of the
/// fields the tests check, and answers OK, or an error for a SessionRef that FailFor names. It is not an item of any production.
Class OcuTalon.Test.Watch.IncidentProbe Extends OcuTalon.Watch.IncidentManager
{

/// The Notifications that SendNotice recorded, in order, each {sessionRef, kind, catalogKey, slots, approvalRef, incidentRef, decisionRef}.
Property Sent As %DynamicArray [ Transient ];

/// The SessionRefs, comma-separated, whose send answers an error.
Property FailFor As %String(MAXLEN = "") [ Transient ];

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
