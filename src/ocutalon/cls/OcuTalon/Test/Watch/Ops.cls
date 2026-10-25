/// Tests of WatchOps, OcuTalon.Watch.Ops (Story 5.1; AD-1, AD-4, AD-18, AD-33). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on,
/// through Test.Watch.Case. Most send the commands to the handlers of a shadow instance of the operation (Ens.Host.GetShadowInstance, as Test.Digest.Store
/// does), in this process; TestThroughTheProduction sends one through the item WatchOps of the running production, whose job reads the production
/// in its own process.
///   - TestStart (matrix "Start"): one row, with the session, Kind production, OCUORDERS, the Orders production, the reader's display name (not the
///     command's), the session's IrisUser as AskedBy, NextDueAt now (UTC, to the second) and no result yet; the answer is Ok, started, with the row's Ref;
///     Ownership.Checks lists it (what /state shows);
///   - TestRepeat ("Repeat"): the same command again, and a new key for the same production, make no second row and answer already_watching with the
///     same Ref; another session gets a row of its own;
///   - TestStop ("Stop", "Stop, not watching"): the session's row goes and the other session's stays, unchanged; a second stop answers not_watching,
///     Ok 0, and removes nothing;
///   - TestOwnerCheck ("Owner check"): a StartWatch for a production that the reader does not list (the production of OCUTALON, an unknown namespace,
///     another name), from any origin, answers Ok 0 and unknown_production with no row, and only_orders on the online demo; an unknown session answers
///     no_session for a start and for a stop, with no row;
///   - TestThroughTheProduction: the item answers a StartWatch and a StopWatch with a CommandResult and writes and removes the row.
Class OcuTalon.Test.Watch.Ops Extends OcuTalon.Test.Watch.Case
{

Parameter CLASS = "OcuTalon.Watch.Ops";

Method TestStart()
{
	If '..Ready() Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Session("start")
	Set user = ##class(OcuTalon.Data.Session).RefIndexOpen(session).IrisUser
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set command = ..Start(session, "zzkey1")
	Set command.DisplayName = "A name that is not the reader's"
	Set sc = host.OnStart(command, .response)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(sc, "the handler answers OK")
	If '..AssertResult(response, 1, "started", "start") Quit
	Set rows = ..Rows(session)
	Do $$$AssertEquals(rows.%Size(), 1, "there is one row")
	If rows.%Size() '= 1 Quit
	Set row = rows.%Get(0)
	Do $$$AssertEquals(row.ref, response.Ref, "its Ref is the answer's")
	Do $$$AssertEquals(row.kind_"|"_row.namespace_"|"_row.production, "production|"_..#ORDERS_"|"_..#ORDERSPRODUCTION, "Kind production, OCUORDERS and the Orders production")
	Do $$$AssertEquals(row.displayName, "Orders", "the display name is the reader's, not the command's")
	Do $$$AssertEquals(row.askedBy, user, "AskedBy is the IrisUser of the session")
	Do $$$AssertTrue((row.nextDueAt '< before) && (row.nextDueAt '> after) && (row.nextDueAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z"), "NextDueAt is the creation time, UTC to the second: "_row.nextDueAt)
	Do $$$AssertEquals(row.lastRunAt_"|"_row.result, "|", "it has not run yet")
	Do $$$AssertEquals($Length(response.Ref), 22, "the Ref has 22 characters")
	Set checks = ##class(OcuTalon.Data.Ownership).Checks(session)
	Do $$$AssertEquals(checks.Count(), 1, "Ownership.Checks lists one watch")
	If checks.Count() = 1 Do $$$AssertEquals(checks.GetAt(1).Kind_"|"_checks.GetAt(1).DisplayName, "production|Orders", "of Kind production and display name Orders")
}

Method TestRepeat()
{
	If '..Ready() Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Session("repeatA")
	Set b = ..Session("repeatB")
	Do $$$AssertStatusOK(host.OnStart(..Start(a, "zzkey1"), .first), "the first start is answered")
	Do $$$AssertStatusOK(host.OnStart(..Start(a, "zzkey1"), .same), "the same command again is answered")
	Do $$$AssertEquals(same.Ok_"|"_same.Outcome_"|"_same.Ref, "1|already_watching|"_first.Ref, "already_watching, Ok, with the existing Ref")
	Do $$$AssertStatusOK(host.OnStart(..Start(a, "zzkey2"), .other), "a new key for the same production is answered")
	Do $$$AssertEquals(other.Ok_"|"_other.Outcome_"|"_other.Ref, "1|already_watching|"_first.Ref, "also already_watching with the same Ref")
	Do $$$AssertEquals(..Rows(a).%Size(), 1, "the session has one row")
	Do $$$AssertStatusOK(host.OnStart(..Start(b, "zzkey3"), .second), "another session's start is answered")
	Do $$$AssertEquals(second.Outcome, "started", "it is a new watch")
	Do $$$AssertTrue(second.Ref '= first.Ref, "with a Ref of its own")
	Do $$$AssertEquals(..Rows(b).%Size(), 1, "the other session has one row")
	Do $$$AssertEquals(..Rows(a).%Size(), 1, "and the first still has one")
}

Method TestStop()
{
	If '..Ready() Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Session("stopA")
	Set b = ..Session("stopB")
	Do host.OnStart(..Start(a, "zzkey1"), .startedA)
	Do host.OnStart(..Start(b, "zzkey2"), .startedB)
	Set rowB = ..Rows(b).%ToJSON()
	Do $$$AssertEquals(..RowsOfProduction(), 2 + ..Others(a, b), "both sessions watch Orders")
	Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set command.SessionRef = a
	Set command.IdempotencyKey = "zzkey3"
	Set command.Namespace = ..#ORDERS
	Set command.Production = ..#ORDERSPRODUCTION
	Do $$$AssertStatusOK(host.OnStop(command, .response), "the stop is answered")
	Do ..AssertResult(response, 1, "stopped", "stop")
	Do $$$AssertEquals(..Rows(a).%Size(), 0, "the first session's row is removed")
	Do $$$AssertEquals(..Rows(b).%ToJSON(), rowB, "and the other session's row is unchanged")
	Set checks = ##class(OcuTalon.Data.Ownership).Checks(a)
	Do $$$AssertEquals(checks.Count(), 0, "Ownership.Checks no longer lists the first session's watch")
	Do $$$AssertStatusOK(host.OnStop(command, .again), "a second stop is answered")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "0|not_watching", "not_watching, Ok 0")
	Do $$$AssertEquals(..Rows(b).%ToJSON(), rowB, "and nothing else was removed")
}

Method TestOwnerCheck()
{
	If '..Ready() Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Session("owner")
	Set rows = ..RowCount()
	Set cases = $ListBuild($ListBuild("OCUTALON", "OcuTalon.Production"), $ListBuild("ZZNS", ..#ORDERSPRODUCTION), $ListBuild(..#ORDERS, "OcuTalon.Production"), $ListBuild("", ""), $ListBuild(..#ORDERS, "Orders"))
	For origin = "tool", "web_user", "telegram", "system" {
		For i = 1:1:$ListLength(cases) {
			Set command = ..Start(session, "zzkey"_origin_i)
			Set command.Origin = origin
			Set command.Namespace = $List($List(cases, i), 1)
			Set command.Production = $List($List(cases, i), 2)
			Do $$$AssertStatusOK(host.OnStart(command, .response), "origin "_origin_": the start of '"_command.Namespace_"/"_command.Production_"' is answered")
			Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "0|unknown_production|", "origin "_origin_": '"_command.Namespace_"/"_command.Production_"' is refused as unknown_production")
		}
	}
	Do $$$AssertEquals(..RowCount(), rows, "no row was written")
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(host.OnStart(..Start(unknown, "zzkeyu1"), .response), "a start for an unknown session is answered")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "no_session")
	Set stop = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set stop.SessionRef = unknown
	Set stop.Namespace = ..#ORDERS
	Set stop.Production = ..#ORDERSPRODUCTION
	Do $$$AssertStatusOK(host.OnStop(stop, .response), "and so is a stop")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "no_session too")
	Set empty = ..Start("", "zzkeyu2")
	Do host.OnStart(empty, .response)
	Do $$$AssertEquals(response.Outcome, "no_session", "an empty SessionRef is no session")
	Do $$$AssertEquals(..RowCount(), rows, "still no row")
	Do ..SetOnlineDemo(1)
	Set other = ..Start(session, "zzkeyd1")
	Set other.Namespace = "OCUTALON"
	Set other.Production = "OcuTalon.Production"
	Do host.OnStart(other, .response)
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|only_orders", "on the online demo, another production is only_orders")
	Do $$$AssertEquals(..RowCount(), rows, "and writes no row")
	Do $$$AssertStatusOK(host.OnStart(..Start(session, "zzkeyd2"), .response), "Orders is still answered on the online demo")
	Do $$$AssertEquals(response.Outcome, "started", "and started")
}

Method TestThroughTheProduction()
{
	If '..Ready() Quit
	Set session = ..Session("prod")
	Set fixture = ..#FIXTURE
	Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "WatchOps", ..Start(session, "zzkeyp1"), .response), "WatchOps answers a StartWatch")
	Set ok = $IsObject(response) && response.%IsA("OcuTalon.Msg.CommandResult")
	Do $$$AssertTrue(ok, "with a CommandResult")
	If ok Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|started", "that says started: "_response.Message)
	Do $$$AssertEquals(..Rows(session).%Size(), 1, "the row is written")
	Set stop = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set stop.SessionRef = session
	Set stop.Namespace = ..#ORDERS
	Set stop.Production = ..#ORDERSPRODUCTION
	Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "WatchOps", stop, .response), "WatchOps answers a StopWatch")
	Set ok = $IsObject(response) && response.%IsA("OcuTalon.Msg.CommandResult")
	Do $$$AssertTrue(ok, "with a CommandResult")
	If ok Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|stopped", "that says stopped: "_response.Message)
	Do $$$AssertEquals(..Rows(session).%Size(), 0, "the row is gone")
}

/// --- helpers ---


/// A shadow instance of the operation, or "" with a failed assertion.
Method Host() As OcuTalon.Watch.Ops [ Private ]
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#CLASS, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of WatchOps is made")
	Quit $Select($IsObject(host): host, 1: "")
}

/// A StartWatch for the session and the Orders production.
ClassMethod Start(session As %String, key As %String) As OcuTalon.Msg.Command.StartWatch [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = key
	Set command.Origin = "tool"
	Set command.Namespace = ..#ORDERS
	Set command.Production = ..#ORDERSPRODUCTION
	Set command.DisplayName = "Orders"
	Quit command
}

/// Asserts the answer: a CommandResult with the Ok and the outcome, and a Ref when Ok is 1. 1 when it is.
Method AssertResult(response As %RegisteredObject, ok As %Boolean, outcome As %String, label As %String) As %Boolean [ Private ]
{
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Msg.CommandResult") {
		Do $$$AssertTrue(0, label_": the answer is a CommandResult")
		Quit 0
	}
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, ok_"|"_outcome, label_": the answer is "_outcome)
	Do $$$AssertEquals(response.Ref '= "", ok, label_": and it has a Ref only when it carried the command out")
	Quit (response.Ok = ok) && (response.Outcome = outcome)
}

/// The number of rows that watch Orders.
ClassMethod RowsOfProduction() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The number of rows that watch Orders and belong to neither session: other fixtures, which the stack may hold.
ClassMethod Others(a As %String, b As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ? AND Production = ? AND SessionRef NOT IN (?, ?)", ..#ORDERS, ..#ORDERSPRODUCTION, a, b)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

}
