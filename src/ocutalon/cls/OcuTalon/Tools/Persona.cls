/// The persona tool that the Chat agent offers (AD-1, AD-7): propose_persona. It is a method of OcuTalon.Tools.PersonaTools, which declares the
/// step label and the classification as class parameters (the one declaration: this toolset holds no Requirement element, so the two cannot
/// drift). PersonaTools compiles first (DependsOn), because the toolset's generator reads the method that the tool names.
Class OcuTalon.Tools.Persona Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.PersonaTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonPersona">
  <Description>A tool that suggests a new persona for the user in this conversation, as a request that the user answers.</Description>
  <Tool Name="propose_persona" Class="OcuTalon.Tools.PersonaTools" Method="ProposePersona"/>
</ToolSet>
}

}
