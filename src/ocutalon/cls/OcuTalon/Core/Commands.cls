/// The one way to submit a command (AD-1): the web layer, the chat agent's tools and the timers all send their command
/// through Submit, so every command reaches the CommandsIn service with an origin that Submit has checked.
Class OcuTalon.Core.Commands
{

/// Sends the command to the CommandsIn service and returns the status of the call; the service's answer is in result.
/// The status is OK once CommandsIn has answered, and result is then always a CommandResult whose Ok says whether the
/// command was carried out: a refused command, a stub owner and an owner that fails each give status OK and a result with
/// Ok 0 and a plain-English Message. An error status means only that the command never reached CommandsIn: one of
/// Submit's own refusals (below), or a production that cannot take it (not running, shutting down, or CommandsIn disabled).
/// The origin of the command is set here, never taken from its payload:
///   - inside a bridge context (a tool is running) it is "tool", whatever origin the caller names;
///   - otherwise it is the origin argument, which must be one of Msg.Enum ORIGIN.
/// Submit trusts the origin that its caller authenticated and does not check the caller's roles: the admin-checked
/// endpoints and CommandsIn own those checks.
/// An object that is not a command, or an origin that is not in the enumeration, is an error that names the problem;
/// nothing is sent and the command keeps its origin.
ClassMethod Submit(command As OcuTalon.Msg.Command, origin As %String, Output result As OcuTalon.Msg.CommandResult) As %Status
{
	Set result = ""
	Set command = $Get(command), origin = $Get(origin)
	If '$IsObject(command) || '$ClassMethod($ClassName(command), "%Extends", "OcuTalon.Msg.Command") {
		Quit $SYSTEM.Status.Error(5001, "Submit takes an OcuTalon.Msg.Command, not "_$Select($IsObject(command): "an object of class "_$ClassName(command), 1: "'"_command_"'"))
	}
	If ##class(OcuTalon.Bridge.Context).Active() {
		Set effective = "tool"
	} Else {
		If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#ORIGIN), origin) {
			Quit $SYSTEM.Status.Error(5001, "The origin '"_origin_"' is not one of "_##class(OcuTalon.Msg.Enum).#ORIGIN)
		}
		Set effective = origin
	}
	Set command.Origin = effective
	Set sc = ##class(Ens.Director).CreateBusinessService("CommandsIn", .service)
	If $$$ISERR(sc) Quit sc
	Quit service.ProcessInput(command, .result)
}

}
