/// Lane B's rows of the production-item oracle (Story 0.6, matrix row 1): the items of lane B's region of
/// OcuTalon.Production, in the order of the production. OcuTalon.Test.Install.Production reads them after lane A's rows,
/// and the live tests of docker/tests/ read both through its Items(). Lane B edits these rows, and only these, when it
/// builds, adds, disables or reconfigures one of its items (AD-29, AD-33). stub is 1 for an item class that must carry
/// STUB (every unbuilt item; not the stock classes). A setting is {"target","name","value"}.
Class OcuTalon.Test.Core.ProductionItems
{

/// Lane B's rows as a dynamic array.
ClassMethod Items() As %DynamicArray
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||Items").Data)
}

XData Items [ MimeType = application/json ]
{
[
 {"lane": "B", "name": "WebChatIn", "class": "OcuTalon.Channel.WebChat.In", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "WebChatOut", "class": "OcuTalon.Channel.WebChat.Out", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "SimMailboxIn", "class": "OcuTalon.Channel.SimMailbox.In", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "SimMailboxOut", "class": "OcuTalon.Channel.SimMailbox.Out", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "SimPhoneOut", "class": "OcuTalon.Channel.SimPhone.Out", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "AnswersIn", "class": "OcuTalon.Core.AnswersIn", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "CommandsIn", "class": "OcuTalon.Core.CommandsIn", "pool": 0, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "B", "name": "NoticesIn", "class": "OcuTalon.Core.NoticesIn", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "StatusMonitor", "class": "OcuTalon.Core.StatusMonitor", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "Conversation", "class": "OcuTalon.Core.Conversation", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "Intake", "class": "OcuTalon.Core.Intake", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "OutcomeRouter", "class": "EnsLib.MsgRouter.RoutingEngine", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Host", "name": "BusinessRuleName", "value": "OcuTalon.Core.Rule.Outcome"}]},
 {"lane": "B", "name": "Notify", "class": "EnsLib.MsgRouter.RoutingEngine", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Host", "name": "BusinessRuleName", "value": "OcuTalon.Core.Rule.Notify"}]},
 {"lane": "B", "name": "SessionOps", "class": "OcuTalon.Core.SessionOps", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "SettingsOps", "class": "OcuTalon.Core.SettingsOps", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "HeartbeatIn", "class": "OcuTalon.Schedule.HeartbeatIn", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "ReminderOps", "class": "OcuTalon.Schedule.ReminderOps", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "ReminderTimer", "class": "OcuTalon.Schedule.ReminderTimer", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "BreakFeedIn", "class": "OcuTalon.Demo.BreakFeedIn", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "B", "name": "PartnerTrigger", "class": "OcuTalon.Demo.PartnerTrigger", "pool": 1, "enabled": 1, "stub": 1, "settings": []}
]
}

}
