/// The names of OcuTalon's built-in tools of release 1 (AD-22). The model sees these names, and the CI mock keys its
/// tool calls on them. Each name is snake_case. Tools of later steps fix their own names in their own stories.
Class OcuTalon.Tools.Names
{

Parameter SETREMINDER = "set_reminder";

Parameter LISTREMINDERS = "list_reminders";

Parameter CANCELREMINDER = "cancel_reminder";

Parameter STARTWATCH = "start_watch";

Parameter STOPWATCH = "stop_watch";

Parameter LISTPRODUCTIONS = "list_productions";

Parameter DISMISSINCIDENT = "dismiss_incident";

Parameter CHECKSTATUS = "check_status";

Parameter READFAILEDMESSAGES = "read_failed_messages";

Parameter READEVENTLOG = "read_event_log";

Parameter READITEMSETTINGS = "read_item_settings";

Parameter RECENTACTIVITY = "recent_activity";

/// Every name above, comma-separated, in the order of the parameters.
Parameter RELEASE1 = {..#SETREMINDER_","_..#LISTREMINDERS_","_..#CANCELREMINDER_","_..#STARTWATCH_","_..#STOPWATCH_","_..#LISTPRODUCTIONS_","_..#DISMISSINCIDENT_","_..#CHECKSTATUS_","_..#READFAILEDMESSAGES_","_..#READEVENTLOG_","_..#READITEMSETTINGS_","_..#RECENTACTIVITY};

}
