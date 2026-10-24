/// A production that only Test.Bridge.Timeouts.TestApplyStopped reads (Story 1.7; AD-5, AD-19): its Decide sets no TimerSeconds, so a System
/// Default Settings row of that setting takes effect, and its TriageAgent names a Config Store entry that the test creates (OcuTalonZzStopped).
/// Every item is disabled and the production is never started.
Class OcuTalon.Test.Bridge.ZzStoppedProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Test.Bridge.ZzStoppedProduction" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Decide" ClassName="OcuTalon.Bridge.Process.Decide" PoolSize="1" Enabled="false"/>
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="false">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Triage</Setting>
    <Setting Target="Adapter" Name="ProviderConfig">@{config:OcuTalonZzStopped}</Setting>
  </Item>
</Production>
}

}
