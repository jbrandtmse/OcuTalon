Include Ensemble

/// The one way a tool submits a command (AD-1, AD-4, AD-6, AD-18), and the shaping of the owner's answer for the model.
///   - Run fills the common fields of the command from the bridge context of the call: SessionRef is the context's OwnerRef, and
///     IdempotencyKey is the context's ItemId, a colon and the command's position in the call (the context's CommandCount plus 1, written
///     back, so that a call that runs again numbers its commands from 1 again). It sends the command through
///     OcuTalon.Core.Commands.Submit, which sets the origin tool because a context is active, and puts the CommandResult in result. A call
///     with no context, with an owner that is not a session's Ref (instance, eval, empty) or with no ItemId submits nothing.
///   - Answer is the CommandResult as a dynamic object for the model: ok, the owner's message unchanged, and, when the owner gave them, the ref
///     and the due time in the instance zone. The UTC time is never shown to the model.
///   - Listed is the answer of ListReminders: Answer for a refusal, otherwise the pending reminders that the owner's Data holds, in its order,
///     with their due times in the instance zone. A Data that cannot be read is a failure, never an empty list.
/// The model-facing texts are plain sentences for the model, never shown to the user as written, in ASCII. A tool method runs inside AI
/// Hub's callback, so this class makes no AI Hub call and no Python call (AD-6), and it never reads or writes a table of the owner.
Class OcuTalon.Tools.CommandCall
{

/// The answer when the call is not a session's turn.
Parameter NOSESSION = "Reminders belong to the conversation of a signed-in session, and this call has none, so nothing was done.";

/// The answer when the command could not be submitted or its answer is not a CommandResult.
Parameter NOTSENT = "The reminder service did not answer, so nothing was done.";

/// The answer when the list that the owner gave cannot be read.
Parameter NOTREAD = "The reminder list could not be read, so it is not known which reminders are pending.";

/// Submits the command for the session of the call. Returns "" once the owner has answered (the CommandResult is in result), and otherwise
/// the object for the model, {"ok": false, "message": ...}: NOSESSION when the call is not a session's turn (nothing is submitted), and
/// NOTSENT when Submit gives an error or an answer that is not a CommandResult (one Type 3 warning names the command's class and holds the
/// status text, redacted). It leaves the event-log session of the calling job as it was: CommandsIn is a business service, which clears the
/// job's session when its ProcessInput ends, so the warnings that the job logs after a tool call stay in the session of its decision.
ClassMethod Run(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %DynamicObject
{
	Set result = ""
	If '##class(OcuTalon.Bridge.Context).Active() Quit ..Refusal(..#NOSESSION)
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	If '$IsObject(context) || '..IsSessionRef(context.OwnerRef) || (context.ItemId = "") Quit ..Refusal(..#NOSESSION)
	Set position = +context.CommandCount + 1
	Do ##class(OcuTalon.Bridge.Context).Put("CommandCount", position)
	Set command.SessionRef = context.OwnerRef
	Set command.IdempotencyKey = context.ItemId_":"_position
	Set answered = ""
	Set jobSession = $Get($$$JobSessionId)
	Try {
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .answered)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If jobSession '= "" Set $$$JobSessionId = jobSession
	If $$$ISOK(sc) && ('$IsObject(answered) || '$ClassMethod($ClassName(answered), "%Extends", "OcuTalon.Msg.CommandResult")) {
		Set sc = $SYSTEM.Status.Error(5001, "The answer is not an OcuTalon.Msg.CommandResult")
	}
	If $$$ISERR(sc) {
		$$$LOGWARNING("A reminder tool could not submit "_$ClassName(command)_": "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		Quit ..Refusal(..#NOTSENT)
	}
	Set result = answered
	Quit ""
}

/// The CommandResult as an object for the model: ok (a JSON boolean) and the owner's message unchanged, then, only when they are not empty,
/// ref, due (OcuTalon.Data.Time.ForMessage of the due time) and dueLocal (ToLocal of it).
ClassMethod Answer(result As OcuTalon.Msg.CommandResult) As %DynamicObject
{
	Set answer = {}
	Do answer.%Set("ok", +result.Ok, "boolean")
	Set answer.message = result.Message
	If result.Ref '= "" Set answer.ref = result.Ref
	If result.DueAt '= "" {
		Set due = ##class(OcuTalon.Data.Time).ForMessage(result.DueAt)
		Set local = ##class(OcuTalon.Data.Time).ToLocal(result.DueAt)
		If due '= "" Set answer.due = due
		If local '= "" Set answer.dueLocal = local
	}
	Quit answer
}

/// The answer of ListReminders for the model. A refusal (Ok 0) is Answer. Otherwise it reads result.Data, the list contract
/// {"reminders": [{"ref", "text", "dueAt"}, ...]}, and gives {"ok": true, "zone": the instance zone, "reminders": [{"ref", "text", "due",
/// "dueLocal"}, ...]} in the order of Data. A Data that cannot be read (not JSON, no reminders array, a reminder with no ref or with a due
/// time that is not UTC to the second) logs one Type 3 warning and gives {"ok": false, "message": NOTREAD}.
ClassMethod Listed(result As OcuTalon.Msg.CommandResult) As %DynamicObject
{
	If 'result.Ok Quit ..Answer(result)
	Set reminders = []
	Set problem = ""
	Try {
		Set data = {}.%FromJSON(result.Data)
		If data.%GetTypeOf("reminders") '= "array" {
			Set problem = "the data has no reminders array"
		} Else {
			Set iterator = data.reminders.%GetIterator()
			While iterator.%GetNext(, .item) {
				If $IsObject(item) && (item.%GetTypeOf("ref") = "string") && (item.ref '= "") && (item.%GetTypeOf("text") = "string") && (item.%GetTypeOf("dueAt") = "string") {
					Set due = ##class(OcuTalon.Data.Time).ForMessage(item.dueAt)
					Set local = ##class(OcuTalon.Data.Time).ToLocal(item.dueAt)
				} Else {
					Set due = "", local = ""
				}
				If (due = "") || (local = "") {
					Set problem = "a reminder of the data has no ref, no text or no readable due time"
					Quit
				}
				Do reminders.%Push({"ref": (item.ref), "text": (item.text), "due": (due), "dueLocal": (local)})
			}
		}
	} Catch exception {
		Set problem = "the data is not JSON"
	}
	If problem '= "" {
		$$$LOGWARNING("The list of ListReminders cannot be read: "_##class(OcuTalon.Bridge.Redact).Text(problem))
		Quit ..Refusal(..#NOTREAD)
	}
	Quit {"ok": true, "zone": (##class(OcuTalon.Data.Time).Zone()), "reminders": (reminders)}
}

/// {"ok": false, "message": the text}.
ClassMethod Refusal(message As %String) As %DynamicObject [ Private ]
{
	Quit {"ok": false, "message": (message)}
}

/// 1 when the text is a session's Ref: 22 characters from A-Z, a-z, 0-9, - and _.
ClassMethod IsSessionRef(text As %String) As %Boolean [ Private ]
{
	Quit text ? 22(1A,1N,1"-",1"_")
}

}
