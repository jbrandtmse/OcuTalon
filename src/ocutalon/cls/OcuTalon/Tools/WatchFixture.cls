/// The methods behind OcuTalon.Tools.Watch (AD-7). The fixture of Story 1.1: every method answers {"items":[]} and
/// touches nothing. A tool method runs inside AI Hub's callback, so it makes no read, no write, no %AI call and no Python
/// call (AD-6). Story 5.4 replaces this class in place with the real readers.
Class OcuTalon.Tools.WatchFixture Extends %AI.Tool
{

/// The failed messages of a production: none in the fixture.
ClassMethod ReadFailedMessages(production As %String = "") As %String
{
	Quit "{""items"":[]}"
}

/// The event log of a production: nothing in the fixture.
ClassMethod ReadEventLog(production As %String = "") As %String
{
	Quit "{""items"":[]}"
}

/// The settings of the items of a production: none in the fixture.
ClassMethod ReadItemSettings(production As %String = "") As %String
{
	Quit "{""items"":[]}"
}

}
