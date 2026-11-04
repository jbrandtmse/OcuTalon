/// A subclass of OcuTalon.Core.NoticesIn for the tests, which overrides its private Forward: it sends nothing and records what
/// the send saw. It adds nothing to the product's surface; the product never refers to it. Sends counts the forwards;
/// SeenTarget and LastNotification are those of the last, and SeenSessionId and SeenSuperSession are the trace session that the
/// service had set when it forwarded.
Class OcuTalon.Test.Core.NoticesInProbe Extends OcuTalon.Core.NoticesIn
{

/// The number of forwards.
Property Sends As %Integer [ InitialExpression = 0 ];

/// The target item of the last forward.
Property SeenTarget As %String;

/// The notification of the last forward.
Property LastNotification As %Library.Persistent;

/// The service's %SessionId when it forwarded.
Property SeenSessionId As %String;

/// The service's %SuperSession when it forwarded.
Property SeenSuperSession As %String;

Method Forward(target As %String, notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set ..Sends = ..Sends + 1
	Set ..SeenTarget = target
	Set ..SeenSessionId = ..%SessionId
	Set ..SeenSuperSession = ..%SuperSession
	Set ..LastNotification = notification
	Quit $$$OK
}

}
