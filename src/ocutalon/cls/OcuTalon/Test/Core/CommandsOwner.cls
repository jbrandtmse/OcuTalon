/// The test owner of OcuTalon.Test.Core.CommandsRouting: it stands in for the owner item that CommandsIn sends a command to,
/// through OcuTalon.Test.Core.CommandsInProbe. It has no Test methods and the product never refers to it. OnMessage records
/// each call under ^OcuTalonTest("CommandsRouting", RunNumber, n), with n counted in ^OcuTalonTest("CommandsRouting",
/// RunNumber): target, class (the request's class), origin, key, sessionRef and, for an IncidentCommand, verb and incidentRef.
/// It answers by AnswerMode:
///   - ok: a CommandResult with Ok 1, Outcome "test" and Message the target;
///   - stub-op: the error status of an Epic 0 operation stub (code 5003);
///   - stub-bp: the status of an Epic 0 process stub, <Ens>ErrBPTerminated carrying 5003;
///   - error: another error status;
///   - none: OK with no response;
///   - wrong: OK with an Ens.StringResponse, which is not a CommandResult;
///   - throw: a thrown error.
Class OcuTalon.Test.Core.CommandsOwner Extends Ens.BusinessOperation
{

/// The subscript of the run under ^OcuTalonTest("CommandsRouting").
Property RunNumber As %String;

/// How OnMessage answers.
Property AnswerMode As %String [ InitialExpression = "ok" ];

/// The owner item that the command was sent to.
Property SentTo As %String;

Method OnMessage(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	Set n = $Increment(^OcuTalonTest("CommandsRouting", ..RunNumber))
	Set call = $Name(^OcuTalonTest("CommandsRouting", ..RunNumber, n))
	Set @call@("target") = ..SentTo
	Set @call@("class") = $ClassName(request)
	Set @call@("origin") = request.Origin
	Set @call@("key") = request.IdempotencyKey
	Set @call@("sessionRef") = request.SessionRef
	If request.%Extends("OcuTalon.Msg.IncidentCommand") {
		Set @call@("verb") = request.Verb
		Set @call@("incidentRef") = request.IncidentRef
	}
	If ..AnswerMode = "stub-op" Quit $$$ERROR($$$NotImplemented)
	If ..AnswerMode = "stub-bp" Quit $$$ERROR($$$EnsErrBPTerminated, ..SentTo, 1, $SYSTEM.Status.GetErrorText($$$ERROR($$$NotImplemented)))
	If ..AnswerMode = "error" Quit $SYSTEM.Status.Error(5001, "zz owner failed")
	If ..AnswerMode = "wrong" {
		Set response = ##class(Ens.StringResponse).%New("zz")
		Quit $$$OK
	}
	If ..AnswerMode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz owner threw"))
	If ..AnswerMode = "ok" {
		Set response = ##class(OcuTalon.Msg.CommandResult).%New()
		Set response.Ok = 1
		Set response.Outcome = "test"
		Set response.Message = ..SentTo
	}
	Quit $$$OK
}

}
