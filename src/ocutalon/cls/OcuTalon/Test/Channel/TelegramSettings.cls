/// Tests of the Telegram endpoint settings and of the client SSL configuration (Story 12.2; AD-19, AD-23, NFR-11, U-164). THESE TESTS RUN
/// IN FRESH THROWAWAY STACKS AND IN CI ONLY (Rule 21), never warm and never on a dev slot, because they change the SSL configuration
/// OcuTalonClient in %SYS; each puts back what it changed.
///   - TestEndpointSettings: the ApiBase rows of both items hold the base of OCUTALON_TELEGRAM_API_BASE (the public API when it is empty),
///     Install.Step.Telegram.Base writes both, a row changed by hand is written again by Run(), and both items resolve SSLConfig to
///     OcuTalonClient;
///   - TestSSLConfiguration: OcuTalonClient exists as an enabled client configuration that verifies the peer against the OS store, and
///     the SSL step puts back a value changed by hand (VerifyPeer), and creates it when it is absent;
///   - TestCAFileInImage (U-164 condition 1): the CA bundle that the OS store stands for exists in this image and holds certificates;
///   - TestBadCertificateRefused (U-164 condition 1): a disposable TLS server with a self-signed certificate, started by the test in its
///     own container on a loopback port, answers a client configuration that trusts its certificate and is refused by OcuTalonClient;
///     OcuTalonClient's OS store follows OpenSSL's default verify paths (SSL_CERT_FILE), so on Linux it reads TestCAFileInImage's
///     bundle; and Api.Call over https uses the SSL configuration it is given.
Class OcuTalon.Test.Channel.TelegramSettings Extends %UnitTest.TestCase
{

Parameter PRODUCTION = "OcuTalon.Production";

Parameter STEP = "OcuTalon.Install.Step.Telegram";

Parameter SSLSTEP = "OcuTalon.Install.Step.SSL";

Parameter API = "OcuTalon.Channel.Telegram.Api";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The rows saved by a test: a list of RunnerFixture snapshots.
Property Rows As %String(MAXLEN = "") [ Private ];

/// The Telegram state mark as found.
Property MarkFound As %String(MAXLEN = "") [ Private ];

/// The seam ^OcuTalonTest("TelegramIncluded") as found: $Data and the value.
Property SeamData As %Integer [ Private ];

Property SeamValue As %String [ Private ];

/// 1 when this stack may be changed: a throwaway with the mock (the CI override sets the Bot API base).
Method Guard() As %Boolean [ Private ]
{
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set reason = $ClassMethod(mock, "TelegramMissingReason", $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMBASEVAR")), $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMTOKENVAR")))
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason '= "" Do $$$AssertTrue(0, reason)
	Quit reason = ""
}

/// Saves the four rows that Run() writes, the mark and the seam.
Method Save() [ Private ]
{
	Set rows = ""
	For item = "TelegramIn", "TelegramOut" {
		For setting = "Enabled", "ApiBase" {
			Do $ClassMethod(..#FIXTURE, "RememberDefault", .rows, item, setting)
		}
	}
	Set ..Rows = rows
	Set ..MarkFound = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK)
	Set ..SeamData = $Data(^OcuTalonTest("TelegramIncluded"))
	Set ..SeamValue = $Get(^OcuTalonTest("TelegramIncluded"))
}

/// Puts the saved rows, the mark and the seam back.
Method Restore() [ Private ]
{
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "RestoreDefaults", ..Rows), "the Enabled and ApiBase rows are put back")
	Do ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK, ..MarkFound)
	If ..SeamData {
		Set ^OcuTalonTest("TelegramIncluded") = ..SeamValue
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
}

/// What the ApiBase row of the item holds, or "-" when there is none.
Method Row(item As %String) As %String [ Private ]
{
	Set id = ..#PRODUCTION_"||"_item_"||*||ApiBase"
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit "-"
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// The base that a start writes: the variable's value, or the public API.
Method Expected() As %String [ Private ]
{
	Set value = $SYSTEM.Util.GetEnviron($Parameter(..#API, "BASEVAR"))
	Quit $Select(value = "": $Parameter(..#API, "PUBLICBASE"), 1: value)
}

/// The ApiBase rows, Base(), Run() and the SSLConfig default.
Method TestEndpointSettings()
{
	If '..Guard() Quit
	Do ..Save()
	Try {
		Set expected = ..Expected()
		Do $$$AssertEquals(..Row("TelegramIn")_"|"_..Row("TelegramOut"), expected_"|"_expected, "a start wrote the ApiBase row of both items from the environment")
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "Base", ""), "Base with an empty value succeeds")
		Set public = $Parameter(..#API, "PUBLICBASE")
		Do $$$AssertEquals(..Row("TelegramIn")_"|"_..Row("TelegramOut"), public_"|"_public, "both rows hold the public API")
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "Base", "http://mock:8080"), "Base with a value succeeds")
		Do $$$AssertEquals(..Row("TelegramIn")_"|"_..Row("TelegramOut"), "http://mock:8080|http://mock:8080", "both rows hold the value")
		Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", "TelegramIn", "ApiBase", "http://zz-by-hand:1"), "a row is changed by hand")
		Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(0)
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "Run succeeds")
		Do $$$AssertEquals(..Row("TelegramIn")_"|"_..Row("TelegramOut"), expected_"|"_expected, "and writes the row again")
		For item = "TelegramIn", "TelegramOut" {
			Set host = ##class(Ens.Host).GetShadowInstance(..#PRODUCTION_"||"_item, .sc)
			Do $$$AssertStatusOK(sc, item_": the item is resolved")
			If $IsObject(host) {
				Do $$$AssertEquals(host.SSLConfig, "OcuTalonClient", item_" resolves SSLConfig to OcuTalonClient")
				Do $$$AssertEquals(host.ApiBase, expected, item_" resolves ApiBase to the row")
			}
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the endpoint test failed: "_$Translate(ex.DisplayString(), $Char(13, 10), "  "))
	}
	Do ..Restore()
}

/// The properties of OcuTalonClient, as "type|enabled|verify|CA file", or "" when it is absent.
ClassMethod Client() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	If '##class(Security.SSLConfigs).Exists("OcuTalonClient") Quit ""
	If $$$ISERR(##class(Security.SSLConfigs).Get("OcuTalonClient", .properties)) Quit "-"
	Quit properties("Type")_"|"_properties("Enabled")_"|"_properties("VerifyPeer")_"|"_properties("CAFile")
}

/// Changes a property of OcuTalonClient (in %SYS).
ClassMethod Change(property As %String, value As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Set properties(property) = value
	Quit ##class(Security.SSLConfigs).Modify("OcuTalonClient", .properties)
}

/// Deletes OcuTalonClient (in %SYS).
ClassMethod Drop() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.SSLConfigs).Delete("OcuTalonClient")
}

/// OcuTalonClient: a client configuration that verifies the peer against the OS store, kept by the SSL step.
Method TestSSLConfiguration()
{
	If '..Guard() Quit
	Try {
		Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "OcuTalonClient exists: client, enabled, VerifyPeer 1, the OS store")
		Do $$$AssertStatusOK(..Change("VerifyPeer", 0), "VerifyPeer is set to 0 by hand")
		Do $$$AssertEquals(..Client(), "0|1|0|%OSCertificateStore", "and it holds 0")
		Do $$$AssertStatusOK($ClassMethod(..#SSLSTEP, "Run"), "the SSL step runs")
		Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "and puts VerifyPeer back to 1")
		Do $$$AssertStatusOK(..Change("Enabled", 0), "the configuration is disabled by hand")
		Do $$$AssertStatusOK($ClassMethod(..#SSLSTEP, "Run"), "the SSL step runs")
		Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "and enables it")
		Do $$$AssertStatusOK(..Drop(), "the configuration is deleted")
		Do $$$AssertEquals(..Client(), "", "and is absent")
		Do $$$AssertStatusOK($ClassMethod(..#SSLSTEP, "Run"), "the SSL step runs")
		Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "and creates it")
	} Catch ex {
		Do $$$AssertTrue(0, "the SSL test failed: "_$Translate(ex.DisplayString(), $Char(13, 10), "  "))
	}
	If ..Client() '= "0|1|1|%OSCertificateStore" Do $ClassMethod(..#SSLSTEP, "Run")
}

/// The CA bundle of the image (Ubuntu's ca-certificates).
Parameter BUNDLE = "/etc/ssl/certs/ca-certificates.crt";

/// OpenSSL's default CA file (OPENSSLDIR/cert.pem of the image's libssl, which IRIS loads), which the OS store reads on Linux
/// (TestBadCertificateRefused shows that it follows OpenSSL's default verify paths).
Parameter DEFAULTBUNDLE = "/usr/lib/ssl/cert.pem";

/// OpenSSL's variable that names the default CA file in place of DEFAULTBUNDLE.
Parameter CERTFILEVAR = "SSL_CERT_FILE";

/// The number of certificates in a PEM file, or -1 when the file cannot be read.
ClassMethod Certificates(file As %String) As %Integer [ Private ]
{
	If '##class(%File).Exists(file) Quit -1
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set count = 0
	While 'stream.AtEnd {
		If $Extract(stream.ReadLine(), 1, 27) = "-----BEGIN CERTIFICATE-----" Set count = count + 1
	}
	Quit count
}

/// U-164 condition 1: the CA bundle that OcuTalonClient's OS store stands for exists in this image, and holds certificates.
Method TestCAFileInImage()
{
	If '..Guard() Quit
	Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "OcuTalonClient names the OS store")
	Do $$$AssertTrue(..Certificates(..#BUNDLE) > 50, "the image's CA bundle "_..#BUNDLE_" exists and holds certificates: "_..Certificates(..#BUNDLE))
	Do $$$AssertEquals(..Certificates(..#DEFAULTBUNDLE), ..Certificates(..#BUNDLE), "OpenSSL's default bundle "_..#DEFAULTBUNDLE_" leads to the same file")
}

/// The disposable TLS server of TestBadCertificateRefused: a self-signed certificate that the test makes, and openssl s_server on a
/// loopback port, both in a temporary folder of this container. 1 when it started; dir, port and cert say where.
Method StartServer(Output dir As %String, Output port As %Integer, Output cert As %String) As %Boolean [ Private ]
{
	Set dir = ##class(%File).TempFilename("d")
	Do ##class(%File).Delete(dir)
	Set dir = dir_"/"
	If '##class(%File).CreateDirectoryChain(dir) Quit 0
	Set cert = dir_"cert.pem"
	Set key = dir_"key.pem"
	Set made = $ZF(-100, "", "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-subj", "/CN=ocutalon-test", "-days", "1", "-addext", "subjectAltName=IP:127.0.0.1")
	If made '= 0 Quit 0
	Set port = 40000 + $Random(10000)
	Set script = "echo $$ > "_dir_"pid; exec openssl s_server -accept 127.0.0.1:"_port_" -cert "_cert_" -key "_key_" -www -quiet"
	Quit $ZF(-100, "/ASYNC", "sh", "-c", script) = 0
}

/// Stops the server and removes its folder.
Method StopServer(dir As %String) [ Private ]
{
	If dir = "" Quit
	If ##class(%File).Exists(dir_"pid") {
		Set stream = ##class(%Stream.FileCharacter).%New()
		Do stream.LinkToFile(dir_"pid")
		Set pid = $ZStrip(stream.ReadLine(), "<>W")
		Kill stream
		If pid ? 1.N Do $ZF(-100, "", "kill", pid)
	}
	Do ##class(%File).RemoveDirectoryTree(dir)
}

/// A GET of the server over TLS with the SSL configuration; the status is the request's, and code is the HTTP status or "".
ClassMethod Get(port As %Integer, config As %String, Output code As %String) As %Status [ Private ]
{
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = port
	Set request.Https = 1
	Set request.SSLConfiguration = config
	Set request.Timeout = 5
	Set sc = request.Get("/")
	Set code = $Select($IsObject(request.HttpResponse): request.HttpResponse.StatusCode, 1: "")
	Quit sc
}

/// Makes the throwaway client configuration ZzTrustTest, which trusts the file (in %SYS); deletes it for a file of "".
ClassMethod Trust(file As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If file = "" Quit $Select(##class(Security.SSLConfigs).Exists("ZzTrustTest"): ##class(Security.SSLConfigs).Delete("ZzTrustTest"), 1: $$$OK)
	Kill properties
	Set properties("Type") = 0
	Set properties("Enabled") = 1
	Set properties("VerifyPeer") = 1
	Set properties("CAFile") = file
	Quit $Select(##class(Security.SSLConfigs).Exists("ZzTrustTest"): ##class(Security.SSLConfigs).Modify("ZzTrustTest", .properties), 1: ##class(Security.SSLConfigs).Create("ZzTrustTest", .properties))
}

/// U-164 condition 1: a request through OcuTalonClient to a TLS server with a bad certificate (self-signed, started here, in this
/// container, on a loopback port) is refused. The control: the same server answers a client configuration that trusts its certificate,
/// so the refusal is the verification, not a broken server. Then the OS store is shown to be OpenSSL's default verify paths: with
/// SSL_CERT_FILE naming the server's certificate in this process, OcuTalonClient trusts it, so without the variable it trusts OpenSSL's
/// default CA file, the image's bundle (TestCAFileInImage). Last, Api.Call over https uses the configuration it is given: through
/// OcuTalonClient the handshake succeeds, and through a configuration that does not exist it fails (error 6085). The variable is put
/// back as found on every path.
Method TestBadCertificateRefused()
{
	If '..Guard() Quit
	Set dir = ""
	Set env = "OcuTalon.Test.Agent.KeyScan"
	Set hadVar = $ClassMethod(env, "HasEnv", ..#CERTFILEVAR)
	Set varFound = $SYSTEM.Util.GetEnviron(..#CERTFILEVAR)
	Try {
		Do $$$AssertTrue(..StartServer(.dir, .port, .cert), "the disposable TLS server is started on a loopback port")
		Do $$$AssertEquals(..Client(), "0|1|1|%OSCertificateStore", "OcuTalonClient exists: client, enabled, VerifyPeer 1, the OS store")
		Do $$$AssertStatusOK(..Trust(cert), "a client configuration that trusts the server's certificate is made")
		Set deadline = $ZHorolog + 15
		For {
			Set sc = ..Get(port, "ZzTrustTest", .code)
			If $$$ISOK(sc) || ($ZHorolog >= deadline) Quit
			Hang 0.5
		}
		Do $$$AssertStatusOK(sc, "the server answers a client that trusts its certificate")
		Do $$$AssertEquals(code, 200, "with HTTP 200")
		Set sc = ..Get(port, "OcuTalonClient", .code)
		Do $$$AssertStatusNotOK(sc, "OcuTalonClient refuses the server's self-signed certificate")
		Do $$$AssertEquals(code, "", "and no HTTP answer was read")
		Do $ClassMethod(env, "SetEnv", ..#CERTFILEVAR, cert)
		Set sc = ..Get(port, "OcuTalonClient", .code)
		Do $$$AssertStatusOK(sc, "with SSL_CERT_FILE naming the certificate, OcuTalonClient trusts it: its OS store is OpenSSL's default verify paths")
		Do $$$AssertEquals(code, 200, "with HTTP 200")
		Set base = "https://127.0.0.1:"_port
		Set answer = $ClassMethod(..#API, "Call", base, "OcuTalonClient", "getMe", {}, 2, .status, .sc)
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(($Find(text, "(error 6085)") = 0) && ($Find(text, "(error 6159)") = 0), "Api.Call over https through OcuTalonClient gets past the handshake: "_text)
		Set answer = $ClassMethod(..#API, "Call", base, "ZzNoSuchSSLConfig", "getMe", {}, 2, .status, .sc)
		Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "(error 6085)") > 0, "and through a configuration that does not exist it fails at the handshake")
	} Catch ex {
		Do $$$AssertTrue(0, "the bad-certificate test failed: "_$Translate(ex.DisplayString(), $Char(13, 10), "  "))
	}
	If hadVar {
		Do $ClassMethod(env, "SetEnv", ..#CERTFILEVAR, varFound)
	} Else {
		Do $ClassMethod(env, "UnsetEnv", ..#CERTFILEVAR)
	}
	Do ..StopServer(dir)
	Do $$$AssertStatusOK(..Trust(""), "the test's client configuration is deleted")
}

}
