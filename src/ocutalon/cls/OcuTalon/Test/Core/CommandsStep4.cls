/// Tests of the step 4 verbs of Lane B and how CommandsIn routes them (Story 35.2; AD-1, AD-21, AD-29). Safe on a slot: no production runs, so
/// the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to OcuTalon.Test.Core.CommandsOwner and
/// records each call. The origin rules and every text are written out here, never read from CommandsIn.
///   - TestContracts: the six verb classes have exactly the properties of XData Contracts and share the Ens.MessageBody extent;
///   - TestOrigins: each verb by every origin of Msg.Enum ORIGIN, "zz" and "" reaches its owner (McpOps for the five MCP verbs from web_admin
///     only, EmailOut for SendEmail from system only, since a tool's SendEmail needs a mailbox) or is refused with its text; a refusal sends
///     nothing, and a reached owner got the very object, with its origin and SessionRef unchanged;
///   - TestMcpVerbsFromATool: each MCP verb with origin tool, and inside a bridge context whatever origin it says, is refused and nothing is sent;
///   - TestSendEmailOwnAddress: a tool's SendEmail is routed only when email.owner is the command's SessionRef and every recipient is
///     email.address, ignoring case and surrounding spaces; a foreign recipient, an empty list, no address, another owner and, inside a
///     bridge context, another SessionRef are refused with nothing sent;
///   - TestToolVerbs: the real TOOLVERBS holds SendEmail and no MCP verb, and the real Routes send the five MCP verbs to McpOps from web_admin
///     only and SendEmail to EmailOut from tool and system;
///   - TestRestartRunnersWithoutProduction: RestartRunners' work answers OK and restarts nothing for no running production or another one;
///   - TestMcpEntryStubs: SaveMcpEntry and RemoveMcpEntry answer code 5003 and leave no Config Store entry.
/// The run's calls are kept under ^OcuTalonTest("CommandsRouting", "step4<n>") and deleted after the tests; email.owner and email.address are
/// put back as found; the context of the test process is ended before and after the tests.
Class OcuTalon.Test.Core.CommandsStep4 Extends OcuTalon.Test.Contract
{

/// The MCP verbs.
Parameter MCPVERBS = "AddMcpServer,RemoveMcpServer,ClassifyTool,SetSourcePoll,RemoveSourcePoll";

/// The run's subscript.
Property Run As %String;

/// The settings as found: $ListBuild(owner row exists, owner value, address row exists, address value).
Property Found As %List;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Run = "step4"_$Increment(^OcuTalonTest("CommandsStep4", "n"))
	Set ..Found = $ListBuild(##class(OcuTalon.Data.Setting).KeyIndexExists("email.owner"), ##class(OcuTalon.Data.Setting).Get("email.owner"), ##class(OcuTalon.Data.Setting).KeyIndexExists("email.address"), ##class(OcuTalon.Data.Setting).Get("email.address"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Do ..PutBack("email.owner", $List(..Found, 1), $List(..Found, 2))
	Do ..PutBack("email.address", $List(..Found, 3), $List(..Found, 4))
	Quit $$$OK
}

/// The six verb classes have exactly their contract and keep the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll", "SendEmail" {
		Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command."_verb, "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", verb_" is answered with a CommandResult")
	}
}

/// Each verb by every origin against the oracle: routed to the owner, or refused with its text and nothing sent. The tool origin of
/// SendEmail needs a mailbox, so it is refused here (TestSendEmailOwnAddress routes it).
Method TestOrigins()
{
	Do ..SetMailbox("", "")
	Set verbs = $ListFromString(..#MCPVERBS) _ $ListBuild("SendEmail")
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
				Set same = (probe.LastRequest = command)
				Do $$$AssertEquals(same, 1, label_": the owner got the very object CommandsIn was given")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", label_": the owner's result is the answer")
			} Else {
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, expected, label_" says why")
			}
		}
	}
	Do $$$AssertEquals(tried, 48, "all 48 pairs were tried")
}

/// An MCP verb from a tool is refused with the chat text and nothing is sent: with origin tool, and inside a bridge context whatever origin the
/// command says (the origin is tool there).
Method TestMcpVerbsFromATool()
{
	Set probe = ..NewProbe()
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll" {
		Do probe.OnProcessInput(..NewCommand(verb, "tool", "zzsessA"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" from a tool is refused")
	}
	Do $$$AssertEquals(..Calls(), 0, "no MCP verb from a tool reaches McpOps")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll" {
			For origin = "web_admin", "system", "tool" {
				Do probe.OnProcessInput(..NewCommand(verb, origin, "zzsessA"), .output)
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" saying "_origin_" inside a context is refused")
			}
		}
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(..Calls(), 0, "and nothing reaches McpOps")
}

/// A tool's SendEmail is routed only to the session user's own mailbox address (AD-1): email.owner is the command's SessionRef, email.address is
/// set, and every recipient equals it ignoring case and surrounding spaces.
Method TestSendEmailOwnAddress()
{
	Set refused = "That can't be done from the chat. Nothing was changed."
	Do ..SetMailbox("zzsessA", "Me@Example.org")
	Set probe = ..NewProbe()
	For recipients = "me@example.org", "ME@EXAMPLE.ORG", "  me@example.org  ", "me@example.org, ME@example.org ,me@example.org", "Me@Example.org" {
		Set before = ..Calls()
		Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", recipients), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "'"_recipients_"' is the own address and is routed")
		Do $$$AssertEquals(..Calls(), before + 1, "'"_recipients_"' is sent once")
		Do $$$AssertEquals(..Call(..Calls(), "target")_"|"_..Call(..Calls(), "origin")_"|"_..Call(..Calls(), "sessionRef"), "EmailOut|tool|zzsessA", "'"_recipients_"' goes to EmailOut as a tool's, for A")
	}
	Set before = ..Calls()
	For recipients = "other@example.org", "me@example.org,other@example.org", "other@example.org,me@example.org", "me@example.org.evil.net", "xme@example.org", "", "   ", ",", "me@example.org,", ",me@example.org", "me@example.org,,me@example.org" {
		Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", recipients), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "'"_recipients_"' is refused")
	}
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessB", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "another session than email.owner is refused")
	Do probe.OnProcessInput(..NewEmail("tool", "", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "an empty SessionRef is refused")
	Do ..SetMailbox("zzsessA", "")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "no email.address refuses every list")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", ""), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "no email.address and an empty list is refused")
	Do ..SetMailbox("", "me@example.org")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "no email.owner refuses")
	Do $$$AssertEquals(..Calls(), before, "no refusal sent anything")

	Do ..SetMailbox("zzsessA", "me@example.org")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessB"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session B begins")
	Try {
		Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "me@example.org"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "inside B's context a SendEmail for A is refused, whatever origin it says")
		Do $$$AssertEquals(..Calls(), before, "and nothing is sent")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "me@example.org"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "inside A's context a SendEmail for A to its own address is routed")
		Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "other@example.org"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "inside the context another recipient is refused: the origin is tool there")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Calls()
	Do probe.OnProcessInput(..NewEmail("system", "zzsessB", "anyone@example.org,else@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "once the context has ended, origin system reaches EmailOut with any recipients")
	Do $$$AssertEquals(..Calls(), before + 1, "and is sent")
	Do probe.OnProcessInput(..NewEmail("system", "zzsessB", ""), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "origin system with an empty list is the owner's to validate")
}

/// The real TOOLVERBS and Routes: SendEmail is a tool verb and no MCP verb is; the five MCP verbs go to McpOps from web_admin only, and
/// SendEmail to EmailOut from tool and system.
Method TestToolVerbs()
{
	Set toolVerbs = ","_$Parameter("OcuTalon.Core.CommandsIn", "TOOLVERBS")_","
	Do $$$AssertTrue(toolVerbs [ ",SendEmail,", "SendEmail is a tool verb")
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll" {
		Do $$$AssertTrue(toolVerbs '[ (","_verb_","), verb_" is not a tool verb")
	}
	Set routes = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.CommandsIn||Routes").Data)
	Set mcp = 0, email = 0, other = 0
	Set iterator = routes.%GetIterator()
	While iterator.%GetNext(, .route) {
		If route.owner = "McpOps" {
			Set mcp = mcp + 1
			Do $$$AssertTrue($ListFind($ListFromString(..#MCPVERBS), route.verb) > 0, route.verb_" is one of the five MCP verbs")
			Do $$$AssertEquals(route.origins, "web_admin", route.verb_" is routed to McpOps for web_admin only")
		} ElseIf route.owner = "EmailOut" {
			Set email = email + 1
			Do $$$AssertEquals(route.verb_"|"_route.origins, "SendEmail|tool,system", "SendEmail is routed to EmailOut for tool and system")
		} ElseIf $ListFind($ListFromString(..#MCPVERBS_",SendEmail"), route.verb) {
			Set other = other + 1
		}
	}
	Do $$$AssertEquals(mcp, 5, "five verbs are routed to McpOps")
	Do $$$AssertEquals(email, 1, "one verb is routed to EmailOut")
	Do $$$AssertEquals(other, 0, "no step 4 verb goes to another owner")
}

/// Both MCP entry stubs answer code 5003, and write no Config Store entry (AD-19, AD-21: built in Story 21.4).
Method TestMcpEntryStubs()
{
	Set server = "zzstub"_$Increment(^OcuTalonTest("CommandsStep4", "stub"))
	Set name = "AI.MCP.OcuTalon_"_server
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists(name), 0, "the entry is absent before")
	Set sc = ##class(OcuTalon.Core.SettingsOps).SaveMcpEntry(server, "http://127.0.0.1:1/mcp", "secret://zz")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "SaveMcpEntry answers the not-built code")
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists(name), 0, "and writes no entry")
	Set sc = ##class(OcuTalon.Core.SettingsOps).RemoveMcpEntry(server)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "RemoveMcpEntry answers the not-built code")
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists(name), 0, "and leaves no entry")
}

/// RestartRunners with no OcuTalon production running answers OK and restarts nothing (AD-21), through its work for the running production's
/// name (RestartIn): "" (none runs) and another production's name answer OK without a restart, wherever the test runs. Where no OcuTalon
/// production runs, RestartRunners itself answers OK too; where it runs, Test.Core.RestartRunners covers the restart.
Method TestRestartRunnersWithoutProduction()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SettingsOps).RestartIn(""), "no production running: OK, nothing restarted")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SettingsOps).RestartIn("ZzOther.Production"), "another production running: OK, nothing restarted")
	If ##class(Ens.Director).IsProductionRunning(.name) && (name = "OcuTalon.Production") Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SettingsOps).RestartRunners(), "RestartRunners answers OK with no OcuTalon production running")
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
	If verb = "SendEmail" {
		Set command.Recipients = "someone@example.org"
		Set command.Subject = "zz"
		Set command.Text = "zz"
	}
	Quit command
}

/// A SendEmail with the origin, session and recipients.
Method NewEmail(origin As %String, sessionRef As %String, recipients As %String) As OcuTalon.Msg.Command.SendEmail [ Private ]
{
	Set command = ..NewCommand("SendEmail", origin, sessionRef)
	Set command.Recipients = recipients
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
	Quit $Select(verb = "SendEmail": "EmailOut", 1: "McpOps")
}

/// The oracle of the origin rules with no mailbox set: "" when the verb from the origin is routed, otherwise the text of its refusal.
/// SendEmail from tool is refused without a mailbox.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	If verb = "SendEmail" {
		If origin = "system" Quit ""
		If origin = "tool" Quit "That can't be done from the chat. Nothing was changed."
		Quit "OcuTalon can't take that command from here. Nothing was changed."
	}
	If origin = "web_admin" Quit ""
	If origin = "tool" Quit "That can't be done from the chat. Nothing was changed."
	Quit "Only an OcuTalon admin can change settings. Nothing was changed."
}

/// Sets the product keys email.owner and email.address.
Method SetMailbox(owner As %String, address As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set("email.owner", owner), "email.owner is set")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set("email.address", address), "email.address is set")
}

/// Puts a key back as found: its row with the value, or no row.
ClassMethod PutBack(key As %String, existed As %Boolean, value As %String) [ Private ]
{
	If existed {
		Do ##class(OcuTalon.Data.Setting).Set(key, value)
	} Else {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
		Kill ^||OcuTalon.Setting(key)
	}
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Msg.Command.AddMcpServer": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Server": "%String(MAXLEN=40)",
   "Url": "%String(MAXLEN=2000)",
   "ActingUser": "%String(MAXLEN=160)"
  }
 },
 "OcuTalon.Msg.Command.RemoveMcpServer": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Server": "%String(MAXLEN=40)",
   "ActingUser": "%String(MAXLEN=160)"
  }
 },
 "OcuTalon.Msg.Command.ClassifyTool": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Server": "%String(MAXLEN=40)",
   "Tool": "%String(MAXLEN=128)",
   "Classification": "%String(MAXLEN=16)",
   "ActingUser": "%String(MAXLEN=160)"
  }
 },
 "OcuTalon.Msg.Command.SetSourcePoll": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Server": "%String(MAXLEN=40)",
   "Tool": "%String(MAXLEN=128)",
   "Name": "%String(MAXLEN=100)",
   "Arguments": "%String(MAXLEN=)",
   "IntervalMinutes": "%Integer",
   "ActingUser": "%String(MAXLEN=160)"
  }
 },
 "OcuTalon.Msg.Command.RemoveSourcePoll": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "SourceRef": "%String(MAXLEN=22)",
   "ActingUser": "%String(MAXLEN=160)"
  }
 },
 "OcuTalon.Msg.Command.SendEmail": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "Recipients": "%String(MAXLEN=2000)",
   "Subject": "%String(MAXLEN=200)",
   "Text": "%String(MAXLEN=)"
  }
 }
}
}

}
