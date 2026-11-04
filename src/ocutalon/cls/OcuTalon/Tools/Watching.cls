/// The watch tools that the Chat agent offers (AD-1, AD-7, AD-18, AD-28): start_watch, stop_watch, list_productions, dismiss_incident, check_status and recent_activity (Story 5.13).
/// The first five are methods of OcuTalon.Tools.WatchTools and recent_activity is the method of OcuTalon.Tools.RecentActivity; each provider declares the step label and the
/// classification of its tools as class parameters (the one declaration: this toolset holds no Requirement element, so the two cannot drift). Both providers compile first
/// (DependsOn), because the toolset's generator reads the methods that the tools name. The class is not OcuTalon.Tools.Watch, which is the Diagnosis agent's read-only toolset.
Class OcuTalon.Tools.Watching Extends %AI.ToolSet [ DependsOn = (OcuTalon.Tools.WatchTools, OcuTalon.Tools.RecentActivity) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatching">
  <Description>Tools that start and stop the watch of a production for the user in this conversation, list the productions that can be watched, dismiss one of the user's incidents, read the latest results of the user's background checks, and tell what happened in the user's recent incidents.</Description>
  <Tool Name="start_watch" Class="OcuTalon.Tools.WatchTools" Method="StartWatch"/>
  <Tool Name="stop_watch" Class="OcuTalon.Tools.WatchTools" Method="StopWatch"/>
  <Tool Name="list_productions" Class="OcuTalon.Tools.WatchTools" Method="ListProductions"/>
  <Tool Name="dismiss_incident" Class="OcuTalon.Tools.WatchTools" Method="DismissIncident"/>
  <Tool Name="check_status" Class="OcuTalon.Tools.WatchTools" Method="CheckStatus"/>
  <Tool Name="recent_activity" Class="OcuTalon.Tools.RecentActivity" Method="RecentActivity"/>
</ToolSet>
}

}
