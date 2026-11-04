/// The toolset of the grant tests (Story 3.1): alpha, beta and gamma, the methods of OcuTalon.Test.Install.ZzGrantTools. A test fixture, never
/// part of a production. The tool class compiles first (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Install.ZzGrantToolset Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Install.ZzGrantTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonZzGrant">
  <Description>Three tools that do nothing, for the tests of the grants that tools declare.</Description>
  <Tool Name="alpha" Class="OcuTalon.Test.Install.ZzGrantTools" Method="Alpha"/>
  <Tool Name="beta" Class="OcuTalon.Test.Install.ZzGrantTools" Method="Beta"/>
  <Tool Name="gamma" Class="OcuTalon.Test.Install.ZzGrantTools" Method="Gamma"/>
</ToolSet>
}

}
