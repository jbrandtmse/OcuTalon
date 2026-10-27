/// AnswersIn, the adapterless service through which every answer to an approval request enters the production (AD-1, AD-11).
/// FromPage is the web entry (Story 10.3 adds the Telegram entry, which feeds the same OnProcessInput). OnProcessInput holds the
/// one rule set of who may answer, applied for every entry, in this order:
///   1. inside a bridge context (a tool's job) the answer is not_allowed, logged as a warning: a risky action waits for a person;
///   2. a SessionRef that is not a 22-character Ref is not_found;
///   3. a request that Ownership.Approval does not return for the SessionRef is not_found, whatever the Action and Channel: the
///      session's own request, or on a local install (onlineDemo not 1) an instance request of a visible incident of a production
///      the session watches; with onlineDemo 1 only the session's own request. A failed read is an error status;
///   4. an Action other than approve or reject, or a Channel other than web, phone or telegram, is bad_answer.
/// The role rule stays with Approval.Answer: the row's RequiredRole is checked against the session's IRIS user.
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
	If '$IsObject(row) Quit ..Refuse("not_found", .pOutput)
	If '$ListFind($ListFromString("approve,reject"), pInput.Action) || '$ListFind($ListFromString(..#CHANNELS), pInput.Channel) Quit ..Refuse("bad_answer", .pOutput)
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
