/// A %Net.SMTP for the tests (Story 21.6) that connects to nothing: Send records the settings that it was called with in
/// ^||OcuTalonEmailOutSender("sent") as $ListBuild(UseSTARTTLS, SSLConfiguration, SSLCheckServerIdentity, ContinueAfterBadSend) and answers OK. The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutSmtp Extends %Net.SMTP
{

Method Send(msg As %Net.MailMessage) As %Status
{
	Set ^||OcuTalonEmailOutSender("sent") = $ListBuild(..UseSTARTTLS, ..SSLConfiguration, ..SSLCheckServerIdentity, ..ContinueAfterBadSend)
	Quit $$$OK
}

}
