/// The Config Store API (AD-19). Epic 0 fixes the signature with a stub body; Lane A implements it in Story 1.1.
Class OcuTalon.Bridge.ConfigStore
{

/// Merges fields into the Config Store entry, leaving the entry's other fields as they are. Not implemented yet: it
/// returns an error that says so, so that no caller can mistake the stub for a merge that happened.
ClassMethod Merge(entry As %String, fields As %DynamicObject) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Bridge.ConfigStore.Merge is not implemented yet (Story 1.1)")
}

}
