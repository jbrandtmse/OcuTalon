/// The text of a page for the web chat card, the Telegram copy and the page email (Story 24.3a, DW-1430; AD-14, AD-19, AD-32), so that all show the identical cause sentence. Text(notification, channel)
/// is OcuTalon.Watch.Paging.Text of a copy of the Notification whose Slots are the same except for a string slot cause, which is OcuTalon.Bridge.Redact.Text of it, then cut to
/// MAXCAUSE characters (the limit of an incident's Cause). Every other slot is unchanged, and the Notification that was passed in is never changed. Slots that cannot be read
/// are passed on as they are, for Paging.Text to refuse. Only the *Out operations that render a page for the web, Telegram or email call it: producers never render.
Class OcuTalon.Channel.PageText [ Abstract ]
{

/// The most characters of a cause that the text carries (the MAXLEN of Data.Incident's Cause).
Parameter MAXCAUSE = 1000;

/// The text of the page for the channel (see the class comment), or "" with the status in sc.
ClassMethod Text(notification As OcuTalon.Msg.Notification, channel As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	Set text = ""
	Try {
		Set copy = notification.%ConstructClone()
		Try {
			Set slots = {}.%FromJSON(notification.Slots)
			If slots.%GetTypeOf("cause") = "string" {
				Do slots.%Set("cause", $Extract(##class(OcuTalon.Bridge.Redact).Text(slots.cause), 1, ..#MAXCAUSE), "string")
				Set copy.Slots = slots.%ToJSON()
			}
		} Catch {
			Set copy.Slots = notification.Slots
		}
		Set text = ##class(OcuTalon.Watch.Paging).Text(copy, channel, .sc)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set text = ""
	}
	Quit text
}

}
