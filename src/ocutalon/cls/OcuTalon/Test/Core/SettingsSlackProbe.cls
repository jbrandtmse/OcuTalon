/// A subclass of OcuTalon.Test.Core.SettingsOpsProbe for Test.Core.SettingsSlack (Story 27.3). With ^OcuTalonTest("SettingsSlackProbe", "race") set to
/// "team|member|sessionRef", the next audit write first links that member of that team to that session (what a second admin's link made after the first one's
/// checks would be) and clears the answer, so that a LinkSlackMember's save after its audit entry meets a taken member or session.
Class OcuTalon.Test.Core.SettingsSlackProbe Extends OcuTalon.Test.Core.SettingsOpsProbe
{

Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Set sc = ##super(data)
	Set race = $Get(^OcuTalonTest("SettingsSlackProbe", "race"))
	If race '= "" {
		Kill ^OcuTalonTest("SettingsSlackProbe", "race")
		Do ##class(OcuTalon.Data.SlackLink).Link($Piece(race, "|", 1), $Piece(race, "|", 2), $Piece(race, "|", 3), .raced)
	}
	Quit sc
}

}
