/// Tests of what the roles of OcuTalon's own MCP server can and cannot do (Story 28.3; AD-21, AD-24; R-28.3-1 (c)), in a job that signs in as a fixture user, as a web request does. THEY RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), through Test.Mcp.ServiceCase. The job reports through ^IRIS.TempOcuTalonMcp(run), which every user can write, because a user without database read
/// cannot write ^OcuTalonTest. Whether a call through iris-mcp-server runs with the same roles is not measured here (Story 28.5): the application role is added by IRIS to a request that runs in
/// /mcp/ocutalon, which these jobs stand for with the user's own roles.
///   - TestOutsideTheApplication (the Planner's pin 1): a user who holds only OcuTalonMCPClient, signed in outside /mcp/ocutalon (the terminal's path), gets <PROTECT> on each of the code, data and
///     private databases, one assertion each; a control user who holds the three read grants reads all three;
///   - TestInsideTheRoles (R-28.3-1 (c)): a user who holds OcuTalonMCPClient and the grants of the application role (the role ROLEINSIDE, a copy) reads the three databases, gets <PROTECT> on a write
///     to each, runs OnAuthenticate, ReadOnlyProblem and both tools of OcuTalon.Mcp.ServiceRead with its own records (a check and an incident) and no others, and writes its audit entry.
Class OcuTalon.Test.Mcp.ServiceRoles Extends OcuTalon.Test.Mcp.ServiceCase
{

/// The longest to wait for the job's report, in seconds.
Parameter JOBSECONDS = 60;

/// The databases of the application role's grants, in the order of the probe's report: code, data, private.
Parameter DATABASES = "OCUTALON_CODE,OCUTALON_DATA,OCUTALON_PRIVATE";

/// The directories of the databases, as a "|" list in DATABASES' order.
ClassMethod Directories() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set dirs = ""
	For i = 1:1:3 {
		Do ##class(Config.Databases).Get($Piece(..#DATABASES, ",", i), .properties)
		Set dirs = dirs _ $Select(i = 1: "", 1: "|") _ ##class(%File).NormalizeDirectory($Get(properties("Directory")), $SYSTEM.Util.ManagerDirectory())
	}
	Quit dirs
}

/// Starts the job in the mode (outside or inside) as the user and waits for its report. Returns the node of the report, or "" (with a failure) when the job does not finish in JOBSECONDS.
Method RunProbe(mode As %String, user As %String) As %String [ Private ]
{
	Set number = $Increment(^OcuTalonTest("McpServiceRoles", "n"))
	Set run = $Name(^IRIS.TempOcuTalonMcp(number))
	If run '= "" Kill @run
	Job ##class(OcuTalon.Test.Mcp.ServiceRoles).Probe(number, mode, user, ..Directories())
	Set finished = ##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), ..#JOBSECONDS)
	Do $$$AssertTrue(finished, "the job reports within " _ ..#JOBSECONDS _ " seconds")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing")
	Do $$$AssertEquals($Get(@run@("login")), 1, "control: the job logged in as the fixture user")
	Do $$$AssertEquals($Get(@run@("user")), user, "control: and runs as it")
	Do $$$AssertTrue($Get(@run@("job")) '= $Job, "control: the job is not this process")
	If finished && ($Get(@run@("login")) = 1) Quit run
	Quit ""
}

/// The job: logs in as the user (no password) and reports under ^IRIS.TempOcuTalonMcp(run): job, login, user and roles; for each database (dirs, a "|" list) a read of a global of that
/// database by its directory ("read", i: "ok" and $Data, or the error's first nine characters) and, in the mode inside, a write to it ("write", i: "written" or the error); in the mode inside
/// also: "authenticate" (OnAuthenticate's status), "problem" (ReadOnlyProblem), and the JSON of both tools of OcuTalon.Mcp.ServiceRead ("checks", "activity"); then done. It uses no class
/// before the reads, because the user may not read the code database.
ClassMethod Probe(run As %String, mode As %String, user As %String, dirs As %String)
{
	Set node = $Name(^IRIS.TempOcuTalonMcp(run))
	Try {
		Set @node@("job") = $Job
		Set @node@("login") = $SYSTEM.Security.Login(user)
		Set @node@("user") = $Username
		Set @node@("roles") = $Roles
		For i = 1:1:3 {
			Set ref = "^|""^^" _ $Piece(dirs, "|", i) _ """|ZzMcpProbe"
			Try {
				Set found = $Data(@ref)
				Set @node@("read", i) = "ok " _ found
			} Catch {
				Set @node@("read", i) = $Extract($ZERROR, 1, 9)
			}
			If mode = "inside" {
				Try {
					Set @ref = 1
					Kill @ref
					Set @node@("write", i) = "written"
				} Catch {
					Set @node@("write", i) = $Extract($ZERROR, 1, 9)
				}
			}
		}
		If mode = "inside" {
			Set @node@("authenticate") = ##class(OcuTalon.Mcp.Service).OnAuthenticate("Basic", "")
			Set @node@("problem") = ##class(OcuTalon.Mcp.Service).ReadOnlyProblem()
			Set @node@("checks") = ##class(OcuTalon.Mcp.ServiceRead).CheckStatus().%ToJSON()
			Set @node@("activity") = ##class(OcuTalon.Mcp.ServiceRead).RecentActivity().%ToJSON()
		}
	} Catch exception {
		Set @node@("error") = $ZERROR
	}
	Set @node@("done") = 1
}

Method TestOutsideTheApplication()
{
	If '..Guard() Quit
	Set resources = $Parameter("OcuTalon.Install.Step.Mcp", "APPROLERESOURCES")
	Set client = ..NewUser("o", $Parameter("OcuTalon.Install.Step.Mcp", "CLIENTROLE"))
	Do ..NewRole(..#ROLEREADS, resources)
	Set control = ..NewUser("k", ..#ROLEREADS)
	Set run = ..RunProbe("outside", client)
	If run '= "" {
		Do $$$AssertEquals($Get(@run@("roles")), $Parameter("OcuTalon.Install.Step.Mcp", "CLIENTROLE"), "control: the user holds only OcuTalonMCPClient")
		For i = 1:1:3 {
			Do $$$AssertEquals($Get(@run@("read", i)), "<PROTECT>", "outside the application, OcuTalonMCPClient cannot read the database " _ $Piece(..#DATABASES, ",", i))
		}
	}
	If run '= "" Kill @run
	Set run = ..RunProbe("outside", control)
	If run '= "" {
		For i = 1:1:3 {
			Do $$$AssertTrue($Get(@run@("read", i)) [ "ok", "control: the user with the read grants reads the database " _ $Piece(..#DATABASES, ",", i) _ ": " _ $Get(@run@("read", i)))
		}
	}
	If run '= "" Kill @run
}

Method TestInsideTheRoles()
{
	If '..Guard() Quit
	Set resources = $Parameter("OcuTalon.Install.Step.Mcp", "APPROLERESOURCES")
	Do ..NewRole(..#ROLEINSIDE, resources)
	Set user = ..NewUser("i", $Parameter("OcuTalon.Install.Step.Mcp", "CLIENTROLE") _ "," _ ..#ROLEINSIDE)
	Set other = ..#USER _ "other"
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set otherSession = ##class(OcuTalon.Test.Data.Fixture).Session(other)
	Set refs = session _ "," _ otherSession
	Set refs = refs _ "," _ ##class(OcuTalon.Test.Data.Fixture).Check(session, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": "ZzMcpMine", "Result": "failed", "Finding": "zz finding", "LastRunAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set refs = refs _ "," _ ##class(OcuTalon.Test.Data.Fixture).Check(otherSession, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": "ZzMcpTheirs", "Result": "passed", "Finding": "zz finding", "LastRunAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	For owner = session, otherSession {
		Set count = $Select(owner = session: 3, 1: 8)
		Set refs = refs _ "," _ ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).AddSeconds(now, -600), ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"State": "open", "Count": (count), "NoticeCount": (count), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -840)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -660))})
	}
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set run = ..RunProbe("inside", user)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	If run '= "" {
		Do $$$AssertTrue($Get(@run@("roles")) [ ..#ROLEINSIDE, "control: the job holds the copy of the application role")
		For i = 1:1:3 {
			Do $$$AssertTrue($Get(@run@("read", i)) [ "ok", "it reads the database " _ $Piece(..#DATABASES, ",", i) _ ": " _ $Get(@run@("read", i)))
			Do $$$AssertEquals($Get(@run@("write", i)), "<PROTECT>", "and cannot write the database " _ $Piece(..#DATABASES, ",", i))
		}
		Do $$$AssertEquals($Get(@run@("authenticate")), 1, "OnAuthenticate lets the request through")
		Do $$$AssertEquals($Get(@run@("problem")), "", "ReadOnlyProblem is empty")
		Set checks = {}.%FromJSON($Get(@run@("checks"), "{}"))
		Do $$$AssertTrue(($Get(@run@("checks")) [ "ZzMcpMine") && ($Get(@run@("checks")) '[ "ZzMcpTheirs"), "check_status holds the caller's check and not another user's: " _ $Extract($Get(@run@("checks")), 1, 200))
		Set activity = {}.%FromJSON($Get(@run@("activity"), "{}"))
		Do $$$AssertEquals(activity.ok, 1, "recent_activity answers ok under the roles")
		Set size = $Select($IsObject(activity.incidents): activity.incidents.%Size(), 1: -1)
		Do $$$AssertEquals(size, 1, "recent_activity holds one incident under the roles: " _ $Extract($Get(@run@("activity")), 1, 200))
		If size = 1 Do $$$AssertEquals(activity.incidents.%Get(0).count, 3, "the caller's own (count 3), and not the other user's (count 8)")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", user, , 2)
		Do $$$AssertEquals(entries.%Size(), 2, "and each of the two calls wrote its audit entry as the caller")
		If entries.%Size() = 2 Do $$$AssertEquals(entries.%Get(0).username, user, "the entries are written by the caller")
	}
	If run '= "" Kill @run
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
}

}
