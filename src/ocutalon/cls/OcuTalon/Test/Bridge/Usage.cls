/// Tests of the Usage row, the Price and the installer's prices (Story 1.4; AD-19, AD-20; FR-2). Pure and in process: nothing is sent
/// and no production runs. The tests write rows of their own (Usage rows with a DecisionRef of their own, a Price row of a model that
/// no product uses), delete them again, and put the two Price rows of the product back as they were (OnAfterOneTest).
///   - TestCost: the cost of one turn at the seeded rates of Claude Haiku 5.5 and Claude Sonnet 5.5, each tier at its own rate, the
///     long tier above 100,000 tokens (not at 100,000), the average request when the largest is unknown, a model with no Price
///     row (empty cost, never 0) and the exact model match;
///   - TestFromStats: the row of one Chat from two stats readings, the last response's usage, and the request: the four sums with
///     input = prompt + cache read + cache write, the request count, the largest request from the last usage or empty without it, the
///     request's fields, Estimated 0 and RecordedAt in UTC, a counter that falls, a missing first reading and a missing second;
///   - TestHasSpend: a request or a token is spend; a tool call alone and no change are not;
///   - TestSeedPrices: Installer.Run() creates both rows with the values of the table, leaves an edited row alone and creates a deleted
///     row again;
///   - TestTotals: Usage.Totals sums the rows of a decision, takes the model of the newest, is empty for no row and for no ref, and has no
///     cost when any row has none.
Class OcuTalon.Test.Bridge.Usage Extends %UnitTest.TestCase
{

Parameter HAIKU = "claude-haiku-5-5";

Parameter SONNET = "claude-sonnet-5-5";

/// A model of the tests that no product uses, priced with the rates of Claude Haiku 5.5.
Parameter FIXTURE = "zz-usage-fixture";

/// The DecisionRefs of the Usage rows that the test wrote.
Property Refs As %List;

/// The Price rows that the test may have changed, each $ListBuild(model, existed, InputPerMTok, OutputPerMTok, CacheReadPerMTok,
/// CacheWritePerMTok, LongThresholdTokens, LongInputPerMTok, LongOutputPerMTok).
Property Saved As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Refs, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
	}
	Set ..Refs = ""
	Set position = 0
	While $ListNext(..Saved, position, saved) {
		Do ..Restore(saved)
	}
	Set ..Saved = ""
	Quit $$$OK
}

/// The cost of one turn: hand-computed at every tier of Claude Haiku 5.5 (input 0.10, output 0.50, cache read 0.01, cache write 0.125,
/// and above 100,000 tokens input 0.50 and output 2.50 with each cache rate times 5), and for Claude Sonnet 5.5 (2, 10, 0.20, 2.50,
/// no long tier). Rates are those of Installer.Prices().
Method TestCost()
{
	Set haiku = ..NewPrice(..#HAIKU)
	Do $$$AssertEquals(haiku.Cost(90000, 5000, 4000, 2000, 100000, 1), .01055, "largest 100,000 is not above the threshold: 9000 + 50 + 500 + 1000 micro-dollars")
	Do $$$AssertEquals(haiku.Cost(90000, 5000, 4000, 2000, 100001, 1), .05275, "largest 100,001 prices the whole turn at the long tier: 45000 + 250 + 2500 + 5000 micro-dollars")
	Do $$$AssertEquals(haiku.Cost(92000, 5000, 4000, 2000, "", 1), .05375, "with no largest, the one request of 101,000 tokens is above the threshold")
	Do $$$AssertEquals(haiku.Cost(92000, 5000, 4000, 2000, "", 2), .01075, "and two requests average 50,500 tokens, which is not")
	Do $$$AssertEquals(haiku.Cost(92000, 5000, 4000, 2000, "", 0), .05375, "a request count of 0 counts as 1")
	Do $$$AssertEquals(haiku.Cost(1200, 2000, 600, 300, 3800, 1), .000365, "the fixed usage of the mock: 120 + 20 + 75 + 150 micro-dollars")
	Do $$$AssertEquals(haiku.Cost(2100, 512, 512, 130, 1612, 2), .000344, "the two requests of the mock's turn: 344.12 micro-dollars rounded to 6 decimals")
	Do $$$AssertEquals(haiku.Cost(0, 0, 0, 0, 0, 0), 0, "no token costs 0")
	Do $$$AssertEquals(haiku.Cost("", "", "", "", "", ""), 0, "and so does an empty count")

	Set sonnet = ..NewPrice(..#SONNET)
	Do $$$AssertEquals(sonnet.Cost(1000, 1000, 0, 1000, 3000, 1), .0122, "Sonnet: 2000 + 200 + 10000 micro-dollars")
	Do $$$AssertEquals(sonnet.Cost(1000, 1000, 0, 1000, 3000, 1), sonnet.Cost(1000, 1000, 0, 1000, 500000, 1), "Sonnet has no long tier, so a large request costs the same")
	Do $$$AssertEquals(sonnet.Cost(0, 0, 1000, 0, 1000, 1), .0025, "a Sonnet cache write costs 2.50 a million")

	Set price = ..NewPrice(..#HAIKU, ..#FIXTURE)
	Do $$$AssertStatusOK(price.%Save(), "a Price row of a model of the tests is saved")
	Set ..Saved = ..Saved _ $ListBuild($ListBuild(..#FIXTURE, 0))
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Price).CostFor(..#FIXTURE, 90000, 5000, 4000, 2000, 100000, 1), .01055, "CostFor prices the usage at the row of the model")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Price).CostFor(..#FIXTURE, 90000, 5000, 4000, 2000, 100001, 1), .05275, "also at the long tier")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Price).CostFor("zz-unpriced", 90000, 5000, 4000, 2000, 100000, 1), "", "a model with no Price row has an empty cost")
	Do $$$AssertNotTrue(##class(OcuTalon.Bridge.Data.Price).CostFor("zz-unpriced", 0, 0, 0, 0, 0, 1) = 0, "which is not 0, not even for no usage")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Price).CostFor("", 1, 1, 1, 1, 1, 1), "", "so does an empty model")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Price).CostFor($ZConvert(..#FIXTURE, "U"), 1, 1, 1, 1, 1, 1), "", "and so does a model that matches the row in another case: the match is exact")
}

/// FromStats: the deltas of two readings, the sums, and the fields of the request. The model of the tests is priced at the rates of
/// Claude Haiku 5.5, so the cost of the second case is the mock's turn: 0.000344.
Method TestFromStats()
{
	Set price = ..NewPrice(..#HAIKU, ..#FIXTURE)
	Do $$$AssertStatusOK(price.%Save(), "a Price row of a model of the tests is saved")
	Set ..Saved = ..Saved _ $ListBuild($ListBuild(..#FIXTURE, 0))
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = "zzitem1"
	Set request.OwnerRef = "zzowner1"
	Set request.Channel = "phone"
	Set request.DecisionRef = "zzdecision1"
	Set before = ..Stats(3, 1000, 100, 200, 50)
	Set after = ..Stats(5, 3100, 230, 712, 562)
	Set last = {"prompt_tokens": 1100, "completion_tokens": 80, "cache_read_tokens": 512, "cache_creation_tokens": 0, "total_tokens": 1180}
	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, before, after, last, .row)
	Do $$$AssertStatusOK(sc, "the row is built")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.%Id(), "", "and is not saved")
	Do $$$AssertEquals(row.RequestCount, 2, "RequestCount is the delta of total_interactions, not the second reading")
	Do $$$AssertEquals(row.InputTokens, 3124, "InputTokens adds the prompt delta 2100, the cache-read delta 512 and the cache-write delta 512")
	Do $$$AssertEquals(row.OutputTokens, 130, "OutputTokens is the delta of total_completion_tokens")
	Do $$$AssertEquals(row.CacheReadTokens_"|"_row.CacheWriteTokens, "512|512", "the cache counts are their deltas")
	Do $$$AssertEquals(row.LargestRequestTokens, 1612, "LargestRequestTokens is the input of the last request: prompt 1100 + cache read 512 + cache creation 0")
	Do $$$AssertEquals(row.CostUSD, .000344, "CostUSD is priced from the Price row of the model")
	Do $$$AssertEquals(row.Estimated, 0, "Estimated is 0")
	Do $$$AssertTrue(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_row.RecordedAt)
	Do $$$AssertEquals(row.DecisionRef_"|"_row.ItemId_"|"_row.Kind_"|"_row.OwnerRef_"|"_row.Channel, "zzdecision1|zzitem1|turn|zzowner1|phone", "DecisionRef, ItemId, Kind, OwnerRef and Channel are the request's")
	Do $$$AssertEquals(row.Agent_"|"_row.Model, "ChatAgent|"_..#FIXTURE, "Agent and Model are the ones given")

	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, before, after, "", .row)
	Do $$$AssertStatusOK(sc, "a row is built with no usage of a last response, as after a Chat that threw")
	Do $$$AssertEquals(row.LargestRequestTokens, "", "its LargestRequestTokens is empty")
	Do $$$AssertEquals(row.InputTokens_"|"_row.RequestCount, "3124|2", "and the sums are the same")
	Do $$$AssertEquals(row.CostUSD, .000344, "the cost is the same: the average request of 1562 tokens is below the threshold")

	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, "", after, "", .row)
	Do $$$AssertStatusOK(sc, "a row is built with no first reading")
	Do $$$AssertEquals(row.RequestCount_"|"_row.InputTokens_"|"_row.OutputTokens, "5|"_(3100 + 712 + 562)_"|230", "which counts the whole second reading")
	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, after, before, "", .row)
	Do $$$AssertStatusOK(sc, "a row is built from readings in the wrong order")
	Do $$$AssertEquals(row.RequestCount_"|"_row.InputTokens_"|"_row.OutputTokens_"|"_row.CacheReadTokens, "0|0|0|0", "a counter that falls counts as 0")
	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, before, "", "", .row)
	Do $$$AssertStatusNotOK(sc, "no second reading gives an error")
	Do $$$AssertEquals(row, "", "and no row")

	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", "zz-unpriced", before, after, last, .row)
	Do $$$AssertStatusOK(sc, "a row of a model with no Price row is built")
	Do $$$AssertEquals(row.CostUSD, "", "with an empty cost")
	Do $$$AssertEquals(row.InputTokens, 3124, "and its counts")

	Set big = ..Stats(1, 99000, 10, 5000, 4000)
	Set sc = ##class(OcuTalon.Bridge.Data.Usage).FromStats(request, "ChatAgent", ..#FIXTURE, ..Stats(0, 0, 0, 0, 0), big, {"prompt_tokens": 90000, "cache_read_tokens": 5000, "cache_creation_tokens": 5001}, .row)
	Do $$$AssertEquals(row.LargestRequestTokens, 100001, "a last request of 100,001 tokens")
	Do $$$AssertEquals(row.CostUSD, ##class(OcuTalon.Bridge.Data.Price).CostFor(..#FIXTURE, 99000, 5000, 4000, 10, 100001, 1), "is priced at the long tier")
	Do $$$AssertTrue(row.CostUSD > ..NewPrice(..#HAIKU).Cost(99000, 5000, 4000, 10, 100000, 1), "which costs more than the base tier")
}

/// HasSpend: 1 when a reading holds a model request or a token more than the one before, for each of the five counters; 0 for no
/// change, for a tool call alone, for a missing reading and for counters that a reading lacks.
Method TestHasSpend()
{
	Set has = "OcuTalon.Bridge.Data.Usage"
	Set zero = ..Stats(0, 0, 0, 0, 0)
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, zero), 0, "no change is no spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", ..Stats(2, 10, 5, 1, 1), ..Stats(2, 10, 5, 1, 1)), 0, "no change at non-zero readings is no spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(1, 0, 0, 0, 0)), 1, "a model request is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(0, 1, 0, 0, 0)), 1, "a prompt token is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(0, 0, 1, 0, 0)), 1, "a completion token is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(0, 0, 0, 1, 0)), 1, "a cache-read token is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(0, 0, 0, 0, 1)), 1, "a cache-write token is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", ..Stats(3, 10, 5, 1, 1), ..Stats(4, 10, 5, 1, 1)), 1, "one more request after non-zero readings is spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ..Stats(0, 0, 0, 0, 0, 3)), 0, "tool calls alone are no spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", ..Stats(3, 10, 5, 1, 1), ..Stats(1, 4, 2, 0, 0)), 0, "counters that fall are no spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", "", ..Stats(1, 5, 5, 0, 0)), 1, "with no first reading, the second reading is the spend")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", "", zero), 0, "and a second reading of zeros is none")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", zero, ""), 0, "with no second reading there is no spend to see")
	Do $$$AssertEquals($ClassMethod(has, "HasSpend", {}, {}), 0, "readings with no counters are no spend")
}

/// Installer.Run() creates the Price rows of Claude Haiku 5.5 and Claude Sonnet 5.5 with the values of the story's table, and
/// returns OK. A row that an admin edited keeps its edit, and a deleted row is created again.
Method TestSeedPrices()
{
	For model = ..#HAIKU, ..#SONNET {
		Set ..Saved = ..Saved _ $ListBuild(..Snapshot(model))
		Do ..Remove(model)
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).Run(), "Installer.Run() returns OK with the rows absent")
	Do $$$AssertEquals(..Values(..#HAIKU), ".1|.5|.01|.125|100000|.5|2.5", "Claude Haiku 5.5: 0.10, 0.50, 0.01, 0.125, long tier above 100,000 at 0.50 and 2.50")
	Do $$$AssertEquals(..Values(..#SONNET), "2|10|.2|2.5|||", "Claude Sonnet 5.5: 2, 10, 0.20, 2.50 and no long tier")
	Do $$$AssertEquals(..Rows(..#HAIKU)_"|"_..Rows(..#SONNET), "1|1", "each model has one row")

	Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(..#HAIKU)
	Set row.InputPerMTok = 0.2
	Set row.LongThresholdTokens = 50000
	Do $$$AssertStatusOK(row.%Save(), "an admin edits the input price and the threshold of Claude Haiku 5.5")
	Kill row
	Do ..Remove(..#SONNET)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).Run(), "Installer.Run() returns OK again")
	Do $$$AssertEquals(..Values(..#HAIKU), ".2|.5|.01|.125|50000|.5|2.5", "the edited values stay")
	Do $$$AssertEquals(..Values(..#SONNET), "2|10|.2|2.5|||", "and the deleted row is created again")
	Do $$$AssertEquals(..Rows(..#HAIKU)_"|"_..Rows(..#SONNET), "1|1", "with one row for each model")
}

/// Totals: the sums of the rows of a decision, the model of the newest row, the number of rows. A ref with no row, and an empty ref,
/// have empty values. A row with no cost makes the cost empty and leaves the other sums.
Method TestTotals()
{
	Set totals = "OcuTalon.Bridge.Data.Usage"
	Set ref = ..NewRef()
	Do ..AddRow(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
	Do ..AddRow(ref, "claude-sonnet-5-5", 1200, 50, 0, 100, .0123)
	Do ..AddRow(..NewRef(), "claude-haiku-5-5", 99999, 99999, 99999, 99999, 9)
	Set sums = $ClassMethod(totals, "Totals", ref)
	Do $$$AssertEquals(sums.inputTokens_"|"_sums.outputTokens_"|"_sums.cacheReadTokens_"|"_sums.cacheWriteTokens, "5000|350|2000|700", "the token fields are the sums over the rows of the ref, and no other row")
	Do $$$AssertEquals(sums.costUSD, .012665, "so is the cost")
	Do $$$AssertEquals(sums.model, "claude-sonnet-5-5", "the model is the newest row's")
	Do $$$AssertEquals(sums.rows, 2, "and rows is the number of rows")
	Do $$$AssertEquals(sums.%GetTypeOf("inputTokens")_"|"_sums.%GetTypeOf("costUSD")_"|"_sums.%GetTypeOf("model"), "number|number|string", "the sums are JSON numbers")

	Set sums = $ClassMethod(totals, "Totals", ..NewRef())
	Do $$$AssertEquals(sums.inputTokens_"|"_sums.outputTokens_"|"_sums.cacheReadTokens_"|"_sums.cacheWriteTokens_"|"_sums.costUSD_"|"_sums.model, "|||||", "a ref with no row has empty values")
	Do $$$AssertEquals(sums.rows, 0, "and no rows")
	Set sums = $ClassMethod(totals, "Totals", "")
	Do $$$AssertEquals(sums.inputTokens_"|"_sums.costUSD_"|"_sums.model_"|"_sums.rows, "|||0", "an empty ref has empty values too")

	Set unknown = ..NewRef()
	Do ..AddRow(unknown, "claude-haiku-5-5", 100, 10, 0, 0, .0001)
	Do ..AddRow(unknown, "zz-unpriced", 200, 20, 5, 6, "")
	Set sums = $ClassMethod(totals, "Totals", unknown)
	Do $$$AssertEquals(sums.costUSD, "", "a row with no cost makes the cost empty, never the sum of the others")
	Do $$$AssertEquals(sums.inputTokens_"|"_sums.outputTokens_"|"_sums.cacheReadTokens_"|"_sums.cacheWriteTokens_"|"_sums.model_"|"_sums.rows, "300|30|5|6|zz-unpriced|2", "while the other fields are still the sums")
}

/// --- helpers ---
/// A stats reading with the counters that matter.
ClassMethod Stats(interactions As %Integer, prompt As %Integer, completion As %Integer, cacheRead As %Integer, cacheWrite As %Integer, toolCalls As %Integer = 0) As %DynamicObject [ Private ]
{
	Quit {"total_interactions": (interactions), "total_prompt_tokens": (prompt), "total_completion_tokens": (completion), "total_cache_read_tokens": (cacheRead), "total_cache_creation_tokens": (cacheWrite), "total_tool_calls": (toolCalls)}
}

/// The Installer.Prices() entry of the model, or "".
ClassMethod Rates(model As %String) As %List [ Private ]
{
	Set found = ""
	Set prices = ##class(OcuTalon.Bridge.Installer).Prices()
	Set position = 0
	While $ListNext(prices, position, price) {
		If $List(price, 1) = model Set found = price
	}
	Quit found
}

/// An unsaved Price row with the rates of the model in Installer.Prices(), under the name asModel (default: the model).
ClassMethod NewPrice(model As %String, asModel As %String = "") As OcuTalon.Bridge.Data.Price [ Private ]
{
	Set rates = ..Rates(model)
	Set row = ##class(OcuTalon.Bridge.Data.Price).%New()
	Set row.Model = $Select(asModel = "": model, 1: asModel)
	Set row.InputPerMTok = $List(rates, 2)
	Set row.OutputPerMTok = $List(rates, 3)
	Set row.CacheReadPerMTok = $List(rates, 4)
	Set row.CacheWritePerMTok = $List(rates, 5)
	Set row.LongThresholdTokens = $List(rates, 6)
	Set row.LongInputPerMTok = $List(rates, 7)
	Set row.LongOutputPerMTok = $List(rates, 8)
	Quit row
}

/// The values of the Price row of the model, as InputPerMTok|OutputPerMTok|CacheReadPerMTok|CacheWritePerMTok|LongThresholdTokens|
/// LongInputPerMTok|LongOutputPerMTok, or "none" when there is no row.
ClassMethod Values(model As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
	If '$IsObject(row) Quit "none"
	Quit row.InputPerMTok_"|"_row.OutputPerMTok_"|"_row.CacheReadPerMTok_"|"_row.CacheWritePerMTok_"|"_row.LongThresholdTokens_"|"_row.LongInputPerMTok_"|"_row.LongOutputPerMTok
}

/// The number of Price rows of the model.
ClassMethod Rows(model As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Price WHERE Model = ?", model)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// What Restore needs to put the Price row of the model back: $ListBuild(model, existed, the seven values).
ClassMethod Snapshot(model As %String) As %List [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
	If '$IsObject(row) Quit $ListBuild(model, 0)
	Quit $ListBuild(model, 1, row.InputPerMTok, row.OutputPerMTok, row.CacheReadPerMTok, row.CacheWritePerMTok, row.LongThresholdTokens, row.LongInputPerMTok, row.LongOutputPerMTok)
}

/// Deletes the Price rows of the model.
ClassMethod Remove(model As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Price WHERE Model = ?", model)
}

/// Puts the Price row of a snapshot back: the row of the model is deleted, and created again with the values when it existed.
ClassMethod Restore(saved As %List) [ Private ]
{
	Set model = $List(saved, 1)
	Do ..Remove(model)
	If '$List(saved, 2) Quit
	Set row = ##class(OcuTalon.Bridge.Data.Price).%New()
	Set row.Model = model
	Set row.InputPerMTok = $List(saved, 3)
	Set row.OutputPerMTok = $List(saved, 4)
	Set row.CacheReadPerMTok = $List(saved, 5)
	Set row.CacheWritePerMTok = $List(saved, 6)
	Set row.LongThresholdTokens = $List(saved, 7)
	Set row.LongInputPerMTok = $List(saved, 8)
	Set row.LongOutputPerMTok = $List(saved, 9)
	Do row.%Save()
}

/// A new DecisionRef, which the test deletes the Usage rows of afterwards.
Method NewRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs _ $ListBuild(ref)
	Quit ref
}

/// Saves a Usage row of the DecisionRef.
Method AddRow(ref As %String, model As %String, input As %Integer, completion As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.Usage).%New()
	Set row.DecisionRef = ref
	Set row.OwnerRef = "instance"
	Set row.Model = model
	Set row.InputTokens = input
	Set row.OutputTokens = completion
	Set row.CacheReadTokens = cacheRead
	Set row.CacheWriteTokens = cacheWrite
	Set row.CostUSD = cost
	Do $$$AssertStatusOK(row.%Save(), "a Usage row of "_model_" is saved")
}

}
