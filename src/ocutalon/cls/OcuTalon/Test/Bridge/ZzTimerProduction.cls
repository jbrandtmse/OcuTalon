/// A production that only the tests of Timeouts.Apply read (Story 1.7; AD-5, AD-8): its Decide sets TimerSeconds in the production definition, so
/// a System Default Settings row of that setting cannot take effect, and its TriageAgent names the Config Store entry of the product's Triage
/// runner. Every item is disabled and the production is never started.
Class OcuTalon.Test.Bridge.ZzTimerProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Test.Bridge.ZzTimerProduction" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="false">
    <Setting Target="Host" Name="TimerSeconds">45</Setting>
  </Item>
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="false">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Triage</Setting>
    <Setting Target="Adapter" Name="ProviderConfig">@{config:OcuTalonTriage}</Setting>
  </Item>
</Production>
}

}
