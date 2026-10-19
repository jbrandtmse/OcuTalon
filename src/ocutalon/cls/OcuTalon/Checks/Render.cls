/// Renders the results of the background checks for a reply (AD-28). Epic 0 fixes the signature with a stub body; Lane A
/// implements it in Story 5.7.
Class OcuTalon.Checks.Render
{

/// The catalog key that renders the check results, with the rows to show in rows. Not implemented yet: it answers an
/// empty key and no rows.
ClassMethod Render(results As %DynamicArray, Output rows As %DynamicArray) As %String
{
	Set rows = []
	Quit ""
}

}
