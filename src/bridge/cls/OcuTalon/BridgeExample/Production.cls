/// The example production of the bridge (AD-2, AD-31, FR-5): a small production of its own, with nothing of OcuTalon, that makes a
/// decision through the bridge and routes on it. An item enters at ExampleItemIn (OcuTalon.BridgeExample.ItemIn Send):
///   - ExampleTriage renders the item and asks Decide for its decision;
///   - Decide, with every extension setting at its do-nothing default, sends the request to TriageAgent, an agent runner that runs
///     OcuTalon.BridgeExample.Agent (on its own allow-list) and checks the reply against OcuTalon.Bridge.Msg.DecisionPayload, and
///     AgentSteps records each step;
///   - ExampleRouter routes the decision by the rule OcuTalon.BridgeExample.Rule: a fallback to ExampleFallbackOut, tellnow and act to
///     ExampleNotifyOut, digest to ExampleDigestOut, and ignore nowhere. The three operations are of one class that logs the decision.
/// The definition holds the structure and the settings that wire it: the three settings of TriageAgent and the rule of the router. It
/// holds no Model, ProviderConfig, TimerSeconds or DecisionTokenBudget (AD-5, AD-19): a developer writes those as System Default
/// Settings of their own namespace, and a value in this definition would hide them. It does not enable the testing service. The
/// production is never started by an install, and it is never an autostart production.
Class OcuTalon.BridgeExample.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.BridgeExample.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="ExampleItemIn" ClassName="OcuTalon.BridgeExample.ItemIn" PoolSize="0" Enabled="true"/>
  <Item Name="ExampleTriage" ClassName="OcuTalon.BridgeExample.Triage" PoolSize="1" Enabled="true"/>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="true"/>
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.BridgeExample.Agent</Setting>
    <Setting Target="Adapter" Name="AgentAllowList">OcuTalon.BridgeExample.Agent</Setting>
    <Setting Target="Host" Name="ReplyClass">OcuTalon.Bridge.Msg.DecisionPayload</Setting>
  </Item>
  <Item Name="AgentSteps" ClassName="OcuTalon.Bridge.Operation.Steps" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleRouter" ClassName="EnsLib.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">OcuTalon.BridgeExample.Rule</Setting>
  </Item>
  <Item Name="ExampleNotifyOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleDigestOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
  <Item Name="ExampleFallbackOut" ClassName="OcuTalon.BridgeExample.Outcome" PoolSize="1" Enabled="true"/>
</Production>
}

}
