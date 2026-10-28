/// NoticesIn, the adapterless service that receives the notifications that the bridge sends (AD-32). Send is the way in: it
/// creates this service in the caller's own process and calls ProcessInput, so a bridge context of the caller is visible
/// here. Each OcuTalon.Msg.Notification is forwarded to Notify asynchronously, which delivers it on each of the session's
/// channels (AD-31, AD-32):
///   - inside an active bridge context the send joins the turn's thread (AD-26): the trace session is the context's
///     ThreadSessionId when it is above 0, and the SuperSession is the context's SuperSession. Trace.Join is never used;
///   - otherwise the send is a session of its own, whose SuperSession is the TraceRef of the Session row of the
///     notification's SessionRef;
///   - an input that is not a Notification is an error status and nothing is sent. So is a production that is not running.
/// The senders to come are BridgeSink's tool-call notices (Story 31.2) and the daily-cap message (Story 16.9); the
/// incident notices reach Notify from IncidentManager, which sends to it itself.
Class OcuTalon.Core.NoticesIn Extends Ens.BusinessService
{

/// The item that every notification is forwarded to.
Parameter TARGET = "Notify";

/// The way in: creates the service in this process and hands it the notification. The status is an error when the production
/// cannot take it (not running, shutting down, or NoticesIn disabled), when the input is not a Notification, or when the
/// send fails.
ClassMethod Send(notification As OcuTalon.Msg.Notification) As %Status
{
	Set sc = ##class(Ens.Director).CreateBusinessService("NoticesIn", .service)
	If $$$ISERR(sc) Quit sc
	Quit service.ProcessInput($Get(notification), .output)
}

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Msg.Notification") Quit $SYSTEM.Status.Error(5001, "NoticesIn takes an OcuTalon.Msg.Notification")
	Do ..Join(pInput)
	Quit ..Forward(..#TARGET, pInput)
}

/// Puts the send in the right trace session: inside a bridge context the session of its ThreadSessionId, when it has one,
/// with its SuperSession; otherwise a session of its own, with the TraceRef of the notification's Session row as SuperSession.
Method Join(notification As OcuTalon.Msg.Notification) [ Private ]
{
	Set ..%SessionId = "", ..%SuperSession = ""
	If ##class(OcuTalon.Bridge.Context).Active() {
		Set context = ##class(OcuTalon.Bridge.Context).Current()
		If context.ThreadSessionId > 0 Set ..%SessionId = context.ThreadSessionId
		Set ..%SuperSession = context.SuperSession
	} ElseIf notification.SessionRef '= "" {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(notification.SessionRef)
		If $IsObject(session) Set ..%SuperSession = session.TraceRef
	}
}

/// The one send of the class: the notification to the target item, asynchronously. Private, so that only OnProcessInput sends
/// through it, after the checks; a test subclass overrides it to record the send.
Method Forward(target As %String, notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, notification)
}

}
