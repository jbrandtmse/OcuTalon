Include Ensemble

/// A subclass of OcuTalon.Channel.Email.Out for the tests (Story 21.6): its Deliver is the stand-in of the adapter, so that nothing is opened. Deliver
/// records each message it is given under ^||OcuTalonEmailOutProbe("sent", n) = $ListBuild(from, to (comma-separated), subject, text, charset, multipart,
/// parts, attachments, the value of the header X-OcuTalon-Ref) and counts the calls in ^||OcuTalonEmailOutProbe("calls"), and, when a Delivery row of channel
/// email has exactly that Ref as its ChannelMessageId at the time of the call (the claim of a claimed send), its FallbackReason under
/// ^||OcuTalonEmailOutProbe("claim", n). It answers by ^||OcuTalonEmailOutProbe("answer"): "" for OK, unreachable (SMTPOpen), timeout (SMTPTimeout),
/// dropped (SMTPConnectionFailed during DATA), lost (SMTPConnectionFailed before the greeting), refused (SMTPAUTHFailed), rejected (SMTPResponse, whose text holds SERVER-WORDS and an address) or throw. OAuth2Mode answers ^||OcuTalonEmailOutProbe("oauth") (1 stands in for an adapter
/// with OAuth2ApplicationName set, Story 21.8). The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutProbe Extends OcuTalon.Channel.Email.Out
{

/// A held lock costs a test a second, not ten.
Parameter CLAIMWAIT = 1;

Method OAuth2Mode() As %Boolean [ Private ]
{
	Quit +$Get(^||OcuTalonEmailOutProbe("oauth"))
}

Method Deliver(message As %Net.MailMessage) As %Status [ Private ]
{
	Set n = $Increment(^||OcuTalonEmailOutProbe("calls"))
	Set ref = message.Headers.GetAt("X-OcuTalon-Ref")
	Set own = ##class(%SQL.Statement).%ExecDirect(, "SELECT FallbackReason, ChannelMessageId FROM OcuTalon_Data.Delivery WHERE Channel = 'email' AND ChannelMessageId = ?", ref)
	While own.%Next() {
		If own.%Get("ChannelMessageId") = ref Set ^||OcuTalonEmailOutProbe("claim", n) = own.%Get("FallbackReason") Quit
	}
	Set to = ""
	For i = 1:1:message.To.Count() Set to = to_$Select(to = "": "", 1: ",")_message.To.GetAt(i)
	Do message.TextData.Rewind()
	Set text = message.TextData.Read(1000000)
	Set ^||OcuTalonEmailOutProbe("sent", n) = $ListBuild(message.From, to, message.Subject, text, message.Charset, message.IsMultiPart, message.Parts.Count(), message.Cc.Count() + message.Bcc.Count(), message.Headers.GetAt("X-OcuTalon-Ref"))
	// QA (21.7): when a live test names a real sender in ^||OcuTalonEmailOutProbe("sender") = $ListBuild(host, port, credentials, SSLConfig), the message goes
	// through the real Channel.Email.Sender (the test subclass EmailOutSender, whose switch the test sets), so that the digest path is shown to reach the wire
	// only the way every path does.
	If $Data(^||OcuTalonEmailOutProbe("sender"), sender) {
		Set adapter = ##class(OcuTalon.Test.Channel.EmailOutSender).%New()
		Set adapter.SMTPServer = $List(sender, 1), adapter.SMTPPort = $List(sender, 2), adapter.Credentials = $List(sender, 3), adapter.SSLConfig = $List(sender, 4)
		Do adapter.OnInit()
		Quit adapter.SendMail(message)
	}
	Set answer = $Get(^||OcuTalonEmailOutProbe("answer"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "SERVER-WORDS zzthrown@example.com"))
	If answer = "unreachable" Quit $$$ERROR($$$SMTPOpen)
	If answer = "timeout" Quit $$$ERROR($$$SMTPTimeout)
	If answer = "dropped" Quit $$$ERROR($$$SMTPConnectionFailed, "DATA", "<READ>")
	If answer = "lost" Quit $$$ERROR($$$SMTPConnectionFailed, "init", "<READ>")
	If answer = "refused" Quit $$$ERROR($$$SMTPAUTHFailed)
	If answer = "rejected" Quit $$$ERROR($$$SMTPResponse, "RCPT TO", "550 SERVER-WORDS zzrejected@example.com")
	Quit $$$OK
}

}
