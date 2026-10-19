/// The ownership API (AD-14, AD-20): how Web and Core read what a session owns, including the cost of its turns and
/// runs. Lane B. Epic 0 fixes the signatures with stub bodies; Lane B implements them in Stories 2.2 and 2.6.
Class OcuTalon.Data.Ownership
{

/// The cost of one turn, as an object. Not implemented yet: it answers an empty object. Story 2.6.
ClassMethod TurnCost(turnRef As %String) As %DynamicObject
{
	Quit {}
}

/// The cost of the session's runs since a UTC time, as an object. Not implemented yet: it answers an empty object.
/// Story 2.2.
ClassMethod RunCost(sessionRef As %String, since As %String) As %DynamicObject
{
	Quit {}
}

}
