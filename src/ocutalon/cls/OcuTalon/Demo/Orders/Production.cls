/// The Orders production (Story 0.10, AD-3): the demo's production to watch and break, in namespace OCUORDERS, which the Demo
/// installer step creates with demo mode on and starts. It is not autostart. PartnerOrdersIn is the simulated partner, a service
/// with no job that Partner.Send drives; OrdersFromPartner runs the transform, so an order whose date is not YYYY-MM-DD fails
/// there; OrdersToWarehouse takes the orders that pass. The description "Orders" is what the watch lists match (Story 5.1).
/// The XData holds structure only (AD-5).
Class OcuTalon.Demo.Orders.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="OcuTalon.Demo.Orders.Production" TestingEnabled="false">
  <Description>Orders</Description>
  <Item Name="PartnerOrdersIn" ClassName="OcuTalon.Demo.Orders.Partner" PoolSize="0" Enabled="true">
    <Setting Target="Host" Name="TargetConfigName">OrdersFromPartner</Setting>
  </Item>
  <Item Name="OrdersFromPartner" ClassName="OcuTalon.Demo.Orders.Translator" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="TargetConfigName">OrdersToWarehouse</Setting>
  </Item>
  <Item Name="OrdersToWarehouse" ClassName="OcuTalon.Demo.Orders.Warehouse" PoolSize="1" Enabled="true"/>
</Production>
}

}
