/// Tests of OcuTalon.Production and of the Production installer step (Story 0.6, matrix rows 1 and 3 to 5). Nothing here
/// starts, stops or updates a production: the tests read the definition of OcuTalon.Production, call the stub handlers of
/// shadow instances, write the System Default Setting row of the EvalIn switch (restored as it was found), and compile a
/// fixture production of their own with one System Default Setting row of its own, both deleted afterwards.
/// The oracle is a copy of the ownership table, split by lane so that each lane edits only its own rows (AD-29, AD-33):
/// lane A's rows are XData Items below, lane B's are in OcuTalon.Test.Core.ProductionItems, and Items() returns both in
/// the order of the production. The counts the tests use come from the oracle.
///   - TestDefinition: the compiled XData holds exactly the items of the oracle, each between the markers of its lane,
///     with the four markers once each in order and no item outside a region;
///   - TestStubsAnswer: every item class that carries STUB answers "not implemented" (code 5003), with no response and no
///     new log row; the two rule classes carry STUB and hold a rule set with no rule;
///   - TestRunnerModels: the three runners resolve claude-haiku-5-5, an unknown item resolves nothing, and
///     UnresolvedRunners names exactly the enabled runners with no model in a fixture production;
///   - TestStepHelpers: EvalEnabled is 1 only for "1", SetEval writes the row, and NotRunning names the production when
///     it does not run.
/// The fixture production is OcuTalon.Test.Install.ZzProd<n>, n from ^OcuTalonTest("Production","n") (never reset);
/// OnBeforeAllTests and OnAfterAllTests delete every such class, and the EvalIn row is put back as it was found.
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
	Do $$$AssertTrue(expectedStubs > 0, "the oracle marks item classes as stubs")
	Do $$$AssertEquals(stubs, expectedStubs, "exactly the item classes that the oracle marks carry STUB: "_stubs)
	Do $$$AssertEquals(..LogRows(), before, "the stub handlers write no log row")
	For class = "OcuTalon.Core.Rule.Outcome", "OcuTalon.Core.Rule.Notify" {
		Do $$$AssertEquals(+$Parameter(class, "STUB"), 1, class_" carries STUB")
		Set sc = ##class(Ens.Rule.Model.ruleDefinition).LoadFromClass(class, .definition)
		Do $$$AssertStatusOK(sc, class_" loads its rule definition")
		If $$$ISOK(sc) {
			Do $$$AssertEquals(definition.ruleSets.Count(), 1, class_" has one rule set")
			Do $$$AssertEquals(definition.ruleSets.GetAt(1).actions.Count(), 0, class_" has no rule in it")
		}
	}
}

/// Row 4: the three runner items resolve claude-haiku-5-5 and an unknown item resolves nothing; the runners of the
/// production leave nothing unresolved. In a fixture production, UnresolvedRunners names the enabled runners whose
/// model does not resolve and no others: a runner with a Model setting, a runner whose agent class carries MODEL, a
/// disabled runner and an item of another class are left out; a runner whose agent class does not exist is named; a
/// System Default Setting that enables the disabled runner brings it in.
Method TestRunnerModels()
{
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ..#PRODUCTION), "claude-haiku-5-5", item_" resolves claude-haiku-5-5")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("Zz"_..Number, ..#PRODUCTION), "", "an unknown item resolves nothing")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(..#PRODUCTION), "", "no runner of the production is unresolved")
	Do $$$AssertTrue(##class(OcuTalon.Install.Step.Production).UnresolvedRunners("Zz"_..Number_".NoSuchProduction") '= "", "a production whose definition cannot be opened is not reported as resolved")

	Set fixture = "OcuTalon.Test.Install.ZzProd"_..Number
	Set sc = ..Create("FixtureProduction", fixture)
	Do $$$AssertStatusOK(sc, "the fixture production compiles")
	If $$$ISERR(sc) Quit
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

	If ##class(Ens.Director).IsProductionRunning(.running), running = ..#PRODUCTION {
		Do $$$AssertSkipped("OcuTalon.Production runs in this namespace, so NotRunning cannot say that it does not")
	} Else {
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "OcuTalon.Production is not running", "NotRunning names the production")
	}
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

/// Deletes every fixture production class that an earlier run may have left, with its System Default Settings.
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
 {"lane": "A", "name": "TelegramIn", "class": "OcuTalon.Channel.Telegram.In", "pool": 1, "enabled": 0, "stub": 1, "settings": []},
 {"lane": "A", "name": "TelegramOut", "class": "OcuTalon.Channel.Telegram.Out", "pool": 1, "enabled": 0, "stub": 1, "settings": []},
 {"lane": "A", "name": "Decide", "class": "OcuTalon.Bridge.Process.Decide", "pool": 1, "enabled": 1, "stub": 1, "settings": [{"target": "Host", "name": "HostSinkClass", "value": "OcuTalon.Core.BridgeSink"}, {"target": "Host", "name": "ReplyFilterClass", "value": "OcuTalon.Checks.ReplyGuard"}]},
 {"lane": "A", "name": "ApprovalHold", "class": "OcuTalon.Bridge.Process.ApprovalHold", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "ApprovalStartIn", "class": "OcuTalon.Bridge.Service.ApprovalStart", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "TriageAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 1, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Triage"}]},
 {"lane": "A", "name": "DiagnosisAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 1, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Diagnosis"}]},
 {"lane": "A", "name": "ChatAgent", "class": "OcuTalon.Bridge.Operation.AgentRunner", "pool": 1, "enabled": 1, "stub": 1, "settings": [{"target": "Adapter", "name": "AgentClass", "value": "OcuTalon.Agent.Chat"}]},
 {"lane": "A", "name": "AgentSteps", "class": "OcuTalon.Bridge.Operation.Steps", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "OcuTalonApprovals", "class": "EnsLib.Workflow.Operation", "pool": 1, "enabled": 1, "stub": 0, "settings": []},
 {"lane": "A", "name": "FailurePoller", "class": "OcuTalon.Watch.FailurePoller", "pool": 0, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "IncidentManager", "class": "OcuTalon.Watch.IncidentManager", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "WatchOps", "class": "OcuTalon.Watch.Ops", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "EvalIn", "class": "OcuTalon.Eval.In", "pool": 0, "enabled": 0, "stub": 1, "settings": []},
 {"lane": "A", "name": "EvalSink", "class": "OcuTalon.Eval.Sink", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "FixExecutor", "class": "OcuTalon.Fix.Executor", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "Checks", "class": "OcuTalon.Checks.Process", "pool": 1, "enabled": 1, "stub": 1, "settings": []},
 {"lane": "A", "name": "DigestStore", "class": "OcuTalon.Digest.Store", "pool": 1, "enabled": 1, "stub": 1, "settings": []}
]
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
