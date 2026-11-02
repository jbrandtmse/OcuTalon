/// A lab result as the chart accepts it (Story 9.9): the result value is a number.
Class OcuTalon.Test.Eval.Feed.ChartResult Extends OcuTalon.Test.Eval.Feed.TypedRecord
{

Property ResultId As %String;

Property PatientRef As %String;

Property TestCode As %String;

Property ResultValue As %Numeric;

Property Units As %String;

/// The record of the request, not validated.
ClassMethod From(request As Ens.Request) As OcuTalon.Test.Eval.Feed.ChartResult
{
	Quit ##class(OcuTalon.Test.Eval.Feed.TypedRecord).Copy(..NewPinned(), request)
}

}
