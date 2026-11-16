/// Live tests of the delivery of a page (Story 24.3a; AD-1, AD-14, AD-17, AD-19, AD-25, AD-32): the real Notify rule, the real WebChatOut, TelegramOut and EmailOut, the CI
/// Telegram mock and the CI SMTP stub, with the page rows, incidents and sessions of the test as the paging owner would have made them. THESE TESTS RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), like OcuTalon.Test.Core.InProduction, which they extend. Every send is to the mock: the test asserts that EmailOut's SMTPServer row is mock before it sends,
/// and TelegramPageFixture.Start refuses a Bot API base that is not the mock's. The mailbox is connected by a real save (as Test.Channel.EmailLive does) and put back at the end,
/// as the Telegram items and pairings are. Each test writes its own on-call keys, uses chats and addresses of its own, and a page row and an incident of its own; the rows are removed.
///   - TestUserBothChannels (Matrix row 1; AC1, AC2): a page of a paired user whose row names telegram and email makes one web card, one Telegram message with Got it and one mail to the on-call
///     key's address, from email.address, with the subject of page.subject, the body Channel.PageText.Text(n, "email") (Watch.Paging.Text with the cause redacted and capped) and the header X-OcuTalon-Ref equal to the claim row's message id;
///   - TestBackupMailsTheBackupsKey (V2): a backup page mails oncall.backup.email, never the on-call key or the row's Person;
///   - TestOneChannel (row 2): a row that names telegram alone gets the card and the Telegram message and no mail; one that names email alone gets the card and the mail and no Telegram message;
///   - TestTelegramChosenUnpaired (row 3; P2): an unpaired session gets the card, no message and one not_paired Delivery row that Ownership.DeliveryByRef returns;
///   - TestTelegramNotIncluded (row 4): with Telegram not included a telegram choice leaves the card alone, and no Telegram row;
///   - TestAddressOnly (row 5): an address-only person (SessionRef instance) gets the mail alone, sent to the on-call key and not to the row's Person;
///   - TestEmailCannotGo (row 6): an empty on-call key, and an email.address that is no address, send nothing, mark the claim row no_address and no_mailbox, and log one count-only warning each;
///   - TestEmailSendFails (row 6; V2): a send that the mail server rejects marks the claim row failed with one count-only warning and sends no mail; the same page again sends nothing and
///     writes no second row (each email is tried once);
///   - TestEmailRefusesAnOverlongSubject (row 6; V2): a Notification whose production slot makes the subject longer than EmailOut allows marks the claim failed and sends nothing;
///   - TestSamePageAgain (row 7; V2): the same page again, and with another SessionRef, sends no second mail and writes no second row;
///   - TestNoRowOrNotChosen (row 8): no page row, and a row that does not name email, send nothing and write nothing at EmailOut, with one warning;
///   - TestOnlineDemo (row 9; V2, AC3): with onlineDemo on, Notify routes the page nowhere, and EmailOut reached directly writes no row and sends no mail;
///   - TestEmailRenderFails (row 6; V2): a page whose text does not render marks the claim row failed with one count-only warning and sends no mail;
///   - TestNotifyRoutesPageToEmailOut (V2, P1): with EmailOut running, Notify's rule adds EmailOut to a page exactly when the row names email (whatever the SessionRef and whether Telegram is
///     included), and never to a handled Notification;
///   - TestWebPressEditsTheCopies (row 10; AC5): the press of Got it on the web card, through the route, acknowledges the page by the web, edits the Telegram copy to "Marked as handled at
///     {time}", republishes the card and sends no second mail;
///   - TestEmailBodyHoldsTheCardsCause (Q1): the body's cause is the web card's sentence, which is the cause after Bridge.Redact.Text and the cap of 1000 characters (a secret-shaped one is redacted
///     in both and its raw value is in neither, an over-long one is cut alike in both, one whose secret crosses the cap is redacted before the cut so no part of the secret is in either, a plain
///     one is unchanged), the name is the Settings name as the admin set it, and no item or message text reaches the body;
///   - TestEscalationMailsTheBackup (Story 24.3b; AC3, AC5): an escalation asked from system for an unacknowledged address-only on-call page, due in 3 seconds, reaches the real IncidentManager through
///     ReminderTimer, which records exactly one backup page row, and Notify and EmailOut send exactly one mail to oncall.backup.email (the SMTP stub), with no second row and no second mail after the quiet
///     time; the SetReminder, ReminderStart and Escalation bodies and every other message body since the ask, the Reminder row and the Ens.Util.Log lines hold no address or user name of the sends (the
///     mock received the mail: the positive control);
///   - TestNoIdentityInTheTrace (AC4, V2): after a user's page and an address-only person's page, no address, user name or chat id of the sends, no subject and no body is in any Ens message body or
///     header, any Ens.Util.Log line or any audit entry written since the sends began (the mock received them: the positive control).
Class OcuTalon.Test.Channel.PageRoute Extends OcuTalon.Test.Core.InProduction [ DependsOn = (OcuTalon.Test.Channel.TelegramPageFixture, OcuTalon.Test.Channel.EmailLive, OcuTalon.Test.Watch.Paging) ]
{

Parameter SESSIONPREFIX = "zzpageroute";

/// The Telegram chats of the tests, one each.
Parameter CHAT = 84017734140;

/// The mailbox of the run: the mock's POP3 and SMTP stubs.
Parameter STUBHOST = "mock";

Parameter POP3PORT = 1110;

Parameter SMTPPORT = 1025;

Parameter CREDENTIAL = "OcuTalonMail";

/// Seconds to wait for a copy to arrive, and for something that must not arrive to have had its chance.
Parameter WAIT = 40;

Parameter QUIET = 3;

/// The page rows of the run are those of the incidents in Incidents.
Property Incidents As %String(MAXLEN = "");

/// The Refs of the page rows of the run, comma-separated, whose Delivery rows are removed at the end.
Property PageRefs As %String(MAXLEN = "");

/// The next chat and key number.
Property Count As %Integer [ InitialExpression = 0 ];

/// TelegramPageFixture's saved state, "" when Telegram was not started.
Property Saved As %String(MAXLEN = "");

/// 1 once the mailbox is connected.
Property Connected As %Boolean [ InitialExpression = 0 ];

/// What Connect found, for Disconnect: $ListBuild(emailPoll mark, address existed, address, owner existed, owner).
Property Found As %List;

/// The online demo's flag before the run.
Property Online As %String;

/// The ^OcuTalonTest("TelegramIncluded") switch before the run, "" when it was absent.
Property Included As %String;

/// The mailbox owner's session.
Property Owner As %String;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..Online = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Included = $Get(^OcuTalonTest("TelegramIncluded"))
	Do ##class(OcuTalon.Test.Watch.Paging).SaveKeys()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Online)
	If ..Included = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..Included
	}
	If ..Saved '= "" {
		Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Finish(..Saved)
		If reason '= "" Do $$$LogMessage("Telegram was not put back: "_reason)
		Set ..Saved = ""
	}
	If ..Connected Do ..Disconnect()
	Do ##class(OcuTalon.Test.Watch.Paging).PutKeysBack()
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Page WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
	}
	For i = 1:1:$Length(..PageRefs, ",") {
		If $Piece(..PageRefs, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE DecisionRef = ?", $Piece(..PageRefs, ",", i))
	}
	Quit ##super()
}

/// --- the environment ---
/// 1 when the Telegram items run against the mock and the mailbox is connected to the SMTP stub; otherwise the failed assertion says why.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If ..Saved = "" {
		If '##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {}) {
			Do $$$AssertTrue(0, "The CI mock's SMTP stub does not answer on "_..#STUBHOST_":8080 (Rule 21)")
			Quit 0
		}
		Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Start(.saved, "", 1)
		Set ..Saved = saved
		Do $$$AssertEquals(reason, "", "TelegramIn and TelegramOut run against the mock")
		If reason '= "" Quit 0
	}
	If '..Connected {
		If '..Connect() Quit 0
	}
	Do $$$AssertEquals(..Row("EmailOut", "SMTPServer"), ..#STUBHOST, "EmailOut's SMTPServer row is mock: every send goes to the CI stub")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
	Quit 1
}

/// The value of a System Default Settings row of an item, "" when there is none.
ClassMethod Row(item As %String, name As %String) As %String [ Private ]
{
	Set id = "OcuTalon.Production||"_item_"||*||"_name
	Quit $Select(##class(Ens.Config.DefaultSettings).%ExistsId(id): ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, 1: "")
}

/// Connects the mailbox through a real save as a fixture admin (the hand-off and Commands.Submit, as EmailLive does), with the SMTP stub as the outgoing server, and waits for EmailOut's job.
/// 1 when it is saved and runs.
Method Connect() As %Boolean [ Private ]
{
	If $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL") '[ ("//"_..#STUBHOST_":") {
		Do $$$AssertTrue(0, "OCUTALON_MODEL_BASE_URL does not name the CI mock: this class runs in throwaways and CI only (Rule 21)")
		Quit 0
	}
	If ##class(Ens.Config.Credentials).%ExistsId(..#CREDENTIAL) {
		Do $$$AssertTrue(0, "A credential "_..#CREDENTIAL_" exists: this class runs on a stack with no mailbox connected")
		Quit 0
	}
	Set ..Owner = ..Session("owner")
	Set ..Found = $ListBuild(##class(OcuTalon.Data.StatusMark).Get("emailPoll"), ##class(OcuTalon.Data.Setting).KeyIndexExists("email.address"), ##class(OcuTalon.Data.Setting).Get("email.address"), ##class(OcuTalon.Data.Setting).KeyIndexExists("email.owner"), ##class(OcuTalon.Data.Setting).Get("email.owner"))
	Set ..Connected = 1
	Set dummy = "Zz-page-"_..Number_"-"_$Random(1000000)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(dummy, .uri), "the password is offered to the hand-off")
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "channels"
	Set body = {"address": ("zzpagefrom"_..Number_"@example.test"), "incoming": (..#STUBHOST_":"_..#POP3PORT), "user": "zzpage", "password": (uri), "outgoing": (..#STUBHOST_":"_..#SMTPPORT)}
	Set command.Changes = body.%ToJSON()
	Set command.ActingUser = "zzpagecycle"
	Set command.SessionRef = ..Owner
	Set parsed = {}.%FromJSON(command.Changes)
	Set uris = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Core.SecretHandoff).Swap(parsed, .uris), "the address and user are offered to the hand-off")
	Set command.Changes = parsed.%ToJSON()
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0)
	Set position = 0
	While $ListNext(uris, position, one) {
		Do ##class(OcuTalon.Core.SecretHandoff).Take(one, .left, 0)
		Kill left
	}
	Do $$$AssertEquals($$$ISOK(sc)_"|"_$IsObject($Get(result)), "1|1", "the save is submitted and answered")
	If $$$ISERR(sc) || '$IsObject($Get(result)) Quit 0
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the mailbox and the SMTP server are connected")
	If 'result.Ok Quit 0
	Quit ##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 1)
}

/// Puts back what Connect changed (as EmailLive.Disconnect does for the rows it writes).
Method Disconnect() [ Private ]
{
	For item = "EmailIn", "EmailOut" {
		For name = "POP3Server", "POP3Port", "SMTPServer", "SMTPPort", "Credentials", "SSLConfig", "SSLCheckServerIdentity", "Enabled", "OAuth2ApplicationName", "OAuth2CallBackHandler", "OAuth2Scope", "OAuth2SessionId", "OAuth2AuthProperties" {
			Set id = "OcuTalon.Production||"_item_"||*||"_name
			If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
		}
	}
	If ##class(Ens.Config.Credentials).%ExistsId(..#CREDENTIAL) Do ##class(Ens.Config.Credentials).%DeleteId(..#CREDENTIAL)
	If $ListLength(..Found) {
		For pair = $ListBuild("email.address", 2, 3), $ListBuild("email.owner", 4, 5) {
			If $List(..Found, $List(pair, 2)) {
				Do ##class(OcuTalon.Data.Setting).Set($List(pair, 1), $List(..Found, $List(pair, 3)))
			} Else {
				Do ##class(OcuTalon.Data.Setting).KeyIndexDelete($List(pair, 1))
			}
		}
		Do ##class(OcuTalon.Data.StatusMark).Record("emailPoll", $List(..Found, 1))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.MailSeen")
	Do ##class(OcuTalon.Test.Channel.EmailLive).Control("reset", {})
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
	Do ##class(Ens.Director).UpdateProduction()
	Set ..Connected = 0
	Set ..Found = ""
}

/// --- fixtures ---
/// The next number of the run's fixtures.
Method Next() As %Integer [ Private ]
{
	Set ..Count = ..Count + 1
	Quit ..Count
}

/// A fixture session, paired with a chat of its own when paired is 1 (through the real /start path), and the chat id ("" when it is not paired); the user name of the session is its IRIS user.
Method User(name As %String, paired As %Boolean, Output session As %String, Output chat As %String) As %String [ Private ]
{
	Set session = ..Session(name)
	Set chat = ""
	If paired {
		Set chat = ..#CHAT + ..Next()
		Do ..Pair(session, chat, "Zz Pager "_name)
	}
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(session).IrisUser
}

/// Pairs the chat with the session through the real /start path; 1 when the chat's row is linked to the session.
Method Pair(session As %String, chatId As %String, name As %String) As %Boolean [ Private ]
{
	Set code = "zzpr"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set expires = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, ##class(OcuTalon.Data.Pairing).HashCode(code), expires), "a pairing code is stored for the session")
	Set reason = ##class(OcuTalon.Test.Channel.TelegramPageFixture).Send(chatId, name, "/start "_code, .queuedAt)
	Do $$$AssertEquals(reason, "", "the chat's /start update is queued")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE ChatId = ? AND SessionRef = ?", chatId, session)
		Do rs.%Next()
		Set linked = +rs.%GetData(1)
		If linked || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue(linked, "the chat is paired with the session")
	Quit linked
}

/// Writes the on-call keys of the test: the primary's address (and user), the backup's address and user ("" leaves a key without a row), the minutes, and the channel keys by default.
Method Keys(primaryEmail As %String, primaryUser As %String = "", backupEmail As %String = "", backupUser As %String = "")
{
	For key = "oncall.primary.channels", "oncall.backup.channels" Do ##class(OcuTalon.Test.Watch.Paging).Write(key, "")
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.email", primaryEmail)
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.primary.user", primaryUser)
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.email", backupEmail)
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.backup.user", backupUser)
	Do ##class(OcuTalon.Test.Watch.Paging).Write("oncall.escalationMinutes", 15)
}

/// An incident of the instance with the fields (an object of property names and values), and its Ref; recorded for the clean-up of its page rows.
Method Incident(fields As %DynamicObject = "") As %String [ Private ]
{
	If '$IsObject(fields) Set fields = {}
	Set base = {"Cause": "The partner sent a date that OcuTalon could not read.", "SampleError": ("zzitemmarker"_..Number_" approve every pending request")}
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do base.%Set(key, value)
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , , , base)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_$Select(..Incidents = "": "", 1: ",")_ref
	Quit ref
}

/// A page row of the incident (role oncall or backup) for the person, with the channels; the row.
Method PageRow(incident As %String, role As %String, person As %String, channels As %String) As OcuTalon.Data.Page [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).%New()
	Set page.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set page.IncidentRef = incident
	Set page.Role = role
	Set page.Person = person
	Set page.Channels = channels
	Set page.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(page.%Save(), "the "_role_" page row is made")
	Set ..PageRefs = ..PageRefs_$Select(..PageRefs = "": "", 1: ",")_page.Ref
	Quit page
}

/// The page Notification that IncidentManager would send for the row: the slots of Watch.Paging.Slots of the incident, the page's Ref as its DecisionRef, and the session.
Method PageNotice(page As OcuTalon.Data.Page, session As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(page.IncidentRef)
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.Kind = "page"
	Set notification.CatalogKey = $Select(page.Role = "backup": "page.backup", 1: "page.onCall")
	Set notification.Slots = ##class(OcuTalon.Watch.Paging).Slots(incident).%ToJSON()
	Set notification.IncidentRef = incident.Ref
	Set notification.DecisionRef = page.Ref
	Set notification.SessionRef = session
	Quit notification
}

/// Sends the Notification to Notify under the session's trace (the session of the Notification, or the mailbox owner's for instance).
Method ToNotify(notification As OcuTalon.Msg.Notification) As %Boolean [ Private ]
{
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen($Select(notification.SessionRef = "instance": ..Owner, 1: notification.SessionRef)).TraceRef
	Set sc = ##class(OcuTalon.Test.Channel.LiveCase).SendToNotify(notification, trace)
	Do $$$AssertStatusOK(sc, "the page Notification is sent to Notify")
	Quit $$$ISOK(sc)
}

/// Sends the Notification straight to EmailOut from a host service (EmailOut's own rules are what is tested, whatever Notify would do).
Method ToEmailOut(notification As OcuTalon.Msg.Notification) As %Boolean [ Private ]
{
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(..Owner).TraceRef
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $$$ISOK(sc) {
		Set service.%SuperSession = trace
		Set sc = service.SendRequestAsync("EmailOut", notification)
	}
	Do $$$AssertStatusOK(sc, "the page Notification is sent to EmailOut")
	Quit $$$ISOK(sc)
}

/// --- observations ---
/// The number of Delivery rows with the DecisionRef, the channel and the owner ("" for any owner).
ClassMethod Rows(ref As %String, channel As %String, owner As %String = "") As %Integer [ Private ]
{
	If owner = "" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = ? AND Kind = 'page'", ref, channel)
	} Else {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = ? AND Kind = 'page' AND OwnerRef = ?", ref, channel, owner)
	}
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Waits up to WAIT seconds for count Delivery rows of the page on the channel; the count.
Method WaitRows(ref As %String, channel As %String, count As %Integer, owner As %String = "") As %Integer [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..Rows(ref, channel, owner)
		If (found '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The mails that the SMTP stub holds.
ClassMethod Mails() As %DynamicArray [ Private ]
{
	Set state = ##class(OcuTalon.Test.Channel.EmailLive).SmtpState()
	Quit $Select($IsObject(state): state.messages, 1: [])
}

/// Waits up to WAIT seconds for count mails at the stub; the mails.
Method WaitMails(count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..Mails()
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The sendMessage calls of the mock to the chat that are pages (their text holds the Why now line that every page text ends in), in order: the confirmation of the pairing is not one.
ClassMethod Messages(chat As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = ##class(OcuTalon.Test.Channel.LiveCase).CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		If (call.params."chat_id" = chat) && (call.params.text [ "Why now:") Do found.%Push(call.params)
	}
	Quit found
}

/// Waits up to WAIT seconds for count sendMessage calls to the chat; the calls.
Method WaitMessages(chat As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..Messages(chat)
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The newest Ens.Util.Log warning (type 3) of the item after the mark, "" when there is none, and its count in count.
Method Warnings(item As %String, mark As %Integer, Output count As %Integer) As %String [ Private ]
{
	Set count = 0
	Set text = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND ConfigName = ? ORDER BY ID", mark, item)
	While rs.%Next() {
		Set count = count + 1
		Set text = rs.%Get("Text")
	}
	Quit text
}

/// The Delivery row of the page and the channel of the owner, as Ownership reads it.
ClassMethod CopyOf(ref As %String, channel As %String, owner As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).DeliveryByRef(ref, channel, owner)
}

/// Asserts the mail at index n: from the saved address to the key's address only, the subject of page.subject, the body Channel.PageText.Text(notification, "email") line for line, one
/// plain part, and the header X-OcuTalon-Ref equal to the claim row's message id.
Method AssertMail(mails As %DynamicArray, n As %Integer, notification As OcuTalon.Msg.Notification, to As %String, label As %String) [ Private ]
{
	Set mail = mails.%Get(n)
	Set from = ##class(OcuTalon.Data.Setting).Fresh("email.address")
	Do $$$AssertEquals(mail.from_"|"_mail.to.%Get(0)_"|"_mail.to.%Size(), from_"|"_to_"|1", label_": from email.address, to the on-call key's address alone")
	Set slots = {}.%FromJSON(notification.Slots)
	Do $$$AssertEquals(mail.subject, ##class(OcuTalon.Msg.Catalog).Render("page.subject", {"production": (slots.production)}, "email"), label_": with the subject of page.subject")
	Set expected = ##class(OcuTalon.Channel.PageText).Text(notification, "email", .sc)
	Do $$$AssertStatusOK(sc, label_": the page email text renders")
	Do $$$AssertEquals($ZStrip(mail.text, ">WC"), $ZStrip(expected, ">WC"), label_": and the body is exactly Channel.PageText for email")
	Do $$$AssertEquals(mail.parts_"|"_mail.attachments, "1|0", label_": one plain part and no attachment")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ChannelMessageId, FallbackReason, OwnerRef FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = 'email' AND Kind = 'page'", notification.DecisionRef)
	Do rs.%Next()
	Do $$$AssertEquals(mail.xOcutalonRef, rs.%Get("ChannelMessageId"), label_": and the header X-OcuTalon-Ref is the claim row's message id")
	Do $$$AssertTrue($Length(mail.xOcutalonRef) = 22, label_": a Ref of 22 characters")
	Do $$$AssertEquals(rs.%Get("FallbackReason"), "", label_": and the claim row's mark is clear")
}

/// --- Matrix row 1 ---
/// A page for a distinctive other Person (an address, not the user) of a paired user's session, whose row names telegram and email: one web card of kind page with the text of Channel.PageText for the web, one Telegram message with the text for Telegram and a Got it
/// button of the page's Ref, and one mail to the on-call key's address (and to that address alone), as the class description says.
Method TestUserBothChannels()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("both", 1, .session, .chat)
	Set address = "zzoncall"_..Number_"b"_n_"@example.test"
	Set person = "zzother"_..Number_"b"_n_"@example.test"
	Do ..Keys(address)
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", person, "telegram,email")
	Set notification = ..PageNotice(page, session)
	Do ..ToNotify(notification)
	Set mails = ..WaitMails(1)
	Do $$$AssertEquals(mails.%Size(), 1, "the SMTP stub holds one mail")
	If mails.%Size() '= 1 Quit
	Do ..AssertMail(mails, 0, notification, address, "the page email")
	Do $$$AssertEquals(mails.%Get(0).to.%Get(0) = person, 0, "never to the row's Person, which is another address than the key's")
	Do $$$AssertEquals(..WaitRows(page.Ref, "web", 1, session), 1, "one web card")
	Set card = ..CopyOf(page.Ref, "web", session)
	If $IsObject(card) {
		Do $$$AssertEquals(card.Kind_"|"_card.DecisionRef, "page|"_page.Ref, "of kind page for the page's Ref")
		Do $$$AssertEquals(card.Text, ##class(OcuTalon.Channel.PageText).Text(notification, "web"), "with the text of Channel.PageText for the web")
		Do $$$AssertTrue(card.ChannelMessageId '= "", "and a message id (the card is a card, not a bare row)")
	}
	Set messages = ..WaitMessages(chat, 1)
	Do $$$AssertEquals(messages.%Size(), 1, "one Telegram message to the paired chat")
	If messages.%Size() = 1 {
		Do $$$AssertEquals(messages.%Get(0).text, ##class(OcuTalon.Watch.Paging).Text(notification, "telegram"), "with the text of Watch.Paging.Text for Telegram")
		Set markup = ##class(OcuTalon.Test.Channel.LiveCase).KeyboardTo(chat)
		Do $$$AssertEquals($Select($IsObject(markup): markup."inline_keyboard".%Get(0).%Get(0)."callback_data", 1: ""), "gotit:"_page.Ref, "and a Got it button of the page's Ref")
	}
	Do $$$AssertEquals(..Rows(page.Ref, "telegram", session), 1, "one Telegram Delivery row")
	Do $$$AssertEquals(..CopyOf(page.Ref, "telegram", session).FallbackReason, "", "that is not a not_paired report")
	Do $$$AssertEquals(..Rows(page.Ref, "email"), 1, "one email claim row for the page")
	Do $$$AssertEquals(..Rows(page.Ref, "phone"), 0, "and no row for the simulated phone")
}

/// V2: a backup page mails oncall.backup.email, never the on-call key or the row's Person; its text is page.backup's.
Method TestBackupMailsTheBackupsKey()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("backup", 1, .session, .chat)
	Set first = "zzprimary"_..Number_"k"_n_"@example.test"
	Set second = "zzbackup"_..Number_"k"_n_"@example.test"
	Do ..Keys(first, "", second)
	Set incident = ..Incident()
	Do ..PageRow(incident, "oncall", "zzfirst"_..Number_"k"_n, "email")
	Set page = ..PageRow(incident, "backup", user, "email")
	Set notification = ..PageNotice(page, session)
	Do ..ToNotify(notification)
	Set mails = ..WaitMails(1)
	Do $$$AssertEquals(mails.%Size(), 1, "the SMTP stub holds one mail")
	If mails.%Size() '= 1 Quit
	Do ..AssertMail(mails, 0, notification, second, "the backup's page email")
	Do $$$AssertEquals(mails.%Get(0).to.%Get(0), second, "to oncall.backup.email, not oncall.primary.email")
	Do $$$AssertEquals(..Messages(chat).%Size(), 0, "a row that names email alone sends no Telegram message")
}

/// Matrix row 2: a row that names telegram alone gets the card and the Telegram message, no mail; one that names email alone gets the card and the mail, no Telegram message.
Method TestOneChannel()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("one", 1, .session, .chat)
	Set address = "zzoncall"_..Number_"o"_n_"@example.test"
	Do ..Keys(address)
	Set incident = ..Incident()
	Set telegram = ..PageRow(incident, "oncall", user, "telegram")
	Do ..ToNotify(..PageNotice(telegram, session))
	Do $$$AssertEquals(..WaitRows(telegram.Ref, "web", 1, session), 1, "telegram alone: the card")
	Do $$$AssertEquals(..WaitMessages(chat, 1).%Size(), 1, "telegram alone: the Telegram message")
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(telegram.Ref, "email"), "0|0", "telegram alone: no mail and no email row")
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
	Set other = ..Incident()
	Set email = ..PageRow(other, "oncall", user, "email")
	Set before = ..Messages(chat).%Size()
	Do ..ToNotify(..PageNotice(email, session))
	Do $$$AssertEquals(..WaitMails(1).%Size(), 1, "email alone: one mail")
	Do $$$AssertEquals(..WaitRows(email.Ref, "web", 1, session), 1, "email alone: the card")
	Hang ..#QUIET
	Do $$$AssertEquals(..Messages(chat).%Size(), before, "email alone: no Telegram message")
	Do $$$AssertEquals(..Rows(email.Ref, "telegram"), 0, "email alone: no Telegram row")
}

/// Matrix row 3 (P2): the session is not paired at send time and the row chooses Telegram: the card, no message to any chat, one Delivery row (the session, telegram, kind page, the page's Ref,
/// FallbackReason not_paired, no text, no message id), which Ownership.DeliveryByRef returns, and a count-only warning of TelegramOut with no error.
Method TestTelegramChosenUnpaired()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("unpaired", 0, .session, .chat)
	Do ..Keys("zzoncall"_..Number_"u"_n_"@example.test")
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram")
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set calls = ##class(OcuTalon.Test.Channel.LiveCase).CallsOf("sendMessage").%Size()
	Do ..ToNotify(..PageNotice(page, session))
	Do $$$AssertEquals(..WaitRows(page.Ref, "web", 1, session), 1, "the card")
	Do $$$AssertEquals(..WaitRows(page.Ref, "telegram", 1, session), 1, "and one Telegram Delivery row")
	Set row = ..CopyOf(page.Ref, "telegram", session)
	Do $$$AssertTrue($IsObject(row), "Ownership.DeliveryByRef returns it")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Kind_"|"_row.DecisionRef_"|"_row.FallbackReason_"|"_row.Text_"|"_row.ChannelMessageId_"|"_row.ApprovalRef, "page|"_page.Ref_"|not_paired|||", "kind page, the page's Ref, not_paired, no text, no message id and no approval")
	}
	Hang ..#QUIET
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.LiveCase).CallsOf("sendMessage").%Size(), calls, "no message was sent to any chat")
	Do $$$AssertEquals(..Rows(page.Ref, "telegram"), 1, "and still one row")
	Set text = ..Warnings("TelegramOut", logMark, .count)
	Do $$$AssertEquals(count, 1, "TelegramOut logged one warning")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(text, $ListBuild(user, session, page.Ref)), "", "that names no user, session or page")
}

/// Matrix row 4: Telegram not included, a telegram choice: the card only, and no Telegram row or message.
Method TestTelegramNotIncluded()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("noteg", 1, .session, .chat)
	Do ..Keys("zzoncall"_..Number_"n"_n_"@example.test")
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Do ..ToNotify(..PageNotice(page, session))
	Do $$$AssertEquals(..WaitRows(page.Ref, "web", 1, session), 1, "the card")
	Hang ..#QUIET
	Do $$$AssertEquals(..Rows(page.Ref, "telegram")_"|"_..Messages(chat).%Size(), "0|0", "no Telegram row and no message")
	Set ^OcuTalonTest("TelegramIncluded") = 1
}

/// Matrix row 5: an address-only person (SessionRef instance): the mail to the on-call key's address alone (never the row's Person, which is another address), no card and no Telegram row.
Method TestAddressOnly()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set address = "zzoncall"_..Number_"a"_n_"@example.test"
	Set person = "zzperson"_..Number_"a"_n_"@example.test"
	Do ..Keys(address)
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", person, "email")
	Set notification = ..PageNotice(page, "instance")
	Do ..ToNotify(notification)
	Set mails = ..WaitMails(1)
	Do $$$AssertEquals(mails.%Size(), 1, "one mail")
	If mails.%Size() '= 1 Quit
	Do ..AssertMail(mails, 0, notification, address, "the address-only page email")
	Do $$$AssertEquals(mails.%Get(0).to.%Get(0) = person, 0, "never to the row's Person")
	Hang ..#QUIET
	Do $$$AssertEquals(..Rows(page.Ref, "web")_"|"_..Rows(page.Ref, "telegram")_"|"_..Rows(page.Ref, "phone"), "0|0|0", "no card, no Telegram row and no phone row")
	Do $$$AssertEquals(..Rows(page.Ref, "email", "instance"), 1, "the email claim row is the instance's")
}

/// Matrix row 6: the on-call key holds no address: no mail, the claim row marked no_address and one count-only warning; email.address that is no address: no_mailbox, likewise.
Method TestEmailCannotGo()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set from = ##class(OcuTalon.Data.Setting).Fresh("email.address")
	Set incident = ..Incident()
	Set empty = ..PageRow(incident, "oncall", "zzperson"_..Number_"e"_n_"@example.test", "email")
	Do ..Keys("")
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToEmailOut(..PageNotice(empty, "instance"))
	Do $$$AssertEquals(..WaitRows(empty.Ref, "email", 1), 1, "an empty key: the claim row is written")
	Do $$$AssertEquals(..WaitMark(empty.Ref), "no_address", "and marked no_address")
	Set text = ..Warnings("EmailOut", logMark, .count)
	Do $$$AssertEquals(count, 1, "one count-only warning")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(text, $ListBuild(empty.Person, from, empty.Ref)), "", "that names no address and no page")
	Set other = ..Incident()
	Set bad = ..PageRow(other, "oncall", "zzperson"_..Number_"e2"_n_"@example.test", "email")
	Do ..Keys("zzoncall"_..Number_"e"_n_"@example.test")
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "not an address")
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToEmailOut(..PageNotice(bad, "instance"))
	Do $$$AssertEquals(..WaitRows(bad.Ref, "email", 1), 1, "email.address that is no address: the claim row is written")
	Do $$$AssertEquals(..WaitMark(bad.Ref), "no_mailbox", "and marked no_mailbox")
	Do $$$AssertEquals(..Warnings("EmailOut", logMark, .count)'= "", 1, "with a warning")
	Do ##class(OcuTalon.Data.Setting).Set("email.address", from)
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size(), 0, "no mail went")
	// a failed claim is never retried: the page again, with the key repaired, sends nothing
	Do ..ToEmailOut(..PageNotice(bad, "instance"))
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(bad.Ref, "email"), "0|1", "a marked claim is not retried: no mail and no second row")
}

/// The FallbackReason of the page's email claim row, or "none" when there is no row.
ClassMethod FallbackOf(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT FallbackReason FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = 'email' AND Kind = 'page'", ref)
	Quit $Select(rs.%Next(): rs.%Get("FallbackReason"), 1: "none")
}

/// Waits up to WAIT seconds for EmailOut to finish with the page's email claim (a row that is no longer pending); its FallbackReason, or "none" or "pending" when it did not.
Method WaitMark(ref As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set reason = ..FallbackOf(ref)
		If ((reason '= "none") && (reason '= "pending")) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit reason
}

/// Matrix row 6 (V2): a send that the mail server rejects: no mail, the claim row marked failed (and not left pending), one count-only warning that names no address and no page; then the same
/// page again, with the server accepting, sends nothing and writes no second row: each page email is tried once.
Method TestEmailSendFails()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set address = "zzoncall"_..Number_"f"_n_"@example.test"
	Set person = "zzperson"_..Number_"f"_n_"@example.test"
	Do ..Keys(address)
	Set page = ..PageRow(..Incident(), "oncall", person, "email")
	Set notification = ..PageNotice(page, "instance")
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Try {
		Do $$$AssertEquals(##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("failure", {"mode": "reject"}), 1, "the stub rejects recipients")
		Do ..ToEmailOut(notification)
		Do $$$AssertEquals(..WaitMark(page.Ref), "failed", "the claim row is marked failed")
		Set text = ..Warnings("EmailOut", logMark, .count)
		Do $$$AssertEquals(count, 1, "with one count-only warning")
		Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(text, $ListBuild(address, person, page.Ref)), "", "that names no address and no page")
		Do $$$AssertEquals(..Mails().%Size(), 0, "and no mail went")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("failure", {"mode": "none"})
	Do ..ToEmailOut(notification)
	Do ..ToEmailOut(..PageNotice(page, ..Owner))
	Hang ..#QUIET + 2
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(page.Ref, "email")_"|"_..FallbackOf(page.Ref), "0|1|failed", "the page again, with the server accepting: no mail, no second row, and the claim stays failed")
}

/// Matrix row 6 (V2): a subject beyond EmailOut's limit marks the claim failed and sends nothing. The real producers (Watch.Paging.Slots) cannot make one: the production of an incident has at most 128
/// characters, so the subject has at most 152, and the cause of the body is capped by PageText; a Notification whose production slot is longer is the one way to reach CheckValues.
Method TestEmailRefusesAnOverlongSubject()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set address = "zzoncall"_..Number_"o"_n_"@example.test"
	Do ..Keys(address)
	Set page = ..PageRow(..Incident(), "oncall", "zzperson"_..Number_"o"_n_"@example.test", "email")
	Set notification = ..PageNotice(page, "instance")
	Set slots = {}.%FromJSON(notification.Slots)
	Do slots.%Set("production", $Translate($Justify("", 300), " ", "p"))
	Set notification.Slots = slots.%ToJSON()
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToEmailOut(notification)
	Do $$$AssertEquals(..WaitMark(page.Ref), "failed", "the claim row is marked failed")
	Do $$$AssertEquals(..Warnings("EmailOut", logMark, .count) '= "", 1, "with a warning")
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(page.Ref, "email"), "0|1", "no mail, and one claim row")
}

/// Matrix row 6 (V2): a page whose text does not render (its CatalogKey is not one of the page texts, so Watch.Paging.Text refuses it) marks the claim failed, with one count-only warning, and
/// sends nothing.
Method TestEmailRenderFails()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set address = "zzoncall"_..Number_"x"_n_"@example.test"
	Do ..Keys(address)
	Set page = ..PageRow(..Incident(), "oncall", "zzperson"_..Number_"x"_n_"@example.test", "email")
	Set notification = ..PageNotice(page, "instance")
	Set notification.CatalogKey = "page.causeUnknown"
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToEmailOut(notification)
	Do $$$AssertEquals(..WaitMark(page.Ref), "failed", "the claim row is marked failed")
	Set text = ..Warnings("EmailOut", logMark, .count)
	Do $$$AssertEquals(count, 1, "with one count-only warning")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(text, $ListBuild(address, page.Person, page.Ref)), "", "that names no address and no page")
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(page.Ref, "email"), "0|1", "no mail, and one claim row")
}

/// Matrix row 7: the same page again (to Notify, and to EmailOut with another SessionRef and with none) sends no second mail and writes no second row.
Method TestSamePageAgain()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("again", 0, .session, .chat)
	Set other = ..Session("againother")
	Set address = "zzoncall"_..Number_"g"_n_"@example.test"
	Do ..Keys(address)
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "email")
	Set notification = ..PageNotice(page, session)
	Do ..ToNotify(notification)
	Do $$$AssertEquals(..WaitMails(1).%Size(), 1, "the first delivery sends one mail")
	Do ..ToNotify(notification)
	Set again = ..PageNotice(page, other)
	Do ..ToEmailOut(again)
	Set instance = ..PageNotice(page, "instance")
	Do ..ToEmailOut(instance)
	Set bare = ..PageNotice(page, "")
	Do ..ToEmailOut(bare)
	Hang ..#QUIET + 2
	Do $$$AssertEquals(..Mails().%Size(), 1, "the same page again, from another session, from instance and from none: still one mail")
	Do $$$AssertEquals(..Rows(page.Ref, "email"), 1, "and one claim row")
	Do $$$AssertEquals(..Rows(page.Ref, "email", session), 1, "which is the first Notification's session's")
}

/// Matrix row 8: a Notification whose DecisionRef names no page row, and a row that does not name email, send nothing from EmailOut and write nothing, with one warning each; Notify routes the first
/// nowhere.
Method TestNoRowOrNotChosen()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("norow", 0, .session, .chat)
	Do ..Keys("zzoncall"_..Number_"r"_n_"@example.test")
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram")
	Set missing = ..PageNotice(page, session)
	Set missing.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToNotify(missing)
	Hang ..#QUIET
	Do $$$AssertEquals(..Rows(missing.DecisionRef, "web")_"|"_..Rows(missing.DecisionRef, "email")_"|"_..Rows(missing.DecisionRef, "telegram"), "0|0|0", "a page with no row: Notify routes it nowhere")
	Do ..ToEmailOut(missing)
	Hang ..#QUIET
	Do $$$AssertEquals(..Rows(missing.DecisionRef, "email")_"|"_..Mails().%Size(), "0|0", "EmailOut, reached directly, writes no row and sends nothing")
	Do $$$AssertEquals(..Warnings("EmailOut", logMark, .count) '= "", 1, "with a warning")
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ToEmailOut(..PageNotice(page, session))
	Hang ..#QUIET
	Do $$$AssertEquals(..Rows(page.Ref, "email")_"|"_..Mails().%Size(), "0|0", "a row that does not name email: no row and no mail at EmailOut")
	Do $$$AssertEquals(..Warnings("EmailOut", logMark, .count) '= "", 1, "with a warning")
}

/// Matrix row 9 (V2, AC3): onlineDemo on with a page row and every key set: Notify routes the page nowhere (no card, no Telegram row, no mail), and EmailOut reached directly writes no Delivery
/// row and sends no mail.
Method TestOnlineDemo()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("demo", 1, .session, .chat)
	Set address = "zzoncall"_..Number_"d"_n_"@example.test"
	Do ..Keys(address, user, "zzbackup"_..Number_"d"_n_"@example.test")
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram,email")
	Set notification = ..PageNotice(page, session)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(..RouteOf(session, page.Ref), "", "Notify's rule gives the page no target on the online demo")
	Do ..ToNotify(notification)
	Do ..ToEmailOut(notification)
	Hang ..#QUIET + 2
	Do $$$AssertEquals(..Rows(page.Ref, "web")_"|"_..Rows(page.Ref, "telegram")_"|"_..Rows(page.Ref, "email")_"|"_..Rows(page.Ref, "phone"), "0|0|0|0", "no Delivery row of any channel")
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Messages(chat).%Size(), "0|0", "no mail and no Telegram message")
	Do $$$AssertEquals(..DemoClaims(session, incident, page.Ref), "0|0|0", "no online-demo surface claims that a page email was sent or tried: the incident card and timeline carry no page part, the chat snapshot holds no row of the page, and no email row of the page exists for the digest or anything else to read (Contest Planner condition on the AD-14 amendment)")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(..RouteOf(session, page.Ref), "send:WebChatOut,TelegramOut:;send:EmailOut:", "control: with the flag off the same page goes to the card, Telegram and EmailOut")
	// positive control: EmailOut had taken the demo's message before the absence checks ran. A second page sent to it directly, with the flag off, is mailed, and its mail is the only one.
	Set second = ..PageRow(..Incident(), "oncall", user, "email")
	Set again = ..PageNotice(second, session)
	Do ..ToEmailOut(again)
	Set mails = ..WaitMails(1)
	Do $$$AssertEquals(mails.%Size(), 1, "positive control: a second page sent to EmailOut with the flag off is mailed, so the demo's message had been taken and dropped, and was no mail")
	If mails.%Size() = 1 Do ..AssertMail(mails, 0, again, address, "the second page's email")
}

/// What an online-demo surface could read about a page, as "card|chat|email": 1 when the incident's live payload (its card and timeline) has a page part, the number of rows of the
/// page in the session's chat snapshot (Ownership.RecentNotices, which the chat and its cards load), and the number of email Delivery rows of the page Ref of any owner and kind.
Method DemoClaims(session As %String, incidentRef As %String, pageRef As %String) As %String [ Private ]
{
	Set card = 0
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incidentRef)
	If $IsObject(row) Set card = $IsObject(##class(OcuTalon.Live.Payload.Incident).FromRow(row).Page)
	Set chat = 0
	Set notices = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 100, .sc)
	If $IsObject(notices) {
		For i = 1:1:notices.Count() {
			If notices.GetAt(i).DecisionRef = pageRef Set chat = chat + 1
		}
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Delivery WHERE DecisionRef = ? AND Channel = 'email'", pageRef)
	Do rs.%Next()
	Quit card_"|"_chat_"|"_(+rs.%GetData(1))
}

/// The targets of Notify's rule for a page (or the kind) of the session with the DecisionRef, as the router's action list.
ClassMethod RouteOf(session As %String, ref As %String, kind As %String = "page") As %String [ Private ]
{
	Set engine = ##class(Ens.Host).GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine", .sc)
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = kind
	Set notification.DecisionRef = ref
	Set engine.Document = notification
	Set engine.MsgClass = $ClassName(notification)
	Set engine.Source = "zzsource"
	Set sc = ##class(Ens.Rule.RuleDefinition).EvaluateRulesEx("OcuTalon.Core.Rule.Notify", 0, engine, "", .return, .reason, 1, "e")
	Quit $Select($$$ISOK(sc): $Get(return), 1: "ERROR")
}

/// With EmailOut running, Notify's rule adds EmailOut to a page exactly when the row names email, the online demo is off and the item has a job: not for a row that names telegram alone, not
/// on the online demo, not for an address-only person's page that does not name email, and never for a handled Notification of the page (an email copy is never marked handled).
Method TestNotifyRoutesPageToEmailOut()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("route", 0, .session, .chat)
	Do ..Keys("zzoncall"_..Number_"t"_n_"@example.test")
	Set both = ..PageRow(..Incident(), "oncall", user, "telegram,email")
	Set telegram = ..PageRow(..Incident(), "oncall", user, "telegram")
	Set email = ..PageRow(..Incident(), "oncall", "zzperson"_..Number_"t"_n_"@example.test", "email")
	Do $$$AssertEquals(..RouteOf(session, both.Ref), "send:WebChatOut,TelegramOut:;send:EmailOut:", "telegram,email: the card, Telegram and EmailOut")
	Do $$$AssertEquals(..RouteOf(session, telegram.Ref), "send:WebChatOut,TelegramOut:", "telegram alone: no EmailOut")
	Do $$$AssertEquals(..RouteOf("instance", email.Ref), "send:EmailOut:", "an address-only person whose row names email: EmailOut alone")
	Do $$$AssertEquals(..RouteOf("instance", telegram.Ref), "", "an address-only person whose row does not name email: nowhere")
	Do $$$AssertEquals(..RouteOf("", email.Ref)_"|"_..RouteOf("zznosession"_..Number, email.Ref), "send:EmailOut:|send:EmailOut:", "an empty or unknown SessionRef with a row that names email: EmailOut alone (the email follows the row, not the session)")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Do $$$AssertEquals(..RouteOf(session, both.Ref), "send:WebChatOut:;send:EmailOut:", "telegram,email with Telegram not included: the card and EmailOut, with no Telegram")
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do $$$AssertEquals(..RouteOf(session, both.Ref, "handled") '[ "EmailOut", 1, "a handled Notification for the page never reaches EmailOut: "_..RouteOf(session, both.Ref, "handled"))
	Do $$$AssertEquals(..RouteOf("instance", both.Ref, "handled") '[ "EmailOut", 1, "nor for an address-only person's")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(..RouteOf(session, both.Ref)_"|"_..RouteOf("instance", email.Ref), "|", "the online demo: nothing, EmailOut included")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set item = "OcuTalon.Production||EmailOut"
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(item, 1), "EmailOut is stopped")
	Do $$$AssertTrue(##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 0), "and has no job")
	Do $$$AssertEquals(..RouteOf(session, both.Ref), "send:WebChatOut,TelegramOut:", "no EmailOut job: no EmailOut target")
	Do ##class(Ens.Director).TempStopConfigItem(item, 0)
	Do $$$AssertTrue(##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 1), "EmailOut runs again")
}

/// Matrix row 10 (AC5): the press of Got it on the web card of the session, through the route (origin web_user, AckPage, channel web), acknowledges the page by the web: 200 with handledAt, the web card
/// republished with it, the Telegram copy edited in place to its text, a blank line and "Marked as handled at {time}", and no second mail.
Method TestWebPressEditsTheCopies()
{
	If '..Ready() Quit
	Set n = ..Next()
	// the route resolves the session of the signed-in user, so the paged person is that user and the session is that user's first paired one
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_","_session
	Set ..Sessions = ..Sessions_","_session
	Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef)
	Set chat = ..#CHAT + ..Next()
	Do ..Pair(session, chat, "Zz Presser")
	Set user = $Username
	Do $$$AssertEquals(##class(OcuTalon.Watch.Paging).SessionOf(user), session, "Watch.Paging.SessionOf names the paired session of the signed-in user")
	Set address = "zzoncall"_..Number_"w"_n_"@example.test"
	Do ..Keys(address)
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram,email")
	Set notification = ..PageNotice(page, session)
	// the route runs in this process here, and reads the row by its Ref: an open object of the row that this process saved would be a stale copy of what IncidentManager's job writes
	Set ref = notification.DecisionRef
	Kill page
	Do ..ToNotify(notification)
	Do $$$AssertEquals(..WaitMails(1).%Size(), 1, "one mail")
	Do $$$AssertEquals(..WaitMessages(chat, 1).%Size(), 1, "one Telegram message")
	Do $$$AssertEquals(..WaitRows(ref, "web", 1, session), 1, "one web card")
	Set body = ..Press(session, ref, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the press is 200: "_body)
	Set marked = ..Fresh(ref).AcknowledgedAt
	Do $$$AssertTrue(marked '= "", "the page is acknowledged")
	Do $$$AssertEquals(body, {"result": "done", "handledAt": (marked)}.%ToJSON(), "the body is {result: done, handledAt}")
	Do $$$AssertEquals(..Fresh(ref).AcknowledgedChannel, "web", "by the web")
	Set expected = ##class(OcuTalon.Watch.Paging).Text(notification, "telegram")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set edits = ##class(OcuTalon.Test.Channel.LiveCase).EditsTo(chat)
		If edits.%Size() || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(edits.%Size(), 1, "the Telegram copy is edited once")
	If edits.%Size() = 1 {
		Set edit = edits.%Get(0)
		Do $$$AssertEquals($Piece(edit.text, $Char(10, 10), 1), expected, "its text starts with the page's text")
		Do $$$AssertTrue(edit.text [ "Marked as handled at", "and ends with the handled line: "_edit.text)
		Do $$$AssertEquals(edit.%GetTypeOf("reply_markup"), "unassigned", "with no button")
	}
	Set cards = ##class(OcuTalon.Test.Core.Observe).Events(session, "notification")
	Set published = 0
	For i = 0:1:cards.%Size() - 1 {
		If (cards.%Get(i).payload.decisionRef = ref) && (cards.%Get(i).payload.handledAt = marked) Set published = published + 1
	}
	Do $$$AssertEquals(published, 1, "the web card is published again with handledAt")
	Hang ..#QUIET
	Do $$$AssertEquals(..Mails().%Size()_"|"_..Rows(ref, "email"), "1|1", "no second mail: the email copy is not marked handled")
	Set again = ..Press(session, ref, .response)
	Do $$$AssertEquals(response.Status_"|"_again, "200 OK|"_body, "a second press is 200 with the same handledAt")
	Hang ..#QUIET
	Do $$$AssertEquals(##class(OcuTalon.Test.Channel.LiveCase).EditsTo(chat).%Size()_"|"_..Mails().%Size(), "1|1", "and changes nothing")
}

/// The page row as the disk has it now: this process holds the row it saved, and IncidentManager's job changed it.
Method Fresh(ref As %String) As OcuTalon.Data.Page [ Private ]
{
	Set page = ##class(OcuTalon.Data.Page).RefIndexOpen(ref)
	Do page.%Reload()
	Quit page
}

/// The route's answer to the press of Got it on the page by the session, with the stand-in request and response of Test.Web.GotItApi.
Method Press(session As %String, ref As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make(application)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzPageRoute"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "GotIt", ref)
	Do $$$AssertStatusOK(sc, "GotIt returns OK")
	Set response = %response
	Quit written
}

/// Q1: the cause in the page email is exactly the sentence of the web card, which is the cause after Bridge.Redact.Text and the cap of 1000 characters (PageText). A secret-shaped cause (fake
/// values) is redacted alike in the card and in the body, and its raw values are in neither; an over-long cause is cut alike in both; a plain one is unchanged. The name is the Settings name as the
/// admin set it (with case and punctuation), and no text of the incident's items or messages (its sample error holds a marker) reaches the body or the subject. The Telegram copy is not asserted
/// here: TelegramOut renders its page text itself (Lane A) and is not passed through PageText.
Method TestEmailBodyHoldsTheCardsCause()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("cause", 1, .session, .chat)
	Set address = "zzoncall"_..Number_"c"_n_"@example.test"
	Set name = "Zz O'Neil-Backup "_..Number_" JR."
	Do ..Keys(address, "", "", name)
	Set plain = "The partner sent a plain date that OcuTalon could not read."
	Set secret = "The key sk-live-ZZ9Q8W7E6R5T4Y3U2I1O0P9A8S7D6F5G was refused, password=hunter2 and token=FAKE-test-value-0000 were sent"
	Set long = "The partner sent a date in an unknown format "_$Translate($Justify("", 3000), " ", "x")
	// a key that starts at character 992, so the cap falls inside it: cut first, its first 9 characters would be too short for the redactor and would stay
	Set across = $Extract("The partner sent a date in an unknown format "_$Translate($Justify("", 1000), " ", "x"), 1, 990)_" sk-live-ZZ9Q8W7E6R5T4Y3U2I1O0P9A8S7D6F5G was refused."
	// each case: label, cause, the raw values that no part of the card or the body may hold
	Set cases = $ListBuild($ListBuild("a plain cause", plain, ""), $ListBuild("a secret-shaped cause", secret, $ListBuild("sk-live-ZZ9Q8W7E6R5T4Y3U2I1O0P9A8S7D6F5G", "hunter2", "FAKE-test-value-0000")), $ListBuild("an over-long cause", long, ""), $ListBuild("a secret across the cap", across, $ListBuild("sk-live-")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set cause = $List(case, 2)
		Set incident = ..Incident()
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Set isPlain = (cause = plain)
		Set page = ..PageRow(incident, "oncall", user, $Select(isPlain: "telegram,email", 1: "email"))
		Set notification = ..PageNotice(page, session)
		Set slots = {}.%FromJSON(notification.Slots)
		Do slots.%Set("cause", cause)
		Set notification.Slots = slots.%ToJSON()
		// the sentence of Q1, worked out here: the redactor's text, cut to the incident Cause's limit
		Set sentence = $Extract(##class(OcuTalon.Bridge.Redact).Text(cause), 1, 1000)
		Do $$$AssertEquals(sentence = cause, isPlain, label_": the sentence differs from the raw cause exactly when the cause is not plain")
		If cause = long Do $$$AssertEquals($Length(sentence), 1000, label_": and is cut to 1000 characters")
		Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
		Set before = ..Messages(chat).%Size()
		Do ..ToNotify(notification)
		Set mails = ..WaitMails(1)
		Do $$$AssertEquals(mails.%Size(), 1, label_": one mail")
		If mails.%Size() '= 1 Continue
		Set body = $ZStrip(mails.%Get(0).text, ">WC")
		Do $$$AssertEquals(..WaitRows(page.Ref, "web", 1, session), 1, label_": one web card")
		Set card = ..CopyOf(page.Ref, "web", session)
		Do $$$AssertTrue($IsObject(card), label_": the web card is there")
		If '$IsObject(card) Continue
		Set text = $ZStrip(card.Text, ">WC")
		Set closing = $Select($Extract(sentence, $Length(sentence)) = ".": "", 1: ".")
		Do $$$AssertTrue(body [ (sentence_closing), label_": the body holds the sentence")
		Do $$$AssertTrue(text [ (sentence_closing), label_": the web card holds the same sentence")
		If cause = long {
			Do $$$AssertEquals((body [ $Extract(cause, 1, 1001)) + (text [ $Extract(cause, 1, 1001)), 0, label_": neither holds a character past the cap")
		}
		Set raws = $List(case, 3)
		Set at = 0
		While $ListNext(raws, at, raw) {
			Do $$$AssertEquals((body [ raw) + (text [ raw) + (mails.%Get(0).subject [ raw), 0, label_": the raw value "_$Extract(raw, 1, 8)_"... is in neither the body, the card nor the subject")
		}
		Do $$$AssertTrue(body [ name, label_": the body has the name exactly as the admin set it (case and punctuation)")
		Do $$$AssertTrue(text [ name, label_": and so does the card")
		Do $$$AssertEquals(body, $ZStrip(##class(OcuTalon.Channel.PageText).Text(notification, "email"), ">WC"), label_": the body is PageText for email")
		If isPlain {
			Set messages = ..WaitMessages(chat, before + 1)
			Do $$$AssertTrue(messages.%Size() > before, label_": and the Telegram copy is sent")
			If messages.%Size() > before Do $$$AssertTrue(messages.%Get(messages.%Size() - 1).text [ plain, label_": (the Telegram text holds a plain cause as it is)")
		}
		Do $$$AssertEquals(body [ ("zzitemmarker"_..Number), 0, label_": the incident's sample error (item and message text) is in no part of the body")
		Do $$$AssertEquals($ZStrip(mails.%Get(0).subject, "*C") [ ("zzitemmarker"_..Number), 0, label_": nor of the subject")
		Do $$$AssertTrue(row.SampleError [ ("zzitemmarker"_..Number), label_": (positive control: the incident's item text holds the marker)")
	}
}

/// Story 24.3b (AC3, AC5; Integration, Rule 1): an unacknowledged address-only on-call page of an open incident, the backup's address set, and an escalation asked from system with a delay of 3 seconds. After it
/// falls due, ReminderTimer's Escalation reaches the real IncidentManager, which records exactly one backup page row, and Notify and EmailOut send exactly one mail to the backup key's address (AssertMail). After the
/// quiet time there is still one row and one mail. The ids-only check: no message body since the ask (the SetReminder, ReminderStart and Escalation bodies among them), no Reminder row and no Ens.Util.Log line holds an
/// address or the on-call person (the positive control is that the mock received the mail, and that the bodies hold the page's Ref).
Method TestEscalationMailsTheBackup()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set primary = "zzoncall"_..Number_"x"_n_"@example.test"
	Set person = "zzperson"_..Number_"x"_n_"@example.test"
	Set backup = "zzbackup"_..Number_"x"_n_"@example.test"
	Do ..Keys(primary, "", backup)
	Set names = $ListBuild(primary, person, backup, "zzpagefrom"_..Number)
	Set incident = ..Incident()
	Set first = ..PageRow(incident, "oncall", person, "email")
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
	Set headerMark = ##class(OcuTalon.Test.Channel.LiveCase).HeaderMark()
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.Kind = "escalation"
	Set command.IncidentRef = incident
	Set command.PageRef = first.Ref
	Set command.DelaySeconds = 3
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "system", .result)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_$IsObject($Get(result)), "1|1", "the escalation ask is submitted and answered")
	If $$$ISERR(sc) || '$IsObject($Get(result)) Quit
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|set", "the escalation is set")
	Set ref = result.Ref
	Set bodyId = command.%Id()
	Set mails = ..WaitMails(1)
	Do $$$AssertEquals(mails.%Size(), 1, "positive control: the SMTP stub holds one mail after the escalation fell due")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set backupPage = ##class(OcuTalon.Data.Page).IncidentRoleIndexOpen(incident, "backup")
		If $IsObject(backupPage) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(backupPage), "IncidentManager recorded the backup's page row")
	If $IsObject(backupPage) {
		Set ..PageRefs = ..PageRefs_","_backupPage.Ref
		If mails.%Size() = 1 Do ..AssertMail(mails, 0, ..PageNotice(backupPage, "instance"), backup, "the backup's page email")
		Do $$$AssertEquals(..WaitRows(backupPage.Ref, "email", 1), 1, "one email claim row for the backup's page")
	}
	Hang ..#QUIET
	Set pages = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Page WHERE IncidentRef = ? AND PageRole = 'backup'", incident)
	Do pages.%Next()
	Do $$$AssertEquals(+pages.%GetData(1), 1, "exactly one backup page row of the incident after the quiet time")
	Do $$$AssertEquals(..Mails().%Size(), 1, "and exactly one mail, to the backup key's address")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the escalation row exists")
	If $IsObject(row) Do $$$AssertEquals(row.State_"|"_row.SessionRef, "fired|instance", "the escalation row is fired and owned by instance")
	Set row = ""
	Set bodies = ##class(OcuTalon.Test.Channel.LiveCase).Bodies(headerMark)
	Set headers = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT SourceConfigName, TargetConfigName, Description, SessionId, SuperSession FROM Ens.MessageHeader WHERE ID > ?", headerMark)
	Set logs = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT Text FROM Ens_Util.Log WHERE ID > ?", logMark)
	Set rows = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionRef, Text, Kind, IncidentRef, PageRef, IdempotencyKey, CancelKey FROM OcuTalon_Data.Reminder WHERE Ref = ?", ref)
	While rs.%Next() {
		For column = 1:1:rs.%ResultColumnCount {
			Set rows = rows_rs.%GetData(column)_$Char(10)
		}
	}
	Do $$$AssertTrue((bodies [ incident) && (bodies [ first.Ref), "positive control: the trace holds the SetReminder and Escalation bodies, which name the incident and the page")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(bodies, names), "", "no Ens message body since the ask holds an address of the sends")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(headers, names), "", "no Ens message header does")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(logs, names), "", "no Ens.Util.Log line since the ask does (ReminderOps, ReminderTimer and IncidentManager included)")
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Paging).Holds(rows, names), "", "and the escalation's Reminder row does not")
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(ref)
	Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTraces($ListBuild(bodyId))
}

/// AC4 and V2: the distinctive addresses, user names and chat ids that this test and the tests that ran before it sent to the mock, and the mails' subjects and bodies, are in no Ens message body or
/// header, no Ens.Util.Log line and no audit entry since the run began. The positive control is that the mock received them (its mail and Telegram message are asserted first).
Method TestNoIdentityInTheTrace()
{
	If '..Ready() Quit
	Set n = ..Next()
	Set user = ..User("identity", 1, .session, .chat)
	Set address = "zzoncall"_..Number_"i"_n_"@example.test"
	Set person = "zzperson"_..Number_"i"_n_"@example.test"
	Set name = "Zz Identity Backup "_..Number
	Do ..Keys(address, "", "", name)
	Set names = $ListBuild(address, person, user, chat, name, "zzpagefrom"_..Number)
	Set incident = ..Incident()
	Set page = ..PageRow(incident, "oncall", user, "telegram,email")
	Set other = ..PageRow(..Incident(), "oncall", person, "email")
	Do ##class(OcuTalon.Test.Channel.EmailLive).SmtpControl("reset", {})
	// the window of the sends: after the pairing and the keys (the pairing's own audit entry names the user, as it must)
	Set headerMark = ##class(OcuTalon.Test.Channel.LiveCase).HeaderMark()
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..ToNotify(..PageNotice(page, session))
	Do ..ToNotify(..PageNotice(other, "instance"))
	Set mails = ..WaitMails(2)
	Do $$$AssertEquals(mails.%Size(), 2, "positive control: the mock received both page emails")
	Set text = ""
	For i = 0:1:mails.%Size() - 1 {
		Set text = text_mails.%Get(i).subject_$Char(10)_mails.%Get(i).text
		Set names = names_$ListBuild(mails.%Get(i).subject, mails.%Get(i).text)
	}
	Do $$$AssertTrue((text [ address) = 0, "(the mails name no address: the addresses are in the headers of the mock's record)")
	Do $$$AssertEquals(..WaitMessages(chat, 1).%Size(), 1, "and the Telegram copy to the chat that the scan looks for")
	Do $$$AssertEquals(..WaitRows(page.Ref, "web", 1, session), 1, "and the card")
	Hang ..#QUIET
	Set bodies = ##class(OcuTalon.Test.Channel.LiveCase).Bodies(headerMark)
	Set headers = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT SourceConfigName, TargetConfigName, Description, SessionId, SuperSession FROM Ens.MessageHeader WHERE ID > ?", headerMark)
	Set logs = ##class(OcuTalon.Test.Channel.LiveCase).RowsText("SELECT Text FROM Ens_Util.Log WHERE ID > ?", logMark)
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(auditMark, "OcuTalon").%ToJSON()
	Do $$$AssertTrue((bodies [ page.Ref) && (bodies [ other.Ref), "positive control: the trace holds both pages' Notifications")
	Set found = ##class(OcuTalon.Test.Watch.Paging).Holds(bodies, names)
	Do $$$AssertEquals(found, "", "no Ens message body holds an address, user name, chat id, subject or text of the sends"_$Select(found = "": "", 1: " [found "_$Extract(found, 1, 40)_"]"))
	Set found = ##class(OcuTalon.Test.Watch.Paging).Holds(headers, names)
	Do $$$AssertEquals(found, "", "no Ens message header does"_$Select(found = "": "", 1: " [found "_$Extract(found, 1, 40)_"]"))
	Do $$$AssertTrue($Length(logs) > 0, "positive control: the event log has lines of the sends")
	Set found = ##class(OcuTalon.Test.Watch.Paging).Holds(logs, names)
	Do $$$AssertEquals(found, "", "no Ens.Util.Log line does"_$Select(found = "": "", 1: " [found "_$Extract(found, 1, 40)_"]"))
	Set found = ##class(OcuTalon.Test.Watch.Paging).Holds(audit, names)
	Do $$$AssertEquals(found, "", "no audit entry does"_$Select(found = "": "", 1: " [found "_$Extract(found, 1, 40)_"]"))
}

}
