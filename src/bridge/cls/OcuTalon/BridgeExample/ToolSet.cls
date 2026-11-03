/// The toolset of the bridge example's agent (AD-2, AD-6, FR-5): example_count_items, example_forward_item and example_archive_item, the
/// methods CountItems, ForwardItem and ArchiveItem of OcuTalon.BridgeExample.Tools. The tool class compiles first (DependsOn), because the
/// toolset's generator reads the methods that the tools name. The toolset holds no classification: the developer's ToolClassification
/// setting classifies the tools.
Class OcuTalon.BridgeExample.ToolSet Extends %AI.ToolSet [ DependsOn = OcuTalon.BridgeExample.Tools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BridgeExampleTools">
  <Description>Three tools of the bridge example: one that counts the example's items, and two that change something and may have to wait for a person's approval.</Description>
  <Tool Name="example_count_items" Class="OcuTalon.BridgeExample.Tools" Method="CountItems"/>
  <Tool Name="example_forward_item" Class="OcuTalon.BridgeExample.Tools" Method="ForwardItem"/>
  <Tool Name="example_archive_item" Class="OcuTalon.BridgeExample.Tools" Method="ArchiveItem"/>
</ToolSet>
}

}
