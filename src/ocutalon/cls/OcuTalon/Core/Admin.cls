/// The admin terminal entry point (AD-1, AD-19): an OcuTalon admin switches demo mode from a terminal in the OCUTALON
/// namespace with do ##class(OcuTalon.Core.Admin).SetDemoMode(0|1). Each method checks the caller's roles before it submits
/// anything, sets the command's ActingUser from the process's $USERNAME, submits it through Commands.Submit with the origin
/// system, prints the plain-English line of the answer and returns the CommandResult.
Class OcuTalon.Core.Admin
{

/// The role that may change settings.
Parameter ROLE = "OcuTalonAdmin";

Parameter MESSAGEINVALID = "SetDemoMode takes 1 (on) or 0 (off). Nothing was changed.";

Parameter MESSAGENOTRUNNING = "OcuTalon isn't taking commands now: its production isn't running or CommandsIn is disabled. Nothing was changed.";

Parameter MESSAGESUBMITFAILED = "OcuTalon couldn't submit the change: {error}. Nothing was changed.";

/// Switches demo mode on (1) or off (0), as a number or a string. Prints the answer's line and returns the CommandResult.
/// Anything else is invalid, and a caller whose roles do not include OcuTalonAdmin is refused with the text of CommandsIn's
/// admin-only refusal; neither submits anything. A production that is not running, and an error thrown by the submit, are
/// answered with the text that says so. The result is never an error status and never thrown.
ClassMethod SetDemoMode(mode As %String = "") As OcuTalon.Msg.CommandResult
{
	Try {
		If '((mode = "0") || (mode = "1")) {
			Set result = ..Result("invalid", ..#MESSAGEINVALID)
		} ElseIf '..Allowed(..Roles()) {
			Set result = ..Result("not_allowed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY)
		} Else {
			Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
			Set command.DemoMode = (mode = "1")
			Set command.ActingUser = $USERNAME
			Set sc = ..Send(command, "system", .result)
			If $$$ISERR(sc) {
				Set result = ..Result("not_running", ..#MESSAGENOTRUNNING)
			} ElseIf '$IsObject($Get(result)) {
				Set result = ..Result("failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
			}
		}
	} Catch exception {
		Set result = ..Result("failed", $Replace(..#MESSAGESUBMITFAILED, "{error}", ..ErrorText(exception.AsStatus())))
	}
	Write result.Message, !
	Quit result
}

/// The roles of the calling process. A test subclass overrides it.
ClassMethod Roles() As %String [ Private ]
{
	Quit $ROLES
}

/// Submits the command with the origin and answers the status of the submit. A test subclass overrides it.
ClassMethod Send(command As OcuTalon.Msg.Command, origin As %String, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
}

/// 1 when the comma-separated roles include OcuTalonAdmin, by whole name. A holder of %All without OcuTalonAdmin gets 0.
ClassMethod Allowed(roles As %String) As %Boolean
{
	Quit ''$ListFind($ListFromString($Get(roles)), ..#ROLE)
}

/// The text of an error status for a plain-English line: without its ERROR #n: prefix and without a closing full stop.
ClassMethod ErrorText(sc As %Status) As %String
{
	Set text = $SYSTEM.Status.GetErrorText(sc)
	If $Extract(text, 1, 7) = "ERROR #" Set text = $Piece(text, ": ", 2, *)
	If $Extract(text, *) = "." Set text = $Extract(text, 1, *-1)
	Quit text
}

/// An unsaved CommandResult that carries nothing out: Ok 0, the outcome code and the message.
ClassMethod Result(outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 0
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

}
