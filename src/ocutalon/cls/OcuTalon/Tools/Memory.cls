/// The memory tools that the Chat agent offers (AD-1, AD-7, AD-21): save_memory, search_memories, list_memories and forget_memory. Each tool is a method of
/// OcuTalon.Tools.MemoryTools, which declares the step label and the classification of each one as class parameters (the one declaration: this toolset
/// holds no Requirement element, so the two cannot drift). MemoryTools compiles first (DependsOn), because the toolset's generator reads the methods that
/// the tools name.
Class OcuTalon.Tools.Memory Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.MemoryTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonMemory">
  <Description>Tools that save, find, list and forget the memories of the user in this conversation.</Description>
  <Tool Name="save_memory" Class="OcuTalon.Tools.MemoryTools" Method="SaveMemory"/>
  <Tool Name="search_memories" Class="OcuTalon.Tools.MemoryTools" Method="SearchMemories"/>
  <Tool Name="list_memories" Class="OcuTalon.Tools.MemoryTools" Method="ListMemories"/>
  <Tool Name="forget_memory" Class="OcuTalon.Tools.MemoryTools" Method="ForgetMemory"/>
</ToolSet>
}

}
