Include Ensemble

/// A subclass of OcuTalon.Channel.Email.Out for the tests (Story 21.6): its Deliver is the stand-in of the adapter, so that nothing is opened. Deliver
/// records each message it is given under ^||OcuTalonEmailOutProbe("sent", n) = $ListBuild(from, to (comma-separated), subject, text, charset, multipart,
/// parts, attachments) and counts the calls in ^||OcuTalonEmailOutProbe("calls"). It answers by ^||OcuTalonEmailOutProbe("answer"): "" for OK, unreachable
/// (SMTPOpen), refused (SMTPAUTHFailed), rejected (SMTPResponse, whose text holds SERVER-WORDS and an address) or throw. The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutProbe Extends OcuTalon.Channel.Email.Out
{

Method Deliver(message As %Net.MailMessage) As %Status [ Private ]
{
	Set n = $Increment(^||OcuTalonEmailOutProbe("calls"))
	Set to = ""
	For i = 1:1:message.To.Count() Set to = to_$Select(to = "": "", 1: ",")_message.To.GetAt(i)
	Do message.TextData.Rewind()
	Set text = message.TextData.Read(1000000)
	Set ^||OcuTalonEmailOutProbe("sent", n) = $ListBuild(message.From, to, message.Subject, text, message.Charset, message.IsMultiPart, message.Parts.Count(), message.Cc.Count() + message.Bcc.Count())
	Set answer = $Get(^||OcuTalonEmailOutProbe("answer"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "SERVER-WORDS zzthrown@example.com"))
	If answer = "unreachable" Quit $$$ERROR($$$SMTPOpen)
	If answer = "refused" Quit $$$ERROR($$$SMTPAUTHFailed)
	If answer = "rejected" Quit $$$ERROR($$$SMTPResponse, "RCPT TO", "550 SERVER-WORDS zzrejected@example.com")
	Quit $$$OK
}

}
