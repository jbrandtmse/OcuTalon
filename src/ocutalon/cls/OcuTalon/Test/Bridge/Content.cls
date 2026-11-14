/// Tests of the content extension and of the runner's image path (Story 26.3; AD-6, AD-7, AD-9, AD-20, AD-31, FR-5). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), except
/// TestBaseSendsNothing and TestMerge, which need nothing: the others send requests through Decide to the runner ChatAgent and the CI mock, so they need the CI
/// override's environment, and they put the helper Test.Bridge.ContentProbe behind the ContentClass setting of the Decide item of the running production (RunnerFixture UseItemSetting)
/// and put the setting back. Where they lack the environment they fail with the reason and send nothing to a real model API. The image is a 4 by 4 red PNG; the mock logs whole
/// messages, so its request log shows what the model call carried. Each test deletes the Decision, Usage and step rows of its requests and the AI sessions it saved.
///   - TestRunnerSendsTheImage (Task 0, the runner pin): an untrusted turn whose ItemId the probe names is sent to the model as one user message of a text block and one base64 image block
///     (media type image/png, the file's bytes), with max_tokens 8,000 and none of temperature, top_p and top_k; the Reply is the scenario's text with no fallback; one Usage row and the
///     Decision totals hold the call (input and output tokens above 0, a cost); the step renderer fired (one model step with a summary and no image bytes); Part was called once,
///     for that turn, in the runner's job, and Accepted once, after the Decision row was saved, with the filtered text; and no AI session was saved or linked;
///   - TestUserTurnUsesChat: the same request with provenance user, with the probe naming it, is a plain Chat: Part is not called, the model's request holds no image block, and the
///     turn is answered;
///   - TestPartErrorMakesNoCall: an error status of Part ends the request before any model call (the mock's log holds nothing for it), Decide takes the fallback route (Fallback 1) and
///     Accepted is not called;
///   - TestAcceptedOnlyOnAccept: a refusal, an empty reply and a cut-off reply are fallbacks that never call Accepted, and carry no member of it;
///   - TestAcceptedMembersMerged: the members that Accepted answers are in the reply's HostData, and a mode that answers no member leaves the reply as it is; and, on OcuTalon's image,
///     a turn whose runner already put a member of its own (the scenario photo-recall: search_memories finds a stored memory of the owner and puts HostData.memories) carries both that
///     member and the one of Accepted;
///   - TestAcceptedFailureKeepsTheReply: an error status and an exception from Accepted leave the reply unchanged (text, no fallback, the same Decision row), add no member and log one warning
///     of Decide's Accept;
///   - TestBaseSendsNothing: the base class gives no content and no member, and with the base named in the setting an untrusted turn is sent as text only and its HostData is unchanged
///     (the bridge alone, FR-5);
///   - TestMerge: HostData.Merge returns the JSON with each member set, replaces a member of the same name, keeps the others, takes a non-object or empty json as an empty object, keeps types,
///     and returns json unchanged for empty or non-object members.
/// The repeatability of the shipped Part is pinned in Test.Agent.Content (TestPartRepeatable).
Class OcuTalon.Test.Bridge.Content Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter PROBE = "OcuTalon.Test.Bridge.ContentProbe";

/// The text of the scenario photo-caption.
Parameter CAPTION = "The photo shows a small red square on a white background.";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// What the stored configuration of the production had of the item settings that the test changed, as a dynamic array of {"item","saved"}, to be put back.
Property Swaps As %DynamicArray;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The owners whose memories the test stored (Test.Memory.Fixture.Store), comma-separated.
Property Owners As %String(MAXLEN = "") [ Transient ];

Method OnBeforeAllTests() As %Status
{
	Set sc = $$$OK
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
		Merge ^||OcuTalonTestBridgeContent = state
		Do ##class(OcuTalon.Memory.Embedding).Embed("warm the embedder", .vector)
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ContentProbe")
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ContentProbe")
	For i = 1:1:$Length(..Owners, ",") {
		If $Piece(..Owners, ",", i) '= "" Do ##class(OcuTalon.Test.Memory.Fixture).Purge($Piece(..Owners, ",", i))
	}
	Set ..Owners = ""
	Set running = $ClassMethod(..#FIXTURE, "Running")
	If running Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If $IsObject(..Swaps) {
		For i = ..Swaps.%Size() - 1:-1:0 {
			Do $ClassMethod(..#FIXTURE, "RestoreItemSetting", ..Swaps.%Get(i).item, ..Swaps.%Get(i).saved)
		}
		Set ..Swaps = ""
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys")
	}
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Merge state = ^||OcuTalonTestBridgeContent
		Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	}
	Kill ^||OcuTalonTestBridgeContent
	Quit $$$OK
}

/// An untrusted turn with a photo goes to the model as a text block and one image block, and the rest of the runner's rules hold (the Task 0 measurement, kept as the pin).
Method TestRunnerSendsTheImage()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set ^OcuTalonTest("ContentProbe", "item") = request.ItemId
	Set eventMark = $ClassMethod(..#FIXTURE, "EventMark")
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, ..#CAPTION, "the reply is the scenario's text")
	Do $$$AssertEquals(answer.Fallback_"|"_answer.FallbackReason, "0|", "with no fallback")
	Do $$$AssertEquals(answer.Tainted, 1, "and the turn that sent an image is tainted")
	Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Do $$$AssertEquals(requests.%Size(), 1, "the mock got one request for the turn")
	Set logged = requests.%Get(0)
	Do $$$AssertEquals(logged.status_"|"_logged.scenario, "200|photo-caption", "which ran the scenario of the marker")
	Set messages = logged.request.messages
	Do $$$AssertEquals(messages.%Size(), 1, "it holds one message")
	Do $$$AssertEquals(messages.%Get(0).role, "user", "of the user")
	Set blocks = messages.%Get(0).content
	Do $$$AssertEquals(blocks.%Size(), 2, "with two blocks")
	If blocks.%Size() '= 2 Quit
	Set text = blocks.%Get(0), image = blocks.%Get(1)
	Do $$$AssertEquals(text.type, "text", "the first is a text block")
	Do $$$AssertTrue(text.text [ "Describe the photo.", "that holds the turn's text")
	Do $$$AssertEquals(image.type, "image", "the second is an image block")
	Do $$$AssertEquals(image.source.type_"|"_image.source."media_type", "base64|image/png", "of base64 data, image/png")
	Do $$$AssertEquals(image.source.data, $Parameter(..#PROBE, "PNG"), "which is the file's bytes")
	Do $$$AssertEquals(logged.maxTokens, 8000, "the cap is 8,000")
	For name = "temperature", "top_p", "top_k" {
		Do $$$AssertEquals(logged.request.%IsDefined(name), 0, "the request has no "_name)
	}
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "turn")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Fallback, 0, "the Decision row is a normal one")
		Do $$$AssertTrue((row.InputTokens > 0) && (row.OutputTokens > 0) && (row.CostUSD '= ""), "with the tokens and the cost of the call: "_$ClassMethod(..#FIXTURE, "Totals", row))
		Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Totals", row), $ClassMethod(..#FIXTURE, "Totals", answer), "the reply carries the same totals")
	} Else {
		Do $$$AssertTrue(0, "the Decision row is recorded")
	}
	Set usage = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), SUM(InputTokens), SUM(OutputTokens) FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", ref)
	Do usage.%Next()
	Do $$$AssertTrue((usage.%GetData(1) = 1) && (usage.%GetData(2) > 0) && (usage.%GetData(3) > 0), "one Usage row holds the call: "_usage.%GetData(1)_" row, "_usage.%GetData(2)_" in, "_usage.%GetData(3)_" out")
	Set links = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ?", request.OwnerRef)
	Do links.%Next()
	Do $$$AssertEquals(links.%GetData(1), 0, "no conversation link names an AI session")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "SessionMark"), ..SessionMark, "and no AI session was saved")
	Do $$$AssertEquals(..Part(1), $ListBuild("turn", "untrusted", request.ItemId), "Part was called once, for the turn")
	Do $$$AssertEquals(^OcuTalonTest("ContentProbe", "part"), 1, "and only once")
	Do $$$AssertEquals(^OcuTalonTest("ContentProbe", "accepted"), 1, "Accepted was called once")
	Do $$$AssertEquals($Get(^OcuTalonTest("ContentProbe", "accepted", 1)), $ListBuild(request.ItemId, ..#CAPTION), "with the item and the filtered reply text")
	Set hostData = {}.%FromJSON(answer.HostData)
	Do $$$AssertEquals(hostData.probe.text, ..#CAPTION, "and its member is in the reply's HostData")
	Set steps = ..StepsOf(answer.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 1, "the step renderer recorded one model step")
	If steps.%Size() = 1 {
		Do $$$AssertEquals(steps.%Get(0).kind, "model", "of kind model")
		Do $$$AssertTrue((steps.%Get(0).summary '= "") && '(steps.%Get(0).summary [ $Extract($Parameter(..#PROBE, "PNG"), 1, 40)), "with a summary that holds no image bytes")
	}
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "LogRowsHolding", eventMark, $Extract($Parameter(..#PROBE, "PNG"), 1, 40)), 0, "and the event log holds none of the image")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks($Parameter(..#PROBE, "PNG")), "", "no message body, header or log holds the image's base64")
}

/// A turn with provenance user is a plain Chat: the probe is never asked for a part, and the model's request holds no image.
Method TestUserTurnUsesChat()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	Set request = ..NewTurn("user", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set ^OcuTalonTest("ContentProbe", "item") = request.ItemId
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text_"|"_answer.Fallback, ..#CAPTION_"|0", "the turn is answered")
	Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Do $$$AssertEquals(requests.%Size(), 1, "with one model request")
	If requests.%Size() = 1 Do $$$AssertEquals(..ImageBlocks(requests.%Get(0)), 0, "that holds no image block")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "part")), 0, "Part was never called")
}

/// An error status of Part ends the request before any model call; Decide takes its fallback route and never calls Accepted.
Method TestPartErrorMakesNoCall()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	Set ^OcuTalonTest("ContentProbe", "partError") = "The photo cannot be opened."
	Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set ^OcuTalonTest("ContentProbe", "item") = request.ItemId
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Fallback, 1, "with a fallback reply")
	Do $$$AssertTrue(answer.FallbackReason '= "", "and a reason: "_answer.FallbackReason)
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Drain", "ChatAgent"), $$$OK, "the runner has handled everything sent to it")
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", ..LogMark, .after), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FindRequests", after, ref).%Size(), 0, "no model request was made")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "part")), 1, "Part was asked once")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "accepted")), 0, "and Accepted was never called")
}

/// A reply that Decide classifies as unusable never calls Accepted and carries no member of it.
Method TestAcceptedOnlyOnAccept()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	For case = $ListBuild("refusal", "refusal"), $ListBuild("empty", "empty"), $ListBuild("max-tokens", "cut_off") {
		Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:"_$List(case, 1)_"]]", .ref)
		Set ^OcuTalonTest("ContentProbe", "item") = request.ItemId
		Set sc = ..Ask(request, .answer, .entries)
		Do $$$AssertStatusOK(sc, $List(case, 1)_": Decide answers the turn")
		If '$IsObject(answer) Continue
		Do $$$AssertEquals(answer.Fallback_"|"_answer.FallbackReason, "1|"_$List(case, 2), $List(case, 1)_": a fallback with that reason")
		Do $$$AssertEquals(answer.HostData '[ "probe", 1, $List(case, 1)_": no member of Accepted")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "accepted")), 0, "Accepted was never called")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "part")), 3, "though Part was asked for each of the three")
}

/// The members of Accepted join the others in the reply's HostData; a mode that answers none leaves it as it is.
Method TestAcceptedMembersMerged()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set ^OcuTalonTest("ContentProbe", "mode") = "none"
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn with a mode that gives no member")
	If $IsObject(answer) Do $$$AssertEquals(answer.HostData, "", "the reply's HostData is empty, as the runner left it")
	Set ^OcuTalonTest("ContentProbe", "mode") = "members"
	Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn with a member")
	If $IsObject(answer) Do $$$AssertEquals(answer.HostData, {"probe": {"text": (..#CAPTION)}}.%ToJSON(), "the reply's HostData is the member")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ContentProbe", "accepted")), 2, "Accepted was called once for each turn")
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: the runner's own member needs a stored memory, embedded by a worker")
		Quit
	}
	// The runner's own member: search_memories puts HostData.memories for a memory of the owner, and Accepted adds its member beside it.
	Set request = ..NewTurn("untrusted", "What was in the photo I sent? [[mock:photo-recall]]", .ref)
	Set ..Owners = request.OwnerRef
	Set memoryRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set text = "The photo shows a small red square on a white background."
	Set saved = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(request.OwnerRef, memoryRef, text, saved), "a memory of the owner is stored")
	Set ^OcuTalonTest("ContentProbe", "mode") = "members"
	Set ^OcuTalonTest("ContentProbe", "item") = request.ItemId
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn whose runner puts a member of its own")
	If '$IsObject(answer) || (answer.HostData = "") {
		Do $$$AssertTrue(0, "the reply carries a HostData")
		Quit
	}
	Set hostData = {}.%FromJSON(answer.HostData)
	Do $$$AssertEquals(answer.Fallback, 0, "the turn is no fallback")
	Do $$$AssertEquals(hostData.%Size(), 2, "the HostData holds two members: the runner's and the one of Accepted")
	Set found = hostData.memories
	Do $$$AssertEquals($IsObject(found) && (found.%Size() = 1) && (found.%Get(0).memoryRef = memoryRef) && (found.%Get(0).text = text), 1, "the runner's member memories names the stored memory")
	Do $$$AssertEquals($IsObject(hostData.probe) && (hostData.probe.text = answer.Text), 1, "and the member probe of Accepted holds the reply's text")
}

/// An error status and an exception from Accepted leave the reply as it is, and Decide logs a warning.
Method TestAcceptedFailureKeepsTheReply()
{
	If '..Prepare() Quit
	Do ..Use(..#PROBE)
	For mode = "error", "throw" {
		Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
		Set ^OcuTalonTest("ContentProbe", "mode") = mode
		Set mark = $ClassMethod(..#FIXTURE, "EventMark")
		Set sc = ..Ask(request, .answer, .entries)
		Do $$$AssertStatusOK(sc, mode_": Decide answers the turn")
		If '$IsObject(answer) Continue
		Do $$$AssertEquals(answer.Text_"|"_answer.Fallback, ..#CAPTION_"|0", mode_": the reply is unchanged and not a fallback")
		Do $$$AssertEquals(answer.HostData, "", mode_": with no member")
		Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Warnings", mark, "OcuTalon.Bridge.Process.Decide", "Accept", $ListBuild(answer.DecisionRef)), 1, mode_": one warning of Accept names the decision")
		Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "turn")
		Do $$$AssertTrue($IsObject(row) && (row.Fallback = 0) && (row.Ref = answer.DecisionRef), mode_": the Decision row stands")
	}
}

/// The bridge alone: the base gives no content and no member, and a turn is then sent as text only.
Method TestBaseSendsNothing()
{
	Set base = "OcuTalon.Bridge.Ext.Content"
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn", request.Provenance = "untrusted", request.ItemId = "zz", request.OwnerRef = "zz"
	Do $$$AssertStatusOK($ClassMethod(base, "Part", request, .mediaType, .data), "the base Part answers OK")
	Do $$$AssertEquals(mediaType_"|"_data, "|", "with no media type and no stream")
	Do $$$AssertStatusOK($ClassMethod(base, "Accepted", request, "text", .hostData), "the base Accepted answers OK")
	Do $$$AssertEquals(hostData.%ToJSON(), "{}", "with no member")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Ext.Accessor).Check("ContentClass", base), "the accessor knows the setting against the base")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Ext.Accessor).Check("ContentClass", "OcuTalon.Bridge.Ext.TurnTools"), "and refuses a class that is not of it")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Process.Decide", "SETTINGS") [ "ContentClass:Extensions", 1, "ContentClass is a setting of Decide in the category Extensions")
	If '..Prepare() Quit
	Do ..Use(base)
	Set request = ..NewTurn("untrusted", "Describe the photo. [[mock:photo-caption]]", .ref)
	Set sc = ..Ask(request, .answer, .entries)
	Do $$$AssertStatusOK(sc, "Decide answers the turn with the base named")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Text_"|"_answer.Fallback_"|"_answer.HostData_"|"_answer.Tainted, ..#CAPTION_"|0||0", "the reply is the text, nothing is merged and the turn is not tainted")
	Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one model request")
	If requests.%Size() = 1 Do $$$AssertEquals(..ImageBlocks(requests.%Get(0)), 0, "with no image block")
}

/// HostData.Merge, a pure method: members set one by one, a member replaces one of the same name, the others stay, and a bad json is an empty object.
Method TestMerge()
{
	Set merge = "OcuTalon.Bridge.HostData"
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "", {"a": 1}), "{""a"":1}", "an empty json becomes an object that holds the member")
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "{""a"":1,""b"":""x""}", {"c": [1], "d": {"e": true}}), "{""a"":1,""b"":""x"",""c"":[1],""d"":{""e"":true}}", "members are added and the others stay, an array and an object included")
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "{""a"":1,""b"":2}", {"a": "new"}), "{""a"":""new"",""b"":2}", "a member of the same name is replaced")
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "not json", {"a": 1}), "{""a"":1}", "a json that does not parse counts as empty")
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "[1,2]", {"a": 1}), "{""a"":1}", "a json that is not an object counts as empty")
	Set members = {}
	Do members.%Set("flag", 1, "boolean")
	Do members.%Set("none", "", "null")
	Do members.%Set("text", "1", "string")
	Do $$$AssertEquals($ClassMethod(merge, "Merge", "{}", members), "{""flag"":true,""none"":null,""text"":""1""}", "a boolean, a null and a string keep their types")
	For json = "", "{""a"":1}", "not json", "[1]" {
		Do $$$AssertEquals($ClassMethod(merge, "Merge", json, {}), json, "an empty members object returns '"_json_"' unchanged")
		Do $$$AssertEquals($ClassMethod(merge, "Merge", json, ""), json, "no members returns '"_json_"' unchanged")
		Do $$$AssertEquals($ClassMethod(merge, "Merge", json, "text"), json, "members that are not an object return '"_json_"' unchanged")
		Do $$$AssertEquals($ClassMethod(merge, "Merge", json, [1]), json, "an array of members returns '"_json_"' unchanged")
	}
}

/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the mock key variable. Otherwise the test
/// fails with the reason and quits; OnAfterAllTests puts the entries back. Today's day mark is removed first, so that no earlier class leaves the day capped.
Method Prepare() As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Puts the class behind the ContentClass setting of Decide; OnAfterOneTest puts the setting back.
Method Use(class As %String) [ Private ]
{
	Set sc = $ClassMethod(..#FIXTURE, "UseItemSetting", "Decide", "Host", "ContentClass", class, .saved)
	Do $$$AssertStatusOK(sc, "the ContentClass of Decide is "_class)
	If '$IsObject(..Swaps) Set ..Swaps = []
	If $IsObject(saved) Do ..Swaps.%Push({"item": "Decide", "saved": (saved)})
}

/// A turn request of the provenance whose ItemId is its reference, and whose owner is a reference of its own.
Method NewTurn(provenance As %String, text As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", provenance, text, .ref, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// Sends the request through Decide; answer is the Reply and entries the mock's log since the send.
Method Ask(request As OcuTalon.Bridge.Msg.Request, Output answer As %Persistent, Output entries As %DynamicArray) As %Status [ Private ]
{
	Set ..LogMark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .answer)
	Do $ClassMethod(..#MOCK, "LogSince", ..LogMark, .entries)
	Quit sc
}

/// The mock's log mark of the last Ask.
Property LogMark As %Integer [ Transient ];

/// The note of the nth call of Part.
ClassMethod Part(n As %Integer) As %List [ Private ]
{
	Quit $Get(^OcuTalonTest("ContentProbe", "part", n))
}

/// The number of image blocks in the messages of a logged request.
ClassMethod ImageBlocks(logged As %DynamicObject) As %Integer [ Private ]
{
	Set count = 0
	Set messages = logged.request.messages.%GetIterator()
	While messages.%GetNext(, .message) {
		If message.%GetTypeOf("content") '= "array" Continue
		Set blocks = message.content.%GetIterator()
		While blocks.%GetNext(, .block) {
			If block.type = "image" Set count = count + 1
		}
	}
	Quit count
}

/// The AgentStep rows of the decision, once the AgentSteps operation has written them (a poll of up to 10 seconds).
ClassMethod StepsOf(decisionRef As %String) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + 10
	For {
		Set steps = $ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "StepsOf", decisionRef)
		If (steps.%Size() > 0) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit steps
}

}
