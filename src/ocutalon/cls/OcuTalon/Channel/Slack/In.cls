Include Ensemble

/// SlackIn, the adapterless inbound service of the Slack channel (AD-1, AD-14, AD-19, AD-24, AD-26; Story 27.1). OcuTalon.Web.Hook creates it in its own process
/// (Ens.Director.CreateBusinessService) and calls ProcessInput with a Channel.Slack.Event, after the route has checked that Slack is on, the size, Slack's
/// signature and the JSON. The service never calls Slack. It runs under the hook's role OcuTalonWebhook with no grant of its own (AD-24), and it logs nothing
/// that holds content or an id other than the event's id.
///   - On is the one switch: SLACK_SIGNING_SECRET and SLACK_BOT_TOKEN are both set and non-empty in the environment (read with $SYSTEM.Util.GetEnviron at the
///     moment of the call, never stored) and the online demo is off. With Slack off, ProcessInput answers an error status and sends nothing;
///   - an input that is not an Event answers an error status and sends nothing;
///   - the event id is claimed (Data.SlackLink ClaimEvent): the first claim within two hours is processed and a repeat (Slack's retry) answers OK and does nothing;
///     a claim is given back when the hand-over fails, so that Slack's retry is processed;
///   - the event is classified, in this order. A turn is a plain direct message: event type message, channel_type im, no subtype and no bot_id, a sender,
///     text that is not blank, and a member whose Data.SlackLink row matches both the team and the member id and whose session has a row. It becomes one
///     OcuTalon.Msg.Item with channel slack, provenance user, FromGuide 0 and only the text (no sender, no member id, no team id), sent asynchronously to
///     Conversation after Core.Trace.Join, in the session's trace thread, by the steps of Channel.Telegram.In Turn (Slack has no allowance: it is off on the
///     online demo). Slack has no approval surface: a Slack turn is a typed turn and nothing typed answers an approval request (AD-11);
///   - every other event leaves one Channel.Slack.Ignored (a fixed kind and reason and the event id) sent asynchronously to Intake, which drops it silently, in a
///     trace session of its own (the service's %SessionId and %SuperSession are empty), and goes no further: a bot's message (our own replies included), an edit, a delete, a
///     join or a file share, a channel message, a member who is not linked or is linked in another workspace, an app mention and every other type.
/// An error status of ProcessInput means that the event did not reach the production: the hook answers 503.
Class OcuTalon.Channel.Slack.In Extends Ens.BusinessService
{

/// The item that takes a turn.
Parameter TARGET = "Conversation";

/// The item that takes an ignored event.
Parameter INTAKE = "Intake";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "slack";

/// The environment variable of the signing secret.
Parameter SECRETVARIABLE = "SLACK_SIGNING_SECRET";

/// The environment variable of the bot token.
Parameter TOKENVARIABLE = "SLACK_BOT_TOKEN";

Parameter ERROROFF = "Slack is off, so SlackIn takes no event.";

Parameter ERRORINPUT = "SlackIn takes an event from the Slack route and nothing else.";

Parameter ERRORSESSION = "The linked session has no session row.";

Parameter LOGJOIN = "SlackIn could not join the session's trace thread, so this turn is traced on its own.";

Parameter LOGSTARTED = "SlackIn could not record the session's trace thread, so the next turn starts another.";

/// 1 when Slack is on: both environment variables are non-empty and the online demo is off. demo is the online-demo flag when the caller already has it, or "" to
/// read the setting. The value of a variable is never kept.
ClassMethod On(demo As %Boolean = "") As %Boolean
{
	If $SYSTEM.Util.GetEnviron(..#SECRETVARIABLE) = "" Quit 0
	If $SYSTEM.Util.GetEnviron(..#TOKENVARIABLE) = "" Quit 0
	If demo = "" Set demo = (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
	Quit 'demo
}

/// Takes an event; pOutput is always empty.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '..On() Quit $SYSTEM.Status.Error(5001, ..#ERROROFF)
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Channel.Slack.Event") Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	Set event = pInput
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	If event.EventId = "" Quit ..Ignore("other", "unhandled_type", "")
	If '##class(OcuTalon.Data.SlackLink).ClaimEvent(event.EventId, now) Quit $SYSTEM.Status.OK()
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set reason = ..Classify(event, .kind, .sessionRef)
		If reason = "" {
			Set sc = ..Turn(sessionRef, event.Text, now)
		} Else {
			Set sc = ..Ignore(kind, reason, event.EventId)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Do ##class(OcuTalon.Data.SlackLink).UnclaimEvent(event.EventId)
	Quit sc
}

/// "" when the event is a turn, with sessionRef the linked session; otherwise the reason it is not (one of Ignored REASONS), with kind the kind of event (one of
/// Ignored KINDS). The checks run in this order: type, channel type, bot, subtype, sender, text, link.
Method Classify(event As OcuTalon.Channel.Slack.Event, Output kind As %String, Output sessionRef As %String) As %String [ Private ]
{
	Set sessionRef = ""
	If event.EventType '= "message" {
		Set kind = $Select(event.EventType = "app_mention": "app_mention", 1: "other")
		Quit "unhandled_type"
	}
	If event.ChannelType '= "im" {
		Set kind = $Select((event.ChannelType = "channel") || (event.ChannelType = "group") || (event.ChannelType = "mpim"): "message.channel", 1: "message.other")
		Quit "not_im"
	}
	Set kind = "message.im"
	If event.BotId '= "" Quit "bot"
	If event.Subtype '= "" Quit "subtype"
	If (event.MemberId = "") || (event.TeamId = "") Quit "no_sender"
	If $ZStrip(event.Text, "<>WC") = "" Quit "blank"
	Set sessionRef = ##class(OcuTalon.Data.SlackLink).SessionFor(event.TeamId, event.MemberId)
	If sessionRef '= "" Quit ""
	Quit $Select(##class(OcuTalon.Data.SlackLink).LinkedInAnotherTeam(event.TeamId, event.MemberId): "other_team", 1: "unlinked")
}

/// A linked member's direct message as the session's turn, in the steps of Channel.Telegram.In Turn without its allowance and file steps: the session's row must
/// exist; Trace.Join gives the session's thread of the day, which is the service's %SessionId, with the session's TraceRef as its %SuperSession (a failed Join is
/// one warning and the turn is traced on its own); one Msg.Item goes to Conversation; when the day had no thread, Trace.Started records the thread that the send gave.
/// The service's %SessionId and %SuperSession are empty again, and the job's session id is cleared, when the method ends, also after an exception, which it then
/// raises to the caller. The status is the send's.
Method Turn(sessionRef As %String, text As %String, now As %String) As %Status [ Private ]
{
	Set thrown = ""
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
		If '$IsObject(session) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
			Quit
		}
		Set thread = ##class(OcuTalon.Core.Trace).Join(sessionRef, .joinSc, now)
		If $SYSTEM.Status.IsError(joinSc) $$$LOGWARNING(..#LOGJOIN)
		Set ..%SessionId = thread
		Set ..%SuperSession = session.TraceRef
		Try {
			Set item = ##class(OcuTalon.Msg.Item).%New()
			Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set item.SessionRef = sessionRef
			Set item.Channel = ..#CHANNEL
			Set item.Provenance = "user"
			Set item.Text = text
			Set item.FromGuide = 0
			Set sc = ..SendTurn(item)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $SYSTEM.Status.IsOK(joinSc) && (thread = "") {
			Set startedSc = ##class(OcuTalon.Core.Trace).Started(sessionRef, $Select($SYSTEM.Status.IsOK(sc): ..%SessionId, 1: ""), now)
			If $SYSTEM.Status.IsError(startedSc) $$$LOGWARNING(..#LOGSTARTED)
		}
	} Catch exception {
		Set thrown = exception
	}
	Set ..%SessionId = ""
	Set ..%SuperSession = ""
	Kill $$$JobSessionId
	If $IsObject(thrown) Throw thrown
	Quit sc
}

/// One Ignored record for an event that is not a turn, sent in a trace session of its own. The status is the send's.
Method Ignore(kind As %String, reason As %String, eventId As %String) As %Status [ Private ]
{
	Set ignored = ##class(OcuTalon.Channel.Slack.Ignored).%New()
	Set ignored.Kind = kind
	Set ignored.Reason = reason
	Set ignored.EventId = eventId
	Set ..%SessionId = ""
	Set ..%SuperSession = ""
	Kill $$$JobSessionId
	Quit ..SendIgnored(ignored)
}

/// The one send of a turn's Item to Conversation, asynchronously. Private; a test subclass overrides it.
Method SendTurn(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#TARGET, item)
}

/// The one send of an Ignored record to Intake, asynchronously. Private; a test subclass overrides it.
Method SendIgnored(ignored As OcuTalon.Channel.Slack.Ignored) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#INTAKE, ignored)
}

}
