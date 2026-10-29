/// Tests of what an incident notice says (Story 5.8; AD-8, AD-15, AD-31, AD-32), over unsaved fixture rows: OcuTalon.Watch.Notice (the key, the open variant and
/// the slots of each variant, with the with-fix builder), the catalog text that those slots render to (OcuTalon.Msg.Catalog.RenderAt with a fixed clock; the
/// expected times come from OcuTalon.Data.Time.ForMessage, so the tests hold in any zone) and OcuTalon.Watch.ErrorText Text and Summary (DW-261). They need no
/// production and no namespace, so a warm stack runs them. They write nothing.
///   - TestKeysAndVariants: a fallback of any reason is incident.fallback with the variant fallback; unknown is incident.noFixUnknown and no_fix; a usable data-format
///     diagnosis has no key and no variant (its notice is the with-fix notice of Story 7.2); any other category is incident.noFix and no_fix;
///   - TestNoFix, TestUnknown, TestFallback and TestWithFix: each variant's slots rendered: the no-fix text exactly as the epics criterion states it, then the
///     unknown text's first line, the fallback text for each reason (an empty or unknown reason gives unusable) and the UJ-1 text of the with-fix builder's slots
///     plus the dry run's (Story 7.2: the builder given a dry run adds field, before, after and resendCount and refuses a dry run without a field, a before or an after or
///     with a resend below 1; Slots given the key incident.noFix builds the no-fix slots of a data-format row);
///   - TestLaterRequest (Story 7.6; AC 5): WithFixSlots given a count and a time (the round's) replaces the count and time slots; the slots of the UX fixture's
///     values render the text of incident.laterRequest in the fixture exactly (telegram, and the page wording on the web), and a count of 0 or one that is no
///     whole number and an empty time are refused;
///   - TestResultKeys (Story 7.3; AC 5): Notice.ResultKey picks the catalog key of a final or interrupted FixResult by the Result texts convention, row by row and in
///     the order of the convention (a request that is executing first, then an interrupted run, then a run that resent, completed, failed and skipped nothing and
///     has a reason, then failures with skips, failures, skips, and else all through); Notice.ResultSlots gives the slots that each of the seven keys declares, and
///     they and the text they render are the UX fixtures' exactly (among them "Nothing was resent: OcuTalon isn't allowed to resend messages in that production.
///     Nothing was changed." and "All 50 orders went through."); an empty count is 0, remaining is at least 0, and slots that cannot be built (no reason where the
///     key renders one, a noun without both forms, a key that is no result key) give "" and an error;
///   - TestApprovedText (Story 7.3; AC 1): answered.approved renders "Approved from the web chat at 14:20 ET." (the page wording has no full stop);
///   - TestEveryChannel: every variant renders on web, phone, mailbox and telegram;
///   - TestGroupLines: two groups give two lines in order, a group with no NoticeCount is left out, an empty error summary is written as no error text, and each line's
///     count is the group's NoticeCount, not its Count that moved on, so the lines add up to the count slot;
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

/// The zone of the fixture clock of the UX text of the later request: Friday 2026-10-16 at 14:20 in America/New_York.
Parameter ZONE = "America/New_York";

/// The TZ of the process before TestLaterRequest set the fixture zone (-1 when it was undefined), with ZoneSaved 1 while it is changed.
Property SavedZone As %String;

Property ZoneSaved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..ZoneSaved {
		Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
		Set ..ZoneSaved = 0
	}
	Quit $$$OK
}

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

/// A group (not saved): count failures (noticeCount when count is empty), of which noticeCount settled with the notice.
ClassMethod Group(seq As %Integer, item As %String, noticeCount As %Integer, summary As %String, firstAt As %String, count As %Integer = "") As OcuTalon.Data.FailureGroup
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.Seq = seq
	Set group.ItemName = item
	Set group.NoticeCount = noticeCount
	Set group.Count = $Select(count '= "": count, 1: noticeCount)
	Set group.ErrorSummary = summary
	Set group.FirstAt = firstAt
	Quit group
}

/// The groups of a notice: two that settled (the first has gained a failure since, so its Count is 31 against its NoticeCount of 30) and one that did not,
/// 52 failures in all, as the Row.
ClassMethod Groups() As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	Do list.Insert(..Group(1, "OrdersFromPartner", 30, ..#SENTENCE, ..#FIRST, 31))
	Do list.Insert(..Group(2, "OrdersToWarehouse", 20, "", ..#SECOND))
	Do list.Insert(..Group(3, "OrdersLate", "", "Joined after the settle.", ..#SECOND, 1))
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

/// A FixResult with the properties of the object set (Final, Interrupted, Total, Resent, Completed, FailedAgain, Skipped, Reason).
ClassMethod Result(fields As %DynamicObject) As OcuTalon.Fix.Msg.FixResult
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = "zzNoticeTextRequest01"
	Set result.IncidentRef = "zzNoticeTextRef"
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set $Property(result, name) = value
	}
	Quit result
}

/// Asserts the key that ResultKey gives for the state of the request's row and the result.
Method AssertKey(state As %String, fields As %DynamicObject, key As %String, label As %String)
{
	Do $$$AssertEquals($ClassMethod(..#NOTICE, "ResultKey", state, ..Result(fields)), key, label_": "_key)
}

/// The members of the object (slots) as "name=value,..." in name order, an object value as its JSON text.
ClassMethod Flat(slots As %DynamicObject) As %String
{
	If '$IsObject(slots) Quit "<none>"
	Set iterator = slots.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set sorted(name) = $Select($IsObject(value): value.%ToJSON(), 1: value)
	}
	Set text = ""
	Set name = ""
	For {
		Set name = $Order(sorted(name), 1, value)
		Quit:name=""
		Set text = text _ $Select(text = "": "", 1: ",") _ name _ "=" _ value
	}
	Quit text
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
	Set dryRun = {"affected": 50, "resend": 50, "leftOut": 0, "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16", "itemNoun": {"one": "order", "other": "orders"}}
	Set built = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, dryRun)
	Do $$$AssertStatusOK(sc, "the slots are built from a dry run")
	If $IsObject(built) {
		Do $$$AssertEquals(built.field_"|"_built.before_"|"_built.after_"|"_built.resendCount_"|"_built.%GetTypeOf("resendCount"), "OrderDate|10/16/2026|2026-10-16|50|number", "which adds field, before, after and resendCount as an integer")
		Do $$$AssertEquals(built.%ToJSON(), slots.%ToJSON(), "and they are the slots of the UJ-1 text")
		Do $$$AssertEquals(..Render("incident.withFix", built, "phone"), head_". Approve?"_dry, "which renders as the UJ-1 notice text")
	}
	Set odd = {"affected": 50, "resend": 1, "leftOut": 0, "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16"}
	Set built = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, odd)
	Do $$$AssertStatusOK(sc, "a resend of 1 is built")
	If $IsObject(built) Do $$$AssertEquals(built.resendCount, 1, "as a count of 1")
	Set bad = {"affected": 50, "resend": 50, "leftOut": 0, "before": "10/16/2026", "after": "2026-10-16"}
	Set built = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, bad)
	Do $$$AssertStatusNotOK(sc, "a dry run without a field is refused")
	Do $$$AssertEquals($IsObject(built), 0, "and gives no slots")
	For key = "before", "after" {
		Set bad = {"resend": 50, "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16"}
		Do bad.%Remove(key)
		Do $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, bad)
		Do $$$AssertStatusNotOK(sc, "a dry run without "_key_" is refused")
	}
	For resend = 0, -1, "x", "" {
		Set bad = {"resend": (resend), "field": "OrderDate", "before": "10/16/2026", "after": "2026-10-16"}
		Do $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, bad)
		Do $$$AssertStatusNotOK(sc, "a dry run that resends '"_resend_"' is refused")
	}
	Set forced = $ClassMethod(..#NOTICE, "Slots", row, ..Groups(), .sc, $Parameter(..#NOTICE, "KEYNOFIX"))
	Do $$$AssertStatusOK(sc, "the no-fix slots of a data-format row are built when the key is given")
	If $IsObject(forced) Do $$$AssertEquals(forced.cause_"|"_forced.groups.%Size()_"|"_forced.count, ..#CAUSE_".|2|50", "with the cause and the groups")
	Do $ClassMethod(..#NOTICE, "Slots", row, ..Groups(), .sc)
	Do $$$AssertStatusNotOK(sc, "and are refused without it")
}

Method TestLaterRequest()
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Set ..ZoneSaved = 1
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Set fixture = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Test.Msg.Catalog||Fixtures").Data).%Get("incident.laterRequest")
	Set row = ..Row("data_format_change")
	Set row.FixSummary = "repair and resend all 3"
	Set dryRun = {"affected": 3, "resend": 3, "leftOut": 0, "field": "order date", "before": "10/16/2026", "after": "2026-10-16"}
	Set slots = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, dryRun, 3, "2026-10-16T18:20:00Z")
	Do $$$AssertStatusOK(sc, "the later slots are built")
	If '$IsObject(slots) Quit
	Do $$$AssertEquals(slots.count_"|"_slots.%GetTypeOf("count")_"|"_slots.time_"|"_slots.resendCount_"|"_slots.fixSummary_"|"_slots.itemNoun.other, "3|number|2026-10-16T18:20:00Z|3|repair and resend all 3|orders", "the given count and time replace the row's, and the dry run adds its slots")
	Do $$$AssertEquals($Parameter(..#NOTICE, "KEYLATER"), "incident.laterRequest", "the key is the later request's")
	Set telegram = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.laterRequest", slots.%ToJSON(), "telegram", "2026-10-16T18:20:00Z", 1, .sc)
	Do $$$AssertStatusOK(sc, "it renders on telegram")
	Do $$$AssertEquals(telegram, fixture.text, "the text is the UX fixture's exactly")
	Do $$$AssertEquals(telegram, "3 more orders failed since 14:20 ET, with the same cause. I can repair and resend all 3. Approve?"_$Char(10, 10)_"Dry run: 3 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 3 repaired copies; the originals stay unchanged. Nothing has changed yet."_$Char(10, 10)_"Details and trace: on your OcuTalon page.", "as the epics criterion states it")
	Set web = ##class(OcuTalon.Msg.Catalog).RenderAt("incident.laterRequest", slots.%ToJSON(), "web", "2026-10-16T18:20:00Z", 1, .sc)
	Do $$$AssertEquals(web, fixture.web, "and the page wording is the fixture's web text")
	Set own = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, dryRun)
	Do $$$AssertStatusOK(sc, "the slots without a count and a time are built")
	If $IsObject(own) Do $$$AssertEquals(own.count_"|"_own.time, "50|"_..#FIRST, "and take the row's NoticeCount and FirstAt")
	For count = 0, -1, "x", "1.5", "" {
		Set none = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, dryRun, count, "2026-10-16T18:20:00Z")
		Do $$$AssertStatusNotOK(sc, "a count of '"_count_"' is refused")
		Do $$$AssertEquals($IsObject(none), 0, "and gives no slots")
	}
	Set none = $ClassMethod(..#NOTICE, "WithFixSlots", row, .sc, dryRun, 3, "")
	Do $$$AssertStatusNotOK(sc, "an empty time is refused")
	Do $$$AssertEquals($IsObject(none), 0, "and gives no slots")
}

Method TestResultKeys()
{
	Set fixtures = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Test.Msg.Catalog||Fixtures").Data)
	Set noun = fixtures.%Get("result.allThrough").slots.itemNoun
	Set reason = "OcuTalon isn't allowed to resend messages in that production"

	// the convention, first match wins
	Do ..AssertKey("executing", {"Final": 1, "Total": 50, "Completed": 30}, "result.stillResending", "the request is executing")
	Do ..AssertKey("executing", {"Interrupted": 1, "Total": 50, "Completed": 30}, "result.stillResending", "the request is executing, whatever else the result says")
	Do ..AssertKey("failed", {"Interrupted": 1, "Total": 50, "Completed": 30}, "result.interrupted", "the run was interrupted")
	Do ..AssertKey("failed", {"Interrupted": 1, "Total": 3, "Reason": (reason)}, "result.interrupted", "interrupted comes before couldn't start")
	Do ..AssertKey("failed", {"Final": 1, "Total": 3, "Reason": (reason)}, "result.couldNotStart", "every count 0 and a reason")
	Do ..AssertKey("done", {"Final": 1, "Total": 3, "Skipped": 3, "Reason": "message 101 changed"}, "result.skipped", "a reason with skipped targets is not couldn't start")
	Do ..AssertKey("done", {"Final": 1, "Total": 3, "Resent": 3, "Reason": "x"}, "result.allThrough", "a reason with resent targets is not couldn't start")
	Do ..AssertKey("failed", {"Final": 1, "Total": 3}, "result.allThrough", "every count 0 and no reason is not couldn't start")
	Do ..AssertKey("done", {"Final": 1, "Total": 50, "Completed": 45, "FailedAgain": 2, "Skipped": 3, "Reason": "x"}, "result.failedAndSkipped", "failures and skips")
	Do ..AssertKey("done", {"Final": 1, "Total": 50, "Completed": 48, "FailedAgain": 2, "Reason": "x"}, "result.failedAgain", "failures")
	Do ..AssertKey("done", {"Final": 1, "Total": 50, "Completed": 47, "Skipped": 3}, "result.skipped", "skips")
	Do ..AssertKey("done", {"Final": 1, "Total": 50, "Resent": 50, "Completed": 50}, "result.allThrough", "otherwise all through")

	// the slots and the texts of the UX fixtures
	Set cases = $ListBuild(
		$ListBuild("result.allThrough", "done", "{""Final"":1,""Total"":50,""Resent"":50,""Completed"":50}"),
		$ListBuild("result.failedAgain", "done", "{""Final"":1,""Total"":50,""Resent"":50,""Completed"":48,""FailedAgain"":2,""Reason"":""the order date still wasn't accepted""}"),
		$ListBuild("result.skipped", "done", "{""Final"":1,""Total"":50,""Resent"":47,""Completed"":47,""Skipped"":3,""Reason"":""message 101 changed""}"),
		$ListBuild("result.failedAndSkipped", "done", "{""Final"":1,""Total"":50,""Resent"":47,""Completed"":45,""FailedAgain"":2,""Skipped"":3,""Reason"":""the order date still wasn't accepted""}"),
		$ListBuild("result.stillResending", "executing", "{""Total"":50,""Resent"":50,""Completed"":30}"),
		$ListBuild("result.interrupted", "failed", "{""Interrupted"":1,""Total"":50,""Resent"":50,""Completed"":30}"),
		$ListBuild("result.couldNotStart", "failed", "{""Final"":1,""Total"":3,""Reason"":"""_reason_"""}"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set key = $List(case, 1)
		Set result = ..Result({}.%FromJSON($List(case, 3)))
		Do $$$AssertEquals($ClassMethod(..#NOTICE, "ResultKey", $List(case, 2), result), key, key_": the key of the fixture's result")
		Set slots = $ClassMethod(..#NOTICE, "ResultSlots", key, result, noun, .sc)
		Do $$$AssertStatusOK(sc, key_": the slots are built")
		If '$IsObject(slots) Continue
		Set fixture = fixtures.%Get(key)
		Do $$$AssertEquals(..Flat(slots), ..Flat(fixture.slots), key_": the slots are the fixture's")
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots.%ToJSON(), "telegram", ..#NOW, 1, .sc)
		Do $$$AssertStatusOK(sc, key_": renders")
		Do $$$AssertEquals(text, fixture.text, key_": the text is the fixture's exactly")
	}
	Set slots = $ClassMethod(..#NOTICE, "ResultSlots", "result.couldNotStart", ..Result({"Final": 1, "Total": 3, "Reason": (reason)}), noun, .sc)
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("result.couldNotStart", slots.%ToJSON(), "phone", ..#NOW, 0, .sc), "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed.", "couldn't start renders as the UX document has it")
	Set slots = $ClassMethod(..#NOTICE, "ResultSlots", "result.allThrough", ..Result({"Final": 1, "Total": 50, "Resent": 50, "Completed": 50}), noun, .sc)
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("result.allThrough", slots.%ToJSON(), "phone", ..#NOW, 0, .sc), "All 50 orders went through.", "all through renders as the UX document has it")
	Set slots = $ClassMethod(..#NOTICE, "ResultSlots", "result.skipped", ..Result({"Final": 1, "Total": 3, "Skipped": 3, "Reason": "x"}), noun, .sc)
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt("result.skipped", slots.%ToJSON(), "phone", ..#NOW, 0, .sc), "0 of 3 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.", "skipped renders with no run copy counted: 0 of 3")

	// an empty count is 0, and remaining is at least 0
	Set slots = $ClassMethod(..#NOTICE, "ResultSlots", "result.interrupted", ..Result({"Interrupted": 1}), noun, .sc)
	Do $$$AssertEquals(..Flat(slots), "completed=0,count=0,itemNoun="_noun.%ToJSON()_",remaining=0", "an empty count is 0 and remaining is 0")
	Set slots = $ClassMethod(..#NOTICE, "ResultSlots", "result.interrupted", ..Result({"Interrupted": 1, "Total": 3, "Completed": 5}), noun, .sc)
	Do $$$AssertEquals(slots.remaining, 0, "remaining is never below 0")
	Do $$$AssertEquals(slots.%GetTypeOf("count")_"|"_slots.%GetTypeOf("completed")_"|"_slots.%GetTypeOf("remaining"), "number|number|number", "and the counts are JSON numbers")

	// slots that cannot be built
	Set none = $ClassMethod(..#NOTICE, "ResultSlots", "result.couldNotStart", ..Result({"Final": 1, "Total": 3}), noun, .sc)
	Do $$$AssertStatusNotOK(sc, "couldn't start with no reason is refused")
	Do $$$AssertEquals($IsObject(none), 0, "and gives no slots")
	Set none = $ClassMethod(..#NOTICE, "ResultSlots", "result.failedAgain", ..Result({"Final": 1, "Total": 3, "FailedAgain": 1}), noun, .sc)
	Do $$$AssertStatusNotOK(sc, "failures with no reason are refused")
	Set none = $ClassMethod(..#NOTICE, "ResultSlots", "result.skipped", ..Result({"Final": 1, "Total": 3, "Skipped": 3}), {"one": "order"}, .sc)
	Do $$$AssertStatusNotOK(sc, "a noun without both forms is refused")
	Set none = $ClassMethod(..#NOTICE, "ResultSlots", "result.skipped", ..Result({"Final": 1, "Total": 3, "Skipped": 3}), "", .sc)
	Do $$$AssertStatusNotOK(sc, "so is no noun")
	Set none = $ClassMethod(..#NOTICE, "ResultSlots", "incident.noFix", ..Result({"Final": 1, "Total": 3}), noun, .sc)
	Do $$$AssertStatusNotOK(sc, "a key that is no result key is refused")
}

Method TestApprovedText()
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Set ..ZoneSaved = 1
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Set slots = {"channel": "web", "time": "2026-10-16T18:20:00Z"}
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", slots.%ToJSON(), "phone", "2026-10-16T18:20:00Z", 1, .sc)
	Do $$$AssertStatusOK(sc, "answered.approved renders")
	Do $$$AssertEquals(text, "Approved from the web chat at 14:20 ET.", "as the UX document has it")
	Set web = ##class(OcuTalon.Msg.Catalog).RenderAt("answered.approved", slots.%ToJSON(), "web", "2026-10-16T18:20:00Z", 1, .sc)
	Do $$$AssertEquals(web, "Approved from the web chat at 14:20 ET", "and the page wording has no full stop")
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
	Set slots = ..SlotsOf(..Row("partner_outage"), "the count slot")
	If $IsObject(slots) Do $$$AssertEquals(lines.%Get(0).count + lines.%Get(1).count, slots.count, "the lines add up to the count slot, although the first group's Count has moved on")
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
