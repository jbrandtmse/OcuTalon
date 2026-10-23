/// Maps (OwnerRef, agent) to an AI session; only the runner writes it, and only for turn requests with provenance user (AD-6). Lane A.
/// The agent of a link is the name of the runner item (ChatAgent in OcuTalon). The class also owns the conversation lock, so that the
/// runner and Decide cannot drift apart on its name:
///   - the lock is the incremental lock ^OcuTalonBP.Conv(OwnerRef, agent), the link's own unique key. The key exists before the first
///     turn creates the row, so two first turns cannot both create one. A plain LOCK is never used, because it would drop every other
///     lock that the job holds;
///   - the runner (Adapter.Agent) holds it from the open or creation of the AI session to the save, and releases it after the session
///     object is released. A turn that waits for it LOCKSECONDS is refused as busy (Reply.Busy);
///   - Decide takes it only to probe: it Locks and at once Unlocks, to learn whether an earlier turn, even one that Decide gave up on,
///     still holds the conversation (Process.Decide);
///   - Unlock runs outside any transaction.
/// Only the adapter calls Point and SessionOf. The adapter and Decide are the only callers of Lock and Unlock. No other product class
/// names this class.
Class OcuTalon.Bridge.Data.ConversationLink Extends %Persistent
{

/// How long a turn waits for the conversation lock, in seconds, before it is answered as busy (AD-6).
Parameter LOCKSECONDS = 2;

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.ConvLink";

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The agent of the conversation.
Property Agent As %String(MAXLEN = 32);

/// The AI session's id.
Property SessionId As %String(MAXLEN = 128);

Index OwnerRefAgentIndex On (OwnerRef, Agent) [ Unique ];

/// The id of the AI session that the link of the owner and the agent names, or "" when there is no link.
ClassMethod SessionOf(ownerRef As %String, agent As %String) As %String
{
	If (ownerRef = "") || (agent = "") || '..OwnerRefAgentIndexExists(ownerRef, agent, .id) Quit ""
	Quit ..SessionIdGetStored(id)
}

/// Makes the link of the owner and the agent name the AI session: creates the row, or updates the SessionId of the row that exists.
/// This is the only writer of the class. The caller holds the conversation lock (Lock).
ClassMethod Point(ownerRef As %String, agent As %String, sessionId As %String) As %Status
{
	If ownerRef = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an OwnerRef")
	If agent = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an agent")
	If sessionId = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an AI session id")
	Set link = ..OwnerRefAgentIndexOpen(ownerRef, agent)
	If '$IsObject(link) {
		Set link = ..%New()
		Set link.OwnerRef = ownerRef
		Set link.Agent = agent
	}
	Set link.SessionId = sessionId
	Quit link.%Save()
}

/// Takes the conversation lock of the owner and the agent, waiting up to seconds (LOCKSECONDS by default). 1 when it is taken, 0 when
/// it is not. The lock is incremental: each Lock that returns 1 is paired with one Unlock.
ClassMethod Lock(ownerRef As %String, agent As %String, seconds As %Integer = {..#LOCKSECONDS}) As %Boolean
{
	Lock +^OcuTalonBP.Conv(ownerRef, agent):seconds
	Quit $Test
}

/// Releases one hold of the conversation lock of the owner and the agent. Call it outside any transaction, so that the release is not
/// deferred to the end of one.
ClassMethod Unlock(ownerRef As %String, agent As %String)
{
	Lock -^OcuTalonBP.Conv(ownerRef, agent)
}

Storage Default
{
<Data name="ConversationLinkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OwnerRef</Value>
</Value>
<Value name="3">
<Value>Agent</Value>
</Value>
<Value name="4">
<Value>SessionId</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.ConvLinkD</DataLocation>
<DefaultData>ConversationLinkDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.ConvLinkD</IdLocation>
<IndexLocation>^OcuTalonBP.ConvLinkI</IndexLocation>
<StreamLocation>^OcuTalonBP.ConvLinkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
