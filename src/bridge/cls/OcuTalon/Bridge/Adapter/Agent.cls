/// The adapter of the agent runners (AD-6). It extends AI Hub's outbound agent adapter and calls nothing in AI Hub at start,
/// so the runner items start and run with no model key (FR-38). Story 1.2 builds the agent on first use.
Class OcuTalon.Bridge.Adapter.Agent Extends EnsLib.AI.Agent.OutboundAdapter
{

/// Calls nothing in AI Hub and returns OK.
Method OnInit() As %Status [ Internal ]
{
	Quit $$$OK
}

}
