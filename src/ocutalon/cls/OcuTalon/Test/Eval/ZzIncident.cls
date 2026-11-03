/// A test double of IncidentManager for the evaluation incident (Test.Eval.Incident; test only). A shadow instance cannot SendRequestAsync, so this class, which
/// extends the probe of the live path, replaces the two sends of the evaluation branch and keeps the probe's recording of every send the branch must never make
/// (Sent, DryRuns, Raised, Executed, Started, Alarms, Cancelled).
///   - SendDiagnose records the request to Decide in Asked as {kind, provenance, itemId, ownerRef, traceRef, threadSessionId, summary, input}, and answers OK,
///     or an error when FailDiagnose is set.
///   - SendEval records the ItemDecision to EvalSink in Delivered as {itemId, sourceItemId, ownerRef, channel, summary, decisionRef, outcome, fallback,
///     fallbackReason}, and answers OK, or an error when FailEval is set.
///   - CaseRequest, CaseAnswer and CaseRefuse are OnRequest, OnResponse and OnError with the diagnose key, as the framework calls them for an IncidentCase:
///     CaseRefuse is OnError under an error response header and then, when OnError answers OK, OnResponse with no answer under the same header, which is
///     what Ens.BusinessProcess does after an error that OnError handled.
Class OcuTalon.Test.Eval.ZzIncident Extends OcuTalon.Test.Watch.IncidentProbe
{

/// The requests that SendDiagnose recorded, in order.
Property Asked As %DynamicArray [ Transient ];

/// The ItemDecisions that SendEval recorded, in order.
Property Delivered As %DynamicArray [ Transient ];

/// 1 to make SendDiagnose answer an error.
Property FailDiagnose As %Boolean [ InitialExpression = 0, Transient ];

/// 1 to make SendEval answer an error.
Property FailEval As %Boolean [ InitialExpression = 0, Transient ];

Method SendDiagnose(request As OcuTalon.Bridge.Msg.Request) As %Status [ Private ]
{
	If '$IsObject(..Asked) Set ..Asked = []
	Do ..Asked.%Push({"kind": (request.Kind), "provenance": (request.Provenance), "itemId": (request.ItemId), "ownerRef": (request.OwnerRef), "traceRef": (request.TraceRef), "threadSessionId": (request.ThreadSessionId), "summary": (request.Summary), "input": (request.Input)})
	If ..FailDiagnose Quit $SYSTEM.Status.Error(5001, "The send to Decide is refused")
	Quit $$$OK
}

Method SendEval(decision As OcuTalon.Msg.ItemDecision) As %Status [ Private ]
{
	If '$IsObject(..Delivered) Set ..Delivered = []
	Do ..Delivered.%Push({"itemId": (decision.ItemId), "sourceItemId": (decision.SourceItemId), "ownerRef": (decision.OwnerRef), "channel": (decision.Channel), "summary": (decision.Summary), "decisionRef": (decision.DecisionRef), "outcome": (decision.Outcome), "fallback": (+decision.Fallback), "fallbackReason": (decision.FallbackReason)})
	If ..FailEval Quit $SYSTEM.Status.Error(5001, "The send to EvalSink is refused")
	Quit $$$OK
}

/// The request handler, as the framework calls it when EvalIn sends the IncidentCase: the status, and the response in response.
Method CaseRequest(case As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit ..OnRequest(case, .response)
}

/// The answer handler of the diagnose request of the case, as the framework calls it when Decide answers.
Method CaseAnswer(case As %Library.Persistent, response As %RegisteredObject) As %Status
{
	Quit ..OnResponse(case, , "", response, ..#DIAGNOSEKEY)
}

/// The error handler of the diagnose request of the case, as the framework calls it when Decide refuses the request: OnError, then, when it answers OK,
/// OnResponse with no answer, both under an error response header of the error.
Method CaseRefuse(case As %Library.Persistent, error As %Status) As %Status
{
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.IsError = 1
	Set header.ErrorStatus = error
	Set ..%CurrentResponseHeader = header
	Set sc = ..OnError(case, , "", error, ..#DIAGNOSEKEY)
	If $$$ISOK(sc) Set sc = ..OnResponse(case, , "", "", ..#DIAGNOSEKEY)
	Set ..%CurrentResponseHeader = ""
	Quit sc
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
