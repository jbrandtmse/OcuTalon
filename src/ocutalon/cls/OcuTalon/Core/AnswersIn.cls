/// AnswersIn, the adapterless service through which every answer to an approval request enters the production (AD-1, AD-11).
/// FromPage is the web entry and FromTelegram the Telegram entry; both feed the same OnProcessInput through Deliver. OnProcessInput
/// holds the one rule set of who may answer, applied for every entry, in this order:
///   1. inside a bridge context (a tool's job) the answer is not_allowed, logged as a warning: a risky action waits for a person;
///   2. a SessionRef that is not a 22-character Ref is not_found;
///   3. a request that Ownership.Approval does not return for the SessionRef, or a cancelled one, is not_found, whatever the Action
///      and Channel: the session's own request, or on a local install (onlineDemo not 1) an instance request of a visible incident of
///      a production the session watches; with onlineDemo 1 only the session's own request. A failed read is an error status;
///   4. an Action other than approve or reject, or a Channel other than web, phone or telegram, is bad_answer.
/// The role rule stays with Approval.Answer: the row's RequiredRole is checked against the session's IRIS user. The answer handed
/// over names the request's own Ref, as Ownership.Approval read it.
/// An accepted answer is sent synchronously to AnswerOps, in a trace session of its own whose SuperSession is the TraceRef of
/// the session's Session row (an answer is not a turn, AD-26), and AnswerOps' AnswerResult is the output. AnswerOps calls
/// Approval.Answer in a production job, so the answer, its audit entry and its live-event fan-out run with the production's
/// privileges (DW-68). This class never calls Approval.Answer, Allowance or Conversation, and never takes a user name or a
/// SessionRef from the caller of a channel: FromPage resolves the session from the CSP session.
/// OnProcessInput answers an error status when the answer could not be handed over or no AnswerResult came back, and
/// otherwise OK with the AnswerResult, bad_answer, not_allowed and not_found included.
Class OcuTalon.Core.AnswersIn Extends Ens.BusinessService
{

/// The channels an answer may name.
Parameter CHANNELS = "web,phone,telegram";

/// How long the service waits for AnswerOps, in seconds: Approval.Answer can wait for its lock and for the hold's task.
Parameter TIMEOUT = 30;

/// The web entry: resolves the session from the CSP session (Ownership.SessionRef), then creates the service in this process and
/// hands it the answer. sessionRef is the session's Ref (empty when the CSP session can't be resolved) and result the AnswerResult.
/// The status is an error when the session can't be resolved or the answer did not reach AnswerOps.
ClassMethod FromPage(ref As %String, action As %String, channel As %String, Output result As OcuTalon.Core.Msg.AnswerResult, Output sessionRef As %String) As %Status
{
	Set result = ""
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = $Get(ref)
	Set answer.Action = $Get(action)
	Set answer.Channel = $Get(channel)
	Set answer.SessionRef = sessionRef
	Quit ..Deliver(answer, .result)
}

/// The Telegram entry (AD-11, DW-200): the press of a chat on Approve or Reject under an approval message. It resolves the session only
/// from the chat's live Pairing row, never from the press, and hands the answer to the one rule set of OnProcessInput with channel
/// telegram. Approval.Answer receives only the paired session's 22-character Ref, never a ChatRef or a chat id. ref is the approval
/// request's Ref, action approve or reject, and chatRef the press's ChatRef (Data.Pairing). code is exactly one of:
///   - approved and rejected, with the slots {"count", "itemNoun": {"one", "other"}} of the request's dry run when it has one (approved)
///     and {} otherwise;
///   - already_answered {"action", "channel", "time"} of the answer that won, and expired {"time"} of the request's ExpiresAt;
///   - not_paired {}: the chat has no live pairing;
///   - not_allowed {"kind"}: the session may not answer, or {} when the chat's row holds a session value that is no Ref, in which case
///     nothing is sent (a chat row without a session value is not_paired);
///   - not_visible {}: the request exists but is not the session's to see; unknown {}: it does not, or the Ref or the action is not one.
/// The status is an error only when the answer could not be handed over or no result came back; code is then unknown.
ClassMethod FromTelegram(ref As %String, action As %String, chatRef As %String, Output code As %String, Output slots As %DynamicObject) As %Status
{
	Set code = "unknown", slots = {}
	Set ref = $Get(ref), action = $Get(action), chatRef = $Get(chatRef)
	If '##class(OcuTalon.Bridge.Approval).IsRef(ref) || '$ListFind($ListFromString("approve,reject"), action) Quit $SYSTEM.Status.OK()
	Set chat = ##class(OcuTalon.Data.Pairing).Chat(chatRef)
	If '$IsObject(chat) || (chat.SessionRef = "") {
		Set code = "not_paired"
		Quit $SYSTEM.Status.OK()
	}
	Set sessionRef = chat.SessionRef
	Set chat = ""
	If '##class(OcuTalon.Bridge.Approval).IsRef(sessionRef) {
		Set code = "not_allowed"
		Quit $SYSTEM.Status.OK()
	}
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = ref
	Set answer.Action = action
	Set answer.Channel = "telegram"
	Set answer.SessionRef = sessionRef
	Set sc = ..Deliver(answer, .result)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject($Get(result)) Quit $SYSTEM.Status.Error(5001, "AnswersIn answered no AnswerResult")
	Set code = ..TelegramCode(result, ref, action, sessionRef, .slots)
	Quit $SYSTEM.Status.OK()
}

/// The code and slots of FromTelegram for an AnswerResult. The request is read through Ownership.Approval for the session, which is
/// how the dry run, the expiry and the kind are found; a request that read does not return gives empty slots.
ClassMethod TelegramCode(result As OcuTalon.Core.Msg.AnswerResult, ref As %String, action As %String, sessionRef As %String, Output slots As %DynamicObject) As %String [ Private ]
{
	Set slots = {}
	Set verdict = result.Result
	If verdict = "done" {
		If action = "reject" Quit "rejected"
		Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
		If $IsObject(row) {
			Set dry = ##class(OcuTalon.Live.Payload.Approval).FromRow(row).DryRun
			If $IsObject(dry) {
				If dry.Affected '= "" Do slots.%Set("count", dry.Affected, "number")
				If $IsObject(dry.ItemNoun) Do slots.%Set("itemNoun", {"one": (dry.ItemNoun.One), "other": (dry.ItemNoun.Other)})
			}
		}
		Quit "approved"
	}
	If verdict = "already_answered" {
		Do slots.%Set("action", result.WinnerAction, "string")
		Do slots.%Set("channel", result.WinnerChannel, "string")
		Do slots.%Set("time", result.WinnerAt, "string")
		Quit "already_answered"
	}
	If verdict = "expired" {
		Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
		Do slots.%Set("time", $Select($IsObject(row): row.ExpiresAt, 1: ""), "string")
		Quit "expired"
	}
	If verdict = "not_allowed" {
		Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
		Do slots.%Set("kind", $Select($IsObject(row): row.Kind, 1: ""), "string")
		Quit "not_allowed"
	}
	If verdict = "not_found" Quit $Select(##class(OcuTalon.Data.Ownership).ApprovalKnown(ref): "not_visible", 1: "unknown")
	Quit "unknown"
}

/// The one hand-over of an entry: creates the service in this process and gives it the answer (a seam for the tests). The status is an
/// error when the service can't be created or does not take the answer.
ClassMethod Deliver(answer As OcuTalon.Core.Msg.Answer, Output result As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set result = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("AnswersIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(answer, .result)
}

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Core.Msg.Answer") Quit $SYSTEM.Status.Error(5001, "AnswersIn takes an OcuTalon.Core.Msg.Answer")
	If ##class(OcuTalon.Bridge.Context).Active() {
		$$$LOGWARNING("AnswersIn refused an answer to "_pInput.Ref_" inside a bridge context")
		Quit ..Refuse("not_allowed", .pOutput)
	}
	If '##class(OcuTalon.Bridge.Approval).IsRef(pInput.SessionRef) Quit ..Refuse("not_found", .pOutput)
	Set row = ##class(OcuTalon.Data.Ownership).Approval(pInput.Ref, pInput.SessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject(row) || (row.State = "cancelled") Quit ..Refuse("not_found", .pOutput)
	If '$ListFind($ListFromString("approve,reject"), pInput.Action) || '$ListFind($ListFromString(..#CHANNELS), pInput.Channel) Quit ..Refuse("bad_answer", .pOutput)
	Set pInput.Ref = row.Ref
	Set ..%SessionId = "", ..%SuperSession = ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(pInput.SessionRef)
	If $IsObject(session) Set ..%SuperSession = session.TraceRef
	Set sc = ..Send(pInput, .response)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject($Get(response)) || 'response.%IsA("OcuTalon.Core.Msg.AnswerResult") Quit $SYSTEM.Status.Error(5001, "AnswerOps answered no AnswerResult")
	Set pOutput = response
	Quit $$$OK
}

/// The one send of the class: the answer to AnswerOps, synchronously. Private, so that only OnProcessInput sends through it, after
/// the checks; a test subclass overrides it to stand in for AnswerOps.
Method Send(request As OcuTalon.Core.Msg.Answer, Output response As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestSync("AnswerOps", request, .response, ..#TIMEOUT)
}

/// An AnswerResult that carries the result and nothing else; OK.
Method Refuse(result As %String, Output output As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set output = ##class(OcuTalon.Core.Msg.AnswerResult).%New()
	Set output.Result = result
	Quit $$$OK
}

}
