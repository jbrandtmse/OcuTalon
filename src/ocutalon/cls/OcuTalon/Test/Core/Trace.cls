/// Tests of Core.Trace, the trace thread of a session and the position of an Item in Visual Trace (Story 2.9; AD-26, AD-4,
/// AD-13). Safe on a slot: the thread tests use fixture sessions and a second job that holds a session row's lock, and the
/// position tests make their own Ens.MessageHeader, Ens.Util.Log, Ens.Rule.Log and Ens.Util.IOLog rows in sessions of their
/// own. Every synthetic header carries a SuperSession of the run (zztrace<n>), so that Fixture.RemoveMessages removes it with the
/// log rows of its session.
///   - TestJoinStartsAndKeepsTheThread: a session with no thread gets "" and an OK status, and the row's lock stays held until
///     Started records the thread for the day; then Join gives that thread and holds nothing;
///   - TestNewThreadAfterLocalMidnight: the two sides of the instance zone's local midnight, found by stepping the UTC time
///     through Data.Time.ToLocal, are two days, so a thread of the one is not the other's;
///   - TestStartedWithoutASessionRecordsNothing: Started with no session row is an error and creates no row, and an empty
///     session id records nothing; both release the lock;
///   - TestBusyLockAndNoRowFail: a lock that another job holds makes Join wait about LOCKWAIT seconds and answer an error with
///     nothing held; a session with no row is an error too;
///   - TestPositionCountsAsVisualTraceDraws: the position of a header counts the headers and the event-log and rule-log rows
///     whose host is already on the diagram, with the events shown and hidden, and no I/O-log row;
///   - TestPositionAgreesWithVisualTrace: the same synthetic sessions, and others that hold log rows around every header, are laid
///     out by Visual Trace's own BuildTraceInfo (called as the page calls it for the trace role, with the events shown and hidden
///     and the I/O log not read), and the position of every header in that layout is the position Core.Trace gives it;
///   - TestPositionOfAnUnknownHeader: an unknown header is an error and leaves both positions empty;
///   - TestSecondJoinWaitsForTheFirstThread (QA): while one job holds a day's first message, another job's Join waits for the
///     lock, then reads the thread the first one recorded, even with the Session row open from before (as WebChatIn holds it),
///     so that two first messages of a day cannot start two threads;
///   - TestPositionAgreesWithVisualTraceOnRandomSessions (QA): 28 sessions of pseudo-random headers (ties in time, equal
///     source and target), event rows of every type and rule rows (hosts on and off the diagram, no host, MessageIds of every
///     kind, times at, before and after the headers') are laid out by Visual Trace's own BuildTraceInfo, and Position gives every
///     header the place of that layout, with the events shown and hidden.
/// The run's number is n from ^OcuTalonTest("Trace","n") (never reset); the lock holder's records are under ^OcuTalonTest("Trace",
/// "job", key), which the tests remove.
Class OcuTalon.Test.Core.Trace Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The SuperSessions of the synthetic headers of the run.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("Trace", "n"))
	Set ..Refs = ""
	Set ..Supers = []
	Kill ^OcuTalonTest("Trace", "job")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Kill ^OcuTalonTest("Trace", "job")
	Quit $SYSTEM.Status.OK()
}

/// A session with no thread: Join answers "" with an OK status and keeps the row's lock, which another job cannot take. Started
/// records the id with the day of now and releases the lock, which another job can then take; Join then answers the thread, and
/// holds nothing.
Method TestJoinStartsAndKeepsTheThread()
{
	Set ref = ..Session("join")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).%Id()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, now)
	Do $$$AssertStatusOK(sc, "a session with no thread joins without an error")
	Do $$$AssertEquals(thread, "", "and has no thread")
	Do $$$AssertEquals(..LockFree(id), 0, "the row's lock is kept for the caller's send")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(ref, 777, now), "Started records the thread")
	Do $$$AssertEquals(..LockFree(id), 1, "and releases the lock")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "777|"_##class(OcuTalon.Core.Trace).Day(now), "the row holds the thread and the day")
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, now)
	Do $$$AssertStatusOK(sc, "the next Join is fine")
	Do $$$AssertEquals(thread, 777, "and gives the thread")
	Do $$$AssertEquals(..LockFree(id), 1, "and holds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).ThreadSessionId, 777, "the row is unchanged")
}

/// One second either side of the instance zone's local midnight: the thread of the second before it is not the thread of the
/// second after it. The two times are found by stepping the UTC time by the hour through Data.Time.ToLocal until the local date
/// changes, and then by halving the last hour.
Method TestNewThreadAfterLocalMidnight()
{
	Set ref = ..Session("midnight")
	Set before = ..LastSecondOfADay(.after)
	Do $$$AssertTrue(before '= "", "the local midnight was found in the hours stepped: "_before_" / "_after)
	If before = "" Quit
	Do $$$AssertNotEquals(##class(OcuTalon.Core.Trace).Day(before), ##class(OcuTalon.Core.Trace).Day(after), "the two times are on two local dates")
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, before)
	Do $$$AssertEquals(thread, "", "before midnight the session has no thread")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(ref, 111, before), "the first thread is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Core.Trace).Join(ref, .sc, before), 111, "the second before midnight is in the first thread")
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, after)
	Do $$$AssertStatusOK(sc, "the second after midnight joins without an error")
	Do $$$AssertEquals(thread, "", "and has no thread: the first thread is yesterday's")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(ref, 222, after), "the new thread is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Core.Trace).Join(ref, .sc, after), 222, "after midnight the new thread is the day's")
	Do $$$AssertEquals(##class(OcuTalon.Core.Trace).Join(ref, .sc, before), "", "and the old thread is no longer today's for the earlier second")
	Do ##class(OcuTalon.Core.Trace).Started(ref, "", before)
}

/// Started for a session with no row is an error status and makes no row; for a session with a row and an empty session id it is
/// OK and the row stays as it was. A time that cannot be read records nothing. In every case the row's lock is released.
Method TestStartedWithoutASessionRecordsNothing()
{
	Set unknown = "zztraceunknown"_..Number
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.Trace).Started(unknown, 5150), "Started for an unknown session is an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(unknown), 0, "and makes no session row")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(unknown, ""), "an empty session id for an unknown session records nothing, without an error")
	Set ref = ..Session("started")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).%Id()
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)
	Do $$$AssertEquals(..LockFree(id), 0, "Join keeps the lock")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Started(ref, ""), "an empty session id is OK")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and records nothing")
	Do $$$AssertEquals(..LockFree(id), 1, "and still releases the lock")
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.Trace).Started(ref, 5150, "not a time"), "a time that cannot be read is an error")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "and records nothing")
	Do $$$AssertEquals(..LockFree(id), 1, "the lock is released then too")
	Do $$$AssertEquals(##class(OcuTalon.Core.Trace).Join(ref, .sc, "not a time"), "", "Join with a time that cannot be read gives no thread")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Do $$$AssertEquals(..LockFree(id), 1, "and holds nothing")
}

/// Another job holds the row's lock: Join waits about LOCKWAIT seconds, then answers "" with an error status, and holds nothing
/// (the other job lets go, and a third job takes the lock). A session with no row is an error at once.
Method TestBusyLockAndNoRowFail()
{
	Set ref = ..Session("busy")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).%Id()
	Kill ^OcuTalonTest("Trace", "job", "hold")
	Job ##class(OcuTalon.Test.Core.Trace).Hold(id, "hold")
	Do ..WaitFor($Name(^OcuTalonTest("Trace", "job", "hold", "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Trace", "job", "hold", "ready")), 1, "another job holds the row's lock")
	Set started = $ZHorolog
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc)
	Set waited = $ZHorolog - started
	Do $$$AssertEquals(thread, "", "Join gives no thread")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Do $$$AssertTrue((waited >= (##class(OcuTalon.Core.Trace).#LOCKWAIT - 0.5)) && (waited < (##class(OcuTalon.Core.Trace).#LOCKWAIT + 5)), "after about "_##class(OcuTalon.Core.Trace).#LOCKWAIT_" seconds: "_waited)
	Set ^OcuTalonTest("Trace", "job", "hold", "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("Trace", "job", "hold", "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Trace", "job", "hold", "done")), 1, "the other job lets go")
	Do $$$AssertEquals(..LockFree(id), 1, "and Join held nothing")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "the row records nothing")

	Set thread = ##class(OcuTalon.Core.Trace).Join("zztraceunknown"_..Number, .sc)
	Do $$$AssertEquals(thread, "", "a session with no row has no thread")
	Do $$$AssertStatusNotOK(sc, "and Join says so")
	Set thread = ##class(OcuTalon.Core.Trace).Join("", .sc)
	Do $$$AssertStatusNotOK(sc, "so does an empty SessionRef")
}

/// The matrix row Position, on synthetic rows: headers h1 (A to B), h2 (B to C), h3 (C to D), h4 (D to E); an event of host A
/// before h1, an event of host C before h2, a rule row of host B before h3, and an I/O row received before h3 whose request is h4.
/// h3 is the 4th item with events (h1, h2, the rule row, h3) and the 3rd without: A's event is dropped because nothing was on
/// the diagram yet, C's because only h1's A and B were, and the I/O row is never drawn for the trace role (h4 is the 5th and
/// the 4th, as it would be without the I/O row). Then: an
/// event at the time of a header counts before it when its MessageId is below the header's and after it when it is the header's;
/// a rule row with no CurrentHeaderId and no ConfigName takes the host of the session's first header and the session's id; and
/// a session of more than 40 items has its last header beyond the 40th.
Method TestPositionCountsAsVisualTraceDraws()
{
	Set super = ..Super("matrix")
	Set t = "2030-01-01 10:00:00."
	Set h1 = ..Header(super, "", t_"100", "ZzA", "ZzB")
	Set session = h1
	Set h2 = ..Header(super, session, t_"300", "ZzB", "ZzC")
	Set h3 = ..Header(super, session, t_"500", "ZzC", "ZzD")
	Set h4 = ..Header(super, session, t_"700", "ZzD", "ZzE")
	Do ..Event(session, t_"050", "ZzA", h1)
	Do ..Event(session, t_"200", "ZzC", h1)
	Do ..Rule(session, t_"400", "ZzB", h2)
	Do ..IO(session, "ZzC", h4, t_"450")
	Do ..AssertPosition(h1, 1, 1, "h1")
	Do ..AssertPosition(h2, 2, 2, "h2")
	Do ..AssertPosition(h3, 4, 3, "h3: the rule row counts, and the two events and the I/O row do not")
	Do ..AssertPosition(h4, 5, 4, "h4: the I/O row of its request is not counted either")

	Set super = ..Super("sametime")
	Set t = "2030-01-02 10:00:00."
	Set k1 = ..Header(super, "", t_"100", "ZzA", "ZzB")
	Set session = k1
	Set k2 = ..Header(super, session, t_"300", "ZzB", "ZzC")
	Set k3 = ..Header(super, session, t_"500", "ZzC", "ZzD")
	Do ..Event(session, t_"300", "ZzA", 1)
	Do ..Event(session, t_"300", "ZzA", k2)
	Do ..AssertPosition(k2, 3, 2, "k2: of two events at its time, the one with a lower MessageId counts before it")
	Do ..AssertPosition(k3, 5, 3, "k3: the one with its MessageId counts after it, before the next header")

	Set super = ..Super("rule")
	Set t = "2030-01-03 10:00:00."
	Set m1 = ..Header(super, "", t_"100", "ZzX", "ZzY")
	Set session = m1
	Set m2 = ..Header(super, session, t_"300", "ZzY", "ZzZ")
	Do ..Rule(session, t_"200", "", "")
	Do ..AssertPosition(m2, 3, 2, "m2: a rule row with no host and no header is the first header's source, and counts")

	Set super = ..Super("long")
	Set t = "2030-01-04 10:00:00."
	Kill long
	Set session = ""
	For i = 1:1:45 {
		Set long(i) = ..Header(super, session, t_$Translate($Justify(i * 10, 3), " ", "0"), "ZzA", "ZzB")
		If i = 1 Set session = long(1)
	}
	For i = 1:1:3 Do ..Event(session, t_$Translate($Justify(i * 10 + 5, 3), " ", "0"), "ZzA", long(1))
	Do ..AssertPosition(long(45), 48, 45, "a thread of more than 40 items: the 45th header is at 48 with the events of A, at 45 without")
	Do ..AssertPosition(long(41), 44, 41, "and the 41st at 44 and 41")
}

/// The positions that Core.Trace gives every header of a session are the ones that Visual Trace's own BuildTraceInfo lays out, with
/// the events shown and hidden. Four sessions: the rows of the matrix test, a session whose log rows sit at the times of its headers
/// with MessageIds below, at and above theirs, one with I/O rows of earlier and later requests, which the trace role's page does not
/// read, and one in which a host first appears on a later header and its rows come before and after it.
Method TestPositionAgreesWithVisualTrace()
{
	Set t = "2030-02-01 10:00:00."
	Set super = ..Super("oracle1")
	Set a1 = ..Header(super, "", t_"100", "ZzA", "ZzB")
	Set a2 = ..Header(super, a1, t_"300", "ZzB", "ZzC")
	Set a3 = ..Header(super, a1, t_"500", "ZzC", "ZzD")
	Set a4 = ..Header(super, a1, t_"700", "ZzD", "ZzE")
	Do ..Event(a1, t_"050", "ZzA", a1)
	Do ..Event(a1, t_"200", "ZzC", a1)
	Do ..Rule(a1, t_"400", "ZzB", a2)
	Do ..IO(a1, "ZzC", a4, t_"450")
	Do ..AssertAgainstViewer(a1, $ListBuild(a1, a2, a3, a4))

	Set super = ..Super("oracle2")
	Set b1 = ..Header(super, "", t_"100", "ZzA", "ZzB")
	Set b2 = ..Header(super, b1, t_"300", "ZzB", "ZzC")
	Set b3 = ..Header(super, b1, t_"300", "ZzC", "ZzD")
	Set b4 = ..Header(super, b1, t_"600", "ZzD", "ZzA")
	For at = t_"100", t_"300", t_"600" {
		For host = "ZzA", "ZzC", "ZzD", "ZzE" {
			Do ..Event(b1, at, host, 1)
			Do ..Event(b1, at, host, b2)
			Do ..Event(b1, at, host, b3 + 1)
		}
	}
	Do ..Rule(b1, t_"300", "", "")
	Do ..Rule(b1, t_"300", "ZzC", b2)
	Do ..AssertAgainstViewer(b1, $ListBuild(b1, b2, b3, b4))

	Set super = ..Super("oracle3")
	Set c1 = ..Header(super, "", t_"100", "ZzA", "ZzB")
	Set c2 = ..Header(super, c1, t_"200", "ZzB", "ZzC")
	Set c3 = ..Header(super, c1, t_"300", "ZzC", "ZzB")
	Set c4 = ..Header(super, c1, t_"400", "ZzB", "ZzA")
	Do ..IO(c1, "ZzA", c1, t_"050")
	Do ..IO(c1, "ZzB", c2, t_"150")
	Do ..IO(c1, "ZzC", c4, t_"250")
	Do ..IO(c1, "ZzA", c3, t_"350")
	Do ..IO(c1, "ZzA", c1, t_"390")
	Do ..Event(c1, t_"150", "ZzB", c1)
	Do ..Event(c1, t_"250", "ZzC", c2)
	Do ..AssertAgainstViewer(c1, $ListBuild(c1, c2, c3, c4))

	Set super = ..Super("oracle4")
	Set d1 = ..Header(super, "", t_"100", "ZzIn", "ZzProc")
	Set d2 = ..Header(super, d1, t_"200", "ZzProc", "ZzDecide")
	Set d3 = ..Header(super, d1, t_"300", "ZzDecide", "ZzProc")
	Set d4 = ..Header(super, d1, t_"400", "ZzProc", "ZzNotify")
	Set d5 = ..Header(super, d1, t_"500", "ZzNotify", "ZzOut")
	Do ..Event(d1, t_"100", "ZzOut", d1)
	Do ..Event(d1, t_"100", "ZzProc", d1)
	Do ..Rule(d1, t_"100", "ZzNotify", d1)
	Do ..Event(d1, t_"200", "ZzDecide", d2)
	Do ..Event(d1, t_"300", "ZzDecide", d3)
	Do ..Event(d1, t_"500", "ZzOut", d5)
	Do ..Rule(d1, t_"500", "ZzNotify", d5)
	Do ..Event(d1, t_"600", "ZzOut", d5)
	Do ..AssertAgainstViewer(d1, $ListBuild(d1, d2, d3, d4, d5))
}

/// An unknown header, an empty one and one that is not a number are errors that leave both positions empty.
Method TestPositionOfAnUnknownHeader()
{
	For headerId = 2147483000, "", "zz" {
		Set withEvents = "x", withoutEvents = "x"
		Set sc = ##class(OcuTalon.Core.Trace).Position(headerId, .withEvents, .withoutEvents)
		Do $$$AssertStatusNotOK(sc, "header '"_headerId_"' is an error")
		Do $$$AssertEquals(withEvents_"|"_withoutEvents, "|", "and both positions are empty")
	}
}

/// Two first messages of a day cannot start two threads (the class comment): while a job holds the first message's lock, between
/// Join and Started, the Join of another waits for the lock and then reads the row afresh, so it gets the thread that the first
/// recorded, without an error, after having waited. The second caller holds the Session row open from before the first message
/// recorded its thread, as WebChatIn's Accept does, so a Join that trusted that copy would start a second thread. The job lets go
/// of the lock half a second after it is told to.
Method TestSecondJoinWaitsForTheFirstThread()
{
	Set ref = ..Session("race")
	Set held = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set id = held.%Id()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Kill ^OcuTalonTest("Trace", "job", "race")
	Job ##class(OcuTalon.Test.Core.Trace).First(ref, now, "race", 4711, 0.5)
	Do ..WaitFor($Name(^OcuTalonTest("Trace", "job", "race", "joined")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Trace", "job", "race", "joined")), 1, "the first message's job joined: no thread, and it holds the row's lock")
	Set ^OcuTalonTest("Trace", "job", "race", "go") = 1
	Set started = $ZHorolog
	Set thread = ##class(OcuTalon.Core.Trace).Join(ref, .sc, now)
	Set waited = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "the second Join is fine")
	Do $$$AssertEquals(thread, 4711, "and gives the thread the first message recorded")
	Do $$$AssertTrue((waited >= 0.2) && (waited < ##class(OcuTalon.Core.Trace).#LOCKWAIT), "after waiting for the lock: "_waited_" seconds")
	Do $$$AssertEquals(..LockFree(id), 1, "and it holds nothing")
	Do ..WaitFor($Name(^OcuTalonTest("Trace", "job", "race", "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Trace", "job", "race", "done")), 1, "the first message's job is done")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "4711|"_##class(OcuTalon.Core.Trace).Day(now), "the row holds the one thread")
	If thread = "" Do ##class(OcuTalon.Core.Trace).Started(ref, "", now)
	Kill held
	Kill ^OcuTalonTest("Trace", "job", "race")
}

/// Position against Visual Trace's own layout on sessions that nobody chose: 28 sessions whose headers, event rows and rule
/// rows come from a fixed pseudo-random sequence. The headers are 3 to 10, at times 0, 100 or 200 ms apart (so some have the time
/// of the one before), from and to one of five hosts. The event rows (up to 14, of any type 2 to 6) and rule rows (up to 4) are
/// at multiples of 50 ms from the start to a little after the last header (so many sit at a header's time), by one of the five
/// hosts, by a host no header has, or by none, with the MessageId of a header, of the one after it, of one beyond the last, or none.
/// For every header of every session, Position gives the place that BuildTraceInfo lays it out at, events shown and hidden.
Method TestPositionAgreesWithVisualTraceOnRandomSessions()
{
	Set seed = 20261023
	Set pool = $ListBuild("ZzH1", "ZzH2", "ZzH3", "ZzH4", "ZzH5")
	For scenario = 1:1:28 {
		Set super = ..Super("fuzz"_scenario)
		Set count = 3 + ..Next(.seed, 8)
		Kill ids
		Set session = ""
		Set at = 0
		For i = 1:1:count {
			Set at = at + (..Next(.seed, 3) * 100)
			Set ids(i) = ..Header(super, session, ..Stamp(scenario, at), $List(pool, 1 + ..Next(.seed, 5)), $List(pool, 1 + ..Next(.seed, 5)))
			If i = 1 Set session = ids(1)
		}
		Set last = at + 300
		For j = 1:1:..Next(.seed, 15) {
			Set host = ..Host(.seed, pool)
			Set time = ..Stamp(scenario, ..Next(.seed, last \ 50 + 1) * 50)
			Do ..Event(session, time, host, ..Message(.seed, .ids, count), 2 + ..Next(.seed, 5))
		}
		For j = 1:1:..Next(.seed, 5) {
			Set host = ..Host(.seed, pool)
			Set time = ..Stamp(scenario, ..Next(.seed, last \ 50 + 1) * 50)
			Do ..Rule(session, time, host, ..Message(.seed, .ids, count))
		}
		Set list = ""
		For i = 1:1:count Set list = list_$ListBuild(ids(i))
		Do ..AssertAgainstViewer(session, list)
	}
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zztrace"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The SuperSession of one test's synthetic headers, kept for the clean-up.
Method Super(name As %String) As %String [ Private ]
{
	Set super = "zztrace"_..Number_name
	Do ..Supers.%Push(super)
	Quit super
}

/// A synthetic request header from source to target (Fixture.Header); the first header of a session is given no session and starts
/// its own.
Method Header(super As %String, session As %String, created As %String, source As %String, target As %String) As %String [ Private ]
{
	Set id = ##class(OcuTalon.Test.Data.Fixture).Header(super, session, created, source, target, .sc)
	Do $$$AssertStatusOK(sc, "a synthetic header "_source_" to "_target_" is saved")
	Quit id
}

/// An event-log row of the session logged at the time by the host, in the context of the message (of the type, Info by default).
Method Event(session As %String, time As %String, host As %String, message As %String, type As %Integer = 4) [ Private ]
{
	Set log = ##class(Ens.Util.Log).%New()
	Set log.SessionId = session
	Set log.TimeLogged = time
	Set log.ConfigName = host
	Set log.MessageId = message
	Set log.Type = type
	Set log.Text = "zz event"
	Do $$$AssertStatusOK(log.%Save(), "an event row of "_host_" is saved")
}

/// A rule-log row of the session executed at the time by the host, for the header (either may be empty).
Method Rule(session As %String, time As %String, host As %String, current As %String) [ Private ]
{
	Set log = ##class(Ens.Rule.Log).%New()
	Set log.SessionId = session
	Set log.TimeExecuted = time
	Set log.RuleName = "zz rule"
	Set log.ConfigName = host
	Set log.CurrentHeaderId = current
	Do $$$AssertStatusOK(log.%Save(), "a rule row of "_host_" is saved")
}

/// An I/O-log row of the session for the request, received at the time by the host.
Method IO(session As %String, host As %String, request As %String, received As %String) [ Private ]
{
	Set log = ##class(Ens.Util.IOLog).%New()
	Set log.SessionId = session
	Set log.ConfigName = host
	Set log.CorrespondingRequestId = request
	Set log.TimeReceived = received
	Do $$$AssertStatusOK(log.%Save(), "an I/O row of "_host_" is saved")
}

/// Position of the header must be with and without events.
Method AssertPosition(headerId As %String, with As %Integer, without As %Integer, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Core.Trace).Position(headerId, .withEvents, .withoutEvents)
	Do $$$AssertStatusOK(sc, label_": Position is OK")
	Do $$$AssertEquals(withEvents_"|"_withoutEvents, with_"|"_without, label_": with and without events")
}

/// For each header of the session: Position gives what Visual Trace lays out for the session, with the events shown and hidden.
Method AssertAgainstViewer(session As %String, headers As %List) [ Private ]
{
	Do ..Layout(session, 1, .shown)
	Do ..Layout(session, 0, .hidden)
	Set position = 0
	While $ListNext(headers, position, headerId) {
		Set sc = ##class(OcuTalon.Core.Trace).Position(headerId, .withEvents, .withoutEvents)
		Do $$$AssertStatusOK(sc, "Position reads header "_headerId)
		Do $$$AssertEquals(withEvents_"|"_withoutEvents, $Get(shown(headerId))_"|"_$Get(hidden(headerId)), "header "_headerId_" of session "_session_": Position gives the place Visual Trace gives it, with events and without")
	}
}

/// The places that Visual Trace's BuildTraceInfo gives the message headers of the session, as layout(headerId) = n, with the event and
/// rule rows shown or hidden. BuildTraceInfo is called as the Visual Trace page calls it, with a session of its own for the page's
/// temporary data. The I/O log is switched off: the page reads it with a statement that the trace role (SELECT on Ens.MessageHeader
/// alone) may not run, so the page of a trace user draws no I/O row, which this process, holding every privilege, would draw.
Method Layout(session As %String, events As %Boolean, Output layout) [ Private ]
{
	New %request, %session
	Set %request = ##class(%CSP.Request).%New()
	Set %session = ##class(%CSP.Session).%New("ZzTrace"_..Number, 0)
	Set %request.Data("INCLUDEEVENTS", 1) = events
	Set %request.Data("INCLUDEIOLOG", 1) = 0
	Do ##class(EnsPortal.SVG.VisualTrace).ClearTraceData()
	Set summary = ##class(EnsPortal.SVG.VisualTrace).BuildTraceInfo(session, 1)
	Do $$$AssertTrue(+summary > 0, "Visual Trace lays out the session: "_summary)
	Kill layout
	Set data = $Name(^IRIS.Temp.EnsPortal.Data(%session.SessionId, "VisualTrace"))
	For n = 1:1:+$Get(@data@(0, "count")) {
		If '$Get(@data@(n, "event")) && '$Get(@data@(n, "iolog")) && '$Get(@data@(n, "ack")) Set layout(@data@(n, "id")) = n
	}
	Do ##class(EnsPortal.SVG.VisualTrace).ClearTraceData()
}

/// The next number from 0 to n - 1 of the pseudo-random sequence (the Park-Miller generator), advancing the seed.
ClassMethod Next(ByRef seed As %Integer, n As %Integer) As %Integer [ Private ]
{
	Set seed = (seed * 16807) # 2147483647
	Quit (seed \ 7) # n
}

/// The time stamp of the scenario's day, 10:00 plus ms milliseconds, as the Ens tables write them.
ClassMethod Stamp(scenario As %Integer, ms As %Integer) As %String [ Private ]
{
	Quit "2030-04-"_$Translate($Justify(scenario, 2), " ", "0")_" 10:"_$Translate($Justify(ms \ 60000, 2), " ", "0")_":"_$Translate($Justify((ms # 60000) \ 1000, 2), " ", "0")_"."_$Translate($Justify(ms # 1000, 3), " ", "0")
}

/// A host for a log row: one of the pool, "ZzX" that no header has, or none.
ClassMethod Host(ByRef seed As %Integer, pool As %List) As %String [ Private ]
{
	Set pick = ..Next(.seed, 7)
	Quit $Case(pick, 5: "ZzX", 6: "", : $List(pool, pick + 1))
}

/// A MessageId for a log row: none (one in five), the ID of a header, the ID after a header's, or one beyond the last header's.
ClassMethod Message(ByRef seed As %Integer, ByRef ids, count As %Integer) As %String [ Private ]
{
	Set kind = ..Next(.seed, 5)
	Set which = 1 + ..Next(.seed, count)
	Quit $Case(kind, 0: "", 1: ids(which), 2: ids(which), 3: ids(which) + 1, : ids(count) + 5)
}

/// The job body of a day's first message: Join gives no thread and keeps the row's lock; the job says so, waits to be told to go,
/// holds the lock for the pause, records the thread (Started) and says so.
ClassMethod First(ref As %String, now As %String, key As %String, thread As %Integer, pause As %Numeric)
{
	Set joined = ##class(OcuTalon.Core.Trace).Join(ref, .sc, now)
	Set ^OcuTalonTest("Trace", "job", key, "joined") = $Select($SYSTEM.Status.IsOK(sc) && (joined = ""): 1, 1: -1)
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("Trace", "job", key, "go")) && ($ZHorolog < deadline) {
		Hang 0.02
	}
	Hang pause
	Do ##class(OcuTalon.Core.Trace).Started(ref, thread, now)
	Set ^OcuTalonTest("Trace", "job", key, "done") = 1
}

/// 1 when another job can take the Session row's lock now, 0 when it cannot (a lock is held per process, so only a second job
/// can tell), and "" when the job gave no answer within 60 seconds, which no assertion takes for either. Other tests of the
/// thread call it too.
ClassMethod LockFree(id As %String) As %Boolean
{
	Kill ^OcuTalonTest("Trace", "job", "try")
	Job ##class(OcuTalon.Test.Core.Trace).TryLock(id, "try")
	Do ..WaitFor($Name(^OcuTalonTest("Trace", "job", "try", "result")), 60)
	Quit $Get(^OcuTalonTest("Trace", "job", "try", "result"))
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The job body of the holder: takes the row's lock, says so, keeps it until released, lets go and says so.
ClassMethod Hold(id As %String, key As %String)
{
	Set sc = ##class(OcuTalon.Data.Session).%LockId(id, 0, 5)
	If $SYSTEM.Status.IsError(sc) Quit
	Set ^OcuTalonTest("Trace", "job", key, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("Trace", "job", key, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do ##class(OcuTalon.Data.Session).%UnlockId(id)
	Set ^OcuTalonTest("Trace", "job", key, "done") = 1
}

/// The job body of the lock probe: tries the row's lock for a second and records whether it got it, then lets go.
ClassMethod TryLock(id As %String, key As %String)
{
	Set free = $SYSTEM.Status.IsOK(##class(OcuTalon.Data.Session).%LockId(id, 0, 1))
	If free Do ##class(OcuTalon.Data.Session).%UnlockId(id)
	Set ^OcuTalonTest("Trace", "job", key, "result") = free
}

/// The UTC time of the last second of a local date, and in after the first second of the next: UTC hours from a fixed date are
/// stepped until Data.Time.ToLocal gives another date, and the last hour is halved. "" when 48 hours show no change.
ClassMethod LastSecondOfADay(Output after As %String) As %String [ Private ]
{
	Set after = ""
	Set start = $ZDateH("2030-06-15", 3)
	Set day = ##class(OcuTalon.Core.Trace).Day(..Utc(start, 0))
	For hour = 1:1:48 {
		If ##class(OcuTalon.Core.Trace).Day(..Utc(start, hour * 3600)) '= day Quit
	}
	If hour > 48 Quit ""
	Set low = (hour - 1) * 3600
	Set high = hour * 3600
	While high - low > 1 {
		Set middle = (low + high) \ 2
		If ##class(OcuTalon.Core.Trace).Day(..Utc(start, middle)) = day {
			Set low = middle
		} Else {
			Set high = middle
		}
	}
	Set after = ..Utc(start, high)
	Quit ..Utc(start, low)
}

/// The UTC time, YYYY-MM-DDThh:mm:ssZ, of a day (a $Horolog day number) and a number of seconds after its start.
ClassMethod Utc(days As %Integer, seconds As %Integer) As %String [ Private ]
{
	Quit $Translate($ZDateTime((days + (seconds \ 86400)) _ "," _ (seconds # 86400), 3, 1), " ", "T")_"Z"
}

}
