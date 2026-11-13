/// A subclass of OcuTalon.Web.Files for Test.Web.FilesApi, which overrides its private Post so that the route runs on a slot with no production (Story 25.3; AD-22).
/// It has no Test methods and the product never refers to it. Post records each Channel.WebChat.Post under ^OcuTalonTest("FilesProbe", "posts", n) (n counted in "posts"):
/// sessionRef, clientId, text, fileRef, fileName, fileMediaType and fileSize, and whether the Item's file row existed when the post arrived (rowFound). It answers by
/// ^OcuTalonTest("FilesProbe", "answer"): "" is an accepted message ({"accepted":1,"duplicate":0}), or a duplicate when the clientId was posted before; "duplicate" always
/// a duplicate; "refused" a refusal ({"accepted":0,"refused":1}); "status" an error status; "throw" throws; "garbage" an output that is not JSON. The roles of the signed-in
/// user are the text in ^OcuTalonTest("FilesProbe", "roles") when it is set (comma-separated, as $Roles is), which the OcuTalon user role check and the admin check read,
/// and the process's own $Roles otherwise.
Class OcuTalon.Test.Web.FilesProbe Extends OcuTalon.Web.Files
{

ClassMethod Post(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set n = $Increment(^OcuTalonTest("FilesProbe", "posts"))
	Set call = $Name(^OcuTalonTest("FilesProbe", "posts", n))
	Set @call@("sessionRef") = input.SessionRef
	Set @call@("clientId") = input.ClientId
	Set @call@("text") = input.Text
	Set @call@("fileRef") = input.FileRef
	Set @call@("fileName") = input.FileName
	Set @call@("fileMediaType") = input.FileMediaType
	Set @call@("fileSize") = input.FileSize
	Set @call@("rowFound") = $IsObject(##class(OcuTalon.Core.Files).Describe(input.FileRef, input.SessionRef))
	Set answer = $Get(^OcuTalonTest("FilesProbe", "answer"))
	If answer = "status" Quit $SYSTEM.Status.Error(5001, "zz WebChatIn is not running")
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz WebChatIn threw"))
	If answer = "garbage" {
		Set output = "not json"
		Quit $SYSTEM.Status.OK()
	}
	If answer = "refused" {
		Set output = {"accepted": 0, "duplicate": 0, "refused": 1}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set seen = $Data(^OcuTalonTest("FilesProbe", "seen", input.SessionRef, input.ClientId))
	Set ^OcuTalonTest("FilesProbe", "seen", input.SessionRef, input.ClientId) = 1
	Set output = {"accepted": 1, "duplicate": ((answer = "duplicate") || seen)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The roles of the signed-in user: the test's, when it set them.
ClassMethod Roles() As %String [ Private ]
{
	If $Data(^OcuTalonTest("FilesProbe", "roles")) Quit ^OcuTalonTest("FilesProbe", "roles")
	Quit ##super()
}

/// 1 when the test's roles hold the OcuTalon user role, else the process's own check.
ClassMethod HasUserRole() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("FilesProbe", "roles")) Quit (","_^OcuTalonTest("FilesProbe", "roles")_",") [ (","_##class(OcuTalon.Web.Public.Shell).#ROLE_",")
	Quit ##super()
}

}
