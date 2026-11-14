/// Tests of the Chat agent's email tool (Story 22.7; AD-1, AD-10, AD-16, AD-17, AD-25): send_email, the toolset OcuTalon.Tools.Email, its provider OcuTalon.Tools.EmailTools and the email fix
/// kind OcuTalon.Fix.Kind.Email that decides it. THE TESTS BUT TestDeclarations RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running (a risky call raises a
/// request through the approval service, and the tool submits through the CommandsIn item, behind which the double Test.Tools.CommandsDouble sits, as for Test.Tools.Persona) and fail with the
/// reason where they do not have it. No mail is sent: the double answers the SendEmail, and the real EmailOut is Test.Fix.Email's. Each test creates the mailbox keys it needs and puts back what
/// it found.
///   - TestDeclarations: Chat's TOOLSETS names the toolset, which offers send_email once, from EmailTools, with the step label "Sending an email", not read-only, trusted output, the rule of
///     CLASSIFYRULESENDEMAIL and the three inputs recipients, subject and text, all required and with the approved descriptions; the hooks are no tools; the kind's NAME is EmailOut's FIXKIND and
///     its limits are EmailOut's;
///   - TestClassify: the recipient rule row by row: the own address (case, spaces, duplicates, 20 of it) is safe; another address, the own address plus another, none, 21, a number, a string
///     instead of an array, bad values, no mailbox, a mailbox of another session, no context and {} are risky; extra keys such as "classification":"safe" change nothing; the answer follows the
///     stored keys at once;
///   - TestCommandHoldsNoAddress (DW-1255): for any spelling or repeat of the own address the submitted command's Recipients is the marker own and no field of it holds an address;
///   - TestSafeSend: a safe call submits one SendEmail (origin tool, the session of the call, the key <ItemId>:1, the marker own as its recipients, the subject and the text) and answers exactly
///     {ok, outcome, message} of the CommandResult, nothing of its Ref or Data; one Action entry counts the one address sent to and holds no address, subject or text;
///   - TestNoSession: no context, an owner that is not a session's Ref or an empty ItemId answer NOSESSION and submit nothing;
///   - TestOnlineDemo: with onlineDemo 1 the tool answers not_available with EmailOut's sentence and submits and audits nothing, and the hook sets that sentence as its refusal and raises nothing;
///   - TestHoldRefusals: the hook raises nothing and sets EmailOut's sentence for no mailbox address (MESSAGENOTCONNECTED) and for parameters that EmailOut would refuse or that a SendEmail command cannot hold (MESSAGEREFUSED);
///   - TestHoldRaisesTheRequest: the hook raises one fix request of the kind email with the exact row shape, for another address, the own address plus another, and another session's call to
///     the mailbox address; it carries no Tool field and no incident, its dry run holds every recipient, the subject and the text, and the model's answer is the gate's HELD;
///   - TestGateDecides: through the gate, a user's turn gets HELD for another address and a safe own address is allowed; an untrusted or tainted turn is denied UNTRUSTED for both, with no
///     request and no hook call.
Class OcuTalon.Test.Tools.Email Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The test double of CommandsIn, and the item it sits behind.
Parameter DOUBLE = "OcuTalon.Test.Tools.CommandsDouble";

Parameter ITEM = "CommandsIn";

Parameter TOOLS = "OcuTalon.Tools.EmailTools";

Parameter TOOLSET = "OcuTalon.Tools.Email";

Parameter KIND = "OcuTalon.Fix.Kind.Email";

Parameter OUT = "OcuTalon.Channel.Email.Out";

Parameter GATE = "OcuTalon.Bridge.Policy.Gate";

/// The address of the mailbox of the tests, and the product keys that hold it.
Parameter ADDRESS = "Owner@Example.test";

Parameter ADDRESSKEY = "email.address";

Parameter OWNERKEY = "email.owner";

/// What CommandCall answers for a call that is not a session's turn.
Parameter CALL = "OcuTalon.Tools.CommandCall";

/// What the CommandsIn item had before the double was put behind it (RunnerFixture.UseItemClass), as the JSON text it gave, or "" while the double is not behind it.
Property Swap As %String(MAXLEN = "");

/// The mailbox keys as the test found them: $ListBuild(address exists, address, owner exists, owner), or "" while the test has not changed them.
Property Found As %List;

/// The onlineDemo setting before the test changed it, and whether it did.
Property Before As %String;

Property Saved As %Boolean [ InitialExpression = 0 ];

/// The sessions whose approval rows the test may have made: OnAfterOneTest ends and deletes every row they own.
Property Owners As %List;

/// The Refs of the sessions that AdminSession made: OnAfterOneTest deletes them.
Property AdminSessions As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	If ..Saved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Before)
		Set ..Saved = 0
	}
	Do ..PutBackMailbox()
	Set position = 0
	While $ListNext(..Owners, position, who) {
		Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner(who)
	}
	Set ..Owners = ""
	If $Data(^OcuTalonTest("Approval", "refs")) || $Data(^OcuTalonTest("Approval", "job")) Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	If ..AdminSessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..AdminSessions)
	Set ..AdminSessions = ""
	Quit $$$OK
}

/// A session of the README admin (its Ref), as a send_email call to another address needs: Raise refuses a requester who is no OcuTalon admin (Story 25.5). OnAfterOneTest deletes it.
Method AdminSession() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER)
	Set ..AdminSessions = ..AdminSessions _ $Select(..AdminSessions = "": "", 1: ",") _ ref
	Quit ref
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
	Quit sc
}

/// The declarations. The toolset offers exactly send_email, once, from EmailTools, with the label, flags and rule of the spec and the approved descriptions; the hooks are no tools. The kind's NAME
/// is the FIXKIND of EmailOut and its limits are EmailOut's.
Method TestDeclarations()
{
	Do $$$AssertTrue($ListFind($ListFromString($Parameter("OcuTalon.Agent.Chat", "TOOLSETS")), ..#TOOLSET) > 0, "Chat's TOOLSETS names "_..#TOOLSET)
	Set name = $Parameter("OcuTalon.Tools.Names", "SENDEMAIL")
	Do $$$AssertEquals(name, "send_email", "the tool's name is the one of Tools.Names")
	Set tools = $ClassMethod(..#TOOLSET, "%New").%Discover().tools
	Do $$$AssertEquals(tools.%Size(), 1, "the toolset offers one tool")
	Set seen = 0
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If tool.name = name Set seen = seen + 1
		Do $$$AssertEquals(tool.provider, ..#TOOLS, tool.name_" is a method of "_..#TOOLS)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.StepBuffer).LabelFor(tool.provider, tool.name), "Sending an email", "its step label is Sending an email")
		Do $$$AssertEquals($Parameter(..#TOOLS, "STEPLABELSENDEMAIL"), "Sending an email", "the label is the class parameter")
		Do $$$AssertEquals($Parameter(..#TOOLS, "READONLYSENDEMAIL")_"|"_$Parameter(..#TOOLS, "TRUSTEDOUTPUTSENDEMAIL"), "0|1", "it is not read-only and its output is trusted")
		Do $$$AssertEquals($Parameter(..#TOOLS, "CLASSIFYRULESENDEMAIL"), "safe when every recipient is the user's own email address; otherwise risky, so it waits for approval", "with the approved rule")
		Do $$$AssertEquals(tool.description, "Sends a plain-text email from the user's connected mailbox. Email to the user's own address is sent at once; email to anyone else becomes an approval request and is sent only after the user approves it. The answer says whether the email was sent.", "the tool's description is the approved one")
		Set properties = tool.parameters.properties
		Do $$$AssertEquals(properties.recipients.description, "The email addresses to send to: one or more, at most 20.", "the description of recipients")
		Do $$$AssertEquals(properties.subject.description, "The subject, one line, at most 200 characters.", "the description of subject")
		Do $$$AssertEquals(properties.text.description, "The body of the email, plain text.", "the description of text")
		Do $$$AssertEquals(properties.recipients.type, "array", "recipients is an array")
		Set required = ""
		Set at = tool.parameters.required.%GetIterator()
		While at.%GetNext(, .one) {
			Set required = required _ $ListBuild(one)
		}
		Do $$$AssertEquals($ListToString($Select($ListLength(required) > 1: ..Sorted(required), 1: required)), "recipients,subject,text", "all three are required")
		Do $$$AssertEquals(tool.metadata."origin_class", ..#TOOLS, "it says that it originates in "_..#TOOLS)
	}
	Do $$$AssertEquals(seen, 1, name_" is offered once")
	Set own = $ClassMethod(..#TOOLS, "%New").%Discover().tools
	Do $$$AssertEquals(own.%Size(), 1, ..#TOOLS_" offers its one method: the hooks are Internal, so they are no tools")
	Do $$$AssertEquals(##class(%Dictionary.CompiledMethod).%OpenId(..#TOOLS_"||SendEmail").ReturnType, "%Library.DynamicObject", "SendEmail returns a dynamic object")
	Do $$$AssertEquals($Parameter(..#KIND, "NAME"), $Parameter(..#OUT, "FIXKIND"), "the kind's NAME is EmailOut's FIXKIND, so the approval EmailOut checks is the kind's")
	Do $$$AssertEquals($Parameter(..#KIND, "PARAMETERS"), "recipients,subject,text", "its parameters are the recipients, the subject and the text")
	Do $$$AssertEquals($Parameter(..#KIND, "RESOURCES")_"|"_$Parameter(..#KIND, "TARGETTYPE")_"|"_$Parameter(..#KIND, "DIAGNOSED")_"|"_$Parameter(..#KIND, "ASKED")_"|"_$Parameter(..#KIND, "RESULTTARGET"), "|recipient|0|0|FixExecutor", "it needs no resource, targets recipients, is never diagnosed or asked for, and its result goes to FixExecutor")
	Do $$$AssertEquals($Parameter(..#KIND, "EMAILNOSTART"), "OcuTalon couldn't start sending the email, so it wasn't sent.", "its reason for an email that could not start is the approved sentence")
	Do $$$AssertEquals($Parameter(..#KIND, "OUT"), ..#OUT, "its limits and sentences are read from EmailOut")
}

/// The recipient rule, row by row. Each row is classified in a user's turn of the owner session with the stored keys the row names; the answer is the kind's Classify, the hook the gate calls.
Method TestClassify()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mailbox(..#ADDRESS, owner)
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Set cases = $ListBuild(
		$ListBuild("the own address", "[""Owner@Example.test""]", "safe"),
		$ListBuild("the own address in another case, with spaces", "[""  OWNER@example.TEST ""]", "safe"),
		$ListBuild("the own address twice", "[""owner@example.test"", ""OWNER@example.test""]", "safe"),
		$ListBuild("the own address 20 times", ..Times("owner@example.test", 20).%ToJSON(), "safe"),
		$ListBuild("the own address 21 times", ..Times("owner@example.test", 21).%ToJSON(), "risky"),
		$ListBuild("another address", "[""partner@example.test""]", "risky"),
		$ListBuild("the own address and another", "[""owner@example.test"", ""partner@example.test""]", "risky"),
		$ListBuild("another address first", "[""partner@example.test"", ""owner@example.test""]", "risky"),
		$ListBuild("no recipient", "[]", "risky"),
		$ListBuild("an empty recipient", "[""""]", "risky"),
		$ListBuild("a number", "[5]", "risky"),
		$ListBuild("an object", "[{""a"": 1}]", "risky"),
		$ListBuild("a malformed address", "[""owner@""]", "risky"),
		$ListBuild("the address with a comma list", "[""owner@example.test,partner@example.test""]", "risky"),
		$ListBuild("the address with a display name", "[""Owner <owner@example.test>""]", "risky"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set arguments = {"subject": "A subject", "text": "A text."}
		Set arguments.recipients = {}.%FromJSON("{""r"":"_$List(case, 2)_"}").r
		Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", arguments), $List(case, 3), $List(case, 1)_": "_$List(case, 3))
	}
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": "owner@example.test", "subject": "s", "text": "t"}), "risky", "a string instead of an array: risky")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"subject": "s", "text": "t"}), "risky", "no recipients member: risky")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {}), "risky", "{}: risky")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", ""), "risky", "no arguments object: risky")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "", "text": "t"}), "risky", "an empty subject: risky, so the hook refuses it")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": ""}), "risky", "an empty text: risky")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": 5, "text": "t"}), "risky", "a subject that is no string: risky")
	Set own = ["owner@example.test"]
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": (own), "subject": "s", "text": "t", "classification": "safe", "to": "user"}), "safe", "extra keys change nothing for the own address")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["partner@example.test"], "subject": "s", "text": "t", "classification": "safe", "readOnly": 1, "trustedOutput": 1, "owner": "x", "safe": true}), "risky", "and no extra key makes another address safe")
	Set row = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#TOOLS, "send_email", {"recipients": ["partner@example.test"], "subject": "s", "text": "t"})
	Do $$$AssertEquals(row.classification_"|"_row.readOnly_"|"_row.trustedOutput_"|"_row.by, "risky|0|1|code", "the gate reads it from the hook: risky, not read-only, trusted output, by code")
	Set row = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#TOOLS, "send_email", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"})
	Do $$$AssertEquals(row.classification_"|"_row.readOnly_"|"_row.trustedOutput_"|"_row.by, "safe|0|1|code", "and safe for the own address, still not read-only")
	Do ##class(OcuTalon.Bridge.Context).End()

	Do ..Begin(##class(OcuTalon.Bridge.Ids).NewRef(), ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "risky", "a mailbox of another session: risky, also for its address")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "risky", "no context: risky")

	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Do ##class(OcuTalon.Data.Setting).Set(..#OWNERKEY, ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "risky", "when the mailbox moves to another session the very next call is risky (the keys are read from their rows)")
	Do ##class(OcuTalon.Data.Setting).Set(..#OWNERKEY, owner)
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "safe", "and back to safe when it moves back")
	Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, "not an address")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["not an address"], "subject": "s", "text": "t"}), "risky", "a stored address that is not an address: risky")
	Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#ADDRESSKEY)
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "risky", "no mailbox address: risky")
	Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, ..#ADDRESS)
	Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#OWNERKEY)
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}), "risky", "no mailbox owner: risky")
}

/// DW-1255 rule 4: the command of a safe call holds no address. Whatever spellings and repeats of the own address the call lists (and 20 of them), the one SendEmail that the tool submits has the
/// marker OWNADDRESS of SendEmail as its Recipients, which means the mailbox's own address, and no field of it holds the address, the call's spelling of it or any other address.
Method TestCommandHoldsNoAddress()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mailbox(..#ADDRESS, owner)
	Do $$$AssertEquals($Parameter("OcuTalon.Msg.Command.SendEmail", "OWNADDRESS"), "own", "the marker of a tool send is own")
	Set twenty = []
	For i = 1:1:20 Do twenty.%Push(" Owner@EXAMPLE.test ")
	Set cases = $ListBuild(
		$ListBuild("one spelling", ["owner@example.test"]),
		$ListBuild("two spellings", ["owner@example.test", "OWNER@example.test"]),
		$ListBuild("the own address twice", [" OWNER@example.test", "owner@EXAMPLE.test "]),
		$ListBuild("twenty times", twenty))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("CommandsDouble")
		Do ##class(OcuTalon.Bridge.Context).End()
		Do ..Begin(owner, itemId)
		Set answer = ##class(OcuTalon.Tools.EmailTools).SendEmail($List(case, 2), "A zz subject", "A zz text.")
		Set calls = ..Calls()
		Do $$$AssertEquals(calls.%Size(), 1, $List(case, 1)_": one command was submitted")
		If calls.%Size() = 1 {
			Set fields = calls.%Get(0).fields
			Do $$$AssertEquals(fields.Recipients, "own", $List(case, 1)_": its Recipients is the marker, not an address")
			Do $$$AssertEquals(($ZConvert(fields.%ToJSON(), "L") [ "x.test")_"|"_($ZConvert(fields.%ToJSON(), "L") [ "example.test"), "0|0", $List(case, 1)_": no field of the command holds an address")
		}
	}
}

/// A safe call (the matrix row "Safe send"): one SendEmail is submitted through CommandCall with origin tool and the key <ItemId>:1, with the marker of a tool send as Recipients (the mailbox's own address, whatever spellings or repeats the call listed), the
/// subject and the text. The answer is exactly {ok, outcome, message} of the CommandResult: the double also answers a Ref and a Data that holds the subject, and neither reaches the model. One
/// Action entry is written, and it holds no address, subject or text.
Method TestSafeSend()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mailbox(..#ADDRESS, owner)
	Do ..Begin(owner, itemId)
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set answer = ##class(OcuTalon.Tools.EmailTools).SendEmail(["owner@example.test", " OWNER@EXAMPLE.TEST "], "A zz subject", "A zz text.")
	Do $$$AssertEquals(answer.%ToJSON(), {"ok": true, "outcome": "sent", "message": "The email was sent."}.%ToJSON(), "the answer is {ok, outcome, message} and nothing else")
	Do $$$AssertEquals(..Keys(answer), "message,ok,outcome", "its members are exactly ok, outcome and message: no subject, recipient, ref or data")
	Set calls = ..Calls()
	Do $$$AssertEquals(calls.%Size(), 1, "the double recorded one command")
	If calls.%Size() = 1 {
		Set call = calls.%Get(0)
		Do $$$AssertEquals(call.class_"|"_call.origin_"|"_call.sessionRef_"|"_call.key, "OcuTalon.Msg.Command.SendEmail|tool|"_owner_"|"_itemId_":1", "a SendEmail with origin tool, the session of the call and the key <ItemId>:1")
		Do $$$AssertEquals(call.fields.Recipients_"|"_call.fields.Subject_"|"_call.fields.Text, "own|A zz subject|A zz text.", "to the mailbox's own address by the marker (no address in the command), with the subject and the text")
		Do $$$AssertEquals(..Keys(call.fields), "IdempotencyKey,Origin,Recipients,SessionRef,Subject,Text", "and no other field")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Action", "", "EmailOut", "", 1, 20)
	Set mine = ..EmailEntries(entries)
	Do $$$AssertEquals(mine.%Size(), 1, "one Action entry of the action email is written")
	If mine.%Size() = 1 {
		Set data = mine.%Get(0).data
		Do $$$AssertEquals(data.action_"|"_data.target_"|"_data.result_"|"_data.approvalRef_"|"_data.sessionRef_"|"_data.counts.recipients, "email|EmailOut|sent||"_owner_"|1", "the entry says email, EmailOut, sent, no approval, the session and the number of recipients sent to (the own address once)")
		Set text = mine.%Get(0).%ToJSON()
		Do $$$AssertEquals(($ZConvert(text, "L") [ "example.test")_"|"_(text [ "zz subject")_"|"_(text [ "zz text"), "0|0|0", "and holds no address, subject or text")
	}
	Do $$$AssertEquals(+##class(OcuTalon.Bridge.Context).Current().CommandCount, 1, "the command count of the turn moved to 1")
}

/// With no bridge context, an owner of instance, eval, empty or not a Ref, or an empty ItemId, the answer is NOSESSION and nothing is submitted or audited.
Method TestNoSession()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mailbox(..#ADDRESS, owner)
	Set cases = $ListBuild(
		$ListBuild("no context", 0, "", ""),
		$ListBuild("the owner instance", 1, "instance", itemId),
		$ListBuild("an empty owner", 1, "", itemId),
		$ListBuild("an owner that is not a Ref", 1, "zzOwnerTooShort", itemId),
		$ListBuild("an empty ItemId", 1, owner, ""))
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ##class(OcuTalon.Bridge.Context).End()
		If $List(case, 2) Do ..Begin($List(case, 3), $List(case, 4))
		Set answer = ##class(OcuTalon.Tools.EmailTools).SendEmail(["owner@example.test"], "s", "t")
		Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "message": ($Parameter(..#CALL, "NOSESSION"))}.%ToJSON(), $List(case, 1)_": the answer is NOSESSION")
		Do $$$AssertEquals(..Calls().%Size(), 0, $List(case, 1)_": the double recorded nothing")
	}
	Do $$$AssertEquals(..EmailEntries(##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Action")).%Size(), 0, "and no Action entry was written")
}

/// The online demo: the tool answers not_available with EmailOut's sentence, the double records nothing, the command count does not move and no entry is written; the hook sets that sentence as its
/// refusal and raises nothing, for another address and for the own one. With the flag off the same call sends.
Method TestOnlineDemo()
{
	If '..Prepare() Quit
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set itemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Owners = ..Owners _ $ListBuild(owner)
	Do ..Mailbox(..#ADDRESS, owner)
	Do ..Begin(owner, itemId)
	Set sentence = $Parameter(..#OUT, "MESSAGEUNAVAILABLE")
	Do $$$AssertEquals(sentence, "Email can't be connected on the online demo. Nothing was changed.", "the sentence is EmailOut's demo sentence")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1), "the online demo is on")
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..Requests().%ToJSON()
	Set answer = ##class(OcuTalon.Tools.EmailTools).SendEmail(["owner@example.test"], "s", "t")
	Do $$$AssertEquals(answer.%ToJSON(), {"ok": false, "outcome": "not_available", "message": (sentence)}.%ToJSON(), "the tool answers not_available with EmailOut's sentence")
	Do $$$AssertEquals(..Calls().%Size()_"|"_+##class(OcuTalon.Bridge.Context).Current().CommandCount, "0|0", "nothing was submitted and the command count did not move")
	Do $$$AssertEquals(..EmailEntries(##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Action")).%Size(), 0, "and no entry was written")
	For address = "partner@example.test", "owner@example.test" {
		Set ref = "zz"
		Set refusal = "zz"
		Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", {"recipients": [(address)], "subject": "s", "text": "t"}, owner, "", "", .ref, .refusal)
		Do $$$AssertEquals($$$ISOK(sc)_"|"_ref_"|"_refusal, "1||"_sentence, "the hook refuses with the sentence and raises no request for "_address)
	}
	Do $$$AssertEquals(..Requests().%ToJSON(), before, "no approval request exists")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0), "the online demo is off")
	Set answer = ##class(OcuTalon.Tools.EmailTools).SendEmail(["owner@example.test"], "s", "t")
	Do $$$AssertEquals(answer.outcome, "sent", "control: with the online demo off the same call sends")
	Do $$$AssertEquals(..Calls().%Size(), 1, "and the double recorded it")
}

/// The hook raises nothing and sets EmailOut's sentence for no mailbox address (MESSAGENOTCONNECTED) and for parameters that EmailOut would refuse (MESSAGEREFUSED).
Method TestHoldRefusals()
{
	If '..Prepare() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Owners = ..Owners _ $ListBuild(owner)
	Do ..Mailbox("", "")
	Set before = ..Requests().%ToJSON()
	Do ..AssertRefusal({"recipients": ["partner@example.test"], "subject": "s", "text": "t"}, owner, $Parameter(..#OUT, "MESSAGENOTCONNECTED"), "no mailbox address")
	Do ..Mailbox(..#ADDRESS, owner)
	Set refused = $Parameter(..#OUT, "MESSAGEREFUSED")
	Do $$$AssertEquals(refused, "The email wasn't sent because a recipient, the subject or the text wasn't allowed.", "the sentence is EmailOut's")
	Set long = ""
	For i = 1:1:201 Set long = long _ "x"
	Set cases($Increment(n)) = "no recipient|[]|s|t"
	Set cases($Increment(n)) = "21 recipients|"_..Times("partner@example.test", 21).%ToJSON()_"|s|t"
	Set cases($Increment(n)) = "a malformed address|[""partner""]|s|t"
	Set cases($Increment(n)) = "an address that is no string|[5]|s|t"
	Set cases($Increment(n)) = "an address that is an object|[{""a"":1}]|s|t"
	Set cases($Increment(n)) = "an address that is an array|[[""partner@example.test""]]|s|t"
	Set cases($Increment(n)) = "recipients that is no array|""partner@example.test""|s|t"
	Set cases($Increment(n)) = "an empty subject|[""partner@example.test""]|  |t"
	Set cases($Increment(n)) = "a subject of 201 characters|[""partner@example.test""]|"_long_"|t"
	Set cases($Increment(n)) = "a subject with a line break|[""partner@example.test""]|a"_$Char(10)_"b|t"
	Set cases($Increment(n)) = "an empty text|[""partner@example.test""]|s|"
	Set cases($Increment(n)) = "a text of white space|[""partner@example.test""]|s| "_$Char(10)_" "
	Set cases($Increment(n)) = "a text with a control character|[""partner@example.test""]|s|a"_$Char(7)_"b"
	Set wide = $Translate($Justify("", 60), " ", "x")_"@"_$Translate($Justify("", 45), " ", "d")_".test"
	Set cases($Increment(n)) = "20 valid addresses that, joined, are longer than a SendEmail command holds|"_..Times(wide, 20).%ToJSON()_"|s|t"
	For i = 1:1:n {
		Set arguments = {"subject": ($Piece(cases(i), "|", 3)), "text": ($Piece(cases(i), "|", 4))}
		Set arguments.recipients = {}.%FromJSON("{""r"":"_$Piece(cases(i), "|", 2)_"}").r
		Do ..AssertRefusal(arguments, owner, refused, $Piece(cases(i), "|", 1))
	}
	Do ..AssertRefusal({"recipients": ["partner@example.test"], "text": "t"}, owner, refused, "no subject")
	Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", {"recipients": ["partner@example.test"], "subject": ("Tab"_$Char(9)_"ok"), "text": ("line one"_$Char(10)_"line"_$Char(9)_"two"_$Char(13))}, owner, "", "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(refusal = refused), "1|1", "a tab in the subject is a control character and refuses")
	Do $$$AssertEquals(..Requests().%ToJSON(), before, "no approval request exists")
}

/// A risky call is raised as one fix request of the kind email: the exact row shape (the matrix row "Risky send"), for another address, the own address plus another, and another session's call to the
/// mailbox address.
Method TestHoldRaisesTheRequest()
{
	If '..Prepare() Quit
	Set owner = ..AdminSession()
	Set other = ..AdminSession()
	Set trace = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Mailbox(..#ADDRESS, owner)
	Set cases = $ListBuild(
		$ListBuild("another address", owner, "[""partner@example.test""]"),
		$ListBuild("the own address and another", owner, "[""Owner@Example.test"", "" partner@example.test""]"),
		$ListBuild("another session's call to the mailbox address", other, "[""Owner@Example.test""]"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set who = $List(case, 2)
		Set ..Owners = ..Owners _ $ListBuild(who)
		Set list = {}.%FromJSON("{""r"":"_$List(case, 3)_"}").r
		Set arguments = {"recipients": (list), "subject": "A zz subject", "text": ("A zz text."_$Char(10)_"Second line.")}
		Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", arguments, who, trace, "", .ref, .refusal)
		Do $$$AssertEquals($$$ISOK(sc)_"|"_refusal, "1|", $List(case, 1)_": the hook raises and refuses nothing")
		Do $$$AssertEquals($Length(ref), 22, $List(case, 1)_": it gives the new request's Ref")
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		Do $$$AssertTrue($IsObject(row), $List(case, 1)_": the row exists")
		If '$IsObject(row) Continue
		Set expectedRecipients = []
		Set at = list.%GetIterator()
		While at.%GetNext(, .one) {
			Do expectedRecipients.%Push($ZStrip(one, "<>W"))
		}
		Do $$$AssertEquals(row.Kind_"|"_row.State_"|"_row.FixKind_"|"_row.IncidentRef_"|"_row.ResultTarget, "fix|pending|email||FixExecutor", $List(case, 1)_": a pending fix of the kind email with no incident and the result target FixExecutor")
		Do $$$AssertEquals(row.OwnerRef_"|"_row.TraceRef, who_"|"_trace, $List(case, 1)_": the owner and the trace of the call")
		Do $$$AssertEquals(row.FixTargets, $Select(expectedRecipients.%Size() = 2: "1,2", 1: "1"), $List(case, 1)_": the targets are the recipients' positions")
		Do $$$AssertEquals(row.FixParameters, {"recipients": (expectedRecipients), "subject": "A zz subject", "text": ("A zz text."_$Char(10)_"Second line.")}.%ToJSON(), $List(case, 1)_": FixParameters holds the trimmed recipients as an array, the subject and the text")
		Do $$$AssertEquals(row.DryRun, {"to": (expectedRecipients), "subject": "A zz subject", "text": ("A zz text."_$Char(10)_"Second line.")}.%ToJSON(), $List(case, 1)_": the dry run holds every recipient, the subject and the text exactly")
		Do $$$AssertEquals(row.ToolName_row.ToolArguments_row.ToolSource_row.ToolFingerprint_row.Runner, "", $List(case, 1)_": no Tool or Runner field")
		Do $$$AssertEquals(row.RequiredRole, "OcuTalonUser", $List(case, 1)_": for the role OcuTalonUser")
	}
	Do $$$AssertEquals(..Requests(owner_","_other).%Size(), 3, "three requests exist for the two sessions")
	Set subject = ""
	For i = 1:1:$Parameter(..#OUT, "SUBJECTMAX") Set subject = subject _ "x"
	Set text = $Char(9)_"tab"_$Char(13, 10)_"carriage return and line feed"
	Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", {"recipients": ["partner@example.test"], "subject": (subject), "text": (text)}, owner, trace, "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_refusal_"|"_$Length(ref), "1||22", "a subject of exactly the limit and a text with a tab and a carriage return are raised")
	Set text = ""
	For i = 1:1:$Parameter(..#OUT, "TEXTMAX") Set text = text _ "y"
	Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", {"recipients": ["partner@example.test"], "subject": "s", "text": (text)}, owner, trace, "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_refusal_"|"_$Length(ref), "1||22", "a text of exactly the limit is raised")
	Do $$$AssertEquals($ClassMethod(..#TOOLS, "ClassifySENDEMAIL", {"recipients": ["partner@example.test"], "subject": (subject), "text": (text)}), "risky", "and another address stays risky at the limits")
}

/// Through the gate (Check, the hook of the tool class is found on the origin class): another address in a user's turn is denied with the gate's HELD and one request is raised; the own address
/// is allowed (the hook is not called); an untrusted turn and a tainted turn are denied with UNTRUSTED for the own address and another one, with no request.
Method TestGateDecides()
{
	If '..Prepare() Quit
	Set owner = ..AdminSession()
	Do ..Mailbox(..#ADDRESS, owner)
	Set gate = ..#GATE
	Set held = $Parameter(gate, "HELD")
	Set untrusted = $Parameter(gate, "UNTRUSTED")
	Set other = {"recipients": ["partner@example.test"], "subject": "s", "text": "t"}
	Set own = {"recipients": ["owner@example.test"], "subject": "s", "text": "t"}
	Set ..Owners = ..Owners _ $ListBuild(owner)
	Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals(..Sentence(..Check(other)), held, "another address in a user's turn is denied with HELD")
	Do $$$AssertEquals(..Requests(owner).%Size(), 1, "and one request is raised")
	Do $$$AssertEquals(..Sentence(..Check(own)), "<OK>", "the own address is allowed")
	Do $$$AssertEquals(..Requests(owner).%Size(), 1, "and raises none")
	Do $$$AssertEquals(+##class(OcuTalon.Bridge.Context).Current().Tainted, 0, "a trusted-output tool leaves the turn untainted")
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Requests(owner).%Size()
	For provenance = "untrusted", "user" {
		Do ..Begin(owner, ##class(OcuTalon.Bridge.Ids).NewRef(), provenance)
		If provenance = "user" Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "the turn is tainted")
		Set label = $Select(provenance = "user": "a tainted turn", 1: "an untrusted turn")
		Do $$$AssertEquals(..Sentence(..Check(own)), untrusted, label_": the own address is denied with UNTRUSTED")
		Do $$$AssertEquals(..Sentence(..Check(other)), untrusted, label_": and so is another address")
		Do ##class(OcuTalon.Bridge.Context).End()
	}
	Do $$$AssertEquals(..Requests(owner).%Size(), before, "no request was raised in either")
}

/// --- helpers ---
/// The gate's decision for send_email with the arguments, in the context as it is.
Method Check(arguments As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Policy.Gate).Check("send_email", {"id": "call_id", "name": "send_email", "arguments": (arguments)}, {"origin_class": (..#TOOLS), "requires_auth": false}, "")
}

/// The status text of a denial after the gate's code, "<OK>" for an allowed call.
ClassMethod Sentence(sc As %Status) As %String [ Private ]
{
	If $$$ISOK(sc) Quit "<OK>"
	Set codes = $SYSTEM.Status.GetErrorCodes(sc)
	If codes '= $Parameter(..#GATE, "DENIEDCODE") Quit "<code "_codes_">"
	Set text = $SYSTEM.Status.GetOneStatusText(sc)
	Set prefix = "Tool access denied: "
	Quit $Select($Extract(text, 1, $Length(prefix)) = prefix: $Extract(text, $Length(prefix) + 1, *), 1: text)
}

/// Asserts that the hook sets the sentence as its refusal and raises nothing.
Method AssertRefusal(arguments As %DynamicObject, owner As %String, sentence As %String, label As %String) [ Private ]
{
	Set ref = "zz"
	Set refusal = "zz"
	Set sc = $ClassMethod(..#TOOLS, "HoldSENDEMAIL", arguments, owner, "", "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_ref_"|"_refusal, "1||"_sentence, label_": the hook refuses with the sentence and raises nothing")
}

/// A list of the address repeated count times.
ClassMethod Times(address As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set list = []
	For i = 1:1:count Do list.%Push(address)
	Quit list
}

/// The member names of the object, sorted and comma-separated.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys _ $ListBuild(key)
	}
	Quit $ListToString(..Sorted(keys))
}

ClassMethod Sorted(list As %List) As %List [ Private ]
{
	Set position = 0
	While $ListNext(list, position, value) {
		Set sorted(value) = ""
	}
	Set result = ""
	Set value = ""
	For {
		Set value = $Order(sorted(value))
		Quit:value=""
		Set result = result _ $ListBuild(value)
	}
	Quit result
}

/// The entries of the audit log whose data is an email Action entry.
ClassMethod EmailEntries(entries As %DynamicArray) As %DynamicArray [ Private ]
{
	Set mine = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If $IsObject(entry.data) && (entry.data.%Get("action") = "email") Do mine.%Push(entry)
	}
	Quit mine
}

/// The approval rows of the fix kind email, as the array of their Refs; with owners, only those of the owners in the comma-separated list.
ClassMethod Requests(owners As %String = "") As %DynamicArray [ Private ]
{
	Set refs = []
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, OwnerRef FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE FixKind = 'email' ORDER BY ID")
	While rows.%Next() {
		If (owners = "") || $ListFind($ListFromString(owners), rows.%Get("OwnerRef")) Do refs.%Push(rows.%Get("Ref"))
	}
	Quit refs
}

/// Sets the mailbox keys (an empty address deletes both) and remembers what the test found, for PutBackMailbox.
Method Mailbox(address As %String, owner As %String) [ Private ]
{
	If '$ListLength(..Found) {
		Set ..Found = $ListBuild(##class(OcuTalon.Data.Setting).KeyIndexExists(..#ADDRESSKEY), ##class(OcuTalon.Data.Setting).Get(..#ADDRESSKEY), ##class(OcuTalon.Data.Setting).KeyIndexExists(..#OWNERKEY), ##class(OcuTalon.Data.Setting).Get(..#OWNERKEY))
	}
	If address = "" {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#ADDRESSKEY)
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#OWNERKEY)
		Quit
	}
	Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, address)
	Do ##class(OcuTalon.Data.Setting).Set(..#OWNERKEY, owner)
}

/// Puts the mailbox keys back as the test found them.
Method PutBackMailbox() [ Private ]
{
	If '$ListLength(..Found) Quit
	For pair = $ListBuild(..#ADDRESSKEY, 1, 2), $ListBuild(..#OWNERKEY, 3, 4) {
		If $List(..Found, $List(pair, 2)) {
			Do ##class(OcuTalon.Data.Setting).Set($List(pair, 1), $List(..Found, $List(pair, 3)))
		} Else {
			Do ##class(OcuTalon.Data.Setting).KeyIndexDelete($List(pair, 1))
		}
	}
	Set ..Found = ""
}

/// 1 when the production is ready and the double is behind the CommandsIn item (OnAfterAllTests puts the real service back).
Method Prepare() As %Boolean [ Private ]
{
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	If ..Swap = "" {
		Set sc = $ClassMethod(fixture, "UseItemClass", ..#ITEM, ..#DOUBLE, .saved)
		If $IsObject(saved) Set ..Swap = saved.%ToJSON()
		Do $$$AssertStatusOK(sc, "the double is put behind the "_..#ITEM_" item")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Begins a bridge context in the test process for a turn of the owner with the ItemId and the provenance, as the runner does before Chat.
Method Begin(owner As %String, itemId As %String, provenance As %String = "user") [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = provenance
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of '"_owner_"'")
}

/// The commands that the double recorded, in order, as a dynamic array of {"class","origin","sessionRef","key","fields"}.
ClassMethod Calls() As %DynamicArray [ Private ]
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("CommandsDouble", "calls", n))
		Quit:n=""
		Set record = ^OcuTalonTest("CommandsDouble", "calls", n)
		Do calls.%Push({"class": ($List(record, 1)), "origin": ($List(record, 2)), "sessionRef": ($List(record, 3)), "key": ($List(record, 4)), "fields": ({}.%FromJSON($List(record, 5)))})
	}
	Quit calls
}

}
