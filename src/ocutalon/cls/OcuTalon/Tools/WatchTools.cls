/// The methods behind OcuTalon.Tools.Watching (AD-1, AD-3, AD-4, AD-9, AD-10, AD-18): the three watch tools of the Chat agent, start_watch,
/// stop_watch and list_productions. start_watch and stop_watch resolve the name the user gave through OcuTalon.Watch.Reader, the only reader of
/// the productions, and submit StartWatch or StopWatch through OcuTalon.Tools.CommandCall, so the tools never write a watch themselves:
/// WatchOps owns the BackgroundCheck rows and checks every start again. stop_watch reads the session's own watches through the ownership API
/// (OcuTalon.Data.Ownership.Checks) before it asks the reader, so that a watch on a production the reader no longer lists can still be stopped. The session comes from the bridge context of the call, never from an
/// argument. list_productions reads the reader's list and submits nothing.
///   - A call that is not a session's turn answers NOSESSION before anything is read or submitted.
///   - A name that no production matches submits nothing and answers unknown_production with the name, the list of the names that can be watched
///     (joined with a comma and with "and" before the last one) and each production's name and namespace. On the online demo it answers
///     only_orders with the README link instead. A name that two productions match answers ambiguous with each one's name and namespace, and
///     the optional namespace argument picks one.
///   - A name that one production matches is submitted. The answer is CommandCall.Answer with the outcome (started, already_watching, stopped,
///     not_watching, or the owner's refusal) and the production's display name added.
/// The answers carry the outcome and the values to say, never the sentence: the Chat agent's instructions hold the sentences (AD-32). The shaping
/// of the answers is OcuTalon.Tools.WatchAnswers, because a tool provider returns only through Return.
/// Each tool declares, by the naming rule of ReminderTools (the tool's name in upper case with _ and - removed), its step label (AD-9) and its
/// classification for the gate (AD-10). All three are safe and trusted output: their answers are built in code from the owner's CommandResult
/// and from IRIS's production registry, so no content from outside the instance reaches the model through them, and a result never taints the
/// turn (a start_watch after a list_productions in one turn still runs). start_watch and stop_watch are not read-only, so the gate denies them
/// in an untrusted or tainted turn; list_productions is read-only, so it also runs there.
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

Parameter CLASSIFICATIONSTARTWATCH = "safe";

Parameter READONLYSTARTWATCH = 0;

Parameter TRUSTEDOUTPUTSTARTWATCH = 1;

Parameter CLASSIFICATIONSTOPWATCH = "safe";

Parameter READONLYSTOPWATCH = 0;

Parameter TRUSTEDOUTPUTSTOPWATCH = 1;

Parameter CLASSIFICATIONLISTPRODUCTIONS = "safe";

Parameter READONLYLISTPRODUCTIONS = 1;

Parameter TRUSTEDOUTPUTLISTPRODUCTIONS = 1;

/// Starts watching a production for the user in this conversation: a background check that tells the user only when something needs them.
/// Call it directly with the name the user gave, such as Orders. The answer has an outcome. started: the watch is on, and production is the
/// name to say. already_watching: the user already watches it. unknown_production: no production has that name, and the answer gives the list
/// of names to offer. only_orders: this is the online demo, which watches only the Orders production. ambiguous: two productions have that
/// name, so ask the user which one they meant. Anything else: the message says why nothing was done.
ClassMethod StartWatch(name As %String(DESCRIPTION = "The name of the production, exactly as the user gave it, such as Orders."), namespace As %String(DESCRIPTION = "Only when an earlier answer was ambiguous: the namespace of the production that the user picked. Otherwise leave it out.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session()
	If $IsObject(refusal) Quit ..Return(refusal)
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
ClassMethod StopWatch(name As %String(DESCRIPTION = "The name of the production, exactly as the user gave it, such as Orders."), namespace As %String(DESCRIPTION = "Only when an earlier answer was ambiguous: the namespace of the production that the user picked. Otherwise leave it out.") = "") As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set refusal = ##class(OcuTalon.Tools.WatchAnswers).ResolveStop(name, namespace, context.OwnerRef, .match)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set command.Namespace = match.namespace
	Set command.Production = match.production
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Submitted(result, match))
}

/// Lists the productions that can be watched: each one's name and namespace. Use it to answer which productions OcuTalon can watch. It starts
/// nothing.
ClassMethod ListProductions() As %DynamicObject
{
	Quit ..Return(##class(OcuTalon.Tools.WatchAnswers).Listed(##class(OcuTalon.Watch.Reader).Productions()))
}

}
