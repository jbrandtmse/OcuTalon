/// The input that Web.Api hands to BreakFeedIn for a press of Break the feed (Story 4.3): the Ref of the signed-in session, taken
/// from the CSP session and never from the client (AD-4). Not a message: it has no storage and is never saved.
Class OcuTalon.Demo.Press Extends %RegisteredObject
{

/// The pressing session's Ref.
Property SessionRef As %String(MAXLEN = 22);

}
