/// A subclass of OcuTalon.Core.StatusMonitor for the tests, which overrides its private seams so that the unit tests run on a
/// slot with no production (Story 2.10; AD-22): Readings answers the keys and the budget that the test sets, and Stream answers
/// the private stream that the test publishes on, so that nothing is read from the bridge and nothing is published on the
/// instance stream. ThrowReading makes Readings throw, as a bridge that fails would. AllowanceSessions (Story 16.9) answers the
/// list of sessions with an open allowance window that the test sets in HeldReading, and an error status when FailHeld is 1, so that
/// no run reads the real sessions; HeldReads counts its calls. SessionStream answers the stream that the test set for a session in
/// SessionStreams (a fixture session of its own), so that the allowance statuses go to streams that the production's own
/// StatusMonitor, where one runs, never publishes on. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Core.StatusMonitorProbe Extends OcuTalon.Core.StatusMonitor
{

/// The keys reading of the next run: {"TriageAgent": 0|1, "DiagnosisAgent": 0|1, "ChatAgent": 0|1}.
Property KeysReading As %DynamicObject [ Transient ];

/// The budget reading of the next run, as Budget.State() answers it.
Property BudgetReading As %DynamicObject [ Transient ];

/// The stream that the events are published on.
Property StreamRef As %String [ Transient ];

/// The sessions with an open allowance window that the next run reads: a list of Refs, empty for none.
Property HeldReading As %String [ Transient ];

/// 1 when AllowanceSessions answers an error status.
Property FailHeld As %Boolean [ InitialExpression = 0, Transient ];

/// How many times AllowanceSessions was called, which is how many reads of the held sessions the runs made (QA, Story 16.9).
Property HeldReads As %Integer [ InitialExpression = 0, Transient ];

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

Method AllowanceSessions(now As %String, Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Set ..HeldReads = ..HeldReads + 1
	If ..FailHeld {
		Set sc = $SYSTEM.Status.Error(5001, "zz the probe's allowance read fails")
		Quit ""
	}
	Quit ..HeldReading
}

/// The stream that the allowance status of each session is published on, by session Ref; a session with none uses its own.
Property SessionStreams As %String [ MultiDimensional, Transient ];

Method SessionStream(sessionRef As %String) As %String [ Private ]
{
	Quit $Get(..SessionStreams(sessionRef), sessionRef)
}

}
