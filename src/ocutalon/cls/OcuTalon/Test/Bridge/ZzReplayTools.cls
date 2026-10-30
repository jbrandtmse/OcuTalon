/// The toolset of the replay tests (Story 30.3): zz_replay_send and zz_replay_throw, the methods Send and Throws of
/// OcuTalon.Test.Bridge.ZzReplayTool. A test fixture, never part of a production. The tool class compiles first (DependsOn), because the toolset's
/// generator reads the methods that the tools name.
Class OcuTalon.Test.Bridge.ZzReplayTools Extends %AI.ToolSet [ DependsOn = OcuTalon.Test.Bridge.ZzReplayTool ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonReplayTools">
  <Description>Risky tools that the replay tests approve and replay.</Description>
  <Tool Name="zz_replay_send" Class="OcuTalon.Test.Bridge.ZzReplayTool" Method="Send"/>
  <Tool Name="zz_replay_throw" Class="OcuTalon.Test.Bridge.ZzReplayTool" Method="Throws"/>
</ToolSet>
}

}
