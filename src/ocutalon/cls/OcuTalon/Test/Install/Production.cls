Include Ensemble

/// Tests of OcuTalon.Production and of the Production installer step (Story 0.6, matrix rows 1 and 3 to 5; Story 1.1; Story 1.2;
/// Story 1.3; Story 1.5; Story 1.12; Story 39.11). Nothing
/// here starts, stops or updates a production: the tests read the definition of OcuTalon.Production, call the stub handlers of
/// shadow instances, write the System Default Setting row of the EvalIn switch (restored as it was found), write the Enabled row
/// and the runtime flag of TelegramIn (both put back as found) and an Enabled row for the production and every item of
/// TelegramIn's class (deleted after the test), compile a shadow subclass of the step (deleted by its test), and compile a
/// fixture production of their own with System Default Setting rows of its own, both deleted afterwards.
/// The oracle is a copy of the ownership table, split by lane so that each lane edits only its own rows (AD-29, AD-33):
/// lane A's rows are XData Items below, lane B's are in OcuTalon.Test.Core.ProductionItems, and Items() returns both in
/// the order of the production. The counts the tests use come from the oracle.
///   - TestDefinition: the compiled XData holds exactly the items of the oracle, each between the markers of its lane,
///     with the four markers once each in order and no item outside a region;
///   - TestStubsAnswer: every item class that carries STUB answers "not implemented" (code 5003), with no response and no
///     new log row; the two rule classes carry STUB and hold a rule set with no rule. Decide (built in Story 1.3), the three
///     agent runners and AgentSteps (built in Story 1.5) and DigestStore (built in Story 1.12) carry no STUB, so the oracle marks them "stub": 0, and so do ApprovalHold and ApprovalStartIn (built in Story 3.4) and FailurePoller (built in Story 5.2: an inbound adapter service every 3 seconds, so its row has pool 1 and the setting CallInterval 3), IncidentManager (built in Story 5.5), Checks (built in Story 5.6), and FixExecutor (built in Story 7.3), and ReconcileIn (built in Story 15.2: an inbound adapter service every 5 seconds, so its row has pool 1 and the setting CallInterval 5). EvalIn and EvalSink are built in Story 9.1. From step 2 (Story 33.1), the three retry runners TriageAgentRetry, DiagnosisAgentRetry and ChatAgentRetry were disabled with an empty AgentClass setting, and Digest was disabled and carried STUB; Story 17.2 built the retry runners: they are enabled, with the AgentClass of their first runner (and the ReplyClass of Triage and Diagnosis), and no RetryItem is set anywhere at install, so a default install makes no second-model request; Story 17.6 built Digest: it is enabled and carries no STUB; From step 3 (Story 34.1), MemoryOps and DocumentOps are disabled and carry STUB; Stories 19.3 and 19.4 build them; MemoryOps is built (Story 19.3): enabled, with no STUB; DocumentOps is built (Story 19.4): enabled, with no STUB, and the Decide item gains the ToolClassification setting that classifies the documents search (AD-10; its class is written \u0025AI.RAG.KnowledgeBase in the XML, which JSON reads as the class name, because the rule ai-allowlist of test-class-rules.sh reads the XData of Production.cls as code);
///   - TestRunnerModels: UnresolvedRunners names exactly the enabled runners with no model in a fixture production (the
///     runners of OcuTalon.Production itself are checked by OcuTalon.Test.Agent.Models);
///   - TestSeedModels: Runners lists the runners of the fixture production, and SeedModels writes the Model row of the runner
///     whose agent class has a MODEL and no other, and never overwrites a row;
///   - TestSeedSpecificity: a row of the production that gives a runner with a MODEL its model, for the runner and the class of
///     its adapter, for every item of that class, for every item and class, or under the name Adapter:Model, keeps SeedModels
///     from writing a Model row for it, and SeedModels of a production whose definition cannot be opened is an error that
///     writes nothing (a test writes no row for any other production);
///   - TestSeedEfforts: SeedEfforts writes the Effort row of the runner whose agent class has an EFFORT and no other, and never
///     overwrites a row, an empty one included, and the agents of the product seed low (Triage), high (Diagnosis) and nothing (Chat);
///   - TestSeedAllowList: SeedAllowList writes one AgentAllowList row for every item, holding the distinct AgentClass values of the
///     runners in order, and writes nothing when a runner resolves a list from an item row, or when a row exists, an empty one
///     included; a production that cannot be opened is an error that writes nothing;
///   - TestStepHelpers: EvalEnabled is 1 only for "1", SetEval and WriteDefault write their rows, and NotRunning names the
///     production when it does not run;
///   - TestNotRunningFollowsTheRow: on a running OcuTalon.Production, NotRunning leaves out TelegramIn (pool 1, no job) when its
///     Enabled row is 0 or its runtime flag is off, and names it when the flag is on and its row is 1 or missing (skipped when the
///     production does not run or TelegramIn has a job);
///   - TestNotRunningFollowsABroaderRow: the Enabled row that applies to an item may be of any specificity, as Ens reads it: a row for
///     the production and every item of TelegramIn's class (written and deleted by the test) of 0 leaves TelegramIn out, and of 1
///     names it (the same skip conditions);
///   - TestNotRunningLeavesOutAnItemWithAJob: on a running OcuTalon.Production, NotRunning names none of the enabled items (flag on, pool,
///     no row of 0) that have an alive job that is not in error (reads only);
///   - TestNotRunningNamesTheProduction: a step class whose PRODUCTION is not the running one answers "<production> is not running"
///     (a shadow subclass of the step that the test compiles and deletes; it runs also where OcuTalon.Production runs, which
///     TestStepHelpers cannot check);
///   - TestAutoStart: AutoStart marks ^Ens.AutoStart for the caller "ipm" only, and leaves it as it was for any other caller
///     (^Ens.AutoStart is put back after the test);
///   - TestExampleInstalledNotStarted: the bridge example production is compiled and registered, and neither running nor the
///     autostart production.
/// The fixture production is OcuTalon.Test.Install.ZzProd<n>, n from ^OcuTalonTest("Production","n") (never reset);
/// OnBeforeAllTests and OnAfterAllTests delete every such class with its rows, and the EvalIn row is put back as it was found.
Class OcuTalon.Test.Install.Production Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The run's number.
Property Number As %Integer;

/// 1 when the EvalIn System Default Setting row existed before the tests, with its value and description.
Property RowFound As %Boolean;

Property RowValue As %String(MAXLEN = 2000);

Property RowDescription As %String(MAXLEN = 2000);

Property RowDeployable As %Boolean;

/// 1 when TestAutoStart saved ^Ens.AutoStart with its subnodes (in ^||OcuTalonTestAutoStart) and the last-production node of the
/// namespace (in ^||OcuTalonTestLastProduction); OnAfterOneTest puts both back exactly as they were, defined or not.
Property AutoStartSaved As %Boolean [ InitialExpression = 0 ];

/// The Enabled row of TelegramIn as found (RunnerFixture.SnapshotDefault), "" when TestNotRunningFollowsTheRow has saved none;
/// OnAfterOneTest puts it back.
Property TelegramRow As %List;

/// The runtime flag of TelegramIn as found, $Data and the value, when TelegramRow is saved.
Property TelegramFlagData As %Integer;

Property TelegramFlagValue As %String;

/// The id of the Enabled row for the production and every item of one class that TestNotRunningFollowsABroaderRow has written, ""
/// when it has written none; OnAfterOneTest deletes it.
Property BroadRowId As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Production", "n"))
	Set id = ..RowId()
	Set ..RowFound = ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	If ..RowFound {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Set ..RowValue = row.SettingValue
		Set ..RowDescription = row.Description
		Set ..RowDeployable = row.Deployable
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..TelegramRow '= "" {
		If ..TelegramFlagData {
			Set $$$ConfigIsEnabled("TelegramIn") = ..TelegramFlagValue
		} Else {
			Kill $$$ConfigIsEnabled("TelegramIn")
		}
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefault(..TelegramRow)
		Set ..TelegramRow = ""
	}
	If ..BroadRowId '= "" {
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(..BroadRowId)
		Set ..BroadRowId = ""
	}
	If ..AutoStartSaved {
		Kill ^Ens.AutoStart, ^Ens.Configuration("csp", "LastProduction")
		Merge ^Ens.AutoStart = ^||OcuTalonTestAutoStart
		Merge ^Ens.Configuration("csp", "LastProduction") = ^||OcuTalonTestLastProduction
		Kill ^||OcuTalonTestAutoStart, ^||OcuTalonTestLastProduction
		Set ..AutoStartSaved = 0
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..RestoreRow()
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Row 1: the compiled definition of OcuTalon.Production holds exactly the items of the oracle, in order, each with its
/// class, pool size, enabled flag and settings; each item sits between the markers of the lane that owns it; the four
/// markers appear once each in the order lane A begin, lane A end, lane B begin, lane B end; and no item sits outside a
/// region. The production does not enable testing.
Method TestDefinition()
{
	Set oracle = ..Items()
	For lane = "A", "B" {
		Set rows = $Case(lane, "A": ..Read("Items"), : ##class(OcuTalon.Test.Core.ProductionItems).Items())
		Do $$$AssertTrue(rows.%Size() > 0, "the oracle holds rows of lane "_lane)
		Set others = ""
		Set iterator = rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			If row.lane '= lane Set others = others _ " " _ row.name
		}
		Do $$$AssertEquals(others, "", "every row in lane "_lane_"'s part of the oracle names lane "_lane)
	}
	Set text = ..DefinitionText()
	Do $$$AssertTrue(text '= "", "the ProductionDefinition block is read")
	Set markers = $ListBuild("<!-- lane A: begin -->", "<!-- lane A: end -->", "<!-- lane B: begin -->", "<!-- lane B: end -->")
	Set lane = ""
	Set order = ""
	Set outside = ""
	Set items = 0
	Kill laneOf
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $ZStrip($Piece(text, $Char(10), i), "<>W")
		Set marker = $ListFind(markers, line)
		If marker {
			Set order = order _ marker
			Set lane = $Case(marker, 1: "A", 3: "B", : "")
		}
		If $Extract(line, 1, 6) = "<Item " {
			Set items = items + 1
			Set name = $Piece($Piece(line, " Name=""", 2), """", 1)
			If lane = "" Set outside = outside _ " " _ name
			Set laneOf(name) = lane
		}
	}
	Do $$$AssertEquals(order, "1234", "the four lane markers appear once each, in the order A begin, A end, B begin, B end")
	Do $$$AssertEquals(outside, "", "no item sits outside a lane region")
	Do $$$AssertEquals(items, oracle.%Size(), "the XData holds as many items as the oracle: "_oracle.%Size())

	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	Do $$$AssertEquals(production.TestingEnabled, 0, "testing is not enabled")
	Do $$$AssertEquals(production.Items.Count(), oracle.%Size(), "the compiled production holds as many items as the oracle")
	Set lanes = 0
	Set iterator = oracle.%GetIterator()
	While iterator.%GetNext(.position, .expected) {
		Set item = production.Items.GetAt(position + 1)
		If '$IsObject(item) {
			Do $$$AssertTrue(0, "item "_(position + 1)_" ("_expected.name_") exists")
			Continue
		}
		Do $$$AssertEquals(..Describe(item), ..DescribeExpected(expected), "item "_(position + 1)_" is "_expected.name_" as the ownership table says")
		Do $$$AssertEquals($Get(laneOf(expected.name)), expected.lane, expected.name_" sits in the region of lane "_expected.lane)
		Set lanes = lanes + 1
	}
	Do $$$AssertEquals(lanes, oracle.%Size(), "every oracle item was compared")
}

/// Row 3: every item class that carries STUB answers "not implemented" (code 5003) from the handler of a shadow
/// instance, gives no response and writes no log row; an item class that does not carry it is one the table marks as not
/// a stub. The two rule classes carry STUB and have a rule set with no rule. Every item class is compiled.
Method TestStubsAnswer()
{
	Set before = ..LogRows()
	Set stubs = 0
	Set expectedStubs = 0
	Set iterator = ..Items().%GetIterator()
	While iterator.%GetNext(, .expected) {
		Set class = expected.class
		Set expectedStubs = expectedStubs + expected.stub
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), expected.name_": "_class_" is compiled")
		Set stub = +$Parameter(class, "STUB")
		Do $$$AssertEquals(stub, expected.stub, expected.name_": "_class_" "_$Select(expected.stub: "carries", 1: "does not carry")_" STUB")
		If 'stub Continue
		Set stubs = stubs + 1
		Set host = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
		If '$IsObject(host) {
			Do $$$AssertTrue(0, expected.name_": a shadow instance is made: "_$SYSTEM.Status.GetErrorText(sc))
			Continue
		}
		Set request = ##class(Ens.StringRequest).%New("x")
		Kill response
		If $ClassMethod(class, "%Extends", "Ens.BusinessProcess") {
			Set sc = host.OnRequest(request, .response)
		} ElseIf $ClassMethod(class, "%Extends", "Ens.BusinessOperation") {
			Set sc = host.OnMessage(request, .response)
		} Else {
			Set sc = host.OnProcessInput(request, .response)
		}
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, expected.name_" answers code 5003")
		Do $$$AssertTrue('$IsObject($Get(response)), expected.name_" gives no response")
	}
	Do $$$AssertTrue(expectedStubs >= 0, "the oracle marks item classes as stubs")
	Do $$$AssertEquals(stubs, expectedStubs, "exactly the item classes that the oracle marks carry STUB: "_stubs)
	Do $$$AssertEquals(..LogRows(), before, "the stub handlers write no log row")
	// The STUB and empty-rule-set assertions below hold only while a rule class is still a stub; a built rule class is skipped.
	For class = "OcuTalon.Core.Rule.Outcome", "OcuTalon.Core.Rule.Notify" {
		If +$Parameter(class, "STUB") '= 1 Continue
		Do $$$AssertEquals(+$Parameter(class, "STUB"), 1, class_" carries STUB")
		Set sc = ##class(Ens.Rule.Model.ruleDefinition).LoadFromClass(class, .definition)
		Do $$$AssertStatusOK(sc, class_" loads its rule definition")
		If $$$ISOK(sc) {
			Do $$$AssertEquals(definition.ruleSets.Count(), 1, class_" has one rule set")
			Do $$$AssertEquals(definition.ruleSets.GetAt(1).actions.Count(), 0, class_" has no rule in it")
		}
	}
}

/// Row 4: in a fixture production with no Model row, UnresolvedRunners names the enabled runners whose model does not resolve
/// and no others: a runner with a Model setting, a runner whose agent class carries MODEL, a disabled runner and an item of
/// another class are left out; a runner whose agent class does not exist is named; a System Default Setting that enables the
/// disabled runner brings it in. An unknown item of the fixture resolves nothing.
Method TestRunnerModels()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
	Do ..DeleteModelRows(fixture)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("Zz"_..Number, fixture), "", "an unknown item resolves nothing")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzModelSet", fixture), "claude-sonnet-5-5", "a Model setting of the adapter is the model")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzAgentModel", fixture), "claude-haiku-5-5", "the MODEL of the agent class is the model when the setting is empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzNoModel", fixture), "", "a runner whose agent class has no MODEL resolves nothing")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzMissingClass", fixture), "", "a runner whose agent class does not exist resolves nothing")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(fixture), "ZzNoModel,ZzMissingClass", "only the enabled runners without a model are unresolved")
	Set row = ##class(Ens.Config.DefaultSettings).%New()
	Set row.ProductionName = fixture
	Set row.ItemName = "ZzOffNoModel"
	Set row.HostClassName = "*"
	Set row.SettingName = "Enabled"
	Set row.SettingValue = 1
	Do $$$AssertStatusOK(row.%Save(), "the System Default Setting that enables the disabled runner is saved")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(fixture), "ZzNoModel,ZzMissingClass,ZzOffNoModel", "a runner enabled by a System Default Setting counts")
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(fixture_"||ZzOffNoModel||*||Enabled")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(fixture), "ZzNoModel,ZzMissingClass", "and no longer once the setting is gone")
}

/// Runners lists the five runners of the fixture production in order, each with its agent class and its enabled flag, and not
/// the item of another class; SeedModels writes the Model row of ZzAgentModel, whose agent class has MODEL claude-haiku-5-5,
/// and no row for ZzModelSet (it has a Model setting), ZzNoModel and ZzOffNoModel (no MODEL) or ZzMissingClass (no class). A
/// second run leaves the row as it is, also when it holds another model, and a runner that has a row is left alone. The
/// fixture production has no Model row when the test starts and when it ends.
Method TestSeedModels()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
	Do ..DeleteModelRows(fixture)
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(fixture, .runners)
	Do $$$AssertStatusOK(sc, "Runners reads the fixture production")
	Do $$$AssertEquals(runners, 5, "it lists five runners")
	Set listed = ""
	For i = 1:1:runners {
		Set listed = listed _ $Select(listed = "": "", 1: ";") _ $ListToString(runners(i), "|")
	}
	Do $$$AssertEquals(listed, "ZzNoModel|%AI.Agent|1;ZzModelSet|%AI.Agent|1;ZzAgentModel|OcuTalon.Agent.Triage|1;ZzMissingClass|OcuTalon.Test.Install.ZzNoSuchAgent|1;ZzOffNoModel|%AI.Agent|0", "each with its agent class and its enabled flag")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Install.Step.Production).Runners("Zz"_..Number_".NoSuchProduction", .none), "a production that cannot be opened is an error")
	Do $$$AssertEquals(+$Get(none), 0, "and has no runner")

	Try {
		Do $$$AssertEquals(..ModelRows(fixture), "", "the fixture production has no Model row")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(fixture), "SeedModels runs")
		Do $$$AssertEquals(..ModelRows(fixture), "ZzAgentModel=claude-haiku-5-5", "only ZzAgentModel gets a row, with the MODEL of its agent class")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzModelSet", fixture), "claude-sonnet-5-5", "ZzModelSet keeps its own model")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(fixture), "ZzNoModel,ZzMissingClass", "the runners without a MODEL stay unresolved")

		Set id = fixture_"||ZzAgentModel||*||Model"
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Set row.SettingValue = "claude-sonnet-5-5"
		Do $$$AssertStatusOK(row.%Save(), "the row of ZzAgentModel is set to another model")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(fixture), "SeedModels runs again")
		Do $$$AssertEquals(..ModelRows(fixture), "ZzAgentModel=claude-sonnet-5-5", "the existing row is kept as it is")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..DeleteModelRows(fixture)
	Do $$$AssertEquals(..ModelRows(fixture), "", "the fixture production has no Model row afterwards")
}

/// A runner whose agent class has a MODEL is seeded when no row gives it a model, and is left alone when a row of the
/// production gives it one: for its item and the class of its adapter, for every item of that class, for every item and class,
/// or under the name Adapter:Model. The row is then the only row that SeedModels leaves, and it is the model the runner
/// resolves. A production that cannot be opened is an error and gets no row.
Method TestSeedSpecificity()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
	Set adapter = $Parameter("OcuTalon.Bridge.Operation.AgentRunner", "ADAPTER")
	Do $$$AssertTrue(adapter '= "", "the runner class names its adapter class: "_adapter)
	Set item = "ZzAgentModel"
	Do ..DeleteModelRows(fixture)
	Try {
		Do $$$AssertEquals(..ModelRows(fixture), "", "the fixture production has no Model row")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(fixture), "SeedModels runs with no row")
		Do $$$AssertEquals(..ModelRows(fixture), item_"=claude-haiku-5-5", "and seeds the runner with the MODEL of its agent class")
		Do ..DeleteModelRows(fixture)
		Set variants = $ListBuild($ListBuild(item, adapter, "Model"), $ListBuild("*", adapter, "Model"), $ListBuild("*", "*", "Model"), $ListBuild(item, "*", "Adapter:Model"))
		Set position = 0
		While $ListNext(variants, position, variant) {
			Set label = "a row for item '"_$List(variant, 1)_"', class '"_$List(variant, 2)_"', setting '"_$List(variant, 3)_"'"
			Set row = ##class(Ens.Config.DefaultSettings).%New()
			Set row.ProductionName = fixture
			Set row.ItemName = $List(variant, 1)
			Set row.HostClassName = $List(variant, 2)
			Set row.SettingName = $List(variant, 3)
			Set row.SettingValue = "claude-sonnet-5-5"
			Do $$$AssertStatusOK(row.%Save(), label_" is saved")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, fixture), "claude-sonnet-5-5", label_" gives the runner its model")
			Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(fixture), "SeedModels runs")
			Do $$$AssertEquals(..ModelRows(fixture), $Select($List(variant, 3) = "Model": $List(variant, 1)_"=claude-sonnet-5-5", 1: ""), label_" is the only row, so the runner is not seeded")
			Do ..DeleteModelRows(fixture)
		}
		Set missing = "OcuTalon.Test.Install.ZzNoSuchProd"_..Number
		Do $$$AssertStatusNotOK(##class(OcuTalon.Install.Step.Production).SeedModels(missing), "SeedModels of a production that cannot be opened is an error")
		Do $$$AssertEquals(..ModelRows(missing), "", "and writes no row")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..DeleteModelRows(fixture)
	Do $$$AssertEquals(..ModelRows(fixture), "", "the fixture production has no Model row afterwards")
}

/// SeedEfforts writes the Effort row of ZzAgentModel, whose agent class (Triage) has EFFORT low, and no row for the runners whose
/// agent class has none (%AI.Agent) or does not exist. A second run leaves the row as it is, also when it holds another effort or
/// no effort (empty, the model's default), and a runner that has a row for every item is left alone. The agents of the product
/// seed low, high and nothing.
Method TestSeedEfforts()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
	Set step = "OcuTalon.Install.Step.Production"
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Triage"), "low", "Triage has the EFFORT low")
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Diagnosis"), "high", "Diagnosis has the EFFORT high")
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Chat"), "", "Chat has none")
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "%AI.Agent"), "", "%AI.Agent has none")
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Test.Install.ZzNoSuchAgent"), "", "a class that does not exist has none")
	Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "Ens.StringRequest"), "", "and neither has a class that is not an %AI.Agent")
	Do ..DeleteRows(fixture, "Effort")
	Try {
		Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "", "the fixture production has no Effort row")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedEfforts", fixture), "SeedEfforts runs")
		Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "ZzAgentModel=low", "only ZzAgentModel gets a row, with the EFFORT of its agent class")
		Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(fixture_"||ZzAgentModel||*||Effort").HostClassName, "*", "for any class")

		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(fixture_"||ZzAgentModel||*||Effort")
		Set row.SettingValue = "medium"
		Do $$$AssertStatusOK(row.%Save(), "the row of ZzAgentModel is set to another effort")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedEfforts", fixture), "SeedEfforts runs again")
		Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "ZzAgentModel=medium", "the existing row is kept as it is")
		Set row.SettingValue = ""
		Do $$$AssertStatusOK(row.%Save(), "the row of ZzAgentModel is set to no effort, the model's default")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedEfforts", fixture), "SeedEfforts runs again")
		Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "ZzAgentModel=", "an existing empty row is kept too: the row is not absent")

		Do ..DeleteRows(fixture, "Effort")
		Set row = ##class(Ens.Config.DefaultSettings).%New()
		Set row.ProductionName = fixture
		Set row.ItemName = "*"
		Set row.HostClassName = "*"
		Set row.SettingName = "Effort"
		Set row.SettingValue = "high"
		Do $$$AssertStatusOK(row.%Save(), "a row of the production gives every runner an effort")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedEfforts", fixture), "SeedEfforts runs with it")
		Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "*=high", "and writes no row of its own")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..DeleteRows(fixture, "Effort")
	Do $$$AssertEquals(..SettingRows(fixture, "Effort"), "", "the fixture production has no Effort row afterwards")
}

/// SeedAllowList writes one AgentAllowList row for every item, holding the distinct AgentClass values of the five runners of the
/// fixture production in their order. A second run leaves the row as it is, also when it holds another list or an empty one. It
/// writes nothing when a runner has a list of its own, and an error for a production that cannot be opened.
Method TestSeedAllowList()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
	Set step = "OcuTalon.Install.Step.Production"
	Do ..DeleteRows(fixture, "AgentAllowList")
	Try {
		Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "", "the fixture production has no AgentAllowList row")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedAllowList", fixture), "SeedAllowList runs")
		Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "*=%AI.Agent,OcuTalon.Agent.Triage,OcuTalon.Test.Install.ZzNoSuchAgent", "one row for every item, with the distinct agent classes of the runners")
		For item = "ZzNoModel", "ZzAgentModel", "ZzOffNoModel" {
			Do $$$AssertEquals(##class(Ens.Director).GetAdapterSettingValue(fixture_"||"_item, "AgentAllowList", .status), "%AI.Agent,OcuTalon.Agent.Triage,OcuTalon.Test.Install.ZzNoSuchAgent", item_" resolves the list")
		}

		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(fixture_"||*||*||AgentAllowList")
		Set row.SettingValue = "OcuTalon.Agent.Triage"
		Do $$$AssertStatusOK(row.%Save(), "the row is set to another list")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedAllowList", fixture), "SeedAllowList runs again")
		Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "*=OcuTalon.Agent.Triage", "the existing row is kept as it is")
		Set row.SettingValue = ""
		Do $$$AssertStatusOK(row.%Save(), "the row is set to an empty list, which refuses every class")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedAllowList", fixture), "SeedAllowList runs again")
		Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "*=", "an existing empty row is kept too: the row is not absent")

		Do ..DeleteRows(fixture, "AgentAllowList")
		Set row = ##class(Ens.Config.DefaultSettings).%New()
		Set row.ProductionName = fixture
		Set row.ItemName = "ZzModelSet"
		Set row.HostClassName = "*"
		Set row.SettingName = "AgentAllowList"
		Set row.SettingValue = "%AI.Agent"
		Do $$$AssertStatusOK(row.%Save(), "a runner gets a list of its own")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedAllowList", fixture), "SeedAllowList runs with it")
		Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "ZzModelSet=%AI.Agent", "and writes no row of its own, because that runner resolves a list")

		Set missing = "OcuTalon.Test.Install.ZzNoSuchProd"_..Number
		Do $$$AssertStatusNotOK($ClassMethod(step, "SeedAllowList", missing), "SeedAllowList of a production that cannot be opened is an error")
		Do $$$AssertEquals(..SettingRows(missing, "AgentAllowList"), "", "and writes no row")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..DeleteRows(fixture, "AgentAllowList")
	Do $$$AssertEquals(..SettingRows(fixture, "AgentAllowList"), "", "the fixture production has no AgentAllowList row afterwards")
}

/// SeedClassification (Story 19.4; AD-5) writes the System Default Setting row (production, Decide, any class, ToolClassification) with the product's entry for the
/// documents search, merging with the row it finds: a missing or blank row becomes the product's entries; the developer's entries stay in their places, a wrong
/// documents entry is replaced in its place (and a repeated one dropped), a second run changes nothing, a row that already holds the result is not written
/// again (its text and description stay), an element that is not an object is kept as it is, and a row that is not a JSON array is left as it is
/// with one warning. The oracle's Decide item holds no ToolClassification setting (TestDefinition). The rows are those of the fixture production.
Method TestSeedClassification()
{
	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set step = "OcuTalon.Install.Step.Production"
	Set own = $ClassMethod(step, "ClassificationEntries").%ToJSON()
	Set docs = "{""class"":""%AI.RAG.KnowledgeBase"",""tool"":""documents"",""classification"":""safe"",""readOnly"":1,""trustedOutput"":0}"
	Do $$$AssertEquals(own, "["_docs_"]", "the product ships one entry: AI Hub's knowledge base, documents, safe, read-only, output not trusted")
	Set dev1 = "{""class"":""Zz.Tools"",""tool"":""zz_a"",""classification"":""risky""}"
	Set dev2 = "{""class"":""Zz.Tools"",""tool"":""zz_b"",""classification"":""safe"",""readOnly"":1}"
	Do ..DeleteRows(fixture, "ToolClassification")
	Try {
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "", "the fixture production has no ToolClassification row")
		Do ..TakeWarnings()
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a production with no row")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide="_own, "and creates the row of Decide with the product's entries")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs again")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide="_own, "and the second run leaves the row as it is")

		Do ..PutClassification(fixture, "["_dev1_","_dev2_"]")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a row of the developer's entries")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide=["_dev1_","_dev2_","_docs_"]", "and adds the documents entry after them, losing none")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs again on it")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide=["_dev1_","_dev2_","_docs_"]", "and is idempotent there too")

		Set wrong = "{""class"":""%AI.RAG.KnowledgeBase"",""tool"":""documents"",""classification"":""risky"",""trustedOutput"":1}"
		Do ..PutClassification(fixture, "["_dev1_","_wrong_","_dev2_","_wrong_"]")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a row with a wrong documents entry, twice")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide=["_dev1_","_docs_","_dev2_"]", "and replaces the first in its place, drops the repeat and keeps the developer's entries")

		Set spaced = "[ "_dev1_" , "_docs_" ]"
		Do ..PutClassification(fixture, spaced)
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a row that already holds the product's entry, written with spaces")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification")_"|"_##class(Ens.Config.DefaultSettings).%OpenId(fixture_"||Decide||*||ToolClassification").Description, "Decide="_spaced_"|Zz test row", "and does not write it again: its text and its description stay")
		Do ..PutClassification(fixture, "["_dev1_",null,true]")
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a row with a null and a true element")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide=["_dev1_",null,true,"_docs_"]", "and keeps those elements as they are")

		Do ..PutClassification(fixture, " "_$Char(10))
		Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on a blank row")
		Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide="_own, "and a blank row becomes the product's entries")

		Do ..TakeWarnings()
		For malformed = "not json", "{""class"":""x""}", "42" {
			Do ..PutClassification(fixture, malformed)
			Do $$$AssertStatusOK($ClassMethod(step, "SeedClassification", fixture), "SeedClassification runs on '"_malformed_"'")
			Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "Decide="_malformed, "and leaves that row as it is")
		}
		Set warnings = ..TakeWarnings()
		Do $$$AssertEquals($ListLength(warnings), 3, "with one warning each")
		Do $$$AssertTrue($ListGet(warnings, 1) [ "ToolClassification", "that names the setting")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..DeleteRows(fixture, "ToolClassification")
	Do ..TakeWarnings()
	Do $$$AssertEquals(..SettingRows(fixture, "ToolClassification"), "", "the fixture production has no ToolClassification row afterwards")
}

/// Row 5: EvalEnabled is 1 only for "1"; SetEval writes the System Default Setting row (production, EvalIn, any class,
/// Enabled) with 1, then with 0, and says in its description that the step writes it; NotRunning says that
/// OcuTalon.Production is not running when it does not run.
Method TestStepHelpers()
{
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).EvalEnabled("1"), 1, "1 enables")
	For value = "", "0", "true", " 1", "1 ", "01", 2 {
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).EvalEnabled(value), 0, "'"_value_"' does not enable")
	}
	Set id = ..RowId()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SetEval(1), "SetEval(1)")
	Do $$$AssertEquals(..ValueOf(id), 1, "the row holds 1")
	Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%OpenId(id).Description [ "Production install step", "the description says the step writes the row")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SetEval(0), "SetEval(0)")
	Do $$$AssertEquals(..ValueOf(id), 0, "the row holds 0")
	Do ..RestoreRow()
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(id), ..RowFound, "the row is as it was found")
	If ..RowFound Do $$$AssertEquals(..ValueOf(id), ..RowValue, "with the value it had")

	Set production = "OcuTalon.Test.Install.ZzProd"_..Number
	Set rowId = production_"||ZzItem||*||ZzSetting"
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(production, "ZzItem", "ZzSetting", "one", "first"), "WriteDefault creates a row")
	Do $$$AssertEquals(..ValueOf(rowId), "one", "the row holds the value")
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(rowId).Description, "first", "and the description")
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(rowId).HostClassName, "*", "for any class")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(production, "ZzItem", "ZzSetting", "two", "second"), "WriteDefault changes the row it finds")
	Do $$$AssertEquals(..ValueOf(rowId), "two", "the row holds the new value")
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(rowId).Description, "second", "and the new description")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND SettingName = 'ZzSetting'", production)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and there is still one row")
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(rowId)

	If ##class(Ens.Director).IsProductionRunning(.running), running = ..#PRODUCTION {
		Do $$$AssertSkipped("OcuTalon.Production runs in this namespace, so NotRunning cannot say that it does not")
	} Else {
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "OcuTalon.Production is not running", "NotRunning names the production")
	}
}

/// NotRunning reads the Enabled row of the System Default Settings as Ens does: TelegramIn (pool 1, no job) is left out when the row
/// is 0 or the runtime flag is off, whatever the row, and named when the flag is on and the row is 1 or missing. The row and the flag
/// are written for each case and put back after the test.
Method TestNotRunningFollowsTheRow()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set item = "TelegramIn"
	If '##class(Ens.Director).IsProductionRunning(.running) || (running '= ..#PRODUCTION) {
		Do $$$AssertSkipped(..#PRODUCTION_" does not run in this namespace, so NotRunning cannot be read per item")
		Quit
	}
	If $ListLength($ClassMethod(fixture, "Jobs", item)) {
		Do $$$AssertSkipped(item_" has a job here, and this test cannot stop it")
		Quit
	}
	Set ..TelegramRow = $ClassMethod(fixture, "SnapshotDefault", item, "Enabled")
	Set ..TelegramFlagData = $Data($$$ConfigIsEnabled(item), value)
	Set ..TelegramFlagValue = $Get(value)
	Do $$$AssertTrue($Get($$$ConfigPoolSize(item)) > 0, item_" has a pool")
	For case = 1:1:6 {
		Set row = $Case(case, 1: 0, 2: 0, 3: 1, 4: 1, : "")
		Set flag = $Select(case # 2: 1, 1: 0)
		Set named = $Case(case, 3: 1, 5: 1, : 0)
		If row = "" {
			Do ##class(Ens.Config.DefaultSettings).%DeleteId($ClassMethod(fixture, "DefaultId", item, "Enabled"))
			Do $$$AssertNotTrue(##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, item, $Get($$$ConfigClassName(item)), "", "Enabled"), "no Enabled row of any specificity applies to "_item)
		} Else {
			Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", item, "Enabled", row), "the Enabled row of "_item_" is set to "_row)
		}
		Set $$$ConfigIsEnabled(item) = flag
		Set label = item_" with "_$Select(row = "": "no Enabled row", 1: "Enabled row "_row)_" and runtime flag "_flag
		Set actual = $ListFind($ListFromString(##class(OcuTalon.Install.Step.Production).NotRunning()), item) > 0
		Do $$$AssertEquals(actual, named, label_$Select(named: " is named", 1: " is not named")_" by NotRunning")
	}
}

/// Ens takes the Enabled row that applies to an item from the System Default Settings at any specificity, and so does NotRunning:
/// a row of the production for every item of TelegramIn's class (item "*", the class of TelegramIn) of 0 leaves TelegramIn (pool 1,
/// no job, runtime flag 1) out, and of 1 names it. TelegramIn's own row is deleted for the test and put back after it, as is the
/// runtime flag; the broad row is deleted after the test, and the test writes none where one with that id already exists.
Method TestNotRunningFollowsABroaderRow()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set item = "TelegramIn"
	If '##class(Ens.Director).IsProductionRunning(.running) || (running '= ..#PRODUCTION) {
		Do $$$AssertSkipped(..#PRODUCTION_" does not run in this namespace, so NotRunning cannot be read per item")
		Quit
	}
	If $ListLength($ClassMethod(fixture, "Jobs", item)) {
		Do $$$AssertSkipped(item_" has a job here, and this test cannot stop it")
		Quit
	}
	Set class = $Get($$$ConfigClassName(item))
	Do $$$AssertTrue(class '= "", item_" has a class at runtime")
	Set id = ..#PRODUCTION_"||*||"_class_"||Enabled"
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
		Do $$$AssertSkipped("a row "_id_" exists here, and this test does not touch rows it did not write")
		Quit
	}
	Set ..TelegramRow = $ClassMethod(fixture, "SnapshotDefault", item, "Enabled")
	Set ..TelegramFlagData = $Data($$$ConfigIsEnabled(item), value)
	Set ..TelegramFlagValue = $Get(value)
	Do ##class(Ens.Config.DefaultSettings).%DeleteId($ClassMethod(fixture, "DefaultId", item, "Enabled"))
	Set ..BroadRowId = id
	Set $$$ConfigIsEnabled(item) = 1
	Do $$$AssertTrue($Get($$$ConfigPoolSize(item)) > 0, item_" has a pool")
	For row = 0, 1 {
		Kill value
		If row = 0 {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Config.DefaultSettings (ProductionName, ItemName, HostClassName, SettingName, SettingValue, Description) VALUES (?, '*', ?, 'Enabled', 0, 'Written by a test; the test deletes it.')", ..#PRODUCTION, class)
		} Else {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens_Config.DefaultSettings SET SettingValue = 1 WHERE ID = ?", id)
		}
		Do $$$AssertTrue(result.%SQLCODE >= 0, "the broad Enabled row is written with "_row)
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, item, class, "", "Enabled", .value) && (value = row), "the row that applies to "_item_" is that broad row, "_row)
		Set named = $ListFind($ListFromString(##class(OcuTalon.Install.Step.Production).NotRunning()), item) > 0
		Do $$$AssertEquals(named, row, item_" with a broad Enabled row "_row_" and runtime flag 1 is "_$Select(row: "", 1: "not ")_"named by NotRunning")
	}
}

/// An enabled item (runtime flag on, a pool, no Enabled row of 0) that has an alive job which is not in error is not named by
/// NotRunning: the production runs those items, and NotRunning reads only what is there.
Method TestNotRunningLeavesOutAnItemWithAJob()
{
	If '##class(Ens.Director).IsProductionRunning(.running) || (running '= ..#PRODUCTION) {
		Do $$$AssertSkipped(..#PRODUCTION_" does not run in this namespace, so NotRunning cannot be read per item")
		Quit
	}
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	Do $$$AssertStatusOK(result.Execute(), "the jobs are listed")
	Kill candidates
	While result.Next() {
		If result.Get("State") '= "Alive" Continue
		If $ListFind($ListFromString($Parameter("OcuTalon.Install.Step.Production", "DEADSTATUSES")), result.Get("Status")) Continue
		Set item = result.Get("ConfigName")
		If item = "" Continue
		If '$Get($$$ConfigIsEnabled(item)) || '$Get($$$ConfigPoolSize(item)) Continue
		If ##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, item, $Get($$$ConfigClassName(item)), "", "Enabled", .row), 'row Continue
		Set candidates(item) = ""
	}
	Set count = 0
	Set wrong = ""
	Set named = $ListFromString(##class(OcuTalon.Install.Step.Production).NotRunning())
	Set item = ""
	For {
		Set item = $Order(candidates(item))
		Quit:item=""
		Set count = count + 1
		If $ListFind(named, item) Set wrong = wrong _ $Select(wrong = "": "", 1: ",") _ item
	}
	Do $$$AssertTrue(count > 0, "the running production has at least one enabled item with an alive job")
	Do $$$AssertEquals(wrong, "", "NotRunning names none of the "_count_" enabled items that have an alive job")
}

/// The sentence for a production that does not run: a step class whose PRODUCTION parameter names a production that is not the
/// running one answers with that name and "is not running", whether or not OcuTalon.Production runs here (TestStepHelpers can read this
/// only where it does not run). The step class is a subclass that the test compiles, with a name that Clean sweeps, and deletes.
Method TestNotRunningNamesTheProduction()
{
	Set shadow = "OcuTalon.Test.Install.ZzProdStep"_..Number
	Set sc = ..Create("StepShadow", shadow)
	Do $$$AssertStatusOK(sc, "the shadow step compiles")
	If $$$ISERR(sc) Quit
	Try {
		Do $$$AssertEquals($Parameter(shadow, "PRODUCTION"), shadow, "its PRODUCTION is not a production that runs")
		Do $$$AssertEquals($ClassMethod(shadow, "NotRunning"), shadow_" is not running", "NotRunning names the production and says that it does not run")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the shadow step answers")
	}
	Do $SYSTEM.OBJ.Delete(shadow, "-d")
	Do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%ExistsId(shadow), 0, "and is deleted")
}

/// AutoStart marks the production autostart for the caller "ipm" and changes nothing for any other caller, the Docker path's
/// "after-start" and the empty caller included.
Method TestAutoStart()
{
	Kill ^||OcuTalonTestAutoStart, ^||OcuTalonTestLastProduction
	Merge ^||OcuTalonTestAutoStart = ^Ens.AutoStart
	Merge ^||OcuTalonTestLastProduction = ^Ens.Configuration("csp", "LastProduction")
	Set ..AutoStartSaved = 1
	Set step = "OcuTalon.Install.Step.Production"
	Kill ^Ens.AutoStart
	Do $$$AssertStatusOK($ClassMethod(step, "AutoStart", "after-start"), "AutoStart for the Docker path")
	Do $$$AssertEquals($Data(^Ens.AutoStart), 0, "does not mark an unmarked instance")
	Do $$$AssertStatusOK($ClassMethod(step, "AutoStart", ""), "AutoStart for no caller")
	Do $$$AssertEquals($Data(^Ens.AutoStart), 0, "does not mark either")
	Set ^Ens.AutoStart = "Zz.Other.Production"
	Do $$$AssertStatusOK($ClassMethod(step, "AutoStart", "after-start"), "AutoStart for the Docker path on a marked instance")
	Do $$$AssertEquals($Get(^Ens.AutoStart), "Zz.Other.Production", "does not clear or change the mark")
	Do $$$AssertStatusOK($ClassMethod(step, "AutoStart", "ipm"), "AutoStart for ipm")
	Do $$$AssertEquals($Get(^Ens.AutoStart), ..#PRODUCTION, "marks OcuTalon.Production")
}

/// The package installs the bridge example (AD-2) and starts nothing of it: OcuTalon.BridgeExample.Production and its agent are
/// compiled, the production is registered with its twelve items and TestingEnabled off, and it is neither the running production
/// nor the autostart production.
Method TestExampleInstalledNotStarted()
{
	Set example = "OcuTalon.BridgeExample.Production"
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(example), "the example production is compiled")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.BridgeExample.Agent"), "and so is its agent")
	Set definition = ##class(Ens.Config.Production).%OpenId(example)
	Do $$$AssertTrue($IsObject(definition), "the example production is registered")
	If $IsObject(definition) {
		Do $$$AssertEquals(definition.Items.Count(), 12, "with its twelve items")
		Do $$$AssertEquals(+definition.TestingEnabled, 0, "and TestingEnabled off")
	}
	Do ##class(Ens.Director).IsProductionRunning(.running)
	Do $$$AssertTrue($Get(running) '= example, "the example production is not running")
	Do $$$AssertTrue($Get(^Ens.AutoStart) '= example, "and is not the autostart production")
}

/// The oracle as a dynamic array: lane A's rows of XData Items, then lane B's rows of OcuTalon.Test.Core.ProductionItems,
/// in the order of the production. The live tests of docker/tests/ read the same list in their container, so that the
/// ownership table has one copy in the tests.
ClassMethod Items() As %DynamicArray
{
	Set items = ..Read("Items")
	Set iterator = ##class(OcuTalon.Test.Core.ProductionItems).Items().%GetIterator()
	While iterator.%GetNext(, .item) {
		Do items.%Push(item)
	}
	Quit items
}

/// --- helpers ---
/// The id of the EvalIn System Default Setting row.
ClassMethod RowId() As %String [ Private ]
{
	Quit ..#PRODUCTION_"||EvalIn||*||Enabled"
}

/// The value of a System Default Setting row.
ClassMethod ValueOf(id As %String) As %String [ Private ]
{
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// Puts the EvalIn row back as it was found: the same value, or no row.
Method RestoreRow() [ Private ]
{
	Set id = ..RowId()
	If ..RowFound {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		If '$IsObject(row) {
			Set row = ##class(Ens.Config.DefaultSettings).%New()
			Set row.ProductionName = ..#PRODUCTION
			Set row.ItemName = "EvalIn"
			Set row.HostClassName = "*"
			Set row.SettingName = "Enabled"
		}
		Set row.SettingValue = ..RowValue
		Set row.Description = ..RowDescription
		Set row.Deployable = ..RowDeployable
		Do row.%Save()
	} ElseIf ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	}
}

/// The Model rows of a production as item=value, separated by semicolons, in the order of the items.
ClassMethod ModelRows(production As %String) As %String [ Private ]
{
	Quit ..SettingRows(production, "Model")
}

/// The rows of a production for a setting as item=value, separated by semicolons, in the order of the items.
ClassMethod SettingRows(production As %String, setting As %String) As %String [ Private ]
{
	Set rows = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ItemName, SettingValue FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND SettingName = ? ORDER BY ItemName", production, setting)
	While result.%Next() {
		Set rows = rows _ $Select(rows = "": "", 1: ";") _ result.%GetData(1) _ "=" _ result.%GetData(2)
	}
	Quit rows
}

/// Writes the ToolClassification row of Decide for the production with the value (the row is deleted afterwards by the test).
ClassMethod PutClassification(production As %String, value As %String) [ Private ]
{
	Do ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, "Decide", "ToolClassification", value, "Zz test row")
}

/// The warnings the install step recorded since the last call, as a list.
ClassMethod TakeWarnings() As %List [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Production).TakeWarnings()
}

/// Deletes the rows of a production for a setting.
ClassMethod DeleteRows(production As %String, setting As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND SettingName = ?", production, setting)
}

/// Deletes the Model and Adapter:Model rows of a production.
ClassMethod DeleteModelRows(production As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND SettingName IN ('Model', 'Adapter:Model')", production)
}

/// The ProductionDefinition block of OcuTalon.Production as text, lines separated by a line feed.
ClassMethod DefinitionText() As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#PRODUCTION_"||ProductionDefinition")
	If '$IsObject(xdata) Quit ""
	Quit $Replace(xdata.Data.Read(1000000), $Char(13), "")
}

/// A compiled item as one line: name, class, pool size, enabled, and its settings as Target:Name=Value in the item's order.
ClassMethod Describe(item As Ens.Config.Item) As %String [ Private ]
{
	Set settings = ""
	For i = 1:1:item.Settings.Count() {
		Set setting = item.Settings.GetAt(i)
		Set settings = settings _ $Select(settings = "": "", 1: ";") _ setting.Target _ ":" _ setting.Name _ "=" _ setting.Value
	}
	Quit item.Name_"|"_item.ClassName_"|"_item.PoolSize_"|"_item.Enabled_"|"_settings
}

/// An oracle item as the same line.
ClassMethod DescribeExpected(expected As %DynamicObject) As %String [ Private ]
{
	Set settings = ""
	Set iterator = expected.settings.%GetIterator()
	While iterator.%GetNext(, .setting) {
		Set settings = settings _ $Select(settings = "": "", 1: ";") _ setting.target _ ":" _ setting.name _ "=" _ setting.value
	}
	Quit expected.name_"|"_expected.class_"|"_expected.pool_"|"_+expected.enabled_"|"_settings
}

/// The rows of the log that classes of OcuTalon wrote.
ClassMethod LogRows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE SourceClass %STARTSWITH 'OcuTalon.'")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Creates and compiles a class from an XData block of this class, with @CLASS@ replaced by the class name.
Method Create(block As %String, className As %String) As %Status [ Private ]
{
	Set text = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_block).Data.Read(100000)
	Set text = $Replace($Replace(text, $Char(13), ""), "@CLASS@", className)
	Set sc = ##class(%Compiler.UDL.TextServices).SetTextFromString($Namespace, className, text, $Char(10))
	If $$$ISOK(sc) Set sc = $SYSTEM.OBJ.Compile(className, "ck-d")
	Quit sc
}

/// Deletes every class named OcuTalon.Test.Install.ZzProd... that an earlier run may have left (the fixture productions and the
/// shadow step classes), with the System Default Settings of the fixture productions.
ClassMethod Clean() [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Test.Install.ZzProd'")
	Set result = statement.%Execute()
	While result.%Next() {
		Set name = result.%GetData(1)
		Do $SYSTEM.OBJ.Delete(name, "-d")
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Config.DefaultSettings WHERE ProductionName %STARTSWITH 'OcuTalon.Test.Install.ZzProd'")
}

/// An XData block of JSON as a dynamic object.
ClassMethod Read(xdataName As %String) As %DynamicAbstractObject [ Private ]
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_xdataName).Data)
}

/// Lane A's rows of the oracle: the items of lane A's region, in the order of the production. Lane A edits these rows,
/// and only these, when it builds, adds, disables or reconfigures one of its items. stub is 1 for an item class that must
/// carry STUB (every unbuilt item; not the stock classes). A setting is {"target","name","value"}.
XData Items [ MimeType = application/json ]
{
[
 {"lane": "A", "name": "TelegramIn", "class": "OcuTalon.Channel.Telegram.In", "pool": 1, "enabled": 0, "stub": 0, "settings": [{"target": "Adapter", "name": "CallInterval", "value": "1"}]},
 {"lane": "A", "name": "TelegramOut", "class": "OcuTalon.Channel.Telegram.Out", "pool": 1, "enabled": 0, "stub": 0, "settings": []},
 {"lane": "A", "name": "Decide", "class": "OcuTalon.Bridge.Process.Decide", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Host", "name": "HostSinkClass", "value": "OcuTalon.Core.BridgeSink"}, {"target": "Host", "name": "ReplyFilterClass", "value": "OcuTalon.Checks.ReplyGuard"}, {"target": "Host", "name": "TurnToolsClass", "value": "OcuTalon.Docs.TurnTools"}, {"target": "Host", "name": "ClassificationClass", "value": "OcuTalon.Mcp.Classification"}, {"target": "Host", "name": "McpServersClass", "value": "OcuTalon.Mcp.Attach"}]},
 {"lane": "A", "name": "ApprovalHold", "class": "OcuTalon.Bridge.Process.ApprovalHold", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "ApprovalStartIn", "class": "OcuTalon.Bridge.Service.ApprovalStart", "pool": 0, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "TriageAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Triage"}, {"target": "Host", "name": "ReplyClass", "value": "OcuTalon.Bridge.Msg.DecisionPayload"}]},
 {"lane": "A", "name": "DiagnosisAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 2, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Diagnosis"}, {"target": "Host", "name": "ReplyClass", "value": "OcuTalon.Watch.Msg.DiagnosisPayload"}]},
 {"lane": "A", "name": "ChatAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Chat"}]},
 {"lane": "A", "name": "TriageAgentRetry", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Triage"}, {"target": "Host", "name": "ReplyClass", "value": "OcuTalon.Bridge.Msg.DecisionPayload"}]},
 {"lane": "A", "name": "DiagnosisAgentRetry", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Diagnosis"}, {"target": "Host", "name": "ReplyClass", "value": "OcuTalon.Watch.Msg.DiagnosisPayload"}]},
 {"lane": "A", "name": "ChatAgentRetry", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Chat"}]},
 {"lane": "A", "name": "AgentSteps", "class": "OcuTalon.Bridge.Operation.Steps", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "OcuTalonApprovals", "class": "EnsLib.Workflow.Operation", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "FailurePoller", "class": "OcuTalon.Watch.FailurePoller", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "CallInterval", "value": "3"}]},
 {"lane": "A", "name": "IncidentManager", "class": "OcuTalon.Watch.IncidentManager", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "WatchOps", "class": "OcuTalon.Watch.Ops", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "EvalIn", "class": "OcuTalon.Eval.In", "pool": 0, "enabled": 0, "stub": 0, "settings": []},
 {"lane": "A", "name": "EvalSink", "class": "OcuTalon.Eval.Sink", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "FixExecutor", "class": "OcuTalon.Fix.Executor", "pool": 2, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "Checks", "class": "OcuTalon.Checks.Process", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "DigestStore", "class": "OcuTalon.Digest.Store", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "Digest", "class": "OcuTalon.Digest.Process", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "ReconcileIn", "class": "OcuTalon.Install.ReconcileIn", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "CallInterval", "value": "5"}]},
 {"lane": "A", "name": "MemoryOps", "class": "OcuTalon.Memory.Ops", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "DocumentOps", "class": "OcuTalon.Docs.Ops", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "McpOps", "class": "OcuTalon.Mcp.Ops", "pool": 1, "enabled": 1, "stub": 0, "settings": []}
]
}

/// A step whose PRODUCTION is not a production that runs, for TestNotRunningNamesTheProduction.
XData StepShadow [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step.Production
{

Parameter PRODUCTION = "@CLASS@";

}
}

/// A production with five runners and an item that is not a runner, for UnresolvedRunners.
XData FixtureProduction [ MimeType = text/plain ]
{
Class @CLASS@ Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="@CLASS@" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="ZzNoModel" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">%AI.Agent</Setting>
  </Item>
  <Item Name="ZzModelSet" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">%AI.Agent</Setting>
    <Setting Target="Adapter" Name="Model">claude-sonnet-5-5</Setting>
  </Item>
  <Item Name="ZzAgentModel" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Triage</Setting>
  </Item>
  <Item Name="ZzMissingClass" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Test.Install.ZzNoSuchAgent</Setting>
  </Item>
  <Item Name="ZzOffNoModel" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="false">
    <Setting Target="Adapter" Name="AgentClass">%AI.Agent</Setting>
  </Item>
  <Item Name="ZzNotRunner" ClassName="OcuTalon.Bridge.Operation.Steps" PoolSize="1" Enabled="true"/>
</Production>
}

}
}

}
