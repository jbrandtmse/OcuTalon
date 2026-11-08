Include Ensemble

/// The documents area's entry points that other areas call (AD-4, AD-21; Lane A).
Class OcuTalon.Docs Extends %RegisteredObject
{

/// Called by OcuTalon.Core.SessionOps.End on an online-demo sign-out, in the job of SessionOps: removes everything the session's documents left (Story 19.5).
/// Under the owner's exclusive lock (OcuTalon.Docs.Store LockOwner, 5 seconds), it deletes every OcuTalon.Data.Document row whose OwnerRef is the SessionRef
/// exactly and then drops the session's knowledge-base tables (the table OcuTalonKB.S followed by the session's row id, and its _Config table; DROP TABLE
/// leaves no class and no global), so another session's documents are not touched. A drop that waits for the lock while DocumentOps indexes the session's
/// document gets it within a passage (the writer stops while the owner is marked as being dropped, Store Drain); the next batch finds no row and stops, and no
/// table is made again. A lock that is not free in 5 seconds is an
/// error status, and the sign-out stays resumable. It is idempotent: a session with nothing to drop, an empty or unknown reference, and a second call are OK and
/// change nothing. It publishes no event (the session is ending), names no AI Hub class, and does not read the onlineDemo setting.
ClassMethod DropSession(sessionRef As %String) As %Status
{
	Set store = "OcuTalon.Docs.Store"
	If (sessionRef = "") || (sessionRef = $Parameter(store, "OWNER")) || (sessionRef = $Parameter(store, "EVALOWNER")) Quit $$$OK
	Set sc = $$$OK
	Set locked = 0
	Try {
		Do $ClassMethod(store, "Drain", sessionRef, 1)
		Set sc = $ClassMethod(store, "LockOwner", sessionRef, 1)
		If $$$ISERR(sc) Quit
		Set locked = 1
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Document WHERE OwnerRef = ?", sessionRef)
		If rs.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$GeneralError, "The documents of the session cannot be read: " _ rs.%Message))
		While rs.%Next() {
			Set deleted = ##class(OcuTalon.Data.Document).%DeleteId(rs.%Get("ID"))
			If $$$ISERR(deleted) $$$ThrowStatus(deleted)
		}
		Set table = $ClassMethod(store, "TableFor", sessionRef, .suffix)
		If table '= "" Set sc = $ClassMethod(store, "Drop", table)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If locked Do $ClassMethod(store, "UnlockOwner", sessionRef, 1)
	Do $ClassMethod(store, "Drain", sessionRef, 0)
	Quit sc
}

}
