/// Tests that every run of a background check is recorded in Digest.Data.CheckRun and that Build reads it (Story 17.5; AD-18). The runs are real: a shadow
/// instance of Test.Checks.Probe runs OcuTalon.Checks.Process over fixture checks, so the real Run and Record update the BackgroundCheck row and its
/// trigger writes the CheckRun; only the production read is fed. The vital signs and the live read of Build come from Test.Digest.CoverageProbe.
///   - TestProcessRunRecorded (the integration): a due check runs once, one CheckRun holds its result, the run's session as HeaderId and the time of the
///     run, and Build derives that entry's row from it;
///   - TestReasonMap: a not_checked run records timeout for no answer in time, unreachable for no read access and for a production that is no longer
///     the namespace's, and error for a read that throws; a failed run records no reason;
///   - TestTriggerFires: the trigger writes one row for each change of LastRunAt, by SQL and by object, and none for another update or for the same time;
///   - TestRecordRunReasons: the reason of a recorded run, from its finding;
///   - TestFailedWriteWarns: a CheckRun that cannot be written logs one warning and throws nothing;
///   - TestOneLiveReadHelper (DW-786): the live-read rules are one helper. By structure, from the method definitions: Coverage Live names no
///     REASON or FINDING parameter of Checks.Process and makes no upper-case letter of its own, and Live, Process Run and Process Finding call the shared
///     class methods of Process. By parity, for the reads unreadable, not current, timeout, unknown state, thrown, cut with none of the session's
///     failures, stopped, suspended with a cut, troubled and running: the result and finding of a real Process run (the shadow probe) and the live row
///     that Build gives (CoverageProbe, on a watch whose latest run passed) are equal, and are the expected texts.
Class OcuTalon.Test.Digest.Runs Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Checks.Probe";

Parameter COVERAGE = "OcuTalon.Test.Digest.CoverageProbe";

/// The SessionId of the shadow instance: the run's header.
Parameter SESSIONID = 535353;

Property Refs As %String(MAXLEN = "");

Property Sessions As %String(MAXLEN = "");

Property Checks As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#COVERAGE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#COVERAGE, "Reset")
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method Clean()
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Checks = ""
}

/// The integration: Checks.Process, then CheckRun, then Build.
Method TestProcessRunRecorded()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Session()
	Set start = ##class(OcuTalon.Data.Time).NowUtc()
	Set created = ##class(OcuTalon.Data.Time).AddSeconds(start, -30)
	Set ref = ..Watch(session, "Zz.DRun1", {"CreatedAt": (created)})
	Do $ClassMethod(..#PROBE, "Feed", "Zz.DRun1", {"outcome": "read", "state": "stopped", "rows": []})
	Do ..Tick(host)
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|Production stopped", "the run failed: the production is stopped")
	Set run = ..RunsOf(ref)
	Do $$$AssertEquals(run.%Size(), 1, "one CheckRun for the run")
	Set one = run.%Get(0)
	Do $$$AssertEquals(one.result_"|"_one.reason_"|"_one.finding_"|"_one.sessionRef, "failed||Production stopped|"_session, "its result, no reason, its finding and the session")
	Do $$$AssertEquals(one.ranAt, row.LastRunAt, "the time of the run")
	Do $$$AssertEquals(one.headerId, ..#SESSIONID, "and the run's session as the header")
	Set lastRunAt = row.LastRunAt
	Set row = ""
	Set one = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Kind = 'production' WHERE Ref = ?", ref)
	Set after = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 1)
	Set sc = $ClassMethod(..#COVERAGE, "Build", session, created, after, .rows, .lines)
	Do $$$AssertStatusOK(sc, "Build is OK")
	Do $$$AssertEquals(rows.%Size(), 6, "five vital rows and the watch")
	Set watch = rows.%Get(5)
	Do $$$AssertEquals(watch.entry_"|"_watch.result_"|"_watch.finding_"|"_watch.checkedAt, "Zz.DRun1 production|failed|Production stopped|"_lastRunAt, "Build derives the entry's row from the recorded run: "_watch.entry_"|"_watch.result_"|"_watch.finding_"|"_watch.checkedAt)
	Do $$$AssertEquals(lines.%Get(5).key, "digest.failed", "on a failed line")
}

/// The Reason of each kind of not_checked run, from the real Run.
Method TestReasonMap()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Session()
	Set created = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30)
	Set names = $ListBuild("Timeout", "Unreadable", "NotCurrent", "Throws", "Passed")
	Set specs = $ListBuild("{""outcome"":""read"",""state"":""timeout""}", "{""outcome"":""unreadable""}", "{""outcome"":""not_current""}", "{""throw"":""boom""}", "{""outcome"":""read"",""state"":""running""}")
	Set expected = $ListBuild("not_checked|timeout|No answer in time", "not_checked|unreachable|No read access to its namespace", "not_checked|unreachable|No longer its namespace's production", "not_checked|error|Couldn't be read", "passed||")
	For i = 1:1:$ListLength(names) {
		Set production = "Zz.DMap"_$List(names, i)
		Set refs(i) = ..Watch(session, production, {"CreatedAt": (created)})
		Do $ClassMethod(..#PROBE, "Feed", production, ##class(%DynamicObject).%FromJSON($List(specs, i)))
	}
	Do ..Tick(host)
	For i = 1:1:$ListLength(names) {
		Set run = ..RunsOf(refs(i))
		Do $$$AssertEquals(run.%Size(), 1, $List(names, i)_": one CheckRun")
		Set one = run.%Get(0)
		Do $$$AssertEquals(one.result_"|"_one.reason_"|"_one.finding, $List(expected, i), $List(names, i)_": result, reason and finding")
	}
}

Method TestTriggerFires()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.DTrigger", {"CreatedAt": "2030-05-01T10:00:00Z"})
	Do $$$AssertEquals(..RunsOf(ref).%Size(), 0, "control: the fixture insert records no run")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", ref)
	Do $$$AssertEquals(..RunsOf(ref).%Size(), 0, "an update that leaves LastRunAt alone records no run")
	Set update = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ?, Finding = ?, LastRunHeaderId = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", "failed", "Production stopped", 77, ref)
	Do $$$AssertEquals(update.%SQLCODE, 0, "the update is applied")
	Set runs = ..RunsOf(ref)
	Do $$$AssertEquals(runs.%Size(), 1, "an update by SQL that changes LastRunAt records one run")
	Set one = runs.%Get(0)
	Do $$$AssertEquals(one.ranAt_"|"_one.result_"|"_one.finding_"|"_one.headerId_"|"_one.sessionRef, "2030-06-01T12:00:00Z|failed|Production stopped|77|"_session, "with the new values")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Finding = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", "again", ref)
	Do $$$AssertEquals(..RunsOf(ref).%Size(), 1, "the same LastRunAt again records none")
	Set object = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Set object.LastRunAt = "2030-06-01T12:01:00Z"
	Set object.Result = "passed"
	Set object.Finding = ""
	Do $$$AssertStatusOK(object.%Save(), "an object save")
	Set runs = ..RunsOf(ref)
	Do $$$AssertEquals(runs.%Size(), 2, "records one run too")
	Do $$$AssertEquals(runs.%Get(1).ranAt_"|"_runs.%Get(1).result, "2030-06-01T12:01:00Z|passed", "with the saved values")
}

Method TestRecordRunReasons()
{
	Set session = ..Session()
	Set process = "OcuTalon.Checks.Process"
	Set findings = $ListBuild($Parameter(process, "REASONTIMEOUT"), $Parameter(process, "REASONUNREADABLE"), $Parameter(process, "REASONNOTCURRENT"), $Parameter(process, "REASONREAD"), $Parameter(process, "REASONTOOMANY"), "something else", "")
	Set expected = $ListBuild("timeout", "unreachable", "unreachable", "error", "error", "error", "error")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	For i = 1:1:$ListLength(findings) {
		Do $ClassMethod("OcuTalon.Checks.Coverage", "RecordRun", ref, session, "2030-06-01T12:0"_i_":00Z", "not_checked", $List(findings, i), 5)
	}
	Set runs = ..RunsOf(ref)
	Do $$$AssertEquals(runs.%Size(), 7, "seven runs")
	For i = 1:1:7 {
		Do $$$AssertEquals(runs.%Get(i - 1).reason, $List(expected, i), "'"_$List(findings, i)_"' is "_$List(expected, i))
	}
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod("OcuTalon.Checks.Coverage", "RecordRun", other, session, "2030-06-01T12:00:00Z", "failed", $Parameter(process, "REASONTIMEOUT"), "")
	Do $$$AssertEquals(..RunsOf(other).%Get(0).reason, "", "a run that is not not_checked has no reason, whatever its finding")
}

Method TestOneLiveReadHelper()
{
	Set process = "OcuTalon.Checks.Process"
	Set live = ..Body("OcuTalon.Checks.Coverage", "Live")
	Set run = ..Body(process, "Run")
	Set finding = ..Body(process, "Finding")
	Do $$$AssertTrue(live [ "Process).", "control: the body of Live was read")
	Do $$$AssertTrue(run [ "..Finding(", "control: the body of Run was read")
	Do $$$AssertTrue(finding [ "..Joined(", "control: the body of Finding was read")
	Set names = ""
	Set parameters = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ParameterDefinition WHERE parent = ? AND (Name %STARTSWITH 'FINDING' OR Name %STARTSWITH 'REASON')", process)
	While parameters.%Next() {
		Set name = parameters.%Get("Name")
		Set names = names_$ListBuild(name)
		Do $$$AssertEquals(live [ (""""_name_""""), 0, "Live does not name the parameter "_name_" of Process")
		Do $$$AssertEquals(live [ ("Process).#"_name), 0, "nor read it directly")
	}
	Do $$$AssertTrue($ListLength(names) > 10, "control: the parameters of Process were listed")
	Do $$$AssertEquals(live [ "$Parameter(", 0, "Live reads no parameter by name")
	Do $$$AssertEquals(live [ "$ZConvert(", 0, "Live makes no upper-case first letter of its own")
	Do $$$AssertEquals(run [ "$ZConvert(", 0, "nor does Run")
	Do $$$AssertEquals(finding [ "$ZConvert(", 0, "nor does Finding")
	For name = "NotCheckedReason", "ScopedFailures", "IsCut", "StateText", "FailureText", "Joined" {
		Do $$$AssertTrue(live [ ("Process)."_name_"("), "Live calls "_name)
	}
	For name = "NotCheckedReason", "ScopedFailures", "IsCut" {
		Do $$$AssertTrue(run [ (".."_name_"("), "Run calls "_name)
	}
	For name = "StateText", "FailureText", "Joined" {
		Do $$$AssertTrue(finding [ (".."_name_"("), "Finding calls "_name)
	}
	Do ..ParityOfLiveRead()
}

/// The same reads fed to a real Process run and to the live read of Build: the result and the finding of each are equal and are the expected ones.
Method ParityOfLiveRead()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set limit = ##class(OcuTalon.Watch.Mark).#MAXFAILURES
	Set runSession = ..Session()
	Set liveSession = ..Session()
	Set otherSession = ..Session()
	Set created = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30)
	Set ranAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -5)
	Set labels = $ListBuild("unreadable", "not current", "timeout", "unknown state", "thrown", "cut with none of the session's", "stopped", "suspended with a cut", "troubled", "running")
	Set specs = $ListBuild("{""outcome"":""unreadable"",""state"":""running""}", "{""outcome"":""not_current"",""state"":""running""}", "{""outcome"":""read"",""state"":""timeout"",""failures"":2}", "{""outcome"":""read"",""state"":""unknown""}", "{""throw"":""boom""}", "{""outcome"":""read"",""state"":""running"",""others"":"_limit_"}", "{""outcome"":""read"",""state"":""stopped"",""failures"":1}", "{""outcome"":""read"",""state"":""suspended"",""failures"":1,""others"":"_(limit - 1)_"}", "{""outcome"":""read"",""state"":""troubled"",""failures"":2}", "{""outcome"":""read"",""state"":""running""}")
	Set expected = $ListBuild("not_checked|No read access to its namespace", "not_checked|No longer its namespace's production", "not_checked|No answer in time", "not_checked|Couldn't be read", "not_checked|Couldn't be read", "not_checked|Too many new failures to count", "failed|Production stopped, 1 new failure", "failed|Production suspended, at least 1 new failures", "failed|Production troubled, 2 new failures", "passed|")
	For i = 1:1:$ListLength(labels) {
		Set spec = ##class(%DynamicObject).%FromJSON($List(specs, i))
		Set runProduction = "Zz.DPar"_i_"r"
		Set liveProduction = "Zz.DPar"_i_"l"
		Set runRefs(i) = ..Watch(runSession, runProduction, {"CreatedAt": (created)})
		Do $ClassMethod(..#PROBE, "Feed", runProduction, ..ReadOf(spec, runSession, otherSession))
		Set liveRefs(i) = ##class(OcuTalon.Test.Data.Fixture).Check(liveSession, "ZZNS", liveProduction, {"CreatedAt": (created)})
		Set ..Refs = ..Refs_","_liveRefs(i)
		Do $ClassMethod("OcuTalon.Checks.Coverage", "RecordRun", liveRefs(i), liveSession, ranAt, "passed", "", "")
		Do $ClassMethod(..#COVERAGE, "FeedRead", liveProduction, ..ReadOf(spec, liveSession, otherSession))
	}
	Do ..Tick(host)
	Set after = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 1)
	Set sc = $ClassMethod(..#COVERAGE, "Build", liveSession, created, after, .rows, .lines)
	Do $$$AssertStatusOK(sc, "Build is OK")
	Do $$$AssertEquals(rows.%Size(), 5 + $ListLength(labels), "five vital rows and a row for each watch")
	For i = 1:1:$ListLength(labels) {
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(runRefs(i))
		Set viaRun = row.Result_"|"_row.Finding
		Set one = rows.%Get(4 + i)
		Set viaLive = one.result_"|"_one.finding
		Do $$$AssertEquals(viaRun, $List(expected, i), $List(labels, i)_": the run's result and finding")
		Do $$$AssertEquals(viaLive, viaRun, $List(labels, i)_": the live row gives the same result and finding")
	}
}

/// The read of a spec ({"outcome", "state", "failures" (of the session), "others" (of another session), "throw"}) for the probe: its rows hold the
/// failures of the session and of the other session, each with the TraceRef of its session as the SuperSession.
Method ReadOf(spec As %DynamicObject, session As %String, other As %String) As %DynamicObject
{
	Set read = {"outcome": (spec.outcome), "state": (spec.state), "throw": (spec.throw)}
	Set rows = []
	For n = 1:1:+spec.failures {
		Do rows.%Push({"kind": "header", "headerId": (n), "superSession": (##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef), "at": "2030-06-01 11:59:59.000", "logId": ""})
	}
	For n = 1:1:+spec.others {
		Do rows.%Push({"kind": "header", "headerId": (n + 100000), "superSession": (##class(OcuTalon.Data.Session).RefIndexOpen(other).TraceRef), "at": "2030-06-01 11:59:59.000", "logId": ""})
	}
	Do read.%Set("rows", rows)
	Quit read
}

/// The code of a method, as its class definition holds it (%Dictionary.MethodDefinition).
ClassMethod Body(class As %String, method As %String) As %String
{
	Set definition = ##class(%Dictionary.MethodDefinition).%OpenId(class_"||"_method)
	If '$IsObject(definition) Quit ""
	Set stream = definition.Implementation
	Do stream.Rewind()
	Quit stream.Read(1000000)
}

Method TestFailedWriteWarns()
{
	Set session = ..Session()
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = +$Get(^Ens.Util.LogD)
	Do $ClassMethod("OcuTalon.Checks.Coverage", "RecordRun", ref, session, "2030-06-01T12:00:00Z", $Justify("", 60), "", "not a number")
	Do $$$AssertEquals(..RunsOf(ref).%Size(), 0, "a run that cannot be written leaves no row")
	Set log = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text [ ?", mark, "A run of check "_ref_" could not be recorded")
	Do log.%Next()
	Do $$$AssertEquals(log.%GetData(1), 1, "and one warning is logged")
}

/// --- helpers ---
Method Host() As OcuTalon.Test.Checks.Probe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If $IsObject(host) Set host.%SessionId = ..#SESSIONID
	Quit host
}

Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzdruns")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture check of the probe's Kind, due at once; its Ref.
Method Watch(session As %String, production As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"Kind": ($Parameter(..#PROBE, "KIND")), "NextDueAt": "", "DisplayName": (production)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Checks = ..Checks_$Select(..Checks = "": "", 1: ",")_ref
	Quit ref
}

Method Tick(host As OcuTalon.Test.Checks.Probe)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set host.Only = ..Checks
	Set host.OnlyIncidents = ""
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the Tick is answered OK")
}

/// The CheckRun rows of the check, oldest first, as {ranAt, result, reason, finding, headerId, sessionRef}.
ClassMethod RunsOf(ref As %String) As %DynamicArray
{
	Set runs = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT RanAt, Result, Reason, Finding, HeaderId, SessionRef FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? ORDER BY RanAt, ID", ref)
	While result.%Next() {
		Do runs.%Push({"ranAt": (result.%Get("RanAt")), "result": (result.%Get("Result")), "reason": (result.%Get("Reason")), "finding": (result.%Get("Finding")), "headerId": (result.%Get("HeaderId")), "sessionRef": (result.%Get("SessionRef"))})
	}
	Quit runs
}

}
