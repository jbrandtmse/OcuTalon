/// Tests of the Chat agent's reminder tools (Story 1.10; AD-1, AD-4, AD-7, AD-9, AD-10, AD-18, FR-34): set_reminder, list_reminders and
/// cancel_reminder, the toolset OcuTalon.Tools.Reminders and the helper OcuTalon.Tools.CommandCall. THE TESTS BUT TestDeclarations AND TestAnswerShapes RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL
/// and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fail with the reason where they do not have them. CommandsIn is a stub until Lane B's
/// Story 2.3, and ReminderOps until Epic 8, so the first test points the Config Store entry of each runner at the non-secret CI variable
/// OCUTALON_MOCK_KEY_HEADER (RunnerFixture.PointKeys) and puts the double Test.Tools.CommandsDouble behind the CommandsIn item (RunnerFixture.UseItemClass);
/// OnAfterAllTests puts the stub and the entries back, also after a failure. The double records every command it receives in
/// ^OcuTalonTest("CommandsDouble","calls") and answers from fixture Reminder rows the way ReminderOps will (the list contract). The live tests drive real
/// turns of the Chat agent through ApprovalStartIn and Decide (RunnerFixture.Run) against the CI mock, and read what the double received, what the model got
/// back (the tool_result blocks of the mock's log) and the steps of Visual Trace. The in-process tests begin a bridge context in the test process, as
/// Test.Tools.Result does, and call the tool methods. Every user turn has an owner of its own (a new Ref).
///   - TestDeclarations (AC1, AC2; no production needed): Chat's TOOLSETS is the toolset, which offers exactly the three names of Tools.Names, each once, from
///     ReminderTools; each tool's step label is its own class parameter, not the generic one; the classification parameters are the table of the spec; the
///     inputs are text, delaySeconds and localDueAt, none and reminderRefs, and none names a session, an owner or an origin; the toolset holds no Requirement;
///   - TestSetRelative (AC3, AC4, AC7): "Remind me in 1 minute to stretch." (reminder-set-relative) submits one SetReminder with origin tool, the session of the
///     turn, the key <ItemId>:1, Text and DelaySeconds 60 and no other field; the model's next request carries ok, message, ref, due and dueLocal; the reply is
///     the scenario's text; the steps are model, tool (Setting a reminder) and model, in the session of the decision; the Reminder table is unchanged;
///   - TestSetLocal (AC3, AC4): "Remind me Thursday at 10 ..." (reminder-set-local) from a user item rendered at a fixed Monday: the model's first message
///     starts with the preamble, and the command holds LocalDueAt and Text, no DelaySeconds and no DueAt;
///   - TestSetRefused (AC3): a refusal of the double reaches the model as {"ok": false, "message": the owner's}, with no ref and no due time;
///   - TestCancel and TestCancelRefused (AC5, AC7): the turn lists, then cancels by the Ref that the list gave: ListReminders with the key :1 and CancelReminder
///     with that ReminderRef and the key :2; the model reads the list and then the answer; a refusal reaches the model as {"ok": false, "message": ...} exactly,
///     the reply is a normal one and the tool step is ok;
///   - TestList and TestListInZone (AC6): only the session's pending reminders, the sooner first, with ref, text, due and dueLocal and the zone; in
///     America/New_York either side of the end of daylight-saving time the local times are 10:30; with a Data that no row holds, the tool returns that Data;
///   - TestListUnreadable (AC6): a Data that is not JSON, or has no reminders array, or has a reminder with no ref, an empty ref, no text, a text that is no string or a
///     due time that is not UTC to the second, or holds an entry that is no object, or holds a good reminder before a bad one, is a failure with one warning, never an
///     empty list or a half list, while {"reminders": []} is an empty list;
///   - TestListRefused (AC5, AC7): the owner's refusal of ListReminders reaches the model as {"ok": false, "message": the owner's}, with no warning;
///   - TestAnswerShapes (AC3): Answer leaves out the ref and the due times that the owner did not give or that Data.Time cannot read, and keeps ok and message;
///   - TestKeys (AC7): the same turn sent to ChatAgent twice submits the keys <ItemId>:1 and <ItemId>:2 in each round; the two calls of one response are two tool
///     steps in the runner's Reply (the steps that Decide sends to Visual Trace), each with its label (QA);
///   - TestNoSession, TestSubmitFails, TestSubmitEmpty, TestSubmitRedacted and TestBadDelay (AC8): no context, an owner that is not a session's Ref or an empty
///     ItemId submits nothing and answers NOSESSION; a failed submit, and a submit that is answered with no CommandResult, answer NOTSENT with one warning that
///     names the verb's class, whose status text has passed through the redactor; a delaySeconds that is not a whole number answers BADDELAY;
///   - TestSubmitKeepsTheJobSession (AC8; AD-1, AD-9): a tool's submit leaves the event-log session of the job as it was, answered or failed, so the warnings that
///     ChatAgent's job logs after a tool call stay in the decision's session (CommandsIn is a business service, and a business service clears the job's session).
/// Added by QA (Story 1.10), each pinning a row of the matrix that the tests above leave to a mutation that stays green:
///   - TestSetAnswerInZone (AC3): the due time that a set answers is in the instance zone (New York, and Auckland where the date changes too), not only a UTC time
///     with its Z cut off, which TestSetRelative cannot tell apart in the UTC of a throwaway;
///   - TestRefusalsAreUnchanged (AC3, AC5): a refusal of the owner reaches the model character for character when it holds quotes, a backslash, a tab, a line break,
///     white space at both ends, a non-ASCII character or 700 characters, for each of the three tools;
///   - TestToolsPassOnWhatTheModelGave (AC3, AC4): the tools are thin (decision 5): both due forms, none, an empty text, a day and time that cannot be read and a
///     ref that no reminder has all reach the owner as given, each field only when the model gave it;
///   - TestListKeepsTheOwnersOrder (AC6): the list is in the order of the owner's Data, which is neither the order of the due times nor of the refs nor of the texts;
///   - TestBadDelayThroughTheToolManager (AC8): a delaySeconds of 1.5, -5 or abc, given as AI Hub's tool manager decodes it, answers BADDELAY and submits nothing,
///     while 60 and an omitted one reach the owner, so a coercion by AI Hub would show.
/// Added by Story 11.8 (DW-140; AC1, AC3):
///   - TestCancelSeveral (AC1): cancel_reminder takes reminderRefs and submits one CancelReminder for each ref, in order, with the keys of the next positions;
///     one refused (refuseRef of the double) does not stop the others and stays in its entry; one ref, as a list or as a string, keeps the flat answer; a failed
///     submit answers NOTSENT in each entry with one warning each; a ref given twice is submitted twice;
///   - TestCancelThroughTheToolManager (AC3): a JSON array and a JSON string reach the method as AI Hub's tool manager decodes them, the bad shapes answer BADREFS
///     and record nothing, and a call outside a session's turn answers NOSESSION first.
/// The steps of every live test are checked by RunnerFixture.StepProblems (DW-316).
/// The tests of the cancel and the list also compare the whole Reminder table before and after the turn (a tool that updates a row is caught, not only one that adds).
/// OnAfterOneTest and OnAfterAllTests put back what a test made, also when it failed: the fixture Reminder rows (by Ref), ^OcuTalonTest("CommandsDouble"), the
/// Decision, Usage and AgentStep rows of the turns (by ItemId), the AI sessions the turns saved with their links, the context, the process zone (the base class
/// ZoneCase), the CommandsIn item (RestoreItemClass) and the keys of the runners (RestoreKeys). OnAfterAllTests returns the status of those two restores, and an
/// error when a new service of the CommandsIn item is not of the class that the item had or when an entry of a runner does not hold the placeholder of the
/// Provider step (RunnerFixture.KeysAre), so a restore that did not happen fails the class.
Class OcuTalon.Test.Tools.Reminders Extends OcuTalon.Test.Bridge.ZoneCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The test double of CommandsIn.
Parameter DOUBLE = "OcuTalon.Test.Tools.CommandsDouble";

/// The production item that the double sits behind.
Parameter ITEM = "CommandsIn";

/// The runner of the Chat agent.
Parameter RUNNER = "ChatAgent";

Parameter TOOLS = "OcuTalon.Tools.ReminderTools";

Parameter TOOLSET = "OcuTalon.Tools.Reminders";

/// The helper that submits the commands, which holds the texts for the model.
Parameter CALL = "OcuTalon.Tools.CommandCall";

/// The Ref of the reminder that the scenario reminder-cancel cancels.
Parameter CANCELREF = "zzReminderStretch00001";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// What the CommandsIn item had before the double was put behind it (RunnerFixture.UseItemClass), as the JSON text it gave, or "" while the double is not
/// behind it. A text, because an object property of this class would read as a new empty object when it is unset.
Property Swap As %String(MAXLEN = "");

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the turns that the test made.
Property ItemIds As %List;

/// The Refs of the Reminder rows that the test saved.
Property Rows As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Set position = 0
	While $ListNext(..Rows, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Reminder WHERE Ref = ?", ref)
	}
	Set ..Rows = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Quit sc
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

/// The declarations (AC1, AC2). Chat's TOOLSETS names the reminder toolset, whose discovery lists exactly set_reminder, list_reminders and cancel_reminder
/// (the names of Tools.Names), each once, with ReminderTools as the provider, and ReminderTools offers its three methods and none of Result's. Each tool's
/// step label is the class parameter STEPLABEL<NAME>, not the generic label. The classification parameters are set and cancel: safe, not read-only,
/// trusted output (their answers are built by code, so two calls in one response both run and nothing taints the turn: DW-136); list: safe, read-only,
/// trusted output (DW-139). The inputs are text, delaySeconds and localDueAt for set (text required), none for list and
/// reminderRefs for cancel (required, an array of strings), and none names a session, an owner or an origin. The descriptions tell the model the two due forms and that
/// cancel takes the ref that list gave, and none starts with an SQL verb. The toolset holds no Requirement element, and each method returns a dynamic object.
Method TestDeclarations()
{
	Set names = "OcuTalon.Tools.Names"
	Do $$$AssertTrue(..StartsWithSqlVerb("  delete the reminders"), "control: a text that starts with an SQL verb is flagged")
	Do $$$AssertNotTrue(..StartsWithSqlVerb("Sets a reminder, then deletes nothing"), "and one that does not start with one is not")
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Chat", "TOOLSETS"), ..#TOOLSET_",OcuTalon.Tools.Watching", "Chat's TOOLSETS is "_..#TOOLSET_" and, since Story 5.1, OcuTalon.Tools.Watching")
	Set expected = $ListBuild($Parameter(names, "SETREMINDER"), $Parameter(names, "LISTREMINDERS"), $Parameter(names, "CANCELREMINDER"))
	Set want("set_reminder") = $ListBuild("safe", 0, 1, "Setting a reminder", "delaySeconds,localDueAt,text", "text")
	Set want("list_reminders") = $ListBuild("safe", 1, 1, "Listing your reminders", "", "")
	Set want("cancel_reminder") = $ListBuild("safe", 0, 1, "Cancelling a reminder", "reminderRefs", "reminderRefs")
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Do $$$AssertEquals(tools.%Size(), 3, "the toolset offers three tools")
	Set found = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set found = found _ $ListBuild(tool.name)
		Set name = tool.name
		Do $$$AssertEquals(tool.provider, ..#TOOLS, name_" is a method of "_..#TOOLS)
		If '$Data(want(name)) {
			Do $$$AssertTrue(0, name_" is not one of the three tools")
			Continue
		}
		Set upper = $ZConvert($Translate(name, "_-"), "U")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, name), $List(want(name), 4), name_" has its own step label")
		Do $$$AssertNotEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, name), ##class(OcuTalon.Bridge.Adapter.StepBuffer).#GENERICLABEL, name_" does not have the generic label")
		Do $$$AssertEquals($Parameter(tool.provider, "STEPLABEL"_upper), $List(want(name), 4), name_"'s label is the class parameter STEPLABEL"_upper)
		Do $$$AssertEquals($Parameter(tool.provider, "CLASSIFICATION"_upper), $List(want(name), 1), name_" is classified "_$List(want(name), 1))
		Do $$$AssertEquals($Parameter(tool.provider, "READONLY"_upper), $List(want(name), 2), name_" has READONLY "_$List(want(name), 2))
		Do $$$AssertEquals($Parameter(tool.provider, "TRUSTEDOUTPUT"_upper), $List(want(name), 3), name_" has TRUSTEDOUTPUT "_$List(want(name), 3))
		Set inputs = ..SortedKeys(tool.parameters.properties)
		Do $$$AssertEquals(inputs, $List(want(name), 5), name_" takes the inputs '"_$List(want(name), 5)_"'")
		Do $$$AssertEquals($ListToString(..Items(tool.parameters.required)), $List(want(name), 6), name_" requires '"_$List(want(name), 6)_"'")
		If name = "set_reminder" Do $$$AssertEquals(tool.parameters.properties.delaySeconds.type, "integer", "set_reminder's delaySeconds is an integer in the schema, so the model is asked for a whole number")
		If name = "cancel_reminder" {
			Do $$$AssertEquals(tool.parameters.properties.reminderRefs.type, "array", "cancel_reminder's reminderRefs is an array in the schema, so the model is asked for a list of refs")
			Do $$$AssertEquals(tool.parameters.properties.reminderRefs.items.type, "string", "whose items are strings")
		}
		For input = 1:1:$Length(inputs, ",") {
			Set one = $Piece(inputs, ",", input)
			If one = "" Continue
			Do $$$AssertTrue(tool.parameters.properties.%Get(one).description '= "", name_"'s input "_one_" has a description for the model")
			Do $$$AssertNotTrue(..StartsWithSqlVerb(tool.parameters.properties.%Get(one).description), name_"'s input "_one_" does not start with an SQL verb")
			For forbidden = "session", "owner", "origin" {
				Do $$$AssertNotTrue($ZConvert(one, "L") [ forbidden, name_"'s input "_one_" does not name a "_forbidden)
			}
		}
		Do $$$AssertNotTrue(..StartsWithSqlVerb(tool.description), name_"'s description does not start with an SQL verb")
		Do $$$AssertEquals(tool.metadata."origin_class", ..#TOOLS, name_" says that it originates in "_..#TOOLS)
	}
	Set position = 0
	While $ListNext(expected, position, name) {
		Set seen = 0
		Set at = 0
		While $ListNext(found, at, discovered) {
			If discovered = name Set seen = seen + 1
		}
		Do $$$AssertEquals(seen, 1, name_" is offered once")
	}
	Do $$$AssertEquals($ListLength(found), $ListLength(expected), "and nothing else is offered")

	Set own = $ClassMethod(..#TOOLS, "%New").%Discover().tools
	Set ownNames = ""
	Set iterator = own.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set ownNames = ownNames _ $ListBuild(tool.name)
	}
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Agent.Runners).Sorted(ownNames)), "CancelReminder,ListReminders,SetReminder", ..#TOOLS_" offers its three methods and none of Result's")
	For method = "SetReminder", "ListReminders", "CancelReminder" {
		Set return = ##class(%Dictionary.CompiledMethod).%OpenId(..#TOOLS_"||"_method).ReturnType
		Do $$$AssertTrue(return [ "DynamicObject", method_" returns a dynamic object: "_return)
	}
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set descriptions(tool.name) = tool.description
	}
	Do $$$AssertTrue(descriptions("set_reminder") [ "delaySeconds", "the description of set_reminder names delaySeconds, for a relative time")
	Do $$$AssertTrue(descriptions("set_reminder") [ "localDueAt", "and localDueAt, for a day and time")
	Do $$$AssertTrue(descriptions("set_reminder") [ "Local time", "which is worked out from the Local time line of the message")
	Do $$$AssertTrue(descriptions("cancel_reminder") [ "list_reminders", "the description of cancel_reminder says that it takes the ref that list_reminders gave")
	Do $$$AssertTrue(descriptions("cancel_reminder") [ "all in this one call", "and that every ref goes in one call")
	Set definition = ##class(%Dictionary.XDataDefinition).%OpenId(..#TOOLSET_"||Definition")
	Set xml = $Select($IsObject(definition): definition.Data.Read(32000), 1: "")
	Do $$$AssertTrue(xml '= "", "the toolset has its Definition")
	Do $$$AssertTrue(xml '[ "Requirement", "and holds no Requirement element: the class parameters are the one declaration")
	Do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%OpenId(..#TOOLSET).DependsOn, ..#TOOLS, "and it depends on the tool class")
}

/// "Remind me in 1 minute to stretch." (AC3, AC4, AC7; scenario reminder-set-relative). The Chat agent calls set_reminder; the tool submits one SetReminder through
/// Commands.Submit, in the job of ChatAgent. The double recorded one command with origin tool, the session of the turn (the OwnerRef), the key <ItemId>:1,
/// Text stretch and DelaySeconds 60, and no other field (no DueAt, no LocalDueAt). The model's second request carries ok, message, ref, due and dueLocal,
/// with the times of Data.Time for the double's due time and none in UTC. The reply is the scenario's text and no fallback. Visual Trace shows the steps model,
/// tool (Setting a reminder, whose summary names set_reminder, status ok) and model, all in the session of the decision. The Reminder table has the same
/// number of rows.
Method TestSetRelative()
{
	If '..Prepare() Quit
	Set before = ..ReminderCount()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn("Remind me in 1 minute to stretch. [[mock:reminder-set-relative]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock set the reminder.") Quit
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.SetReminder", owner, request.ItemId_":1", "DelaySeconds,IdempotencyKey,Origin,SessionRef,Text", "SetReminder")
		Set fields = calls.%Get(0).fields
		Do $$$AssertEquals(fields.Text_"|"_fields.DelaySeconds, "stretch|60", "with the text and the delay that the model gave")
	}
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(1)), "cancel_reminder,check_status,dismiss_incident,list_productions,list_reminders,set_reminder,start_watch,stop_watch", "the second request offers the three reminder tools and, since Stories 5.1, 5.9 and 5.7, the five watching tools")
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "and carries one tool result")
		If $ListLength(results) = 1 Do ..AssertObject($List(results, 1), ..SetAnswer(), "the model reads the answer of the owner")
		If $ListLength(results) = 1 Do $$$AssertTrue($List(results, 1) '[ "2027-03-04T15:00:00Z", "and never the UTC time")
	}
	Do ..AssertSteps(answer, session, $ListBuild("Setting a reminder"), $ListBuild("set_reminder"))
	Do $$$AssertEquals(..ReminderCount(), before, "the tool wrote no Reminder row")
}

/// "Remind me Thursday at 10 to load the new certificate." (AC3, AC4; scenario reminder-set-local). The input is rendered by Agent.Input.Render for a user item at a
/// fixed Monday, so the first message of the first request starts with the preamble line, which states the local time and the zone. The mock's tool call gives the
/// local date and time, and the double recorded a SetReminder with LocalDueAt 2026-10-29T10:00:00 and Text, and no DelaySeconds and no DueAt.
Method TestSetLocal()
{
	If '..Prepare() Quit
	Set now = "2026-10-26T14:00:00Z"
	Do $SYSTEM.Process.TimeZone("")
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.Provenance = "user"
	Set item.Text = "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-set-local]]"
	Set input = ##class(OcuTalon.Agent.Input).Render(item, now)
	Set preamble = ##class(OcuTalon.Agent.Input).Preamble(now)
	Do $$$AssertTrue($Extract(preamble, 1, 12) = "Local time: ", "control: the preamble states the local time: "_preamble)
	Do $$$AssertEquals($Piece(preamble, " (time zone ", 1), "Local time: Monday 2026-10-26 14:00", "control: it names the weekday, the local date and the time that Thursday at 10 is worked out from")
	Do $$$AssertTrue(preamble [ " (time zone ", "and the zone: "_preamble)
	Set monday = $ZDateH($Piece(preamble, " ", 4), 3)
	Set thursday = $ZDate(monday + ((4 - $ZDate(monday, 10)) # 7), 3)
	Do $$$AssertTrue($Extract(input, 1, $Length(preamble)) = preamble, "control: the rendered input starts with it")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Turn(input, owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock set the reminder.") Quit
	Do $$$AssertTrue(requests.%Size() > 0, "the mock logged the requests of the turn: "_requests.%Size())
	If requests.%Size() > 0 {
		Set first = $Piece(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(requests.%Get(0)), $Char(1), 1)
		Do $$$AssertEquals($Extract(first, 1, $Length(preamble) + 5), "user:"_preamble, "the model's first message starts with the preamble line")
	}
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.SetReminder", owner, request.ItemId_":1", "IdempotencyKey,LocalDueAt,Origin,SessionRef,Text", "SetReminder")
		Set fields = calls.%Get(0).fields
		Do $$$AssertEquals(fields.LocalDueAt_"|"_fields.Text, "2026-10-29T10:00:00|load the new certificate", "with the local date and time and the text that the model gave")
		Do $$$AssertEquals(fields.LocalDueAt, thursday_"T10:00:00", "which is the Thursday after the Monday of the preamble, at 10, in the form YYYY-MM-DDThh:mm:ss with no zone")
	}
}

/// A refusal of the owner (AC3). The double refuses SetReminder with a message. The tool, called in process under the context of owner A, answers exactly
/// {"ok": false, "message": the double's message}: no ref and no due time. The command carried the session of the context.
Method TestSetRefused()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("CommandsDouble", "refuse", "SetReminder") = "That time has already passed."
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 0)
	Do ..AssertObject(answer, {"ok": false, "message": "That time has already passed."}, "the refusal reaches the model")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded the command")
	If calls.%Size() = 1 Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.SetReminder", owner, itemId_":1", "DelaySeconds,IdempotencyKey,Origin,SessionRef,Text", "SetReminder")
}

/// "Cancel my reminder to stretch." (AC5, AC7; scenario reminder-cancel). Owner A has the pending reminder zzReminderStretch00001. The model lists, then cancels by
/// the Ref that the list gave. The double recorded ListReminders with the key <ItemId>:1 and CancelReminder with that ReminderRef and the key :2. Request 2
/// carries the list with that row, and request 3 carries the answer to the cancel. Visual Trace shows Listing your reminders and Cancelling a reminder.
Method TestCancel()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..AddReminder(owner, ..#CANCELREF, "stretch", "2027-03-04T15:00:00Z", "pending")
	Set rows = ..RowsText()
	Set sc = ..Turn("Cancel my reminder to stretch. [[mock:reminder-cancel]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock cancelled the reminder.") Quit
	Do $$$AssertTrue(..RowsText() = rows, "the tools wrote and changed no Reminder row: the pending reminder is still pending, for the owner to cancel")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded two commands")
	If calls.%Size() = 2 {
		Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.ListReminders", owner, request.ItemId_":1", "IdempotencyKey,Origin,SessionRef", "ListReminders")
		Do ..AssertCall(calls.%Get(1), "OcuTalon.Msg.Command.CancelReminder", owner, request.ItemId_":2", "IdempotencyKey,Origin,ReminderRef,SessionRef", "CancelReminder")
		Do $$$AssertEquals(calls.%Get(1).fields.ReminderRef, ..#CANCELREF, "the cancel names the Ref that the list gave")
	}
	Do $$$AssertEquals(requests.%Size(), 3, "the mock logged three requests")
	If requests.%Size() = 3 {
		Set second = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(second), 1, "request 2 carries the list")
		If $ListLength(second) = 1 Do ..AssertListed($List(second, 1), $ListBuild($ListBuild(..#CANCELREF, "stretch", "2027-03-04T15:00:00Z")), "the list of request 2")
		Set third = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(2))
		Do $$$AssertEquals($ListLength(third), 2, "request 3 carries the list and the answer to the cancel")
		If $ListLength(third) = 2 {
			Do $$$AssertEquals($List(third, 1), $List(second, 1), "the list is as it was")
			Do ..AssertObject($List(third, 2), {"ok": true, "message": "The CI double cancelled the reminder.", "ref": (..#CANCELREF)}, "the model reads the answer to the cancel")
		}
	}
	Do ..AssertSteps(answer, session, $ListBuild("Listing your reminders", "Cancelling a reminder"), $ListBuild("list_reminders", "cancel_reminder"))
}

/// A cancel that the owner refuses (AC5, AC7). The same turn as TestCancel, with the double refusing CancelReminder with "That reminder has already fired." Request
/// 3 carries exactly {"ok": false, "message": "That reminder has already fired."} as the answer to the cancel. The reply is the scenario's text, a normal
/// reply (its Decision is not a fallback), and both tool steps are ok.
Method TestCancelRefused()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..AddReminder(owner, ..#CANCELREF, "stretch", "2027-03-04T15:00:00Z", "pending")
	Set ^OcuTalonTest("CommandsDouble", "refuse", "CancelReminder") = "That reminder has already fired."
	Set rows = ..RowsText()
	Set sc = ..Turn("Cancel my reminder to stretch. [[mock:reminder-cancel]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock cancelled the reminder.") Quit
	Do $$$AssertTrue(..RowsText() = rows, "the tools wrote and changed no Reminder row")
	Do $$$AssertEquals(requests.%Size(), 3, "the mock logged three requests")
	If requests.%Size() = 3 {
		Set third = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(2))
		Do $$$AssertEquals($ListLength(third), 2, "request 3 carries the list and the answer to the cancel")
		If $ListLength(third) = 2 Do ..AssertObject($List(third, 2), {"ok": false, "message": "That reminder has already fired."}, "the model reads the owner's reason, unchanged")
	}
	Do ..AssertSteps(answer, session, $ListBuild("Listing your reminders", "Cancelling a reminder"), $ListBuild("list_reminders", "cancel_reminder"))
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded the list and the cancel")
}

/// Several refs in one cancel_reminder call (AC1; DW-140, U-118), in process. Each case is a session's turn of its own.
///   - Three refs: three CancelReminder commands in the order of the refs, each with origin tool, the session, and the keys :1, :2 and :3; the answer is
///     {"ok": true, "results": [one answer for each ref, with its ref]};
///   - the owner refuses the second (refuseRef): the first and the third are still submitted, the second's entry is {"ok": false, "message": the owner's, "ref"}
///     and the top ok is false;
///   - one ref, as a one-element list and as the string: one command, and the flat answer of a single cancel, with no results;
///   - a failed submit of two refs: both are recorded, both entries are {"ok": false, "message": NOTSENT, "ref"}, with one warning each;
///   - a ref given twice is submitted twice, each with its own key, and the tool does not dedupe.
Method TestCancelSeveral()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set r1 = ..RefOf("Sev1")
	Set r2 = ..RefOf("Sev2")
	Set r3 = ..RefOf("Sev3")
	Set done = "The CI double cancelled the reminder."
	Set verb = "OcuTalon.Msg.Command.CancelReminder"
	Set names = "IdempotencyKey,Origin,ReminderRef,SessionRef"

	Set itemId = ..Fresh(owner)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1), (r2), (r3)])
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 3, "three refs: the double recorded three commands")
	If calls.%Size() = 3 {
		For i = 0:1:2 {
			Do ..AssertCall(calls.%Get(i), verb, owner, itemId_":"_(i + 1), names, "cancel "_(i + 1))
			Do $$$AssertEquals(calls.%Get(i).fields.ReminderRef, $Case(i, 0: r1, 1: r2, :r3), "cancel "_(i + 1)_" names ref "_(i + 1)_", in the order given")
		}
	}
	Do ..AssertResults(answer, [{"ok": true, "message": (done), "ref": (r1)}, {"ok": true, "message": (done), "ref": (r2)}, {"ok": true, "message": (done), "ref": (r3)}], "three refs")

	Set itemId = ..Fresh(owner)
	Set ^OcuTalonTest("CommandsDouble", "refuseRef", r2) = "That reminder has already fired."
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1), (r2), (r3)])
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 3, "one refused: R1 and R3 are still submitted, three commands")
	If calls.%Size() = 3 Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key_"|"_calls.%Get(2).key, itemId_":1|"_itemId_":2|"_itemId_":3", "with the keys of their positions")
	Do ..AssertResults(answer, [{"ok": true, "message": (done), "ref": (r1)}, {"ok": false, "message": "That reminder has already fired.", "ref": (r2)}, {"ok": true, "message": (done), "ref": (r3)}], "one refused")
	Do $$$AssertEquals(answer.ok, 0, "and the top ok is false")

	Set itemId = ..Fresh(owner)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1)])
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "one ref in a list: one command")
	If calls.%Size() = 1 Do ..AssertCall(calls.%Get(0), verb, owner, itemId_":1", names, "cancel")
	Do ..AssertObject(answer, {"ok": true, "message": (done), "ref": (r1)}, "one ref in a list answers the flat answer")
	Set itemId = ..Fresh(owner)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder(r1)
	Do $$$AssertEquals(..Calls().%Size(), 1, "one ref as a string: one command")
	Do ..AssertObject(answer, {"ok": true, "message": (done), "ref": (r1)}, "and the flat answer")
	Set itemId = ..Fresh(owner)
	Set ^OcuTalonTest("CommandsDouble", "refuseRef", r1) = "That reminder has already fired."
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1)])
	Do ..AssertObject(answer, {"ok": false, "message": "That reminder has already fired."}, "one ref that the owner refuses answers the owner's refusal, with no ref and no results")

	Set itemId = ..Fresh(owner)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1), (r1)])
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "a ref given twice: the tool submits it twice")
	If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key, itemId_":1|"_itemId_":2", "each with its own key")
	Do ..AssertResults(answer, [{"ok": true, "message": (done), "ref": (r1)}, {"ok": true, "message": (done), "ref": (r1)}], "a ref given twice")

	Set itemId = ..Fresh(owner)
	Set ^OcuTalonTest("CommandsDouble", "fail") = 1
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder([(r1), (r2)])
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "failed submit: the double recorded both commands")
	If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key, itemId_":1|"_itemId_":2", "with the keys :1 and :2")
	Set notsent = $Parameter(..#CALL, "NOTSENT")
	Do ..AssertResults(answer, [{"ok": false, "message": (notsent), "ref": (r1)}, {"ok": false, "message": (notsent), "ref": (r2)}], "a failed submit")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild(verb, "The CI double was set to fail")), 2, "with one warning of Run for each ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 2, "and no other warning of "_..#CALL)
}

/// cancel_reminder through AI Hub's tool manager (AC3; DW-140), in process (a fresh %AI.ToolMgr, as TestBadDelayThroughTheToolManager does). A JSON
/// {"reminderRefs": [R1, R2]} gives two commands, keys :1 and :2, and the several-ref answer; {"reminderRefs": "R3"} gives one command and the flat answer;
/// each bad shape (reminderRefs left out, [], {}, "", null, and a list with a 5, an {} or a null in it) answers BADREFS and records nothing; and a call
/// outside a session's turn answers NOSESSION whatever its arguments.
Method TestCancelThroughTheToolManager()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set r1 = ..RefOf("Mgr1")
	Set r2 = ..RefOf("Mgr2")
	Set r3 = ..RefOf("Mgr3")
	Set done = "The CI double cancelled the reminder."
	Set manager = ##class(%AI.ToolMgr).%New()
	Do $$$AssertStatusOK(manager.RegisterToolSet(..#TOOLSET), "a fresh tool manager registers the reminder toolset")
	Do manager.%Discover()
	Set itemId = ..Fresh(owner)
	Set result = manager.ExecuteTool("cancel_reminder", {}.%FromJSON("{""reminderRefs"":[""" _ r1 _ """,""" _ r2 _ """]}"))
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "a JSON array of two refs: two commands")
	If calls.%Size() = 2 {
		Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.CancelReminder", owner, itemId_":1", "IdempotencyKey,Origin,ReminderRef,SessionRef", "the first")
		Do ..AssertCall(calls.%Get(1), "OcuTalon.Msg.Command.CancelReminder", owner, itemId_":2", "IdempotencyKey,Origin,ReminderRef,SessionRef", "the second")
		Do $$$AssertEquals(calls.%Get(0).fields.ReminderRef_"|"_calls.%Get(1).fields.ReminderRef, r1_"|"_r2, "for the refs in order")
	}
	Do ..AssertResults(result.value, [{"ok": true, "message": (done), "ref": (r1)}, {"ok": true, "message": (done), "ref": (r2)}], "the answer of a JSON array")
	Set itemId = ..Fresh(owner)
	Set result = manager.ExecuteTool("cancel_reminder", {}.%FromJSON("{""reminderRefs"":""" _ r3 _ """}"))
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "a JSON string: one command")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(0).fields.ReminderRef, itemId_":1|"_r3, "with the key :1 and the ref")
	Do ..AssertObject(result.value, {"ok": true, "message": (done), "ref": (r3)}, "and the flat answer")
	Set itemId = ..Fresh(owner)
	Do manager.ExecuteTool("cancel_reminder", {}.%FromJSON("{""reminderRefs"":[""""]}"))
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "a list holding an empty string holds a string: it goes to the owner as one command")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(0).fields.ReminderRef, itemId_":1|", "with the key :1 and an empty ref")

	Set itemId = ..Fresh(owner)
	Set badrefs = $Parameter(..#TOOLS, "BADREFS")
	For json = "{}", "{""reminderRefs"":[]}", "{""reminderRefs"":{}}", "{""reminderRefs"":""""}", "{""reminderRefs"":null}", "{""reminderRefs"":[5]}", "{""reminderRefs"":[{}]}", "{""reminderRefs"":[null]}", "{""reminderRefs"":[""a"",5]}", "{""reminderRefs"":[true]}" {
		Set result = manager.ExecuteTool("cancel_reminder", {}.%FromJSON(json))
		Do ..AssertObject(result.value, {"ok": false, "message": (badrefs)}, json_" answers BADREFS")
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "and the double recorded nothing")

	Do ##class(OcuTalon.Bridge.Context).End()
	Set result = manager.ExecuteTool("cancel_reminder", {}.%FromJSON("{""reminderRefs"":[""" _ r1 _ """]}"))
	Do ..AssertObject(result.value, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, "with no session's turn, a good call answers NOSESSION")
	Set result = manager.ExecuteTool("cancel_reminder", {})
	Do ..AssertObject(result.value, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, "and so does a bad one, before the refs are read")
	Do $$$AssertEquals(..Calls().%Size(), 0, "and nothing is submitted")
	Do manager.Cleanup()
}

/// "Which reminders do I have?" (AC6; scenario reminder-list). Owner A has two pending reminders (due 2027-03-04T15:00:00Z and, sooner, 2027-03-02T09:00:00Z),
/// a fired one and a cancelled one; owner B has a pending one. The double answers from the table the way ReminderOps will. The tool submitted ListReminders
/// with no field of its own. Request 2 carries A's two pending reminders only, the sooner first, each with its ref, its text, its due time from Data.Time.ForMessage
/// and its local time from Data.Time.ToLocal, and the instance zone.
Method TestList()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set late = ..RefOf("ListLate"), soon = ..RefOf("ListSoon")
	Do ..AddReminder(owner, late, "renew the licence", "2027-03-04T15:00:00Z", "pending")
	Do ..AddReminder(owner, soon, "call the vendor", "2027-03-02T09:00:00Z", "pending")
	Do ..AddReminder(owner, ..RefOf("ListFired"), "an old one", "2027-03-01T09:00:00Z", "fired")
	Do ..AddReminder(owner, ..RefOf("ListCancelled"), "a dropped one", "2027-03-03T09:00:00Z", "cancelled")
	Do ..AddReminder(other, ..RefOf("ListOther"), "someone else's", "2027-03-02T08:00:00Z", "pending")
	Set rows = ..RowsText()
	Set sc = ..Turn("Which reminders do I have? [[mock:reminder-list]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock listed the reminders.") Quit
	Do $$$AssertTrue(..RowsText() = rows, "the list tool wrote and changed no Reminder row")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.ListReminders", owner, request.ItemId_":1", "IdempotencyKey,Origin,SessionRef", "ListReminders")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests")
	If requests.%Size() = 2 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "request 2 carries one tool result")
		If $ListLength(results) = 1 {
			Do ..AssertListed($List(results, 1), $ListBuild($ListBuild(soon, "call the vendor", "2027-03-02T09:00:00Z"), $ListBuild(late, "renew the licence", "2027-03-04T15:00:00Z")), "A's pending reminders, the sooner first")
			Do $$$AssertTrue(($List(results, 1) '[ "someone else's") && ($List(results, 1) '[ "an old one") && ($List(results, 1) '[ "a dropped one"), "and nothing of B's, nor the fired or the cancelled one")
		}
	}
	Do ..AssertSteps(answer, session, $ListBuild("Listing your reminders"), $ListBuild("list_reminders"))
}

/// The list in a zone (AC6), in process. In America/New_York, owner A's pending reminders due 2026-10-31T14:30:00Z and 2026-11-02T15:30:00Z (either side of the
/// end of daylight-saving time, 2026-11-01) are both 10:30 local, and the zone is America/New_York. With the double's data mode set to a reminder that no row
/// holds, the tool returns exactly that reminder, so it reads the Data and never the table.
Method TestListInZone()
{
	If '..Prepare() Quit
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set first = ..RefOf("ZoneBefore"), second = ..RefOf("ZoneAfter")
	Do ..AddReminder(owner, first, "before the change", "2026-10-31T14:30:00Z", "pending")
	Do ..AddReminder(owner, second, "after the change", "2026-11-02T15:30:00Z", "pending")
	Do ..Begin(owner, itemId)
	Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do $$$AssertEquals(answer.zone, "America/New_York", "the zone is the instance zone")
	Do ..AssertListedObject(answer, $ListBuild($ListBuild(first, "before the change", "2026-10-31T14:30:00Z", "2026-10-31T10:30:00"), $ListBuild(second, "after the change", "2026-11-02T15:30:00Z", "2026-11-02T10:30:00")), "the reminders either side of the change")

	Set ^OcuTalonTest("CommandsDouble", "data") = "{""reminders"":[{""ref"":"""_..RefOf("ZoneNoRow")_""",""text"":""from the double"",""dueAt"":""2026-12-01T15:30:00Z""}]}"
	Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do ..AssertListedObject(answer, $ListBuild($ListBuild(..RefOf("ZoneNoRow"), "from the double", "2026-12-01T15:30:00Z", "2026-12-01T10:30:00")), "with a Data that no row holds, exactly that reminder")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded both lists")
}

/// A list that cannot be read (AC6), in process. A Data that is not JSON, one without a reminders array, one with a reminder that has no ref, an empty ref, no text
/// or a text that is no string, one with a due time that is not a time or that is not UTC to the second (no Z), one with an entry that is no object and one with a
/// good reminder before a bad one each answer {"ok": false, "message": NOTREAD} and log one warning of Listed: never an empty list. A Data of an empty reminders
/// array is an empty list, which says that none is pending.
Method TestListUnreadable()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set good = "{""ref"":""zzReminderGoodOne00001"",""text"":""ok"",""dueAt"":""2027-03-04T15:00:00Z""}"
	Set bad = $ListBuild("not json", "{""items"":[]}", "", "{""reminders"":[{""text"":""no ref"",""dueAt"":""2027-03-04T15:00:00Z""}]}", "{""reminders"":[{""ref"":""zzReminderBadDue000001"",""text"":""x"",""dueAt"":""soon""}]}", "{""reminders"":""none""}",
		"{""reminders"":[{""ref"":""zzReminderNoText000001"",""dueAt"":""2027-03-04T15:00:00Z""}]}",
		"{""reminders"":[""not an object""]}",
		"{""reminders"":["_good_",{""ref"":""zzReminderNoText000001"",""dueAt"":""2027-03-04T15:00:00Z""}]}",
		"{""reminders"":[{""ref"":"""",""text"":""x"",""dueAt"":""2027-03-04T15:00:00Z""}]}",
		"{""reminders"":[{""ref"":""zzReminderNumText00001"",""text"":5,""dueAt"":""2027-03-04T15:00:00Z""}]}",
		"{""reminders"":[{""ref"":""zzReminderNoZone000001"",""text"":""x"",""dueAt"":""2027-03-04T15:00:00""}]}")
	Set position = 0
	While $ListNext(bad, position, data) {
		Set ^OcuTalonTest("CommandsDouble", "data") = data
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTREAD"))}, "a Data of '"_$Extract(data, 1, 40)_"' is not read")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Listed"), 1, "and one warning of Listed is logged")
	}
	Set ^OcuTalonTest("CommandsDouble", "data") = "{""reminders"":[]}"
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do ..AssertListedObject(answer, "", "a Data of an empty reminders array is an empty list")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 0, "which logs no warning")
}

/// A list that the owner refuses (AC5, AC7), in process. The double refuses ListReminders with a message. The tool answers exactly {"ok": false, "message": the owner's},
/// with no reminders and no zone: a refusal is the owner's answer and no unreadable list, so no warning is logged.
Method TestListRefused()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set ^OcuTalonTest("CommandsDouble", "refuse", "ListReminders") = "Your reminders cannot be listed right now."
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do ..AssertObject(answer, {"ok": false, "message": "Your reminders cannot be listed right now."}, "the owner's refusal reaches the model")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 0, "and logs no warning")
	Do $$$AssertEquals(..Calls().%Size(), 1, "the double recorded the command")
}

/// The shape of the model's answer to a command (AC3), in process: ok (a boolean) and the owner's message always; the ref only when the owner gave one; the two due
/// times only when the owner gave a due time that Data.Time can read, so that no empty string reaches the model.
Method TestAnswerShapes()
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 1
	Set result.Message = "Done."
	Set result.Ref = "zzReminderShape0000001"
	Set result.DueAt = "soon"
	Do ..AssertObject(##class(OcuTalon.Tools.CommandCall).Answer(result), {"ok": true, "message": "Done.", "ref": "zzReminderShape0000001"}, "a due time that cannot be read leaves out due and dueLocal")
	Set result.Ref = ""
	Set result.DueAt = ""
	Do ..AssertObject(##class(OcuTalon.Tools.CommandCall).Answer(result), {"ok": true, "message": "Done."}, "no ref and no due time leave out all three")
	Set result.Ok = 0
	Set result.Message = "Not done."
	Do ..AssertObject(##class(OcuTalon.Tools.CommandCall).Answer(result), {"ok": false, "message": "Not done."}, "a refusal is ok false and the owner's message")
	Set result.DueAt = $Parameter(..#DOUBLE, "SETDUEAT")
	Set answer = ##class(OcuTalon.Tools.CommandCall).Answer(result)
	Do $$$AssertEquals(..SortedKeys(answer), "due,dueLocal,message,ok", "control: a due time that can be read gives due and dueLocal")
}

/// The keys of the commands of a re-sent turn (AC7). The scenario reminder-set-two makes two set_reminder calls in one response. The same turn (the same ItemId,
/// owner and DecisionRef) is sent to ChatAgent twice, as a re-sent turn with tools would be (Decide answers a repeated item from its recorded decision, so
/// the test goes to the runner). Each round makes two SetReminder commands with the keys <ItemId>:1 and <ItemId>:2, the texts stretch and drink water in
/// order, and round 2 records the same two keys as round 1.
Method TestKeys()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "Remind me to stretch and to drink water. [[mock:reminder-set-two]]", .ref, owner)
	Set one.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set two = one.%ConstructClone()
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertEquals(two.ItemId_"|"_two.OwnerRef_"|"_two.DecisionRef, ref_"|"_owner_"|"_one.DecisionRef, "control: the second request is the same turn")
	Set sc = $ClassMethod(fixture, "Send", ..#RUNNER, one, .first)
	Do $$$AssertStatusOK(sc, "round 1 is answered")
	Do $$$AssertEquals($Select($IsObject(first): first.Text, 1: "none"), "The CI mock set the reminders.", "with the text of the scenario")
	Set steps = [].%FromJSON($Select($IsObject(first) && (first.Steps '= ""): first.Steps, 1: "[]"))
	Set kinds = ""
	Set labels = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set kinds = kinds _ $Select(kinds = "": "", 1: ",") _ step.kind
		If step.kind = "tool" {
			Set labels = labels _ $ListBuild(step.label_"|"_step.status_"|"_(step.summary [ "set_reminder"))
		}
	}
	Do $$$AssertEquals(kinds, "model,tool,tool,model", "round 1 shows two tool steps, one for each call of the response: "_kinds)
	Do $$$AssertEquals($ListToString(labels, ";"), "Setting a reminder|ok|1;Setting a reminder|ok|1", "each with its label and its status, and its summary names set_reminder: "_$ListToString(labels, ";"))
	Set sc = $ClassMethod(fixture, "Send", ..#RUNNER, two, .again)
	Do $$$AssertStatusOK(sc, "round 2 is answered")
	Do $$$AssertEquals($Select($IsObject(again): again.Text, 1: "none"), "The CI mock set the reminders.", "with the same text")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 4, "the double recorded four commands, two in each round")
	If calls.%Size() = 4 {
		For round = 0, 1 {
			Set text = $Select(round = 0: "round 1", 1: "round 2")
			Do ..AssertCall(calls.%Get(round * 2), "OcuTalon.Msg.Command.SetReminder", owner, ref_":1", "DelaySeconds,IdempotencyKey,Origin,SessionRef,Text", "SetReminder")
			Do ..AssertCall(calls.%Get(round * 2 + 1), "OcuTalon.Msg.Command.SetReminder", owner, ref_":2", "DelaySeconds,IdempotencyKey,Origin,SessionRef,Text", "SetReminder")
			Do $$$AssertEquals(calls.%Get(round * 2).fields.Text_"|"_calls.%Get(round * 2 + 1).fields.Text, "stretch|drink water", text_" sets stretch and then drink water")
		}
	}
}

/// Nothing without a session's turn (AC8), in process. Each tool, called with no bridge context, or with a context whose OwnerRef is instance, eval, empty or not
/// a Ref, or whose ItemId is empty, answers {"ok": false, "message": NOSESSION} and submits nothing: the double records nothing.
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
		For tool = "set_reminder", "list_reminders", "cancel_reminder" {
			Set answer = ..CallTool(tool)
			Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}, $List(case, 1)_": "_tool_" answers NOSESSION")
		}
		Do $$$AssertEquals(..Calls().%Size(), 0, $List(case, 1)_": the double recorded nothing")
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin(owner, itemId)
	Set answer = ..CallTool("list_reminders")
	Do $$$AssertEquals(answer.ok, 1, "control: with a session's turn the same call is answered by the double")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and the double recorded it")
}

/// A failed submit (AC8), in process. With the double in fail mode, each tool answers {"ok": false, "message": NOTSENT} and logs one warning of Run that names the
/// class of its verb and holds the status text. The double still recorded each command, with the keys :1, :2 and :3 of the call's positions.
Method TestSubmitFails()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("CommandsDouble", "fail") = 1
	Do ..Begin(owner, itemId)
	Set verbs("set_reminder") = "OcuTalon.Msg.Command.SetReminder"
	Set verbs("list_reminders") = "OcuTalon.Msg.Command.ListReminders"
	Set verbs("cancel_reminder") = "OcuTalon.Msg.Command.CancelReminder"
	For tool = "set_reminder", "list_reminders", "cancel_reminder" {
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ..CallTool(tool)
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTSENT"))}, tool_" answers NOTSENT")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild(verbs(tool), "The CI double was set to fail")), 1, tool_" logged one warning of Run that names "_verbs(tool)_" and the status")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 1, "and no other warning of "_..#CALL)
	}
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 3, "the double recorded the three commands")
	If calls.%Size() = 3 {
		Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key_"|"_calls.%Get(2).key, itemId_":1|"_itemId_":2|"_itemId_":3", "with the keys of their positions in the call")
	}
}

/// A submit that is answered with no CommandResult (AC8), in process. With the double in empty mode (an OK status and no result), each tool answers
/// {"ok": false, "message": NOTSENT} and logs one warning of Run that names the class of its verb and says that the answer is no CommandResult.
Method TestSubmitEmpty()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("CommandsDouble", "empty") = 1
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set verbs("set_reminder") = "OcuTalon.Msg.Command.SetReminder"
	Set verbs("list_reminders") = "OcuTalon.Msg.Command.ListReminders"
	Set verbs("cancel_reminder") = "OcuTalon.Msg.Command.CancelReminder"
	For tool = "set_reminder", "list_reminders", "cancel_reminder" {
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ..CallTool(tool)
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTSENT"))}, tool_" answers NOTSENT when the answer is no CommandResult")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild(verbs(tool), "not an OcuTalon.Msg.CommandResult")), 1, tool_" logged one warning of Run that names "_verbs(tool)_" and the answer")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, "", ..#CALL), 1, "and no other warning of "_..#CALL)
	}
	Do $$$AssertEquals(..Calls().%Size(), 3, "the double recorded the three commands")
}

/// The status text of a failed submit is redacted (AC8), in process. A status text that holds a key-shaped value (made up here at run time, never written
/// as a literal) reaches the warning of Run as [redacted], and the warning holds no part of the key. The double, a business service with no adapter, also
/// logs the status as it is (Ens.BusinessService), so the test deletes the event-log rows that hold the value at its end.
Method TestSubmitRedacted()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set secret = "sk-ant-"_$Translate($Justify("", 30), " ", "x")
	Set ^OcuTalonTest("CommandsDouble", "fail") = "refused "_secret
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set answer = ..CallTool("cancel_reminder")
	Do ..AssertObject(answer, {"ok": false, "message": ($Parameter(..#CALL, "NOTSENT"))}, "cancel_reminder answers NOTSENT")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild("OcuTalon.Msg.Command.CancelReminder", "refused [redacted]")), 1, "the warning holds the status text with the key redacted")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#CALL, "Run", $ListBuild("sk-ant")), 0, "and no part of the key")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Text [ ?", mark, secret)
}

/// The event-log session of the calling job survives a submit (AC8; AD-1, AD-9), in process. A tool runs in ChatAgent's job, whose event-log rows carry the
/// session of the decision, and CommandsIn is a business service, which clears the job's session when its ProcessInput ends. With a session set for this job,
/// each tool, answered by the double, leaves it as it was, and so does a failed submit, whose warning of Run is logged in that session. The job's session is put
/// back as it was at the end, also after an error.
Method TestSubmitKeepsTheJobSession()
{
	If '..Prepare() Quit
	Set had = $Data(%Ensemble("SessionId"), was)
	Set session = 900000000 + $Random(99999999)
	Try {
		Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
		Set %Ensemble("SessionId") = session
		For tool = "set_reminder", "list_reminders", "cancel_reminder" {
			Set answer = ..CallTool(tool)
			Do $$$AssertEquals(answer.ok, 1, tool_" is answered by the double")
			Do $$$AssertEquals($Get(%Ensemble("SessionId")), session, tool_" leaves the job's session as it was")
		}
		Set ^OcuTalonTest("CommandsDouble", "fail") = 1
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set answer = ..CallTool("set_reminder")
		Do $$$AssertEquals(answer.ok, 0, "control: the failed submit answers ok false")
		Do $$$AssertEquals($Get(%Ensemble("SessionId")), session, "a failed submit leaves the job's session as it was too")
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass = ? AND SourceMethod = 'Run'", mark, ..#CALL)
		Set sessions = ""
		While rows.%Next() {
			Set sessions = sessions _ $ListBuild(rows.%GetData(1))
		}
		Do $$$AssertEquals($ListToString(sessions), session, "and its warning of Run is logged in the job's session")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test ran to its end")
	}
	If had # 2 {
		Set %Ensemble("SessionId") = was
	} Else {
		Kill %Ensemble("SessionId")
	}
}

/// A delaySeconds that is not a whole number (AC8), in process. abc, 1.5 and -5 each answer {"ok": false, "message": BADDELAY} and the double records nothing. A
/// whole number given as text, and none at all, reach the double.
Method TestBadDelay()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	For delay = "abc", "1.5", "-5", "6 0", "1e3" {
		Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", delay)
		Do ..AssertObject(answer, {"ok": false, "message": ($Parameter("OcuTalon.Tools.ReminderTools", "BADDELAY"))}, "a delaySeconds of '"_delay_"' is refused")
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "and nothing is submitted")
	Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", "60")
	Do $$$AssertEquals(answer.ok, 1, "control: a whole number given as text reaches the double")
	Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", "", "2026-10-29T10:00:00")
	Do $$$AssertEquals(answer.ok, 1, "and so does no delay at all")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded those two")
	If calls.%Size() = 2 {
		Do $$$AssertEquals(calls.%Get(0).key_"|"_calls.%Get(1).key, itemId_":1|"_itemId_":2", "numbered from 1: a refused call takes no position")
	}
}

/// The due time of the answer to a set is in the instance zone (AC3), in process (QA). The double's due time is 2027-03-04T15:00:00Z. In America/New_York (standard
/// time on that day) it is 10:00 local, and in Pacific/Auckland (daylight time) it is 04:00 on the next day, so dueLocal changes the date as well as the hour. due is
/// the text of Data.Time.ForMessage in that zone, which ends with the local clock time, and no UTC time is shown. TestSetRelative runs in the zone of the instance,
/// UTC in a throwaway, where a time that only has its Z cut off would look right.
Method TestSetAnswerInZone()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set due = $Parameter(..#DOUBLE, "SETDUEAT")
	Set cases = $ListBuild($ListBuild("America/New_York", "2027-03-04T10:00:00", "10:00"), $ListBuild("Pacific/Auckland", "2027-03-05T04:00:00", "04:00"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set zone = $List(case, 1)
		Do $SYSTEM.Process.TimeZone(zone)
		Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 60)
		Do ..AssertObject(answer, {"ok": true, "message": "The CI double set the reminder.", "ref": ($Parameter(..#DOUBLE, "SETREF")), "due": (##class(OcuTalon.Data.Time).ForMessage(due)), "dueLocal": ($List(case, 2))}, zone_": the answer to a set")
		Set text = answer.due
		Do $$$AssertEquals($Extract(text, $Length(text) - 4, $Length(text)), $List(case, 3), zone_": due ends with the local clock time: "_text)
		Do $$$AssertTrue(answer.%ToJSON() '[ "15:00", zone_": and the UTC clock time is not shown")
	}
	Do $$$AssertEquals(..Calls().%Size(), 2, "the double recorded both sets")
}

/// A refusal of the owner reaches the model unchanged, whatever it holds (AC3, AC5), in process (QA). For each of the three tools, the double refuses with a text that
/// holds quotes, a backslash, a slash, a tab, a line break, white space at both ends and a non-ASCII character (made up here with $Char), and then with a text of
/// 700 characters. The answer is {"ok": false, "message": the text}, character for character: not trimmed, not cut and not escaped.
Method TestRefusalsAreUnchanged()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set odd = "  She said ""no"" \ and / "_$Char(9)_"with a tab"_$Char(10)_"and a second line "_$Char(8217)_" end  "
	Set long = $Translate($Justify("", 700), " ", "x")_" end"
	Set verbs("set_reminder") = "SetReminder"
	Set verbs("list_reminders") = "ListReminders"
	Set verbs("cancel_reminder") = "CancelReminder"
	For tool = "set_reminder", "list_reminders", "cancel_reminder" {
		For kind = 1, 2 {
			Set message = $Select(kind = 1: odd, 1: long)
			Set what = tool_" with "_$Select(kind = 1: "an odd text", 1: "a text of "_$Length(message)_" characters")
			Set ^OcuTalonTest("CommandsDouble", "refuse", verbs(tool)) = message
			Set answer = ..CallTool(tool)
			Do $$$AssertEquals(answer.%GetTypeOf("ok")_"|"_answer.ok_"|"_..SortedKeys(answer), "boolean|0|message,ok", what_": the answer is ok false with a message and nothing else")
			Do $$$AssertEquals(answer.message, message, what_": the message is the owner's, character for character")
		}
	}
}

/// The tools are thin (AC3, AC4; decision 5), in process (QA). Whatever the model gave reaches the owner as given, each field only when the model gave it, and the
/// owner decides: both due forms, no due form, an empty text, a day and time that cannot be read, and a ref that no reminder has. The double accepts all of them
/// (it checks nothing), so the commands that it recorded show what the tools passed on. The keys are numbered from 1 in the order of the calls.
Method TestToolsPassOnWhatTheModelGave()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Set set = "OcuTalon.Msg.Command.SetReminder"
	Do $$$AssertEquals(##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 60, "2026-10-29T10:00:00").ok, 1, "both due forms are answered by the owner (here, the double)")
	Do $$$AssertEquals(##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch").ok, 1, "so is no due form")
	Do $$$AssertEquals(##class(OcuTalon.Tools.ReminderTools).SetReminder("", 60).ok, 1, "and an empty text")
	Do $$$AssertEquals(##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", "", "next Thursday").ok, 1, "and a day and time that cannot be read")
	Do $$$AssertEquals(##class(OcuTalon.Tools.ReminderTools).CancelReminder("no such reminder").ok, 1, "and a ref that no reminder has")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 5, "the double recorded five commands")
	If calls.%Size() = 5 {
		Do ..AssertCall(calls.%Get(0), set, owner, itemId_":1", "DelaySeconds,IdempotencyKey,LocalDueAt,Origin,SessionRef,Text", "both due forms")
		Do ..AssertCall(calls.%Get(1), set, owner, itemId_":2", "IdempotencyKey,Origin,SessionRef,Text", "no due form")
		Do ..AssertCall(calls.%Get(2), set, owner, itemId_":3", "DelaySeconds,IdempotencyKey,Origin,SessionRef", "an empty text")
		Do ..AssertCall(calls.%Get(3), set, owner, itemId_":4", "IdempotencyKey,LocalDueAt,Origin,SessionRef,Text", "a day and time that cannot be read")
		Do ..AssertCall(calls.%Get(4), "OcuTalon.Msg.Command.CancelReminder", owner, itemId_":5", "IdempotencyKey,Origin,ReminderRef,SessionRef", "a ref that no reminder has")
		Do $$$AssertEquals(calls.%Get(0).fields.DelaySeconds_"|"_calls.%Get(0).fields.LocalDueAt_"|"_calls.%Get(0).fields.Text, "60|2026-10-29T10:00:00|stretch", "both due forms and the text as the model gave them")
		Do $$$AssertEquals(calls.%Get(3).fields.LocalDueAt, "next Thursday", "the day and time that cannot be read, as given")
		Do $$$AssertEquals(calls.%Get(4).fields.ReminderRef, "no such reminder", "the ref, as given")
	}
}

/// The list is in the order of the owner's Data (AC6), in process (QA). The double's data mode gives three reminders in an order that is neither the order of their
/// due times nor of their refs nor of their texts, and the answer holds them in that order: the tool does not sort what the owner has ordered.
Method TestListKeepsTheOwnersOrder()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set one = $ListBuild(..RefOf("OrderB"), "mid", "2027-03-05T09:00:00Z")
	Set two = $ListBuild(..RefOf("OrderC"), "zulu", "2027-03-02T09:00:00Z")
	Set three = $ListBuild(..RefOf("OrderA"), "alpha", "2027-03-09T09:00:00Z")
	Set data = {"reminders": []}
	Set position = 0
	Set all = $ListBuild(one, two, three)
	While $ListNext(all, position, reminder) {
		Do data.reminders.%Push({"ref": ($List(reminder, 1)), "text": ($List(reminder, 2)), "dueAt": ($List(reminder, 3))})
	}
	Set ^OcuTalonTest("CommandsDouble", "data") = data.%ToJSON()
	Set answer = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do ..AssertListed(answer, all, "the reminders in the order of the owner's Data")
}

/// A delaySeconds that is not a whole number, given as AI Hub's tool manager decodes it (AC8), in process (QA). TestBadDelay calls the method with strings, so it cannot
/// see AI Hub turn an argument into another value on its way to the method. Here a fresh tool manager runs set_reminder with a JSON 1.5, -5 and "abc": each answers
/// {"ok": false, "message": BADDELAY} and the double records nothing. A JSON 60, and no delaySeconds with a localDueAt, reach the double with the field that was
/// given and no other, with the keys :1 and :2.
Method TestBadDelayThroughTheToolManager()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Set manager = ##class(%AI.ToolMgr).%New()
	Do $$$AssertStatusOK(manager.RegisterToolSet(..#TOOLSET), "a fresh tool manager registers the reminder toolset")
	Set tools = manager.%Discover()
	Do $$$AssertEquals(tools.%Size(), 3, "and discovers its three tools")
	For delay = "1.5", "-5", """abc""" {
		Set arguments = {}.%FromJSON("{""text"":""stretch"",""delaySeconds"":"_delay_"}")
		Set result = manager.ExecuteTool("set_reminder", arguments)
		Do ..AssertObject(result.value, {"ok": false, "message": ($Parameter("OcuTalon.Tools.ReminderTools", "BADDELAY"))}, "a delaySeconds of "_delay_" is refused")
	}
	Do $$$AssertEquals(..Calls().%Size(), 0, "and nothing is submitted")
	Set result = manager.ExecuteTool("set_reminder", {"text": "stretch", "delaySeconds": 60})
	Do $$$AssertEquals($Select($IsObject(result.value): result.value.ok, 1: "none"), 1, "control: a delaySeconds of 60 is answered by the owner")
	Set result = manager.ExecuteTool("set_reminder", {"text": "stretch", "localDueAt": "2026-10-29T10:00:00"})
	Do $$$AssertEquals($Select($IsObject(result.value): result.value.ok, 1: "none"), 1, "and so is a day and time with no delaySeconds")
	Do manager.Cleanup()
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 2, "the double recorded those two")
	If calls.%Size() = 2 {
		Do ..AssertCall(calls.%Get(0), "OcuTalon.Msg.Command.SetReminder", owner, itemId_":1", "DelaySeconds,IdempotencyKey,Origin,SessionRef,Text", "the delay")
		Do ..AssertCall(calls.%Get(1), "OcuTalon.Msg.Command.SetReminder", owner, itemId_":2", "IdempotencyKey,LocalDueAt,Origin,SessionRef,Text", "the day and time, with no delay")
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

/// Begins a bridge context in the test process for a turn of the owner with the ItemId, as the runner does before Chat.
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

/// Calls the tool (by its name) in process with arguments that are fine, and gives its answer.
ClassMethod CallTool(tool As %String) As %DynamicObject [ Private ]
{
	If tool = "set_reminder" Quit ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 60)
	If tool = "list_reminders" Quit ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Quit ##class(OcuTalon.Tools.ReminderTools).CancelReminder(..#CANCELREF)
}

/// Sends a user turn of the owner through Decide (RunnerFixture.Run) and reads the mock's log for it: request is the Request, answer the Reply, session the
/// session of the request and requests the entries of the mock's log for the turn, in order. The turn's ItemId is remembered for OnAfterOneTest.
Method Turn(text As %String, owner As %String, Output request As OcuTalon.Bridge.Msg.Request, Output answer As %Persistent, Output session As %Integer, Output requests As %DynamicArray) As %Status [ Private ]
{
	Set fixture = ..#FIXTURE
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", text, .ref, owner)
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
	Do $$$AssertEquals(answer.ToolsRun, 1, "and it says that tools ran")
	Set row = ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "a Decision row of kind turn is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", "which is not a fallback")
	Quit $$$ISOK(sc) && ($IsObject(row))
}

/// The steps of Visual Trace (AC1, AC7): the AgentStep messages of the decision are a model step, then a tool step and a model step for each tool call. The
/// tool steps have the labels, their summaries name the tools, and their status is ok. The steps, and the runner's reply, are in the session of the decision.
/// RunnerFixture.StepProblems does the check and names whatever is wrong.
Method AssertSteps(answer As %Persistent, session As %Integer, labels As %List, tools As %List) [ Private ]
{
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "StepProblems", answer.DecisionRef, session, labels, tools, "ChatAgent"), "", "the steps of the turn are right")
}

/// Asserts the record of one command of the double: its class, origin tool, the session, the key, the names of its non-empty fields and the verb.
Method AssertCall(call As %DynamicObject, class As %String, owner As %String, key As %String, names As %String, verb As %String) [ Private ]
{
	Do $$$AssertEquals(call.class, class, verb_": the command is a "_class)
	Do $$$AssertEquals(call.origin, "tool", verb_": its origin is tool")
	Do $$$AssertEquals(call.sessionRef, owner, verb_": its SessionRef is the OwnerRef of the turn")
	Do $$$AssertEquals(call.key, key, verb_": its key is "_key)
	Do $$$AssertEquals(..SortedKeys(call.fields), names, verb_": it sets "_names_" and no other field")
}

/// A fresh start of a case for the tests of several refs: the double's records and modes are cleared, the context ends, and a context of a new turn of the owner
/// begins. Gives the turn's ItemId.
Method Fresh(owner As %String) As %String [ Private ]
{
	Kill ^OcuTalonTest("CommandsDouble")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, itemId)
	Quit itemId
}

/// Asserts that the answer of a cancel of several refs (a dynamic object, as the tool returns it) is {"ok": every entry ok, "results": [...]}, with one entry
/// for each expected one, in order, each the flat object that AssertObject compares.
Method AssertResults(actual As %DynamicObject, entries As %DynamicArray, label As %String) [ Private ]
{
	If '$IsObject(actual) {
		Do $$$AssertTrue(0, label_": the answer is an object: "_$Extract(actual, 1, 200))
		Quit
	}
	Do $$$AssertEquals(..SortedKeys(actual), "ok,results", label_": the answer has ok and results and nothing else")
	Do $$$AssertEquals(actual.%GetTypeOf("ok"), "boolean", label_": ok is a boolean")
	Set every = 1
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If 'entry.ok Set every = 0
	}
	Do $$$AssertEquals(actual.ok, every, label_": ok is true only when every entry is")
	Set results = actual.results
	If '$IsObject(results) || ('results.%IsA("%Library.DynamicArray")) {
		Do $$$AssertTrue(0, label_": results is an array")
		Quit
	}
	Do $$$AssertEquals(results.%Size(), entries.%Size(), label_": one entry for each ref")
	For i = 0:1:entries.%Size() - 1 {
		If i < results.%Size() Do ..AssertObject(results.%Get(i), entries.%Get(i), label_": entry "_(i + 1))
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

/// The answer that the double gives a SetReminder, as the model reads it: ok, the double's message, its ref, and its due time from Data.Time in the two forms.
ClassMethod SetAnswer() As %DynamicObject [ Private ]
{
	Set due = $Parameter(..#DOUBLE, "SETDUEAT")
	Quit {"ok": true, "message": "The CI double set the reminder.", "ref": ($Parameter(..#DOUBLE, "SETREF")), "due": (##class(OcuTalon.Data.Time).ForMessage(due)), "dueLocal": (##class(OcuTalon.Data.Time).ToLocal(due))}
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

/// Asserts that the answer of the list tool (a dynamic object, or the JSON text that the model got) is {"ok": true, "zone": the instance zone, "reminders": [...]}
/// with the reminders of the list, each $ListBuild(ref, text, dueAt (UTC)) and, as the model reads them, the due time of Data.Time.ForMessage and the local
/// time of Data.Time.ToLocal of the UTC time, and no UTC time.
Method AssertListed(actual As %Any, reminders As %List, label As %String) [ Private ]
{
	Set full = ""
	Set position = 0
	While $ListNext(reminders, position, one) {
		Set full = full _ $ListBuild($ListBuild($List(one, 1), $List(one, 2), $List(one, 3), ##class(OcuTalon.Data.Time).ToLocal($List(one, 3))))
	}
	Do ..AssertListedObject(actual, full, label)
}

/// As AssertListed, with each reminder $ListBuild(ref, text, dueAt (UTC), the local time that the list should show).
Method AssertListedObject(actual As %Any, reminders As %List, label As %String) [ Private ]
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
			Do $$$AssertTrue(0, label_": the result is a JSON object")
			Quit
		}
	}
	Do $$$AssertEquals(..SortedKeys(actual), "ok,reminders,zone", label_": the fields are ok, zone and reminders")
	Do $$$AssertEquals(actual.%GetTypeOf("ok")_"|"_actual.ok, "boolean|1", label_": ok is true")
	Do $$$AssertEquals(actual.zone, ##class(OcuTalon.Data.Time).Zone(), label_": the zone is the instance zone")
	Do $$$AssertEquals(actual.%GetTypeOf("reminders"), "array", label_": reminders is an array")
	If actual.%GetTypeOf("reminders") '= "array" Quit
	Do $$$AssertEquals(actual.reminders.%Size(), $ListLength(reminders), label_": it holds "_$ListLength(reminders)_" reminder(s)")
	If actual.reminders.%Size() '= $ListLength(reminders) Quit
	For i = 1:1:$ListLength(reminders) {
		Set want = $List(reminders, i)
		Set got = actual.reminders.%Get(i - 1)
		Do $$$AssertEquals(..SortedKeys(got), "due,dueLocal,ref,text", label_": reminder "_i_" has a ref, a text, a due time and a local time and nothing else")
		Do $$$AssertEquals(got.ref_"|"_got.text, $List(want, 1)_"|"_$List(want, 2), label_": reminder "_i_" is "_$List(want, 1))
		Do $$$AssertEquals(got.due, ##class(OcuTalon.Data.Time).ForMessage($List(want, 3)), label_": its due time is Data.Time.ForMessage of "_$List(want, 3))
		Do $$$AssertEquals(got.dueLocal, $List(want, 4), label_": its local time is "_$List(want, 4))
		Do $$$AssertTrue(got.%ToJSON() '[ $List(want, 3), label_": and the UTC time is not shown")
	}
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

/// 1 when the text starts, after white space, with an SQL verb that changes data (Test.Bridge.CodeRules SQLVERBS).
ClassMethod StartsWithSqlVerb(text As %String) As %Boolean [ Private ]
{
	Quit ''$Locate(text, "(?i)^\s*("_##class(OcuTalon.Test.Bridge.CodeRules).#SQLVERBS_")\b")
}

/// A Ref for a fixture reminder: zzReminder, the tag, and zeros up to 22 characters.
ClassMethod RefOf(tag As %String) As %String [ Private ]
{
	Quit $Extract("zzReminder"_tag_"0000000000000000", 1, 22)
}

/// Saves a Reminder row of the session, remembering its Ref for OnAfterOneTest. A row that an earlier run left under the Ref is deleted first.
Method AddReminder(owner As %String, ref As %String, text As %String, dueAt As %String, state As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Reminder WHERE Ref = ?", ref)
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ref
	Set row.SessionRef = owner
	Set row.Text = text
	Set row.DueAt = dueAt
	Set row.State = state
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set ..Rows = ..Rows _ $ListBuild(ref)
	Do $$$AssertStatusOK(row.%Save(), "the "_state_" reminder "_ref_" is saved")
}

/// Every row of the Reminder table as one text, by Ref: two readings are equal when no row was added, removed or changed between them.
ClassMethod RowsText() As %String [ Private ]
{
	Set text = ""
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, SessionRef, Text, DueAt, State, Late FROM OcuTalon_Data.Reminder ORDER BY Ref")
	While rows.%Next() {
		Set text = text _ rows.%GetData(1) _ "|" _ rows.%GetData(2) _ "|" _ rows.%GetData(3) _ "|" _ rows.%GetData(4) _ "|" _ rows.%GetData(5) _ "|" _ rows.%GetData(6) _ $Char(10)
	}
	Quit text
}

/// The number of rows of the Reminder table.
ClassMethod ReminderCount() As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder")
	Do rows.%Next()
	Quit rows.%GetData(1)
}

}
