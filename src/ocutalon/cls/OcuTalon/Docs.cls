/// The documents area's entry points that other areas call (AD-21; Lane A). THIS CLASS HOLDS ONLY THE SIGN-OUT STUB until Story 19.5.
Class OcuTalon.Docs Extends %RegisteredObject
{

/// Called by OcuTalon.Core.SessionOps.End on an online-demo sign-out: drops the session's knowledge base (the table OcuTalonKB.S followed by
/// the session's row id, its _Config table) and its Document rows. THIS IS A STUB until Story 19.5: no document exists before Epic 19, so it
/// returns OK and changes nothing, and a sign-out that calls it keeps signing out.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	Quit $$$OK
}

}
