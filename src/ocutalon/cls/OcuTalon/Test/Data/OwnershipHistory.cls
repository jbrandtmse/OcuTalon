/// Tests of Ownership.HistoryDecisions, Ownership.HistoryIncidents and the Rows kinds historyDecisions, historyDecisionTotal, historyIncidents and historyIncidentTotal
/// (Story 25.2; AD-4, AD-13, AD-18). Safe on a slot: no production is needed. The sessions are Refs only (the read takes any Ref); the rows are fixtures
/// (Test.Data.Fixture), each recorded under its Ref and removed after every test.
///   - TestFilters: each filter alone and combined (outcome, channel, day, fallback), outcome tellnow matching a fallback row whose stored Outcome is not
///     tellnow, a channel taken from the usage rows of the decision, a decision with no usage row matching only when no channel is set;
///   - TestDayEdges: the local-day window in two zones, at local 23:59:59 and 00:00:00;
///   - TestPaging: 26 rows give two pages (25, then 1), a page past the last is empty with the page count, newest first and then newest ID first;
///   - TestIsolation: another session's, eval's, instance's and no owner's decisions, and decisions of another kind, are never in a list or a count; the same for incidents,
///     plus an incident that was not noticed;
///   - TestInstanceIncidents: an instance incident of a production the session's check watches is listed on a local install and never on the online demo;
///   - TestIncidentPaging: the incident list's order, pages and page count;
///   - TestRefusals: the four kinds refuse an empty, eval or instance owner, and the reads refuse a filter or page that is not one of the allowed values.
Class OcuTalon.Test.Data.OwnershipHistory Extends OcuTalon.Test.Bridge.ZoneCase
{

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Kill ^||OcuTalonTest.OwnHistory
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Kill ^||OcuTalonTest.OwnHistory
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit ##super(testname)
}

/// Each filter alone and combined, over six decisions of one session.
Method TestFilters()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	Do ..AssertNames(a, "", "", "", "", "d2,d1,d4,d3,d5,d6", "no filter: newest first")
	Do ..AssertNames(a, "ignore", "", "", "", "d1", "outcome ignore")
	Do ..AssertNames(a, "digest", "", "", "", "d2", "outcome digest leaves out the fallback row whose stored outcome is digest")
	Do ..AssertNames(a, "act", "", "", "", "d4", "outcome act")
	Do ..AssertNames(a, "tellnow", "", "", "", "d3,d5,d6", "outcome tellnow matches the stored tellnow and every fallback, as the chip shows it")
	Do ..AssertNames(a, "", "", "", "yes", "d5,d6", "fallback yes")
	Do ..AssertNames(a, "", "", "", "no", "d2,d1,d4,d3", "fallback no")
	Do ..AssertNames(a, "", "", ..Date(0), "", "d2,d1", "day today")
	Do ..AssertNames(a, "", "", ..Date(1), "", "d4,d3", "day yesterday")
	Do ..AssertNames(a, "", "", ..Date(5), "", "", "a day with no row")
	Do ..AssertNames(a, "", "mailbox", "", "", "d2,d4", "channel mailbox, from the usage rows")
	Do ..AssertNames(a, "", "web", "", "", "d1,d6", "channel web, also through a second usage row")
	Do ..AssertNames(a, "", "phone", "", "", "d3", "channel phone")
	Do ..AssertNames(a, "", "telegram", "", "", "d6", "a decision with two usage rows matches the channel of either")
	Do ..AssertNames(a, "", "heartbeat", "", "", "", "a channel no usage row has")
	Do ..AssertNames(a, "act", "mailbox", "", "", "d4", "outcome and channel")
	Do ..AssertNames(a, "act", "web", "", "", "", "outcome and a channel that does not match")
	Do ..AssertNames(a, "tellnow", "", "", "yes", "d5,d6", "outcome tellnow and fallback yes")
	Do ..AssertNames(a, "tellnow", "", "", "no", "d3", "outcome tellnow and fallback no")
	Do ..AssertNames(a, "", "mailbox", ..Date(1), "", "d4", "channel and day")
	Do ..AssertNames(a, "act", "mailbox", ..Date(1), "no", "d4", "four filters")
	Do ..AssertNames(a, "digest", "mailbox", ..Date(1), "no", "", "four filters with no match")
	Do ..AssertNames(a, "", "mailbox", "", "yes", "", "a decision with no usage row never matches a channel (d5 is a fallback with none)")
}

/// The day filter is the local date, from its first instant to the first instant of the next, in zones whose midnight is not the UTC midnight.
Method TestDayEdges()
{
	For zone = "America/New_York", "Asia/Kolkata", "Pacific/Auckland" {
		Do ..PutZone(zone)
		Kill ^||OcuTalon.Bridge.Time
		Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
		Kill ^||OcuTalonTest.OwnHistory
		Do ..Dec(a, "e1", "ignore", 0, ..Date(2)_" 23:59:59", "")
		Do ..Dec(a, "e2", "ignore", 0, ..Date(1)_" 00:00:00", "")
		Do ..Dec(a, "e3", "ignore", 0, ..Date(1)_" 23:59:59", "")
		Do ..Dec(a, "e4", "ignore", 0, ..Date(0)_" 00:00:00", "")
		Do ..AssertNames(a, "", "", ..Date(1), "", "e3,e2", zone_": the day holds its first and its last second")
		Do ..AssertNames(a, "", "", ..Date(2), "", "e1", zone_": the day before ends at 23:59:59")
		Do ..AssertNames(a, "", "", ..Date(0), "", "e4", zone_": the next day starts at 00:00:00")
	}
}

/// 26 rows: two pages, newest first and then newest ID first; a page past the last is empty with the page count.
Method TestPaging()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set base = ##class(OcuTalon.Data.Time).FromLocal(..Date(1)_"T10:00:00")
	For i = 1:1:26 {
		Do ..DecAt(a, "p"_i, "act", 0, ##class(OcuTalon.Data.Time).AddSeconds(base, i * 60), "")
	}
	Do ..DecAt(a, "tie1", "act", 0, ##class(OcuTalon.Data.Time).AddSeconds(base, 0), "")
	Do ..DecAt(a, "tie2", "act", 0, ##class(OcuTalon.Data.Time).AddSeconds(base, 0), "")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", 1, .pages, .sc)
	Do $$$AssertStatusOK(sc, "page 1: OK")
	Do $$$AssertEquals(list.Count()_"|"_pages, "25|2", "page 1 holds 25 and there are two pages")
	Do $$$AssertEquals(..Name(list.GetAt(1))_"|"_..Name(list.GetAt(25)), "p26|p2", "page 1 runs from the newest to the 25th")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", 2, .pages, .sc)
	Do $$$AssertStatusOK(sc, "page 2: OK")
	Do $$$AssertEquals(list.Count()_"|"_pages_"|"_..Name(list.GetAt(1))_"|"_..Name(list.GetAt(2))_"|"_..Name(list.GetAt(3)), "3|2|p1|tie2|tie1", "page 2 holds the rest: the same time then newest ID first")
	For page = 3, 9999 {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", page, .pages, .sc)
		Do $$$AssertStatusOK(sc, "page "_page_": not an error")
		Do $$$AssertEquals(list.Count()_"|"_pages, "0|2", "page "_page_": empty, with the page count")
	}
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", 1, .pages, .sc)
	Do $$$AssertEquals(pages, 2, "the count of pages is the same for every page")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "act", "", "", "no", 2, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages, "3|2", "filters and a page together: the count follows the filters")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "ignore", "", "", "", 1, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages, "0|1", "no match: one page, no row")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(##class(OcuTalon.Bridge.Ids).NewRef(), "", "", "", "", 1, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages, "0|1", "a session with no row: one page, no row")
}

/// Another session's, eval's, instance's and no owner's decisions, decisions of another kind and un-noticed incidents are never listed or counted.
Method TestIsolation()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef(), b = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Dec(a, "a1", "act", 0, ..Date(0)_" 10:00:00", "web")
	Do ..Dec(b, "b1", "act", 0, ..Date(0)_" 10:01:00", "web")
	Do ..Dec("eval", "ev", "act", 0, ..Date(0)_" 10:02:00", "web")
	Do ..Dec("instance", "in", "act", 0, ..Date(0)_" 10:03:00", "web")
	Do ..Dec("", "no", "act", 0, ..Date(0)_" 10:04:00", "web")
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Row("a1"), "eval", {"Channel": "mailbox"})
	Do ..Dec(a, "ak", "act", 0, ..Date(0)_" 10:05:00", "web", "turn")
	Do ..AssertNames(a, "", "", "", "", "a1", "A's decisions: its own decide row only")
	Do ..AssertNames(b, "", "", "", "", "b1", "B's decisions: its own only")
	Do ..AssertNames(a, "act", "web", ..Date(0), "no", "a1", "A with every filter: its own only")
	Do ..AssertNames(a, "", "mailbox", "", "", "", "a usage row of another owner for A's decision is not a channel of A's")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", 1, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages, "1|1", "A's count holds its own row only")
	Set noticed = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Inc(a, "ia", noticed)
	Do ..Inc(a, "iu", "")
	Do ..Inc(b, "ib", noticed)
	Do ..Inc("eval", "ie", noticed)
	Do ..Inc("instance", "ii", noticed, "ZZNS", "Zz.Other")
	Do ..AssertIncidents(a, 1, "ia", "A's incidents: its own noticed one; not the un-noticed one, B's, eval's, nor the instance one of an unwatched production")
	Do ..AssertIncidents(b, 1, "ib", "B's incidents: its own noticed one only")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(##class(OcuTalon.Bridge.Ids).NewRef(), 1, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages, "0|1", "a session with no incident: no row, one page")
}

/// An instance incident is listed for a session whose check watches its production on a local install, and never on the online demo or for a session that does not watch.
Method TestInstanceIncidents()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef(), b = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.History")
	Set noticed = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Inc("instance", "ins", noticed, "ZZNS", "Zz.History")
	Do ..Inc(a, "own", ##class(OcuTalon.Data.Time).AddSeconds(noticed, -60))
	Do ..AssertIncidents(a, 2, "ins,own", "local install: the watching session lists the instance incident and its own, newest first")
	Do ..AssertIncidents(b, 0, "", "local install: a session that watches nothing lists no instance incident")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Do ..AssertIncidents(a, 1, "own", "online demo: only the session's own incident")
}

/// The incident list: newest NoticedAt first and then newest ID first, 25 to a page, the page count, a page past the last empty.
Method TestIncidentPaging()
{
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set base = ##class(OcuTalon.Data.Time).NowUtc()
	For i = 1:1:26 Do ..Inc(a, "n"_i, ##class(OcuTalon.Data.Time).AddSeconds(base, -i * 60))
	Do ..Inc(a, "tie1", ##class(OcuTalon.Data.Time).AddSeconds(base, -27 * 60))
	Do ..Inc(a, "tie2", ##class(OcuTalon.Data.Time).AddSeconds(base, -27 * 60))
	Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(a, 1, .pages, .sc)
	Do $$$AssertStatusOK(sc, "page 1: OK")
	Do $$$AssertEquals(list.Count()_"|"_pages_"|"_..Name(list.GetAt(1))_"|"_..Name(list.GetAt(25)), "25|2|n1|n25", "page 1 holds 25, newest first, and there are two pages")
	Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(a, 2, .pages, .sc)
	Do $$$AssertEquals(list.Count()_"|"_pages_"|"_..Name(list.GetAt(1))_"|"_..Name(list.GetAt(2))_"|"_..Name(list.GetAt(3)), "3|2|n26|tie2|tie1", "page 2 holds the rest, the same time newest ID first")
	For page = 3, 9999 {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(a, page, .pages, .sc)
		Do $$$AssertStatusOK(sc, "page "_page_": not an error")
		Do $$$AssertEquals(list.Count()_"|"_pages, "0|2", "page "_page_": empty, with the page count")
	}
}

/// The kinds refuse an empty, eval and instance owner; the reads refuse a bad filter or page, with an empty list and nothing read.
Method TestRefusals()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Seed(a)
	For owner = "", "eval", "instance", "EVAL", "Instance", "eval ", "EVAL  " {
		Set rows = $ClassMethod(probe, "Call", "historyDecisions", owner, .sc, "", "", "", "", "", "", "", "", "", "", 25, 0)
		Do $$$AssertStatusNotOK(sc, "historyDecisions: '"_owner_"' is not a session's Ref")
		Do $$$AssertEquals(rows.Count(), 0, "historyDecisions: with no rows")
		Set rows = $ClassMethod(probe, "Call", "historyDecisionTotal", owner, .sc, "", "", "", "", "", "", "", "", "", "")
		Do $$$AssertStatusNotOK(sc, "historyDecisionTotal: '"_owner_"' is not a session's Ref")
		Set rows = $ClassMethod(probe, "Call", "historyIncidents", owner, .sc, 1, 25, 0)
		Do $$$AssertStatusNotOK(sc, "historyIncidents: '"_owner_"' is not a session's Ref")
		Do $$$AssertEquals(rows.Count(), 0, "historyIncidents: with no rows")
		Set rows = $ClassMethod(probe, "Call", "historyIncidentTotal", owner, .sc, 1)
		Do $$$AssertStatusNotOK(sc, "historyIncidentTotal: '"_owner_"' is not a session's Ref")
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(owner, "", "", "", "", 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "HistoryDecisions: '"_owner_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "HistoryDecisions: with no rows")
		Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(owner, 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "HistoryIncidents: '"_owner_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "HistoryIncidents: with no rows")
	}
	Set rows = $ClassMethod(probe, "Call", "historyDecisions", a, .sc, "", "", "", "", "", "", "", "", "", "", 25, 0)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 6, "and gives its six decisions")
	For bad = "foo", "Tell now", "tellnow ", "TELLNOW", "ignore' OR '1'='1" {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, bad, "", "", "", 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "outcome '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "outcome '"_bad_"': with no rows")
	}
	For bad = "x", "Web", "web,phone", "web ", "mailbox' OR '1'='1" {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", bad, "", "", 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "channel '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "channel '"_bad_"': with no rows")
	}
	For bad = "1", "0", "Yes", "true", "yes ", "no'" {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", bad, 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "fallback '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "fallback '"_bad_"': with no rows")
	}
	For bad = "2026-13-01", "2026-02-30", "11/10/2026", "2026-1-1", "2026-11-10T00:00:00", "2026-11-10 ", "abc", "99999-01-01" {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", bad, "", 1, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "day '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "day '"_bad_"': with no rows")
	}
	For bad = 0, "01", "abc", 10000, "", -1, 1.5, "1x", "+1" {
		Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", bad, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "decisions page '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "decisions page '"_bad_"': with no rows")
		Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(a, bad, .pages, .sc)
		Do $$$AssertStatusNotOK(sc, "incidents page '"_bad_"' is refused")
		Do $$$AssertEquals(list.Count(), 0, "incidents page '"_bad_"': with no rows")
	}
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, "", "", "", "", 9999, .pages, .sc)
	Do $$$AssertStatusOK(sc, "page 9999 is the highest page and is read")
}

/// --- helpers ---
/// The local date YYYY-MM-DD of today minus ago days.
ClassMethod Date(ago As %Integer) As %String [ Private ]
{
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Quit $ZDate($ZDateH(today, 3) - ago, 3)
}

/// The name that Dec or Inc gave to the row of the ref, and "(unknown)" for a row nothing named.
ClassMethod Name(row As %Persistent) As %String [ Private ]
{
	If '$IsObject(row) Quit "(no row)"
	Quit $Get(^||OcuTalonTest.OwnHistory(row.Ref), "(unknown)")
}

/// The ref of the row that was named name.
ClassMethod Row(name As %String) As %String [ Private ]
{
	Quit $Get(^||OcuTalonTest.OwnHistory("name", name))
}

/// A decision of the owner at the local time "YYYY-MM-DD hh:mm:ss", named name, with a usage row of the channel when it is not "".
Method Dec(owner As %String, name As %String, outcome As %String, fallback As %Boolean, local As %String, channel As %String, kind As %String = "decide") [ Private ]
{
	Do ..DecAt(owner, name, outcome, fallback, ##class(OcuTalon.Data.Time).FromLocal($Piece(local, " ", 1)_"T"_$Piece(local, " ", 2)), channel, kind)
}

/// Dec at a UTC time.
Method DecAt(owner As %String, name As %String, outcome As %String, fallback As %Boolean, at As %String, channel As %String, kind As %String = "decide") [ Private ]
{
	Set fields = {"Outcome": (outcome), "Fallback": (fallback)}
	If fallback Set fields.FallbackReason = "no_key"
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, kind, at, fields)
	Set ^||OcuTalonTest.OwnHistory(ref) = name
	Set ^||OcuTalonTest.OwnHistory("name", name) = ref
	Set ..Refs = ..Refs_","_ref
	If channel '= "" Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref, owner, {"Channel": (channel), "RecordedAt": (at)})
}

/// An incident of the owner, named name, noticed at noticedAt ("" for none), on the namespace and production.
Method Inc(owner As %String, name As %String, noticedAt As %String, namespace As %String = "ZZNS", production As %String = "Zz.Production") [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticedAt, namespace, production)
	Set ^||OcuTalonTest.OwnHistory(ref) = name
	Set ^||OcuTalonTest.OwnHistory("name", name) = ref
	Set ..Refs = ..Refs_","_ref
}

/// Six decisions of session a: d1 to d4 with a channel each, d5 a fallback with no usage row (stored outcome digest), d6 a fallback with two usage rows (telegram, web).
Method Seed(a As %String) [ Private ]
{
	Do ..Dec(a, "d1", "ignore", 0, ..Date(0)_" 10:00:00", "web")
	Do ..Dec(a, "d2", "digest", 0, ..Date(0)_" 11:00:00", "mailbox")
	Do ..Dec(a, "d3", "tellnow", 0, ..Date(1)_" 10:00:00", "phone")
	Do ..Dec(a, "d4", "act", 0, ..Date(1)_" 12:00:00", "mailbox")
	Do ..Dec(a, "d5", "digest", 1, ..Date(2)_" 09:00:00", "")
	Do ..Dec(a, "d6", "ignore", 1, ..Date(3)_" 09:00:00", "telegram")
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Row("d6"), a, {"Channel": "web"})
}

/// The names of page 1 of the decisions that match the filters, comma-separated, equal to expected.
Method AssertNames(a As %String, outcome As %String, channel As %String, day As %String, fallback As %String, expected As %String, message As %String) [ Private ]
{
	Set list = ##class(OcuTalon.Data.Ownership).HistoryDecisions(a, outcome, channel, day, fallback, 1, .pages, .sc)
	Do $$$AssertStatusOK(sc, message_": OK")
	Set names = ""
	For i = 1:1:list.Count() Set names = names_$Select(names = "": "", 1: ",")_..Name(list.GetAt(i))
	Do $$$AssertEquals(names, expected, message)
}

/// The names of page 1 of the incidents the session sees, comma-separated, equal to expected, with count rows.
Method AssertIncidents(a As %String, count As %Integer, expected As %String, message As %String) [ Private ]
{
	Set list = ##class(OcuTalon.Data.Ownership).HistoryIncidents(a, 1, .pages, .sc)
	Do $$$AssertStatusOK(sc, message_": OK")
	Set names = ""
	For i = 1:1:list.Count() Set names = names_$Select(names = "": "", 1: ",")_..Name(list.GetAt(i))
	Do $$$AssertEquals(list.Count()_"|"_names, count_"|"_expected, message)
}

}
