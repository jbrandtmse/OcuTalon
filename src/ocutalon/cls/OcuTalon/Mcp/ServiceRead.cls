/// The two read-only tools that OcuTalon's own MCP server offers (Story 28.3; AD-1, AD-4, AD-10, AD-17, AD-21): check_status and recent_activity, which tell a developer's MCP client the
/// latest results of the calling IRIS user's background checks and what happened in that user's recent incidents. They are the chat tools' own answers for a different owner:
/// recent_activity extends OcuTalon.Tools.RecentActivity and answers its Activity, check_status answers WatchAnswers CheckResults and Checked, and each tool's classification is the
/// chat tool's declaration (the parameters below are the chat parameters' own values, so the two cannot drift).
///   - The owner is the session of the calling IRIS user (Caller, $Username), found by OcuTalon.Mcp.Service OwnerOf, which never creates a session; no argument names a session or a user.
///     Every row is read through the ownership API, so a call reads only its caller's records. A call begins no bridge context, so nothing is submitted and CommandCall Session
///     would answer NOSESSION.
///   - Every call writes exactly one audit entry through OcuTalon.Mcp.Service Served (outcome ok, demo, nosession or notread; a read that throws is outcome notread). When that fails the call answers NOTAUDITED and no data.
///   - On the online demo each tool answers DEMOOFF and reads nothing. A caller with no session answers NOSESSION, and rows that cannot be read answer the tool's own not-read text.
///   - The answers are built in code from the caller's own rows, so they are trusted output; a tool never logs a warning, because the role that serves a call cannot write the event log.
/// The only public methods are the two tools. The description of a tool is its method's doc comment: text for the developer's model, never shown to a user as written.
Class OcuTalon.Mcp.ServiceRead Extends OcuTalon.Tools.RecentActivity [ DependsOn = OcuTalon.Tools.WatchTools ]
{

Parameter CLASSIFICATIONCHECKSTATUS = {##class(OcuTalon.Tools.WatchTools).#CLASSIFICATIONCHECKSTATUS};

Parameter READONLYCHECKSTATUS = {##class(OcuTalon.Tools.WatchTools).#READONLYCHECKSTATUS};

Parameter TRUSTEDOUTPUTCHECKSTATUS = {##class(OcuTalon.Tools.WatchTools).#TRUSTEDOUTPUTCHECKSTATUS};

Parameter STEPLABELCHECKSTATUS = {##class(OcuTalon.Tools.WatchTools).#STEPLABELCHECKSTATUS};

/// The answer on the online demo.
Parameter DEMOOFF = "OcuTalon's MCP server is off on the online demo.";

/// The answer for an IRIS user with no OcuTalon session.
Parameter NOSESSION = "OcuTalon has no records for this IRIS user yet. Sign in to OcuTalon once, then ask again.";

/// The answer of check_status when the checks cannot be read.
Parameter CHECKSNOTREAD = "Your background checks could not be read, so nothing is known about them.";

/// The answer when the call could not be audited.
Parameter NOTAUDITED = "This call could not be written to the audit log, so nothing was read.";

/// The message of recent_activity for an empty list.
Parameter NONE = "No incident is recorded for your OcuTalon session in the last 24 hours. This says nothing about what is happening now.";

/// The message of recent_activity when the incidents cannot be read.
Parameter NOTREAD = "Your incidents could not be read, so nothing is known about what happened earlier.";

/// Reads the latest results of your OcuTalon background checks, one per watched production and one for the queue-backlog check when you watch queue backlogs. The answer is ok with checks, in a fixed order. Each check has result: passed, failed, not_checked when the last run could not check, or empty when it has not run yet; entry: the name of what is checked, such as Orders production; finding: what the last run found, or why it could not check; and checked: when it last ran, in the instance's time. An empty list means that nothing is watched. When ok is false, the message says why.
ClassMethod CheckStatus() As %DynamicObject
{
	Set owner = ..Owner(..#CHECKSNOTREAD, .answer, .outcome)
	If owner '= "" {
		Try {
			Set refusal = ..Results(owner, .results)
			If $IsObject(refusal) {
				Set answer = {"ok": false, "message": (..#CHECKSNOTREAD)}
				Set outcome = "notread"
			} Else {
				Set answer = ##class(OcuTalon.Tools.WatchAnswers).Checked(results)
				Set outcome = "ok"
			}
		} Catch {
			Set answer = {"ok": false, "message": (..#CHECKSNOTREAD)}
			Set outcome = "notread"
		}
	}
	Quit ..Finish("check_status", outcome, owner, answer)
}

/// Tells what happened earlier in your OcuTalon session: your recent incidents (the last 24 hours, at most 5, newest first), each with its approvals and the result of its fix. The answer is ok with hours (the window) and incidents. An incident has production: the name to say; item: the production item that failed; count: how many failures; firstFailure and lastFailure: when, in the instance's time; element: the field at fault, empty when it is not known; causeCategory: the kind of cause, such as data_format_change; fixKind: the kind of fix that was proposed, empty when none was; state: open, awaiting_approval, fixing, resolved or closed; and approvals. An approval has answer: waiting, approved, rejected, expired or cancelled; channel: where it was answered, empty when nobody answered it; answered: when it was answered, or when it expired, and empty while it waits; and fix, which is null when no fix ran, otherwise resent (the failed messages sent again), wentThrough (how many of them went through), failedAgain and finished (false while the fix is still running). When incidents is empty, the answer has a message: say plainly that nothing is recorded for the last 24 hours, and never say that everything is fine or that nothing is wrong, because an empty list says nothing about now. When ok is false, the answer has only a message: say that the records could not be read, and say nothing about what happened.
ClassMethod RecentActivity() As %DynamicObject
{
	Set owner = ..Owner(..#NOTREAD, .answer, .outcome)
	If owner '= "" {
		Try {
			Set answer = ..Activity(owner, ..#NONE, ..#NOTREAD)
			Set outcome = $Select(answer.ok: "ok", 1: "notread")
		} Catch {
			Set answer = {"ok": false, "message": (..#NOTREAD)}
			Set outcome = "notread"
		}
	}
	Quit ..Finish("recent_activity", outcome, owner, answer)
}

/// The results of the owner's background checks in results and, when they cannot be read, the refusal (WatchAnswers CheckResults). A test subclass overrides it.
ClassMethod Results(owner As %String, Output results As %DynamicArray) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Tools.WatchAnswers).CheckResults(owner, .results)
}

/// The caller's IRIS user name: the owner of every served call. A test subclass overrides it.
ClassMethod Caller() As %String [ Private ]
{
	Quit $Username
}

/// The session Ref of the user (Service OwnerOf), with the status of the lookup in sc. A test subclass overrides it.
ClassMethod Lookup(irisUser As %String, Output sc As %Status) As %String [ Private ]
{
	Quit ##class(OcuTalon.Mcp.Service).OwnerOf(irisUser, .sc)
}

/// The session Ref of the caller, or "" with the answer and the audit outcome of a call that reads nothing: DEMOOFF (outcome demo) on the online demo, NOSESSION (nosession) for a
/// caller with no session and notRead (notread) when the lookup fails.
ClassMethod Owner(notRead As %String, Output answer As %DynamicObject, Output outcome As %String) As %String [ Private ]
{
	If ##class(OcuTalon.Mcp.Service).OnlineDemo() {
		Set answer = {"ok": false, "message": (..#DEMOOFF)}
		Set outcome = "demo"
		Quit ""
	}
	Set owner = ..Lookup(..Caller(), .sc)
	If $$$ISERR(sc) {
		Set answer = {"ok": false, "message": (notRead)}
		Set outcome = "notread"
	} ElseIf owner = "" {
		Set answer = {"ok": false, "message": (..#NOSESSION)}
		Set outcome = "nosession"
	}
	Quit owner
}

/// Writes the audit entry of the call and returns the answer, or the NOTAUDITED answer when the entry cannot be written.
ClassMethod Finish(tool As %String, outcome As %String, owner As %String, answer As %DynamicObject) As %DynamicObject [ Private ]
{
	Set sc = ##class(OcuTalon.Mcp.Service).Served(tool, outcome, owner, ..Caller())
	If $$$ISERR(sc) Quit ..Return({"ok": false, "message": (..#NOTAUDITED)})
	Quit ..Return(answer)
}

}
