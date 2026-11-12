Include Ensemble

/// The POP3 adapter of EmailIn (Story 21.2; AD-14, AD-19, AD-28, AD-33): EnsLib.EMail.InboundAdapter with a poll of its own. The parent
/// re-reads every message on every poll, logs From, To and Subject, and leaves repeated downloads to the service ("Service code
/// responsibility"); this poll keeps what it has seen, reads only new mail, logs counts only and never deletes. Its settings are the
/// parent's: POP3Server, POP3Port, Credentials (the Interoperability credential OcuTalonMail), SSLConfig (OcuTalonClient, or
/// OcuTalonClient* for STARTTLS on port 110) and the OAuth2 settings that Story 21.3 uses; the product offers no plain connection.
/// DeleteMessage is forced to 0 at OnInit, whatever the setting says; a poll deletes an email from the server only when the property is 1. Each poll, in order:
///   - reads the credential again (a changed password applies at the next poll), connects, and lists the unique ids (UIDL);
///   - a mailbox that is new to EmailIn (Data.MailSeen holds no baseline marker for its identity, the hash of server, port and user name)
///     is baselined: every listed UIDL is recorded seen (Baseline 1) and no Item is made, so only mail that arrives afterwards is read;
///   - otherwise every listed UIDL with no row is new; the oldest NEWMAX of them go on (the rest wait for the next poll). A new email
///     over MAXBYTES (the LIST size) is read as headers only (Sender and Subject, an empty Text), and so is one whose whole read failed in
///     READTRIES polls of this job; any other is fetched. The Mail
///     (Sender, Subject, Text: the plain part, else the HTML part with its tags removed, cut to the size of the simulated mailbox)
///     goes to the service through Deliver, and its UIDL is recorded seen when the service took it. A refusal stops the poll, and what was
///     recorded stays; a refused hand-off is the service's (no owner session, no send) and is tried again at the next poll. When the
///     production asks the item to stop (StopAsked), the poll ends after the email in hand, as a good poll, and the rest wait for the next;
///   - after a poll that reached its end the rows of mail that is no longer listed, and every row of another mailbox, are deleted;
///   - QUIT: the connection is closed with no DELE ever sent.
/// Every poll ends with the status mark emailPoll (StatusMark.Record): {at, ok, reason, lastOkAt}. The reason of a failed poll is one of
/// three plain sentences and never holds server text, an address or a credential: REASONUNREACHABLE when the connection or the TLS
/// handshake failed or the server did not greet as a POP3 server (another protocol, or no greeting in time), REASONREFUSED when it answered
/// -ERR while connecting (to USER, PASS or STLS), REASONUNREADABLE for any other failure. A poll that handed an email on still waits
/// CallInterval for the next one (the framework would otherwise poll again at once), so at most NEWMAX emails go on per interval.
/// OnTask returns OK for a failed poll too, logging the reason as a warning and nothing else, because the framework would log the
/// text of an error status, and that text can hold the server's words.
Class OcuTalon.Channel.Email.Adapter Extends EnsLib.EMail.InboundAdapter
{

/// The most new emails one poll hands on (RULED V-COST).
Parameter NEWMAX = 50;

/// The largest email, in bytes, that is read whole; a larger one is read as headers only.
Parameter MAXBYTES = 1048576;

/// The status mark of the poll outcome (AD-14).
Parameter MARK = "emailPoll";

/// The reasons of a failed poll (Public text P1a to P1c).
Parameter REASONUNREACHABLE = "OcuTalon couldn't reach the mail server.";

Parameter REASONREFUSED = "The mail server refused the user name or password.";

Parameter REASONUNREADABLE = "OcuTalon couldn't read the mailbox.";

/// The status code of a POP3 server's -ERR answer ($$$POP3Error).
Parameter POP3ERROR = 6015;

/// The polls in a row that may fail to read one new email whole; after them it is read as headers only, as an email over MAXBYTES is.
Parameter READTRIES = 3;

/// The failed whole reads of a new email in this job, by UIDL.
Property ReadFailures As %String [ MultiDimensional, Private ];

/// The read timeout of the POP3 connection, in seconds (the class's default is 30): under the 10 seconds that a production update waits for an
/// item to stop, so that one read that hangs ends in time for the update; between emails the poll ends early when a stop is asked (StopAsked).
Parameter TIMEOUT = 8;

Method OnInit() As %Status
{
	Set sc = ##super()
	Set ..DeleteMessage = 0
	Set ..MailServer.timeout = ..#TIMEOUT
	Quit sc
}

/// One poll, as the class description says. It never throws and always returns OK.
Method OnTask() As %Status
{
	Set reason = "", handed = 0, baseline = 0
	Try {
		Set ok = ..Poll(.reason, .handed, .baseline)
	} Catch {
		Set ok = 0
		Set reason = ..#REASONUNREADABLE
	}
	If $IsObject(..BusinessHost) Set ..BusinessHost.%WaitForNextCallInterval = 1
	Try {
		If ..MailServer.Connected Do ..MailServer.QuitAndCommit()
	} Catch {
	}
	Try {
		Do ..Record(ok, reason)
		If 'ok {
			$$$LOGWARNING(reason)
		} ElseIf handed || baseline {
			$$$LOGINFO("EmailIn read "_handed_" new email(s)"_$Select(baseline: " and recorded "_baseline_" existing one(s) as seen", 1: ""))
		}
	} Catch {
	}
	Quit $$$OK
}

/// One poll: 1 when it reached its end, else 0 with the plain reason. handed is the number of emails sent on, baseline the number of
/// existing emails recorded as seen by a first poll.
Method Poll(Output reason As %String, Output handed As %Integer, Output baseline As %Integer) As %Boolean [ Private ]
{
	Set reason = "", handed = 0, baseline = 0
	Do ..CredentialsSet(..Credentials)
	If '$IsObject(..%CredentialsObj) {
		Set reason = ..#REASONUNREADABLE
		Quit 0
	}
	Set token = ""
	If ..OAuth2ApplicationName '= "" {
		Set granted = 0
		Set sc = $ClassMethod(..OAuth2CallBackHandler, "OnGetAccessToken", $This, ..OAuth2GrantType, ..OAuth2ApplicationName, ..OAuth2SessionId, ..%CredentialsObj.Username, ..OAuth2Scope, ..OAuth2AuthProperties, ..OAuth2GrantTypeSpecific, .granted, .token)
		If $$$ISERR(sc) {
			Set reason = ..#REASONREFUSED
			Quit 0
		}
	}
	Set sc = ..MailServer.ConnectPort(..POP3Server, ..POP3Port, ..%CredentialsObj.Username, ..%CredentialsObj.Password, token)
	If $$$ISERR(sc) {
		Set reason = ..ConnectReason(sc)
		Quit 0
	}
	Set mailbox = ##class(OcuTalon.Data.MailSeen).IdentityOf(..POP3Server, ..POP3Port, ..%CredentialsObj.Username)
	Set sc = ..MailServer.GetMessageUIDArray("", .uids)
	If $$$ISERR(sc) || '$IsObject($Get(uids)) {
		Set reason = ..#REASONUNREADABLE
		Quit 0
	}
	Kill listed
	For n = 1:1:uids.Count() {
		If uids.GetAt(n) '= "" Set listed(uids.GetAt(n)) = ""
	}
	If '##class(OcuTalon.Data.MailSeen).Baselined(mailbox) {
		For n = 1:1:uids.Count() {
			Set sc = ##class(OcuTalon.Data.MailSeen).Record(mailbox, uids.GetAt(n), 1)
			If $$$ISERR(sc) Quit
			Set baseline = baseline + 1
		}
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.MailSeen).Record(mailbox, ##class(OcuTalon.Data.MailSeen).#MARKER, 1)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.MailSeen).Trim(mailbox, .listed)
		If $$$ISERR(sc) {
			Set reason = ..#REASONUNREADABLE
			Quit 0
		}
		Quit 1
	}
	Set new = ""
	For n = 1:1:uids.Count() {
		If $ListLength(new) >= ..#NEWMAX Quit
		If '##class(OcuTalon.Data.MailSeen).Seen(mailbox, uids.GetAt(n)) Set new = new_$ListBuild(n)
	}
	If new '= "" {
		Set sc = ..MailServer.GetSizeOfMessages("", .sizes)
		If $$$ISERR(sc) {
			Set reason = ..#REASONUNREADABLE
			Quit 0
		}
	}
	Set position = 0
	While $ListNext(new, position, n) {
		If ..StopAsked() Quit
		Set uidl = uids.GetAt(n)
		Set sc = ..Read(n, uidl, +sizes.GetAt(n), .mail)
		If $$$ISOK(sc) Set sc = ..Deliver(mail)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.MailSeen).Record(mailbox, uidl, 0)
		If $$$ISOK(sc) && ..DeleteMessage Set sc = ..MailServer.DeleteMessage(n)
		If $$$ISERR(sc) {
			Set reason = ..#REASONUNREADABLE
			Quit
		}
		Set handed = handed + 1
	}
	If reason '= "" Quit 0
	If $$$ISERR(##class(OcuTalon.Data.MailSeen).Trim(mailbox, .listed)) {
		Set reason = ..#REASONUNREADABLE
		Quit 0
	}
	Quit 1
}

/// The plain reason of a failed connection: the server's -ERR answer (to USER, PASS or STLS) is the refusal; a refused or lost connection, a
/// TLS failure, a greeting that is not POP3's (another protocol on the port, or none in time) and every other failure of the connection is
/// "couldn't reach". The status text is read here only and never kept.
ClassMethod ConnectReason(sc As %Status) As %String
{
	Quit $Select($SYSTEM.Status.Equals(sc, ..#POP3ERROR) && ($SYSTEM.Status.GetErrorText(sc) [ ": -ERR"): ..#REASONREFUSED, 1: ..#REASONUNREACHABLE)
}

/// Reads email n (UIDL uidl, size bytes) into the Mail: the whole email when it is within MAXBYTES and its whole read has not failed READTRIES
/// times, else its headers only.
Method Read(n As %Integer, uidl As %String, size As %Integer, Output mail As OcuTalon.Channel.Email.Mail) As %Status [ Private ]
{
	Set mail = ##class(OcuTalon.Channel.Email.Mail).%New()
	Set mail.Uidl = uidl
	If (size > ..#MAXBYTES) || ($Get(..ReadFailures(uidl)) >= ..#READTRIES) {
		Set sc = ..MailServer.FetchMessageHeaders(n, .headers)
		If $$$ISERR(sc) Quit sc
		Set mail.Sender = ..Line($Get(headers("from")))
		Set mail.Subject = ..Line($Get(headers("subject")))
		Quit $$$OK
	}
	Set sc = ..MailServer.Fetch(n, .message)
	If $$$ISERR(sc) {
		Set ..ReadFailures(uidl) = $Get(..ReadFailures(uidl)) + 1
		Quit sc
	}
	Kill ..ReadFailures(uidl)
	Set mail.Sender = ..Line(message.From)
	Set mail.Subject = ..Line(message.Subject)
	Set mail.Text = ..TextOf(message)
	Quit $$$OK
}

/// A header value as one line of at most 1000 characters: control characters become spaces.
ClassMethod Line(value As %String) As %String
{
	Set line = ##class(%Regex.Matcher).%New("[\x{00}-\x{1F}\x{7F}]+", $Get(value)).ReplaceAll(" ")
	Quit $Extract($ZStrip(line, "<>W"), 1, 1000)
}

/// The text of the email: the first plain-text part, else the first HTML part with its tags removed; "" when it has neither. Cut to the size of
/// the simulated mailbox's body (SimMailbox.In BODYMAX).
ClassMethod TextOf(message As %Net.MailMessagePart) As %String
{
	Set max = ##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX
	Set plain = "", html = ""
	Do ..Collect(message, .plain, .html, 0)
	If $ZStrip(plain, "<>WC") '= "" Quit $Extract(plain, 1, max)
	Quit $Extract(..StripTags(html), 1, max)
}

/// Looks through the parts for the first text part and the first HTML part (depth at most 8).
ClassMethod Collect(part As %Net.MailMessagePart, ByRef plain As %String, ByRef html As %String, depth As %Integer) [ Private ]
{
	If depth > 8 Quit
	If part.IsMultiPart {
		For i = 1:1:part.Parts.Count() {
			Do ..Collect(part.Parts.GetAt(i), .plain, .html, depth + 1)
		}
		Quit
	}
	If part.IsBinary || '$IsObject(part.TextData) Quit
	If part.IsHTML {
		If html = "" Set html = ..Body(part)
	} ElseIf plain = "" {
		Set plain = ..Body(part)
	}
}

/// The text of a part's stream, at most MAXBYTES characters.
ClassMethod Body(part As %Net.MailMessagePart) As %String [ Private ]
{
	Do part.TextData.Rewind()
	Quit part.TextData.Read(..#MAXBYTES)
}

/// HTML as plain text: script and style blocks and the tags are removed, the entities are decoded and white space is collapsed. Every step reads
/// the text once from front to back, so hostile markup (many unclosed tags) costs time in proportion to its size only; a script or style block
/// that is never closed runs to the end of the text, as a browser reads it.
ClassMethod StripTags(html As %String) As %String
{
	If html = "" Quit ""
	Set text = ..DropBlocks(..DropBlocks(html, "script"), "style")
	Set text = ..DropTags(text)
	Set text = $ZConvert(text, "I", "HTML")
	Set text = ##class(%Regex.Matcher).%New("[ \t\r\n\x{A0}]+", text).ReplaceAll(" ")
	Quit $ZStrip(text, "<>W")
}

/// The text without its <tag ...> ... </tag> blocks (tag in lower case), each replaced by a space.
ClassMethod DropBlocks(text As %String, tag As %String) As %String [ Private ]
{
	Set lower = $ZConvert(text, "L"), out = "", from = 1
	For {
		Set after = $Find(lower, "<"_tag, from)
		If 'after Quit
		Set out = out_$Extract(text, from, after - $Length(tag) - 2)_" "
		Set close = $Find(lower, "</"_tag, after)
		If 'close {
			Set from = $Length(text) + 1
			Quit
		}
		Set end = $Find(lower, ">", close)
		Set from = $Select(end: end, 1: $Length(text) + 1)
	}
	Quit out_$Extract(text, from, *)
}

/// The text without its <...> tags, each replaced by a space; a "<" with no ">" after it stays.
ClassMethod DropTags(text As %String) As %String [ Private ]
{
	Set out = "", from = 1
	For {
		Set open = $Find(text, "<", from)
		If 'open Quit
		Set close = $Find(text, ">", open)
		If 'close Quit
		Set out = out_$Extract(text, from, open - 2)_" "
		Set from = close
	}
	Quit out_$Extract(text, from, *)
}

/// 1 when the production asks this job to stop or to be quiescent (an update that restarts the item, a production stop). A test subclass overrides it.
Method StopAsked() As %Boolean [ Private ]
{
	Quit ##class(Ens.Job).ShouldBeQuiescent() || ##class(Ens.Job).ShouldTerminate()
}

/// Hands the Mail to the service of the item. A test subclass overrides it.
Method Deliver(mail As OcuTalon.Channel.Email.Mail) As %Status [ Private ]
{
	Quit ..BusinessHost.ProcessInput(mail)
}

/// Records the outcome of the poll in the status mark emailPoll: {at, ok, reason, lastOkAt}; lastOkAt is this poll's time when it
/// succeeded, else the earlier mark's, else "".
ClassMethod Record(ok As %Boolean, reason As %String)
{
	Set at = ##class(OcuTalon.Data.Time).NowUtc()
	Set lastOkAt = ""
	Set earlier = ##class(OcuTalon.Data.StatusMark).Get(..#MARK)
	If earlier '= "" {
		Try {
			Set lastOkAt = {}.%FromJSON(earlier).lastOkAt
		} Catch {
			Set lastOkAt = ""
		}
	}
	If ok Set lastOkAt = at
	Set mark = {}
	Do mark.%Set("at", at, "string")
	Do mark.%Set("ok", +ok, "number")
	Do mark.%Set("reason", $Select(ok: "", 1: reason), "string")
	Do mark.%Set("lastOkAt", lastOkAt, "string")
	Do ##class(OcuTalon.Data.StatusMark).Record(..#MARK, mark.%ToJSON())
}

}
