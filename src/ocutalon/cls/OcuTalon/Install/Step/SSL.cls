/// The SSL step (AD-23, AD-19): makes the one general client SSL configuration of OcuTalon's outbound HTTPS, OcuTalonClient, in %SYS.
/// It is structural: at every start the step creates it when it is absent and otherwise modifies it, so a value changed by hand does
/// not last. The configuration is a client configuration (Type 0), enabled, that verifies the server (VerifyPeer 1) against the
/// operating system's trusted CA store (CAFile %OSCertificateStore), with the TLS versions that IRIS defaults to. It holds no secret:
/// no private key, no certificate, no password and no credential of any kind. Every outbound HTTPS client of OcuTalon names it by
/// its host setting (Telegram's SSLConfig), and a request to an http:// base never uses it. The first failure is the status.
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
