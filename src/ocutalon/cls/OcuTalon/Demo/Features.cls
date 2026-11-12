/// The feature catalog of the demo guide's "Other things to try" panel (Story 4.11; AD-12, AD-29). It is read-only: it lists the ids of
/// the features this instance has, from what the server already knows, and it runs no SQL and writes nothing (no row, no global, no lock, no
/// setting). Demo.Guide.View puts the list into GuideState.Features, so it rides /v1/state and the guide.state event.
/// The ids, in this order, each listed only when its condition holds:
///   - incidentSummary (Story 23.6): always, first, because it closes the guide's incident and shows its summary, a control of this demo shipped in the same package;
///   - persona: the class of the Set persona command is compiled (Epic 40);
///   - suspiciousEmail, rejectFix, reroute (Story 23.2), partnerWarning (Story 23.5), queueWatch (Story 23.7), demoView: always, because they are this demo's own controls, shipped in the same package as this class;
///   - memory: the memory operation is compiled and is not a stub (its STUB parameter, AD-29, is not 1);
///   - memoryCard (Story 41.13): the same condition as memory, listed right after it;
///   - documents: the documents operation is compiled and is not a stub; the Documents page does not count;
///   - heartbeat: the class of the Run now command is compiled (Epic 39);
///   - sources: when memory or documents is listed, because a cited answer or a From memory chip needs one of them.
///   - usage: always, because the Usage page ships in the same package as this class;
///   - history (Story 25.2): always, last, because the History page ships in the same package as this class.
Class OcuTalon.Demo.Features Extends %RegisteredObject
{

/// The class whose presence means the persona feature.
Parameter PERSONA = "OcuTalon.Msg.Command.SetPersona";

/// The class that carries the memory feature, a stub until it is built.
Parameter MEMORY = "OcuTalon.Memory.Ops";

/// The class that carries the documents feature, a stub until it is built.
Parameter DOCUMENTS = "OcuTalon.Docs.Ops";

/// The class whose presence means the heartbeat feature.
Parameter HEARTBEAT = "OcuTalon.Msg.Command.RunHeartbeat";

/// The ids of the features this instance has: Ids of the instance's probes.
ClassMethod Present() As %List
{
	Set has = {}
	Set has.persona = ..Compiled(..#PERSONA)
	Set has.memory = ..Built(..#MEMORY)
	Set has.documents = ..Built(..#DOCUMENTS)
	Set has.heartbeat = ..Compiled(..#HEARTBEAT)
	Quit ..Ids(has)
}

/// The pure mapping from probe flags to the list of ids. has is an object with the flags persona, memory, documents and heartbeat; a flag
/// that is absent or false leaves its id out.
ClassMethod Ids(has As %DynamicObject) As %List
{
	Set ids = $ListBuild("incidentSummary")
	If has.%Get("persona") Set ids = ids _ $ListBuild("persona")
	Set ids = ids _ $ListBuild("suspiciousEmail", "rejectFix", "reroute", "partnerWarning", "queueWatch", "demoView")
	If has.%Get("memory") Set ids = ids _ $ListBuild("memory")
	If has.%Get("memory") Set ids = ids _ $ListBuild("memoryCard")
	If has.%Get("documents") Set ids = ids _ $ListBuild("documents")
	If has.%Get("heartbeat") Set ids = ids _ $ListBuild("heartbeat")
	If has.%Get("memory") || has.%Get("documents") Set ids = ids _ $ListBuild("sources")
	Set ids = ids _ $ListBuild("usage", "history")
	Quit ids
}

/// 1 when the class is compiled.
ClassMethod Compiled(class As %String) As %Boolean [ Private ]
{
	Quit ''##class(%Dictionary.CompiledClass).%ExistsId(class)
}

/// 1 when the class is compiled and is not marked STUB = 1.
ClassMethod Built(class As %String) As %Boolean [ Private ]
{
	If '..Compiled(class) Quit 0
	Quit '+$Parameter(class, "STUB")
}

}
