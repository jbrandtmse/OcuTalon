/// Tests of the two tools that OcuTalon's own MCP server serves (Story 28.3; AD-1, AD-4, AD-17, AD-21): OcuTalon.Mcp.ServiceRead, called in this process through
/// Test.Mcp.ServiceReadProbe, which takes the caller from a test global instead of $Username. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), through Test.Watch.Case; each test makes its
/// own sessions and rows, which Case removes, and the audit event switch that TestAuditFailsClosed turns off is put back by OnAfterOneTest.
///   - TestOwnRecordsOnly (AC 5; R-28.3-2): callers A and B each have checks and incidents of their own; each tool's answer for A holds A's rows and none of B's (and the other way round), it is
///     what the chat tool's own readers give for that owner, and no bridge context is active before, during or after a call, so CommandCall Session still answers NOSESSION;
///   - TestNoSession: an IRIS user with no session gets the ruled text for each tool, with no Data.Session row created, and one audit entry (outcome nosession);
///   - TestOnlineDemo (AC 2): on the online demo each tool answers the ruled text, reads nothing, and writes one audit entry (outcome demo, no session Ref);
///   - TestUnreadable: a failing ownership read, a read that throws and a failing session lookup each answer the tool's own not-read text and no data, with outcome notread and one audit entry;
///   - TestAuditEntries (AC 6): every served call writes exactly one IRIS audit entry of type MCP with change served, server ocutalon, the tool, its outcome word, irisUser the caller, the
///     session Ref (or "") and channel mcp, and no other member;
///   - TestAuditFailsClosed (AC 6): when the entry cannot be written the answer is the ruled audit text and holds no data.
Class OcuTalon.Test.Mcp.ServiceTools Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzmcpsvc";

Parameter PROBE = "OcuTalon.Test.Mcp.ServiceReadProbe";

Parameter EVENT = "OcuTalon/MCP/MCP";

Property EventBefore As %String;

Property EventSaved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..EventSaved {
		Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, ..EventBefore)
		Set ..EventSaved = 0
	}
	Kill ^||OcuTalonMcpCaller, ^||OcuTalonMcpActive, ^||OcuTalonMcpRead, ^||OcuTalonMcpUnread
	Quit ##super(testname)
}

/// The IRIS user name of the fixture session that Session(name) makes.
Method UserOf(name As %String) As %String [ Private ]
{
	Quit ..#SESSIONPREFIX _ ..Number _ name
}

/// Calls the tool (CheckStatus or RecentActivity) of the probe as the caller, with no bridge context, and gives the answer as a dynamic object.
Method Call(method As %String, caller As %String) As %DynamicObject [ Private ]
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^||OcuTalonMcpActive, ^||OcuTalonMcpRead
	Set ^||OcuTalonMcpCaller = caller
	Set answer = $ClassMethod(..#PROBE, method)
	If '$IsObject(answer) Set answer = {}.%FromJSON(answer)
	Quit answer
}

/// The tool's name in the audit entry.
ClassMethod ToolName(method As %String) As %String [ Private ]
{
	Quit $Select(method = "CheckStatus": "check_status", 1: "recent_activity")
}

/// Asserts that exactly one served entry of the tool is in the audit log since the mark, made by the caller, with the outcome and the session Ref, in the one shape of the call.
/// An entry of the caller's other tool, written just before the mark, is not counted. text is the JSON of the entry's data ("" when there is not exactly one).
Method AssertAudit(mark As %String, caller As %String, method As %String, outcome As %String, sessionRef As %String, label As %String, Output text As %String) [ Private ]
{
	Set text = ""
	Set audit = "OcuTalon.Test.Bridge.AuditLog"
	Set tool = ..ToolName(method)
	Do $ClassMethod(audit, "Wait", mark, "OcuTalon", "MCP", "MCP", caller)
	Set found = $ClassMethod(audit, "Entries", mark, "OcuTalon", "MCP", "MCP", caller)
	Set entries = []
	Set iterator = found.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.data.tool = tool Do entries.%Push(one)
	}
	Do $$$AssertEquals(entries.%Size(), 1, label _ ": one audit entry of the caller for " _ tool _ " (" _ entries.%Size() _ ")")
	If entries.%Size() '= 1 Quit
	Set entry = entries.%Get(0)
	Set text = entry.data.%ToJSON()
	Do $$$AssertEquals(entry.data.%Size(), 7, label _ ": the data has exactly the 7 members of the call shape")
	Do $$$AssertEquals(entry.data.change _ "|" _ entry.data.server _ "|" _ entry.data.tool _ "|" _ entry.data.outcome, "served|ocutalon|" _ tool _ "|" _ outcome, label _ ": served, the server, the tool and the outcome")
	Do $$$AssertEquals(entry.data.irisUser _ "|" _ entry.data.sessionRef _ "|" _ entry.data.channel, caller _ "|" _ sessionRef _ "|mcp", label _ ": the caller, the session Ref and the channel mcp")
	Do $$$AssertEquals(entry.description, "MCP tool " _ tool _ " of ocutalon served: " _ outcome, label _ ": the description is built from the data")
}

/// A noticed incident of the owner, 11 minutes since its last failure, with the count given and no group, request or run: its Ref is kept for the clean-up.
Method Incident(owner As %String, count As %Integer) As %String [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).AddSeconds(now, -600), ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"State": "open", "Count": (count), "NoticeCount": (count), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -840)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -660))})
	Set ..Refs = ..Refs _ "," _ ref
	Quit ref
}

/// A background check row of the session, named for the display name and with the result.
Method Check(session As %String, name As %String, result As %String) [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": (name), "Result": (result), "Finding": (name _ " finding"), "LastRunAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set ..Refs = ..Refs _ "," _ ref
}

Method TestOwnRecordsOnly()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set a = ..Session("a")
	Set b = ..Session("b")
	Set userA = ..UserOf("a")
	Set userB = ..UserOf("b")
	Do ..Check(a, "Orders", "failed")
	Do ..Check(b, "ZzMcpBeta", "passed")
	Set ..Refs = ..Refs _ "," _ ##class(OcuTalon.Test.Tools.RecentActivity).Demo(a, 0, 660, .incidentA, .requestA, .times)
	Do ..Incident(b, 7)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "control: no bridge context is active before the calls")
	Set statusA = ..Call("CheckStatus", userA)
	Do $$$AssertEquals(+$Get(^||OcuTalonMcpActive), 0, "no bridge context was active during the call")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and none is active after it")
	Do $$$AssertEquals(statusA.checks.%Size(), 1, "A's check_status holds one check")
	Do $$$AssertTrue(statusA.%ToJSON() [ "Orders production", "A's check_status holds A's check")
	Do $$$AssertTrue(statusA.%ToJSON() '[ "ZzMcpBeta", "and not B's")
	Do $$$AssertEquals(##class(OcuTalon.Tools.WatchAnswers).CheckResults(a, .results), "", "control: the chat tool's own reader reads A's checks")
	Do $$$AssertEquals(statusA.%ToJSON(), ##class(OcuTalon.Tools.WatchAnswers).Checked(results).%ToJSON(), "and the served answer is what Checked gives for them")
	Set statusB = ..Call("CheckStatus", userB)
	Do $$$AssertTrue(statusB.%ToJSON() [ "ZzMcpBeta", "B's check_status holds B's check")
	Do $$$AssertTrue(statusB.%ToJSON() '[ "Orders", "and not A's")
	Set activityA = ..Call("RecentActivity", userA)
	Do ..AssertObject(activityA, ##class(OcuTalon.Test.Tools.RecentActivity).DemoAnswer(times, ""), "A's recent_activity is the answer for A's incident")
	Set activityB = ..Call("RecentActivity", userB)
	Do $$$AssertEquals(activityB.incidents.%Size(), 1, "B's recent_activity holds one incident")
	Do $$$AssertEquals(activityB.incidents.%Get(0).count, 7, "B's own, and not A's of 50")
	Do $$$AssertTrue(activityB.%ToJSON() '[ "resent", "with none of A's approvals")
	Do $$$AssertEquals(+$Get(^||OcuTalonMcpActive), 0, "no bridge context was active during the calls")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and none is active after them")
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session()
	Do $$$AssertTrue($IsObject(refusal) && (refusal.message = ##class(OcuTalon.Tools.CommandCall).#NOSESSION), "CommandCall Session still answers NOSESSION, so no command can be submitted from a served call")
}

Method TestNoSession()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set user = ..UserOf("none")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 0, "control: the user has no session")
	For method = "CheckStatus", "RecentActivity" {
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answer = ..Call(method, user)
		Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "message": ($Parameter(..#PROBE, "NOSESSION"))}.%ToJSON(), method _ " answers the ruled text and nothing else")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 0, method _ " created no session row")
		Do ..AssertAudit(mark, user, method, "nosession", "", method _ " with no session")
	}
}

Method TestOnlineDemo()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set session = ..Session("demo")
	Set user = ..UserOf("demo")
	Do ..Check(session, "ZzMcpDemo", "failed")
	Do ..Incident(session, 4)
	Do ..SetOnlineDemo(1)
	For method = "CheckStatus", "RecentActivity" {
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answer = ..Call(method, user)
		Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "message": ($Parameter(..#PROBE, "DEMOOFF"))}.%ToJSON(), method _ " answers the ruled text and nothing else on the online demo")
		Do $$$AssertEquals(+$Get(^||OcuTalonMcpRead), 0, method _ " read nothing")
		Do ..AssertAudit(mark, user, method, "demo", "", method _ " on the online demo")
	}
	Set sc = ##class(OcuTalon.Mcp.Service).OnAuthenticate("Basic", "")
	Do $$$AssertStatusNotOK(sc, "OnAuthenticate refuses on the online demo")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ $Parameter("OcuTalon.Mcp.Service", "DEMOOFF"), "with the ruled text")
}

Method TestUnreadable()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set session = ..Session("unread")
	Set user = ..UserOf("unread")
	Do ..Check(session, "ZzMcpUnread", "failed")
	Do ..Incident(session, 4)
	Set cases = $ListBuild($ListBuild("CheckStatus", "checks", $Parameter(..#PROBE, "CHECKSNOTREAD")), $ListBuild("RecentActivity", "incidents", $Parameter(..#PROBE, "NOTREAD")))
	Set cases = cases _ $ListBuild($ListBuild("CheckStatus", "checks-throw", $Parameter(..#PROBE, "CHECKSNOTREAD")), $ListBuild("RecentActivity", "incidents-throw", $Parameter(..#PROBE, "NOTREAD")))
	Set cases = cases _ $ListBuild($ListBuild("CheckStatus", "session", $Parameter(..#PROBE, "CHECKSNOTREAD")), $ListBuild("RecentActivity", "session", $Parameter(..#PROBE, "NOTREAD")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set method = $List(case, 1)
		Set ^||OcuTalonMcpUnread = $List(case, 2)
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answer = ..Call(method, user)
		Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "message": ($List(case, 3))}.%ToJSON(), method _ " answers its not-read text and no data")
		Do ..AssertAudit(mark, user, method, "notread", $Select($List(case, 2) = "session": "", 1: session), method _ " with an unreadable read (" _ $List(case, 2) _ ")")
		Kill ^||OcuTalonMcpUnread
		Set answer = ..Call(method, user)
		Do $$$AssertTrue(answer.ok, "control: with the read working, " _ method _ " answers ok")
	}
}

Method TestAuditEntries()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set session = ..Session("audit")
	Set user = ..UserOf("audit")
	Do ..Check(session, "ZzMcpAudit", "failed")
	Do ..Incident(session, 4)
	For method = "CheckStatus", "RecentActivity" {
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set answer = ..Call(method, user)
		Do $$$AssertTrue(answer.ok, method _ " answers ok")
		Do ..AssertAudit(mark, user, method, "ok", session, method _ " answered", .text)
		Do $$$AssertTrue((text '[ "ZzMcpAudit") && (text '[ "failed"), method _ ": the entry holds no result text")
	}
}

Method TestAuditFailsClosed()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(0)
	Set session = ..Session("closed")
	Set user = ..UserOf("closed")
	Do ..Check(session, "ZzMcpClosed", "failed")
	Do ..Incident(session, 4)
	Set ..EventBefore = ##class(OcuTalon.Test.Bridge.AuditLog).EventState(..#EVENT)
	Set ..EventSaved = 1
	Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, 0)
	For method = "CheckStatus", "RecentActivity" {
		Set answer = ..Call(method, user)
		Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "message": ($Parameter(..#PROBE, "NOTAUDITED"))}.%ToJSON(), method _ " answers the ruled audit text and no data when the entry cannot be written")
		Do $$$AssertEquals(+$Get(^||OcuTalonMcpRead), 1, method _ ": control: the rows were read, and the answer was held back")
	}
	Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, ..EventBefore)
	Set ..EventSaved = 0
	Set answer = ..Call("CheckStatus", user)
	Do $$$AssertTrue(answer.ok, "control: with the event on again, check_status answers ok")
}

}
