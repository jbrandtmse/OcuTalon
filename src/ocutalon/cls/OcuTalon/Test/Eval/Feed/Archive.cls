/// A test feed item that fails with an ObjectScript error of its own (Story 9.9): it reads archiveSlot, a local variable that nothing sets, so every
/// message ends in an <UNDEFINED> error that Ens traps. No field of the message and no setting of the item is involved.
Class OcuTalon.Test.Eval.Feed.Archive Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
	Set total = archiveSlot + 1
	Quit $$$OK
}

}
