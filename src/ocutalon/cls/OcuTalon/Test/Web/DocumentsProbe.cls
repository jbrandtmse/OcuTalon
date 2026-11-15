/// A subclass of OcuTalon.Web.Documents for Test.Web.DocumentsApi, which overrides its private Submit so that the routes run on a slot with no
/// production (Story 34.2; AD-22). It has no Test methods and the product never refers to it. Submit records each command under
/// ^OcuTalonTest("DocumentsProbe", "submits", n) (n counted in "submits"): class, origin (the class's ORIGIN, which the real Submit passes to
/// Commands.Submit), name, contentType, uploadRef, size (the bytes of the Upload row the command names, read when the command arrives),
/// uploadSessionRef (that row's SessionRef), sessionRef and documentRef. It answers by
/// ^OcuTalonTest("DocumentsProbe", "answer"): "" is a done command (Ok 1, Ref zzDocRef0123456789abcd; a done AddDocument takes its Upload row,
/// as DocumentOps does, unless ^OcuTalonTest("DocumentsProbe", "keep") is set), "not_built", "not_found", "failed" and
/// any other word are a CommandResult with Ok 0 and that Outcome, "status" is an error status, "throw" throws an error, "okerror" is an Ok result with an error status and "none" is OK with no result. The route's sweep measures its hour from ^OcuTalonTest("DocumentsProbe", "now") when it is set, else from SLOTNOW (2000-01-01, so it deletes no real row), and "throw" there makes the sweep throw (SweepNow). The owner item is running
/// unless ^OcuTalonTest("DocumentsProbe", "owner") is "off". The text route's own body builder reads a text that is no stream when ^OcuTalonTest("DocumentsProbe", "textfail") is set. The roles of the
/// signed-in user are the text in ^OcuTalonTest("DocumentsProbe", "roles") when it is set (comma-separated, as $Roles is), which the OcuTalon
/// user role check and the admin check of OnPreDispatch read, and the process's own $Roles otherwise.
Class OcuTalon.Test.Web.DocumentsProbe Extends OcuTalon.Web.Documents
{

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set n = $Increment(^OcuTalonTest("DocumentsProbe", "submits"))
	Set call = $Name(^OcuTalonTest("DocumentsProbe", "submits", n))
	Set @call@("class") = $ClassName(command)
	Set @call@("origin") = ..#ORIGIN
	Set @call@("sessionRef") = command.SessionRef
	If command.%IsA("OcuTalon.Msg.Command.AddDocument") {
		Set @call@("name") = command.Name
		Set @call@("contentType") = command.ContentType
		Set @call@("uploadRef") = command.UploadRef
		Set upload = ##class(OcuTalon.Data.Upload).RefIndexOpen(command.UploadRef)
		If $IsObject(upload) {
			Set @call@("size") = upload.Content.Size
			Set @call@("uploadSessionRef") = upload.SessionRef
		}
		Kill upload
	}
	If command.%IsA("OcuTalon.Msg.Command.RemoveDocument") Set @call@("documentRef") = command.DocumentRef
	Set answer = $Get(^OcuTalonTest("DocumentsProbe", "answer"))
	If answer = "status" Quit $SYSTEM.Status.Error(5001, "zz CommandsIn is not running")
	If answer = "none" Quit $SYSTEM.Status.OK()
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz CommandsIn threw"))
	If answer = "okerror" {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 1
		Set result.Outcome = "added"
		Quit $SYSTEM.Status.Error(5001, "zz an answer with an error status")
	}
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	If answer = "" {
		Set result.Ok = 1
		Set result.Outcome = "added"
		Set result.Ref = "zzDocRef0123456789abcd"
		If command.%IsA("OcuTalon.Msg.Command.AddDocument") && '$Get(^OcuTalonTest("DocumentsProbe", "keep")) Do ##class(OcuTalon.Data.Upload).Take(command.UploadRef, command.SessionRef)
	} Else {
		Set result.Ok = 0
		Set result.Outcome = answer
	}
	Quit $SYSTEM.Status.OK()
}

/// The JSON body of the text route, built by the route's own TextBody; when the test set ^OcuTalonTest("DocumentsProbe", "textfail"), that
/// TextBody gets a stand-in for the row with the row's ref and name and a text that is no stream, so its read of the text fails.
ClassMethod TextBody(row As OcuTalon.Data.Document, Output body As %Stream.TmpCharacter) As %Status [ Private ]
{
	If $Get(^OcuTalonTest("DocumentsProbe", "textfail")) Set row = {"Ref": (row.Ref), "Name": (row.Name), "Text": ""}
	Quit ##super(row, .body)
}

/// The time the route's sweep measures from: ^OcuTalonTest("DocumentsProbe", "now") when the test set it, else SLOTNOW, so that a test that
/// does not set it purges no row of the slot (a purge at the real clock runs only on a throwaway).
ClassMethod SweepNow() As %String [ Private ]
{
	Set now = $Get(^OcuTalonTest("DocumentsProbe", "now"), ..#SLOTNOW)
	If now = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "The sweep's clock failed"))
	Quit now
}

/// The sweep's clock when the test set none: an hour before it, no upload is made.
Parameter SLOTNOW = "2000-01-01T00:00:00Z";

/// 1 unless the test set ^OcuTalonTest("DocumentsProbe", "owner") to "off": the owner item is running (the slot has no production to ask).
ClassMethod OwnerRunning() As %Boolean [ Private ]
{
	Quit ($Get(^OcuTalonTest("DocumentsProbe", "owner")) '= "off")
}

/// The roles of the signed-in user: the test's, when it set them.
ClassMethod Roles() As %String [ Private ]
{
	If $Data(^OcuTalonTest("DocumentsProbe", "roles")) Quit ^OcuTalonTest("DocumentsProbe", "roles")
	Quit ##super()
}

/// 1 when the test's roles hold the OcuTalon user role, else the process's own check.
ClassMethod HasUserRole() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("DocumentsProbe", "roles")) Quit (","_^OcuTalonTest("DocumentsProbe", "roles")_",") [ (","_##class(OcuTalon.Web.Public.Shell).#ROLE_",")
	Quit ##super()
}

/// The live role set of OnPreDispatch's re-read: the test's own roles (Roles).
ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = ..Roles()
	Quit $$$OK
}

}
