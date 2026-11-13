/// Tests of the step 4 verbs of Lane B and how CommandsIn routes them (Story 35.2; AD-1, AD-21, AD-29). Safe on a slot: no production runs, so
/// the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to OcuTalon.Test.Core.CommandsOwner and
/// records each call. The origin rules and every text are written out here, never read from CommandsIn.
///   - TestContracts: the seven verb classes have exactly the properties of XData Contracts and share the Ens.MessageBody extent;
///   - TestOrigins: each verb by every origin of Msg.Enum ORIGIN, "zz" and "" reaches its owner (McpOps for the five MCP verbs and SettingsOps for ListMcpServers,
///     from web_admin only, EmailOut for SendEmail from system only, since a tool's SendEmail needs a mailbox) or is refused with its text; a refusal sends
///     nothing, and a reached owner got the very object, with its origin and SessionRef unchanged;
///   - TestMcpVerbsFromATool: each MCP verb and ListMcpServers with origin tool, and inside a bridge context whatever origin it says, is refused and nothing is sent;
///   - TestSendEmailOwnAddress: a tool's SendEmail is routed only when email.owner is the command's SessionRef and every recipient is
///     email.address, ignoring case and surrounding spaces; a foreign recipient, an empty list, no address, another owner and, inside a
///     bridge context, another SessionRef are refused with nothing sent;
///   - TestSendEmailTurnMustBeClean (Story 21.6, ruling e; AD-10): inside a bridge context a tool's SendEmail to the own address is routed only when the
///     context's Provenance is user and its turn is not tainted; an untrusted, an empty-provenance and a tainted context are refused with the chat text
///     and nothing reaches EmailOut; the context of a replay of an approved call (Kind tool, provenance user) is routed whatever its taint says, because the
///     gate taints it when it allows the call and reads no taint in a replay; a replay context that is not provenance user is refused;
///   - TestSendEmailNotConnected (Story 21.6, matrix "Not connected"): a SendEmail whose send fails with the dispatch error of an item that the production
///     does not register answers not_connected with the accepted sentence (the answers of the other errors are unchanged); with no EmailOut job the real
///     gate answers not_connected at once, without the whole TIMEOUT wait of a send to a disabled item, and sends nothing;
///   - TestSendEmailAfterSave (Story 21.2, matrix row 13; DW-1042): the keys that the real SettingsOps.SaveEmail writes route the saving session's tool SendEmail to
///     the saved address and refuse another session and another address; when another admin saves, the first session is refused and the second routed, also over
///     a cache that still names the first;
///   - TestToolVerbs: the real TOOLVERBS holds SendEmail and no MCP verb, and the real Routes send the five MCP verbs to McpOps and ListMcpServers to SettingsOps from web_admin
///     only and SendEmail to EmailOut from tool and system;
///   - TestRestartRunnersWithoutProduction: RestartRunners' work answers OK and restarts nothing for no running production or another one;
///   - TestMcpEntryWrite (Story 21.4; DW-1041): through McpOps' handler, an add with a secret writes the entry AI.MCP.OcuTalon_<server> (a bearer secret:// reference) and the wallet key
///     OcuTalon_MCP_<server>.Key, an add without one writes the no-credential entry and no collection, an add whose handoff cannot be taken is failed and leaves nothing, a refused
///     address with a secret writes nothing, and a remove cancels the server's pending tool_call row (counted by Ownership.PendingToolCalls before) and drops the entry, key and
///     collection; the secret shows in no audit entry, event log row, trace global or ^OcuTalon* global, and the test's objects are gone afterwards;
///   - TestWebhookVerbs (Story 35.3): CreateWebhook and SetWebhookSecret by every origin reach SettingsOps from web_admin only and are refused from the others
///     (the chat text for tool, also inside a bridge context; the admin-only text for web_user, system, telegram, timer, "zz" and ""), with nothing sent; the
///     real TOOLVERBS holds neither, and the real Routes send both to SettingsOps from web_admin only;
///   - TestMcpSettingsRoutes (Story 21.4): Web.Api's XData UrlMap forwards /v1/settings/mcp to Web.McpSettings, whose own UrlMap holds the four routes.
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

/// The server name of the entry test's fixtures (row, tool rows, resource, wallet collection OcuTalon_MCP_<server> and its key, Config Store entry
/// AI.MCP.OcuTalon_<server>, approval rows), "" when none is left.
Property StubServer As %String;

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
	Do ..DropStubFixtures()
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Do ..PutBack("email.owner", $List(..Found, 1), $List(..Found, 2))
	Do ..PutBack("email.address", $List(..Found, 3), $List(..Found, 4))
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Kill ^||OcuTalonSettingsEmailProbe
	Quit $$$OK
}

/// The six verb classes have exactly their contract and keep the Ens.MessageBody extent.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll", "SendEmail", "ListMcpServers" {
		Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command."_verb, "RESPONSECLASSNAME"), "OcuTalon.Msg.CommandResult", verb_" is answered with a CommandResult")
	}
}

/// Each verb by every origin against the oracle: routed to the owner, or refused with its text and nothing sent. The tool origin of
/// SendEmail needs a mailbox, so it is refused here (TestSendEmailOwnAddress routes it).
Method TestOrigins()
{
	Do ..SetMailbox("", "")
	Set verbs = $ListFromString(..#MCPVERBS) _ $ListBuild("SendEmail", "ListMcpServers")
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
	Do $$$AssertEquals(tried, 56, "all 56 pairs were tried")
}

/// An MCP verb from a tool is refused with the chat text and nothing is sent: with origin tool, and inside a bridge context whatever origin the
/// command says (the origin is tool there).
Method TestMcpVerbsFromATool()
{
	Set probe = ..NewProbe()
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll", "ListMcpServers" {
		Do probe.OnProcessInput(..NewCommand(verb, "tool", "zzsessA"), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" from a tool is refused")
	}
	Do $$$AssertEquals(..Calls(), 0, "no MCP verb from a tool reaches McpOps or SettingsOps")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll", "ListMcpServers" {
			For origin = "web_admin", "system", "tool" {
				Do probe.OnProcessInput(..NewCommand(verb, origin, "zzsessA"), .output)
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" saying "_origin_" inside a context is refused")
			}
		}
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(..Calls(), 0, "and nothing reaches McpOps or SettingsOps")
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
	Set request.Provenance = "user"
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

/// The keys that the real save writes (Story 21.2, matrix row 13; DW-1042): SettingsOps.SaveEmail, through a probe whose credential, settings rows and
/// production update are stand-ins, writes email.address and email.owner, and CommandsIn then routes a tool's SendEmail to the saved address for the saving
/// session only. When another admin saves, the mailbox moves: even with this process's cache holding the first admin's pair, as another process's would
/// for up to a minute, the first session is refused and the second is routed (CommandsIn reads both keys from their rows).
Method TestSendEmailAfterSave()
{
	Set refused = "That can't be done from the chat. Nothing was changed."
	Do ..SaveMailbox("zzsessA", "Me@Example.org")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("email.owner")_"|"_##class(OcuTalon.Data.Setting).Get("email.address"), "zzsessA|Me@Example.org", "the real save wrote the owner and the address")
	Set probe = ..NewProbe()
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "the saving session's tool SendEmail to the saved address is routed")
	Do $$$AssertEquals(..Call(..Calls(), "target"), "EmailOut", "to EmailOut")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessB", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "another session's identical command is refused")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "other@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "another address is refused")
	Set before = ..Calls()
	Do ..SaveMailbox("zzsessB", "Me@Example.org")
	Set ^||OcuTalon.Setting("email.owner") = $ListBuild("zzsessA", 1, $ZHorolog)
	Set ^||OcuTalon.Setting("email.address") = $ListBuild("Me@Example.org", 1, $ZHorolog)
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "after the mailbox moves to B, A is refused even over a cache that still names A")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessB", "me@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "and B is routed")
	Do $$$AssertEquals(..Calls(), before + 1, "only B's command was sent")
}

/// Story 21.6, ruling e (AD-10): a tool's SendEmail to the own address inside a bridge context needs a clean turn.
Method TestSendEmailTurnMustBeClean()
{
	Set refused = "That can't be done from the chat. Nothing was changed."
	Do ..SetMailbox("zzsessA", "me@example.org")
	Set probe = ..NewProbe()
	Set before = ..Calls()
	Set cases = $ListBuild("user|0|1", "user|1|0", "untrusted|0|0", "untrusted|1|0", "|0|0", "|1|0", "other|0|0", "user|1|1|tool", "user|0|1|tool", "untrusted|0|0|tool", "|1|0|tool")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
		Set request.OwnerRef = "zzsessA"
		Set request.Provenance = $Piece(case, "|", 1)
		If $Piece(case, "|", 4) '= "" Set request.Kind = $Piece(case, "|", 4)
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context begins")
		If $Piece(case, "|", 2) Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "and is tainted")
		Try {
			Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
			If $Piece(case, "|", 3) {
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "1|test", "provenance '"_$Piece(case, "|", 1)_"', tainted "_$Piece(case, "|", 2)_", kind '"_$Piece(case, "|", 4)_"': routed")
			} Else {
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|"_refused, "provenance '"_$Piece(case, "|", 1)_"', tainted "_$Piece(case, "|", 2)_", kind '"_$Piece(case, "|", 4)_"': refused")
			}
		} Catch exception {
			Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
		}
		Do ##class(OcuTalon.Bridge.Context).End()
	}
	Do $$$AssertEquals(..Calls(), before + 3, "only the clean user turn and the user replays (tainted or not) reached EmailOut")
	Do probe.OnProcessInput(..NewEmail("tool", "zzsessA", "me@example.org"), .output)
	Do $$$AssertEquals(output.Outcome, "test", "outside a context (no turn) the own-address rule alone decides, as before")
}

/// Story 21.6 (matrix "Not connected"): the not-registered dispatch error and a missing EmailOut job answer not_connected.
Method TestSendEmailNotConnected()
{
	Set sentence = "No outgoing mail server is connected, so the email wasn't sent."
	Set probe = ..NewProbe("unregistered")
	Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "anyone@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_connected|"_sentence, "the not-registered dispatch error of a SendEmail is not_connected")
	Set probe = ..NewProbe("unregistered")
	Do probe.OnProcessInput(..NewCommand("AddMcpServer", "web_admin", "zzsessA"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", "the same error for another verb is failed, as before")
	Set probe = ..NewProbe("error")
	Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "anyone@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", "another error of a SendEmail is failed")
	Set probe = ..NewProbe("stub-op")
	Do probe.OnProcessInput(..NewEmail("system", "zzsessA", "anyone@example.org"), .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_built", "and a stub's 5003 is not_built, as before")
	Set item = "OcuTalon.Production||EmailOut"
	Set wasRunning = '##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 0)
	If wasRunning {
		Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(item, 1), "EmailOut runs here, so the test stops it")
		Do $$$AssertTrue(##class(OcuTalon.Test.Channel.LiveCase).WaitJobs("EmailOut", 0), "and it has no job")
	}
	Kill ^OcuTalonTest("CommandsRouting", ..Run)
	Set service = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.CommandsIn", .sc)
	Do $$$AssertStatusOK(sc, "the real gate is made")
	Set started = $ZHorolog
	Set sc = service.OnProcessInput(..NewEmail("system", "zzsessA", "anyone@example.org"), .real)
	Do $$$AssertEquals($Select($IsObject($Get(real)): real.Ok_"|"_real.Outcome_"|"_real.Message, 1: "no answer"), "0|not_connected|"_sentence, "with no EmailOut job the real gate answers not_connected")
	Do $$$AssertTrue($ZHorolog - started < 10, "at once, not after the wait of a send to a disabled item")
	If wasRunning Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(item, 0), "and EmailOut is started again")
}

/// The real TOOLVERBS and Routes: SendEmail is a tool verb and no MCP verb is; the five MCP verbs go to McpOps from web_admin only, and
/// SendEmail to EmailOut from tool and system.
Method TestToolVerbs()
{
	Set toolVerbs = ","_$Parameter("OcuTalon.Core.CommandsIn", "TOOLVERBS")_","
	Do $$$AssertTrue(toolVerbs [ ",SendEmail,", "SendEmail is a tool verb")
	For verb = "AddMcpServer", "RemoveMcpServer", "ClassifyTool", "SetSourcePoll", "RemoveSourcePoll", "ListMcpServers" {
		Do $$$AssertTrue(toolVerbs '[ (","_verb_","), verb_" is not a tool verb")
	}
	Set routes = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.CommandsIn||Routes").Data)
	Set mcp = 0, email = 0, other = 0, list = 0
	Set iterator = routes.%GetIterator()
	While iterator.%GetNext(, .route) {
		If route.owner = "McpOps" {
			Set mcp = mcp + 1
			Do $$$AssertTrue($ListFind($ListFromString(..#MCPVERBS), route.verb) > 0, route.verb_" is one of the five MCP verbs")
			Do $$$AssertEquals(route.origins, "web_admin", route.verb_" is routed to McpOps for web_admin only")
		} ElseIf route.verb = "ListMcpServers" {
			Set list = list + 1
			Do $$$AssertEquals(route.owner_"|"_route.origins, "SettingsOps|web_admin", "ListMcpServers is routed to SettingsOps for web_admin only")
		} ElseIf route.owner = "EmailOut" {
			Set email = email + 1
			Do $$$AssertEquals(route.verb_"|"_route.origins, "SendEmail|tool,system", "SendEmail is routed to EmailOut for tool and system")
		} ElseIf $ListFind($ListFromString(..#MCPVERBS_",SendEmail"), route.verb) {
			Set other = other + 1
		}
	}
	Do $$$AssertEquals(mcp, 5, "five verbs are routed to McpOps")
	Do $$$AssertEquals(list, 1, "ListMcpServers is routed to SettingsOps")
	Do $$$AssertEquals(email, 1, "one verb is routed to EmailOut")
	Do $$$AssertEquals(other, 0, "no step 4 verb goes to another owner")
}

/// The entry write that McpOps does in its own job (Story 21.4; AD-19, AD-21; DW-1041), through McpOps' handler as CommandsIn would deliver the command, with the
/// restart of the runners left out (Test.Mcp.OpsProbe):
///   - an add with a secret answers added, writes the entry AI.MCP.OcuTalon_<server> (read without resolving: the address and a bearer token that is the secret:// reference of the key
///     OcuTalon_MCP_<server>.Key, no secret) and the wallet key that holds the secret, and audits one MCP entry;
///   - an add with no secret writes an entry with no auth member and no wallet collection;
///   - an add whose handoff cannot be taken (it was taken before) answers failed with one fixed warning and leaves no row, resource, entry, collection or key;
///   - an add of a secret with a non-loopback http:// address is refused with the address text (the condition of the Contest Planner): nothing is written and the handoff is not taken;
///   - a remove cancels the server's pending tool_call row (the count of Ownership.PendingToolCalls is 1 before and 0 after), audits one MCP entry, and drops the entry, key and collection.
/// The secret shows in no audit entry, event log row, trace global or ^OcuTalon* global, and the test's rows, entries, collections and approval rows are gone afterwards.
Method TestMcpEntryWrite()
{
	Kill ^||ZzOps
	Set found = ..WalletIds()
	Do $$$AssertTrue($Extract(found, 1, 7) '= "SQLCODE", "the wallet is readable ("_found_")")
	Set server = "zzentry"_$Increment(^OcuTalonTest("CommandsStep4", "entry"))
	Set name = "AI.MCP.OcuTalon_"_server
	Set collection = "OcuTalon_MCP_"_server
	If ##class(%Wallet.Collection).Exists(collection) || ##class(%ConfigStore.Configuration).Exists(name) Quit
	Set ..StubServer = server
	Set logMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set secret = "zzEntry"_$Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "AAA")
	Set url = "http://127.0.0.1:1/mcp"
	// an add with a secret
	Set result = ..AddThrough(server, url, secret)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|added|"_##class(OcuTalon.Mcp.Ops).#MESSAGEADDED, "the add with a secret is answered added")
	Do $$$AssertEquals(+$Get(^||ZzOps("restarts")), 1, "the runners are restarted once")
	Do $$$AssertEquals(##class(%ConfigStore.Configuration).Exists(name), 1, "the entry "_name_" exists")
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(name, .details, 0, 0), "it is read without resolving its secret")
	Do $$$AssertEquals(details.transport_"|"_details.url, "remote|"_url, "it holds the transport and the address")
	Do $$$AssertEquals(details.auth.type_"|"_details.auth.token, "bearer|secret://"_collection_".Key#token", "and a bearer token that is the reference of the wallet key")
	Do $$$AssertEquals(+(details.%ToJSON() [ secret), 0, "the entry does not hold the secret")
	Do $$$AssertEquals(##class(%Wallet.Collection).Exists(collection)_"|"_##class(%Wallet.Secret).Exists(collection_".Key"), "1|1", "the wallet collection and key exist")
	Do $$$AssertEquals(+(##class(%Wallet.KeyValue).GetSecretValue(collection_".Key") [ secret), 1, "the wallet key holds the secret")
	Do $$$AssertEquals(..WalletIds(), found_$Select(found = "": "", 1: ";")_"Collection:"_collection_";Secret:"_collection_".Key", "and the wallet gained only them")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", server).%Size(), 1, "one MCP audit entry names the server")
	Do ..AssertNoLeak(secret, mark, logMark, "after the add")
	// a remove: the pending request of the server is counted, cancelled and its entry dropped
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(server)
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_delete_ticket", "{""id"":""T-1""}", toolref)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "pending", 3600, , .ref), "a pending tool_call request of the server is saved")
	Set pending = ##class(OcuTalon.Data.Ownership).PendingToolCalls(server, .sc)
	Do $$$AssertEquals(pending_"|"_$SYSTEM.Status.IsOK(sc), "1|1", "PendingToolCalls counts it")
	Set result = ..RunThrough(..NewRemove(server))
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "1|removed|"_##class(OcuTalon.Mcp.Ops).#MESSAGEREMOVED, "the remove is answered removed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(ref, "State"), "cancelled", "the pending request is cancelled (Story 22.4's CancelPending)")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).PendingToolCalls(server), 0, "and none is pending afterwards")
	Do $$$AssertEquals(..Left(server), "", "the row, the tool rows, the resource, the entry, the wallet key and the collection are gone")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", server, , 2).%Size(), 2, "the removal is audited too")
	Do ..DropApproval(ref)
	Do ..AssertNoLeak(secret, mark, logMark, "after the remove")
	// an add with no secret
	Set result = ..AddThrough(server, url, "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|added", "the add with no secret is answered added")
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).GetDetails(name, .plain, 0, 0), "its entry is read")
	Do $$$AssertEquals(plain.url_"|"_plain.%IsDefined("auth"), url_"|0", "it holds the address and no auth member")
	Do $$$AssertEquals(##class(%Wallet.Collection).Exists(collection)_"|"_##class(%Wallet.Secret).Exists(collection_".Key"), "0|0", "and no wallet collection or key is made")
	Do $$$AssertEquals(..RunThrough(..NewRemove(server)).Outcome, "removed", "it is removed")
	Do $$$AssertEquals(..Left(server), "", "and nothing of it is left")
	// the handoff cannot be taken
	Set warnings = ##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(logMark, "the entry or the wallet secret of the MCP server could not be written")
	Set command = ..NewAdd(server, url)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri), "a secret is offered")
	Do ##class(OcuTalon.Core.SecretHandoff).Take(uri, .gone)
	Kill gone
	Set command.Handoff = uri
	Set result = ..RunThrough(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|failed|"_##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "an add whose handoff was taken before is answered failed")
	Do $$$AssertEquals(..Left(server), "", "and leaves no row, resource, entry, collection or key")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(logMark, "the entry or the wallet secret of the MCP server could not be written"), warnings + 1, "with one warning of a fixed text")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "MCP", "MCP", server).%Size(), 4, "and no audit entry of it (the four of the two adds and the two removes before)")
	// a secret with a plain http:// address to another computer
	Set command = ..NewAdd(server, "http://192.0.2.7/mcp")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri), "a secret is offered for a plain http address")
	Set command.Handoff = uri
	Set result = ..RunThrough(command)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Message, "0|bad_address|"_##class(OcuTalon.Mcp.Ops).#MESSAGEADDRESS, "the add is refused with the address text")
	Do $$$AssertEquals(..Left(server), "", "no wallet key, entry or row is written")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .kept), "McpOps did not take the handoff")
	Do $$$AssertEquals(kept, secret, "it still held the secret")
	Kill kept
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "MCP", "MCP", server).%Size(), 4, "and no audit entry of the refused add")
	Do ..AssertNoLeak(secret, mark, logMark, "after the refusals")
	Kill secret
	Do ..DropStubFixtures()
	Do $$$AssertEquals(..StubServer, "", "the test's rows, entry, collection and approval rows are removed")
	Do $$$AssertEquals(..WalletIds(), found, "and the wallet is left as the test found it")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).PendingToolCalls(server), 0, "and no pending request is left")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.ApprovalRows).Prop(ref, "State"), "<no row>", "the approval row is deleted")
	Kill ^||ZzOps
}

/// The secret is in no OcuTalon audit entry (from the mark), no event log row (from the log mark), no trace global and no ^OcuTalon* global.
Method AssertNoLeak(secret As %String, mark As %String, logMark As %Integer, when As %String) [ Private ]
{
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", , , secret).%Size(), 0, "no OcuTalon audit entry holds the secret "_when)
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(logMark, secret), 0, "no event log row holds it "_when)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(secret), "", "no trace global holds it "_when)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(secret), "", "and no ^OcuTalon* global holds it "_when)
}

/// What is left of a server's objects as a text of places ("" when nothing): the row, the tool rows, the resource, the entry, the wallet key and the collection.
Method Left(server As %String) As %String [ Private ]
{
	Set places = ""
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(server) Set places = places_$ListBuild("the row")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", server)
	If result.%Next(), result.%GetData(1) Set places = places_$ListBuild("the tool rows")
	If ..ResourceExists("OcuTalon_MCP_"_server) Set places = places_$ListBuild("the resource")
	If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_"_server) Set places = places_$ListBuild("the entry")
	If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_"_server_".Key") Set places = places_$ListBuild("the wallet key")
	If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_"_server) Set places = places_$ListBuild("the wallet collection")
	Quit $ListToString(places, ", ")
}

/// 1 when the Security resource exists.
Method ResourceExists(resource As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.Resources).Exists(resource)
}

/// An AddMcpServer command with origin web_admin and no handoff.
Method NewAdd(server As %String, url As %String) As OcuTalon.Msg.Command.AddMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
	Set command.Server = server
	Set command.Url = url
	Set command.Origin = "web_admin"
	Set command.ActingUser = "zzadmin"
	Quit command
}

/// A RemoveMcpServer command with origin web_admin.
Method NewRemove(server As %String) As OcuTalon.Msg.Command.RemoveMcpServer [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set command.Server = server
	Set command.Origin = "web_admin"
	Set command.ActingUser = "zzadmin"
	Quit command
}

/// The add through McpOps' handler: the secret (when there is one) is offered to the handoff, and the handoff is discarded afterwards whatever happened.
Method AddThrough(server As %String, url As %String, secret As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ..NewAdd(server, url)
	Set uri = ""
	If secret '= "" {
		Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri), "the secret is offered")
		Set command.Handoff = uri
	}
	Set result = ..RunThrough(command)
	Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
	Quit result
}

/// Delivers the command to McpOps' handler through a probe that is told CommandsIn sent it, with the restart left out, and answers the CommandResult.
Method RunThrough(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow("CommandsIn", .sc)
	Do $$$AssertStatusOK(sc, "the probe of McpOps is made")
	Set sc = probe.MessageHandler(command, .result)
	Do $$$AssertStatusOK(sc, "the command is delivered and answered with an OK status")
	Quit result
}

/// Deletes the fixture approval row of the Ref, whatever its state.
Method DropApproval(ref As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen($Get(ref))
	If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
}

/// The webhook verbs go to SettingsOps from web_admin only (Story 35.3): every origin, "zz" and "" against the oracle, a bridge context, TOOLVERBS and Routes.
Method TestWebhookVerbs()
{
	Set origins = $ListFromString($Parameter("OcuTalon.Msg.Enum", "ORIGIN")) _ $ListBuild("zz", "")
	Set tried = 0
	For verb = "CreateWebhook", "SetWebhookSecret" {
		For o = 1:1:$ListLength(origins) {
			Set origin = $List(origins, o)
			Set probe = ..NewProbe()
			Set tried = tried + 1
			Set command = ..NewCommand(verb, origin, "zzsess"_verb)
			Set sc = probe.OnProcessInput(command, .output)
			Set label = verb_" from '"_origin_"'"
			Do $$$AssertStatusOK(sc, label_" is answered with a status that is OK")
			If origin = "web_admin" {
				Do $$$AssertEquals(..Calls(), 1, label_" is routed")
				Do $$$AssertEquals(..Call(1, "target"), "SettingsOps", label_" goes to SettingsOps")
				Set same = (probe.LastRequest = command)
				Do $$$AssertEquals(same, 1, label_": the owner got the very object")
			} Else {
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, $Select(origin = "tool": "That can't be done from the chat. Nothing was changed.", 1: "Only an OcuTalon admin can change settings. Nothing was changed."), label_" says why")
			}
		}
	}
	Do $$$AssertEquals(tried, 16, "both verbs by all eight origins")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.OwnerRef = "zzsessA"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "zzss"_..Run), "a context of session A begins")
	Try {
		Set probe = ..NewProbe()
		For verb = "CreateWebhook", "SetWebhookSecret" {
			Do probe.OnProcessInput(..NewCommand(verb, "web_admin", "zzsessA"), .output)
			Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "0|not_allowed|That can't be done from the chat. Nothing was changed.", verb_" inside a context is refused")
		}
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(..Calls(), 0, "and nothing reaches SettingsOps")
	Do $$$AssertTrue(($Parameter("OcuTalon.Core.CommandsIn", "TOOLVERBS") '[ "Webhook"), "the real TOOLVERBS holds no webhook verb")
	Set routes = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.CommandsIn||Routes").Data)
	Set found = 0
	For i = 0:1:routes.%Size() - 1 {
		Set route = routes.%Get(i)
		If (route.verb = "CreateWebhook") || (route.verb = "SetWebhookSecret") {
			Set found = found + 1
			Do $$$AssertEquals(route.owner_"|"_route.origins, "SettingsOps|web_admin", route.verb_" goes to SettingsOps from web_admin only")
		}
	}
	Do $$$AssertEquals(found, 2, "both routes are in the table")
}

/// The MCP settings routes (Story 21.4): Web.Api's XData UrlMap forwards the prefix /v1/settings/mcp to OcuTalon.Web.McpSettings, once, and that class's own UrlMap holds
/// the four routes (GET the list, POST servers, DELETE servers/:server, POST classify).
Method TestMcpSettingsRoutes()
{
	Set text = ..UrlMapText("OcuTalon.Web.Api")
	Do $$$AssertTrue(text [ "Url=""/v1/state""", "the UrlMap of Web.Api was read")
	Do $$$AssertEquals($Length(text, "<MapPrefix=""/v1/settings/mcp""Forward=""OcuTalon.Web.McpSettings""/>") - 1, 1, "it forwards /v1/settings/mcp to Web.McpSettings, once")
	Set routes = ..UrlMapText("OcuTalon.Web.McpSettings")
	Do $$$AssertTrue(routes [ "<RouteUrl=""""Method=""GET""Call=""List""/>", "Web.McpSettings routes GET the list")
	Do $$$AssertTrue(routes [ "<RouteUrl=""/servers""Method=""POST""Call=""Add""/>", "POST servers")
	Do $$$AssertTrue(routes [ "<RouteUrl=""/servers/:server""Method=""DELETE""Call=""Remove""/>", "DELETE servers/:server")
	Do $$$AssertTrue(routes [ "<RouteUrl=""/classify""Method=""POST""Call=""Classify""/>", "and POST classify")
	Do $$$AssertEquals($Length(routes, "<RouteUrl=") - 1, 4, "and no other route")
}

/// The XData UrlMap of the class as text, with the quotes made double and the white space taken out.
Method UrlMapText(class As %String) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledXData).%OpenId(class_"||UrlMap")
	Do $$$AssertTrue($IsObject(compiled), "the UrlMap XData of "_class_" is compiled")
	If '$IsObject(compiled) Quit ""
	Set stream = compiled.Data
	Set text = ""
	While 'stream.AtEnd { Set text = text_stream.Read(32000) }
	Quit $Translate($Replace(text, "'", """"), " "_$Char(9, 10, 13))
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

/// The wallet's collections and secrets as one text, or "SQLCODE <code>" when the extents cannot be read. The wallet is kept in the instance's
/// security database, so the text is the same from every namespace.
Method WalletIds() As %String [ Private ]
{
	Set ids = ""
	For table = "Collection", "Secret" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID FROM %Wallet."_table_" ORDER BY 1")
		If rs.%SQLCODE < 0 Quit
		While rs.%Next() { Set ids = ids_$ListBuild(table_":"_rs.%GetData(1)) }
	}
	If rs.%SQLCODE < 0 Quit "SQLCODE "_rs.%SQLCODE
	Quit $ListToString(ids, ";")
}

/// Removes what the entry test made when it is still there: the server's rows, resource and grant, the Config Store entry, the wallet key and collection
/// (deleting a collection deletes its keys), and clears StubServer once none of them is left.
Method DropStubFixtures() [ Private ]
{
	Set server = ..StubServer
	If server = "" Quit
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", server)
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(server, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
	Do ##class(OcuTalon.Install.Step.Mcp).Revoke(server)
	Set name = "AI.MCP.OcuTalon_"_server
	If ##class(%ConfigStore.Configuration).Exists(name) Do ##class(%ConfigStore.Configuration).Delete(name)
	If ##class(%Wallet.Secret).Exists("OcuTalon_MCP_"_server_".Key") Do ##class(%Wallet.KeyValue).Delete("OcuTalon_MCP_"_server_".Key")
	If ##class(%Wallet.Collection).Exists("OcuTalon_MCP_"_server) Do ##class(%Wallet.Collection).Delete("OcuTalon_MCP_"_server)
	If ..Left(server) = "" Set ..StubServer = ""
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
	Quit $Case(verb, "SendEmail": "EmailOut", "CreateWebhook": "SettingsOps", "SetWebhookSecret": "SettingsOps", "ListMcpServers": "SettingsOps", : "McpOps")
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

/// Saves the mailbox for the session through the real SaveEmail, run by a SettingsEmailProbe (stand-in credential, settings rows and production update). The address and
/// user name are offered to the hand-off as the route does (Story 21.14), and every reference left is taken back.
Method SaveMailbox(session As %String, address As %String) [ Private ]
{
	Set secret = "zzstep4pw"_$Job_$Random(100000)
	Set sc = ##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri)
	Do $$$AssertStatusOK(sc, "the password is offered")
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "channels"
	Set body = {"address": (address), "incoming": "pop.example.com", "user": "zzstep4", "password": (uri)}
	Set uris = $ListBuild(uri)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Core.SecretHandoff).Swap(body, .uris), "the address and user are offered")
	Set command.Changes = body.%ToJSON()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = session
	Set command.Origin = "web_admin"
	Set save = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.SettingsEmailProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the settings probe is made")
	Set sc = save.OnMessage(command, .result)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the real save is done")
	Set position = 0
	While $ListNext(uris, position, one) {
		Do ##class(OcuTalon.Core.SecretHandoff).Take(one, .discard, 0)
		Kill discard
	}
	Kill secret
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
   "Handoff": "%String(MAXLEN=128)",
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
   "Text": "%String(MAXLEN=)",
   "ApprovalRef": "%String(MAXLEN=22)"
  }
 },
 "OcuTalon.Msg.Command.ListMcpServers": {
  "super": "OcuTalon.Msg.Command",
  "props": {
   "Origin": "%String(MAXLEN=32)",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "SessionRef": "%String(MAXLEN=22)",
   "ActingUser": "%String(MAXLEN=160)"
  }
 }
}
}

}
