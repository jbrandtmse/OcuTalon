/// Tests of the conversation link class at the interface that the runner and Decide call (Story 1.8, QA; AD-6, AD-33): LOCKSECONDS, SessionOf, Point, Lock and
/// Unlock of OcuTalon.Bridge.Data.ConversationLink. No model and no production are needed: the lock is observed from another process
/// (Test.Bridge.Conversation LockFree) or held by one (Test.Bridge.Decide StartHolder and StopHolder). Every link and lock belongs to an agent name that no runner item has
/// (ZzLinkAgent, ZzLinkOther) and to an owner that is a new Ref, so the tests share nothing with a conversation of the product or of another test.
///   - TestLockSeconds: a turn waits 2 seconds for the conversation lock before it is answered as busy (AD-6);
///   - TestSessionOfAndPoint: SessionOf gives "" for a conversation with no link; Point makes the link and, called again for the same owner and agent, moves
///     it to another session without a second row; an owner and an agent are each part of the key; Point refuses an empty owner, agent or session id and
///     writes nothing, and SessionOf gives "" for an empty owner or agent;
///   - TestLockIsPerConversation: the lock is the one of an owner and an agent: a hold of (owner, agent) does not hold another owner or another agent;
///   - TestLockIsIncremental: each Lock that returns 1 is paired with one Unlock, so a second hold of the same process is taken at once and one Unlock leaves
///     the lock held;
///   - TestLockKeepsOtherLocks: the Lock and Unlock of one conversation, as Decide's probe makes them, do not release a lock that the process holds on another
///     conversation (a plain LOCK or a bare unlock would);
///   - TestLockRefuses: while another process holds the lock, Lock is refused after the seconds it was given (none, 1 and the default of LOCKSECONDS), and
///     is taken once the other process has released it.
/// Every test releases the locks it took and stops the process it started on every path, and deletes the links it made.
Class OcuTalon.Test.Bridge.Link Extends %UnitTest.TestCase
{

/// The link class under test.
Parameter LINK = "OcuTalon.Bridge.Data.ConversationLink";

/// The agent of the links and locks of the tests.
Parameter AGENT = "ZzLinkAgent";

/// Another agent, for the tests of the key.
Parameter OTHERAGENT = "ZzLinkOther";

/// The locks this process took with Take and has not released with Drop, as a list of $ListBuild(owner, agent).
Property Held As %List;

/// The owners whose lock a process started by the test holds (Test.Bridge.Decide StartHolder), as a list.
Property Holders As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Holders, position, owner) {
		Do ##class(OcuTalon.Test.Bridge.Decide).StopHolder(owner)
	}
	Set ..Holders = ""
	Set position = 0
	While $ListNext(..Held, position, hold) {
		Do $ClassMethod(..#LINK, "Unlock", $List(hold, 1), $List(hold, 2))
	}
	Set ..Held = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent IN (?, ?)", ..#AGENT, ..#OTHERAGENT)
	Quit $$$OK
}

/// A turn waits 2 seconds for the conversation lock before it is answered as busy (AD-6).
Method TestLockSeconds()
{
	Do $$$AssertEquals($Parameter(..#LINK, "LOCKSECONDS"), 2, "the conversation lock is waited for 2 seconds")
}

/// SessionOf, Point and the key of the link. Point is the only writer: it makes the link, moves it, and refuses what cannot name a conversation.
Method TestSessionOfAndPoint()
{
	Set link = ..#LINK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#AGENT), "", "a conversation with no link has no session")
	Do $$$AssertStatusOK($ClassMethod(link, "Point", owner, ..#AGENT, "11"), "Point makes the link of the owner and the agent")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#AGENT), "11", "SessionOf gives the session it names")
	Do $$$AssertEquals(..Rows(owner), 1, "in one row")
	Do $$$AssertStatusOK($ClassMethod(link, "Point", owner, ..#AGENT, "12"), "Point moves the link of the same owner and agent")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#AGENT), "12", "SessionOf gives the new session")
	Do $$$AssertEquals(..Rows(owner), 1, "and the owner still has one row for the agent")

	Do $$$AssertEquals($ClassMethod(link, "SessionOf", other, ..#AGENT), "", "another owner has no link: the owner is part of the key")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#OTHERAGENT), "", "and the same owner has none with another agent: so is the agent")
	Do $$$AssertStatusOK($ClassMethod(link, "Point", owner, ..#OTHERAGENT, "21"), "Point makes the link of the owner and the other agent")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#OTHERAGENT)_"|"_$ClassMethod(link, "SessionOf", owner, ..#AGENT), "21|12", "each conversation of the owner names its own session")
	Do $$$AssertEquals(..Rows(owner), 2, "in two rows")

	Set rows = ..Rows()
	Do $$$AssertStatusNotOK($ClassMethod(link, "Point", "", ..#AGENT, "13"), "Point refuses an empty owner")
	Do $$$AssertStatusNotOK($ClassMethod(link, "Point", owner, "", "13"), "an empty agent")
	Do $$$AssertStatusNotOK($ClassMethod(link, "Point", owner, ..#AGENT, ""), "and an empty session id")
	Do $$$AssertEquals(..Rows(), rows, "and writes nothing")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, ..#AGENT), "12", "the link is as it was")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", "", ..#AGENT)_"|"_$ClassMethod(link, "SessionOf", owner, ""), "|", "SessionOf gives no session for an empty owner or an empty agent")
}

/// The lock is the one of an owner and an agent: another owner and another agent are other conversations.
Method TestLockIsPerConversation()
{
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set test = "OcuTalon.Test.Bridge.Conversation"
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#AGENT), 1, "control: nobody holds the lock of (owner, agent)")
	Do $$$AssertEquals(..Take(owner, ..#AGENT), 1, "this process takes it")
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#AGENT), 0, "another process cannot")
	Do $$$AssertEquals($ClassMethod(test, "LockFree", other, ..#AGENT), 1, "but takes the lock of another owner")
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#OTHERAGENT), 1, "and the lock of the same owner and another agent")
	Do ..Drop(owner, ..#AGENT)
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#AGENT), 1, "and the lock is free once it is released")
}

/// Each Lock that returns 1 is paired with one Unlock: a second hold of the same process is taken at once, and one Unlock leaves the lock held.
Method TestLockIsIncremental()
{
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set test = "OcuTalon.Test.Bridge.Conversation"
	Do $$$AssertEquals(..Take(owner, ..#AGENT), 1, "the first hold is taken")
	Do $$$AssertEquals(..Take(owner, ..#AGENT), 1, "a second hold of the same process is taken at once")
	Do ..Drop(owner, ..#AGENT)
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#AGENT), 0, "one Unlock leaves the lock held")
	Do ..Drop(owner, ..#AGENT)
	Do $$$AssertEquals($ClassMethod(test, "LockFree", owner, ..#AGENT), 1, "and the second frees it")
}

/// Decide's probe, a Lock and at once an Unlock of one conversation, leaves the lock that the process holds on another conversation as it was: the lock is
/// incremental, and a plain LOCK or a bare unlock would release it.
Method TestLockKeepsOtherLocks()
{
	Set held = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set probed = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set test = "OcuTalon.Test.Bridge.Conversation"
	Do $$$AssertEquals(..Take(held, ..#AGENT), 1, "this process holds the lock of one conversation")
	Do $$$AssertEquals(..Take(probed, ..#AGENT), 1, "it takes the lock of another, to probe it")
	Do ..Drop(probed, ..#AGENT)
	Do $$$AssertEquals($ClassMethod(test, "LockFree", probed, ..#AGENT), 1, "and releases it")
	Do $$$AssertEquals($ClassMethod(test, "LockFree", held, ..#AGENT), 0, "the first conversation is still held")
	Do ..Drop(held, ..#AGENT)
	Do $$$AssertEquals($ClassMethod(test, "LockFree", held, ..#AGENT), 1, "until it is released")
}

/// While another process holds the conversation lock, Lock is refused after the seconds it was given, and it is taken once the other process has let go.
Method TestLockRefuses()
{
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set link = ..#LINK
	Set ..Holders = ..Holders _ $ListBuild(owner)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Decide).StartHolder(owner, ..#AGENT), "another process holds the lock of (owner, agent)")

	Set started = $ZHorolog
	Set got = $ClassMethod(link, "Lock", owner, ..#AGENT, 0)
	Set elapsed = $ZHorolog - started
	If got Do $ClassMethod(link, "Unlock", owner, ..#AGENT)
	Do $$$AssertEquals(got, 0, "Lock with no seconds is refused")
	Do $$$AssertTrue(elapsed < 1, "at once: "_$Number(elapsed, 2)_" s")
	Set started = $ZHorolog
	Set got = $ClassMethod(link, "Lock", owner, ..#AGENT, 1)
	Set elapsed = $ZHorolog - started
	If got Do $ClassMethod(link, "Unlock", owner, ..#AGENT)
	Do $$$AssertEquals(got, 0, "Lock of 1 second is refused")
	Do $$$AssertTrue((elapsed '< 0.9) && (elapsed < 4), "after that second: "_$Number(elapsed, 2)_" s")
	Set started = $ZHorolog
	Set got = $ClassMethod(link, "Lock", owner, ..#AGENT)
	Set elapsed = $ZHorolog - started
	If got Do $ClassMethod(link, "Unlock", owner, ..#AGENT)
	Do $$$AssertEquals(got, 0, "Lock with the default seconds is refused")
	Do $$$AssertTrue((elapsed '< 1.9) && (elapsed < 6), "after the seconds of LOCKSECONDS: "_$Number(elapsed, 2)_" s")

	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Decide).StopHolder(owner), "the other process released the lock")
	Do $$$AssertEquals(..Take(owner, ..#AGENT), 1, "and Lock now takes it")
	Do ..Drop(owner, ..#AGENT)
}

/// --- helpers ---
/// Takes the conversation lock of (owner, agent) without waiting and remembers the hold, so that OnAfterOneTest releases it on every path. 1 when it is taken.
Method Take(owner As %String, agent As %String) As %Boolean [ Private ]
{
	Set got = $ClassMethod(..#LINK, "Lock", owner, agent, 0)
	If got Set ..Held = ..Held _ $ListBuild($ListBuild(owner, agent))
	Quit got
}

/// Releases one hold that Take made of the lock of (owner, agent).
Method Drop(owner As %String, agent As %String) [ Private ]
{
	Do $ClassMethod(..#LINK, "Unlock", owner, agent)
	Set held = ..Held
	Do ..Forget(.held, owner, agent)
	Set ..Held = held
}

/// Removes one hold of the lock of (owner, agent) from held, a list of $ListBuild(owner, agent). 1 when held had one. Test.Agent.Conversation keeps its
/// holds the same way.
ClassMethod Forget(ByRef held As %List, owner As %String, agent As %String) As %Boolean
{
	Set kept = ""
	Set found = 0
	Set position = 0
	While $ListNext(held, position, hold) {
		If 'found && ($List(hold, 1) = owner) && ($List(hold, 2) = agent) {
			Set found = 1
		} Else {
			Set kept = kept _ $ListBuild(hold)
		}
	}
	Set held = kept
	Quit found
}

/// The number of link rows of the agents of the tests: the owner's when one is given, else all.
ClassMethod Rows(owner As %String = "") As %Integer [ Private ]
{
	If owner = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent IN (?, ?)", ..#AGENT, ..#OTHERAGENT)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ? AND Agent IN (?, ?)", owner, ..#AGENT, ..#OTHERAGENT)
	}
	Do result.%Next()
	Quit result.%GetData(1)
}

}
