/// Tests of how the Digest item composes and records one digest (Story 17.6; AD-1, AD-3, AD-18, AD-28, AD-30, AD-32). Safe on a slot: no production runs, the
/// tests handle a Compose with a shadow instance of OcuTalon.Test.Digest.ProcessProbe, which records the Notification and the summary request instead of
/// sending them, and feeds the rows of the checks (ProcessProbe Feed). The needs-you list, the cost and the saved items are the product's own, read from
/// fixture rows. The window of a Compose ends at 2030-06-03 09:00 in America/New_York, the process zone of the class. The digest's parts and lines are
/// rendered through Catalog.Render for the channel telegram, so that a slot of the wrong type fails the test.
///   - TestPartOrder: with a failed row, a passed row, an unhandled tell-now Decision and nothing saved, the parts are the greeting, the vital signs, what was
///     checked, the key of Render with whatFailed, what needs the user, nothing saved and the cost, in that order, with the lines and rows of the check
///     rows, and every part renders;
///   - TestQuietDay: everything passed and nothing needs the user: the quiet parts, checks.allPassed as the CatalogKey, and at most 150 words;
///   - TestNothingWatched, TestVitalsNotAll: digest.nothingWatched alone, with checks.nothingWatched; the vital signs that did not pass are named;
///   - TestGreeting: the greeting of the compose hour in the instance zone, by the three bands;
///   - TestCost: the cost sums the session's and instance's Usage of the previous local day and never eval's, another session's, today's or the earlier
///     days', at the edges of the day, and renders as "Yesterday's cost: $0.04.";
///   - TestSavedSummary, TestSummaryCut: items in the window make one summary request (untrusted, fresh, no seed, owner the session, channel system, the
///     summaries quoted as data) and the digest waits for the answer, which is cut to 240 characters;
///   - TestSummaryFallback: a fallback, an error, an unusable answer, an empty text and a send that fails each give digest.savedNoSummary with the reason
///     (an unknown one unusable), one information line, and the Decision's Ref in the digest, and the digest still goes;
///   - TestNothingSaved: no item in the window: no request to Decide, and digest.savedNone; items outside the window do not count;
///   - TestSentRow: the Sent row holds every field of the digest, and AllClear is 1 only for checks.allPassed;
///   - TestAllClearNeedsVitalsAndNothingOpen: AllClear is 1 only when the five vital signs passed and nothing needs the user as well: a failed vital sign
///     or an open needs-you entry with every checked entry passed gives 0;
///   - TestItemsAreInTheProduction: every item that Digest sends to is an item of OcuTalon.Production;
///   - TestNeedsYouParts: the parts for one entry, several and overflowing entries;
///   - TestFailurePath: an error of the rows or of the send of the Notification is returned, and no Sent row follows;
///   - The digest routing (Story 17.6, Story 21.7): Digest hands every composed digest to Notify, once, whatever digest.channels names. The channels
///     available to the session are set on the probe (OwnChannels) and digest.channels is taken out of the way before each test (so that a row left by
///     another test cannot narrow the channels) and put back after it. TestRouteOwn: with no value saved, or one that names every available channel, the
///     digest goes to Notify alone, its Sent row lists every available channel and misses none, Digest writes no routing row, and a later tick sends
///     nothing more; TestRouteSubset: a saved subset (email included) still goes to Notify alone, and the Sent row lists the channels of the subset that are
///     available, in the order of Notify's rule; TestRouteNoneReachable: a saved value that names no available channel sends nothing, ends the Compose with an
///     error status holding the fixed diagnostic, writes no Sent row and makes no model request, also when the value changes while the summary is awaited;
///     TestRouteForeign: a channel that is not available, an unknown name and the name of an item add no destination;
///     TestProductChannels: the product's own reading of the channels (web, phone with demo mode, telegram when paired);
///   - TestWebDigestUnchanged, TestPhoneDigestUnchanged, TestTelegramDigestUnchanged (Story 21.7, ruling O1): the digest that a channel gets is the text it got
///     before Digest handed every digest to Notify, byte for byte: for a fixed requested digest of a session with only that channel named, Digest sends one
///     Notification to Notify at compose time (the same moment as before, with no direct send to the channel's item), Notify's rule reaches the channel's item
///     alone, and the text of the channel (the web chat's and the simulated phone's delivered by the real operation, Telegram's by the helper that
///     TelegramOut renders with) is the literal text written out here;
///   - TestChannelsMatchNotify: the channels that Digest records equal the channels that Notify's rule for a digest reaches, evaluated on the router for demo
///     mode on and off, Telegram included or not, a session paired or not and several values of digest.channels, and demo mode and the Telegram setting are put
///     back; TestNotifyFailure: a send to Notify that fails or throws ends the Compose with an error status, writes no Sent row, and a later tick sends nothing
///     for it (the delivery of each channel is recorded by its own item).
Class OcuTalon.Test.Digest.Compose Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

Parameter CHANNELS = "digest.channels";

Parameter NOCHANNEL = "No digest channel is reachable: none of the saved digest channels is one of this session's channels.";

Parameter ZONE = "America/New_York";

/// The text of the fixed digest of TestWebDigestUnchanged, TestPhoneDigestUnchanged and TestTelegramDigestUnchanged, which each channel delivers (the web chat,
/// the simulated phone and Telegram render the same pieces the same way) exactly as it did before Digest handed every digest to Notify.
Parameter FIXEDDIGEST = {"Good morning."_$Char(10)_"Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%."_$Char(10)_"I'm not watching any productions yet, so this digest covers the vital signs only. Ask me to watch one."_$Char(10)_"Passed: IRIS instance (at Jun 1, 2030 at 08:00)."_$Char(10)_"Passed: database space (at Jun 1, 2030 at 08:00)."_$Char(10)_"Passed: journal space (at Jun 1, 2030 at 08:00)."_$Char(10)_"Passed: license use (at Jun 1, 2030 at 08:00)."_$Char(10)_"Passed: system log (at Jun 1, 2030 at 08:00)."_$Char(10)_"Nothing was saved for later."_$Char(10)_"Yesterday's cost: $0.00."};

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The ids of the Handled rows made, comma-separated.
Property Handled As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// 1 once a test has saved digest.channels, and the row as it was: $ListBuild(found, value).
Property ChannelsKept As %Boolean [ InitialExpression = 0 ];

Property ChannelsWas As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Clean", "")
	Do ..SaveChannels("")
	Set ..LogMark = ..LastLog()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $ClassMethod(..#PROBE, "Clean", ..Sessions)
	Do ..PutChannelsBack()
	For i = 1:1:$Length(..Handled, ",") {
		If $Piece(..Handled, ",", i) '= "" Do ##class(OcuTalon.Data.Handled).%DeleteId($Piece(..Handled, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = "", ..Sessions = "", ..Handled = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Quit sc
}

/// Makes the digest.channels row the value ("" for no row); the first call of a test notes the row as it was.
Method SaveChannels(value As %String)
{
	Set key = ..#CHANNELS
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If '..ChannelsKept {
		Set ..ChannelsKept = 1
		Set ..ChannelsWas = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	}
	If value = "" {
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	} Else {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(key, value), "digest.channels is saved as '"_value_"'")
	}
}

/// Puts the digest.channels row back as the test found it.
Method PutChannelsBack()
{
	If '..ChannelsKept Quit
	Set key = ..#CHANNELS
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If $List(..ChannelsWas, 1) {
		Do ##class(OcuTalon.Data.Setting).Set(key, $List(..ChannelsWas, 2))
	} ElseIf $IsObject(row) {
		Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
	}
	Kill ^||OcuTalon.Setting(key)
	Set ..ChannelsKept = 0, ..ChannelsWas = ""
}

/// The items that the probe recorded the Notifications for, in order, comma-separated.
Method Items() As %String
{
	Set items = ""
	For n = 1:1:$ClassMethod(..#PROBE, "Count", "notice") {
		Set items = items_$Select(items = "": "", 1: ",")_$List($ClassMethod(..#PROBE, "Record", "notice", n), 6)
	}
	Quit items
}

/// Handles a requested Compose of the session on a host whose available channels are own and whose digest.channels is saved (empty for no row); the status.
/// The probe is reset first, and number tells the keys of the Composes apart.
Method Route(session As %String, own As %String, saved As %String, number As %Integer, Output host As OcuTalon.Test.Digest.ProcessProbe) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Do ..SaveChannels(saved)
	Set host = ..Host()
	Set host.OwnChannels = own
	Set host.Only = session
	Quit ..Handle(..Compose(session, "requested", , session_":route"_number), host)
}

/// The id of the newest row of the event log.
ClassMethod LastLog() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

Method Keep(ref As %String)
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzcompose")
	Do ..Keep(ref)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

Method Utc(local As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(local)
}

Method Host() As OcuTalon.Test.Digest.ProcessProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set host.%SessionId = $Parameter(..#PROBE, "TRACESESSION")
	Quit host
}

/// A Compose for the session whose window ends at the local time and starts a day earlier.
Method Compose(session As %String, kind As %String = "scheduled", endLocal As %String = "2030-06-03T09:00:00", key As %String = "") As OcuTalon.Digest.Msg.Compose
{
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = kind
	Set compose.DueAt = $Select(kind = "scheduled": ..Utc("2030-06-03T08:00:00"), 1: "")
	Set compose.IdempotencyKey = key
	Set compose.WindowEnd = ..Utc(endLocal)
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowEnd, -86400)
	Quit compose
}

/// Hands the Compose to the host and returns the status of the handling.
Method Handle(compose As OcuTalon.Digest.Msg.Compose, host As OcuTalon.Test.Digest.ProcessProbe) As %Status
{
	Kill response
	Quit host.OnRequest(compose, .response)
}

/// The Notification n that the probe recorded, as {session, kind, catalogKey, decisionRef, slots}; "" when there is none.
Method Notice(n As %Integer = 1) As %DynamicObject
{
	Set record = $ClassMethod(..#PROBE, "Record", "notice", n)
	If record = "" Quit ""
	Quit {"session": ($List(record, 1)), "kind": ($List(record, 2)), "catalogKey": ($List(record, 3)), "decisionRef": ($List(record, 4)), "slots": ({}.%FromJSON($List(record, 5)))}
}

/// The keys of the parts, comma-separated.
Method Keys(slots As %DynamicObject) As %String
{
	Set keys = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_part.key
	}
	Quit keys
}

/// The part with the key, or "".
Method Part(slots As %DynamicObject, key As %String) As %DynamicObject
{
	Set found = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = key {
			Set found = part
			Quit
		}
	}
	Quit found
}

/// The Telegram rendering of every part and line, one on each line; an element that does not render fails the test.
Method Render(slots As %DynamicObject) As %String
{
	Set text = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		Set rendered = ##class(OcuTalon.Msg.Catalog).Render(part.key, part.slots, "telegram", .sc)
		Do $$$AssertStatusOK(sc, part.key_" renders")
		Set text = text_$Select(text = "": "", 1: $Char(10))_rendered
	}
	Set iterator = slots.lines.%GetIterator()
	While iterator.%GetNext(, .line) {
		Set rendered = ##class(OcuTalon.Msg.Catalog).Render(line.key, line.slots, "telegram", .sc)
		Do $$$AssertStatusOK(sc, line.key_" renders")
		Set text = text_$Char(10)_rendered
	}
	Quit text
}

/// The number of words of a text.
ClassMethod Words(text As %String) As %Integer
{
	Set text = $Translate(text, $Char(10, 13, 9), "   ")
	Set count = 0
	For i = 1:1:$Length(text, " ") {
		If $Piece(text, " ", i) '= "" Set count = count + 1
	}
	Quit count
}

/// A decide Decision of the session recorded minutesAgo minutes before the end of the window.
Method Decision(session As %String, minutesAgo As %Integer, summary As %String, outcome As %String = "tellnow") As %String
{
	Set at = ##class(OcuTalon.Data.Time).AddSeconds(..Utc("2030-06-03T09:00:00"), -60 * minutesAgo)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", at, {"Summary": (summary), "Outcome": (outcome)})
	Do ..Keep(ref)
	Quit ref
}

/// An item saved for later by the session at the local time.
Method Item(session As %String, local As %String) As %String
{
	Set itemId = $ClassMethod("OcuTalon.Test.Digest.Store", "NewRef")
	Do $ClassMethod("OcuTalon.Test.Digest.Store", "NewRow", session, itemId, ..Utc(local), .sc)
	Do $$$AssertStatusOK(sc, "an item is saved")
	Quit itemId
}

/// The number of event-log lines since the test began whose text holds the fragment.
Method Logged(fragment As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Text LIKE ?", ..LogMark, "%"_fragment_"%")
	Do rs.%Next()
	Quit rs.%GetData(1)
}

Method SentRows(session As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The newest Sent row of the session, as an object of its fields.
Method Sent(session As %String) As %DynamicObject
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Ref, SessionRef, ItemId, DecisionRef, Kind, DueAt, WindowStart, SentAt, CatalogKey, Slots, AllClear, IdempotencyKey, Channels, Failed, Attempts FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", session)
	If 'rs.%Next() Quit ""
	Set row = {}
	For field = "Ref", "SessionRef", "ItemId", "DecisionRef", "Kind", "DueAt", "WindowStart", "SentAt", "CatalogKey", "Slots", "AllClear", "IdempotencyKey", "Channels", "Failed", "Attempts" {
		Do row.%Set(field, rs.%Get(field))
	}
	Quit row
}

Method Watched(result As %String, entry As %String, finding As %String = "") As %DynamicObject
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": "2030-06-03T12:00:00Z"}
}

Method TestPartOrder()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "Orders production")), (..Watched("failed", "Billing source", "5 messages queued"))])
	Do ..Decision(session, 30, "Partner support: invoice question")
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "one Notification is sent")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(notice.session_"|"_notice.kind, session_"|digest", "for the session, of the kind digest")
	Set slots = notice.slots
	Do $$$AssertEquals(..Keys(slots), "digest.greetingMorning,digest.healthy,digest.checked,checks.notEverythingRestPassed,digest.needsYou,digest.savedNone,digest.cost", "the parts are in the order of the contract")
	Do $$$AssertEquals(notice.catalogKey, "checks.notEverythingRestPassed", "the CatalogKey is Render's key over the watched rows")
	Do $$$AssertEquals(..Part(slots, "digest.checked").slots.checked, "the Orders production and the Billing source", "what was checked names every watched entry")
	Do $$$AssertEquals(..Part(slots, "checks.notEverythingRestPassed").slots.%ToJSON(), "{""whatFailed"":""Billing source""}", "Render's key carries the entry that did not pass")
	Do $$$AssertEquals(..Part(slots, "digest.needsYou").slots.count, 2, "two things need the user")
	Do $$$AssertEquals(..Part(slots, "digest.needsYou").slots.what, "Billing source: 5 messages queued; Partner support: invoice question", "the failed row first, then the Decision")
	Do $$$AssertEquals(slots.lines.%Size(), 7, "there is one line for each of the seven rows")
	Do $$$AssertEquals(slots.rows.%Size(), 7, "and the seven rows")
	Do $$$AssertEquals(slots.lines.%Get(6).key_"|"_slots.rows.%Get(6).result, "digest.failed|failed", "the lines and rows are those of the check rows")
	Set text = ..Render(slots)
	Do $$$AssertTrue(text [ "Good morning.", "the greeting renders")
	Do $$$AssertTrue(text [ "Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.", "the vital signs render")
	Do $$$AssertTrue(text [ "I checked the Orders production and the Billing source.", "what was checked renders")
	Do $$$AssertTrue(text [ "Not everything: Billing source. Everything else I checked passed.", "and so does the reserved sentence")
	Do $$$AssertTrue(text [ "2 things need you: Billing source: 5 messages queued; Partner support: invoice question.", "and what needs the user")
	Do $$$AssertTrue(text [ "Failed: Billing source (5 messages queued, ", "and the coverage lines")
}

Method TestQuietDay()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "Orders production"))])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.checkedQuiet,checks.allPassed,digest.savedNone,digest.cost", "a quiet day has no needs-you part")
	Do $$$AssertEquals(notice.catalogKey, "checks.allPassed", "the CatalogKey is the all-clear")
	Set text = ..Render(notice.slots)
	Do $$$AssertTrue(text [ "I checked the Orders production (all running, no errors, no backlog).", "it says what was checked")
	Do $$$AssertTrue(text [ "Everything I checked passed.", "and the reserved sentence")
	Do $$$AssertTrue(..Words(text) <= 150, "a quiet digest has at most 150 words: "_..Words(text))
}

Method TestNothingWatched()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.nothingWatched,digest.savedNone,digest.cost", "with nothing watched the checked part is digest.nothingWatched alone")
	Do $$$AssertEquals(notice.catalogKey, "checks.nothingWatched", "and the CatalogKey is never an all-clear")
	Do $$$AssertEquals(..Sent(session).AllClear, 0, "the Sent row is no all-clear")
	Do ..Render(notice.slots)
}

Method TestVitalsNotAll()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set row = vitals.rows.%Get(1)
	Set row.result = "failed"
	Set row.finding = "OCUTALON_DATA 8% free"
	Set row = vitals.rows.%Get(2)
	Set row.result = "not_checked"
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "Orders production"))], vitals)
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.vitalsNotAll,digest.checkedQuiet,checks.allPassed,digest.savedNone,digest.cost", "failing vital signs give digest.vitalsNotAll")
	Do $$$AssertEquals(..Part(notice.slots, "digest.vitalsNotAll").slots.whatFailed, "database space and journal space", "which names them")
	Do $$$AssertTrue(..Render(notice.slots) [ "Not every vital sign passed: database space and journal space.", "and renders")
}

Method TestGreeting()
{
	For case = "2030-06-03T00:00:00|digest.greetingMorning", "2030-06-03T11:59:59|digest.greetingMorning", "2030-06-03T12:00:00|digest.greetingAfternoon", "2030-06-03T17:59:59|digest.greetingAfternoon", "2030-06-03T18:00:00|digest.greetingEvening", "2030-06-03T23:59:59|digest.greetingEvening" {
		Set local = $Piece(case, "|", 1)
		Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "Greeting", ..Utc(local)), $Piece(case, "|", 2), local_" in the instance zone")
	}
}

Method TestCost()
{
	Set session = ..Session()
	Set other = ..Session()
	For case = "0.011|"_session_"|2030-06-02T10:00:00", "0.001|"_session_"|2030-06-02T00:00:00", "0.03|instance|2030-06-02T23:59:59", "9|eval|2030-06-02T10:00:00", "1|"_other_"|2030-06-02T10:00:00", "0.5|"_session_"|2030-06-03T01:00:00", "5|"_session_"|2030-06-03T00:00:00", "7|"_session_"|2030-06-01T23:59:59" {
		Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref, $Piece(case, "|", 2), {"CostUSD": ($Piece(case, "|", 1)), "RecordedAt": (..Utc($Piece(case, "|", 3)))})
		Do ..Keep(ref)
	}
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set cost = ..Part(..Notice(1).slots, "digest.cost")
	Do $$$AssertEquals(cost.slots.%GetTypeOf("cost"), "number", "the cost is a number")
	Do $$$AssertEquals(+cost.slots.cost, 0.042, "it sums the session's and instance's cost of yesterday, midnight to midnight, and never eval's or another session's")
	Do $$$AssertTrue(..Render(..Notice(1).slots) [ "Yesterday's cost: $0.04.", "and renders with two decimals")
	Set sc = $$$OK
	Do $$$AssertEquals(+##class(OcuTalon.Digest.Cost).Yesterday(session, ..Utc("2030-06-03T09:00:00"), .sc), 0.042, "Cost.Yesterday gives the same sum")
	Do $$$AssertEquals(+##class(OcuTalon.Digest.Cost).Yesterday(session, ..Utc("2030-06-05T09:00:00"), .sc), 0, "and 0 for a day with nothing spent")
	Do ##class(OcuTalon.Digest.Cost).Yesterday(session, "not a time", .sc)
	Do $$$AssertStatusNotOK(sc, "and an error for a time it cannot read")
}

Method TestSavedSummary()
{
	Set session = ..Session()
	Set a = ..Item(session, "2030-06-03T06:00:00")
	Set b = ..Item(session, "2030-06-03T07:00:00")
	Set c = ..Item(session, "2030-06-03T09:00:00")
	Do ..Item(session, "2030-06-02T08:59:59")
	Do ..Item(session, "2030-06-03T09:00:01")
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "Orders production"))])
	Set host = ..Host()
	Set compose = ..Compose(session)
	Do $$$AssertStatusOK(..Handle(compose, host), "the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 1, "exactly one request goes to Decide")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "and the digest waits for the answer")
	Set request = $ClassMethod(..#PROBE, "Summary", 1)
	Do $$$AssertEquals(request.kind_"|"_request.provenance_"|"_request.sessionMode_"|"_request.seedText_"|"_request.ownerRef_"|"_request.channel, "turn|untrusted|fresh||"_session_"|system", "it is an untrusted, fresh turn with no seed, for the session, on the channel system")
	Do $$$AssertEquals($Length(request.itemId), 22, "its ItemId is a new reference")
	Do $$$AssertEquals(request.systemNote, ##class(OcuTalon.Digest.Process).#SYSTEMNOTE, "it carries the fixed note")
	Do $$$AssertTrue(request.input [ "Subject: Saved for later", "its input names the subject")
	Do $$$AssertTrue((request.input [ ("> Summary "_a)) && (request.input [ ("> Summary "_b)) && (request.input [ ("> Summary "_c)), "and quotes the three summaries of the window as data")
	Do $$$AssertEquals($Length(request.input, "> Summary "), 4, "and only those")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "Two newsletters and a shipping notice."
	Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set reply.DecisionRef = decisionRef
	Kill response
	Do $$$AssertStatusOK(host.OnResponse(compose, .response, "", reply, "summary"), "the answer is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "then one Notification is sent")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(notice.decisionRef, decisionRef, "with the Decision of the request")
	Set saved = ..Part(notice.slots, "digest.saved")
	Do $$$AssertEquals(saved.slots.%ToJSON(), "{""count"":3,""summary"":""Two newsletters and a shipping notice.""}", "and digest.saved with the count and the summary")
	Do $$$AssertTrue(..Render(notice.slots) [ "Saved for later (3): Two newsletters and a shipping notice.", "which renders")
	Set row = ..Sent(session)
	Do $$$AssertEquals(row.ItemId_"|"_row.DecisionRef, request.itemId_"|"_decisionRef, "the Sent row records the request's ItemId and the Decision")
}

Method TestSummaryCut()
{
	Set session = ..Session()
	Do ..Item(session, "2030-06-03T06:00:00")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Set compose = ..Compose(session)
	Do $$$AssertStatusOK(..Handle(compose, host), "the Compose is handled")
	Set text = ""
	For i = 1:1:30 {
		Set text = text_"abcdefghi"_$Select(i < 30: " ", 1: "")
	}
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "  "_text_"  "
	Do $$$AssertStatusOK(host.OnResponse(compose, .response, "", reply, "summary"), "the answer is handled")
	Set summary = ..Part(..Notice(1).slots, "digest.saved").slots.summary
	Do $$$AssertEquals($Length(summary), 240, "a long summary is cut to 240 characters")
	Do $$$AssertEquals(summary, $Extract($ZStrip(text, "<>W"), 1, 240), "its first 240")
}

Method TestSummaryFallback()
{
	Set session = ..Session()
	Do ..Item(session, "2030-06-03T06:00:00")
	Do ..Item(session, "2030-06-03T07:00:00")
	Do ..Item(session, "2030-06-03T08:00:00")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set n = 0
	For case = "fallback:timeout|timeout", "fallback:weird|unusable", "error|unusable", "string|unusable", "empty|empty", "send|unusable" {
		Set kind = $Piece($Piece(case, "|", 1), ":", 1)
		Set reason = $Piece($Piece(case, "|", 1), ":", 2)
		Set expected = $Piece(case, "|", 2)
		Set host = ..Host()
		Set compose = ..Compose(session)
		Set compose.DueAt = ##class(OcuTalon.Data.Time).AddSeconds(compose.DueAt, n)
		Set decisionRef = ""
		If kind = "send" Set host.FailSummary = 1
		Do $$$AssertStatusOK(..Handle(compose, host), kind_": the Compose is handled")
		Kill response
		If kind = "fallback" {
			Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
			Set reply.Fallback = 1
			Set reply.FallbackReason = reason
			Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set reply.DecisionRef = decisionRef
			Do host.OnResponse(compose, .response, "", reply, "summary")
		} ElseIf kind = "error" {
			Do $$$AssertStatusOK(host.OnError(compose, .response, "", $SYSTEM.Status.Error(5001, "zz the request failed"), "summary"), "error: OnError returns OK, so that the framework runs OnResponse")
			Do host.OnResponse(compose, .response, "", "", "summary")
		} ElseIf kind = "string" {
			Do host.OnResponse(compose, .response, "", ##class(Ens.StringResponse).%New("x"), "summary")
		} ElseIf kind = "empty" {
			Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
			Set reply.Text = "   "
			Do host.OnResponse(compose, .response, "", reply, "summary")
		}
		Set n = n + 1
		Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), n, kind_": the digest still goes")
		Set notice = ..Notice(n)
		Do $$$AssertEquals(..Part(notice.slots, "digest.savedNoSummary").slots.%ToJSON(), "{""count"":3,""fallbackReason"":"""_expected_"""}", kind_": digest.savedNoSummary with the reason "_expected)
		Do $$$AssertEquals(notice.decisionRef, decisionRef, kind_": the digest carries the Decision of the request")
		If kind = "send" Do $$$AssertEquals(..Sent(session).ItemId, "", kind_": a request that was never sent leaves the Sent row no ItemId")
	}
	Set prefix = "The saved-for-later summary of a digest fell back: "
	Do $$$AssertEquals(..Logged(prefix_"timeout")_"|"_..Logged(prefix_"empty")_"|"_..Logged(prefix_"unusable"), "1|1|4", "each fallback is logged once, with its reason")
	Do $$$AssertTrue(..Render(..Notice(1).slots) [ "Saved for later (3): I couldn't summarize them this time (the model didn't answer within", "and the line renders")
}

Method TestNothingSaved()
{
	Set session = ..Session()
	Do ..Item(session, "2030-06-02T08:59:59")
	Do ..Item(session, "2030-06-03T09:00:01")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 0, "no item in the window: no request to Decide")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "and the digest goes at once")
	Do $$$AssertEquals(..Part(..Notice(1).slots, "digest.savedNone").slots.%ToJSON(), "{}", "with digest.savedNone")
}

Method TestSentRow()
{
	Set session = ..Session()
	Set number = 0
	For case = "checks.allPassed|1", "checks.notEverything|0", "checks.nothingWatched|0" {
		Set number = number + 1
		Set key = $Piece(case, "|", 1)
		Do $ClassMethod(..#PROBE, "Reset")
		Do $ClassMethod(..#PROBE, "Feed", $Case(key, "checks.allPassed": [(..Watched("passed", "Orders production"))], "checks.notEverything": [(..Watched("failed", "Orders production", "3 items in error"))], : []))
		Set host = ..Host()
		Set compose = ..Compose(session, "requested", , session_":"_number)
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK(..Handle(compose, host), key_": the Compose is handled")
		Set after = ##class(OcuTalon.Data.Time).NowUtc()
		Set row = ..Sent(session)
		Set notice = ..Notice(1)
		Do $$$AssertEquals($Length(row.Ref), 22, key_": the row has a reference")
		Do $$$AssertEquals(row.SessionRef_"|"_row.ItemId_"|"_row.DecisionRef_"|"_row.Kind_"|"_row.DueAt_"|"_row.IdempotencyKey, session_"|||requested||"_session_":"_number, key_": session, no item, no Decision, kind, an empty DueAt and the key")
		Do $$$AssertEquals(row.WindowStart, compose.WindowStart, key_": the window starts where the Compose says")
		Do $$$AssertEquals($ListToString($ClassMethod(..#PROBE, "Record", "rows", 1), "|"), compose.WindowStart_"|"_compose.WindowEnd, key_": the coverage rows are built over the Compose's window")
		Do $$$AssertTrue((row.SentAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z") && '(before ] row.SentAt) && '(row.SentAt ] after), key_": SentAt is UTC between the clock before and after: "_row.SentAt)
		Do $$$AssertEquals(row.CatalogKey_"|"_row.AllClear, key_"|"_$Piece(case, "|", 2), key_": the CatalogKey and AllClear")
		Do $$$AssertEquals(row.Slots, {"parts": (notice.slots.parts), "lines": (notice.slots.lines), "rows": (notice.slots.rows)}.%ToJSON(), key_": the Slots are the Notification's")
	}
}

Method TestAllClearNeedsVitalsAndNothingOpen()
{
	Set session = ..Session()
	Set number = 0
	For case = "every check passed, nothing open|1", "a vital sign failed|0", "an entry needs the user|0" {
		Set number = number + 1
		Set why = $Piece(case, "|", 1)
		Do $ClassMethod(..#PROBE, "Reset")
		Set vitals = $ClassMethod(..#PROBE, "Healthy")
		If number = 2 {
			Set vital = vitals.rows.%Get(1)
			Set vital.result = "failed"
			Set vital.finding = "OCUTALON_DATA 8% free"
		}
		If number = 3 Do ..Decision(session, 10, "Partner support: invoice question")
		Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "Orders production"))], vitals)
		Set host = ..Host()
		Do $$$AssertStatusOK(..Handle(..Compose(session, "requested", , session_":clear"_number), host), why_": the Compose is handled")
		Set row = ..Sent(session)
		Do $$$AssertEquals(row.CatalogKey_"|"_row.AllClear, "checks.allPassed|"_$Piece(case, "|", 2), why_": the CatalogKey is the all-clear of the watched entries, and AllClear is "_$Piece(case, "|", 2))
	}
}

Method TestItemsAreInTheProduction()
{
	Set production = ##class(Ens.Config.Production).%OpenId("OcuTalon.Production")
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	For i = 1:1:production.Items.Count() {
		Set present(production.Items.GetAt(i).Name) = ""
	}
	Set class = "OcuTalon.Digest.Process"
	Set names = $Parameter(class, "SELF")_","_$Parameter(class, "DECIDE")_","_$Parameter(class, "NOTIFY")
	For i = 1:1:$Length(names, ",") {
		Set name = $Piece(names, ",", i)
		Do $$$AssertTrue($Data(present(name)) > 0, name_" is an item of OcuTalon.Production")
	}
}

Method TestNeedsYouParts()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [])
	Do ..Decision(session, 10, "Partner support: invoice question")
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "one entry: the Compose is handled")
	Set slots = ..Notice(1).slots
	Do $$$AssertEquals(..Keys(slots), "digest.greetingMorning,digest.healthy,digest.nothingWatched,digest.needsYouOne,digest.savedNone,digest.cost", "one entry is digest.needsYouOne")
	Do $$$AssertEquals(..Part(slots, "digest.needsYouOne").slots.%ToJSON(), "{""what"":""Partner support: invoice question""}", "with its name")
	Do $ClassMethod(..#PROBE, "Reset")
	Set session = ..Session()
	For i = 1:1:200 {
		Do ..Decision(session, 600 - i, "Mail "_i)
	}
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "200 entries: the Compose is handled")
	Set slots = ..Notice(1).slots
	Do $$$AssertEquals(..Keys(slots), "digest.greetingMorning,digest.healthy,digest.nothingWatched,digest.needsYou,digest.needsYouMore,digest.savedNone,digest.cost", "overflow adds digest.needsYouMore after digest.needsYou")
	Set needs = ..Part(slots, "digest.needsYou")
	Do $$$AssertEquals(needs.slots.count, 200, "count is the total")
	Do $$$AssertEquals(needs.slots.what, "Mail 200; Mail 199; Mail 198; Mail 197; Mail 196", "the five newest are named, newest first")
	Do $$$AssertEquals(..Part(slots, "digest.needsYouMore").slots.%ToJSON(), "{""n"":195}", "and the rest are counted")
	Do $$$AssertTrue(..Render(slots) [ "And 195 more on the OcuTalon page.", "which renders")
}

Method TestRouteOwn()
{
	Set session = ..Session()
	Set number = 0
	For case = "web,phone,telegram||no value saved, all three own", "web,phone||no value saved, two own", "web||no value saved, one own", "web|web,phone,telegram|the default value names every channel", "web,telegram||no value saved, web and telegram own", "web,phone,telegram|telegram,phone,web|every own channel named in another order", "web,telegram|web,phone,telegram,email|every own channel named, and another name" {
		Set number = number + 1
		Set own = $Piece(case, "|", 1), saved = $Piece(case, "|", 2), why = $Piece(case, "|", 3)
		Do $$$AssertStatusOK(..Route(session, own, saved, number, .host), why_": the Compose is handled")
		Do $$$AssertEquals(..Items(), "Notify", why_": the digest goes to Notify alone, whose route reaches the session's own channels "_own)
		Set row = ..Sent(session)
		Do $$$AssertEquals(row.Channels_"|"_row.Failed_"|"_row.Attempts, own_"||0", why_": the Sent row says the digest went to every own channel and missed none")
		Do $$$AssertEquals($ClassMethod(..#PROBE, "RouteRows").%Size(), 0, why_": Digest writes no routing row, because Notify does")
		Do ..Retick(host)
		Do $$$AssertEquals(..Items(), "Notify", why_": a later tick sends nothing more")
	}
}

Method TestRouteSubset()
{
	Set session = ..Session()
	Set number = 0
	For case = "web,phone,telegram|web,telegram|web,telegram", "web,phone,telegram|telegram,web|web,telegram", "web,phone,telegram|phone|phone", "web,phone,telegram|web|web", "web,phone|web|web", "web,telegram|telegram|telegram", "web,phone,telegram|Phone, Telegram|phone,telegram", "web,email|email|email", "web,phone,telegram,email|web,email|web,email", "web,phone,telegram,email|email,telegram|telegram,email" {
		Set number = number + 1
		Set own = $Piece(case, "|", 1), saved = $Piece(case, "|", 2), expected = $Piece(case, "|", 3)
		Do $$$AssertStatusOK(..Route(session, own, saved, number), "available "_own_", saved '"_saved_"': the Compose is handled")
		Do $$$AssertEquals(..Items(), "Notify", "available "_own_", saved '"_saved_"': the digest goes to Notify alone")
		Set row = ..Sent(session)
		Do $$$AssertEquals(row.Channels_"|"_row.Failed, expected_"|", "available "_own_", saved '"_saved_"': the Sent row lists "_expected_" and misses none")
	}
	Do $$$AssertEquals(..SentRows(session), 10, "one Sent row for each digest")
}

/// Asserts that the status is the error of a digest that no channel is reachable for, with its diagnostic.
Method AssertNoChannel(sc As %Status, label As %String)
{
	Do $$$AssertStatusNotOK(sc, label_": the Compose ends with an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ..#NOCHANNEL, label_": which holds the diagnostic: "_$SYSTEM.Status.GetErrorText(sc))
}

Method TestRouteNoneReachable()
{
	Set session = ..Session()
	Do $$$AssertEquals($Parameter("OcuTalon.Digest.Process", "MESSAGENOCHANNEL"), ..#NOCHANNEL, "the diagnostic is the ruled text, byte for byte")
	Do ..Item(session, "2030-06-03T07:00:00")
	Set sc = ..Route(session, "web", "telegram", 1)
	Do $$$AssertStatusNotOK(sc, "own web, saved telegram: the Compose ends with an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ..#NOCHANNEL, "which holds the diagnostic: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "nothing is sent")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 0, "and no model request is made for it")
	Do $$$AssertEquals(..SentRows(session), 0, "and no Sent row is written")
	Do ..AssertNoChannel(..Route(session, "web,phone", "telegram", 2), "own web and phone, saved telegram")
	Do $$$AssertEquals(..Items(), "", "and nothing is sent")
	Do ..AssertNoChannel(..Route(session, "web", "email,sms", 3), "a value of unknown names only")
	Do $$$AssertEquals(..Items(), "", "and nothing is sent")
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Do ..SaveChannels("web")
	Set host = ..Host()
	Set host.OwnChannels = "web"
	Set compose = ..Compose(session, "requested", , session_":later")
	Do $$$AssertStatusOK(..Handle(compose, host), "with web saved, the Compose waits for the summary")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "summary"), 1, "after one model request")
	Do ..SaveChannels("telegram")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "A summary."
	Kill response
	Set sc = host.OnResponse(compose, .response, "", reply, "summary")
	Do $$$AssertStatusNotOK(sc, "a value changed while the summary was awaited is read again: the Compose ends with an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ..#NOCHANNEL, "which holds the diagnostic")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "and nothing is sent")
	Do $$$AssertEquals(..SentRows(session), 0, "and no Sent row is written")
}

Method TestRouteForeign()
{
	Set session = ..Session()
	Do $$$AssertStatusOK(..Route(session, "web", "web,email,slack,x@example.org", 1), "own web, saved web and names that are no channel: the Compose is handled")
	Do $$$AssertEquals(..Items(), "Notify", "the digest goes to Notify alone: no name adds a destination")
	Do ..AssertNoChannel(..Route(session, "web", "telegram,phone,email", 2), "own web, saved channels that are not the session's")
	Do $$$AssertEquals(..Items(), "", "a channel outside the session's own is no destination")
	Do $$$AssertStatusOK(..Route(session, "web,phone", "phone,fax", 3), "own web and phone, saved phone and an unknown name: the Compose is handled")
	Do $$$AssertEquals(..Items()_"|"_..Sent(session).Channels, "Notify|phone", "the digest goes to Notify, which reaches the phone alone")
	Do ..AssertNoChannel(..Route(session, "web,phone,telegram", "TelegramOut,SimPhoneOut,WebChatOut,Notify", 4), "the names of items are no channels")
	Do $$$AssertEquals(..Items(), "", "and nothing is sent")
	Do $$$AssertStatusOK(..Route(session, "web", "WEB,Phone", 5), "the names are read without regard to case")
	Do $$$AssertEquals(..Items(), "Notify", "web is named: Notify alone")
	Do ..AssertNoChannel(..Route(session, "web", "email", 6), "own web, saved email, which is no channel of the session")
	Do $$$AssertEquals(..Items(), "", "email alone is a destination only when the session has it")
}

/// The channels that Notify's rule reaches for the Notification, evaluated on a shadow router as the router item does (Test.Core.Routing.Route is private to
/// that class): the targets of every action of the action list (the rules Notification and DigestEmail each add one), mapped to channels in the order of
/// the list, comma-separated; "" when the rule gives no action.
Method NotifyChannels(notification As OcuTalon.Msg.Notification) As %String
{
	Set engine = ##class(Ens.Host).GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine", .sc)
	Do $$$AssertTrue($IsObject(engine), "a shadow router is made")
	Set engine.Document = notification
	Set engine.MsgClass = $ClassName(notification)
	Set engine.Source = "zzsource"
	Set sc = ##class(Ens.Rule.RuleDefinition).EvaluateRulesEx("OcuTalon.Core.Rule.Notify", 0, engine, "", .return, .reason, 1, "e")
	Do $$$AssertStatusOK(sc, "Notify's rule is evaluated")
	Set channels = ""
	For action = 1:1:$Length($Get(return), ";") {
		Set entry = $Piece(return, ";", action)
		If '$Find(entry, "send:") Continue
		Set targets = $Piece($Piece(entry, "send:", 2), ":", 1)
		For i = 1:1:$Length(targets, ",") {
			Set channels = channels_$Select(channels = "": "", 1: ",")_$Case($Piece(targets, ",", i), "WebChatOut": "web", "SimPhoneOut": "phone", "TelegramOut": "telegram", "EmailOut": "email", : "?"_$Piece(targets, ",", i))
		}
	}
	Quit channels
}

Method TestChannelsMatchNotify()
{
	Set session = ..Session()
	Set paired = ..Session()
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Pairing(paired))
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set included = $Get(^OcuTalonTest("TelegramIncluded"))
	Try {
		Set host = ..Host()
		For named = "", "web,telegram", "phone,telegram", "telegram", "phone", "web,phone,telegram,email" {
			Do ..SaveChannels(named)
			For demo = 0, 1 {
				Do ##class(OcuTalon.Test.Demo.Step).Put(demo, "2030-01-02T03:04:05Z")
				For telegram = 0, 1 {
					Set ^OcuTalonTest("TelegramIncluded") = telegram
					For ref = session, paired {
						Set notification = ##class(OcuTalon.Msg.Notification).%New()
						Set notification.SessionRef = ref
						Set notification.Kind = "digest"
						Set label = "digest.channels '"_named_"', demo "_$Select(demo: "on", 1: "off")_", Telegram "_$Select(telegram: "included", 1: "not included")_", "_$Select(ref = paired: "paired", 1: "not paired")
						Do $$$AssertEquals($ListToString(host.Product(ref)), ..NotifyChannels(notification), label_": the channels that Digest records are the channels of Notify's route")
					}
				}
			}
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the Notify comparison failed: "_exception.DisplayString())
	}
	If included = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = included
	}
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(found, value, updatedAt)
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.nowFound, .nowValue, .nowUpdatedAt)
	Do $$$AssertEquals(nowFound_"|"_nowValue_"|"_nowUpdatedAt, found_"|"_value_"|"_updatedAt, "demo mode is put back as the test found it")
	Do $$$AssertEquals($Get(^OcuTalonTest("TelegramIncluded")), included, "and so is the Telegram setting")
}

/// A Tick that is due for no fixture session (before every session's CreatedAt), handled by the host: it only sends the digests that missed a channel again.
Method Retick(host As OcuTalon.Test.Digest.ProcessProbe)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = "2020-01-01T00:00:00Z"
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "a tick is handled")
}

/// Handles a requested Compose of the session on a host whose available channels are web,phone,telegram and whose digest.channels names web and telegram,
/// with the send to Notify failing (fail) or throwing; the host and the status of the Compose.
Method Broken(session As %String, throw As %Boolean, Output host As OcuTalon.Test.Digest.ProcessProbe) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Do ..SaveChannels("web,telegram")
	Set host = ..Host()
	Set host.OwnChannels = "web,phone,telegram"
	If throw {
		Set host.ThrowItems = "Notify"
	} Else {
		Set host.FailItems = "Notify"
	}
	Set host.Only = session
	Quit ..Handle(..Compose(session, "requested", , session_":broken"), host)
}

Method TestNotifyFailure()
{
	Set session = ..Session()
	For throw = 0, 1 {
		Set kind = $Select(throw: "throws", 1: "fails")
		Set sc = ..Broken(session, throw, .host)
		Do $$$AssertStatusNotOK(sc, "a send to Notify that "_kind_": the Compose ends with an error status")
		Do $$$AssertEquals(..Items(), "Notify", "the digest was sent to Notify, once, and to no channel's item")
		Do $$$AssertEquals(..SentRows(session), 0, "and no Sent row is written")
		Do $$$AssertEquals($ClassMethod(..#PROBE, "RouteRows").%Size(), 0, "Digest writes no routing row")
		Set host.FailItems = "", host.ThrowItems = ""
		Do ..Retick(host)
		Do $$$AssertEquals(..Items(), "Notify", "a later tick sends nothing for it")
	}
}

Method TestProductChannels()
{
	Set session = ..Session()
	Set paired = ..Session()
	Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Pairing(paired))
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set included = $Get(^OcuTalonTest("TelegramIncluded"))
	Try {
		Set host = ..Host()
		Set ^OcuTalonTest("TelegramIncluded") = 1
		Do ##class(OcuTalon.Test.Demo.Step).Remove()
		Do $$$AssertEquals($ListToString(host.Product(session)), "web", "demo mode off, no pairing: web alone")
		Do $$$AssertEquals($ListToString(host.Product(paired)), "web,telegram", "paired, Telegram included: web and telegram")
		Do ##class(OcuTalon.Test.Demo.Step).Put("1", "2030-01-02T03:04:05Z")
		Do $$$AssertEquals($ListToString(host.Product(session)), "web,phone", "demo mode on: web and phone")
		Do $$$AssertEquals($ListToString(host.Product(paired)), "web,phone,telegram", "demo mode on and paired: all three, in the order of Notify's rule")
		Set ^OcuTalonTest("TelegramIncluded") = 0
		Do $$$AssertEquals($ListToString(host.Product(paired)), "web,phone", "Telegram not included: no telegram, though paired")
	} Catch exception {
		Do $$$AssertTrue(0, "the channels test failed: "_exception.DisplayString())
	}
	If included = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = included
	}
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(found, value, updatedAt)
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.nowFound, .nowValue, .nowUpdatedAt)
	Do $$$AssertEquals(nowFound_"|"_nowValue_"|"_nowUpdatedAt, found_"|"_value_"|"_updatedAt, "demo mode is put back as the test found it")
	Do $$$AssertEquals($Get(^OcuTalonTest("TelegramIncluded")), included, "and so is the Telegram setting")
}

/// A requested digest of a fresh session with only the channel named and the channel available (its demo mode and pairing set up by the caller), composed
/// with the vital signs healthy and nothing watched; the session. The Notification Digest sent is the probe's record 1.
Method FixedDigest(channel As %String, number As %Integer) As %String
{
	Set session = ..Session()
	Do $$$AssertStatusOK(..Route(session, channel, channel, number), "the digest of the session is composed for "_channel)
	Do $$$AssertEquals(..Items(), "Notify", channel_": Digest sent one Notification, to Notify, at compose time and to no channel's item")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, channel_": and sent it once")
	Do $$$AssertEquals(..Sent(session).Channels, channel, channel_": the Sent row lists the channel")
	Quit session
}

/// The Notification that the probe recorded as record 1, as the router would get it.
Method RecordedNotification() As OcuTalon.Msg.Notification
{
	Set notice = ..Notice(1)
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = notice.session
	Set notification.Kind = notice.kind
	Set notification.CatalogKey = notice.catalogKey
	Set notification.DecisionRef = notice.decisionRef
	Set notification.Slots = notice.slots.%ToJSON()
	Quit notification
}

Method TestWebDigestUnchanged()
{
	Set session = ..FixedDigest("web", 1)
	Set notification = ..RecordedNotification()
	Do $$$AssertEquals(..NotifyChannels(notification), "web", "Notify's rule reaches the web chat alone")
	Set expected = ..#FIXEDDIGEST
	Do $$$AssertEquals(##class(OcuTalon.Channel.DigestText).Text(notification.Slots, "web"), expected, "the web text of the digest is the text it always was")
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.WebChat.Out", .sc)
	Do $$$AssertStatusOK(out.OnNotification(notification, .response), "the web chat's operation delivers it")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND Kind = 'digest'", session)
	Do $$$AssertTrue(rs.%Next(), "the web card is recorded")
	Do $$$AssertEquals(rs.%Get("Text"), expected, "with the text of the digest as it always was, byte for byte")
}

Method TestPhoneDigestUnchanged()
{
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Try {
		Do ##class(OcuTalon.Test.Demo.Step).Put(1, "2030-01-02T03:04:05Z")
		Set session = ..FixedDigest("phone", 2)
		Set notification = ..RecordedNotification()
		Do $$$AssertEquals(..NotifyChannels(notification), "phone", "with demo mode on, Notify's rule reaches the simulated phone alone")
		Set expected = ..#FIXEDDIGEST
		Do $$$AssertEquals(##class(OcuTalon.Channel.DigestText).Text(notification.Slots, "phone"), expected, "the phone text of the digest is the text it always was")
		Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.SimPhone.Out", .sc)
		Do $$$AssertStatusOK(out.OnNotification(notification, .response), "the simulated phone's operation delivers it")
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone'", session)
		Do $$$AssertTrue(rs.%Next(), "the phone message is recorded")
		Do $$$AssertEquals(rs.%Get("Text"), expected, "with the text of the digest as it always was, byte for byte")
	} Catch exception {
		Do $$$AssertTrue(0, "the phone digest test failed: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(found, value, updatedAt)
}

Method TestTelegramDigestUnchanged()
{
	Set included = $Get(^OcuTalonTest("TelegramIncluded"))
	Try {
		Set ^OcuTalonTest("TelegramIncluded") = 1
		Set session = ..Session()
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Pairing(session))
		Do $$$AssertStatusOK(..Route(session, "telegram", "telegram", 3), "the digest of a paired session is composed for telegram")
		Do $$$AssertEquals(..Items(), "Notify", "Digest sent one Notification, to Notify, at compose time and to no channel's item")
		Do $$$AssertEquals(..Sent(session).Channels, "telegram", "the Sent row lists telegram")
		Set notification = ..RecordedNotification()
		Do $$$AssertEquals(..NotifyChannels(notification), "telegram", "Notify's rule reaches Telegram alone")
		Do $$$AssertEquals(##class(OcuTalon.Channel.DigestText).Text(notification.Slots, "telegram"), ..#FIXEDDIGEST, "the Telegram text of the digest, the text that TelegramOut renders, is the text it always was")
	} Catch exception {
		Do $$$AssertTrue(0, "the Telegram digest test failed: "_exception.DisplayString())
	}
	If included = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = included
	}
}

Method TestFailurePath()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Set host.FailRows = 1
	Do $$$AssertStatusNotOK(..Handle(..Compose(session), host), "an error of the rows is returned")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "no Notification follows")
	Do $$$AssertEquals(..SentRows(session), 0, "and no Sent row")
	Set host = ..Host()
	Set host.FailNotice = 1
	Do $$$AssertStatusNotOK(..Handle(..Compose(session), host), "an error of the send of the Notification is returned")
	Do $$$AssertEquals(..SentRows(session), 0, "and no Sent row follows it")
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "a Compose that is handled after both is OK")
	Do $$$AssertEquals(..SentRows(session), 1, "and gives the one Sent row")
}

}
