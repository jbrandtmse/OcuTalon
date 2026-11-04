/// Tests of the Provider installer step (Story 1.1; AD-7, AD-19, DW-39). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs the Config Store entries and the ProviderConfig rows that the after-start script's Provider step wrote,
/// it runs the step again, and it deletes one entry and its row. Each test puts back the entry and the row that it changes.
///   - TestDetails: the pure builder gives, for each row of the matrix, exactly the entry of the matrix: the judges' install,
///     CI, a base URL alone with every flag value, the flag alone, a CA file; and it never gives a model or anything but the
///     literal key placeholder, also with a key in the environment;
///   - TestBadOverrides: a base URL that is not http(s)://host/.../v1/ (or that holds a user name, a query or a fragment) and a
///     CA file that does not exist fail the step, naming the variable and never the URL, and leave every entry and row as they
///     were;
///   - TestApplyCaFile: a CA file that exists, given to the step, reaches every entry as the tls block of http_config, and a
///     run from the environment puts the entries back;
///   - TestEntries: after the start, each runner of OcuTalon.Production has the entry that Details gives for this environment,
///     with the default read and edit resources, and its ProviderConfig row is @{config:OcuTalon<Agent>}, which expands to
///     the entry with the key still a placeholder;
///   - TestRerun: stale fields in an entry (a model, a base URL, a header, a typed key) are gone after Run(), which modifies
///     the entry where a create would fail, and empty read and edit resources are the default ones again;
///   - TestEntryBeforeSetting: with an entry and its row deleted, Run() writes both, and the row can only be written after the
///     entry, because the setting's validation expands @{config:}.
/// Added by Story 1.7 (AD-8, AD-19, AD-23):
///   - every entry holds the timeouts of the bridge timer in http_config, after custom_headers and tls, in the judges' install too: the
///     request timeout and the whole retry block (TestDetails for the timers 60 and 30, TestEntries and TestRerun for the stored
///     entries; TestRerun also shows that a stale part of the block is rewritten whole);
///   - TestTimerRow: a TimerSeconds row of Decide, 20 or 12, reaches every entry at the next run, as the block of that timer, and the
///     entries go back to the block of 60 when the row is gone;
///   - TestBadTimer: a TimerSeconds row that Timeouts.Check refuses (111, 11, x) fails the step, naming TimerSeconds, and every entry and
///     row stays as it was.
/// Every System Default Settings row that a test puts is put back.
Class OcuTalon.Test.Install.Provider Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The base URL of the CI mock.
Parameter MOCKURL = "http://mock:8080/v1/";

/// The literal placeholder of the key.
Parameter PLACEHOLDER = "@{env:ANTHROPIC_API_KEY}";

/// The timeouts that every entry holds under the timer of 60, as the members of http_config, written out: (60 - 10) \ 2 is 25.
Parameter BLOCK = """request_timeout_secs"":25,""retry"":{""max_retries"":1,""attempt_timeout_secs"":25,""initial_backoff_ms"":500,""max_backoff_ms"":2000}";

/// The same under the timer of 30: (30 - 10) \ 2 is 10.
Parameter BLOCK30 = """request_timeout_secs"":10,""retry"":{""max_retries"":1,""attempt_timeout_secs"":10,""initial_backoff_ms"":500,""max_backoff_ms"":2000}";

/// The same under the timer of 20: (20 - 10) \ 2 is 5.
Parameter BLOCK20 = """request_timeout_secs"":5,""retry"":{""max_retries"":1,""attempt_timeout_secs"":5,""initial_backoff_ms"":500,""max_backoff_ms"":2000}";

/// The System Default Settings rows before the test touched them (Test.Agent.RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	Quit $$$OK
}

/// Every row of the matrix that the pure builder answers, and what the entry holds. Every entry holds the timeouts of the timer
/// (the timer 60 unless one is given), after the headers and the tls block.
Method TestDetails()
{
	Set triage = "OcuTalon.Agent.Triage"
	Set head = "{""model_provider"":""anthropic"",""api_key"":""@{env:ANTHROPIC_API_KEY}"""
	Set block = ..#BLOCK
	Set agents = $ListBuild("OcuTalon.Agent.Triage", "triage", "OcuTalon.Agent.Diagnosis", "diagnosis", "OcuTalon.Agent.Chat", "chat")

	// Judges' install: no override, no base_url, and an http_config that holds the timeouts alone.
	For i = 1:2:5 {
		Do ..Expect("the judges' install for "_$List(agents, i), ..Pure($List(agents, i)), head_",""http_config"":{"_block_"}}")
	}
	// CI: the base URL and the flag 1 give base_url and the agent's own mock key.
	For i = 1:2:5 {
		Do ..Expect("CI for "_$List(agents, i), ..Pure($List(agents, i), ..#MOCKURL, "", "1"), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":"""_$List(agents, i + 1)_"""},"_block_"}}")
	}
	// Base URL alone: base_url only, whatever the flag is unless it is exactly 1 (DW-39).
	For flag = "", "0", "true", " 1", "1 ", "01", 2 {
		Do ..Expect("a base URL with the flag '"_flag_"'", ..Pure(triage, ..#MOCKURL, "", flag), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{"_block_"}}")
	}
	Do ..Expect("a base URL with no flag argument", ..Pure(triage, ..#MOCKURL), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{"_block_"}}")
	// Flag alone: the header and no base_url (owner value 11).
	Do ..Expect("the flag alone", ..Pure(triage, "", "", "1"), head_",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""},"_block_"}}")
	// CA file: the full tls block with both accept_invalid_* flags false.
	Set tls = """tls"":{""ca_certificates"":[""/opt/ca/extra.pem""],""accept_invalid_certs"":false,""accept_invalid_hostnames"":false}"
	Do ..Expect("a CA file", ..Pure(triage, "", "/opt/ca/extra.pem", ""), head_",""http_config"":{"_tls_","_block_"}}")
	Do ..Expect("a CA file with the base URL and the flag", ..Pure(triage, ..#MOCKURL, "/opt/ca/extra.pem", "1"), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""},"_tls_","_block_"}}")
	// An agent class with no MOCKKEY gets no header.
	Do ..Expect("an agent class that does not exist", ..Pure("OcuTalon.Agent.ZzNoSuchAgent", ..#MOCKURL, "", "1"), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{"_block_"}}")

	// The timer: 30 gives 10, in the judges' install and with every override, and the whole retry block either way.
	Set block30 = ..#BLOCK30
	For i = 1:2:5 {
		Do ..Expect("the judges' install for "_$List(agents, i)_" under a timer of 30", ..Pure($List(agents, i), "", "", "", 30), head_",""http_config"":{"_block30_"}}")
	}
	Do ..Expect("CI under a timer of 30", ..Pure(triage, ..#MOCKURL, "/opt/ca/extra.pem", "1", 30), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""},"_tls_","_block30_"}}")
	Do ..Expect("a timer of 20", ..Pure(triage, "", "", "", 20), head_",""http_config"":{"_..#BLOCK20_"}}")
	Do ..Expect("a timer of 60 given as text", ..Pure(triage, "", "", "", "60"), head_",""http_config"":{"_block_"}}")
	// A timer that Timeouts.Check refuses gives no timeouts at all, never a part of the block (the step refuses such a timer before it writes).
	For timer = 11, 111, "x", "" {
		Do ..Expect("a timer of '"_timer_"'", ..Pure(triage, "", "", "", timer), head_"}")
	}

	// Never a model, and never anything but the literal placeholder, whatever the overrides are; each combination of the
	// overrides gives its own entry.
	Kill seen
	For url = "", ..#MOCKURL {
		For file = "", "/opt/ca/extra.pem" {
			For flag = "", "1" {
				Set details = ..Pure(triage, url, file, flag)
				Set seen(details.%ToJSON()) = ""
				Do $$$AssertTrue('details.%IsDefined("model"), "no model: "_url_" "_file_" "_flag)
				Do $$$AssertEquals(details."api_key", ..#PLACEHOLDER, "the key is the literal placeholder: "_url_" "_file_" "_flag)
				Do $$$AssertEquals($Length(details.%ToJSON(), "@{"), 2, "and the only @{ is the placeholder's: "_url_" "_file_" "_flag)
				Do $$$AssertEquals(details."http_config".%GetTypeOf("request_timeout_secs")_"|"_details."http_config".retry.%Size(), "number|4", "and the request timeout and the four members of the retry block are there: "_url_" "_file_" "_flag)
			}
		}
	}
	Set distinct = 0
	Set json = ""
	For {
		Set json = $Order(seen(json))
		Quit:json=""
		Set distinct = distinct + 1
	}
	Do $$$AssertEquals(distinct, 8, "the eight combinations of the overrides give eight different entries")

	// The key's value is never read: with a key in the environment the entry still holds the placeholder.
	Set fake = "ocutalon-details-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set variable = "ANTHROPIC_API_KEY"
	Set had = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable)
	Set previous = $SYSTEM.Util.GetEnviron(variable)
	Try {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, fake)
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron(variable), fake, "the fake key is in the environment of the process")
		Do ..Expect("a key in the environment", ..Pure(triage, ..#MOCKURL, "", "1"), head_",""base_url"":"""_..#MOCKURL_""",""http_config"":{""custom_headers"":{""x-ocutalon-mockkey"":""triage""},"_block_"}}")
		Do $$$AssertTrue(..Pure(triage).%ToJSON() '[ fake, "and the details hold no key")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the details are built without an exception")
	}
	If had {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(variable, previous)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(variable)
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.KeyScan).HasEnv(variable), had, "the key variable is as it was found")
}

/// A bad base URL or a missing CA file fails the step, naming the variable (and the path), and nothing is written.
Method TestBadOverrides()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	For url = "", ..#MOCKURL, "https://api.anthropic.com/v1/", "http://host/prefix/v1/", "HTTPS://Host/v1/" {
		Do $$$AssertStatusOK($ClassMethod(provider, "CheckBaseUrl", url), "the base URL '"_url_"' is accepted")
	}
	For url = "api.anthropic.com/v1/", "ftp://host/v1/", "http://host/v1", "http://host/", "http://host/v1/x", " http://host/v1/", "http:///v1/", "http://v1/", "http://ho st/v1/", "http://user:secret-pass@host/v1/", "http://host/v1/?token=secret-pass", "http://host/?token=secret-pass/v1/", "http://host/#secret-pass/v1/", "http://host/a@b/v1/" {
		Set sc = $ClassMethod(provider, "CheckBaseUrl", url)
		Do $$$AssertStatusNotOK(sc, "the base URL '"_url_"' is refused")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ "OCUTALON_MODEL_BASE_URL", "and the error names OCUTALON_MODEL_BASE_URL")
		Do $$$AssertTrue(text '[ "secret-pass", "and holds none of its value")
		Do $$$AssertTrue(text '[ url, "and not the URL")
	}
	Set file = ##class(%File).TempFilename("pem")
	Do $$$AssertStatusOK($ClassMethod(provider, "CheckCaFile", ""), "no CA file is accepted")
	Do $$$AssertStatusOK($ClassMethod(provider, "CheckCaFile", file), "a CA file that exists is accepted")
	Do ##class(%File).Delete(file)
	Set sc = $ClassMethod(provider, "CheckCaFile", file)
	Do $$$AssertStatusNotOK(sc, "a CA file that does not exist is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_EXTRA_CA_FILE", "and the error names OCUTALON_EXTRA_CA_FILE")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ file, "and the path")

	Set before = ..State()
	Do ..AssertWritten("before the runs")
	Set sc = $ClassMethod(provider, "Apply", "http://host/v2/", "", "1")
	Do $$$AssertStatusNotOK(sc, "the step fails for a bad base URL")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_MODEL_BASE_URL", "naming the variable")
	Do $$$AssertEquals(..State(), before, "and writes nothing")
	Set sc = $ClassMethod(provider, "Apply", ..#MOCKURL, file, "1")
	Do $$$AssertStatusNotOK(sc, "the step fails for a missing CA file")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("OCUTALON_EXTRA_CA_FILE names a file that does not exist: "_file), "naming the variable and the path")
	Do $$$AssertEquals(..State(), before, "and writes nothing")
}

/// A CA file that exists, given to Apply, reaches every entry: the stored entry is the entry of Details for the file, with the
/// tls block of http_config and both accept_invalid_* flags false. A run from the environment then puts the entries back.
Method TestApplyCaFile()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	Set url = $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")
	Set flag = $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")
	Set file = ##class(%File).TempFilename("pem")
	Set before = ..State()
	Do ..AssertWritten("before the run")
	Try {
		Do $$$AssertStatusOK($ClassMethod(provider, "Apply", url, file, flag), "Apply accepts a CA file that exists")
		For class = "OcuTalon.Agent.Triage", "OcuTalon.Agent.Diagnosis", "OcuTalon.Agent.Chat" {
			Set name = "OcuTalon"_$Piece(class, ".", $Length(class, "."))
			Set stored = ..EntryJson(name)
			Do $$$AssertEquals(stored, $ClassMethod(provider, "Details", class, url, file, flag, ..Timer()).%ToJSON(), name_" is the entry of Details for the file")
			Set tls = {}.%FromJSON(stored)."http_config".tls
			Do $$$AssertEquals(tls."ca_certificates".%Get(0), file, name_" lists the file as its CA certificate")
			Do $$$AssertEquals(tls."accept_invalid_certs", 0, name_" accepts no invalid certificate")
			Do $$$AssertEquals(tls."accept_invalid_hostnames", 0, name_" accepts no invalid host name")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK($ClassMethod(provider, "Run"), "a run from the environment puts the entries back")
	Do $$$AssertEquals(..State(), before, "and the entries and rows are as they were")
}

/// After the start, each runner has the entry of Details for this environment, with the default resources, and its
/// ProviderConfig row names the entry.
Method TestEntries()
{
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(..#PRODUCTION, .runners)
	Do $$$AssertStatusOK(sc, "the runners are read")
	Do $$$AssertEquals(runners, 3, "there are three runners")
	Do $$$AssertStatusOK(##class(%AI.Utils.SettingStore).RegisterDefaults(), "the setting stores are registered")
	Set names = ""
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		Set class = $List(runners(i), 2)
		Set name = "OcuTalon"_$Piece(class, ".", $Length(class, "."))
		Set names = names _ $Select(names = "": "", 1: ",") _ name
		Set fqn = "AI.LLM."_name
		Do $$$AssertTrue(##class(%ConfigStore.Configuration).Exists(fqn), item_" has the entry "_fqn)
		Set sc = ##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 0)
		Do $$$AssertStatusOK(sc, "the entry "_fqn_" is read")
		If $$$ISERR(sc) Continue
		Do $$$AssertEquals(details.%ToJSON(), ..ForEnv(class).%ToJSON(), fqn_" is the entry of Details for this environment")
		Set derived = ##class(OcuTalon.Bridge.Timeouts).Derive(..Timer()).%Get("http_config")
		Do $$$AssertTrue($IsObject(derived) && $IsObject(details."http_config"), fqn_" has an http_config, and the timer of Decide gives a block")
		If $IsObject(derived) && $IsObject(details."http_config") {
			Do $$$AssertEquals(details."http_config"."request_timeout_secs", derived."request_timeout_secs", fqn_" holds the request timeout of the timer of Decide")
			Set retry = details."http_config".%Get("retry")
			Do $$$AssertEquals($Select($IsObject(retry): retry.%ToJSON(), 1: "none"), derived.retry.%ToJSON(), "and the whole retry block of that timer")
		}
		Do $$$AssertTrue('details.%IsDefined("model"), fqn_" has no model")
		Do $$$AssertEquals(details."api_key", ..#PLACEHOLDER, fqn_" holds the literal placeholder")
		Do $$$AssertEquals(..Resources(fqn), "%Admin_ConfigStore %Admin_ConfigStore", fqn_" has the default read and edit resources")
		Set row = ..Row(item)
		Do $$$AssertEquals(row, "@{config:"_name_"}", item_"'s ProviderConfig row names the entry")
		Set expanded = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand(row))
		Do $$$AssertEquals(expanded."api_key", ..#PLACEHOLDER, "and expands to the entry with the key still a placeholder")
	}
	Do $$$AssertEquals(names, "OcuTalonTriage,OcuTalonDiagnosis,OcuTalonChat", "the entries are those of the three agents, in the order of the runners")
}

/// Stale fields in the Triage entry are gone after Run(): the entry is modified, where a create would fail, and gets the
/// default read and edit resources again.
Method TestRerun()
{
	Set fqn = "AI.LLM.OcuTalonTriage"
	Set expected = ..ForEnv("OcuTalon.Agent.Triage").%ToJSON()
	Set found = ##class(%ConfigStore.Configuration).Exists(fqn)
	Do $$$AssertTrue(found, "the Triage entry exists")
	If 'found Quit
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(fqn, .snapshot, 0, 0), "the entry is read")
	Set resources = ..Resources(fqn)
	Try {
		Set stale = {}.%FromJSON(snapshot.%ToJSON())
		Do stale.%Set("model", "claude-opus-stale")
		Do stale.%Set("base_url", "http://stale.invalid/v1/")
		Do stale.%Set("api_key", "ocutalon-stale-typed-value")
		Do stale.%Set("http_config", {"custom_headers": {"x-ocutalon-mockkey": "stale"}, "request_timeout_secs": 99, "retry": {"max_retries": 7}})
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Modify(fqn, stale, , , "", ""), "stale fields and empty resources are written into the entry")
		Do $$$AssertTrue(..EntryJson("OcuTalonTriage") [ "claude-opus-stale", "the entry now holds the stale model")
		Do $$$AssertEquals(..Resources(fqn), " ", "and anyone may read and edit it")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "Run() modifies the existing entries")
		Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), expected, "and the details are exactly the computed object again, the stale request timeout and retry block rewritten whole")
		Do $$$AssertEquals(..Resources(fqn), "%Admin_ConfigStore %Admin_ConfigStore", "and the read and edit resources are the default again")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(%ConfigStore.Configuration).Modify(fqn, , , , $Piece(resources, " ", 1), $Piece(resources, " ", 2))
	Do ..RestoreEntry("OcuTalonTriage", snapshot)
	Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), snapshot.%ToJSON(), "the entry is as it was found")
	Do $$$AssertEquals(..Resources(fqn), resources, "with the resources it had")
}

/// With the Triage entry and its row deleted, Run() writes both. The row is validated against the entry, so it only saves
/// when the entry is written first.
Method TestEntryBeforeSetting()
{
	Set fqn = "AI.LLM.OcuTalonTriage"
	Set id = ..#PRODUCTION_"||TriageAgent||*||ProviderConfig"
	Set found = ##class(%ConfigStore.Configuration).Exists(fqn) && ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	Do $$$AssertTrue(found, "the Triage entry and its ProviderConfig row exist")
	If 'found Quit
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(fqn, .snapshot, 0, 0), "the entry is read")
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Set rowValue = row.SettingValue
	Set rowDescription = row.Description
	Try {
		Do $$$AssertStatusOK(##class(Ens.Config.DefaultSettings).%DeleteId(id), "the row is deleted")
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Delete(fqn), "and the entry")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "Run() writes both again")
		Do $$$AssertTrue(##class(%ConfigStore.Configuration).Exists(fqn), "the entry is back")
		Do $$$AssertEquals(..Row("TriageAgent"), "@{config:OcuTalonTriage}", "and so is the row")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..RestoreEntry("OcuTalonTriage", snapshot)
	Do ..RestoreRow(id, rowValue, rowDescription)
	Do $$$AssertEquals(..EntryJson("OcuTalonTriage"), snapshot.%ToJSON(), "the entry is as it was found")
	Do $$$AssertEquals(..Row("TriageAgent"), rowValue, "and so is the row")
}

/// A TimerSeconds row of Decide reaches every entry at the next run (AD-8, AD-23): a row of 20 gives the block of 20, 12 the block of 12 (a
/// request timeout of 1), the entry being the entry of Details for that timer and nothing else; with the row gone, the next run gives the
/// block of 60 again. The ProviderConfig rows stay as they were.
Method TestTimerRow()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set url = $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")
	Set flag = $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")
	Set file = $SYSTEM.Util.GetEnviron("OCUTALON_EXTRA_CA_FILE")
	Set saved = ..SavedRows
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "TimerSeconds")
	Set ..SavedRows = saved
	Do $ClassMethod(fixture, "RestoreDefault", $ListBuild("Decide", "TimerSeconds", 0))
	Set before = ..State()
	Do ..AssertWritten("before the runs")
	Try {
		Do $$$AssertEquals(..Timer(), 60, "with no row the timer is 60")
		For timer = 20, 12 {
			Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", timer), "a TimerSeconds row of "_timer_" is written")
			Do $$$AssertStatusOK($ClassMethod(provider, "Run"), "the step runs")
			Set attempt = (timer - 10) \ 2
			For class = "OcuTalon.Agent.Triage", "OcuTalon.Agent.Diagnosis", "OcuTalon.Agent.Chat" {
				Set name = "OcuTalon"_$Piece(class, ".", $Length(class, "."))
				Set stored = {}.%FromJSON(..EntryJson(name))
				Do $$$AssertEquals(stored.%Get("http_config")."request_timeout_secs", attempt, name_" has the request timeout of "_timer_": "_attempt)
				Do $$$AssertEquals(stored.%Get("http_config").retry."attempt_timeout_secs"_"|"_stored.%Get("http_config").retry."max_retries"_"|"_stored.%Get("http_config").retry."max_backoff_ms", attempt_"|1|2000", name_" has the whole retry block of "_timer)
				Do $$$AssertEquals(stored.%Get("http_config").%Size(), 2 + (flag = 1) + (file '= ""), name_" has nothing else in http_config than the headers and tls of the environment, and the two timeouts")
				Do $$$AssertEquals(..EntryJson(name), $ClassMethod(provider, "Details", class, url, file, flag, timer).%ToJSON(), name_" is the entry of Details for the timer "_timer)
			}
		}
		Do $ClassMethod(fixture, "RestoreDefault", $ListBuild("Decide", "TimerSeconds", 0))
		Do $$$AssertStatusOK($ClassMethod(provider, "Run"), "with the row gone the step runs")
		Do $$$AssertEquals(..State(), before, "and every entry and row is as it was: the block of 60 again")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
}

/// A TimerSeconds row that Timeouts.Check refuses fails the step, naming TimerSeconds, and writes no entry and no row: every entry and row
/// stays as it was (AD-8, AD-23). The rows are 111, 11 and x, the last written by SQL as a hand edit could write it.
Method TestBadTimer()
{
	Set provider = "OcuTalon.Install.Step.Provider"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set url = $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL")
	Set flag = $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER")
	Set saved = ..SavedRows
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "TimerSeconds")
	Set ..SavedRows = saved
	Do $ClassMethod(fixture, "RestoreDefault", $ListBuild("Decide", "TimerSeconds", 0))
	Set before = ..State()
	Do ..AssertWritten("before the runs")
	For timer = 111, 11, "x" {
		Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "TimerSeconds", timer), "a TimerSeconds row of '"_timer_"' is written")
		Set sc = $ClassMethod(provider, "Apply", url, "", flag)
		Do $$$AssertStatusNotOK(sc, "the step fails for a timer of '"_timer_"'")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue((text [ "TimerSeconds") && (text [ "12 to 110"), "naming TimerSeconds and the range: "_text)
		Do $$$AssertEquals(..State(), before, "and writes no entry and no row")
	}
	Do $ClassMethod(fixture, "RestoreDefault", $ListBuild("Decide", "TimerSeconds", 0))
	Do $$$AssertStatusOK($ClassMethod(provider, "Run"), "with the row gone the step runs")
	Do $$$AssertEquals(..State(), before, "and every entry and row is as it was")
}

/// --- helpers ---
/// The timer that the step reads: the TimerSeconds of Decide in OcuTalon.Production.
ClassMethod Timer() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide")
}

/// Details of the Provider step for an agent class under the overrides given, none by default, and the timer 60 unless one is given. The
/// builder reads no environment.
ClassMethod Pure(class As %String, url As %String = "", file As %String = "", flag As %String = "", timer As %String = 60) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Provider).Details(class, url, file, flag, timer)
}

/// Details of the Provider step for an agent class under the overrides of this environment and the timer of Decide.
ClassMethod ForEnv(class As %String) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Provider).Details(class, $SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_EXTRA_CA_FILE"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), ..Timer())
}

/// Asserts that the object is, field for field and in order, the JSON text.
Method Expect(label As %String, actual As %DynamicObject, json As %String) [ Private ]
{
	Do $$$AssertEquals(actual.%ToJSON(), {}.%FromJSON(json).%ToJSON(), label)
}

/// The details of an entry of AI.LLM as JSON text, or "" when there is no such entry.
ClassMethod EntryJson(name As %String) As %String
{
	If $$$ISERR(##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_name, .details, 0, 0)) Quit ""
	Quit details.%ToJSON()
}

/// The read and edit resources of an entry, separated by a space, or "" when there is no such entry.
ClassMethod Resources(fqn As %String) As %String [ Private ]
{
	If $$$ISERR(##class(%ConfigStore.Configuration).Get(fqn, .entry)) Quit ""
	Quit entry.ReadResource_" "_entry.EditResource
}

/// The value of the ProviderConfig row of a runner, or "" when there is none.
ClassMethod Row(item As %String) As %String
{
	Set id = ..#PRODUCTION_"||"_item_"||*||ProviderConfig"
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit ""
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// Asserts that each runner's entry and its ProviderConfig row exist.
Method AssertWritten(when As %String) [ Private ]
{
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Do $$$AssertTrue(..EntryJson("OcuTalon"_$Extract(item, 1, $Length(item) - 5)) '= "", "the entry of "_item_" exists "_when)
		Do $$$AssertTrue(..Row(item) '= "", "and so does its ProviderConfig row")
	}
}

/// Every entry and row that the step writes, as one text.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Set name = "OcuTalon"_$Extract(item, 1, $Length(item) - 5)
		Set state = state _ $Char(10) _ name _ " " _ ..EntryJson(name) _ " " _ ..Row(item)
	}
	Quit state
}

/// Puts an entry back as it was found: its details modified when it exists, created with the description otherwise.
ClassMethod RestoreEntry(name As %String, details As %DynamicObject, description As %String = "")
{
	If '$IsObject($Get(details)) Quit
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_name) {
		Do ##class(%ConfigStore.Configuration).Modify("AI.LLM."_name, details)
	} Else {
		Do ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", name, details, "", description)
	}
}

/// Puts the System Default Setting row (production||item||*||setting) back with its value and description.
ClassMethod RestoreRow(id As %String, value As %String, description As %String)
{
	Do ##class(OcuTalon.Install.Step.Production).WriteDefault($Piece(id, "||", 1), $Piece(id, "||", 2), $Piece(id, "||", 4), value, description)
}

}
