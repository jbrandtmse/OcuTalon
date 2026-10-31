/// A shipment as the ledger accepts it (Story 9.9): the time of shipping is a time stamp and the weight is a number that is not below 0.
Class OcuTalon.Test.Eval.Feed.LedgerEntry Extends OcuTalon.Test.Eval.Feed.TypedRecord
{

Property ShipmentId As %String;

Property OrderNumber As %String;

Property ShippedAt As %TimeStamp;

Property Weight As %Numeric(MINVAL = 0);

Property Carrier As %String;

/// The record of the request, not validated.
ClassMethod From(request As Ens.Request) As OcuTalon.Test.Eval.Feed.LedgerEntry
{
	Quit ##class(OcuTalon.Test.Eval.Feed.TypedRecord).Copy(..NewPinned(), request)
}

}
