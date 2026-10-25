/// WebChatIn, the adapterless service through which the web chat sends into OcuTalon (AD-1, AD-14, AD-30). The REST surface
/// creates it in its own process (Ens.Director.CreateBusinessService) and calls ProcessInput with one of two inputs:
///   - a Channel.WebChat.Post, the page's message. In order: a message whose clientId the session already has is a duplicate
///     (the output says so and nothing is sent); Core.Allowance.TryConsume must allow the message, and a refusal queues
///     nothing and answers an error status; then the service joins the session's trace thread (AD-26): Core.Trace.Join gives
///     the thread of the day, which becomes the service's %SessionId, and the session's TraceRef becomes its SuperSession.
///     It sends Conversation an Item with a new ItemId, the session's SessionRef, channel web, provenance user, the text,
///     FromGuide and ClientId. When the day had no thread, the Item starts one: Core.Trace.Started records the session the send
///     gave, or nothing when the send failed, in every path. A Join that fails (no session row, a lock that stays busy) logs
///     one warning and the message is sent in a session of its own, so a message is never refused or lost for the thread. The
///     output is the JSON text {"accepted":1,"duplicate":0|1};
///   - a Core.Msg.RunTurns, which goes to Conversation unchanged: the way in for code outside the production that restarts the
///     turn queue (Conversation.Reconcile).
/// Any other input, and a Post with an empty session, clientId or text or a session with no Session row, answers an error
/// status, sends nothing and asks the allowance nothing. The service sends only to Conversation, asynchronously.
Class OcuTalon.Channel.WebChat.In Extends Ens.BusinessService
{

/// The item that takes every Item and RunTurns.
Parameter TARGET = "Conversation";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "web";

Parameter ERRORINPUT = "WebChatIn takes a message from the page or a request to run the turns, and nothing else.";

Parameter ERRORPOST = "A message needs a session, a clientId and some text.";

Parameter ERRORSESSION = "The message's session has no session row.";

Parameter ERRORREFUSED = "The session's allowance does not take this message.";

Parameter ERRORJOIN = "WebChatIn could not join the session's trace thread, so this turn is traced on its own: ";

Parameter ERRORSTARTED = "WebChatIn could not record the session's trace thread, so the next turn starts another: ";

/// Takes a message or a RunTurns request; pOutput is the JSON text of the answer for a message, empty otherwise.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	If pInput.%IsA("OcuTalon.Core.Msg.RunTurns") Quit ..Send(..#TARGET, pInput)
	If pInput.%IsA("OcuTalon.Channel.WebChat.Post") Quit ..Accept(pInput, .pOutput)
	Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
}

/// The steps of a message, in order; see the class comment.
Method Accept(post As OcuTalon.Channel.WebChat.Post, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	If (post.SessionRef = "") || (post.ClientId = "") || ($ZStrip(post.Text, "<>WC") = "") Quit $SYSTEM.Status.Error(5001, ..#ERRORPOST)
	Set found = ##class(OcuTalon.Data.Ownership).TurnByClient(post.SessionRef, post.ClientId, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If $IsObject(found) {
		Set output = {"accepted": 1, "duplicate": 1}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(post.SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
	If '..Allowed(post.SessionRef, ..#CHANNEL, post.Text, .retryAt, .firstRefusal) Quit $SYSTEM.Status.Error(5001, ..#ERRORREFUSED)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set thread = ##class(OcuTalon.Core.Trace).Join(post.SessionRef, .joinSc, now)
	If $SYSTEM.Status.IsError(joinSc) $$$LOGWARNING(..#ERRORJOIN_$SYSTEM.Status.GetErrorText(joinSc))
	Set ..%SessionId = thread
	Set ..%SuperSession = session.TraceRef
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set item = ##class(OcuTalon.Msg.Item).%New()
		Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set item.SessionRef = post.SessionRef
		Set item.Channel = ..#CHANNEL
		Set item.Provenance = "user"
		Set item.Text = post.Text
		Set item.FromGuide = post.FromGuide
		Set item.ClientId = post.ClientId
		Set sc = ..Send(..#TARGET, item)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsOK(joinSc) && (thread = "") {
		Set startedSc = ##class(OcuTalon.Core.Trace).Started(post.SessionRef, $Select($SYSTEM.Status.IsOK(sc): ..%SessionId, 1: ""), now)
		If $SYSTEM.Status.IsError(startedSc) $$$LOGWARNING(..#ERRORSTARTED_$SYSTEM.Status.GetErrorText(startedSc))
	}
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set output = {"accepted": 1, "duplicate": 0}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The one send of the class: the request to the item, asynchronously. Private; a test subclass overrides it.
Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request)
}

/// The one call of the allowance. Private; a test subclass overrides it to refuse.
Method Allowed(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Core.Allowance).TryConsume(sessionRef, channel, text, .retryAt, .firstRefusal)
}

}
