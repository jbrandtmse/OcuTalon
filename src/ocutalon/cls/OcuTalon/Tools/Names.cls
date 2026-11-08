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

/// The persona proposal tool of the personality epics (AD-7); not a release-1 tool, so RELEASE1 does not list it.
Parameter PROPOSEPERSONA = "propose_persona";
/// The name of step 2's digest tool, Story 17.6. It is not part of RELEASE1.
Parameter DIGESTTOOLS = "send_digest";

/// The memory tools of step 3 (AD-21); not release-1 tools, so RELEASE1 does not list them.
Parameter SAVEMEMORY = "save_memory";

Parameter SEARCHMEMORIES = "search_memories";

Parameter LISTMEMORIES = "list_memories";

Parameter FORGETMEMORY = "forget_memory";

/// The four memory tools above, comma-separated, in the order of the parameters.
Parameter MEMORYTOOLS = {..#SAVEMEMORY_","_..#SEARCHMEMORIES_","_..#LISTMEMORIES_","_..#FORGETMEMORY};

}
