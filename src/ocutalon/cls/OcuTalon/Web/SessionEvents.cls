/// The session events of the application /ocutalon (AD-4). OnLogin runs at the sign-in request, as the signed-in
/// user with the application's roles, and attaches the user's durable OcuTalon session to the CSP session
/// (Ownership.Attach), so that the first API call finds it. A user without the OcuTalon user role gets no session
/// row. OnLogin always answers OK: an error status would neither log the user out nor show the sign-in page, and
/// a session that was not attached here is attached by the first API call (Ownership.SessionRef). A failure is
/// written to the console log, without the user name.
Class OcuTalon.Web.SessionEvents Extends %CSP.SessionEvents [ ProcedureBlock ]
{

/// Attaches the signed-in user's durable session when the user holds the OcuTalon user role.
ClassMethod OnLogin() As %Status
{
	Quit ..AttachFor(##class(OcuTalon.Web.Public.Shell).HasRole())
}

/// OnLogin's work for a user who holds the role (hasRole 1) or does not (0): the role attaches the durable session,
/// no role does nothing. The answer is OK in every case, and a failure is logged.
ClassMethod AttachFor(hasRole As %Boolean) As %Status
{
	Try {
		If hasRole {
			Set sc = ##class(OcuTalon.Data.Ownership).Attach()
			If $SYSTEM.Status.IsError(sc) Do ..Log("the session could not be attached, error "_$SYSTEM.Status.GetErrorCodes(sc))
		}
	} Catch exception {
		Do ..Log("the session could not be attached, error "_$SYSTEM.Status.GetErrorCodes(exception.AsStatus()))
	}
	Quit $SYSTEM.Status.OK()
}

/// Writes one line to the console log; a failure of the log itself is ignored.
ClassMethod Log(text As %String) [ Private ]
{
	Try {
		Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Web.SessionEvents: "_text, 0, 1)
	} Catch {
	}
}

}
