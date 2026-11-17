/// The one toolset of OcuTalon's own MCP server (Story 28.3; AD-10, AD-21): the read-only tools check_status and recent_activity, both methods of OcuTalon.Mcp.ServiceRead.
/// It is OcuTalon.Mcp.Service's SPECIFICATION, so it is the whole list of tools a developer's MCP client can be offered. It holds no Requirement element: the classification of a tool is
/// the provider's own declaration (class parameters), which Service ReadOnlyProblem reads with the gate's readers. The provider compiles first (DependsOn), because the toolset's
/// generator reads the methods that the tools name.
Class OcuTalon.Mcp.ServiceTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Mcp.ServiceRead ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonServer">
  <Description>Read-only tools that read your OcuTalon background check results and your recent incidents.</Description>
  <Tool Name="check_status" Class="OcuTalon.Mcp.ServiceRead" Method="CheckStatus"/>
  <Tool Name="recent_activity" Class="OcuTalon.Mcp.ServiceRead" Method="RecentActivity"/>
</ToolSet>
}

}
