/// A SettingsOpsProbe whose role calls go to OcuTalon.Test.Core.RolesStub (the seam RolesClass), so that the roles commands run with no security object touched.
Class OcuTalon.Test.Core.SettingsRolesProbe Extends OcuTalon.Test.Core.SettingsOpsProbe
{

ClassMethod RolesClass() As %String [ Private ]
{
	Quit "OcuTalon.Test.Core.RolesStub"
}

}
