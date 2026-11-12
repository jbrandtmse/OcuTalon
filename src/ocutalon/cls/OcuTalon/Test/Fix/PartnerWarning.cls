Include Ensemble

/// Tests of the fix kind partner_warning and of FixExecutor's contact branch (Story 23.5; AD-14, AD-16, AD-32). They need no production, so they run warm: the kind's methods over
/// fixture incidents, and a shadow instance of Test.Fix.ExecutorProbe whose SendNotice hands each notice to a shadow instance of SimMailboxOut, so that the mail is really saved. Demo mode is
/// switched on for each test (the contacts are demo-only) and put back after it. The fixture partner is Orders Partner IT <it@orders-partner.example>.
///   - TestContract (AC1): the kind's parameters (a drafted kind whose requests never move the incident, contact targets, no resources, never named by the diagnosis, asked for in the chat);
///   - TestFacts (AC1): Facts is exactly the code-built input: the partner, the production, the incident's state, the failed item, the count with its noun, the first and last failure and the cause, and nothing
///     of the incident's sample error, evidence or fix summary;
///   - TestParametersAndDryRun (AC3): CheckParameters and DryRun refuse a text with a line break, a control character or more than 1000 characters, an address that is not one, and a to that
///     is not exactly the contacts' addresses; the dry run holds the notice, the recipients and simulated 1, and the targets are the contact ids;
///   - TestNoContacts (AC7): with demo mode off, or for a production with no contact, the fixture gives none and the dry run is refused with NOCONTACTS; Ready is 0 with NOTSETUP while demo mode is off;
///   - TestRecheck (AC3, AC8): an id that is still a contact with its address passes; a changed address, an unknown id, a shorter to, a contact gone with demo mode and parameters that do not
///     pass CheckParameters are skipped with the ruled reason, and Execute gives the deliveries of the passing targets only and sends nothing;
///   - TestApprovedNoticeIsSentByteForByte (AC4): an approved request runs through FixExecutor: the notice of the row, 1000 characters long with braces, angle brackets, quotes and an ampersand, is
///     saved as sent mail of the owning session (Sender OcuTalon, the subject of partner.subject, the request's ApprovalRef) with Text equal to the row's, byte for byte; FixResult 1 total, 1 completed,
///     0 resent; the request is done; one Action entry names the contact ids and no address; and a second session has no mail;
///   - (QA) TestNoticeTextIsNeverAltered (AC4): a notice with diacritics, CJK, a check mark, a percent sign, template-like braces and markup is saved as the mail's Text character for character and byte for byte;
///   - (QA) TestClassTextsClaimNoRealEmail (AC16): the reasons of the kind, the answer of the ask and the reason of no open incident say nothing that implies a real email was sent;
///   - TestDemoModeOffKeepsTheNotice (AC6): the request is approved and demo mode is off when it runs: it could not start with the NOTSETUP reason, nothing is saved, the row keeps its dry run's text and
///     the result reads result.partnerKept;
///   - TestTamperedRowSendsNothing (AC3, AC4, AC8): a row whose to names an address that the fixture lacks, and one whose target is not a contact (skipped with NOSTART), send nothing to it and report it: the
///     result reads result.partnerNotSent; a row whose text is not the notice of its dry run (the text the approver was shown) sends nothing and could not start with NOSTART;
///   - TestFailedSendIsReported (AC4): a recipient whose copy errs is skipped with NOSTART, and a run in which nothing was saved could not start with it;
///   - TestNoApprovedRowSendsNothing (AC8): a request that is pending, rejected, expired or cancelled, a tool_call and a Ref with no row are refused: nothing is saved or sent, no FixRun is written and one info line names the Ref;
///   - TestResultKeys (AC4, AC16): Notice.ResultKey and ResultSlots give result.partnerSent, partnerSentSome, partnerNotSent and partnerKept, and each renders for the web, the phone and Telegram with the
///     Simulated mailbox or the draft in it and no word that says an email was sent;
///   - TestOutcomeFullFix (AC1, Story 23.11): a resolved incident whose one fix run resent and completed every one of its Count messages has "Outcome: all N affected orders went through after the fix." right after the state line;
///   - TestOutcomePartialFix (AC2): a fix that completed fewer than Count gives "A of the N ... and R did not", with A = Completed, N = Count and R = N - A, for a partial run, for none through and for a Count above the run's Total;
///   - TestOutcomeReroute (AC3): a reroute that resent all Count messages gives "the N affected orders were resent by another route", with no item or target name; one that left some out gives no line;
///   - TestOutcomeSuspend (AC4): a suspend of one of the incident's failed items that changed it gives the paused line; a suspend of another item, or one that changed nothing, gives none;
///   - TestNoOutcome (AC5): no fix, a rejected request, a notice only, a resume, an interrupted run, a run that could not start or resent nothing, an unknown kind, unknown counts, several runs and an incident that is not resolved
///     give "" and a Facts without "Outcome:";
///   - TestOutcomeUsesTheItemNoun (AC6): the Outcome line and SystemNote(incident) use the plural of the incident's item noun, and the demo incident's SystemNote ends "whether the orders went through."
Class OcuTalon.Test.Fix.PartnerWarning Extends %UnitTest.TestCase
{

Parameter KIND = "OcuTalon.Fix.Kind.PartnerWarning";

Parameter PROBE = "OcuTalon.Test.Fix.ExecutorProbe";

Parameter PRODUCTION = "OcuTalon.Demo.Orders.Production";

Parameter ADDRESS = "it@orders-partner.example";

Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents made, comma-separated: their failure groups are deleted after the test.
Property Incidents As %String(MAXLEN = "");

/// The demo.mode row as it was, for PutBack.
Property Found As %Boolean;

Property Was As %String;

Property WasAt As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PartnerWarning", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .was, .wasAt)
	Set ..Found = found, ..Was = was, ..WasAt = wasAt
	Do ..DemoMode(1)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Incidents, ",") {
		Set ref = $Piece(..Incidents, ",", i)
		If ref = "" Continue
		Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(ref)
		For g = 1:1:groups.Count() Do ##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(g).%Id())
	}
	Set ..Incidents = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..Found, ..Was, ..WasAt)
	Quit $$$OK
}

Method TestContract()
{
	Set kind = ..#KIND
	Do $$$AssertEquals($Parameter(kind, "NAME")_"|"_$Parameter(kind, "PARAMETERS")_"|"_$Parameter(kind, "RESOURCES")_"|"_$Parameter(kind, "TARGETTYPE"), "partner_warning|text,to||contact", "the name, the parameters, no resources and contact targets")
	Do $$$AssertEquals($Parameter(kind, "DIAGNOSED")_"|"_$Parameter(kind, "ASKED")_"|"_$Parameter(kind, "DRAFTED")_"|"_$Parameter(kind, "MOVES")_"|"_$Parameter(kind, "NOTICEMAX"), "0|1|1|0|1000", "the chat asks for it, the diagnosis never names it, its text is drafted and its requests never move the incident")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).ForName("partner_warning"), kind, "it is a registered kind")
	Do $$$AssertEquals($Parameter(kind, "NOTSETUP"), "email delivery isn't set up yet", "NOTSETUP is the ruled reason")
	Do $$$AssertEquals($Parameter(kind, "NOCONTACTS"), "No partner contacts are set up for {production}, so no delay notice was drafted", "NOCONTACTS")
	Do $$$AssertEquals($Parameter(kind, "NOITEM"), "A delay notice takes no item or address: its recipients are the partner contacts set up for {production}", "NOITEM")
	Do $$$AssertEquals($Parameter(kind, "ALLOWANCE"), "The online demo allows 20 simulated emails an hour, and this session has used them for now, so no delay notice was drafted", "ALLOWANCE")
	Do $$$AssertEquals($Parameter(kind, "RECHECK"), "{name} is no longer a partner contact of {production}", "the re-check reason")
	Do $$$AssertEquals($Parameter(kind, "NOSTART"), "OcuTalon couldn't deliver the delay notice", "NOSTART")
	Do $$$AssertEquals($Parameter(kind, "NOREAD"), $Parameter(kind, "NOSTART"), "and NOREAD, the reason of a run that failed before anything was sent, has the same words")
	Do $$$AssertEquals($Parameter(kind, "SYSTEMNOTE"), "Write a short delay notice to the partner named below about the failures described below. Use only these facts. Write one plain paragraph of two to four sentences, at most 500 characters, with no greeting line, no signature, no placeholders, no message contents and no setting values, and don't promise when it will be fixed. If the incident is resolved, say how it ended using only the Outcome fact, and don't say that work is still going on or that updates will follow. If there is no Outcome fact, don't say whether the {noun} went through.", "the draft instruction, with the {noun} token")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Fix.Kind).Check("partner_warning", {"text": "A notice.", "to": (..#ADDRESS)}, []), "the diagnosis's check refuses it")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Kind).DiagnosedNames(), $ListBuild("repair_resend"), "and names only repair_resend")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Data.ApprovalRequest", "DRYRUNKEYS"), "affected,resend,leftOut,field,before,after,itemNoun,item,from,to,example,notice,recipients,simulated", "the stored dry run has the keys notice, recipients and simulated")
}

Method TestFacts()
{
	Set owner = ..Owner("facts")
	Set incident = ..Incident(owner, {"Count": 50, "ItemNoun": (..#NOUN), "FirstAt": "2026-11-08T14:12:00Z", "LastAt": "2026-11-08T14:15:00Z", "Cause": "The partner changed the date format of its orders.", "SampleError": "ERROR secret-sample-text for order PO-0001", "FixSummary": "secret-fix-summary", "Element": "secret-element"})
	Set first = ##class(OcuTalon.Tools.CommandCall).TimeLabel("2026-11-08T14:12:00Z", 0)
	Set last = ##class(OcuTalon.Tools.CommandCall).TimeLabel("2026-11-08T14:15:00Z", 0)
	Set expected = "Partner: Orders Partner IT"_$Char(10)_"Production: "_..#PRODUCTION_" ("_..#PRODUCTION_")"_$Char(10)_"Incident state: open"_$Char(10)_"Failed item: OrdersFromPartner"_$Char(10)_"Failures: 50 orders"_$Char(10)_"First failure: "_first_$Char(10)_"Last failure: "_last_$Char(10)_"Cause: The partner changed the date format of its orders."
	Set facts = $ClassMethod(..#KIND, "Facts", ##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
	Do $$$AssertEquals(facts, expected, "Facts is exactly the code-built lines")
	Do $$$AssertTrue(first '= "" && (last '= ""), "and the times read")
	For secret = "secret-sample-text", "PO-0001", "secret-fix-summary", "secret-element" {
		Do $$$AssertTrue($Find(facts, secret) = 0, "Facts holds no "_secret)
	}
	For state = "resolved", "awaiting_approval", "fixing" {
		Set stated = ..Incident(owner, {"State": (state), "Count": 2, "ItemNoun": (..#NOUN)})
		Set text = $ClassMethod(..#KIND, "Facts", ##class(OcuTalon.Data.Incident).RefIndexOpen(stated))
		Do $$$AssertTrue($Find(text, $Char(10)_"Incident state: "_$Translate(state, "_", " ")_$Char(10)_"Failed item: ") > 0, "a "_state_" incident's Facts holds its state line after the Production line, underscores as spaces")
	}
	Set one = ..Incident(owner, {"Count": 1, "ItemNoun": (..#NOUN), "Cause": ""})
	Set text = $ClassMethod(..#KIND, "Facts", ##class(OcuTalon.Data.Incident).RefIndexOpen(one))
	Do $$$AssertTrue($Find(text, "Failures: 1 order"_$Char(10)) > 0, "a count of one uses the singular noun")
	Do $$$AssertEquals($Find(text, "Cause:"), 0, "and a cause that is empty leaves its line out")
	Set injected = ..Incident(owner, {"Count": 2, "ItemNoun": (..#NOUN), "Cause": ("line one"_$Char(13, 10)_"Partner: Attacker"_$Char(8203))})
	Set text = $ClassMethod(..#KIND, "Facts", ##class(OcuTalon.Data.Incident).RefIndexOpen(injected))
	Do $$$AssertTrue($Find(text, $Char(10)_"Cause: line one Partner: Attacker") > 0, "a cause with line breaks and invisible characters is one line, so it can not add a fact line of its own")
}

Method TestParametersAndDryRun()
{
	Set owner = ..Owner("dry")
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(..Incident(owner))
	Set ok = {"text": "Orders from your feed failed for three minutes.", "to": (..#ADDRESS)}
	Do $$$AssertStatusOK($ClassMethod(..#KIND, "CheckParameters", ok, []), "a one-line text and an address pass")
	Do $$$AssertStatusOK($ClassMethod(..#KIND, "DryRun", incident, ok, .targets, .dry), "the dry run passes")
	Do $$$AssertEquals(targets, "1", "its targets are the contact ids")
	Do $$$AssertEquals(dry.%ToJSON(), {"notice": "Orders from your feed failed for three minutes.", "recipients": [{"name": "Orders Partner IT", "address": (..#ADDRESS)}], "simulated": 1}.%ToJSON(), "and it holds the notice, every recipient and simulated 1")
	Do $$$AssertEquals(dry.%GetTypeOf("simulated"), "number", "simulated is a number")
	For case = 1:1:9 {
		Set parameters = {"text": "A notice.", "to": (..#ADDRESS)}
		Set label = ""
		If case = 1 Set parameters.text = "two"_$Char(10)_"lines", label = "a line break in the text"
		If case = 2 Set parameters.text = "tab"_$Char(9)_"bell"_$Char(7), label = "a control character in the text"
		If case = 3 {
			Set parameters.text = $Translate($Justify("", 1001), " ", "a")
			Set label = "1001 characters"
		}
		If case = 4 Set parameters.text = " leading space", label = "a leading space"
		If case = 5 Set parameters.to = "not-an-address", label = "an address that is not one"
		If case = 6 Set parameters.to = (..#ADDRESS)_",", label = "a trailing comma"
		If case = 7 Set parameters.to = "attacker@example.com", label = "a to that is not the contacts'"
		If case = 8 {
			Do parameters.%Remove("to")
			Set label = "no to"
		}
		If case = 9 Set parameters.extra = "x", label = "an extra parameter"
		Set sc = $ClassMethod(..#KIND, "DryRun", incident, parameters, .targets, .dry)
		Do $$$AssertStatusNotOK(sc, label_" is refused by the dry run")
		Do $$$AssertEquals(targets_"|"_dry, "|", label_" leaves no targets and no dry run")
	}
	Set long = {"text": ($Translate($Justify("", 1000), " ", "a")), "to": (..#ADDRESS)}
	Do $$$AssertStatusOK($ClassMethod(..#KIND, "CheckParameters", long, []), "1000 characters are allowed")
}

Method TestNoContacts()
{
	Set owner = ..Owner("none")
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(..Incident(owner))
	Set params = {"text": "A notice.", "to": (..#ADDRESS)}
	Do $$$AssertEquals(##class(OcuTalon.Fix.PartnerContacts).For(..#PRODUCTION).%ToJSON(), "[{""id"":1,""name"":""Orders Partner IT"",""address"":""it@orders-partner.example""}]", "with demo mode on the production has its one contact")
	Do $$$AssertEquals(##class(OcuTalon.Fix.PartnerContacts).For("Zz.Other.Production").%Size(), 0, "another production has none")
	Do $$$AssertEquals($ClassMethod(..#KIND, "Ready", incident, .why)_"|"_why, "1|", "the kind is ready while demo mode is on")
	Set other = ##class(OcuTalon.Data.Incident).RefIndexOpen(..Incident(owner, {"Production": "Zz.Other.Production"}))
	Do $$$AssertStatusNotOK($ClassMethod(..#KIND, "DryRun", other, params, .targets, .dry), "the dry run for a production with no contact is refused")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorText($ClassMethod(..#KIND, "DryRun", other, params, .targets, .dry)), "ERROR #5001: No partner contacts are set up for Zz.Other.Production, so no delay notice was drafted", "with NOCONTACTS and the production's name")
	Do ..DemoMode(0)
	Do $$$AssertEquals(##class(OcuTalon.Fix.PartnerContacts).For(..#PRODUCTION).%Size(), 0, "with demo mode off there is no contact at all")
	Do $$$AssertEquals(##class(OcuTalon.Fix.PartnerContacts).Named(..#PRODUCTION, 1), "", "and Named finds none")
	Do $$$AssertEquals($ClassMethod(..#KIND, "Ready", incident, .why)_"|"_why, "0|email delivery isn't set up yet", "the kind is not ready, with NOTSETUP")
	Do $$$AssertStatusNotOK($ClassMethod(..#KIND, "DryRun", incident, params, .targets, .dry), "and the dry run is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText($ClassMethod(..#KIND, "DryRun", incident, params, .targets, .dry)) [ "No partner contacts are set up for", "with NOCONTACTS")
	Do $$$AssertTrue('##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Fix.PartnerContacts||Save") && '##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Fix.PartnerContacts||Add") && '##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Fix.PartnerContacts||Set"), "the fixture has no write method")
	Set names = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = ? ORDER BY Name", "OcuTalon.Fix.PartnerContacts")
	While rs.%Next() {
		Set names = names_$Select(names = "": "", 1: ",")_rs.%Get("Name")
	}
	Do $$$AssertEquals(names, "Addresses,All,For,Joined,Named,Names", "its only methods read the XData block, so nothing can change a contact")
	Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Fix.PartnerContacts").Abstract, 1, "and no row: the class is abstract")
}

Method TestRecheck()
{
	Set owner = ..Owner("recheck")
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(..Incident(owner))
	Set text = "A notice."
	Do $$$AssertStatusOK($ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": (..#ADDRESS)}, "1", .passed, .skipped), "the re-check is made")
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), "1|0", "contact 1 with its address passes")
	Set gone = "Orders Partner IT is no longer a partner contact of "_..#PRODUCTION
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": "other@results-partner.example"}, "1", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%ToJSON(), "|[{""id"":1,""reason"":"""_gone_"""}]", "an address that differs from the one at its position is skipped and reported")
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": "it@results-partner.example"}, "1", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%ToJSON(), "|[{""id"":1,""reason"":"""_gone_"""}]", "a request raised before the contact was renamed (to the retired address) is skipped with the same reason and nothing is sent")
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": (..#ADDRESS_",b@results-partner.example")}, "1,2", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%ToJSON(), "1|[{""id"":2,""reason"":""OcuTalon couldn't deliver the delay notice""}]", "an id that is no contact is skipped with NOSTART (no name is known for it), and the contact that passes still passes")
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": (..#ADDRESS)}, "1,2", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), "1|1", "a to that is shorter than the targets skips the target with no address")
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": ("two"_$Char(10)_"lines"), "to": (..#ADDRESS)}, "1", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%ToJSON(), "|[{""id"":1,""reason"":""OcuTalon couldn't deliver the delay notice""}]", "parameters that do not pass CheckParameters skip every target, with NOSTART")
	// Execute: the deliveries of the passing targets, and nothing sent
	Set before = ..MailRows()
	Do $$$AssertStatusOK($ClassMethod(..#KIND, "Execute", incident, {"text": (text), "to": (..#ADDRESS)}, "1", .result), "Execute is made")
	Do $$$AssertEquals(result.%ToJSON(), "{""deliveries"":[{""id"":1,""name"":""Orders Partner IT"",""address"":"""_..#ADDRESS_"""}],""skipped"":[]}", "it gives the deliveries")
	Do $$$AssertEquals(..MailRows(), before, "and sends nothing itself")
	Do $ClassMethod(..#KIND, "Execute", incident, {"text": (text), "to": "other@results-partner.example"}, "1", .result)
	Do $$$AssertEquals(result.deliveries.%Size()_"|"_result.skipped.%Size(), "0|1", "an address that differs gives no delivery")
	Do ..DemoMode(0)
	Do $ClassMethod(..#KIND, "Recheck", incident, {"text": (text), "to": (..#ADDRESS)}, "1", .passed, .skipped)
	Do $$$AssertEquals(passed_"|"_skipped.%Size(), "|1", "a contact that the fixture no longer gives (demo mode off) is skipped")
}

Method TestApprovedNoticeIsSentByteForByte()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("send")
	Set other = ..Owner("sendother")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set notice = ..LongNotice()
	Do $$$AssertEquals($Length(notice), 1000, "the notice is 1000 characters long")
	Set ref = ..Request(owner, incident, "approved", notice)
	Do $$$AssertStatusOK(..Send(host, ref), "the Execute is handled")
	Set mail = ..Mail(owner)
	Do $$$AssertEquals(mail.%Size(), 1, "one mail is saved for the owning session")
	If mail.%Size() = 1 {
		Set one = mail.%Get(0)
		Do $$$AssertTrue(one.text = notice, "its Text equals the row's text byte for byte")
		Do $$$AssertEquals(one.kind_"|"_one.direction_"|"_one.sender_"|"_one.approvalRef_"|"_one.itemId, "mailbox|out|OcuTalon|"_ref_"|", "it is sent mail of OcuTalon that carries the request's Ref")
		Do $$$AssertEquals(one.subject, "Simulated delay notice to Orders Partner IT <"_..#ADDRESS_">", "with the subject of partner.subject")
	}
	Do $$$AssertEquals(..Mail(other).%Size(), 0, "a second session has no mail")
	Do $$$AssertEquals(host.Notices.%Size(), 1, "one notice was sent to SimMailboxOut")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.final_"|"_last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped_"|"_last.reason, "1|1|0|1|0|0|", "the result is Total 1, Completed 1 and Resent 0")
	Do $$$AssertEquals(..State(ref), "done", "the request is done")
	Set key = ##class(OcuTalon.Watch.Notice).ResultKey("done", ..ResultOf(last), "partner_warning")
	Do $$$AssertEquals(key, "result.partnerSent", "which reads result.partnerSent")
	Do $$$AssertEquals(host.Audits.%Size(), 1, "one Action entry is written")
	Set entry = host.Audits.%Get(0)
	Do $$$AssertEquals(entry.action_"|"_entry.approvalRef_"|"_entry.counts.completed, "partner_warning|"_ref_"|1", "for the kind and the request")
	Do $$$AssertEquals(entry.target, "1 partner contact (1) of "_..#PRODUCTION_" (simulated)", "naming the contact ids")
	Do $$$AssertEquals($Find(entry.%ToJSON(), "@"), 0, "and no address")
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(ref)
	Do $$$AssertTrue($IsObject(run) && (run.EndedAt '= ""), "its FixRun has ended")
}

/// (QA, Story 23.5; AC4) The sent text is the row's text whatever characters it holds: letters with diacritics, an en dash, CJK, a check mark, a percent sign, braces that
/// look like a template slot, a doubled brace, markup, quotes and a backslash, are saved as the mail's Text unchanged (not rendered as a catalog template, not folded to ASCII, not
/// collapsed, not cut). The characters are built with $Char so that no encoding of this file can change them.
Method TestNoticeTextIsNeverAltered()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("unicode")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set notice = "Bestellungen f"_$Char(252)_"r M"_$Char(252)_"ller "_$Char(8211)_" "_$Char(27880, 25991)_" "_$Char(10003)_" 100% {recipient} {{x}} {0} <b>&amp;</b> ""q"" 'q' \ / and a slash."
	Do $$$AssertEquals(notice, $ClassMethod(..#KIND, "Normalise", notice), "the notice is one line as the kind wants it")
	Set ref = ..Request(owner, incident, "approved", notice)
	Do $$$AssertStatusOK(..Send(host, ref), "the Execute is handled")
	Set mail = ..Mail(owner)
	Do $$$AssertEquals(mail.%Size(), 1, "one mail is saved")
	If mail.%Size() = 1 {
		Do $$$AssertTrue(mail.%Get(0).text = notice, "its Text equals the row's text byte for byte")
		Do $$$AssertEquals($Length(mail.%Get(0).text), $Length(notice), "with the same number of characters")
		Do $$$AssertEquals($Length($ZConvert(mail.%Get(0).text, "O", "UTF8")), $Length($ZConvert(notice, "O", "UTF8")), "and the same number of bytes in UTF-8")
	}
	Do $$$AssertEquals(..State(ref), "done", "the request is done")
}

/// (QA, Story 23.5; AC16) The fixed texts of the partner delay notice that live in classes and not in the catalog (the kind's reasons, the answer of the ask and the reason of no open incident) never say or imply that
/// a real email was sent, and the ones that speak of delivery say that it is simulated, or that email delivery isn't set up.
Method TestClassTextsClaimNoRealEmail()
{
	Set texts = $ListBuild(
		$Parameter(..#KIND, "NOTSETUP"), $Parameter(..#KIND, "NOCONTACTS"), $Parameter(..#KIND, "NOITEM"), $Parameter(..#KIND, "ALLOWANCE"),
		$Parameter(..#KIND, "RECHECK"), $Parameter(..#KIND, "NOSTART"), $Parameter(..#KIND, "NOREAD"), $Parameter("OcuTalon.Watch.IncidentManager", "MESSAGEDRAFTING"), $Parameter("OcuTalon.Tools.WatchTools", "NOWARNING"))
	Set position = 0
	While $ListNext(texts, position, text) {
		Do $$$AssertTrue(text '= "", "a text is there: "_$Extract(text, 1, 40))
		For phrase = "email was sent", "emails were sent", "emailed", "by email", "sent an email", "email has been sent", "email sent", "we sent", "was sent to the partner", "delivered to" {
			Do $$$AssertEquals($Find($ZConvert(text, "L"), phrase), 0, "'"_$Extract(text, 1, 40)_"...' holds no '"_phrase_"'")
		}
	}
	Do $$$AssertTrue($Parameter(..#KIND, "ALLOWANCE") [ "simulated emails", "the allowance text says that the emails are simulated")
	Do $$$AssertEquals($Parameter(..#KIND, "NOTSETUP"), "email delivery isn't set up yet", "and the kept-as-a-draft reason is the ruled one")
}

Method TestDemoModeOffKeepsTheNotice()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("kept")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set ref = ..Request(owner, incident, "approved", "Orders failed for three minutes.")
	Do ..DemoMode(0)
	Do $$$AssertStatusOK(..Send(host, ref), "the Execute is handled")
	Do $$$AssertEquals(..Mail(owner).%Size()_"|"_$Select($IsObject(host.Notices): host.Notices.%Size(), 1: 0), "0|0", "nothing is saved or sent")
	Do $$$AssertEquals(..State(ref), "failed", "the request ends failed")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.final_"|"_last.total_"|"_last.completed_"|"_last.reason, "1|1|0|email delivery isn't set up yet", "with the NOTSETUP reason")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("failed", ..ResultOf(last), "partner_warning"), "result.partnerKept", "which reads result.partnerKept")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Do $$$AssertEquals({}.%FromJSON(row.DryRun).notice, "Orders failed for three minutes.", "the row keeps the notice's text")
	Do $$$AssertEquals({}.%FromJSON(row.FixParameters).text, "Orders failed for three minutes.", "and its parameters")
	Do $$$AssertEquals(host.Audits.%Size(), 1, "one Action entry is written")
}

Method TestTamperedRowSendsNothing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("tamper")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set ref = ..Request(owner, incident, "approved", "A notice.", {"FixParameters": {"text": "A notice.", "to": "attacker@example.com"}.%ToJSON()})
	Do $$$AssertStatusOK(..Send(host, ref), "an Execute for a row whose to names an unconfigured address is handled")
	Do $$$AssertEquals(..Mail(owner).%Size()_"|"_$Select($IsObject(host.Notices): host.Notices.%Size(), 1: 0), "0|0", "nothing is sent, so the address is never used")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.total_"|"_last.completed_"|"_last.skipped_"|"_last.reason, "1|0|1|Orders Partner IT is no longer a partner contact of "_..#PRODUCTION, "the contact is skipped and reported")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("done", ..ResultOf(last), "partner_warning"), "result.partnerNotSent", "which reads result.partnerNotSent")
	Set unknown = ..Request(owner, incident, "approved", "A notice.", {"FixTargets": "7"})
	Do $$$AssertStatusOK(..Send(host, unknown), "a row whose target is no contact is handled")
	Do $$$AssertEquals(..Mail(owner).%Size()_"|"_..Count(host.Notices), "0|0", "and sends nothing")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.completed_"|"_last.skipped, "0|1", "and reports it")
	Set twice = ..Request(owner, incident, "approved", "A notice.", {"FixTargets": "1,2", "FixParameters": {"text": "A notice.", "to": (..#ADDRESS_",b@results-partner.example")}.%ToJSON()})
	Do $$$AssertStatusOK(..Send(host, twice), "a row with one contact and one id that is none is handled")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.total_"|"_last.completed_"|"_last.skipped_"|"_$Piece(last.reason, " is no", 1), "2|1|1|OcuTalon couldn't deliver the delay notice", "one is sent and one is reported")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("done", ..ResultOf(last), "partner_warning"), "result.partnerSentSome", "which reads result.partnerSentSome")
	Do $$$AssertEquals(..Mail(owner).%Size(), 1, "and only the contact's mail is saved")
	Set other = ..Request(owner, incident, "approved", "A notice.", {"FixParameters": {"text": "Another notice.", "to": (..#ADDRESS)}.%ToJSON()})
	Do $$$AssertStatusOK(..Send(host, other), "a row whose text is not the notice of its dry run is handled")
	Do $$$AssertEquals(..Mail(owner).%Size()_"|"_..Count(host.Notices), "1|1", "and sends nothing more: only the text the approver was shown is ever sent")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.total_"|"_last.completed_"|"_last.reason_"|"_..State(other), "1|0|OcuTalon couldn't deliver the delay notice|failed", "it could not start, with NOSTART")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("failed", ..ResultOf(last), "partner_warning"), "result.partnerNotSent", "which reads result.partnerNotSent")
}

Method TestFailedSendIsReported()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("failsend")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set host.FailNoticeFor = owner
	Set ref = ..Request(owner, incident, "approved", "A notice.")
	Do $$$AssertStatusOK(..Send(host, ref), "the Execute is handled")
	Do $$$AssertEquals(..Mail(owner).%Size(), 0, "nothing was saved")
	Set last = host.Results.%Get(host.Results.%Size() - 1)
	Do $$$AssertEquals(last.total_"|"_last.completed_"|"_last.reason, "1|0|OcuTalon couldn't deliver the delay notice", "the run could not start with NOSTART")
	Do $$$AssertEquals(..State(ref), "failed", "and the request is failed")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Notice).ResultKey("failed", ..ResultOf(last), "partner_warning"), "result.partnerNotSent", "it reads result.partnerNotSent")
}

Method TestNoApprovedRowSendsNothing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("refused")
	Set incident = ..Incident(owner, {"State": "resolved"})
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set cases = $ListBuild("pending", "rejected", "expired", "cancelled", "tool_call", "unknown")
	Set position = 0
	While $ListNext(cases, position, case) {
		If case = "unknown" {
			Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		} ElseIf case = "tool_call" {
			Set ref = ..Request(owner, incident, "approved", "A notice.", {"Kind": "tool_call"})
		} Else {
			Set ref = ..Request(owner, incident, case, "A notice.")
		}
		Set whole = ..Whole(ref)
		Do $$$AssertStatusOK(..Send(host, ref), case_": the Execute is handled")
		Do $$$AssertEquals(..Whole(ref), whole, case_": the row is as it was")
		Do $$$AssertEquals(..Mail(owner).%Size()_"|"_..Count(host.Notices)_"|"_..Count(host.Results), "0|0|0", case_": nothing is saved, sent or reported")
		Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.FixRun).OfRequest(ref)), 0, case_": no FixRun is written")
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", mark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_ref)
		Do rs.%Next()
		Do $$$AssertEquals(+rs.%GetData(1), 1, case_": one info line names the Ref")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", mark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_ref)
	}
}

Method TestResultKeys()
{
	Set notice = "OcuTalon.Watch.Notice"
	Set all = ..ResultOf({"Final": 1, "Total": 3, "Completed": 3})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", all, "partner_warning")_"|"_$ClassMethod(notice, "ResultKey", "done", all), "result.partnerSent|result.allThrough", "every recipient sent reads partnerSent for this kind only")
	Set some = ..ResultOf({"Final": 1, "Total": 3, "Completed": 2, "Skipped": 1, "Reason": "Partner contact 3 is no longer a partner contact of Orders"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", some, "partner_warning"), "result.partnerSentSome", "some sent reads partnerSentSome")
	Set none = ..ResultOf({"Final": 1, "Total": 1, "Skipped": 1, "Reason": "x"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "done", none, "partner_warning"), "result.partnerNotSent", "none sent reads partnerNotSent")
	Set kept = ..ResultOf({"Final": 1, "Total": 1, "Reason": "email delivery isn't set up yet"})
	Do $$$AssertEquals($ClassMethod(notice, "ResultKey", "failed", kept, "partner_warning")_"|"_$ClassMethod(notice, "ResultKey", "done", kept, "partner_warning"), "result.partnerKept|result.partnerNotSent", "a failed run with the NOTSETUP reason reads partnerKept")
	Set slots = $ClassMethod(notice, "ResultSlots", "result.partnerSent", all, {}, .sc)
	Do $$$AssertEquals(slots.%ToJSON(), "{""count"":3}", "partnerSent has the count")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("result.partnerSent", slots, "phone", .sc), "The delay notice went to the Simulated mailbox for all 3 partner contacts. No real email was sent.", "and renders as ruled")
	Set slots = $ClassMethod(notice, "ResultSlots", "result.partnerSentSome", some, {}, .sc)
	Do $$$AssertEquals(slots.%ToJSON(), "{""completed"":2,""total"":3,""reason"":""Partner contact 3 is no longer a partner contact of Orders""}", "partnerSentSome has the counts and the reason")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("result.partnerSentSome", slots, "telegram", .sc), "The delay notice went to the Simulated mailbox for 2 of 3 partner contacts. Not sent to the rest: Partner contact 3 is no longer a partner contact of Orders. No real email was sent.", "and renders as ruled")
	Do $ClassMethod(notice, "ResultSlots", "result.partnerNotSent", ..ResultOf({"Final": 1, "Total": 1}), {}, .sc)
	Do $$$AssertStatusNotOK(sc, "a result that has no reason gives no slots for partnerNotSent")
	Set slots = $ClassMethod(notice, "ResultSlots", "result.partnerKept", kept, {}, .sc)
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("result.partnerKept", slots, "web", .sc), "The delay notice is approved and kept as a draft: email delivery isn't set up yet, so nothing was sent.", "partnerKept needs no slot")
}

/// --- helpers ---
/// Switches demo mode on (1) or off (0) and drops this process's cache of the setting.
Method DemoMode(on As %Boolean)
{
	Do ##class(OcuTalon.Test.Demo.Step).Put(+on, ##class(OcuTalon.Data.Time).NowUtc())
}

/// A shadow instance of the executor probe.
Method Host() As OcuTalon.Test.Fix.ExecutorProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture rows.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzpartner"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture incident of the owner on the Orders production (noticed, open unless fields say otherwise) with a failure group of three orders at OrdersFromPartner; its Ref.
Method Incident(owner As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"State": "open", "OpenVariant": "", "Count": 3, "NoticeCount": 3, "ItemNoun": (..#NOUN)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set production = $Select(all.%IsDefined("Production"): all.Production, 1: ..#PRODUCTION)
	Do all.%Remove("Production")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", production, all)
	Set ..Refs = ..Refs_","_ref
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = ref
	Set group.Seq = 1
	Set group.ItemName = "OrdersFromPartner"
	Set group.ErrorPattern = "The order date was not in the expected format"
	Set group.ErrorSummary = "The order date was not in the expected format"
	Set group.Seen = "h1,h2,h3"
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = "2026-11-08T14:12:00Z"
	Set group.LastAt = "2026-11-08T14:15:00Z"
	$$$ThrowOnError(group.%Save())
	Set ..Incidents = ..Incidents_","_ref
	Quit ref
}

/// A fixture partner_warning request of the owner for the incident in the state, with the notice, its target 1 and its recipient, with the fields after the defaults; its Ref.
Method Request(owner As %String, incident As %String, state As %String, notice As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"FixKind": "partner_warning", "FixTargets": "1", "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Do all.%Set("FixParameters", {"text": (notice), "to": (..#ADDRESS)}.%ToJSON())
	Do all.%Set("DryRun", {"notice": (notice), "recipients": [{"name": "Orders Partner IT", "address": (..#ADDRESS)}], "simulated": 1}.%ToJSON())
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , all)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// A notice of 1000 characters with braces, angle brackets, quotes, an ampersand and a percent sign: what a catalog template or a trim would change.
ClassMethod LongNotice() As %String
{
	Set text = "Orders {from} <your feed> failed & we said ""soon"" 100% of the time. "
	While $Length(text) < 1000 {
		Set text = text_"More text "
	}
	Quit $Extract(text, 1, 999)_"."
}

/// Hands the probe an Execute for the Ref; the status.
Method Send(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String) As %Status
{
	Set request = ##class(OcuTalon.Fix.Msg.Execute).%New()
	Set request.ApprovalRef = ref
	Set response = ""
	Quit host.OnMessage(request, .response)
}

/// The sent mail of the session, oldest first, as {text, kind, direction, sender, subject, approvalRef, itemId}.
ClassMethod Mail(session As %String) As %DynamicArray
{
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text, Kind, Direction, Sender, Subject, ApprovalRef, ItemId FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'mailbox' AND Direction = 'out' ORDER BY ID", session)
	While rs.%Next() {
		Do rows.%Push({"text": (rs.%Get("Text")), "kind": (rs.%Get("Kind")), "direction": (rs.%Get("Direction")), "sender": (rs.%Get("Sender")), "subject": (rs.%Get("Subject")), "approvalRef": (rs.%Get("ApprovalRef")), "itemId": (rs.%Get("ItemId"))})
	}
	Quit rows
}

/// The number of SimMessage rows of every session of the fixture (to see that something sent nothing).
Method MailRows() As %Integer
{
	Set total = 0
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Set total = total + ..Mail($Piece(..Refs, ",", i)).%Size()
	}
	Quit total
}

/// The state of the request's row.
ClassMethod State(ref As %String) As %String
{
	Quit ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State
}

/// Every column of the request's row as text, to compare before and after; "<none>" for a Ref with no row.
ClassMethod Whole(ref As %String) As %String
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?", ref)
	If 'rs.%Next() Quit "<none>"
	Set text = ""
	For i = 1:1:rs.%ResultColumnCount Set text = text _ rs.%GetData(i) _ $Char(31)
	Quit text
}

/// The number of entries of a probe's list; 0 for a list that was never made.
ClassMethod Count(list As %DynamicArray) As %Integer
{
	Quit $Select($IsObject(list): list.%Size(), 1: 0)
}

/// A FixResult object from the probe's recorded result (a dynamic object of its fields) or from fields given.
ClassMethod ResultOf(fields As %DynamicObject) As OcuTalon.Fix.Msg.FixResult
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set name = $ZConvert($Extract(name), "U")_$Extract(name, 2, *)
		If ##class(%Dictionary.CompiledProperty).%ExistsId("OcuTalon.Fix.Msg.FixResult||"_name) Set $Property(result, name) = value
	}
	Quit result
}

/// A resolved fixture incident of the owner with the count, a failure group at OrdersFromPartner and the orders noun; its Ref.
Method Resolved(owner As %String, count As %Integer = 50, fields As %DynamicObject = "") As %String
{
	Set all = {"State": "resolved", "Count": (count), "NoticeCount": (count)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Quit ..Incident(owner, all)
}

/// A request of the kind (default state done) of the incident with the parameters, its FixRun with the counts of run (a dynamic object of FixRun properties; "" for a request with no run), and the request's Ref
/// added to the incident's RequestRefs; both rows are registered for cleanup. The request's Ref.
Method Ran(owner As %String, incident As %String, kind As %String, parameters As %DynamicObject, run As %DynamicObject = "", state As %String = "done") As %String
{
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , {"FixKind": (kind), "FixParameters": (parameters.%ToJSON()), "FixTargets": "1"})
	Set ..Refs = ..Refs_","_request
	If $IsObject(run) Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, request, run)
	Do ..Link(incident, request)
	Quit request
}

/// Adds the request Ref to the incident's RequestRefs.
Method Link(incident As %String, request As %String)
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = row.RequestRefs_$Select(row.RequestRefs = "": "", 1: ",")_request
	$$$ThrowOnError(row.%Save())
}

/// The counts of a run as FixRun properties: Total, Resent, Completed, FailedAgain, Skipped, with Interrupted 0.
ClassMethod Counts(total As %Integer, resent As %Integer, completed As %Integer, failedAgain As %Integer, skipped As %Integer) As %DynamicObject
{
	Quit {"Total": (total), "Resent": (resent), "Completed": (completed), "FailedAgain": (failedAgain), "Skipped": (skipped), "Interrupted": 0}
}

/// The Outcome line of the incident.
Method OutcomeOf(incident As %String) As %String
{
	Quit $ClassMethod(..#KIND, "Outcome", ##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
}

/// The Facts of the incident.
Method FactsOf(incident As %String) As %String
{
	Quit $ClassMethod(..#KIND, "Facts", ##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
}

/// Story 23.11 (AC1): a fix that resent and completed all 50 messages gives the full line, right after the state line.
Method TestOutcomeFullFix()
{
	Set owner = ..Owner("full")
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {"field": "OrderDate", "sourceFormat": "DD/MM/YYYY", "targetFormat": "YYYY-MM-DD"}, ..Counts(50, 50, 50, 0, 0))
	Set line = "Outcome: all 50 affected orders went through after the fix."
	Do $$$AssertEquals(..OutcomeOf(incident), line, "the full-fix line")
	Do $$$AssertTrue($Find(..FactsOf(incident), $Char(10)_"Incident state: resolved"_$Char(10)_line_$Char(10)_"Failed item: OrdersFromPartner"_$Char(10)) > 0, "Facts holds it right after the state line")
	Do ..Ran(owner, incident, "partner_warning", {"text": "A notice.", "to": (..#ADDRESS)}, ..Counts(1, 0, 1, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(incident), line, "a notice sent after the fix does not count as a second run")
}

/// Story 23.11 (AC2): the partial line for a partial run, for none through and for a Count above the run's Total.
Method TestOutcomePartialFix()
{
	Set owner = ..Owner("partial")
	Set partial = ..Resolved(owner, 50)
	Do ..Ran(owner, partial, "repair_resend", {}, ..Counts(50, 48, 45, 3, 2))
	Do $$$AssertEquals(..OutcomeOf(partial), "Outcome: 45 of the 50 affected orders went through after the fix, and 5 did not.", "a partial fix")
	Do $$$AssertTrue($Find(..FactsOf(partial), $Char(10)_"Incident state: resolved"_$Char(10)_"Outcome: 45 of the 50") > 0, "and Facts holds it after the state line")
	Set none = ..Resolved(owner, 50)
	Do ..Ran(owner, none, "repair_resend", {}, ..Counts(50, 50, 0, 50, 0))
	Do $$$AssertEquals(..OutcomeOf(none), "Outcome: 0 of the 50 affected orders went through after the fix, and 50 did not.", "none through")
	Set byCount = ..Resolved(owner, 52)
	Do ..Ran(owner, byCount, "repair_resend", {}, ..Counts(50, 50, 50, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(byCount), "Outcome: 50 of the 52 affected orders went through after the fix, and 2 did not.", "a Count above what the run completed counts the rest as not gone through")
}

/// Story 23.11 (AC3): a reroute that resent all 50 gives the reroute line with no item or target name; one that left some out gives none.
Method TestOutcomeReroute()
{
	Set owner = ..Owner("reroute")
	Set all = ..Resolved(owner, 50)
	Do ..Ran(owner, all, "reroute", {"target": "OrdersForReview"}, ..Counts(50, 50, 40, 10, 0))
	Set line = ..OutcomeOf(all)
	Do $$$AssertEquals(line, "Outcome: the 50 affected orders were resent by another route.", "the reroute line, whatever failed again")
	Do $$$AssertEquals($Find(line, "OrdersForReview") + $Find(line, "OrdersFromPartner"), 0, "and it names neither the target nor the item")
	Set left = ..Resolved(owner, 50)
	Do ..Ran(owner, left, "reroute", {"target": "OrdersForReview"}, ..Counts(48, 48, 48, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(left), "", "a reroute that left two out (the dry run) gives no line")
	Set skipped = ..Resolved(owner, 50)
	Do ..Ran(owner, skipped, "reroute", {"target": "OrdersForReview"}, ..Counts(50, 49, 49, 0, 1))
	Do $$$AssertEquals(..OutcomeOf(skipped), "", "and neither does one that skipped a message")
}

/// Story 23.11 (AC4): a suspend of the failed item that changed it gives the paused line; another item, or nothing changed, gives none.
Method TestOutcomeSuspend()
{
	Set owner = ..Owner("suspend")
	Set paused = ..Resolved(owner, 50)
	Do ..Ran(owner, paused, "suspend_item", {"item": "OrdersFromPartner"}, ..Counts(1, 0, 1, 0, 0))
	Set line = ..OutcomeOf(paused)
	Do $$$AssertEquals(line, "Outcome: the affected flow was paused, and the 50 affected orders haven't gone through yet.", "the paused line")
	Do $$$AssertEquals($Find(line, "OrdersFromPartner"), 0, "without the item's name")
	Set other = ..Resolved(owner, 50)
	Do ..Ran(owner, other, "suspend_item", {"item": "OrdersToWarehouse"}, ..Counts(1, 0, 1, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(other), "", "a suspend of an item that did not fail gives no line")
	Set unchanged = ..Resolved(owner, 50)
	Do ..Ran(owner, unchanged, "suspend_item", {"item": "OrdersFromPartner"}, ..Counts(1, 0, 0, 0, 1))
	Do $$$AssertEquals(..OutcomeOf(unchanged), "", "and a suspend that changed nothing gives none")
	Set noItem = ..Resolved(owner, 50)
	Do ..Ran(owner, noItem, "suspend_item", {}, ..Counts(1, 0, 1, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(noItem), "", "and a suspend whose request holds no item gives none")
}

/// Story 23.11 (AC5): every ending that the records do not map onto one ruled line, and an incident that is not resolved, gives "" and a Facts without "Outcome:".
Method TestNoOutcome()
{
	Set owner = ..Owner("none")
	Set full = ..Counts(50, 50, 50, 0, 0)
	Set n = 0
	Set incident = ..Resolved(owner, 50)
	Set case($Increment(n)) = incident_"|no request"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, "", "rejected")
	Set case($Increment(n)) = incident_"|a rejected request with no run"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, "", "expired")
	Set case($Increment(n)) = incident_"|an expired request with no run"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "partner_warning", {"text": "A notice.", "to": (..#ADDRESS)}, ..Counts(1, 0, 1, 0, 0))
	Set case($Increment(n)) = incident_"|only a partner_warning run"
	For state = "open", "awaiting_approval", "fixing" {
		Set incident = ..Resolved(owner, 50, {"State": (state)})
		Do ..Ran(owner, incident, "repair_resend", {}, full)
		Set case($Increment(n)) = incident_"|a full-fix run of a "_state_" incident"
	}
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "resume_item", {"item": "OrdersFromPartner"}, ..Counts(1, 0, 1, 0, 0))
	Set case($Increment(n)) = incident_"|a resume"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, {"Total": 50, "Resent": 30, "Completed": 20, "FailedAgain": 0, "Skipped": 20, "Interrupted": 10})
	Set case($Increment(n)) = incident_"|an interrupted run"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(50, 0, 0, 0, 0), "failed")
	Set case($Increment(n)) = incident_"|a run that could not start"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(50, 0, 0, 0, 50))
	Set case($Increment(n)) = incident_"|nothing resent"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(0, 0, 0, 0, 0))
	Set case($Increment(n)) = incident_"|a run with all counts 0"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "zz_unknown_kind", {}, full)
	Set case($Increment(n)) = incident_"|an unknown kind"
	Set incident = ..Resolved(owner, 0)
	Do ..Ran(owner, incident, "repair_resend", {}, full)
	Set case($Increment(n)) = incident_"|Count 0"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, {"EndedAt": "", "Total": 50, "Resent": 50, "Completed": 50, "FailedAgain": 0, "Skipped": 0, "Interrupted": 0})
	Set case($Increment(n)) = incident_"|a run without EndedAt"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(51, 51, 50, 1, 0))
	Set case($Increment(n)) = incident_"|a Total above Count"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(50, 50, 51, 0, 0))
	Set case($Increment(n)) = incident_"|a Completed above Count"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, full)
	Do ..Ran(owner, incident, "suspend_item", {"item": "OrdersFromPartner"}, ..Counts(1, 0, 1, 0, 0))
	Set case($Increment(n)) = incident_"|a full fix and then a suspend"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(50, 50, 20, 30, 0))
	Do ..Ran(owner, incident, "reroute", {"target": "OrdersForReview"}, ..Counts(30, 30, 30, 0, 0))
	Set case($Increment(n)) = incident_"|a partial fix and then a reroute"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(50, 50, 50, 1, 0))
	Set case($Increment(n)) = incident_"|a fix that completed all but had one fail again"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "repair_resend", {}, ..Counts(60, 50, 45, 5, 10))
	Set case($Increment(n)) = incident_"|a Total above Count with Completed below it"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "reroute", {"target": "OrdersForReview"}, ..Counts(50, 50, 51, 0, 0))
	Set case($Increment(n)) = incident_"|a reroute with a Completed above Count"
	Set other = ..Resolved(owner, 50)
	Set foreign = ..Ran(owner, other, "repair_resend", {}, full)
	Set incident = ..Resolved(owner, 50)
	Do ..Link(incident, foreign)
	Set case($Increment(n)) = incident_"|the full-fix request of another incident"
	Set incident = ..Resolved(owner, 50)
	Do ..Link(incident, "no-such-request-"_..Number)
	Set case($Increment(n)) = incident_"|a request ref with no row"
	Set incident = ..Resolved(owner, 50)
	Set suspend = ..Ran(owner, incident, "suspend_item", {"item": "OrdersFromPartner"}, ..Counts(1, 0, 1, 0, 0))
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(suspend)
	Set row.FixParameters = "not json"
	$$$ThrowOnError(row.%Save())
	Set case($Increment(n)) = incident_"|a suspend whose parameters are not JSON"
	Set incident = ..Resolved(owner, 50)
	Do ..Ran(owner, incident, "suspend_item", {"item": {"name": "OrdersFromPartner"}}, ..Counts(1, 0, 1, 0, 0))
	Set case($Increment(n)) = incident_"|a suspend whose item is not a string"
	For i = 1:1:n {
		Set ref = $Piece(case(i), "|"), label = $Piece(case(i), "|", 2)
		Do $$$AssertEquals(..OutcomeOf(ref), "", label_": no Outcome line")
		Do $$$AssertEquals($Find(..FactsOf(ref), "Outcome:"), 0, label_": Facts has no Outcome line")
	}
}

/// Story 23.11 (AC6): the Outcome line and the rendered instruction use the plural of the incident's item noun, "orders" on the demo.
Method TestOutcomeUsesTheItemNoun()
{
	Set owner = ..Owner("noun")
	Set incident = ..Resolved(owner, 7, {"ItemNoun": ({"one": "message", "other": "messages"}.%ToJSON())})
	Do ..Ran(owner, incident, "reroute", {"target": "OrdersForReview"}, ..Counts(7, 7, 7, 0, 0))
	Do $$$AssertEquals(..OutcomeOf(incident), "Outcome: the 7 affected messages were resent by another route.", "the Outcome line uses the incident's noun")
	Set note = $ClassMethod(..#KIND, "SystemNote", ##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
	Set tail = "If there is no Outcome fact, don't say whether the messages went through."
	Set ends = ($Extract(note, $Length(note) - $Length(tail) + 1, $Length(note)) = tail)
	Do $$$AssertTrue(ends, "the instruction ends with the noun")
	Do $$$AssertEquals($Find(note, "{noun}"), 0, "and holds no token")
	Set demo = ..Incident(owner, {"State": "resolved"})
	Set note = $ClassMethod(..#KIND, "SystemNote", ##class(OcuTalon.Data.Incident).RefIndexOpen(demo))
	Set tail = "If there is no Outcome fact, don't say whether the orders went through."
	Set ends = ($Extract(note, $Length(note) - $Length(tail) + 1, $Length(note)) = tail)
	Do $$$AssertTrue(ends, "and the demo incident's ends with orders")
}

}
