/// The toolset of the tool that OcuTalon.Test.Bridge.ZzTurnTools adds to one request (Story 19.5): one read-only tool, zz_turn_probe. A test fixture, never part
/// of a production. The tool class compiles first (DependsOn).
Class OcuTalon.Test.Bridge.ZzTurnProbeTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzTurnTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonTurnProbeTools">
  <Description>A toolset that a test TurnToolsClass adds to one request.</Description>
  <Tool Name="zz_turn_probe" Class="OcuTalon.Test.Bridge.ZzTurnTool" Method="Probe">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
