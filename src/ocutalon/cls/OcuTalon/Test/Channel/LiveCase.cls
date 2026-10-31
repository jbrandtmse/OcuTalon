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
///     that every test ends with the one call on every path.
///   - The wait helpers poll for the offset, the Telegram state, a mark and the mock's calls.
///   - WaitMonitor, InstanceSeq, Events, WaitEvent and WaitClear read the telegramPaused status events that the production's own
///     StatusMonitor publishes on the instance stream (the pattern of OcuTalon.Test.Schedule.Stalled): the monitor's silent first run must be
///     over, and a test that caused a pause waits for its clear, so that no event of it lands in a later test's window.
///   - The helpers that keep no state of the test are public class methods (BaseReason, WaitJobs, CallsOf, WaitCalls, WaitState, WaitMark,
///     WaitMonitor, MonitorSettled, MonitorAge, InstanceSeq, Events, WaitEvent, WaitClear, EpochNow), and so are Enable, Disable, Marks and
///     PutMarks, which hold the bodies of StartItems, StopItems, SaveMarks and RestoreMarks. The second user of them is
///     OcuTalon.Test.Channel.TelegramPageFixture (Story 12.8), which the page's browser test calls from an IRIS script.
Class OcuTalon.Test.Channel.LiveCase Extends %UnitTest.TestCase [ Abstract ]
{

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter BOTAPI = "OcuTalon.Test.Channel.BotApi";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The longest, in seconds, that StartItems and StopItems wait for the jobs of an item.
Parameter WAITJOB = 30;

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

/// 1 when the test may send: the stack is a throwaway, no poller has a live job, and the reset worked.
Method Ready() As %Boolean [ Private ]
{
	Set ..Token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
	Set reason = ##class(OcuTalon.Test.Contract.Mock).TelegramMissingReason($SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASEVAR), ..Token)
	If reason = "" Set reason = ##class(OcuTalon.Test.Channel.BotApi).PollerReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Set status = ##class(OcuTalon.Test.Channel.BotApi).Reset()
	Do $$$AssertStatusOK(status, "the mock's Bot API side is reset before the test")
	Quit $$$ISOK(status)
}

/// Ends a test: the reset again, whatever happened.
Method Finish() [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Channel.BotApi).Reset(), "the mock's Bot API side is reset after the test")
}

/// The text of an exception with the token cut out.
Method Safe(ex As %Exception.AbstractException) As %String [ Private ]
{
	Set text = $Translate(ex.DisplayString(), $Char(13, 10), "  ")
	If ..Token '= "" Set text = $Replace(text, ..Token, "[token]")
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
ClassMethod HeaderMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of message headers after the mark whose source item is the item.
ClassMethod HeadersFrom(mark As %Integer, item As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = ?", mark, item)
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

/// Deletes the fixture sessions (zztg...) with their events and counters.
ClassMethod DropSessions() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zztg'")
	While result.%Next() {
		Set stream = result.%Get("Ref")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
		Kill ^OcuTalonP.LiveEventC(stream)
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

/// A private-chat message update for the chat id.
ClassMethod PrivateMessage(chatId As %Integer) As %DynamicObject [ Private ]
{
	Quit {"message": {"chat": {"id": (chatId), "type": "private"}, "text": "zz private"}}
}

}
