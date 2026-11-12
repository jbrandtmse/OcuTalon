/// The privileges that registering the mail OAuth2 client needs (Story 21.8; DW-1180; AD-24). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it makes a
/// role and a user in %SYS and registers IRIS's OAuth2 client OcuTalonMail through the real OcuTalon.Channel.Email.OAuth, and puts every object back.
/// The production runs as the user _Ensemble, which holds %All on the stack that was measured, so the earlier runs of registering proved that the path works and
/// not what it needs. This class measures what it needs with a fixture user, which holds only the fixture role ROLE, that logs in to a child process (the one-argument Login, no password): FLOOR
/// is the set of resources that only lets such a user run OcuTalon's code, and MEASURED is what registering needs on top of it. The class makes no grant to any
/// OcuTalon role or install path, and what it lists is what was measured, not a claim about the least a production could run with.
///   - TestRegisterNeedsEachPrivilege: with FLOOR and all of MEASURED the fixture user registers the client (it existed after the call) and removes it
///     again; with FLOOR and MEASURED minus one member, for each member, registering is refused and leaves no client OcuTalonMail and no new server definition
///     or token row in %SYS; with MEASURED and no FLOOR registering is refused too. The list is printed in the test log, one line for each member with the error code of its refusal.
Class OcuTalon.Test.Channel.EmailOAuthPrivileges Extends %UnitTest.TestCase
{

/// The fixture user and its role (IRIS allows no user and role of one name), and the folder of the child's report. The user has a random password that nothing uses, so
/// that it can only be reached by the one-argument Login.
Parameter USER = "zzOcuTalonOAuthPriv";

Parameter ROLE = "zzOcuTalonOAuthPrivRole";

Parameter FOLDER = "/tmp/zzocutalonoauthpriv/";

/// The seconds that the child may take.
Parameter JOBSECONDS = 60;

/// The dummy client of the registering, and the page origin it is registered for.
Parameter CLIENTID = "zz-priv-client.example";

Parameter ORIGIN = "http://127.0.0.1:52773";

/// The floor: the resources that only let the user run OcuTalon's code in OCUTALON.
Parameter FLOOR = "%DB_OCUTALON_CODE:R";

/// What registering needs on top of the floor (the measured list; a member is a resource and the permission).
Parameter MEASURED = "%Admin_OAuth2_Client:USE,%DB_IRISSYS:R";

/// Why the class does not run ("" when it may).
Property Missing As %String [ Private ];

Property AppWas As %String [ Private ];

Method OnBeforeAllTests() As %Status
{
	If $SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Email.OAuth).#TESTVARIABLE) '= 1 {
		Set ..Missing = "this is not a throwaway made with the CI override ("_##class(OcuTalon.Channel.Email.OAuth).#TESTVARIABLE_" is not 1), so the privilege tests don't run here"
		Quit $$$OK
	}
	Set ..AppWas = ##class(OcuTalon.Test.Channel.EmailOAuth).AppEnabled()
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Do ##class(%File).RemoveDirectoryTree(..#FOLDER)
	Quit $$$OK
}

/// Removes the fixture user and role, whatever the registering left in %SYS, and puts the web application's flag back.
Method Clean() [ Private ]
{
	Do ..DropUser()
	Do ##class(OcuTalon.Test.Channel.EmailOAuth).Wipe()
	If ..AppWas '= "" Do ##class(OcuTalon.Test.Channel.EmailOAuth).SetApp(+..AppWas)
}

/// 1 when the class may change IRIS's objects here; otherwise the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// With the floor and the measured set the fixture user registers the client and removes it; leaving out any one member, registering is refused and changes nothing.
Method TestRegisterNeedsEachPrivilege()
{
	If '..Guard() Quit
	Set clean = ##class(OcuTalon.Test.Channel.EmailOAuth).Snapshot()
	Set all = ..#MEASURED
	Set full = ..Run(..#FLOOR_$Select(..#FLOOR = "": "", 1: ",")_all, "full")
	If '$IsObject(full) Quit
	Do $$$AssertEquals(full.error, "", "control: the job threw nothing: "_full.error)
	Do $$$AssertEquals(full.login_"|"_full.user, "1|"_..#USER, "control: the job logged in as the fixture user")
	Do $$$AssertTrue('$ListFind($ListFromString(full.roles, ","), "%All") && '$ListFind($ListFromString(full.roles, ","), "%Manager"), "control: with neither %All nor %Manager ("_full.roles_")")
	Do $$$AssertEquals(full.register, 1, "with the floor and all of the measured set, registering succeeds: "_full.registerError)
	Do $$$AssertEquals(full.clientDuring, 1, "and the client OcuTalonMail existed after it")
	Do $$$AssertEquals(full.remove, 1, "and removing it succeeds: "_full.removeError)
	Do $$$AssertEquals($Piece(##class(OcuTalon.Test.Channel.EmailOAuth).Snapshot(), "|", 1, 4), $Piece(clean, "|", 1, 4), "and no client, server definition or token row is left")
	Do $$$LogMessage("DW-1180: the removal by this user leaves the web application /csp/sys/oauth2 as the registering made it (its count of clients is an SQL read that the user may not make): "_##class(OcuTalon.Test.Channel.EmailOAuth).AppEnabled())
	Do ..Clean()
	Do $$$LogMessage("DW-1180 measured set: "_all)
	Set count = $Length(all, ",")
	For i = 1:1:count {
		Set member = $Piece(all, ",", i)
		Set rest = ""
		For j = 1:1:count {
			If j '= i Set rest = rest_$Select(rest = "": "", 1: ",")_$Piece(all, ",", j)
		}
		Set report = ..Run(..#FLOOR_$Select(..#FLOOR = "": "", 1: ",")_rest, "without"_i)
		If '$IsObject(report) Continue
		Do $$$AssertEquals(report.login, 1, member_": the job logged in")
		Do $$$AssertEquals(report.user, ..#USER, member_": the job ran as the fixture user")
		Do $$$AssertEquals(report.register, 0, "without "_member_", registering is refused")
		Do $$$AssertEquals(##class(OcuTalon.Test.Channel.EmailOAuth).Snapshot(), clean, "without "_member_", no client, server definition or token row was made")
		Do $$$LogMessage("DW-1180: without "_member_" registering is refused: "_report.registerError_report.error)
		Do ..Clean()
	}
	Set report = ..Run(all, "withoutfloor")
	If $IsObject(report) {
		Do $$$AssertEquals(report.register, 0, "without the floor "_..#FLOOR_" registering is refused")
		Do $$$AssertEquals(##class(OcuTalon.Test.Channel.EmailOAuth).Snapshot(), clean, "without the floor, no client, server definition or token row was made")
		Do $$$LogMessage("DW-1180: without the floor "_..#FLOOR_" registering is refused: "_report.registerError_report.error)
	}
	Do ..Clean()
}

/// Runs the child as a user whose role holds the resources; answers its report (a dynamic object), or "" when it did not report.
Method Run(resources As %String, tag As %String) As %DynamicObject [ Private ]
{
	Do ##class(%File).CreateDirectoryChain(..#FOLDER)
	Set path = ##class(%File).NormalizeFilename(..#FOLDER_tag_".json")
	Do ##class(%File).Delete(path)
	Do $$$AssertStatusOK(..CreateUser(resources), tag_": the fixture user is made with "_resources)
	Job ##class(OcuTalon.Test.Channel.EmailOAuthPrivileges).Probe(..#USER, path, ..#CLIENTID, ..#ORIGIN)
	Set deadline = $ZHorolog + ..#JOBSECONDS
	While '##class(%File).Exists(path) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Set finished = ##class(%File).Exists(path)
	Do $$$AssertTrue(finished, tag_": the job reports within "_..#JOBSECONDS_" seconds")
	If 'finished Quit ""
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(path)
	Set report = ##class(%DynamicObject).%FromJSON(stream)
	Quit report
}

/// The child: logs in as the user (the one-argument Login), registers the client for Google through the real class (the probe stands in for the job check, which is not
/// a privilege; the CI switch stays off, so the endpoints are the real https constants, no warning is logged to OcuTalon's database and no provider is contacted), checks that the client exists, removes it, and writes a JSON report to the file through a temporary name that is renamed once complete.
ClassMethod Probe(user As %String, path As %String, clientId As %String, origin As %String)
{
	Set report = {"error": "", "login": 0, "register": 0, "registerError": "", "clientDuring": 0, "remove": 0, "removeError": ""}
	Try {
		Do report.%Set("login", $SYSTEM.Security.Login(user))
		Do report.%Set("user", $Username)
		Do report.%Set("roles", $Roles)
		Set ^||OcuTalonEmailOAuthProbe("job") = 1
		Set sc = ##class(OcuTalon.Test.Channel.EmailOAuthProbe).Register("google", clientId, "zz-priv-secret", origin, "", .changed, .owned, .app)
		Do report.%Set("register", $SYSTEM.Status.IsOK(sc))
		If $SYSTEM.Status.IsError(sc) Do report.%Set("registerError", $SYSTEM.Status.GetErrorText(sc))
		If $SYSTEM.Status.IsOK(sc) {
			Do report.%Set("clientDuring", ##class(OcuTalon.Test.Channel.EmailOAuth).ClientExists("OcuTalonMail"))
			Set sc = ##class(OcuTalon.Test.Channel.EmailOAuthProbe).Remove(owned, .nowOwned, .gone)
			Do report.%Set("remove", $SYSTEM.Status.IsOK(sc))
			If $SYSTEM.Status.IsError(sc) Do report.%Set("removeError", $SYSTEM.Status.GetErrorText(sc))
		}
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

/// Makes the fixture role with the resources (permission after the colon) and the user that holds only it.
Method CreateUser(resources As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Do ..DropUser()
	Set sc = ##class(Security.Roles).Create(..#ROLE, "OcuTalon test fixture", resources)
	If $$$ISERR(sc) Quit sc
	Quit ##class(Security.Users).Create(..#USER, ..#ROLE, "Zz"_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18))_"xY!9", "OcuTalon test fixture", , , , 0, 1)
}

/// Removes the fixture user and role.
Method DropUser() [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If ##class(Security.Users).Exists(..#USER) Do ##class(Security.Users).Delete(..#USER)
	If ##class(Security.Roles).Exists(..#ROLE) Do ##class(Security.Roles).Delete(..#ROLE)
}

}
