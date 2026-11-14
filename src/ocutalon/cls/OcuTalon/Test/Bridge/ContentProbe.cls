/// The ContentClass of the content tests (Story 26.3; AD-6, AD-31): a helper that extends the bridge's Ext.Content and answers a fixed PNG for the ItemId that
/// ^OcuTalonTest("ContentProbe", "item") names. THE PRODUCTION'S JOBS CALL IT, so its state is in globals and not in the process: the runner's job calls Part and the job of
/// Decide calls Accepted.
///   - Part notes each call in ^OcuTalonTest("ContentProbe", "part", n) as the kind, provenance and ItemId of the request, answers the error text of the node "partError" when it is set,
///     and otherwise answers the PNG (media type image/png) for the ItemId of the node "item", and no content for any other;
///   - Accepted notes each call in ^OcuTalonTest("ContentProbe", "accepted", n) as the ItemId and the text, and in ^OcuTalonTest("ContentProbe", "row", n) whether the Decision row of the
///     request's ItemId and kind exists at that moment, then by the node "mode": "" or "members" gives {"probe": {"text": <the text>}}, "none" gives no member, and "error" (an error status)
///     and "throw" (an exception) first put that member in hostData, so that a Decide that merged it anyway would show it.
/// ImageBytes and ImageBase64 are the PNG: a 4 by 4 red square.
Class OcuTalon.Test.Bridge.ContentProbe Extends OcuTalon.Bridge.Ext.Content
{

/// The base64 of the PNG that Part answers.
Parameter PNG = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGP4z8AARwzEcQCukw/x0F8jngAAAABJRU5ErkJggg==";

ClassMethod Part(request As OcuTalon.Bridge.Msg.Request, Output mediaType As %String, Output data As %Stream.Object) As %Status
{
	Set mediaType = ""
	Set data = ""
	Set ^OcuTalonTest("ContentProbe", "part", $Increment(^OcuTalonTest("ContentProbe", "part"))) = $ListBuild(request.Kind, request.Provenance, request.ItemId)
	If $Get(^OcuTalonTest("ContentProbe", "partError")) '= "" Quit $$$ERROR($$$GeneralError, ^OcuTalonTest("ContentProbe", "partError"))
	If (request.ItemId = "") || (request.ItemId '= $Get(^OcuTalonTest("ContentProbe", "item"))) Quit $$$OK
	Set data = ..Image()
	Set mediaType = "image/png"
	Quit $$$OK
}

ClassMethod Accepted(request As OcuTalon.Bridge.Msg.Request, text As %String, Output hostData As %DynamicObject) As %Status
{
	Set hostData = {}
	Set n = $Increment(^OcuTalonTest("ContentProbe", "accepted"))
	Set ^OcuTalonTest("ContentProbe", "accepted", n) = $ListBuild(request.ItemId, text)
	Set ^OcuTalonTest("ContentProbe", "row", n) = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexExists(request.ItemId, request.Kind)
	Set mode = $Get(^OcuTalonTest("ContentProbe", "mode"))
	If mode = "none" Quit $$$OK
	Set hostData.probe = {"text": (text)}
	If mode = "error" Quit $$$ERROR($$$GeneralError, "The probe refuses to accept")
	If mode = "throw" $$$ThrowStatus($$$ERROR($$$GeneralError, "The probe throws"))
	Quit $$$OK
}

/// The PNG as a new binary stream at its start.
ClassMethod Image() As %Stream.TmpBinary
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Do stream.Write($SYSTEM.Encryption.Base64Decode(..#PNG))
	Do stream.Rewind()
	Quit stream
}

/// The number of calls of the node (part or accepted) so far.
ClassMethod Calls(node As %String) As %Integer
{
	Quit +$Get(^OcuTalonTest("ContentProbe", node))
}

}
