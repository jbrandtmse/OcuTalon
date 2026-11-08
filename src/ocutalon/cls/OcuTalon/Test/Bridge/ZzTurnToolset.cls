/// The toolset that OcuTalon.Test.Bridge.ZzTurnAdapter attaches in OnAfterAgentInit (Story 19.5): one read-only tool, zz_turn_set. A test fixture, never part of
/// a production. The tool class compiles first (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzTurnToolset Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzTurnTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonTurnToolset">
  <Description>A toolset that a test adapter attaches when it builds its agent.</Description>
  <Tool Name="zz_turn_set" Class="OcuTalon.Test.Bridge.ZzTurnTool" Method="Attached">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
