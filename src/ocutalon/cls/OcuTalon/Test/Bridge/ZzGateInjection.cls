/// The toolset of the provenance and taint tests (Story 3.3; AD-10): the seven tools of OcuTalon.Test.Bridge.ZzGateTool that the injection cases
/// need, in a toolset of their own because OcuTalon.Test.Bridge.ZzGateTools is the governance sample of Test.Bridge.Gate (TestGovernanceSample),
/// and more tools there would change its run and flag sets. A test fixture, never part of a production. The tool class compiles first
/// (DependsOn), because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzGateInjection Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzGateTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonGateInjection">
  <Description>Tools that the provenance and taint tests of the gate call.</Description>
  <Tool Name="zz_gate_read" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ReadOutside"/>
  <Tool Name="zz_gate_trusted" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ReadOwn"/>
  <Tool Name="zz_gate_risky_read" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="RiskyRead"/>
  <Tool Name="zz_resend_failed" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ResendFailed"/>
  <Tool Name="zz_change_endpoint" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ChangeEndpoint"/>
  <Tool Name="zz_approve_requests" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="ApproveRequests"/>
  <Tool Name="zz_gate_note" Class="OcuTalon.Test.Bridge.ZzGateTool" Method="Note"/>
</ToolSet>
}

}
