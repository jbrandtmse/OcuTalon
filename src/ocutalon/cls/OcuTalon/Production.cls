/// The OcuTalon production (AD-3, AD-29, AD-33): every release-1 item, each between the markers of the lane that owns
/// it. The ProductionDefinition block below is the only one IRIS loads, and a save from the portal rewrites it whole and
/// drops the markers, so the definition is edited only here, and each lane edits only its own region.
/// The XData holds structure only (AD-5): the items, their classes, pool sizes and enabled flags, the agent class of
/// each runner, the rule of each router and the extension classes of Decide. Values that change, such as the models and
/// the EvalIn switch, are System Default Settings. An adapterless service has pool size 0 and runs no job. The
/// production is never marked autostart on the Docker path: the Production installer step starts it (AD-23).
Class OcuTalon.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>2</ActorPoolSize>
  <!-- lane A: begin -->
  <Item Name="TelegramIn" ClassName="OcuTalon.Channel.Telegram.In" PoolSize="1" Enabled="false"/>
  <Item Name="TelegramOut" ClassName="OcuTalon.Channel.Telegram.Out" PoolSize="1" Enabled="false"/>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="HostSinkClass">OcuTalon.Core.BridgeSink</Setting>
    <Setting Target="Host" Name="ReplyFilterClass">OcuTalon.Checks.ReplyGuard</Setting>
  </Item>
  <Item Name="ApprovalHold" ClassName="OcuTalon.Bridge.Process.ApprovalHold" PoolSize="1" Enabled="true"/>
  <Item Name="ApprovalStartIn" ClassName="OcuTalon.Bridge.Service.ApprovalStart" PoolSize="0" Enabled="true"/>
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Triage</Setting>
  </Item>
  <Item Name="DiagnosisAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Diagnosis</Setting>
  </Item>
  <Item Name="ChatAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Chat</Setting>
  </Item>
  <Item Name="AgentSteps" ClassName="OcuTalon.Bridge.Operation.Steps" PoolSize="1" Enabled="true"/>
  <Item Name="OcuTalonApprovals" ClassName="EnsLib.Workflow.Operation" PoolSize="1" Enabled="true"/>
  <Item Name="FailurePoller" ClassName="OcuTalon.Watch.FailurePoller" PoolSize="0" Enabled="true"/>
  <Item Name="IncidentManager" ClassName="OcuTalon.Watch.IncidentManager" PoolSize="1" Enabled="true"/>
  <Item Name="WatchOps" ClassName="OcuTalon.Watch.Ops" PoolSize="1" Enabled="true"/>
  <Item Name="EvalIn" ClassName="OcuTalon.Eval.In" PoolSize="0" Enabled="false"/>
  <Item Name="EvalSink" ClassName="OcuTalon.Eval.Sink" PoolSize="1" Enabled="true"/>
  <Item Name="FixExecutor" ClassName="OcuTalon.Fix.Executor" PoolSize="1" Enabled="true"/>
  <Item Name="Checks" ClassName="OcuTalon.Checks.Process" PoolSize="1" Enabled="true"/>
  <Item Name="DigestStore" ClassName="OcuTalon.Digest.Store" PoolSize="1" Enabled="true"/>
  <!-- lane A: end -->
  <!-- lane B: begin -->
  <Item Name="WebChatIn" ClassName="OcuTalon.Channel.WebChat.In" PoolSize="0" Enabled="true"/>
  <Item Name="WebChatOut" ClassName="OcuTalon.Channel.WebChat.Out" PoolSize="1" Enabled="true"/>
  <Item Name="SimMailboxIn" ClassName="OcuTalon.Channel.SimMailbox.In" PoolSize="0" Enabled="true"/>
  <Item Name="SimMailboxOut" ClassName="OcuTalon.Channel.SimMailbox.Out" PoolSize="1" Enabled="true"/>
  <Item Name="SimPhoneOut" ClassName="OcuTalon.Channel.SimPhone.Out" PoolSize="1" Enabled="true"/>
  <Item Name="AnswersIn" ClassName="OcuTalon.Core.AnswersIn" PoolSize="0" Enabled="true"/>
  <Item Name="CommandsIn" ClassName="OcuTalon.Core.CommandsIn" PoolSize="0" Enabled="true"/>
  <Item Name="NoticesIn" ClassName="OcuTalon.Core.NoticesIn" PoolSize="0" Enabled="true"/>
  <Item Name="StatusMonitor" ClassName="OcuTalon.Core.StatusMonitor" PoolSize="0" Enabled="true"/>
  <Item Name="Conversation" ClassName="OcuTalon.Core.Conversation" PoolSize="1" Enabled="true"/>
  <Item Name="Intake" ClassName="OcuTalon.Core.Intake" PoolSize="1" Enabled="true"/>
  <Item Name="OutcomeRouter" ClassName="EnsLib.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">OcuTalon.Core.Rule.Outcome</Setting>
  </Item>
  <Item Name="Notify" ClassName="EnsLib.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">OcuTalon.Core.Rule.Notify</Setting>
  </Item>
  <Item Name="SessionOps" ClassName="OcuTalon.Core.SessionOps" PoolSize="1" Enabled="true"/>
  <Item Name="SettingsOps" ClassName="OcuTalon.Core.SettingsOps" PoolSize="1" Enabled="true"/>
  <Item Name="HeartbeatIn" ClassName="OcuTalon.Schedule.HeartbeatIn" PoolSize="0" Enabled="true"/>
  <Item Name="ReminderOps" ClassName="OcuTalon.Schedule.ReminderOps" PoolSize="1" Enabled="true"/>
  <Item Name="ReminderTimer" ClassName="OcuTalon.Schedule.ReminderTimer" PoolSize="1" Enabled="true"/>
  <Item Name="BreakFeedIn" ClassName="OcuTalon.Demo.BreakFeedIn" PoolSize="0" Enabled="true"/>
  <Item Name="PartnerTrigger" ClassName="OcuTalon.Demo.PartnerTrigger" PoolSize="1" Enabled="true"/>
  <!-- lane B: end -->
</Production>
}

}
