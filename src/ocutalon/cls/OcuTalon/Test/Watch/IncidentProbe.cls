/// An IncidentManager that a test can call Tell on (test only; Story 5.3, ledger entry DW-241). Tell is private to IncidentManager, and its two error
/// branches (a failed Session.Recipients read, a failed publish while other recipients still get the event) have no seam in the product, so
/// Test.Watch.Tell makes a shadow instance of this class in its own process and calls Say, which is Tell and nothing else. It overrides nothing and is not
/// an item of any production.
Class OcuTalon.Test.Watch.IncidentProbe Extends OcuTalon.Watch.IncidentManager
{

/// Tell of the incident: payload as an event of the type on each recipient's stream, with the warnings that Tell logs.
Method Say(incident As OcuTalon.Data.Incident, type As %String, payload As %RegisteredObject)
{
	Do ..Tell(incident, type, payload)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
