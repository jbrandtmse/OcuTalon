/// The watch tools that the Chat agent offers (AD-1, AD-7, AD-18, AD-28): start_watch, stop_watch, list_productions, dismiss_incident and check_status. Each tool is a method of
/// OcuTalon.Tools.WatchTools, which declares the step label and the classification of each one as class parameters (the one declaration: this
/// toolset holds no Requirement element, so the two cannot drift). WatchTools compiles first (DependsOn), because the toolset's generator reads
/// the methods that the tools name. The class is not OcuTalon.Tools.Watch, which is the Diagnosis agent's read-only toolset.
Class OcuTalon.Tools.Watching Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.WatchTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatching">
  <Description>Tools that start and stop the watch of a production for the user in this conversation, list the productions that can be watched, dismiss one of the user's incidents, and read the latest results of the user's background checks.</Description>
  <Tool Name="start_watch" Class="OcuTalon.Tools.WatchTools" Method="StartWatch"/>
  <Tool Name="stop_watch" Class="OcuTalon.Tools.WatchTools" Method="StopWatch"/>
  <Tool Name="list_productions" Class="OcuTalon.Tools.WatchTools" Method="ListProductions"/>
  <Tool Name="dismiss_incident" Class="OcuTalon.Tools.WatchTools" Method="DismissIncident"/>
  <Tool Name="check_status" Class="OcuTalon.Tools.WatchTools" Method="CheckStatus"/>
</ToolSet>
}

}
