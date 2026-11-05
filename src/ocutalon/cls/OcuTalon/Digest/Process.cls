/// The Digest item (AD-18, AD-28, AD-30; Lane A): the daily digest of what OcuTalon watched. A business process that handles one
/// message and ends (AD-5) and keeps no private text in its properties (AD-3). THIS CLASS IS A STUB until Story 17.6: it carries STUB
/// and answers "not implemented" (code 5003) to every message, writes no row and sends nothing. The item is disabled in the production.
/// The contract it will keep (spine AD-18, "The daily digest"):
///   - it takes the Tick that Checks forwards after each tick's checks, and OcuTalon.Msg.Command.SendDigest from CommandsIn (Story 33.2),
///     and answers a CommandResult;
///   - on a tick, a session that has not ended is due when its latest digest.time has passed in the instance zone and its newest scheduled
///     OcuTalon.Digest.Data.Sent row's DueAt is earlier; the due time is checked under a lock before sending, so a digest missed while IRIS
///     was down goes once after the restart;
///   - its check rows come only from OcuTalon.Checks.Coverage.Build and its all-clear key only from OcuTalon.Checks.Render (AD-28);
///   - it calls Decide at most once per digest, a fresh unlinked untrusted turn on ChatAgent, only when items were saved for later (AD-30);
///   - it alone writes OcuTalon.Digest.Data.Sent, one row per digest sent, and sends one Notification of kind digest.
Class OcuTalon.Digest.Process Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet (Story 17.6).
Parameter STUB = 1;

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
