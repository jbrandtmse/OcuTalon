/// Tests of the session events of /ocutalon (Story 2.2; AD-4): the sign-in attaches the user's durable session when the
/// user holds the role, does nothing without it, and answers OK even when the attach fails, because an error status from
/// OnLogin neither logs the user out nor shows the sign-in page, and writes a failed attach to the console log (messages.log)
/// as one line that names the error code and no user. The role is passed to AttachFor, which OnLogin calls with
/// Shell.HasRole(). The session row that the test may create for the running user is removed by Test.Data.Fixture.Clean.
Class OcuTalon.Test.Web.SessionEvents Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// A failed attach (no CSP session) still answers OK and creates no row; without the role nothing is attached or
/// created; with the role the user's durable session is recorded in the CSP session.
Method TestAttachForAlwaysAnswersOK()
{
	New %session
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set %session = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "a failed attach still answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and creates no session row")

	Set %session = ##class(%CSP.Session).%New("ZzSessionEvents", 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(0), "without the role it answers OK")
	Do $$$AssertEquals($Get(%session.Data("OcuTalon.SessionRef")), "", "attaches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and creates no session row")

	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "with the role it answers OK")
	Set ref = $Get(%session.Data("OcuTalon.SessionRef"))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "and the user's durable session is recorded in the CSP session")
	If $IsObject(row) {
		Do $$$AssertEquals($ZConvert(row.IrisUser, "U"), $ZConvert($Username, "U"), "it is the signed-in user's")
		If before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), $Select(before = 0: 1, 1: before), "one row for the user")
}

/// A failed attach is written to the console log as exactly one new line of OcuTalon.Web.SessionEvents, whose text is the
/// fixed sentence and the error code and nothing else, so it holds no user name; an attach that works, and a user without
/// the role, write no such line. The console log folds a message that repeats the one before it, so a line of this test's
/// own is written first and the attach's line is never a repeat.
Method TestFailureIsLoggedWithoutTheUser()
{
	New %session
	Set log = $System.Util.ManagerDirectory()_"messages.log"
	Do $$$AssertTrue(##class(%File).Exists(log), "the console log exists: "_log)
	Set %session = ""
	Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Test.Web.SessionEvents: a line that the attach's is not a repeat of", 0, 0)
	Set mark = ##class(%File).GetFileSize(log)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "a failed attach answers OK")
	Set lines = ..LinesSince(log, mark)
	Do $$$AssertEquals($ListLength(lines), 1, "and writes one line of OcuTalon.Web.SessionEvents to the console log")
	If $ListLength(lines) = 1 {
		Set text = $Piece($List(lines, 1), "OcuTalon.Web.SessionEvents: ", 2)
		Do $$$AssertEquals(text, "the session could not be attached, error 5001", "the line holds the sentence and the error code only, so no user name")
	}

	Set %session = ##class(%CSP.Session).%New("ZzSessionEventsLog", 0)
	Set mark = ##class(%File).GetFileSize(log)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(0), "without the role it answers OK")
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "and writes no line")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "with the role and a CSP session it answers OK")
	Do $$$AssertEquals($ListLength(..LinesSince(log, mark)), 0, "and writes no line")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen($Get(%session.Data("OcuTalon.SessionRef")))
	If before = 0, $IsObject(row) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
}

/// The lines of OcuTalon.Web.SessionEvents that the console log gained after byte offset mark, as a $List of lines.
ClassMethod LinesSince(log As %String, mark As %Integer) As %List [ Private ]
{
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(log)
	Do stream.MoveTo(mark + 1)
	Set text = ""
	While 'stream.AtEnd {
		Set text = text_stream.Read(32000)
	}
	Set lines = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $Piece(text, $Char(10), i)
		If line [ "OcuTalon.Web.SessionEvents: " Set lines = lines_$ListBuild(line)
	}
	Quit lines
}

}
