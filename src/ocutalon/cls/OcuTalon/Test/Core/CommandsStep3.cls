/// Tests of the verbs of step 3 and how CommandsIn routes them (Story 34.2, PinMemory, UnpinMemory and SearchMemory from Story 41.9, ListPinnedMemories from Story 41.13; AD-1, AD-21, AD-29). Safe on a slot: no production runs, so
/// the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to OcuTalon.Test.Core.CommandsOwner and
/// records each call, or of OcuTalon.Test.Core.CommandsStep3Probe, which sends to the real stub owners. The origin rules and every text are
/// written out here, never read from CommandsIn.
///   - TestContracts: the eight verb classes have exactly the properties of XData Contracts and share the Ens.MessageBody extent;
///   - TestOrigins: each verb by every origin of Msg.Enum ORIGIN, "photo" (the origin of a photo caption, Story 26.3), "zz" and "" included, reaches its owner (MemoryOps for the memory verbs,
///     DocumentOps for the document verbs) from its listed origins only, or is refused with its text, and a refusal sends nothing: SaveMemory from tool and photo,
///     ForgetMemory from tool and web_user, PinMemory, UnpinMemory, SearchMemory, ListPinnedMemories, AddDocument and RemoveDocument from web_user;
///   - TestContextOwnSessionOnly: inside a bridge context a SaveMemory or ForgetMemory for a SessionRef that is not the context's OwnerRef is
///     not_allowed and nothing is sent, as for SendDigest (AD-1); the context's own session is routed, and a document verb, PinMemory, UnpinMemory, SearchMemory or ListPinnedMemories that says
///     web_user is refused inside a context (the origin is tool there, and none of them is a tool verb);
///   - TestSearchMemoryWaits (Story 41.9): a SearchMemory waits SEARCHTIMEOUT (20) seconds, and a send that gets no answer in time is answered Ok 0 Outcome busy; any other verb waits TIMEOUT (120)
///     and the same silence is failed; a SearchMemory that is answered in time gets the owner's answer as it is;
///   - TestListPinnedWaits and TestSearchAllowance (Story 41.13, DW-1031): a ListPinnedMemories waits SEARCHTIMEOUT as a search does; with onlineDemo 1, each SearchMemory counts against the message
///     allowance in CommandsIn: past the limit it answers Ok 0 allowance with Data {retryAt, limit}, sends nothing and records no Turn and no window; under it, it is sent and adds one entry;
///     ListPinnedMemories counts none; with the flag off nothing is counted; TestSearchAllowanceBusyLock: a busy row lock answers Ok 0 failed, sends nothing and counts nothing;
///   - TestRealStubOwners: the real OcuTalon.Docs.Ops (built in Story 19.4) and the real OcuTalon.Memory.Ops (built in Story 19.3; its pin handlers in Story 41.12) answer their verbs
///     as built, no_session for the session of the test, which has no row; each received the very object CommandsIn was given, with its origin and
///     SessionRef unchanged.
/// The run's calls are kept under ^OcuTalonTest("CommandsRouting", "step3<n>") and deleted after the tests; the context of the test process is
/// ended before and after the tests.
Class OcuTalon.Test.Core.CommandsStep3 Extends OcuTalon.Test.Contract
{

/// The run's subscript.
Property Run As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Run = "step3"_$Increment(^OcuTalonTest("CommandsStep3", "n"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Quit $$$OK
}

/// The eight verb classes have exactly their contract and keep the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
	Set content = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Msg.Command.AddDocument||ContentType")
	Do $$$AssertEquals($Select($IsObject(content): content.Parameters.GetAt("VALUELIST"), 1: "(missing)"), ",markdown,text,pdf,docx", "ContentType is one of the four kinds")
	For verb = "SaveMemory", "ForgetMemory", "PinMemory", "UnpinMemory", "SearchMemory", "ListPinnedMemories", "AddDocument", "RemoveDocument" {
		Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command."_verb, "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", verb_" is answered with a CommandResult")
	}
}

/// Each verb by every origin against the oracle: routed to the owner, or refused with its text and nothing sent.
Method TestOrigins()
{
	Set verbs = $ListBuild("SaveMemory", "ForgetMemory", "PinMemory", "UnpinMemory", "SearchMemory", "ListPinnedMemories", "AddDocument", "RemoveDocument")
	Set origins = $ListFromString($Parameter("OcuTalon.Msg.Enum", "ORIGIN")) _ $ListBuild("photo", "zz", "")
	Do $$$AssertEquals($ListLength(origins), 9, "the six origins of Msg.Enum, 'photo', 'zz' and ''")
	Set tried = 0
	For v = 1:1:$ListLength(verbs) {
		For o = 1:1:$ListLength(origins) {
			Set verb = $List(verbs, v), origin = $List(origins, o)
			Set probe = ..NewProbe()
			Set tried = tried + 1
			Set command = ..NewCommand(verb, origin, "zzsess"_verb)
			Set sc = probe.OnProcessInput(command, .output)
			Set label = verb_" from '"_origin_"'"
			Do $$$AssertStatusOK(sc, label_" is answered with a status that is OK")
			Set expected = ..Expected(verb, origin)
			If expected = "" {
				Do $$$AssertEquals(..Calls(), 1, label_" is routed")
				Do $$$AssertEquals(..Call(1, "target"), ..OwnerOf(verb), label_" goes to "_..OwnerOf(verb))
				Do $$$AssertEquals(..Call(1, "class"), "OcuTalon.Msg.Command."_verb, label_" arrives as its own class")
				Do $$$AssertEquals(..Call(1, "origin")_"|"_..Call(1, "sessionRef"), origin_"|zzsess"_verb, label_" arrives with its origin and session unchanged")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", label_": the owner's result is the answer")
			} Else {
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, expected, label_" says why")
			}
		}
	}
	Do $$$AssertEquals(tried, 72, "all 72 pairs were tried")
}

/// Inside a bridge context a tool may save or forget a memory only for the context's own session (AD-1): a SessionRef that is not the
/// context's OwnerRef, an empty one included, is not_allowed with nothing sent, whatever origin the command says. A PinMemory, UnpinMemory or SearchMemory
/// inside a context is not_allowed and nothing is sent, even for the context's own session, because none of them is a tool verb.
Method TestContextOwnSessionOnly()
{
	Set probe = ..NewProbe()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		For verb = "SaveMemory", "ForgetMemory" {
			Set sent = ..Calls()
			For session = "zzsessB", "", "ZZSESSA" {
				For origin = "tool", "web_user" {
					Do probe.OnProcessInput(..NewCommand(verb, origin, session), .output)
					Set label = verb_" for '"_session_"' saying "_origin
					Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed inside A's context")
					Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", label_" says so")
					Do $$$AssertEquals(..Calls(), sent, label_" reaches no owner")
				}
			}
			Do probe.OnProcessInput(..NewCommand(verb, "tool", "zzsessA"), .output)
			Do $$$AssertEquals(output.Ok, 1, verb_" for session A is routed inside its context")
			Do $$$AssertEquals(..Call(..Calls(), "target")_"|"_..Call(..Calls(), "origin")_"|"_..Call(..Calls(), "sessionRef"), "MemoryOps|tool|zzsessA", verb_" goes to MemoryOps, for A")
		}
		Set before = ..Calls()
		For verb = "AddDocument", "RemoveDocument" {
			Do probe.OnProcessInput(..NewCommand(verb, "web_user", "zzsessA"), .output)
			Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", verb_" that says web_user is a tool's inside a context, and refused")
		}
		Do $$$AssertEquals(..Calls(), before, "and nothing is sent")
		Set before = ..Calls()
		For verb = "PinMemory", "UnpinMemory", "SearchMemory", "ListPinnedMemories" {
			For origin = "tool", "web_user" {
				Do probe.OnProcessInput(..NewCommand(verb, origin, "zzsessA"), .output)
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" saying "_origin_" for A's own session is refused inside A's context")
			}
		}
		Do $$$AssertEquals(..Calls(), before, "and no pin or search is sent")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Calls()
	Do probe.OnProcessInput(..NewCommand("SaveMemory", "tool", "zzsessB"), .output)
	Do $$$AssertEquals(output.Ok, 1, "once the context has ended a SaveMemory for B is routed")
	Do $$$AssertEquals(..Calls(), before + 1, "and sent")
}

/// The real owners of Lane A (MemoryOps and DocumentOps) answer the verbs they handle (the memory verbs SaveMemory, ForgetMemory, PinMemory and UnpinMemory, and the two document verbs) as built, no_session for a session with no row, and receive the request unchanged.
Method TestRealStubOwners()
{
	Set verbs = $ListBuild("SaveMemory", "ForgetMemory", "PinMemory", "UnpinMemory", "AddDocument", "RemoveDocument")
	For v = 1:1:$ListLength(verbs) {
		Set verb = $List(verbs, v)
		Set origin = $Select((verb = "SaveMemory") || (verb = "ForgetMemory"): "tool", 1: "web_user")
		Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsStep3Probe", .sc)
		Do $$$AssertStatusOK(sc, "a shadow instance of the stub probe is made")
		Set command = ..NewCommand(verb, origin, "zzsessA")
		Set sc = probe.OnProcessInput(command, .output)
		Do $$$AssertStatusOK(sc, verb_" is answered with a status that is OK")
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|no_session", verb_": the real owner is built, so no_session for a session with no row")
		Do $$$AssertEquals(output.Message, $Select(verb [ "Memory": $Parameter("OcuTalon.Memory.Ops", "MESSAGENOSESSION"), 1: $Parameter("OcuTalon.Docs.Ops", "MESSAGENOSESSION")), verb_" says so")
		Do $$$AssertEquals(probe.SeenTarget, ..OwnerOf(verb), verb_" was sent to "_..OwnerOf(verb))
		Set same = (probe.LastRequest = command)
		Do $$$AssertEquals(same, 1, verb_": the owner got the very object CommandsIn was given")
		Do $$$AssertEquals(probe.LastRequest.Origin_"|"_probe.LastRequest.SessionRef, origin_"|zzsessA", verb_": with its origin and SessionRef unchanged")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Docs.Ops", "STUB"), "", "DocumentOps is built: it has no STUB")
	Do $$$AssertEquals($Parameter("OcuTalon.Memory.Ops", "STUB"), "", "MemoryOps is built: it has no STUB")
}

/// A SearchMemory waits SEARCHTIMEOUT (20) seconds for its owner, and a send that ends with no answer (the framework's OK status and no response) is answered Ok 0 with
/// Outcome busy, never failed (Story 41.9). Every other verb waits TIMEOUT (120) seconds and the same silence is failed. The probe stands in for the framework's synchronous
/// send and records the target, the request and the wait that the product asked for.
Method TestSearchMemoryWaits()
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the timeout probe is made")
	Set command = ..NewCommand("SearchMemory", "web_user", "zzsessA")
	Set command.Query = "vpn gateway"
	Set sc = probe.OnProcessInput(command, .output)
	Do $$$AssertStatusOK(sc, "the gate answers with a status that is OK")
	Do $$$AssertEquals(probe.Sends, 1, "one send was made")
	Do $$$AssertEquals(probe.SeenTarget, "MemoryOps", "to MemoryOps")
	Do $$$AssertEquals(probe.SeenTimeout, 20, "a search waits 20 seconds")
	Set same = (probe.SeenRequest = command)
	Do $$$AssertEquals(same, 1, "with the very object the gate was given")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|busy", "no answer in time is Ok 0, busy")
	Do $$$AssertEquals(output.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", "with the gate's own sentence")
	Set other = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
	Set sc = other.OnProcessInput(..NewCommand("ForgetMemory", "web_user", "zzsessA"), .output)
	Do $$$AssertEquals(other.SeenTimeout, 120, "a forget waits 120 seconds")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", "and no answer from it is failed, not busy")
	Set answered = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
	Set reply = ##class(OcuTalon.Msg.CommandResult).%New()
	Set reply.Ok = 1, reply.Outcome = "done", reply.Data = "[]"
	Set answered.Answer = reply
	Set sc = answered.OnProcessInput(command, .output)
	Do $$$AssertEquals(answered.SeenTimeout, 20, "a search that is answered in time waited 20 seconds too")
	Do $$$AssertEquals($IsObject(output) && (output = reply), 1, "and its answer is the owner's, as it is")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Data, "1|done|[]", "Ok 1, done, with the items, never busy")
}

/// A ListPinnedMemories waits SEARCHTIMEOUT (20) seconds for its owner as a SearchMemory does, and a send that ends with no answer is answered Ok 0 Outcome busy (Story 41.13).
Method TestListPinnedWaits()
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the timeout probe is made")
	Set command = ..NewCommand("ListPinnedMemories", "web_user", "zzsessA")
	Set sc = probe.OnProcessInput(command, .output)
	Do $$$AssertStatusOK(sc, "the gate answers with a status that is OK")
	Do $$$AssertEquals(probe.Sends, 1, "one send was made")
	Do $$$AssertEquals(probe.SeenTarget, "MemoryOps", "to MemoryOps")
	Do $$$AssertEquals(probe.SeenTimeout, 20, "the pinned read waits 20 seconds")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|busy", "no answer in time is Ok 0, busy")
	Set answered = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsTimeoutProbe", .sc)
	Set reply = ##class(OcuTalon.Msg.CommandResult).%New()
	Set reply.Ok = 1, reply.Outcome = "done", reply.Data = "{}"
	Set answered.Answer = reply
	Set sc = answered.OnProcessInput(command, .output)
	Do $$$AssertEquals($IsObject(output) && (output = reply), 1, "an answer in time is the owner's, as it is")
}

/// On the online demo each SearchMemory counts as one of the session's messages in CommandsIn, through Allowance.TryConsumeRead (Story 41.13, DW-1031). With the limit at 3 and two entries
/// held, one search is sent and makes 3; the next answers Ok 0 allowance with Data {retryAt, limit} (the oldest entry plus 3600 seconds, and 3), sends nothing and records no Turn, no
/// window and no entry. A ListPinnedMemories never counts, and with the flag off a search counts nothing.
Method TestSearchAllowance()
{
	Set settings = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")_"|"_##class(OcuTalon.Data.Public.Settings).Get("messageAllowance")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsearchallowance"_..Run)
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", 3)
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set oldest = ##class(OcuTalon.Data.Time).AddSeconds(now, -1000)
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		Set row.AllowanceTimes = $ListBuild(oldest, ##class(OcuTalon.Data.Time).AddSeconds(now, -900))
		Do $$$AssertStatusOK(row.%Save(), "the session holds two entries")
		Set probe = ..NewProbe()
		Set command = ..NewCommand("SearchMemory", "web_user", ref)
		Set command.Query = "vpn"
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "a search under the limit is sent and answered by its owner")
		Do $$$AssertEquals(..Calls(), 1, "one send was made")
		Do $$$AssertEquals($ListLength(..Entries(ref)), 3, "and it added one entry")
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|allowance|", "the search at the limit answers Ok 0 allowance, with no message")
		Set data = {}.%FromJSON(output.Data)
		Do $$$AssertEquals(data.retryAt_"|"_data.%GetTypeOf("limit")_"|"_data.limit, ##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600)_"|number|3", "Data holds the oldest entry plus 3600 seconds and the limit 3")
		Do $$$AssertEquals(..Calls(), 1, "nothing was sent to the owner")
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
		Do row.%Reload()
		Do $$$AssertEquals($ListLength(row.AllowanceTimes)_"|"_row.AllowanceUntil, "3|", "no entry and no window were added")
		Do $$$AssertEquals(..TurnsOf(ref), 0, "and no Turn was recorded")
		Set list = ..NewCommand("ListPinnedMemories", "web_user", ref)
		Do probe.OnProcessInput(list, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "a ListPinnedMemories at the limit is sent")
		Do $$$AssertEquals(..Calls(), 2, "to its owner")
		Do $$$AssertEquals($ListLength(..Entries(ref)), 3, "and counts nothing")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "with the flag off the search is sent")
		Do $$$AssertEquals(..Calls(), 3, "to its owner")
		Do $$$AssertEquals($ListLength(..Entries(ref)), 3, "and counts nothing")
	} Catch exception {
		Do $$$AssertTrue(0, "the allowance test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Piece(settings, "|", 1))
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", $Piece(settings, "|", 2))
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(##class(OcuTalon.Test.Data.Fixture).AdoptTurns(ref, ref))
}

/// Story 41.13: a search whose allowance check cannot take the session row's lock (another job holds it) is not sent and not counted: CommandsIn answers Ok 0 failed.
Method TestSearchAllowanceBusyLock()
{
	Set settings = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsearchbusylock"_..Run)
	Set key = "busy"_..Run
	Set held = 0
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).%Id()
		Kill ^OcuTalonTest("Allowance", "job", key)
		Job ##class(OcuTalon.Test.Core.Allowance).Hold(id, key)
		Set deadline = $ZHorolog + 60
		While '$Get(^OcuTalonTest("Allowance", "job", key, "ready")) && ($ZHorolog < deadline) {
			Hang 0.05
		}
		Set held = $Get(^OcuTalonTest("Allowance", "job", key, "ready"))
		Do $$$AssertEquals(held, 1, "another job holds the row's lock")
		Set probe = ..NewProbe()
		Set command = ..NewCommand("SearchMemory", "web_user", ref)
		Set command.Query = "vpn"
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", "the search is refused as failed while the lock is busy")
		Do $$$AssertEquals(..Calls(), 0, "nothing was sent to the owner")
		Do $$$AssertEquals($ListLength(..Entries(ref)), 0, "and nothing was counted")
	} Catch exception {
		Do $$$AssertTrue(0, "the busy-lock test threw: "_exception.DisplayString())
	}
	If held {
		Set ^OcuTalonTest("Allowance", "job", key, "release") = 1
		Set deadline = $ZHorolog + 60
		While '$Get(^OcuTalonTest("Allowance", "job", key, "done")) && ($ZHorolog < deadline) {
			Hang 0.05
		}
	}
	Kill ^OcuTalonTest("Allowance", "job", key)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", settings)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(##class(OcuTalon.Test.Data.Fixture).AdoptTurns(ref, ref))
}

/// --- helpers ---
/// The AllowanceTimes of the session, read from disk.
Method Entries(ref As %String) As %List [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do row.%Reload()
	Quit row.AllowanceTimes
}

/// The number of Turns of the session.
Method TurnsOf(ref As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", ref)
	Quit $Select(rs.%Next(): +rs.%GetData(1), 1: 0)
}

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

/// The owner item of the verb, as this test's oracle has it.
ClassMethod OwnerOf(verb As %String) As %String [ Private ]
{
	Quit $Select(verb [ "Memor": "MemoryOps", 1: "DocumentOps")
}

/// The oracle of the origin rules: "" when the verb from the origin is routed, otherwise the text of its refusal.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	Set listed = $Case(verb, "SaveMemory": "tool,photo", "ForgetMemory": "tool,web_user", : "web_user")
	If $ListFind($ListFromString(listed), origin) Quit ""
	If origin = "tool" Quit "That can't be done from the chat. Nothing was changed."
	Quit "OcuTalon can't take that command from here. Nothing was changed."
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Msg.Command.SaveMemory": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Text": "%String(MAXLEN=2000)"
  }
 },
 "OcuTalon.Msg.Command.ForgetMemory": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "MemoryRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.PinMemory": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "MemoryRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.UnpinMemory": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "MemoryRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.SearchMemory": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Query": "%String(MAXLEN=2000)"
  }
 },
 "OcuTalon.Msg.Command.ListPinnedMemories": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.AddDocument": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Name": "%String(MAXLEN=255)",
   "ContentType": "%String(MAXLEN=16)",
   "UploadRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.RemoveDocument": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "DocumentRef": "%String(MAXLEN=22)"
  }
 }
}
}

}
