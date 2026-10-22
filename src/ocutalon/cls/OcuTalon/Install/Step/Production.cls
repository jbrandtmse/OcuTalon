Include Ensemble

/// The Production step (AD-23): starts OcuTalon.Production, or restarts every item when it is already running, and
/// waits until every enabled item runs and every agent runner resolves a model. Never marks the production autostart:
/// on the Docker path this step is what starts it (AD-3), and an IPM install marks it in Story 15.2.
/// At every start the step first writes the System Default Setting row that enables or disables the EvalIn item from the
/// OCUTALON_EVAL environment variable (AD-22). A System Default Setting overrides the Enabled flag of the production
/// definition, so the definition stays as the class says and a recompile drops nothing. It then seeds the Model row of
/// each agent runner that has no model: the value is the MODEL parameter of the runner's agent class, written only when
/// no item setting and no System Default Setting holds a model, so a model chosen later is never overwritten (AD-7, AD-19).
/// In the same way it seeds the Effort row of each runner whose agent class has an EFFORT parameter and that has no effort,
/// and one AgentAllowList row for every item, holding the AgentClass values of the runners, when no runner resolves an
/// allow-list (AD-6, AD-19). The step never saves the production and never enables an item through the director.
/// What it does with the production it finds:
///   - running, this production: restarts it, so every item gets its job again;
///   - running, Troubled or Suspended under another name: fails naming it, and stops, recovers and starts nothing;
///   - Troubled (an unclean stop), this production: recovers it, then starts it. Recovery puts the messages that were in
///     progress back on their queues and keeps the queued ones for the start, marks queued synchronous messages Suspended,
///     and discards the messages of private queues (Ens.Director);
///   - Stopped, or Suspended under this name: starts it.
/// An item runs when it is enabled and, if it has a pool, has an alive job that is not in error. An adapterless service
/// has pool size 0 and no job; it runs when it is enabled in the running production.
Class OcuTalon.Install.Step.Production Extends OcuTalon.Install.Step
{

/// The production of this installation.
Parameter PRODUCTION = "OcuTalon.Production";

/// The item that OCUTALON_EVAL switches.
Parameter EVALITEM = "EvalIn";

/// The longest the step waits for every item to run, in seconds.
Parameter WAITSECONDS = 60;

/// The longest a restart waits for the jobs to stop, in seconds.
Parameter STOPSECONDS = 30;

/// The agent runner class: its items are the ones whose model the step resolves.
Parameter RUNNERCLASS = "OcuTalon.Bridge.Operation.AgentRunner";

/// The job statuses that mean a job does not run.
Parameter DEADSTATUSES = "error,halted,terminated";

/// Writes the EvalIn switch from the environment, seeds the Model and the Effort of the runners that have none and the
/// allow-list of the agent classes, then starts the production and waits for it.
ClassMethod Run() As %Status
{
	Set sc = ..SetEval(..EvalEnabled($SYSTEM.Util.GetEnviron("OCUTALON_EVAL")))
	If $$$ISERR(sc) Quit sc
	Set sc = ..SeedModels(..#PRODUCTION)
	If $$$ISERR(sc) Quit sc
	Set sc = ..SeedEfforts(..#PRODUCTION)
	If $$$ISERR(sc) Quit sc
	Set sc = ..SeedAllowList(..#PRODUCTION)
	If $$$ISERR(sc) Quit sc
	Quit ..Start(..#WAITSECONDS)
}

/// Starts, recovers or restarts the production by the state the director reports, then polls once a second, up to wait
/// seconds, until NotRunning() is empty. Fails naming the items that do not run, or the runners that resolve no model.
ClassMethod Start(wait As %Integer = {..#WAITSECONDS}) As %Status
{
	Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
	If $$$ISERR(sc) Quit sc
	If state = $$$eProductionStateRunning {
		If name '= ..#PRODUCTION Quit ..Other(name, "running")
		Set sc = ##class(Ens.Director).RestartProduction(..#STOPSECONDS)
	} ElseIf state = $$$eProductionStateTroubled {
		If (name '= "") && (name '= ..#PRODUCTION) Quit ..Other(name, "Troubled")
		Set sc = ##class(Ens.Director).RecoverProduction()
		If $$$ISOK(sc) Set sc = ##class(Ens.Director).StartProduction(..#PRODUCTION)
	} ElseIf (state = $$$eProductionStateStopped) || (state = $$$eProductionStateSuspended) {
		If (name '= "") && (name '= ..#PRODUCTION) Quit ..Other(name, "suspended")
		Set sc = ##class(Ens.Director).StartProduction(..#PRODUCTION)
	} Else {
		Quit $SYSTEM.Status.Error(5001, ..#PRODUCTION_" cannot start: the namespace reports production state "_state_" for '"_name_"'")
	}
	If $$$ISERR(sc) Quit sc

	Set deadline = $ZHorolog + wait
	Set missing = ..NotRunning()
	While (missing '= "") && ($ZHorolog < deadline) {
		Hang 1
		Set missing = ..NotRunning()
	}
	If missing '= "" {
		Quit $SYSTEM.Status.Error(5001, ..#PRODUCTION_" did not finish starting in "_wait_" s: "_$Select(missing = (..#PRODUCTION_" is not running"): missing, 1: "these items do not run: "_missing))
	}
	Set unresolved = ..UnresolvedRunners(..#PRODUCTION)
	If unresolved '= "" {
		Quit $SYSTEM.Status.Error(5001, ..#PRODUCTION_" is running, but these agent runners resolve no model: "_unresolved)
	}
	Quit $SYSTEM.Status.OK()
}

/// The enabled items of the running production that have a pool and no alive job that is not in error, as a comma list.
/// "OcuTalon.Production is not running" when the production does not run under that name. Empty when every item runs.
ClassMethod NotRunning() As %String
{
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= ..#PRODUCTION) Quit ..#PRODUCTION_" is not running"
	Set rs = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	Set sc = rs.Execute()
	If $$$ISOK(sc) {
		While rs.Next() {
			If rs.Get("State") '= "Alive" Continue
			If $ListFind($ListFromString(..#DEADSTATUSES), rs.Get("Status")) Continue
			Set alive(rs.Get("ConfigName")) = ""
		}
	}
	Set missing = ""
	Set item = ""
	For {
		Set item = $Order($$$ConfigRoot(item))
		Quit:item=""
		If item = "%Production" Continue
		If '$Get($$$ConfigIsEnabled(item)) Continue
		If '$Get($$$ConfigPoolSize(item)) Continue
		If '$Data(alive(item)) Set missing = missing _ $Select(missing = "": "", 1: ",") _ item
	}
	Quit missing
}

/// The agent runner items of the production (AD-6): every item of class RUNNERCLASS, in the order of the definition.
/// runners is the count, and runners(i) is $ListBuild(item name, AgentClass, enabled) for the i-th runner. AgentClass is
/// the adapter setting of the item or, when it has none, the System Default Setting; enabled is 1 or 0 and counts a System
/// Default Setting row of Enabled, which overrides the flag of the definition. Fails when the definition cannot be opened.
ClassMethod Runners(production As %String, Output runners) As %Status
{
	Kill runners
	Set runners = 0
	Set config = ##class(Ens.Config.Production).%OpenId(production)
	If '$IsObject(config) Quit $SYSTEM.Status.Error(5001, production_" (its definition cannot be opened)")
	For i = 1:1:config.Items.Count() {
		Set item = config.Items.GetAt(i)
		If item.ClassName '= ..#RUNNERCLASS Continue
		Set enabled = $Select(##class(Ens.Config.DefaultSettings).%GetSetting(production, item.Name, item.ClassName, "", "Enabled", .override): override, 1: item.Enabled)
		Set agentClass = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item.Name, "AgentClass", .status)
		If $$$ISERR(status) Set agentClass = ""
		Set runners = runners + 1
		Set runners(runners) = $ListBuild(item.Name, agentClass, $Select(enabled: 1, 1: 0))
	}
	Quit $SYSTEM.Status.OK()
}

/// The enabled agent runner items of the production whose model does not resolve (AD-7), as a comma list. A production
/// whose definition cannot be opened is named with the reason, so that no runner goes unchecked.
ClassMethod UnresolvedRunners(production As %String) As %String
{
	Set unresolved = ""
	If $$$ISERR(..Runners(production, .runners)) Quit production_" (its definition cannot be opened)"
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		If '$List(runners(i), 3) Continue
		If $ClassMethod(..#RUNNERCLASS, "ResolveModel", item, production) = "" {
			Set unresolved = unresolved _ $Select(unresolved = "": "", 1: ",") _ item
		}
	}
	Quit unresolved
}

/// Writes the Model row (production, runner, any class, Model) for each runner that has no model (AD-7, AD-19): the
/// runner's item setting and every System Default Setting row of any specificity are empty, and its agent class extends
/// %AI.Agent and has a MODEL parameter, which is the value. A runner that has a model keeps it, whether the value came
/// from the definition or from a row, so a model that the settings page chose is never overwritten. A runner whose agent
/// class has no MODEL gets no row, and when it is enabled the start then fails naming it.
ClassMethod SeedModels(production As %String) As %Status
{
	Quit ..SeedRunnerRows(production, "Model", "MODEL", "Seeded by the Production install step when the runner has no model, with the MODEL of its agent class; the step never overwrites it.")
}

/// Writes the Effort row (production, runner, any class, Effort) for each runner that has no effort (AD-7, AD-19), in the
/// way SeedModels writes the Model row: the value is the EFFORT parameter of the runner's agent class. A runner that has an
/// effort keeps it, and so does a runner for which a System Default Setting row of any specificity exists, also an empty one:
/// an empty Effort is a choice, the model's default effort, so the step writes the row only when it is absent (AD-19). A
/// runner whose agent class has no EFFORT gets no row, so it asks the model for its default effort.
ClassMethod SeedEfforts(production As %String) As %Status
{
	Quit ..SeedRunnerRows(production, "Effort", "EFFORT", "Seeded by the Production install step when the runner has no effort, with the EFFORT of its agent class; the step never overwrites it.", 1)
}

/// Writes the row (production, runner, any class, setting) for each runner that has no value for the setting: the runner's
/// item setting and every System Default Setting row of any specificity are empty, and the value is the parameter of the
/// runner's agent class, which is non-empty. With keepEmpty 1, a runner for which such a row exists keeps it, also when the
/// row is empty. This is the loop of SeedModels and SeedEfforts.
ClassMethod SeedRunnerRows(production As %String, setting As %String, parameter As %String, description As %String, keepEmpty As %Boolean = 0) As %Status [ Private ]
{
	Set sc = ..Runners(production, .runners)
	For i = 1:1:runners {
		If $$$ISERR(sc) Quit
		Set item = $List(runners(i), 1)
		Set current = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, setting, .status)
		If $$$ISOK(status) && (current '= "") Continue
		If keepEmpty && ..HasRow(production, item, setting) Continue
		Set value = ..AgentParameter($List(runners(i), 2), parameter)
		If value = "" Continue
		Set sc = ..WriteDefault(production, item, setting, value, description)
	}
	Quit sc
}

/// Writes one AgentAllowList row for every item of the production (item *, any class) (AD-6, AD-19) when no runner resolves a
/// value for the setting: the value is the distinct AgentClass values of the runners, in the order of the runners and
/// comma-separated. A runner that has a value, from its item setting or from any row, keeps it, and so does a runner for which
/// a row exists that is empty (an empty list refuses every class): the settings page owns the list from then on, and a
/// developer adds an agent class to it there. No row is written when no runner has an agent class.
ClassMethod SeedAllowList(production As %String) As %Status
{
	Set sc = ..Runners(production, .runners)
	If $$$ISERR(sc) Quit sc
	Set classes = ""
	Set resolved = 0
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		Set current = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "AgentAllowList", .status)
		If ($$$ISOK(status) && (current '= "")) || ..HasRow(production, item, "AgentAllowList") {
			Set resolved = 1
			Quit
		}
		Set agentClass = $List(runners(i), 2)
		If (agentClass '= "") && '$ListFind(classes, agentClass) Set classes = classes _ $ListBuild(agentClass)
	}
	If resolved || (classes = "") Quit $$$OK
	Quit ..WriteDefault(production, "*", "AgentAllowList", $ListToString(classes, ","), "Seeded by the Production install step when no runner has an allow-list, with the AgentClass of each runner; the step never overwrites it.")
}

/// 1 when a System Default Setting row of any specificity exists for the adapter setting of the runner item, whatever its
/// value, as the running item resolves it (Ens.Config.DefaultSettings.%GetSetting).
ClassMethod HasRow(production As %String, item As %String, setting As %String) As %Boolean [ Private ]
{
	Quit ##class(Ens.Config.DefaultSettings).%GetSetting(production, item, ..#RUNNERCLASS, "Adapter", setting, .value)
}

/// The MODEL parameter of an agent class: "" when the class does not exist or does not extend %AI.Agent.
ClassMethod AgentModel(agentClass As %String) As %String
{
	Quit ..AgentParameter(agentClass, "MODEL")
}

/// The EFFORT parameter of an agent class: "" when the class does not exist, does not extend %AI.Agent or has none.
ClassMethod AgentEffort(agentClass As %String) As %String
{
	Quit ..AgentParameter(agentClass, "EFFORT")
}

/// A parameter of an agent class: "" when the class does not exist or does not extend %AI.Agent.
ClassMethod AgentParameter(agentClass As %String, name As %String) As %String [ Private ]
{
	If (agentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(agentClass) Quit ""
	If '$ClassMethod(agentClass, "%Extends", "%AI.Agent") Quit ""
	Quit $Parameter(agentClass, name)
}

/// 1 only for the text "1": OCUTALON_EVAL switches evaluation on, and anything else leaves it off.
ClassMethod EvalEnabled(value As %String) As %Boolean
{
	Quit $Select(value = "1": 1, 1: 0)
}

/// Writes the System Default Setting row (production, EvalIn, any class, Enabled) with 1 or 0. The row is structural:
/// the step writes it at every start, so a value set by hand does not last.
ClassMethod SetEval(enabled As %Boolean) As %Status
{
	Quit ..WriteDefault(..#PRODUCTION, ..#EVALITEM, "Enabled", $Select(enabled: 1, 1: 0), "Written by the Production install step at every start from OCUTALON_EVAL; do not edit.")
}

/// Writes the System Default Setting row (production, item, any class, setting) with the value and the description: it
/// changes the row when it exists and creates it otherwise. A row that matches every class applies to the director's
/// lookup of the item and to the job of the item alike.
ClassMethod WriteDefault(production As %String, item As %String, setting As %String, value As %String, description As %String) As %Status
{
	Set id = production_"||"_item_"||*||"_setting
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id, , .sc)
		If $$$ISERR(sc) Quit sc
	} Else {
		Set row = ##class(Ens.Config.DefaultSettings).%New()
		Set row.ProductionName = production
		Set row.ItemName = item
		Set row.HostClassName = "*"
		Set row.SettingName = setting
	}
	Set row.SettingValue = value
	Set row.Description = description
	Quit row.%Save()
}

/// The failure for a production other than this one that is not stopped.
ClassMethod Other(name As %String, state As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, ..#PRODUCTION_" cannot start: the production "_name_" is "_state_" in this namespace, and this step stops no other production")
}

}
