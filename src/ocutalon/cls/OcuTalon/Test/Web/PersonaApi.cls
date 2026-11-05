/// Tests of GET and PUT /v1/persona (Story 40.8; FR-67, FR-68, FR-70; AD-1, AD-4, AD-13, AD-17, AD-19), called with stand-in request and
/// response objects and a CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.PairingApi does), through the real
/// production: PUT submits through Commands.Submit, CommandsIn sends the SetPersona to the real SettingsOps, which validates, audits and
/// writes. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): where OcuTalon.Production does not run every test fails with that
/// reason, so that a broken stack can never give a green shard. The failures that the real items never give go through
/// Test.Web.PersonaApiProbe. The expected texts are written out here, never read from SettingsOps. The onlineDemo setting is put back in
/// OnAfterAllTests, the persona keys of the fixture sessions are removed with SettingsOps.ForgetPerson, and the fixture rows and the sessions'
/// messages are removed.
///   - TestGetDefaults: a session with no keys reads Professional, custom offered, nothing pending, the keys in order and as strings;
///   - TestGetSavedAndDemo: a saved language is read back; the online demo reads customOffered false;
///   - TestGetPending: pendingRef is the newest pending setting request of the session, and not a fix request, an answered request or
///     another session's request;
///   - TestGetFails: a failed read is 500 server_error and sends no value;
///   - TestPutPreset: an accepted preset is 200 with the Saved sentence, the keys hold it, one Settings entry (web) records it, and the
///     SetPersona reached SettingsOps with origin web_user;
///   - TestPutLanguageOutsideAscii: a language name outside ASCII comes back as the same characters in PUT and GET, and the entry names it;
///   - TestPutCustomIsAString: a custom text of digits is a JSON string in both answers and is in no audit entry;
///   - TestPutUnusedValues: values the preset does not use are stored empty;
///   - TestPutRefusals: a refused language name, custom text, custom text on the online demo and preset are 400 with the outcome as the code
///     and the owner's sentence, and the keys and the audit log are as they were;
///   - TestPutOnlineDemoPreset: a preset is accepted on the online demo;
///   - TestPutBadBody: a body of the wrong shape is 400 bad_persona and nothing is submitted;
///   - TestPutBodyNamesSession: a sessionRef in the body is ignored;
///   - TestPutSaveFailed: an outcome that is a failure is 500 not_saved with the owner's message as given;
///   - TestPutNotBuilt: not_built is 501 not_built;
///   - TestPutNotDelivered: an error status or no result from the submit is 500 server_error;
///   - TestPutOkFromOwner: an Ok result answers the owner's message and values, or the Saved sentence with no message, and one whose Data
///     is not JSON is 500 server_error;
///   - TestNoSessionIs500: with no CSP session both routes answer 500 server_error and write nothing.
Class OcuTalon.Test.Web.PersonaApi Extends %UnitTest.TestCase
{

/// The longest to wait for an audit entry, in seconds.
Parameter SECONDS = 20;

/// The class of the stand-in whose seams answer the failures.
Parameter PROBE = "OcuTalon.Test.Web.PersonaApiProbe";

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions, for ForgetPerson.
Property Sessions As %String(MAXLEN = "");

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The value of the public setting onlineDemo before the run.
Property SavedDemo As %String;

/// The session that the stand-in CSP session is bound to.
Property Current As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("PersonaApi", "n"))
	Set ..Traces = []
	Set ..Refs = ""
	Set ..Sessions = ""
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
	Kill ^OcuTalonTest("PersonaApiProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Kill ^OcuTalonTest("PersonaApiProbe")
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Core.SettingsOps).ForgetPerson($Piece(..Sessions, ",", i))
	}
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// A session with no keys reads Professional with empty language and custom, custom offered and nothing pending: the five keys in this
/// order, the values with their JSON types.
Method TestGetDefaults()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set body = ..Get(.response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Do $$$AssertEquals(body, "{""preset"":""professional"",""language"":"""",""custom"":"""",""customOffered"":true,""pendingRef"":""""}", "Professional, custom offered, nothing pending")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)", "and nothing was written")
}

/// A saved language is read back (preset language, language Spanish); on the online demo customOffered is false.
Method TestGetSavedAndDemo()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set body = ..Put("{""preset"":""language"",""language"":""Spanish""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the language is saved")
	Set body = ..Get(.response)
	Do $$$AssertEquals(body, "{""preset"":""language"",""language"":""Spanish"",""custom"":"""",""customOffered"":true,""pendingRef"":""""}", "GET reads the saved language")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..Get(.response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(response.Status, "200 OK", "200 on the online demo")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.%GetTypeOf("customOffered")_"|"_answer.customOffered, "boolean|0", "customOffered is the JSON false on the online demo")
}

/// pendingRef is the Ref of the newest pending setting request that the session owns, by the time it was raised: the newer one is the
/// row made first. A fix request, an answered request and another session's request are not reported.
Method TestGetPending()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set newer = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "", "pending", "2030-01-01T10:00:00Z", {"Kind": "setting"})
	Set older = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "", "pending", "2030-01-01T09:00:00Z", {"Kind": "setting"})
	Set fix = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "", "pending", "2030-01-01T11:00:00Z")
	Set done = ##class(OcuTalon.Test.Data.Fixture).Approval(session, "", "done", "2030-01-01T12:00:00Z", {"Kind": "setting"})
	Set other = ##class(OcuTalon.Test.Data.Fixture).Approval(##class(OcuTalon.Bridge.Ids).NewRef(), "", "pending", "2030-01-01T13:00:00Z", {"Kind": "setting"})
	Set ..Refs = ..Refs_","_older_","_newer_","_fix_","_done_","_other
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Do $$$AssertEquals(answer.pendingRef, newer, "pendingRef is the newest pending setting request of the session")
	Do $$$AssertEquals(answer.%GetTypeOf("pendingRef"), "string", "as a string")
}

/// A read that fails is 500 server_error and sends no value: not the defaults, and not the values that the failed read held. The cause
/// goes to ServerError, which logs it.
Method TestGetFails()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set ^OcuTalonTest("PersonaApiProbe", "read") = "fail"
	Set body = ..Get(.response, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "500 server_error")
	Do $$$AssertTrue($Get(^OcuTalonTest("PersonaApiProbe", "logged")) [ "zz the persona could not be read", "and the cause is logged")
}

/// An accepted preset: 200 {"result":"done","message","preset","language","custom"} with the Saved sentence. The three keys hold it, one
/// Settings entry (channel web) records the old form and the new one, and the SetPersona reached SettingsOps once with origin web_user.
/// GET reads the same session before and after the change.
Method TestPutPreset()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Do $$$AssertEquals({}.%FromJSON(..Get(.response)).preset, "professional", "GET reads the default before the change")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Put("{""preset"":""pirate""}", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Do $$$AssertEquals(body, "{""result"":""done"",""message"":""Saved. Applies from your next message. Recorded in the audit log."",""preset"":""pirate"",""language"":"""",""custom"":""""}", "the answer")
	Do $$$AssertEquals(..KeyValues(session), "pirate||", "the three keys hold it")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry names the session")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to_"|"_data.channel, "persona|professional|pirate|web", "persona, from the old form to pirate, on web")
	}
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps")
	Do $$$AssertEquals(sent.%Size(), 1, "one command went from CommandsIn to SettingsOps")
	If sent.%Size() = 1 {
		Set command = $ClassMethod(sent.%Get(0).bodyClass, "%OpenId", sent.%Get(0).bodyId)
		Do $$$AssertEquals(command.%ClassName(1)_"|"_command.Origin_"|"_command.SessionRef, "OcuTalon.Msg.Command.SetPersona|web_user|"_session, "a SetPersona with origin web_user for the caller's session")
	}
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(answer.preset, "pirate", "GET reads it after the change")
}

/// A language name outside ASCII (Portugues with an e circumflex): the same characters come back in PUT and GET, and the entry's "to" is
/// "language: " and the name.
Method TestPutLanguageOutsideAscii()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set name = "Portugu"_$Char(234)_"s (Brasil)"
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Put({"preset": "language", "language": (name)}.%ToJSON(), .response, 1)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.preset_"|"_answer.language_"|"_answer.custom, "language|"_name_"|", "PUT answers the same characters")
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(answer.preset_"|"_answer.language, "language|"_name, "GET answers the same characters")
	Do $$$AssertEquals(..KeyValues(session), "language|"_name_"|", "and the row holds them")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.to, "language: "_name, "its 'to' is language: and the name")
}

/// A custom text of digits on a local install: the JSON string "12345" in PUT and GET, and no audit entry of the session holds the text.
Method TestPutCustomIsAString()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Put("{""preset"":""custom"",""custom"":""12345""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.%GetTypeOf("custom")_"|"_answer.custom, "string|12345", "PUT answers the string")
	Do $$$AssertTrue(body [ """custom"":""12345""", "in the JSON text it is quoted")
	Set answer = {}.%FromJSON(..Get(.response))
	Do $$$AssertEquals(answer.%GetTypeOf("custom")_"|"_answer.custom_"|"_answer.preset, "string|12345|custom", "GET answers the string")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "", "", "12345").%Size(), 0, "and no audit entry holds the text")
}

/// Values that the preset does not use are stored empty: pirate with a language and a custom text keeps neither.
Method TestPutUnusedValues()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set body = ..Put("{""preset"":""pirate"",""language"":""!!"",""custom"":""{{""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.preset_"|"_answer.language_"|"_answer.custom, "pirate||", "the answer holds both empty")
	Do $$$AssertEquals(..KeyValues(session), "pirate||", "and so do the keys")
}

/// A refused value is 400 with the outcome as the code and the owner's sentence, and the keys and the audit log are as they were. An
/// accepted save after the refusals fences the audit read: once its entry is in, it must be the only one since the mark.
Method TestPutRefusals()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set first = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Put("{""preset"":""pirate""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: a pirate persona is saved")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(first, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS).%Size(), 1, "control: and its entry is written")
	Set before = ..KeyValues(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set long = $Translate($Justify("", 1001), " ", "a")
	Set unknown = "Couldn't save. Nothing was changed."
	Set badLanguage = "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters."
	Set badCustom = "Use up to 1,000 characters, without {{ or @{."
	Set notOffered = "On the online demo you can choose a preset or a language. Your choice lasts for this visit."
	Set cases = $ListBuild(
		$ListBuild("a bad language name", {"preset": "language", "language": "Spanish!"}.%ToJSON(), 0, "bad_language", badLanguage),
		$ListBuild("a custom text of 1,001 characters", {"preset": "custom", "custom": (long)}.%ToJSON(), 0, "bad_custom", badCustom),
		$ListBuild("a custom text with {{", {"preset": "custom", "custom": "say {{x}}"}.%ToJSON(), 0, "bad_custom", badCustom),
		$ListBuild("a custom text with @{", {"preset": "custom", "custom": "say @{x}"}.%ToJSON(), 0, "bad_custom", badCustom),
		$ListBuild("custom on the online demo", {"preset": "custom", "custom": "zz"}.%ToJSON(), 1, "custom_not_offered", notOffered),
		$ListBuild("an unknown preset", {"preset": "zz"}.%ToJSON(), 0, "bad_preset", unknown),
		$ListBuild("an empty preset", {"preset": ""}.%ToJSON(), 0, "bad_preset", unknown))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Select($List(case, 3): 1, 1: ""))
		Set body = ..Put($List(case, 2), .response)
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
		Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody($List(case, 4), $List(case, 5)), label_": 400 with the outcome and the sentence")
		Do $$$AssertEquals(..KeyValues(session), before, label_": the keys are as they were")
	}
	Do ..Put("{""preset"":""kindfriend""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: the fence is saved")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "the fence's is the only Settings entry since the mark: no refusal wrote one")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.to, "kindfriend", "and it is the fence's")
}

/// On the online demo a preset is accepted as anywhere else.
Method TestPutOnlineDemoPreset()
{
	If '..Guard() Quit
	Set session = ..Session()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set body = ..Put("{""preset"":""kindfriend""}", .response)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done"",""message"":""Saved. Applies from your next message. Recorded in the audit log."",""preset"":""kindfriend"",""language"":"""",""custom"":""""}", "200 as for any accepted preset")
	Do $$$AssertEquals(..KeyValues(session), "kindfriend||", "and the keys hold it")
}

/// A body of the wrong shape is 400 bad_persona with the Couldn't save sentence, and nothing is submitted: no command goes from CommandsIn
/// to SettingsOps, and the keys stay empty.
Method TestPutBadBody()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set bodies = $ListBuild("zz not json", "[]", """pirate""", "{}", "{""preset"":5}", "{""preset"":null}", "{""preset"":""language"",""language"":5}", "{""preset"":""language"",""language"":null}", "{""preset"":""custom"",""custom"":null}", "{""preset"":""custom"",""custom"":true}", "{""preset"":""pirate"",""custom"":[""a""]}")
	Set position = 0
	While $ListNext(bodies, position, json) {
		Set body = ..Put(json, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_persona", "Couldn't save. Nothing was changed."), json_": 400 bad_persona")
	}
	Set body = ..Put("", .response, 0, 0)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_persona", "Couldn't save. Nothing was changed."), "no body: 400 bad_persona")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps").%Size(), 0, "nothing went from CommandsIn to SettingsOps")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)", "and no key was written")
}

/// A sessionRef in the body is ignored: the caller's own persona changes and the named session's keys do not.
Method TestPutBodyNamesSession()
{
	If '..Guard() Quit
	Set mine = ..Session()
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Session("zzpersonaapi"_..Number_"other")
	Set ..Sessions = ..Sessions_","_theirs
	Set ..Refs = ..Refs_","_theirs
	Do ..Keep(theirs)
	Set body = ..Put("{""preset"":""pirate"",""sessionRef"":"""_theirs_"""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "200")
	Do $$$AssertEquals(..KeyValues(mine), "pirate||", "the caller's own persona changed")
	Do $$$AssertEquals(..KeyValues(theirs), "(none)|(none)|(none)", "the named session's keys did not")
}

/// Values that the preset does not use never reach SetPersona (Story 40.6; DW-669): a 100 KB custom text and language with the preset
/// professional are answered 200 and the SetPersona sent has Language and Custom empty; a language preset drops the custom text and a
/// custom preset drops the language. Nothing is judged about a value the preset does not use.
Method TestPutDropsUnusedValues()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set big = $Translate($Justify("", 100000), " ", "x")
	Set body = ..Put({"preset": "professional", "language": (big), "custom": (big)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "professional with a 100 KB language and custom text is 200")
	Set command = ..SentCommand(trace, 1)
	Do $$$AssertEquals(command.Preset_"|"_command.Language_"|"_command.Custom, "professional||", "the SetPersona has empty Language and Custom")
	Do $$$AssertEquals(..KeyValues(session), "professional||", "and the keys hold professional alone")
	Set body = ..Put({"preset": "language", "language": "Spanish", "custom": (big)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a language preset with a 100 KB custom text is 200")
	Set command = ..SentCommand(trace, 2)
	Do $$$AssertEquals(command.Preset_"|"_command.Language_"|"_command.Custom, "language|Spanish|", "the SetPersona has an empty Custom")
	Set body = ..Put({"preset": "custom", "language": (big), "custom": "Speak plainly."}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a custom preset with a 100 KB language is 200")
	Set command = ..SentCommand(trace, 3)
	Do $$$AssertEquals(command.Preset_"|"_command.Language_"|"_command.Custom, "custom||Speak plainly.", "the SetPersona has an empty Language")
}

/// A used value over its limit is refused in the route with SettingsOps' code and message and nothing is submitted: a custom text of 1,001
/// units is 400 bad_custom and a language of 41 characters is 400 bad_language. A custom text of 1,000 units and a language of 40
/// characters are forwarded and saved.
Method TestPutBoundsUsedValues()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set body = ..Put({"preset": "custom", "custom": ($Translate($Justify("", 1001), " ", "x"))}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_custom", "Use up to 1,000 characters, without {{ or @{."), "a custom text of 1,001 units: 400 bad_custom")
	Set body = ..Put({"preset": "language", "language": ($Translate($Justify("", 41), " ", "a"))}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_..ErrorBody("bad_language", "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters."), "a language of 41 characters: 400 bad_language")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps").%Size(), 0, "nothing was submitted")
	Do $$$AssertEquals(..KeyValues(session), "(none)|(none)|(none)", "and no key was written")
	Set custom = $Translate($Justify("", 1000), " ", "x")
	Set body = ..Put({"preset": "custom", "custom": (custom)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a custom text of 1,000 units is 200")
	Set command = ..SentCommand(trace, 1)
	Do $$$AssertEquals($Length(command.Custom)_"|"_command.Preset, "1000|custom", "and it is forwarded whole")
	Set language = $Translate($Justify("", 40), " ", "a")
	Set body = ..Put({"preset": "language", "language": (language)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a language of 40 characters is 200")
	Set command = ..SentCommand(trace, 2)
	Do $$$AssertEquals(command.Language_"|"_command.Preset, language_"|language", "and it is forwarded whole")
}

/// The nth SetPersona that went from CommandsIn to SettingsOps in the trace session, as the command object, or "".
Method SentCommand(trace As %String, n As %Integer) As OcuTalon.Msg.Command.SetPersona [ Private ]
{
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SettingsOps")
	Do $$$AssertTrue(sent.%Size() >= n, "at least "_n_" command(s) went to SettingsOps")
	If sent.%Size() < n Quit ""
	Quit $ClassMethod(sent.%Get(n - 1).bodyClass, "%OpenId", sent.%Get(n - 1).bodyId)
}

/// An outcome that is a failure is 500 not_saved with the owner's message as given: SettingsOps' sentence for its own outcomes,
/// CommandsIn's for a failed command, and a message of the owner that this route does not know. An owner that gave no message gets the
/// server_error sentence, never a claim that nothing changed. The command carries the caller's session, the body's preset and the values
/// that the preset uses unchanged (the language of the language preset, here one that SettingsOps would refuse: the route does not judge
/// its characters); a value that the preset does not use is dropped (Story 40.6, DW-669).
Method TestPutSaveFailed()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set notSaved = "Couldn't save. Nothing was changed."
	Set mayNot = "Something went wrong inside OcuTalon, so the command may not have finished."
	Set cases = $ListBuild(
		$ListBuild("no_session", notSaved), $ListBuild("not_audited", notSaved), $ListBuild("failed", notSaved),
		$ListBuild("failed", mayNot), $ListBuild("zz_other", "zz the owner's own words"),
		$ListBuild("failed", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set message = $List(case, 2)
		Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 0, "outcome": ($List(case, 1)), "message": (message)}.%ToJSON()
		Set body = ..Put("{""preset"":""language"",""language"":""zz !!"",""custom"":""zz {{""}", .response, 0, 1, ..#PROBE)
		Set expected = $Select(message = "": "Something went wrong inside OcuTalon. Try again.", 1: message)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("not_saved", expected), $List(case, 1)_" with '"_message_"': 500 not_saved with the owner's message")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("PersonaApiProbe", "submitted")), $ListLength(cases), "each PUT submitted one command")
	Do $$$AssertEquals(^OcuTalonTest("PersonaApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("PersonaApiProbe", "submitted", 1, "preset"), session_"|language", "for the caller's session, with the body's preset")
	Do $$$AssertEquals(^OcuTalonTest("PersonaApiProbe", "submitted", 1, "language")_"|"_^OcuTalonTest("PersonaApiProbe", "submitted", 1, "custom"), "zz !!|", "and the used language unchanged, the unused custom text dropped")
}

/// not_built is 501 not_built with the not-built sentence, as for Unpair and DismissIncident.
Method TestPutNotBuilt()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 0, "outcome": "not_built", "message": "This part of OcuTalon isn't built yet. Nothing was changed."}.%ToJSON()
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "501 Not Implemented|"_..ErrorBody("not_built", "This part of OcuTalon isn't built yet."), "501 not_built")
}

/// A submit that gives an error status, or no result object, is 500 server_error, and the cause goes to ServerError, which logs it.
Method TestPutNotDelivered()
{
	If '..Guard() Quit
	Set session = ..Session()
	For mode = "fail", "none" {
		Set ^OcuTalonTest("PersonaApiProbe", "submit") = mode
		Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), mode_": 500 server_error")
		Do $$$AssertTrue($Get(^OcuTalonTest("PersonaApiProbe", "logged")) [ $Select(mode = "fail": "zz CommandsIn is not running", 1: "CommandsIn answered no result"), mode_": and the cause is logged")
	}
}

/// An Ok result answers the owner's message and the values it saved, whatever the body held; with no message it answers the Saved
/// sentence, not an error sentence. An Ok result whose Data is not JSON is 500 server_error.
Method TestPutOkFromOwner()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set data = {"preset": "pirate", "language": "", "custom": ""}.%ToJSON()
	Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "", "data": (data)}.%ToJSON()
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done"",""message"":""Saved. Applies from your next message. Recorded in the audit log."",""preset"":""pirate"",""language"":"""",""custom"":""""}", "200 with the Saved sentence")
	Set data = {"preset": "kindfriend", "language": "zz language", "custom": "zz words"}.%ToJSON()
	Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "zz the owner's own words", "data": (data)}.%ToJSON()
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done"",""message"":""zz the owner's own words"",""preset"":""kindfriend"",""language"":""zz language"",""custom"":""zz words""}", "200 with the owner's message and values")
	Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "x", "data": "zz not json"}.%ToJSON()
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "Data that is no JSON: 500 server_error")
}

/// With no CSP session to take the OcuTalon session from, both routes answer 500 server_error and nothing is submitted; GET does so also
/// where the persona read would succeed, and PUT also where the submit would succeed, so the routes' own session checks are what refuse
/// the calls. PUT checks the session before the body, so a bad body with no session is 500 as well.
Method TestNoSessionIs500()
{
	If '..Guard() Quit
	Set error = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set body = ..Get(.response, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "GET: 500 server_error")
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "PUT: 500 server_error")
	Set body = ..Put("zz not json", .response, 0, 1, "OcuTalon.Web.Api", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "PUT with a bad body: the session comes first")
	Set ^OcuTalonTest("PersonaApiProbe", "read") = "defaults"
	Set body = ..Get(.response, ..#PROBE, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "GET: 500 server_error even where the read itself would succeed")
	Set data = {"preset": "pirate", "language": "", "custom": ""}.%ToJSON()
	Set ^OcuTalonTest("PersonaApiProbe", "submit") = {"ok": 1, "outcome": "saved", "message": "x", "data": (data)}.%ToJSON()
	Set body = ..Put("{""preset"":""pirate""}", .response, 0, 1, ..#PROBE, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "PUT: 500 server_error even where the submit itself would succeed")
	Do $$$AssertEquals($Get(^OcuTalonTest("PersonaApiProbe", "submitted")), "", "and nothing was submitted")
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

/// The stored values of the session's three persona keys as preset|language|custom, "(none)" for a key with no row.
Method KeyValues(session As %String) As %String [ Private ]
{
	Set values = ""
	For name = "preset", "language", "custom" {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Core.SettingsOps).PersonaKey(session, name))
		Set values = values_$Select(values = "" && (name = "preset"): "", 1: "|")_$Select($IsObject(row): row.Value, 1: "(none)")
	}
	Quit values
}

/// Calls GetPersona of the class with the stand-in request and the current session (none with noSession) and returns what it wrote.
Method Get(Output response, class As %String = "OcuTalon.Web.Api", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	Quit ..Run("GetPersona", class, .response, noSession)
}

/// Calls PutPersona of the class with the stand-in request whose body is json (its UTF-8 bytes with binary 1; no body at all with
/// hasBody 0) and the current session (none with noSession) and returns what it wrote.
Method Put(json As %String, Output response, binary As %Boolean = 0, hasBody As %Boolean = 1, class As %String = "OcuTalon.Web.Api", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	If hasBody {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json, binary)
	} Else {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "PUT")
	}
	Quit ..Run("PutPersona", class, .response, noSession)
}

/// Runs the method of the class as the CSP session of the current session; the caller has set %request.
Method Run(method As %String, class As %String, Output response, noSession As %Boolean) As %String [ Private ]
{
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	If 'noSession {
		Set %session = ##class(%CSP.Session).%New("ZzPersonaApi"_..Number, 0)
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
