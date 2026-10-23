Include Ensemble

/// The timeout API of the bridge (AD-5, AD-8, AD-19). Everything that depends on the bridge timer, the number of seconds that Decide
/// waits (the TimerSeconds setting of Decide), is derived here, so that no other class holds a second copy of a number.
///   - Check says whether a timer is allowed: a whole number of seconds from Decide.#MINTIMER to Decide.#MAXTIMER (AD-5).
///   - Derive gives what AI Hub needs for a timer that Check accepts, or an empty object for any other value (AD-8, S2, S18):
///     timeout_ms, the timer minus 5 seconds, which bounds the tool loop (it does not stop a request in flight); and the block
///     http_config for the provider's Config Store entry: request_timeout_secs, (timer - 10) \ 2, and the whole retry block, never
///     a part of it, because AI Hub waits for a Retry-After as long as 30 seconds with a missing or partial block. The worst case of
///     one Chat request is then (max_retries + 1) x attempt_timeout_secs + max_retries x (max_backoff_ms in seconds), which is at
///     most the timer minus 8 seconds: 52 seconds for 60.
///   - Apply is the one run-time change of the timer: it writes the setting, merges Derive's block into the Config Store entry of
///     every runner and restarts Decide and the runners, so that the setting, the entries and the jobs never disagree. Its first
///     caller is the settings operation of Story 17.4.
/// The Provider install step derives the same block at every start (AD-19), from the setting that Apply writes. This class names no
/// other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Timeouts
{

/// The longest Apply waits for the restarted items to run again, in seconds.
Parameter RESTARTSECONDS = 60;

/// The words of the description of the System Default Settings row that Apply writes.
Parameter ROWDESCRIPTION = "Written by OcuTalon.Bridge.Timeouts.Apply together with the Config Store entries of the runners; change the timer through Apply.";

/// OK for a whole number (digits only) from Decide.#MINTIMER to Decide.#MAXTIMER; otherwise an error that names the setting
/// TimerSeconds of Decide and the range, with the value cut to 40 characters and redacted. It is pure and never throws.
ClassMethod Check(timer As %String) As %Status
{
	Set timer = $Get(timer)
	Set min = ##class(OcuTalon.Bridge.Process.Decide).#MINTIMER
	Set max = ##class(OcuTalon.Bridge.Process.Decide).#MAXTIMER
	If (timer ? 1.N) && (+timer '< min) && (+timer '> max) Quit $$$OK
	Quit $$$ERROR($$$GeneralError, "The setting TimerSeconds of Decide is '"_##class(OcuTalon.Bridge.Redact).Text($Extract(timer, 1, 40))_"'; it must be a whole number of seconds from "_min_" to "_max)
}

/// What the timer (in whole seconds) gives, as {"timeout_ms", "http_config": {"request_timeout_secs", "retry": {"max_retries",
/// "attempt_timeout_secs", "initial_backoff_ms", "max_backoff_ms"}}}: timeout_ms is (timer - 5) x 1000, request_timeout_secs and
/// attempt_timeout_secs are (timer - 10) \ 2, max_retries is 1, initial_backoff_ms 500 and max_backoff_ms 2000. A timer that Check
/// refuses gives {}. It is pure.
ClassMethod Derive(timer As %Integer) As %DynamicObject
{
	If $$$ISERR(..Check($Get(timer))) Quit {}
	Set attempt = (timer - 10) \ 2
	Set retry = {}
	Do retry.%Set("max_retries", 1, "number")
	Do retry.%Set("attempt_timeout_secs", attempt, "number")
	Do retry.%Set("initial_backoff_ms", 500, "number")
	Do retry.%Set("max_backoff_ms", 2000, "number")
	Set httpConfig = {}
	Do httpConfig.%Set("request_timeout_secs", attempt, "number")
	Do httpConfig.%Set("retry", retry)
	Set derived = {}
	Do derived.%Set("timeout_ms", (timer - 5) * 1000, "number")
	Do derived.%Set("http_config", httpConfig)
	Quit derived
}

/// Changes the bridge timer of the production (an empty production is the active one), in this order:
///   1. Check(timer);
///   2. every runner item of Decide.#RUNNERS that the production has must have a ProviderConfig of the form @{config:<name>} whose
///      Config Store entry exists, and Decide must read its TimerSeconds; all are checked before anything is written;
///   3. the System Default Settings row of TimerSeconds for the item Decide is written (Ext.Accessor.WriteDefault). When the
///      timer that Ext.Accessor.ValueFor then reads is not the one given, because the production definition sets it, the row is put
///      back and the call fails, naming the setting;
///   4. Derive(timer).http_config is merged into the http_config of the entry of each runner (ConfigStore.Merge), so that its api_key, base_url,
///      custom_headers and tls stay;
///   5. when the production runs, Decide and each runner item that has a job are stopped and started again
///      (Ens.Director.TempStopConfigItem), and the call returns once every one of them has a new job: within RESTARTSECONDS, or with
///      an error that names the items that did not start. The writes stay then, and the next restart applies them. Decisions in flight
///      when the items restart end at their timers.
/// A refusal (steps 1 to 3) changes nothing and names the setting or the runner. A write that fails in step 4 leaves what was
/// written, and the Provider install step derives every entry from the row at the next start. No error, warning or return value
/// holds an entry's details: the text of another component's error passes Redact.Text.
ClassMethod Apply(timer As %Integer, production As %String = "") As %Status
{
	Set sc = ..Check($Get(timer))
	If $$$ISERR(sc) Quit sc
	Set timer = +timer
	If production = "" Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" Quit $$$ERROR($$$GeneralError, "No production is named and none is active, so the setting TimerSeconds of Decide cannot be changed")
	Set sc = ..Entries(production, .runners)
	If $$$ISERR(sc) Quit sc
	Do ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", production, "Decide", .sc)
	If $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The setting TimerSeconds of Decide in "_production_" cannot be read: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))

	Set id = production_"||Decide||*||TimerSeconds"
	Set existed = ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	If existed {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Set was = $ListBuild(row.SettingValue, row.Description)
	}
	Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, "Decide", "TimerSeconds", timer, ..#ROWDESCRIPTION)
	If $$$ISERR(sc) Quit sc
	Set read = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", production, "Decide", .readSc)
	If $$$ISERR(readSc) || (read '= timer) {
		If existed {
			Do ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(production, "Decide", "TimerSeconds", $List(was, 1), $List(was, 2))
		} Else {
			Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
		}
		Quit $$$ERROR($$$GeneralError, "The setting TimerSeconds of Decide in "_production_" stays at '"_##class(OcuTalon.Bridge.Redact).Text($Extract(read, 1, 40))_"' whatever is written to the System Default Settings, because the production definition sets it, so the timer is not changed")
	}

	For i = 1:1:$ListLength(runners) {
		Set runner = $List(runners, i)
		Set fields = {}
		Do fields.%Set("http_config", ..Derive(timer).%Get("http_config"))
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Merge($List(runner, 2), fields)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The Config Store entry of the runner "_$List(runner, 1)_" was not changed: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	Quit ..Restart(production, runners)
}

/// The runner items of Decide.#RUNNERS that the production has, as a list of $ListBuild(item, entry name). An item that the
/// production lacks is left out. A runner whose ProviderConfig is not exactly @{config:<name>} (ConfigStore.EntryOf), or whose entry
/// does not exist, is an error that names the runner (and the entry), never a value of its configuration or its details.
ClassMethod Entries(production As %String, Output runners As %List) As %Status
{
	Set runners = ""
	Set sc = $$$OK
	Set pairs = $ListFromString(##class(OcuTalon.Bridge.Process.Decide).#RUNNERS)
	Set position = 0
	While $ListNext(pairs, position, pair) && $$$ISOK(sc) {
		Set item = $Piece(pair, ":", 2)
		Set config = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "ProviderConfig", .status)
		If $$$ISERR(status) {
			If '$SYSTEM.Status.Equals(status, $$$EnsErrConfigItemNotFound) {
				Set sc = $$$ERROR($$$GeneralError, "The ProviderConfig of the runner "_item_" cannot be read, so the timer is not changed: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(status)))
			}
			Continue
		}
		Set entry = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(config)
		If entry = "" {
			Set sc = $$$ERROR($$$GeneralError, "The runner "_item_" has no ProviderConfig of the form @{config:<name>}, so the timer cannot reach its Config Store entry and is not changed")
		} ElseIf '##class(%ConfigStore.Configuration).Exists(##class(OcuTalon.Bridge.ConfigStore).FullName(entry)) {
			Set sc = $$$ERROR($$$GeneralError, "The runner "_item_" names the Config Store entry "_##class(OcuTalon.Bridge.ConfigStore).FullName(entry)_", which does not exist, so the timer is not changed")
		} Else {
			Set runners = runners _ $ListBuild($ListBuild(item, entry))
		}
	}
	Quit sc
}

/// When the production runs, stops Decide and each runner item that has a job and starts it again (Ens.Director.TempStopConfigItem), and
/// waits, up to RESTARTSECONDS, until every one of them has a job that is not one of the jobs it had. An item with no job is not
/// restarted: it is not running, and its next start applies the writes. A stop or a start that fails lifts the temporary stop again, so
/// that the item is not left stopped. The error names the item that could not be stopped or started, or the items that did not run
/// again in time. Decisions in flight when an item restarts end at their timers.
ClassMethod Restart(production As %String, runners As %List) As %Status
{
	If '##class(Ens.Director).IsProductionRunning(.running) || (running '= production) Quit $$$OK
	Set items = $ListBuild("Decide")
	For i = 1:1:$ListLength(runners) {
		Set items = items _ $ListBuild($List($List(runners, i), 1))
	}
	Set restarted = ""
	Set sc = $$$OK
	Set position = 0
	While $ListNext(items, position, item) && $$$ISOK(sc) {
		Set old = ..Jobs(item)
		If old = "" Continue
		Set sc = ##class(Ens.Director).TempStopConfigItem(production_"||"_item, 1)
		If $$$ISOK(sc) Set sc = ##class(Ens.Director).TempStopConfigItem(production_"||"_item, 0)
		If $$$ISERR(sc) {
			Do ##class(Ens.Director).TempStopConfigItem(production_"||"_item, 0)
			Set sc = $$$ERROR($$$GeneralError, "The item "_item_" could not be restarted, so the new timer applies at the next restart: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
		}
		Set restarted = restarted _ $ListBuild($ListBuild(item, old))
	}
	If $$$ISERR(sc) Quit sc
	Set deadline = $ZHorolog + ..#RESTARTSECONDS
	While 1 {
		Set missing = ""
		For i = 1:1:$ListLength(restarted) {
			Set one = $List(restarted, i)
			If '..HasNewJob($List(one, 1), $List(one, 2)) Set missing = missing _ $ListBuild($List(one, 1))
		}
		If (missing = "") || ($ZHorolog '< deadline) Quit
		Hang 1
	}
	If missing '= "" {
		Quit $$$ERROR($$$GeneralError, "These items did not run again within "_..#RESTARTSECONDS_" seconds, so the new timer applies at their next start: "_$ListToString(missing, ", "))
	}
	Quit $$$OK
}

/// 1 when the item has an alive job that is not in old, a list of job ids.
ClassMethod HasNewJob(item As %String, old As %List) As %Boolean [ Private ]
{
	Set current = ..Jobs(item)
	Set fresh = 0
	Set position = 0
	While $ListNext(current, position, job) {
		If '$ListFind(old, job) Set fresh = 1
	}
	Quit fresh
}

/// The alive jobs of the item that are not in error, as a list of job ids ("" for none).
ClassMethod Jobs(item As %String) As %List [ Private ]
{
	Set jobs = ""
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	If $$$ISERR(result.Execute()) Quit jobs
	While result.Next() {
		If (result.Get("ConfigName") '= item) || (result.Get("State") '= "Alive") Continue
		If $ListFind($ListBuild("error", "halted", "terminated"), result.Get("Status")) Continue
		Set jobs = jobs _ $ListBuild(result.Get("Job"))
	}
	Quit jobs
}

}
