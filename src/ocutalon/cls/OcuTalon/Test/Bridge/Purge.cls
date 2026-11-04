/// Tests of the bridge's purge, OcuTalon.Bridge.Purge.Run (Story 30.2; AD-27, AD-6, AD-5, DW-371). THROWAWAY STACKS AND CI ONLY (Rule 21): Run deletes the
/// Decision and Usage rows older than the cutoff and the unlinked AI sessions of the whole namespace, rows and sessions that these tests did not make,
/// and it marks every unlinked session it meets. Every test gives Run its own clock (the now argument), so no test waits.
///   - TestDecisionsAndUsage (matrix 10, 15): Run(30, T) deletes the Decision and Usage rows recorded 31 days and 30 days + 1 h before T and keeps
///     those recorded 30 days - 1 h, 29 days and 0 days before, and one recorded exactly at the cutoff; Run(100000, T) is OK, deletes no row and marks an unlinked session, which Run(100000, T + 1 day) deletes;
///   - TestSessions (matrix 11): of a linked session and two unlinked ones, Run at T and at T + 86,399 s delete nothing, and Run at T + 86,400 s deletes
///     the two unlinked ones, with their context streams, and keeps the linked one; a run writes no link;
///   - TestLinkMoves (matrix 12): after a link moves from S to S2, S is marked by the first run after the move and deleted by the first run 86,400 s
///     after its mark, never earlier, and S2 is kept and never marked;
///   - TestLinkedAgain (matrix 13): a marked session that a link then names is kept by the next run, which clears its mark;
///   - TestMarks: the mark of a session that is gone is cleared; a mark that cannot be read counts as a first sighting;
///   - TestBadArguments (matrix 14, 16): "", 0, -1, 1.5, abc and 00 as the day count, and an unreadable now, give an error status that names
///     OcuTalon.Bridge.Purge.Run, delete no row or session and write no mark;
///   - TestPartsRunAlone: an error in one part does not stop the others (the decision part fails here, in Test.Bridge.ZzPurgeFailing, the usage and session parts still run);
///   - TestLinkWithoutSession: a link with no session id is ignored;
///   - TestOtherDataKept (QA, Boundaries "Never"): Run deletes no ApprovalRequest, Price, ModelFamily, BackgroundCheck or WatchMark row, however old.
/// Every row, session and link that a test made, and the marks of its own sessions, are removed after the test, also after a failure. The marks that
/// Run writes on the other unlinked sessions of the namespace stay; only Bridge.Purge reads them.
Class OcuTalon.Test.Bridge.Purge Extends %UnitTest.TestCase
{

/// The class under test.
Parameter PURGE = "OcuTalon.Bridge.Purge";

/// The agent of the links.
Parameter AGENT = "ZzPurgeAgent";

/// One day, in seconds.
Parameter DAY = 86400;

/// The owner of the links and rows of the test: a new Ref in every test.
Property Owner As %String;

/// The Refs that Test.Data.Fixture recorded (decisions, and the decision Ref under which a usage row is recorded), as a comma list.
Property Refs As %String(MAXLEN = "");

/// The ids of the AI sessions that the test made, as a list.
Property Sessions As %List;

/// The agents of the links that the test made, as a list.
Property Agents As %List;

/// The ids of the WatchMark rows that the test made, as a list.
Property Marks As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Agents = $ListBuild(..#AGENT)
	Set ..Marks = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Marks, position, markId) {
		Do ##class(OcuTalon.Data.WatchMark).%DeleteId(markId)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set position = 0
	While $ListNext(..Sessions, position, id) {
		Do ##class(%AI.Agent.Session).%DeleteId(id)
		Kill ^OcuTalonBP.Unlinked(id)
	}
	Set position = 0
	While $ListNext(..Agents, position, agent) {
		Set link = ##class(OcuTalon.Bridge.Data.ConversationLink).OwnerRefAgentIndexOpen(..Owner, agent)
		If $IsObject(link) Do ##class(OcuTalon.Bridge.Data.ConversationLink).%DeleteId(link.%Id())
	}
	Quit $$$OK
}

/// Matrix 10 and 15. The rows are recorded relative to one clock T and Run gets T as its now, so the cutoff is exact.
Method TestDecisionsAndUsage()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set day = ..#DAY
	Set offsets = $ListBuild(31 * day, 30 * day + 3600, 30 * day, 30 * day - 3600, 29 * day, 0)
	Set expected = $ListBuild(0, 0, 1, 1, 1, 1)
	Set position = 0
	While $ListNext(offsets, position, offset) {
		Set at = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, -offset)
		Set decision(offset) = ##class(OcuTalon.Test.Data.Fixture).Decision(..Owner, "decide", at)
		Set usage(offset) = ##class(OcuTalon.Test.Data.Fixture).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), ..Owner, {"RecordedAt": (at)})
		Set ..Refs = ..Refs_","_decision(offset)_","_usage(offset)
	}
	Set position = 0
	Set index = 0
	While $ListNext(offsets, position, offset) {
		Set index = index + 1
		Do $$$AssertEquals(..DecisionExists(decision(offset)) _ "|" _ ..UsageExists(usage(offset)), "1|1", "before the run: the rows of "_offset_" s exist")
	}
	Set unlinked = ..NewSession(t)
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 100000, t), "Run(100000, T) is OK")
	Set position = 0
	While $ListNext(offsets, position, offset) {
		Do $$$AssertEquals(..DecisionExists(decision(offset)) _ "|" _ ..UsageExists(usage(offset)), "1|1", "a day count past the calendar deletes no row: "_offset_" s")
	}
	Do $$$AssertEquals(..Mark(unlinked), t, "but the session rule still applies: an unlinked session is marked")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 100000, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, ..#DAY)), "Run(100000, T + 86,400 s) is OK")
	Do $$$AssertEquals(..Exists(unlinked), 0, "and a day later it is deleted")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 30, t), "Run(30, T) is OK")
	Set position = 0
	Set index = 0
	While $ListNext(offsets, position, offset) {
		Set index = index + 1
		Set keep = $List(expected, index)
		Do $$$AssertEquals(..DecisionExists(decision(offset)), keep, "the decision recorded "_offset_" s before T "_$Select(keep: "stays", 1: "is gone"))
		Do $$$AssertEquals(..UsageExists(usage(offset)), keep, "and so does its usage row")
	}
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 30, t), "Run(30, T) again is OK")
	Do $$$AssertEquals(..DecisionExists(decision(30 * day)) _ "|" _ ..DecisionExists(decision(0)), "1|1", "and changes nothing")
}

/// The Never list of the spec: Run purges decisions, usage and sessions only. An approval request, a background check and a watch mark, each dated
/// 400 days before T, and the price and model-family tables, all stay through Run(1, T) and Run(1, T + 1 day).
Method TestOtherDataKept()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set old = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, -400 * ..#DAY)
	Set approval = ##class(OcuTalon.Test.Data.Fixture).Approval(..Owner, "", "answered", old, {"AnsweredAt": (old), "FinishedAt": (old)})
	Set check = ##class(OcuTalon.Test.Data.Fixture).Check(..Owner, "ZZPURGENS", "Zz.Purge.Production", {"CreatedAt": (old), "NextDueAt": (old), "LastRunAt": (old)})
	Set ..Refs = approval_","_check
	Set mark = ##class(OcuTalon.Data.WatchMark).%New()
	Set mark.Namespace = "ZZPURGENS"
	Set mark.Production = "Zz.Purge.Production"
	Set mark.MarkAt = $Extract(old, 1, 19)
	Do $$$AssertStatusOK(mark.%Save(), "a fixture watch mark is saved")
	Set ..Marks = $ListBuild(mark.%Id())
	Set prices = ..Count("OcuTalon_Bridge_Data.Price")
	Set families = ..Count("OcuTalon_Bridge_Data.ModelFamily")
	Do $$$AssertTrue((prices > 0) && (families > 0), "control: the start seeded price and model-family rows: "_prices_" and "_families)
	Do $$$AssertEquals(..OtherData(approval, check, mark.%Id()), "1|1|1", "before the run: the three old rows exist")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 1, t), "Run(1, T) is OK")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 1, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, ..#DAY)), "Run(1, T + 1 day) is OK")
	Do $$$AssertEquals(..OtherData(approval, check, mark.%Id()), "1|1|1", "the approval request, the background check and the watch mark are kept")
	Do $$$AssertEquals(..Count("OcuTalon_Bridge_Data.Price"), prices, "no price row is deleted")
	Do $$$AssertEquals(..Count("OcuTalon_Bridge_Data.ModelFamily"), families, "no model-family row is deleted")
}

/// The rows of the other data as "approval|check|mark", each 1 when the row exists.
ClassMethod OtherData(approvalRef As %String, checkRef As %String, markId As %String) As %String
{
	Quit ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexExists(approvalRef) _ "|" _ ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(checkRef) _ "|" _ ##class(OcuTalon.Data.WatchMark).%ExistsId(markId)
}

/// The number of rows of an SQL table.
ClassMethod Count(table As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Matrix 11. A linked session, an unlinked one and one created now: Run at T marks the two unlinked ones, a run a second short of a day deletes
/// nothing, and a run a day after T deletes both, with their context streams, and keeps the linked one.
Method TestSessions()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set old = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, -3 * ..#DAY)
	Set linked = ..NewSession(old)
	Set unlinkedOld = ..NewSession(old)
	Set unlinkedNew = ..NewSession(t)
	Do ..Point(linked)
	Set stream = ..StreamId(unlinkedOld)
	Do $$$AssertTrue($Data(^AI.Agent.SessionS(stream)), "control: the context stream of a session exists: "_stream)
	Set links = ..Links()

	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, t), "Run(90, T) is OK")
	Do $$$AssertEquals(..Exists(linked) _ "|" _ ..Exists(unlinkedOld) _ "|" _ ..Exists(unlinkedNew), "1|1|1", "it deletes no session at the first sighting")
	Do $$$AssertEquals(..Mark(linked) _ "|" _ ..Mark(unlinkedOld) _ "|" _ ..Mark(unlinkedNew), "|" _ t _ "|" _ t, "it marks the two unlinked sessions with T and not the linked one")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, ..#DAY - 1)), "Run(90, T + 86,399 s) is OK")
	Do $$$AssertEquals(..Exists(linked) _ "|" _ ..Exists(unlinkedOld) _ "|" _ ..Exists(unlinkedNew), "1|1|1", "a second short of a day deletes nothing")
	Do $$$AssertEquals(..Mark(unlinkedOld) _ "|" _ ..Mark(unlinkedNew), t _ "|" _ t, "and keeps the first mark")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, ..#DAY)), "Run(90, T + 86,400 s) is OK")
	Do $$$AssertEquals(..Exists(linked) _ "|" _ ..Exists(unlinkedOld) _ "|" _ ..Exists(unlinkedNew), "1|0|0", "a day after the mark it deletes the two unlinked sessions and keeps the linked one")
	Do $$$AssertEquals(..Mark(linked) _ "|" _ ..Mark(unlinkedOld) _ "|" _ ..Mark(unlinkedNew), "||", "and no mark is left")
	Do $$$AssertEquals($Data(^AI.Agent.SessionS(stream)), 0, "the context stream of a deleted session is gone")
	Do $$$AssertEquals(..Links(), links, "no link was written")
}

/// Matrix 12. The link moves from S to S2: S is marked by the first run after the move, which is when its day starts.
Method TestLinkMoves()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Set s2 = ..NewSession(t)
	Do ..Point(s)
	Do ..Point(s2)
	Set first = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, 10)
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, first), "the first run after the move is OK")
	Do $$$AssertEquals(..Mark(s) _ "|" _ ..Mark(s2), first _ "|", "it marks S and not S2")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(first, ..#DAY - 1)), "a run a second short of a day after the mark is OK")
	Do $$$AssertEquals(..Exists(s) _ "|" _ ..Exists(s2), "1|1", "it deletes nothing: S is kept for the day")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(first, ..#DAY)), "the run a day after the mark is OK")
	Do $$$AssertEquals(..Exists(s) _ "|" _ ..Exists(s2), "0|1", "it deletes S and keeps S2")
	Do $$$AssertEquals(..Mark(s) _ "|" _ ..Mark(s2), "|", "and leaves no mark")
}

/// Matrix 13. A session that is marked and then named by a link again is kept, and its mark is cleared.
Method TestLinkedAgain()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, t), "Run(90, T) is OK")
	Do $$$AssertEquals(..Mark(s), t, "the unlinked session is marked")
	Do ..Point(s)
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, 2 * ..#DAY)), "the next run, two days later, is OK")
	Do $$$AssertEquals(..Exists(s) _ "|" _ ..Mark(s), "1|", "the session is kept and its mark is cleared")
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, ##class(OcuTalon.Bridge.Time).PlusSeconds(t, 4 * ..#DAY)), "and a run two days after that is OK")
	Do $$$AssertEquals(..Exists(s) _ "|" _ ..Mark(s), "1|", "it is still kept: the link still names it")
}

/// The mark of a session that is gone is cleared, and a mark that holds no time counts as a first sighting.
Method TestMarks()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set gone = "999999999"_$Piece($ZHorolog, ".", 2)
	Set ^OcuTalonBP.Unlinked(gone) = t
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Set ^OcuTalonBP.Unlinked(s) = "garbled"
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, t), "Run(90, T) is OK")
	Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(gone)), 0, "the mark of a session that does not exist is cleared")
	Do $$$AssertEquals(..Exists(s) _ "|" _ ..Mark(s), "1|" _ t, "a mark that holds no time is replaced by the time of this run and the session is kept")
	Kill ^OcuTalonBP.Unlinked(gone)
}

/// Matrix 14 and 16. A bad day count or an unreadable now: an error status, and nothing deleted or marked.
Method TestBadArguments()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(..Owner, "decide", ##class(OcuTalon.Bridge.Time).PlusSeconds(t, -400 * ..#DAY))
	Set usage = ##class(OcuTalon.Test.Data.Fixture).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), ..Owner, {"RecordedAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(t, -400 * ..#DAY))})
	Set ..Refs = decision_","_usage
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Set later = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, 3 * ..#DAY)
	For bad = "", 0, -1, 1.5, "abc", "00" {
		Set sc = $ClassMethod(..#PURGE, "Run", bad, later)
		Do $$$AssertStatusNotOK(sc, "Run('"_bad_"') is an error")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Bridge.Purge.Run", "which names OcuTalon.Bridge.Purge.Run")
		Do $$$AssertEquals(..DecisionExists(decision) _ "|" _ ..UsageExists(usage) _ "|" _ ..Exists(s) _ "|" _ ..Mark(s), "1|1|1|", "Run('"_bad_"') deletes nothing and writes no mark")
	}
	For bad = "yesterday", "2026-10-30", "2026-10-30T13:05:09", "2026-02-30T13:05:09Z" {
		Set sc = $ClassMethod(..#PURGE, "Run", 90, bad)
		Do $$$AssertStatusNotOK(sc, "Run(90, '"_bad_"') is an error")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Bridge.Purge.Run", "which names OcuTalon.Bridge.Purge.Run")
		Do $$$AssertEquals(..DecisionExists(decision) _ "|" _ ..UsageExists(usage) _ "|" _ ..Exists(s) _ "|" _ ..Mark(s), "1|1|1|", "Run(90, '"_bad_"') deletes nothing and writes no mark")
	}
}

/// Each part runs whatever an earlier part returned: with the delete of the Decision rows failing (Test.Bridge.ZzPurgeFailing), Run still deletes the
/// Usage rows and marks the unlinked session, and returns the error.
Method TestPartsRunAlone()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set old = ##class(OcuTalon.Bridge.Time).PlusSeconds(t, -400 * ..#DAY)
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(..Owner, "decide", old)
	Set usage = ##class(OcuTalon.Test.Data.Fixture).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), ..Owner, {"RecordedAt": (old)})
	Set ..Refs = decision_","_usage
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Set sc = $ClassMethod("OcuTalon.Test.Bridge.ZzPurgeFailing", "Run", 90, t)
	Do $$$AssertStatusNotOK(sc, "the run returns the error of the failed part")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ZzPurgeFailing", "and it is the error of that part")
	Do $$$AssertEquals(..DecisionExists(decision) _ "|" _ ..UsageExists(usage), "1|0", "the Decision rows stay, and the part after it deleted the Usage rows")
	Do $$$AssertEquals(..Mark(s), t, "and the session part ran")
}

/// A link with no session id (the one writer never makes one) is ignored: the run is OK and still marks an unlinked session.
Method TestLinkWithoutSession()
{
	Set t = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set link = ##class(OcuTalon.Bridge.Data.ConversationLink).%New()
	Set link.OwnerRef = ..Owner
	Set link.Agent = ..#AGENT
	Do $$$AssertStatusOK(link.%Save(), "a link with no session id is saved")
	Set s = ..NewSession(##class(OcuTalon.Bridge.Time).PlusSeconds(t, -5 * ..#DAY))
	Do $$$AssertStatusOK($ClassMethod(..#PURGE, "Run", 90, t), "Run(90, T) is OK")
	Do $$$AssertEquals(..Mark(s), t, "and the unlinked session is marked")
}

/// --- helpers ---
/// A saved AI session with no agent, created at the UTC time (YYYY-MM-DDThh:mm:ssZ), with some context data; its id. The test deletes it afterwards.
Method NewSession(createdAt As %String) As %String
{
	Set session = ##class(%AI.Agent.Session).%New()
	Set session.CreatedAt = $Translate($Extract(createdAt, 1, 19), "T", " ")
	Set session.Model = "zz-purge"
	Do session.ContextData.Write("{""zz"":""purge""}")
	Set sc = session.%Save()
	Do $$$AssertStatusOK(sc, "a fixture AI session is saved")
	Set id = session.%Id()
	Set ..Sessions = ..Sessions _ $ListBuild(id)
	Quit id
}

/// Makes the link of the test's owner and agent name the session.
Method Point(id As %String)
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(..Owner, ..#AGENT, id), "the link names the session "_id)
}

/// The stream id of the session's context data.
ClassMethod StreamId(id As %String) As %String
{
	Set session = ##class(%AI.Agent.Session).%OpenId(id)
	Quit session.ContextData.%Id()
}

/// 1 when the AI session exists.
ClassMethod Exists(id As %String) As %Boolean
{
	Quit ##class(%AI.Agent.Session).%ExistsId(id)
}

/// The mark of the session, or "".
ClassMethod Mark(id As %String) As %String
{
	Quit $Get(^OcuTalonBP.Unlinked(id))
}

/// 1 when the Decision row of the Ref exists.
ClassMethod DecisionExists(ref As %String) As %Boolean
{
	Quit ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(ref)
}

/// 1 when a Usage row of the decision Ref exists.
ClassMethod UsageExists(decisionRef As %String) As %Boolean
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", decisionRef)
	Do result.%Next()
	Quit +result.%GetData(1) > 0
}

/// The links of the test's owner as text, to compare before and after a run.
Method Links() As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Agent, SessionId FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ? ORDER BY Agent", ..Owner)
	While result.%Next() {
		Set text = text _ result.%GetData(1) _ "=" _ result.%GetData(2) _ ";"
	}
	Quit text
}

}
