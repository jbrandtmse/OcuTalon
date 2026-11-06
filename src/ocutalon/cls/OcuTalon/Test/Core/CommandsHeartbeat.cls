/// Tests of the two heartbeat verbs and how CommandsIn routes them (Story 39.2; AD-1, AD-14, AD-18). Safe on a slot: no production runs, so the
/// tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to OcuTalon.Test.Core.CommandsOwner and records
/// each call. The origin rules and every text are written out here, never read from CommandsIn.
///   - TestOrigins: SetHeartbeat and RunHeartbeat by every origin of Msg.Enum ORIGIN, "zz" and "" reach their owner (SettingsOps; Checks) from
///     web_user only, or are refused with their text, and a refusal sends nothing;
///   - TestToolRefused: each verb from origin tool, and from web_user inside a bridge context (the origin is tool there), is not_allowed with the
///     chat sentence and sends nothing (the governance test of AD-1);
///   - TestRunArrivesAsBeatNow: a RunHeartbeat reaches Checks as one OcuTalon.Checks.Msg.BeatNow with the command's SessionRef and a UTC
///     RequestedAt of now, and the owner's result is the answer as it is.
/// The run's calls are kept under ^OcuTalonTest("CommandsRouting", "heartbeat<n>") and deleted after the tests; the context of the test process is
/// ended before and after the tests.
Class OcuTalon.Test.Core.CommandsHeartbeat Extends %UnitTest.TestCase
{

/// The run's subscript.
Property Run As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Run = "heartbeat"_$Increment(^OcuTalonTest("CommandsHeartbeat", "n"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Quit $$$OK
}

/// Each verb by every origin against the oracle: routed to the owner from web_user only, or refused with its text and nothing sent.
Method TestOrigins()
{
	Set verbs = $ListBuild("SetHeartbeat", "RunHeartbeat")
	Set origins = $ListFromString($Parameter("OcuTalon.Msg.Enum", "ORIGIN")) _ $ListBuild("zz", "")
	Do $$$AssertEquals($ListLength(origins), 8, "the six origins of Msg.Enum, 'zz' and ''")
	Set tried = 0
	For v = 1:1:$ListLength(verbs) {
		For o = 1:1:$ListLength(origins) {
			Set verb = $List(verbs, v), origin = $List(origins, o)
			Set probe = ..NewProbe()
			Set tried = tried + 1
			Set sessionRef = "zzsess"_verb
			Set sc = probe.OnProcessInput(..NewCommand(verb, origin, sessionRef), .output)
			Set label = verb_" from '"_origin_"'"
			Do $$$AssertStatusOK(sc, label_" is answered with a status that is OK")
			If origin = "web_user" {
				Do $$$AssertEquals(..Calls(), 1, label_" is routed")
				Do $$$AssertEquals(..Call(1, "target"), $Select(verb = "SetHeartbeat": "SettingsOps", 1: "Checks"), label_" goes to its owner")
				Do $$$AssertEquals(..Call(1, "class"), $Select(verb = "SetHeartbeat": "OcuTalon.Msg.Command.SetHeartbeat", 1: "OcuTalon.Checks.Msg.BeatNow"), label_" arrives as its class")
				Do $$$AssertEquals(..Call(1, "sessionRef"), sessionRef, label_" arrives with its session unchanged")
				If verb = "SetHeartbeat" Do $$$AssertEquals(..Call(1, "origin"), origin, label_" arrives with its origin unchanged")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", label_": the owner's result is the answer")
			} Else {
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, $Select(origin = "tool": "That can't be done from the chat. Nothing was changed.", 1: "OcuTalon can't take that command from here. Nothing was changed."), label_" says why")
			}
		}
	}
	Do $$$AssertEquals(tried, 16, "all 16 pairs were tried")
}

/// A tool may not send either verb, and a web_user command inside a bridge context is a tool's: not_allowed with the chat sentence, nothing sent.
Method TestToolRefused()
{
	Set probe = ..NewProbe()
	For verb = "SetHeartbeat", "RunHeartbeat" {
		Set sent = ..Calls()
		Do probe.OnProcessInput(..NewCommand(verb, "tool", "zzsessA"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", verb_" from tool is not_allowed")
		Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", verb_" from tool says so")
		Do $$$AssertEquals(..Calls(), sent, verb_" from tool sends nothing")
	}
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		For verb = "SetHeartbeat", "RunHeartbeat" {
			For session = "zzsessA", "zzsessB", "" {
				Set sent = ..Calls()
				Do probe.OnProcessInput(..NewCommand(verb, "web_user", session), .output)
				Set label = verb_" for '"_session_"' saying web_user inside A's context"
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", label_" says so")
				Do $$$AssertEquals(..Calls(), sent, label_" sends nothing")
			}
		}
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set sent = ..Calls()
	Do probe.OnProcessInput(..NewCommand("RunHeartbeat", "web_user", "zzsessA"), .output)
	Do $$$AssertEquals(output.Ok_"|"_..Calls(), "1|"_(sent + 1), "once the context has ended the same command from web_user is routed")
}

/// A RunHeartbeat is sent to Checks as one BeatNow with the command's SessionRef and RequestedAt a UTC stamp of now, and the owner's result is the
/// answer as it is; the owner's other answers are CommandsIn's as for any verb.
Method TestRunArrivesAsBeatNow()
{
	Set probe = ..NewProbe()
	Set before = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Do probe.OnProcessInput(..NewCommand("RunHeartbeat", "web_user", "zzsessRun"), .output)
	Set after = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Calls(), 1, "one request is sent")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "class")_"|"_..Call(1, "sessionRef"), "Checks|OcuTalon.Checks.Msg.BeatNow|zzsessRun", "a BeatNow to Checks for the command's session")
	Set requestedAt = ..Call(1, "requestedAt")
	Do $$$AssertTrue(requestedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RequestedAt is a UTC stamp: "_requestedAt)
	Set at = ##class(OcuTalon.Data.Time).Seconds(requestedAt)
	Do $$$AssertTrue((at '< before) && (at '> after), "and it is the time of the send")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "1|test|Checks", "the owner's result is the answer as it is")
	Set last = probe.LastRequest
	Do $$$AssertEquals(last.%ClassName(1), "OcuTalon.Checks.Msg.BeatNow", "the very request that Checks got")
	For mode = "stub-op", "error", "none", "wrong" {
		Set probe = ..NewProbe(mode)
		Do probe.OnProcessInput(..NewCommand("RunHeartbeat", "web_user", "zzsessRun"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|"_$Case(mode, "stub-op": "not_built", : "failed"), "the owner's '"_mode_"' answer is CommandsIn's as for any verb")
	}
}

/// --- helpers ---
/// A shadow instance of the CommandsIn probe that answers with the mode.
Method NewProbe(mode As %String = "ok") As OcuTalon.Test.Core.CommandsInProbe [ Private ]
{
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Run
	Set probe.AnswerMode = mode
	Quit probe
}

/// A command of the verb with the origin and session.
Method NewCommand(verb As %String, origin As %String, sessionRef As %String) As OcuTalon.Msg.Command [ Private ]
{
	Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
	Set command.Origin = origin
	Set command.SessionRef = sessionRef
	Set command.IdempotencyKey = "zzkey"_..Run
	Quit command
}

/// The number of calls the owner has recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("CommandsRouting", ..Run))
}

/// One field of the owner's nth call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("CommandsRouting", ..Run, n, field))
}

}
