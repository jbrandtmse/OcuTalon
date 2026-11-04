/// Tests of how CommandsIn routes the three verbs of Story 33.2 (SendDigest, SaveSettings and GotIt; AD-1, AD-14, AD-19). Safe on a slot: no
/// production runs, so the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to
/// OcuTalon.Test.Core.CommandsOwner and records each call. The origin rules and every text are written out here, never read from CommandsIn.
///   - TestRoutesAndOrigins: each of the three verbs by every origin, "zz" and "" included, reaches its owner (Digest, SettingsOps, SessionOps) or
///     is refused with its text, and a refusal sends nothing;
///   - TestSaveSettingsFromToolRefused: a SaveSettings from a tool, also inside a bridge context while the command says web_admin, sends nothing;
///   - TestSendDigestFromEveryOrigin: SendDigest is sent from tool and web_admin, to Digest, and the owner's CommandResult is the answer;
///   - TestSendDigestTakesNoRecipient (U-268): the class's properties are exactly Msg.Command's, read from the class dictionary, and none is
///     named for a recipient, a channel or an address;
///   - TestSendDigestOwnSessionOnly (U-268): inside a bridge context a SessionRef that is not the context's OwnerRef is not_allowed and nothing
///     reaches the owner, and the context's own session is routed;
///   - TestGotItNotBuilt: SessionOps answers a GotIt with "not implemented" (code 5003), which CommandsIn gives as not_built.
/// The run's calls are kept under ^OcuTalonTest("CommandsRouting", "settings<n>") and deleted after the tests; the context of the test process is
/// ended before and after the tests.
Class OcuTalon.Test.Core.SettingsCommands Extends %UnitTest.TestCase
{

/// The run's subscript.
Property Run As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Run = "settings"_$Increment(^OcuTalonTest("SettingsCommands", "n"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Quit $$$OK
}

/// Each verb by every origin against the oracle: routed to the owner, or refused with its text and nothing sent.
Method TestRoutesAndOrigins()
{
	Set verbs = $ListBuild("SendDigest", "SaveSettings", "GotIt")
	Set origins = $ListBuild("web_user", "web_admin", "telegram", "tool", "timer", "system", "zz", "")
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
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", label_": the owner's result is the answer")
			} Else {
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, expected, label_" says why")
			}
		}
	}
	Do $$$AssertEquals(tried, 24, "all 24 pairs were tried")
}

/// SaveSettings from a tool sends nothing, also inside a bridge context while the command says web_admin.
Method TestSaveSettingsFromToolRefused()
{
	Set probe = ..NewProbe()
	Set command = ..NewCommand("SaveSettings", "tool", "zzsessA")
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "SaveSettings from a tool is not_allowed")
	Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", "with the text for a tool")
	Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context begins")
	Try {
		Set command = ..NewCommand("SaveSettings", "web_admin", "zzsessA")
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "SaveSettings that says web_admin is refused inside a context")
		Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// SendDigest from tool and from web_admin reaches Digest, and the owner's CommandResult comes back as the same object.
Method TestSendDigestFromEveryOrigin()
{
	For origin = "tool", "web_admin" {
		Set probe = ..NewProbe()
		Set command = ..NewCommand("SendDigest", origin, "zzsessA")
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(..Calls(), 1, origin_": sent once")
		Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "origin")_"|"_..Call(1, "sessionRef"), "Digest|"_origin_"|zzsessA", origin_": to Digest, with its origin and session unchanged")
		Set same = (output = probe.LastResponse)
		Do $$$AssertEquals(same, 1, origin_": the owner's CommandResult is the answer, as the same object")
	}
	Set probe = ..NewProbe("stub-op")
	Do probe.OnProcessInput(..NewCommand("SendDigest", "web_admin", "zzsessA"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_built", "a Digest that is still a stub answers not_built")
}

/// The class has the properties of Msg.Command and no other: no recipient, no channel, no address of any kind (U-268).
Method TestSendDigestTakesNoRecipient()
{
	Set own = ..PropertyNames("OcuTalon.Msg.Command.SendDigest")
	Set base = ..PropertyNames("OcuTalon.Msg.Command")
	Do $$$AssertTrue(base [ "SessionRef", "the base's properties are read: "_base)
	Do $$$AssertEquals(own, base, "SendDigest's properties are exactly those of Msg.Command")
	For i = 1:1:$Length(own, ",") {
		Set name = $Piece(own, ",", i)
		Do $$$AssertTrue('$Match(name, "(?i).*(recip|address|channel|email|mail|phone|chat|target|destination|dest|^to).*"), name_" does not name a destination")
	}
}

/// Inside a bridge context a tool may send SendDigest only for the context's own session (U-268): a SessionRef that is not the context's
/// OwnerRef, an empty one included, is not_allowed with nothing sent, whatever origin the command says.
Method TestSendDigestOwnSessionOnly()
{
	Set probe = ..NewProbe()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		For session = "zzsessB", "", "ZZSESSA" {
			For origin = "tool", "web_admin" {
				Do probe.OnProcessInput(..NewCommand("SendDigest", origin, session), .output)
				Set label = "SendDigest for '"_session_"' saying "_origin
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed inside A's context")
				Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", label_" says so")
				Do $$$AssertEquals(..Calls(), 0, label_" reaches no owner")
			}
		}
		Do probe.OnProcessInput(..NewCommand("SendDigest", "tool", "zzsessA"), .output)
		Do $$$AssertEquals(output.Ok, 1, "session A's own digest is routed inside its context")
		Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "sessionRef"), "Digest|zzsessA", "to Digest, for A")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Calls()
	Do probe.OnProcessInput(..NewCommand("SendDigest", "web_admin", "zzsessB"), .output)
	Do $$$AssertEquals(output.Ok, 1, "once the context has ended a web_admin SendDigest for B is routed")
	Do $$$AssertEquals(..Calls(), before + 1, "and sent")
}

/// SessionOps answers a GotIt with "not implemented" (code 5003) and no result, which CommandsIn gives as not_built (Story 18.4 builds it); the
/// owner's three real commands are still carried out by the class.
Method TestGotItNotBuilt()
{
	Set owner = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.SessionOps", .sc)
	Do $$$AssertStatusOK(sc, "SessionOps is made")
	Set command = ..NewCommand("GotIt", "web_user", "zzsessA")
	Set command.Ref = "zzdecision0123456789ab"
	Set command.Channel = "web"
	Set sc = owner.OnMessage(command, .response)
	Do $$$AssertStatusNotOK(sc, "the answer is an error status")
	Do $$$AssertTrue($ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003), "with the code of a stub, 5003: "_$SYSTEM.Status.GetErrorCodes(sc))
	Do $$$AssertEquals(response, "", "and no result")
	Set probe = ..NewProbe("stub-op")
	Do probe.OnProcessInput(..NewCommand("GotIt", "web_user", "zzsessA"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_built", "CommandsIn gives that answer as not_built")
	Do $$$AssertEquals(output.Message, "This part of OcuTalon isn't built yet. Nothing was changed.", "with its text")
}

/// --- helpers ---
/// The names of the compiled properties of the class, comma-separated in name order.
Method PropertyNames(class As %String) As %String [ Private ]
{
	Set names = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? ORDER BY Name", class)
	While result.%Next() {
		Set names = names_$Select(names = "": "", 1: ",")_result.%Get("Name")
	}
	Quit names
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
	Quit $Case(verb, "SendDigest": "Digest", "SaveSettings": "SettingsOps", : "SessionOps")
}

/// The oracle of the origin rules: "" when the verb from the origin is routed, otherwise the text of its refusal.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	If (origin = "tool") && (verb '= "SendDigest") Quit "That can't be done from the chat. Nothing was changed."
	If verb = "SendDigest" Quit $Select($ListFind($ListBuild("tool", "web_admin"), origin): "", 1: "OcuTalon can't take that command from here. Nothing was changed.")
	If verb = "SaveSettings" Quit $Select($ListFind($ListBuild("web_admin", "system"), origin): "", 1: "Only an OcuTalon admin can change settings. Nothing was changed.")
	Quit $Select($ListFind($ListBuild("web_user", "web_admin", "telegram"), origin): "", 1: "OcuTalon can't take that command from here. Nothing was changed.")
}

}
