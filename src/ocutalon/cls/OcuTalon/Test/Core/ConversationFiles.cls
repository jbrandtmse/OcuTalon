/// Tests of the file turn of Conversation (Story 25.3; AD-6, AD-10, AD-14, AD-30; security condition (i), ruling 4). Safe on a slot: no production runs there, so the tests
/// call OnRequest on shadow instances of Test.Core.ConversationProbe, as Test.Core.ConversationTurns does. The files are stored through Core.Files.Store and the Items
/// are built as WebChatIn (channel web) and a Telegram service (channel telegram, a fixture) build them: provenance untrusted, the four file fields from SetItem. Every
/// sentence is written out here.
///   - TestFileItemBecomesTurn: a web file Item and a Telegram file Item each become a Turn of their own session with SentFile set from the stored row (exactly ref, name,
///     mediaType and size), no text, the Item's channel, and the queued chat.message carries sentFile with those four keys;
///   - TestSentFileFromTheRow: an Item whose file name, media type and size differ from its stored row gives a Turn whose SentFile is the row's (Core.Files.Describe);
///   - TestNoReaderReply: with no reader (the probe's seam forced off, so that the test holds after Story 25.6 turns READSFILES on), each of the two turns ends done with the reply "I got {name}, but I can't read files yet." (the
///     safe name), nothing is sent to Decide, the done chat.message carries the reply and sentFile, one Outbound goes to Notify with that text and the turn's channel, and
///     the turn is not tainted;
///   - TestReaderTurnIsUntrusted: with a reader (the probe's seam), the decide and the turn request both carry provenance untrusted, the Item that ItemOf rebuilds is untrusted
///     with the four file fields, and in a context begun from that request the gate denies a tool that is not read-only with its UNTRUSTED sentence;
///   - TestFileItemDrops: a file Item with provenance user, one whose FileRef is another session's, one with an unknown FileRef, one with no ItemId and one with no session
///     are each dropped (no Turn, no call, no event), and an Item with no text and no FileRef is still dropped;
///   - TestMarkerReachesNothing: the bytes of the file (a marker string) are in no Turn row, no recorded call and no event of the session.
/// From Story 25.6 (READSFILES 1) Conversation reads the file of a turn with a reader (the probe's seam, or the product's own) before the turn's first request:
///   - TestReadFailure: a damaged PDF ends the turn done with Docs.Extract.Failure of its reason, with no Decide send, FileRead read 0 (no text member), and the chat.message fileRead
///     {fileRef, kind, read 0, addable 0}; one Outbound carries the sentence;
///   - TestReadDocument: a readable PDF is sent to Decide (decide, then turn) after its FileRead {read 1, addable 1} was saved, and the done chat.message carries fileRead addable 1;
///   - TestReadError: a ReadFile that answers an error status, one whose result is not an object and one that is read 0 with no text, for a PDF and for a photo, end the turn with the "failed" sentence
///     and no Decide send, with FileRead of the file's kind;
///   - TestReadPhoto: a readable photo is sent through Decide untrusted after FileRead {photo, read 1, addable 0} was saved, and its chat.message fileRead is not addable;
///   - TestReadOnDemo: with the online demo flag set a PDF and a photo end the turn with the failed sentence, no Decide send and no Caption;
///   - TestCaptionCarried: a usable reply's HostData caption {memoryRef, text} is the Turn's Caption and the chat.message caption; a malformed caption is dropped; an unusable (fallback) reply that carries a caption saves nothing, so neither the Turn nor the chat.message has one;
///   - TestNoExtractedText: the extracted text (a content marker) and the file's bytes (a bytes marker) are in no Turn column, no chat.message and no Outbound, FileRead holds only its
///     members and the content marker is only in the turn requests' Input.
Class OcuTalon.Test.Core.ConversationFiles Extends %UnitTest.TestCase
{

/// The text inside every stored file.
Parameter MARKER = "zzfilemarker7731";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The number of recorded calls that Pump has looked at.
Property Handled As %Integer;

/// The number of the newest row of the event log when the run began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("ConversationFiles", "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..LogMark = ..LastLog()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) = "" Continue
		Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written($Piece(..Sessions, ",", i))
		If written '= "" Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_written
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) = "" Continue
		Do ##class(OcuTalon.Test.Core.DecideDouble).Clear($Piece(..Sessions, ",", i))
		Do ##class(OcuTalon.Data.SentFile).DropSession($Piece(..Sessions, ",", i))
	}
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", ..LogMark, "OcuTalon.Test.Core.ConversationProbe")
	Quit $SYSTEM.Status.OK()
}

Method TestFileItemBecomesTurn()
{
	For channel = "web", "telegram" {
		Set session = ..Session(channel)
		Set file = ..Store(session, channel, "zz-"_channel_".pdf")
		Set item = ..FileItem(session, channel, file)
		Do $$$AssertEquals(##class(OcuTalon.Data.SentFile).RefIndexOpen(file.ref).Channel, channel, channel_": the stored row has the channel of the file")
		Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), channel_": the file Item is taken")
		Set turns = ..Turns(session)
		Do $$$AssertEquals(turns.Count(), 1, channel_": one Turn")
		Set row = turns.GetAt(1)
		Do $$$AssertEquals(row.Channel_"|"_row.Text_"|"_row.ItemId, channel_"||"_item.ItemId, channel_": the Turn keeps the channel and the ItemId, and has no text")
		Set keep = {}.%FromJSON(row.SentFile)
		Do $$$AssertEquals(row.SentFile, {"ref": (file.ref), "name": (file.name), "mediaType": "application/pdf", "size": (file.size)}.%ToJSON(), channel_": SentFile holds exactly ref, name, mediaType and size of the stored row")
		Set events = ..ChatEvents(session)
		Do $$$AssertTrue(events.%Size() >= 1, channel_": chat.message was published")
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.state_"|"_payload.text, "queued|", channel_": the first one is the queued turn")
		Do $$$AssertEquals(payload.sentFile.%ToJSON(), row.SentFile, channel_": and carries sentFile, with exactly those four keys")
	}
}

Method TestSentFileFromTheRow()
{
	Set session = ..Session("row")
	Set file = ..Store(session, "web", "zz-row.pdf")
	Set item = ..FileItem(session, "web", file)
	Set item.FileName = "zz-"_$Char(8238)_"fdp.exe"
	Set item.FileMediaType = "text/html"
	Set item.FileSize = 1
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "the file Item is taken")
	Set turns = ..Turns(session)
	Do $$$AssertEquals(turns.Count(), 1, "one Turn")
	If turns.Count() '= 1 Quit
	Do $$$AssertEquals(turns.GetAt(1).SentFile, ##class(OcuTalon.Core.Files).Describe(file.ref, session).%ToJSON(), "SentFile is the stored row's ref, name, media type and size, never the Item's")
}

Method TestNoReaderReply()
{
	For channel = "web", "telegram" {
		Set session = ..Session(channel)
		Set ^OcuTalonTest("ConversationProbe", ..Number, "reader") = 0
		Set file = ..Store(session, channel, "zz<b>"_channel_".pdf")
		Set item = ..FileItem(session, channel, file)
		Set probe = ..NewProbe()
		Do $$$AssertStatusOK(probe.OnRequest(item, .response), channel_": the file Item is taken")
		Set probes(1) = probe
		Do ..Pump(.probes)
		Set reply = "I got zz<b>"_channel_".pdf, but I can't read files yet."
		Set row = ..Turns(session).GetAt(1)
		Do $$$AssertEquals(row.State_"|"_row.ReplyText_"|"_row.Tainted_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason, "done|"_reply_"|0||", channel_": the Turn is done with the fixed reply, untainted, and is no fallback")
		Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, channel_": nothing is sent to Decide")
		Set done = ..ChatEvents(session, row.Ref)
		Set last = done.%Get(done.%Size() - 1).payload
		Do $$$AssertEquals(last.state_"|"_last.replyText_"|"_last.sentFile.name, "done|"_reply_"|"_file.name, channel_": the done chat.message carries the reply and the file")
		Set outbound = ..SentFor("Notify", session)
		Do $$$AssertEquals($ListLength(outbound), 1, channel_": one Outbound goes to Notify")
		Do $$$AssertEquals(..Call($List(outbound, 1), "text")_"|"_..Call($List(outbound, 1), "originChannel")_"|"_..Call($List(outbound, 1), "catalogKey"), reply_"|"_channel_"|", channel_": with the reply text, the turn's channel and no catalog key")
	}
}

Method TestReaderTurnIsUntrusted()
{
	Set session = ..Session("reader")
	Set ^OcuTalonTest("ConversationProbe", ..Number, "reader") = 1
	Set file = ..StoreStream(session, "web", "zz-reader.pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 reader text"))
	Set item = ..FileItem(session, "web", file)
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the file Item is taken")
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 2, "with a reader the turn runs through Decide: two requests")
	Do $$$AssertEquals(..Call($List(decides, 1), "kind")_"|"_..Call($List(decides, 2), "kind"), "decide|turn", "decide, then turn")
	Do $$$AssertEquals(..Call($List(decides, 1), "provenance")_"|"_..Call($List(decides, 2), "provenance"), "untrusted|untrusted", "both requests carry provenance untrusted")
	Set row = ..Turns(session).GetAt(1)
	Set rebuilt = probe.ItemFor(row)
	Do $$$AssertEquals(rebuilt.Provenance_"|"_rebuilt.FileRef_"|"_rebuilt.FileName_"|"_rebuilt.FileMediaType_"|"_rebuilt.FileSize_"|"_rebuilt.Text, "untrusted|"_file.ref_"|"_file.name_"|application/pdf|"_file.size_"|", "the Item rebuilt from the Turn is untrusted and has the four file fields and no text")
	Do $$$AssertEquals(row.ReplyText '= "I got zz-reader.pdf, but I can't read files yet.", 1, "and the turn was not answered with the no-reader reply")
	// The gate: a context begun from the turn's request lets only safe, read-only tools run.
	Set request = ##class(OcuTalon.Core.Intake).RequestFor(rebuilt, "turn", "", "")
	Do $$$AssertEquals(request.Provenance, "untrusted", "the request built from that Item is untrusted")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request), "a context of the turn begins")
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", {"id": "call_id", "name": "set_reminder", "arguments": {}}, {"origin_class": "OcuTalon.Tools.ReminderTools", "requires_auth": false}, "OcuTalon.Test.Bridge.ProbeSink")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(..Sentence(sc), ##class(OcuTalon.Bridge.Policy.Gate).#UNTRUSTED, "set_reminder is denied with the gate's UNTRUSTED sentence")
}

Method TestFileItemDrops()
{
	Set session = ..Session("drops")
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session("zzconvfiles"_..Number_"other")
	Set ..Sessions = ..Sessions_","_other
	Set ..Refs = ..Refs_","_other
	Set mine = ..Store(session, "web", "zz-mine.pdf")
	Set theirs = ..Store(other, "web", "zz-theirs.pdf")
	Set mark = ..LastLog()
	Set cases = $ListBuild("provenance user", "another session's file", "unknown file", "no ItemId", "no session", "unknown session", "no text and no file")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set item = ..FileItem(session, "web", mine)
		If case = "provenance user" Set item.Provenance = "user"
		If case = "another session's file" Do ##class(OcuTalon.Core.Files).SetItem(item, theirs)
		If case = "unknown file" Set item.FileRef = "zzunknownfileref"_..Number
		If case = "no ItemId" Set item.ItemId = ""
		If case = "no session" Set item.SessionRef = ""
		If case = "unknown session" Set item.SessionRef = "zzunknownsession"_..Number
		If case = "no text and no file" {
			Set item = ..FileItem(session, "web", mine)
			Set item.FileRef = "", item.FileName = "", item.FileMediaType = "", item.FileSize = ""
		}
		Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), case_": the status is OK")
		Do $$$AssertEquals(..Turns(session).Count(), 0, case_": no Turn is made")
		Do $$$AssertEquals(..Calls(), 0, case_": nothing is sent")
		Do $$$AssertEquals(..ChatEvents(session).%Size(), 0, case_": nothing is published")
	}
	Do $$$AssertEquals(..Warnings(mark, .text), 7, "each drop is one warning")
	Do $$$AssertTrue((text '[ "zz-mine") && (text '[ "zz-theirs") && (text '[ ..#MARKER), "and no warning names a file")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Take", "Conversation dropped an item")
	Set item = ..FileItem(session, "web", mine)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "a good file Item is taken")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "and makes a Turn")
}

Method TestMarkerReachesNothing()
{
	Set session = ..Session("marker")
	Set file = ..Store(session, "web", "zz-marker.pdf")
	Set ^OcuTalonTest("ConversationProbe", ..Number, "reader") = 1
	Set probe = ..NewProbe()
	Do probe.OnRequest(..FileItem(session, "web", file), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Do $$$AssertTrue(..Calls() > 0, "the turn made calls")
	Set found = 0
	Set key = $Name(^OcuTalonTest("ConversationProbe", ..Number))
	Set node = key
	For {
		Set node = $Query(@node, 1, value)
		Quit:node=""
		If $Extract(node, 1, $Length(key) - 1) '= $Extract(key, 1, $Length(key) - 1) Quit
		If value [ ..#MARKER Set found = found + 1
	}
	Do $$$AssertEquals(found, 0, "the marker is in no recorded call")
	Set row = ..Turns(session).GetAt(1)
	Do $$$AssertTrue($Get(^OcuTalonP.TurnD(row.%Id())) '[ ..#MARKER, "and in no field of the Turn")
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Do $$$AssertTrue(events.%ToJSON() '[ ..#MARKER, "and in no event")
}

Method TestReadFailure()
{
	Set session = ..Session("failure")
	Set file = ..StoreStream(session, "web", "zz-damaged.pdf", ##class(OcuTalon.Test.Docs.Samples).PdfJunk())
	Do ..RunFile(session, file)
	Set row = ..Turns(session).GetAt(1)
	Set reason = {}.%FromJSON(row.FileRead).reason
	Set reply = ##class(OcuTalon.Docs.Extract).Failure(reason)
	Do $$$AssertTrue(reason '= "", "the read gave a reason code: "_reason)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText_"|"_row.Tainted_"|"_row.ReplyCatalogKey, "done|"_reply_"|0|", "the Turn is done with the code-written sentence of the reason, and is no fallback")
	Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, "nothing is sent to Decide: no request and no model call")
	Do $$$AssertEquals(row.TriageDecisionRef_row.TurnDecisionRef, "", "and the turn has no Decision")
	Set read = {}.%FromJSON(row.FileRead)
	Do $$$AssertEquals(read.read_"|"_read.kind_"|"_read.fileRef_"|"_read.%IsDefined("text"), "0|document|"_file.ref_"|0", "FileRead is read 0 of the document, without a text member")
	Set done = ..ChatEvents(session, row.Ref)
	Set last = done.%Get(done.%Size() - 1).payload
	Do $$$AssertEquals(last.state_"|"_last.replyText, "done|"_reply, "the done chat.message carries the sentence")
	Do $$$AssertEquals(last.fileRead.%ToJSON(), {"fileRef": (file.ref), "kind": "document", "read": 0, "addable": 0}.%ToJSON(), "and fileRead {fileRef, kind, read 0, addable 0}")
	Set outbound = ..SentFor("Notify", session)
	Do $$$AssertEquals($ListLength(outbound), 1, "one Outbound goes to Notify")
	Do $$$AssertEquals(..Call($List(outbound, 1), "text"), reply, "with the sentence")
}

Method TestReadDocument()
{
	Set session = ..Session("document")
	Set file = ..StoreStream(session, "web", "zz-readable.pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 readable text"))
	Do ..RunFile(session, file)
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 2, "a readable document runs through Decide: two requests")
	Set saved = {}.%FromJSON(..Call($List(decides, 1), "fileRead"))
	Do $$$AssertEquals(saved.read_"|"_saved.addable_"|"_saved.kind, "1|1|document", "FileRead (read 1, addable 1) was saved before the decide request was sent")
	Do $$$AssertEquals(saved.%IsDefined("text"), 0, "and holds no text")
	Do $$$AssertEquals(..Call($List(decides, 1), "provenance")_"|"_..Call($List(decides, 2), "provenance"), "untrusted|untrusted", "both requests carry provenance untrusted")
	Set row = ..Turns(session).GetAt(1)
	Do $$$AssertEquals(row.State, "done", "the turn is done")
	Set done = ..ChatEvents(session, row.Ref)
	Set last = done.%Get(done.%Size() - 1).payload
	Do $$$AssertEquals(last.fileRead.%ToJSON(), {"fileRef": (file.ref), "kind": "document", "read": 1, "addable": 1}.%ToJSON(), "the done chat.message carries fileRead addable 1")
}

Method TestReadError()
{
	For mode = "error", "nonobject", "notext" {
		For kind = "document", "photo" {
			Set session = ..Session("err"_mode_kind)
			Set label = mode_" "_kind
			If kind = "document" {
				Set file = ..StoreStream(session, "web", "zz-err-"_mode_".pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 never read"))
			} Else {
				Set file = ..StoreStream(session, "web", "zz-err-"_mode_".jpg", ##class(OcuTalon.Test.Docs.Samples).Stream($Char(255, 216, 255, 224)_"JFIF zz25s6 never read"))
			}
			Do ..RunFile(session, file, "", mode)
			Set row = ..Turns(session).GetAt(1)
			Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|"_##class(OcuTalon.Docs.Extract).Failure("failed"), label_": the turn ends with the failed sentence")
			Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, label_": nothing is sent to Decide")
			Do $$$AssertEquals(row.TriageDecisionRef_row.TurnDecisionRef, "", label_": and the turn has no Decision")
			Set read = {}.%FromJSON(row.FileRead)
			Do $$$AssertEquals(read.read_"|"_read.reason_"|"_read.kind_"|"_read.fileRef_"|"_read.%IsDefined("text"), "0|"_$Select(mode = "notext": "damaged", 1: "failed")_"|"_kind_"|"_file.ref_"|0", label_": FileRead is read 0 of the file's kind, without a text member")
		}
	}
}

/// A photo is read like a document: FileRead is {kind photo, read 1, addable 0}, the turn goes through Decide untrusted, and its chat.message fileRead is not addable.
Method TestReadPhoto()
{
	Set session = ..Session("photo")
	Set file = ..StoreStream(session, "web", "zz-photo.jpg", ##class(OcuTalon.Test.Docs.Samples).Stream($Char(255, 216, 255, 224)_"JFIF zz25s6 photo"))
	Do ..RunFile(session, file)
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 2, "a readable photo runs through Decide: two requests")
	Set saved = {}.%FromJSON(..Call($List(decides, 1), "fileRead"))
	Do $$$AssertEquals(saved.read_"|"_saved.addable_"|"_saved.kind_"|"_saved.%IsDefined("text"), "1|0|photo|0", "FileRead (photo, read 1, addable 0, no text) was saved before the decide request was sent")
	Do $$$AssertEquals(..Call($List(decides, 1), "provenance")_"|"_..Call($List(decides, 2), "provenance"), "untrusted|untrusted", "both requests carry provenance untrusted")
	Set row = ..Turns(session).GetAt(1)
	Do $$$AssertEquals(row.State, "done", "the turn is done")
	Set done = ..ChatEvents(session, row.Ref)
	Set last = done.%Get(done.%Size() - 1).payload
	Do $$$AssertEquals(last.fileRead.%ToJSON(), {"fileRef": (file.ref), "kind": "photo", "read": 1, "addable": 0}.%ToJSON(), "the done chat.message carries fileRead addable 0")
}

/// With the online demo flag set nothing is read (Agent.Input.ReadFile): a PDF and a photo each end the turn with the failed sentence and no Decide send, whatever the Item says.
Method TestReadOnDemo()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Try {
		For kind = "document", "photo" {
			Set session = ..Session("demo"_kind)
			If kind = "document" {
				Set file = ..StoreStream(session, "web", "zz-demo.pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 demo text"))
			} Else {
				Set file = ..StoreStream(session, "web", "zz-demo.jpg", ##class(OcuTalon.Test.Docs.Samples).Stream($Char(255, 216, 255, 224)_"JFIF zz25s6 demo"))
			}
			// The Decide double holds a usable caption reply, so that "no Caption" below fails if the turn reached Decide.
			Do ..RunFile(session, file, {"caption": {"memoryRef": "zzdemocap", "text": "zz demo caption"}}.%ToJSON())
			Set row = ..Turns(session).GetAt(1)
			Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|"_##class(OcuTalon.Docs.Extract).Failure("failed"), kind_": the turn ends with the failed sentence")
			Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, kind_": nothing is sent to Decide")
			Set read = {}.%FromJSON(row.FileRead)
			Do $$$AssertEquals(read.read_"|"_read.reason_"|"_read.kind, "0|failed|"_kind, kind_": FileRead is read 0, failed")
			Do $$$AssertEquals(row.Caption, "", kind_": and the turn has no Caption")
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the demo test failed: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
}

Method TestCaptionCarried()
{
	Set good = {"memoryRef": "zzcap1", "text": "A red bicycle by a wall."}
	Set cases = $ListBuild(
		$ListBuild("valid", {"caption": (good)}.%ToJSON(), good.%ToJSON()),
		$ListBuild("extra member", {"caption": {"memoryRef": "zzcap1", "text": "A red bicycle by a wall.", "x": 1}}.%ToJSON(), good.%ToJSON()),
		$ListBuild("no text", {"caption": {"memoryRef": "zzcap1"}}.%ToJSON(), ""),
		$ListBuild("empty ref", {"caption": {"memoryRef": "", "text": "x"}}.%ToJSON(), ""),
		$ListBuild("number text", {"caption": {"memoryRef": "zzcap1", "text": 5}}.%ToJSON(), ""),
		$ListBuild("not an object", {"caption": "x"}.%ToJSON(), ""),
		$ListBuild("an array", {"caption": [(good)]}.%ToJSON(), ""),
		$ListBuild("bad json", "{""caption"": {", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set session = ..Session("cap"_position)
		Set file = ..StoreStream(session, "web", "zz-cap"_position_".pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 caption turn"))
		Do ..RunFile(session, file, $List(case, 2))
		Set row = ..Turns(session).GetAt(1)
		Do $$$AssertEquals(row.State, "done", label_": the turn ends")
		Do $$$AssertEquals(row.Caption, $List(case, 3), label_": the Turn's Caption")
		Set done = ..ChatEvents(session, row.Ref)
		Set last = done.%Get(done.%Size() - 1).payload
		Do $$$AssertEquals($Select(last.%IsDefined("caption"): last.caption.%ToJSON(), 1: ""), $List(case, 3), label_": and the chat.message caption")
		Set outbound = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(outbound, 1), "learned")_..Call($List(outbound, 1), "memories"), "", label_": the Outbound carries no caption member")
	}
	// An unusable reply saves nothing: a fallback reply that carries a caption in its HostData keeps no Caption, and its chat.message has no caption.
	Set position = 0
	Set answers = $ListBuild("fallback:budget", "fallback:zzbogus")
	While $ListNext(answers, position, answer) {
		Set label = "a reply of "_answer_" with a caption in its HostData"
		Set session = ..Session("capfb"_position)
		Set file = ..StoreStream(session, "web", "zz-capfb"_position_".pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 caption fallback"))
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild(answer))
		Do ..RunFile(session, file, {"caption": (good)}.%ToJSON())
		Set row = ..Turns(session).GetAt(1)
		Do $$$AssertEquals(row.State, "done", label_": the turn ends")
		Do $$$AssertEquals(row.FallbackReason, $Select(answer = "fallback:budget": "budget", 1: "unusable"), label_": it ended as a fallback, not as a model reply")
		Do $$$AssertEquals(row.Caption, "", label_": the Turn has no Caption")
		Set done = ..ChatEvents(session, row.Ref)
		Set last = done.%Get(done.%Size() - 1).payload
		Do $$$AssertEquals(last.%IsDefined("caption"), 0, label_": and its chat.message has no caption")
	}
}

/// P3 hygiene: the extracted text and the bytes of the file are in no stored column, chat.message or Outbound.
Method TestNoExtractedText()
{
	Set content = "zz25s6content"_..Number
	Set bytesMark = "zz25s6bytes"_..Number
	Set session = ..Session("hygiene")
	Set file = ..StoreStream(session, "web", "zz-hygiene.pdf", ##class(OcuTalon.Test.Docs.Samples).PdfText("zz25s6 text "_content, "%"_bytesMark))
	Do ..RunFile(session, file, {"caption": {"memoryRef": "zzcaphyg", "text": "A caption without the file text."}}.%ToJSON())
	Set row = ..Turns(session).GetAt(1)
	Do $$$AssertEquals(row.State, "done", "the turn is done")
	// A positive control: the content reached the turn's request Input, as chat text does.
	Set seen = ##class(OcuTalon.Test.Core.DecideDouble).Seen(session)
	Set inInput = 0
	For i = 0:1:seen.%Size() - 1 {
		If seen.%Get(i).input [ content Set inInput = inInput + 1
		If seen.%Get(i).input [ bytesMark Set inInput = inInput + 100
	}
	Do $$$AssertEquals(inInput, 2, "the content marker is in the Input of both requests, and the bytes marker in neither")
	// The two columns.
	Set read = {}.%FromJSON(row.FileRead)
	Set keys = ""
	Set iterator = read.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
		Do $$$AssertTrue(((value _ "") '[ content) && ((value _ "") '[ bytesMark) && ((value _ "") '[ "%PDF"), "FileRead member "_key_" holds neither marker nor bytes")
	}
	Do $$$AssertEquals(keys, "fileRef,kind,read,chars,cut,addable", "FileRead has only its members: no text member")
	Do $$$AssertEquals(read.%GetTypeOf("chars")_"|"_(read.chars > $Length(content)), "number|1", "chars is a count of the text's characters, never a copy of it")
	Do $$$AssertTrue((row.FileRead '[ content) && (row.FileRead '[ bytesMark) && (row.Caption '[ content) && (row.Caption '[ bytesMark), "neither column holds a marker")
	// The whole stored row, the events and the Outbound.
	Do $$$AssertTrue(($Get(^OcuTalonP.TurnD(row.%Id())) '[ content) && ($Get(^OcuTalonP.TurnD(row.%Id())) '[ bytesMark), "no field of the stored Turn holds a marker")
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Do $$$AssertTrue((events.%ToJSON() '[ content) && (events.%ToJSON() '[ bytesMark), "no chat.message holds a marker")
	Set done = ..ChatEvents(session, row.Ref)
	Set last = done.%Get(done.%Size() - 1).payload
	Do $$$AssertEquals(last.fileRead.%ToJSON(), {"fileRef": (file.ref), "kind": "document", "read": 1, "addable": 1}.%ToJSON(), "chat.message fileRead holds exactly four members")
	Set outbound = ..SentFor("Notify", session)
	Do $$$AssertEquals($ListLength(outbound), 1, "one Outbound")
	Set leak = 0
	For n = 1:1:..Calls() {
		If ..Call(n, "target") '= "Notify" Continue
		Set field = ""
		For {
			Set field = $Order(^OcuTalonTest("ConversationProbe", ..Number, n, field), 1, value)
			Quit:field=""
			If (value [ content) || (value [ bytesMark) Set leak = leak + 1
		}
	}
	Do $$$AssertEquals(leak, 0, "no Outbound field holds a marker")
}

/// --- helpers ---
/// Takes the file turn of the session as a Conversation with a reader (the real ReadFile, unless readfile names a failing seam), and pumps it to its end. hostData, when given, is the
/// HostData of the turn's reply.
Method RunFile(session As %String, file As %DynamicObject, hostData As %String = "", readfile As %String = "") [ Private ]
{
	Set ^OcuTalonTest("ConversationProbe", ..Number, "reader") = 1
	If readfile '= "" Set ^OcuTalonTest("ConversationProbe", ..Number, "readfile") = readfile
	If hostData '= "" Do ##class(OcuTalon.Test.Core.DecideDouble).SetReply(session, hostData)
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(..FileItem(session, "web", file), .response), "the file Item is taken")
	Set probes(1) = probe
	Do ..Pump(.probes)
}

/// Stores the stream as a file of the session; the file object {ref, name, mediaType, size}.
Method StoreStream(session As %String, channel As %String, name As %String, bytes As %Stream.Object) As %DynamicObject [ Private ]
{
	Set code = ##class(OcuTalon.Core.Files).Store(session, channel, name, bytes, .file, .sc)
	Do $$$AssertEquals(code, "", "the file "_name_" is stored")
	Quit file
}

/// A fixture session; its Ref is kept for the clean-up and the double's scripts are cleared.
Method Session(name As %String) As %String [ Private ]
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzconvfiles"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ##class(OcuTalon.Test.Core.DecideDouble).Clear(ref)
	Quit ref
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Core.ConversationProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.ConversationProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// Stores a small PDF that holds the marker for the session and returns the file object {ref, name, mediaType, size}.
Method Store(session As %String, channel As %String, name As %String) As %DynamicObject [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write("%PDF-1.4 "_..#MARKER)
	Do bytes.Rewind()
	Set code = ##class(OcuTalon.Core.Files).Store(session, channel, name, bytes, .file, .sc)
	Do $$$AssertEquals(code, "", "the file "_name_" is stored")
	Quit file
}

/// The Item for the stored file as a channel builds it: untrusted, the four file fields from SetItem, no text. The web channel gives it a ClientId.
Method FileItem(session As %String, channel As %String, file As %DynamicObject) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = session
	Set item.Channel = channel
	Set item.Provenance = "untrusted"
	If channel = "web" Set item.ClientId = "zzc"_..Number_$Increment(^OcuTalonTest("ConversationFiles", "c"))
	Do ##class(OcuTalon.Core.Files).SetItem(item, file)
	Quit item
}

/// The sentence of a gate denial without its prefix.
ClassMethod Sentence(sc As %Status) As %String [ Private ]
{
	If $$$ISOK(sc) Quit "<OK>"
	Set text = $SYSTEM.Status.GetOneStatusText(sc)
	Set prefix = "Tool access denied: "
	Quit $Select($Extract(text, 1, $Length(prefix)) = prefix: $Extract(text, $Length(prefix) + 1, *), 1: text)
}

/// Hands every kept answer of every probe to its callbacks, and every RunTurns request that a probe recorded to a new probe, until no work is left.
Method Pump(ByRef probes) [ Private ]
{
	For round = 1:1:200 {
		Set work = 0
		Set i = ""
		For {
			Set i = $Order(probes(i))
			Quit:i=""
			Set work = work + probes(i).Deliver()
		}
		Set limit = ..Calls()
		For n = ..Handled + 1:1:limit {
			If (..Call(n, "target") = "Conversation") && (..Call(n, "class") = "OcuTalon.Core.Msg.RunTurns") {
				Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
				Set run.SessionRef = ..Call(n, "sessionRef")
				Set probe = ..NewProbe()
				Set probes($Order(probes(""), -1) + 1) = probe
				Do $$$AssertStatusOK(probe.OnRequest(run, .response), "the RunTurns request is handled by a new instance")
				Set work = work + 1
			}
		}
		Set ..Handled = limit
		If 'work Quit
	}
}

/// The number of calls the probes recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("ConversationProbe", ..Number))
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("ConversationProbe", ..Number, n, field))
}

/// The numbers of the calls to the target, as a list; with kind only the Decide requests of that kind.
Method Sent(target As %String, kind As %String = "") As %List [ Private ]
{
	Set list = ""
	For n = 1:1:..Calls() {
		If ..Call(n, "target") '= target Continue
		If (kind '= "") && (..Call(n, "kind") '= kind) Continue
		Set list = list_$ListBuild(n)
	}
	Quit list
}

/// The numbers of the calls to the target for the session (an Outbound's sessionRef).
Method SentFor(target As %String, session As %String) As %List [ Private ]
{
	Set list = ""
	For n = 1:1:..Calls() {
		If (..Call(n, "target") = target) && (..Call(n, "sessionRef") = session) Set list = list_$ListBuild(n)
	}
	Quit list
}

/// The session's turns, as Ownership reads them.
Method Turns(session As %String) As %ListOfObjects [ Private ]
{
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
	Do $$$AssertStatusOK(sc, "the turns are read")
	Quit turns
}

/// The chat.message events of the session's stream, in order, as an array; with ref only those of that turn.
Method ChatEvents(session As %String, ref As %String = "") As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "chat.message") && ((ref = "") || (event.payload.ref = ref)) Do found.%Push(event)
	}
	Quit found
}

/// The number of the newest row of the event log, 0 when it is empty.
Method LastLog() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings that Conversation logged for a dropped Item after the row mark; text is the newest one's text.
Method Warnings(mark As %Integer, Output text As %String) As %Integer [ Private ]
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ? ORDER BY ID", mark, "Take", "Conversation dropped an item")
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

}
