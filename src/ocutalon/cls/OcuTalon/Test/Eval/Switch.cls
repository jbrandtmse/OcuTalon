/// Tests of the evaluation switch (Story 9.1; AD-16, AD-22; CON-3). READ ONLY: they change no setting and send nothing. They read the
/// definition of OcuTalon.Production and the running production, so TestStartRefused needs the running production of a throwaway or
/// CI stack (Rule 21) and fails with the reason where there is none.
///   - TestDefinition: EvalIn is OcuTalon.Eval.In with pool 0 and Enabled 0, no item is EnsLib.Testing.Service, and the production's
///     testing switch is off;
///   - TestRow: the System Default Setting row of EvalIn's Enabled is what the Production install step writes from OCUTALON_EVAL
///     (EvalEnabled): 1 only for the text "1";
///   - TestStartRefused: without OCUTALON_EVAL=1 Start returns the director's error, which says disabled, with no run Ref, no row and
///     nothing sent; with OCUTALON_EVAL=1 the director creates EvalIn, and this class calls no Start.
Class OcuTalon.Test.Eval.Switch Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The item under test.
Parameter ITEM = "EvalIn";

/// OcuTalon.Production's definition: EvalIn is disabled with no job, no item is the testing service, and testing is off.
Method TestDefinition()
{
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	Do $$$AssertEquals(production.TestingEnabled, 0, "testing is not enabled")
	Set found = 0, testing = ""
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If item.ClassName = "EnsLib.Testing.Service" Set testing = testing_" "_item.Name
		If item.Name = ..#ITEM {
			Set found = found + 1
			Do $$$AssertEquals(item.ClassName, "OcuTalon.Eval.In", "EvalIn is an OcuTalon.Eval.In")
			Do $$$AssertEquals(+item.Enabled, 0, "EvalIn is disabled in the definition")
			Do $$$AssertEquals(+item.PoolSize, 0, "EvalIn has no job of its own (adapterless)")
		}
	}
	Do $$$AssertEquals(found, 1, "the production holds EvalIn once")
	Do $$$AssertEquals(testing, "", "no item is EnsLib.Testing.Service")
}

/// The row of EvalIn's Enabled setting is 1 exactly when OCUTALON_EVAL is the text 1, and 0 otherwise.
Method TestRow()
{
	Set id = ..#PRODUCTION_"||"_..#ITEM_"||*||Enabled"
	Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "the Production install step wrote the EvalIn row")
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit
	Set expected = ##class(OcuTalon.Install.Step.Production).EvalEnabled($SYSTEM.Util.GetEnviron("OCUTALON_EVAL"))
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, expected, "the row is "_expected_", as OCUTALON_EVAL says")
}

/// Without OCUTALON_EVAL=1, Start is refused: the director's error says disabled, there is no run Ref and no row, and nothing is sent.
/// With OCUTALON_EVAL=1 the director creates EvalIn.
Method TestStartRefused()
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name) && ($Get(name) = ..#PRODUCTION)
	Do $$$AssertTrue(running, ..#PRODUCTION_" runs: this test runs in throwaways and CI only (Rule 21)")
	If 'running Quit
	If ##class(OcuTalon.Install.Step.Production).EvalEnabled($SYSTEM.Util.GetEnviron("OCUTALON_EVAL")) {
		Do $$$AssertStatusOK(##class(Ens.Director).CreateBusinessService(..#ITEM, .service), "OCUTALON_EVAL is 1: the director creates EvalIn")
		Quit
	}
	Set rows = ..Rows()
	Set headers = ..Headers()
	Set sc = ##class(OcuTalon.Eval.In).Start(, , .runRef, .sent, .skipped)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "Start is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "disabled", "the error says disabled: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(runRef, "", "there is no run Ref")
	Do $$$AssertEquals(sent, 0, "nothing was sent")
	Do $$$AssertEquals(skipped.%Size(), 0, "no case is listed")
	Do $$$AssertEquals(..Rows(), rows, "no case row was made")
	Do $$$AssertEquals(..Headers(), headers, "no message left EvalIn")
}

/// The number of case rows.
ClassMethod Rows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Eval_Data.CaseResult")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of message headers that EvalIn sent.
ClassMethod Headers() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ?", ..#ITEM)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
