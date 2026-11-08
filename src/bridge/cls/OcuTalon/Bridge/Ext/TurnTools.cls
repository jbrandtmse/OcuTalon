/// The bridge's per-request tools extension (AD-31): gives one request tools of its own, such as a knowledge base of the owner's documents. The
/// default gives none, so the bridge runs alone (FR-5). A host extends this class and names the subclass in the TurnToolsClass setting of the Decide
/// item. The runner reads the setting in its own job, once for each request, before the AI session opens (AD-6), and calls Tools.
///   - Each object in tools answers AddToManager(manager As %AI.ToolMgr) As %Status, as AI Hub's %AI.RAG.KnowledgeBase does, and the runner keeps
///     it referenced until the request ends, so an object that owns a native handle stays alive for the whole request.
///   - When Tools gives no object, the request keeps the agent's own tool manager, and no request ever adds a tool to it.
///   - When it gives any, the runner builds a new tool manager for that request with the agent's own tools, the tools that the adapter attached
///     when the agent was built, these tools, the gate and the step audit policy (AD-10), and puts the agent's own manager back when the
///     request ends. An agent that declares skills cannot take tools of its own this way, and the request fails naming the agent.
///   - Tools runs in the runner's job, outside every AI Hub callback. It makes no change to the data it reads, and a failure it cannot hide is an
///     error status, which ends the request with that status.
Class OcuTalon.Bridge.Ext.TurnTools
{

/// The tools of the request of kind (turn, decide or diagnose) for ownerRef, the owner of the conversation (empty for a request with none). tools
/// is a %ListOfObjects, empty when the request has none of its own. Returns OK, or the error that ends the request. Gives none by default.
ClassMethod Tools(ownerRef As %String, kind As %String, Output tools As %ListOfObjects) As %Status
{
	Set tools = ##class(%ListOfObjects).%New()
	Quit $$$OK
}

}
