/// The governed proxy that a request offers when an MCP server is attached to its tool manager (Story 22.3; AD-10, AD-21): the tool call_mcp_tool, which is a method of
/// OcuTalon.Tools.McpCall (the one declaration of the step label, the classification and the answers). McpCall compiles first (DependsOn), because the toolset's generator reads
/// the method that the tool names. The toolset is in no agent's TOOLSETS: OcuTalon.Mcp.Attach names it through ProxyToolSet, and the runner registers it on the tool manager
/// of a request that holds an MCP server.
Class OcuTalon.Tools.McpProxy Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.McpCall ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonMcpProxy">
  <Tool Name="call_mcp_tool" Class="OcuTalon.Tools.McpCall" Method="CallMcpTool"/>
</ToolSet>
}

}
