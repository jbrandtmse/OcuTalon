/// The SSL step (AD-23, AD-19): makes the one general client SSL configuration of OcuTalon's outbound HTTPS, OcuTalonClient, in %SYS.
/// At every start the step creates it when it is absent and otherwise modifies it, writing five structural properties, so a change
/// by hand to any of them does not last: Type 0 (a client configuration), Enabled 1, VerifyPeer 1 (the server is verified), CAFile
/// %OSCertificateStore (the operating system's trusted CAs; on Linux, OpenSSL's default verify paths) and the Description. It writes
/// no other property: a new configuration has the TLS versions and ciphers that IRIS defaults to, and the step never writes a private
/// key, a certificate, a password or a credential of any kind. Every outbound HTTPS client of OcuTalon names it by its host setting
/// (Telegram's SSLConfig), and a request to an http:// base never uses it. The first failure is the status.
Class OcuTalon.Install.Step.SSL Extends OcuTalon.Install.Step
{

/// The name of the client configuration.
Parameter NAME = "OcuTalonClient";

/// The trusted CAs: the operating system's store.
Parameter CAFILE = "%OSCertificateStore";

Parameter DESCRIPTION = "OcuTalon's client configuration for outbound HTTPS: it verifies the server against the operating system's CA store. Written by the SSL install step at every start; do not edit.";

ClassMethod Run() As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Set properties("Type") = 0
	Set properties("Enabled") = 1
	Set properties("VerifyPeer") = 1
	Set properties("CAFile") = ..#CAFILE
	Set properties("Description") = ..#DESCRIPTION
	If ##class(Security.SSLConfigs).Exists(..#NAME) {
		Set sc = ##class(Security.SSLConfigs).Modify(..#NAME, .properties)
	} Else {
		Set sc = ##class(Security.SSLConfigs).Create(..#NAME, .properties)
	}
	If $SYSTEM.Status.IsError(sc) Quit $SYSTEM.Status.AppendStatus($SYSTEM.Status.Error(5001, $ClassName()_": the client SSL configuration "_..#NAME_" could not be made"), sc)
	Quit $SYSTEM.Status.OK()
}

}
