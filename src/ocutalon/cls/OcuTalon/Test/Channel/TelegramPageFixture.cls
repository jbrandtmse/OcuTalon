/// The IRIS side of the page's real-pause browser test (Story 12.8; FR-22, AD-12, AD-14, AD-18, NFR-11): web/e2e/demo-path/telegram-page.spec.ts
/// calls it from IRIS scripts, one method per step, to drive the real TelegramIn against the CI mock and the production's own StatusMonitor.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it has no Test method, so it is no test class and joins no shard run.
/// It is built on the class methods of OcuTalon.Test.Channel.LiveCase, which it calls instead of copying.
///   - Start guards the stack, saves what Finish puts back and starts TelegramIn; Conflict queues the 409 and waits for the pause and for
///     StatusMonitor's onset; Resume stands in for the five minutes by moving the mark; Finish puts everything back.
///   - Each of those methods returns "" when it worked, or the reason it did not. No reason, and no value this class returns except Token,
///     holds the Bot API token: an exception's text has the token cut out.
///   - Finish is safe after any partial Start. It does nothing for a Start that was refused before it changed anything (saved is "").
///   - Token is the stack's dummy token, for the spec's search of the page and nothing else.
Class OcuTalon.Test.Channel.TelegramPageFixture Extends %RegisteredObject
{

/// The live-test helpers.
Parameter CASE = "OcuTalon.Test.Channel.LiveCase";

/// The item the page's pause comes from.
Parameter ITEM = "TelegramIn";

/// The pause mark.
Parameter MARK = "telegramPaused";

/// The longest, in seconds, to wait for TelegramIn to record that it is on.
Parameter WAITON = 20;

/// The longest, in seconds, to wait for a long poll to be open.
Parameter WAITPOLL = 20;

/// The longest, in seconds, to wait for the pause mark after the 409 is queued.
Parameter WAITMARK = 5;

/// The longest, in seconds, to wait for TelegramIn to delete the mark once its time has passed.
Parameter WAITRESUME = 20;

/// Starts TelegramIn against the mock. The guards come first: the Bot API base is the mock's, the token is set, no TelegramIn job is live
/// and the production runs. Then StatusMonitor must be past its silent first run and the mock's Bot API side is reset. saved is what
/// Finish needs: it is set before TelegramIn is enabled, and again once its Enabled row is known. Returns "" once the Telegram state is on.
ClassMethod Start(Output saved As %String) As %String
{
	Set saved = ""
	Set rows = ""
	Set marks = ""
	Set since = 0
	Try {
		Set mock = "OcuTalon.Test.Contract.Mock"
		Set reason = $ClassMethod(mock, "TelegramMissingReason", $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMBASEVAR")), ..Token())
		If reason = "" Set reason = ##class(OcuTalon.Test.Channel.BotApi).PollerReason()
		If reason = "" Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
		If reason '= "" Return reason
		If '$ClassMethod(..#CASE, "WaitMonitor") Return "StatusMonitor's job is not past its silent first run"
		Set sc = ##class(OcuTalon.Test.Channel.BotApi).Reset()
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		Set marks = $ClassMethod(..#CASE, "Marks")
		Set since = $ClassMethod(..#CASE, "InstanceSeq")
		Set saved = ..Pack(rows, marks, since)
		Set sc = $ClassMethod(..#CASE, "Enable", ..#ITEM, .rows)
		Set saved = ..Pack(rows, marks, since)
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitState", "on", ..#WAITON) Return ..#ITEM_" did not record the state on within "_..#WAITON_" s"
	} Catch ex {
		If marks '= "" Set saved = ..Pack(rows, marks, since)
		Return "Start failed: "_..Safe(ex)
	}
	Quit ""
}

/// Queues the 409 while a long poll is open and waits for the pause: until is the mark (a UTC time) and onset is the Seq of StatusMonitor's
/// onset event on the instance stream. Returns "" when both came.
ClassMethod Conflict(Output until As %String, Output onset As %Integer) As %String
{
	Set until = ""
	Set onset = 0
	Try {
		Set since = $ClassMethod(..#CASE, "InstanceSeq")
		If $ClassMethod(..#CASE, "WaitCalls", "getUpdates", 1, ..#WAITPOLL).%Size() < 1 Return "no long poll is open within "_..#WAITPOLL_" s"
		If '##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}) Return "the mock did not accept the telegram-conflict scenario"
		If '$ClassMethod(..#CASE, "WaitMark", ..#MARK, 1, ..#WAITMARK) Return "the pause mark is not set within "_..#WAITMARK_" s of the 409"
		Set until = ##class(OcuTalon.Data.StatusMark).Get(..#MARK)
		Set onset = $ClassMethod(..#CASE, "WaitEvent", since, 1)
		If 'onset Return "StatusMonitor published no onset of the pause"
	} Catch ex {
		Return "Conflict failed: "_..Safe(ex)
	}
	Quit ""
}

/// Stands in for the elapsed pause: the mark is moved to seconds ahead, TelegramIn's first 200 deletes it, and clear is the Seq of
/// StatusMonitor's clear event after onset. Returns "" when both happened.
ClassMethod Resume(seconds As %Numeric, onset As %Integer, Output clear As %Integer) As %String
{
	Set clear = 0
	Try {
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
		Set sc = ##class(OcuTalon.Data.StatusMark).Record(..#MARK, until)
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitMark", ..#MARK, 0, ..#WAITRESUME) Return "TelegramIn did not delete the pause mark within "_..#WAITRESUME_" s"
		Set clear = $ClassMethod(..#CASE, "WaitEvent", onset, 0)
		If 'clear Return "StatusMonitor published no clear of the pause"
	} Catch ex {
		Return "Resume failed: "_..Safe(ex)
	}
	Quit ""
}

/// Puts back what Start saved, after any partial Start: TelegramIn is disabled and has no job, its Enabled row and the two Telegram marks
/// are as they were (the marks are read back and compared), the mock's Bot API side is reset (after the item has no job, as BotApi.Reset
/// requires), and StatusMonitor has published the clear of any pause. Returns "" or the first reason something was not put back.
ClassMethod Finish(saved As %String) As %String
{
	If saved = "" Quit ""
	Set first = ""
	Try {
		Set list = $ZConvert($SYSTEM.Encryption.Base64Decode(saved), "I", "UTF8")
		Set rows = $List(list, 1)
		Set marks = $List(list, 2)
		Set since = $List(list, 3)
		If rows '= "" {
			Set sc = $ClassMethod(..#CASE, "Disable", ..#ITEM, rows)
			If $$$ISERR(sc) Set first = $SYSTEM.Status.GetErrorText(sc)
		}
		Do $ClassMethod(..#CASE, "PutMarks", marks)
		If ($ClassMethod(..#CASE, "Marks") '= marks) && (first = "") Set first = "the two Telegram marks are not as Start found them"
		Set sc = ##class(OcuTalon.Test.Channel.BotApi).Reset()
		If $$$ISERR(sc) && (first = "") Set first = $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitClear", since) && (first = "") Set first = "StatusMonitor published no clear of the pause"
	} Catch ex {
		If first = "" Set first = "Finish failed: "_..Safe(ex)
	}
	Quit first
}

/// The Bot API token of this stack (the CI dummy), read from the environment (AD-19). For the spec's search of the page only.
ClassMethod Token() As %String
{
	Quit $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
}

/// What Finish needs, as one line of base64 without line breaks: the UTF-8 of $ListBuild(rows, marks, since).
ClassMethod Pack(rows As %List, marks As %List, since As %Integer) As %String [ Private ]
{
	Quit $SYSTEM.Encryption.Base64Encode($ZConvert($ListBuild(rows, marks, since), "O", "UTF8"), 1)
}

/// The text of an exception, in one line, with the token cut out (LiveCase.Cut).
ClassMethod Safe(ex As %Exception.AbstractException) As %String [ Private ]
{
	Quit $ClassMethod(..#CASE, "Cut", ex.DisplayString(), ..Token())
}

}
