/// The method behind OcuTalon.Tools.McpProxy (AD-6, AD-9, AD-10, AD-21, NFR-3): the tool call_mcp_tool of Story 22.3, the one way a call reaches an MCP server. The gate
/// rewrites every allowed native MCP call into a call of it, and classifies a direct call of it exactly as the native call of the same server and tool; the work is
/// OcuTalon.Mcp.Proxy's (the demo refusal, the fingerprint compared again just before the call, OcuTalon's own bounded client, one audit entry).
///   - It answers the text of the tool's result, passed through Result.Return so that the results of the model step stay within the room of the step, and cut and marked as cut
///     when they do not fit; or one of the sentences MCPCHANGED, MCPFAILED, MCPTIMEOUT and MCPDEMO, which hold no text of the server, no url and no argument.
///   - The classification the gate gives a call of this tool is per call (the admin's classification of the server's tool, Gate FromProxy), so the parameters below are only the
///     static facts that the security overview shows and the fallback of a tool that is classified by name: the tool is risky and not read-only. TRUSTEDOUTPUT is 0: an MCP
///     result is never trusted, and the gate taints the turn when it allows the call.
///   - ClassifyCALLMCPTOOL is the hook that makes the overview show the rule of CLASSIFYRULECALLMCPTOOL instead of a static word. The gate never calls it: it classifies the
///     proxy before it looks for a hook.
/// A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no Python call (AD-6); the hook is Internal, because a public method of a tool
/// class becomes a tool, and a tool class quits a value only through ..Return. The description of a tool is its method's doc comment, and an argument's DESCRIPTION is what the model reads about it: they are text for the model.
Class OcuTalon.Tools.McpCall Extends OcuTalon.Tools.Result
{

Parameter STEPLABELCALLMCPTOOL = "Running an MCP tool";

Parameter CLASSIFICATIONCALLMCPTOOL = "risky";

Parameter READONLYCALLMCPTOOL = 0;

Parameter TRUSTEDOUTPUTCALLMCPTOOL = 0;

/// The rule that the security overview shows after "per call: ".
Parameter CLASSIFYRULECALLMCPTOOL = "the admin's classification of the server's tool at its current fingerprint; unclassified counts as risky";

/// The answer for a tool that changed since an admin classified it, or that the server no longer lists. Nothing was run.
Parameter MCPCHANGED = "this MCP tool changed since it was classified, so nothing was run; an admin must classify it again.";

/// The answer for a server that could not run the tool (not registered, not reachable, an error). There is no result.
Parameter MCPFAILED = "the MCP server could not run this tool, so there is no result.";

/// The answer for a server that did not answer in time.
Parameter MCPTIMEOUT = "the MCP server did not answer in time, so there is no result.";

/// The answer on the online demo, where no MCP server runs. Nothing was run.
Parameter MCPDEMO = "MCP tools are not available on the online demo, so nothing was run.";

/// Runs a tool of a registered MCP server through OcuTalon's governed proxy.
ClassMethod CallMcpTool(server As %String(DESCRIPTION = "The MCP server's name."), tool As %String(DESCRIPTION = "The tool's name on that server."), arguments As %DynamicObject(DESCRIPTION = "The tool's input, as a JSON object.") = "") As %Any
{
	Set used = 0
	If ##class(OcuTalon.Bridge.Context).Active() Set used = +##class(OcuTalon.Bridge.Context).Current().ToolResultChars
	Set answer = ##class(OcuTalon.Mcp.Proxy).Call(server, tool, arguments, ..Room() - used)
	If answer.%GetTypeOf("text") = "string" Quit ..Return(answer.text)
	Quit ..Return($Case(answer.%Get("refusal"), "changed": ..#MCPCHANGED, "timeout": ..#MCPTIMEOUT, "demo": ..#MCPDEMO, : ..#MCPFAILED))
}

/// The hook that gives the security overview the rule of this tool; the gate classifies a call of the proxy itself and never calls it.
ClassMethod ClassifyCALLMCPTOOL(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit ..Return("risky")
}

}
