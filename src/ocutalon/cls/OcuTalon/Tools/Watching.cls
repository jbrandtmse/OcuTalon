/// The watch tools that the Chat agent offers (AD-1, AD-7, AD-18, AD-28): start_watch, stop_watch, list_productions, dismiss_incident, check_status and recent_activity (Story 5.13),
/// and send_digest (Story 17.6). The first five are methods of OcuTalon.Tools.WatchTools, recent_activity is the method of OcuTalon.Tools.RecentActivity and send_digest is the method of
/// OcuTalon.Tools.DigestTools; each provider declares the step label and the
/// classification of its tools as class parameters (the one declaration: this toolset holds no Requirement element, so the two cannot drift). Both providers compile first
/// (DependsOn), because the toolset's generator reads the methods that the tools name. The class is not OcuTalon.Tools.Watch, which is the Diagnosis agent's read-only toolset.
Class OcuTalon.Tools.Watching Extends %AI.ToolSet [ DependsOn = (OcuTalon.Tools.WatchTools, OcuTalon.Tools.RecentActivity, OcuTalon.Tools.DigestTools) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatching">
  <Description>Tools that start and stop the watch of a production for the user in this conversation, list the productions that can be watched, dismiss one of the user's incidents, read the latest results of the user's background checks, tell what happened in the user's recent incidents, and send the user's digest now.</Description>
  <Tool Name="start_watch" Class="OcuTalon.Tools.WatchTools" Method="StartWatch"/>
  <Tool Name="stop_watch" Class="OcuTalon.Tools.WatchTools" Method="StopWatch"/>
  <Tool Name="list_productions" Class="OcuTalon.Tools.WatchTools" Method="ListProductions"/>
  <Tool Name="dismiss_incident" Class="OcuTalon.Tools.WatchTools" Method="DismissIncident"/>
  <Tool Name="check_status" Class="OcuTalon.Tools.WatchTools" Method="CheckStatus"/>
  <Tool Name="recent_activity" Class="OcuTalon.Tools.RecentActivity" Method="RecentActivity"/>
  <Tool Name="send_digest" Class="OcuTalon.Tools.DigestTools" Method="SendDigest"/>
</ToolSet>
}

}
