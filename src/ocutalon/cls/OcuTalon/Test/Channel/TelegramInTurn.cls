Include Ensemble

/// Tests of the steps of a paired chat's turn in TelegramIn (Story 12.6; AD-14, AD-20, AD-26, AD-30). They need no production: the tests call
/// the service's Turn through OcuTalon.Test.Channel.TelegramInProbe, a subclass that records the allowance call, the send to Conversation, the
/// send to Notify and the give-back instead of making them. The real chain is the job of OcuTalon.Test.Channel.TelegramChat.
///   - TestFailedSendGivesTheEntryBack: a send that fails calls Refund once for the session, after the send, and logs LOGSEND once; a send that
///     works calls it never; the service's %SessionId and %SuperSession are "" again afterwards;
///   - TestThrownSendGivesTheEntryBack: a send that throws is a failed send: Refund once and LOGSEND once, and the service is clean;
///   - TestThrownRefundIsRaised: an exception in the turn (here the give-back's) is raised to the caller after the service's %SessionId,
///     %SuperSession and the job's session id are cleared, and after the session row's lock that Join kept is released;
///   - TestFirstTurnStartsTheThread: a day with no thread sends the Item in no session, and Trace.Started records the thread that the send gave
///     and releases the session row's lock; the job's session id is cleared after the turn; the next turn joins that thread; a send that fails
///     records no thread and releases the lock as well;
///   - TestFailedJoinStillSends: a join that fails (the session's row is gone) is logged as LOGJOIN once, and the Item is still sent, in no
///     session, with the session's TraceRef as its SuperSession;
///   - TestMissingSessionRowSendsNothing: a session with no row logs LOGNOSESSION once and asks and sends nothing;
///   - TestBusyAllowanceSendsNothing: an allowance refused with no retryAt logs LOGBUSYALLOWANCE once and sends nothing, not even a notice.
///   - TestRefusedNotice (QA): a refused message asks the allowance for channel telegram and the text as sent, and sends no Item; the first
///     refusal of a window sends one allowance Notification (no ChatRef) in no session of its own, under the session's TraceRef; a later one
///     sends none; a notice that fails to send is one LOGNOTICE warning; and the service's %SessionId and %SuperSession are "" again after
///     each of them, so that a later update of the same poll answer carries no session's TraceRef.
/// The fixture sessions (zztg...) come from Test.Data.Fixture and are removed by OnAfterAllTests. The run's number is n from
/// ^OcuTalonTest("TelegramInTurn","n") (never reset); the probe records under ^OcuTalonTest("TelegramInProbe", n), which OnAfterAllTests kills.
Class OcuTalon.Test.Channel.TelegramInTurn Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("TelegramInTurn", "n"))
	Set ..Refs = ""
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

/// A failed send gives the allowance entry back once, and a send that works gives nothing back.
Method TestFailedSendGivesTheEntryBack()
{
	Set session = ..Session("refund")
	Set probe = ..NewProbe()
	Set probe.FailSend = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do probe.Run(session, "zz send fails")
	Do $$$AssertEquals(..Targets(), "allowed|Conversation|refund", "the allowance is asked, the send fails and the entry is given back, in that order")
	Do $$$AssertEquals(..Call(3, "sessionRef"), session, "for the session")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGSEND), 1, "and the failed send is one warning")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service's %SessionId and %SuperSession are empty again")
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Do ..NewProbe().Run(session, "zz fine")
	Do $$$AssertEquals(..Targets(), "allowed|Conversation", "a send that works gives nothing back")
}

/// The first turn of a day sends its Item in no session and records the thread that the send gave; the next turn joins it.
Method TestFirstTurnStartsTheThread()
{
	Set session = ..Session("thread")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set probe = ..NewProbe()
	Set probe.NewSession = 5150
	Do probe.Run(session, "zz starts the thread")
	Do $$$AssertEquals(..Call(2, "sessionId")_"|"_..Call(2, "superSession"), "|"_trace, "the Item is sent in no session, under the session's TraceRef")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "5150|"_##class(OcuTalon.Core.Trace).Day(), "and the session it started is recorded for today")
	Do $$$AssertNotTrue(..Locked(session), "the session row's lock that Join kept is released")
	Do $$$AssertEquals($Get($$$JobSessionId), "", "and the job's session id is cleared, so that a later log row is not filed under the turn")
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 6160
	Do probe.Run(session, "zz joins it")
	Do $$$AssertEquals(..Call(2, "sessionId"), 5150, "the next turn is sent in that thread")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ThreadSessionId, 5150, "which stays the thread")

	Set other = ..Session("failedthread")
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.NewSession = 7170
	Set probe.FailSend = 1
	Do probe.Run(other, "zz send fails")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(other)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, "|", "a send that fails records no thread")
	Do $$$AssertNotTrue(..Locked(other), "and releases the session row's lock all the same")
}

/// A send that throws is a failed send: the entry is given back once and the failure is one warning.
Method TestThrownSendGivesTheEntryBack()
{
	Set session = ..Session("thrownsend")
	Set probe = ..NewProbe()
	Set probe.ThrowSend = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do probe.Run(session, "zz send throws")
	Do $$$AssertEquals(..Targets(), "allowed|Conversation|refund", "the allowance is asked, the send throws and the entry is given back")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGSEND), 1, "and the thrown send is one warning")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service's %SessionId and %SuperSession are empty again")
}

/// An exception in the turn is raised to the caller, after the service is clean and the session row's lock is released.
Method TestThrownRefundIsRaised()
{
	Set session = ..Session("thrownrefund")
	Set probe = ..NewProbe()
	Set probe.NewSession = 8180
	Set probe.FailSend = 1
	Set probe.ThrowRefund = 1
	Set thrown = ""
	Try {
		Do probe.Run(session, "zz refund throws")
	} Catch exception {
		Set thrown = exception.Name
	}
	Do $$$AssertEquals(thrown, "zz refund threw", "the exception reaches the caller")
	Do $$$AssertEquals(..Targets(), "allowed|Conversation|refund", "after the allowance, the send and the give-back")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service's %SessionId and %SuperSession are empty again")
	Do $$$AssertEquals($Get($$$JobSessionId), "", "and the job's session id is cleared")
	Do $$$AssertNotTrue(..Locked(session), "the session row's lock that Join kept is released")
}

/// A join that fails is one warning, and the turn goes on in a session of its own.
Method TestFailedJoinStillSends()
{
	Set session = ..Session("join")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set probe = ..NewProbe()
	Set probe.DropRow = 1
	Set probe.NewSession = 5150
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do probe.Run(session, "zz the join fails")
	Do $$$AssertEquals(..Targets(), "allowed|Conversation", "the Item is sent all the same")
	Do $$$AssertEquals(..Call(2, "sessionId")_"|"_..Call(2, "superSession"), "|"_trace, "in no session, under the session's TraceRef")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGJOIN), 1, "and the failed join is one warning")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGSTARTED), 0, "with no attempt to record a thread")
}

/// A session with no row is one warning, and nothing is asked or sent.
Method TestMissingSessionRowSendsNothing()
{
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..NewProbe().Run("zztgturn"_..Number_"none", "zz nobody")
	Do $$$AssertEquals(..Targets(), "", "the allowance is not asked and nothing is sent")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGNOSESSION), 1, "and the missing row is one warning")
}

/// An allowance that cannot be asked (no retryAt) is one warning, and nothing is sent: not the Item, not a notice.
Method TestBusyAllowanceSendsNothing()
{
	Set session = ..Session("busy")
	Set probe = ..NewProbe()
	Set probe.RefuseBusy = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do probe.Run(session, "zz busy")
	Do $$$AssertEquals(..Targets(), "allowed", "only the allowance is asked: no Item, no notice, no give-back")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGBUSYALLOWANCE), 1, "and the busy allowance is one warning")
}

/// A refused message sends the allowance notice once, in no session, under the session's TraceRef, and leaves the service clean.
Method TestRefusedNotice()
{
	Set session = ..Session("notice")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do $$$AssertTrue(trace '= "", "the session has a TraceRef")
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.FirstRefusal = 1
	Do probe.Run(session, "zz over the limit")
	Do $$$AssertEquals(..Targets(), "allowed|Notify", "the allowance is asked and the first refusal sends one Notification, and no Item")
	Do $$$AssertEquals(..Call(1, "channel")_"|"_..Call(1, "text"), "telegram|zz over the limit", "the allowance was asked for channel telegram and the text as sent")
	Do $$$AssertEquals(..Call(2, "sessionRef")_"|"_..Call(2, "kind")_"|"_..Call(2, "catalogKey")_"|"_..Call(2, "chatRef"), session_"|allowance|conversation.sessionAllowance|", "it is the session's allowance notice, with no ChatRef")
	Do $$$AssertEquals(..Call(2, "sessionId")_"|"_..Call(2, "superSession"), "|"_trace, "sent in no session of its own, under the session's TraceRef")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "the service's %SessionId and %SuperSession are empty again")

	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.FirstRefusal = 0
	Do probe.Run(session, "zz still over")
	Do $$$AssertEquals(..Targets(), "allowed", "a later refusal of the window sends nothing")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "and leaves the service clean")

	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.Refuse = 1
	Set probe.FailNotify = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do probe.Run(session, "zz notice fails")
	Do $$$AssertEquals(..Targets(), "allowed|Notify", "a notice that fails to send is not tried again")
	Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Channel.Telegram.In).#LOGNOTICE, "Notice"), 1, "and is one warning")
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "|", "with the service clean")
}

/// 1 when any process holds the lock of the session's row (the lock that Trace.Join keeps until Trace.Started), as the lock table shows it.
Method Locked(sessionRef As %String) As %Boolean [ Private ]
{
	If '##class(OcuTalon.Data.Session).RefIndexExists(sessionRef, .id) Quit 0
	Set held = 0
	Set name = ""
	For {
		Set name = $Order(^$LOCK(name))
		If name = "" Quit
		If name [ ("OcuTalonP.SessionD(" _ id _ ")") {
			Set held = 1
			Quit
		}
	}
	Quit held
}

/// A fixture session (zztg...); its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zztgturn"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe, in the run's records.
Method NewProbe() As OcuTalon.Test.Channel.TelegramInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.TelegramInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// The targets of the recorded calls in order, joined with "|".
Method Targets() As %String [ Private ]
{
	Set found = ""
	For n = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		Set found = found_$Select(found = "": "", 1: "|")_..Call(n, "target")
	}
	Quit found
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("TelegramInProbe", ..Number, n, field))
}

/// The warnings of the turn after the log mark that start with the text; they are removed from the log.
Method Warned(mark As %Integer, start As %String, method As %String = "Turn") As %Integer [ Private ]
{
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, method, start)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, method, start)
	Quit count
}

}
