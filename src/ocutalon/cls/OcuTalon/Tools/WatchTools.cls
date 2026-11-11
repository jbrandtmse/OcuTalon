/// The methods behind OcuTalon.Tools.Watching (AD-1, AD-3, AD-4, AD-9, AD-10, AD-15, AD-18, AD-28): the five watch tools of the Chat agent, start_watch,
/// stop_watch, list_productions, dismiss_incident and check_status. start_watch and stop_watch resolve the name the user gave through OcuTalon.Watch.Reader, the only reader of
/// the productions, and submit StartWatch or StopWatch through OcuTalon.Tools.CommandCall, so the tools never write a watch themselves:
/// WatchOps owns the BackgroundCheck rows and checks every start again. stop_watch reads the session's own watches through the ownership API
/// (OcuTalon.Data.Ownership.Checks) before it asks the reader, so that a watch on a production the reader no longer lists can still be stopped. The session comes from the bridge context of the call, never from an
/// argument. list_productions reads the reader's list and submits nothing.
/// dismiss_incident finds the incident to dismiss among the session's own noticed open or resolved incidents (OcuTalon.Tools.WatchAnswers.ResolveIncident,
/// through the ownership API) and submits Msg.Command.Dismiss for its Ref through CommandCall.Run, so the tool never writes or opens an incident:
/// IncidentManager is the only writer (AD-33). Exactly one match is submitted; several answer ambiguous, none unknown_incident, and no candidate at all
/// no_incident, with the busy incidents (awaiting_approval or fixing) listed in others. The answer carries the owner's outcome, the production, the Ref
/// and the state, and no diagnosis or error text, so it is trusted output.
/// propose_fix (Story 23.2) finds the incident like dismiss_incident (the session's own open or resolved incidents, through the ownership API; for partner_warning, Story 23.5,
/// those of every state but closed, with no item, and with none the answer is refused with NOWARNING) and submits Msg.Command.ProposeFix
/// for its Ref through CommandCall.Run: IncidentManager asks for the dry run and raises the approval request itself, so the tool never raises, writes or opens anything. It is
/// safe, not read-only and trusted output, like dismiss_incident, so the gate denies it in an untrusted or tainted turn. Its answer carries the owner's outcome, the production, the
/// kind, the item and the request's Ref, and no diagnosis or error text.
/// check_status reads the latest results of the session's own background checks through OcuTalon.Tools.WatchAnswers.CheckResults (the ownership API) and
/// copies them, as they are, to the bridge context's HostData as the checks member, where Conversation finds them for Checks.Render (AD-28). The tool
/// never decides or interprets a result and submits nothing. Its answer is built from the session's own rows (the display name, the result, the finding
/// that Checks built in code, and the time in the instance zone), so no content from outside the instance reaches the model through it.
///   - A call that is not a session's turn answers NOSESSION before anything is read or submitted, with one exception: a call whose context's owner is
///     eval (an evaluation turn case, Story 9.7) answers the rows that the case recorded in the OcuTalon.Eval.Msg.TurnResult of the context's ItemId
///     (WatchAnswers.EvalCheckResults) in the same form, and puts them in HostData in the same way, so that the reply is rendered as the product
///     renders it. The branch is chosen by the owner of the call alone, never by an argument; an eval call with no such rows answers NOSESSION, and never
///     the results of any session.
///   - A name that no production matches submits nothing and answers unknown_production with the name, the list of the names that can be watched
///     (joined with a comma and with "and" before the last one) and each production's name and namespace. On the online demo it answers
///     only_orders with the README link instead. A name that two productions match answers ambiguous with each one's name and namespace, and
///     the optional namespace argument picks one.
///   - A name that one production matches is submitted. The answer is CommandCall.Answer with the outcome (started, already_watching, stopped,
///     not_watching, or the owner's refusal) and the production's display name added.
/// The answers carry the outcome and the values to say, never the sentence: the Chat agent's instructions hold the sentences (AD-32). The shaping
/// of the answers is OcuTalon.Tools.WatchAnswers, because a tool provider returns only through Return.
/// Each tool declares, by the naming rule of ReminderTools (the tool's name in upper case with _ and - removed), its step label (AD-9) and its
/// classification for the gate (AD-10). All five are safe and trusted output: their answers are built in code from the owner's CommandResult,
/// from IRIS's production registry and, for dismiss_incident and check_status, from the session's own incident and watch rows (Test.Bridge.Gate pins
/// the keys and messages of their answers), so no content from outside the instance reaches the model through them, and a result never taints the
/// turn (a start_watch after a list_productions in one turn still runs). start_watch, stop_watch and dismiss_incident are not read-only, so the gate denies them
/// in an untrusted or tainted turn; list_productions and check_status are read-only, so they also run there.
/// It extends OcuTalon.Tools.Result and returns only through Return. A tool method runs inside AI Hub's callback, so it makes no AI Hub call
/// and no Python call (AD-6). The description of a tool is its method's doc comment, and an argument's DESCRIPTION is what the model reads
/// about it: they are text for the model, never shown to the user as written.
Class OcuTalon.Tools.WatchTools Extends OcuTalon.Tools.Result
{

/// The README link of the answer only_orders: the sentence of the online demo points to it.
Parameter READMELINK = "https://github.com/jbrandtmse/OcuTalon#readme";

Parameter STEPLABELSTARTWATCH = "Starting a watch";

Parameter STEPLABELSTOPWATCH = "Stopping a watch";

Parameter STEPLABELLISTPRODUCTIONS = "Listing the productions";

Parameter STEPLABELDISMISSINCIDENT = "Dismissing an incident";

Parameter STEPLABELCHECKSTATUS = "Reading the check results";

Parameter STEPLABELPROPOSEFIX = "Asking to approve a fix";

Parameter CLASSIFICATIONSTARTWATCH = "safe";

Parameter READONLYSTARTWATCH = 0;

Parameter TRUSTEDOUTPUTSTARTWATCH = 1;

Parameter CLASSIFICATIONSTOPWATCH = "safe";

Parameter READONLYSTOPWATCH = 0;

Parameter TRUSTEDOUTPUTSTOPWATCH = 1;

Parameter CLASSIFICATIONLISTPRODUCTIONS = "safe";

Parameter READONLYLISTPRODUCTIONS = 1;

Parameter TRUSTEDOUTPUTLISTPRODUCTIONS = 1;

Parameter CLASSIFICATIONDISMISSINCIDENT = "safe";

Parameter READONLYDISMISSINCIDENT = 0;

Parameter TRUSTEDOUTPUTDISMISSINCIDENT = 1;

Parameter CLASSIFICATIONCHECKSTATUS = "safe";

Parameter READONLYCHECKSTATUS = 1;

Parameter TRUSTEDOUTPUTCHECKSTATUS = 1;

Parameter CLASSIFICATIONPROPOSEFIX = "safe";

Parameter READONLYPROPOSEFIX = 0;

Parameter TRUSTEDOUTPUTPROPOSEFIX = 1;

/// The answer of start_watch and stop_watch for a kind of watch that is neither production nor queues (text for the model).
Parameter UNKNOWNKIND = "That kind of watch is not one OcuTalon has, so nothing was done.";

/// The states of the incidents that propose_fix may name (AD-15), and, for partner_warning, which never moves an incident (Story 23.5), every state but closed.
Parameter FIXABLE = "open,resolved";

Parameter WARNABLE = "open,awaiting_approval,fixing,resolved";

/// The reason that propose_fix gives for a partner_warning when the session has no incident that is not closed.
Parameter NOWARNING = "There's no open incident to warn the partner about, so no delay notice was drafted";

/// Starts watching a production for the user in this conversation: a background check that tells the user only when something needs them.
/// Call it directly with the name the user gave, such as Orders. The answer has an outcome. started: the watch is on, and production is the
/// name to say. already_watching: the user already watches it. unknown_production: no production has that name, and the answer gives the list
/// of names to offer. only_orders: this is the online demo, which watches only the Orders production. ambiguous: two productions have that
/// name, so ask the user which one they meant. Anything else: the message says why nothing was done.
/// With kind queues it starts the queue-backlog check instead: every minute OcuTalon looks at the queues it can read and tells the user about a queue that backs
/// up past its threshold. The name is then ignored, no production is looked up, and the answer has outcome started or already_watching and check, the name
/// of the check. A kind that is neither production nor queues answers unknown_kind.
ClassMethod StartWatch(name As %String(DESCRIPTION = "The name of the production, exactly as the user gave it, such as Orders."), namespace As %String(DESCRIPTION = "Only when an earlier answer was ambiguous: the namespace of the production that the user picked. Otherwise leave it out.") = "", kind As %String(DESCRIPTION = "production (the default) or queues: queues watches every queue OcuTalon can read for a backlog, and then name is ignored.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session()
	If $IsObject(refusal) Quit ..Return(refusal)
	If kind = ##class(OcuTalon.Watch.Ops).#QUEUEKIND {
		Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()
		Set command.Kind = kind
		Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
		If $IsObject(refusal) Quit ..Return(refusal)
		Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Queued(result))
	}
	If '##class(OcuTalon.Tools.WatchAnswers).KnownKind(kind) Quit ..Return({"ok": false, "outcome": "unknown_kind", "message": (..#UNKNOWNKIND)})
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).Resolve(name, namespace, .match)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()
	Set command.Namespace = match.namespace
	Set command.Production = match.production
	Set command.DisplayName = match.displayName
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Submitted(result, match))
}

/// Stops watching a production for the user in this conversation. Call it directly with the name the user gave, such as Orders. The watches of this
/// conversation are read first (through the ownership API), then the list of the productions. The answer has
/// an outcome. stopped: the watch is off. not_watching: the user was not watching it. unknown_production, only_orders and ambiguous are as for
/// start_watch. Anything else: the message says why nothing was done.
/// With kind queues it stops the queue-backlog check instead (the name is ignored, and the answer has outcome stopped or not_watching and check, the name
/// of the check). A kind that is neither production nor queues answers unknown_kind.
ClassMethod StopWatch(name As %String(DESCRIPTION = "The name of the production, exactly as the user gave it, such as Orders."), namespace As %String(DESCRIPTION = "Only when an earlier answer was ambiguous: the namespace of the production that the user picked. Otherwise leave it out.") = "", kind As %String(DESCRIPTION = "production (the default) or queues: queues stops the queue-backlog check, and then name is ignored.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	If kind = ##class(OcuTalon.Watch.Ops).#QUEUEKIND {
		Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
		Set command.Kind = kind
		Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
		If $IsObject(refusal) Quit ..Return(refusal)
		Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Queued(result))
	}
	If '##class(OcuTalon.Tools.WatchAnswers).KnownKind(kind) Quit ..Return({"ok": false, "outcome": "unknown_kind", "message": (..#UNKNOWNKIND)})
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).ResolveStop(name, namespace, context.OwnerRef, .match)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set command.Namespace = match.namespace
	Set command.Production = match.production
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Submitted(result, match))
}

/// Lists the productions that can be watched: each one's name and namespace, and its running state (running, stopped and so on). Use it to answer which
/// productions OcuTalon can watch, and whether each is running. It starts nothing.
ClassMethod ListProductions() As %DynamicObject
{
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Listed(##class(OcuTalon.Watch.Reader).Productions()))
}

/// Dismisses an incident of the user in this conversation: closes an open or resolved incident that the user has been told about. Call it at once when the
/// user asks to dismiss an incident, with the production's name when the user names one. The incident is found among this conversation's open and
/// resolved incidents. The answer has an outcome. closed: the incident is dismissed; production, ref and state say which. ambiguous: several incidents
/// match, so ask the user which one they meant, and the answer lists them in incidents. unknown_incident: no open or resolved incident matches, and the
/// answer lists the ones there are in incidents. no_incident: there is no open or resolved incident; others lists the incidents that cannot be dismissed
/// now, because their fix waits for approval (awaiting_approval) or is running (fixing). Anything else: the message says why nothing was dismissed.
ClassMethod DismissIncident(production As %String(DESCRIPTION = "The name of the production the incident is about, exactly as the user gave it, such as Orders. Only when the user names one.") = "", incident As %String(DESCRIPTION = "Only when an earlier answer of dismiss_incident listed incidents and the user picked one: that incident's ref. Otherwise leave it out.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).ResolveIncident(production, incident, context.OwnerRef, .match)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set command = ##class(OcuTalon.Msg.Command.Dismiss).%New()
	Set command.IncidentRef = match.ref
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Dismissed(result, match))
}

/// Asks for approval of a fix that the user asked for: suspend_item (disable a production item), resume_item (enable it again, which is also how a suspend is undone), reroute
/// (resend the failed messages of an incident as copies to another item) or partner_warning (draft a delay notice to the partner about the incident). Call it at once when the
/// user asks for one of these, with the item the user named: for suspend_item and resume_item the item to change, for reroute the item to send the failed messages to, and for
/// partner_warning no item. It works on the user's open or resolved incident, found as for dismiss_incident (production names it when the user does); a partner_warning works on
/// any incident that is not closed. It raises an approval request with a dry run and changes nothing until the user approves it. The answer has an outcome. raised: the request
/// is raised; approvalRef says which, and the user sees it in the chat. drafting: for partner_warning, the notice is being drafted and will come as an approval request.
/// already_asked: the same request is already waiting. refused: the message says why the fix can't be done. nothing: there is nothing to do, for example no failed message to
/// reroute. ambiguous, unknown_incident and no_incident are as for dismiss_incident. Anything else: the message says why nothing was raised.
ClassMethod ProposeFix(kind As %String(DESCRIPTION = "One of suspend_item, resume_item, reroute or partner_warning."), item As %String(DESCRIPTION = "The name of the production item to suspend or resume; for reroute, the name of the item to send the failed messages to. For partner_warning leave it out.") = "", production As %String(DESCRIPTION = "The name of the production the incident is about, exactly as the user gave it, such as Orders. Only when the user names one.") = "", incident As %String(DESCRIPTION = "Only when an earlier answer listed incidents and the user picked one: that incident's ref. Otherwise leave it out.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set warning = (kind = "partner_warning")
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).ResolveIncident(production, incident, context.OwnerRef, .match, $Select(warning: ..#WARNABLE, 1: ..#FIXABLE))
	If $IsObject(refusal) {
		If (kind = "reroute") && (refusal.outcome = "no_incident") Set refusal = {"ok": false, "outcome": "nothing", "message": (##class(OcuTalon.Watch.IncidentManager).#MESSAGENOTHING)}
		If warning && (refusal.outcome = "no_incident") Set refusal = {"ok": false, "outcome": "refused", "message": (..#NOWARNING)}
		Quit ..Return(refusal)
	}
	Set command = ##class(OcuTalon.Msg.Command.ProposeFix).%New()
	Set command.IncidentRef = match.ref
	Set command.FixKind = kind
	Set command.Parameters = $Select(warning && (item = ""): {}, kind = "reroute": {"target": (item)}, 1: {"item": (item)}).%ToJSON()
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Set answer.outcome = result.Outcome
	Set answer.production = match.production
	Set answer.kind = kind
	If item '= "" Set answer.item = item
	If result.Ref '= "" {
		Do answer.%Remove("ref")
		Set answer.approvalRef = result.Ref
	}
	Quit ..Return(answer)
}

/// Reads the latest results of the user's background checks in this conversation, one per watched production and one for the queue-backlog check when the user watches queue backlogs. Call it when the user asks whether everything
/// is fine, OK or working, or how the watched productions are doing. The answer is ok with checks, a list in a fixed order. Each check has result: passed,
/// failed, not_checked when the last run could not check, or empty when the check has not run yet; entry: the name to say, such as Orders production;
/// finding: what the last run found, or why it could not check; and checked: when it last ran, in the instance's time, empty before its first run. An empty
/// list means that nothing is watched. OcuTalon shows the results itself under your reply, with its own sentence that says whether everything passed, so
/// do not list them and do not say that everything passed. Anything else: the message says why the checks could not be read.
ClassMethod CheckStatus() As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) {
		If '##class(OcuTalon.Tools.WatchAnswers).EvalCheckResults(context, .results) Quit ..Return(refusal)
	} Else {
		Set refusal = ##class(OcuTalon.Tools.WatchAnswers).CheckResults(context.OwnerRef, .results)
		If $IsObject(refusal) Quit ..Return(refusal)
	}
	Do ##class(OcuTalon.Tools.WatchAnswers).PutChecks(results)
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Checked(results))
}

}
