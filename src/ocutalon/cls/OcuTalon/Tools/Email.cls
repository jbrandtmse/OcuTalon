/// The email tool that the Chat agent offers (AD-1, AD-7): send_email. It is a method of OcuTalon.Tools.EmailTools, which declares the step label and the classification as class
/// parameters (the one declaration: this toolset holds no Requirement element, so the two cannot drift). EmailTools compiles first (DependsOn), because the toolset's generator reads the
/// method that the tool names.
Class OcuTalon.Tools.Email Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.EmailTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonEmail">
  <Description>Sends a plain-text email from the user's connected mailbox. Email to the user's own address is sent at once; email to anyone else becomes an approval request and is sent only after the user approves it. The answer says whether the email was sent.</Description>
  <Tool Name="send_email" Class="OcuTalon.Tools.EmailTools" Method="SendEmail"/>
</ToolSet>
}

}
