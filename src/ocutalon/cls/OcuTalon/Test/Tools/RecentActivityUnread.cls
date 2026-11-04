/// A test double of OcuTalon.Tools.RecentActivity (Story 5.13): the same tool, except that the process-private global ^||RecentActivityUnread names a read that
/// fails with an error status. "incidents" fails the read of the incidents and "approvals" fails the read of an incident's approvals; any other value reads as the
/// tool does. Test.Tools.RecentActivity TestUnreadableRuns calls it and kills the global. Nothing else uses this class, and it is not a test case.
Class OcuTalon.Test.Tools.RecentActivityUnread Extends OcuTalon.Tools.RecentActivity
{

ClassMethod ReadIncidents(owner As %String, Output rows As %ListOfObjects, Output sc As %Status) [ Private ]
{
	If $Get(^||RecentActivityUnread) = "incidents" {
		Set rows = ##class(%ListOfObjects).%New()
		Set sc = $SYSTEM.Status.Error(5001, "The double fails the read of the incidents")
		Quit
	}
	Do ##super(owner, .rows, .sc)
}

ClassMethod ReadApprovals(incidentRef As %String, owner As %String, Output requests As %ListOfObjects, Output sc As %Status) [ Private ]
{
	If $Get(^||RecentActivityUnread) = "approvals" {
		Set requests = ##class(%ListOfObjects).%New()
		Set sc = $SYSTEM.Status.Error(5001, "The double fails the read of the approvals")
		Quit
	}
	Do ##super(incidentRef, owner, .requests, .sc)
}

}
