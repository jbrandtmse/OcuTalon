/// One Slack event that the route accepted, handed to SlackIn by OcuTalon.Web.Hook after the signature, the size and the JSON have been checked (Story 27.1).
/// It is a plain object, never stored or sent as a message, and holds only what the classification needs, as Slack reported it; every value is untrusted.
/// SlackIn never logs, traces or audits any of it but the event id.
Class OcuTalon.Channel.Slack.Event Extends %RegisteredObject
{

/// The Events API envelope's event_id, the key that a retry is recognised by.
Property EventId As %String(MAXLEN = 64);

/// The envelope's type: event_callback for an event.
Property EnvelopeType As %String(MAXLEN = 64);

/// The event's type, for example message or app_mention.
Property EventType As %String(MAXLEN = 64);

/// The event's channel_type: im for a direct message.
Property ChannelType As %String(MAXLEN = 32);

/// The event's subtype; empty for a plain message.
Property Subtype As %String(MAXLEN = 64);

/// The event's bot_id; empty unless a bot wrote the message.
Property BotId As %String(MAXLEN = 64);

/// The envelope's team_id: the workspace.
Property TeamId As %String(COLLATION = "EXACT", MAXLEN = 32);

/// The event's user: the member who wrote the message.
Property MemberId As %String(COLLATION = "EXACT", MAXLEN = 32);

/// The message text.
Property Text As %String(MAXLEN = "");

/// The event of a parsed envelope: its fields, each only when it is a string of at most its limit of characters (any other value is left empty,
/// so that a value never matches a row by its first characters and an event id is always a usable subscript).
ClassMethod FromJson(envelope As %DynamicObject) As OcuTalon.Channel.Slack.Event
{
	Set event = ..%New()
	Set inner = envelope.%Get("event")
	If '$IsObject(inner) || 'inner.%IsA("%Library.DynamicObject") Set inner = {}
	Set event.EventId = ..Field(envelope, "event_id", 64)
	Set event.EnvelopeType = ..Field(envelope, "type", 64)
	Set event.TeamId = ..Field(envelope, "team_id", 32)
	Set event.EventType = ..Field(inner, "type", 64)
	Set event.ChannelType = ..Field(inner, "channel_type", 32)
	Set event.Subtype = ..Field(inner, "subtype", 64)
	Set event.BotId = ..Field(inner, "bot_id", 64)
	Set event.MemberId = ..Field(inner, "user", 32)
	Set event.Text = ..Field(inner, "text", "")
	Quit event
}

/// The string member of an object, "" when it is missing, not a string, or longer than max characters (max "" is no limit).
ClassMethod Field(object As %DynamicObject, name As %String, max As %Integer) As %String [ Private ]
{
	If object.%GetTypeOf(name) '= "string" Quit ""
	Set value = object.%Get(name)
	Quit $Select((max '= "") && ($Length(value) > max): "", 1: value)
}

}
