/// CommandsIn, the adapterless service that is the production's one command gate (AD-1, AD-33). OcuTalon.Core.Commands.Submit
/// is the way in: it creates this service in the caller's own process and calls ProcessInput, so a bridge context of the
/// caller is visible here. For each command:
///   - the verb is matched by the exact class name of the command against the table Routes, which names the verb's one owner
///     item and the origins that may send it; a class not in the table (IncidentCommand included) is unknown_command;
///   - the origin is "tool" whenever a bridge context is active in this process, whatever the command says, and otherwise the
///     command's Origin. A tool may send only the verbs of TOOLVERBS, and Dismiss only for an incident that
///     Ownership.Incident returns for the command's SessionRef; any other origin must be one the table names for the verb;
///   - a refusal changes nothing: nothing is sent, and the caller gets a CommandResult with Ok 0, an Outcome (not_allowed,
///     not_found or unknown_command) and a plain-English Message;
///   - an accepted command is sent synchronously to its owner in the right trace session (AD-26): inside a turn the session
///     of the context's ThreadSessionId and its SuperSession, otherwise a session of its own whose SuperSession is the
///     TraceRef of the Session row of the command's SessionRef. Dismiss reaches IncidentManager as an IncidentCommand with
///     Verb "dismiss"; every other verb is sent as the command object itself, so that IdempotencyKey, SessionRef and Origin
///     arrive unchanged;
///   - the owner's CommandResult is the answer, as it is. An owner that is still a stub (code 5003, or a process stub's
///     <Ens>ErrBPTerminated that carries it) gives Outcome not_built; any other error, a timeout, no answer or an answer that
///     is not a CommandResult gives Outcome failed. Both have Ok 0.
/// OnProcessInput never answers an error status and never throws: an error thrown inside it is logged once and answers failed.
/// So Submit's status is OK whenever this service answered. Role checks are not made here: they stay with the admin-checked
/// entry points.
Class OcuTalon.Core.CommandsIn Extends Ens.BusinessService
{

/// The package of the verb classes; the rest of a command's class name is its verb.
Parameter VERBPACKAGE = "OcuTalon.Msg.Command.";

/// The verbs that origin tool may send (AD-1, FR-24, NFR-14). Dismiss is further limited to an incident the session can see.
Parameter TOOLVERBS = "SetReminder,CancelReminder,ListReminders,StartWatch,StopWatch,Dismiss";

/// How long the gate waits for the owner's answer, in seconds.
Parameter TIMEOUT = 120;

/// The Message of each refusal and failure.
Parameter MESSAGENOTFROMTOOL = "That can't be done from the chat. Nothing was changed.";

Parameter MESSAGEADMINONLY = "Only an OcuTalon admin can change settings. Nothing was changed.";

Parameter MESSAGETELEGRAMONLY = "A pairing completes only from Telegram. Nothing was changed.";

Parameter MESSAGENOTALLOWED = "OcuTalon can't take that command from here. Nothing was changed.";

Parameter MESSAGENOTFOUND = "This session has no such incident. Nothing was changed.";

Parameter MESSAGEUNKNOWN = "OcuTalon doesn't know that command. Nothing was changed.";

Parameter MESSAGENOTBUILT = "This part of OcuTalon isn't built yet. Nothing was changed.";

Parameter MESSAGEFAILED = "Something went wrong inside OcuTalon, so the command may not have finished.";

/// Receives a command and answers its CommandResult in pOutput; the status is always OK.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Set pOutput = ..Carry($Get(pInput))
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pOutput = ..Result("failed", ..#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// Checks the command and sends it to its owner; returns the CommandResult to answer.
Method Carry(command As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..Route(command, .verb, .owner, .origins) Quit ..Result("unknown_command", ..#MESSAGEUNKNOWN)
	Set origin = $Select(##class(OcuTalon.Bridge.Context).Active(): "tool", 1: command.Origin)
	If (origin = "tool") && '$ListFind($ListFromString(..#TOOLVERBS), verb) Quit ..Result("not_allowed", ..#MESSAGENOTFROMTOOL)
	If '$ListFind($ListFromString(origins), origin) {
		Quit ..Result("not_allowed", $Select(owner = "SettingsOps": ..#MESSAGEADMINONLY, verb = "Pair": ..#MESSAGETELEGRAMONLY, 1: ..#MESSAGENOTALLOWED))
	}
	If (origin = "tool") && (verb = "Dismiss") {
		Set incident = ##class(OcuTalon.Data.Ownership).Incident(command.IncidentRef, command.SessionRef, .sc)
		If '$IsObject(incident) Quit ..Result("not_found", ..#MESSAGENOTFOUND)
	}
	Do ..Join(command)
	Set request = $Select(verb = "Dismiss": ..Dismissal(command), 1: command)
	Set sc = ..Send(owner, request, .response)
	If $$$ISERR(sc) {
		If ..IsStub(sc) Quit ..Result("not_built", ..#MESSAGENOTBUILT)
		Quit ..Result("failed", ..#MESSAGEFAILED)
	}
	If '$IsObject($Get(response)) || 'response.%IsA("OcuTalon.Msg.CommandResult") Quit ..Result("failed", ..#MESSAGEFAILED)
	Quit response
}

/// The one send of the class: the command to the owner item, synchronously. Private so that no caller outside the class
/// sends; a test subclass overrides it to stand in for the owner.
Method Send(target As %String, request As OcuTalon.Msg.Command, Output response As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestSync(target, request, .response, ..#TIMEOUT)
}

/// Finds the command's verb in the table: 1 and the verb, its owner item and its origins (comma-separated) when the command's
/// class is exactly one of the table's verb classes, otherwise 0.
ClassMethod Route(command As %RegisteredObject, Output verb As %String, Output owner As %String, Output origins As %String) As %Boolean [ Private ]
{
	Set (verb, owner, origins) = ""
	If '$IsObject(command) Quit 0
	Set class = $ClassName(command)
	If $Extract(class, 1, $Length(..#VERBPACKAGE)) '= ..#VERBPACKAGE Quit 0
	Set name = $Extract(class, $Length(..#VERBPACKAGE) + 1, *)
	Set routes = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.CommandsIn||Routes").Data)
	Set iterator = routes.%GetIterator()
	While iterator.%GetNext(, .route) {
		If route.verb = name {
			Set verb = name, owner = route.owner, origins = route.origins
			Quit
		}
	}
	Quit (verb '= "")
}

/// Puts the send in the right trace session: inside a bridge context the session of its ThreadSessionId, when it has one, with
/// its SuperSession; otherwise a session of its own, with the TraceRef of the command's Session row as SuperSession.
Method Join(command As OcuTalon.Msg.Command) [ Private ]
{
	Set ..%SessionId = "", ..%SuperSession = ""
	If ##class(OcuTalon.Bridge.Context).Active() {
		Set context = ##class(OcuTalon.Bridge.Context).Current()
		If context.ThreadSessionId > 0 Set ..%SessionId = context.ThreadSessionId
		Set ..%SuperSession = context.SuperSession
	} ElseIf command.SessionRef '= "" {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(command.SessionRef)
		If $IsObject(session) Set ..%SuperSession = session.TraceRef
	}
}

/// The request that IncidentManager gets for a Dismiss: an IncidentCommand with Verb "dismiss" and the command's values.
ClassMethod Dismissal(command As OcuTalon.Msg.Command.Dismiss) As OcuTalon.Msg.IncidentCommand [ Private ]
{
	Set request = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set request.Verb = "dismiss"
	Set request.IncidentRef = command.IncidentRef
	Set request.IdempotencyKey = command.IdempotencyKey
	Set request.SessionRef = command.SessionRef
	Set request.Origin = command.Origin
	Quit request
}

/// 1 when the status is an Epic 0 stub's answer: code 5003, or a text that carries #5003 (a process stub's <Ens>ErrBPTerminated).
ClassMethod IsStub(sc As %Status) As %Boolean [ Private ]
{
	Quit ''($ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003) || ($SYSTEM.Status.GetErrorText(sc) [ "#5003"))
}

/// A CommandResult that carries out nothing: Ok 0, the outcome code and the plain-English message.
ClassMethod Result(outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 0
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

/// The verbs, one entry each: the owner item that carries the verb out, and the origins that may send it (Msg.Enum ORIGIN).
/// A verb that is not here is not routed. Every settings verb, now and later, goes to SettingsOps with the origins
/// system and web_admin.
XData Routes [ MimeType = application/json ]
{
[
 {"verb": "SetReminder", "owner": "ReminderOps", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "CancelReminder", "owner": "ReminderOps", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "ListReminders", "owner": "ReminderOps", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "StartWatch", "owner": "WatchOps", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "StopWatch", "owner": "WatchOps", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "Dismiss", "owner": "IncidentManager", "origins": "web_user,web_admin,telegram,tool,timer,system"},
 {"verb": "SetDemoMode", "owner": "SettingsOps", "origins": "web_admin,system"},
 {"verb": "Pair", "owner": "SessionOps", "origins": "telegram"},
 {"verb": "Unpair", "owner": "SessionOps", "origins": "web_user,web_admin,telegram,timer,system"},
 {"verb": "EndSession", "owner": "SessionOps", "origins": "web_user,web_admin,telegram,timer,system"}
]
}

}
