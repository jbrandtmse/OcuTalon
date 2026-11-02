/// The test feed's source (Story 9.9): an adapterless service that sends each message of a Batch to the Batch's Target, each in a session of its own, with
/// the Batch's TraceRef as the SuperSession of every message, so that one case's headers are told apart from every other case's by that reference.
/// The sends are asynchronous: the item at Target fails or not in its own job.
Class OcuTalon.Test.Eval.Feed.Sender Extends Ens.BusinessService
{

/// Sessions are reset inside this method, after the host's start of input has cleared them.
Method OnProcessInput(pInput As OcuTalon.Test.Eval.Feed.Batch, Output pOutput As %RegisteredObject) As %Status
{
	Set sc = $$$OK
	For i = 1:1:pInput.Messages.Count() {
		Set ..%SessionId = ""
		Set ..%SuperSession = pInput.TraceRef
		Set sc = ..SendRequestAsync(pInput.Target, pInput.Messages.GetAt(i))
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

}
