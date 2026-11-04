/// The toolset of the tool result tests (Story 1.9): zz_result_text and zz_result_object, the methods Text and Object of
/// OcuTalon.Test.Tools.ZzResultTool, which answer a text and a dynamic object of the asked number of characters through the shared base of
/// the built-in tools. Both are read-only. A test fixture, never part of a production. The tool class compiles first (DependsOn), because the
/// toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Tools.ZzResultTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Tools.ZzResultTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonResultTools">
  <Description>Two read-only tools that answer a test text and a test object of the asked length.</Description>
  <Tool Name="zz_result_text" Class="OcuTalon.Test.Tools.ZzResultTool" Method="Text">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="zz_result_object" Class="OcuTalon.Test.Tools.ZzResultTool" Method="Object">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
