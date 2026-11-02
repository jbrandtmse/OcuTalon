/// The test feed's stand-in partner (Story 9.9): an HTTP service that answers every request. A URL under UNAVAILABLE is answered with 503 Service
/// Unavailable, one under FAULT with 500 Internal Server Error, any other with 200 OK. It returns OK in every case, so that it logs no error of its own:
/// the failures of the feed are the callers'.
Class OcuTalon.Test.Eval.Feed.Partner Extends Ens.BusinessService
{

Parameter ADAPTER = "EnsLib.HTTP.InboundAdapter";

/// The URL prefix that is answered with 503.
Parameter UNAVAILABLE = "/payer/";

/// The URL prefix that is answered with 500.
Parameter FAULT = "/reference-lab/";

Property Adapter As EnsLib.HTTP.InboundAdapter;

Method OnProcessInput(pInput As %Library.AbstractStream, Output pOutput As %Library.AbstractStream) As %Status
{
	Set url = $Get(pInput.Attributes("URL"))
	Set pOutput = ##class(%Library.GlobalCharacterStream).%New()
	Do pOutput.Write("feed partner")
	If $Extract(url, 1, $Length(..#UNAVAILABLE)) = ..#UNAVAILABLE {
		Set pOutput.Attributes("ResponseCode") = "503 Service Unavailable"
	} ElseIf $Extract(url, 1, $Length(..#FAULT)) = ..#FAULT {
		Set pOutput.Attributes("ResponseCode") = "500 Internal Server Error"
	} Else {
		Set pOutput.Attributes("ResponseCode") = "200 OK"
	}
	Quit $$$OK
}

}
