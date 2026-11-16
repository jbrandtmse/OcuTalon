Include Ensemble

/// The photo of a turn (AD-6, AD-21, AD-31, Story 26.3; Lane A): the host's extension of OcuTalon.Bridge.Ext.Content, named in the ContentClass setting of the
/// Decide item. A photo turn is the caption request of a photo that the session sent: a turn request of provenance untrusted whose ItemId is the ItemId of a
/// Data.Turn whose SentFile is a JPEG or a PNG.
///   - Part gives the runner the stored bytes of that photo and their media type (Core.Files.Open, for the request's OwnerRef only), so that the runner sends
///     them with the turn's text. A request with no photo gives no content. A photo that cannot be sent is an error status and no model call is made: the
///     file is gone or belongs to another session, the online demo flag is set, or SENDSPHOTOS is 0.
///   - Accepted keeps the caption: the filtered reply text, trimmed and cut to CAPTIONMAX characters, is saved as a memory of the session through the
///     SaveMemory command (Core.Commands, then CommandsIn and MemoryOps; AD-1) with the origin photo, so that recalling it taints a turn and it cannot be
///     pinned, with the IdempotencyKey ItemId:caption, and with the source learned (Memory.Ops). It answers {"caption": {memoryRef, text}}, built by code from
///     the saved row. Only a turn request of provenance untrusted is captioned (the gate of Part): any other request, a turn with no photo, the online demo and
///     SENDSPHOTOS 0 save nothing and answer {}; a refused or failed save is an error status, which Decide logs and never raises.
///   - Accepted also records which memories the reply used (Story 28.2; AD-21, AD-31), before and whatever the turn's provenance: for a turn request with an OwnerRef, the Refs in the
///     memories member of the reply's HostData (replyHostData, at most MAXUSED of them) are sent once, as an OcuTalon.Memory.Msg.Used with the owner and the time of now, through the adapterless
///     service MemoryIn, which has MemoryOps set their LastUsedAt. A reply with no such member sends nothing. The send is asynchronous, and a failure to make it is one warning with no memory
///     text: it never stops the caption and adds no member to hostData.
///   - Readable is the check that Agent.Input.ReadFile makes of a photo file.
/// The photo's bytes go no further than the runner's model call: no message body, agent step or log holds them.
Class OcuTalon.Agent.Content Extends OcuTalon.Bridge.Ext.Content
{

/// The media types of a photo, comma-separated.
Parameter PHOTOTYPES = "image/jpeg,image/png";

/// 1 when photos are sent to the model. 0 refuses every photo (Part and Readable) and saves no caption.
Parameter SENDSPHOTOS = 1;

/// The most characters of a caption memory.
Parameter CAPTIONMAX = 2000;

/// The most memories one reply marks as used.
Parameter MAXUSED = 5;

/// The business service that takes the Used message.
Parameter MEMORYIN = "MemoryIn";

/// 1 when the media type is one of PHOTOTYPES.
ClassMethod IsPhotoType(mediaType As %String) As %Boolean
{
	Quit ''$ListFind($ListFromString(..#PHOTOTYPES), $ZConvert($ZStrip($Get(mediaType), "<>W"), "L"))
}

/// The image of the turn of the request (see the class description).
ClassMethod Part(request As OcuTalon.Bridge.Msg.Request, Output mediaType As %String, Output data As %Stream.Object) As %Status
{
	Set mediaType = ""
	Set data = ""
	Set file = ..Photo(request.OwnerRef, request.ItemId, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(file) Quit $$$OK
	If '..Sendable() Quit $$$ERROR($$$GeneralError, "Photos are not sent to the model here, so the photo of the turn was not read.")
	Set stream = ##class(OcuTalon.Core.Files).Open(file.ref, request.OwnerRef, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(stream) Quit $$$ERROR($$$GeneralError, "The photo of the turn cannot be opened, so nothing was sent.")
	Set mediaType = file.mediaType
	Set data = stream
	Quit $$$OK
}

/// Records the memories the reply used, then saves the caption of a photo turn (see the class description).
ClassMethod Accepted(request As OcuTalon.Bridge.Msg.Request, text As %String, Output hostData As %DynamicObject, replyHostData As %String = "") As %Status
{
	Set hostData = {}
	Do ..Used(request, replyHostData)
	If (request.Kind '= "turn") || (request.Provenance '= "untrusted") Quit $$$OK
	Set file = ..Photo(request.OwnerRef, request.ItemId, .sc)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(file) || '..Sendable() Quit $$$OK
	Set caption = $ZStrip($Extract($ZStrip($Get(text), "<>WC"), 1, ..#CAPTIONMAX), "<>WC")
	If caption = "" Quit $$$OK
	Set command = ##class(OcuTalon.Msg.Command.SaveMemory).%New()
	Set command.SessionRef = request.OwnerRef
	Set command.IdempotencyKey = request.ItemId_":caption"
	Set command.Text = caption
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, ##class(OcuTalon.Memory.Ops).#PHOTOORIGIN, .result)
	If $$$ISERR(sc) Quit sc
	If '$IsObject(result) || 'result.Ok || (result.Outcome '= "saved") || (result.Ref = "") {
		Quit $$$ERROR($$$GeneralError, "The caption was not saved"_$Select($IsObject(result): " ("_result.Outcome_")", 1: "")_".")
	}
	Set hostData = {"caption": {"memoryRef": (result.Ref), "text": (caption)}}
	Quit $$$OK
}

/// Sends MemoryIn one Used for the memories in the memories member of the reply's HostData (see the class description). Never throws and never fails the caller:
/// a failure is one warning that holds the redacted status text and no memory text.
ClassMethod Used(request As OcuTalon.Bridge.Msg.Request, replyHostData As %String) [ Private ]
{
	If (request.Kind '= "turn") || (request.OwnerRef = "") || ($Get(replyHostData) = "") Quit
	Try {
		Set memories = {}.%FromJSON(replyHostData).memories
		If '$IsObject(memories) || 'memories.%IsA("%Library.DynamicArray") Quit
		Set refs = []
		Set iterator = memories.%GetIterator()
		While iterator.%GetNext(, .memory) && (refs.%Size() < ..#MAXUSED) {
			If $IsObject(memory) && (memory.%GetTypeOf("memoryRef") = "string") && (memory.memoryRef '= "") Do refs.%Push(memory.memoryRef)
		}
		If 'refs.%Size() Quit
		Set used = ##class(OcuTalon.Memory.Msg.Used).%New()
		Set used.SessionRef = request.OwnerRef
		Set used.MemoryRefs = refs.%ToJSON()
		Set used.UsedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = ##class(Ens.Director).CreateBusinessService(..#MEMORYIN, .service)
		If $$$ISOK(sc) Set sc = service.ProcessInput(used)
		If $$$ISERR(sc) Do ..UsedFailed($SYSTEM.Status.GetErrorText(sc))
	} Catch exception {
		Do ..UsedFailed(exception.DisplayString())
	}
}

/// The one warning of a use that could not be sent.
ClassMethod UsedFailed(reason As %String) [ Private ]
{
	Do ##class(Ens.Util.Log).LogWarning($ClassName(), "Used", "The memories that the reply used could not be recorded: "_##class(OcuTalon.Bridge.Redact).Text($Extract(reason, 1, 300)))
}

/// The Describe object {ref, name, mediaType, size} of the photo that the turn with the ItemId carries for the session, or "" when there is no such turn, it
/// carries no file, or its file is not a photo. An owner with no Session row (instance, eval, a model test) has no turn and no photo. sc is an error status only when the turn
/// of a session cannot be read.
ClassMethod Photo(ownerRef As %String, itemId As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set file = ""
	If (ownerRef = "") || (itemId = "") || '##class(OcuTalon.Data.Session).RefIndexExists(ownerRef) Quit ""
	Set turn = ##class(OcuTalon.Memory.Ops).TurnOfItem(ownerRef, itemId, .sc)
	If $$$ISERR(sc) || '$IsObject(turn) || (turn.SentFile = "") Quit ""
	Try {
		Set parsed = {}.%FromJSON(turn.SentFile)
		If $IsObject(parsed) && parsed.%IsA("%Library.DynamicObject") && (parsed.%GetTypeOf("ref") = "string") && ..IsPhotoType(parsed.%Get("mediaType")) Set file = parsed
	} Catch exception {
		Set file = ""
	}
	Quit file
}

/// 1 when a photo may be sent to the model: SENDSPHOTOS is 1 and the online demo flag is not set.
ClassMethod Sendable() As %Boolean
{
	Quit (+..#SENDSPHOTOS = 1) && '..OnlineDemo()
}

/// 1 when the session's file can be sent as a photo: Sendable and the file opens for the session. ReadFile asks it.
ClassMethod Readable(fileRef As %String, sessionRef As %String) As %Boolean
{
	If '..Sendable() Quit 0
	Set stream = ##class(OcuTalon.Core.Files).Open(fileRef, sessionRef, .sc)
	Quit $$$ISOK(sc) && $IsObject(stream) && (stream.Size > 0)
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

}
