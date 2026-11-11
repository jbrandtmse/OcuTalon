/// CommandsIn, the adapterless service that is the production's one command gate (AD-1, AD-33). OcuTalon.Core.Commands.Submit
/// is the way in: it creates this service in the caller's own process and calls ProcessInput, so a bridge context of the
/// caller is visible here. For each command:
///   - the verb is matched by the exact class name of the command against the table Routes, which names the verb's one owner
///     item and the origins that may send it; a class not in the table (IncidentCommand included) is unknown_command;
///   - the origin is "tool" whenever a bridge context is active in this process, whatever the command says, and otherwise the
///     command's Origin. A tool may send only the verbs of TOOLVERBS, and Dismiss only for an incident that
///     Ownership.Incident returns for the command's SessionRef, which inside a bridge context must be the context's OwnerRef;
///     any other origin must be one the table names for the verb (a refusal of a settings verb says "admin only" unless the verb's
///     origins include web_user or tool, as the persona and heartbeat verbs' do; SetHeartbeat and RunHeartbeat are web_user only, and neither is
///     a tool verb; the precedent verbs MarkNoise and ForgetPrecedent are web_user only and no tool verb either). SendDigest, the one step 2 verb a tool may also send, takes no
///     recipient: it reaches only the session's own digest.channels, and inside a bridge context its SessionRef must be the context's
///     OwnerRef, so a tool cannot name another session. ProposePersona, the one settings verb a tool may send, is held to the same rule:
///     inside a bridge context its SessionRef must be the context's OwnerRef (DW-570), so a tool proposes only the persona of the
///     session whose turn it is in, and the refusal is not_allowed and nothing reaches SettingsOps;
///   - the memory verbs PinMemory and UnpinMemory are web_user only and no tool verb, so inside a bridge context they are not_allowed; ForgetMemory
///     is accepted from tool (with the context check below) and from web_user; SearchMemory, a read verb that the web layer sends for the Memory
///     card's search, is web_user only and no tool verb either;
///   - ListPinnedMemories, the read behind the Memory card's Pinned tab, is web_user only and no tool verb, and is sent with the search's bounded wait
///     (Story 41.13);
///   - on the online demo (Data.Setting onlineDemo = 1) each SearchMemory counts as one of the session's messages through Allowance.TryConsumeRead,
///     before anything is sent and without a Turn or an allowance window; past the limit the answer is Outcome allowance (Ok 0) with Data {retryAt, limit}
///     (Story 41.13). The list, the pinned read and every other verb never count;
///   - step 4 (AD-1, AD-21): the five MCP verbs AddMcpServer, RemoveMcpServer, ClassifyTool, SetSourcePoll and RemoveSourcePoll go to
///     McpOps from web_admin only; none is a tool verb, and a refusal from any other origin than tool says "admin only", as for
///     SettingsOps. SendEmail goes to EmailOut from system (FixExecutor's approved email fix) and from tool; from tool it is accepted
///     only for the session user's own mailbox: inside a bridge context its SessionRef must be the context's OwnerRef, the product key
///     email.owner must be the SessionRef, and the product key email.address must be set and equal, ignoring case and surrounding
///     spaces, every comma-separated recipient (an empty list is refused). Inside a bridge context a tool's SendEmail also needs a clean turn (AD-10): the
///     context's Provenance must be user (the replay of an approved call sets it) and its Tainted flag 0 (a replay context needs only the provenance), so a turn that read untrusted content
///     cannot send without the approval path (Story 21.6). Otherwise the refusal is not_allowed and nothing is sent;
///   - a refusal changes nothing: nothing is sent, and the caller gets a CommandResult with Ok 0, an Outcome (not_allowed,
///     not_found or unknown_command) and a plain-English Message;
///   - an accepted command is sent synchronously to its owner in the right trace session (AD-26): inside a turn the session
///     of the context's ThreadSessionId and its SuperSession, otherwise a session of its own whose SuperSession is the
///     TraceRef of the Session row of the command's SessionRef. Dismiss reaches IncidentManager as an IncidentCommand with
///     Verb "dismiss"; RunHeartbeat reaches Checks as an OcuTalon.Checks.Msg.BeatNow with the command's SessionRef and the UTC time of
///     now as RequestedAt (a BeatNow has no Origin and no IdempotencyKey); every other verb is sent as the command object itself, so that
///     IdempotencyKey, SessionRef and Origin arrive unchanged;
///   - the owner's CommandResult is the answer, as it is. An owner that is still a stub (code 5003, or a process stub's
///     <Ens>ErrBPTerminated that carries it) gives Outcome not_built; any other error, a timeout, no answer or an answer that
///     is not a CommandResult gives Outcome failed. Both have Ok 0.
///     A SendEmail gives Outcome not_connected (Ok 0) with MESSAGENOTCONNECTED, the sentence that EmailOut itself answers when it has no address (Story 21.6),
///     when EmailOut has no alive job (the item is disabled until an outgoing server is saved, and a message sent to a disabled item that the production
///     defines waits for the whole TIMEOUT and ends with no answer), and when the send fails because EmailOut is not registered in the running production.
///     A SearchMemory that has no answer within SEARCHTIMEOUT seconds gives Outcome busy (Ok 0) instead, which the web layer answers with its own busy text.
///     A ListPinnedMemories that has no answer within SEARCHTIMEOUT seconds gives Outcome busy (Ok 0) the same way (Story 41.13).
/// OnProcessInput never answers an error status and never throws: an error thrown inside it is logged once and answers failed.
/// So Submit's status is OK whenever this service answered. Role checks are not made here: they stay with the admin-checked
/// entry points.
Class OcuTalon.Core.CommandsIn Extends Ens.BusinessService
{

/// The package of the verb classes; the rest of a command's class name is its verb.
Parameter VERBPACKAGE = "OcuTalon.Msg.Command.";

/// The verbs that origin tool may send (AD-1, FR-24, NFR-14). Dismiss and ProposeFix are further limited to an incident the session can see.
/// ProposePersona is the one settings verb among them, and a tool is the only origin that may send it. SendEmail is limited to the
/// session user's own mailbox address (Carry). No MCP verb is among them.
Parameter TOOLVERBS = "SetReminder,CancelReminder,ListReminders,StartWatch,StopWatch,Dismiss,SendDigest,SaveMemory,ForgetMemory,ProposePersona,SendEmail,ProposeFix";

/// How long the gate waits for the owner's answer, in seconds.
Parameter TIMEOUT = 120;

/// How long the gate waits for the answer to a SearchMemory, in seconds. A search is a read that a person waits for, so a slow or stuck embedder
/// ends the wait early: the answer is Outcome busy (Ok 0), never failed.
Parameter SEARCHTIMEOUT = 20;

/// The Message of each refusal and failure.
Parameter MESSAGENOTFROMTOOL = "That can't be done from the chat. Nothing was changed.";

Parameter MESSAGEADMINONLY = "Only an OcuTalon admin can change settings. Nothing was changed.";

Parameter MESSAGETELEGRAMONLY = "A pairing completes only from Telegram. Nothing was changed.";

Parameter MESSAGENOTALLOWED = "OcuTalon can't take that command from here. Nothing was changed.";

Parameter MESSAGENOTFOUND = "This session has no such incident. Nothing was changed.";

Parameter MESSAGEUNKNOWN = "OcuTalon doesn't know that command. Nothing was changed.";

Parameter MESSAGENOTBUILT = "This part of OcuTalon isn't built yet. Nothing was changed.";

Parameter MESSAGEFAILED = "Something went wrong inside OcuTalon, so the command may not have finished.";

/// The Message of a SendEmail that finds no EmailOut running (Public text Q3 of Story 21.6, the same sentence as EmailOut's).
Parameter MESSAGENOTCONNECTED = "No outgoing mail server is connected, so the email wasn't sent.";

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
		Quit ..Result("not_allowed", $Select(((owner = "SettingsOps") || (owner = "McpOps")) && '$ListFind($ListFromString(origins), "web_user") && '$ListFind($ListFromString(origins), "tool"): ..#MESSAGEADMINONLY, verb = "Pair": ..#MESSAGETELEGRAMONLY, 1: ..#MESSAGENOTALLOWED))
	}
	If (origin = "tool") && (verb = "ProposePersona") && ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit ..Result("not_allowed", ..#MESSAGENOTFROMTOOL)
	If (origin = "tool") && (verb = "Dismiss") {
		If ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit ..Result("not_found", ..#MESSAGENOTFOUND)
		Set incident = ##class(OcuTalon.Data.Ownership).Incident(command.IncidentRef, command.SessionRef, .sc)
		If '$IsObject(incident) Quit ..Result("not_found", ..#MESSAGENOTFOUND)
	}
	If (origin = "tool") && (verb = "ProposeFix") {
		If ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit ..Result("not_found", ..#MESSAGENOTFOUND)
		Set incident = ##class(OcuTalon.Data.Ownership).Incident(command.IncidentRef, command.SessionRef, .sc)
		If '$IsObject(incident) Quit ..Result("not_found", ..#MESSAGENOTFOUND)
	}
	If (origin = "tool") && ((verb = "SendDigest") || (verb = "SaveMemory") || (verb = "ForgetMemory")) && ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit ..Result("not_allowed", ..#MESSAGENOTFROMTOOL)
	If (origin = "tool") && (verb = "SendEmail") && ('..OwnAddressOnly(command) || '..CleanTurn()) Quit ..Result("not_allowed", ..#MESSAGENOTFROMTOOL)
	If verb = "SearchMemory" {
		Set refusal = ..SearchAllowance(command)
		If $IsObject(refusal) Quit refusal
	}
	Do ..Join(command)
	Set request = $Select(verb = "Dismiss": ..Dismissal(command), verb = "RunHeartbeat": ..BeatRequest(command), 1: command)
	Set sc = ..Send(owner, request, .response)
	If $$$ISERR(sc) {
		If ..IsStub(sc) Quit ..Result("not_built", ..#MESSAGENOTBUILT)
		If (verb = "SendEmail") && ..IsNotRegistered(sc) Quit ..Result("not_connected", ..#MESSAGENOTCONNECTED)
		Quit ..Result("failed", ..#MESSAGEFAILED)
	}
	If '$IsObject($Get(response)) || 'response.%IsA("OcuTalon.Msg.CommandResult") Quit ..Result("failed", ..#MESSAGEFAILED)
	Quit response
}

/// 1 when a SendEmail from a tool is for the session user's own mailbox: inside a bridge context the command's SessionRef is the
/// context's OwnerRef, the product key email.owner is the SessionRef, email.address is set, and every comma-separated recipient,
/// trimmed and lower-cased, equals it lower-cased. An empty list, an empty recipient or no mailbox gives 0. Both keys are read from their
/// rows and never from the per-process cache, because the mailbox moves to the admin who saved last (SettingsOps.SaveEmail) and a cached
/// pair could name the old owner with the new address.
ClassMethod OwnAddressOnly(command As OcuTalon.Msg.Command.SendEmail) As %Boolean [ Private ]
{
	If ##class(OcuTalon.Bridge.Context).Active() && (command.SessionRef '= ##class(OcuTalon.Bridge.Context).Current().OwnerRef) Quit 0
	Set address = $ZConvert($ZStrip(..Stored("email.address"), "<>W"), "L")
	If (address = "") || (command.SessionRef = "") || (..Stored("email.owner") '= command.SessionRef) Quit 0
	Set recipients = command.Recipients
	If $ZStrip(recipients, "<>W") = "" Quit 0
	Set own = 1
	For i = 1:1:$Length(recipients, ",") {
		If $ZConvert($ZStrip($Piece(recipients, ",", i), "<>W"), "L") '= address Set own = 0
	}
	Quit own
}

/// The Kind of the context of a replay of an approved call (Msg.Enum REQUESTKIND tool, Bridge.Policy.Gate REPLAYKIND).
Parameter REPLAYKIND = "tool";

/// 1 when the command is not sent from inside a bridge context, or the context's turn is clean: its Provenance is user (the replay of an approved call
/// sets it, AD-10) and no result that is not trusted output has reached it (Tainted 0). A replay context is clean whatever its taint says: the gate
/// reads no taint in a replay (the grant of the approved call is single use) and taints the context when it allows the call, before the tool runs.
ClassMethod CleanTurn() As %Boolean [ Private ]
{
	If '##class(OcuTalon.Bridge.Context).Active() Quit 1
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	Quit (context.Provenance = "user") && ((context.Kind = ..#REPLAYKIND) || 'context.Tainted)
}

/// The value of the product key right now, read from its row and never from the per-process cache; "" when the row is absent.
ClassMethod Stored(key As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Setting).Fresh(key)
}

/// The one send of the class: the command to the owner item, synchronously. Private, so that only Carry sends through it,
/// after the checks; a test subclass overrides it to stand in for the owner.
Method Send(target As %String, request As Ens.Request, Output response As %Library.Persistent) As %Status [ Private ]
{
	If request.%IsA("OcuTalon.Msg.Command.SendEmail") && '..ItemRunning(target) {
		Set response = ..Result("not_connected", ..#MESSAGENOTCONNECTED)
		Quit $$$OK
	}
	If request.%IsA("OcuTalon.Msg.Command.ListPinnedMemories") Quit ..SendSearch(target, request, .response)
	If request.%IsA("OcuTalon.Msg.Command.SearchMemory") Quit ..SendSearch(target, request, .response)
	Quit ..SendRequestSync(target, request, .response, ..#TIMEOUT)
}

/// The refusal that a SearchMemory meets on the online demo, or "" when it may go on (Story 41.13, DW-1031): Allowance.TryConsumeRead counts it
/// against the session's message allowance. Refused with a retryAt, the result is Outcome allowance with Data {retryAt, limit}; refused without
/// one (the row's lock stayed busy, or a failure), it is the gate's failed result. Nothing is recorded by a refusal.
Method SearchAllowance(command As OcuTalon.Msg.Command.SearchMemory) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ##class(OcuTalon.Core.Allowance).TryConsumeRead(command.SessionRef, .retryAt) Quit ""
	If retryAt = "" Quit ..Result("failed", ..#MESSAGEFAILED)
	Set result = ..Result("allowance", "")
	Set data = {}
	Set data.retryAt = retryAt
	Do data.%Set("limit", ##class(OcuTalon.Core.Allowance).Limit(), "number")
	Set result.Data = data.%ToJSON()
	Quit result
}

/// The send of a SearchMemory: it waits SEARCHTIMEOUT seconds. A synchronous send that has no answer by then ends with an OK status and no response, which
/// is answered here as a CommandResult with Ok 0 and Outcome busy (the Message is the gate's failed sentence); the owner still finishes the request, and
/// nothing is changed by it.
/// A ListPinnedMemories is sent the same way (Story 41.13).
Method SendSearch(target As %String, request As Ens.Request, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set sc = ..SendRequestSync(target, request, .response, ..#SEARCHTIMEOUT)
	If $$$ISOK(sc) && '$IsObject($Get(response)) Set response = ..Result("busy", ..#MESSAGEFAILED)
	Quit sc
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

/// The request that Checks gets for a RunHeartbeat: a BeatNow with the command's SessionRef and RequestedAt the UTC time of now.
ClassMethod BeatRequest(command As OcuTalon.Msg.Command.RunHeartbeat) As OcuTalon.Checks.Msg.BeatNow [ Private ]
{
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = command.SessionRef
	Set request.RequestedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit request
}

/// 1 when the status is an Epic 0 stub's answer: code 5003, or a text that carries #5003 (a process stub's <Ens>ErrBPTerminated).
ClassMethod IsStub(sc As %Status) As %Boolean [ Private ]
{
	Quit ''($ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003) || ($SYSTEM.Status.GetErrorText(sc) [ "#5003"))
}

/// 1 when the status is the dispatch error of an item that the production does not register (Ens.Host.SendRequestSync).
ClassMethod IsNotRegistered(sc As %Status) As %Boolean [ Private ]
{
	Quit ''($SYSTEM.Status.GetErrorCodes(sc) [ "ErrBusinessDispatchNameNotRegistered")
}

/// 1 when the production item has an alive job that is not in error.
ClassMethod ItemRunning(item As %String) As %Boolean [ Private ]
{
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	If $$$ISERR(result.Execute()) Quit 0
	Set found = 0
	While result.Next() {
		If (result.Get("ConfigName") '= item) || (result.Get("State") '= "Alive") Continue
		If $ListFind($ListBuild("error", "halted", "terminated"), result.Get("Status")) Continue
		Set found = 1
		Quit
	}
	Quit found
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
/// A verb that is not here is not routed. Every settings verb goes to SettingsOps with the origins system and web_admin,
/// except the persona verbs (AD-1): SetPersona from web_user only, the person's own page, and ProposePersona from tool only, and the
/// heartbeat verbs (Epic 39): SetHeartbeat to SettingsOps and RunHeartbeat to Checks, each from web_user only, and the precedent verbs (Epic 41,
/// AD-21): MarkNoise and ForgetPrecedent to PrecedentOps, each from web_user only; neither is a tool verb.
/// The memory verbs (Epic 41, AD-21): PinMemory and UnpinMemory to MemoryOps from web_user only, neither a tool verb, and ForgetMemory
/// to MemoryOps from tool and from web_user (the Memory card's Forget; MemoryOps forgets only the command's own session's row), and SearchMemory
/// (a read) to MemoryOps from web_user only.
/// ListPinnedMemories (a read, Story 41.13) goes to MemoryOps from web_user only.
/// A settings verb whose origins include web_user or tool is refused with the plain not-allowed text, not the admin-only one.
/// Step 4 (Story 35.2, AD-1, AD-21): the MCP verbs go to McpOps from web_admin only, and SendEmail to EmailOut from tool (own address only,
/// Carry) and system. SendDigest goes to Digest, and GotIt to SessionOps. TestModel (Story 18.3) goes to SettingsOps from web_admin only.
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
 {"verb": "SetPersona", "owner": "SettingsOps", "origins": "web_user"},
 {"verb": "ProposePersona", "owner": "SettingsOps", "origins": "tool"},
 {"verb": "Pair", "owner": "SessionOps", "origins": "telegram"},
 {"verb": "Unpair", "owner": "SessionOps", "origins": "web_user,web_admin,telegram,timer,system"},
 {"verb": "EndSession", "owner": "SessionOps", "origins": "web_user,web_admin,telegram,timer,system"},
 {"verb": "SendDigest", "owner": "Digest", "origins": "tool,web_admin"},
 {"verb": "SaveSettings", "owner": "SettingsOps", "origins": "web_admin,system"},
 {"verb": "TestModel", "owner": "SettingsOps", "origins": "web_admin"},
 {"verb": "GotIt", "owner": "SessionOps", "origins": "web_user,web_admin,telegram"},
 {"verb": "SaveMemory", "owner": "MemoryOps", "origins": "tool"},
 {"verb": "ForgetMemory", "owner": "MemoryOps", "origins": "tool,web_user"},
 {"verb": "AddDocument", "owner": "DocumentOps", "origins": "web_user"},
 {"verb": "RemoveDocument", "owner": "DocumentOps", "origins": "web_user"},
 {"verb": "SetHeartbeat", "owner": "SettingsOps", "origins": "web_user"},
 {"verb": "RunHeartbeat", "owner": "Checks", "origins": "web_user"},
 {"verb": "MarkNoise", "owner": "PrecedentOps", "origins": "web_user"},
 {"verb": "ForgetPrecedent", "owner": "PrecedentOps", "origins": "web_user"},
 {"verb": "PinMemory", "owner": "MemoryOps", "origins": "web_user"},
 {"verb": "UnpinMemory", "owner": "MemoryOps", "origins": "web_user"},
 {"verb": "SearchMemory", "owner": "MemoryOps", "origins": "web_user"},
 {"verb": "AddMcpServer", "owner": "McpOps", "origins": "web_admin"},
 {"verb": "RemoveMcpServer", "owner": "McpOps", "origins": "web_admin"},
 {"verb": "ClassifyTool", "owner": "McpOps", "origins": "web_admin"},
 {"verb": "SetSourcePoll", "owner": "McpOps", "origins": "web_admin"},
 {"verb": "RemoveSourcePoll", "owner": "McpOps", "origins": "web_admin"},
 {"verb": "SendEmail", "owner": "EmailOut", "origins": "tool,system"},
 {"verb": "ProposeFix", "owner": "IncidentManager", "origins": "tool"},
 {"verb": "ListPinnedMemories", "owner": "MemoryOps", "origins": "web_user"}
]
}

}
