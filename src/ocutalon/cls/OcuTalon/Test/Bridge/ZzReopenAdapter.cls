/// The runner's adapter that cannot open a saved AI session other than the one named in the process-private global ^||ZzReopenOnly, for
/// Test.Bridge.Compaction: the fork of a compaction is saved and then has to be opened again, and this adapter refuses that reopen, so that
/// the fallback after a failed switch is tested. With the global unset it differs from the adapter in nothing.
Class OcuTalon.Test.Bridge.ZzReopenAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

Method OpenSession(id As %String, Output session As %AI.Agent.Session) As %Status
{
	If $Data(^||ZzReopenOnly) && (id '= ^||ZzReopenOnly) {
		Set session = ""
		Quit $$$ERROR($$$GeneralError, "ZzReopenAdapter: the AI session '"_id_"' cannot be opened")
	}
	Quit ##super(id, .session)
}

}
