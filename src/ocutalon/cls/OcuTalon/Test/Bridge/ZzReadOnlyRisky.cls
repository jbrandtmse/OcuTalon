/// A toolset of the read-only rule's tests (Story 17.2; Decide.ToolsetsReadOnly): one tool of OcuTalon.Test.Bridge.ZzReadOnlyTool, a read-only tool classified risky. A test fixture,
/// never part of a production. The tool class compiles first (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzReadOnlyRisky Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzReadOnlyTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonReadOnlyRisky">
  <Description>A toolset of the read-only rule's tests.</Description>
  <Tool Name="zz_ro_risky" Class="OcuTalon.Test.Bridge.ZzReadOnlyTool" Method="RiskyLook"/>
</ToolSet>
}

}
