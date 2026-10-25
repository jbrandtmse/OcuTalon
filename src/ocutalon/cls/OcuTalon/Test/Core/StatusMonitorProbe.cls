/// A subclass of OcuTalon.Core.StatusMonitor for the tests, which overrides its two private seams so that the unit tests run on a
/// slot with no production (Story 2.10; AD-22): Readings answers the keys and the budget that the test sets, and Stream answers
/// the private stream that the test publishes on, so that nothing is read from the bridge and nothing is published on the
/// instance stream. ThrowReading makes Readings throw, as a bridge that fails would. It has no Test methods and the product never
/// refers to it.
Class OcuTalon.Test.Core.StatusMonitorProbe Extends OcuTalon.Core.StatusMonitor
{

/// The keys reading of the next run: {"TriageAgent": 0|1, "DiagnosisAgent": 0|1, "ChatAgent": 0|1}.
Property KeysReading As %DynamicObject [ Transient ];

/// The budget reading of the next run, as Budget.State() answers it.
Property BudgetReading As %DynamicObject [ Transient ];

/// The stream that the events are published on.
Property StreamRef As %String [ Transient ];

/// 1 when Readings throws.
Property ThrowReading As %Boolean [ InitialExpression = 0, Transient ];

Method Readings(Output keys As %DynamicObject, Output budget As %DynamicObject) [ Private ]
{
	If ..ThrowReading Throw ##class(%Exception.General).%New("ZzStatusProbe", 5001, , "the probe's readings fail")
	Set keys = ..KeysReading
	Set budget = ..BudgetReading
}

Method Stream() As %String [ Private ]
{
	Quit ..StreamRef
}

}
