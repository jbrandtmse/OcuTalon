/// Tests of the session starts of Conversation (Story 41.3; AD-21, AD-7, AD-30). Safe on a slot: no production runs there, so the tests call OnRequest on shadow instances of
/// OcuTalon.Test.Core.ConversationStartProbe, which hands each request to Decide to OcuTalon.Test.Core.DecideDouble and records the context of every request that Conversation builds;
/// Deliver hands the answers back, as the framework would. A session start is the session's first turn of its local day, a turn that is fresh, and the turn after a reply with
/// SessionRotated; the turn request of a session start carries the context {"sessionStart":1} and no other request carries one. The tests that run real turns take the time of the
/// turns from the clock, so their expected values come from the CreatedAt that each Turn reads back, never from the wall clock.
///   - TestFirstOfDay: the first turn of a session, and a turn after an earlier turn of another day, start a session; the second turn of a day does not;
///   - TestFresh: the turn after a tainted reply, and the retry after a broken session, start a session;
///   - TestAfterRotation: the turn after a reply with SessionRotated starts a session, and the turn after that does not;
///   - TestOtherTurnsUnchanged: a turn of the same day that continues, and its Busy resend, carry no context; no decide request carries one; and the Input of such a request is that of Render(item);
///   - TestRotationKept: the Turn keeps the reply's SessionRotated, 1 for rotated and 0 for reply;
///   - TestStartsSessionBoundaries: StartsSession with turns at 23:59:59 and 00:00:00, a refused earlier turn, a fresh turn and a rotated reply;
///   - TestStartsSessionReadFailure: a turn whose session can't be read, one whose time can't be read, and one whose session's last replied turn can't be read (through the
///     probe) start a session, each with one warning; a fresh turn reads nothing.
Class OcuTalon.Test.Core.ConversationSessionStart Extends %UnitTest.TestCase
{

/// The context of a session start, as JSON.
Parameter START = "{""sessionStart"":1}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("ConversationSessionStart", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Core.DecideDouble).Clear($Piece(..Sessions, ",", i))
	}
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// The first turn of a session starts a session; so does a turn after an earlier turn of another day; the second turn of a day does not. The decide request of every turn carries none.
Method TestFirstOfDay()
{
	Set session = ..Session("firstday")
	Set first = ..Say(session, "zz first", "firstday1")
	Set second = ..Say(session, "zz second", "firstday2")
	Set contexts = ..Contexts("turn")
	Do $$$AssertEquals($ListLength(contexts), 2, "two turn requests")
	Do $$$AssertEquals($List(contexts, 1), ..#START, "the first turn of a session starts a session")
	Do $$$AssertEquals($List(contexts, 2), ..StartIfNewDay(first, second), "the second turn starts one only when the local day has changed since the first")
	Do $$$AssertEquals(..Contexts("decide"), $ListBuild("", ""), "and no decide request carries a context")
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set other = ..Session("otherday")
	Set old = ##class(OcuTalon.Test.Data.Fixture).Turn(other, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -172800), "done", "zz two days ago")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_old
	Do ..Say(other, "zz today", "otherday1")
	Do $$$AssertEquals(..Contexts("turn"), $ListBuild(..#START), "a turn after an earlier turn of another day starts a session")
}

/// A turn after a tainted reply is fresh and starts a session; so does the retry after a broken session.
Method TestFresh()
{
	Set session = ..Session("fresh")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("tainted", "reply"))
	Do ..Say(session, "zz first", "fresh1")
	Do ..Say(session, "zz second", "fresh2")
	Set contexts = ..Contexts("turn")
	Do $$$AssertEquals($ListLength(contexts), 2, "two turn requests")
	Set turns = ..TurnCalls()
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode"), "fresh", "the turn after a tainted reply is fresh")
	Do $$$AssertEquals($List(contexts, 2), ..#START, "and it starts a session, whatever the day")
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set session = ..Session("broken")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("reply", "broken", "reply"))
	Set first = ..Say(session, "zz first", "broken1")
	Set second = ..Say(session, "zz second", "broken2")
	Set contexts = ..Contexts("turn")
	Do $$$AssertEquals($ListLength(contexts), 3, "three turn requests: the first turn's, the second turn's and its retry")
	Set turns = ..TurnCalls()
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode")_"|"_..Call($List(turns, 3), "sessionMode"), "continue|fresh", "the retry after a broken session is fresh")
	Do $$$AssertEquals($List(contexts, 2), ..StartIfNewDay(first, second), "the broken attempt itself is a start only by the day")
	Do $$$AssertEquals($List(contexts, 3), ..#START, "the retry starts a session")
	Do $$$AssertEquals(..Contexts("decide"), $ListBuild("", ""), "and no decide request carries a context")
}

/// The turn after a reply with SessionRotated starts a session; the turn after that, whose last reply was not rotated, does not (unless the day changed).
Method TestAfterRotation()
{
	Set session = ..Session("rotation")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("rotated", "reply", "reply"))
	Set first = ..Say(session, "zz first", "rotation1")
	Set second = ..Say(session, "zz second", "rotation2")
	Set third = ..Say(session, "zz third", "rotation3")
	Set contexts = ..Contexts("turn")
	Do $$$AssertEquals($ListLength(contexts), 3, "three turn requests")
	Do $$$AssertEquals(first.SessionRotated_"|"_second.SessionRotated, "1|0", "the first reply rotated the session and the second did not")
	Do $$$AssertEquals($List(contexts, 2), ..#START, "the turn after a reply with SessionRotated starts a session")
	Do $$$AssertEquals($List(contexts, 3), ..StartIfNewDay(second, third), "the turn after that starts one only when the day changed")
	Set turns = ..TurnCalls()
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode"), "continue", "the rotation made the request a start without making it fresh")
}

/// A turn of the same day that continues, and its Busy resend, carry no context; no decide request carries one; and the Input of such a request is the Input that Render(item) gives.
Method TestOtherTurnsUnchanged()
{
	Set session = ..Session("unchanged")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("reply", "busy", "reply"))
	Set first = ..Say(session, "zz first", "unchanged1")
	Set second = ..Say(session, "zz second", "unchanged2")
	Set contexts = ..Contexts("turn")
	Do $$$AssertEquals($ListLength(contexts), 3, "three turn requests: the first turn's, the second turn's and its resend after Busy")
	Set expected = ..StartIfNewDay(first, second)
	Do $$$AssertEquals($List(contexts, 2)_"|"_$List(contexts, 3), expected_"|"_expected, "the Busy resend of the second turn carries the same context as its first request")
	Do $$$AssertEquals(..Contexts("decide"), $ListBuild("", ""), "no decide request carries a context")
	Set turns = ..TurnCalls()
	Do $$$AssertEquals($ListLength(turns), 3, "the calls are the three turn requests")
	Set probe = ..NewProbe()
	Set item = probe.ItemFor(second)
	Set plain = ##class(OcuTalon.Agent.Input).Render(item)
	Set plain = ..AfterPreamble(plain)
	If expected = "" {
		Do $$$AssertEquals(..AfterPreamble(..Call($List(turns, 3), "input")), plain, "the Input of the resend that carries no context is that of Render(item)")
		Do $$$AssertEquals(..AfterPreamble(..Call($List(turns, 2), "input")), plain, "so is the Input of the request that carries no context")
	}
	Set request = ##class(OcuTalon.Core.Intake).RequestFor(item, "turn", "", "")
	Do $$$AssertEquals(..AfterPreamble(request.Input), plain, "and RequestFor with no context renders as Render(item)")
	Set with = ##class(OcuTalon.Core.Intake).RequestFor(item, "decide", "zztrace", 7, {"sessionStart": 1})
	Set without = ##class(OcuTalon.Core.Intake).RequestFor(item, "decide", "zztrace", 7)
	Do $$$AssertEquals(..Fields(with), ..Fields(without), "RequestFor with a context sets every code-written field as it does with none")
	Do $$$AssertEquals(..Fields(with), "decide|"_item.Provenance_"|"_second.ItemId_"|"_##class(OcuTalon.Core.Intake).SummaryOf(item)_"|"_item.SessionRef_"|zztrace|"_item.Channel_"|7", "and those are the item's")
}

/// The code-written fields of a request, the Input aside: Kind, Provenance, ItemId, Summary, OwnerRef, TraceRef, Channel and ThreadSessionId.
ClassMethod Fields(request As OcuTalon.Bridge.Msg.Request) As %String [ Private ]
{
	Quit request.Kind_"|"_request.Provenance_"|"_request.ItemId_"|"_request.Summary_"|"_request.OwnerRef_"|"_request.TraceRef_"|"_request.Channel_"|"_request.ThreadSessionId
}

/// The Input without its first line, the preamble, which carries the clock to the minute.
ClassMethod AfterPreamble(input As %String) As %String [ Private ]
{
	Quit $Piece(input, $Char(10), 2, *)
}

/// The Turn keeps the reply's SessionRotated: 1 for a rotated reply and 0 for a plain one.
Method TestRotationKept()
{
	Set session = ..Session("kept")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("rotated", "reply"))
	Set first = ..Say(session, "zz first", "kept1")
	Set second = ..Say(session, "zz second", "kept2")
	Do $$$AssertEquals(first.State_"|"_first.SessionRotated, "done|1", "a rotated reply leaves SessionRotated 1 on the Turn")
	Do $$$AssertEquals(second.State_"|"_second.SessionRotated, "done|0", "a plain reply leaves 0")
}

/// StartsSession with fixed times: a turn at 23:59:59 and one at 00:00:00 are of two local days; a refused earlier turn of the day does not count; a fresh turn is a start; the turn
/// after a rotated reply is a start.
Method TestStartsSessionBoundaries()
{
	Set conversation = "OcuTalon.Core.Conversation"
	Set session = ..Session("bounds")
	Set evening = ..Fix(session, "2030-06-14T23:59:59", "done", 0)
	Set midnight = ..Fix(session, "2030-06-15T00:00:00", "done", 0)
	Set later = ..Fix(session, "2030-06-15T00:00:01", "done", 0)
	Set last = ..Fix(session, "2030-06-15T23:59:59", "done", 0)
	Set nextDay = ..Fix(session, "2030-06-16T00:00:00", "done", 0)
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", evening, 0), 1, "the first turn of the session starts a session")
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", midnight, 0), 1, "a turn at 00:00:00 is the first of its day, after a turn at 23:59:59 the day before")
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", later, 0), 0, "a turn at 00:00:01 is the second of that day")
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", last, 0), 0, "a turn at 23:59:59 is of the same day as the turns of 00:00:00 and 00:00:01")
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", nextDay, 0), 1, "a turn at 00:00:00 the next day starts a session")
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", later, 1), 1, "a fresh turn starts a session, however the day went")
	Set other = ..Session("refusedearlier")
	Do ..Fix(other, "2030-06-15T09:00:00", "refused", 0)
	Set only = ..Fix(other, "2030-06-15T09:00:05", "queued", 0)
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", only, 0), 1, "a refused earlier turn of the day does not count: the next turn is the first")
	Set rotated = ..Session("rotatedlast")
	Set one = ..Fix(rotated, "2030-06-15T09:00:00", "done", 1)
	Set two = ..Fix(rotated, "2030-06-15T09:30:00", "running", 0)
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", two, 0), 1, "the turn after a reply with SessionRotated is a start, though it is the second of its day")
	Do ..Reply(two, 0)
	Set three = ..Fix(rotated, "2030-06-15T10:00:00", "running", 0)
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", three, 0), 0, "and the turn after a plain reply is not")
	Set plainSession = ..Session("plainlast")
	Do ..Fix(plainSession, "2030-06-15T09:00:00", "done", 0)
	Set next = ..Fix(plainSession, "2030-06-15T09:30:00", "running", 0)
	Do $$$AssertEquals($ClassMethod(conversation, "StartsSession", next, 0), 0, "a second turn of the day after a plain reply is not a start")
}

/// A session that can't be read, and a time that can't be read, start a session, each with one warning.
Method TestStartsSessionReadFailure()
{
	Set mark = ..LastLog()
	Set turn = ##class(OcuTalon.Data.Turn).%New()
	Set turn.SessionRef = ""
	Set turn.CreatedAt = "2030-06-15T09:00:00Z"
	Set turn.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).StartsSession(turn, 0), 1, "a session that can't be read starts a session")
	Do $$$AssertEquals(..Warnings(mark), 1, "with one warning")
	Set session = ..Session("unreadable")
	Set turn.SessionRef = session
	Set turn.CreatedAt = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).StartsSession(turn, 0), 1, "a turn whose time can't be read starts a session")
	Do $$$AssertEquals(..Warnings(mark), 2, "with one more warning")
	Set turn.CreatedAt = "2030-06-15T09:00:00Z"
	Set turn.SessionRef = ""
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).StartsSession(turn, 1), 1, "a fresh turn starts a session, and reads nothing")
	Do $$$AssertEquals(..Warnings(mark), 2, "so there is no warning, though its session can't be read")
	Set probe = "OcuTalon.Test.Core.ConversationStartProbe"
	Set other = ..Session("lastunread")
	Do ..Fix(other, "2030-06-15T09:00:00", "done", 0)
	Set next = ..Fix(other, "2030-06-15T09:30:00", "running", 0)
	Do $$$AssertEquals($ClassMethod(probe, "StartsSession", next, 0), 0, "the second turn of a day after a plain reply is not a start")
	Do $$$AssertEquals(..Warnings(mark), 2, "and is no warning")
	Set ^||ConversationStartProbe("failLast") = 1
	Set starts = $ClassMethod(probe, "StartsSession", next, 0)
	Kill ^||ConversationStartProbe
	Do $$$AssertEquals(starts, 1, "when the last replied turn can't be read, it starts a session")
	Do $$$AssertEquals(..Warnings(mark), 3, "with one more warning")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass IN (?, ?) AND SourceMethod = ?", mark, "OcuTalon.Core.Conversation", probe, "StartsSession")
}

/// --- helpers ---
/// A fixture session, kept for the clean-up; the double's scripts for it are cleared.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzstart" _ ..Number _ name)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Set ..Sessions = ..Sessions _ $Select(..Sessions = "": "", 1: ",") _ ref
	Do ##class(OcuTalon.Test.Core.DecideDouble).Clear(ref)
	Quit ref
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Core.ConversationStartProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.ConversationStartProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// A message of the session through the pipeline, to its end, and the Turn that it made. clientSuffix keeps the ClientId unique in the session.
Method Say(session As %String, text As %String, clientSuffix As %String) As OcuTalon.Data.Turn [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = "web"
	Set item.Provenance = "user"
	Set item.Text = text
	Set item.ClientId = "zzss" _ ..Number _ clientSuffix
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the Item is taken")
	Do probe.Deliver()
	Set turn = ##class(OcuTalon.Data.Ownership).TurnByClient(session, item.ClientId)
	Do $$$AssertEquals($IsObject(turn) && (turn.State = "done"), 1, "the turn is done")
	Quit turn
}

/// The contexts of the requests of a kind that Conversation built, in order, as a list of JSON texts ("" for none).
Method Contexts(kind As %String) As %List [ Private ]
{
	Set list = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("ConversationProbe", ..Number, "context", n), 1, entry)
		Quit:n=""
		If $List(entry, 1) = kind Set list = list _ $ListBuild($List(entry, 2))
	}
	Quit list
}

/// The numbers of the recorded calls that are Decide's turn requests, as a list.
Method TurnCalls() As %List [ Private ]
{
	Set list = ""
	For n = 1:1:+$Get(^OcuTalonTest("ConversationProbe", ..Number)) {
		If (..Call(n, "target") = "Decide") && (..Call(n, "kind") = "turn") Set list = list _ $ListBuild(n)
	}
	Quit list
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("ConversationProbe", ..Number, n, field))
}

/// The context that the second turn of a session carries when the first turn was a plain reply: a session start only when the local day of the two turns' CreatedAt differs.
Method StartIfNewDay(first As OcuTalon.Data.Turn, second As OcuTalon.Data.Turn) As %String [ Private ]
{
	Set one = $Piece(##class(OcuTalon.Data.Time).ToLocal(first.CreatedAt), "T", 1)
	Set two = $Piece(##class(OcuTalon.Data.Time).ToLocal(second.CreatedAt), "T", 1)
	Quit $Select(one = two: "", 1: ..#START)
}

/// A fixture turn of the session at a local date-time. A done turn has a reply decision, so that it is a replied turn; rotated is its SessionRotated.
Method Fix(session As %String, local As %String, state As %String, rotated As %Boolean) As OcuTalon.Data.Turn [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(session, ##class(OcuTalon.Data.Time).FromLocal(local), state, "zz " _ local)
	Set ..Refs = ..Refs _ "," _ ref
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
	If state = "done" Set turn.TurnDecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn.SessionRotated = rotated
	Do $$$AssertStatusOK(turn.%Save(), "a fixture turn is saved")
	Quit turn
}

/// Makes the turn a replied one: done, with a reply decision and the reply's SessionRotated.
Method Reply(turn As OcuTalon.Data.Turn, rotated As %Boolean) [ Private ]
{
	Set turn.State = "done"
	Set turn.TurnDecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn.SessionRotated = rotated
	Do $$$AssertStatusOK(turn.%Save(), "the reply is kept")
}

/// The number of the newest row of the event log.
Method LastLog() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings of StartsSession in the event log after the mark, run as Conversation's or as the probe's.
Method Warnings(mark As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND SourceClass IN (?, ?) AND SourceMethod = ? AND Type = 3", mark, "OcuTalon.Core.Conversation", "OcuTalon.Test.Core.ConversationStartProbe", "StartsSession")
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
