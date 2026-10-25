/// A subclass of OcuTalon.Core.StatusMonitor for the tests that keeps its two private seams as the product has them and makes them
/// callable (Story 2.10; AD-22): StreamName answers Stream() and ReadingsOf answers Readings(), so that a test can check what the
/// production job reads and which stream it publishes on without running the job. It has no Test methods and the product never
/// refers to it.
Class OcuTalon.Test.Core.StatusMonitorSeamProbe Extends OcuTalon.Core.StatusMonitor
{

/// The stream that the job publishes on: Stream().
Method StreamName() As %String
{
	Quit ..Stream()
}

/// The readings that the job takes: Readings().
Method ReadingsOf(Output keys As %DynamicObject, Output budget As %DynamicObject)
{
	Do ..Readings(.keys, .budget)
}

}
