/// Tests of GET and PUT /v1/heartbeat and POST /v1/heartbeat/run (Story 39.2; FR-63, FR-66; AD-1, AD-4, AD-13, AD-17, AD-18, AD-19), called with
/// stand-in request and response objects and a CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.PersonaApi does), through the
/// real production: PUT submits through Commands.Submit, CommandsIn sends the SetHeartbeat to the real SettingsOps, which validates, audits and
/// writes; POST sends a RunHeartbeat that CommandsIn gives to the real Checks as a BeatNow. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): where OcuTalon.Production does not run every test fails with that reason, so that a broken stack can never give a green shard. The
/// answers that the real items never give go through Test.Web.HeartbeatApiProbe. The expected texts are written out here, never read from the
/// product. The onlineDemo setting is put back in OnAfterAllTests, the heartbeat keys and HeartbeatBeat rows of the fixture sessions are removed, and so
/// are their beats' decisions, the fixture rows and the sessions' messages. A running production's Tick may make a HeartbeatBeat row for a fixture
/// session of its own, so the tests of the GET compare the settings and the private fields, not the whole answer, where a row could appear.
///   - TestGetDefaults, TestGetOnlineDemoSample, TestGetAfterPut, TestGetRowView, TestGetFails: the GET: the settings, the online demo's sample,
///     the values just saved (never a cached older one), the row's public view with traceUrl and none of its private fields, a failed read;
///   - TestPutAccepted, TestPutRefusals, TestPutBadBody, TestPutLongChecklist, TestPutBodyNamesSession: the PUT: the answer, the keys and the audit entry
///     read back from the IRIS audit log, the refusals, the bodies that submit nothing and a sessionRef in the body that is ignored;
///   - TestPutOutcomes: the mapping of the owner's outcomes, and what the route submits, through the probe;
///   - TestRunSendsThenCoolsDown, TestRunEmptyThenCooldown (real Checks): the 202, the 409 cooldown with availableAt and the 409 empty;
///   - TestRunOutcomes: the mapping of Checks' outcomes, through the probe;
///   - TestNoSessionIs500: with no CSP session all three routes answer 500 server_error.
Class OcuTalon.Test.Web.HeartbeatApi Extends %UnitTest.TestCase
{

/// The longest to wait for an audit entry, in seconds.
Parameter SECONDS = 20;

/// The longest to wait for a beat's decision, in seconds.
Parameter WAITDECISION = 90;

/// The class of the stand-in whose seams answer the failures.
Parameter PROBE = "OcuTalon.Test.Web.HeartbeatApiProbe";

/// The sentence of a refusal that changed nothing.
Parameter NOTSAVED = "Couldn't save. Nothing was changed.";

/// The sentence of a failure inside OcuTalon.
Parameter SERVERERROR = "Something went wrong inside OcuTalon. Try again.";

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions, for ForgetPerson and the HeartbeatBeat rows.
Property Sessions As %String(MAXLEN = "");

/// The ItemIds of the beats that a test made, for the decisions.
Property ItemIds As %List;

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The value of the public setting onlineDemo before the run.
Property SavedDemo As %String;

/// 1 when the entries of the runners were pointed at the CI mock key variable by a test.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The session that the stand-in CSP session is bound to.
Property Current As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("HeartbeatApi", "n"))
	Set ..Traces = []
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..ItemIds = ""
	Set ..Missing = ""
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Kill ^OcuTalonTest("HeartbeatApiProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Kill ^OcuTalonTest("HeartbeatApiProbe")
	Set sc = $SYSTEM.Status.OK()
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
	}
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" {
			Do ##class(OcuTalon.Core.SettingsOps).ForgetPerson(ref)
			Do ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexDelete(ref)
		}
	}
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit sc
}

/// A session with no keys reads the install's defaults: on, 30 minutes, 08:00 to 20:00, an empty checklist and no sample. A Tick may have made the
/// session's row, so the settings are compared, and the private fields must be absent.
Method TestGetDefaults()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set body = ..Get(.response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.on_"|"_answer.interval_"|"_answer.from_"|"_answer.to_"|"_answer.checklist_"|"_answer.sample, "1|30|08:00|20:00||0", "the defaults")
	Do $$$AssertEquals(answer.%GetTypeOf("on")_"|"_answer.%GetTypeOf("interval")_"|"_answer.%GetTypeOf("sample"), "boolean|number|boolean", "with their JSON types")
	Do ..AssertNoPrivate(body, session)
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)|(none)|(none)", "and nothing was written")
}

/// On the online demo a session with no checklist reads off, 30 minutes and the three-line sample, with sample true; no key is written.
Method TestGetOnlineDemoSample()
{
	If '..Guard() Quit
	Set session = ..Session()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..Get(.response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.on_"|"_answer.interval_"|"_answer.sample, "0|30|1", "off, 30 minutes, the sample")
	Do $$$AssertEquals(answer.checklist, "Tell me if an Orders incident is still open or waiting for my approval."_$Char(10)_"Remind me of anything due in the next hour."_$Char(10)_"Ignore everything else.", "the checklist is the three-line sample")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)|(none)|(none)", "and nothing was written")
}

/// A GET after a PUT shows the values just saved, from the rows: a cache entry that another read left behind does not show.
Method TestGetAfterPut()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set text = "Look at Orders."_$Char(10)_"Be brief."
	Set body = ..Put({"on": false, "interval": 240, "from": "06:30", "to": "22:15", "checklist": (text)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the heartbeat is saved")
	For name = "on", "interval", "from", "to", "checklist" {
		Set ^||OcuTalon.Setting(##class(OcuTalon.Checks.Beat).SettingKey(session, name)) = $ListBuild("zzstale", 1, $ZHorolog)
	}
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(answer.on_"|"_answer.interval_"|"_answer.from_"|"_answer.to_"|"_answer.checklist_"|"_answer.sample, "0|240|06:30|22:15|"_text_"|0", "GET reads the saved values from the rows")
	Set body = ..Put({"on": true, "interval": 30, "from": "", "to": "", "checklist": ""}.%ToJSON(), .response)
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(answer.on_"|"_answer.interval_"|"_answer.sample, "1|30|0", "and the next save")
	Do $$$AssertEquals(answer.%IsDefined("from")_"|"_answer.%IsDefined("to"), "1|1", "an all-day person's from and to are present")
	Do $$$AssertEquals(answer.from_"|"_answer.to, "|", "and empty")
}

/// The person's HeartbeatBeat row: the answer holds the row's public view (the event's members) and traceUrl, and never the SessionRef, a snapshot
/// key, the item's Id or the decision's Ref.
Method TestGetRowView()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	If '$IsObject(row) Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.SessionRef = session
	Set row.NextDueAt = "2030-01-01T10:30:00Z"
	Set row.LastBeatAt = "2030-01-01T10:00:00Z"
	Set row.LastItemId = "zzItemIdPrivate"
	Set row.LastOutcome = "act"
	Set row.LastDecisionRef = "zzDecisionRefPrivate"
	Set row.LastTraceSessionId = 77
	Set row.LastRunNowAt = "2030-01-01T09:45:00Z"
	Set row.LastSnapshotKey = "zzSnapshotKeyPrivate"
	Set row.LastQuietKey = "zzQuietKeyPrivate"
	Do $$$AssertStatusOK(row.%Save(), "the person's row is made")
	Set body = ..Get(.response)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.nextDueAt_"|"_answer.lastBeatAt_"|"_answer.lastOutcome_"|"_answer.lastRunNowAt, "2030-01-01T10:30:00Z|2030-01-01T10:00:00Z|act|2030-01-01T09:45:00Z", "the row's public members")
	Do $$$AssertEquals(answer.traceHeaderId_"|"_answer.traceNamespace, "77|"_$Namespace, "the trace pair")
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Set url = ##class(OcuTalon.Web.TraceLink).Url(77, $Namespace, , , .viewer)
	Do $$$AssertTrue(url '= "", "the trace application of the namespace gives a URL")
	Do $$$AssertEquals(answer.traceUrl, url, "and the answer carries it as traceUrl")
	Do $$$AssertEquals(answer.checklist_"|"_answer.sample, "|0", "the checklist and sample follow the view")
	Do ..AssertNoPrivate(body, session)
}

/// A read that fails is 500 server_error and sends no value: not the settings that the failed read held. The cause goes to ServerError, which logs it.
Method TestGetFails()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set ^OcuTalonTest("HeartbeatApiProbe", "read") = "fail"
	Set body = ..Get(.response, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ..#SERVERERROR), "500 server_error")
	Do $$$AssertTrue($Get(^OcuTalonTest("HeartbeatApiProbe", "logged")) [ "zz the heartbeat could not be read", "and the cause is logged")
}

/// An accepted PUT: 200 with the Saved sentence and the values; the five keys hold them, one Settings entry (channel web) records the changed keys,
/// and the SetHeartbeat reached SettingsOps once with origin web_user.
Method TestPutAccepted()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Put("{""on"":true,""interval"":60,""from"":""07:15"",""to"":""21:45"",""checklist"":""a\nb""}", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Do $$$AssertEquals(body, "{""result"":""done"",""message"":""Saved. Applies within a minute. Recorded in the audit log."",""on"":true,""interval"":60,""from"":""07:15"",""to"":""21:45"",""checklist"":""a\nb""}", "the answer")
	Do $$$AssertEquals(..KeyValues(session), "1|60|07:15|21:45|a"_$Char(10)_"b", "the five keys hold the values")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry names the session")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.setting_"|"_data.channel_"|"_data.irisUser_"|"_data.sessionRef, "heartbeat|web|"_$Username_"|"_session, "heartbeat, on web, for the IRIS user and the session")
		Do $$$AssertTrue(data.to [ "interval=60; from=07:15; to=21:45; checklist=3 characters", "its 'to' names the changed keys: "_data.to)
		Do $$$AssertTrue(data.%ToJSON() '[ "a\nb", "and holds no checklist text")
	}
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps")
	Do $$$AssertEquals(sent.%Size(), 1, "one command went from CommandsIn to SettingsOps")
	If sent.%Size() = 1 {
		Set command = $ClassMethod(sent.%Get(0).bodyClass, "%OpenId", sent.%Get(0).bodyId)
		Do $$$AssertEquals(command.%ClassName(1)_"|"_command.Origin_"|"_command.SessionRef, "OcuTalon.Msg.Command.SetHeartbeat|web_user|"_session, "a SetHeartbeat with origin web_user for the caller's session")
		Do $$$AssertEquals(command.On_"|"_command.Interval_"|"_command.From_"|"_command.To, "1|60|07:15|21:45", "with on as 1 and the interval as its text")
	}
	Set body = ..Put({"on": true, "interval": 30, "from": "", "to": "", "checklist": ""}.%ToJSON(), .response)
	Do $$$AssertEquals(body, "{""result"":""done"",""message"":""Saved. Applies within a minute. Recorded in the audit log."",""on"":true,""interval"":30,""from"":"""",""to"":"""",""checklist"":""""}", "all day: the answer holds the empty hours")
}

/// A refused value is 400 with the outcome as the code and the owner's sentence, and the keys and the audit log are as they were. An accepted save after
/// the refusals fences the audit read: once its entry is in, it must be the only one since the mark.
Method TestPutRefusals()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set first = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Put({"on": true, "interval": 60, "from": "07:15", "to": "21:45", "checklist": "zz first"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: a heartbeat is saved")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(first, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS).%Size(), 1, "control: and its entry is written")
	Set before = ..KeyValues(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set badList = "Use up to 1,000 characters, without {{ or @{."
	Set cases = $ListBuild(
		$ListBuild("interval 15", {"on": true, "interval": 15, "from": "", "to": "", "checklist": ""}.%ToJSON(), "bad_interval", ..#NOTSAVED),
		$ListBuild("interval 45", {"on": true, "interval": 45, "from": "", "to": "", "checklist": ""}.%ToJSON(), "bad_interval", ..#NOTSAVED),
		$ListBuild("interval 2880", {"on": true, "interval": 2880, "from": "", "to": "", "checklist": ""}.%ToJSON(), "bad_interval", ..#NOTSAVED),
		$ListBuild("interval 60.5", {"on": true, "interval": 60.5, "from": "", "to": "", "checklist": ""}.%ToJSON(), "bad_interval", ..#NOTSAVED),
		$ListBuild("from 07:10", {"on": true, "interval": 30, "from": "07:10", "to": "20:00", "checklist": ""}.%ToJSON(), "bad_hours", ..#NOTSAVED),
		$ListBuild("to 24:00", {"on": true, "interval": 30, "from": "08:00", "to": "24:00", "checklist": ""}.%ToJSON(), "bad_hours", ..#NOTSAVED),
		$ListBuild("from 7:15", {"on": true, "interval": 30, "from": "7:15", "to": "20:00", "checklist": ""}.%ToJSON(), "bad_hours", ..#NOTSAVED),
		$ListBuild("only from", {"on": true, "interval": 30, "from": "08:00", "to": "", "checklist": ""}.%ToJSON(), "bad_hours", ..#NOTSAVED),
		$ListBuild("only to", {"on": true, "interval": 30, "from": "", "to": "20:00", "checklist": ""}.%ToJSON(), "bad_hours", ..#NOTSAVED),
		$ListBuild("a checklist with {{", {"on": true, "interval": 30, "from": "", "to": "", "checklist": "say {{x}}"}.%ToJSON(), "bad_checklist", badList),
		$ListBuild("a checklist with @{", {"on": true, "interval": 30, "from": "", "to": "", "checklist": "say @{x}"}.%ToJSON(), "bad_checklist", badList),
		$ListBuild("a checklist with a tab", {"on": true, "interval": 30, "from": "", "to": "", "checklist": ("a"_$Char(9)_"b")}.%ToJSON(), "bad_checklist", badList),
		$ListBuild("a checklist with U+0007", {"on": true, "interval": 30, "from": "", "to": "", "checklist": ("a"_$Char(7)_"b")}.%ToJSON(), "bad_checklist", badList))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set body = ..Put($List(case, 2), .response)
		Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody($List(case, 3), $List(case, 4)), $List(case, 1)_": 400 with the outcome and the sentence")
		Do $$$AssertEquals(..KeyValues(session), before, $List(case, 1)_": the keys are as they were")
	}
	Do ..Put({"on": false, "interval": 120, "from": "", "to": "", "checklist": "zz fence"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the fence is saved")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "the fence's is the only Settings entry since the mark: no refusal wrote one")
	If entries.%Size() = 1 Do $$$AssertTrue(entries.%Get(0).data.to [ "on=0; interval=120", "and it is the fence's")
}

/// A body of the wrong shape is 400 bad_heartbeat with the Couldn't save sentence, and nothing is submitted: no command goes from CommandsIn to
/// SettingsOps, and the keys stay empty.
Method TestPutBadBody()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set bodies = $ListBuild("zz not json", "[]", """x""", "{}", "{""interval"":30,""from"":"""",""to"":"""",""checklist"":""""}", "{""on"":true,""from"":"""",""to"":"""",""checklist"":""""}", "{""on"":true,""interval"":30,""to"":"""",""checklist"":""""}", "{""on"":true,""interval"":30,""from"":"""",""checklist"":""""}", "{""on"":true,""interval"":30,""from"":"""",""to"":""""}", "{""on"":1,""interval"":30,""from"":"""",""to"":"""",""checklist"":""""}", "{""on"":""true"",""interval"":30,""from"":"""",""to"":"""",""checklist"":""""}", "{""on"":true,""interval"":""30"",""from"":"""",""to"":"""",""checklist"":""""}", "{""on"":true,""interval"":30,""from"":null,""to"":"""",""checklist"":""""}", "{""on"":true,""interval"":30,""from"":"""",""to"":5,""checklist"":""""}", "{""on"":true,""interval"":30,""from"":"""",""to"":"""",""checklist"":[""a""]}")
	Set position = 0
	While $ListNext(bodies, position, json) {
		Set body = ..Put(json, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_heartbeat", ..#NOTSAVED), json_": 400 bad_heartbeat")
	}
	Set body = ..Put("", .response, 0, 0)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_heartbeat", ..#NOTSAVED), "no body: 400 bad_heartbeat")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps").%Size(), 0, "nothing went from CommandsIn to SettingsOps")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)|(none)|(none)", "and no key was written")
}

/// A checklist of 1,001 characters is 400 bad_checklist in the route and nothing is submitted; one of 1,000 is forwarded and saved.
Method TestPutLongChecklist()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set body = ..Put({"on": true, "interval": 30, "from": "", "to": "", "checklist": ($Translate($Justify("", 1001), " ", "x"))}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_checklist", "Use up to 1,000 characters, without {{ or @{."), "1,001 characters: 400 bad_checklist")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps").%Size(), 0, "nothing was submitted")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)|(none)|(none)", "and no key was written")
	Set text = $Translate($Justify("", 1000), " ", "x")
	Set body = ..Put({"on": false, "interval": 30, "from": "", "to": "", "checklist": (text)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "1,000 characters: 200")
	Do $$$AssertEquals($Length(..KeyValue(session, "checklist")), 1000, "and the checklist is stored whole")
}

/// A sessionRef in the body is ignored: the caller's own heartbeat changes and the named session's keys do not.
Method TestPutBodyNamesSession()
{
	If '..Guard() Quit
	Set mine = ..Session()
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Session("zzheartbeatapi"_..Number_"other")
	Set ..Sessions = ..Sessions_","_theirs
	Set ..Refs = ..Refs_","_theirs
	Do ..Keep(theirs)
	Set body = ..Put({"on": false, "interval": 60, "from": "", "to": "", "checklist": "zz mine", "sessionRef": (theirs)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Do $$$AssertEquals(..KeyValues(mine), "0|60|||zz mine", "the caller's own heartbeat changed")
	Do $$$AssertEquals(..KeyValues(theirs), "(none)|(none)|(none)|(none)|(none)", "the named session's keys did not")
}

/// The owner's outcomes through the probe, and what the route submits: a SetHeartbeat for the caller's session with on as 1 or 0 and the interval as
/// text; bad_on, bad_interval, bad_hours and bad_checklist are 400 with the owner's message; failures are 500 not_saved with the owner's message as
/// given (the server_error sentence when it gave none); not_built is 501; an Ok result answers the owner's values, or the Saved sentence with no
/// message; Data that is no JSON, an error status and no result are 500 server_error.
Method TestPutOutcomes()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set values = {"on": false, "interval": 120, "from": "09:00", "to": "17:30", "checklist": "zz words"}.%ToJSON()
	Set cases = $ListBuild(
		$ListBuild("bad_on", "zz bad on"), $ListBuild("bad_interval", "zz bad interval"), $ListBuild("bad_hours", "zz bad hours"), $ListBuild("bad_checklist", "zz bad checklist"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": ($List(case, 1)), "message": ($List(case, 2))}.%ToJSON()
		Set body = ..Put(values, .response, 0, 1, ..#PROBE)
		Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody($List(case, 1), $List(case, 2)), $List(case, 1)_": 400 with the owner's message")
	}
	Set notSaved = ..#NOTSAVED
	Set mayNot = "Something went wrong inside OcuTalon, so the command may not have finished."
	Set cases = $ListBuild(
		$ListBuild("no_session", notSaved), $ListBuild("not_audited", notSaved), $ListBuild("failed", notSaved),
		$ListBuild("failed", mayNot), $ListBuild("zz_other", "zz the owner's own words"), $ListBuild("failed", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set message = $List(case, 2)
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": ($List(case, 1)), "message": (message)}.%ToJSON()
		Set body = ..Put(values, .response, 0, 1, ..#PROBE)
		Set expected = $Select(message = "": ..#SERVERERROR, 1: message)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("not_saved", expected), $List(case, 1)_" with '"_message_"': 500 not_saved with the owner's message")
	}
	Set submitted = +$Get(^OcuTalonTest("HeartbeatApiProbe", "submitted"))
	Do $$$AssertEquals(submitted, 10, "each PUT submitted one command")
	Do $$$AssertEquals(^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "session"), "SetHeartbeat|"_session, "a SetHeartbeat for the caller's session")
	Do $$$AssertEquals(^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "on")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "interval")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "from")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "to")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "checklist"), "0|120|09:00|17:30|zz words", "with the values as text")
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": "not_built", "message": "This part of OcuTalon isn't built yet. Nothing was changed."}.%ToJSON()
	Set body = ..Put(values, .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "501 Not Implemented|"_..ErrorBody("not_built", "This part of OcuTalon isn't built yet."), "not_built: 501")
	For mode = "fail", "none" {
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = mode
		Set body = ..Put(values, .response, 0, 1, ..#PROBE)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ..#SERVERERROR), mode_": 500 server_error")
		Do $$$AssertTrue($Get(^OcuTalonTest("HeartbeatApiProbe", "logged")) [ $Select(mode = "fail": "zz CommandsIn is not running", 1: "CommandsIn answered no result"), mode_": and the cause is logged")
	}
	Set data = {"on": 1, "interval": 60, "from": "", "to": "", "checklist": "zz"}.%ToJSON()
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "", "data": (data)}.%ToJSON()
	Set body = ..Put(values, .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done"",""message"":""Saved. Applies within a minute. Recorded in the audit log."",""on"":true,""interval"":60,""from"":"""",""to"":"""",""checklist"":""zz""}", "Ok with no message: 200 with the Saved sentence and the owner's values")
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "zz the owner's own words", "data": (data)}.%ToJSON()
	Set body = ..Put(values, .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals($Piece(body, ",", 2), """message"":""zz the owner's own words""", "Ok with a message: the owner's message")
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "x", "data": "zz not json"}.%ToJSON()
	Set body = ..Put(values, .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ..#SERVERERROR), "Data that is no JSON: 500 server_error")
}

/// With the real Checks, a run now of a person whose checklist is empty is 409 empty (and sets LastRunNowAt), and the next one is 409 cooldown with
/// availableAt two minutes after the first.
Method TestRunEmptyThenCooldown()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set body = ..Put({"on": false, "interval": 1440, "from": "", "to": "", "checklist": ""}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: an empty checklist is saved")
	Set body = ..Post(.response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "409 Conflict|application/json|"_..ErrorBody("empty", "Your checklist is empty."), "409 empty")
	Set row = ..Beat(session)
	Do $$$AssertTrue($IsObject(row) && (row.LastRunNowAt '= ""), "Checks recorded the request: LastRunNowAt is set")
	If '$IsObject(row) Quit
	Set at = ##class(OcuTalon.Data.Time).AddSeconds(row.LastRunNowAt, 120)
	Set body = ..Post(.response)
	Set expected = {"error": {"code": "cooldown", "message": ("You can run it again at "_##class(OcuTalon.Data.Time).ForMessage(at)_".")}, "availableAt": (at)}.%ToJSON()
	Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_expected, "the next one is 409 cooldown with availableAt two minutes after the first")
}

/// A run now with a saved checklist, the model key present and the cap not reached is 202 {"result":"sent"}: Checks sets LastRunNowAt and LastItemId.
/// A second one within 2 minutes is 409 cooldown with availableAt = LastRunNowAt + 120 seconds, and sends nothing. The beat's decision is waited for
/// before the clean-up, so that no late writer outlives the test.
Method TestRunSendsThenCoolsDown()
{
	If '..Guard() Quit
	If '..Beatable() Quit
	Set session = ..Session()
	Set text = "zz run now [[mock:decide-ignore:"_session_"]]"
	Set body = ..Put({"on": false, "interval": 1440, "from": "", "to": "", "checklist": (text)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the checklist is saved, the heartbeat off so that no Tick runs it")
	Set body = ..Post(.response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "202 Accepted|application/json|{""result"":""sent""}", "202 sent")
	Set row = ..Beat(session)
	Do $$$AssertTrue($IsObject(row), "the person has a row")
	If '$IsObject(row) Quit
	Do $$$AssertTrue(row.LastRunNowAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "Checks set LastRunNowAt: "_row.LastRunNowAt)
	Do $$$AssertTrue(row.LastItemId '= "", "and LastItemId")
	If row.LastItemId '= "" Set ..ItemIds = ..ItemIds_$ListBuild(row.LastItemId)
	Set at = ##class(OcuTalon.Data.Time).AddSeconds(row.LastRunNowAt, 120)
	Set body = ..Post(.response)
	Set expected = {"error": {"code": "cooldown", "message": ("You can run it again at "_##class(OcuTalon.Data.Time).ForMessage(at)_".")}, "availableAt": (at)}.%ToJSON()
	Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_expected, "the second is 409 cooldown with availableAt two minutes after the first")
	Set again = ..Beat(session)
	Do $$$AssertEquals(again.LastRunNowAt_"|"_again.LastItemId, row.LastRunNowAt_"|"_row.LastItemId, "and the cooldown sent nothing: the row is as it was")
	Set end = $ZHorolog + ..#WAITDECISION
	For {
		Set decision = ##class(OcuTalon.Data.Ownership).DecisionOfItem(row.LastItemId, session, .sc)
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue($IsObject(decision), "Intake recorded the beat's decision")
}

/// The outcomes of Checks through the probe: sent is 202; cooldown and backoff are 409 with their sentence (the time in the instance zone) and
/// availableAt beside the error; cap, nokey and empty are 409 with theirs and no availableAt; not_built is 501; failed, an outcome the route does not
/// know, an error status and no result are 500 server_error. The route submits a RunHeartbeat for the caller's session and reads no body.
Method TestRunOutcomes()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set at = "2030-06-15T14:12:00Z"
	Set time = ##class(OcuTalon.Data.Time).ForMessage(at)
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 1, "outcome": "sent", "message": ""}.%ToJSON()
	Set body = ..Post(.response, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "202 Accepted|{""result"":""sent""}", "sent: 202")
	Do $$$AssertEquals(^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("HeartbeatApiProbe", "submitted", 1, "session"), "RunHeartbeat|"_session, "a RunHeartbeat for the caller's session")
	Set cases = $ListBuild(
		$ListBuild("cooldown", at, "You can run it again at "_time_"."),
		$ListBuild("backoff", at, "The last beat failed, so the next one waits until "_time_"."),
		$ListBuild("cap", "", "Today's cost limit has been reached."),
		$ListBuild("nokey", "", "No model key is set."),
		$ListBuild("empty", "", "Your checklist is empty."))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set outcome = $List(case, 1), availableAt = $List(case, 2)
		Set data = $Select(availableAt '= "": {"availableAt": (availableAt)}.%ToJSON(), 1: "")
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": (outcome), "message": "zz the owner's words", "data": (data)}.%ToJSON()
		Set body = ..Post(.response, ..#PROBE)
		Set expected = {"error": {"code": (outcome), "message": ($List(case, 3))}}
		If availableAt '= "" Do expected.%Set("availableAt", availableAt, "string")
		Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_expected.%ToJSON(), outcome_": 409 with its sentence"_$Select(availableAt '= "": " and availableAt", 1: ""))
	}
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": "not_built", "message": "This part of OcuTalon isn't built yet. Nothing was changed."}.%ToJSON()
	Set body = ..Post(.response, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "501 Not Implemented|"_..ErrorBody("not_built", "This part of OcuTalon isn't built yet."), "not_built: 501")
	For outcome = "failed", "zz_unknown", "not_allowed" {
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 0, "outcome": (outcome), "message": "zz the owner's words"}.%ToJSON()
		Set body = ..Post(.response, ..#PROBE)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ..#SERVERERROR), outcome_": 500 server_error")
		Do $$$AssertTrue($Get(^OcuTalonTest("HeartbeatApiProbe", "logged")) [ outcome, outcome_": and the cause is logged")
	}
	For mode = "fail", "none" {
		Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = mode
		Set body = ..Post(.response, ..#PROBE)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", ..#SERVERERROR), mode_": 500 server_error")
	}
}

/// With no CSP session to take the OcuTalon session from, all three routes answer 500 server_error and nothing is submitted; GET also where the read
/// would succeed, and PUT and POST also where the submit would succeed, so the routes' own session checks are what refuse the calls. PUT checks the
/// session before the body, so a bad body with no session is 500 as well.
Method TestNoSessionIs500()
{
	If '..Guard() Quit
	Set error = ..ErrorBody("server_error", ..#SERVERERROR)
	Set body = ..Get(.response, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "GET: 500 server_error")
	Set body = ..Put("{""on"":true,""interval"":30,""from"":"""",""to"":"""",""checklist"":""""}", .response, 0, 1, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "PUT: 500 server_error")
	Set body = ..Put("zz not json", .response, 0, 1, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "PUT with a bad body: the session comes first")
	Set body = ..Post(.response, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "POST run: 500 server_error")
	Set ^OcuTalonTest("HeartbeatApiProbe", "read") = "defaults"
	Set body = ..Get(.response, ..#PROBE, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "GET: 500 server_error even where the read itself would succeed")
	Set ^OcuTalonTest("HeartbeatApiProbe", "submit") = {"ok": 1, "outcome": "sent", "message": ""}.%ToJSON()
	Set body = ..Post(.response, ..#PROBE, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "POST run: 500 server_error even where the submit itself would succeed")
	Do $$$AssertEquals($Get(^OcuTalonTest("HeartbeatApiProbe", "submitted")), "", "and nothing was submitted")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The preconditions of a real beat, as Test.Checks.BeatCase has them: the entries of the runners point at the CI mock key variable (OnAfterAllTests puts them
/// back), the TriageAgent's key is present and today's cost cap is not reached. 1 when they hold; otherwise a failed assertion that names the precondition, and 0.
Method Beatable() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Set keyed = ##class(OcuTalon.Bridge.Keys).Status(##class(OcuTalon.Checks.Beat).#AGENT)
	Do $$$AssertEquals(keyed, 1, "precondition: the TriageAgent's key is present (Bridge.Keys.Status)")
	Set capped = ##class(OcuTalon.Bridge.Budget).State().capped
	Do $$$AssertEquals(+capped, 0, "precondition: the daily cost cap is not reached (Bridge.Budget.State)")
	Quit (keyed = 1) && 'capped
}

/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Keep(ref)
	Set ..Current = ref
	Quit ref
}

/// Keeps the session's TraceRef for the clean-up of the messages.
Method Keep(ref As %String) [ Private ]
{
	Do ..Traces.%Push(..TraceOf(ref))
}

/// The TraceRef of the session.
Method TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// The person's HeartbeatBeat row as stored now, or "".
ClassMethod Beat(session As %String) As OcuTalon.Data.HeartbeatBeat [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The answer holds none of the row's private fields and not the SessionRef.
Method AssertNoPrivate(body As %String, session As %String) [ Private ]
{
	For private = session, "zzItemIdPrivate", "zzDecisionRefPrivate", "zzSnapshotKeyPrivate", "zzQuietKeyPrivate", "lastItemId", "lastDecisionRef", "lastSnapshotKey", "lastQuietKey", "sessionRef" {
		Do $$$AssertEquals(body [ private, 0, "the answer does not hold '"_private_"'")
	}
}

/// The stored value of the session's heartbeat key of the name, "(none)" for a key with no row.
Method KeyValue(session As %String, name As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Checks.Beat).SettingKey(session, name))
	Quit $Select($IsObject(row): row.Value, 1: "(none)")
}

/// The stored values of the session's five heartbeat keys as on|interval|from|to|checklist, "(none)" for a key with no row.
Method KeyValues(session As %String) As %String [ Private ]
{
	Quit ..KeyValue(session, "on")_"|"_..KeyValue(session, "interval")_"|"_..KeyValue(session, "from")_"|"_..KeyValue(session, "to")_"|"_..KeyValue(session, "checklist")
}

/// Calls GetHeartbeat of the class with the stand-in request and the current session (none with noSession) and returns what it wrote.
Method Get(Output response, class As %String = "OcuTalon.Web.Api", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	Quit ..Run("GetHeartbeat", class, .response, noSession)
}

/// Calls PutHeartbeat of the class with the stand-in request whose body is json (its UTF-8 bytes with binary 1; no body at all with hasBody 0) and the
/// current session (none with noSession) and returns what it wrote.
Method Put(json As %String, Output response, binary As %Boolean = 0, hasBody As %Boolean = 1, class As %String = "OcuTalon.Web.Api", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	If hasBody {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json, binary)
	} Else {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "PUT")
	}
	Quit ..Run("PutHeartbeat", class, .response, noSession)
}

/// Calls RunHeartbeat of the class with a stand-in request that has no body and the current session (none with noSession) and returns what it wrote.
Method Post(Output response, class As %String = "OcuTalon.Web.Api", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "POST")
	Quit ..Run("RunHeartbeat", class, .response, noSession)
}

/// Runs the method of the class as the CSP session of the current session; the caller has set %request.
Method Run(method As %String, class As %String, Output response, noSession As %Boolean) As %String [ Private ]
{
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	If 'noSession {
		Set %session = ##class(%CSP.Session).%New("ZzHeartbeatApi"_..Number, 0)
		Set %session.Data("OcuTalon.SessionRef") = ..Current
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, class, method)
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

}
