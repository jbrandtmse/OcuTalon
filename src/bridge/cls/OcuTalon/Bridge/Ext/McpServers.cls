/// The bridge's MCP servers extension (AD-31): the channel through which a runner learns which MCP servers its host has registered and reports
/// what became of each attach. The default names no server, so the bridge runs alone and attaches nothing (FR-5). A host extends this class and
/// names the subclass in the McpServersClass setting of the Decide item. The runner reads the setting in its own job when it builds its agent
/// (AD-6), after the gate is set, and a class that is missing or does not extend this base fails the build with that error (no silent fallback).
///   - Servers lists the servers to attach, each as {"server", "config"}: the host's name for the server and the name of its Config Store entry
///     (AI.MCP. followed by letters, digits and underscores). The runner attaches the entry as mcp:remote:@{config:<config>}, so the entry's url and
///     its credentials stay in the Config Store, and a name that does not match is reported as invalid and never attached.
///   - OnAttach receives one report per server, after that server was tried and before the next one: {"status", "reason", "tools", "refused"} and,
///     for an attached server, "fingerprints". status is attached or unavailable. reason is empty for an attached server and unreachable, failed or
///     invalid for an unavailable one. tools lists the names of the server's tools that were attached, and refused lists the names that were refused
///     because a tool with that name was already on the agent's manager. fingerprints is an object from each attached tool's name to its fingerprint
///     (OcuTalon.Bridge.Context ToolFingerprint of the tool's description and input schema), so that a host can tell that a tool changed. The report
///     holds code words, tool names and fingerprints only, never AI Hub's error text, which can name a URL or hold a credential.
///   - A failed or unavailable server never fails the build, and neither does an error from OnAttach: the runner logs it and goes on with the next server.
Class OcuTalon.Bridge.Ext.McpServers
{

/// The reasons of a report for a server that is unavailable, comma-separated.
Parameter REASONS = "unreachable,failed,invalid";

/// The servers to attach, as a %DynamicArray of {"server", "config"}. Gives none by default.
ClassMethod Servers(Output servers As %DynamicArray) As %Status
{
	Set servers = []
	Quit $$$OK
}

/// Receives the report of one attach. Returns OK and does nothing by default.
ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit $$$OK
}

}
