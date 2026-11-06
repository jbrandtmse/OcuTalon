/// Tests of the Chat agent's digest tool, send_digest (Story 17.6; AD-1, AD-9, AD-10, AD-18, Q5 (b), Q6, Q7, U-268). TestDeclaration and TestFixedText need no
/// production; TestResultSaysSending RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it drives a real turn of the Chat agent through Decide against the CI mock
/// (scenario digest-send-now), with the real CommandsIn and Digest items behind the tool.
///   - TestDeclaration: send_digest is a method of Tools.DigestTools, in the Watching toolset, safe, not read-only, with trusted output and the step label "Sending
///     your digest"; it takes no input; Tools.Names DIGESTTOOLS holds its name and RELEASE1 does not;
///   - TestFixedText (the fixed-strings test): the Message of an accepted SendDigest is, byte for byte, "The digest is on its way to the user's digest channels. Its
///     delivery is not confirmed yet: tell the user it is on its way, not that it has arrived.", and it holds no word that says the digest was sent or arrived;
///   - TestResultSaysSending (Q5 (b)): the mock's marker turn calls send_digest, the tool submits SendDigest with origin tool and the key <ItemId>:1, and the tool
///     result that the model reads in its next request is exactly {"message": <that text>, "ok": true} (the order of AI Hub's JSON), with no digest content and no
///     name; the turn ends without a
///     wait near the 120 seconds of CommandsIn, and the digest goes: one Sent row of kind requested that holds the key.
Class OcuTalon.Test.Digest.Tool Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter TOOLS = "OcuTalon.Tools.DigestTools";

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

/// The message the tool result must hold.
Parameter MESSAGE = "The digest is on its way to the user's digest channels. Its delivery is not confirmed yet: tell the user it is on its way, not that it has arrived.";

/// The longest a turn may take, in seconds: well under the 120 of CommandsIn's wait.
Parameter TURNSECONDS = 60;

Property Refs As %String(MAXLEN = "");

Property Sessions As %String(MAXLEN = "");

Property Pointed As %Boolean [ InitialExpression = 0 ];

Property SessionMark As %Integer;

/// The digest.channels row before the class (ProcessProbe ForgetChannels).
Property ChannelsWas As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..ChannelsWas = $ClassMethod(..#PROBE, "ForgetChannels")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..SessionMark = $Select($ClassMethod(..#FIXTURE, "Running"): $ClassMethod(..#FIXTURE, "SessionMark"), 1: 0)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = "", ..Sessions = ""
	If $ClassMethod(..#FIXTURE, "Running") Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do $ClassMethod(..#PROBE, "PutChannelsBack", ..ChannelsWas)
	Set sc = $$$OK
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
	}
	Quit sc
}

Method TestDeclaration()
{
	Set names = "OcuTalon.Tools.Names"
	Set tools = $ClassMethod("OcuTalon.Tools.Watching", "%New").%Discover().tools
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If tool.name = $Parameter(names, "DIGESTTOOLS") Set found = tool
	}
	Do $$$AssertTrue($IsObject(found), "the Watching toolset offers send_digest")
	If $IsObject(found) {
		Do $$$AssertEquals(found.provider, ..#TOOLS, "as a method of "_..#TOOLS)
		Do $$$AssertEquals(found.parameters.properties.%Size(), 0, "with no input")
		Do $$$AssertTrue(found.description [ "digest", "and a description for the model")
		Do $$$AssertTrue(found.description '[ "was sent", "which never says the digest was sent")
	}
	Do $$$AssertEquals($Parameter(..#TOOLS, "CLASSIFICATIONSENDDIGEST")_"|"_$Parameter(..#TOOLS, "READONLYSENDDIGEST")_"|"_$Parameter(..#TOOLS, "TRUSTEDOUTPUTSENDDIGEST")_"|"_$Parameter(..#TOOLS, "STEPLABELSENDDIGEST"), "safe|0|1|Sending your digest", "it is safe, not read-only, trusted output, with its step label")
	Do $$$AssertEquals($Parameter(names, "DIGESTTOOLS"), "send_digest", "Tools.Names DIGESTTOOLS holds the name")
	Do $$$AssertEquals($ListFind($ListFromString($Parameter(names, "RELEASE1")), "send_digest"), 0, "and RELEASE1 does not")
	Do $$$AssertEquals(##class(%Dictionary.CompiledMethod).%OpenId(..#TOOLS_"||SendDigest").ReturnType, "%Library.DynamicObject", "SendDigest returns a dynamic object")
}

Method TestFixedText()
{
	Set text = $Parameter("OcuTalon.Digest.Process", "MESSAGESENDING")
	Do $$$AssertEquals(text, ..#MESSAGE, "the Message is the ruled text, byte for byte")
	Do $$$AssertEquals($Length(text), 147, "of 147 characters")
	Do $$$AssertTrue((text '[ "was sent") && (text '[ "has been sent") && (text '[ "was delivered") && (text '[ "has been delivered"), "and says neither that the digest was sent nor that it was delivered")
	Set ascii = 1
	For i = 1:1:$Length(text) {
		If $Ascii(text, i) > 127 Set ascii = 0
	}
	Do $$$AssertTrue(ascii, "and is ASCII")
}

Method TestResultSaysSending()
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit
	}
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zztool")
	Set ..Refs = session
	Set ..Sessions = session
	Set item = ##class(OcuTalon.Digest.Data.Item).%New()
	Set item.SessionRef = session
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.Channel = "mailbox"
	Set item.Summary = "Partner mail [[mock:digest-summary]]"
	Set item.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(item.%Save(), "an item is saved for later, so that the digest asks Decide for a summary while the tool call is inside CommandsIn")
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", "Send my digest now. [[mock:digest-send-now]]", .ref, session)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .answer, .traceSession)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	Do $$$AssertTrue(elapsed < ..#TURNSECONDS, "the turn ends in "_$FNumber(elapsed, "", 1)_" seconds, nowhere near the 120 of CommandsIn's wait")
	If '$IsObject($Get(answer)) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, "The CI mock asked for the digest.", "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Fallback_"|"_answer.ToolsRun, "0|1", "which is not a fallback, and tools ran")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, request.ItemId)
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Do $$$AssertTrue($ListFind($ListFromString($ClassMethod(..#FIXTURE, "ToolNames", requests.%Get(0))), "send_digest"), "the model is offered send_digest")
		Set results = $ClassMethod(..#FIXTURE, "ToolResults", requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
		If $ListLength(results) = 1 {
			Set seen = {}.%FromJSON($List(results, 1))
			Set members = 0
			Set iterator = seen.%GetIterator()
			While iterator.%GetNext(.name) {
				Set members = members + 1
			}
			Do $$$AssertEquals(members_"|"_seen.%GetTypeOf("ok")_"|"_seen.ok, "2|boolean|1", "which holds ok true and one other member: no digest content and no name")
			Do $$$AssertEquals(seen.message, ..#MESSAGE, "the message is the fixed text, byte for byte")
			Do $$$AssertEquals($List(results, 1), {"message": (..#MESSAGE), "ok": true}.%ToJSON(), "and the whole result is exactly that object")
		}
	}
	Set end = $ZHorolog + 40
	Set row = ""
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Kind, DueAt, IdempotencyKey FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
		If rs.%Next() {
			Set row = {"kind": (rs.%Get("Kind")), "dueAt": (rs.%Get("DueAt")), "key": (rs.%Get("IdempotencyKey"))}
			Quit
		}
		If $ZHorolog > end Quit
		Hang 0.25
	}
	Do $$$AssertTrue($IsObject(row), "the digest is sent, after the chat turn, though both turns share the one-job ChatAgent")
	If $IsObject(row) Do $$$AssertEquals(row.kind_"|"_row.dueAt_"|"_row.key, "requested||"_request.ItemId_":1", "as a requested digest that holds the key of the tool call")
	Set read = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Slots FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do read.%Next()
	Set slots = {}.%FromJSON($Select(read.%GetData(1) = "": "{""parts"": []}", 1: read.%GetData(1)))
	Set summary = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = "digest.saved" Set summary = part.slots.summary
	}
	Do $$$AssertEquals($Length(summary), 240, "with the model's summary, cut to 240 characters")
}

}
