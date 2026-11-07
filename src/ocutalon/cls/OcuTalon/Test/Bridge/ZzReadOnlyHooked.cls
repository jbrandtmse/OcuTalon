/// A toolset of the read-only rule's tests (Story 17.2; Decide.ToolsetsReadOnly): one tool of OcuTalon.Test.Bridge.ZzReadOnlyTool, a safe, read-only tool with a per-call classification. A test fixture,
/// never part of a production. The tool class compiles first (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzReadOnlyHooked Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzReadOnlyTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonReadOnlyHooked">
  <Description>A toolset of the read-only rule's tests.</Description>
  <Tool Name="zz_ro_hooked" Class="OcuTalon.Test.Bridge.ZzReadOnlyTool" Method="HookedLook"/>
</ToolSet>
}

}
