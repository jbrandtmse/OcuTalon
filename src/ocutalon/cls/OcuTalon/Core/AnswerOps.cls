/// AnswerOps, the business operation that carries out an answer to an approval request (AD-11, Veto V1). AnswersIn is its only
/// sender: a request whose header does not come from the item AnswersIn is refused with an error status and logged, and nothing is
/// answered. For an Answer it:
///   - reads the IRIS user from the Session row of the request's SessionRef (a message carries a SessionRef and never a user name,
///     AD-4); a SessionRef with no Session row is not_found;
///   - refuses an approve of an email request to anyone but the owner's own address unless the IRIS user holds the role OcuTalonAdmin (Fix.Kind.Email MayApprove, DW-1262): the
///     result is not_allowed, Approval.Answer is not called and the request stays as it was. A reject is never refused by this rule, and any other request is not asked;
///   - calls Approval.Answer(Ref, Action, Channel, IrisUser, SessionRef) in this production job, so that the answer, its Approval
///     audit entry and its live-event fan-out run with the production's privileges: the checked cross-owner reads that fan an
///     instance request out to its watchers fail in a web request and succeed here (DW-68). The RequiredRole rule stays with Answer;
///   - answers an AnswerResult with Answer's result and, for already_answered, the winner;
///   - when Answer returns done, and only then, sends PrecedentOps one RecordPrecedent {ApprovalRef, Action, Channel, SessionRef}, asynchronously and with
///     no answer wanted (AD-21; Story 41.5). PrecedentOps alone decides whether the answer becomes a precedent. A failed send is one warning and the
///     AnswerResult is unchanged.
/// An exception is an error status: the caller never gets a partial result.
Class OcuTalon.Core.AnswerOps Extends Ens.BusinessOperation
{

/// The class of the approval API. A test subclass names a double.
Parameter APPROVALAPI = "OcuTalon.Bridge.Approval";

/// The only item that may send to this operation.
Parameter SENDER = "AnswersIn";

/// The item that records a done answer as a precedent.
Parameter PRECEDENTITEM = "PrecedentOps";

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
	If request.Action = "approve" {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.Ref)
		If $IsObject(row) && '##class(OcuTalon.Fix.Kind.Email).MayApprove(row, session.IrisUser) {
			Set response.Result = "not_allowed"
			Quit $$$OK
		}
	}
	Set result = $ClassMethod(..#APPROVALAPI, "Answer", request.Ref, request.Action, request.Channel, session.IrisUser, request.SessionRef, .winner)
	Set response.Result = result
	If result = "done" Do ..Record(request)
	If $IsObject($Get(winner)) {
		Set response.WinnerAction = winner.%Get("action")
		Set response.WinnerChannel = winner.%Get("channel")
		Set response.WinnerAt = winner.%Get("at")
	}
	Quit $$$OK
}

/// Sends PrecedentOps the RecordPrecedent of a done answer. A failed send, and an error thrown, are one warning and nothing else.
Method Record(request As OcuTalon.Core.Msg.Answer) [ Private ]
{
	Try {
		Set message = ##class(OcuTalon.Core.Msg.RecordPrecedent).%New()
		Set message.ApprovalRef = request.Ref
		Set message.Action = request.Action
		Set message.Channel = request.Channel
		Set message.SessionRef = request.SessionRef
		Set sc = ..SendPrecedent(message)
		If $$$ISERR(sc) $$$LOGWARNING("AnswerOps could not send the precedent of answer " _ request.Ref _ ": " _ $SYSTEM.Status.GetErrorText(sc))
	} Catch exception {
		$$$LOGWARNING("AnswerOps could not send the precedent of answer " _ request.Ref _ ": " _ exception.DisplayString())
	}
}

/// Sends the message to PrecedentOps, asynchronously, with no answer wanted (a seam for the tests).
Method SendPrecedent(message As OcuTalon.Core.Msg.RecordPrecedent) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#PRECEDENTITEM, message)
}

}
