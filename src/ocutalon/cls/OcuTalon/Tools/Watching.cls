/// The watch tools that the Chat agent offers (AD-1, AD-7, AD-18): start_watch, stop_watch and list_productions. Each tool is a method of
/// OcuTalon.Tools.WatchTools, which declares the step label and the classification of each one as class parameters (the one declaration: this
/// toolset holds no Requirement element, so the two cannot drift). WatchTools compiles first (DependsOn), because the toolset's generator reads
/// the methods that the tools name. The class is not OcuTalon.Tools.Watch, which is the Diagnosis agent's read-only toolset.
Class OcuTalon.Tools.Watching Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.WatchTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonWatching">
  <Description>Tools that start and stop the watch of a production for the user in this conversation, and list the productions that can be watched.</Description>
  <Tool Name="start_watch" Class="OcuTalon.Tools.WatchTools" Method="StartWatch"/>
  <Tool Name="stop_watch" Class="OcuTalon.Tools.WatchTools" Method="StopWatch"/>
  <Tool Name="list_productions" Class="OcuTalon.Tools.WatchTools" Method="ListProductions"/>
</ToolSet>
}

}
