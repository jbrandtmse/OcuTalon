/// The watch tools that the Chat agent offers (AD-1, AD-7, AD-18, AD-28): start_watch, stop_watch, list_productions, dismiss_incident, check_status and recent_activity (Story 5.13),
/// send_digest (Story 17.6), incident_summary (Story 23.6, a second method of OcuTalon.Tools.RecentActivity) and propose_fix (Story 23.2, a sixth method of OcuTalon.Tools.WatchTools; it also asks for a partner delay notice, Story 23.5). The first five and propose_fix are methods of OcuTalon.Tools.WatchTools, recent_activity is the method of OcuTalon.Tools.RecentActivity and send_digest is the method of
/// OcuTalon.Tools.DigestTools; each provider declares the step label and the
/// classification of its tools as class parameters (the one declaration: this toolset holds no Requirement element, so the two cannot drift). Both providers compile first
/// (DependsOn), because the toolset's generator reads the methods that the tools name. The class is not OcuTalon.Tools.Watch, which is the Diagnosis agent's read-only toolset.
Class OcuTalon.Tools.Watching Extends %AI.ToolSet [ DependsOn = (OcuTalon.Tools.WatchTools, OcuTalon.Tools.RecentActivity, OcuTalon.Tools.DigestTools) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatching">
  <Description>Tools that start and stop the watch of a production, or the queue-backlog watch, for the user in this conversation, list the productions that can be watched, dismiss one of the user's incidents, read the latest results of the user's background checks, tell what happened in the user's recent incidents, give the summary of the user's latest closed incident, ask for approval of a suspend, a resume or a reroute that the user asked for, ask for a delay notice to the partner to be drafted for approval, and send the user's digest now.</Description>
  <Tool Name="start_watch" Class="OcuTalon.Tools.WatchTools" Method="StartWatch"/>
  <Tool Name="stop_watch" Class="OcuTalon.Tools.WatchTools" Method="StopWatch"/>
  <Tool Name="list_productions" Class="OcuTalon.Tools.WatchTools" Method="ListProductions"/>
  <Tool Name="dismiss_incident" Class="OcuTalon.Tools.WatchTools" Method="DismissIncident"/>
  <Tool Name="check_status" Class="OcuTalon.Tools.WatchTools" Method="CheckStatus"/>
  <Tool Name="recent_activity" Class="OcuTalon.Tools.RecentActivity" Method="RecentActivity"/>
  <Tool Name="send_digest" Class="OcuTalon.Tools.DigestTools" Method="SendDigest"/>
  <Tool Name="incident_summary" Class="OcuTalon.Tools.RecentActivity" Method="IncidentSummary"/>
  <Tool Name="propose_fix" Class="OcuTalon.Tools.WatchTools" Method="ProposeFix"/>
</ToolSet>
}

}
