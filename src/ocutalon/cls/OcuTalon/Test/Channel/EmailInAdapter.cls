/// A subclass of OcuTalon.Channel.Email.Adapter for the tests (Story 21.2): its OnInit is the real one, and then it replaces the connection by an
/// OcuTalon.Test.Channel.EmailInPop3, so nothing is opened. CredentialsSet makes a credential object that is never stored (user zzmailuser), and Deliver
/// records each email it is given under ^||OcuTalonEmailInAdapter("delivered", n) = $ListBuild(uidl, sender, subject, text) and its SentRef under ^||OcuTalonEmailInAdapter("delivered", n, "ref") and answers an error status when
/// ^||OcuTalonEmailInAdapter("fail") is 1, or at its nth call since ^||OcuTalonEmailInAdapter("calls") was set to 0 when ^||OcuTalonEmailInAdapter("failAt") is n. Like
/// Ens.BusinessService.ProcessInput, a hand-off clears the business host's %WaitForNextCallInterval when the adapter has a host. StopAsked answers 1 once
/// ^||OcuTalonEmailInAdapter("stopAfter") emails have been handed on. SwitchOn stands in for the CI-only environment variable of the job: it answers 1 when
/// ^||OcuTalonEmailInAdapter("plain") is 1. The product never refers to it.
Class OcuTalon.Test.Channel.EmailInAdapter Extends OcuTalon.Channel.Email.Adapter
{

Method OnInit() As %Status
{
	Set sc = ##super()
	Set ..MailServer = ##class(OcuTalon.Test.Channel.EmailInPop3).%New()
	Quit sc
}

ClassMethod SwitchOn() As %Boolean
{
	Quit ($Get(^||OcuTalonEmailInAdapter("plain")) = 1)
}

Method CredentialsSet(pInVal As %String) As %Status
{
	Set credential = ##class(Ens.Config.Credentials).%New()
	Set credential.Password = "zz-not-a-password"
	Set credential.Username = $Select($Get(^||OcuTalonEmailInAdapter("user")) '= "": ^||OcuTalonEmailInAdapter("user"), 1: "zzmailuser")
	Set ..%CredentialsObj = credential
	Set i%Credentials = pInVal
	Quit $$$OK
}

Method StopAsked() As %Boolean [ Private ]
{
	Quit ($Get(^||OcuTalonEmailInAdapter("stopAfter")) '= "") && (+$Get(^||OcuTalonEmailInAdapter("delivered")) >= ^||OcuTalonEmailInAdapter("stopAfter"))
}

Method Deliver(mail As OcuTalon.Channel.Email.Mail) As %Status [ Private ]
{
	If $IsObject(..BusinessHost) Set ..BusinessHost.%WaitForNextCallInterval = 0
	If $Get(^||OcuTalonEmailInAdapter("fail")) || ($Get(^||OcuTalonEmailInAdapter("failAt")) && ($Increment(^||OcuTalonEmailInAdapter("calls")) = ^||OcuTalonEmailInAdapter("failAt"))) Quit $SYSTEM.Status.Error(5001, "SERVER-WORDS the service refused zzserver@example.com")
	Set n = $Increment(^||OcuTalonEmailInAdapter("delivered"))
	Set ^||OcuTalonEmailInAdapter("delivered", n) = $ListBuild(mail.Uidl, mail.Sender, mail.Subject, mail.Text)
	Set ^||OcuTalonEmailInAdapter("delivered", n, "ref") = mail.SentRef
	Quit $$$OK
}

}
