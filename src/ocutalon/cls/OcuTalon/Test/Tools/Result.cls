/// Tests of the shared base of the built-in tools, OcuTalon.Tools.Result (Story 1.9; AD-10, NFR-3; Consistency Conventions: Tool results). The pure tests
/// begin a bridge context, call Result.Return and read the running total in the context (ToolResultChars). TestStepCap runs a tool through the real
/// runner and the CI mock. THAT TEST RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like Test.Bridge.Runner: the requests go to the CI mock, so the test
/// needs the CI override's environment and the mock's request log, and where it has neither it fails with the reason and builds no provider.
/// The room of one model step is 10,000 tokens, which is 40,000 characters.
///   - TestWhole: a result that fits comes back unchanged (a dynamic object stays the same object) and its length is added to the total, up to a total of
///     exactly the room;
///   - TestCut: the result that crosses the room is cut to fit with the note, which says how many characters are shown of how many, the piece shown is
///     the start of the text, the whole is at most what was left and the total is the room; a later result is the note alone;
///   - TestLeftOut: a result that arrives when less room than the note remains is the note alone; it fits the room when the note does and passes it, by the
///     note, when it does not, once for each such result;
///   - TestRoomResets: the step renderer's OnMessage sets the total to 0, so the next model step has a full room again;
///   - TestBegin: a new context starts the total at 0, and ToolResultChars is a field of the context;
///   - TestNoContext: with no context Return measures against a fresh room and keeps nothing;
///   - TestUnknownTotal: a value whose text cannot be built whole (it is longer than the longest string) is left out, and the note gives unknown as the total;
///   - TestNote: the note is ASCII and at most 56 characters for the longest numbers;
///   - TestOwnMethodsAreTools: a class that extends Result is offered to the model with its own methods only, never Return or the other methods of Result;
///   - TestStepCap: through the real runner and the mock (scenario result-cap), a first response asks for a text and an object of 30,000 characters each:
///     the model's next request carries the text whole and the object's JSON cut to fit, ending with the note, together at most 40,000 characters; a second
///     response asks for a text of 1,000 characters and the request after it carries it whole, because the room started again; the reply is the scenario's text.
/// Every test ends the context it began, and removes the Usage rows that ZzRunner wrote.
Class OcuTalon.Test.Tools.Result Extends %UnitTest.TestCase
{

/// The class under test.
Parameter RESULT = "OcuTalon.Tools.Result";

/// The tool class of the tool result fixtures.
Parameter TOOL = "OcuTalon.Test.Tools.ZzResultTool";

/// The runner test class, whose helper makes the shadow runner.
Parameter RUNNERTEST = "OcuTalon.Test.Bridge.Runner";

/// The room of one model step in characters: 10,000 tokens at 4 characters a token.
Parameter ROOM = 40000;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", "ZzRunner")
	Quit $$$OK
}

/// A result that fits the room that is left comes back as it is, with its type: the same object for a dynamic object, the same text for a string. Its length
/// (the length of its JSON for an object) is added to the total. A text of exactly what is left fits.
Method TestWhole()
{
	Do ..Begin()
	Set object = {"items": []}
	Set back = ..Return(object)
	Do $$$AssertTrue($IsObject(back) && (back = object), "a dynamic object that fits comes back as the same object")
	Do $$$AssertEquals(..Total(), 12, "and the 12 characters of its JSON are used")
	Set back = ..Return("plain text")
	Do $$$AssertEquals(back, "plain text", "a string that fits comes back as it is")
	Do $$$AssertEquals(..Total(), 22, "and its 10 characters are added")
	Set left = ..#ROOM - 22
	Set text = ..Filler(left)
	Do $$$AssertEquals(..Return(text), text, "a text of exactly what is left, "_left_" characters, fits")
	Do $$$AssertEquals(..Total(), ..#ROOM, "and the total is the room")
	Set back = ..Return("")
	Do $$$AssertEquals(back, "", "an empty text fits a room that is used up exactly")
	Do $$$AssertEquals(..Total(), ..#ROOM, "and adds nothing")
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", 0)
	Set object = {"data": (..Filler(39989))}
	Set back = ..Return(object)
	Do $$$AssertTrue($IsObject(back) && (back = object), "an object whose JSON is exactly the room, "_$Length(object.%ToJSON())_" characters, comes back whole")
	Do $$$AssertEquals(..Total(), ..#ROOM, "and fills it")
}

/// The result that crosses the room is cut: the first characters of its text that fit with a line break and the note, so that the whole is at most what was left;
/// the note says how many characters are shown of how many; the total becomes the room. It is a string, also for an object. A result after it is the note alone.
Method TestCut()
{
	Do ..Begin()
	Set first = ..Filler(30000)
	Do $$$AssertEquals(..Return(first), first, "a text of 30,000 characters fits an empty room")
	Set object = {"data": (..Filler(30000))}
	Set json = object.%ToJSON()
	Set left = ..#ROOM - 30000
	Set back = ..Return(object)
	Do $$$AssertTrue('$IsObject(back), "an object that does not fit comes back as a string: cut JSON is no object")
	Set shown = ..ExpectedShown(left, $Length(json))
	Do $$$AssertTrue(shown > 9000, "control: about "_shown_" of its "_$Length(json)_" characters can be shown")
	Set expected = $Extract(json, 1, shown)_$Char(10)_..Note(shown, $Length(json))
	Do $$$AssertEquals(back, expected, "it is the first "_shown_" characters of its JSON, a line break and the note")
	Do $$$AssertTrue($Length(back) '> left, "and it fits what was left: "_$Length(back)_" of "_left)
	Do $$$AssertEquals(..Total(), ..#ROOM, "the total is the room")
	Set later = ..Return("one more")
	Do $$$AssertEquals(later, ..Note(0, 8), "a result after it is the note alone, with 0 characters shown")
	Do $$$AssertEquals(..Total(), ..#ROOM + $Length(..Note(0, 8)), "and its note is added to the total")
	Set later = ..Return({"items": []})
	Do $$$AssertEquals(later, ..Note(0, 12), "so is an object, with the length of its JSON as the total")

	// a text, cut, shows its start
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", 0)
	Set text = ..Filler(45000)
	Set back = ..Return(text)
	Set shown = ..ExpectedShown(..#ROOM, 45000)
	Do $$$AssertEquals(back, $Extract(text, 1, shown)_$Char(10)_..Note(shown, 45000), "a text of 45,000 characters is cut to its first "_shown_" characters and the note")
	Do $$$AssertTrue($Length(back) '> ..#ROOM, "which is at most the room")
	Do $$$AssertEquals(..Total(), ..#ROOM, "and fills it")
}

/// A result that arrives when less room than its piece and the note need remains is the note alone, with no character of it shown. The note fits the room when
/// the room that is left is at least its length, and passes it, by the note, when it is not: a step passes its room only that way, by one note for each such
/// result.
Method TestLeftOut()
{
	Do ..Begin()
	Set note = ..Note(0, 100)
	Set text = ..Filler(100)
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", ..#ROOM - $Length(note) - 1)
	Do $$$AssertEquals(..Return(text), note, "with the length of the note and one character left, the result is the note alone")
	Do $$$AssertEquals(..Total(), ..#ROOM - 1, "which fits: the total is one below the room")
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", ..#ROOM - $Length(note))
	Do $$$AssertEquals(..Return(text), note, "with exactly the length of the note left, it is the note alone too")
	Do $$$AssertEquals(..Total(), ..#ROOM, "and the total is the room")
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", ..#ROOM - $Length(note) + 1)
	Do $$$AssertEquals(..Return(text), note, "with less than the length of the note left, it is still the note alone")
	Do $$$AssertEquals(..Total(), ..#ROOM + 1, "and the total passes the room, by one character")
	Do ##class(OcuTalon.Bridge.Context).Put("ToolResultChars", ..#ROOM - 10)
	Do $$$AssertEquals(..Return(text), note, "with 10 characters left, the note alone")
	Do $$$AssertEquals(..Total(), ..#ROOM - 10 + $Length(note), "the total passes the room by the note less the 10 characters")
	Do $$$AssertEquals(..Return(text), note, "the next result is the note alone too")
	Do $$$AssertEquals(..Total(), ..#ROOM - 10 + (2 * $Length(note)), "and the total grows by one note for each")
}

/// The step renderer's OnMessage, which AI Hub calls for each model response, sets the total of the context to 0 (AD-10): the results of one model step share
/// one room, and the next step has its own.
Method TestRoomResets()
{
	Do ..Begin()
	Set text = ..Filler(39990)
	Do $$$AssertEquals(..Return(text), text, "a text of 39,990 characters fits")
	Do $$$AssertEquals(..Total(), 39990, "the total is 39,990")
	Do $$$AssertEquals(..Return(text), ..Note(0, 39990), "a second text of 39,990 characters in the same step is the note alone: 10 characters are left")
	Do ##class(OcuTalon.Bridge.Adapter.StepRenderer).%New().OnMessage({"value": "the next model response"})
	Do $$$AssertEquals(..Total(), 0, "OnMessage sets the total to 0")
	Do $$$AssertEquals(..Return(text), text, "and the same text fits again in the next step")
	Do $$$AssertEquals(..Total(), 39990, "with the total 39,990")
}

/// A new context starts the total at 0 (Begin), whatever a context before it held, and ToolResultChars is a field that Put sets and Current reads.
Method TestBegin()
{
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Bridge.Context).#FIELDS), "ToolResultChars"), "ToolResultChars is a field of the context")
	Do ..Begin()
	Do $$$AssertEquals(..Total(), 0, "a new context starts the total at 0")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("ToolResultChars", 1234), "Put sets the total")
	Do $$$AssertEquals(..Total(), 1234, "and Current reads it")
	Do ..Begin()
	Do $$$AssertEquals(..Total(), 0, "a context that begins again starts it at 0 again")
}

/// With no context (a tool that runs outside a runner's call), Return measures against a fresh room each time and keeps nothing.
Method TestNoContext()
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "control: there is no context")
	Set text = ..Filler(45000)
	Set shown = ..ExpectedShown(..#ROOM, 45000)
	Set expected = $Extract(text, 1, shown)_$Char(10)_..Note(shown, 45000)
	Do $$$AssertEquals(..Return(text), expected, "a text of 45,000 characters is cut against the full room")
	Do $$$AssertEquals(..Return(text), expected, "and again, because nothing was kept")
	Set small = {"items": []}
	Set back = ..Return(small)
	Do $$$AssertTrue($IsObject(back) && (back = small), "an object that fits comes back whole")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and Return began no context")
}

/// A value whose text cannot be built whole is left out (AD-10): a dynamic object that holds a stream of 4,000,000 characters has a JSON longer than the longest
/// string, which raises when it is built. The result is the note alone with unknown as the total, and the note is added to the total.
Method TestUnknownTotal()
{
	Do ..Begin()
	Set stream = ##class(%Stream.TmpCharacter).%New()
	Set chunk = ..Filler(100000)
	For i = 1:1:40 {
		Do stream.Write(chunk)
	}
	Set object = {}
	Do object.%Set("data", stream, "stream")
	Set back = ..Return(object)
	Do $$$AssertEquals(back, "[cut by OcuTalon: 0 of unknown characters shown]", "the result is the note alone, with unknown as the total")
	Do $$$AssertEquals(..Total(), $Length(back), "and its length is added to the total")
}

/// The note is ASCII, it holds the two numbers, and it is at most 56 characters for the longest numbers (a result of the longest string: 3,641,144 characters).
Method TestNote()
{
	Set note = ..Note(40000, 3641144)
	Do $$$AssertEquals(note, "[cut by OcuTalon: 40000 of 3641144 characters shown]", "the note for the longest numbers")
	Do $$$AssertTrue($Length(note) '> 56, "is "_$Length(note)_" characters, at most 56")
	Set ascii = 1
	For i = 1:1:$Length(..Note(9950, 30011)) {
		If $Ascii(..Note(9950, 30011), i) > 126 Set ascii = 0
	}
	Do $$$AssertTrue(ascii, "the note is ASCII")
	Do $$$AssertEquals(..Note(0, "unknown"), "[cut by OcuTalon: 0 of unknown characters shown]", "and gives unknown for a total that is not known")
}

/// A class that extends Result is offered to the model with its own methods only: Return, Room, Note and ShownChars are inherited, and AI Hub exposes a
/// method of the concrete class only. The Watch fixture offers its three, and the test tool of the step cap its own three (it has a helper of its own).
Method TestOwnMethodsAreTools()
{
	Do $$$AssertEquals(..ToolNames("OcuTalon.Tools.WatchFixture"), "ReadEventLog ReadFailedMessages ReadItemSettings", "the Watch fixture offers its three methods and none of Result's")
	Do $$$AssertEquals(..ToolNames(..#TOOL), "Filler Object Text", "the test tool offers the methods it defines and none of Result's")
}

/// The step cap through the real runner and the CI mock (AC4; scenario result-cap). The agent ZzResultAgent runs in the shadow runner ZzRunner. The mock's first
/// reply asks for zz_result_text with 30,000 characters and zz_result_object with 30,000 in one response; the second asks for zz_result_text with 1,000; the
/// third is the text. The request after the first response carries the text whole and the object's JSON cut, ending with the note, which says how many of
/// the characters are shown; together they are at most 40,000 characters. AI Hub encodes a string result as a JSON string, so the contents are decoded first
/// (an object that fits is not a string and comes whole). The request after the second response carries the 1,000 characters whole, because the renderer's
/// OnMessage started the room again, and still carries the two results of the first. The reply is the scenario's text.
Method TestStepCap()
{
	If ..Guard() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set host = $ClassMethod(..#RUNNERTEST, "NewRunner", "OcuTalon.Test.Tools.ZzResultAgent", "low")
	Set request = ..NewRequest("[[mock:result-cap]] Read the results.")
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the request is answered")
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text_"|"_reply.FailureText, "The CI mock read the results.|", "with the text of the scenario's last reply and no failure")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set logged = $ClassMethod(fixture, "FindRequests", entries, request.ItemId)
	Do $$$AssertEquals(logged.%Size(), 3, "the mock logged three requests")
	If logged.%Size() '= 3 Quit

	Set second = $ClassMethod(fixture, "ToolResults", logged.%Get(1))
	Do $$$AssertEquals($ListLength(second), 2, "request 2 carries two tool results")
	If $ListLength(second) = 2 {
		Set text = ..Decoded($List(second, 1))
		Set cut = ..Decoded($List(second, 2))
		Set whole = ..Filler(30000)
		Set json = {"data": (whole)}.%ToJSON()
		Do $$$AssertEquals(text, whole, "the text of 30,000 characters comes whole")
		Do $$$AssertEquals($Extract($List(second, 2)), """", "the object's result is a string, which AI Hub encodes: its JSON cut is no object")
		Set note = $Piece(cut, $Char(10), $Length(cut, $Char(10)))
		Set shown = +$Piece($Piece(note, "cut by OcuTalon: ", 2), " of ", 1)
		Do $$$AssertEquals(note, ..Note(shown, $Length(json)), "it ends with the note, which gives the length of the object's JSON, "_$Length(json)_", as the total")
		Do $$$AssertTrue((shown > 0) && (shown < $Length(json)), "and fewer characters shown than there are: "_shown)
		Do $$$AssertEquals(cut, $Extract(json, 1, shown)_$Char(10)_note, "the characters shown are the start of the object's JSON")
		Do $$$AssertTrue($Length(text) + $Length(cut) '> ..#ROOM, "together the two results are at most "_..#ROOM_" characters: "_($Length(text) + $Length(cut)))
		Do $$$AssertTrue($Length(text) + $Length(cut) > ..#ROOM - 100, "and they use the room: nothing was cut that fitted")
	}

	Set third = $ClassMethod(fixture, "ToolResults", logged.%Get(2))
	Do $$$AssertEquals($ListLength(third), 3, "request 3 carries three tool results")
	If $ListLength(third) = 3 {
		Do $$$AssertEquals($List(third, 1)_"|"_$List(third, 2), $List(second, 1)_"|"_$List(second, 2), "the first two are the results of request 2, as they were")
		Do $$$AssertEquals(..Decoded($List(third, 3)), ..Filler(1000), "the text of 1,000 characters of the second response comes whole: the room started again")
	}
}

/// --- helpers ---
/// Begins a context for an untrusted turn, with the total at 0.
Method Begin() [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "untrusted"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins")
}

/// Result.Return of the value.
ClassMethod Return(value) As %Any [ Private ]
{
	Quit $ClassMethod(..#RESULT, "Return", value)
}

/// The running total of the context, or -1 when there is none.
ClassMethod Total() As %Integer [ Private ]
{
	Set context = ##class(OcuTalon.Bridge.Context).Current()
	Quit $Select($IsObject(context): context.ToolResultChars, 1: -1)
}

/// The note the way the spec words it, built here and not read from the class.
ClassMethod Note(shown As %Integer, total As %String) As %String [ Private ]
{
	Quit "[cut by OcuTalon: "_shown_" of "_total_" characters shown]"
}

/// The largest number of characters k, at least 1, of a text of length characters such that k characters, a line break and the note for k fit in left, found by
/// trying them from the top; 0 when there is none.
ClassMethod ExpectedShown(left As %Integer, length As %Integer) As %Integer [ Private ]
{
	For k = $Select(length < left: length, 1: left):-1:1 {
		If k + 1 + $Length(..Note(k, length)) '> left Quit
	}
	Quit $Select(k < 1: 0, 1: k)
}

/// A text of chars characters: the digits 0 to 9 over and over (OcuTalon.Test.Tools.ZzResultTool Filler).
ClassMethod Filler(chars As %Integer) As %String [ Private ]
{
	Quit $ClassMethod(..#TOOL, "Filler", chars)
}

/// The names of the methods that the class is offered with, sorted and joined by a space.
ClassMethod ToolNames(class As %String) As %String [ Private ]
{
	Set names = ""
	Set tools = $ClassMethod(class, "%New").%Discover().%Get("tools")
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set sorted(tool.name) = ""
	}
	Set name = ""
	For {
		Set name = $Order(sorted(name))
		Quit:name=""
		Set names = names _ $Select(names = "": "", 1: " ") _ name
	}
	Quit names
}

/// The text a tool returned, from the content that the model got: AI Hub encodes a string result as a JSON string (a pair of quotes, with the quotes and the
/// line breaks of the text escaped), so a content that starts with a quote is decoded; any other content is the JSON of an object and stays as it is.
ClassMethod Decoded(content As %String) As %String [ Private ]
{
	If $Extract(content) '= """" Quit content
	Quit {}.%FromJSON("{""v"":"_content_"}").v
}

/// A request for the runner: an untrusted turn (it is linked to no conversation, so it saves no AI session) with the input, a reference in it so that the
/// mock's log finds it, and a DecisionRef of its own, because Decide allocates it before the runner is asked.
ClassMethod NewRequest(input As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ref
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Channel = "system"
	Set request.Summary = "Test "_ref
	Set request.Input = input_" (test "_ref_")"
	Quit request
}

/// 1 when the test must not run: the environment is not the CI override's, and the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason = "" Quit 0
	Do $$$AssertTrue(0, reason)
	Quit 1
}

}
