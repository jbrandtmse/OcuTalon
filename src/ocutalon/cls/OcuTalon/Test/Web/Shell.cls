/// Tests of the shell's file serving and redirect (matrix rows 8 and 13), called on the class with a stand-in
/// request and response, so that the gateway, which normalises paths before IRIS sees them, cannot answer in
/// the class's place. A fixture web application (/zzshell<n>) serves a temporary folder that holds the
/// files, a directory and, one level above the folder, a file that must never be reached. OnAfterAllTests removes
/// the application and the folder; the real applications are never touched.
Class OcuTalon.Test.Web.Shell Extends %UnitTest.TestCase
{

/// The fixture's number: the application is /zzshell<n>.
Property Number As %Integer;

Property Application As %String;

/// The temporary folder: app/ is the application's Path, secret.txt lies beside it.
Property Root As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Shell", "n"))
	Set ..Application = "/zzshell"_..Number
	Set file = ##class(%File).TempFilename("d")
	Do ##class(%File).Delete(file)
	Set ..Root = ##class(%File).NormalizeDirectory(file)
	Set sc = $SYSTEM.Status.OK()
	If '##class(%File).CreateDirectoryChain(..Root_"app/sub/") Set sc = $SYSTEM.Status.Error(5001, "cannot create "_..Root)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..WriteFile(..Root_"app/index.html", "<!doctype html>index-body")
	If $SYSTEM.Status.IsOK(sc) Set sc = ..WriteFile(..Root_"app/inside.txt", "inside-body")
	If $SYSTEM.Status.IsOK(sc) Set sc = ..WriteFile(..Root_"secret.txt", "secret-body")
	If $SYSTEM.Status.IsOK(sc) Set sc = ..CreateApplication()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	If ..Root '= "" Do ##class(%File).RemoveDirectoryTree(..Root)
	Quit $SYSTEM.Status.OK()
}

/// A file of the folder is streamed with its content; index.html alone carries the page policy and no-cache.
Method TestServesFiles()
{
	Set body = ..Serve("inside.txt", .response)
	Do $$$AssertEquals(..Code(response), 200, "a file of the folder is served")
	Do $$$AssertEquals(body, "inside-body", "with its content")
	Do $$$AssertEquals(response.GetHeader("Content-Security-Policy"), "", "no page policy on another file")
	Do $$$AssertEquals(response.GetHeader("Cache-Control"), "", "and no cache header of ours")

	Set body = ..Serve("index.html", .response)
	Do $$$AssertEquals(..Code(response), 200, "index.html is served")
	Do $$$AssertEquals(body, "<!doctype html>index-body", "with its content")
	Do $$$AssertEquals(response.GetHeader("Content-Security-Policy"), "script-src 'self'", "the page policy")
	Do $$$AssertEquals(response.GetHeader("Cache-Control"), "no-cache", "no-cache")
}

/// A missing file and a directory answer 404 and write no body, also for a name that the folder lacks but
/// IRIS's /csp/broker/ holds, where the stream server looks next.
Method TestAnswersNotFound()
{
	For path = "no-such-file.js", "sub", "sub/no-such-file.js", "zenutils.js", "sub/x/cspxmlhttp.js" {
		Set body = ..Serve(path, .response)
		Do $$$AssertEquals(..Code(response), 404, "'"_path_"' answers 404")
		Do $$$AssertEquals(body, "", "'"_path_"' writes no body")
	}
}

/// A path that leaves the folder is refused by the class itself, before the stream server is asked. The stream
/// server also answers 404 for these paths and the gateway normalises them first, so the outcome is the same
/// without the guard; what only the guard guarantees is that the path never reaches the file layer.
Method TestRefusesPathsThatLeaveTheFolder()
{
	For path = "../secret.txt", "sub/../../secret.txt", "..\secret.txt", "/secret.txt", "sub\..\..\secret.txt" {
		Set body = ..Serve(path, .response, .reached)
		Do $$$AssertEquals(..Code(response), 404, "'"_path_"' answers 404")
		Do $$$AssertTrue(body '[ "secret-body", "'"_path_"' does not stream the file outside the folder")
		Do $$$AssertEquals(body, "", "'"_path_"' writes no body")
		Do $$$AssertEquals(reached, 0, "'"_path_"' never reaches the stream server")
	}
}

/// A conditional GET for a file that has not changed since keeps the stream server's 304 and writes no body,
/// for index.html too: a reload of the shell is answered this way.
Method TestNotModified()
{
	For path = "index.html", "inside.txt" {
		Set body = ..Serve(path, .response, , "Fri, 01 Jan 2100 00:00:00 GMT")
		Do $$$AssertEquals(..Code(response), 304, "'"_path_"' not modified since answers 304")
		Do $$$AssertEquals(body, "", "'"_path_"' writes no body")
	}
}

/// The sign-in POST is answered with a redirect to the same URL and query, on one line.
Method TestRedirect()
{
	Set response = ..Redirect("/ocutalon/index.html", "x=1&y=2")
	Do $$$AssertEquals(..Code(response), 303, "303 See Other")
	Do $$$AssertEquals(response.GetHeader("Location"), "/ocutalon/index.html?x=1&y=2", "the same URL and query")
	Set response = ..Redirect("/ocutalon/", "")
	Do $$$AssertEquals(response.GetHeader("Location"), "/ocutalon/", "no query, no question mark")
	Set response = ..Redirect("/ocutalon/a"_$Char(13, 10)_"b", "q="_$Char(10)_"c")
	Do $$$AssertEquals(response.GetHeader("Location"), "/ocutalon/ab?q=c", "line breaks in the URL and the query are dropped")
}

/// --- helpers ---

/// Serves path through the shell with stand-in request and response objects, as the fixture application,
/// and returns the body that was written. response is the response object; reached is 1 when the stream
/// server was asked for a file. since, when given, is the request's If-Modified-Since header.
Method Serve(path As %String, Output response, Output reached, since As %String = "") As %String [ Private ]
{
	New %request, %response, %stream
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make(..Application_"/")
	If since '= "" Set %request.CgiEnvs("HTTP_IF_MODIFIED_SINCE") = since
	Set %response = ##class(%CSP.Response).%New()
	Set file = ##class(%File).TempFilename("html")
	Set io = $IO
	Open file:("NWS"):5
	If '$Test Quit ""
	Use file
	Try {
		Set sc = ##class(OcuTalon.Web.Public.Shell).Serve(path)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Set reached = $Data(%request.Data("FILE"))
	Set response = %response
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(file)
	Set body = stream.Read(100000)
	Kill stream
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK(sc, "'"_path_"' is answered without an error status")
	Quit body
}

/// The numeric status of a response.
ClassMethod Code(response As %CSP.Response) As %Integer [ Private ]
{
	Quit +$Piece(response.Status, " ")
}

/// Answers a POST for url and query through the shell's Redirect, and returns the response object.
Method Redirect(url As %String, query As %String) As %CSP.Response [ Private ]
{
	New %request, %response
	Set %request = ##class(%CSP.Request).%New()
	Set %response = ##class(%CSP.Response).%New()
	Set %request.URL = url
	If query '= "" Set %request.CgiEnvs("QUERY_STRING") = query
	Do $$$AssertStatusOK(##class(OcuTalon.Web.Public.Shell).Redirect(""), "Redirect")
	Quit %response
}

Method WriteFile(path As %String, text As %String) As %Status [ Private ]
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set sc = stream.LinkToFile(path)
	If $SYSTEM.Status.IsOK(sc) Set sc = stream.Write(text)
	If $SYSTEM.Status.IsOK(sc) Set sc = stream.%Save()
	Quit sc
}

Method CreateApplication() As %Status [ Private ]
{
	New $Namespace
	Set home = $Namespace
	Set $Namespace = "%SYS"
	Set props("NameSpace") = home
	Set props("Enabled") = 1
	Set props("AutheEnabled") = 32
	Set props("Path") = ..Root_"app/"
	Set props("ServeFiles") = 3
	Set props("CookiePath") = ..Application_"/"
	Quit ##class(Security.Applications).Create(..Application, .props)
}

/// Deletes every fixture application that an earlier run may have left, and the fixture's nodes.
ClassMethod Clean() [ Private ]
{
	Kill ^OcuTalonTest("Shell")
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Applications WHERE Name %STARTSWITH '/zzshell'")
	While result.%Next() {
		Do ##class(Security.Applications).Delete(result.%GetData(1))
	}
}

}
