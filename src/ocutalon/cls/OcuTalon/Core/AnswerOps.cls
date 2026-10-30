/// AnswerOps, the business operation that carries out an answer to an approval request (AD-11, Veto V1). AnswersIn is its only
/// sender: a request whose header does not come from the item AnswersIn is refused with an error status and logged, and nothing is
/// answered. For an Answer it:
///   - reads the IRIS user from the Session row of the request's SessionRef (a message carries a SessionRef and never a user name,
///     AD-4); a SessionRef with no Session row is not_found;
///   - calls Approval.Answer(Ref, Action, Channel, IrisUser, SessionRef) in this production job, so that the answer, its Approval
///     audit entry and its live-event fan-out run with the production's privileges: the checked cross-owner reads that fan an
///     instance request out to its watchers fail in a web request and succeed here (DW-68). The role rule stays with Answer;
///   - answers an AnswerResult with Answer's result and, for already_answered, the winner.
/// An exception is an error status: the caller never gets a partial result.
Class OcuTalon.Core.AnswerOps Extends Ens.BusinessOperation
{

/// The class of the approval API. A test subclass names a double.
Parameter APPROVALAPI = "OcuTalon.Bridge.Approval";

/// The only item that may send to this operation.
Parameter SENDER = "AnswersIn";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Try {
		Set sc = ..Carry($Get(pRequest), .pResponse)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set pResponse = ""
		$$$LOGERROR(exception.DisplayString())
	}
	Quit sc
}

/// Checks the sender and carries out the answer; response is the AnswerResult.
Method Carry(request As %RegisteredObject, Output response As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set response = ""
	If '$IsObject($Get(request)) || 'request.%IsA("OcuTalon.Core.Msg.Answer") {
		$$$LOGERROR("AnswerOps takes an OcuTalon.Core.Msg.Answer")
		Quit $SYSTEM.Status.Error(5001, "AnswerOps takes an OcuTalon.Core.Msg.Answer")
	}
	Set source = $Select($IsObject(..%RequestHeader): ..%RequestHeader.SourceConfigName, 1: "")
	If source '= ..#SENDER {
		$$$LOGERROR("AnswerOps refused an answer sent by '"_source_"': only "_..#SENDER_" may send one")
		Quit $SYSTEM.Status.Error(5001, "AnswerOps takes answers from "_..#SENDER_" only")
	}
	Set response = ##class(OcuTalon.Core.Msg.AnswerResult).%New()
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(request.SessionRef)
	If '$IsObject(session) {
		Set response.Result = "not_found"
		Quit $$$OK
	}
	Set result = $ClassMethod(..#APPROVALAPI, "Answer", request.Ref, request.Action, request.Channel, session.IrisUser, request.SessionRef, .winner)
	Set response.Result = result
	If $IsObject($Get(winner)) {
		Set response.WinnerAction = winner.%Get("action")
		Set response.WinnerChannel = winner.%Get("channel")
		Set response.WinnerAt = winner.%Get("at")
	}
	Quit $$$OK
}

}
