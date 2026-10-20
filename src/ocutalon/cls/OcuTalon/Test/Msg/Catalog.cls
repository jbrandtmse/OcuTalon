/// Tests of the message catalog and its one renderer (Story 0.9; AD-29, AD-32). The XData blocks hold the expectations, typed
/// apart from the catalog's templates:
///   - Keys: the 57 keys of OcuTalon.Msg.Catalog.Core and the 22 of OcuTalon.Msg.Catalog.Watch;
///   - Gaps: the keys whose entry carries a gap field, the forms the UX does not fix;
///   - Reasons: the plain-words text of each of the 12 Msg.Enum FALLBACKREASON values;
///   - Fixtures: for every key, its slots (the UJ-1 values) and the exact text it renders on the message channels, and its
///     web text where that differs.
/// The fixture context is the process zone America/New_York, now 2026-10-16T18:20:00Z (Friday 14:20 EDT) and the online-demo
/// flag on, passed to RenderAt. The process zone is set before each test and restored after it. TestRenderReadsClockAndFlag
/// changes the public setting onlineDemo and puts it back, and TestNotificationHandoff saves one Notification row and deletes
/// it, again in OnAfterAllTests when a failed run left it.
Class OcuTalon.Test.Msg.Catalog Extends OcuTalon.Test.Contract
{

/// The fixture clock: Friday 2026-10-16 at 14:20 in America/New_York.
Parameter NOW = "2026-10-16T18:20:00Z";

/// The fixture zone.
Parameter ZONE = "America/New_York";

/// The slot types that an entry may declare.
Parameter SLOTTYPES = "time,count,noun,text,sentence,channel,fallbackReason,groups,cost";

/// The fields that an entry may have.
Parameter ENTRYFIELDS = "text,web,slots,source,gap";

/// The TZ of the process before the tests: -1 when it was undefined.
Property SavedZone As %String;

/// The stored online-demo flag before the tests, "" when it was unset.
Property SavedFlag As %String;

/// The run's number, from ^OcuTalonTest("MsgCatalog","n"), which is never reset.
Property Number As %Integer;

/// The id of this run's Notification row, "" when none is saved.
Property NotificationId As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Set ..SavedFlag = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Number = $Increment(^OcuTalonTest("MsgCatalog", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..RestoreZone()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..RestoreZone()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedFlag)
	Do ..RemoveNotification()
	Quit $$$OK
}

/// Both catalog classes parse, hold exactly their keys, and every entry is well formed.
Method TestEntries()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Msg.Catalog", "CLASSES"), "OcuTalon.Msg.Catalog.Core,OcuTalon.Msg.Catalog.Watch", "the renderer reads the two catalog classes")
	Set keys = ..Read("Keys")
	Set core = ..Read("Entries", "OcuTalon.Msg.Catalog.Core")
	Set watch = ..Read("Entries", "OcuTalon.Msg.Catalog.Watch")
	Do $$$AssertEquals(keys.core.%Size(), 57, "the expected Core list has 57 keys")
	Do $$$AssertEquals(keys.watch.%Size(), 22, "the expected Watch list has 22 keys")
	Do $$$AssertEquals(..SortedKeys(core), ..SortedList(keys.core), "Core holds exactly its 57 keys")
	Do $$$AssertEquals(..SortedKeys(watch), ..SortedList(keys.watch), "Watch holds exactly its 22 keys")
	Set corePrefixes = ..Prefixes(..SortedKeys(core))
	Set watchPrefixes = ..Prefixes(..SortedKeys(watch))
	Set shared = ""
	For i = 1:1:$Length(corePrefixes, ",") {
		Set prefix = $Piece(corePrefixes, ",", i)
		If $ListFind($ListFromString(watchPrefixes), prefix) Set shared = shared_" "_prefix
	}
	Do $$$AssertEquals(shared, "", "no key prefix is in both classes")
	Set gapped = ""
	For class = "OcuTalon.Msg.Catalog.Core", "OcuTalon.Msg.Catalog.Watch" {
		Set entries = $Select(class = "OcuTalon.Msg.Catalog.Core": core, 1: watch)
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(.key, .entry) {
			Set problems = ..Problems(key, entry)
			Do $$$AssertEquals(problems, "", key_" is well formed"_$Select(problems = "": "", 1: ": "_problems))
			If entry.%IsDefined("gap") Set gapped(key) = ""
		}
	}
	Set expected = ..Read("Gaps")
	Do $$$AssertEquals(expected.%Size(), 9, "9 keys are expected to carry a gap")
	Set wanted = ..SortedList(expected)
	Set actual = ""
	Set key = ""
	For {
		Set key = $Order(gapped(key))
		Quit:key=""
		Set actual = actual_$Select(actual = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(actual, wanted, "the keys with a gap are exactly the 9 listed")
}

/// Rows 1, 2 and 10's channels: the fixtures cover exactly the catalog, every key renders on the four channels with the
/// fixture's text, the message channels agree, the web channel uses its own wording, and the other channels are refused.
Method TestEveryKeyOnEveryChannel()
{
	Set fixtures = ..Read("Fixtures")
	Set catalogKeys = ..SortedKeys(..Read("Entries", "OcuTalon.Msg.Catalog.Core"))_","_..SortedKeys(..Read("Entries", "OcuTalon.Msg.Catalog.Watch"))
	Do $$$AssertEquals(..SortedList($ListFromString(catalogKeys)), ..SortedKeys(fixtures), "the fixtures cover exactly the 79 keys of the catalog")
	Set refused = ..RefusedChannels()
	Do $$$AssertEquals(refused, "email,webhook,slack,system", "four Msg.Enum channels are refused")
	Set iterator = fixtures.%GetIterator()
	While iterator.%GetNext(.key, .fixture) {
		Set expectedWeb = $Select(fixture.%IsDefined("web"): fixture.web, 1: fixture.text)
		For channel = "phone", "mailbox", "telegram", "web" {
			Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, fixture.slots, channel, ..#NOW, 1, .sc)
			Do $$$AssertStatusOK(sc, key_" renders on "_channel)
			Do $$$AssertEquals(text, $Select(channel = "web": expectedWeb, 1: fixture.text), key_" on "_channel_" is the fixture's text")
		}
		Set json = ##class(OcuTalon.Msg.Catalog).RenderAt(key, fixture.slots.%ToJSON(), "telegram", ..#NOW, 1, .sc)
		Do $$$AssertEquals(json, fixture.text, key_" renders the same from JSON text slots")
		For i = 1:1:$Length(refused, ",") + 1 {
			Set channel = $Piece(refused_",", ",", i)
			Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, fixture.slots, channel, ..#NOW, 1, .sc)
			Set problem = $Select(text '= "": "it rendered", $$$ISOK(sc): "no error", $SYSTEM.Status.GetErrorText(sc) '[ ("channel '"_channel_"'"): "the error does not name the channel", 1: "")
			Do $$$AssertEquals(problem, "", key_" on the channel '"_channel_"' gives an empty text and an error naming it")
		}
	}
}

/// Rows 3 and 4: the local date decides which form a time takes, " ET" is only on the online demo, and a preceding "at"
/// becomes "on" before a dated time.
Method TestTimesAndLocalInstall()
{
	Do ..AssertExpired("2026-10-16T18:12:00Z", 1, "Expired at 14:12 ET. Nothing was changed.", "the same local day")
	Do ..AssertExpired("2026-10-16T18:12:00Z", 0, "Expired at 14:12. Nothing was changed.", "a local install has no ET")
	Do ..AssertExpired("2026-10-17T02:00:00Z", 1, "Expired at 22:00 ET. Nothing was changed.", "02:00Z is 22:00 on the same local day")
	Do ..AssertExpired("2026-10-15T18:12:00Z", 1, "Expired on Thursday at 14:12 ET. Nothing was changed.", "one day before")
	Do ..AssertExpired("2026-10-19T14:00:00Z", 1, "Expired on Monday at 10:00 ET. Nothing was changed.", "three days ahead")
	Do ..AssertExpired("2026-10-10T18:12:00Z", 1, "Expired on Saturday at 14:12 ET. Nothing was changed.", "six days before")
	Do ..AssertExpired("2026-10-22T18:12:00Z", 1, "Expired on Thursday at 14:12 ET. Nothing was changed.", "six days ahead")
	Do ..AssertExpired("2026-10-09T18:12:00Z", 1, "Expired on Oct 9 at 14:12 ET. Nothing was changed.", "seven days before")
	Do ..AssertExpired("2026-10-23T18:12:00Z", 1, "Expired on Oct 23 at 14:12 ET. Nothing was changed.", "seven days ahead")
	Do ..AssertExpired("2025-12-30T15:00:00Z", 1, "Expired on Dec 30, 2025 at 10:00 ET. Nothing was changed.", "another year")
	Do ..AssertExpired("2025-12-30T15:00:00Z", 0, "Expired on Dec 30, 2025 at 10:00. Nothing was changed.", "another year, local install")
	Do ..AssertExpired("2026-10-17T04:30:00Z", 1, "Expired on Saturday at 00:30 ET. Nothing was changed.", "00:30 the next local day, one hour after now", "2026-10-17T03:30:00Z")
	Do ..AssertExpired("2026-10-17T03:10:00Z", 1, "Expired at 23:10 ET. Nothing was changed.", "23:10 the same local day as 23:30", "2026-10-17T03:30:00Z")
	Do ..AssertExpired("2025-12-31T17:00:00Z", 1, "Expired on Wednesday at 12:00 ET. Nothing was changed.", "two days before across a new year", "2026-01-02T17:00:00Z")
	Do ..AssertExpired("2026-01-15T22:30:00Z", 1, "Expired at 17:30 ET. Nothing was changed.", "standard time in winter", "2026-01-15T17:00:00Z")
	Set late = ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.late", {"time": "2026-10-15T14:00:00Z", "text": "Call the vendor."}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(late, "Reminder (late; it was due on Thursday at 10:00 ET): Call the vendor.", "'at' becomes 'on' before a dated time")
	Set late = ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.late", {"time": "2026-10-16T14:00:00Z", "text": "Call the vendor."}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(late, "Reminder (late; it was due at 10:00 ET): Call the vendor.", "'at' stays before a bare time")
}

/// Row 5: the item noun's form comes from the count slot, which is the total in the results.
Method TestNoun()
{
	Set group = {"itemName": "OrdersFromPartner", "count": 1, "errorSummary": "The order date was not in the expected format", "firstAt": "2026-10-16T18:12:00Z"}
	For count = 1, 0, 50 {
		Set slots = {"count": (count), "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "groups": [(group)]}
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.noFixUnknown", slots, "telegram", ..#NOW, 1, .sc)
		Do $$$AssertEquals($Piece(text, ".", 1), count_" "_$Select(count = 1: "order", 1: "orders")_" failed since 14:12 ET", "count "_count_" picks the noun's form")
	}
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("result.failedAgain", {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 1, "failedAgain": 49, "failReason": "x"}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals($Piece(text, ".", 1), "1 of 50 orders went through", "a result takes the form from the total, not from the completed count")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("result.skipped", {"count": 1, "itemNoun": {"one": "order", "other": "orders"}, "completed": 0, "skipped": 1}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals($Piece(text, ".", 1), "0 of 1 order went through", "a total of 1 takes the singular")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("press.approved", {"count": 1, "itemNoun": {"one": "message", "other": "messages"}}, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertEquals(text, "Approved. Repairing and resending 1 message.", "the noun is the diagnosis's, in its singular")
}

/// Row 6: a string slot is trimmed, loses control characters, collapses whitespace and line breaks to one space, and drops one
/// trailing period before a period of the text; its braces and line breaks cannot inject a placeholder or a line.
Method TestStringSlots()
{
	Set tail = " None of my fixes applies to this, so I'm not proposing one. Nothing was changed."
	Set base = {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "groups": [{"itemName": "A", "count": 1, "errorSummary": "b", "firstAt": "2026-10-16T18:12:00Z"}]}
	Set head = "50 orders failed since 14:12 ET. "
	Set cases = $ListBuild($ListBuild("The partner changed"_$Char(10)_"its   date"_$Char(9)_"format."_$Char(13, 10), "The partner changed its date format"))
	Set cases = cases_$ListBuild($ListBuild("  The partner changed its date format  ", "The partner changed its date format"))
	Set cases = cases_$ListBuild($ListBuild("Date"_$Char(1)_" format"_$Char(7)_".", "Date format"))
	Set cases = cases_$ListBuild($ListBuild("Bad {count} cause", "Bad {count} cause"))
	Set cases = cases_$ListBuild($ListBuild("Bad {cause} cause.", "Bad {cause} cause"))
	Set cases = cases_$ListBuild($ListBuild("x"_$Char(10, 10)_"Approve?", "x Approve?"))
	Set cases = cases_$ListBuild($ListBuild("Ends with three..."_$Char(10), "Ends with three.."))
	Set cases = cases_$ListBuild($ListBuild("The partner"_$Char(8239)_"changed"_$Char(8195, 8195)_"its"_$Char(12288)_"date format", "The partner changed its date format"))
	Set cases = cases_$ListBuild($ListBuild("Date"_$Char(8203)_"s"_$Char(8238)_" format"_$Char(8297)_$Char(65279), "Dates format"))
	For i = 1:1:$ListLength(cases) {
		Set case = $ListGet(cases, i)
		Do base.%Set("cause", $List(case, 1))
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.noFix", base, "telegram", ..#NOW, 1, .sc)
		Do $$$AssertStatusOK(sc, "string case "_i_" renders")
		Do $$$AssertEquals($Piece(text, "Failures:", 1), head_$List(case, 2)_"."_tail_$Char(10, 10), "string case "_i_" is cleaned")
	}
	Set reason = ##class(OcuTalon.Msg.Catalog).RenderAt("notice.tellNow", {"whatHappened": "Mail from Dana", "reason": "It mentions a deadline today."}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(reason, "Mail from Dana"_$Char(10)_"Why now: It mentions a deadline today.", "'Why now:' keeps the reason's own period")
	Set reason = ##class(OcuTalon.Msg.Catalog).RenderAt("notice.tellNow", {"whatHappened": "Mail about {reason}", "reason": "a {whatHappened}"}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(reason, "Mail about {reason}"_$Char(10)_"Why now: a {whatHappened}", "substitution is a single pass")
	Set reminder = ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.due", {"text": "Call the vendor"}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(reminder, "Reminder: Call the vendor.", "a reminder with no period gets the text's period")
	Set reminder = ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.due", {"text": "Call the vendor."}, "phone", ..#NOW, 1, .sc)
	Do $$$AssertEquals(reminder, "Reminder: Call the vendor.", "a reminder with a period keeps one")
}

/// Row 7: one line per group, in order, with the same time forms as any message time.
Method TestGroups()
{
	Set slots = {"count": 7, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "fallbackReason": "empty"}
	Set groups = []
	Do groups.%Push({"itemName": "OrdersFromPartner", "count": 5, "errorSummary": "The order date was not in the expected format", "firstAt": "2026-10-16T18:12:00Z"})
	Do groups.%Push({"itemName": "PartnerAck", "count": 2, "errorSummary": "The ack was late", "firstAt": "2026-10-15T18:12:00Z"})
	Do slots.%Set("groups", groups)
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.fallback", slots, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertStatusOK(sc, "two groups render")
	Set lines = $Piece($Piece(text, "Failures:"_$Char(10), 2), $Char(10, 10), 1)
	Do $$$AssertEquals(lines, "OrdersFromPartner: 5, 'The order date was not in the expected format', first at 14:12 ET"_$Char(10)_"PartnerAck: 2, 'The ack was late', first on Thursday at 14:12 ET", "one line per group, in order, 'at' before a dated time becomes 'on'")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.fallback", slots, "telegram", ..#NOW, 0, .sc)
	Do $$$AssertEquals($Piece($Piece(text, "Failures:"_$Char(10), 2), $Char(10, 10), 1), "OrdersFromPartner: 5, 'The order date was not in the expected format', first at 14:12"_$Char(10)_"PartnerAck: 2, 'The ack was late', first on Thursday at 14:12", "a local install has no ET in the lines")
	Do ..AssertRefused("an empty groups array", "incident.fallback", ..WithSlot(slots, "groups", []), "telegram", "groups")
	Do ..AssertRefused("groups that are not an array", "incident.fallback", ..WithSlot(slots, "groups", "none"), "telegram", "groups", "array")
	Do ..AssertRefused("a group that is not an object", "incident.fallback", ..WithSlot(slots, "groups", [1]), "telegram", "group 1", "object")
	Set bad = {"itemName": "A", "count": -1, "errorSummary": "b", "firstAt": "2026-10-16T18:12:00Z"}
	Do ..AssertRefused("a group with a bad count", "incident.fallback", ..WithSlot(slots, "groups", [(bad)]), "telegram", "group 1", "count")
	Do bad.%Set("count", 1)
	Do bad.%Set("firstAt", "tomorrow")
	Do ..AssertRefused("a group with a bad time", "incident.fallback", ..WithSlot(slots, "groups", [(bad)]), "telegram", "group 1", "firstAt")
	Do bad.%Set("firstAt", "2026-10-16T18:12:00Z")
	Do bad.%Set("errorSummary", " ")
	Do ..AssertRefused("a group with an empty summary", "incident.fallback", ..WithSlot(slots, "groups", [(bad)]), "telegram", "group 1", "errorSummary")
}

/// Row 8: the channel and the fallback reason read as words; all 12 FALLBACKREASON values of Msg.Enum render, so a new value
/// without a map fails here; invalid and unusable share the generic reason.
Method TestEnumeratedSlots()
{
	Set channels = $ListBuild($ListBuild("web", "the web chat"), $ListBuild("phone", "the simulated phone"), $ListBuild("telegram", "Telegram"))
	For i = 1:1:$ListLength(channels) {
		Set pair = $ListGet(channels, i)
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.alreadyApproved", {"channel": ($List(pair, 1)), "time": "2026-10-16T18:15:00Z"}, "phone", ..#NOW, 1, .sc)
		Do $$$AssertEquals(text, "Already answered: approved from "_$List(pair, 2)_" at 14:15 ET.", "the channel "_$List(pair, 1)_" reads as "_$List(pair, 2))
	}
	Set reasons = ..Read("Reasons")
	Set enum = $ListFromString($Parameter("OcuTalon.Msg.Enum", "FALLBACKREASON"))
	Do $$$AssertEquals($ListLength(enum), 12, "Msg.Enum has 12 fallback reasons")
	Do $$$AssertEquals(reasons.%Size(), 12, "the expected reasons are 12")
	Set position = 0
	While $ListNext(enum, position, reason) {
		Do $$$AssertTrue(reasons.%IsDefined(reason), reason_" has an expected text")
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("conversation.turnFallback", {"fallbackReason": (reason)}, "telegram", ..#NOW, 1, .sc)
		Do $$$AssertStatusOK(sc, reason_" renders")
		Do $$$AssertEquals(text, "I couldn't answer that: "_reasons.%Get(reason)_". Nothing was changed.", reason_" gives its text")
	}
	Do ..AssertRefused("the channel mailbox", "answered.alreadyApproved", {"channel": "mailbox", "time": "2026-10-16T18:15:00Z"}, "phone", "channel", "mailbox")
	Do ..AssertRefused("the channel email", "answered.alreadyApproved", {"channel": "email", "time": "2026-10-16T18:15:00Z"}, "phone", "channel", "email")
	Do ..AssertRefused("the channel Telegram in capitals", "answered.alreadyApproved", {"channel": "TELEGRAM", "time": "2026-10-16T18:15:00Z"}, "phone", "channel", "TELEGRAM")
	Do ..AssertRefused("an unknown fallback reason", "conversation.turnFallback", {"fallbackReason": "melted"}, "phone", "fallbackReason", "melted")
	Do ..AssertRefused("a fallback reason that is the key's suffix", "conversation.turnFallback", {"fallbackReason": "noKey"}, "phone", "fallbackReason", "noKey")
}

/// Row 9: a cost shows by the UX's Formats rule; a negative amount or a non-number is refused.
Method TestCost()
{
	Set cases = $ListBuild($ListBuild("5", "$5.00"), $ListBuild("1.24", "$1.24"), $ListBuild("0.042", "$0.042"), $ListBuild("0.0006", "$0.0006"), $ListBuild("0.00004", "<$0.0001"))
	Set cases = cases_$ListBuild($ListBuild("0", "<$0.0001"), $ListBuild("0.0001", "$0.0001"), $ListBuild("0.01", "$0.010"), $ListBuild("1", "$1.00"), $ListBuild("12.5", "$12.50"))
	Set cases = cases_$ListBuild($ListBuild("0.99996", "$1.00"), $ListBuild("0.99949", "$0.999"), $ListBuild("0.009996", "$0.010"), $ListBuild("0.009949", "$0.0099"))
	For i = 1:1:$ListLength(cases) {
		Set case = $ListGet(cases, i)
		Set slots = ##class(%DynamicAbstractObject).%FromJSON("{""cap"": "_$List(case, 1)_", ""time"": ""2026-10-16T18:15:00Z""}")
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("banner.costCap", slots, "web", ..#NOW, 1, .sc)
		Do $$$AssertEquals(text, "OcuTalon has reached today's cost limit of "_$List(case, 2)_". Decisions use fixed rules until 14:15 ET.", "the cost "_$List(case, 1)_" shows as "_$List(case, 2))
	}
	Set time = "2026-10-16T18:15:00Z"
	Do ..AssertRefused("a negative cost", "banner.costCap", {"cap": -1, "time": (time)}, "web", "cap")
	Do ..AssertRefused("a cost that is text", "banner.costCap", {"cap": "5", "time": (time)}, "web", "cap", "number")
	Do ..AssertRefused("a cost that is null", "banner.costCap", ##class(%DynamicAbstractObject).%FromJSON("{""cap"": null, ""time"": ""2026-10-16T18:15:00Z""}"), "web", "cap")
	Do ..AssertRefused("no cost", "banner.costCap", {"time": (time)}, "web", "cap", "missing")
}

/// Row 10: every bad input gives an empty text and an error in plain English that names the key and the slot or channel.
Method TestErrors()
{
	Set fixtures = ..Read("Fixtures")
	Set good = fixtures.%Get("incident.withFix").slots
	Set key = "incident.withFix"
	Do ..AssertRefused("an unknown key", "incident.nope", good, "telegram", "incident.nope")
	Do ..AssertRefused("an empty key", "", good, "telegram", "key")
	For channel = "email", "webhook", "slack", "system", "" {
		Do ..AssertRefused("the channel '"_channel_"'", key, good, channel, "channel '"_channel_"'", key)
	}
	For slots = "[1,2]", """text""", "5", "{", "null", "true" {
		Do ..AssertRefused("slots "_slots, key, slots, "telegram", "slots", key)
	}
	Do ..AssertRefused("slots that are a dynamic array", key, [], "telegram", "slots", key)
	Do ..AssertRefused("slots that are not a dynamic object", key, ##class(%DynamicArray).%New(), "telegram", "slots", key)
	Set iterator = good.%GetIterator()
	While iterator.%GetNext(.name) {
		Do ..AssertRefused("the slot "_name_" missing", key, ..WithoutSlot(good, name), "telegram", "'"_name_"'", "missing")
		Do ..AssertRefused("the slot "_name_" null", key, ..WithSlot(good, name, "", "null"), "telegram", "'"_name_"'")
	}
	For name = "cause", "fixSummary", "field", "before", "after" {
		Do ..AssertRefused("the slot "_name_" empty", key, ..WithSlot(good, name, ""), "telegram", "'"_name_"'", "empty")
		Do ..AssertRefused("the slot "_name_" blank", key, ..WithSlot(good, name, " "_$Char(10)_" "), "telegram", "'"_name_"'", "empty")
		Do ..AssertRefused("the slot "_name_" a number", key, ..WithSlot(good, name, 5, "number"), "telegram", "'"_name_"'", "string")
	}
	For name = "cause", "fixSummary", "after" {
		Do ..AssertRefused("the slot "_name_" a lone period", key, ..WithSlot(good, name, "."), "telegram", "'"_name_"'", "empty")
	}
	Set text = ##class(OcuTalon.Msg.Catalog).Render("press.rejected", "", , .sc)
	Do $$$AssertTrue((text = "") && $$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "press.rejected") && ($SYSTEM.Status.GetErrorText(sc) [ "channel"), "Render with no channel gives an empty text and an error, and does not throw")
	For time = "2026-10-16 18:12:00", "2026-10-16T18:12:00", "2026-10-16T18:12:00+00:00", "yesterday", "2026-13-45T10:00:00Z", "", "2026-02-30T00:00:00Z" {
		Do ..AssertRefused("the time '"_time_"'", key, ..WithSlot(good, "time", time), "telegram", "'time'")
	}
	Do ..AssertRefused("a time that is a number", key, ..WithSlot(good, "time", 5, "number"), "telegram", "'time'", "string")
	For count = -1, 1.5 {
		Do ..AssertRefused("the count "_count, key, ..WithSlot(good, "count", count, "number"), "telegram", "'count'", "whole number")
	}
	For count = "50", "", "abc" {
		Do ..AssertRefused("the count '"_count_"' as text", key, ..WithSlot(good, "count", count), "telegram", "'count'", "number")
	}
	Do ..AssertRefused("a count that is true", key, ..WithSlot(good, "count", 1, "boolean"), "telegram", "'count'", "number")
	Do ..AssertRefused("a resend count of -2", key, ..WithSlot(good, "resendCount", -2, "number"), "telegram", "'resendCount'", "whole number")
	Do ..AssertRefused("itemNoun with no other form", key, ..WithSlot(good, "itemNoun", {"one": "order"}), "telegram", "'itemNoun'", "'other'")
	Do ..AssertRefused("itemNoun with no one form", key, ..WithSlot(good, "itemNoun", {"other": "orders"}), "telegram", "'itemNoun'", "'one'")
	Do ..AssertRefused("itemNoun with a form that is a number", key, ..WithSlot(good, "itemNoun", {"one": 1, "other": "orders"}), "telegram", "'itemNoun'", "string")
	Do ..AssertRefused("itemNoun with an empty form", key, ..WithSlot(good, "itemNoun", {"one": "", "other": "orders"}), "telegram", "'itemNoun'", "empty")
	Do ..AssertRefused("itemNoun with a blank form", key, ..WithSlot(good, "itemNoun", {"one": "order", "other": " "}), "telegram", "'itemNoun'", "empty")
	Do ..AssertRefused("itemNoun that is text", key, ..WithSlot(good, "itemNoun", "orders"), "telegram", "'itemNoun'", "object")
	Do ..AssertRefused("itemNoun that is an array", key, ..WithSlot(good, "itemNoun", ["order", "orders"]), "telegram", "'itemNoun'", "object")
	Do ..AssertRefused("itemNoun that is null", key, ..WithSlot(good, "itemNoun", "", "null"), "telegram", "'itemNoun'", "object")
	Do ..AssertRefused("a noun with no count slot", "press.approved", {"itemNoun": {"one": "order", "other": "orders"}}, "telegram", "'count'", "press.approved")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, good, "telegram", "garbage", 1, .sc)
	Do $$$AssertTrue((text = "") && $$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "clock 'garbage'") && ($SYSTEM.Status.GetErrorText(sc) [ key), "a clock that is not a time gives an empty text and an error naming it")
}

/// Row 11: a slot that the entry does not declare is ignored.
Method TestExtraSlots()
{
	Set fixture = ..Read("Fixtures").%Get("incident.withFix")
	Set slots = ..WithSlot(fixture.slots, "unused", "x")
	Do slots.%Set("another", 5)
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.withFix", slots, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertStatusOK(sc, "extra slots do not fail the render")
	Do $$$AssertEquals(text, fixture.text, "extra slots do not change the text")
	Set laterFixture = ..Read("Fixtures").%Get("incident.laterRequest")
	Set later = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.laterRequest", laterFixture.slots, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertStatusOK(sc, "the later request renders")
	Do $$$AssertEquals(later, laterFixture.text, "the later request renders the fixture's text")
	Set withCause = ..WithSlot(laterFixture.slots, "cause", "The partner changed its date format.")
	Set same = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.laterRequest", withCause, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertStatusOK(sc, "the later request renders with a cause it does not declare")
	Do $$$AssertEquals(same, later, "the cause that the later request does not show is ignored")
}

/// The entry of a key, with the class that holds it; an unknown key gives an empty value and an error naming it.
Method TestEntry()
{
	Set entry = ##class(OcuTalon.Msg.Catalog).Entry("press.rejected", .sc)
	Do $$$AssertStatusOK(sc, "a Core key has an entry")
	Do $$$AssertEquals(entry.class, "OcuTalon.Msg.Catalog.Core", "the entry names the class that holds it")
	Do $$$AssertEquals(entry.text, "Rejected. Nothing was changed.", "the entry holds the text")
	Set entry = ##class(OcuTalon.Msg.Catalog).Entry("watch.onlyOrders", .sc)
	Do $$$AssertStatusOK(sc, "a Watch key has an entry")
	Do $$$AssertEquals(entry.class, "OcuTalon.Msg.Catalog.Watch", "the entry names the Watch class")
	Set entry = ##class(OcuTalon.Msg.Catalog).Entry("nope.key", .sc)
	Do $$$AssertEquals(entry, "", "an unknown key has no entry")
	Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "nope.key"), "the error names the key")
}

/// Row 12: a saved Notification, as a producer sets it, renders the UJ-1 incident notice on Telegram from its JSON slots.
Method TestNotificationHandoff()
{
	Set fixture = ..Read("Fixtures").%Get("incident.withFix")
	Do ..RemoveNotification()
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = "ZzCat"_..Number
	Set notification.Kind = "incident"
	Set notification.CatalogKey = "incident.withFix"
	Set notification.Slots = fixture.slots.%ToJSON()
	Set sc = notification.%Save()
	Do $$$AssertStatusOK(sc, "the notification is saved")
	If $$$ISERR(sc) Quit
	Set id = notification.%Id()
	Set ..NotificationId = id
	Kill notification
	Set opened = ##class(OcuTalon.Msg.Notification).%OpenId(id)
	Do $$$AssertTrue($IsObject(opened), "the notification is read back")
	If '$IsObject(opened) Quit
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(opened.CatalogKey, opened.Slots, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertStatusOK(sc, "the saved key and slots render")
	Do $$$AssertEquals(text, fixture.text, "the saved notification renders the UJ-1 incident notice")
	Set object = ##class(OcuTalon.Msg.Catalog).RenderAt(opened.CatalogKey, fixture.slots, "telegram", ..#NOW, 1, .sc)
	Do $$$AssertEquals(text, object, "JSON text and a dynamic object give the same text")
	Kill opened
	Do ..RemoveNotification()
	Do $$$AssertNotTrue(##class(OcuTalon.Msg.Notification).%ExistsId(id), "the notification row is deleted")
}

/// Row 13: Render reads the clock and the online-demo flag itself: " ET" follows the flag, and the text equals RenderAt for a
/// clock read just before or just after the call.
Method TestRenderReadsClockAndFlag()
{
	For flag = 1, 0 {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag), "onlineDemo is set to "_flag)
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set slots = {"time": (before)}.%ToJSON()
		Set text = ##class(OcuTalon.Msg.Catalog).Render("answered.expired", slots, "telegram", .sc)
		Set after = ##class(OcuTalon.Data.Time).NowUtc()
		Set first = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.expired", slots, "telegram", before, flag, .scFirst)
		Set second = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.expired", slots, "telegram", after, flag, .scSecond)
		Do $$$AssertStatusOK(sc, "Render with the flag "_flag_" succeeds")
		Do $$$AssertTrue((text = first) || (text = second), "Render equals RenderAt for the clock and the flag "_flag_": "_text)
		Do $$$AssertEquals($Find(text, " ET") > 0, flag, "ET is present exactly when the flag is "_flag)
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedFlag)
}

/// Asserts the text of a message with a time in the instance zone: slots {"time": utc} of answered.expired.
Method AssertExpired(utc As %String, flag As %Boolean, expected As %String, label As %String, now As %String = "") [ Private ]
{
	If now = "" Set now = ..#NOW
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.expired", {"time": (utc)}, "phone", now, flag, .sc)
	Do $$$AssertStatusOK(sc, label_" renders")
	Do $$$AssertEquals(text, expected, label)
}

/// Asserts that RenderAt refused: an empty text and an error status whose text holds the one or two fragments.
Method AssertRefused(label As %String, key As %String, slots, channel As %String, first As %String, second As %String = "") [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots, channel, ..#NOW, 1, .sc)
	Set error = $Select($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "")
	Set problem = $Select(text '= "": "it rendered '"_text_"'", error = "": "there is no error", error '[ first: "the error '"_error_"' does not hold '"_first_"'", (second '= "") && (error '[ second): "the error '"_error_"' does not hold '"_second_"'", 1: "")
	Do $$$AssertEquals(problem, "", label_" gives an empty text and a named error")
}

/// A copy of the slots with one value set: an object as it is, anything else with the JSON type given (string, number,
/// boolean or null).
ClassMethod WithSlot(slots As %DynamicObject, name As %String, value, type As %String = "string") As %DynamicObject [ Private ]
{
	Set copy = ##class(%DynamicAbstractObject).%FromJSON(slots.%ToJSON())
	If $IsObject(value) {
		Do copy.%Set(name, value)
	} Else {
		Do copy.%Set(name, value, type)
	}
	Quit copy
}

/// A copy of the slots without one name.
ClassMethod WithoutSlot(slots As %DynamicObject, name As %String) As %DynamicObject [ Private ]
{
	Set copy = ##class(%DynamicAbstractObject).%FromJSON(slots.%ToJSON())
	Do copy.%Remove(name)
	Quit copy
}

/// The problems of one entry, as one line; "" when it is well formed.
ClassMethod Problems(key As %String, entry As %DynamicObject) As %String [ Private ]
{
	Set problems = ""
	If '$Match(key, "^[a-z][A-Za-z]*\.[a-z][A-Za-z0-9]*$") || ($Length(key) > 128) Set problems = problems_"the key is not <prefix>.<name>; "
	Set iterator = entry.%GetIterator()
	While iterator.%GetNext(.field) {
		If '$ListFind($ListFromString(..#ENTRYFIELDS), field) Set problems = problems_"the field "_field_" is unknown; "
	}
	If (entry.%GetTypeOf("text") '= "string") || (entry.%Get("text") = "") Set problems = problems_"the text is missing or empty; "
	If entry.%IsDefined("web") && ((entry.%GetTypeOf("web") '= "string") || (entry.%Get("web") = "")) Set problems = problems_"the web text is empty; "
	If entry.%IsDefined("gap") && ((entry.%GetTypeOf("gap") '= "string") || (entry.%Get("gap") = "")) Set problems = problems_"the gap is empty; "
	If (entry.%GetTypeOf("source") '= "string") || (entry.%Get("source") = "") || ('$Match(entry.%Get("source"), "^[ -~]+$")) {
		Set problems = problems_"the source is missing or is not ASCII prose; "
	}
	If entry.%GetTypeOf("slots") '= "object" Quit problems_"the slots are not an object; "
	Kill declared
	Set nouns = 0
	Set iterator = entry.slots.%GetIterator()
	While iterator.%GetNext(.name, .type) {
		Set declared(name) = ""
		If '$ListFind($ListFromString(..#SLOTTYPES), type) Set problems = problems_"the slot "_name_" has the unknown type "_type_"; "
		If type = "noun" {
			Set nouns = nouns + 1
			If name '= "itemNoun" Set problems = problems_"the noun slot is "_name_", not itemNoun; "
		}
	}
	If nouns && (entry.slots.%Get("count") '= "count") Set problems = problems_"a noun needs a count slot; "
	Set wanted = ..Names(.declared)
	If ..Placeholders(entry.%Get("text")) '= wanted Set problems = problems_"the text uses {"_..Placeholders(entry.%Get("text"))_"}, not the declared {"_wanted_"}; "
	If entry.%IsDefined("web") && (..Placeholders(entry.%Get("web")) '= wanted) Set problems = problems_"the web text uses {"_..Placeholders(entry.%Get("web"))_"}, not the declared {"_wanted_"}; "
	Quit problems
}

/// The sorted, comma-separated placeholder names of a text.
ClassMethod Placeholders(text As %String) As %String [ Private ]
{
	Kill found
	Set position = 1
	While position <= $Length(text) {
		Set open = $Find(text, "{", position)
		If open = 0 Quit
		Set close = $Find(text, "}", open)
		If close = 0 Quit
		Set found($Extract(text, open, close - 2)) = ""
		Set position = close
	}
	Quit ..Names(.found)
}

/// The subscripts of an array, in order, comma-separated.
ClassMethod Names(ByRef array) As %String [ Private ]
{
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(array(name))
		Quit:name=""
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Quit names
}

/// The names of a JSON object, sorted and comma-separated.
ClassMethod SortedKeys(object As %DynamicObject) As %String [ Private ]
{
	Kill names
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.name) {
		Set names(name) = ""
	}
	Quit ..Names(.names)
}

/// The elements of a JSON array of strings (or a $ListBuild list), sorted and comma-separated.
ClassMethod SortedList(list) As %String [ Private ]
{
	Kill names
	If $IsObject(list) {
		Set iterator = list.%GetIterator()
		While iterator.%GetNext(, .name) {
			Set names(name) = ""
		}
	} Else {
		Set position = 0
		While $ListNext(list, position, name) {
			Set names(name) = ""
		}
	}
	Quit ..Names(.names)
}

/// The prefixes of a comma list of keys, comma-separated.
ClassMethod Prefixes(keys As %String) As %String [ Private ]
{
	Kill prefixes
	For i = 1:1:$Length(keys, ",") {
		Set prefixes($Piece($Piece(keys, ",", i), ".", 1)) = ""
	}
	Quit ..Names(.prefixes)
}

/// The Msg.Enum CHANNEL values that Render does not serve, comma-separated.
ClassMethod RefusedChannels() As %String [ Private ]
{
	Set refused = ""
	Set enum = $ListFromString($Parameter("OcuTalon.Msg.Enum", "CHANNEL"))
	Set served = $ListFromString($Parameter("OcuTalon.Msg.Catalog", "CHANNELS"))
	Set position = 0
	While $ListNext(enum, position, channel) {
		If '$ListFind(served, channel) Set refused = refused_$Select(refused = "": "", 1: ",")_channel
	}
	Quit refused
}

/// Deletes this run's Notification row, if there is one.
Method RemoveNotification() [ Private ]
{
	If (..NotificationId '= "") && ##class(OcuTalon.Msg.Notification).%ExistsId(..NotificationId) {
		Do ##class(OcuTalon.Msg.Notification).%DeleteId(..NotificationId)
	}
	Set ..NotificationId = ""
}

/// Puts the TZ of the process back as it was before the tests.
Method RestoreZone() [ Private ]
{
	Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
}

/// The keys of the two catalog classes, written apart from them.
XData Keys [ MimeType = application/json ]
{
{
 "core": [
  "pairing.paired",
  "pairing.badCode",
  "pairing.start",
  "pairing.notPaired",
  "pairing.stopped",
  "pairing.unpairedFromPage",
  "pairing.otherChatPaired",
  "press.approved",
  "press.rejected",
  "press.notPairedChat",
  "press.unavailable",
  "press.rejectedFollowUp",
  "answered.approved",
  "answered.approvedBy",
  "answered.rejected",
  "answered.rejectedBy",
  "answered.expired",
  "answered.alreadyApproved",
  "conversation.turnFallback",
  "conversation.dailyCap",
  "conversation.sessionAllowance",
  "fallbackReason.timeout",
  "fallbackReason.empty",
  "fallbackReason.cutOff",
  "fallbackReason.refusal",
  "fallbackReason.error",
  "fallbackReason.rateLimited",
  "fallbackReason.budget",
  "fallbackReason.tooLarge",
  "fallbackReason.dailyCap",
  "fallbackReason.noKey",
  "fallbackReason.generic",
  "notice.tellNow",
  "reminder.due",
  "reminder.late",
  "banner.allowance",
  "banner.dailyCap",
  "banner.unreachable",
  "banner.noModelKey",
  "banner.costCap",
  "banner.heartbeatStalled",
  "banner.telegramPaused",
  "banner.resetSoon",
  "banner.reconnecting",
  "bannerAction.installYourself",
  "bannerAction.howToSetKey",
  "bannerAction.budgets",
  "bannerAction.setUpBot",
  "signIn.title",
  "signIn.heading",
  "signIn.submit",
  "signIn.help",
  "signIn.errorCredentials",
  "signIn.errorNoRole",
  "signIn.logoAlt",
  "signIn.signedOut",
  "audit.recorded"
 ],
 "watch": [
  "watch.productionStopped",
  "watch.itemDisabled",
  "watch.unknownProduction",
  "watch.onlyOrders",
  "agent.noCommands",
  "checks.notEverything",
  "checks.notEverythingRestPassed",
  "checks.everythingElsePassed",
  "checks.allPassed",
  "checks.nothingWatched",
  "incident.withFix",
  "incident.laterRequest",
  "incident.fallback",
  "incident.noFix",
  "incident.noFixUnknown",
  "result.allThrough",
  "result.failedAgain",
  "result.skipped",
  "result.failedAndSkipped",
  "result.stillResending",
  "result.interrupted",
  "result.couldNotStart"
 ]
}
}

/// The keys whose entry carries a gap field: the forms the UX does not fix.
XData Gaps [ MimeType = application/json ]
{
[
 "answered.alreadyApproved",
 "incident.withFix",
 "incident.laterRequest",
 "result.allThrough",
 "result.failedAgain",
 "result.skipped",
 "result.failedAndSkipped",
 "result.stillResending",
 "result.interrupted"
]
}

/// The plain-words text of each Msg.Enum FALLBACKREASON value; invalid and unusable share the generic reason.
XData Reasons [ MimeType = application/json ]
{
{
 "no_key": "no model key is set",
 "daily_cap": "today's cost limit has been reached",
 "budget": "this would have gone over the token budget",
 "too_large": "this request would have been too large to send",
 "timeout": "the model didn't answer within 60 seconds",
 "rate_limited": "the model was busy and retries ran out",
 "error": "the model returned an error",
 "refusal": "the model declined to answer",
 "cut_off": "the model's reply was cut off",
 "empty": "the model's reply was empty",
 "invalid": "the model's reply couldn't be used",
 "unusable": "the model's reply couldn't be used"
}
}

/// For every key: the slots (UJ-1 values) and the exact text on the message channels, and the web text where it differs.
XData Fixtures [ MimeType = application/json ]
{
{
 "pairing.paired": {"slots": {}, "text": "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair)."},
 "pairing.badCode": {"slots": {}, "text": "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one."},
 "pairing.start": {"slots": {}, "text": "This is OcuTalon, an assistant that runs inside InterSystems IRIS. To use it here, open your OcuTalon page and scan the QR code there; that pairs this chat with your session."},
 "pairing.notPaired": {"slots": {}, "text": "This chat isn't paired yet. Open your OcuTalon page and scan the QR code there."},
 "pairing.stopped": {"slots": {}, "text": "Unpaired. This chat won't get OcuTalon messages anymore. Scan the QR code on the OcuTalon page to pair again."},
 "pairing.unpairedFromPage": {"slots": {}, "text": "Unpaired from the OcuTalon page. Scan the QR code there to pair again."},
 "pairing.otherChatPaired": {"slots": {}, "text": "Another Telegram chat was paired with this OcuTalon session, so this chat is no longer paired."},
 "press.approved": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}}, "text": "Approved. Repairing and resending 50 orders."},
 "press.rejected": {"slots": {}, "text": "Rejected. Nothing was changed."},
 "press.notPairedChat": {"slots": {}, "text": "Only the paired chat can answer this request."},
 "press.unavailable": {"slots": {}, "text": "That request is no longer available."},
 "press.rejectedFollowUp": {"slots": {}, "text": "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page."},
 "answered.approved": {"slots": {"channel": "telegram", "time": "2026-10-16T18:15:00Z"}, "text": "Approved from Telegram at 14:15 ET.", "web": "Approved from Telegram at 14:15 ET"},
 "answered.approvedBy": {"slots": {"user": "sam", "channel": "web", "time": "2026-10-16T18:15:00Z"}, "text": "Approved by sam from the web chat at 14:15 ET.", "web": "Approved by sam from the web chat at 14:15 ET"},
 "answered.rejected": {"slots": {"channel": "phone", "time": "2026-10-16T18:15:00Z"}, "text": "Rejected from the simulated phone at 14:15 ET. Nothing was changed."},
 "answered.rejectedBy": {"slots": {"user": "sam", "channel": "telegram", "time": "2026-10-16T18:15:00Z"}, "text": "Rejected by sam from Telegram at 14:15 ET. Nothing was changed."},
 "answered.expired": {"slots": {"time": "2026-10-16T18:15:00Z"}, "text": "Expired at 14:15 ET. Nothing was changed."},
 "answered.alreadyApproved": {"slots": {"channel": "web", "time": "2026-10-16T18:15:00Z"}, "text": "Already answered: approved from the web chat at 14:15 ET."},
 "conversation.turnFallback": {"slots": {"fallbackReason": "timeout"}, "text": "I couldn't answer that: the model didn't answer within 60 seconds. Nothing was changed."},
 "conversation.dailyCap": {"slots": {"time": "2026-10-17T04:00:00Z", "readmeLink": "https://example.com/ocutalon-readme"}, "text": "The online demo has used today's model allowance. Decisions use fixed rules until Saturday at 00:00 ET. You can install OcuTalon yourself to keep going: https://example.com/ocutalon-readme"},
 "conversation.sessionAllowance": {"slots": {"limit": 50, "time": "2026-10-16T19:02:00Z", "readmeLink": "https://example.com/ocutalon-readme"}, "text": "You've used this session's 50 messages for the hour. You can send more at 15:02 ET, or install OcuTalon yourself to keep going: https://example.com/ocutalon-readme"},
 "fallbackReason.timeout": {"slots": {}, "text": "the model didn't answer within 60 seconds"},
 "fallbackReason.empty": {"slots": {}, "text": "the model's reply was empty"},
 "fallbackReason.cutOff": {"slots": {}, "text": "the model's reply was cut off"},
 "fallbackReason.refusal": {"slots": {}, "text": "the model declined to answer"},
 "fallbackReason.error": {"slots": {}, "text": "the model returned an error"},
 "fallbackReason.rateLimited": {"slots": {}, "text": "the model was busy and retries ran out"},
 "fallbackReason.budget": {"slots": {}, "text": "this would have gone over the token budget"},
 "fallbackReason.tooLarge": {"slots": {}, "text": "this request would have been too large to send"},
 "fallbackReason.dailyCap": {"slots": {}, "text": "today's cost limit has been reached"},
 "fallbackReason.noKey": {"slots": {}, "text": "no model key is set"},
 "fallbackReason.generic": {"slots": {}, "text": "the model's reply couldn't be used"},
 "notice.tellNow": {"slots": {"whatHappened": "Mail from Dana Smith: Invoice 4412 is overdue", "reason": "It mentions a deadline today."}, "text": "Mail from Dana Smith: Invoice 4412 is overdue\nWhy now: It mentions a deadline today."},
 "reminder.due": {"slots": {"text": "Call the vendor."}, "text": "Reminder: Call the vendor."},
 "reminder.late": {"slots": {"time": "2026-10-15T14:00:00Z", "text": "Call the vendor."}, "text": "Reminder (late; it was due on Thursday at 10:00 ET): Call the vendor."},
 "banner.allowance": {"slots": {"limit": 50, "time": "2026-10-16T19:02:00Z"}, "text": "You've used this session's 50 messages for the hour (messages you send in the chat or Telegram). You can send more at 15:02 ET."},
 "banner.dailyCap": {"slots": {"time": "2026-10-17T04:00:00Z"}, "text": "The online demo has used today's model allowance. Decisions use fixed rules until Saturday at 00:00 ET."},
 "banner.unreachable": {"slots": {}, "text": "Can't reach OcuTalon. Retrying every 10 seconds."},
 "banner.noModelKey": {"slots": {}, "text": "OcuTalon has no model key, so every decision uses fixed rules. Add ANTHROPIC_API_KEY to the .env file and restart OcuTalon."},
 "banner.costCap": {"slots": {"cap": 5, "time": "2026-10-17T04:00:00Z"}, "text": "OcuTalon has reached today's cost limit of $5.00. Decisions use fixed rules until Saturday at 00:00 ET."},
 "banner.heartbeatStalled": {"slots": {"time": "2026-10-16T18:15:00Z"}, "text": "Background checks have paused: the heartbeat last ran at 14:15 ET. Watches and reminders may be late until it recovers."},
 "banner.telegramPaused": {"slots": {"time": "2026-10-16T18:30:00Z"}, "text": "Telegram is paused: this bot is in use by another OcuTalon. OcuTalon will try again at 14:30 ET. Each OcuTalon needs its own bot."},
 "banner.resetSoon": {"slots": {}, "text": "The demo resets in 5 minutes. Your session and Telegram pairing will be cleared."},
 "banner.reconnecting": {"slots": {}, "text": "Reconnecting\u2026 New messages may be delayed."},
 "bannerAction.installYourself": {"slots": {}, "text": "Install it yourself"},
 "bannerAction.howToSetKey": {"slots": {}, "text": "How to set a key"},
 "bannerAction.budgets": {"slots": {}, "text": "Budgets"},
 "bannerAction.setUpBot": {"slots": {}, "text": "Set up a bot"},
 "signIn.title": {"slots": {}, "text": "Sign in \u00B7 OcuTalon"},
 "signIn.heading": {"slots": {}, "text": "Sign in to OcuTalon"},
 "signIn.submit": {"slots": {}, "text": "Sign in"},
 "signIn.help": {"slots": {}, "text": "Use the IRIS account your install created; the README lists it."},
 "signIn.errorCredentials": {"slots": {}, "text": "That user name and password didn't work."},
 "signIn.errorNoRole": {"slots": {}, "text": "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it."},
 "signIn.logoAlt": {"slots": {}, "text": "OcuTalon"},
 "signIn.signedOut": {"slots": {}, "text": "You were signed out. Sign in again to continue."},
 "audit.recorded": {"slots": {}, "text": "Recorded in the IRIS audit log."},
 "watch.productionStopped": {"slots": {"production": "Orders", "time": "2026-10-16T18:12:00Z"}, "text": "The Orders production stopped at 14:12 ET.\nWhy now: you asked me to watch the Orders production."},
 "watch.itemDisabled": {"slots": {"itemName": "order importer", "production": "Orders", "time": "2026-10-16T18:12:00Z"}, "text": "The order importer in the Orders production was disabled at 14:12 ET.\nWhy now: you asked me to watch the Orders production."},
 "watch.unknownProduction": {"slots": {"name": "Order", "list": "Orders, Billing"}, "text": "I can't find a production called 'Order'. I can see: Orders, Billing. Which one did you mean?"},
 "watch.onlyOrders": {"slots": {"readmeLink": "https://example.com/ocutalon-readme"}, "text": "On the online demo I can only watch the Orders production. Install OcuTalon to watch your own productions: https://example.com/ocutalon-readme"},
 "agent.noCommands": {"slots": {}, "text": "I can't run commands. I can check productions, read failed messages and propose fixes that wait for your approval."},
 "checks.notEverything": {"slots": {"whatFailed": "the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval"}, "text": "Not everything: the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval."},
 "checks.notEverythingRestPassed": {"slots": {"whatFailed": "the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval"}, "text": "Not everything: the Orders production has 50 failed orders since 14:12 ET, and a fix is waiting for your approval. Everything else I checked passed."},
 "checks.everythingElsePassed": {"slots": {}, "text": "Everything else I checked passed."},
 "checks.allPassed": {"slots": {}, "text": "Everything I checked passed."},
 "checks.nothingWatched": {"slots": {}, "text": "I'm not watching any productions yet, so I can't say. Ask me to watch one."},
 "incident.withFix": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "cause": "The partner changed its date format.", "fixSummary": "repair and resend all 50", "field": "order date", "before": "10/16/2026", "after": "2026-10-16", "resendCount": 50}, "text": "50 orders failed since 14:12 ET. The partner changed its date format. I can repair and resend all 50. Approve?\n\nDry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.", "web": "50 orders failed since 14:12 ET. The partner changed its date format. I can repair and resend all 50.\n\nDry run: 50 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."},
 "incident.laterRequest": {"slots": {"count": 3, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:20:00Z", "fixSummary": "repair and resend all 3", "field": "order date", "before": "10/16/2026", "after": "2026-10-16", "resendCount": 3}, "text": "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?\n\nDry run: 3 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 3 repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page.", "web": "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3.\n\nDry run: 3 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 3 repaired copies; the originals stay unchanged. Nothing has changed yet.\n\nDetails and trace: on your OcuTalon page."},
 "incident.fallback": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "fallbackReason": "timeout", "groups": [{"itemName": "OrdersFromPartner", "count": 50, "errorSummary": "The order date was not in the expected format", "firstAt": "2026-10-16T18:12:00Z"}]}, "text": "50 orders failed since 14:12 ET. I couldn't work out the cause (the model didn't answer within 60 seconds), so I'm not proposing a fix. Nothing was changed.\n\nFailures:\nOrdersFromPartner: 50, 'The order date was not in the expected format', first at 14:12 ET\n\nDetails and trace: on your OcuTalon page."},
 "incident.noFix": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "cause": "The partner now requires a signed header.", "groups": [{"itemName": "OrdersFromPartner", "count": 50, "errorSummary": "The order date was not in the expected format", "firstAt": "2026-10-16T18:12:00Z"}]}, "text": "50 orders failed since 14:12 ET. The partner now requires a signed header. None of my fixes applies to this, so I'm not proposing one. Nothing was changed.\n\nFailures:\nOrdersFromPartner: 50, 'The order date was not in the expected format', first at 14:12 ET\n\nDetails and trace: on your OcuTalon page."},
 "incident.noFixUnknown": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "time": "2026-10-16T18:12:00Z", "groups": [{"itemName": "OrdersFromPartner", "count": 50, "errorSummary": "The order date was not in the expected format", "firstAt": "2026-10-16T18:12:00Z"}]}, "text": "50 orders failed since 14:12 ET. I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.\n\nFailures:\nOrdersFromPartner: 50, 'The order date was not in the expected format', first at 14:12 ET\n\nDetails and trace: on your OcuTalon page."},
 "result.allThrough": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}}, "text": "All 50 orders went through."},
 "result.failedAgain": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 48, "failedAgain": 2, "failReason": "the order date still wasn't accepted"}, "text": "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval."},
 "result.skipped": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 47, "skipped": 3}, "text": "47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval."},
 "result.failedAndSkipped": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 45, "failedAgain": 2, "failReason": "the order date still wasn't accepted", "skipped": 3}, "text": "45 of 50 orders went through. 2 failed again (the order date still wasn't accepted), and 3 had changed since the dry run, so I skipped them. I won't retry any of them without a new approval."},
 "result.stillResending": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 30}, "text": "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done."},
 "result.interrupted": {"slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "completed": 30, "remaining": 20}, "text": "The resend stopped when OcuTalon restarted: 30 of 50 orders went through. The other 20 need a new approval."},
 "result.couldNotStart": {"slots": {"reason": "OcuTalon isn't allowed to resend messages in that production"}, "text": "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."}
}
}

}
