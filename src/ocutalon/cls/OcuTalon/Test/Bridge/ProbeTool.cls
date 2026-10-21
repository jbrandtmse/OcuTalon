/// The tool of the context probe (Story 1.2; AD-6): a test fixture, never part of a production. Probe reads the per-call context
/// of this process, puts what it saw in the context's HostData as JSON, taints the turn, and returns {"seen":1}. It makes no AI
/// Hub call and no Python call: a tool method runs inside AI Hub's callback (AD-6).
Class OcuTalon.Test.Bridge.ProbeTool Extends %AI.Tool
{

/// Records what the context holds: every field of it, as JSON, in HostData. Tainted becomes 1.
ClassMethod Probe() As %DynamicObject
{
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	Set seen = {}
	If $IsObject(context) {
		Set fields = $ListFromString(##class(OcuTalon.Bridge.Context).#FIELDS)
		Set position = 0
		While $ListNext(fields, position, name) {
			Do seen.%Set(name, $Property(context, name))
		}
	} Else {
		Do seen.%Set("context", "none")
	}
	Do ##class(OcuTalon.Bridge.Context).Put("HostData", seen.%ToJSON())
	Do ##class(OcuTalon.Bridge.Context).Put("Tainted", 1)
	Quit {"seen": 1}
}

}
