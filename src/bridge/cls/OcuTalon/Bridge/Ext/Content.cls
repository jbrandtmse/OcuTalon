/// The bridge's content extension (AD-6, AD-31, Story 26.3): lets a host send one image with an untrusted chat turn and learn of each accepted
/// reply. The default sends nothing and adds nothing, so the bridge runs alone (FR-5). A host extends this class and names the subclass in the
/// ContentClass setting of the Decide item.
///   - Part runs in the runner's job, once for each model call of a request of kind turn with provenance untrusted, before the AI session chats and never
///     inside a callback. A request of any other kind or provenance never reaches it, because a linked turn saves its AI session and an image must
///     never enter a stored session. When it answers a stream with bytes, the runner sends the turn's text and that one image together through
///     ChatWithContent, under every rule that binds Chat (the gate, the step audit policy, the usage record and the no-callback rule). The image is content
///     from outside, so the turn that sends it is tainted (the reply's Tainted is 1). It never goes into a message body, an agent step or the event log. It must give the same answer when called again, because a resend or a retry runs the
///     request again. An error status ends the request with that status before any model call.
///   - Accepted runs in the job of Decide, once, after Decide has accepted a usable reply of a turn and saved the turn's decision row, and gets the
///     filtered reply text. The members that it puts in hostData are added to the reply's HostData, and a member replaces one of the same name.
///     An error status or an exception from it is logged as a warning and never fails the reply.
Class OcuTalon.Bridge.Ext.Content
{

/// The image to send with the request, as its media type (image/jpeg or image/png) and a binary stream. Gives none by default: an empty media type
/// and no stream. Returns OK, or the error that ends the request.
ClassMethod Part(request As OcuTalon.Bridge.Msg.Request, Output mediaType As %String, Output data As %Stream.Object) As %Status
{
	Set mediaType = ""
	Set data = ""
	Quit $$$OK
}

/// The members to add to the HostData of the reply of an accepted turn, given its filtered text. Gives none by default.
ClassMethod Accepted(request As OcuTalon.Bridge.Msg.Request, text As %String, Output hostData As %DynamicObject) As %Status
{
	Set hostData = {}
	Quit $$$OK
}

}
