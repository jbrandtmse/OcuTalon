/// Tests that the vital signs are read, and a capped database is never passed, by a process that holds the role of the service user (Story 17.5; AD-24,
/// owner ruling U-290 as reversed). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: they make a user that
/// holds OcuTalonServiceRole and a role of the read and write of OcuTalon's databases, start a job that logs in as it and runs Checks.Coverage Build over the real
/// readers, and read the job's report. One database of OcuTalon is given a very large maximum size for the second job and put back after each test, also
/// after a failure; the user is deleted by the same hooks.
///   - TestNoPrivilegeNeeded: the job holds no %Admin_Operate:USE (control); with no maximum on any database the five vital rows are read and each is passed
///     or failed (never unread), with whole-number figures; the database space row is not_checked with the ruled reason, on the size-limit line and with
///     no figure, once a database has a maximum size.
Class OcuTalon.Test.Watch.ServiceUser Extends OcuTalon.Test.Watch.Case
{

Parameter USER = "ZzQaVitals17";

Parameter JOBSECONDS = 40;

/// The role that gives the user the databases to run OcuTalon's code: read and write of OcuTalon's databases, and nothing administrative.
Parameter ROLE = "ZzQaVitalsDb17";

Parameter RESOURCES = "%DB_OCUTALON_CODE:RW,%DB_OCUTALON_DATA:RW,%DB_OCUTALON_PRIVATE:RW,%DB_OCUTALON_PUBLIC:RW";

/// The folder of the jobs' report files.
Parameter FOLDER = "/tmp/zzqavitals17/";

/// The Ref of the fixture session of the test, for the clean-up.
Property FixtureSession As %String(MAXLEN = 22);

/// The directory of the database that the test gave a maximum size, and the maximum it had (MB).
Property Capped As %String(MAXLEN = "");

Property WasMaxSize As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..DropUser()
	Quit ##super()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Uncap()
	Do ..DropUser()
	Do ..DropFixtureSession()
	Do ##class(%File).RemoveDirectoryTree(..#FOLDER)
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Do ..Uncap()
	Do ..DropUser()
	Do ..DropFixtureSession()
	Do ##class(%File).RemoveDirectoryTree(..#FOLDER)
	Quit ##super()
}

/// Removes the fixture session of the test, if it made one.
Method DropFixtureSession()
{
	If ..FixtureSession = "" Quit
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..FixtureSession)
	Set ..FixtureSession = ""
}

Method TestNoPrivilegeNeeded()
{
	If '..Ready() Quit
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzqavitals")
	Set ..FixtureSession = session
	Do $$$AssertStatusOK(..CreateUser(), "a user that holds the service role is made")
	Set ok = ..Report("plain", session, .plain)
	If ok {
		Do $$$AssertEquals(plain.user, ..#USER, "control: the job runs as the user")
		Do $$$AssertTrue($ListFind($ListFromString(plain.roles, ","), "OcuTalonServiceRole") && '$ListFind($ListFromString(plain.roles, ","), "%All") && '$ListFind($ListFromString(plain.roles, ","), "%Manager"), "with the service role, and neither %All nor %Manager: "_plain.roles)
		Do $$$AssertEquals(plain.operate, 0, "control: it holds no %Admin_Operate:USE")
		Do $$$AssertEquals(plain.sc, 1, "Build is OK")
		Set rows = plain.rows
		Set figures = plain.figures
		Do $$$AssertEquals(rows.%Size(), 5, "five vital rows, no watch")
		For i = 0:1:rows.%Size() - 1 {
			Set row = rows.%Get(i)
			Do $$$AssertTrue((row.result = "passed") || (row.result = "failed"), row.entry_" is read: "_row.result_" "_row.finding)
		}
		Do $$$AssertEquals(figures.databasesFull, figures.databasesFull \ 1, "databasesFull is a whole number: "_figures.databasesFull)
		Do $$$AssertTrue(figures.databasesFull '= "", "and is there, because no database has a maximum size")
		Do $$$AssertEquals(figures.upDays, figures.upDays \ 1, "upDays is a whole number")
	}
	Set directory = ..PublicDirectory()
	Do $$$AssertTrue(directory '= "", "the directory of OcuTalon's public database is found")
	If directory = "" Quit
	Do $$$AssertStatusOK(..Cap(directory, 100000), "OcuTalon's public database is given a maximum size")
	Set ok = ..Report("capped", session, .capped)
	If 'ok Quit
	Set rows = capped.rows
	Set lines = capped.lines
	Set figures = capped.figures
	Do $$$AssertEquals(capped.operate, 0, "control: the job holds no %Admin_Operate:USE")
	Do $$$AssertEquals(rows.%Get(1).entry_"|"_rows.%Get(1).result_"|"_rows.%Get(1).finding, "database space|not_checked|OcuTalon can't read this database's size limit", "a database with a maximum size: not_checked, with the ruled reason, never passed")
	Do $$$AssertEquals(lines.%Get(1).key, "digest.notCheckedSizeLimit", "on the size-limit line")
	Do $$$AssertEquals(figures.databasesFull, "", "with no figure")
	Set others = ""
	For i = 0:1:rows.%Size() - 1 {
		If i '= 1 Set others = others_$Select(others = "": "", 1: ",")_rows.%Get(i).result
	}
	Do $$$AssertTrue(others '[ "not_checked", "the other four signs are still read: "_others)
}

/// --- helpers ---
/// Starts the job in the mode for the session and waits for its report file; the report, a dynamic object, is given in report, and 1 when the job reported and threw nothing.
Method Report(mode As %String, session As %String, Output report As %DynamicObject) As %Boolean [ Private ]
{
	Set report = {}
	Do ##class(%File).CreateDirectoryChain(..#FOLDER)
	Set path = ..File(mode)
	Do ##class(%File).Delete(path)
	Job ##class(OcuTalon.Test.Watch.ServiceUser).Probe(mode, ..#USER, session, path)
	Set deadline = $ZHorolog + ..#JOBSECONDS
	While '##class(%File).Exists(path) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Set finished = ##class(%File).Exists(path)
	Do $$$AssertTrue(finished, mode_": the job reports within "_..#JOBSECONDS_" seconds")
	If 'finished Quit 0
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(path)
	Set report = ##class(%DynamicObject).%FromJSON(stream)
	Do $$$AssertEquals(report.error, "", mode_": and threw nothing: "_report.error)
	Do $$$AssertEquals(report.login, 1, mode_": it logged in")
	Quit (report.error = "")
}

/// The path of the report file of a mode.
ClassMethod File(mode As %String) As %String [ Private ]
{
	Quit ##class(%File).NormalizeFilename(..#FOLDER_mode_".json")
}

/// The job: logs in as the user (the one-argument Login, no password), then runs Build over the last day for the session and writes its report to the file
/// as JSON, through a temporary name that is renamed once complete: login, user, roles, operate (the result of Security.Check on %Admin_Operate:USE), sc
/// (1 when Build's status is OK), rows, lines and figures; or error when it throws. The test globals are not writable by such a user, so the report is a file.
ClassMethod Probe(mode As %String, user As %String, session As %String, path As %String)
{
	Set report = {"error": ""}
	Try {
		Do report.%Set("login", $SYSTEM.Security.Login(user))
		Do report.%Set("user", $Username)
		Do report.%Set("roles", $Roles)
		Do report.%Set("operate", +$SYSTEM.Security.Check("%Admin_Operate", "USE"))
		Set to = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = ##class(OcuTalon.Checks.Coverage).Build(session, ##class(OcuTalon.Data.Time).AddSeconds(to, -86400), to, .rows, .lines, .vitals)
		Do report.%Set("sc", $SYSTEM.Status.IsOK(sc))
		Do report.%Set("rows", rows)
		Do report.%Set("lines", lines)
		Do report.%Set("figures", vitals.figures)
	} Catch exception {
		Do report.%Set("error", exception.DisplayString())
	}
	Set temporary = path_".tmp"
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(temporary)
	Do stream.Write(report.%ToJSON())
	Do stream.%Save()
	Set stream = ""
	Do ##class(%File).Rename(temporary, path)
}

/// The directory of OcuTalon's public database, as the reader names it, or "".
Method PublicDirectory() As %String [ Private ]
{
	Set dest = ##class(%SYS.Namespace).GetGlobalDest("OCUTALON", "^"_##class(OcuTalon.Data.Public.Settings).#GLOBALNAME)
	Quit $Select($Piece(dest, "^", 2) = "": "", 1: ##class(%File).NormalizeDirectory($Piece(dest, "^", 2)))
}

/// Gives the database in the directory a maximum size in megabytes; the one it had is kept for Uncap.
Method Cap(directory As %String, megabytes As %Integer) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set database = ##class(SYS.Database).%OpenId(directory)
	If '$IsObject(database) Quit $SYSTEM.Status.Error(5001, "The database "_directory_" is not found")
	Set ..Capped = directory
	Set ..WasMaxSize = database.MaxSize
	Set database.MaxSize = megabytes
	Quit database.%Save()
}

/// Puts the maximum size of the database that Cap changed back.
Method Uncap() [ Private ]
{
	If ..Capped = "" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	Set database = ##class(SYS.Database).%OpenId(..Capped)
	If $IsObject(database) {
		Set database.MaxSize = ..WasMaxSize
		Do database.%Save()
	}
	Set ..Capped = ""
}

/// Makes the user, which holds the service role and ROLE, and a random password that nothing uses. ROLE holds the resources of RESOURCES that exist.
Method CreateUser() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ..DropUser()
	Set resources = ""
	For i = 1:1:$Length(..#RESOURCES, ",") {
		Set resource = $Piece(..#RESOURCES, ",", i)
		If ##class(Security.Resources).Exists($Piece(resource, ":", 1)) Set resources = resources_$Select(resources = "": "", 1: ",")_resource
	}
	Set sc = ##class(Security.Roles).Create(..#ROLE, "OcuTalon test fixture", resources)
	If $$$ISERR(sc) Quit sc
	Quit ##class(Security.Users).Create(..#USER, "OcuTalonServiceRole,"_..#ROLE, "Zz"_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18))_"xY!9", "OcuTalon test fixture", , , , 0, 1)
}

Method DropUser() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(..#USER) Do ##class(Security.Users).Delete(..#USER)
	If ##class(Security.Roles).Exists(..#ROLE) Do ##class(Security.Roles).Delete(..#ROLE)
}

}
