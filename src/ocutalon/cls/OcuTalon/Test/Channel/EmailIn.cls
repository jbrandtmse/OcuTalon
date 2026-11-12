/// Tests of EmailIn's adapter and service (Story 21.2; AD-14, AD-19, AD-28, AD-30, AD-33) against a stand-in for %Net.POP3 (Test.Channel.EmailInPop3): the
/// adapter is a Test.Channel.EmailInAdapter, the real adapter with its connection and its hand-off to the service replaced, and the service a
/// Test.Channel.EmailInServiceProbe, the real service with its send recorded. Safe on a slot: no production runs, nothing is opened, and every Data.MailSeen
/// row, the status mark emailPoll and the product key email.owner are put back. Every text is written out here, never read from the product.
///   - TestFirstPollIsBaseline (matrix row 8): the first poll of a mailbox new to EmailIn records every listed UIDL as seen, makes no Item and reads no email,
///     and records emailPoll ok 1;
///   - TestNewMail (row 9): new emails are handed on oldest first with their UIDL, From, Subject and plain text, each is recorded seen after it was handed on,
///     the connection ends with QUIT, and nothing is ever deleted; at most 50 go on in a poll and the rest on the next (RULED V-COST);
///   - TestSeenMail (row 10): a seen email is never handed on again, also by a new adapter instance (an EmailIn restart);
///   - TestLargeAndHtmlMail (row 11): an email over 1,048,576 bytes is read as headers only; an HTML-only email has its tags removed and its text cut to
///     10,000 characters; a multipart email gives its plain part;
///   - TestFailedPoll (row 12): each failure has the sentence of its kind, the mark holds {at, ok 0, reason, lastOkAt} and nothing else, no server text, address
///     or user name is in the mark or the log, a failed poll still returns OK, and the seen rows of emails already handed on stay;
///   - TestGoneMail: a UIDL that is no longer listed has its row deleted after a successful poll, and so has every row of another mailbox;
///   - TestDeleteIsNeverHonoured: the DeleteMessage setting is forced to 0, whatever it was, and no poll deletes;
///   - TestNoRepeatAfterFailure: an email whose hand-off failed is not recorded seen and goes on at the next poll;
///   - TestUnreadableEmailIsReadAsHeaders (DW-1138): an email whose whole read fails in 3 polls in a row is read as headers only at the 4th, so the
///     mail after it is not held up and nothing is dropped;
///   - TestStopEndsThePollBetweenEmails: when the production asks the item to stop, the poll ends after the email in hand as a good poll, and the
///     rest go on at the next poll;
///   - TestWaitsForTheNextInterval: a poll that handed emails on leaves the business host waiting CallInterval for the next poll (RULED V-COST: at
///     most 50 per interval), although the hand-off cleared the flag;
///   - TestServiceItem (row 9): the service sends one Item to Intake for an email: channel email, provenance untrusted, the owner from the email.owner row, the
///     three fields, every other field empty, the SuperSession the owner's TraceRef; the text is cut to the size of the simulated mailbox's body (RULED V-COST);
///   - TestServiceRefusals: an input that is no email, an email with no UIDL, no owner or an owner without a session row, and a failed send, are error statuses and
///     send nothing (a failed send sends the one).
///   - TestAdapterCarriesSentRef (DW-1167): the adapter gives the service the value of the header X-OcuTalon-Ref of an email, from the whole read and from the
///     headers-only read, and an empty value for an email without it;
///   - TestServiceSkipsOwnMail (DW-1167, ruling V4): the service makes no Item of an email only when its Ref is a sent email Delivery row's, its From is
///     email.address and the Ref was not taken before; it takes the Ref's one use and logs the Ref and nothing of the email; the first email with the Ref and
///     a From that is not email.address does not use it up; the claim row of an email that was not sent, a row of another channel, an unknown or forged Ref,
///     an empty one and a second use each leave an Item as before.
/// The run's number is n from ^OcuTalonTest("EmailIn","n") (never reset).
Class OcuTalon.Test.Channel.EmailIn Extends %UnitTest.TestCase
{

/// The adapter and the service under test.
Parameter ADAPTER = "OcuTalon.Test.Channel.EmailInAdapter";

Parameter SERVICE = "OcuTalon.Test.Channel.EmailInServiceProbe";

/// The stand-in connection.
Parameter POP3 = "OcuTalon.Test.Channel.EmailInPop3";

/// The sentences of a failed poll (Public text P1a to P1c).
Parameter UNREACHABLE = "OcuTalon couldn't reach the mail server.";

Parameter REFUSED = "The mail server refused the user name or password.";

Parameter UNREADABLE = "OcuTalon couldn't read the mailbox.";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The mailbox identities that the run made, comma-separated.
Property Mailboxes As %String(MAXLEN = "");

/// The Refs of the Delivery rows a test made, comma-separated.
Property Deliveries As %String(MAXLEN = "");

/// The key email.address as found: $ListBuild(row exists, value).
Property AddressFound As %List;

/// The status mark emailPoll and the key email.owner as found: $ListBuild(mark, owner row exists, owner).
Property Found As %List;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("EmailIn", "n"))
	Set ..Refs = ""
	Set ..Mailboxes = ""
	Set ..Deliveries = ""
	Set address = ##class(OcuTalon.Data.Setting).KeyIndexOpen("email.address")
	Set ..AddressFound = $ListBuild($IsObject(address), $Select($IsObject(address): address.Value, 1: ""))
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("email.owner")
	Set ..Found = $ListBuild(##class(OcuTalon.Data.StatusMark).Get("emailPoll"), $IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^||OcuTalonEmailInPop3
	Kill ^||OcuTalonEmailInAdapter
	Kill ^OcuTalonTest("EmailInServiceProbe", ..Number)
	Do ##class(OcuTalon.Data.StatusMark).Record("emailPoll", "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^||OcuTalonEmailInPop3
	Kill ^||OcuTalonEmailInAdapter
	Kill ^OcuTalonTest("EmailInServiceProbe", ..Number)
	Set position = 0
	For i = 1:1:$Length(..Mailboxes, ",") {
		If $Piece(..Mailboxes, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.MailSeen WHERE Mailbox = ?", $Piece(..Mailboxes, ",", i))
	}
	Do ##class(OcuTalon.Data.StatusMark).Record("emailPoll", $List(..Found, 1))
	If $List(..Found, 2) {
		Do ##class(OcuTalon.Data.Setting).Set("email.owner", $List(..Found, 3))
	} Else {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete("email.owner")
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	For i = 1:1:$Length(..Deliveries, ",") {
		If $Piece(..Deliveries, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE ChannelMessageId = ?", $Piece(..Deliveries, ",", i))
	}
	If $List(..AddressFound, 1) {
		Do ##class(OcuTalon.Data.Setting).Set("email.address", $List(..AddressFound, 2))
	} Else {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete("email.address")
	}
	Kill ^||OcuTalon.Setting("email.address"), ^||OcuTalon.Setting("email.owner")
	Quit $$$OK
}

/// Matrix row 8: the first poll of a new mailbox makes no Item.
Method TestFirstPollIsBaseline()
{
	Set adapter = ..Adapter("first")
	Do ..Mail("u1"), ..Mail("u2"), ..Mail("u3")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 0, "no email is handed on")
	Do $$$AssertEquals(..Count("Fetch")_"|"_..Count("FetchMessageHeaders")_"|"_..Count("GetSizeOfMessages"), "0|0|0", "and none is read")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,u2=1,u3=1,baseline marker=1", "the three emails and then the marker are recorded, all as baseline")
	Set mark = ..Mark()
	Do $$$AssertEquals(mark.ok_"|"_mark.reason_"|"_(mark.lastOkAt = mark.at)_"|"_(mark.at ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"), "1||1|1", "emailPoll is ok, with no reason, and lastOkAt is this poll")
	Do $$$AssertEquals(..Count("QuitAndCommit")_"|"_..Count("DeleteMessage"), "1|0", "the connection ends with QUIT and nothing is deleted")
	Do $$$AssertEquals(^||OcuTalonEmailInPop3("connect"), $ListBuild("pop.example.com", 995, ^||OcuTalonEmailInAdapter("user")), "it connected to the server and port of the settings, as the credential's user")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 0, "the second poll finds nothing new")
}

/// Matrix row 9: new mail is handed on, oldest first, and recorded seen after it; at most 50 a poll.
Method TestNewMail()
{
	Set adapter = ..Adapter("new")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2", "Dana <dana@example.com>", "zz Invoice", "zz first body"), ..Mail("u3", "b@example.com", "zz Two", "zz second body"), ..Mail("u4", "c@example.com", "zz Three", "zz third body")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 3, "three new emails are handed on")
	Do $$$AssertEquals(..Handed(1), $ListBuild("u2", "Dana <dana@example.com>", "zz Invoice", "zz first body"), "the oldest first, with its UIDL, sender, subject and text")
	Do $$$AssertEquals($List(..Handed(2), 1)_","_$List(..Handed(3), 1), "u3,u4", "then the others in order")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1,u2=0,u3=0,u4=0", "each is recorded seen, not as baseline")
	Do $$$AssertEquals(..Count("DeleteMessage"), 0, "nothing is deleted")
	Do $$$AssertEquals(..Count("Fetch"), 3, "each was read whole once")
	Do $$$AssertEquals(..Mark().ok, 1, "the poll is ok")
	// at most 50 a poll
	Kill ^||OcuTalonEmailInAdapter("delivered")
	For i = 1:1:60 {
		Do ..Mail("m"_$Justify(i, 3))
	}
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 50, "of 60 new emails a poll hands on 50")
	Do $$$AssertEquals($List(..Handed(1), 1)_","_$List(..Handed(50), 1), "m  1,m 50", "the oldest 50")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 60, "and the next poll hands on the other 10")
	Do $$$AssertEquals($List(..Handed(51), 1)_","_$List(..Handed(60), 1), "m 51,m 60", "the rest, oldest first")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 60, "then there is nothing more")
}

/// Matrix row 10: a seen email is never handed on again, also after a restart (a new adapter instance reads the table).
Method TestSeenMail()
{
	Set adapter = ..Adapter("seen")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "one new email is handed on")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "a second poll does not hand it on again")
	Set again = ..Adapter("seen", 0)
	Do again.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "nor does a restarted adapter")
	Do ..Mail("u3")
	Do again.OnTask()
	Do $$$AssertEquals(..Delivered(), 2, "but a newer one goes on")
	Do $$$AssertEquals($List(..Handed(2), 1), "u3", "it is u3")
}

/// Matrix row 11: a large email is read as headers only; an HTML-only email loses its tags and is cut; a multipart email gives its plain part.
Method TestLargeAndHtmlMail()
{
	Set adapter = ..Adapter("large")
	Do ..Mail("u0")
	Do adapter.OnTask()
	Do ..Mail("big", "Big <big@example.com>", "zz Big one", "zz never read", "", 1048577)
	Do ..Mail("edge", "Edge <edge@example.com>", "zz Edge", "zz read whole", "", 1048576)
	Do ..Mail("html", "h@example.com", "zz Html", "", "<html><head><style>p{color:red}</style></head><body><p>Hi &amp; welcome&nbsp;there</p><script>alert(1)</script><p>Second</p></body></html>")
	Do ..Mail("long", "l@example.com", "zz Long", $Translate($Justify("", 12000), " ", "x"))
	Do ..Mail("alt", "a@example.com", "zz Alt", "zz plain part", "<p>zz html part</p>", 0, 1)
	Do ..Mail("htmllong", "hl@example.com", "zz Html long", "", "<p>"_$Translate($Justify("", 12000), " ", "y")_"</p>")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 6, "six emails are handed on")
	Do $$$AssertEquals(..Handed(1), $ListBuild("big", "Big <big@example.com>", "zz Big one", ""), "an email of 1,048,577 bytes has its headers only: sender and subject, an empty text")
	Do $$$AssertEquals($Get(^||OcuTalonEmailInPop3("fetched", 2))_"|"_$Get(^||OcuTalonEmailInPop3("headers", 2)), "|1", "it was read by its headers, not whole")
	Do $$$AssertEquals($Get(^||OcuTalonEmailInPop3("fetched", 3)), 1, "an email of exactly 1,048,576 bytes is read whole")
	Do $$$AssertEquals($List(..Handed(2), 4), "zz read whole", "with its text")
	Do $$$AssertEquals($List(..Handed(3), 4), "Hi & welcome there Second", "an HTML-only email has its tags, script and style removed, its entities decoded and its white space collapsed")
	Do $$$AssertEquals($Length($List(..Handed(4), 4)), 10000, "a long text is cut to 10,000 characters")
	Do $$$AssertEquals($List(..Handed(5), 4), "zz plain part", "a multipart email gives its plain part")
	Do $$$AssertEquals($Length($List(..Handed(6), 4))_"|"_($List(..Handed(6), 4) '[ "<"), "10000|1", "an HTML text is cut after its tags are removed")
}

/// Hostile HTML costs time in proportion to its size: 100,000 unclosed script tags and 300,000 "<" with no ">" are stripped in well under a second each,
/// an unclosed script or style block runs to the end of the text, and a "<" with no ">" stays.
Method TestStripTagsIsLinear()
{
	Set adapter = "OcuTalon.Channel.Email.Adapter"
	Set scripts = "", opens = ""
	For i = 1:1:100000 {
		Set scripts = scripts_"<script "
	}
	For i = 1:1:30 {
		Set opens = opens_$Translate($Justify("", 10000), " ", "<")
	}
	Set start = $ZHorolog
	Set unclosed = $ClassMethod(adapter, "StripTags", "keep "_scripts_" dropped")
	Set bare = $ClassMethod(adapter, "StripTags", "a"_opens_"b")
	Set seconds = $ZHorolog - start
	Do $$$AssertEquals(unclosed, "keep", "unclosed script blocks run to the end of the text")
	Do $$$AssertEquals($Length(bare)_"|"_$Extract(bare, 1)_"|"_$Extract(bare, *), "300002|a|b", "a < with no > stays")
	Do $$$AssertTrue(seconds < 5, "both are stripped in under 5 seconds: "_seconds)
	Do $$$AssertEquals($ClassMethod(adapter, "StripTags", "x<style>p{}</style>y<STYLE>z"), "x y", "style blocks are dropped, closed or not, in any case")
	Do $$$AssertEquals($ClassMethod(adapter, "StripTags", "a<b>c</b> <i"), "a c <i", "tags go and an unfinished one stays")
}

/// Matrix row 12: each failure has its sentence; the mark holds the four members and nothing of the server.
Method TestFailedPoll()
{
	Set adapter = ..Adapter("failed")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Set okAt = ..Mark().at
	Set cases = $ListBuild("ConnectPort|6012|"_..#UNREACHABLE, "ConnectPort|6013|"_..#UNREACHABLE, "ConnectPort|6085|"_..#UNREACHABLE, "ConnectPort|6015~-ERR SERVER-WORDS zzserver@example.com|"_..#REFUSED, "ConnectPort|6015~|"_..#UNREACHABLE, "ConnectPort|6015~* OK SERVER-WORDS IMAP ready|"_..#UNREACHABLE, "ConnectPort|6018|"_..#UNREACHABLE, "GetMessageUIDArray|6015|"_..#UNREADABLE, "GetMessageUIDArray|6014|"_..#UNREADABLE)
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^||OcuTalonEmailInPop3("answer")
		Set ^||OcuTalonEmailInPop3("answer", $Piece(case, "|", 1)) = $Piece(case, "|", 2)
		Set sc = adapter.OnTask()
		Do $$$AssertStatusOK(sc, $Piece(case, "|", 1)_" "_$Piece(case, "|", 2)_": a failed poll returns OK")
		Set mark = ..Mark()
		Do $$$AssertEquals(mark.ok_"|"_mark.reason, "0|"_$Piece(case, "|", 3), $Piece(case, "|", 1)_" "_$Piece(case, "|", 2)_": ok 0 and the sentence of its kind")
		Do $$$AssertEquals(mark.lastOkAt, okAt, "lastOkAt stays the last good poll's")
		Set names = ""
		Set iterator = mark.%GetIterator()
		While iterator.%GetNext(.key) {
			Set names = names_$Select(names = "": "", 1: ",")_key
		}
		Do $$$AssertEquals(names, "at,ok,reason,lastOkAt", "the mark has these four members")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("emailPoll") [ "SERVER-WORDS", 0, "the mark has no server text")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("emailPoll") [ "zzserver@example.com", 0, "no address")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("emailPoll") [ "zzmailuser", 0, "and no user name")
	}
	Kill ^||OcuTalonEmailInPop3("answer")
	// a failed read of the first new email hands nothing on
	Do ..Mail("u2"), ..Mail("u3"), ..Mail("u4")
	Set ^||OcuTalonEmailInPop3("answer", "Fetch") = 6015
	Do adapter.OnTask()
	Do $$$AssertEquals(..Mark().reason, ..#UNREADABLE, "a failed read of an email is the unreadable sentence")
	Do $$$AssertEquals(..Delivered(), 0, "nothing was handed on")
	Kill ^||OcuTalonEmailInPop3("answer")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Mark().ok, 1, "a good poll after the failures is ok again")
	Do $$$AssertEquals(..Mark().lastOkAt = ..Mark().at, 1, "with lastOkAt now")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", "SERVER-WORDS"), 0, "no log row holds the server's words")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", "zzserver@example.com"), 0, "or the address")
}

/// An email whose hand-off failed is not recorded seen and goes on at the next poll; the ones handed on before it stay seen.
Method TestNoRepeatAfterFailure()
{
	Set adapter = ..Adapter("norepeat")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2"), ..Mail("u3")
	Set ^||OcuTalonEmailInAdapter("fail") = 1
	Do adapter.OnTask()
	Do $$$AssertEquals(..Mark().ok_"|"_..Mark().reason, "0|"_..#UNREADABLE, "a refused hand-off fails the poll")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1", "and records nothing for the email")
	Kill ^||OcuTalonEmailInAdapter("fail")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 2, "the next poll hands both on")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1,u2=0,u3=0", "and records them")
	// a failure after the first of two: the first stays seen, the second goes on at the next poll
	Do ..Mail("u4"), ..Mail("u5")
	Set ^||OcuTalonEmailInAdapter("failAt") = 2
	Set ^||OcuTalonEmailInAdapter("calls") = 0
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 3, "u4 was handed on, u5 was refused")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1,u2=0,u3=0,u4=0", "u4 is recorded seen and u5 is not")
	Kill ^||OcuTalonEmailInAdapter("failAt")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 4, "u5 goes on at the next poll")
	Do $$$AssertEquals($List(..Handed(4), 1), "u5", "it is u5")
}

/// DW-1138: an email whose whole read fails in READTRIES polls in a row is read as headers only at the next, and the mail after it goes on.
Method TestUnreadableEmailIsReadAsHeaders()
{
	Set adapter = ..Adapter("unreadable")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2", "Dana <dana@example.com>", "zz cannot be read", "zz body"), ..Mail("u3", "b@example.com", "zz after it", "zz later body")
	Set ^||OcuTalonEmailInPop3("answer", "Fetch") = 6015
	For try = 1:1:3 {
		Do adapter.OnTask()
		Do $$$AssertEquals(..Delivered()_"|"_..Mark().reason, "0|"_..#UNREADABLE, "poll "_try_": the whole read fails, nothing goes on")
	}
	Do $$$AssertEquals(..Count("FetchMessageHeaders"), 0, "control: no headers were read yet")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "the 4th poll hands it on")
	Do $$$AssertEquals(..Handed(1), $ListBuild("u2", "Dana <dana@example.com>", "zz cannot be read", ""), "as headers only: its sender and subject, an empty text")
	Kill ^||OcuTalonEmailInPop3("answer")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 2, "the next email is not held up")
	Do $$$AssertEquals(..Handed(2), $ListBuild("u3", "b@example.com", "zz after it", "zz later body"), "and is read whole")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1,u2=0,u3=0", "both are recorded seen")
}

/// A stop asked during a poll ends it after the email in hand; the rest go on at the next poll.
Method TestStopEndsThePollBetweenEmails()
{
	Set adapter = ..Adapter("stop")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2"), ..Mail("u3"), ..Mail("u4")
	Set ^||OcuTalonEmailInAdapter("stopAfter") = 1
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "a stop asked after the first email ends the poll there")
	Do $$$AssertEquals(..Mark().ok_"|"_..Mark().reason, "1|", "as a good poll")
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,baseline marker=1,u2=0", "only the email handed on is recorded")
	Kill ^||OcuTalonEmailInAdapter("stopAfter")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 3, "the next poll hands the other two on")
	Do $$$AssertEquals($List(..Handed(2), 1)_","_$List(..Handed(3), 1), "u3,u4", "in order")
}

/// RULED V-COST: a poll that handed emails on leaves the host waiting CallInterval for the next poll.
Method TestWaitsForTheNextInterval()
{
	Set adapter = ..Adapter("interval")
	Set adapter.BusinessHost = ..Service()
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2")
	Set adapter.BusinessHost.%WaitForNextCallInterval = 1
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "control: an email was handed on, which clears the flag")
	Do $$$AssertEquals(adapter.BusinessHost.%WaitForNextCallInterval, 1, "the host still waits CallInterval for the next poll")
	Set ^||OcuTalonEmailInAdapter("fail") = 1
	Do ..Mail("u3")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Mark().ok, 0, "control: a refused hand-off fails the poll")
	Do $$$AssertEquals(adapter.BusinessHost.%WaitForNextCallInterval, 1, "and the next try waits CallInterval too")
}

/// A UIDL that is no longer listed has its row deleted after a good poll, and so has every row of another mailbox.
Method TestGoneMail()
{
	Set adapter = ..Adapter("gone")
	Do ..Mail("u1"), ..Mail("u2"), ..Mail("u3")
	Do adapter.OnTask()
	Set other = ##class(OcuTalon.Data.MailSeen).IdentityOf("elsewhere.example.com", 995, "zzgone"_..Number)
	Set ..Mailboxes = ..Mailboxes_$Select(..Mailboxes = "": "", 1: ",")_other
	Do $$$AssertStatusOK(##class(OcuTalon.Data.MailSeen).Record(other, "x1", 0), "a row of another mailbox exists")
	Do ##class(OcuTalon.Test.Channel.EmailInPop3).Remove("u2")
	Set ^||OcuTalonEmailInPop3("answer", "GetMessageUIDArray") = 6015
	Do adapter.OnTask()
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,u2=1,u3=1,baseline marker=1", "a failed poll deletes nothing")
	Kill ^||OcuTalonEmailInPop3("answer")
	Do adapter.OnTask()
	Do $$$AssertEquals(..SeenRows(adapter), "u1=1,u3=1,baseline marker=1", "a good poll deletes the row of the email that is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.MailSeen).Seen(other, "x1"), 0, "and the row of the other mailbox")
}

/// The DeleteMessage setting is forced to 0, and no poll deletes, whatever the setting was.
Method TestDeleteIsNeverHonoured()
{
	Set adapter = ..Adapter("delete", 1, 1)
	Do $$$AssertEquals(adapter.DeleteMessage, 0, "OnInit forces DeleteMessage to 0")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 1, "an email is handed on")
	Do $$$AssertEquals(..Count("DeleteMessage"), 0, "and the server is never asked to delete")
}

/// The service's Item for an email (matrix row 9) and the cut to the simulated mailbox's size.
Method TestServiceItem()
{
	Set owner = ..Session("item")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(owner).TraceRef
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", owner)
	Set service = ..Service()
	Set mail = ##class(OcuTalon.Channel.Email.Mail).%New()
	Set mail.Uidl = "u1"
	Set mail.Sender = "Dana <dana@example.com>"
	Set mail.Subject = "zz Invoice"
	Set mail.Text = "zz body"
	Do $$$AssertStatusOK(service.OnProcessInput(mail, .output), "the email is accepted")
	Do $$$AssertEquals(^OcuTalonTest("EmailInServiceProbe", ..Number), 1, "one request is sent")
	Set call = $Name(^OcuTalonTest("EmailInServiceProbe", ..Number, 1))
	Do $$$AssertEquals(@call@("target")_"|"_@call@("class")_"|"_@call@("superSession"), "Intake|OcuTalon.Msg.Item|"_trace, "an Item to Intake in the owner's TraceRef SuperSession")
	Do $$$AssertEquals(@call@("sessionRef")_"|"_@call@("channel")_"|"_@call@("provenance"), owner_"|email|untrusted", "owned by email.owner, channel email, provenance untrusted")
	Do $$$AssertEquals(@call@("sender")_"|"_@call@("subject")_"|"_@call@("text"), "Dana <dana@example.com>|zz Invoice|zz body", "with the three fields")
	Do $$$AssertTrue(@call@("itemId") ? 22(1AN,1"-",1"_"), "and a new Ref as its ItemId")
	Do $$$AssertEquals(@call@("sourceItemId")_"|"_@call@("catalogKey")_"|"_@call@("slots")_"|"_@call@("clientId")_"|"_@call@("fromGuide"), "||||0", "every other field is empty or 0")
	Set mail.Text = $Translate($Justify("", 12000), " ", "t")
	Set mail.Subject = $Translate($Justify("", 1200), " ", "s")
	Do service.OnProcessInput(mail, .output)
	Set call = $Name(^OcuTalonTest("EmailInServiceProbe", ..Number, 2))
	Do $$$AssertEquals($Length(@call@("text"))_"|"_$Length(@call@("subject")), "10000|1000", "a text of 12,000 characters is cut to 10,000 (the simulated mailbox's body size) and a subject to 1,000")
	Do $$$AssertEquals(##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX, 10000, "which is the constant of the simulated mailbox")
	Set other = ..Session("item2")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", other)
	Do service.OnProcessInput(mail, .output)
	Do $$$AssertEquals(^OcuTalonTest("EmailInServiceProbe", ..Number, 3, "sessionRef"), other, "when the mailbox moves to another admin, the next email is that admin's: the owner is read from the row")
}

/// Refusals: nothing is sent.
Method TestServiceRefusals()
{
	Set service = ..Service()
	Do ##class(OcuTalon.Data.Setting).KeyIndexDelete("email.owner")
	Set mail = ##class(OcuTalon.Channel.Email.Mail).%New()
	Set mail.Uidl = "u1"
	Set mail.Subject = "zz s"
	Do $$$AssertStatusNotOK(service.OnProcessInput(mail, .output), "an email with no owner is refused")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", "zznosuchsession0000000")
	Do $$$AssertStatusNotOK(service.OnProcessInput(mail, .output), "an owner with no session row is refused")
	Set owner = ..Session("refusals")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", owner)
	Do $$$AssertStatusNotOK(service.OnProcessInput("text", .output), "an input that is no object is refused")
	Do $$$AssertStatusNotOK(service.OnProcessInput(##class(OcuTalon.Channel.SimMailbox.Mail).%New(), .output), "an input of another class is refused")
	Set mail.Uidl = ""
	Do $$$AssertStatusNotOK(service.OnProcessInput(mail, .output), "an email with no UIDL is refused")
	Do $$$AssertEquals($Get(^OcuTalonTest("EmailInServiceProbe", ..Number), 0), 0, "nothing was sent")
	Set mail.Uidl = "u2"
	Set service.FailSend = 1
	Do $$$AssertStatusNotOK(service.OnProcessInput(mail, .output), "a failed send is an error status")
	Do $$$AssertEquals($Get(^OcuTalonTest("EmailInServiceProbe", ..Number), 0), 1, "after one send")
}

/// The adapter reads the header of the email.
Method TestAdapterCarriesSentRef()
{
	Set adapter = ..Adapter("ref")
	Do ..Mail("u1")
	Do adapter.OnTask()
	Do ..Mail("u2", "a@example.com", "zz s2", "zz b2", , , , "zzRefWhole00000000001"), ..Mail("u3", "a@example.com", "zz s3", "zz b3", , 2000000, , "zzRefHeaders0000000002"), ..Mail("u4")
	Do adapter.OnTask()
	Do $$$AssertEquals(..Delivered(), 3, "three emails are handed on")
	Do $$$AssertEquals($Get(^||OcuTalonEmailInAdapter("delivered", 1, "ref"))_"|"_$Get(^||OcuTalonEmailInAdapter("delivered", 2, "ref"))_"|"_$Get(^||OcuTalonEmailInAdapter("delivered", 3, "ref")), "zzRefWhole00000000001|zzRefHeaders0000000002|", "the Ref of the whole read, the Ref of the headers-only read, and none for an email without the header")
	Do $$$AssertEquals(..Count("Fetch")_"|"_..Count("FetchMessageHeaders"), "2|1", "the second was read as headers only")
}

/// DW-1167, ruling V4: an email that EmailOut sent to the mailbox makes no Item, once.
Method TestServiceSkipsOwnMail()
{
	Set owner = ..Session("echo")
	Set other = ..Session("echoother")
	Do ##class(OcuTalon.Data.Setting).Set("email.owner", owner)
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "zzown@example.com")
	Set sentRef = ..Row(owner, "email", "digest", "")
	Set toolRef = ..Row(owner, "email", "", "")
	Set pendingRef = ..Row(owner, "email", "", "pending")
	Set failedRef = ..Row(owner, "email", "", "failed")
	Set webRef = ..Row(owner, "web", "digest", "")
	Set forged = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set service = ..Service()
	// A sent Ref but a From that is not the own address: an Item, and the use of the Ref is kept.
	Do ..Take(service, "u1", "zzother@example.com", sentRef)
	Do $$$AssertEquals(..Sends(), 1, "a Ref of a sent email from another sender is an Item")
	Do $$$AssertEquals(..Echoed(sentRef), "", "and does not use up the Ref")
	Do ..Take(service, "u1b", "zzown@example.com.evil.net", sentRef)
	Do ..Take(service, "u1c", "Zz Own <zzown@example.org>", sentRef)
	Do $$$AssertEquals(..Sends(), 3, "a sender that only looks like the address is an Item too")
	// All three hold: no Item, the use is taken, the Ref is logged.
	Set before = ..LastLog()
	Do ..Take(service, "u2", "OcuTalon <ZZOWN@Example.com>", sentRef)
	Do $$$AssertEquals(..Sends(), 3, "a Ref of a sent email from the own address (a name and brackets, any case) makes no Item")
	Do $$$AssertTrue(..Echoed(sentRef) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the Ref's use is taken")
	Set texts = ..InfoTexts(before)
	Do $$$AssertEquals($ListToString(texts, "|"), "EmailIn made no item from its own email "_sentRef, "one information line, with the Ref and nothing of the email")
	// The second use.
	Do ..Take(service, "u3", "zzown@example.com", sentRef)
	Do $$$AssertEquals(..Sends(), 4, "the same Ref again is an Item")
	// A tool email's row is a sent email too.
	Do ..Take(service, "u4", "zzown@example.com", toolRef)
	Do $$$AssertEquals(..Sends(), 4, "the Ref of a sent tool email is skipped as well")
	// Everything else is an Item.
	Do ..Take(service, "u5", "zzown@example.com", forged)
	Do $$$AssertEquals(..Sends(), 5, "a Ref that no row has (a forged one) is an Item")
	Do ..Take(service, "u6", "zzown@example.com", "")
	Do $$$AssertEquals(..Sends(), 6, "an email with no Ref is an Item")
	Do ..Take(service, "u7", "zzown@example.com", pendingRef)
	Do ..Take(service, "u8", "zzown@example.com", failedRef)
	Do $$$AssertEquals(..Sends(), 8, "the Ref of a claim whose send did not finish or failed is an Item")
	Do ..Take(service, "u9", "zzown@example.com", webRef)
	Do $$$AssertEquals(..Sends(), 9, "the message id of a row of another channel is an Item")
	Set padded = ..Row(owner, "email", "", "")
	Do ..Take(service, "u10", "zzown@example.com", " "_padded)
	Do $$$AssertEquals(..Sends(), 10, "a Ref with spaces around it is not the Ref")
	Do $$$AssertEquals(..Echoed(padded), "", "and does not use up the Ref it was made from")
	Do ##class(OcuTalon.Data.Setting).Set("email.address", "zzmoved@example.com")
	Do ..Take(service, "u11", "zzown@example.com", ..Row(owner, "email", "digest", ""))
	Do $$$AssertEquals(..Sends(), 11, "when the mailbox address has moved, the old address is not the own one")
}

/// A Delivery row for the owner; the Ref of the row (its ChannelMessageId), kept for the clean-up.
Method Row(owner As %String, channel As %String, kind As %String, fallbackReason As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(owner, channel, ref, "", kind, "", "", "", fallbackReason), "a Delivery row is made")
	Set ..Deliveries = ..Deliveries_$Select(..Deliveries = "": "", 1: ",")_ref
	Quit ref
}

/// The email goes to the service with the Ref in its header.
Method Take(service As OcuTalon.Test.Channel.EmailInServiceProbe, uidl As %String, from As %String, ref As %String) [ Private ]
{
	Set mail = ##class(OcuTalon.Channel.Email.Mail).%New()
	Set mail.Uidl = uidl
	Set mail.Sender = from
	Set mail.Subject = "zz s"
	Set mail.SentRef = ref
	Do $$$AssertStatusOK(service.OnProcessInput(mail, .output), "the email "_uidl_" is accepted")
}

Method Sends() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("EmailInServiceProbe", ..Number))
}

/// The EchoedAt of the sent email Delivery row of the Ref.
ClassMethod Echoed(ref As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT EchoedAt FROM OcuTalon_Data.Delivery WHERE ChannelMessageId = ?", ref)
	Do result.%Next()
	Quit result.%Get("EchoedAt")
}

ClassMethod LastLog() As %Integer [ Private ]
{
	Set last = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do last.%Next()
	Quit +last.%GetData(1)
}

/// The texts of the log rows of EmailIn after the row id start, as a list.
ClassMethod InfoTexts(start As %Integer) As %List [ Private ]
{
	Set texts = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Text [ 'EmailIn' ORDER BY ID", start)
	While result.%Next() {
		Set texts = texts_$ListBuild(result.%GetData(1))
	}
	Quit texts
}

/// --- helpers ---

/// A new adapter for a mailbox of its own (the user name zzmailuser<tag><run>), made like the production makes one: the settings, then OnInit.
/// first 0 leaves the mailbox as the earlier adapter of the tag made it (a restart); deleteSetting is the DeleteMessage setting the adapter starts with.
Method Adapter(tag As %String, first As %Boolean = 1, deleteSetting As %Boolean = 0) As OcuTalon.Test.Channel.EmailInAdapter [ Private ]
{
	Set user = "zzmailuser"_tag_..Number
	Set ^||OcuTalonEmailInAdapter("user") = user
	Set adapter = ##class(OcuTalon.Test.Channel.EmailInAdapter).%New()
	Set adapter.POP3Server = "pop.example.com"
	Set adapter.POP3Port = 995
	Set adapter.Credentials = "OcuTalonMail"
	Set adapter.DeleteMessage = deleteSetting
	Do $$$AssertStatusOK(adapter.OnInit(), "the adapter starts")
	Set mailbox = ##class(OcuTalon.Data.MailSeen).IdentityOf("pop.example.com", 995, user)
	If first {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.MailSeen WHERE Mailbox = ?", mailbox)
		Set ..Mailboxes = ..Mailboxes_$Select(..Mailboxes = "": "", 1: ",")_mailbox
	}
	Quit adapter
}

/// Adds an email to the stand-in's mailbox.
ClassMethod Mail(uidl As %String, from As %String = "a@example.com", subject As %String = "zz subject", text As %String = "zz body", html As %String = "", size As %Integer = 0, parts As %Boolean = 0, ref As %String = "")
{
	Do ##class(OcuTalon.Test.Channel.EmailInPop3).Add(uidl, from, subject, text, html, size, parts, ref)
}

/// The number of emails handed on since the last Kill.
ClassMethod Delivered() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonEmailInAdapter("delivered"))
}

/// The nth email handed on, as $ListBuild(uidl, sender, subject, text).
ClassMethod Handed(n As %Integer) As %List [ Private ]
{
	Quit $Get(^||OcuTalonEmailInAdapter("delivered", n))
}

/// The number of calls of a method of the stand-in.
ClassMethod Count(name As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Channel.EmailInPop3).Count(name)
}

/// The rows of the adapter's mailbox as "uidl=baseline,...", the marker first and the rest in the order of their Uidl as recorded.
Method SeenRows(adapter As OcuTalon.Test.Channel.EmailInAdapter) As %String [ Private ]
{
	Set mailbox = ##class(OcuTalon.Data.MailSeen).IdentityOf(adapter.POP3Server, adapter.POP3Port, ^||OcuTalonEmailInAdapter("user"))
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Uidl, Baseline FROM OcuTalon_Data.MailSeen WHERE Mailbox = ? ORDER BY ID", mailbox)
	Set out = ""
	While result.%Next() {
		Set out = out_$Select(out = "": "", 1: ",")_result.%GetData(1)_"="_+result.%GetData(2)
	}
	Quit out
}

/// The emailPoll mark as an object.
ClassMethod Mark() As %DynamicObject [ Private ]
{
	Quit {}.%FromJSON(##class(OcuTalon.Data.StatusMark).Get("emailPoll"))
}

/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzemailin"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the service whose sends are recorded.
Method Service() As OcuTalon.Test.Channel.EmailInServiceProbe [ Private ]
{
	Set service = ##class(Ens.Host).GetShadowInstance("class||"_..#SERVICE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the service is made")
	Set service.RunNumber = ..Number
	Quit service
}

}
