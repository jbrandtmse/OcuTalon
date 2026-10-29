/// A subclass of OcuTalon.Core.Admin for the tests, which override its private seams Roles and Send: the roles come from
/// ^OcuTalonTest("AdminProbe", "roles"), and nothing reaches the production. Each Send is counted in
/// ^OcuTalonTest("AdminProbe", "sent") and records the command's DemoMode and ActingUser and the origin argument ("origin") under
/// ^OcuTalonTest("AdminProbe", "sent", n). The answer comes from ^OcuTalonTest("AdminProbe", "answer"): "" is an OK status
/// with a CommandResult of Ok 1 and the outcome "zzdone", "error" is an error status, "throw" throws, and "noresult" is an
/// OK status with no CommandResult. Capture runs SetDemoMode with its output going to a temporary file and answers what was
/// printed. The product never refers to it.
Class OcuTalon.Test.Core.AdminProbe Extends OcuTalon.Core.Admin
{

ClassMethod Roles() As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("AdminProbe", "roles"))
}

ClassMethod Send(command As OcuTalon.Msg.Command, origin As %String, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("AdminProbe", "sent"))
	Set ^OcuTalonTest("AdminProbe", "sent", n, "demoMode") = command.DemoMode
	Set ^OcuTalonTest("AdminProbe", "sent", n, "actingUser") = command.ActingUser
	Set ^OcuTalonTest("AdminProbe", "sent", n, "origin") = origin
	Set answer = $Get(^OcuTalonTest("AdminProbe", "answer"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw."))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz no production")
	If answer = "noresult" Quit $$$OK
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 1
	Set result.Outcome = "zzdone"
	Set result.Message = "zz done"
	Quit $$$OK
}

/// What SetDemoMode(mode) prints, with a line feed for each new line: the current device is a temporary file while it runs, and
/// the file is read and removed after it (the device is put back at the end).
ClassMethod Capture(mode As %String) As %String
{
	Set file = ##class(%File).TempFilename("txt")
	Set io = $IO
	Set text = ""
	Open file:"NWS":5
	If '$Test Quit "<<the capture file did not open>>"
	Try {
		Use file
		Do ..SetDemoMode(mode)
	} Catch exception {
		Set text = "<<thrown: "_exception.DisplayString()_">>"
	}
	Use io
	Close file
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set text = $Translate(stream.Read(32000), $Char(13))_text
	Kill stream
	Do ##class(%File).Delete(file)
	Quit text
}

}
