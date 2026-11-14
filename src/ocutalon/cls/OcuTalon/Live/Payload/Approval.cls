/// The payload of the approval live event: the public view of one approval request. Lane B publishes it.
Class OcuTalon.Live.Payload.Approval Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The approval request's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum APPROVALKIND.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// One of Msg.Enum APPROVALSTATE.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// The incident's Ref, when the request belongs to one.
Property IncidentRef As %String(%JSONFIELDNAME = "incidentRef", MAXLEN = 22);

/// The tool that waits for the answer.
Property ToolName As %String(%JSONFIELDNAME = "toolName", MAXLEN = 128);

/// Why the request needs an answer.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 1000);

/// The name of the fix kind of a fix request (Story 23.2), such as repair_resend, suspend_item, resume_item or reroute; empty for any other kind of request.
Property FixKind As %String(%JSONFIELDNAME = "fixKind", MAXLEN = 64);

/// What the action would do, from the dry run.
Property DryRun As OcuTalon.Live.Payload.Part.DryRun(%JSONFIELDNAME = "dryRun");

/// When the request was raised, UTC to the second.
Property RaisedAt As %String(%JSONFIELDNAME = "raisedAt", MAXLEN = 20);

/// When the request expires, UTC to the second.
Property ExpiresAt As %String(%JSONFIELDNAME = "expiresAt", MAXLEN = 20);

/// The answer's action.
Property AnsweredAction As %String(%JSONFIELDNAME = "answeredAction", MAXLEN = 32);

/// One of Msg.Enum CHANNEL.
Property AnsweredChannel As %String(%JSONFIELDNAME = "answeredChannel", MAXLEN = 32);

/// Who answered.
Property AnsweredBy As %String(%JSONFIELDNAME = "answeredBy", MAXLEN = 128);

/// When the request was answered, UTC to the second.
Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 20);

/// The result of the approved action.
Property Result As %String(%JSONFIELDNAME = "result", MAXLEN = 32);

/// When the action finished, UTC to the second.
Property FinishedAt As %String(%JSONFIELDNAME = "finishedAt", MAXLEN = 20);

/// The trace session id of the request's incident (AD-26); absent when the request has no incident that the session can
/// see, or the incident has no trace.
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// The payload for an approval request row, with every row-backed field set (the fix kind of a fix request included); dryRun is the row's stored JSON parsed
/// into its part (left absent when the row holds none or it can't be read). A partner_warning request (Story 23.5) has the DryRun {notice, recipients, simulated}: its part holds
/// only the notice, the recipients as "Name <address>" and simulated, with no repair keys and no reading. A setting request (Story 40.6) has the DryRun {key, ownerRef, old, new}:
/// its part holds only before and after, each the old or new object's text, the string itself when it is one, and "" when it is missing; every other
/// field of the part stays empty, eitherWay is 0 and Reading is not asked. An email request (a fix request of the kind email, Story 22.7) has the DryRun {to, subject, text}, with to an array of
/// addresses: its part holds the recipients as plain addresses, the exact text as the notice and the exact subject as before, every other field empty, simulated 0, eitherWay 0 and no
/// reading. A dry run of an email request that is not as expected leaves those members out, and the part is still there, never an error. For any other kind the part's eitherWay and reading are the answer of Watch.Notice Reading over that dry run
/// and the row's FixParameters, the rule that chose the notice's key: eitherWay 1 with the reading, else 0 and no reading. Neither is kept on the row. The reason has no source in the row and
/// stays empty. The trace target is the request's incident's: when sessionRef, the Ref of the session the payload is for,
/// and the row's IncidentRef are both set and Ownership.Incident gives an incident that session can see with a
/// TraceHeaderId, traceHeaderId is that id and traceNamespace the current namespace. Otherwise the payload has no target.
ClassMethod FromRow(row As OcuTalon.Bridge.Data.ApprovalRequest, sessionRef As %String = "") As OcuTalon.Live.Payload.Approval
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Kind = row.Kind
	Set payload.State = row.State
	Set payload.IncidentRef = row.IncidentRef
	Set payload.ToolName = row.ToolName
	Set payload.FixKind = row.FixKind
	Set payload.RaisedAt = row.RaisedAt
	Set payload.ExpiresAt = row.ExpiresAt
	Set payload.AnsweredAction = row.AnsweredAction
	Set payload.AnsweredChannel = row.AnsweredChannel
	Set payload.AnsweredBy = row.AnsweredBy
	Set payload.AnsweredAt = row.AnsweredAt
	Set payload.Result = row.Result
	Set payload.FinishedAt = row.FinishedAt
	If (sessionRef '= "") && (row.IncidentRef '= "") {
		Set incident = ##class(OcuTalon.Data.Ownership).Incident(row.IncidentRef, sessionRef, .sc)
		If $SYSTEM.Status.IsOK(sc), $IsObject(incident), incident.TraceHeaderId '= "" {
			Set payload.TraceHeaderId = incident.TraceHeaderId
			Set payload.TraceNamespace = $Namespace
		}
	}
	If row.DryRun '= "" {
		Try {
			Set dry = ##class(%DynamicObject).%FromJSON(row.DryRun)
			Set part = ##class(OcuTalon.Live.Payload.Part.DryRun).%New()
			If row.Kind = "setting" {
				Set part.Before = ..SettingText(dry, "old")
				Set part.After = ..SettingText(dry, "new")
				Set payload.DryRun = part
				Quit
			}
			If row.FixKind = "partner_warning" {
				Set part.Notice = dry.notice
				Set part.Simulated = +dry.simulated
				If $IsObject(dry.recipients) {
					Set iterator = dry.recipients.%GetIterator()
					While iterator.%GetNext(, .recipient) {
						Do part.Recipients.Insert(recipient.name_" <"_recipient.address_">")
					}
				}
				Set payload.DryRun = part
				Quit
			}
			If (row.Kind = "fix") && (row.FixKind = "email") {
				Do ..EmailPart(dry, part)
				Set payload.DryRun = part
				Quit
			}
			Set part.Affected = dry.affected
			Set part.Resend = dry.resend
			Set part.LeftOut = dry.leftOut
			Set part.Field = dry.field
			Set part.Before = dry.before
			Set part.After = dry.after
			Set part.Item = dry.item
			Set part.From = dry.from
			Set part.To = dry.to
			Set part.Example = dry.example
			If $IsObject(dry.itemNoun) {
				Set part.ItemNoun = ##class(OcuTalon.Live.Payload.Part.ItemNoun).%New()
				Set part.ItemNoun.One = dry.itemNoun.one
				Set part.ItemNoun.Other = dry.itemNoun.other
			}
			Set reading = ##class(OcuTalon.Watch.Notice).Reading(dry, row.FixParameters)
			If reading '= "" {
				Set part.EitherWay = 1
				Set part.Reading = reading
			}
			Set payload.DryRun = part
		} Catch {
			Set payload.DryRun = ""
		}
	}
	Quit payload
}

/// Fills the part of an email request from its dry run {to, subject, text}: every address of the array to as a plain string in Recipients, the text in Notice and the subject in
/// Before. A member that is missing or not of its type is left out, and so is the whole list when one entry of to is not a string, so that no object reference is ever shown.
ClassMethod EmailPart(dry As %DynamicObject, part As OcuTalon.Live.Payload.Part.DryRun) [ Private ]
{
	If dry.%GetTypeOf("to") = "array" {
		Set clean = 1
		For i = 0:1:dry.to.%Size() - 1 {
			If dry.to.%GetTypeOf(i) '= "string" Set clean = 0
		}
		If clean {
			For i = 0:1:dry.to.%Size() - 1 Do part.Recipients.Insert(dry.to.%Get(i))
		}
	}
	If dry.%GetTypeOf("text") = "string" Set part.Notice = dry.text
	If dry.%GetTypeOf("subject") = "string" Set part.Before = dry.subject
}

/// The text of the setting DryRun's value of the name (old or new): the object's text, the string itself, else "".
ClassMethod SettingText(dry As %DynamicObject, name As %String) As %String [ Private ]
{
	Set type = dry.%GetTypeOf(name)
	If type = "string" Quit dry.%Get(name)
	If type '= "object" Quit ""
	Set value = dry.%Get(name)
	Quit $Select(value.%GetTypeOf("text") = "string": value.%Get("text"), 1: "")
}

}
