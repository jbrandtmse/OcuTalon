/// A subclass of OcuTalon.Channel.Email.Sender for the tests (Story 21.6): SwitchOn stands in for the CI-only environment variable of the job and answers
/// ^||OcuTalonEmailOutSender("switch"), so that a test can have it on or off whatever the job's environment says; CredentialsSet, when
/// ^||OcuTalonEmailOutSender("user") is set, stands in for the Interoperability credential with that user name. The product never refers to it.
Class OcuTalon.Test.Channel.EmailOutSender Extends OcuTalon.Channel.Email.Sender
{

ClassMethod SwitchOn() As %Boolean
{
	Quit +$Get(^||OcuTalonEmailOutSender("switch"))
}

Method CredentialsSet(name As %String) As %Status
{
	If '$Data(^||OcuTalonEmailOutSender("user"), user) Quit ##super(name)
	Set credentials = ##class(Ens.Config.Credentials).%New()
	Set credentials.Username = user
	Set ..%CredentialsObj = credentials
	Quit $$$OK
}

}
