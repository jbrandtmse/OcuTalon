/// Tests of the model-key API (AD-6, AD-19, AD-20, AD-28; FR-38): Keys.Present, Keys.Absent, Keys.Record, Keys.Forget and Keys.Status,
/// in process, with one job of their own (TestRecord). They need no mock and send nothing. THROWAWAY STACKS AND CI ONLY (Rule 21):
/// TestStatus puts the entries of the runners back to the placeholder of the Provider step and restarts the three runners of the running
/// OcuTalon.Production (RunnerFixture.RestoreKeys). They read the environment of this process and, for the entries, the Config Store,
/// where the test creates one entry of its own, AI.LLM.OcuTalonZzKeys<n> (n from ^OcuTalonTest("Keys","n"), never reset), after
/// RebuildRegistry(), and deletes it at the end. The fixture records are ^OcuTalonBP.KeyState(ZzKeysItem...), removed by prefix before
/// and after the run. The entry holds placeholders and one literal word, never a key, and no test writes a real key anywhere.
/// A key is present only for exactly one @{env:NAME} placeholder whose variable is set; a form that the bridge cannot judge (unknown) is
/// not present either, so Present is 0 for it.
///   - TestPresent: Present of "", {}, {"api_key":""}, {"api_key":"@{env:PATH}"}, {"api_key":"@{env:ZZOCUTALONNOSUCHVAR}"},
///     {"api_key":"literal-value"}, @{config:ZzNoSuchEntry} and "not json" is 0, 0, 0, 1, 0, 0, 0 and 0; every result is exactly 0 or 1;
///     no row of the event log written since the test began holds the value of PATH; a control shows that PATH is set in this process and
///     that the other variable is not;
///   - TestPresentForms: further forms that Present has to judge, an api_key that is not one placeholder, a null or non-string api_key,
///     a JSON array, white space around the text, and a text that starts like JSON and is not: none of the forms that are not judged is
///     present;
///   - TestPresentEntry: @{config:<name>} reads the entry without resolving it: an api_key placeholder whose variable is set is 1,
///     one whose variable is not set is 0, an entry with no api_key is 0, a literal is 0, and the full name of the entry works too;
///   - TestStatus: Status of an item that is not in the production is 0 (and of an empty name), and the status of each runner item of the
///     active production, whose entries are at the placeholder of the Provider step (RestoreKeys restarts the three runners), is the
///     record that its job wrote at its start and equals Present of its ProviderConfig; every result is exactly 0 or 1;
///   - TestRecord: Record of the six configurations, and the state each one leaves in the record, which is the state word and the job
///     number and nothing else (no part of the value of PATH, no descendant node); Status is 1 only for present; Forget
///     removes the record of its own job and leaves the record of another job; an item never recorded, an empty item and a node that is
///     no record are 0; no row of the event log written since the test began holds the value of PATH;
///   - TestStatusReadsOnlyTheRecord: the code of Status names ^OcuTalonBP.KeyState and has no ##class( and no .. call, no $SYSTEM. call,
///     no $ZF(, $ZU( or $ZUTIL( call, no indirection, Xecute or X command, no embedded SQL or macro, and no global but the record, so that
///     it reads no setting, no Config Store and no environment variable (controls show that each pattern flags code that does);
///   - TestAbsentReadsProviderConfig: with the System Default Settings row ProviderConfig of TriageAgent (the Provider step writes it)
///     put to inline configurations, Absent follows it, Decide's precheck is no_key exactly where Absent is 1, Status keeps the value
///     it had, and the row is put back (Test.Agent.RunnerFixture.SnapshotDefault, PutDefault and RestoreDefault). Absent of an item
///     that is not in the production and of an empty name is 1;
///   - TestNeverThrows: Record, Forget, Status and Present throw nothing for an item name that is no valid subscript or a value that is no
///     text, and Status of such an item is 0; a value that is no text is recorded as unknown;
///   - TestAbsentOtherReadErrorIsNotAbsent: Absent of an item whose ProviderConfig read fails for another reason than a missing item (an
///     error status, and an exception) is exactly 0, so that a read that cannot be made never blocks a request.
Class OcuTalon.Test.Bridge.Keys Extends %UnitTest.TestCase
{

/// The variable that a CI start leaves unset, and that no process sets.
Parameter UNSET = "ZZOCUTALONNOSUCHVAR";

/// The prefix of the fixture items of the record.
Parameter ITEM = "ZzKeysItem";

/// The patterns of the scan of Status (ICU regular expressions, in any case): a $SYSTEM. call, $ZF(, $ZU( or $ZUTIL(; an indirection,
/// an Xecute or an X command; embedded SQL or a macro, whose expansion the scan does not see; a global but the record, or a routine call.
Parameter SYSTEMCALL = "\$(SYSTEM\.|ZF\(|ZU(TIL)?\()";

Parameter INDIRECTION = "@|\bXECUTE\b|(^|\{)\s*X(:\S+)?\s";

Parameter HIDDEN = "&SQL\(|\$\$\$";

Parameter OTHERGLOBAL = "\^(?!OcuTalonBP\.KeyState)";

/// The run's number.
Property Number As %Integer;

/// The ProviderConfig row of TriageAgent before the test touched it (Test.Agent.RunnerFixture.SnapshotDefault), or "".
Property Saved As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("Keys", "n"))
	Do ..KillRecords()
	Quit ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteEntry()
	Do ..KillRecords()
	Kill ^OcuTalonTest("Keys", ..Number)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DeleteEntry()
	Do ..KillRecords()
	If ..Saved '= "" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefault(..Saved)
		Set ..Saved = ""
	}
	Quit $$$OK
}

/// The Keys row of the matrix: the eight configurations and Status of an item that is not there, with the controls that make the
/// answers mean something, and the proof that no value is logged.
Method TestPresent()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set path = $SYSTEM.Util.GetEnviron("PATH")
	Do $$$AssertTrue(path '= "", "control: PATH is set in this process ("_$Length(path)_" characters)")
	Do $$$AssertEquals($SYSTEM.Util.GetEnviron(..#UNSET), "", "control: "_..#UNSET_" is not set")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set cases = $ListBuild("", "{}", "{""api_key"":""""}", "{""api_key"":""@{env:PATH}""}", "{""api_key"":""@{env:"_..#UNSET_"}""}", "{""api_key"":""literal-value""}", "@{config:ZzNoSuchEntry}", "not json")
	Set expected = $ListBuild(0, 0, 0, 1, 0, 0, 0, 0)
	For i = 1:1:$ListLength(cases) {
		Set text = $List(cases, i)
		Set result = $ClassMethod(keys, "Present", text)
		Do $$$AssertEquals(result, $List(expected, i), "Present of '"_text_"' is "_$List(expected, i))
		Do $$$AssertTrue((result = 0) || (result = 1), "and exactly 0 or 1: '"_result_"'")
	}
	Set result = $ClassMethod(keys, "Status", "ZzNoSuchItem")
	Do $$$AssertEquals(result, 0, "Status of an item that is not in the production is 0")
	Do $$$AssertTrue((result = 0) || (result = 1), "exactly 0 or 1")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, path), 0, "no row of the event log since the test began holds the value of PATH")
}

/// Forms that Present has to judge, beyond the matrix.
Method TestPresentForms()
{
	Set keys = "OcuTalon.Bridge.Keys"
	// not one placeholder: not judged, so not present
	For key = "@{env:PATH}x", "x@{env:PATH}", "@{env:PATH:-fallback}", "@{env:NO-DASH}", "@{secret:x}", "secret://wallet/key", "@{env:"_..#UNSET_"} @{env:PATH}" {
		Set text = {"api_key": (key)}.%ToJSON()
		Do $$$AssertEquals($ClassMethod(keys, "Present", text), 0, "an api_key that is not exactly one placeholder is not present: "_key)
	}
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":null}"), 0, "a null api_key is missing")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":"" ""}"), 0, "an api_key of white space is empty")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":5}"), 0, "an api_key that is no string is a form that is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""api_key"":{""a"":1}}"), 0, "nor is an object")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "[]"), 0, "a JSON array is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{"), 0, "text that starts like JSON and is not is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Present", $Char(10, 9)_"{""api_key"":""@{env:PATH}""}"_$Char(13, 10)), 1, "white space around the text is ignored")
	Do $$$AssertEquals($ClassMethod(keys, "Present", " "), 0, "a text of white space is empty")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "{""model_provider"":""anthropic"",""api_key"":""@{env:PATH}"",""base_url"":""http://mock/v1/""}"), 1, "a full inline configuration is read")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "@{config:}"), 0, "a reference with no name is not judged")
}

/// @{config:<name>}: the entry AI.LLM.<name> is read without resolving it.
Method TestPresentEntry()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Do $$$AssertTrue($SYSTEM.Security.Check("%Admin_ConfigStore", "USE"), "control: this process holds %Admin_ConfigStore:USE, so it reads the entries")
	Set name = ..EntryName()
	Set reference = "@{config:"_name_"}"
	Set sc = ..CreateEntry({"model_provider": "anthropic", "api_key": "@{env:PATH}"})
	Do $$$AssertStatusOK(sc, "an entry with the placeholder of PATH is created")
	If $$$ISERR(sc) Quit
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 1, "an api_key placeholder whose variable is set is present")
	Do $$$AssertEquals($ClassMethod(keys, "Present", "@{config:AI.LLM."_name_"}"), 1, "the name may be written in full")
	Do ..DeleteEntry()
	Do $$$AssertStatusOK(..CreateEntry({"model_provider": "anthropic", "api_key": ("@{env:"_..#UNSET_"}")}), "an entry with a placeholder of an unset variable is created")
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an api_key placeholder whose variable is not set is missing")
	Do ..DeleteEntry()
	Do $$$AssertStatusOK(..CreateEntry({"model_provider": "anthropic", "api_key": "literal-value"}), "an entry with a literal word is created")
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "a literal value is not judged, so it is not present")
	Do ..DeleteEntry()
	Set sc = ..CreateEntry({"model_provider": "anthropic"})
	If $$$ISOK(sc) {
		Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an entry with no api_key is missing")
	} Else {
		Do $$$LogMessage("an entry with no api_key cannot be created here, so the case is not tested: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do ..DeleteEntry()
	Do $$$AssertEquals($ClassMethod(keys, "Present", reference), 0, "an entry that does not exist is missing")
}

/// Status is the record that the job of each runner item wrote at its start. With the entries at the placeholder of the Provider step and
/// the runners started again, it equals Present of the item's ProviderConfig.
Method TestStatus()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Do $$$AssertEquals($ClassMethod(keys, "Status", "ZzNoSuchItem"), 0, "an item that is not in the production has no key")
	Do $$$AssertEquals($ClassMethod(keys, "Status", ""), 0, "and neither has an empty name")
	Set reason = $ClassMethod(fixture, "RunningReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
	Do $$$AssertStatusOK($ClassMethod(fixture, "RestoreKeys"), "the entries of the runners are put back to the placeholder of the Provider step, and the runners restarted")
	Do $$$AssertTrue($ClassMethod(fixture, "KeysAre", placeholder), "the entry of each runner holds "_placeholder)
	Do $$$AssertTrue($ClassMethod(fixture, "WaitAllRun"), "every item runs")
	For item = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Set config = ##class(Ens.Director).GetAdapterSettingValue(production_"||"_item, "ProviderConfig", .sc)
		Do $$$AssertStatusOK(sc, item_"'s ProviderConfig is read")
		Do $$$AssertTrue(config [ "@{config:", item_"'s ProviderConfig names a Config Store entry")
		Do $$$AssertTrue($ClassMethod(fixture, "WaitRecord", item), item_" has recorded its state in a job that runs")
		Set status = $ClassMethod(keys, "Status", item)
		Do $$$AssertTrue((status = 0) || (status = 1), item_": exactly 0 or 1: '"_status_"'")
		Set record = $Get(^OcuTalonBP.KeyState(item))
		Do $$$AssertEquals($ListLength(record), 2, item_" has a record of a state and a job")
		Do $$$AssertTrue($ListFind($ClassMethod(fixture, "Jobs", item), $ListGet(record, 2)) > 0, "written by a job of "_item_": "_$ListGet(record, 2))
		Do $$$AssertEquals(status, $ListGet(record, 1) = "present", item_": Status is the record")
		Do $$$AssertEquals(status, $ClassMethod(keys, "Present", config), item_": Status is Present of its ProviderConfig")
	}
}

/// Record keeps the state of a configuration and the job that wrote it, Status reads it, and Forget removes only the record of its own job.
/// The configurations are those of the matrix; the states are present, absent, absent, absent, unknown and unknown.
Method TestRecord()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set path = $SYSTEM.Util.GetEnviron("PATH")
	Do $$$AssertTrue(path '= "", "control: PATH is set in this process ("_$Length(path)_" characters)")
	Do $$$AssertEquals($SYSTEM.Util.GetEnviron(..#UNSET), "", "control: "_..#UNSET_" is not set")
	Do $$$AssertTrue($SYSTEM.Security.Check("%Admin_ConfigStore", "USE"), "control: this process holds %Admin_ConfigStore:USE, so a reference to an entry that does not exist is judged absent")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set cases = $ListBuild("{""api_key"":""@{env:PATH}""}", "{""api_key"":""@{env:"_..#UNSET_"}""}", "{}", "@{config:ZzNoSuchEntry}", "{""api_key"":""literal-value""}", "not json")
	Set states = $ListBuild("present", "absent", "absent", "absent", "unknown", "unknown")
	For i = 1:1:$ListLength(cases) {
		Set item = ..Item(i)
		Set config = $List(cases, i)
		Do $ClassMethod(keys, "Record", item, config)
		Set record = $Get(^OcuTalonBP.KeyState(item))
		Do $$$AssertEquals($ListGet(record, 1), $List(states, i), "the record of '"_config_"' holds the state "_$List(states, i))
		Do $$$AssertEquals($ListGet(record, 2), $Job, "and the job that wrote it")
		Do $$$AssertEquals(record, $ListBuild($List(states, i), $Job), "and the record is that state word and that job number and nothing else, so no part of a key")
		Do $$$AssertEquals($Data(^OcuTalonBP.KeyState(item)), 1, "and the node has no descendant")
		Do $$$AssertEquals($Find(record, path), 0, "and no part of the value of PATH is in it")
		Set status = $ClassMethod(keys, "Status", item)
		Do $$$AssertEquals(status, (i = 1), "Status of '"_config_"' is "_(i = 1))
		Do $$$AssertTrue((status = 0) || (status = 1), "and exactly 0 or 1: '"_status_"'")
	}
	// Forget of the job that wrote the record removes it
	Set item = ..Item(1)
	Do $ClassMethod(keys, "Forget", item)
	Do $$$AssertEquals($Data(^OcuTalonBP.KeyState(item)), 0, "Forget of the record of this job removes the node")
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 0, "and Status is 0")
	Do $$$AssertEquals($ClassMethod(keys, "Status", ..Item(99)), 0, "an item that was never recorded is 0")
	Do $$$AssertEquals($ClassMethod(keys, "Status", ""), 0, "and so is an empty name")
	Set count = ..RecordCount()
	Do $ClassMethod(keys, "Record", "", cases)
	Do $ClassMethod(keys, "Forget", "")
	Do $$$AssertEquals(..RecordCount(), count, "an empty item records and forgets nothing")
	// a record that this job wrote is not removed by another job
	Set item = ..Item(1)
	Do $ClassMethod(keys, "Record", item, $List(cases, 1))
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 1, "a record of a present key reads 1")
	Set run = $Name(^OcuTalonTest("Keys", ..Number, "forget"))
	Kill @run
	Job ##class(OcuTalon.Test.Bridge.Keys).ForgetInJob(..Number, item, $List(cases, 1))
	Do $$$AssertTrue(##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), 60), "the job finished")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing")
	Do $$$AssertTrue($Get(@run@("job")) '= $Job, "control: the job is not this process")
	Do $$$AssertEquals($Get(@run@("ownBefore")), 1, "control: the job reads a record that it wrote as 1")
	Do $$$AssertEquals($Get(@run@("ownAfter")), 0, "and Forget of its own record removes it")
	Do $$$AssertEquals($Get(@run@("otherAfter")), 1, "the job sees the record of this process after its Forget")
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 1, "Forget of the job leaves the record of this process, and Status stays 1")
	Do $$$AssertEquals($ListGet($Get(^OcuTalonBP.KeyState(item)), 2), $Job, "and the record is still this process's")
	Do $ClassMethod(keys, "Forget", item)
	Do $$$AssertEquals($Data(^OcuTalonBP.KeyState(item)), 0, "Forget of this process removes it")
	// a node that is no record
	Set ^OcuTalonBP.KeyState(item) = "present"
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 0, "a node that is no list reads 0")
	Set ^OcuTalonBP.KeyState(item) = $ListBuild("unknown", $Job)
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 0, "an unknown record reads 0")
	Set ^OcuTalonBP.KeyState(item) = $ListBuild("absent", $Job)
	Do $$$AssertEquals($ClassMethod(keys, "Status", item), 0, "an absent record reads 0")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, path), 0, "no row of the event log since the test began holds the value of PATH")
	Kill @run
}

/// The job body of TestRecord. It reports under ^OcuTalonTest("Keys", number, "forget"): its job number; whether it reads as 1 a record of
/// a present key that it wrote itself (ownBefore) and as 0 after its Forget (ownAfter); and Status of the record that the parent wrote
/// (item) after the job's Forget of that item (otherAfter).
ClassMethod ForgetInJob(number As %Integer, item As %String, config As %String)
{
	Set run = $Name(^OcuTalonTest("Keys", number, "forget"))
	Try {
		Set @run@("job") = $Job
		Set own = item_"Own"
		Do ##class(OcuTalon.Bridge.Keys).Record(own, config)
		Set @run@("ownBefore") = ##class(OcuTalon.Bridge.Keys).Status(own)
		Do ##class(OcuTalon.Bridge.Keys).Forget(own)
		Set @run@("ownAfter") = ##class(OcuTalon.Bridge.Keys).Status(own)
		Do ##class(OcuTalon.Bridge.Keys).Forget(item)
		Set @run@("otherAfter") = ##class(OcuTalon.Bridge.Keys).Status(item)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// Status reads the record and nothing else: its code (the code lines of the compiled method, comment lines dropped) names
/// ^OcuTalonBP.KeyState and has no ##class( and no .. call, no dynamic dispatch, no system call (SYSTEMCALL), no indirection, Xecute or
/// X command (INDIRECTION), no embedded SQL or macro (HIDDEN) and no other global or routine call (OTHERGLOBAL). Controls show that each
/// pattern flags code that does, Absent and State among it, so that the scan is not blind.
Method TestStatusReadsOnlyTheRecord()
{
	Set status = ..Code("Status")
	Do $$$AssertTrue(status '= "", "the code of Status is read")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, "^OcuTalonBP.KeyState", 1), "Status names ^OcuTalonBP.KeyState")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, "##class(", 1), "and has no ##class(")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, "\.\.[#%A-Za-z]"), "and no .. call")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, "\$(ClassMethod|Method|ZObjMethod|ZObjClassMethod|Property)\("), "and no dynamic dispatch")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, ..#SYSTEMCALL), "and no $SYSTEM. call, $ZF(, $ZU( or $ZUTIL(")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, ..#INDIRECTION), "and no indirection, Xecute or X command")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, ..#HIDDEN), "and no embedded SQL or macro")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(status, ..#OTHERGLOBAL), "and no global but ^OcuTalonBP.KeyState, and no routine call")
	Set absent = ..Code("Absent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(absent, "##class(", 1), "control: the scan flags the ##class( of Absent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(absent, "\.\.[#%A-Za-z]"), "and the .. call of Absent")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(..Code("State"), ..#SYSTEMCALL), "and the $SYSTEM. call of State")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = $ZF(-1, ""env"")", ..#SYSTEMCALL), "and a $ZF( call")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = @name", ..#INDIRECTION), "and an indirection")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Xecute code", ..#INDIRECTION), "and an Xecute")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = $ZU(5)", ..#SYSTEMCALL), "and a $ZU( call")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"X code", ..#INDIRECTION), "and an X command")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"&sql(SELECT 1 INTO :x)", ..#HIDDEN), "and embedded SQL")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"Set x = "_$Char(36, 36, 36)_"OK", ..#HIDDEN), "and a macro")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = ^Other(1)", ..#OTHERGLOBAL), "and a global that is not the record")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = $$tag^routine()", ..#OTHERGLOBAL), "and a routine call")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches("Set x = $ListGet($Get(^OcuTalonBP.KeyState(item)))", ..#OTHERGLOBAL), "but not the record")
}

/// Record, Forget, Status and Present throw nothing, whatever they are given: an item name that is no valid subscript (6000 characters)
/// and a provider configuration that is no text (an object reference). Status of such an item is exactly 0: nothing can be recorded
/// under the long name, and the value that is no text is recorded as unknown.
Method TestNeverThrows()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set long = $Translate($Justify("", 6000), " ", "x")
	Set object = ##class(%DynamicObject).%New()
	Set thrown = ""
	Try {
		Do $ClassMethod(keys, "Record", long, "{""api_key"":""@{env:PATH}""}")
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "Record of an item that is no valid subscript throws nothing")
	Set thrown = ""
	Try {
		Do $ClassMethod(keys, "Forget", long)
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "nor does Forget")
	Set thrown = ""
	Set status = ""
	Try {
		Set status = $ClassMethod(keys, "Status", long)
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "nor does Status")
	Do $$$AssertEquals(status, 0, "and Status of it is exactly 0")
	Set thrown = ""
	Set present = ""
	Try {
		Set present = $ClassMethod(keys, "Present", object)
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "Present of a value that is no text throws nothing")
	Do $$$AssertEquals(present, 0, "and is exactly 0")
	Set thrown = ""
	Try {
		Do $ClassMethod(keys, "Record", ..Item(1), object)
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertEquals(thrown, "", "Record of a value that is no text throws nothing")
	Do $$$AssertEquals($ListGet($Get(^OcuTalonBP.KeyState(..Item(1)))), "unknown", "and records it as unknown, a form that is not judged")
	Do $$$AssertEquals($ClassMethod(keys, "Status", ..Item(1)), 0, "and its Status is exactly 0")
}

/// Absent follows the ProviderConfig setting of the item: an inline configuration whose api_key placeholder names a set variable is a
/// key, one that names an unset variable is none, and so are a configuration without an api_key and a reference to an entry that does
/// not exist; a literal and a text that is not JSON are not judged, so they are not absent. Decide's precheck is no_key exactly where
/// Absent is 1, and Status keeps the value it had, because it reads the record of the running job; the row is put back afterwards.
Method TestAbsentReadsProviderConfig()
{
	Set keys = "OcuTalon.Bridge.Keys"
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set decide = "OcuTalon.Bridge.Process.Decide"
	If ##class(Ens.Director).GetActiveProductionName() = "" {
		Do $$$AssertTrue(0, "no production is active, so the ProviderConfig of TriageAgent cannot be read")
		Quit
	}
	Set ..Saved = $ClassMethod(fixture, "SnapshotDefault", "TriageAgent", "ProviderConfig")
	Set path = $SYSTEM.Util.GetEnviron("PATH")
	Do $$$AssertTrue(path '= "", "control: PATH is set in this process ("_$Length(path)_" characters), so the first case is a key that is present")
	Set mark = $ClassMethod(fixture, "EventMark")
	Do $$$AssertTrue($ClassMethod(fixture, "WaitRecord", "TriageAgent"), "control: TriageAgent has recorded its state in a job that runs, so the value of Status is settled")
	Set before = $ClassMethod(keys, "Status", "TriageAgent")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "decide"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Triage this item."
	Set cases = $ListBuild($ListBuild("{""api_key"":""@{env:PATH}""}", 0), $ListBuild("{""api_key"":""@{env:"_..#UNSET_"}""}", 1), $ListBuild("{}", 1), $ListBuild("@{config:ZzNoSuchEntry}", 1), $ListBuild("{""api_key"":""literal-value""}", 0), $ListBuild("not json", 0))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "TriageAgent", "ProviderConfig", $List(case, 1)), "the ProviderConfig of TriageAgent is '"_$List(case, 1)_"'")
		Set absent = $ClassMethod(keys, "Absent", "TriageAgent")
		Do $$$AssertEquals(absent, $List(case, 2), "Absent of TriageAgent is exactly "_$List(case, 2))
		Set reason = $ClassMethod(decide, "Precheck", request, "TriageAgent", 0)
		If $List(case, 2) {
			Do $$$AssertEquals(reason, "no_key", "Precheck gives no_key where the key is absent")
		} Else {
			Do $$$AssertNotEquals(reason, "no_key", "Precheck does not give no_key where the key is not absent: '"_reason_"'")
		}
		Do $$$AssertEquals($ClassMethod(keys, "Status", "TriageAgent"), before, "Status of TriageAgent keeps the value it had: "_before)
	}
	Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, path), 0, "no row of the event log since the test began holds the value of PATH")
	Do $$$AssertEquals($ClassMethod(keys, "Absent", "ZzNoSuchItem"), 1, "an item that is not in the production has no key, whatever the row says")
	Do $$$AssertEquals($ClassMethod(keys, "Absent", ""), 1, "and neither has an empty name")
}

/// A read of the ProviderConfig setting that fails for another reason than a missing item is not an absent key: Decide's precheck blocks a
/// request only for a key that the bridge can tell is absent. TelegramIn has an adapter that holds no such setting (the read returns an
/// error status) and Decide has no adapter (the read throws); controls show how each read ends, so that each arm of Absent is reached.
Method TestAbsentOtherReadErrorIsNotAbsent()
{
	Set keys = "OcuTalon.Bridge.Keys"
	If ##class(Ens.Director).GetActiveProductionName() = "" {
		Do $$$AssertTrue(0, "no production is active, so the ProviderConfig of an item cannot be read")
		Quit
	}
	Do $$$AssertEquals(..ReadOutcome("TelegramIn"), "status", "control: the read of the ProviderConfig of TelegramIn returns an error status that is not a missing item")
	Do $$$AssertEquals(..ReadOutcome("Decide"), "exception", "control: the read of the ProviderConfig of Decide, which has no adapter, throws")
	Do $$$AssertEquals($ClassMethod(keys, "Absent", "TelegramIn"), 0, "Absent of an item whose read returns another error is exactly 0")
	Do $$$AssertEquals($ClassMethod(keys, "Absent", "Decide"), 0, "and so is Absent of an item whose read fails")
}

/// --- helpers ---
/// How the read of the ProviderConfig setting of the item ends in the active production: "ok", "missing" (the item is not found), "status" (another
/// error status) or "exception".
ClassMethod ReadOutcome(item As %String) As %String [ Private ]
{
	Set outcome = "ok"
	Try {
		Set value = ##class(Ens.Director).GetAdapterSettingValue(##class(Ens.Director).GetActiveProductionName()_"||"_item, "ProviderConfig", .sc)
		If $$$ISERR(sc) Set outcome = $Select($SYSTEM.Status.Equals(sc, "<Ens>ErrConfigItemNotFound"): "missing", 1: "status")
	} Catch {
		Set outcome = "exception"
	}
	Quit outcome
}

/// The name of this run's entry, without the area and type.
Method EntryName() As %String [ Private ]
{
	Quit "OcuTalonZzKeys"_..Number
}

/// Creates this run's entry with the details.
Method CreateEntry(details As %DynamicObject) As %Status [ Private ]
{
	Do ..DeleteEntry()
	Quit ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..EntryName(), details)
}

/// Deletes this run's entry when it exists.
Method DeleteEntry() [ Private ]
{
	If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_..EntryName()) Do ##class(%ConfigStore.Configuration).Delete("AI.LLM."_..EntryName())
}

/// The fixture item of this run and the case.
Method Item(case As %Integer) As %String [ Private ]
{
	Quit ..#ITEM_..Number_"_"_case
}

/// The number of nodes of ^OcuTalonBP.KeyState.
ClassMethod RecordCount() As %Integer [ Private ]
{
	Set count = 0
	Set item = ""
	For {
		Set item = $Order(^OcuTalonBP.KeyState(item))
		Quit:item=""
		Set count = count + 1
	}
	Quit count
}

/// Removes the records of the fixture items (those whose name starts with the prefix), and no other.
ClassMethod KillRecords() [ Private ]
{
	Set item = ..#ITEM
	For {
		Set item = $Order(^OcuTalonBP.KeyState(item))
		If $Extract(item, 1, $Length(..#ITEM)) '= ..#ITEM Quit
		Kill ^OcuTalonBP.KeyState(item)
	}
}

/// The code of the compiled method of OcuTalon.Bridge.Keys: its implementation, with the lines separated by a line feed.
ClassMethod Code(method As %String) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Bridge.Keys||"_method)
	If '$IsObject(compiled) Quit ""
	Set text = ""
	Do compiled.Implementation.Rewind()
	While 'compiled.Implementation.AtEnd {
		Set text = text _ compiled.Implementation.Read(32000)
	}
	Quit $Translate(text, $Char(13), "")
}

}
