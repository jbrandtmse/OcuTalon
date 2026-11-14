/// Tests of the approval card of an email request (Story 22.7, DW-1261; AD-16): Live.Payload.Approval.FromRow shows the recipients, the subject and the text that the stored request holds, exactly,
/// and never the text of an object reference. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need the running OcuTalon.Production (a request is raised through the approval service) and the
/// instance's own web server, which TestStateShowsTheStoredEmail signs in to as two fixture IRIS users of the role OcuTalonUser (made and deleted through Security.Users in %SYS, with passwords from $Random
/// that are never printed), as Test.Install.PasswordGuard.SignInChange does. No mail is sent: no test here approves anything. Each test puts back the mailbox address and the onlineDemo flag it found.
///   - TestCardHoldsTheStoredEmail: a request that the real Fix.Kind.Email.Raise raised (two recipients, a subject with a non-ASCII letter, a text of several lines, quotes and a long line): the payload's
///     recipients are the stored addresses as plain strings in order, its notice the exact text and its before the exact subject; every other member of the part is empty, simulated and eitherWay are 0
///     and there is no reading; the payload's JSON holds no object reference (2@%Library.DynamicArray) and the same members;
///   - TestUnexpectedDryRunsGiveAPartNotAnError: a dry run whose to is a string, an array with a member that is not a string, an array of objects, whose subject or text is not a string, an empty one, an
///     array and one that is not JSON gives a payload and no error, with no recipient and only the members that are strings;
///   - TestStateShowsTheStoredEmail (real HTTP): with the fixture user signed in (the durable session attaches on its first GET of /api/v1/state), a request raised for that session shows in the rail's approvals
///     with the recipients, the subject and the text of the stored row, and nothing of an object reference; a second signed-in user's state shows no such approval and none of its words.
Class OcuTalon.Test.Fix.EmailCard Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzemailcard";

/// The address of the mailbox of the tests (the key email.address that a raise needs), and the recipients of the request.
Parameter ADDRESS = "owner@example.test";

Parameter FIRST = "partner@example.test";

Parameter SECOND = "Second@Example.test";

/// The product key and the settings that the tests change.
Parameter ADDRESSKEY = "email.address";

/// The state to put back: $ListBuild(address row exists, address, onlineDemo), or "" while nothing was changed.
Property Found As %List [ Private ];

/// The IRIS users that a test made, comma-separated: OnAfterOneTest deletes them.
Property Users As %String(MAXLEN = "") [ Private ];

/// The sessions whose approval rows a test may have made: OnAfterOneTest ends and deletes every row they own.
Property Owners As %String(MAXLEN = "") [ Private ];

/// The requests that SignIn signed in: OnAfterOneTest signs each one out, on every path of a test.
Property SignedIn As list Of %Net.HttpRequest [ Private ];

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:..SignedIn.Count() {
		Do ..SignOut(..SignedIn.GetAt(i))
	}
	Do ..SignedIn.Clear()
	For i = 1:1:$Length(..Owners, ",") {
		If $Piece(..Owners, ",", i) '= "" Do ##class(OcuTalon.Test.Bridge.Approval).TrackOwner($Piece(..Owners, ",", i))
	}
	Set ..Owners = ""
	If $Data(^OcuTalonTest("Approval", "refs")) || $Data(^OcuTalonTest("Approval", "job")) Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	For i = 1:1:$Length(..Users, ",") {
		Do ##class(OcuTalon.Test.Install.PasswordGuard).RemoveUser($Piece(..Users, ",", i))
	}
	Set ..Users = ""
	If ..Found '= "" {
		If $List(..Found, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, $List(..Found, 2))
		} Else {
			Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(..#ADDRESSKEY)
		}
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $List(..Found, 3))
		Set ..Found = ""
	}
	Quit $$$OK
}

/// The set-up of every test: the production runs, the mailbox has an address and the online demo is off. 1 when all that holds.
Method Setup() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	If ..Found = "" Set ..Found = $ListBuild(##class(OcuTalon.Data.Setting).KeyIndexExists(..#ADDRESSKEY), ##class(OcuTalon.Data.Setting).Get(..#ADDRESSKEY), ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"))
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Data.Setting).Set(..#ADDRESSKEY, ..#ADDRESS)
	Quit 1
}

/// Raises the request of an email call through the real Fix.Kind.Email.Raise for the owner session; its Ref ("" when nothing was raised, which fails the assertion). Raise refuses a requester who is
/// no admin (Story 25.5), so a session of a fixture name belongs to the README admin before the raise (asAdmin 1); a session of a real fixture user that holds OcuTalonAdmin keeps its user (asAdmin 0).
Method RaiseFor(owner As %String, recipients As %DynamicArray, subject As %String, text As %String, asAdmin As %Boolean = 1) As %String [ Private ]
{
	Set ..Owners = ..Owners _ $Select(..Owners = "": "", 1: ",") _ owner
	If asAdmin {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(owner)
		Set session.IrisUser = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
		Do $$$AssertStatusOK(session.%Save(), "the requester is the README admin")
		Kill session
	}
	Set sc = ##class(OcuTalon.Fix.Kind.Email).Raise({"recipients": (recipients), "subject": (subject), "text": (text)}, owner, ##class(OcuTalon.Bridge.Ids).NewRef(), "", .ref, .refusal)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_(ref '= "")_"|"_refusal, "1|1|", "the request is raised")
	Quit ref
}

/// The stored row of the request, read afresh.
Method RowOf(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Kill row
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the stored request exists")
	Quit row
}

/// The payload's part of an email request holds the stored recipients, subject and text exactly, as plain strings, and nothing else.
Method TestCardHoldsTheStoredEmail()
{
	If '..Setup() Quit
	Set owner = ..Session("a")
	Set subject = "Zz subject "_$Char(233)_"t"_$Char(233)_" ""quoted"""
	Set longLine = $Translate($Justify("", 3000), " ", "x")
	Set text = "Line one, with ""quotes"" and a backslash \"_$Char(10)_"Line two"_$Char(13, 10)_"Line three "_$Char(8364)_" "_longLine
	Set ref = ..RaiseFor(owner, [(..#FIRST), (..#SECOND)], subject, text)
	If ref = "" Quit
	Set row = ..RowOf(ref)
	Set stored = {}.%FromJSON(row.DryRun)
	Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row, owner)
	Do $$$AssertEquals(payload.Kind_"|"_payload.State_"|"_payload.FixKind_"|"_payload.IncidentRef, "fix|pending|email|", "the payload is of a pending fix of the kind email with no incident")
	Set part = payload.DryRun
	Do $$$AssertTrue($IsObject(part), "it has a dry-run part")
	If '$IsObject(part) Quit
	Do $$$AssertEquals(part.Recipients.Count(), 2, "with two recipients")
	Do $$$AssertEquals(part.Recipients.GetAt(1)_"|"_part.Recipients.GetAt(2), ..#FIRST_"|"_..#SECOND, "the addresses as they were raised, in order, as plain strings")
	Do $$$AssertEquals(part.Recipients.GetAt(1)_"|"_part.Recipients.GetAt(2), stored.to.%Get(0)_"|"_stored.to.%Get(1), "and equal to the stored dry run's")
	Do $$$AssertEquals(part.Notice, text, "the notice is the exact text")
	Do $$$AssertEquals(part.Notice, stored.text, "which is the stored dry run's")
	Do $$$AssertEquals(part.Before, subject, "before is the exact subject")
	Do $$$AssertEquals(part.Before, stored.subject, "which is the stored dry run's")
	Do $$$AssertEquals(part.Affected_"|"_part.Resend_"|"_part.LeftOut_"|"_part.Field_"|"_part.After_"|"_part.Item_"|"_part.From_"|"_part.To_"|"_part.Example_"|"_part.Reading, "|||||||||", "every other text or number of the part is empty")
	Do $$$AssertEquals($IsObject(part.ItemNoun)_"|"_part.Simulated_"|"_part.EitherWay, "0|0|0", "with no item noun, not simulated, not either way")
	Do payload.%JSONExportToString(.json)
	Do $$$AssertEquals(json [ "%Library.DynamicArray", 0, "the JSON holds no object reference")
	Do $$$AssertEquals(json [ "@%", 0, "and nothing that reads like one")
	Set card = {}.%FromJSON(json)
	Do $$$AssertEquals(card.dryRun.recipients.%Size()_"|"_card.dryRun.recipients.%Get(0)_"|"_card.dryRun.recipients.%Get(1), "2|"_..#FIRST_"|"_..#SECOND, "the JSON's recipients are the addresses")
	Do $$$AssertEquals(card.dryRun.notice_"|"_card.dryRun.before, text_"|"_subject, "its notice and before are the text and the subject, as parsed back")
}

/// A dry run of an email request that is not as expected gives a payload and no error: the members that are not strings are left out.
Method TestUnexpectedDryRunsGiveAPartNotAnError()
{
	If '..Setup() Quit
	Set owner = ..Session("a")
	Set cases = $ListBuild(
		$ListBuild("to is a string", "{""to"": ""a@x.test"", ""subject"": ""s"", ""text"": ""t""}", 0, "t", "s"),
		$ListBuild("to holds a number", "{""to"": [""a@x.test"", 5], ""subject"": ""s"", ""text"": ""t""}", 0, "t", "s"),
		$ListBuild("to holds an object", "{""to"": [{""x"": 1}], ""subject"": ""s"", ""text"": ""t""}", 0, "t", "s"),
		$ListBuild("to holds an array", "{""to"": [[""a@x.test""]], ""subject"": ""s"", ""text"": ""t""}", 0, "t", "s"),
		$ListBuild("subject and text are not strings", "{""to"": [""a@x.test""], ""subject"": 1, ""text"": null}", 1, "", ""),
		$ListBuild("an empty object", "{}", 0, "", ""),
		$ListBuild("an array", "[1, 2]", 0, "", ""),
		$ListBuild("not JSON", "not json", 0, "", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, "", "pending", , {"FixKind": "email", "ResultTarget": "FixExecutor", "FixParameters": "{}", "DryRun": ($List(case, 2))})
		Set ..Refs = ..Refs _ ","_ref
		Set row = ..RowOf(ref)
		Set thrown = 0
		Try {
			Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(row, owner)
		} Catch {
			Set thrown = 1
		}
		Do $$$AssertEquals(thrown, 0, label_": FromRow raises no error")
		If thrown Continue
		Set part = payload.DryRun
		If '$IsObject(part) {
			Do $$$AssertTrue(($Extract($List(case, 2)) '= "{") && ($List(case, 3) = 0) && ($List(case, 4) = "") && ($List(case, 5) = ""), label_": only a dry run that is not a JSON object leaves no part, and it has nothing to show")
			Continue
		}
		Do $$$AssertEquals(part.Recipients.Count()_"|"_part.Notice_"|"_part.Before, $List(case, 3)_"|"_$List(case, 4)_"|"_$List(case, 5), label_": the part holds only what is a string")
		Do payload.%JSONExportToString(.json)
		Do $$$AssertEquals(json [ "%Library", 0, label_": and its JSON holds no object reference")
	}
}

/// The real route: the state of a signed-in user shows the request of that user's session with the stored recipients, subject and text, and another signed-in user sees none of it.
Method TestStateShowsTheStoredEmail()
{
	If '..Setup() Quit
	Set passwordOne = "Zz-email-card-"_$Random(1000000)
	Set passwordTwo = "Zz-email-card-"_$Random(1000000)
	Set one = ..MakeUser("one", passwordOne, "OcuTalonUser,OcuTalonAdmin")
	Set two = ..MakeUser("two", passwordTwo)
	If (one = "") || (two = "") Quit
	Set sessionOne = ##class(OcuTalon.Test.Data.Fixture).Session(one)
	Set sessionTwo = ##class(OcuTalon.Test.Data.Fixture).Session(two)
	Set ..Refs = ..Refs _ "," _ sessionOne _ "," _ sessionTwo
	Set ..Sessions = ..Sessions _ "," _ sessionOne _ "," _ sessionTwo
	Set requestOne = ..SignIn(one, passwordOne)
	Set requestTwo = ..SignIn(two, passwordTwo)
	If '$IsObject(requestOne) || '$IsObject(requestTwo) Quit
	Set state = ..State(requestOne, .body)
	Do $$$AssertEquals($IsObject(state) && (state.user = one), 1, "the first user's state is the first user's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForUser(one).Ref, sessionOne, "and its durable session is the one of the fixture")
	Do $$$AssertEquals($IsObject(state) && (state.rail.approvals.%Size() = 0), 1, "with no approval yet")

	Set subject = "Zz card subject "_$Char(233)
	Set text = "Zz card text"_$Char(10)_"second line with ""quotes"""
	Set ref = ..RaiseFor(sessionOne, [(..#FIRST), (..#SECOND)], subject, text, 0)
	If ref = "" Quit
	Set row = ..RowOf(ref)
	Set stored = {}.%FromJSON(row.DryRun)
	Set state = ..State(requestOne, .body)
	Set card = ..CardOf(state, ref)
	Do $$$AssertTrue($IsObject(card), "the rail of the first user holds the request")
	If $IsObject(card) {
		Do $$$AssertEquals(card.kind_"|"_card.fixKind_"|"_card.state, "fix|email|pending", "a pending fix of the kind email")
		Do $$$AssertEquals($IsObject(card.dryRun) && (card.dryRun.%GetTypeOf("recipients") = "array"), 1, "the card's dry run has its recipients as an array")
		If '($IsObject(card.dryRun) && (card.dryRun.%GetTypeOf("recipients") = "array")) Set card = ""
	}
	If $IsObject(card) {
		Do $$$AssertEquals(card.dryRun.recipients.%Size()_"|"_card.dryRun.recipients.%Get(0)_"|"_card.dryRun.recipients.%Get(1), "2|"_stored.to.%Get(0)_"|"_stored.to.%Get(1), "the card's recipients are the stored addresses, as addresses")
		Do $$$AssertEquals(card.dryRun.recipients.%Get(0)_"|"_card.dryRun.recipients.%Get(1), ..#FIRST_"|"_..#SECOND, "and the ones that were raised")
		Do $$$AssertEquals(card.dryRun.before, stored.subject, "the card's subject is the stored subject")
		Do $$$AssertEquals(card.dryRun.notice, stored.text, "the card's text is the stored text")
	}
	Do $$$AssertEquals(body [ "DynamicArray", 0, "the state holds no object reference")
	Do $$$AssertEquals(body [ "@%Library", 0, "and nothing that reads like one")

	Set other = ..State(requestTwo, .otherBody)
	Do $$$AssertEquals($IsObject(other) && (other.user = two), 1, "the second user's state is the second user's")
	Do $$$AssertEquals($IsObject(other) && '$IsObject(..CardOf(other, ref)), 1, "and it shows no such approval")
	Do $$$AssertEquals((otherBody [ ref)_"|"_(otherBody [ ..#FIRST)_"|"_(otherBody [ "Zz card"), "0|0|0", "nor its Ref, its recipients or its words")
}

/// Makes an IRIS user of the role OcuTalonUser with the password; its name, or "" when it could not be made. OnAfterOneTest deletes it.
Method MakeUser(name As %String, password As %String, roles As %String = "OcuTalonUser") As %String [ Private ]
{
	Set user = "zzemailcard"_name_..Number
	Set sc = ..CreateUser(user, password, roles)
	Do $$$AssertStatusOK(sc, "the fixture user "_user_" of the roles "_roles_" is made")
	If $$$ISERR(sc) Quit ""
	Set ..Users = ..Users _ $Select(..Users = "": "", 1: ",") _ user
	Quit user
}

/// The status of Security.Users.Create for the user with the role OcuTalonUser. Runs in %SYS.
ClassMethod CreateUser(user As %String, password As %String, roles As %String = "OcuTalonUser") As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.Users).Create(user, roles, password, "OcuTalon test fixture", "OCUTALON", "", "", 0, 1, "Created by a test; the test deletes it.", 1, "", "", , 1, 1)
}

/// A request to the instance's own web server that is signed in as the user (the sign-in form of the web application, as Test.Install.PasswordGuard.SignInChange posts it); it keeps the session cookie,
/// and OnAfterOneTest signs it out. "" when the sign-in did not give the session of the user.
Method SignIn(user As %String, password As %String) As %Net.HttpRequest [ Private ]
{
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ##class(OcuTalon.Test.Install.PasswordGuard).#PORT
	Do request.InsertFormData("IRISUsername", user)
	Do request.InsertFormData("IRISPassword", password)
	Do request.InsertFormData("IRISLogin", "Login")
	Set sc = request.Post("/ocutalon/")
	Do $$$AssertStatusOK(sc, "the sign-in of "_user_" is posted")
	If $$$ISERR(sc) Quit ""
	Do ..SignedIn.Insert(request)
	Do $$$AssertEquals(request.HttpResponse.StatusCode, 303, "and answered with the redirect of a sign-in")
	Quit request
}

/// Signs the request's user out, as SignInChange does.
Method SignOut(request As %Net.HttpRequest) [ Private ]
{
	Do request.Reset()
	Do request.SetParam("IRISLogout", "end")
	Do request.Get("/ocutalon/")
}

/// The state of the signed-in user (GET /ocutalon/api/v1/state) as a dynamic object, "" when it is not a 200 with JSON; body is the response's text.
Method State(request As %Net.HttpRequest, Output body As %String) As %DynamicObject [ Private ]
{
	Set body = ""
	Do request.Reset()
	Set sc = request.Get("/ocutalon/api/v1/state")
	Do $$$AssertStatusOK(sc, "the state is requested")
	If $$$ISERR(sc) || '$IsObject(request.HttpResponse) Quit ""
	Do $$$AssertEquals(request.HttpResponse.StatusCode, 200, "and answered 200")
	Set data = request.HttpResponse.Data
	If $IsObject(data) {
		While 'data.AtEnd {
			Set body = body _ data.Read(20000)
		}
	} Else {
		Set body = data
	}
	If request.HttpResponse.StatusCode '= 200 Quit ""
	Set state = ""
	Try {
		Set state = {}.%FromJSON(body)
	} Catch {
		Do $$$AssertTrue(0, "the state is JSON")
	}
	Quit state
}

/// The card of the request in the rail's approvals of the state, or "".
ClassMethod CardOf(state As %DynamicObject, ref As %String) As %DynamicObject [ Private ]
{
	If '$IsObject(state) Quit ""
	Set found = ""
	Set iterator = state.rail.approvals.%GetIterator()
	While iterator.%GetNext(, .card) {
		If card.ref = ref Set found = card
	}
	Quit found
}

}
