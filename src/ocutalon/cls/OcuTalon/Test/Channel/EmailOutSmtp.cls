/// A Channel.Email.SMTP (a %Net.SMTP with DataBegan) for the tests (Story 21.6) that connects to nothing: Send records the settings that it was called with in
/// ^||OcuTalonEmailOutSender("sent") as $ListBuild(UseSTARTTLS, SSLConfiguration, SSLCheckServerIdentity, ContinueAfterBadSend) and the access token that its authenticator held
/// in ^||OcuTalonEmailOutSender("token"); with a token it logs in as %Net.SMTP does (the authenticator's Start with XOAUTH2, which copies the token into its mechanism)
/// and records the mechanism's copy in ^||OcuTalonEmailOutSender("mechanism"). It answers OK; with ^||OcuTalonEmailOutSender("throw") set it raises an exception instead; with
/// ^||OcuTalonEmailOutSender("status") set it answers that status (an SMTPTimeout, say), and it sets DataBegan to ^||OcuTalonEmailOutSender("databegan") (the flag that the real SMTP
/// object sets once the server has answered DATA with 354).
/// The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutSmtp Extends OcuTalon.Channel.Email.SMTP
{

Method Send(msg As %Net.MailMessage) As %Status
{
	Set ..DataBegan = +$Get(^||OcuTalonEmailOutSender("databegan"))
	Set ^||OcuTalonEmailOutSender("sent") = $ListBuild(..UseSTARTTLS, ..SSLConfiguration, ..SSLCheckServerIdentity, ..ContinueAfterBadSend)
	Set ^||OcuTalonEmailOutSender("token") = ..authenticator.AccessToken
	If ..authenticator.AccessToken '= "" {
		Do ..authenticator.Start("XOAUTH2", .mechanism, .response)
		Set ^||OcuTalonEmailOutSender("mechanism") = $Select($IsObject(..authenticator.Mechanism): ..authenticator.Mechanism.AccessToken, 1: "")
	}
	If $Get(^||OcuTalonEmailOutSender("throw")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz thrown"))
	If $Data(^||OcuTalonEmailOutSender("status"), status) Quit status
	Quit $$$OK
}

}
