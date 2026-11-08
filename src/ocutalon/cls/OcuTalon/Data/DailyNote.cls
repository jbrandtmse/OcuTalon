/// A person's daily note, built by code when it is read, with no model call (FR-71; Epic 41). Lane B. Story 41.2 adds the class with Build as a stub
/// that answers an empty note; Story 41.3 builds the note itself.
Class OcuTalon.Data.DailyNote
{

/// The note of the session for one local day of the instance zone, as one text with its lines separated by line feeds; "" when there is none.
/// day is a local date, YYYY-MM-DD.
ClassMethod Build(sessionRef As %String, day As %String) As %String
{
	Quit ""
}

}
