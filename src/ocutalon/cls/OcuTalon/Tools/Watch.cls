/// The read-only watch tools that the Diagnosis agent offers (AD-7): read_failed_messages, read_event_log and
/// read_item_settings. Each tool is a method of OcuTalon.Tools.WatchReads and is declared ReadOnly, so that a policy
/// can tell it from a tool that changes something. The methods read the incident of the bridge context. WatchReads compiles first (DependsOn),
/// because the toolset's generator reads the methods that the tools name.
Class OcuTalon.Tools.Watch Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.WatchReads ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatch">
  <Description>Read-only tools that read the failed messages, the event log and the item settings of a production.</Description>
  <Tool Name="read_failed_messages" Class="OcuTalon.Tools.WatchReads" Method="ReadFailedMessages">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="read_event_log" Class="OcuTalon.Tools.WatchReads" Method="ReadEventLog">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
  <Tool Name="read_item_settings" Class="OcuTalon.Tools.WatchReads" Method="ReadItemSettings">
    <Requirement Name="ReadOnly" Value="1"/>
  </Tool>
</ToolSet>
}

}
