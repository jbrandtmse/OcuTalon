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
///     (OcuTalon.Bridge.Context ToolFingerprint of the tool's toolref, name, description and input schema), so that a host can tell that a tool changed. The report
///     holds code words, tool names and fingerprints only, never AI Hub's error text, which can name a URL or hold a credential.
///   - Probe asks whether a server answers, before the runner adds the server's tools to a tool manager, at the build and again for each request that composes a
///     manager, always in the runner's job and outside every callback (AD-6). It returns "" when the server answers and otherwise one word of REASONS (any other
///     answer, and an exception, count as failed). AI Hub's own client has no deadline, so a server that accepts a connection and never answers would hold the
///     job for minutes: an answer that says no keeps that server's tools off the manager. It must return within a few seconds and must not call AI Hub. It returns
///     "" by default, which is no probe, so that the bridge alone, which names no server, is unchanged. A host that lists servers overrides it. The runner rests
///     a server that failed the probe (RESTSECONDS of the adapter) before it asks again.
///   - ToolsReadOnly says whether every tool of a server that a runner can call is classified read-only, so that Decide may retry a timed-out request whose
///     agent has such servers (AD-8). The default says no.
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

/// Asks whether the server answers (see the class description): "" when it does, else a word of REASONS. Gives "" by default, which is no probe. server is the
/// host's name for the server and config the name of its Config Store entry, as Servers gave them.
ClassMethod Probe(server As %String, config As %String) As %String
{
	Quit ""
}

/// Receives the report of one attach. Returns OK and does nothing by default.
ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit $$$OK
}

/// 1 only when every tool of the server that a runner can call is classified read-only, so that an attempt in which one ran, and whose outcome is unknown
/// because its timer fired, changed nothing. A server that is unavailable, was never attached or is not known counts as 0. Decide asks it, in its own job, for each
/// server that Servers lists (AD-8). Returns 0 by default.
ClassMethod ToolsReadOnly(server As %String) As %Boolean
{
	Quit 0
}

}
