/// A test feed item that sends each message to an HTTP partner (Story 9.9): it POSTs the message as JSON to the adapter's URL and returns the adapter's
/// status. The adapter's own rules apply: a refused connection, a host that does not resolve and an HTTP 503 are retried until the item's
/// FailureTimeout, any other status that is not 2xx fails at once.
Class OcuTalon.Test.Eval.Feed.PartnerOut Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
	Set sc = pRequest.%JSONExportToString(.body)
	If $$$ISERR(sc) Quit sc
	Quit ..Adapter.PostURL(..Adapter.URL, .httpResponse, "", body)
}

}
