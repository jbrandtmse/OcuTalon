/// The memory area's entry points that other areas call (AD-21; Lane A). THIS CLASS HOLDS ONLY THE SIGN-OUT STUB until Story 19.5.
Class OcuTalon.Memory Extends %RegisteredObject
{

/// Called by OcuTalon.Core.SessionOps.End on an online-demo sign-out: drops the session's memories. THIS IS A STUB until Story 19.5: no
/// memory exists before Epic 19, so it returns OK and changes nothing, and a sign-out that calls it keeps signing out.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	Quit $$$OK
}

}
