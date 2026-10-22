/// The toolset of the step tests (Story 1.5): zz_steps_note, the method Read of OcuTalon.Test.Bridge.StepsNote, and zz_steps_card, the
/// method Read of OcuTalon.Test.Bridge.StepsCard. Both are read-only. A test fixture, never part of a production. The tool classes compile
/// first (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.StepsTools Extends %AI.ToolSet [ DependsOn = (OcuTalon.Test.Bridge.StepsNote, OcuTalon.Test.Bridge.StepsCard) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonStepsTools">
  <Description>Two read-only tools that read a test note and a test card.</Description>
  <Tool Name="zz_steps_note" Class="OcuTalon.Test.Bridge.StepsNote" Method="Read">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="zz_steps_card" Class="OcuTalon.Test.Bridge.StepsCard" Method="Read">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
