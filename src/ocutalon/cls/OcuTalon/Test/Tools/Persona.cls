/// Tests of the Chat agent's persona tool (Story 40.5; AD-1, AD-4, AD-6, AD-7, AD-9, AD-10, AD-32): propose_persona, the toolset OcuTalon.Tools.Persona and its
/// provider OcuTalon.Tools.PersonaTools. THE TESTS BUT TestDeclarations RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running
/// after the Production step, the CI override's environment and the mock's request log, and fail with the reason where they do not have them. They follow
/// Test.Tools.Reminders, with the same double behind the CommandsIn item (Test.Tools.CommandsDouble answers ProposePersona with Ok, Outcome proposed and the
/// Ref PROPOSEREF) and the same restores. Test.Tools.Reminders keeps its private Prepare, Begin and Turn: a subclass would run its tests again.
///   - TestDeclarations (AC4; no production needed): Chat's TOOLSETS names the toolset, which offers exactly Names.PROPOSEPERSONA once, from PersonaTools; its
///     step label, classification, read-only and trusted-output parameters are those of the spec; the inputs are preset, language and custom (preset required),
///     none names a session, an owner or an origin; the toolset holds no Requirement;
///   - TestProposeUserTurn (AC4): in a user turn of owner S, propose_persona submits one ProposePersona with origin tool, SessionRef S, the key <ItemId>:1 and the
///     preset pirate and no other field, and answers ok, outcome proposed, the owner's message and the owner's Ref;
///   - TestProposedWhateverTheOwnerSays (AC4): with the double answering Ok and the outcome raised, the model still reads proposed;
///   - TestProposeFields (AC4): language and custom reach the owner as given, each only when the model gave it;
///   - TestOwnerRefuses (AC4): the owner's refusal reaches the model with its message, its outcome and no ref;
///   - TestNoSession (AC4): no context, an owner that is not a session's Ref or an empty ItemId submits nothing and answers NOSESSION;
///   - TestOnlineDemo (AC6): on the online demo the answer is not_available with CommandsIn MESSAGENOTALLOWED, nothing is submitted and the command count does
///     not move; the setting is put back;
///   - TestProposeThroughATurn (AC4): a real turn of the Chat agent against the CI mock (scenario persona-propose) submits one ProposePersona with origin tool, the
///     turn's owner and the key <ItemId>:1; the model's second request offers propose_persona and carries the tool result; the steps are model, tool (Suggesting
///     a persona) and model.
/// Added by the QA stage (AC4, AC5, AC6), each a real turn of the Chat agent against the same mock scenario:
///   - TestOnlineDemoThroughATurn (AC6): with onlineDemo 1 the model reads not_available with the owner's MESSAGENOTALLOWED and the double records nothing;
///   - TestOwnerRefusalThroughATurn (AC4): the owner's refusal reaches the model as {"ok": false, "outcome": "refused", "message": M} with no ref;
///   - TestUntrustedTurnDenied (AC5): an untrusted turn of Chat has its propose_persona call denied with UNTRUSTED, the double records nothing and the model
///     reads the sentence.
Class OcuTalon.Test.Tools.Persona Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The test double of CommandsIn.
Parameter DOUBLE = "OcuTalon.Test.Tools.CommandsDouble";

/// The production item that the double sits behind.
Parameter ITEM = "CommandsIn";

Parameter TOOLS = "OcuTalon.Tools.PersonaTools";

Parameter TOOLSET = "OcuTalon.Tools.Persona";

/// The helper that submits the commands, which holds the texts for the model.
Parameter CALL = "OcuTalon.Tools.CommandCall";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// What the CommandsIn item had before the double was put behind it (RunnerFixture.UseItemClass), as the JSON text it gave, or "" while the double is not
/// behind it.
Property Swap As %String(MAXLEN = "");

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the turns that the test made.
Property ItemIds As %List;

/// The onlineDemo setting before the test changed it, and whether it did.
Property Before As %String;

Property Saved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Saved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Before)
		Set ..Saved = 0
		// The Chat runner builds its agent once for its job and attaches the documents tool only off the online demo (Story 19.4), so a turn that ran with the demo
		// on has left a job without the tool: the job is started afresh with the setting back.
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart("ChatAgent")
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..Swap '= "" {
		Set saved = {}.%FromJSON(..Swap)
		Set ..Swap = ""
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass(..#ITEM, saved)
		Set made = ##class(Ens.Director).CreateBusinessService(..#ITEM, .service)
		If $$$ISERR(made) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, made)
		} ElseIf $ClassName(service) '= saved.className {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The "_..#ITEM_" item runs "_$ClassName(service)_" after the restore, not "_saved.className))
		}
	}
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys())
		Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
		If '##class(OcuTalon.Test.Agent.RunnerFixture).KeysAre(placeholder) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
	}
	Quit sc
}

/// The declarations (AC4). Chat's TOOLSETS names the persona toolset, whose discovery lists exactly propose_persona (the name in Tools.Names), once, with
/// PersonaTools as the provider. Its step label is the class parameter STEPLABELPROPOSEPERSONA, not the generic label. It is safe, not read-only and trusted
/// output. The inputs are preset, language and custom, with preset required, and none names a session, an owner or an origin. The toolset holds no
/// Requirement element and depends on the tool class.
Method TestDeclarations()
{
	Do $$$AssertTrue($ListFind($ListFromString($Parameter("OcuTalon.Agent.Chat", "TOOLSETS")), ..#TOOLSET) > 0, "Chat's TOOLSETS names "_..#TOOLSET)
	Set name = $Parameter("OcuTalon.Tools.Names", "PROPOSEPERSONA")
	Do $$$AssertEquals(name, "propose_persona", "the tool's name is the one of Tools.Names")
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Do $$$AssertEquals(tools.%Size(), 1, "the toolset offers one tool")
	Set seen = 0
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If tool.name = name Set seen = seen + 1
		Do $$$AssertEquals(tool.provider, ..#TOOLS, tool.name_" is a method of "_..#TOOLS)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, tool.name), "Suggesting a persona", "its step label is Suggesting a persona")
		Do $$$AssertNotEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, tool.name), ##class(OcuTalon.Bridge.Adapter.StepBuffer).#GENERICLABEL, "and not the generic label")
		Do $$$AssertEquals($Parameter(tool.provider, "STEPLABELPROPOSEPERSONA"), "Suggesting a persona", "the label is the class parameter")
		Do $$$AssertEquals($Parameter(tool.provider, "CLASSIFICATIONPROPOSEPERSONA"), "safe", "it is classified safe")
		Do $$$AssertEquals($Parameter(tool.provider, "READONLYPROPOSEPERSONA"), 0, "it is not read-only")
		Do $$$AssertEquals($Parameter(tool.provider, "TRUSTEDOUTPUTPROPOSEPERSONA"), 1, "and its output is trusted")
		Do $$$AssertEquals(..SortedKeys(tool.parameters.properties), "custom,language,preset", "its inputs are custom, language and preset")
		Do $$$AssertEquals($ListToString(..Items(tool.parameters.required)), "preset", "and only preset is required")
		Set inputs = ..SortedKeys(tool.parameters.properties)
		For input = 1:1:$Length(inputs, ",") {
			Set one = $Piece(inputs, ",", input)
			Do $$$AssertTrue(tool.parameters.properties.%Get(one).description '= "", "the input "_one_" has a description for the model")
			For forbidden = "session", "owner", "origin" {
				Do $$$AssertNotTrue($ZConvert(one, "L") [ forbidden, "the input "_one_" does not name a "_forbidden)
			}
		}
		Do $$$AssertEquals(tool.metadata."origin_class", ..#TOOLS, "it says that it originates in "_..#TOOLS)
	}
	Do $$$AssertEquals(seen, 1, name_" is offered once")
	Set own = $ClassMethod(..#TOOLS, "%New").%Discover().tools
	Do $$$AssertEquals(own.%Size(), 1, ..#TOOLS_" offers its one method and none of Result's")
	Set return = ##class(%Dictionary.CompiledMethod).%OpenId(..#TOOLS_"||ProposePersona").ReturnType
	Do $$$AssertTrue(return [ "DynamicObject", "ProposePersona returns a dynamic object: "_return)
	Set definition = ##class(%Dictionary.XDataDefinition).%OpenId(..#TOOLSET_"||Definition")
	Set xml = $Select($IsObject(definition): definition.Data.Read(32000), 1: "")
	Do $$$AssertTrue(xml '= "", "the toolset has its Definition")
	Do $$$AssertTrue(xml '[ "Requirement", "and holds no Requirement element: the class parameters are the one declaration")
	Do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%OpenId(..#TOOLSET).DependsOn, ..#TOOLS, "and it depends on the tool class")
}

/// The matrix row "Propose, user turn" (AC4). In a user turn of owner S with ItemId I, propose_persona with the preset pirate submits one ProposePersona:
/// origin tool, SessionRef S, the key I:1, Preset pirate and no other field. The answer is ok, outcome proposed, the owner's message and the owner's Ref.
Method TestProposeUserTurn()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("pirate")
	Do ..AssertObject(answer, ..Proposed(), "the model reads the owner's answer")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 Do ..AssertCall(calls.%Get(0), owner, itemId_":1", "IdempotencyKey,Origin,Preset,SessionRef", "ProposePersona")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).fields.Preset, "pirate", "with the preset that the model gave")
}

/// The model reads proposed whatever word the owner's Ok answer carries (AC4): the double answers Ok with the outcome raised, and the answer is still
/// ok, outcome proposed, the owner's message and the owner's Ref.
Method TestProposedWhateverTheOwnerSays()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("CommandsDouble", "outcome") = "raised"
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("pirate")
	Do ..AssertObject(answer, ..Proposed(), "the model reads proposed, not the owner's word raised")
	Do $$$AssertEquals(..Calls().%Size(), 1, "the double recorded the command")
}

/// The language and the custom text reach the owner as given, each only when the model gave it (AC4): the tool validates nothing.
Method TestProposeFields()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("language", "Spanish")
	Do ..AssertObject(answer, ..Proposed(), "a language proposal is answered by the owner")
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("custom", "", "Short and dry.")
	Do ..AssertObject(answer, ..Proposed(), "a custom proposal is answered by the owner")
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("nonsense")
	Do ..AssertObject(answer, ..Proposed(), "and so is a preset that the tool does not know, which only the owner may refuse")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 3, "the double recorded three commands")
	If calls.%Size() = 3 {
		Do ..AssertCall(calls.%Get(0), owner, itemId_":1", "IdempotencyKey,Language,Origin,Preset,SessionRef", "the language")
		Do $$$AssertEquals(calls.%Get(0).fields.Language, "Spanish", "which names Spanish")
		Do ..AssertCall(calls.%Get(1), owner, itemId_":2", "Custom,IdempotencyKey,Origin,Preset,SessionRef", "the custom text")
		Do $$$AssertEquals(calls.%Get(1).fields.Custom, "Short and dry.", "which is the text given")
		Do ..AssertCall(calls.%Get(2), owner, itemId_":3", "IdempotencyKey,Origin,Preset,SessionRef", "the unknown preset")
		Do $$$AssertEquals(calls.%Get(2).fields.Preset, "nonsense", "which is passed on as given")
	}
}

/// The matrix row "Owner refuses" (AC4). The double refuses ProposePersona with a message M. The answer is {"ok": false, "outcome": "refused", "message": M}
/// and has no ref.
Method TestOwnerRefuses()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set message = "That is not a persona OcuTalon has. Nothing was changed."
	Set ^OcuTalonTest("CommandsDouble", "refuse", "ProposePersona") = message
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("nonsense")
	Do ..AssertObject(answer, {"ok": false, "outcome": "refused", "message": (message)}, "the owner's refusal reaches the model unchanged")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded the command")
}

/// The matrix row "No session" (AC4). With no bridge context, an owner of instance, eval, empty or not a Ref, or an empty ItemId, the answer is NOSESSION and
/// nothing is submitted.
Method TestNoSession()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set cases = $ListBuild(
		$ListBuild("no context", 0, "", ""),
		$ListBuild("the owner instance", 1, "instance", itemId),
		$ListBuild("the owner eval", 1, "eval", itemId),
		$ListBuild("an empty owner", 1, "", itemId),
		$ListBuild("an owner that is not a Ref", 1, "zzOwnerTooShort", itemId),
		$ListBuild("an empty ItemId", 1, owner, ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Bridge.Context).End()
		If $List(case, 2) Do ..Begin($List(case, 3), $List(case, 4))
		Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("pirate")
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": the answer is NOSESSION")
		Do $$$AssertEquals(..Calls().%Size(), 0, $List(case, 1)_": the double recorded nothing")
	}
}

/// The matrix row "Online demo" (AC6). With onlineDemo 1, a user turn of S gets {"ok": false, "outcome": "not_available", "message": MESSAGENOTALLOWED}; the
/// double records nothing and the context's command count does not move. With the setting off the same call proposes.
Method TestOnlineDemo()
{
	If '..Prepare() Quit
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1), "the online demo is on")
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("pirate")
	Do ..AssertObject(answer, {"ok": false, "outcome": "not_available", "message": ($Parameter("OcuTalon.Core.CommandsIn", "MESSAGENOTALLOWED"))}, "the answer is not_available with the owner's own message")
	Do $$$AssertEquals(..Calls().%Size(), 0, "the double recorded nothing")
	Do $$$AssertEquals(+##class(OcuTalon.Bridge.Context).Current().CommandCount, 0, "and the command count did not move")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0), "the online demo is off")
	Set answer = ##class(OcuTalon.Tools.PersonaTools).ProposePersona("pirate")
	Do ..AssertObject(answer, ..Proposed(), "control: with the online demo off the same call proposes")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and the double recorded it")
}

/// "Please talk like a pirate." (AC4; scenario persona-propose). The Chat agent calls propose_persona; the tool submits one ProposePersona through Commands.Submit, in
/// the job of ChatAgent. The double recorded one command with origin tool, the session of the turn, the key <ItemId>:1 and the preset pirate. The model's second
/// request offers propose_persona and carries the answer: ok, outcome proposed, the double's message and the double's Ref. The reply is the scenario's text and no
/// fallback. Visual Trace shows the steps model, tool (Suggesting a persona) and model.
Method TestProposeThroughATurn()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn("Please talk like a pirate. [[mock:persona-propose]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock suggested the persona.") Quit
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Do ..AssertCall(calls.%Get(0), owner, request.ItemId_":1", "IdempotencyKey,Origin,Preset,SessionRef", "ProposePersona")
		Do $$$AssertEquals(calls.%Get(0).fields.Preset, "pirate", "with the preset that the model gave")
	}
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(1)), "cancel_reminder,check_status,dismiss_incident,documents,forget_memory,incident_summary,list_memories,list_productions,list_reminders,propose_fix,propose_persona,recent_activity,save_memory,search_memories,send_digest,send_email,set_reminder,start_watch,stop_watch", "the second request offers propose_persona with the other eighteen tools of Chat, send_digest (since Story 17.6), incident_summary (since Story 23.6) and propose_fix (since Story 23.2) among them")
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "and carries one tool result")
		If $ListLength(results) = 1 Do ..AssertObject($List(results, 1), ..Proposed(), "the model reads the answer of the owner")
	}
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "StepProblems", answer.DecisionRef, session, $ListBuild("Suggesting a persona"), $ListBuild("propose_persona"), "ChatAgent"), "", "the steps of the turn are right")
}

/// With the online demo on (AC6; scenario persona-propose), a real turn of the Chat agent that calls propose_persona gets not_available with the owner's own
/// message (CommandsIn MESSAGENOTALLOWED): the double records no command, the context's tool still ran (the tool answered), and the model's second request
/// carries exactly that answer and offers the tool. The setting is put back by OnAfterOneTest.
Method TestOnlineDemoThroughATurn()
{
	If '..Prepare() Quit
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1), "the online demo is on")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn("Please talk like a pirate. [[mock:persona-propose]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock suggested the persona.") Quit
	Do $$$AssertEquals(..Calls().%Size(), 0, "the double recorded no command")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Do $$$AssertTrue(","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(1))_"," [ ",propose_persona,", "the second request offers propose_persona")
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "and carries one tool result")
		If $ListLength(results) = 1 Do ..AssertObject($List(results, 1), {"ok": false, "outcome": "not_available", "message": ($Parameter("OcuTalon.Core.CommandsIn", "MESSAGENOTALLOWED"))}, "the model reads not_available with the owner's message")
	}
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "StepProblems", answer.DecisionRef, session, $ListBuild("Suggesting a persona"), $ListBuild("propose_persona"), "ChatAgent"), "", "the steps of the turn are right")
}

/// The owner's refusal in a real turn (AC4; scenario persona-propose): the double refuses ProposePersona with a message M, and the model's second request
/// carries {"ok": false, "outcome": "refused", "message": M} with no ref. The tool still submitted once, with origin tool, the turn's owner and the key
/// <ItemId>:1.
Method TestOwnerRefusalThroughATurn()
{
	If '..Prepare() Quit
	Set message = "That is not a persona OcuTalon has. Nothing was changed."
	Set ^OcuTalonTest("CommandsDouble", "refuse", "ProposePersona") = message
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn("Please talk like a pirate. [[mock:persona-propose]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock suggested the persona.") Quit
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 Do ..AssertCall(calls.%Get(0), owner, request.ItemId_":1", "IdempotencyKey,Origin,Preset,SessionRef", "ProposePersona")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
		If $ListLength(results) = 1 Do ..AssertObject($List(results, 1), {"ok": false, "outcome": "refused", "message": (message)}, "the model reads the owner's refusal, with no ref")
	}
}

/// An untrusted turn of the Chat agent (AC5; scenario persona-propose): the model calls propose_persona, the gate denies it with UNTRUSTED through AI Hub, the
/// method does not run and the double records no command, the turn has one denied tool step, and the model's second request carries the sentence of the
/// denial, not an answer of the owner.
Method TestUntrustedTurnDenied()
{
	If '..Prepare() Quit
	Set untrusted = $Parameter("OcuTalon.Bridge.Policy.Gate", "UNTRUSTED")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn("Please talk like a pirate. [[mock:persona-propose]]", owner, .request, .answer, .session, .requests, "untrusted")
	Do $$$AssertStatusOK(sc, "Decide answers the untrusted turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Set tools = []
	For poll = 0:1:40 {
		Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(answer.DecisionRef)
		Set tools = []
		Set iterator = steps.%GetIterator()
		While iterator.%GetNext(, .step) {
			If step.kind = "tool" Do tools.%Push(step)
		}
		If (tools.%Size() >= 1) && (steps.%Size() >= 3) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(tools.%Size(), 1, "the turn made one tool step")
	If tools.%Size() = 1 {
		Do $$$AssertEquals(tools.%Get(0).status, "denied", "the step is denied")
		Do $$$AssertTrue(tools.%Get(0).summary [ (". Denied: Tool access denied: "_$Extract(untrusted, 1, *-1)_". About "), "with UNTRUSTED after AI Hub's prefix: "_tools.%Get(0).summary)
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "the double recorded no command: the method did not run")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
		If $ListLength(results) = 1 {
			Do $$$AssertTrue($List(results, 1) [ untrusted, "which holds the sentence UNTRUSTED: "_$List(results, 1))
			Do $$$AssertTrue($List(results, 1) '[ "proposed", "and no proposal: "_$List(results, 1))
		}
	}
}

/// --- helpers ---
/// 1 when the production runs with every item in the CI override's environment, the entries of the runners are pointed at the mock key variable and the
/// double sits behind the CommandsIn item. Otherwise the test fails with the reason, and quits. The item and the entries are put back by OnAfterAllTests.
/// Today's day mark is removed first, so that no earlier class leaves the day capped.
Method Prepare() As %Boolean [ Private ]
{
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(fixture, "PointKeys")
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	If ..Swap = "" {
		Set sc = $ClassMethod(fixture, "UseItemClass", ..#ITEM, ..#DOUBLE, .saved)
		If $IsObject(saved) Set ..Swap = saved.%ToJSON()
		Do $$$AssertStatusOK(sc, "the double is put behind the "_..#ITEM_" item")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Begins a bridge context in the test process for a user turn of the owner with the ItemId, as the runner does before Chat.
Method Begin(owner As %String, itemId As %String) [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of '"_owner_"'")
}

/// Sends a turn of the owner (a user's unless the provenance is given) through Decide (RunnerFixture.Run) and reads the mock's log for it: request is the Request, answer the Reply, session the
/// session of the request and requests the entries of the mock's log for the turn, in order. The turn's ItemId is remembered for OnAfterOneTest.
Method Turn(text As %String, owner As %String, Output request As OcuTalon.Bridge.Msg.Request, Output answer As %Persistent, Output session As %Integer, Output requests As %DynamicArray, provenance As %String = "user") As %Status [ Private ]
{
	Set fixture = ..#FIXTURE
	Set request = $ClassMethod(fixture, "NewRequest", "turn", provenance, text, .ref, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session)
	Set requests = []
	If $$$ISOK($ClassMethod(..#MOCK, "LogSince", mark, .entries)) Set requests = $ClassMethod(fixture, "FindRequests", entries, ref)
	Quit sc
}

/// 1 when Decide answered the turn with a Reply whose text is the scenario's last reply, that is no fallback, whose Decision row is a normal one, and that says
/// that a tool ran. Otherwise the assertions fail and it is 0.
Method AssertTurn(sc As %Status, answer As %Persistent, request As OcuTalon.Bridge.Msg.Request, text As %String) As %Boolean [ Private ]
{
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit 0
	}
	Do $$$AssertEquals(answer.Text, text, "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Fallback_"|"_answer.FailureText, "0|", "and not a fallback")
	Do $$$AssertEquals(answer.ToolsRun, 1, "and it says that a tool ran")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "a Decision row of kind turn is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", "which is not a fallback")
	Quit $$$ISOK(sc) && ($IsObject(row))
}

/// The answer that the double gives a ProposePersona, as the model reads it: ok, outcome proposed, the double's message and its ref.
ClassMethod Proposed() As %DynamicObject [ Private ]
{
	Quit {"ok": true, "outcome": "proposed", "message": "The CI double raised the request.", "ref": ($Parameter(..#DOUBLE, "PROPOSEREF"))}
}

/// Asserts the record of one command of the double: a ProposePersona with origin tool, the session, the key and the names of its non-empty fields.
Method AssertCall(call As %DynamicObject, owner As %String, key As %String, names As %String, verb As %String) [ Private ]
{
	Do $$$AssertEquals(call.class, "OcuTalon.Msg.Command.ProposePersona", verb_": the command is a ProposePersona")
	Do $$$AssertEquals(call.origin, "tool", verb_": its origin is tool")
	Do $$$AssertEquals(call.sessionRef, owner, verb_": its SessionRef is the OwnerRef of the turn")
	Do $$$AssertEquals(call.key, key, verb_": its key is "_key)
	Do $$$AssertEquals(..SortedKeys(call.fields), names, verb_": it sets "_names_" and no other field")
}

/// Asserts that the answer (a dynamic object, or the JSON text that the model got) has the fields of the expected flat object with its values and types, and no
/// other. AI Hub writes the keys of an object in alphabetical order, so the order of the fields is not compared.
Method AssertObject(actual As %Any, expected As %DynamicObject, label As %String) [ Private ]
{
	If '$IsObject(actual) {
		Set text = actual
		Set actual = ""
		Try {
			Set actual = {}.%FromJSON(text)
		} Catch {
			Set actual = ""
		}
		If '$IsObject(actual) {
			Do $$$AssertTrue(0, label_": the result is a JSON object: "_$Extract(text, 1, 200))
			Quit
		}
	}
	Do $$$AssertEquals(..SortedKeys(actual), ..SortedKeys(expected), label_": the fields")
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do $$$AssertEquals(actual.%GetTypeOf(key), expected.%GetTypeOf(key), label_": "_key_" is a "_expected.%GetTypeOf(key))
		Do $$$AssertEquals(actual.%Get(key), value, label_": "_key_" is '"_value_"'")
	}
}

/// The commands that the double recorded, in order, as a dynamic array of {"class","origin","sessionRef","key","fields"}: fields is the JSON object of the
/// non-empty properties of the command.
ClassMethod Calls() As %DynamicArray [ Private ]
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("CommandsDouble", "calls", n))
		Quit:n=""
		Set call = ^OcuTalonTest("CommandsDouble", "calls", n)
		Do calls.%Push({"class": ($List(call, 1)), "origin": ($List(call, 2)), "sessionRef": ($List(call, 3)), "key": ($List(call, 4)), "fields": ({}.%FromJSON($List(call, 5)))})
	}
	Quit calls
}

/// The names of the keys of the object, sorted, comma-separated.
ClassMethod SortedKeys(object As %DynamicObject) As %String [ Private ]
{
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set sorted(key) = ""
	}
	Set names = ""
	Set key = ""
	For {
		Set key = $Order(sorted(key))
		Quit:key=""
		Set names = names _ $Select(names = "": "", 1: ",") _ key
	}
	Quit names
}

/// The items of a dynamic array of strings as a list.
ClassMethod Items(array As %DynamicArray) As %List [ Private ]
{
	Set list = ""
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .value) {
		Set list = list _ $ListBuild(value)
	}
	Quit list
}

}
