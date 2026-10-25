/// The reminder tools that the Chat agent offers (AD-1, AD-7, AD-18): set_reminder, list_reminders and cancel_reminder. Each tool is a method of
/// OcuTalon.Tools.ReminderTools, which declares the step label and the classification of each one as class parameters (the one declaration:
/// this toolset holds no Requirement element, so the two cannot drift). ReminderTools compiles first (DependsOn), because the toolset's
/// generator reads the methods that the tools name.
Class OcuTalon.Tools.Reminders Extends %AI.ToolSet [ DependsOn = OcuTalon.Tools.ReminderTools ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonReminders">
  <Description>Tools that set, list and cancel the reminders of the user in this conversation.</Description>
  <Tool Name="set_reminder" Class="OcuTalon.Tools.ReminderTools" Method="SetReminder"/>
  <Tool Name="list_reminders" Class="OcuTalon.Tools.ReminderTools" Method="ListReminders"/>
  <Tool Name="cancel_reminder" Class="OcuTalon.Tools.ReminderTools" Method="CancelReminder"/>
</ToolSet>
}

}
