/// Tests of what an incident notice says (Story 5.8; AD-8, AD-15, AD-31, AD-32), over unsaved fixture rows: OcuTalon.Watch.Notice (the key, the open variant and
/// the slots of each variant, with the with-fix builder), the catalog text that those slots render to (OcuTalon.Msg.Catalog.RenderAt with a fixed clock; the
/// expected times come from OcuTalon.Data.Time.ForMessage, so the tests hold in any zone) and OcuTalon.Watch.ErrorText Text and Summary (DW-261). They need no
/// production and no namespace, so a warm stack runs them. They write nothing.
///   - TestKeysAndVariants: a fallback of any reason is incident.fallback with the variant fallback; unknown is incident.noFixUnknown and no_fix; a usable data-format
///     diagnosis has no key and no variant (its notice is the with-fix notice of Story 7.2); any other category is incident.noFix and no_fix;
///   - TestNoFix, TestUnknown, TestFallback and TestWithFix: each variant's slots rendered: the no-fix text exactly as the epics criterion states it, then the
///     unknown text's first line, the fallback text for each reason (an empty or unknown reason gives unusable) and the UJ-1 text of the with-fix builder's slots
///     plus the dry run's;
///   - TestEveryChannel: every variant renders on web, phone, mailbox and telegram;
///   - TestGroupLines: two groups give two lines in order, a group with no NoticeCount is left out, an empty error summary is written as no error text, and each line's
///     count is the group's NoticeCount;
///   - TestCountAndNoun: count is the NoticeCount, not the Count, and the noun falls back to message/messages when the row has none or it cannot be read;
///   - TestCannotBuild: slots that cannot be built (no group that settled, an empty cause, no first failure time) give "" and an error;
///   - TestErrorText and TestSummary: Text redacts and gives the error's own sentence, Summary is the first sentence of it, at most 80 characters, a longer one cut
///     at a word with U+2026, an empty text gives "", and Summary(Text(raw)) equals Summary(raw).
Class OcuTalon.Test.Watch.NoticeText Extends %UnitTest.TestCase
{

Parameter NOTICE = "OcuTalon.Watch.Notice";

Parameter TEXT = "OcuTalon.Watch.ErrorText";

/// The clock of the renders, and the first failure's time and a later group's, all UTC.
Parameter NOW = "2026-10-25T12:30:00Z";

Parameter FIRST = "2026-10-25T12:00:00Z";

Parameter SECOND = "2026-10-25T12:10:00Z";

Parameter CAUSE = "The partner now sends the order date as month, day and year with slashes";

Parameter SENTENCE = "The order date was not in the expected format.";

/// An incident row (not saved): 52 failures of which 50 settled, the order noun, and the category, fallback and reason given.
ClassMethod Row(category As %String, fallback As %Boolean = 0, reason As %String = "") As OcuTalon.Data.Incident
{
	Set row = ##class(OcuTalon.Data.Incident).%New()
	Set row.Ref = "zzNoticeTextRef"
	Set row.Count = 52
	Set row.NoticeCount = 50
	Set row.FirstAt = ..#FIRST
	Set row.ItemNoun = "{""one"":""order"",""other"":""orders""}"
	Set row.CauseCategory = category
	Set row.Fallback = fallback
	Set row.FallbackReason = reason
	If 'fallback {
		Set row.Cause = ..#CAUSE_"."
		Set row.FixSummary = "rewrite the order date of the failed orders and send them again"
	}
	Quit row
}

/// A group (not saved).
ClassMethod Group(seq As %Integer, item As %String, noticeCount As %Integer, summary As %String, firstAt As %String) As OcuTalon.Data.FailureGroup
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.Seq = seq
	Set group.ItemName = item
	Set group.NoticeCount = noticeCount
	Set group.Count = noticeCount
	Set group.ErrorSummary = summary
	Set group.FirstAt = firstAt
	Quit group
}

/// The groups of a notice: two that settled and one that did not.
ClassMethod Groups() As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	Do list.Insert(..Group(1, "OrdersFromPartner", 30, ..#SENTENCE, ..#FIRST))
	Do list.Insert(..Group(2, "OrdersToWarehouse", 20, "", ..#SECOND))
	Do list.Insert(..Group(3, "OrdersLate", "", "Joined after the settle.", ..#SECOND))
	Quit list
}

/// The time as a message shows it at the fixed clock: "12:00", or "Sunday at 12:00" when it is not the clock's day.
ClassMethod When(utc As %String) As %String
{
	Set time = ##class(OcuTalon.Data.Time).ForMessage(utc, ..#NOW)
	Quit time
}

/// "first at <time>" as the group line writes it: "at" becomes "on" when the time carries a day or a date.
ClassMethod FirstAt(utc As %String) As %String
{
	Set time = ..When(utc)
	Quit $Select(time ? 2N1":"2N: "first at ", 1: "first on ")_time
}

/// The two group lines the fixture Groups give.
ClassMethod Lines() As %String
{
	Quit "OrdersFromPartner: 30, '"_..#SENTENCE_"', "_..FirstAt(..#FIRST)_$Char(10)_"OrdersToWarehouse: 20, 'no error text', "_..FirstAt(..#SECOND)
}

/// The slots as JSON text of the notice for the row, with the status asserted.
Method SlotsOf(row As OcuTalon.Data.Incident, label As %String) As %DynamicObject
{
	Set slots = $ClassMethod(..#NOTICE, "Slots", row, ..Groups(), .sc)
	Do $$$AssertStatusOK(sc, label_": the slots are built")
	Quit $Select($$$ISOK(sc): slots, 1: "")
}

/// The text of the key for the slots on the channel, with the status asserted.
Method Render(key As %String, slots As %DynamicObject, channel As %String = "phone") As %String
{
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), channel, ..#NOW, 0, .sc)
	Do $$$AssertStatusOK(sc, key_" on "_channel_" renders")
	Quit text
}

Method TestKeysAndVariants()
{
	Set fallbacks = $ListBuild("", "timeout", "error", "refusal", "invalid", "zz")
	Set position = 0
	While $ListNext(fallbacks, position, reason) {
		Set row = ..Row("", 1, reason)
		Do $$$AssertEquals($ClassMethod(..#NOTICE, "Key", row)_"|"_$ClassMethod(..#NOTICE, "Variant", row), "incident.fallback|fallback", "a fallback with the reason '"_reason_"'")
	}
	Set row = ..Row("unknown")
	Do $$$AssertEquals($ClassMethod(..#NOTICE, "Key", row)_"|"_$ClassMethod(..#NOTICE, "Variant", row), "incident.noFixUnknown|no_fix", "unknown")
	Set row = ..Row("data_format_change")
	Do $$$AssertEquals($ClassMethod(..#NOTICE, "Key", row)_"|"_$ClassMethod(..#NOTICE, "Variant", row), "|", "a usable data-format diagnosis has a fix, so it has no key and no variant here")
	Set slots = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc)
	Do $$$AssertEquals($Select($IsObject(slots): slots.count, 1: ""), 50, "its with-fix slots are the builder's")
	For category = "partner_outage", "config_error", "other", "" {
		Set row = ..Row(category)
		Do $$$AssertEquals($ClassMethod(..#NOTICE, "Key", row)_"|"_$ClassMethod(..#NOTICE, "Variant", row), "incident.noFix|no_fix", "the category '"_category_"' has no fix")
	}
}

Method TestNoFix()
{
	Set row = ..Row("partner_outage")
	Set slots = ..SlotsOf(row, "no fix")
	If '$IsObject(slots) Quit
	Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.cause_"|"_slots.itemNoun.one_"|"_slots.itemNoun.other_"|"_slots.groups.%Size(), "50|"_..#FIRST_"|"_..#CAUSE_".|order|orders|2", "count, time, cause, noun and two groups")
	Set expected = "50 orders failed since "_..When(..#FIRST)_". "_..#CAUSE_". None of my fixes applies to this, so I'm not proposing one. Nothing was changed."_$Char(10, 10)_"Failures:"_$Char(10)_..Lines()_$Char(10, 10)_"Details and trace: on your OcuTalon page."
	Do $$$AssertEquals(..Render("incident.noFix", slots, "phone"), expected, "the no-fix text, exactly")
	Do $$$AssertEquals(..Render("incident.noFix", slots, "web"), expected, "and on the web")
}

Method TestUnknown()
{
	Set row = ..Row("unknown")
	Set slots = ..SlotsOf(row, "unknown")
	If '$IsObject(slots) Quit
	Do $$$AssertEquals(slots.%IsDefined("cause"), 0, "there is no cause slot")
	Set text = ..Render("incident.noFixUnknown", slots)
	Set first = "50 orders failed since "_..When(..#FIRST)_". I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed."
	Do $$$AssertEquals($Piece(text, $Char(10), 1), first, "the first line")
	Do $$$AssertEquals($Piece(text, $Char(10), 3, *), "Failures:"_$Char(10)_..Lines()_$Char(10, 10)_"Details and trace: on your OcuTalon page.", "then the failures and the pointer")
}

Method TestFallback()
{
	Set reasons = $ListBuild($ListBuild("timeout", "timeout", "the model didn't answer within 60 seconds"), $ListBuild("error", "error", "the model returned an error"), $ListBuild("refusal", "refusal", "the model declined to answer"), $ListBuild("invalid", "invalid", "the model's reply couldn't be used"), $ListBuild("", "unusable", "the model's reply couldn't be used"), $ListBuild("zz", "unusable", "the model's reply couldn't be used"))
	Set position = 0
	While $ListNext(reasons, position, each) {
		Set row = ..Row("", 1, $List(each, 1))
		Set slots = ..SlotsOf(row, "fallback '"_$List(each, 1)_"'")
		If '$IsObject(slots) Continue
		Do $$$AssertEquals(slots.fallbackReason, $List(each, 2), "the reason '"_$List(each, 1)_"' is passed as "_$List(each, 2))
		Do $$$AssertEquals(slots.%IsDefined("cause"), 0, "there is no cause slot")
		Set expected = "50 orders failed since "_..When(..#FIRST)_". I couldn't work out the cause ("_$List(each, 3)_"), so I'm not proposing a fix. Nothing was changed."_$Char(10, 10)_"Failures:"_$Char(10)_..Lines()_$Char(10, 10)_"Details and trace: on your OcuTalon page."
		Do $$$AssertEquals(..Render("incident.fallback", slots), expected, "the fallback text for the reason '"_$List(each, 1)_"'")
	}
}

Method TestWithFix()
{
	Set row = ..Row("data_format_change")
	Set slots = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc)
	Do $$$AssertStatusOK(sc, "the with-fix slots are built")
	If '$IsObject(slots) Quit
	Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.cause_"|"_slots.fixSummary_"|"_slots.itemNoun.other, "50|"_..#FIRST_"|"_..#CAUSE_".|rewrite the order date of the failed orders and send them again|orders", "count, time, cause, fix summary and noun")
	Do $$$AssertEquals(slots.%IsDefined("groups"), 0, "and no groups")
	Do slots.%Set("field", "OrderDate")
	Do slots.%Set("before", "10/16/2026")
	Do slots.%Set("after", "2026-10-16")
	Do slots.%Set("resendCount", 50, "number")
	Set head = "50 orders failed since "_..When(..#FIRST)_". "_..#CAUSE_". I can rewrite the order date of the failed orders and send them again"
	Set dry = $Char(10, 10)_"Dry run: 50 orders affected. Example: OrderDate 10/16/2026 becomes 2026-10-16. I'll resend 50 repaired copies; the originals stay unchanged. Nothing has changed yet."_$Char(10, 10)_"Details and trace: on your OcuTalon page."
	Do $$$AssertEquals(..Render("incident.withFix", slots, "phone"), head_". Approve?"_dry, "the UJ-1 notice text")
	Do $$$AssertEquals(..Render("incident.withFix", slots, "web"), head_"."_dry, "and its page wording, which has no question")
}

Method TestEveryChannel()
{
	For case = 1:1:3 {
		Set row = $Select(case = 1: ..Row("partner_outage"), case = 2: ..Row("unknown"), 1: ..Row("", 1, "timeout"))
		Set key = $Select(case = 1: "incident.noFix", case = 2: "incident.noFixUnknown", 1: "incident.fallback")
		Set slots = ..SlotsOf(row, key)
		If '$IsObject(slots) Continue
		For channel = "web", "phone", "mailbox", "telegram" {
			Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), channel, ..#NOW, 0, .sc)
			Do $$$AssertTrue($$$ISOK(sc) && (text [ "Failures:"), key_" renders on "_channel)
		}
	}
	Set slots = $ClassMethod(..#NOTICE, "WithFixSlots", ..Row("data_format_change"), .sc)
	Do slots.%Set("field", "OrderDate")
	Do slots.%Set("before", "10/16/2026")
	Do slots.%Set("after", "2026-10-16")
	Do slots.%Set("resendCount", 50, "number")
	For channel = "web", "phone", "mailbox", "telegram" {
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.withFix", slots.%ToJSON(), channel, ..#NOW, 0, .sc)
		Do $$$AssertTrue($$$ISOK(sc) && (text [ "Dry run:"), "incident.withFix renders on "_channel)
	}
}

Method TestGroupLines()
{
	Set lines = $ClassMethod(..#NOTICE, "Groups", ..Row("partner_outage"), ..Groups(), .sc)
	Do $$$AssertStatusOK(sc, "the groups are built")
	If '$IsObject(lines) Quit
	Do $$$AssertEquals(lines.%Size(), 2, "two groups: the one without a NoticeCount is left out")
	Do $$$AssertEquals(lines.%Get(0).itemName_"|"_lines.%Get(0).count_"|"_lines.%Get(0).errorSummary_"|"_lines.%Get(0).firstAt, "OrdersFromPartner|30|"_..#SENTENCE_"|"_..#FIRST, "the first group, in Seq order")
	Do $$$AssertEquals(lines.%Get(1).itemName_"|"_lines.%Get(1).count_"|"_lines.%Get(1).errorSummary_"|"_lines.%Get(1).firstAt, "OrdersToWarehouse|20|no error text|"_..#SECOND, "the second, with the fixed value for an empty summary")
	Do $$$AssertEquals(lines.%Get(0).count + lines.%Get(1).count, 50, "the lines add up to the count slot")
}

Method TestCountAndNoun()
{
	Set row = ..Row("partner_outage")
	Set row.NoticeCount = 50
	Set row.Count = 52
	Set slots = ..SlotsOf(row, "moved count")
	If '$IsObject(slots) Quit
	Do $$$AssertEquals(slots.count, 50, "count is the NoticeCount, not the Count that moved on")
	Set row.ItemNoun = ""
	Set row.NoticeCount = 1
	Set one = ..SlotsOf(row, "no noun")
	If $IsObject(one) Do $$$AssertEquals(one.itemNoun.one_"|"_one.itemNoun.other, "message|messages", "no noun gives message and messages")
	Set row.ItemNoun = "not json"
	Set bad = ..SlotsOf(row, "bad noun")
	If $IsObject(bad) Do $$$AssertEquals(bad.itemNoun.one_"|"_bad.itemNoun.other, "message|messages", "so does one that cannot be read")
	Set groups = ##class(%ListOfObjects).%New()
	Do groups.Insert(..Group(1, "OrdersFromPartner", 1, ..#SENTENCE, ..#FIRST))
	Set single = $ClassMethod(..#NOTICE, "Slots", row, groups, .sc)
	If $IsObject(single) Do $$$AssertEquals($Piece(..Render("incident.noFix", single), ". ", 1), "1 message failed since "_..When(..#FIRST), "a count of one reads in the singular")
	Set row.NoticeCount = ""
	Set fromCount = ..SlotsOf(row, "no NoticeCount")
	If $IsObject(fromCount) Do $$$AssertEquals(fromCount.count, 52, "a row with no NoticeCount gives its Count")
}

Method TestCannotBuild()
{
	Set empty = ##class(%ListOfObjects).%New()
	Set slots = $ClassMethod(..#NOTICE, "Slots", ..Row("partner_outage"), empty, .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "no group gives no slots")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set unsettled = ##class(%ListOfObjects).%New()
	Do unsettled.Insert(..Group(1, "OrdersFromPartner", "", ..#SENTENCE, ..#FIRST))
	Set slots = $ClassMethod(..#NOTICE, "Slots", ..Row("partner_outage"), unsettled, .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "a group that did not settle is no group")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set row = ..Row("partner_outage")
	Set row.Cause = ""
	Set slots = $ClassMethod(..#NOTICE, "Slots", row, ..Groups(), .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "an empty cause gives no slots")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set row = ..Row("", 1, "timeout")
	Set row.FirstAt = ""
	Set slots = $ClassMethod(..#NOTICE, "Slots", row, ..Groups(), .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "no first failure time gives no slots")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set slots = $ClassMethod(..#NOTICE, "Slots", ..Row("data_format_change"), ..Groups(), .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "a diagnosis with a fix has no slots of its own here")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set row = ..Row("data_format_change")
	Set row.FixSummary = ""
	Set slots = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc)
	Do $$$AssertEquals($IsObject(slots), 0, "the with-fix builder needs the fix summary")
	Do $$$AssertStatusNotOK(sc, "and gives an error")
}

Method TestErrorText()
{
	Set mark = ##class(OcuTalon.Bridge.Redact).#REDACTED
	Set secret = "sk-"_"ant-api03-ABCDEFGHIJKLMNOPQRSTUV"
	Set wrapped = "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: The partner key "_secret_" was refused."_$Char(13, 10)_"  > ERROR #5001: again"
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Text", wrapped), "The partner key "_mark_" was refused.", "Text gives the error's own sentence, redacted")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Text", wrapped), $ClassMethod(..#TEXT, "Sentence", ##class(OcuTalon.Bridge.Redact).Text(wrapped)), "it is Sentence of the redacted text")
	Set own = ..#SENTENCE_" Expected YYYY-MM-DD, got '10/16/2026'."
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Text", "ERROR #5001: "_own), own, "a plain error text loses its prefix")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Text", $ClassMethod(..#TEXT, "Text", wrapped)), $ClassMethod(..#TEXT, "Text", wrapped), "and Text of a text that is already Text changes nothing")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Text", ""), "", "an empty text gives an empty text")
}

Method TestSummary()
{
	Set mark = ##class(OcuTalon.Bridge.Redact).#REDACTED
	Set secret = "sk-"_"ant-api03-ABCDEFGHIJKLMNOPQRSTUV"
	Set wrapped = "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: The partner key "_secret_" was refused."
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", wrapped), "The partner key "_mark_" was refused.", "a wrapped error with a token gives its redacted own sentence")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", "The first one. The second one."), "The first one.", "two sentences give the first")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", "Why did it fail? Nobody knows. Really."), "Why did it fail?", "a question mark ends a sentence")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", "It failed! Badly."), "It failed!", "so does an exclamation mark")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", ..#SENTENCE_" Expected YYYY-MM-DD, got '10/16/2026'."), ..#SENTENCE, "the measured sentence gives its first sentence")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", "No full stop here"), "No full stop here", "a text with no sentence end is whole")
	Set words = ""
	For letter = "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l" {
		Set words = words_$Select(words = "": "", 1: " ")_$Translate($Justify("", 9), " ", letter)
	}
	Do $$$AssertEquals($Length(words), 119, "the long sentence has 119 characters")
	Set cut = $ClassMethod(..#TEXT, "Summary", words_".")
	Do $$$AssertEquals(cut, "aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeeeeeee fffffffff ggggggggg"_$Char(8230), "it is cut at its last space within 79 characters and ends with U+2026")
	Do $$$AssertTrue($Length(cut) '> 80, "at most 80 characters")
	Set exact = $Extract(words, 1, 79)_"."
	Do $$$AssertEquals($Length(exact), 80, "a sentence of exactly 80 characters")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", exact), exact, "is kept whole")
	Set nospace = $Translate($Justify("", 100), " ", "x")
	Set cut = $ClassMethod(..#TEXT, "Summary", nospace)
	Do $$$AssertEquals($Length(cut)_"|"_$Extract(cut, *), "80|"_$Char(8230), "a long word is cut at 79 characters and ends with U+2026")
	Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", ""), "", "an empty text gives an empty summary")
	For raw = wrapped, "ERROR #5001: "_words_". More.", "Terminating BP X # due to error: ERROR #5001: One. Two.", "" {
		Do $$$AssertEquals($ClassMethod(..#TEXT, "Summary", $ClassMethod(..#TEXT, "Text", raw)), $ClassMethod(..#TEXT, "Summary", raw), "Summary of Text equals Summary of the raw text: "_$Extract(raw, 1, 30))
	}
}

}
