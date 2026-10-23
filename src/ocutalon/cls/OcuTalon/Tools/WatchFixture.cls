/// The methods behind OcuTalon.Tools.Watch (AD-7). The fixture of Story 1.1: every method answers the dynamic object {"items":[]} and
/// touches nothing. It extends OcuTalon.Tools.Result and returns only through Return, so that the model reads the answer as a JSON object
/// and the results of a model step are bounded (AD-10). A tool method runs inside AI Hub's callback, so it makes no read, no write, no
/// %AI call and no Python call (AD-6). Story 5.4 replaces this class in place with the real readers.
Class OcuTalon.Tools.WatchFixture Extends OcuTalon.Tools.Result
{

/// The failed messages of a production: none in the fixture.
ClassMethod ReadFailedMessages(production As %String = "") As %DynamicObject
{
	Quit ..Return({"items": []})
}

/// The event log of a production: nothing in the fixture.
ClassMethod ReadEventLog(production As %String = "") As %DynamicObject
{
	Quit ..Return({"items": []})
}

/// The settings of the items of a production: none in the fixture.
ClassMethod ReadItemSettings(production As %String = "") As %DynamicObject
{
	Quit ..Return({"items": []})
}

}
