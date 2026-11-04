/// A test feed item that validates the message it takes (Story 9.9): it builds the typed record that the message's RECORDCLASS names from the message and
/// returns what %ValidateObject returns, so a datatype, range or required-property error is IRIS's own. It has no adapter and sends nothing on.
Class OcuTalon.Test.Eval.Feed.Intake Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
	Quit $ClassMethod($Parameter(pRequest, "RECORDCLASS"), "From", pRequest).%ValidateObject()
}

}
