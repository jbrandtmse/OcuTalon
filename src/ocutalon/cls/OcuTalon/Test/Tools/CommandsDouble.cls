/// A test double for the CommandsIn service (Story 1.10; AD-1, AD-22): it records every command it receives and answers with a fixture CommandResult.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): Test.Tools.Reminders puts it behind the CommandsIn item of OcuTalon.Production
/// (Test.Agent.RunnerFixture UseItemClass) and puts the stub back, so that OcuTalon.Core.Commands.Submit, which names the item, reaches it from
/// the tests' own process and from the job of ChatAgent. Nothing else loads it.
///   - It records each command: OnProcessInput appends $ListBuild(the verb's class, Origin, SessionRef, IdempotencyKey, the JSON of every property
///     of the command that is not empty, with its value) to ^OcuTalonTest("CommandsDouble","calls",n), n counting from 1 in
///     ^OcuTalonTest("CommandsDouble","calls") (Test.Tools.Reminders reads it; it is the pattern of Test.Bridge.ProbeSink's shared record).
///   - It answers by verb, with an Ok answer:
///       SetReminder: Outcome created, the message "The CI double set the reminder.", and SETREF and SETDUEAT (a time in another year, so
///         that Data.Time.ForMessage gives a dated form that does not depend on today's date) as Ref and DueAt;
///       CancelReminder: Outcome cancelled, the message "The CI double cancelled the reminder.", and the command's ReminderRef as Ref;
///       ListReminders: Outcome listed, an empty message, and the list contract as Data, read with SQL from the rows of OcuTalon_Data.Reminder
///         whose SessionRef is the command's and whose State is pending, by DueAt and then Ref:
///         {"reminders": [{"ref": "<Ref>", "text": "<Text>", "dueAt": "<UTC time>"}, ...]};
///       any other verb: Ok 0, Outcome not_handled.
///   - It follows the modes that a test sets (the test that sets one kills ^OcuTalonTest("CommandsDouble")):
///       ^OcuTalonTest("CommandsDouble","refuse",<the verb's class name without its package>) = <message>: Ok 0, Outcome refused, and that message;
///       ^OcuTalonTest("CommandsDouble","data") = <text>: ListReminders is answered with that text as its Data;
///       ^OcuTalonTest("CommandsDouble","fail") = 1: OnProcessInput returns an error status, after it has recorded the command; any other text is the
///         message of that status;
///       ^OcuTalonTest("CommandsDouble","empty") = 1: OnProcessInput returns an OK status and no result, after it has recorded the command.
Class OcuTalon.Test.Tools.CommandsDouble Extends Ens.BusinessService
{

/// The Ref that the double gives a reminder it "sets": 22 characters.
Parameter SETREF = "zzReminderDouble000001";

/// The due time that the double gives a reminder it "sets": in 2027, so that ForMessage gives a dated form whatever today's date is.
Parameter SETDUEAT = "2027-03-04T15:00:00Z";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject(pInput) Quit $$$ERROR($$$GeneralError, "The CI double takes a command")
	Do ..Record(pInput)
	Set failure = $Get(^OcuTalonTest("CommandsDouble", "fail"))
	If (failure '= "") && (failure '= 0) Quit $$$ERROR($$$GeneralError, $Select(failure = 1: "The CI double was set to fail", 1: failure))
	If $Get(^OcuTalonTest("CommandsDouble", "empty")) = 1 Quit $$$OK
	Set verb = $Piece($ClassName(pInput), ".", $Length($ClassName(pInput), "."))
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	If $Data(^OcuTalonTest("CommandsDouble", "refuse", verb), message) # 2 {
		Set result.Ok = 0
		Set result.Outcome = "refused"
		Set result.Message = message
	} ElseIf verb = "SetReminder" {
		Set result.Ok = 1
		Set result.Outcome = "created"
		Set result.Message = "The CI double set the reminder."
		Set result.Ref = ..#SETREF
		Set result.DueAt = ..#SETDUEAT
	} ElseIf verb = "CancelReminder" {
		Set result.Ok = 1
		Set result.Outcome = "cancelled"
		Set result.Message = "The CI double cancelled the reminder."
		Set result.Ref = pInput.ReminderRef
	} ElseIf verb = "ListReminders" {
		Set result.Ok = 1
		Set result.Outcome = "listed"
		Set result.Message = ""
		Set result.Data = $Select($Data(^OcuTalonTest("CommandsDouble", "data")) # 2: ^OcuTalonTest("CommandsDouble", "data"), 1: ..PendingOf(pInput.SessionRef))
	} Else {
		Set result.Ok = 0
		Set result.Outcome = "not_handled"
		Set result.Message = "The CI double does not handle "_verb_"."
	}
	Set pOutput = result
	Quit $$$OK
}

/// Appends the command to ^OcuTalonTest("CommandsDouble","calls"): $ListBuild(the verb's class, Origin, SessionRef, IdempotencyKey, the JSON of
/// every property that is not empty, with its value).
ClassMethod Record(command As %RegisteredObject)
{
	Set fields = {}
	Set class = ##class(%Dictionary.CompiledClass).%OpenId($ClassName(command))
	For i = 1:1:class.Properties.Count() {
		Set property = class.Properties.GetAt(i)
		If ($Extract(property.Name) = "%") || property.Private || property.Internal Continue
		Set value = $Property(command, property.Name)
		If value '= "" Do fields.%Set(property.Name, value)
	}
	Set n = $Increment(^OcuTalonTest("CommandsDouble", "calls"))
	Set ^OcuTalonTest("CommandsDouble", "calls", n) = $ListBuild($ClassName(command), command.Origin, command.SessionRef, command.IdempotencyKey, fields.%ToJSON())
}

/// The list contract as JSON text: the pending reminders of the session, the earliest due first, then by Ref.
ClassMethod PendingOf(sessionRef As %String) As %String
{
	Set data = {"reminders": []}
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Text, DueAt FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND State = 'pending' ORDER BY DueAt, Ref", sessionRef)
	While rows.%Next() {
		Do data.reminders.%Push({"ref": (rows.%GetData(1)), "text": (rows.%GetData(2)), "dueAt": (rows.%GetData(3))})
	}
	Quit data.%ToJSON()
}

}
