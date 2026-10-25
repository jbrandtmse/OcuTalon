/// The online demo's allowance (AD-20). A channel service asks TryConsume before it queues a message. Story 16.9 adds the
/// online-demo count, the per-session lock, the refused Turn and the notice; until then every message is allowed.
Class OcuTalon.Core.Allowance
{

/// Asks to consume one message of the session's allowance. Returns 1 when the message may be queued; retryAt is then "" and
/// firstRefusal 0. Returns 0 when it may not: retryAt is the UTC time when the session may send again and firstRefusal is 1
/// for the first refusal of a window. It never refuses yet. Conversation never calls it (AD-20).
ClassMethod TryConsume(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean
{
	Set retryAt = ""
	Set firstRefusal = 0
	Quit 1
}

}
