/// End-to-end tests of the command gate over the running production (Story 2.3; AD-1, AD-22, AD-26). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where the
/// production does not run, every test fails with that reason, so that a broken start can never give a green shard. Every
/// test goes through OcuTalon.Core.Commands.Submit, to the two stub owners (ReminderOps and SessionOps), to the built SettingsOps,
/// and to IncidentManager, which Story 5.5 built. Each owner's story rewrites its row here when it builds the owner.
///   - TestStubOwnersAnswerPlainEnglish: a command to each stub owner gives status OK and a CommandResult with Ok 0, not_built
///     and the plain-English text;
///   - TestSettingsOpsSwitches: a SetDemoMode from the system, with the mode the stack already has, is carried out by the real
///     SettingsOps (the Demo step reruns, changing nothing), which writes the row, with the text of its mode, and its answer is
///     one response header that is not an error; the demo.mode row is put back after it;
///   - TestTraceAndThread: outside a turn the command and the owner's answer are messages of one session whose SuperSession is
///     the session's TraceRef; inside a turn they join the thread of the context's ThreadSessionId. A stub owner's answer is
///     one response header (type 2, IsError 1) from the owner to CommandsIn, which carries the owner's error status;
///   - TestGovernanceRefusedFromTool: inside a context the governance verbs are refused and no header goes to SettingsOps or
///     SessionOps;
///   - TestToolDismissReachesIncidentManager: inside a context, the Dismiss of the session's own noticed incident reaches
///     IncidentManager and closes it (Ok 1, closed), and the Dismiss of another session's incident is not_found with no header.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("CommandsInProduction","n")) and the clean-up are those
/// of Test.Core.InProduction; the SuperSessions of the tests' contexts are added to the run's, so that the clean-up removes
/// their messages too.
Class OcuTalon.Test.Core.CommandsInProduction Extends OcuTalon.Test.Core.InProduction
{

/// The text of a stub owner's answer.
Parameter NOTBUILT = "This part of OcuTalon isn't built yet. Nothing was changed.";

/// Each stub owner gets one verb with an origin it accepts: ReminderOps (SetReminder) and SessionOps (EndSession). Each
/// answers with status OK and a CommandResult that carries nothing out, in plain English.
Method TestStubOwnersAnswerPlainEnglish()
{
	If '..Guard() Quit
	Set a = ..Session("stubs")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set table = $ListBuild("SetReminder|ReminderOps|web_user", "EndSession|SessionOps|web_user")
	For i = 1:1:$ListLength(table) {
		Set verb = $Piece($List(table, i), "|", 1)
		Set owner = $Piece($List(table, i), "|", 2)
		Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
		Set command.SessionRef = a
		Set command.IdempotencyKey = "zzkey"_..Number_verb
		Set before = ..Sent(owner)
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, $Piece($List(table, i), "|", 3), .result)
		Do $$$AssertStatusOK(sc, verb_" to "_owner_": the status is OK")
		If '$IsObject(result) {
			Do $$$AssertTrue(0, verb_" to "_owner_": a CommandResult comes back, not '"_$Get(result)_"'")
			Continue
		}
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_built", verb_" to "_owner_": nothing was carried out, the owner is not built")
		Do $$$AssertEquals(result.Message, ..#NOTBUILT, verb_" to "_owner_": and the text is plain English")
		Do $$$AssertEquals(..Sent(owner), before + 1, verb_" to "_owner_": the command reached the owner")
		Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 2, owner, "CommandsIn")
		Do $$$AssertEquals(answers.%Size(), 1, verb_" to "_owner_": the owner's answer is a response header to CommandsIn")
		If answers.%Size() = 1 Do $$$AssertEquals(answers.%Get(0).isError, 1, verb_" to "_owner_": that carries the owner's error")
	}
}

/// A SetDemoMode from the system, with the mode the stack already has, reaches the real SettingsOps once: it is carried out
/// (Ok 1, on or off with the text of that mode), the job writes the row (the same mode, and an UpdatedAt that moves from the
/// test's dated-back one), and the owner's answer is one response header to CommandsIn that is not an error. The Demo step
/// reruns in the SettingsOps job and changes nothing. The demo.mode row is saved first and put back after the switch
/// (Test.Demo.Step); without a row (the Demo step seeds it at the first start) the test fails and switches nothing.
Method TestSettingsOpsSwitches()
{
	If '..Guard() Quit
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	If 'found {
		Do $$$AssertTrue(0, "the stack has a demo.mode row (the Demo step seeds it at the first start)")
		Quit
	}
	Set a = ..Session("settings")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set mode = (value = "1")
	Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
	Set command.SessionRef = a
	Set command.IdempotencyKey = "zzkey"_..Number_"SetDemoMode"
	Set command.DemoMode = mode
	Set command.ActingUser = $USERNAME
	Set before = ..Sent("SettingsOps")
	Do ##class(OcuTalon.Test.Demo.Step).Put(value, "2000-01-01T00:00:00Z")
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "system", .result)
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Set written = $Select($IsObject(row): row.Value_"|"_(row.UpdatedAt '= "2000-01-01T00:00:00Z"), 1: "<none>")
	Kill row
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(found, value, updatedAt)
	Do $$$AssertEquals(written, $Select(mode: "1", 1: "0")_"|1", "the SettingsOps job wrote the row with the same mode")
	Do $$$AssertStatusOK(sc, "SetDemoMode to SettingsOps: the status is OK")
	If '$IsObject(result) {
		Do $$$AssertTrue(0, "SetDemoMode to SettingsOps: a CommandResult comes back, not '"_$Get(result)_"'")
		Quit
	}
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|"_$Select(mode: "on", 1: "off"), "SetDemoMode to SettingsOps: carried out")
	Do $$$AssertEquals(result.Message, $Select(mode: "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change.", 1: "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change."), "and the text is that of the mode")
	Do $$$AssertEquals(..Sent("SettingsOps"), before + 1, "the command reached SettingsOps once")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 2, "SettingsOps", "CommandsIn")
	Do $$$AssertEquals(answers.%Size(), 1, "the answer is one response header to CommandsIn")
	If answers.%Size() = 1 Do $$$AssertEquals(answers.%Get(0).isError, 0, "that is not an error")
}

/// A ListReminders from web_user for session A has one request header from CommandsIn to ReminderOps in a session of its own
/// whose SuperSession is A's TraceRef, and its body is the command with the submitted key; the owner's answer is one response
/// header back to CommandsIn in that session. Then, in a context of session A
/// whose ThreadSessionId is that session and whose SuperSession is A's TraceRef, a second ListReminders has its request
/// header, and the owner's response header, in the same session.
Method TestTraceAndThread()
{
	If '..Guard() Quit
	Set a = ..Session("trace")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.SessionRef = a
	Set command.IdempotencyKey = "zzkey"_..Number_"first"
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	Do $$$AssertStatusOK(sc, "the command is submitted")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "CommandsIn", "ReminderOps")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 2, "ReminderOps", "CommandsIn")
	Do $$$AssertEquals(requests.%Size(), 1, "one request header goes from CommandsIn to ReminderOps")
	Do $$$AssertEquals(answers.%Size(), 1, "and the owner's answer is one response header back to CommandsIn")
	If (requests.%Size() '= 1) || (answers.%Size() '= 1) Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.superSession, trace, "its SuperSession is the session's TraceRef")
	Do $$$AssertEquals(request.bodyClass, "OcuTalon.Msg.Command.ListReminders", "its body is the command")
	Set body = ##class(OcuTalon.Msg.Command.ListReminders).%OpenId(request.bodyId)
	Do $$$AssertTrue($IsObject(body) && (body.IdempotencyKey = ("zzkey"_..Number_"first")), "with the submitted key")
	Set thread = request.sessionId
	Do $$$AssertEquals(thread, request.id, "it has a session of its own, which starts at its request header")
	Do $$$AssertEquals(answers.%Get(0).sessionId, thread, "the answer is in the same session")
	Do $$$AssertEquals(answers.%Get(0).superSession, trace, "with the same SuperSession")

	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = a
	Set begin.ThreadSessionId = thread
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(begin, trace), "a context in that thread begins")
	Try {
		Set second = ##class(OcuTalon.Msg.Command.ListReminders).%New()
		Set second.SessionRef = a
		Set second.IdempotencyKey = "zzkey"_..Number_"second"
		Set sc = ##class(OcuTalon.Core.Commands).Submit(second, "web_user", .result)
		Do $$$AssertStatusOK(sc, "the second command is submitted inside the context")
	} Catch exception {
		Do $$$AssertTrue(0, "Submit inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "CommandsIn", "ReminderOps")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 2, "ReminderOps", "CommandsIn")
	Do $$$AssertEquals(requests.%Size(), 2, "two request headers go from CommandsIn to ReminderOps")
	Do $$$AssertEquals(answers.%Size(), 2, "and two responses come back")
	If (requests.%Size() '= 2) || (answers.%Size() '= 2) Quit
	Do $$$AssertEquals(requests.%Get(1).sessionId, thread, "the second is in the same session as the first")
	Do $$$AssertEquals(requests.%Get(1).superSession, trace, "with the same SuperSession")
	Do $$$AssertEquals(answers.%Get(1).sessionId, thread, "and so is its answer")
}

/// Inside a context the governance verbs are refused through Submit: each gives not_allowed, no header goes from CommandsIn to
/// SettingsOps or SessionOps, and the demo mode is as it was.
Method TestGovernanceRefusedFromTool()
{
	If '..Guard() Quit
	Set a = ..Session("governance")
	Set mode = ..Mode()
	Set settings = ..Sent("SettingsOps")
	Set sessions = ..Sent("SessionOps")
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = a
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(begin, "zzss"_..Number), "a context begins")
	Do ..Supers.%Push("zzss"_..Number)
	Try {
		For verb = "SetDemoMode", "Pair", "Unpair", "EndSession" {
			Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
			Set command.SessionRef = a
			Set command.IdempotencyKey = "zzkey"_..Number_verb
			If verb = "SetDemoMode" Set command.DemoMode = '(mode = "1")
			Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "system", .result)
			Do $$$AssertStatusOK(sc, verb_": the status is OK")
			If '$IsObject(result) {
				Do $$$AssertTrue(0, verb_": a CommandResult comes back")
				Continue
			}
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", verb_" from a tool is not_allowed")
			Do $$$AssertEquals(result.Message, "That can't be done from the chat. Nothing was changed.", verb_" from a tool: and the text says it can't be done from the chat")
		}
	} Catch exception {
		Do $$$AssertTrue(0, "Submit inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(..Sent("SettingsOps"), settings, "no header went to SettingsOps")
	Do $$$AssertEquals(..Sent("SessionOps"), sessions, "no header went to SessionOps")
	Do $$$AssertEquals(..Mode(), mode, "and demo.mode is as it was")
}

/// Inside a context, the Dismiss of session A's own noticed incident reaches IncidentManager, which closes it (Story 5.5);
/// the Dismiss of session B's incident is not_found, and no header goes to IncidentManager.
Method TestToolDismissReachesIncidentManager()
{
	If '..Guard() Quit
	Set a = ..Session("dismissa")
	Set b = ..Session("dismissb")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Incident(a)
	Set other = ##class(OcuTalon.Test.Data.Fixture).Incident(b)
	Set ..Refs = ..Refs_","_own_","_other
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = a
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(begin, "zzss"_..Number), "a context begins")
	Do ..Supers.%Push("zzss"_..Number)
	Try {
		Set before = ..Sent("IncidentManager")
		Set sc = ##class(OcuTalon.Core.Commands).Submit(..Dismissal(a, own), "web_user", .result)
		Do $$$AssertStatusOK(sc, "the Dismiss of the session's own incident is submitted")
		Do $$$AssertEquals($IsObject(result) && (result.Ok_"|"_result.Outcome = "1|closed"), 1, "it reached IncidentManager, which closed the incident")
		Do $$$AssertEquals(..Sent("IncidentManager"), before + 1, "and a header went to IncidentManager")
		Set sc = ##class(OcuTalon.Core.Commands).Submit(..Dismissal(a, other), "web_user", .result)
		Do $$$AssertStatusOK(sc, "the Dismiss of another session's incident is submitted")
		Do $$$AssertEquals($IsObject(result) && (result.Ok_"|"_result.Outcome = "0|not_found"), 1, "it is not_found")
		Do $$$AssertEquals(..Sent("IncidentManager"), before + 1, "and no header went to IncidentManager")
	} Catch exception {
		Do $$$AssertTrue(0, "Submit inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// --- helpers ---
/// A Dismiss of the incident for the session.
Method Dismissal(sessionRef As %String, incidentRef As %String) As OcuTalon.Msg.Command.Dismiss [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Dismiss).%New()
	Set command.SessionRef = sessionRef
	Set command.IncidentRef = incidentRef
	Set command.IdempotencyKey = "zzkey"_..Number_"d"_incidentRef
	Quit command
}

/// The demo mode as its Setting row holds it now, read past the per-process cache of Setting.Get, so that a change made by
/// another job shows at once; "" when there is no row.
ClassMethod Mode() As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("demo.mode")
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The number of request headers from CommandsIn to the owner item, whatever their session.
ClassMethod Sent(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName = ? AND TargetConfigName = ? AND Type = 1", "CommandsIn", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
