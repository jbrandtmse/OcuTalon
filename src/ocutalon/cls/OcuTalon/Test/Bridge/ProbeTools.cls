/// The toolset of the context probe (Story 1.2): one tool, zz_context_probe, which is the method Probe of
/// OcuTalon.Test.Bridge.ProbeTool. A test fixture, never part of a production. ProbeTool compiles first (DependsOn), because the
/// toolset's generator reads the method that the tool names.
Class OcuTalon.Test.Bridge.ProbeTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ProbeTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonContextProbe">
  <Description>One tool that records what the context of the call holds.</Description>
  <Tool Name="zz_context_probe" Class="OcuTalon.Test.Bridge.ProbeTool" Method="Probe"/>
</ToolSet>
}

}
