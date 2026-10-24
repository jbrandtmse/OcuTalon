Include Ensemble

/// The model-key API (FR-38; AD-6, AD-19, AD-20, AD-28). It says whether a runner's model key is set, so that a start with no key
/// shows as such and Decide never sends a request that cannot be answered. It tests for presence only: the key is an environment
/// variable that the provider resolves inside AI Hub, and no method here returns, logs, stores or raises a value of it.
/// One judgement (State) gives a provider configuration one of three states:
///   - present: the api_key is exactly one environment placeholder (@{env:NAME}, ConfigStore KEYPATTERN) whose variable is not
///     empty in this process;
///   - absent: the configuration is empty, names a Config Store entry that does not exist, holds no api_key, or its api_key is
///     exactly one placeholder whose variable is empty;
///   - unknown: every other form, which the bridge cannot judge, and every read that is refused or fails. A literal key is outside
///     AD-19, so it is unknown too.
/// State makes no Config Store call in a process that does not hold %Admin_ConfigStore:USE, the privilege of the entries (AD-19):
/// such a process, a web request, would be refused and audited.
/// Who records, who reads:
///   - Each runner records its state in its own job when it starts (Adapter.Agent.OnInit calls Record) and forgets it when it
///     stops (OnTearDown calls Forget). The record is ^OcuTalonBP.KeyState(item) = $ListBuild(state, job), a global of the private
///     database that every start rewrites.
///   - Status is the read of every process, the web request included: it reads that record and nothing else, so it is 1 only when the
///     last start of the runner recorded a present key and the runner has not stopped normally since. A runner that stopped normally, an
///     unknown state and an absent key are 0. A start that the adapter refuses records too, and a job that ends without its tear-down
///     (a killed job, a crash) leaves its record, so both read what their last start recorded until the runner starts again.
///   - Absent is Decide's read, live in the caller's process: only a key that the bridge can tell is absent blocks a request, so
///     that it never blocks a setup that it cannot judge. The runner's own failure is classified then (Decide.Classify).
/// This class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Keys
{

/// 1 when the record of the runner item says that its model key is present, otherwise 0. agent is the name of the runner item
/// (TriageAgent, DiagnosisAgent or ChatAgent). It reads ^OcuTalonBP.KeyState(agent) and nothing else. It is 0 when there is no record,
/// when the state is absent or unknown, when agent is empty and on any error. It returns 0 or 1 and never throws.
ClassMethod Status(agent As %String) As %Boolean
{
	Set present = 0
	Try {
		If $Get(agent) '= "" Set present = ($ListGet($Get(^OcuTalonBP.KeyState(agent))) = "present")
	} Catch {
		Set present = 0
	}
	Quit present
}

/// 1 when the provider configuration (the text of a ProviderConfig setting) holds a key that is present, otherwise 0: State is
/// present. An absent key and a form that is not judged (unknown) are both 0. It returns 0 or 1 and never throws.
ClassMethod Present(providerConfig As %String) As %Boolean
{
	Set present = 0
	Try {
		Set present = (..State($Get(providerConfig)) = "present")
	} Catch {
		Set present = 0
	}
	Quit present
}

/// 1 when the bridge can tell, now and in this process, that the model key of the runner item is absent, otherwise 0. It reads the
/// ProviderConfig adapter setting of the item in the active production (Ens.Director.GetAdapterSettingValue, as
/// AgentRunner.ResolveModel does). It is 1 when there is no active production, when agent is empty, when the item is not found, and
/// when State of the setting is absent. It is 0 for a present key, for an unknown state, for any other read error and for any
/// exception. It returns 0 or 1 and never throws.
ClassMethod Absent(agent As %String) As %Boolean
{
	Set absent = 0
	Try {
		Set production = ##class(Ens.Director).GetActiveProductionName()
		If (production = "") || ($Get(agent) = "") {
			Set absent = 1
		} Else {
			Set config = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_agent, "ProviderConfig", .sc)
			If $$$ISERR(sc) {
				If $SYSTEM.Status.Equals(sc, $$$EnsErrConfigItemNotFound) Set absent = 1
			} Else {
				Set absent = (..State(config) = "absent")
			}
		}
	} Catch {
		Set absent = 0
	}
	Quit absent
}

/// Records the state of the provider configuration for the runner item: ^OcuTalonBP.KeyState(item) = $ListBuild(State, $Job).
/// Only the runner adapter calls it, in the item's own job. An empty item does nothing; a failure kills the node, so that a
/// record is never half written. It never throws.
ClassMethod Record(item As %String, providerConfig As %String)
{
	If $Get(item) = "" Quit
	Try {
		Set ^OcuTalonBP.KeyState(item) = $ListBuild(..State($Get(providerConfig)), $Job)
	} Catch {
		Try {
			Kill ^OcuTalonBP.KeyState(item)
		} Catch {
		}
	}
}

/// Removes the record of the runner item when this job wrote it, so that a job never removes the record of another job. An empty
/// item, a missing record and a failure do nothing. It never throws.
ClassMethod Forget(item As %String)
{
	If $Get(item) = "" Quit
	Try {
		If $ListGet($Get(^OcuTalonBP.KeyState(item)), 2) = $Job Kill ^OcuTalonBP.KeyState(item)
	} Catch {
	}
}

/// The state of the provider configuration: "present", "absent" or "unknown". White space and control characters around the text
/// are ignored.
///   - Empty: absent.
///   - @{config:<name>}: in a process without %Admin_ConfigStore:USE, unknown, and the Config Store is not called. Otherwise the
///     entry AI.LLM.<name> is read without its secrets resolved (ConfigStore.Details) and its api_key is judged (ApiKeyState). An
///     entry that cannot be read is absent when it does not exist and unknown when it does.
///   - A JSON object: its api_key is judged.
///   - Anything else, a JSON array, text that does not parse and a reference with no name included: unknown.
/// Any exception gives unknown. It never throws and never returns a value of a key.
ClassMethod State(providerConfig As %String) As %String [ Private ]
{
	Set state = "unknown"
	Try {
		Set text = $ZStrip($Get(providerConfig), "<>WC")
		Set name = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(text)
		If text = "" {
			Set state = "absent"
		} ElseIf name '= "" {
			If $SYSTEM.Security.Check("%Admin_ConfigStore", "USE") {
				Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(name, .details)
				If $$$ISOK(sc) {
					Set state = ..ApiKeyState(details)
				} ElseIf '##class(%ConfigStore.Configuration).Exists(##class(OcuTalon.Bridge.ConfigStore).FullName(name)) {
					Set state = "absent"
				}
			}
		} ElseIf $Extract(text) = "{" {
			Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(text)
			If $IsObject(object) && object.%IsA("%Library.DynamicObject") Set state = ..ApiKeyState(object)
		}
	} Catch {
		Set state = "unknown"
	}
	Quit state
}

/// The state of the api_key of the dynamic object (see State): absent when it is unassigned, null or a string that is empty after
/// white space and control characters are removed. Exactly one @{env:NAME} placeholder is present when the variable NAME is not
/// empty in this process and absent when it is. Any other value, a literal, another placeholder form or a value that is no string,
/// is unknown.
ClassMethod ApiKeyState(object As %DynamicObject) As %String [ Private ]
{
	Set type = object.%GetTypeOf("api_key")
	If (type = "unassigned") || (type = "null") Quit "absent"
	If type '= "string" Quit "unknown"
	Set key = object.%Get("api_key")
	If $ZStrip(key, "<>WC") = "" Quit "absent"
	If '$Match(key, ##class(OcuTalon.Bridge.ConfigStore).#KEYPATTERN) Quit "unknown"
	Quit $Select($SYSTEM.Util.GetEnviron($Extract(key, 7, $Length(key) - 1)) '= "": "present", 1: "absent")
}

}
