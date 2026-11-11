/// Tests of Ownership.Usage and the Rows kind usage (Story 37.2; AD-4, AD-13, AD-18, AD-20). Safe on a slot: no production is needed. The sessions
/// are Refs only (the read takes any Ref) and the Usage rows are fixtures (Test.Data.Fixture.Usage) under one tag, removed after every test.
///   - TestBuckets: each bucket equals the hand sum of its rows (the four token kinds, the cost with a NULL cost as 0, the maximum of the largest request),
///     the buckets add up to what RunCost totals for the same window, and the retry agent and the estimated compaction row keep their own buckets;
///   - TestRange: the local-day window (the first instant of the first date up to the first instant of tomorrow), the day edge at local 23:59:59 and
///     00:00:00, and a row at the first instant of tomorrow left out;
///   - TestIsolation: a second session's, eval's, instance's and no owner's rows never appear, in either session's read;
///   - TestRefusals: the kind usage through Test.Data.OwnershipProbe refuses an empty, eval or instance owner, and Usage refuses them and a days
///     that is not a whole number from 1 to 30;
///   - TestEmpty: a session with no rows gets buckets [] and days still lists the range, oldest first;
///   - TestUnreadable: a row in the window whose time cannot be read fails the read (an error status and {}) instead of dropping out of the totals.
Class OcuTalon.Test.Data.OwnershipUsage Extends OcuTalon.Test.Bridge.ZoneCase
{

/// The run's number.
Property Number As %Integer;

/// The tag the fixture rows are recorded under.
Property Tag As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("OwnershipUsage", "n"))
	Set ..Tag = "zzownusage"_..Number
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Tag)
	Quit ##super(testname)
}

/// Every bucket is the hand sum of its rows; the buckets add up to RunCost's totals for the same window.
Method TestBuckets()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	Set usage = ##class(OcuTalon.Data.Ownership).Usage(a, 3, .sc)
	Do $$$AssertStatusOK(sc, "the read is OK")
	Do $$$AssertEquals(usage.buckets.%Size(), 7, "seven buckets in three days")
	Do $$$AssertEquals($ListToString(..KeysOf(usage), "|"), "days|buckets", "the result holds days and buckets only")
	Set bucket = ..Find(usage, ..Date(0), "TriageAgent", "web", "zz-model-x", 0)
	Do $$$AssertEquals(..Line(bucket), "150|15|20|5|.0015|3000", "today's TriageAgent bucket sums its two rows, and its largest request is the larger one")
	Set bucket = ..Find(usage, ..Date(0), "ChatAgent", "phone", "zz-model-y", 0)
	Do $$$AssertEquals(..Line(bucket), "200|20|0|0|0|500", "a row with no cost counts 0")
	Set bucket = ..Find(usage, ..Date(1), "ChatAgentRetry", "telegram", "zz-model-y", 0)
	Do $$$AssertEquals(..Line(bucket), "70|7|1|2|.002|700", "the retry agent keeps its stored name in its own bucket")
	Set bucket = ..Find(usage, ..Date(1), "compaction", "web", "zz-model-y", 1)
	Do $$$AssertEquals(..Line(bucket)_"|"_bucket.estimated, "300|30|0|0|.003|2000|1", "the compaction row is its own estimated bucket")
	Set bucket = ..Find(usage, ..Date(2), "ChatAgent", "web", "zz-model-x", 0)
	Do $$$AssertEquals(..Line(bucket)_"|"_bucket.estimated, "10|1|0|0|.0001|100|0", "an older day's bucket, not estimated")
	Set bucket = usage.buckets.%Get(0)
	Do $$$AssertEquals(bucket.day, ..Date(2), "the buckets begin with the oldest day")
	Set last = usage.buckets.%Get(usage.buckets.%Size() - 1)
	Do $$$AssertEquals(last.day, ..Date(0), "and end with today")
	Set input = 0, output = 0, cacheRead = 0, cacheWrite = 0, cost = 0
	For i = 0:1:usage.buckets.%Size() - 1 {
		Set bucket = usage.buckets.%Get(i)
		Set input = input + bucket.inputTokens, output = output + bucket.outputTokens
		Set cacheRead = cacheRead + bucket.cacheReadTokens, cacheWrite = cacheWrite + bucket.cacheWriteTokens, cost = cost + bucket.costUSD
	}
	Set run = ##class(OcuTalon.Data.Ownership).RunCost(a, ##class(OcuTalon.Data.Time).FromLocal(..Date(2)_"T00:00:00"), .sc)
	Do $$$AssertStatusOK(sc, "RunCost is OK")
	Do $$$AssertEquals(input_"|"_output_"|"_cacheRead_"|"_cacheWrite_"|"_(+cost), "754|78|21|7|"_.0071, "the buckets add up to the hand total")
	Do $$$AssertEquals(input_"|"_output_"|"_cacheRead_"|"_cacheWrite_"|"_(+cost), run.inputTokens_"|"_run.outputTokens_"|"_run.cacheReadTokens_"|"_run.cacheWriteTokens_"|"_(+run.costUSD), "and to what RunCost totals for the same window")
}

/// The window is the local dates, from the first instant of the first to the first instant of tomorrow; the day edge splits. The process zone is one
/// whose midnight is not the UTC midnight, so that a window cut at UTC midnight instead is not the local one.
Method TestRange()
{
	For zone = "America/New_York", "Asia/Kolkata", "Pacific/Auckland" {
		Do ..PutZone(zone)
		Kill ^||OcuTalon.Bridge.Time
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Tag)
		Do ..RangeIn(zone)
	}
}

/// TestRange in the process zone zone.
Method RangeIn(zone As %String) [ Private ]
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	Do ..Row(a, ..Date(-1), "00:00:00", "TriageAgent", "web", "zz-model-x", 0, 999, 0, 0, 0, ".5", 999)
	Set three = ##class(OcuTalon.Data.Ownership).Usage(a, 3, .sc)
	Do $$$AssertStatusOK(sc, zone_": "_"three days: OK")
	Do $$$AssertEquals(three.buckets.%Size(), 7, zone_": "_"a row at the first instant of tomorrow is left out")
	Do $$$AssertEquals(..Total(three), 754, zone_": "_"and so are its tokens")
	Set bucket = ..Find(three, ..Date(2), "TriageAgent", "system", "zz-model-z", 0)
	Do $$$AssertEquals(..Line(bucket), "11|2|0|0|.0002|9", zone_": "_"three days: the row at local 23:59:59 of the first day is in")
	Set two = ##class(OcuTalon.Data.Ownership).Usage(a, 2, .sc)
	Do $$$AssertEquals(two.days.%Get(0)_"|"_two.days.%Get(1), ..Date(1)_"|"_..Date(0), zone_": "_"two days: yesterday and today")
	Do $$$AssertEquals(..Find(two, ..Date(2), "TriageAgent", "system", "zz-model-z", 0), "", zone_": "_"two days: the row at 23:59:59 of the day before the first is out")
	Do $$$AssertEquals(..Find(two, ..Date(2), "ChatAgent", "web", "zz-model-x", 0), "", zone_": "_"two days: the older day's other row is out too")
	Set bucket = ..Find(two, ..Date(1), "TriageAgent", "system", "zz-model-z", 0)
	Do $$$AssertEquals(..Line(bucket), "13|3|0|0|.0003|11", zone_": "_"two days: the row at local 00:00:00 of the first day is in, in day D+1's bucket")
	Do $$$AssertEquals(two.buckets.%Size(), 5, zone_": "_"two days: five buckets")
	Set one = ##class(OcuTalon.Data.Ownership).Usage(a, 1, .sc)
	Do $$$AssertEquals(one.days.%Size()_"|"_one.days.%Get(0)_"|"_one.buckets.%Size(), "1|"_..Date(0)_"|2", zone_": "_"one day: today, and its two buckets")
	Set thirty = ##class(OcuTalon.Data.Ownership).Usage(a, 30, .sc)
	Do $$$AssertEquals(thirty.days.%Size()_"|"_thirty.days.%Get(0)_"|"_thirty.days.%Get(29), "30|"_..Date(29)_"|"_..Date(0), zone_": "_"thirty days: today and the 29 before, oldest first")
	Do $$$AssertEquals(thirty.buckets.%Size(), 7, zone_": "_"and the same seven buckets")
}

/// Another session's, eval's, instance's and no owner's rows are never in the read, and the read of the other session holds only its own.
Method TestIsolation()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef(), b = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	Do ..Row(b, ..Date(0), "12:00:00", "ChatAgent", "web", "zz-model-b", 0, 4000, 0, 0, 0, ".4", 4000)
	Do ..Row("eval", ..Date(0), "12:00:00", "ChatAgent", "web", "zz-model-eval", 0, 5000, 0, 0, 0, ".5", 5000)
	Do ..Row("instance", ..Date(0), "12:00:00", "ChatAgent", "web", "zz-model-instance", 0, 6000, 0, 0, 0, ".6", 6000)
	Do ..Row("", ..Date(0), "12:00:00", "ChatAgent", "web", "zz-model-noowner", 0, 7000, 0, 0, 0, ".7", 7000)
	Set usageA = ##class(OcuTalon.Data.Ownership).Usage(a, 7, .sc)
	Do $$$AssertStatusOK(sc, "A's read is OK")
	Do $$$AssertEquals(usageA.buckets.%Size()_"|"_..Total(usageA), "7|754", "A's read holds its own seven buckets and tokens only")
	Do $$$AssertEquals(..Models(usageA), "zz-model-x,zz-model-y,zz-model-z", "and none of the other owners' models")
	Set usageB = ##class(OcuTalon.Data.Ownership).Usage(b, 7, .sc)
	Do $$$AssertEquals(usageB.buckets.%Size()_"|"_..Total(usageB)_"|"_..Models(usageB), "1|4000|zz-model-b", "B's read holds its own row only")
	Set usageE = ##class(OcuTalon.Data.Ownership).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), 7, .sc)
	Do $$$AssertEquals(usageE.buckets.%Size(), 0, "a session that owns none reads none of them")
}

/// The kind refuses an empty owner and eval and instance in any case, and Usage refuses them and a bad range.
Method TestRefusals()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	Set from = ##class(OcuTalon.Data.Time).FromLocal(..Date(2)_"T00:00:00"), to = ##class(OcuTalon.Data.Time).FromLocal(..Date(-1)_"T00:00:00")
	For owner = "", "eval", "instance", "EVAL", "Instance", "eval ", "EVAL  " {
		Set rows = $ClassMethod(probe, "Call", "usage", owner, .sc, from, to)
		Do $$$AssertStatusNotOK(sc, "usage: '"_owner_"' is not a session's Ref")
		Do $$$AssertEquals(rows.Count(), 0, "usage: with no rows")
		Set usage = ##class(OcuTalon.Data.Ownership).Usage(owner, 7, .sc)
		Do $$$AssertStatusNotOK(sc, "Usage: '"_owner_"' is refused")
		Do $$$AssertEquals(usage.%Size(), 0, "Usage: with an empty result")
	}
	Set rows = $ClassMethod(probe, "Call", "usage", a, .sc, from, to)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 8, "and gives its eight rows")
	For days = 0, 31, -1, 7.5, "abc", "", "07x" {
		Set usage = ##class(OcuTalon.Data.Ownership).Usage(a, days, .sc)
		Do $$$AssertStatusNotOK(sc, "a range of '"_days_"' days is refused")
		Do $$$AssertEquals(usage.%Size(), 0, "with an empty result")
	}
}

/// A session with no rows: buckets [] and the range still listed, oldest first, today last.
Method TestEmpty()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	For days = 1, 7, 30 {
		Set usage = ##class(OcuTalon.Data.Ownership).Usage(a, days, .sc)
		Do $$$AssertStatusOK(sc, days_" days: OK")
		Do $$$AssertEquals(usage.buckets.%ToJSON(), "[]", days_" days: no bucket")
		Do $$$AssertEquals(usage.days.%Size()_"|"_usage.days.%Get(0)_"|"_usage.days.%Get(days - 1), days_"|"_..Date(days - 1)_"|"_..Date(0), days_" days: the range, oldest first and today last")
	}
}

/// A row in the window whose RecordedAt is not a UTC time fails the read, so that the buckets never silently stop adding up to RunCost.
Method TestUnreadable()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Row(a, ..Date(0), "12:00:00", "TriageAgent", "web", "zz-model-x", 0, 100, 10, 0, 0, ".001", 1000)
	Set usage = ##class(OcuTalon.Data.Ownership).Usage(a, 1, .sc)
	Do $$$AssertStatusOK(sc, "a readable row is read")
	Set utc = ##class(OcuTalon.Data.Time).FromLocal(..Date(0)_"T12:30:00")
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Tag, a, {"RecordedAt": ($Extract(utc, 1, 19)_"X"), "InputTokens": 1})
	Set usage = ##class(OcuTalon.Data.Ownership).Usage(a, 1, .sc)
	Do $$$AssertStatusNotOK(sc, "a row with a time that cannot be read fails the read")
	Do $$$AssertEquals(usage.%Size(), 0, "with an empty result")
}

/// --- helpers ---
/// The local date YYYY-MM-DD of today minus ago days (a negative ago is after today).
ClassMethod Date(ago As %Integer) As %String [ Private ]
{
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Quit $ZDate($ZDateH(today, 3) - ago, 3)
}

/// One Usage row of the owner at the local time date, hms, with the given agent, channel, model, estimated flag and four token kinds; cost "" is NULL.
Method Row(owner As %String, date As %String, hms As %String, agent As %String, channel As %String, model As %String, estimated As %Boolean, inTokens As %Integer, outTokens As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String, largest As %Integer) [ Private ]
{
	Set fields = {"Agent": (agent), "Channel": (channel), "Model": (model), "Estimated": (estimated), "InputTokens": (inTokens), "OutputTokens": (outTokens), "CacheReadTokens": (cacheRead), "CacheWriteTokens": (cacheWrite), "LargestRequestTokens": (largest), "RequestCount": 1}
	Set fields.RecordedAt = ##class(OcuTalon.Data.Time).FromLocal(date_"T"_hms)
	If cost '= "" Set fields.CostUSD = cost
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Tag, owner, fields)
}

/// The eight rows of session a, in three local days.
Method Seed(a As %String) [ Private ]
{
	Do ..Row(a, ..Date(0), "12:00:00", "TriageAgent", "web", "zz-model-x", 0, 100, 10, 20, 5, ".001", 1000)
	Do ..Row(a, ..Date(0), "12:30:00", "TriageAgent", "web", "zz-model-x", 0, 50, 5, 0, 0, ".0005", 3000)
	Do ..Row(a, ..Date(0), "13:00:00", "ChatAgent", "phone", "zz-model-y", 0, 200, 20, 0, 0, "", 500)
	Do ..Row(a, ..Date(1), "12:00:00", "ChatAgentRetry", "telegram", "zz-model-y", 0, 70, 7, 1, 2, ".002", 700)
	Do ..Row(a, ..Date(1), "12:00:00", "compaction", "web", "zz-model-y", 1, 300, 30, 0, 0, ".003", 2000)
	Do ..Row(a, ..Date(2), "11:00:00", "ChatAgent", "web", "zz-model-x", 0, 10, 1, 0, 0, ".0001", 100)
	Do ..Row(a, ..Date(2), "23:59:59", "TriageAgent", "system", "zz-model-z", 0, 11, 2, 0, 0, ".0002", 9)
	Do ..Row(a, ..Date(1), "00:00:00", "TriageAgent", "system", "zz-model-z", 0, 13, 3, 0, 0, ".0003", 11)
}

/// The bucket of the result for the key, or "".
ClassMethod Find(usage As %DynamicObject, day As %String, agent As %String, channel As %String, model As %String, estimated As %Boolean) As %DynamicObject [ Private ]
{
	For i = 0:1:usage.buckets.%Size() - 1 {
		Set bucket = usage.buckets.%Get(i)
		If (bucket.day = day) && (bucket.agent = agent) && (bucket.channel = channel) && (bucket.model = model) && (bucket.estimated = estimated) Quit
		Set bucket = ""
	}
	Quit $Get(bucket)
}

/// input|output|cacheRead|cacheWrite|cost|largest of a bucket, as numbers.
ClassMethod Line(bucket As %DynamicObject) As %String [ Private ]
{
	If '$IsObject(bucket) Quit "(no bucket)"
	Quit +bucket.inputTokens_"|"_+bucket.outputTokens_"|"_+bucket.cacheReadTokens_"|"_+bucket.cacheWriteTokens_"|"_+bucket.costUSD_"|"_+bucket.largestRequestTokens
}

/// The input tokens of all the buckets.
ClassMethod Total(usage As %DynamicObject) As %Integer [ Private ]
{
	Set total = 0
	For i = 0:1:usage.buckets.%Size() - 1 Set total = total + usage.buckets.%Get(i).inputTokens
	Quit total
}

/// The distinct models of the buckets, sorted, comma-separated.
ClassMethod Models(usage As %DynamicObject) As %String [ Private ]
{
	Kill seen
	For i = 0:1:usage.buckets.%Size() - 1 Set seen(usage.buckets.%Get(i).model) = ""
	Set text = "", model = ""
	For {
		Set model = $Order(seen(model))
		If model = "" Quit
		Set text = text_$Select(text = "": "", 1: ",")_model
	}
	Quit text
}

/// The names of the result's members, as a list.
ClassMethod KeysOf(usage As %DynamicObject) As %List [ Private ]
{
	Set keys = ""
	Set iterator = usage.%GetIterator()
	While iterator.%GetNext(.name) {
		Set keys = keys_$ListBuild(name)
	}
	Quit keys
}

}
