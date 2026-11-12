/// Tests of how CommandsIn routes the three verbs of Story 33.2 (SendDigest, SaveSettings and GotIt; AD-1, AD-14, AD-19), Story 18.3's TestModel and Story 21.3's
/// MailSignIn (AD-10; U-320 condition 3). Safe on a slot: no
/// production runs, so the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to
/// OcuTalon.Test.Core.CommandsOwner and records each call. The origin rules and every text are written out here, never read from CommandsIn.
///   - TestRoutesAndOrigins: each of the five verbs by every origin, "zz" and "" included, reaches its owner (Digest, SettingsOps, SessionOps) or
///     is refused with its text, and a refusal sends nothing (TestModel and MailSignIn are carried out for web_admin only);
///   - TestMailSignInNeverFromAnAgentTurn (AD-10): inside a bridge context of any provenance, tainted or not, of any kind, a MailSignIn of any origin (tool included) is
///     refused with nothing sent; outside a context only web_admin reaches SettingsOps, with the command unchanged;
///   - TestModelRefusedFromToolAndUser: a TestModel from a tool, from web_user and from the system sends nothing, with the texts of the refusals, also inside a bridge
///     context while the command says web_admin;
///   - TestSaveSettingsFromToolRefused: a SaveSettings from a tool, also inside a bridge context while the command says web_admin, sends nothing;
///   - TestSendDigestFromEveryOrigin: SendDigest is sent from tool and web_admin, to Digest, and the owner's CommandResult is the answer;
///   - TestSendDigestTakesNoRecipient (U-268): the class's properties are exactly Msg.Command's, read from the class dictionary, and none is
///     named for a recipient, a channel or an address;
///   - TestSendDigestOwnSessionOnly (U-268): inside a bridge context a SessionRef that is not the context's OwnerRef is not_allowed and nothing
///     reaches the owner, and the context's own session is routed;
///   - TestGotItBuilt: SessionOps carries out a GotIt, so a Ref that names no Decision is answered 0|not_found with status OK (not code 5003).
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
	Set verbs = $ListBuild("SendDigest", "SaveSettings", "GotIt", "TestModel", "MailSignIn")
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
	Do $$$AssertEquals(tried, 40, "all 40 pairs were tried")
}

/// AD-10 (U-320 3): a MailSignIn never comes from a tainted or agent turn. In a bridge context of any provenance and kind, tainted or not, the command is refused for
/// every origin and nothing reaches SettingsOps; with no context only web_admin is routed.
Method TestMailSignInNeverFromAnAgentTurn()
{
	Set probe = ..NewProbe()
	Set provenances = $ListBuild("user", "untrusted", "", "other")
	Set origins = $ListBuild("tool", "web_admin", "web_user", "system", "telegram", "timer")
	Set tried = 0
	For p = 1:1:$ListLength(provenances) {
		For tainted = 0, 1 {
			For kind = "", "tool" {
				Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
				Set request.OwnerRef = "zzsessA"
				Set request.Provenance = $List(provenances, p)
				If kind '= "" Set request.Kind = kind
				Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context begins")
				If tainted Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "and is tainted")
				Try {
					For o = 1:1:$ListLength(origins) {
						Set command = ..NewCommand("MailSignIn", $List(origins, o), "zzsessA")
						Set command.Action = "start"
						Set tried = tried + 1
						Do probe.OnProcessInput(command, .output)
						Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "MailSignIn from '"_$List(origins, o)_"' in a context of provenance '"_$List(provenances, p)_"', tainted "_tainted_", kind '"_kind_"' is refused")
					}
				} Catch exception {
					Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
				}
				Do ##class(OcuTalon.Bridge.Context).End()
			}
		}
	}
	Do $$$AssertEquals(tried, 96, "all 96 combinations were tried")
	Do $$$AssertEquals(..Calls(), 0, "nothing reached SettingsOps")
	Set command = ..NewCommand("MailSignIn", "web_admin", "zzsessA")
	Set command.Action = "check"
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(..Calls(), 1, "with no context a web_admin MailSignIn is sent once")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "origin")_"|"_..Call(1, "class"), "SettingsOps|web_admin|OcuTalon.Msg.Command.MailSignIn", "to SettingsOps, as its own class")
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

/// A TestModel from a tool, from web_user and from the system is refused with nothing sent, also inside a bridge context while the command says web_admin; from web_admin it
/// reaches SettingsOps with its Agent unchanged.
Method TestModelRefusedFromToolAndUser()
{
	Set probe = ..NewProbe()
	Set expected = $ListBuild($ListBuild("tool", "That can't be done from the chat. Nothing was changed."), $ListBuild("web_user", "Only an OcuTalon admin can change settings. Nothing was changed."), $ListBuild("system", "Only an OcuTalon admin can change settings. Nothing was changed."))
	For i = 1:1:$ListLength(expected) {
		Set one = $List(expected, i)
		Set command = ..NewCommand("TestModel", $List(one, 1), "zzsessA")
		Set command.Agent = "TriageAgent"
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_$List(one, 2), "TestModel from "_$List(one, 1)_" is refused with its text")
		Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
	}
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context begins")
	Try {
		Set command = ..NewCommand("TestModel", "web_admin", "zzsessA")
		Set command.Agent = "TriageAgent"
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "TestModel that says web_admin is refused inside a context")
		Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set probe = ..NewProbe()
	Set command = ..NewCommand("TestModel", "web_admin", "zzsessA")
	Set command.Agent = "ChatAgent"
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(..Calls(), 1, "from web_admin it is sent once")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "origin")_"|"_..Call(1, "class"), "SettingsOps|web_admin|OcuTalon.Msg.Command.TestModel", "to SettingsOps, as its own class")
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

/// SessionOps carries out a GotIt (Story 12.12): the real operation answers a GotIt whose Ref names no Decision with status OK and
/// the result 0|not_found (not the stub's code 5003), and writes no Handled row.
Method TestGotItBuilt()
{
	Set owner = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.SessionOps", .sc)
	Do $$$AssertStatusOK(sc, "SessionOps is made")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set command = ..NewCommand("GotIt", "web_user", "zzsessA")
	Set command.Ref = ref
	Set command.Channel = "web"
	Set sc = owner.OnMessage(command, .response)
	Do $$$AssertStatusOK(sc, "the answer is an OK status, not the stub's 5003")
	Do $$$AssertTrue($IsObject(response), "with a result")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_found", "a Ref that names no Decision is not_found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).Marked(ref), "", "and no Handled row is written")
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
	Quit $Case(verb, "SendDigest": "Digest", "SaveSettings": "SettingsOps", "TestModel": "SettingsOps", "MailSignIn": "SettingsOps", : "SessionOps")
}

/// The oracle of the origin rules: "" when the verb from the origin is routed, otherwise the text of its refusal.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	If (origin = "tool") && (verb '= "SendDigest") Quit "That can't be done from the chat. Nothing was changed."
	If verb = "SendDigest" Quit $Select($ListFind($ListBuild("tool", "web_admin"), origin): "", 1: "OcuTalon can't take that command from here. Nothing was changed.")
	If verb = "SaveSettings" Quit $Select($ListFind($ListBuild("web_admin", "system"), origin): "", 1: "Only an OcuTalon admin can change settings. Nothing was changed.")
	If (verb = "TestModel") || (verb = "MailSignIn") Quit $Select(origin = "web_admin": "", 1: "Only an OcuTalon admin can change settings. Nothing was changed.")
	Quit $Select($ListFind($ListBuild("web_user", "web_admin", "telegram"), origin): "", 1: "OcuTalon can't take that command from here. Nothing was changed.")
}

}
