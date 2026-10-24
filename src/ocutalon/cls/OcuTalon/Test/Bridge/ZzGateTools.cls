/// The toolset of the gate tests (Story 3.2): the tools of OcuTalon.Test.Bridge.ZzGateTool, and set_reminder, the name of a built-in tool, as
/// the method Shadow of that class. A test fixture, never part of a production. The tool class compiles first (DependsOn), because the
/// toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzGateTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzGateTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonGateTools">
  <Description>Tools that the gate tests classify in different ways.</Description>
  <Tool Name="zz_gate_risky" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Risky"/>
  <Tool Name="zz_gate_safe" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Safe"/>
  <Tool Name="zz_gate_held" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Held"/>
  <Tool Name="zz_gate_args" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Args"/>
  <Tool Name="zz_gate_throw" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Throws"/>
  <Tool Name="zz_gate_public" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="PublicRead"/>
  <Tool Name="zz_gate_write" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ReadWrite"/>
  <Tool Name="zz_gate_admin" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Admin"/>
  <Tool Name="set_reminder" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Shadow"/>
</ToolSet>
}

}
