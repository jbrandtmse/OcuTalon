/// The example production of the bridge (AD-2, AD-31, FR-5): the three items that the bridge needs and nothing of OcuTalon.
///   - Decide, with every extension setting at its do-nothing default;
///   - TriageAgent, an agent runner that runs OcuTalon.BridgeExample.Agent (on its own allow-list) and checks the reply
///     against OcuTalon.Bridge.Msg.DecisionPayload;
///   - AgentSteps.
/// The definition holds structure only (AD-5). It sets no provider setting and does not enable the testing service: a
/// developer sets the runner's ProviderConfig, and the production's TestingEnabled if they want to send a request through
/// EnsLib.Testing.Service, as System Default Settings of their own namespace (AD-19). The production is never started by
/// an install, and it is never an autostart production.
Class OcuTalon.BridgeExample.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.BridgeExample.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="true"/>
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.BridgeExample.Agent</Setting>
    <Setting Target="Adapter" Name="AgentAllowList">OcuTalon.BridgeExample.Agent</Setting>
    <Setting Target="Host" Name="ReplyClass">OcuTalon.Bridge.Msg.DecisionPayload</Setting>
  </Item>
  <Item Name="AgentSteps" ClassName="OcuTalon.Bridge.Operation.Steps" PoolSize="1" Enabled="true"/>
</Production>
}

}
