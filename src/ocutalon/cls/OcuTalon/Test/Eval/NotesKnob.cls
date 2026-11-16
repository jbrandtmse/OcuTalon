/// Tests of the notes knob of the evaluation service (Story 27.1, the Contest Planner's R7 channel A/B; AD-22): a case of the notes-cases folder carries notes, and a run
/// that is given a notes channel writes them as Turn rows of an eval-only session and renders the case as the first turn of that session, so that the product's own notes block
/// shows the lines "message (<channel>): ...". They call OnProcessInput on a shadow instance of OcuTalon.Test.Eval.ZzIn, the double of EvalIn that sends and waits for nothing, with the
/// real eval session (Data.Session ForEval, which needs OCUTALON_EVAL=1, which each test sets and restores). The model is never called.
///   - TestChannelLabel: the same notes under the channel slack and under the channel telegram render the same input but for the label, with the three notes and their texts; the Turn
///     rows exist while the case runs, in the notes channel, and are gone with the session at Finish; the request's owner stays eval;
///   - TestInertWhenUnset: with no notes channel a case that carries notes sends exactly what it sends without them: no session, no Turn row, and an input of the preamble and the
///     turn's text alone, equal to that of the same case with no notes;
///   - TestBadChannelSkipsNotesCases: a notes channel that is not a Msg.Enum CHANNEL value skips a case that carries notes with REASONNOTES, leaves nothing behind, and still sends a case
///     with no notes;
///   - TestNotesShape: a notes that is not an array of 1 to 4 notes of {minutesAgo 1 to 600 whole, text 1 to 200 characters}, a notes with a session, and a notes on a kind that is not an
///     all-clear or command case, each skip the case with REASONNOTES and leave nothing behind;
///   - TestTurnForEvalRefusals: Data.Turn ForEval makes nothing without OCUTALON_EVAL=1, for a session that is a person's, for a channel that is not a channel, or for a time that is not a UTC time;
///   - TestDropEvalDeletesTurns: Data.Session DropEval deletes the evaluation session's Turn rows with its row, and no other session's.
Class OcuTalon.Test.Eval.NotesKnob Extends %UnitTest.TestCase
{

Parameter DOUBLE = "OcuTalon.Test.Eval.ZzIn";

/// The fixed notes set of the A/B (Story 27.1, Design Notes 16).
Parameter NOTES = "[{""minutesAgo"":170,""text"":""Good morning, I'm on shift until six.""},{""minutesAgo"":95,""text"":""Thanks, that helps.""},{""minutesAgo"":40,""text"":""Back from lunch now.""}]";

Parameter ASK = "Anything I should know?";

Property Folder As %String(MAXLEN = 500);

Property Run As %String(MAXLEN = 22);

Property EvalWas As %String;

/// The Refs of the eval sessions that a test made itself, comma-separated.
Property Refs As %String(MAXLEN = "");

Property Person As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Folder = ##class(%File).NormalizeDirectory("zznotes"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 12), ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory()))
	Do ##class(%File).CreateDirectoryChain(..Folder)
	Set ..EvalWas = ##class(OcuTalon.Test.Data.Fixture).SetEval("1")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).SetEval(..EvalWas)
	Kill ^OcuTalonTest("EvalIn")
	Do ##class(%File).RemoveDirectoryTree(..Folder)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("EvalIn")
	Set ..Run = "zz"_$Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 20)
	Set ..Refs = ""
	Set ..Person = ""
	Set ^OcuTalonTest("EvalIn", "sessionReal") = 1
	Do ##class(OcuTalon.Test.Data.Fixture).SetEval("1")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).SetEval("1")
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ##class(OcuTalon.Data.Session).DropEval($Piece(..Refs, ",", i))
	}
	Do ##class(OcuTalon.Test.Eval.ZzIn).DeleteBodies()
	Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..Run)
	If ..Person '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Person)
	Kill ^OcuTalonTest("EvalIn")
	Quit $$$OK
}

Method TestChannelLabel()
{
	Do ..WriteCase("zz-notes", ..CaseJson("all-clear", ..#NOTES))
	Set before = ..EvalSessions()
	Set inputs = ""
	For channel = "slack", "telegram" {
		Kill ^OcuTalonTest("EvalIn", "asked")
		Set service = ..Service(channel)
		Do $$$AssertEquals(..Process(service, "zz-notes"), "", channel_": the case is sent")
		Set asked = ^OcuTalonTest("EvalIn", "asked", 1)
		Set inputs(channel) = $List(asked, 5)
		Do $$$AssertEquals($List(asked, 1)_"|"_$List(asked, 3), "turn|eval", channel_": a turn request, whose owner stays eval")
		Set ref = service.Watches.%Get(0).session.ref
		Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
		Do $$$AssertEquals(..Turns(ref), channel_"|Good morning, I'm on shift until six.,"_channel_"|Thanks, that helps.,"_channel_"|Back from lunch now.", channel_": the three notes are Turn rows of the session, oldest first, in the channel")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Eval.ZzIn).Finish(service.Watches), channel_": Finish answers OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(ref)_"|"_..Turns(ref)_"|"_..EvalSessions(), "0||"_before, channel_": and the session and its turns are gone")
		Do ##class(OcuTalon.Test.Eval.ZzIn).DeleteBodies()
		Do ##class(OcuTalon.Eval.Data.CaseResult).Remove(..Run)
	}
	Set slack = inputs("slack"), telegram = inputs("telegram")
	Do $$$AssertTrue(slack [ ##class(OcuTalon.Agent.Input).#NOTESOPENING, "the slack run's input has the notes block")
	Do $$$AssertTrue((slack [ "message (slack): Good morning, I'm on shift until six.") && (slack [ "message (slack): Thanks, that helps.") && (slack [ "message (slack): Back from lunch now."), "its three notes read (slack)")
	Do $$$AssertTrue(slack '[ "(telegram)", "and none reads (telegram)")
	Do $$$AssertTrue((telegram [ "message (telegram): Good morning, I'm on shift until six.") && (telegram [ "message (telegram): Back from lunch now.") && (telegram '[ "(slack)"), "the telegram run's notes read (telegram) and none reads (slack)")
	Do $$$AssertEquals(..Normal(slack, "slack"), ..Normal(telegram, "telegram"), "the two inputs are the same but for the label (and the clock)")
	Do $$$AssertEquals($Extract(slack, *-$Length(..#ASK)+1, *), ..#ASK, "and the turn's text ends each")
}

Method TestInertWhenUnset()
{
	Do ..WriteCase("zz-with", ..CaseJson("all-clear", ..#NOTES))
	Do ..WriteCase("zz-without", ..CaseJson("all-clear", ""))
	Set before = ..EvalSessions()
	Set service = ..Service("")
	Do $$$AssertEquals(..Process(service, "zz-with"), "", "a case with notes is sent with no notes channel")
	Do $$$AssertEquals(..EvalSessions(), before, "no eval session is made")
	Set withNotes = $List(^OcuTalonTest("EvalIn", "asked", 1), 5)
	Set owner = $List(^OcuTalonTest("EvalIn", "asked", 1), 3)
	Do $$$AssertEquals($Piece(withNotes, $Char(10, 10), 2, *), ..#ASK, "its input is the preamble and the turn's text alone")
	Do $$$AssertEquals(owner, "eval", "for the owner eval")
	Do $$$AssertTrue(withNotes '[ ##class(OcuTalon.Agent.Input).#NOTESOPENING, "with no notes block")
	Do $$$AssertEquals(..Process(service, "zz-without"), "", "the same case with no notes member is sent")
	Do $$$AssertEquals($Piece($List(^OcuTalonTest("EvalIn", "asked", 2), 5), $Char(10, 10), 2, *), $Piece(withNotes, $Char(10, 10), 2, *), "with the same input")
	Do $$$AssertEquals($Select($IsObject(service.Watches): service.Watches.%Size(), 1: 0), 0, "and no record of a session is kept")
}

Method TestBadChannelSkipsNotesCases()
{
	Do ..WriteCase("zz-notes", ..CaseJson("all-clear", ..#NOTES))
	Do ..WriteCase("zz-plain", ..CaseJson("all-clear", ""))
	Set before = ..EvalSessions()
	Set prefix = $Piece($Parameter("OcuTalon.Eval.In", "REASONNOTES"), "{why}", 1)
	For channel = "zz-not-a-channel", "Slack", "slack,web" {
		Set service = ..Service(channel)
		Set reason = ..Process(service, "zz-notes")
		Do $$$AssertTrue($Extract(reason, 1, $Length(prefix)) = prefix, "'"_channel_"' skips a notes case with REASONNOTES: "_reason)
		Do $$$AssertTrue(reason [ "the notes channel is not a channel", "and says why: "_reason)
	}
	Do $$$AssertEquals(..EvalSessions()_"|"_+$Get(^OcuTalonTest("EvalIn", "asked")), before_"|0", "no session is left and nothing is asked")
	Do $$$AssertEquals(..Process(..Service("zz-not-a-channel"), "zz-plain"), "", "a case with no notes is still sent")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("EvalIn", "asked")), 1, "and asked")
}

Method TestNotesShape()
{
	Set prefix = $Piece($Parameter("OcuTalon.Eval.In", "REASONNOTES"), "{why}", 1)
	Set note = "{""minutesAgo"":10,""text"":""ok""}"
	Set long = $Translate($Justify("", 201), " ", "x")
	Set cases = $ListBuild("not an array|{""a"":1}", "empty|[]", "five|["_note_","_note_","_note_","_note_","_note_"]", "minutes 0|[{""minutesAgo"":0,""text"":""ok""}]", "minutes 601|[{""minutesAgo"":601,""text"":""ok""}]", "minutes 1.5|[{""minutesAgo"":1.5,""text"":""ok""}]", "minutes string|[{""minutesAgo"":""10"",""text"":""ok""}]", "text blank|[{""minutesAgo"":10,""text"":"" ""}]", "text 201|[{""minutesAgo"":10,""text"":"""_long_"""}]", "no text|[{""minutesAgo"":10}]", "note not an object|[1]")
	Set before = ..EvalSessions()
	Set position = 0
	While $ListNext(cases, position, one) {
		Do ..WriteCase("zz-shape", ..CaseJson("command", $Piece(one, "|", 2, 99)))
		Set reason = ..Process(..Service("slack"), "zz-shape")
		Do $$$AssertTrue($Extract(reason, 1, $Length(prefix)) = prefix, $Piece(one, "|", 1)_": the case is skipped with REASONNOTES: "_reason)
	}
	Set text = ..CaseJson("command", "["_note_"]")
	Set case = ##class(%DynamicAbstractObject).%FromJSON(text)
	Do case.%Set("session", {"forgotten": ["One."]})
	Do ..WriteCase("zz-both", case.%ToJSON())
	Set reason = ..Process(..Service("slack"), "zz-both")
	Do $$$AssertTrue((reason [ prefix) && (reason [ "not both"), "a case with a session and notes is skipped: "_reason)
	Do ..WriteCase("zz-docs", ..CaseJson("documents", "["_note_"]"))
	Set reason = ..Process(..Service("slack"), "zz-docs")
	Do $$$AssertTrue((reason [ prefix) && (reason [ "only an all-clear or command case"), "a notes member on a documents case is skipped: "_reason)
	Do $$$AssertEquals(..EvalSessions()_"|"_+$Get(^OcuTalonTest("EvalIn", "asked")), before_"|0", "no session is left, no memory seed was asked and nothing was sent to Decide")
	Do ..WriteCase("zz-ok", ..CaseJson("command", "["_note_"]"))
	Set service = ..Service("slack")
	Do $$$AssertEquals(..Process(service, "zz-ok"), "", "a valid note is sent")
	Do $$$AssertEquals(..Turns(service.Watches.%Get(0).session.ref), "slack|ok", "as one Turn row")
	Do ##class(OcuTalon.Test.Eval.ZzIn).Finish(service.Watches)
}

Method TestTurnForEvalRefusals()
{
	Set row = ##class(OcuTalon.Data.Session).ForEval(.sc)
	Do $$$AssertStatusOK(sc, "an evaluation session is made")
	Set ref = row.Ref
	Set ..Refs = ref
	Set row = ""
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set made = ##class(OcuTalon.Data.Turn).ForEval(ref, "slack", now, "zz first", .sc)
	Do $$$AssertStatusOK(sc, "a turn of the session is made")
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(made)
	Do $$$AssertEquals($IsObject(turn)_"|"_turn.SessionRef_"|"_turn.State_"|"_turn.Channel_"|"_turn.Text_"|"_turn.CreatedAt, "1|"_ref_"|done|slack|zz first|"_now, "it is a done row of the session, in the channel, with the text and the time")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval(ref, "zzchannel", now, "zz", .sc), "", "a channel that is not a channel is refused")
	Do $$$AssertStatusNotOK(sc, "with an error status")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval(ref, "slack", "yesterday", "zz", .sc), "", "a time that is not a UTC time is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval(ref, "", now, "zz", .sc), "", "an empty channel is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval("zzNoSuchSession00000001", "slack", now, "zz", .sc), "", "a session that does not exist is refused")
	Set ..Person = ##class(OcuTalon.Test.Data.Fixture).Session("zznotesperson")
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval(..Person, "slack", now, "zz", .sc), "", "a person's session is refused")
	For value = "", "0", "true", "11" {
		Do ##class(OcuTalon.Test.Data.Fixture).SetEval(value)
		Do $$$AssertEquals(##class(OcuTalon.Data.Turn).ForEval(ref, "slack", now, "zz", .sc), "", "with OCUTALON_EVAL '"_value_"' nothing is made")
	}
	Do ##class(OcuTalon.Test.Data.Fixture).SetEval("1")
	Do $$$AssertEquals(..Turns(ref), "slack|zz first", "so the session has only its first turn")
	Do $$$AssertEquals(..TurnCount(..Person), 0, "and the person's session has none")
}

Method TestDropEvalDeletesTurns()
{
	Set a = ##class(OcuTalon.Data.Session).ForEval(.sc)
	Set b = ##class(OcuTalon.Data.Session).ForEval(.sc)
	Set refA = a.Ref, refB = b.Ref
	Set (a, b) = ""
	Set ..Refs = refA_","_refB
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Do ##class(OcuTalon.Data.Turn).ForEval(refA, "slack", now, "zz a1", .sc)
	Do ##class(OcuTalon.Data.Turn).ForEval(refA, "slack", now, "zz a2", .sc)
	Do ##class(OcuTalon.Data.Turn).ForEval(refB, "telegram", now, "zz b1", .sc)
	Do $$$AssertEquals(..TurnCount(refA)_"|"_..TurnCount(refB), "2|1", "two sessions hold their turns")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).DropEval(refA), "the first is dropped")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(refA)_"|"_..TurnCount(refA)_"|"_..TurnCount(refB), "0|0|1", "its row and its turns are gone, and the other session keeps its turn")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).DropEval(refB), "the second is dropped")
	Do $$$AssertEquals(..TurnCount(refB), 0, "with its turn")
}

/// --- helpers ---

/// A shadow instance of the double with the notes channel and the run's Ref.
Method Service(channel As %String) As OcuTalon.Test.Eval.ZzIn [ Private ]
{
	Set service = ##class(Ens.Host).GetShadowInstance("class||"_..#DOUBLE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the EvalIn double is made")
	Set service.RunRef = ..Run
	Set service.NotesChannel = channel
	Quit service
}

/// Hands the case's folder to the service; the reason it was not sent, or "".
Method Process(service As OcuTalon.Test.Eval.ZzIn, name As %String) As %String [ Private ]
{
	Kill output
	Set input = ##class(Ens.StringContainer).%New(##class(%File).SubDirectoryName(..Folder, name))
	Do $$$AssertStatusOK(service.OnProcessInput(input, .output), name_": OnProcessInput answers OK")
	Quit output.StringValue
}

/// The text of a case.json of the kind with the notes member (JSON text; "" for none).
Method CaseJson(kind As %String, notes As %String) As %String [ Private ]
{
	Set case = {"name": "zz-case", "kind": (kind), "checks": [], "turn": {"text": (..#ASK)}, "expectation": {}}
	If notes '= "" Do case.%Set("notes", ##class(%DynamicAbstractObject).%FromJSON(notes))
	Quit case.%ToJSON()
}

/// Writes the case.json of a case folder.
Method WriteCase(name As %String, text As %String) [ Private ]
{
	Set directory = ##class(%File).SubDirectoryName(..Folder, name)
	Do ##class(%File).CreateDirectoryChain(directory)
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.Filename = ##class(%File).NormalizeFilename(##class(OcuTalon.Eval.In).#CASEFILE, directory)
	Do stream.Write(text)
	Do $$$AssertStatusOK(stream.%Save(), "the case file is written")
}

/// The Session rows that have no IrisUser.
ClassMethod EvalSessions() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Session WHERE COALESCE(IrisUser, '') = ''")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The Turn rows of the session, oldest first, as "channel|text" joined with commas.
ClassMethod Turns(sessionRef As %String) As %String [ Private ]
{
	Set list = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Channel, Text FROM OcuTalon_Data.Turn WHERE SessionRef = ? ORDER BY CreatedAt, ID", sessionRef)
	While rs.%Next() {
		Set list = list_$Select(list = "": "", 1: ",")_rs.%Get("Channel")_"|"_rs.%Get("Text")
	}
	Quit list
}

ClassMethod TurnCount(sessionRef As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", sessionRef)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The input without its preamble line and without the clock time of each note line, with the channel label replaced by (label): what two runs that differ only in
/// the channel must share.
ClassMethod Normal(input As %String, channel As %String) As %String [ Private ]
{
	Set text = ""
	For i = 2:1:$Length(input, $Char(10)) {
		Set line = $Piece(input, $Char(10), i)
		If line [ " message (" Set line = "message ("_$Piece(line, " message (", 2, *)
		Set text = text_$Replace(line, "("_channel_")", "(label)")_$Char(10)
	}
	Quit text
}

}
