/// Tests of the four verbs of step 3 and how CommandsIn routes them (Story 34.2; AD-1, AD-21, AD-29). Safe on a slot: no production runs, so
/// the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to OcuTalon.Test.Core.CommandsOwner and
/// records each call, or of OcuTalon.Test.Core.CommandsStep3Probe, which sends to the real stub owners. The origin rules and every text are
/// written out here, never read from CommandsIn.
///   - TestContracts: the four verb classes have exactly the properties of XData Contracts and share the Ens.MessageBody extent;
///   - TestOrigins: each verb by every origin of Msg.Enum ORIGIN, "zz" and "" included, reaches its owner (MemoryOps for the memory verbs,
///     DocumentOps for the document verbs) from its listed origin only, or is refused with its text, and a refusal sends nothing: SaveMemory and
///     ForgetMemory from tool, AddDocument and RemoveDocument from web_user;
///   - TestContextOwnSessionOnly: inside a bridge context a SaveMemory or ForgetMemory for a SessionRef that is not the context's OwnerRef is
///     not_allowed and nothing is sent, as for SendDigest (AD-1); the context's own session is routed, and a document verb that says web_user is
///     refused inside a context (the origin is tool there);
///   - TestRealStubOwners: the real OcuTalon.Docs.Ops answers its two verbs with "not implemented", which CommandsIn gives as not_built, and the
///     real OcuTalon.Memory.Ops (built in Story 19.3) answers its two as built, no_session for the session of the test, which has no row; each
///     received the very object CommandsIn was given, with its origin and SessionRef unchanged.
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

/// The four verb classes have exactly their contract and keep the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
	Set content = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Msg.Command.AddDocument||ContentType")
	Do $$$AssertEquals($Select($IsObject(content): content.Parameters.GetAt("VALUELIST"), 1: "(missing)"), ",markdown,text,pdf,docx", "ContentType is one of the four kinds")
	For verb = "SaveMemory", "ForgetMemory", "AddDocument", "RemoveDocument" {
		Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command."_verb, "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", verb_" is answered with a CommandResult")
	}
}

/// Each verb by every origin against the oracle: routed to the owner, or refused with its text and nothing sent.
Method TestOrigins()
{
	Set verbs = $ListBuild("SaveMemory", "ForgetMemory", "AddDocument", "RemoveDocument")
	Set origins = $ListFromString($Parameter("OcuTalon.Msg.Enum", "ORIGIN")) _ $ListBuild("zz", "")
	Do $$$AssertEquals($ListLength(origins), 8, "the six origins of Msg.Enum, 'zz' and ''")
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
	Do $$$AssertEquals(tried, 32, "all 32 pairs were tried")
}

/// Inside a bridge context a tool may save or forget a memory only for the context's own session (AD-1): a SessionRef that is not the
/// context's OwnerRef, an empty one included, is not_allowed with nothing sent, whatever origin the command says.
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
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Calls()
	Do probe.OnProcessInput(..NewCommand("SaveMemory", "tool", "zzsessB"), .output)
	Do $$$AssertEquals(output.Ok, 1, "once the context has ended a SaveMemory for B is routed")
	Do $$$AssertEquals(..Calls(), before + 1, "and sent")
}

/// The real stubs of Lane A answer the four verbs with code 5003, which CommandsIn gives as not_built, and receive the request unchanged.
Method TestRealStubOwners()
{
	Set verbs = $ListBuild("SaveMemory", "ForgetMemory", "AddDocument", "RemoveDocument")
	For v = 1:1:$ListLength(verbs) {
		Set verb = $List(verbs, v)
		Set origin = $Select(verb [ "Memory": "tool", 1: "web_user")
		Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsStep3Probe", .sc)
		Do $$$AssertStatusOK(sc, "a shadow instance of the stub probe is made")
		Set command = ..NewCommand(verb, origin, "zzsessA")
		Set sc = probe.OnProcessInput(command, .output)
		Do $$$AssertStatusOK(sc, verb_" is answered with a status that is OK")
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, $Select(verb [ "Memory": "0|no_session", 1: "0|not_built"), verb_": the real owner is a stub, so not_built, and MemoryOps is built, so no_session")
		Do $$$AssertEquals(output.Message, $Select(verb [ "Memory": $Parameter("OcuTalon.Memory.Ops", "MESSAGENOSESSION"), 1: "This part of OcuTalon isn't built yet. Nothing was changed."), verb_" says so")
		Do $$$AssertEquals(probe.SeenTarget, ..OwnerOf(verb), verb_" was sent to "_..OwnerOf(verb))
		Set same = (probe.LastRequest = command)
		Do $$$AssertEquals(same, 1, verb_": the owner got the very object CommandsIn was given")
		Do $$$AssertEquals(probe.LastRequest.Origin_"|"_probe.LastRequest.SessionRef, origin_"|zzsessA", verb_": with its origin and SessionRef unchanged")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Docs.Ops", "STUB"), 1, "DocumentOps is still a stub")
	Do $$$AssertEquals($Parameter("OcuTalon.Memory.Ops", "STUB"), "", "MemoryOps is built: it has no STUB")
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

/// The owner item of the verb, as this test's oracle has it.
ClassMethod OwnerOf(verb As %String) As %String [ Private ]
{
	Quit $Select(verb [ "Memory": "MemoryOps", 1: "DocumentOps")
}

/// The oracle of the origin rules: "" when the verb from the origin is routed, otherwise the text of its refusal.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	Set listed = $Select(verb [ "Memory": "tool", 1: "web_user")
	If origin = listed Quit ""
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
