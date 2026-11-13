/// Tests of the file turn of Conversation (Story 25.3; AD-6, AD-10, AD-14, AD-30; security condition (i), ruling 4). Safe on a slot: no production runs there, so the tests
/// call OnRequest on shadow instances of Test.Core.ConversationProbe, as Test.Core.ConversationTurns does. The files are stored through Core.Files.Store and the Items
/// are built as WebChatIn (channel web) and a Telegram service (channel telegram, a fixture) build them: provenance untrusted, the four file fields from SetItem. Every
/// sentence is written out here.
///   - TestFileItemBecomesTurn: a web file Item and a Telegram file Item each become a Turn of their own session with SentFile set from the stored row (exactly ref, name,
///     mediaType and size), no text, the Item's channel, and the queued chat.message carries sentFile with those four keys;
///   - TestNoReaderReply: with no reader (the real Core.Files.Readable), each of the two turns ends done with the reply "I got {name}, but I can't read files yet." (the
///     safe name), nothing is sent to Decide, the done chat.message carries the reply and sentFile, one Outbound goes to Notify with that text and the turn's channel, and
///     the turn is not tainted;
///   - TestReaderTurnIsUntrusted: with a reader (the probe's seam), the decide and the turn request both carry provenance untrusted, the Item that ItemOf rebuilds is untrusted
///     with the four file fields, and in a context begun from that request the gate denies a tool that is not read-only with its UNTRUSTED sentence;
///   - TestFileItemDrops: a file Item with provenance user, one whose FileRef is another session's, one with an unknown FileRef, one with no ItemId and one with no session
///     are each dropped (no Turn, no call, no event), and an Item with no text and no FileRef is still dropped;
///   - TestMarkerReachesNothing: the bytes of the file (a marker string) are in no Turn row, no recorded call and no event of the session.
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

Method TestNoReaderReply()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable(), 0, "nothing reads a file on this branch")
	For channel = "web", "telegram" {
		Set session = ..Session(channel)
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
	Set file = ..Store(session, "web", "zz-reader.pdf")
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

/// --- helpers ---
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
