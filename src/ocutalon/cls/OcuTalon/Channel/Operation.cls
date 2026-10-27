/// Operation, the abstract base of the channel operations (WebChatOut, SimPhoneOut, SimMailboxOut; AD-14, AD-4, AD-12). It holds what they share:
/// the check that a message's owner is a session, and the publish of a live event that is logged and goes no further when it fails.
/// A subclass sets LOGNOTASESSION and LOGPUBLISH, the start of its two warnings. Keep records a device message with its
/// Delivery row in one transaction.
Class OcuTalon.Channel.Operation Extends Ens.BusinessOperation [ Abstract ]
{

/// The start of the warning for an owner that is not a session.
Parameter LOGNOTASESSION = "A channel operation dropped a message: its owner is not a session: ";

/// The start of the warning for an event that could not be published.
Parameter LOGPUBLISH = "A channel operation could not publish an event: ";

/// 1 when the owner is a session (Session.Recipients gives back exactly that Ref); otherwise one warning is logged and the answer is 0.
Method IsSession(ownerRef As %String) As %Boolean
{
	Set recipients = ##class(OcuTalon.Data.Session).Recipients(ownerRef)
	If ($ListLength(recipients) = 1) && ($List(recipients, 1) = ownerRef) Quit 1
	$$$LOGWARNING(..#LOGNOTASESSION_$Select(ownerRef = "": "(empty)", $Length(ownerRef) > 40: $Extract(ownerRef, 1, 40), 1: ownerRef))
	Quit 0
}

/// Publishes one event of the type on the owner's stream, with the payload class's FromRow of the row. A status error or an
/// exception (building the payload included) is logged and goes no further.
Method Announce(ownerRef As %String, type As %String, payloadClass As %String, row As %RegisteredObject)
{
	Try {
		Set payload = $ClassMethod(payloadClass, "FromRow", row)
		Set sc = ##class(OcuTalon.Live.Publish).Publish(ownerRef, type, payload, .seq)
		If $$$ISERR(sc) $$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
	} Catch exception {
		$$$LOGWARNING(..#LOGPUBLISH_exception.DisplayString())
	}
}

/// Saves the message and its Delivery row (the message's Ref as ChannelMessageId, no text) in one transaction; row is the
/// saved message. On a failure nothing is kept and row is empty.
Method Keep(message As OcuTalon.Data.SimMessage, channel As %String, approvalRef As %String, kind As %String, decisionRef As %String, Output row As OcuTalon.Data.SimMessage) As %Status
{
	Set row = ""
	Set started = 0
	Set sc = $$$OK
	Try {
		TSTART
		Set started = 1
		Set sc = message.%Save()
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.Delivery).Record(message.SessionRef, channel, message.Ref, approvalRef, kind, "", decisionRef)
		If $$$ISOK(sc) {
			TCOMMIT
			Set started = 0
			Set row = message
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If started TROLLBACK 1
	Quit sc
}

}
