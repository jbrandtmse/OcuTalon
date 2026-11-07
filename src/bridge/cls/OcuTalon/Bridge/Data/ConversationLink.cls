/// Maps (OwnerRef, agent) to an AI session; only Decide writes it, on accepting a reply, and only for turn requests with provenance user (AD-6). Lane A.
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
/// Only Decide calls Point, which writes the link (Process.Decide PointLink), and only when it accepts a reply as the decision's answer (AD-6, AD-8): it is
/// the compare-and-set below, expecting the session that the runner began the turn from. The form with no expected argument has no product caller and is kept
/// for test fixtures. The adapter only reads the link (SessionOf) and takes the conversation lock (Lock, Unlock); Decide also calls Lock and Unlock to probe
/// and SessionOf to size the stored history of a turn that continues a conversation (RequestSize) and to seed the second-model retry. No other
/// product class names this class, except Bridge.Purge, which reads the SessionId of every link through one SELECT to tell which AI sessions are still
/// named, and writes nothing.
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

/// Makes the link of the owner and the agent name the AI session: creates the row, or updates the SessionId of the row that exists. This is
/// the only writer of the class, and Decide (PointLink) the only product caller.
///   - With expected, even "", Point is a compare-and-set: under the lock of the link row itself (the row's ID node, never the conversation
///     lock), the link moves only while it still names expected ("" for a link that does not exist). moved says whether it moved. Decide passes
///     the session the runner began the turn from (the reply's SessionFrom), so a stale attempt never overwrites a newer link.
///   - With no expected argument the link moves unconditionally. That form has no product caller; test fixtures use it.
/// A link row that exists is changed under its lock in both forms, so a compare and a write never interleave with the other form's write; a link
/// that does not exist is created without one, and the unique index lets one creator win while the other tries again against the row that now exists.
/// The status is an error when an unconditional write did not happen.
ClassMethod Point(ownerRef As %String, agent As %String, sessionId As %String, expected As %String, Output moved As %Boolean) As %Status
{
	Set moved = 0
	If ownerRef = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an OwnerRef")
	If agent = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an agent")
	If sessionId = "" Quit $$$ERROR($$$GeneralError, "A conversation link needs an AI session id")
	Set compare = $Data(expected)
	Set sc = $$$OK
	For attempt = 1:1:2 {
		Set exists = ..OwnerRefAgentIndexExists(ownerRef, agent, .id)
		If exists {
			Lock +^OcuTalonBP.ConvLinkD(id):..#LOCKSECONDS
			If '$Test {
				Set sc = $$$ERROR($$$GeneralError, "The conversation link row is locked by another process, so it is not moved")
				Quit
			}
			Set link = ..%OpenId(id, , .sc)
			If $$$ISERR(sc) || (compare && (link.SessionId '= $Get(expected))) {
				Lock -^OcuTalonBP.ConvLinkD(id)
				Quit
			}
		} Else {
			If compare && ($Get(expected) '= "") Quit
			Set link = ..%New()
			Set link.OwnerRef = ownerRef
			Set link.Agent = agent
		}
		Set link.SessionId = sessionId
		Set sc = link.%Save()
		If exists Lock -^OcuTalonBP.ConvLinkD(id)
		If $$$ISOK(sc) {
			Set moved = 1
			Quit
		}
		If exists || '..OwnerRefAgentIndexExists(ownerRef, agent) Quit
		Set sc = $$$OK
	}
	If $$$ISOK(sc) && 'moved && 'compare Set sc = $$$ERROR($$$GeneralError, "The conversation link was not written, because another process wrote it first")
	Quit sc
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
