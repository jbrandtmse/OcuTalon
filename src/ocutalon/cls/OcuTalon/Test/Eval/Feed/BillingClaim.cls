/// A claim as billing accepts it (Story 9.9): the member is required and the amount is a number.
Class OcuTalon.Test.Eval.Feed.BillingClaim Extends OcuTalon.Test.Eval.Feed.TypedRecord
{

Property ClaimId As %String;

Property MemberId As %String [ Required ];

Property ServiceDate As %String;

Property Amount As %Numeric;

Property PayerCode As %String;

/// The record of the request, not validated.
ClassMethod From(request As Ens.Request) As OcuTalon.Test.Eval.Feed.BillingClaim
{
	Quit ##class(OcuTalon.Test.Eval.Feed.TypedRecord).Copy(..NewPinned(), request)
}

}
