/// A stand-in for OcuTalon.Bridge.Msg.Request (Story 1.3), for the test of Decide.Conclude's lost save race: it has the fields that
/// Conclude reads, and the first read of Summary saves Competitor, the Decision row of another call for the same item and kind.
/// Conclude reads Summary only after its check for an existing row and before its own save, so the other call's row appears in
/// that window and the unique index on (ItemId, Kind) refuses Conclude's row. Raced is 1 once Competitor was saved, and
/// RaceStatus is the status of that save.
Class OcuTalon.Test.Bridge.ProbeRaceRequest Extends %RegisteredObject
{

Property Kind As %String;

Property Provenance As %String;

Property ItemId As %String;

Property OwnerRef As %String;

Property Summary As %String;

/// The unsaved Decision row of the other call.
Property Competitor As OcuTalon.Bridge.Data.Decision;

Property Raced As %Boolean [ InitialExpression = 0 ];

Property RaceStatus As %Status;

Method SummaryGet() As %String [ ServerOnly = 1 ]
{
	If '..Raced && $IsObject(..Competitor) {
		Set ..Raced = 1
		Set ..RaceStatus = ..Competitor.%Save()
	}
	Quit i%Summary
}

}
