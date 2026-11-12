/// One event that a webhook received, handed to WebhookIn by OcuTalon.Web.Hook (Story 35.3). It holds the owning session's Ref, the webhook's name (the Item's
/// subject) and the body as text (the Item's text). It is a plain object, never stored or sent as a message, and it holds no secret, header or caller address.
Class OcuTalon.Channel.Webhook.Event Extends %RegisteredObject
{

/// The Ref of the session that owns the webhook.
Property SessionRef As %String(MAXLEN = 22);

/// The webhook's name.
Property Name As %String(MAXLEN = 64);

/// The body of the request, decoded from UTF-8.
Property Text As %String(MAXLEN = "");

}
