/// Tests of what the digest says needs the user (Story 17.6; AD-14, AD-20, FR-35, Q4). Safe on a slot: no production runs; OcuTalon.Digest.NeedsYou reads
/// fixture rows through the ownership API (Decision, Incident and Handled rows of fixture sessions).
///   - TestOrder: one failed row, two unhandled tell-now Decisions, one handled Decision and one incident awaiting approval give four entries in the order
///     row, newer Decision, older Decision, incident, each by its code-written name, and the handled Decision, a Decision of another outcome and an
///     incident in another state are left out;
///   - TestActIncidentOnce: an act Decision that is the DecisionRef of an awaiting incident, and one whose ItemId is the incident's Ref, appear once, as the
///     incident, and an act Decision of an incident that is not awaiting stays a Decision;
///   - TestIncidentWithoutDecision: an incident with no diagnose Decision is named by its production;
///   - TestHandledLeftOut: a Decision that is marked handled is not listed, and is listed again when it is not;
///   - TestOverflow: with more entries than the bound the newest five are named, in the order of the list, and the count is the total (rows, Decisions
///     and incidents together); with 200 unhandled Decisions five are named, count is 200 and more is 195;
///   - TestEmptyItemId: a Decision with no ItemId is listed, and is no incident's own;
///   - TestOverflowEmptyTime: an entry with no time is the oldest: with more entries than the bound it is the one that is dropped;
///   - TestEvalOwner (Story 17.7): for the owner eval (a digest case) the list holds the failed rows alone, in their order, although eval has an unhandled
///     tell-now Decision and an incident awaiting approval; with no failed row it is empty;
///   - TestNothing: no entry gives a count of 0, no names and no overflow;
///   - TestWindow (Story 12.12): with a window start, an unhandled tell-now or act Decision recorded before it is not counted and one at or after it
///     is, a handled one is not, and a failed row and an incident awaiting approval older than the start are counted;
///   - TestNoWindow: with no window start the same fixtures count every unhandled tell-now and act Decision;
///   - TestWindowUndated: a Decision with no RecordedAt counts whatever the window start;
///   - TestProcessWindow: a digest Compose passes its WindowStart on, so the digest names only the Decision recorded inside the window;
///   - TestProcessNoUpperBound: a Decision recorded after the Compose's WindowEnd is still counted.
Class OcuTalon.Test.Digest.NeedsYou Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Digest.NeedsYou";

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The ids of the Handled rows made, comma-separated.
Property Handled As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Handled, ",") {
		If $Piece(..Handled, ",", i) '= "" Do ##class(OcuTalon.Data.Handled).%DeleteId($Piece(..Handled, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = "", ..Handled = ""
	Quit $$$OK
}

Method Keep(ref As %String)
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzneeds")
	Do ..Keep(ref)
	Quit ref
}

/// The UTC time that many minutes after 2030-06-03T10:00:00Z.
Method At(minutes As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds("2030-06-03T10:00:00Z", 60 * minutes)
}

/// A decide Decision of the owner at the minute, with the summary and outcome; its Ref. fields adds members.
Method Decision(owner As %String, minute As %Integer, summary As %String, outcome As %String = "tellnow", fields As %DynamicObject = "") As %String
{
	Set all = {"Summary": (summary), "Outcome": (outcome)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ..At(minute), all)
	Do ..Keep(ref)
	Quit ref
}

/// An incident of the owner in the state, noticed at the minute, whose diagnose Decision is decisionRef; its Ref.
Method Incident(owner As %String, minute As %Integer, state As %String, decisionRef As %String = "", production As %String = "Orders.Production") As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..At(minute), "ZZNS", production, {"State": (state), "DecisionRef": (decisionRef)})
	Do ..Keep(ref)
	Quit ref
}

Method Handle(ref As %String)
{
	Set row = ##class(OcuTalon.Data.Handled).%New()
	Set row.Ref = ref
	Set row.SessionRef = "zz"
	Set row.HandledAt = ..At(1)
	Set row.Channel = "web"
	Do $$$AssertStatusOK(row.%Save(), "the Decision is marked handled")
	Set ..Handled = ..Handled_$Select(..Handled = "": "", 1: ",")_row.%Id()
}

Method Failed(entry As %String, finding As %String, minute As %Integer) As %DynamicObject
{
	Quit {"result": "failed", "entry": (entry), "finding": (finding), "checkedAt": (..At(minute))}
}

/// The names of the result, joined with "|".
Method Names(result As %DynamicObject) As %String
{
	Set names = ""
	Set iterator = result.names.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set names = names_$Select(names = "": "", 1: "|")_name
	}
	Quit names
}

Method List(session As %String, failed As %DynamicArray = "", windowStart As %String = "") As %DynamicObject
{
	Set result = $ClassMethod(..#CLASS, "List", session, $Select($IsObject(failed): failed, 1: []), .sc, windowStart)
	Do $$$AssertStatusOK(sc, "the list is read")
	Quit result
}

Method TestOrder()
{
	Set session = ..Session()
	Set other = ..Session()
	Do ..Decision(session, 10, "Older mail")
	Do ..Decision(session, 20, "Newer mail")
	Set handled = ..Decision(session, 30, "Handled mail")
	Do ..Handle(handled)
	Do ..Decision(session, 40, "Ignored mail", "ignore")
	Do ..Decision(other, 50, "Another session's mail")
	Set diagnosis = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "diagnose", ..At(5), {"Summary": "3 failures at Orders.Operation"})
	Do ..Keep(diagnosis)
	Do ..Incident(session, 5, "awaiting_approval", diagnosis)
	Do ..Incident(session, 6, "open", diagnosis)
	Set result = ..List(session, [(..Failed("Billing source", "5 messages queued", 3))])
	Do $$$AssertEquals(..Names(result), "Billing source: 5 messages queued|Newer mail|Older mail|3 failures at Orders.Operation", "the failed row, the Decisions newest first, then the incident")
	Do $$$AssertEquals(result.count_"|"_result.more, "4|0", "four entries and no overflow")
}

Method TestActIncidentOnce()
{
	Set session = ..Session()
	Set act = ..Decision(session, 10, "Act on the failures", "act")
	Set incident = ..Incident(session, 11, "awaiting_approval", act)
	Set again = ..Decision(session, 12, "Same incident, by item", "act", {"ItemId": (incident)})
	Set result = ..List(session)
	Do $$$AssertEquals(..Names(result), "Act on the failures", "both Decisions of the incident appear once, as the incident")
	Do $$$AssertEquals(result.count, 1, "count is 1")
	Set later = ..Session()
	Set closedAct = ..Decision(later, 10, "Act, but the incident is open", "act")
	Do ..Incident(later, 11, "open", closedAct)
	Set result = ..List(later)
	Do $$$AssertEquals(..Names(result), "Act, but the incident is open", "an act Decision of an incident that is not awaiting stays a Decision")
}

Method TestIncidentWithoutDecision()
{
	Set session = ..Session()
	Do ..Incident(session, 10, "awaiting_approval", , "Orders.Production")
	Set result = ..List(session)
	Do $$$AssertEquals(..Names(result), "Orders.Production", "an incident with no Decision is named by its production")
}

Method TestHandledLeftOut()
{
	Set session = ..Session()
	Set ref = ..Decision(session, 10, "Mail to handle")
	Do $$$AssertEquals(..List(session).count, 1, "an unhandled Decision is listed")
	Do ..Handle(ref)
	Do $$$AssertEquals(..List(session).count, 0, "and a handled one is not")
}

Method TestOverflow()
{
	Set session = ..Session()
	For i = 1:1:3 {
		Do ..Decision(session, 10 * i, "Mail "_i)
	}
	Set diagnosis = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "diagnose", ..At(1), {"Summary": "Incident at 55"})
	Do ..Keep(diagnosis)
	Do ..Incident(session, 55, "awaiting_approval", diagnosis)
	Set result = ..List(session, [(..Failed("Row at 5", "oldest", 5)), (..Failed("Row at 25", "middle", 25)), (..Failed("Row at 45", "late", 45))])
	Do $$$AssertEquals(result.count_"|"_result.more_"|"_result.names.%Size(), "7|2|5", "seven entries: five named and two more")
	Do $$$AssertEquals(..Names(result), "Row at 25: middle|Row at 45: late|Mail 3|Mail 2|Incident at 55", "the five newest by time are kept, in the order of the list")
}

Method TestOverflow200()
{
	Set session = ..Session()
	For i = 1:1:200 {
		Do ..Decision(session, i, "Mail "_i)
	}
	Set result = ..List(session)
	Do $$$AssertEquals(result.count_"|"_result.more_"|"_result.names.%Size(), "200|195|5", "200 entries: five named and 195 more")
	Do $$$AssertEquals(..Names(result), "Mail 200|Mail 199|Mail 198|Mail 197|Mail 196", "the five newest, newest first")
}

Method TestEmptyItemId()
{
	Set session = ..Session()
	Do ..Decision(session, 10, "Act with no item", "act", {"ItemId": ""})
	Do ..Incident(session, 11, "awaiting_approval", , "Orders.Production")
	Set result = ..List(session)
	Do $$$AssertEquals(..Names(result), "Act with no item|Orders.Production", "a Decision with no ItemId is listed, and the incident beside it")
	Do $$$AssertEquals(result.count, 2, "count is 2")
}

Method TestOverflowEmptyTime()
{
	Set session = ..Session()
	For i = 1:1:3 {
		Do ..Decision(session, 10 * i, "Mail "_i)
	}
	Set undated = {"result": "failed", "entry": "Undated row", "finding": "no time", "checkedAt": ""}
	Set result = ..List(session, [(..Failed("Row at 25", "middle", 25)), (..Failed("Row at 45", "late", 45)), (undated)])
	Do $$$AssertEquals(result.count_"|"_result.more_"|"_result.names.%Size(), "6|1|5", "six entries: five named and one more")
	Do $$$AssertEquals(..Names(result), "Row at 25: middle|Row at 45: late|Mail 3|Mail 2|Mail 1", "the entry with no time is the oldest, so it is the one dropped")
}

Method TestEvalOwner()
{
	Set owner = ##class(OcuTalon.Data.Ownership).#EVAL
	Do ..Decision(owner, 10, "Eval mail")
	Set diagnosis = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "diagnose", ..At(5), {"Summary": "An eval diagnosis"})
	Do ..Keep(diagnosis)
	Do ..Incident(owner, 5, "awaiting_approval", diagnosis)
	Set result = ..List(owner, [(..Failed("Billing source", "5 messages queued", 3)), (..Failed("Orders production", "", 4))])
	Do $$$AssertEquals(..Names(result), "Billing source: 5 messages queued|Orders production", "only the failed rows, in their order")
	Do $$$AssertEquals(result.count_"|"_result.more, "2|0", "two entries and no overflow")
	Set result = ..List(owner)
	Do $$$AssertEquals(result.%ToJSON(), "{""count"":0,""names"":[],""more"":0}", "with no failed row nothing needs the owner eval, whatever its Decisions and incidents")
	Set session = ..Session()
	Do ..Decision(session, 10, "A session's mail")
	Set result = ..List(session)
	Do $$$AssertEquals(..Names(result), "A session's mail", "control: a session still lists its Decisions")
}

/// The fixtures of the window tests, with W = At(100): a failed row checked at At(5), an incident awaiting approval noticed at At(10), unhandled tell-now
/// Decisions at At(50), At(100) and At(150), a handled tell-now at At(120) and an act Decision at At(60). Returns the session.
Method WindowFixtures() As %String
{
	Set session = ..Session()
	Do ..Decision(session, 50, "Old mail")
	Do ..Decision(session, 60, "Old act", "act")
	Do ..Decision(session, 100, "Mail at the start")
	Do ..Decision(session, 150, "Late mail")
	Do ..Handle(..Decision(session, 120, "Handled mail"))
	Do ..Incident(session, 10, "awaiting_approval")
	Quit session
}

Method TestWindow()
{
	Set session = ..WindowFixtures()
	Set result = ..List(session, [(..Failed("Billing source", "5 messages queued", 5))], ..At(100))
	Do $$$AssertEquals(..Names(result), "Billing source: 5 messages queued|Late mail|Mail at the start|Orders.Production", "the failed row, the Decisions from the start on (newest first) and the incident")
	Do $$$AssertEquals(result.count_"|"_result.more, "4|0", "four entries: the Decisions before the start and the handled one are not counted")
}

Method TestNoWindow()
{
	Set session = ..WindowFixtures()
	Set result = ..List(session, [(..Failed("Billing source", "5 messages queued", 5))])
	Do $$$AssertEquals(..Names(result), "Late mail|Mail at the start|Old act|Old mail|Orders.Production", "with no window every unhandled tell-now and act Decision counts: the five newest entries are named")
	Do $$$AssertEquals(result.count_"|"_result.more, "6|1", "six entries (the failed row is the oldest, so it is the one more), the handled Decision still left out")
}

Method TestWindowUndated()
{
	Set session = ..Session()
	Do ..Decision(session, 50, "Old mail")
	Do ..Decision(session, 0, "Undated mail", "tellnow", {"RecordedAt": ""})
	Set result = ..List(session, "", ..At(100))
	Do $$$AssertEquals(..Names(result), "Undated mail", "the Decision with no time counts and the old dated one does not")
}

Method TestProcessWindow()
{
	Set session = ..Session()
	Do ..Decision(session, 50, "Old mail")
	Do ..Decision(session, 150, "Late mail")
	Do $$$AssertEquals(..DigestNeeds(session), "digest.needsYouOne|Late mail", "the digest names the one Decision recorded inside the window")
}

Method TestProcessNoUpperBound()
{
	Set session = ..Session()
	Do ..Decision(session, 50, "Old mail")
	Do ..Decision(session, 150, "Late mail")
	Do ..Decision(session, 250, "Later mail")
	Do $$$AssertEquals($Piece(..DigestNeeds(session), "|", 1), "digest.needsYou", "the Decision recorded after the window's end counts too: two things need the owner")
}

/// Handles a digest Compose of the session (WindowStart At(100), WindowEnd At(200)) in a ProcessProbe and returns the key and the "what" slot of the digest's
/// needs-you part, joined with "|" ("" when the digest has none).
Method DigestNeeds(session As %String) As %String [ Private ]
{
	Set probe = "OcuTalon.Test.Digest.ProcessProbe"
	Do $ClassMethod(probe, "Reset")
	Do $ClassMethod(probe, "Feed", [])
	Set was = $ClassMethod(probe, "ForgetChannels")
	Set found = ""
	Try {
		Set host = ##class(Ens.Host).GetShadowInstance("class||"_probe, .sc)
		Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
		Set host.OwnChannels = "web"
		Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
		Set compose.SessionRef = session
		Set compose.Kind = "scheduled"
		Set compose.DueAt = ..At(200)
		Set compose.WindowStart = ..At(100)
		Set compose.WindowEnd = ..At(200)
		Kill response
		Do $$$AssertStatusOK(host.OnRequest(compose, .response), "the Compose is handled")
		Set record = $ClassMethod(probe, "Record", "notice", 1)
		Do $$$AssertTrue(record '= "", "a digest is sent")
		Set slots = {}.%FromJSON($List(record, 5))
		Set iterator = slots.parts.%GetIterator()
		While iterator.%GetNext(, .part) {
			If (part.key = "digest.needsYouOne") || (part.key = "digest.needsYou") Set found = part.key_"|"_part.slots.what
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the digest test threw: "_exception.DisplayString())
	}
	Do $ClassMethod(probe, "PutChannelsBack", was)
	Do $ClassMethod(probe, "Clean", session)
	Do $ClassMethod(probe, "Reset")
	Quit found
}

Method TestNothing()
{
	Set session = ..Session()
	Set result = ..List(session)
	Do $$$AssertEquals(result.%ToJSON(), "{""count"":0,""names"":[],""more"":0}", "nothing needs the user")
}

}
