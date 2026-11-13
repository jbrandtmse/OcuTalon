Include Ensemble

/// The SMTP adapter of EmailOut (Story 21.6; AD-14, AD-19, AD-28, AD-33): EnsLib.EMail.OutboundAdapter with a send of its own. The parent logs the
/// address of every recipient that failed and sets the business host's Retry on a connect error, so that a send could repeat after DATA; this
/// adapter sends once and logs nothing. Its settings are the parent's: SMTPServer, SMTPPort, Credentials (the Interoperability credential
/// OcuTalonMail), SSLConfig (OcuTalonClient for implicit TLS, OcuTalonClient* for STARTTLS) and SSLCheckServerIdentity, which the product writes as
/// 1 and OnInit forces to 1, and the OAuth2 settings of Story 21.8.
/// The transport is TLS only (V7, ruling c). Each send, in order:
///   - Transport decides how to connect: "tls" when SSLConfig is exactly OcuTalonClient or OcuTalonClient* (with the server's host name checked),
///     "plain" only when PlainAllowed holds (the CI-only environment variable OCUTALON_TEST_PLAIN_SMTP is 1 AND the server host is exactly
///     mock, the CI stub), and "" for everything else, an empty or a foreign SSLConfig included: the send then fails (STARTTLSConfigRequired) before any
///     connection is made. No setting, row, route or form value can switch plain on;
///   - the credential OcuTalonMail is read again (never kept from an earlier send), so that a changed password applies at the next send; with no
///     credential or no user name the send fails (SMTPAUTHFailed) before any connection is made;
///   - with OAuth2ApplicationName set (a Google or Microsoft 365 sign-in) the handler OAuth2CallBackHandler (Channel.Email.Token) gives the access token,
///     which IRIS renews when it has expired, and the login is AUTH XOAUTH2 with the credential's user name; a token that cannot be had fails the send
///     (SMTPAUTHFailed). The token is held in the authenticator, and in the SASL mechanism of its login, for that send only and both are emptied after it, whatever the outcome;
///   - the message goes to %Net.SMTP once: ContinueAfterBadSend is 0 (a rejected recipient is the whole send's failure, no partial send) and a
///     failure is never repeated. Each command's timeout is TIMEOUT seconds (DATATIMEOUT for the end of the message), each under the 120 seconds that
///     the command gate waits; a whole send to a server that is slow at every command can still take longer than that.
/// SendMail answers the status of %Net.SMTP, and Classify says what a status means for the person: unreachable (the server could not be reached or
/// used: connection, TLS, STARTTLS, a first answer that is not a greeting, a timeout), refused (the user name or password was refused or there was
/// none, or in OAuth2 mode the token could not be had or was refused), or rejected (the server answered the sender, a recipient or the message with an error).
Class OcuTalon.Channel.Email.Sender Extends EnsLib.EMail.OutboundAdapter
{

/// The CI-only environment variable (ruling c) that lets the adapter use plain SMTP, and EmailIn's adapter plain POP3 in OAuth2 mode (PlainFor), and the one host name they then do.
/// It also allows plain POP3 in OAuth2 mode, for the CI mock only (host mock; set only in ci/compose.ci.yml).
Parameter PLAINVARIABLE = "OCUTALON_TEST_PLAIN_SMTP";

Parameter PLAINHOST = "mock";

/// The seconds that the server may take to answer a command, and to answer the end of the message.
Parameter TIMEOUT = 20;

Parameter DATATIMEOUT = 40;

/// What Classify answers.
Parameter UNREACHABLE = "unreachable";

Parameter REFUSED = "refused";

Parameter REJECTED = "rejected";

Method OnInit() As %Status
{
	Set sc = ##super()
	Set ..SSLCheckServerIdentity = 1
	Set ..ContinueAfterBadSend = 0
	If $IsObject(..SMTP) {
		Set ..SMTP.SSLCheckServerIdentity = 1
		Set ..SMTP.ContinueAfterBadSend = 0
		For command = "EHLO", "HELO", "MAIL", "RCPT", "AUTH", "STARTTLS", "RSET", "QUIT", "DATA", ##class(%Net.SMTP).#TimeoutKeyInitial {
			Set ..SMTP.Timeouts(command) = ..#TIMEOUT
		}
		Set ..SMTP.Timeouts(##class(%Net.SMTP).#TimeoutKeyDataTermination) = ..#DATATIMEOUT
	}
	Quit sc
}

/// The client SSL/TLS configuration that the installer makes (Install.Step.SSL).
ClassMethod Client() As %String
{
	Quit ##class(OcuTalon.Install.Step.SSL).#NAME
}

/// 1 when the CI-only environment variable is 1 (IsOn). A test subclass overrides it to stand in for a job that does not have the variable.
ClassMethod SwitchOn() As %Boolean
{
	Quit ..IsOn($SYSTEM.Util.GetEnviron(..#PLAINVARIABLE))
}

/// 1 only when the value of the variable is exactly 1.
ClassMethod IsOn(value As %String) As %Boolean
{
	Quit ($Get(value) = "1")
}

/// 1 when plain SMTP is allowed for the host: the switch is on and the host is exactly the CI stub's.
ClassMethod PlainAllowed(host As %String) As %Boolean
{
	Quit ..PlainFor($Get(host), ..SwitchOn())
}

/// The rule of PlainAllowed for a given state of the switch: plain is allowed only when the switch is on and the host is exactly the CI stub's. EmailIn's adapter
/// (Channel.Email.Adapter) applies the same rule to its POP3 connection in OAuth2 mode, so there is one rule for the plain exception.
ClassMethod PlainFor(host As %String, switchOn As %Boolean) As %Boolean
{
	Quit $Get(switchOn) && ($Get(host) = ..#PLAINHOST)
}

/// How this send connects: "plain", "tls" or "" (see the class description).
Method Transport() As %String
{
	If ..PlainAllowed(..SMTPServer) Quit "plain"
	Set config = $ZStrip(..SSLConfig, "<>WC")
	If (config = ..Client()) || (config = (..Client()_"*")) Quit "tls"
	Quit ""
}

/// Sends the message once; see the class description. pFailedRecipients is always empty.
Method SendMail(pMailMessage As %Net.MailMessage, Output pFailedRecipients As %ListOfDataTypes) As %Status
{
	Kill pFailedRecipients
	Set pFailedRecipients = $$$NULLOREF
	Set transport = ..Transport()
	If transport = "" Quit $$$ERROR($$$STARTTLSConfigRequired)
	Do ..CredentialsSet(..Credentials)
	If '$IsObject(..%CredentialsObj) || (..%CredentialsObj.Username = "") Quit $$$ERROR($$$SMTPAUTHFailed)
	Set ..SMTP.UseSTARTTLS = 0
	Set ..SMTP.SSLConfiguration = ""
	If transport = "tls" {
		Set config = $ZStrip(..SSLConfig, "<>WC")
		Set ..SMTP.UseSTARTTLS = ("*" = $Extract(config, *))
		Set ..SMTP.SSLConfiguration = $Select(..SMTP.UseSTARTTLS: $Extract(config, 1, *-1), 1: config)
	}
	Set ..SMTP.SSLCheckServerIdentity = 1
	Set ..SMTP.ContinueAfterBadSend = 0
	If ..OAuth2ApplicationName '= "" {
		Set granted = 0, token = ""
		Try {
			Set sc = $ClassMethod(..OAuth2CallBackHandler, "OnGetAccessToken", $This, ..OAuth2GrantType, ..OAuth2ApplicationName, ..OAuth2SessionId, ..%CredentialsObj.Username, ..OAuth2Scope, ..OAuth2AuthProperties, ..OAuth2GrantTypeSpecific, .granted, .token)
		} Catch exception {
			Set sc = exception.AsStatus(), token = ""
		}
		If $$$ISERR(sc) || '$Get(granted) || (token = "") Quit $$$ERROR($$$SMTPAUTHFailed)
		Set ..SMTP.authenticator.AccessToken = token
		Kill token
	}
	Try {
		Set sc = ..SMTP.Send(pMailMessage)
	} Catch exception {
		If ..OAuth2ApplicationName '= "" Do ..ForgetToken()
		Throw exception
	}
	If ..OAuth2ApplicationName '= "" Do ..ForgetToken()
	Quit sc
}

/// Empties the access token from the authenticator and drops the SASL mechanism that its login made, which holds a copy of the token (%Net.Authenticator.Start).
Method ForgetToken() [ Private ]
{
	Set ..SMTP.authenticator.AccessToken = "", ..SMTP.authenticator.Mechanism = ""
}

/// What a failed send means: UNREACHABLE, REFUSED or REJECTED (see the class description). An OK status gives "".
ClassMethod Classify(sc As %Status) As %String
{
	If $$$ISOK($Get(sc, $$$OK)) Quit ""
	If $$$StatusEquals(sc, $$$SMTPAUTHFailed) Quit ..#REFUSED
	If $$$StatusEquals(sc, $$$SMTPResponse) || $$$StatusEquals(sc, $$$SMTPNoSend) Quit ..#REJECTED
	Quit ..#UNREACHABLE
}

}
