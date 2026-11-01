Include Ensemble

/// The abstract base of the live Telegram tests (Story 12.2; AD-22, NFR-11). It has no Test methods, so it is no test class and joins no
/// shard run. The classes that extend it run in throwaway stacks and in CI only (Rule 21), against the CI mock and its dummy token: the CI
/// override points OCUTALON_TELEGRAM_API_BASE at the mock and sets TELEGRAM_BOT_TOKEN to a dummy.
///   - Token, Ready, Finish and Safe: the guard that every live test starts with. Ready fails the test, with the reason, unless the stack
///     is a throwaway with the mock and no TelegramIn job, and resets the mock's Bot API side; Finish resets it again. No text of a
///     failure holds the token.
///   - ReadyLive adds that the production runs, and saves the two Telegram marks. A test that enables an item calls it first.
///   - StartItems and StopItems enable and disable items on the running production, with the System Default Setting row of each item's
///     Enabled snapshotted before and put back after; the job of each item is waited for. StartItems refuses an item whose ApiBase row
///     could reach the public Bot API.
///   - SaveMarks and RestoreMarks keep the marks telegramState and telegramPaused, DropChats deletes the Pairing rows of fixture chat ids,
///     FixtureSession and DropSessions make and remove the zztg... sessions that StateBody needs, and Cleanup does all the endings, so
///     that every test ends with the one call on every path. DropSessions is a public class method (Story 12.5): the second user of it is
///     OcuTalon.Test.Channel.TelegramPageFixture.Finish, which removes the fixture sessions that the page test's Move made.
///   - The wait helpers poll for the offset, the Telegram state, a mark and the mock's calls.
///   - WaitMonitor, InstanceSeq, Events, WaitEvent and WaitClear read the telegramPaused status events that the production's own
///     StatusMonitor publishes on the instance stream (the pattern of OcuTalon.Test.Schedule.Stalled): the monitor's silent first run must be
///     over, and a test that caused a pause waits for its clear, so that no event of it lands in a later test's window.
///   - The helpers that keep no state of the test are public class methods (BaseReason, WaitJobs, CallsOf, WaitCalls, WaitState, WaitMark,
///     WaitMonitor, MonitorSettled, MonitorAge, InstanceSeq, Events, WaitEvent, WaitClear, EpochNow, Cut), and so are Enable, Disable, Marks
///     and PutMarks, which hold the bodies of StartItems, StopItems, SaveMarks and RestoreMarks. The second user of them is
///     OcuTalon.Test.Channel.TelegramPageFixture (Story 12.8), which the page's browser test calls from an IRIS script.
///   - PrivateMessage (an update with a name and a text), TextsTo (the sendMessage texts to one chat) and PairBodies (the Pair commands, or
///     with the verb Unpair the Unpair commands of Story 12.5, since a header mark) are public class methods for the pairing tests (Story
///     12.4); OcuTalon.Test.Channel.TelegramPageFixture calls the first.
///   - BeginPairing and EndPairing (Story 12.6) are the start and the end that the two pairing-based classes share (TelegramPair and
///     TelegramChat): the live guard, the seam on, demo mode checked, both Telegram items on and a long poll open; and the turns of the
///     fixture sessions settled and adopted for their removal, the cleanup, the code rows and the probe row deleted and the seam put back.
///     NewSession, NewCode, Send, Handled, ChatRow, WaitLinked and PairChat, which pair a fixture chat through the real /start path, move
///     there with them. DropSessions also deletes the Turn, Delivery and SimMessage rows of the fixture sessions (zztg...).
///   - Items, Notifications and TextsAfter read what a pairing test checks: the Items that TelegramIn sent to Conversation after a header
///     mark (with the header's SessionId and SuperSession), the Notifications it sent to Notify, and the texts the mock got for a chat.
///   - The scans of the token search are public class methods too: HeaderMark and HeadersFrom (the message headers), RowsText (every text
///     of a SELECT's rows), Bodies (the exported body of every header after a mark) and LiveMark (the live events). TelegramIn calls the
///     two header ones and TelegramNoToken the other four as its own; TelegramPageFixture's search of the pairing codes (Story 12.3) calls
///     HeaderMark, RowsText, Bodies and LiveMark from outside.
Class OcuTalon.Test.Channel.LiveCase Extends %UnitTest.TestCase [ Abstract ]
{

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter BOTAPI = "OcuTalon.Test.Channel.BotApi";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The longest, in seconds, that StartItems and StopItems wait for the jobs of an item.
Parameter WAITJOB = 30;

/// The longest, in seconds, to wait for an effect of a handled update.
Parameter WAIT = 10;

/// The two marks that the Telegram items write.
Parameter MARKS = "telegramState,telegramPaused";

/// The Bot API token of this stack (the CI dummy); never written anywhere.
Property Token As %String [ Private ];

/// The snapshots of the Enabled rows of the started items (RunnerFixture.RememberDefault).
Property RowsFound As %String(MAXLEN = "") [ Private ];

/// The started items, comma-separated.
Property StartedItems As %String [ Private ];

/// The marks as found, as a list of $ListBuild(mark, value).
Property MarksFound As %String(MAXLEN = "") [ Private ];

/// The fixture chat ids that Cleanup deletes, comma-separated.
Property ChatIds As %String(MAXLEN = "") [ Private ];

/// The updates queued so far by Send (the mock numbers them from 1 after the reset, and TelegramIn keeps the id of the last handled plus 1).
Property Sent As %Integer [ InitialExpression = 0, Private ];

/// 1 once the Telegram seam is set by BeginPairing.
Property Seam As %Boolean [ InitialExpression = 0, Private ];

/// The seam as BeginPairing found it.
Property WasIncluded As %Boolean [ Private ];

/// The Refs of the fixture sessions that NewSession made, as a list: EndPairing deletes their code rows and adopts their turns.
Property Sessions As %List [ Private ];

/// The unique text of an event-log probe row, removed by EndPairing.
Property Probe As %String [ Private ];

/// "" when the test may send: the stack is a throwaway, no poller has a live job, and the reset worked; otherwise the reason. Nothing is
/// asserted here, so that it can run in OnBeforeAllTests.
Method ReadyReason() As %String [ Private ]
{
	Set ..Token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
	Set reason = ##class(OcuTalon.Test.Contract.Mock).TelegramMissingReason($SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASEVAR), ..Token)
	If reason = "" Set reason = ##class(OcuTalon.Test.Channel.BotApi).PollerReason()
	If reason '= "" Quit reason
	Set status = ##class(OcuTalon.Test.Channel.BotApi).Reset()
	If $$$ISERR(status) Quit "the mock's Bot API side could not be reset: "_..Cut($SYSTEM.Status.GetErrorText(status), ..Token)
	Quit ""
}

/// 1 when the test may send (ReadyReason is empty); otherwise the test fails with the reason.
Method Ready() As %Boolean [ Private ]
{
	Set reason = ..ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// Ends a test: the reset again, whatever happened.
Method Finish() [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Channel.BotApi).Reset(), "the mock's Bot API side is reset after the test")
}

/// The text of an exception with the token cut out.
Method Safe(ex As %Exception.AbstractException) As %String [ Private ]
{
	Quit ..Cut(ex.DisplayString(), ..Token)
}

/// The text in one line, with the token cut out (an empty token cuts nothing).
ClassMethod Cut(text As %String, token As %String) As %String
{
	Set text = $Translate(text, $Char(13, 10), "  ")
	If $Get(token) '= "" Set text = $Replace(text, token, "[token]")
	Quit text
}

/// Ready, and the production must run (a test that enables an item needs it); the two Telegram marks are saved.
Method ReadyLive() As %Boolean [ Private ]
{
	If '..Ready() Quit 0
	Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Do ..SaveMarks()
	Quit 1
}

/// Enables each item (comma-separated) on the running production and waits for a job of it. The System Default Setting row of each
/// item's Enabled is snapshotted first (a missing row is made with 0, so that the item's own flag is never saved), and StopItems puts it back.
/// An item whose ApiBase row does not name the CI mock or a loopback address over http is not enabled (BaseReason), so that no live
/// test reaches the public Bot API.
Method StartItems(items As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	For i = 1:1:$Length(items, ",") {
		Set item = $Piece(items, ",", i)
		Set rows = ..RowsFound
		Set sc = ..Enable(item, .rows)
		Set ..RowsFound = rows
		If ..BaseReason(item) = "" Set ..StartedItems = ..StartedItems _ $Select(..StartedItems = "": "", 1: ",") _ item
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// Enables one item on the running production and waits for a job of it. rows is the list of snapshots of the Enabled rows
/// (RunnerFixture.RememberDefault): the item's row is added to it before anything is changed, so that Disable can put the row back
/// even when this fails. A row missing for the item is made with 0, so that the item's own flag is never saved. The item is not enabled,
/// and rows is left as it was, when its ApiBase row could reach the public Bot API (BaseReason).
ClassMethod Enable(item As %String, ByRef rows As %List) As %Status
{
	Set reason = ..BaseReason(item)
	If reason '= "" Quit $SYSTEM.Status.Error(5001, reason)
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .rows, item, "Enabled")
	If '$List($ClassMethod(..#FIXTURE, "SnapshotDefault", item, "Enabled"), 3) {
		Set sc = $ClassMethod(..#FIXTURE, "PutDefault", item, "Enabled", 0)
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ##class(Ens.Director).EnableConfigItem(item, 1, 1)
	If $$$ISERR(sc) Quit sc
	If '..WaitJobs(item, 1) Quit $SYSTEM.Status.Error(5001, item_" has no job "_..#WAITJOB_" s after it was enabled")
	Quit $$$OK
}

/// "" when the item's ApiBase row names the CI mock's host or 127.0.0.1 over http; otherwise the reason not to enable the item.
ClassMethod BaseReason(item As %String) As %String
{
	Set row = $ClassMethod(..#FIXTURE, "SnapshotDefault", item, "ApiBase")
	If '$List(row, 3) Quit item_" has no ApiBase row, so it would call the public Bot API; it is not enabled"
	Set api = "OcuTalon.Channel.Telegram.Api"
	Set sc = $ClassMethod(api, "Endpoint", $List(row, 4), .server, .port, .https, .prefix)
	Do $ClassMethod(api, "Endpoint", ##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASE, .mock)
	If $$$ISERR(sc) || https || ((server '= mock) && (server '= "127.0.0.1")) Quit item_"'s ApiBase row names neither the CI mock nor 127.0.0.1 over http; it is not enabled"
	Quit ""
}

/// Disables the started items, waits until each has no job, and puts the Enabled rows back. The status is the first failure; an
/// item that is already disabled is not a failure. Safe to call when nothing was started.
Method StopItems() As %Status [ Private ]
{
	Set sc = ..Disable(..StartedItems, ..RowsFound)
	Set ..RowsFound = ""
	Set ..StartedItems = ""
	Quit sc
}

/// Disables the items (comma-separated), waits until each has no job, and puts back the Enabled rows of rows, as Enable collected them.
/// The status is the first failure; an item that is already disabled is not a failure.
ClassMethod Disable(items As %String, rows As %List) As %Status
{
	Set first = $$$OK
	For i = 1:1:$Length(items, ",") {
		Set item = $Piece(items, ",", i)
		If item = "" Continue
		Set row = $ClassMethod(..#FIXTURE, "SnapshotDefault", item, "Enabled")
		If $List(row, 3) && ($List(row, 4) '= 0) {
			Set sc = ##class(Ens.Director).EnableConfigItem(item, 0, 1)
			If $$$ISERR(sc) && $$$ISOK(first) Set first = sc
		}
		If '..WaitJobs(item, 0) && $$$ISOK(first) Set first = $SYSTEM.Status.Error(5001, item_" still has a job "_..#WAITJOB_" s after it was disabled")
	}
	Set sc = $ClassMethod(..#FIXTURE, "RestoreDefaults", $Get(rows))
	If $$$ISERR(sc) && $$$ISOK(first) Set first = sc
	Quit first
}

/// 1 when the item has a job (running = 1) or has none (running = 0) within WAITJOB seconds.
ClassMethod WaitJobs(item As %String, running As %Boolean) As %Boolean
{
	Set deadline = $ZHorolog + ..#WAITJOB
	For {
		Set has = ($ListLength($ClassMethod(..#FIXTURE, "Jobs", item)) > 0)
		If (has = running) || ($ZHorolog >= deadline) Quit
		Hang 0.5
	}
	Quit has = running
}

/// Saves the two Telegram marks as found.
Method SaveMarks() [ Private ]
{
	Set ..MarksFound = ..Marks()
}

/// The two Telegram marks as they are now, as a list of $ListBuild(mark, value).
ClassMethod Marks() As %List
{
	Set found = ""
	For i = 1:1:$Length(..#MARKS, ",") {
		Set mark = $Piece(..#MARKS, ",", i)
		Set found = found _ $ListBuild($ListBuild(mark, ##class(OcuTalon.Data.StatusMark).Get(mark)))
	}
	Quit found
}

/// Puts the two Telegram marks back as SaveMarks found them (a mark that had no row is deleted).
Method RestoreMarks() [ Private ]
{
	Do ..PutMarks(..MarksFound)
}

/// Puts the marks of found, a list as Marks gives it, back (a mark that had no row is deleted).
ClassMethod PutMarks(found As %List)
{
	Set position = 0
	While $ListNext($Get(found), position, one) {
		Do ##class(OcuTalon.Data.StatusMark).Record($List(one, 1), $List(one, 2))
	}
}

/// Adds fixture chat ids (comma-separated) to the ones that Cleanup deletes.
Method Chat(ids As %String) [ Private ]
{
	Set ..ChatIds = ..ChatIds _ $Select(..ChatIds = "": "", 1: ",") _ ids
}

/// Deletes the Pairing rows of the chat ids (comma-separated).
Method DropChats(ids As %String) [ Private ]
{
	For i = 1:1:$Length(ids, ",") {
		Set id = $Piece(ids, ",", i)
		If id '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE ChatId = ?", id)
	}
}

/// The number of Pairing rows of the chat id.
Method ChatRows(chatId As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE ChatId = ?", chatId)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The highest id of the message headers: the mark that HeadersFrom reads from.
ClassMethod HeaderMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of message headers after the mark whose source item is the item.
ClassMethod HeadersFrom(mark As %Integer, item As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = ?", mark, item)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Every text of every row of a SELECT that names its columns, as one text.
ClassMethod RowsText(sql As %String, mark As %Integer) As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, mark)
	While result.%Next() {
		For column = 1:1:result.%ResultColumnCount {
			Set text = text _ result.%GetData(column) _ $Char(10)
		}
	}
	Quit text
}

/// The exported body of every message header after the mark, as one text.
ClassMethod Bodies(mark As %Integer) As %String
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ?", mark)
	While result.%Next() {
		Set class = result.%GetData(1)
		Set id = result.%GetData(2)
		If (class = "") || (id = "") Continue
		Try {
			Set body = $ClassMethod(class, "%OpenId", id)
			If $IsObject(body) {
				Set xml = ""
				If body.%Extends("%XML.Adaptor") && $$$ISOK(body.XMLExportToString(.xml)) Set text = text _ xml _ $Char(10)
			}
		} Catch {
			Set text = text _ "body not readable: " _ class _ $Char(10)
		}
	}
	Quit text
}

/// The highest id of the live events: the mark that the live-event scan reads from.
ClassMethod LiveMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(%ID) FROM OcuTalon_Live.Event")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// A fixture session of the prefix (zztg...) for StateBody; its events and counters are removed by DropSessions.
Method FixtureSession(prefix As %String) As OcuTalon.Data.Session [ Private ]
{
	Set session = ##class(OcuTalon.Data.Session).ForUser(prefix_$Increment(^OcuTalonTest("TelegramLive", "n")), .sc)
	Do $$$AssertStatusOK(sc, "the fixture session is made")
	Quit session
}

/// Deletes the fixture sessions (zztg...) with their events and counters, and the Turn, Delivery and SimMessage rows that name them.
ClassMethod DropSessions()
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zztg'")
	While result.%Next() {
		Set stream = result.%Get("Ref")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
		Kill ^OcuTalonP.LiveEventC(stream)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Turn WHERE SessionRef = ?", stream)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?", stream)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SimMessage WHERE SessionRef = ?", stream)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zztg'")
}

/// The ending of every test, on every path: the items stopped and their rows put back, the marks put back, the fixture chats deleted
/// and the mock reset.
Method Cleanup() [ Private ]
{
	Do $$$AssertStatusOK(..StopItems(), "the started items are stopped and their rows put back")
	Do ..RestoreMarks()
	Do ..DropChats(..ChatIds)
	Set ..ChatIds = ""
	Do ..DropSessions()
	Do ..Finish()
}

/// The calls of the mock with that method, in order, as a dynamic array.
ClassMethod CallsOf(method As %String) As %DynamicArray
{
	Set found = []
	Set iterator = ##class(OcuTalon.Test.Contract.Mock).Calls().%GetIterator()
	While iterator.%GetNext(, .call) {
		If call.method = method Do found.%Push(call)
	}
	Quit found
}

/// The calls with that method, once there are count of them or after seconds (whichever is first).
ClassMethod WaitCalls(method As %String, count As %Integer, seconds As %Numeric = 20) As %DynamicArray
{
	Set deadline = $ZHorolog + seconds
	For {
		Set found = ..CallsOf(method)
		If (found.%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit found
}

/// 1 when the kept offset becomes want within the seconds.
Method WaitOffset(want As %String, seconds As %Numeric = 20) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		If ##class(OcuTalon.Test.Channel.BotApi).Offset() = want Quit
		If $ZHorolog >= deadline Quit
		Hang 0.25
	}
	Quit ##class(OcuTalon.Test.Channel.BotApi).Offset() = want
}

/// 1 when the Telegram state becomes want (off, on or rejected) within the seconds.
ClassMethod WaitState(want As %String, seconds As %Numeric = 20) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	For {
		If ##class(OcuTalon.Data.StatusMark).TelegramState() = want Quit
		If $ZHorolog >= deadline Quit
		Hang 0.25
	}
	Quit ##class(OcuTalon.Data.StatusMark).TelegramState() = want
}

/// 1 when the mark has a value (present = 1) or has none (present = 0) within the seconds.
ClassMethod WaitMark(mark As %String, present As %Boolean, seconds As %Numeric = 20) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	For {
		If (##class(OcuTalon.Data.StatusMark).Get(mark) '= "") = present Quit
		If $ZHorolog >= deadline Quit
		Hang 0.25
	}
	Quit (##class(OcuTalon.Data.StatusMark).Get(mark) '= "") = present
}

/// StatusMonitor's item.
Parameter MONITOR = "StatusMonitor";

/// StatusMonitor's CallInterval in the production (seconds), plus a margin: its silent first run is over by then.
Parameter SETTLED = 17;

/// The longest, in seconds, to wait for the monitor's job to be old enough.
Parameter WAITMONITOR = 60;

/// The longest, in seconds, to wait for a status event (one call interval of the monitor and a margin).
Parameter WAITEVENT = 30;

/// Waits until StatusMonitor's job has run past its silent first run; 1 when it has.
ClassMethod WaitMonitor() As %Boolean
{
	Set deadline = $ZHorolog + ..#WAITMONITOR
	While ('..MonitorSettled()) && ($ZHorolog < deadline) {
		Hang 0.5
	}
	Quit ..MonitorSettled()
}

ClassMethod MonitorSettled() As %Boolean
{
	Set age = ..MonitorAge()
	Quit (age '= "") && (age >= ..#SETTLED)
}

/// The whole seconds since the newest job of the StatusMonitor item was registered, or "" when there is none (see
/// OcuTalon.Test.Schedule.StallFixture, whose private helper this follows).
ClassMethod MonitorAge() As %Numeric
{
	Set newest = ""
	Set job = ""
	For {
		Set job = $Order($$$EnsJobStatus($$$SystemName, job))
		If job = "" Quit
		If $Get($$$EnsJobStatus($$$SystemName, job, $$$eJobStartConfigName)) '= ..#MONITOR Continue
		Set registered = ##class(OcuTalon.Data.Time).Seconds($Translate($Extract($Get($$$EnsJobStatus($$$SystemName, job, $$$eJobRegTime)), 1, 19), " ", "T")_"Z")
		If registered = "" Continue
		If (newest = "") || (registered > newest) Set newest = registered
	}
	If newest = "" Quit ""
	Quit ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - newest
}

/// The Seq of the last event on the instance stream.
ClassMethod InstanceSeq() As %Integer
{
	Quit ##class(OcuTalon.Live.Publish).LastSeq(##class(OcuTalon.Live.Publish).#INSTANCE)
}

/// The telegramPaused status events of the instance stream after a Seq, in order.
ClassMethod Events(after As %Integer) As %DynamicArray
{
	Set found = []
	Set events = ##class(OcuTalon.Live.Event).Since(##class(OcuTalon.Live.Publish).#INSTANCE, after, 200, "instance")
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "status") && (event.payload.condition = "telegramPaused") Do found.%Push(event)
	}
	Quit found
}

/// The Seq of the first telegramPaused event after a Seq with that active, polled every 0.5 s for up to seconds; 0 when there is none.
ClassMethod WaitEvent(after As %Integer, active As %Boolean, seconds As %Numeric = {..#WAITEVENT}) As %Integer
{
	Set deadline = $ZHorolog + seconds
	For {
		Set events = ..Events(after)
		Set iterator = events.%GetIterator()
		While iterator.%GetNext(, .event) {
			If +event.payload.active = +active Return event.seq
		}
		If $ZHorolog >= deadline Quit
		Hang 0.5
	}
	Quit 0
}

/// 1 when the last telegramPaused event after a Seq is a clear, or there is none; it waits for the clear up to WAITEVENT seconds more than
/// a call interval of the monitor.
ClassMethod WaitClear(after As %Integer) As %Boolean
{
	Set deadline = $ZHorolog + ..#WAITEVENT + 15
	For {
		Set events = ..Events(after)
		If (events.%Size() = 0) || ('events.%Get(events.%Size() - 1).payload.active) Return 1
		If $ZHorolog >= deadline Quit
		Hang 0.5
	}
	Quit 0
}

/// The seconds since the start of Horolog day 0 of a UTC time stamp with milliseconds, such as the mock's ts (2026-10-31T10:00:00.123Z).
ClassMethod Epoch(stamp As %String) As %Numeric [ Private ]
{
	Set day = $ZDateH($Piece(stamp, "T", 1), 3)
	Set clock = $Piece($Piece(stamp, "T", 2), "Z", 1)
	Quit (day * 86400) + ($Piece(clock, ":", 1) * 3600) + ($Piece(clock, ":", 2) * 60) + $Piece(clock, ":", 3)
}

/// The current time in the scale of Epoch, to the millisecond.
ClassMethod EpochNow() As %Numeric
{
	Set now = $ZTimeStamp
	Quit ($Piece(now, ",", 1) * 86400) + $Piece(now, ",", 2)
}

/// Queues updates through the mock's /updates (a list of update objects); 1 when it answered 200.
Method QueueUpdates(updates As %DynamicArray) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Contract.Mock).Control("updates", updates)
}

/// A message update for the chat id: a private chat by default, with the text; first_name is the chat's name when it is not empty, and
/// then the update also has a from object whose names differ from it (TelegramIn reads the chat's name only).
ClassMethod PrivateMessage(chatId As %Integer, name As %String = "", text As %String = "zz private", type As %String = "private") As %DynamicObject
{
	Set chat = {"type": (type)}
	Do chat.%Set("id", +chatId, "number")
	If name = "" Quit {"message": {"chat": (chat), "text": (text)}}
	Do chat.%Set("first_name", name)
	Quit {"message": {"message_id": 1, "from": {"id": (+chatId), "first_name": "Zqfrom", "username": "zqfromuser"}, "chat": (chat), "text": (text)}}
}

/// The text of every sendMessage to the chat id, in order, as a dynamic array.
ClassMethod TextsTo(chatId As %Integer) As %DynamicArray
{
	Set texts = []
	Set iterator = ..CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		If call.params."chat_id" = chatId Do texts.%Push(call.params.text)
	}
	Quit texts
}

/// The bodies of the Pair commands (verb Pair, each as {"codeHash", "chatRef", "origin"}) or of the Unpair commands (verb Unpair, each as
/// {"sessionRef", "chatRef", "origin"}) of the message headers after the mark, one per body, in order.
ClassMethod PairBodies(mark As %Integer, verb As %String = "Pair") As %DynamicArray
{
	Set found = []
	Set seen = ""
	Set class = "OcuTalon.Msg.Command."_verb
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = ? ORDER BY ID", mark, class)
	While result.%Next() {
		Set id = result.%GetData(1)
		If $ListFind(seen, id) Continue
		Set seen = seen _ $ListBuild(id)
		Set body = $ClassMethod(class, "%OpenId", id)
		If '$IsObject(body) Continue
		If verb = "Pair" {
			Do found.%Push({"codeHash": (body.CodeHash), "chatRef": (body.ChatRef), "origin": (body.Origin)})
		} Else {
			Do found.%Push({"sessionRef": (body.SessionRef), "chatRef": (body.ChatRef), "origin": (body.Origin)})
		}
	}
	Quit found
}


/// The start of a test that pairs fixture chats (the ids, comma-separated): the live guard and the saved marks, the seam on, demo mode
/// checked, the fixture chats cleared, TelegramOut and TelegramIn enabled and a long poll open. It asserts nothing and returns "" when
/// all of it holds; otherwise the reason, after EndPairing has put back what was set.
Method BeginPairing(ids As %String) As %String
{
	Set reason = ..ReadyReason()
	If reason = "" Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason '= "" Quit reason
	Do ..SaveMarks()
	Set ..Sent = 0
	Set ..Sessions = ""
	Set ..Probe = ""
	Set ..WasIncluded = ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)
	Set ..Seam = 1
	If '##class(OcuTalon.Core.Rule.Functions).DemoOn() {
		Do ..EndPairing()
		Quit "demo mode is not on, and the guide of the pairing is read in demo mode"
	}
	Do ..Chat(ids)
	Do ..DropChats(ids)
	Set started = ..StartItems("TelegramOut,TelegramIn")
	If $$$ISERR(started) Set reason = "TelegramOut and TelegramIn are not enabled: "_..Cut($SYSTEM.Status.GetErrorText(started), ..Token)
	If (reason = "") && '..WaitState("on", 20) Set reason = "the Telegram state does not become on"
	If (reason = "") && (..WaitCalls("getUpdates", 1, 20).%Size() < 1) Set reason = "no long poll is open"
	If reason '= "" Do ..EndPairing()
	Quit reason
}

/// The end of a pairing-based test, on every path: the turns of the fixture sessions settled (a turn that is still running would save its
/// row after the delete), those turns and their Decision rows adopted and removed, Cleanup, then the probe row and the code rows of the
/// fixture sessions deleted, and the seam put back.
Method EndPairing()
{
	Set refs = ""
	Try {
		Set sessions = $ListToString(..Sessions)
		Do ..SettleTurns(sessions)
		Set refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(sessions, "")
	} Catch {
	}
	Do ..Cleanup()
	Try {
		If refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
		If ..Probe '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", ..Probe)
		For i = 1:1:$ListLength(..Sessions) {
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", $List(..Sessions, i))
		}
	} Catch {
	}
	Set ..Probe = ""
	Set ..Sessions = ""
	If ..Seam Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(..WasIncluded)
	Set ..Seam = 0
}

/// Waits, up to WAIT seconds more than a turn needs, until no Turn of the sessions (comma-separated Refs) is queued or running.
Method SettleTurns(sessions As %String) [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT + 30
	For {
		Set open = 0
		For i = 1:1:$Length(sessions, ",") {
			Set one = $Piece(sessions, ",", i)
			If one = "" Continue
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND State IN ('queued', 'running')", one)
			If result.%Next() Set open = open + result.%GetData(1)
		}
		If 'open || ($ZHorolog >= deadline) Quit
		Hang 0.5
	}
}

/// A fixture session of the prefix that watches nothing, and its Ref; its code row and turns are removed by EndPairing.
Method NewSession(prefix As %String = "zztgpair") As %String [ Private ]
{
	Set session = ..FixtureSession(prefix)
	Set ..Sessions = ..Sessions _ $ListBuild(session.Ref)
	Quit session.Ref
}

/// Stores a new code for the session as the web route does (its hash, valid for lifetime seconds, 600 by default; a negative lifetime
/// stores an expired code); the code is code and its hash is hash.
Method NewCode(session As %String, Output hash As %String, lifetime As %Integer = 600) As %String [ Private ]
{
	Set code = "zzpair"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Set expires = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), lifetime)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, hash, expires), "the session's code is stored as its hash")
	Quit code
}

/// Queues one update and counts it.
Method Send(update As %DynamicObject) [ Private ]
{
	Set batch = []
	Do batch.%Push(update)
	Do $$$AssertTrue(..QueueUpdates(batch), "an update is queued")
	Set ..Sent = ..Sent + 1
}

/// 1 when TelegramIn has handled every queued update.
Method Handled() As %Boolean [ Private ]
{
	Quit ..WaitOffset(..Sent + 1, 20)
}

/// The chat's row: 1 when there is one, with its Ref, SessionRef and DisplayName.
Method ChatRow(chatId As %String, Output ref As %String, Output sessionRef As %String, Output name As %String) As %Boolean [ Private ]
{
	Set ref = "", sessionRef = "", name = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Ref, SessionRef, DisplayName FROM OcuTalon_Data.Pairing WHERE ChatId = ? ORDER BY ID", chatId)
	If 'result.%Next() Quit 0
	Set ref = result.%GetData(1), sessionRef = result.%GetData(2), name = result.%GetData(3)
	Quit 1
}

/// 1 when the chat's row is linked to the session within WAIT seconds.
Method WaitLinked(chatId As %String, session As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT
	For {
		Do ..ChatRow(chatId, , .linked)
		If (linked = session) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit linked = session
}

/// Pairs the chat with the session by a new code, through the real /start path: 1 when the chat's row is linked to the session.
Method PairChat(chatId As %String, name As %String, session As %String) As %Boolean [ Private ]
{
	Set code = ..NewCode(session)
	Do ..Send(..PrivateMessage(chatId, name, "/start "_code))
	Do $$$AssertTrue(..Handled(), "TelegramIn handled the pairing of "_chatId)
	Set linked = ..WaitLinked(chatId, session)
	Do $$$AssertTrue(linked, "the chat "_chatId_" is paired with its session")
	Quit linked
}


/// The Items that TelegramIn sent to Conversation after the header mark, in order, each as {"itemId", "sessionRef", "channel",
/// "provenance", "text", "clientId", "fromGuide", "sessionId", "superSession", "xml"}: the body's fields, the header's SessionId and
/// SuperSession, and the body's exported XML.
Method Items(mark As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId, SessionId, SuperSession FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'TelegramIn' AND TargetConfigName = 'Conversation' AND MessageBodyClassName = 'OcuTalon.Msg.Item' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Msg.Item).%OpenId(result.%GetData(1))
		If '$IsObject(body) Continue
		Set xml = ""
		Do body.XMLExportToString(.xml)
		Do found.%Push({"itemId": (body.ItemId), "sessionRef": (body.SessionRef), "channel": (body.Channel), "provenance": (body.Provenance), "text": (body.Text), "clientId": (body.ClientId), "fromGuide": (+body.FromGuide), "sessionId": (result.%GetData(2)), "superSession": (result.%GetData(3)), "xml": (xml)})
	}
	Quit found
}

/// The Notification bodies that TelegramIn sent to Notify after the mark, in order, each as {"id", "kind", "catalogKey", "chatRef",
/// "sessionRef", "slots", "superSession", "sessionId"}: the body's fields and the header's SuperSession and SessionId.
Method Notifications(mark As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId, SuperSession, SessionId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'TelegramIn' AND TargetConfigName = 'Notify' AND MessageBodyClassName = 'OcuTalon.Msg.Notification' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Msg.Notification).%OpenId(result.%GetData(1))
		If $IsObject(body) Do found.%Push({"id": (body.%Id()), "kind": (body.Kind), "catalogKey": (body.CatalogKey), "chatRef": (body.ChatRef), "sessionRef": (body.SessionRef), "slots": (body.Slots), "superSession": (result.%GetData(2)), "sessionId": (result.%GetData(3))})
	}
	Quit found
}

/// The texts that the mock received for the chat: once there are count of them (or WAIT seconds pass), and 1 s more for any extra one.
Method TextsAfter(chatId As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT
	For {
		If (..TextsTo(chatId).%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Hang 1
	Quit ..TextsTo(chatId)
}

}
