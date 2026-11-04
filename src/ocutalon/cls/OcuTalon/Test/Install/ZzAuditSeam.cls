/// A fixture of the Audit step's tests (Story 3.7, DW-10), never part of a production: a stand-in for the installer's read of instance-wide
/// auditing and for the status mark, each of which fails here, so that the step's "unknown" branch and its mark-write warning can be run. The step
/// reaches it through the test subclasses ZzAuditUnreadable and ZzAuditUnmarked. It changes no setting and stores nothing.
Class OcuTalon.Test.Install.ZzAuditSeam
{

/// The text of the error that InstanceAuditing returns.
Parameter READERROR = "ZzAuditSeam cannot read instance-wide auditing";

/// The text of the error that Record returns.
Parameter WRITEERROR = "ZzAuditSeam cannot write the mark";

/// A read that fails: an error status and enabled empty.
ClassMethod InstanceAuditing(Output enabled As %Boolean) As %Status
{
	Set enabled = ""
	Quit $SYSTEM.Status.Error(5001, ..#READERROR)
}

/// A mark that has no value, so that the step always has a value to record.
ClassMethod Get(mark As %String) As %String
{
	Quit ""
}

/// A record that fails: an error status.
ClassMethod Record(mark As %String, value As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, ..#WRITEERROR)
}

}
