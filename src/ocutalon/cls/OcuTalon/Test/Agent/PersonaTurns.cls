/// Tests that the persona reaches the agents as a data block and changes nothing but wording (Story 40.3; AD-7, AD-22, AD-28, FR-67).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, and FRESH: the production's
/// jobs keep the code they started with, so a warm stack would run old agents. A message goes through WebChatIn to the real
/// Conversation, the real Decide and the real Chat and Triage runners, against the CI mock, and the mock's request log shows what each
/// request carried (Test.Contract.Mock.LogSince). The persona is saved with a real SetPersona through Commands.Submit. Each run's
/// marker key is the run's number and the preset, so that a countdown and a log entry are the test's own. Every test removes the
/// countdowns it armed, and the rows of the run's sessions are removed with their persona rows.
///   - TestCommand, TestWatch, TestWatchUnknown and TestStatus (AC 4, AC 7): for each of the six presets a session saves it and asks
///     for the scenario's turn. The turn's Triage request and its Chat requests hold the persona block on the newest user message
///     (the opening line, the preset's text, the language line for Another language, the style line for Starship computer, Pirate,
///     Kind friend and Your own words only), and Professional's requests hold none. The reply is the catalog sentence, the UX
///     sentence of a started watch or "I looked at the Orders production for you.", the status turn has the key and the rows of the
///     watch's passed row, no reserved wording is left, and the decision's outcome is the script's;
///   - TestTriageItem (AC 5): an untrusted item that a session owns, sent to Intake, is triaged with the block as above, and the
///     Decision row's outcome and confidence are the script's under every preset;
///   - TestDiagnosisHasNoBlock (AC 6): the Diagnosis request of an incident of a Pirate session holds no persona block;
///   - TestPirateStyle (AC 8): the reply filter removes "Everything is fine." and nothing of the Pirate style in the reply, the stored
///     reasons and the done chat.message;
///   - TestNextMessage (AC 9): a saved change applies to the very next message, with no wait.
Class OcuTalon.Test.Agent.PersonaTurns Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzpersturn";

/// The longest to wait for a turn or a decision through the mock, in seconds.
Parameter WAIT = 90;

/// The presets, in the order of PERSONAPRESET.
Parameter PRESETS = "professional,starship,pirate,kindfriend,language,custom";

/// The language that a session on Another language names.
Parameter LANGUAGE = "Portuguese (Brazil)";

/// The text of a session on Your own words.
Parameter CUSTOM = "Be brief and dry.";

/// The opening line of the block, and the style line, as the UX gives them.
Parameter OPENING = "Persona block (from this person's settings; it shapes wording only, never what you do):";

Parameter STYLE = "This persona may open with a greeting and use exclamation marks and emoji.";

/// The scenarios of the run whose countdown a test armed, comma-separated markers; OnAfterOneTest clears them.
Property Armed As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Armed, ",") {
		If $Piece(..Armed, ",", i) '= "" Do ##class(OcuTalon.Test.Contract.Mock).Arm($Piece(..Armed, ",", i), "")
	}
	Set ..Armed = ""
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Core.SettingsOps).ForgetPerson($Piece(..Sessions, ",", i))
	}
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

/// AC 4 and AC 7: a refused command is the catalog sentence, under every preset.
Method TestCommand()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set sentence = ##class(OcuTalon.Msg.Catalog).Render("agent.noCommands", "", "web", .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders agent.noCommands")
	Do $$$AssertEquals(sentence, "I can't run commands. I can check productions, read failed messages and propose fixes that wait for your approval.", "and it is the sentence of the catalog")
	For i = 1:1:$Length(..#PRESETS, ",") {
		Set preset = $Piece(..#PRESETS, ",", i)
		Set session = ..Session("cmd"_preset)
		If '..Save(session, preset, "cmd") Continue
		Set row = ..Ask(session, "persona-command", preset, .entries)
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.ReplyText, sentence, preset_": the reply is the catalog sentence of agent.noCommands")
		Do ..AssertDecided(row, preset)
	}
}

/// AC 4 and AC 7: a started watch is the UX sentence, under every preset.
Method TestWatch()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	For i = 1:1:$Length(..#PRESETS, ",") {
		Set preset = $Piece(..#PRESETS, ",", i)
		Set session = ..Session("watch"_preset)
		If '..Save(session, preset, "watch") Continue
		Set row = ..Ask(session, "persona-watch", preset, .entries)
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.ReplyText, "I'll watch the Orders production and stay quiet unless something needs you.", preset_": the reply is the UX sentence of a started watch")
		Do ..AssertDecided(row, preset)
	}
}

/// AC 4 and AC 7: an unknown production is the catalog sentence with the name and the list, under every preset.
Method TestWatchUnknown()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set sentence = ##class(OcuTalon.Msg.Catalog).Render("watch.unknownProduction", {"name": "Nowhere", "list": "Orders"}, "web", .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders watch.unknownProduction")
	Do $$$AssertEquals(sentence, "I can't find a production called 'Nowhere'. I can see: Orders. Which one did you mean?", "and it is the sentence of the catalog with the name and the list")
	For i = 1:1:$Length(..#PRESETS, ",") {
		Set preset = $Piece(..#PRESETS, ",", i)
		Set session = ..Session("unknown"_preset)
		If '..Save(session, preset, "unknown") Continue
		Set row = ..Ask(session, "persona-watch-unknown", preset, .entries)
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.ReplyText, sentence, preset_": the reply is the catalog sentence of watch.unknownProduction")
		Do ..AssertDecided(row, preset)
	}
}

/// AC 4 and AC 7: the status turn keeps the code's own key and rows, and the guard removes the reserved wording, under every preset.
Method TestStatus()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	For i = 1:1:$Length(..#PRESETS, ",") {
		Set preset = $Piece(..#PRESETS, ",", i)
		Set session = ..Session("status"_preset)
		If '..Save(session, preset, "status") Continue
		Set ref = ..Watch(session)
		Set ranAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set check = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
		If '$IsObject(check) { Do $$$AssertTrue(0, preset_": the watch's row opens") Continue }
		Set check.Result = "passed"
		Set check.Finding = ""
		Set check.LastRunAt = ranAt
		Set check.NextDueAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(ranAt, 86400)
		Do $$$AssertStatusOK(check.%Save(), preset_": the watch has a recorded passed run")
		Set row = ..Ask(session, "persona-status", preset, .entries)
		If '$IsObject(row) Continue
		Do $$$AssertEquals(row.ReplyText, "I looked at the Orders production for you.", preset_": the reply is the scenario's last sentence alone: the reserved wording is gone")
		Do ..AssertNoAllClear(row.ReplyText)
		Do $$$AssertEquals(row.CheckKey, "checks.allPassed", preset_": the key is checks.allPassed: the all-clear comes from the code")
		Set expected = [{"result": "passed", "entry": "Orders production", "finding": "", "checkedAt": (ranAt)}]
		Do $$$AssertEquals(row.CheckRows, expected.%ToJSON(), preset_": the rows are the one passed row of the watch")
		Do ..AssertDecided(row, preset)
	}
}

/// AC 5: Triage decides an untrusted item that a session owns with the block in its request, and decides it as the script says.
Method TestTriageItem()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	For i = 1:1:$Length(..#PRESETS, ",") {
		Set preset = $Piece(..#PRESETS, ",", i)
		Set session = ..Session("item"_preset)
		If '..Save(session, preset, "item") Continue
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set marker = "persona-triage:"_..Key(preset)
		Set token = "[[mock:"_marker_"]]"
		Set item = ##class(OcuTalon.Msg.Item).%New()
		Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set item.SessionRef = session
		Set item.Channel = "mailbox"
		Set item.Provenance = "untrusted"
		Set item.Sender = "zz Dana"
		Set item.Subject = "Invoice"
		Set item.Text = "zz body "_token
		Set ..ItemIds = ..ItemIds _ $ListBuild(item.ItemId)
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Do $$$AssertStatusOK(..SendFrom("Intake", item, trace), preset_": the item is sent to Intake")
		Set decision = ..WaitDecision(item.ItemId, "decide")
		Do $$$AssertTrue($IsObject(decision), preset_": Decide recorded the item's decision")
		If '$IsObject(decision) Continue
		Do $$$AssertEquals(decision.Outcome_"|"_decision.Confidence_"|"_decision.Fallback, "ignore|.4|0", preset_": the outcome and the confidence are the script's, with no fallback")
		Do ..AssertLog(preset, mark, marker, token, "the item")
	}
}

/// AC 6: a Diagnosis request never carries the block, whatever the owner's persona.
Method TestDiagnosisHasNoBlock()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("diagnosis")
	If '..Save(session, "pirate", "diagnosis") Quit
	Do ..Watch(session)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set failures = [{"item": (..Item("persona")), "text": "[[mock:diagnosis-unknown]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))}]
	Do $$$AssertStatusOK(..SendBatch("ZZNS", "Zz.Persona", session, failures), "a failure is sent for the Pirate session")
	Set rows = ..WaitIncident(session, "Zz.Persona", 1)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident")
	If rows.%Size() '= 1 Quit
	Set ref = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set seen = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= "diagnosis-unknown") Continue
		Set seen = seen + 1
		Do $$$AssertEquals($Find(entry.%ToJSON(), "Persona block"), 0, "Diagnosis request "_seen_" holds no persona block")
	}
	Do $$$AssertTrue(seen > 0, "a Diagnosis request was logged: "_seen)
}

/// AC 8: the reply filter removes the all-clear sentence and nothing of the Pirate style.
Method TestPirateStyle()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set boat = $WChar(128674)
	Set session = ..Session("style")
	If '..Save(session, "pirate", "style") Quit
	Set row = ..Ask(session, "persona-pirate-style", "pirate", .entries)
	If '$IsObject(row) Quit
	Set reply = "Ahoy, shipmate! The Orders production sails on! "_boat
	Do $$$AssertEquals(row.ReplyText, reply, "the reply keeps the greeting, the exclamation marks and the emoji, and 'Everything is fine.' is gone")
	Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decision), "the triage decision is recorded")
	If $IsObject(decision) Do $$$AssertEquals(decision.Reasons, "Ahoy, shipmate! A question from the user; the user is answered directly. "_boat, "the stored reasons keep the greeting, the exclamation mark and the emoji, and the sentence is gone")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message", 3, ..#WAIT)
	Set done = ""
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.payload.ref = row.Ref) && (event.payload.state = "done") Set done = event.payload
	}
	Do $$$AssertTrue($IsObject(done), "the stream holds the done chat.message of the turn")
	If $IsObject(done) Do $$$AssertEquals(done.replyText, reply, "and it carries the same reply")
}

/// AC 9: a change of persona applies to the very next message: the save and the message have no wait between them.
Method TestNextMessage()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("next")
	If '..Save(session, "pirate", "next0") Quit
	Set row = ..Ask(session, "persona-command", "pirate", .entries, "p", 1)
	If '$IsObject(row) Quit
	If '..Save(session, "kindfriend", "next1") Quit
	Set row = ..Ask(session, "persona-command", "kindfriend", .entries, "a", 1)
	If '$IsObject(row) Quit
	If '..Save(session, "professional", "next2") Quit
	Set row = ..Ask(session, "persona-command", "professional", .entries, "b", 1)
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.ReplyText, ##class(OcuTalon.Msg.Catalog).Render("agent.noCommands", "", "web"), "the last turn's reply is the catalog sentence")
}

/// --- helpers ---
/// The marker key of the run for the preset (and a suffix): the run's number and the preset.
Method Key(preset As %String, suffix As %String = "") As %String [ Private ]
{
	Quit ..Number_preset_suffix
}

/// Saves the persona of the session with a real SetPersona through Commands.Submit; 1 when it was carried out.
Method Save(session As %String, preset As %String, tag As %String) As %Boolean [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetPersona).%New()
	Set command.SessionRef = session
	Set command.Preset = preset
	If preset = "language" Set command.Language = ..#LANGUAGE
	If preset = "custom" Set command.Custom = ..#CUSTOM
	Set command.IdempotencyKey = "zzkey"_..Number_preset_tag_$Increment(^OcuTalonTest("PersonaTurns", "key"))
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertStatusOK(sc, preset_": SetPersona reaches SettingsOps")
	If '$IsObject(result) || (result.Ok '= 1) {
		Do $$$AssertTrue(0, preset_": SetPersona is carried out: "_$Select($IsObject(result): result.Message, 1: "no result"))
		Quit 0
	}
	Quit 1
}

/// Arms the countdown of the scenario's marker (key: the run and the preset) at 1, sends the message through WebChatIn, and gives
/// the Turn once it is done (or "" with a failed assertion). entries are the mock's log entries of the marker from the send on, and
/// the requests are checked for the block (AssertLog).
Method Ask(session As %String, scenario As %String, preset As %String, Output entries As %DynamicArray, suffix As %String = "", newestOnly As %Boolean = 0) As OcuTalon.Data.Turn [ Private ]
{
	Set marker = scenario_":"_..Key(preset, suffix)
	Set token = "[[mock:"_marker_"]]"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, 1), "the countdown of "_marker_" is armed at 1")
	Set ..Armed = ..Armed_$Select(..Armed = "": "", 1: ",")_marker
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set clientId = "zzp"_..Number_scenario_preset_suffix
	Do $$$AssertStatusOK(..Send(session, clientId, "Hello "_token, .output), preset_": the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, preset_": the Turn is done within "_..#WAIT_" seconds")
		Quit ""
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey, "done||", preset_": the Turn is done and no fallback")
	Do ..AssertLog(preset, mark, marker, token, "the turn", 1, newestOnly)
	Quit row
}

/// The decision of the triage request of the turn is the script's tell-now, whatever the preset.
Method AssertDecided(row As OcuTalon.Data.Turn, preset As %String) [ Private ]
{
	Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(row.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decision), preset_": the triage decision is recorded")
	If $IsObject(decision) Do $$$AssertEquals(decision.Outcome_"|"_decision.Confidence_"|"_decision.Fallback, "tellnow|.9|0", preset_": the outcome and the confidence are the script's, with no fallback")
}

/// The mock's requests of the marker after the mark, for the preset: the user message that holds the token carries the block in AD-7's form
/// (and only a bending preset or Your own words the style line), or, for Professional, no "Persona block" at all. A turn (chat is 1)
/// has at least one Triage request (no tools) and one Chat request (tools); an item has at least one Triage request. With newestOnly
/// Professional's check reads the newest user message alone, since the saved history of a linked Chat session still holds the blocks
/// of the earlier messages.
Method AssertLog(preset As %String, mark As %Integer, marker As %String, token As %String, what As %String, chat As %Boolean = 0, newestOnly As %Boolean = 0) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set triage = 0
	Set chats = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || (entry.marker '= marker) Continue
		Set isChat = (entry.request.tools.%Size() > 0)
		If isChat Set chats = chats + 1
		If 'isChat Set triage = triage + 1
		Set label = preset_": the "_$Select(isChat: "Chat", 1: "Triage")_" request of "_what
		Set text = ..UserText(entry.request, token)
		Do $$$AssertTrue(text [ token, label_" has the user message with the token")
		If preset = "professional" {
			Do $$$AssertEquals($Find($Select(newestOnly: text, 1: entry.%ToJSON()), "Persona block"), 0, label_" holds no persona block"_$Select(newestOnly: " in its newest user message", 1: ""))
			Continue
		}
		Do $$$AssertTrue(text [ ..#OPENING, label_" holds the opening line")
		Do $$$AssertEquals($Find(text, token) > $Find(text, ..#OPENING), 1, label_" has the block before the item")
		If preset = "language" {
			Do $$$AssertTrue(text [ ("Reply in the language named: "_..#LANGUAGE_"."), label_" names the language")
		} ElseIf preset = "custom" {
			Do $$$AssertTrue(text [ ("> "_..#CUSTOM), label_" quotes the person's text")
		} Else {
			Do $$$AssertTrue(text [ ("> "_##class(OcuTalon.Agent.Persona).Preset(preset).text), label_" quotes the preset's text")
		}
		Do $$$AssertEquals(text [ ..#STYLE, (preset '= "language"), label_" has the style line only for a preset that bends the rules and for Your own words")
	}
	Do $$$AssertTrue(triage > 0, "a Triage request of "_what_" was logged for "_preset_": "_triage)
	If chat Do $$$AssertTrue(chats > 0, "a Chat request of the turn was logged for "_preset_": "_chats)
}

/// The text of the message of the request that holds the token, "" when none does.
ClassMethod UserText(request As %DynamicObject, token As %String) As %String [ Private ]
{
	Set iterator = request.messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		Set text = ""
		If message.%GetTypeOf("content") = "string" {
			Set text = message.content
		} ElseIf message.%GetTypeOf("content") = "array" {
			Set blocks = message.content.%GetIterator()
			While blocks.%GetNext(, .block) {
				If block.%GetTypeOf("text") = "string" Set text = text_block.text
			}
		}
		If (message.role = "user") && (text [ token) Quit
		Set text = ""
	}
	Quit text
}

/// The decision of the item and kind once there is one, or "" after WAIT seconds.
Method WaitDecision(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set decision = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(itemId, kind)
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit decision
}

/// Sends the message to the item from a SimMailboxIn host created in this process, with the SuperSession given.
Method SendFrom(target As %String, message As %Library.Persistent, superSession As %String) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set service.%SuperSession = superSession
	Quit service.SendRequestAsync(target, message)
}

/// Asserts that the text holds no phrase of the guard's two lists, ignoring case.
Method AssertNoAllClear(text As %String) [ Private ]
{
	Set phrases = $ListFromString($Parameter("OcuTalon.Checks.ReplyGuard", "RESERVED")_","_$Parameter("OcuTalon.Checks.ReplyGuard", "BANNED"))
	Set position = 0
	While $ListNext(phrases, position, phrase) {
		Do $$$AssertNotTrue($ZConvert(text, "L") [ $ZConvert(phrase, "L"), "the reply does not say '"_phrase_"'")
	}
}

}
