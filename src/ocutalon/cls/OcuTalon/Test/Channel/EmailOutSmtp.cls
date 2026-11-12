/// A %Net.SMTP for the tests (Story 21.6) that connects to nothing: Send records the settings that it was called with in
/// ^||OcuTalonEmailOutSender("sent") as $ListBuild(UseSTARTTLS, SSLConfiguration, SSLCheckServerIdentity, ContinueAfterBadSend) and the access token that its authenticator held
/// in ^||OcuTalonEmailOutSender("token"), and answers OK; with ^||OcuTalonEmailOutSender("throw") set it raises an exception instead. The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutSmtp Extends %Net.SMTP
{

Method Send(msg As %Net.MailMessage) As %Status
{
	Set ^||OcuTalonEmailOutSender("sent") = $ListBuild(..UseSTARTTLS, ..SSLConfiguration, ..SSLCheckServerIdentity, ..ContinueAfterBadSend)
	Set ^||OcuTalonEmailOutSender("token") = ..authenticator.AccessToken
	If $Get(^||OcuTalonEmailOutSender("throw")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz thrown"))
	Quit $$$OK
}

}
