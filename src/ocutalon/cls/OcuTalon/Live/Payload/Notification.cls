/// The payload of the notification live event: one notice card in the chat. Lane B publishes it.
Class OcuTalon.Live.Payload.Notification Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The notification's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum NOTIFICATIONKIND.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// The rendered notice text.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// Why the notice came now.
Property WhyNow As %String(%JSONFIELDNAME = "whyNow", MAXLEN = 1000);

/// The decision's Ref, when the notice is about one.
Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);

/// The incident's Ref, when the notice is about one.
Property IncidentRef As %String(%JSONFIELDNAME = "incidentRef", MAXLEN = 22);

/// The approval request's Ref, when the notice asks for one.
Property ApprovalRef As %String(%JSONFIELDNAME = "approvalRef", MAXLEN = 22);

/// When the thing the notice is about is due, UTC to the second.
Property DueAt As %String(%JSONFIELDNAME = "dueAt", MAXLEN = 20);

/// When the notice was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

}
