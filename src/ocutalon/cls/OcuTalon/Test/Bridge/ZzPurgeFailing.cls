/// Test double of OcuTalon.Bridge.Purge for Test.Bridge.Purge.TestPartsRunAlone: the delete of the Decision rows fails, every other part is the real one.
Class OcuTalon.Test.Bridge.ZzPurgeFailing Extends OcuTalon.Bridge.Purge
{

/// An error status for the Decision table, the real delete for any other table.
ClassMethod DeleteBefore(table As %String, cutoff As %String) As %Status
{
	If table [ "Decision" Quit $SYSTEM.Status.Error(5001, "ZzPurgeFailing: the delete of "_table_" fails")
	Quit ##super(table, cutoff)
}

}
