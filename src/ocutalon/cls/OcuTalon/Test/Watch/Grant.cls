/// Tests of the service role's Read on the OCUORDERS data database (Story 5.1; veto U-79; AD-23, AD-24): the grant that lets Watch.Reader find the Orders
/// production for the service user. These are Lane A's own pins of what the Demo step (Epic 4's file) adds. TestHelper is pure; the others RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case.
///   - TestHelper: Demo.WithOrdersData adds %DB_OCUORDERS_DATA:R, adds it once however often it runs, sets a listed entry to Read, removes it, leaves a
///     list without it as it was, keeps every other entry and its place, and never adds or removes the code database;
///   - TestRoleHoldsTheDataDatabaseOnly: with demo mode on, OcuTalonServiceRole holds %DB_OCUORDERS_DATA with Read and no other OCUORDERS resource, and
///     no write on it;
///   - TestReaderNeedsTheGrant: Watch.Reader finds Orders with the grant and not without it (the test takes the grant away and puts it back), and finds it
///     again once the grant is back.
/// The keep path is pinned by the appended block of docker/tests/test-install-start.sh, which ends in the keep state and checks that the run took the keep
/// path and that the role holds no OCUORDERS resource. The off path shares that role edit (Demo.System calls ServiceRole(0) before it branches).
Class OcuTalon.Test.Watch.Grant Extends OcuTalon.Test.Watch.Case
{

Parameter STEP = "OcuTalon.Install.Step.Demo";

Method TestHelper()
{
	Set data = ..#ORDERSDATA
	Set code = ..#ORDERSCODE
	Set add = $ClassMethod(..#STEP, "WithOrdersData", "", 1)
	Do $$$AssertEquals(add, data_":R", "an empty list gets "_data_":R")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", add, 1), add, "adding it again changes nothing (idempotent)")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U,"_data_":W", 1), "%Ens_Code:U,"_data_":R", "a listed entry keeps its place and is set to Read")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U", 1), "%Ens_Code:U,"_data_":R", "it is added after the other entries")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U,"_data_":R,%DB_X:R", 0), "%Ens_Code:U,%DB_X:R", "removing it keeps the other entries")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", data_":R", 0), "", "removing the only entry leaves an empty list")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U", 0), "%Ens_Code:U", "removing it when it is absent changes nothing")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "", 0), "", "also for an empty list")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U,,"_data_":R,", 1), "%Ens_Code:U,"_data_":R", "an empty entry is dropped")
	Set kept = $ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U,"_code_":R", 1)
	Do $$$AssertEquals(kept, "%Ens_Code:U,"_code_":R,"_data_":R", "the code database is never added: a code entry that is there stays as it was")
	Do $$$AssertEquals($ClassMethod(..#STEP, "WithOrdersData", kept, 0), "%Ens_Code:U,"_code_":R", "and removing the data database leaves the code entry")
	Do $$$AssertTrue($ClassMethod(..#STEP, "WithOrdersData", "%Ens_Code:U", 1) '[ code, "the code database is not in an added list")
}

Method TestRoleHoldsTheDataDatabaseOnly()
{
	If '..Ready() Quit
	Set resources = ..RoleResources()
	Do $$$AssertTrue(resources '= "<no role>", "the service role exists")
	Set data = 0
	Set orders = ""
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If entry [ "OCUORDERS" {
			Set orders = orders _ $ListBuild(entry)
			If $Piece(entry, ":", 1) = ..#ORDERSDATA Set data = data + 1
		}
	}
	Do $$$AssertEquals($ListToString(orders), ..#ORDERSDATA_":R", "the service role holds Read on "_..#ORDERSDATA_" and no other OCUORDERS resource: "_resources)
	Do $$$AssertEquals(data, 1, "the data database is listed once")
	Do $$$AssertNotTrue(resources [ ..#ORDERSCODE, "the code database is not granted")
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	Do $$$AssertStatusOK(sc, "the service user is read from Decide's setting")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, ..#ORDERSDATA, "R"), 1, "the service user can read the OCUORDERS data database")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, ..#ORDERSDATA, "W"), 0, "but not write it")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, ..#ORDERSCODE, "R"), 0, "and cannot read the OCUORDERS code database")
}

Method TestReaderNeedsTheGrant()
{
	If '..Ready() Quit
	Set reader = "OcuTalon.Watch.Reader"
	Do $$$AssertEquals($ClassMethod(reader, "Find", "Orders").%Size(), 1, "with the grant, Orders is found")
	Do ..RevokeRole(..#ORDERSDATA)
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, ..#ORDERSDATA, "R"), 0, "control: without the grant the service user cannot read the OCUORDERS data database")
	Do $$$AssertEquals($ClassMethod(reader, "Find", "Orders").%Size(), 0, "and Orders is not found")
	Do $$$AssertEquals($ClassMethod(reader, "Productions").%Size(), 0, "the list holds nothing")
	Do $$$AssertEquals($ClassMethod(reader, "Admits", ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION), 0, "and Orders is not admitted")
	Do ..GrantRole(..#ORDERSDATA)
	Do $$$AssertEquals($ClassMethod(reader, "Find", "Orders").%Size(), 1, "with the grant put back, Orders is found again")
}

}
