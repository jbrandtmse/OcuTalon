/// The base of the test classes that change the process zone (Story 1.10; DW-32). It saves the zone of the process before every test and puts it
/// back after every test, so that a test can set any zone, "no zone" included, and no test leaves one for the next. A class that extends it keeps
/// no copy of its own, and a class that overrides a hook calls ##super(testname).
/// Since Story 17.4 the instance zone has a run-time source, the InstanceZone row of Decide, which Bridge.Time.Apply follows. So that every class
/// of the base stays hermetic against a stray row, OnBeforeOneTest remembers the row of the active production and deletes it, and clears the
/// process-private state of Apply (^||OcuTalon.Bridge.Time); OnAfterOneTest puts the row back as it was, clears the state again, and then puts
/// the process zone back.
///   - CurrentZone: the zone of the process, -1 for none;
///   - PutZone(saved): puts back a zone that CurrentZone gave, -1 as "no zone" (an empty zone), which the process takes as none;
///   - ForgetZoneRow and RestoreZoneRow: the row's state, for a class that does not extend the base and sets the instance zone itself.
/// It is abstract and holds no Test method, so ci/iris.sh runs no class of it.
Class OcuTalon.Test.Bridge.ZoneCase Extends %UnitTest.TestCase [ Abstract ]
{

/// The zone of the process before the test: -1 for none.
Property SavedZone As %String;

/// The InstanceZone row of Decide before the test (ForgetZoneRow).
Property ZoneRow As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SavedZone = ..CurrentZone()
	Set ..ZoneRow = ..ForgetZoneRow()
	Kill ^||OcuTalon.Bridge.Time
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..RestoreZoneRow(..ZoneRow)
	Kill ^||OcuTalon.Bridge.Time
	Do ..PutZone(..SavedZone)
	Quit $$$OK
}

/// The id of the InstanceZone row of Decide in the active production, or "" when no production is active.
ClassMethod ZoneRowId() As %String
{
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Quit $Select(production = "": "", 1: production_"||Decide||*||InstanceZone")
}

/// Remembers the InstanceZone row of Decide, as $ListBuild(id, existed, value, description), and deletes it, so that the instance zone is the process zone.
ClassMethod ForgetZoneRow() As %List
{
	Set id = ..ZoneRowId()
	If (id = "") || '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit $ListBuild(id, 0, "", "")
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Set state = $ListBuild(id, 1, row.SettingValue, row.Description)
	Set row = ""
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Quit state
}

/// Puts the InstanceZone row back as ForgetZoneRow found it: written again when it existed, otherwise deleted.
ClassMethod RestoreZoneRow(state As %List)
{
	If $Get(state) = "" Quit
	Set id = $List(state, 1)
	If id = "" Quit
	If $List(state, 2) {
		Do ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault($Piece(id, "||", 1), "Decide", "InstanceZone", $List(state, 3), $List(state, 4))
	} Else {
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	}
}

/// The zone of the process: its name, or -1 when the process has none.
ClassMethod CurrentZone() As %String
{
	Quit $SYSTEM.Process.TimeZone()
}

/// Puts the zone of the process back as CurrentZone gave it: -1 becomes "", which is no zone.
ClassMethod PutZone(saved As %String)
{
	Do $SYSTEM.Process.TimeZone($Select(saved = -1: "", 1: saved))
}

}
