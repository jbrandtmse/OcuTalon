/// Tests of the Chat agent's reminder tools (Story 1.10; AD-1, AD-4, AD-7, AD-9, AD-10, AD-18, FR-34): set_reminder, list_reminders and
/// cancel_reminder, the toolset OcuTalon.Tools.Reminders and the helper OcuTalon.Tools.CommandCall. THE TESTS BUT TestDeclarations RUN IN THROWAWAY
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
///     inputs are text, delaySeconds and localDueAt, none and reminderRef, and none names a session, an owner or an origin; the toolset holds no Requirement;
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
///   - TestListUnreadable (AC6): a Data that is not JSON, or has no reminders array, or has a reminder with no ref or no text, or holds an entry that is no object,
///     or holds a good reminder before a bad one, is a failure with one warning, never an empty list or a half list, while {"reminders": []} is an empty list;
///   - TestListRefused (AC5, AC7): the owner's refusal of ListReminders reaches the model as {"ok": false, "message": the owner's}, with no warning;
///   - TestAnswerShapes (AC3): Answer leaves out the ref and the due times that the owner did not give or that Data.Time cannot read, and keeps ok and message;
///   - TestKeys (AC7): the same turn sent to ChatAgent twice submits the keys <ItemId>:1 and <ItemId>:2 in each round;
///   - TestNoSession, TestSubmitFails, TestSubmitEmpty, TestSubmitRedacted and TestBadDelay (AC8): no context, an owner that is not a session's Ref or an empty
///     ItemId submits nothing and answers NOSESSION; a failed submit, and a submit that is answered with no CommandResult, answer NOTSENT with one warning that
///     names the verb's class, whose status text has passed through the redactor; a delaySeconds that is not a whole number answers BADDELAY.
/// OnAfterOneTest and OnAfterAllTests put back what a test made, also when it failed: the fixture Reminder rows (by Ref), ^OcuTalonTest("CommandsDouble"), the
/// Decision, Usage and AgentStep rows of the turns (by ItemId), the AI sessions the turns saved with their links, the context, the process zone (the base class
/// ZoneCase), the CommandsIn item (RestoreItemClass) and the keys of the runners (RestoreKeys). OnAfterAllTests returns the status of those two restores, and an
/// error when a new service of the CommandsIn item is not of the class that the item had, so a restore that did not happen fails the class.
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
	}
	Quit sc
}

/// The declarations (AC1, AC2). Chat's TOOLSETS names the reminder toolset, whose discovery lists exactly set_reminder, list_reminders and cancel_reminder
/// (the names of Tools.Names), each once, with ReminderTools as the provider, and ReminderTools offers its three methods and none of Result's. Each tool's
/// step label is the class parameter STEPLABEL<NAME>, not the generic label. The classification parameters are set and cancel: safe, not read-only, not
/// trusted output; list: safe, read-only, trusted output. The inputs are text, delaySeconds and localDueAt for set (text required), none for list and
/// reminderRef for cancel (required), and none names a session, an owner or an origin. The descriptions tell the model the two due forms and that
/// cancel takes the ref that list gave, and none starts with an SQL verb. The toolset holds no Requirement element, and each method returns a dynamic object.
Method TestDeclarations()
{
	Set names = "OcuTalon.Tools.Names"
	Do $$$AssertTrue(..StartsWithSqlVerb("  delete the reminders"), "control: a text that starts with an SQL verb is flagged")
	Do $$$AssertNotTrue(..StartsWithSqlVerb("Sets a reminder, then deletes nothing"), "and one that does not start with one is not")
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Chat", "TOOLSETS"), ..#TOOLSET, "Chat's TOOLSETS is "_..#TOOLSET)
	Set expected = $ListBuild($Parameter(names, "SETREMINDER"), $Parameter(names, "LISTREMINDERS"), $Parameter(names, "CANCELREMINDER"))
	Set want("set_reminder") = $ListBuild("safe", 0, 0, "Setting a reminder", "delaySeconds,localDueAt,text", "text")
	Set want("list_reminders") = $ListBuild("safe", 1, 1, "Listing your reminders", "", "")
	Set want("cancel_reminder") = $ListBuild("safe", 0, 0, "Cancelling a reminder", "reminderRef", "reminderRef")
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
	Do $$$AssertEquals($ListToString(..Sorted(ownNames)), "CancelReminder,ListReminders,SetReminder", ..#TOOLS_" offers its three methods and none of Result's")
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
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(1)), "cancel_reminder,list_reminders,set_reminder", "the second request offers the three reminder tools")
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
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.Provenance = "user"
	Set item.Text = "Remind me Thursday at 10 to load the new certificate. [[mock:reminder-set-local]]"
	Set input = ##class(OcuTalon.Agent.Input).Render(item, now)
	Set preamble = ##class(OcuTalon.Agent.Input).Preamble(now)
	Do $$$AssertTrue($Extract(preamble, 1, 12) = "Local time: ", "control: the preamble states the local time: "_preamble)
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
	Set sc = ..Turn("Cancel my reminder to stretch. [[mock:reminder-cancel]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock cancelled the reminder.") Quit
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
	Set sc = ..Turn("Cancel my reminder to stretch. [[mock:reminder-cancel]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock cancelled the reminder.") Quit
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
	Set sc = ..Turn("Which reminders do I have? [[mock:reminder-list]]", owner, .request, .answer, .session, .requests)
	If '..AssertTurn(sc, answer, request, "The CI mock listed the reminders.") Quit
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

/// A list that cannot be read (AC6), in process. A Data that is not JSON, one without a reminders array, one with a reminder that has no ref and one with a due
/// time that is not UTC to the second each answer {"ok": false, "message": NOTREAD} and log one warning of Listed: never an empty list. A Data of an empty
/// reminders array is an empty list, which says that none is pending.
Method TestListUnreadable()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set good = "{""ref"":""zzReminderGoodOne0001"",""text"":""ok"",""dueAt"":""2027-03-04T15:00:00Z""}"
	Set bad = $ListBuild("not json", "{""items"":[]}", "", "{""reminders"":[{""text"":""no ref"",""dueAt"":""2027-03-04T15:00:00Z""}]}", "{""reminders"":[{""ref"":""zzReminderBadDue00001"",""text"":""x"",""dueAt"":""soon""}]}", "{""reminders"":""none""}",
		"{""reminders"":[{""ref"":""zzReminderNoText0001"",""dueAt"":""2027-03-04T15:00:00Z""}]}",
		"{""reminders"":[""not an object""]}",
		"{""reminders"":["_good_",{""ref"":""zzReminderNoText0001"",""dueAt"":""2027-03-04T15:00:00Z""}]}")
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
	Set result.Ref = "zzReminderShape00001"
	Set result.DueAt = "soon"
	Do ..AssertObject(##class(OcuTalon.Tools.CommandCall).Answer(result), {"ok": true, "message": "Done.", "ref": "zzReminderShape00001"}, "a due time that cannot be read leaves out due and dueLocal")
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
/// as a literal) reaches the warning of Run as [redacted], and the warning holds no part of the key.
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
Method AssertSteps(answer As %Persistent, session As %Integer, labels As %List, tools As %List) [ Private ]
{
	Set fixture = ..#FIXTURE
	Set steps = $ClassMethod(fixture, "StepsOf", answer.DecisionRef)
	Set kinds = "model"
	For i = 1:1:$ListLength(labels) {
		Set kinds = kinds _ ",tool,model"
	}
	Set actual = ""
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set actual = actual _ $Select(actual = "": "", 1: ",") _ step.kind
	}
	Do $$$AssertEquals(actual, kinds, "the steps are "_kinds)
	Set toolPosition = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set toolPosition = toolPosition + 1
		If toolPosition > $ListLength(labels) Continue
		Do $$$AssertEquals(step.label, $List(labels, toolPosition), "tool step "_toolPosition_" has the label "_$List(labels, toolPosition))
		Do $$$AssertTrue(step.summary [ $List(tools, toolPosition), "and its summary names "_$List(tools, toolPosition)_": "_$Extract(step.summary, 1, 120))
		Do $$$AssertEquals(step.status, "ok", "and its status is ok")
	}
	Set outside = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? AND SessionId <> ?", "OcuTalon.Bridge.Msg.AgentStep", step.id, session)
		Do rows.%Next()
		Set outside = outside + rows.%GetData(1)
	}
	Do $$$AssertEquals(outside, 0, "no step has a header outside the session of the decision")
	Set headers = $ClassMethod(fixture, "Headers", session, "ChatAgent")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "Decide"), 1, "and the runner's reply is in that session too")
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

/// The names of a list, in order of the name.
ClassMethod Sorted(names As %List) As %List [ Private ]
{
	Set position = 0
	While $ListNext(names, position, name) {
		Set sorted(name) = ""
	}
	Set result = ""
	Set name = ""
	For {
		Set name = $Order(sorted(name))
		Quit:name=""
		Set result = result _ $ListBuild(name)
	}
	Quit result
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

/// The number of rows of the Reminder table.
ClassMethod ReminderCount() As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder")
	Do rows.%Next()
	Quit rows.%GetData(1)
}

}
