/// WebhookIn, the adapterless service through which an event of a webhook enters the production (AD-1, AD-14, AD-26, AD-30; Story 35.3). OcuTalon.Web.Hook creates
/// it in its own process (Ens.Director.CreateBusinessService) and calls ProcessInput with a Channel.Webhook.Event, after it has checked the secret, the size, the
/// JSON and the hourly limit. An input that is not an Event, an Event with no session or no text, and a session with no Session row answer an error status and
/// send nothing. In order, the service:
///   - sets the service's SuperSession to the session's TraceRef, so the event has a trace session of its own under the session's (AD-26);
///   - sends Intake an OcuTalon.Msg.Item, asynchronously: a new ItemId, the session's SessionRef, channel webhook, provenance untrusted, Subject the webhook's name
///     and Text the body; every other field is empty or 0. The event is not saved and no live event is published.
/// The output of an accepted event is the JSON text {"itemId"}. The service decides nothing: Intake asks for the decision afterwards. It logs nothing.
Class OcuTalon.Channel.Webhook.In Extends Ens.BusinessService
{

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "webhook";

Parameter ERRORINPUT = "WebhookIn takes an event from the webhook route and nothing else.";

Parameter ERROREVENT = "A webhook event needs a session and some text.";

Parameter ERRORSESSION = "The webhook's session has no session row.";

/// Takes an event; pOutput is the JSON text {"itemId":...} of the Item that was sent.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Channel.Webhook.Event") Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	If (pInput.SessionRef = "") || ($ZStrip(pInput.Text, "<>WC") = "") Quit $SYSTEM.Status.Error(5001, ..#ERROREVENT)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(pInput.SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
	Set ..%SuperSession = session.TraceRef
	Try {
		Set item = ##class(OcuTalon.Msg.Item).%New()
		Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set item.SessionRef = pInput.SessionRef
		Set item.Channel = ..#CHANNEL
		Set item.Provenance = "untrusted"
		Set item.Subject = pInput.Name
		Set item.Text = pInput.Text
		Set sc = ..Send(..#TARGET, item)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set pOutput = {"itemId": (item.ItemId)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The one send of the class: the request to the item, asynchronously. Private; a test subclass overrides it.
Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request)
}

}
