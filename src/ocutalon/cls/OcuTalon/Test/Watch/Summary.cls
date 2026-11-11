/// Tests of the incident summary (Story 23.6; AD-4, AD-15, AD-20, AD-32): what OcuTalon.Watch.Summary builds from an incident's rows and what IncidentManager does with it
/// when an incident closes. The tests need no production: they drive IncidentCommand through OnRequest of a shadow instance of Test.Watch.IncidentProbe, over fixture
/// sessions, incidents, approval requests, fix runs, decisions and usage rows of Test.Data.Fixture, and read the row, the probe's recorded notifications and the text that
/// Watch.Summary.Text renders. They run warm. The times of the fixture rows are before now, so that the closing line (UTC now) is the last of the timeline.
///   - TestFixedDismissed (AC1, AC2, AC4): a resolved incident with an approved request answered on the phone, a fix run and a diagnosis decision with two usage rows is
///     dismissed: the row stores the parts in order (title, first failure, notice, request, approval, fix started, fix ended, closed with Dismiss, cause, element,
///     evidence, sample error, fix, messages, cost), the cost is the sum of the two usage rows, no Decision or Usage row is added, and exactly one summary Notification
///     (summary.title, no slots, the incident's DecisionRef, no approval) goes to the owner; the rendered text has one line per part;
///   - TestClosingLines: closeForReplay and closeQuiet end the timeline with their own line;
///   - TestFallback (AC3): a fallback incident has summary.noCause with the reason, summary.noFixRan and summary.groups with every group, and messages with 0 resent;
///   - TestNoFixVariants (AC3): an incident with a rejected or an expired request and no fix run has the request's line, the cause, summary.noFixRan and the groups;
///   - TestCost (AC2): an unknown cost is summary.costUnknown, an incident without usage rows costs 0;
///   - TestInstanceIncident (AC4): an instance incident watched by two sessions sends one summary Notification to each;
///   - TestBuilderFails (AC4): a row that cannot be summarized closes with no Summary, one warning and no summary Notification;
///   - TestRefusedClose (AC4): a Dismiss while fixing, and any close of a closed incident, build and send nothing;
///   - TestChannelNames (AC13): the channel of an answer reads as the README names it, the Simulated mailbox included;
///   - TestUserName (AC15): the answerer is named on a local install and never on the online demo;
///   - TestSampleErrorLength (AC14): the sample error is no longer than an incident notice's error summary;
///   - TestTimelineOrder (AC1): the timeline is sorted by time whatever the order of the requests;
///   - TestRunEdges (AC1): an interrupted fix run reads summary.fixInterrupted and a run that has not ended only summary.fixStarted;
///   - TestGroupsOnlyWithoutFix (AC3): a fixed incident does not list its failure groups;
///   - TestAnswerEdges (AC13): an answer from a channel with no name, a cancelled or a pending request give no answer line, the approved states that follow the approval
///     give one, and a dry run without a count leaves the request line out (the affected count stands in for the resend count); an answer from email has no line
///     (email has no channel name until real email exists, the Contest Planner's ruling);
///   - TestMarkup (AC14): cause, evidence, fix and sample error with markup are stored and rendered literally on every channel;
///   - TestMarkupCut (AC14, QA): a sample error that starts with markup and is longer than a notice's error summary is cut to that length through Build and shows the
///     markup literally on the web, the phone and Telegram; Built is the fixture the channel tests (WebChatOut, SimPhoneOut, TelegramOut) deliver;
///   - TestInvisibleText (AC14, QA): a cause, element, evidence, fix or sample error that shows nothing (a zero-width space) leaves its line out, so that the stored summary
///     still renders on every channel;
///   - TestPlaceholderText (AC14, QA): a cause, evidence and sample error that look like catalog placeholders ({production}, {count}) render as they are, once, on every channel;
///   - TestPeriodElement: an element that is only a period leaves its line out, so that the stored summary still renders on every channel;
///   - TestGroupsAtClose (AC3): the groups line lists every group with its count at the close, a group that formed after the notice (no NoticeCount) included;
///   - TestProductionName: the title names the demo production by its display name (Orders), and a production that is not listed by its class name;
///   - TestText: the stored summary is read back through Watch.Summary.Text, and an incident without one gives an error status.
///   - TestKindLines (Story 23.2, AC14): the requested and ended lines of the suspend, resume and reroute requests, with no message counts for the item runs;
///   - TestPartnerLines (Story 23.5, AC13): the requested line (with the number of recipients) and the sent, kept or not sent line of each delay notice, with no "the fix started" line, the message counts unchanged and "No fix ran" kept.
/// The fixture rows are removed after each test.
Class OcuTalon.Test.Watch.Summary Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The noun of the incidents.
Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, whose groups are deleted after it, comma-separated.
Property Incidents As %String(MAXLEN = "");

/// The log row before the test.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WatchSummary", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ..DropGroups($Piece(..Incidents, ",", i))
	}
	Set ..Incidents = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Closing", $Parameter(..#PROBE, "LOGSUMMARY"))
	Quit $$$OK
}

Method TestFixedDismissed()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("fixed")
	Do ..Resolved(owner, .incident, .request, .decision)
	Set decisions = ..Count("Decision")
	Set usages = ..Count("Usage")
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|closed", "the Dismiss closes the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State, "closed", "the row is closed")
	Do $$$AssertEquals(..Keys(row), "summary.title,summary.firstFailure,summary.noticed,summary.requested,summary.approved,summary.fixStarted,summary.fixEnded,summary.closedDismiss,summary.cause,summary.element,summary.evidence,summary.sampleError,summary.fix,summary.messages,summary.cost", "the summary holds each part, in order")
	Set summary = {}.%FromJSON(row.Summary)
	Do $$$AssertEquals(summary.lines.%Size(), 0, "and no coverage line")
	Do $$$AssertEquals(..Slots(row, "summary.title").%ToJSON(), "{""count"":50,""itemNoun"":{""one"":""order"",""other"":""orders""},""production"":""Zz.Summary"_..Number_"""}", "the title has the count, the noun and the production")
	Do $$$AssertEquals(..Slots(row, "summary.requested").count, 3, "the request line has the dry run's resend count")
	Set approved = ..Slots(row, "summary.approved")
	Do $$$AssertEquals(approved.channel, "the Simulated phone", "the approval names its channel as the README does")
	Set answered = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request)
	Do $$$AssertEquals(approved.time, answered.AnsweredAt, "at the time of the answer")
	Set ended = ..Slots(row, "summary.fixEnded")
	Do $$$AssertEquals(ended.resent_"|"_ended.completed_"|"_ended.failedAgain_"|"_ended.skipped_"|"_ended.time, "50|50|0|0|"_run.EndedAt, "the fix line has the counts and the end time")
	Do $$$AssertEquals(..Slots(row, "summary.fixStarted").time, run.StartedAt, "the fix start line has the start time")
	Do $$$AssertEquals(..Slots(row, "summary.noticed").time, row.NoticedAt, "the notice line has NoticedAt")
	Do $$$AssertEquals(..Slots(row, "summary.firstFailure").time, row.FirstAt, "the first failure line has FirstAt")
	Set closing = ..Slots(row, "summary.closedDismiss")
	Do $$$AssertEquals(closing.time, row.ClosedAt, "the closing line has the time the row was closed")
	Do $$$AssertEquals(..Slots(row, "summary.cause").cause, "The partner changed the date format.", "the cause is the row's")
	Do $$$AssertEquals(..Slots(row, "summary.element").element, "OrderDate", "so is the element")
	Do $$$AssertEquals(..Slots(row, "summary.evidence").evidence, "OrderDate 16/10/2026 in the sample", "the evidence is the first line of the diagnosis payload")
	Do $$$AssertEquals(..Slots(row, "summary.sampleError").error, "Field OrderDate was not a date.", "the sample error is the row's")
	Do $$$AssertEquals(..Slots(row, "summary.fix").fix, "repair the date and resend the orders", "the fix is the row's")
	Set messages = ..Slots(row, "summary.messages")
	Do $$$AssertEquals(messages.failed_"|"_messages.resent_"|"_messages.completed_"|"_messages.failedAgain_"|"_messages.skipped, "50|50|50|0|0", "the message counts add the fix runs")
	Do $$$AssertEquals(..Slots(row, "summary.cost").cost, 0.0168, "the cost is the sum of the two usage rows")
	Do $$$AssertEquals(..Count("Decision")_"|"_..Count("Usage"), decisions_"|"_usages, "no Decision and no Usage row was added")
	Set sent = ..Summaries(host)
	Do $$$AssertEquals(sent.%Size(), 1, "exactly one summary Notification goes out")
	Set note = sent.%Get(0)
	Do $$$AssertEquals(note.sessionRef_"|"_note.catalogKey_"|"_note.slots_"|"_note.incidentRef_"|"_note.decisionRef_"|"_note.approvalRef, owner_"|summary.title|{}|"_incident_"|"_decision_"|", "to the owner, with the title key, no slots, the incident's Refs and no approval")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertStatusOK(sc, "the stored summary renders")
	Do $$$AssertEquals($Length(text, $Char(10)), 15, "one line per part")
	Do $$$AssertEquals($Piece(text, $Char(10), 1), "Incident summary: 50 orders failed in Zz.Summary"_..Number_".", "the title line")
	Do $$$AssertTrue(text [ ": approved from the Simulated phone.", "the approval line")
	Do $$$AssertTrue(text [ ": OcuTalon asked for approval to repair and resend 3 orders.", "the request line")
	Do $$$AssertTrue(text [ ": the fix ended: 50 resent, 50 completed, 0 failed again, 0 skipped.", "the fix line")
	Do $$$AssertTrue(text [ ": closed with Dismiss.", "the closing line")
	Do $$$AssertTrue(text [ (": the fix started."_$Char(10)), "the fix started line")
	Do $$$AssertEquals($Piece(text, $Char(10), 9, 15), "Cause: The partner changed the date format."_$Char(10)_"Where it failed: OrderDate."_$Char(10)_"Evidence: OrderDate 16/10/2026 in the sample"_$Char(10)_"Sample error: Field OrderDate was not a date."_$Char(10)_"Fix: repair the date and resend the orders"_$Char(10)_"Messages: 50 failed, 50 resent, 50 completed, 0 failed again, 0 skipped."_$Char(10)_"Model cost of this incident: $0.017.", "the lines after the timeline")
	Do $$$AssertNotTrue(text [ "went through", "and the text holds no word that the demo path filters")
}

Method TestClosingLines()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("closing")
	Do ..Resolved(owner, .replay)
	Set result = ..Command(host, "closeForReplay", replay, "")
	Do $$$AssertEquals(result.Ok, 1, "Break the feed's replay rule closes the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(replay)
	Do $$$AssertTrue(..Keys(row) [ "summary.closedReplay", "the closing line is summary.closedReplay")
	Do $$$AssertNotTrue(..Keys(row) [ "closedDismiss", "and not Dismiss")
	Do $$$AssertEquals($Piece(..Keys(row), ",", 8), "summary.closedReplay", "after the fix lines")
	Set text = ##class(OcuTalon.Watch.Summary).Text(replay, "phone", .sc)
	Do $$$AssertTrue(text [ ": closed when Break the feed was pressed again.", "which reads as the ruled text")
	Do ..Resolved(owner, .quiet, , , -3600)
	Set result = ..Command(host, "closeQuiet", quiet, "")
	Do $$$AssertEquals(result.Ok, 1, "15 quiet minutes close the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(quiet)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 8), "summary.closedQuiet", "the closing line is summary.closedQuiet")
	Set text = ##class(OcuTalon.Watch.Summary).Text(quiet, "telegram", .sc)
	Do $$$AssertTrue(text [ ": closed after 15 minutes with no new failures.", "which reads as the ruled text")
	Do $$$AssertEquals(..Summaries(host).%Size(), 2, "and each close sent one summary Notification")
}

Method TestFallback()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("fallback")
	Set incident = ..Incident(owner, "open", {"Fallback": 1, "FallbackReason": "timeout", "Cause": "", "Element": "", "FixSummary": "", "OpenVariant": "fallback", "SampleError": "", "Count": 7})
	Do ..Group(incident, 1, "OrdersFromPartner", 5, "The order date was not valid")
	Do ..Group(incident, 2, "OrdersToWarehouse", 2, "The warehouse refused the order")
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok, 1, "a fallback incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(..Keys(row), "summary.title,summary.firstFailure,summary.noticed,summary.closedDismiss,summary.noCause,summary.noFixRan,summary.groups,summary.messages,summary.cost", "no cause, no fix, the groups and the counts")
	Do $$$AssertEquals(..Slots(row, "summary.noCause").fallbackReason, "timeout", "the reason is the row's")
	Set groups = ..Slots(row, "summary.groups").groups
	Do $$$AssertEquals(groups.%Size(), 2, "every group is listed")
	Do $$$AssertEquals(groups.%Get(0).itemName_"|"_groups.%Get(0).count_"|"_groups.%Get(1).itemName_"|"_groups.%Get(1).count, "OrdersFromPartner|5|OrdersToWarehouse|2", "in Seq order with their counts")
	Set messages = ..Slots(row, "summary.messages")
	Do $$$AssertEquals(messages.failed_"|"_messages.resent_"|"_messages.completed, "7|0|0", "with 0 resent")
	Do $$$AssertEquals(..Slots(row, "summary.cost").cost, 0, "and a cost of 0 with no usage rows")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertStatusOK(sc, "the fallback summary renders")
	Do $$$AssertTrue(text [ "No cause was found: ", "the no-cause line")
	Do $$$AssertTrue(text [ "No fix ran, so nothing was changed.", "the no-fix line")
	Do $$$AssertTrue(text [ ("Failure groups:"_$Char(10)_"OrdersFromPartner: 5, 'The order date was not valid', first "), "the groups, one line each")
}

Method TestNoFixVariants()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("nofix")
	For state = "rejected", "expired" {
		Set incident = ..Incident(owner, "open", {"OpenVariant": (state)})
		Do ..Group(incident, 1, "OrdersFromPartner", 3, "The order date was not valid")
		Set request = ..Request(owner, incident, state, ..T(-6000), $Select(state = "rejected": {"AnsweredChannel": "web", "AnsweredAt": (..T(-5400))}, 1: {"ExpiresAt": (..T(-5400))}))
		Do ..Link(incident, request)
		Set result = ..Command(host, "dismiss", incident, owner)
		Do $$$AssertEquals(result.Ok, 1, "the "_state_" incident is dismissed")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(..Keys(row), "summary.title,summary.firstFailure,summary.noticed,summary.requested,"_$Select(state = "rejected": "summary.rejected", 1: "summary.expired")_",summary.closedDismiss,summary.cause,summary.element,summary.sampleError,summary.noFixRan,summary.groups,summary.messages,summary.cost", state_": the request's line, the cause, no fix and the groups")
		Do $$$AssertEquals(..Slots(row, "summary.groups").groups.%Size(), 1, state_": the group is listed")
		Do $$$AssertEquals(..Slots(row, "summary.messages").resent, 0, state_": nothing was resent")
	}
}

Method TestCost()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("cost")
	Do ..Resolved(owner, .incident, , .decision)
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, owner, {"CostUSD": "", "InputTokens": 10})
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok, 1, "the incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 15), "summary.costUnknown", "a usage row with no cost makes the cost unknown")
	Do $$$AssertEquals(..Slots(row, "summary.costUnknown").%ToJSON(), "{}", "with no slot")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertTrue(text [ "Model cost of this incident: not known.", "which reads as the ruled text")
}

Method TestInstanceIncident()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set a = ..Owner("instancea")
	Set b = ..Owner("instanceb")
	Set production = "Zz.Summary"_..Number_".instance"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set incident = ..Incident("instance", "open", {"OpenVariant": "no_fix"}, production)
	Do ..Group(incident, 1, "OrdersFromPartner", 3, "The order date was not valid")
	Set result = ..Command(host, "dismiss", incident, a)
	Do $$$AssertEquals(result.Ok, 1, "A closes the instance incident")
	Set sent = ..Summaries(host)
	Do $$$AssertEquals(sent.%Size(), 2, "one summary Notification per watcher")
	Set to = sent.%Get(0).sessionRef_","_sent.%Get(1).sessionRef
	Do $$$AssertTrue(($Length(to, ",") = 2) && (to [ a) && (to [ b), "one to A and one to B")
}

Method TestBuilderFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("fails")
	Set incident = ..Incident(owner, "resolved", {"FirstAt": ""})
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|closed", "the close succeeds")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_(row.ClosedAt '= "")_"|"_row.Summary, "closed|1|", "the row is closed with no summary")
	Do $$$AssertEquals(..Summaries(host).%Size(), 0, "no summary Notification is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Closing", $Parameter(..#PROBE, "LOGSUMMARY")_incident), 1, "one warning names the incident")
	Set none = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertEquals(none_"|"_$SYSTEM.Status.IsError(sc), "|1", "reading the missing summary is an error with no text")
}

Method TestRefusedClose()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("refused")
	Set fixing = ..Incident(owner, "fixing")
	Set result = ..Command(host, "dismiss", fixing, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "a Dismiss while fixing is refused")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(fixing)
	Do $$$AssertEquals(row.State_"|"_row.Summary, "fixing|", "and stores no summary")
	Do ..Resolved(owner, .resolved)
	Do $$$AssertEquals(..Command(host, "dismiss", resolved, owner).Ok, 1, "a resolved incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(resolved)
	Set stored = row.Summary
	Do $$$AssertEquals(..Summaries(host).%Size(), 1, "one summary Notification so far")
	Set again = ..Command(host, "dismiss", resolved, owner)
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "0|not_allowed", "a second Dismiss is refused")
	Do $$$AssertEquals(..Command(host, "closeForReplay", resolved, "").Ok, 0, "and so is a replay close")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(resolved).Summary, stored, "the stored summary does not change")
	Do $$$AssertEquals(..Summaries(host).%Size(), 1, "and nothing more is sent")
}

Method TestChannelNames()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("channels")
	Set expected = "web=the web chat,phone=the Simulated phone,telegram=Telegram,mailbox=the Simulated mailbox"
	For i = 1:1:$Length(expected, ",") {
		Set channel = $Piece($Piece(expected, ",", i), "=", 1)
		Set name = $Piece($Piece(expected, ",", i), "=", 2)
		Do ..Resolved(owner, .incident, , , , channel)
		Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, channel_": the incident is dismissed")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(..Slots(row, "summary.approved").channel, name, channel_": the slot holds the README's name")
		For render = "web", "phone", "telegram" {
			Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
			Do $$$AssertStatusOK(sc, channel_" on "_render_": the summary renders")
			Do $$$AssertTrue(text [ (": approved from "_name_"."), channel_" on "_render_": the line reads '"_name_"'")
		}
	}
}

Method TestUserName()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("user")
	Do ..Resolved(owner, .local, , , , "web", "zzanswerer")
	Do $$$AssertEquals(..Command(host, "dismiss", local, owner).Ok, 1, "a local incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(local)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5), "summary.approvedBy", "on a local install the approval line names the user")
	Do $$$AssertEquals(..Slots(row, "summary.approvedBy").user, "zzanswerer", "with the row's AnsweredBy")
	Do $$$AssertTrue(##class(OcuTalon.Watch.Summary).Text(local, "web", .sc) [ ": approved by zzanswerer from the web chat.", "and reads as the ruled text")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Resolved(owner, .online, , , , "web", "zzanswerer")
	Do $$$AssertEquals(..Command(host, "dismiss", online, owner).Ok, 1, "an incident on the online demo is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(online)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5), "summary.approved", "on the online demo the approval line has no user")
	Do $$$AssertNotTrue(row.Summary [ "zzanswerer", "and the stored summary holds no user name")
	Do $$$AssertNotTrue(##class(OcuTalon.Watch.Summary).Text(online, "web", .sc) [ "zzanswerer", "nor does the text")
	Do ..Resolved(owner, .rejected, , , , "telegram", "zzanswerer", "rejected")
	Do $$$AssertEquals(..Command(host, "dismiss", rejected, owner).Ok, 1, "a rejected request on the online demo is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(rejected)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5), "summary.rejected", "a rejection has no user either")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ..Resolved(owner, .rejectedLocal, , , , "telegram", "zzanswerer", "rejected")
	Do $$$AssertEquals(..Command(host, "dismiss", rejectedLocal, owner).Ok, 1, "a rejected request on a local install is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(rejectedLocal)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5), "summary.rejectedBy", "a rejection names the user on a local install")
}

Method TestSampleErrorLength()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("sample")
	Set long = "Field OrderDate was not a date because the partner now sends the day before the month in every message it writes to the queue"
	Do ..Resolved(owner, .incident, , , , , , , long)
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set error = ..Slots(row, "summary.sampleError").error
	Do $$$AssertTrue($Length(error) '> $Parameter("OcuTalon.Watch.ErrorText", "SUMMARYMAX"), "the sample error is no longer than an incident notice's error summary: "_$Length(error))
	Do $$$AssertEquals(error, ##class(OcuTalon.Watch.ErrorText).Summary(long), "and is the notice's own cut")
}

Method TestTimelineOrder()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("order")
	Do ..Resolved(owner, .incident, .request)
	Set early = ..Request(owner, incident, "expired", ..T(-6100), {"ExpiresAt": (..T(-5500))})
	Do ..Link(incident, request_","_early)
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 1, 10), "summary.title,summary.firstFailure,summary.noticed,summary.requested,summary.requested,summary.expired,summary.approved,summary.fixStarted,summary.fixEnded,summary.closedDismiss", "the later request listed first in RequestRefs still comes first in time, and the expiry before the approval")
	Set iterator = {}.%FromJSON(row.Summary).parts.%GetIterator()
	Set last = ""
	Set ordered = 1
	While iterator.%GetNext(, .part) {
		Set time = part.slots.time
		If time = "" Continue
		If last ] time Set ordered = 0
		Set last = time
	}
	Do $$$AssertTrue(ordered, "every timeline line is at or after the one before it")
}

Method TestRunEdges()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("run")
	Do ..Resolved(owner, .interrupted, .request)
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request)
	Set run.Interrupted = 1
	Set run.Resent = 20
	Set run.Completed = 20
	$$$ThrowOnError(run.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", interrupted, owner).Ok, 1, "the incident with an interrupted run is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(interrupted)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5, 7), "summary.approved,summary.fixStarted,summary.fixInterrupted", "an interrupted run reads as interrupted, not as ended")
	Do $$$AssertEquals(..Slots(row, "summary.fixInterrupted").resent, 20, "with the number it resent")
	Do $$$AssertTrue(##class(OcuTalon.Watch.Summary).Text(interrupted, "web", .sc) [ ": the fix was interrupted after resending 20.", "which reads as the ruled text")
	Do ..Resolved(owner, .running, .request2)
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(request2)
	Set run.EndedAt = ""
	$$$ThrowOnError(run.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", running, owner).Ok, 1, "the incident with a run that has not ended is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(running)
	Do $$$AssertEquals($Piece(..Keys(row), ",", 5, 7), "summary.approved,summary.fixStarted,summary.closedDismiss", "a run that has not ended has only its start line")
}

Method TestGroupsOnlyWithoutFix()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("fixedgroups")
	Do ..Resolved(owner, .incident)
	Do ..Group(incident, 1, "OrdersFromPartner", 50, "The order date was not valid")
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "a fixed incident with a failure group is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertNotTrue(..Keys(row) [ "summary.groups", "its summary does not list the groups")
	Do $$$AssertTrue(..Keys(row) [ "summary.fix,", "and has its fix line")
}

Method TestAnswerEdges()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("edges")
	Do ..Resolved(owner, .unnamed, , , , "webhook")
	Do $$$AssertEquals(..Command(host, "dismiss", unnamed, owner).Ok, 1, "an incident answered from a channel with no name is dismissed")
	Set keys = ..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(unnamed))
	Do $$$AssertTrue(keys [ "summary.requested", "its request line stays")
	Do $$$AssertNotTrue((keys [ "summary.approved") || (keys [ "summary.rejected"), "and the answer has no line, because the channel cannot be named")
	Do ..Resolved(owner, .emailed, , , , "email")
	Do $$$AssertEquals(..Command(host, "dismiss", emailed, owner).Ok, 1, "an incident answered from email is dismissed")
	Set keys = ..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(emailed))
	Do $$$AssertTrue(keys [ "summary.requested", "email: its request line stays")
	Do $$$AssertNotTrue((keys [ "summary.approved") || (keys [ "summary.rejected"), "email: and the answer has no line, because email has no channel name yet")
	Set text = ##class(OcuTalon.Watch.Summary).Text(emailed, "web", .sc)
	Do $$$AssertStatusOK(sc, "email: the summary renders")
	Do $$$AssertNotTrue($ZConvert(text, "L") [ "email", "email: and no line names email")
	For state = "cancelled", "pending" {
		Do ..Resolved(owner, .open, , , , "phone", "", state)
		Do $$$AssertEquals(..Command(host, "dismiss", open, owner).Ok, 1, "an incident with a "_state_" request is dismissed")
		Set keys = ..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(open))
		Do $$$AssertTrue(keys [ "summary.requested", state_": the request line stays")
		Do $$$AssertNotTrue((keys [ "summary.approved") || (keys [ "summary.rejected") || (keys [ "summary.expired"), state_": and has no answer line")
	}
	For state = "executing", "done", "failed" {
		Do ..Resolved(owner, .after, , , , "phone", "", state)
		Do $$$AssertEquals(..Command(host, "dismiss", after, owner).Ok, 1, "an incident with a "_state_" request is dismissed")
		Do $$$AssertTrue(..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(after)) [ "summary.approved", state_": the request was approved, so the approval line stays")
	}
	Do ..Resolved(owner, .counted, .request)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Set row.DryRun = "{""affected"":4,""itemNoun"":{""one"":""order"",""other"":""orders""}}"
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", counted, owner).Ok, 1, "an incident whose dry run has only the affected count is dismissed")
	Set summary = ##class(OcuTalon.Data.Incident).RefIndexOpen(counted)
	Do $$$AssertEquals(..Slots(summary, "summary.requested").count, 4, "the affected count stands in for the resend count")
	Do ..Resolved(owner, .uncounted, .request2)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request2)
	Set row.DryRun = "{}"
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", uncounted, owner).Ok, 1, "an incident whose dry run holds no count is dismissed")
	Set keys = ..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(uncounted))
	Do $$$AssertNotTrue(keys [ "summary.requested", "its request line is left out")
	Do $$$AssertTrue(keys [ "summary.approved", "and the approval line stays")
}

Method TestMarkup()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("markup")
	Set markup = "<b>x</b> *y*"
	Do ..Resolved(owner, .incident, , .decision, , , , , markup)
	Set payload = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decision)
	Set payload.Payload = {"evidence": [(markup)]}.%ToJSON()
	$$$ThrowOnError(payload.%Save())
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.Cause = markup
	Set row.FixSummary = markup
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(..Slots(row, "summary.cause").cause_"|"_..Slots(row, "summary.evidence").evidence_"|"_..Slots(row, "summary.fix").fix_"|"_..Slots(row, "summary.sampleError").error, markup_"|"_markup_"|"_markup_"|"_markup, "the stored slots hold the markup as it came")
	For render = "web", "phone", "telegram" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
		Do $$$AssertStatusOK(sc, render_": the summary renders")
		Do $$$AssertTrue((text [ ("Cause: "_markup)) && (text [ ("Evidence: "_markup)) && (text [ ("Fix: "_markup)) && (text [ ("Sample error: "_markup)), render_": the four lines show the markup literally")
	}
}

/// The sample error of Built: markup first, then more than an incident notice's error summary allows, with no sentence end.
Parameter LONGMARKUP = "<b>x</b> *y* Field OrderDate was not a date because the partner now sends the day before the month in every message it writes to the queue";

/// A closed incident of the owner whose summary was built by Build (the dismiss event, a local install) from rows that hold markup: the cause, the fix and the sample
/// error (LONGMARKUP); its Ref. The summary is stored on the row as IncidentManager stores it, with no notification. The caller removes the incident.
ClassMethod Built(owner As %String) As %String
{
	Set all = {"State": "closed", "OpenVariant": "", "FirstAt": (..T(-7200)), "LastAt": (..T(-3600)), "ClosedAt": (..T(0)), "Count": 50, "NoticeCount": 50, "ItemNoun": (..#NOUN), "Cause": "The partner sent <b>x</b> and *y*.", "Element": "OrderDate", "FixSummary": "repair <i>the</i> date", "SampleError": (..#LONGMARKUP)}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..T(-6600), "ZZNS", "Zz.Built", all)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set summary = ##class(OcuTalon.Watch.Summary).Build(row, "dismiss", ..T(0), 0, .sc)
	$$$ThrowOnError(sc)
	Set row.Summary = summary.%ToJSON()
	$$$ThrowOnError(row.%Save())
	Quit ref
}

/// The lines that the built summary of LONGMARKUP's incident must have on every channel, as the test names them: the cause and the cut sample error. The sample error
/// is the notice's own cut of the text, at most SUMMARYMAX characters, and it keeps the markup that begins it.
ClassMethod CutLine() As %String
{
	Quit ##class(OcuTalon.Watch.ErrorText).Summary(..#LONGMARKUP)
}

/// AC14 (QA): a sample error that holds markup and is longer than an incident notice's error summary reaches every channel's text cut to that length and with its markup
/// as it came: "Sample error: " and the cut, no longer than the notice's, starting with the literal "<b>x</b> *y*"; the cause shows its markup too. The cut is less than
/// the whole text, so a build that forgot the cut fails here.
Method TestMarkupCut()
{
	Set owner = ##class(OcuTalon.Test.Data.Fixture).Session("zzsum"_..Number_"cut")
	Set ..Refs = owner
	Set incident = ..Built(owner)
	Set ..Refs = ..Refs_","_incident
	Set cut = ..CutLine()
	Do $$$AssertTrue($Length(cut) '> $Parameter("OcuTalon.Watch.ErrorText", "SUMMARYMAX"), "the cut is no longer than a notice's error summary: "_$Length(cut))
	Do $$$AssertTrue($Length(cut) < $Length(..#LONGMARKUP), "and shorter than the sample error")
	Do $$$AssertTrue($Extract(cut, 1, 13) = "<b>x</b> *y* ", "and starts with the markup as it came")
	For render = "web", "phone", "telegram" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
		Do $$$AssertStatusOK(sc, render_": the summary renders")
		Set lines = $ListFromString(text, $Char(10))
		Set found = ""
		Set position = 0
		While $ListNext(lines, position, line) {
			If $Extract(line, 1, 14) = "Sample error: " Set found = $Extract(line, 15, $Length(line))
		}
		Do $$$AssertEquals(found, cut, render_": the sample error line is the cut, with its markup")
		Do $$$AssertTrue(text [ "Cause: The partner sent <b>x</b> and *y*.", render_": and the cause shows its markup literally")
	}
}

/// AC14 (QA): text that looks like a catalog placeholder, or like another slot's value, is data: the cause, the evidence and the sample error render as they are, once, on every channel
/// (the renderer fills the text in one pass).
Method TestPlaceholderText()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("holders")
	Set holders = "{production} {count} {itemNoun}"
	Do ..Resolved(owner, .incident, , .decision, , , , , holders)
	Set payload = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decision)
	Set payload.Payload = {"evidence": [(holders)]}.%ToJSON()
	$$$ThrowOnError(payload.%Save())
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.Cause = holders
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	For render = "web", "phone", "telegram" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
		Do $$$AssertStatusOK(sc, render_": the summary renders")
		Do $$$AssertTrue((text [ ("Cause: "_holders)) && (text [ ("Evidence: "_holders)) && (text [ ("Sample error: "_holders)), render_": the placeholders stay as written")
		Do $$$AssertEquals($Length(text, holders) - 1, 3, render_": three times (cause, evidence, sample error), and nothing is filled in anywhere else")
	}
}

/// AC14 (QA): a cause, fix or element made only of characters that the renderer drops (a zero-width space) must not make the whole summary unreadable: the incident is
/// dismissed, and its stored summary still renders on every channel (the renderer refuses an empty slot, so the builder must leave such a line out).
Method TestInvisibleText()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("invisible")
	Set invisible = $Char(8203)
	Do ..Resolved(owner, .incident, , .decision, , , , , invisible)
	Set payload = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decision)
	Set payload.Payload = {"evidence": [(invisible)]}.%ToJSON()
	$$$ThrowOnError(payload.%Save())
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.Cause = invisible
	Set row.Element = invisible
	Set row.FixSummary = invisible
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	For render = "web", "phone", "telegram" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
		Do $$$AssertStatusOK(sc, render_": the summary still renders")
		Do $$$AssertTrue(text [ "Incident summary: 50 ", render_": with its title line")
		Do $$$AssertNotTrue((text [ "Cause:") || (text [ "Evidence:") || (text [ "Where it failed:") || (text [ "Fix:") || (text [ "Sample error:"), render_": and no line for the text that shows nothing")
	}
}

Method TestPeriodElement()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("period")
	Do ..Resolved(owner, .incident)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.Element = " ."_$Char(8203)
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the incident is dismissed")
	Set keys = ..Keys(##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
	Do $$$AssertTrue(keys [ "summary.cause", "the cause line stays")
	Do $$$AssertNotTrue(keys [ "summary.element", "and the element that is only a period has no line")
	For render = "web", "phone", "telegram" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(incident, render, .sc)
		Do $$$AssertStatusOK(sc, render_": the summary still renders")
		Do $$$AssertTrue(text [ "Incident summary: 50 ", render_": with its title line")
		Do $$$AssertNotTrue(text [ "Where it failed:", render_": and no element line")
	}
	Do ..Resolved(owner, .dotted)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(dotted)
	Set row.Element = "Order.Date."
	$$$ThrowOnError(row.%Save())
	Do $$$AssertEquals(..Command(host, "dismiss", dotted, owner).Ok, 1, "an incident whose element ends with a period is dismissed")
	Do $$$AssertTrue(##class(OcuTalon.Watch.Summary).Text(dotted, "web", .sc) [ "Where it failed: Order.Date.", "and an element with more than a period keeps its line")
	Do $$$AssertStatusOK(sc, "which renders")
}

Method TestGroupsAtClose()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("groupsclose")
	Set incident = ..Incident(owner, "open", {"Fallback": 1, "FallbackReason": "timeout", "Cause": "", "Element": "", "FixSummary": "", "OpenVariant": "fallback", "SampleError": "", "Count": 9, "NoticeCount": 3})
	Do ..Group(incident, 1, "OrdersFromPartner", 7, "The order date was not valid", 3)
	Do ..Group(incident, 2, "OrdersToWarehouse", 2, "The warehouse refused the order", "")
	Do $$$AssertEquals(..Command(host, "dismiss", incident, owner).Ok, 1, "the fallback incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set groups = ..Slots(row, "summary.groups").groups
	Do $$$AssertEquals(groups.%Size(), 2, "every group is listed, the one that formed after the notice included")
	Do $$$AssertEquals(groups.%Get(0).itemName_"|"_groups.%Get(0).count_"|"_groups.%Get(1).itemName_"|"_groups.%Get(1).count, "OrdersFromPartner|7|OrdersToWarehouse|2", "each with its count at the close, which add up to the failed count")
	Do $$$AssertEquals(..Slots(row, "summary.messages").failed, 9, "the failed count is the incident's")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertStatusOK(sc, "the summary renders")
	Do $$$AssertTrue(text [ ($Char(10)_"OrdersFromPartner: 7, "), "with the group's count at the close")
}

Method TestProductionName()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("production")
	Set namespace = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Do $$$AssertTrue(##class(OcuTalon.Watch.Reader).Admits(namespace, production, .display) && (display = "Orders"), "the demo production is listed with its display name Orders")
	Set demo = ..Incident(owner, "resolved", , production, namespace)
	Do $$$AssertEquals(..Command(host, "dismiss", demo, owner).Ok, 1, "the demo incident is dismissed")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(demo)
	Do $$$AssertEquals(..Slots(row, "summary.title").production, "Orders", "the title names the production by its display name, as the watch cards do")
	Do $$$AssertEquals($Piece(##class(OcuTalon.Watch.Summary).Text(demo, "web", .sc), $Char(10), 1), "Incident summary: 50 orders failed in Orders.", "the title line reads Orders, not the class name")
	Set other = ..Incident(owner, "resolved")
	Do $$$AssertEquals(..Command(host, "dismiss", other, owner).Ok, 1, "an incident of a production that is not listed is dismissed")
	Do $$$AssertEquals(..Slots(##class(OcuTalon.Data.Incident).RefIndexOpen(other), "summary.title").production, "Zz.Summary"_..Number, "and its title names the class name")
}

Method TestText()
{
	Set owner = ..Owner("text")
	Set incident = ..Incident(owner, "resolved")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertEquals(text_"|"_$SYSTEM.Status.IsError(sc), "|1", "an incident with no summary gives an error and no text")
	Set text = ##class(OcuTalon.Watch.Summary).Text(##class(OcuTalon.Bridge.Ids).NewRef(), "web", .sc)
	Do $$$AssertEquals(text_"|"_$SYSTEM.Status.IsError(sc), "|1", "so does an unknown incident")
	Set text = ##class(OcuTalon.Watch.Summary).Text("", "web", .sc)
	Do $$$AssertEquals(text_"|"_$SYSTEM.Status.IsError(sc), "|1", "and an empty Ref")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.Summary = "{""parts"":[{""key"":""summary.noFixRan"",""slots"":{}}],""lines"":[]}"
	Do $$$AssertStatusOK(row.%Save(), "a summary is stored")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Summary).Text(incident, "phone", .sc), "No fix ran, so nothing was changed.", "it renders from the row, one line per part")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Summary).Text(incident, "email", .sc)_"|"_$SYSTEM.Status.IsError(sc), "|1", "a channel that is not rendered is an error")
}

/// Story 23.2 (AC14): an incident with a suspend, a resume and a reroute request has each kind's requested line and the item kinds' own end lines, and the item runs add nothing
/// to the message counts (only the reroute's copies do), nor the diagnosis's fix line or "No fix ran".
Method TestKindLines()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("kinds")
	Set incident = ..Incident(owner, "resolved")
	Set suspend = ..Request(owner, incident, "done", ..T(-6000), {"FixKind": "suspend_item", "FixParameters": ("{""item"":""OrdersToWarehouse""}"), "FixTargets": "5", "DryRun": ("{""item"":""OrdersToWarehouse"",""before"":""enabled"",""after"":""disabled""}"), "AnsweredChannel": "web", "AnsweredAt": (..T(-5900))})
	Set resume = ..Request(owner, incident, "done", ..T(-5000), {"FixKind": "resume_item", "FixParameters": ("{""item"":""OrdersToWarehouse""}"), "FixTargets": "5", "DryRun": ("{""item"":""OrdersToWarehouse"",""before"":""disabled"",""after"":""enabled""}"), "AnsweredChannel": "web", "AnsweredAt": (..T(-4900))})
	Set skipped = ..Request(owner, incident, "done", ..T(-4500), {"FixKind": "resume_item", "FixParameters": ("{""item"":""OrdersToWarehouse""}"), "FixTargets": "5", "DryRun": ("{""item"":""OrdersToWarehouse"",""before"":""disabled"",""after"":""enabled""}"), "AnsweredChannel": "web", "AnsweredAt": (..T(-4400))})
	Set reroute = ..Request(owner, incident, "done", ..T(-4000), {"FixKind": "reroute", "FixParameters": ("{""target"":""OrdersForReview""}"), "FixTargets": "1,2,3", "DryRun": ("{""affected"":3,""resend"":3,""leftOut"":0,""itemNoun"":{""one"":""order"",""other"":""orders""},""from"":""OrdersFromPartner"",""to"":""OrdersForReview"",""example"":""1""}"), "AnsweredChannel": "web", "AnsweredAt": (..T(-3900))})
	Do ..Link(incident, suspend_","_resume_","_skipped_","_reroute)
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, suspend, {"StartedAt": (..T(-5800)), "EndedAt": (..T(-5700)), "Total": 1, "Resent": 0, "Completed": 1, "FailedAgain": 0, "Skipped": 0})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, resume, {"StartedAt": (..T(-4800)), "EndedAt": (..T(-4700)), "Total": 1, "Resent": 0, "Completed": 1, "FailedAgain": 0, "Skipped": 0})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, skipped, {"StartedAt": (..T(-4300)), "EndedAt": (..T(-4200)), "Total": 1, "Resent": 0, "Completed": 0, "FailedAgain": 0, "Skipped": 1})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, reroute, {"StartedAt": (..T(-3800)), "EndedAt": (..T(-3700)), "Total": 3, "Resent": 3, "Completed": 3, "FailedAgain": 0, "Skipped": 0})
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|closed", "the Dismiss closes the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set keys = ..Keys(row)
	Do $$$AssertEquals($Length(keys, "summary.requestedSuspend") - 1, 1, "a suspend request has its requested line: "_keys)
	Do $$$AssertEquals($Length(keys, "summary.requestedResume") - 1, 2, "so has each resume request")
	Do $$$AssertEquals($Length(keys, "summary.requestedReroute") - 1, 1, "and the reroute request")
	Do $$$AssertEquals($Length(keys, "summary.requested,") - 1, 0, "none of them has the repair's requested line")
	Do $$$AssertEquals($Length(keys, "summary.itemSuspended") - 1, 1, "the suspend ends with summary.itemSuspended")
	Do $$$AssertEquals($Length(keys, "summary.itemResumed") - 1, 1, "the resume that changed the item ends with summary.itemResumed")
	Do $$$AssertEquals($Length(keys, "summary.itemNotChanged") - 1, 1, "the resume that changed nothing ends with summary.itemNotChanged")
	Do $$$AssertEquals($Length(keys, "summary.fixEnded") - 1, 1, "and only the reroute ends with the counts (summary.fixEnded)")
	Do $$$AssertEquals($Length(keys, "summary.noFixRan") - 1, 0, "a fix ran, so the summary does not say that none did")
	Do $$$AssertEquals($Length(keys, "summary.fix,") - 1, 0, "and the diagnosis's fix line is not there: no fix of a kind the diagnosis proposes ran")
	Do $$$AssertEquals(..Slots(row, "summary.requestedSuspend").item, "OrdersToWarehouse", "the suspend line names the item")
	Set reroutes = ..Slots(row, "summary.requestedReroute")
	Do $$$AssertEquals(reroutes.count_"|"_reroutes.to, "3|OrdersForReview", "and the reroute line the count and the target")
	Do $$$AssertEquals(..Slots(row, "summary.itemSuspended").item, "OrdersToWarehouse", "the item run line names the item")
	Set messages = ..Slots(row, "summary.messages")
	Do $$$AssertEquals(messages.failed_"|"_messages.resent_"|"_messages.completed_"|"_messages.failedAgain_"|"_messages.skipped, "50|3|3|0|0", "the item runs add nothing to the message counts: only the reroute's copies are in them")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertStatusOK(sc, "the summary renders")
	Do $$$AssertTrue(text [ ": OcuTalon asked for approval to suspend OrdersToWarehouse.", "the suspend line reads as ruled")
	Do $$$AssertTrue(text [ ": OrdersToWarehouse was suspended.", "and its end line")
	Do $$$AssertTrue(text [ ": OcuTalon asked for approval to reroute 3 orders to OrdersForReview.", "and the reroute line")
}

/// Story 23.5 (AC13): an incident with a sent, a kept and a not sent partner delay notice has the requested line (with the number of recipients) and the ended line of each, the message counts are the repair's
/// alone, and the notice's runs make neither a diagnosis fix line nor "No fix ran" go away.
Method TestPartnerLines()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("partner")
	Set incident = ..Incident(owner, "resolved")
	Set parameters = "{""text"":""A notice."",""to"":""it@results-partner.example""}"
	Set dryRun = "{""notice"":""A notice."",""recipients"":[{""name"":""Results Partner IT"",""address"":""it@results-partner.example""}],""simulated"":1}"
	Set sent = ..Request(owner, incident, "done", ..T(-6000), {"FixKind": "partner_warning", "FixParameters": (parameters), "FixTargets": "1", "DryRun": (dryRun), "AnsweredChannel": "web", "AnsweredAt": (..T(-5900))})
	Set kept = ..Request(owner, incident, "failed", ..T(-5000), {"FixKind": "partner_warning", "FixParameters": (parameters), "FixTargets": "1", "DryRun": (dryRun), "AnsweredChannel": "web", "AnsweredAt": (..T(-4900))})
	Set notSent = ..Request(owner, incident, "done", ..T(-4000), {"FixKind": "partner_warning", "FixParameters": (parameters), "FixTargets": "1,2", "DryRun": (dryRun), "AnsweredChannel": "web", "AnsweredAt": (..T(-3900))})
	Do ..Link(incident, sent_","_kept_","_notSent)
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, sent, {"StartedAt": (..T(-5800)), "EndedAt": (..T(-5700)), "Total": 1, "Resent": 0, "Completed": 1, "FailedAgain": 0, "Skipped": 0})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, kept, {"StartedAt": (..T(-4800)), "EndedAt": (..T(-4700)), "Total": 1, "Resent": 0, "Completed": 0, "FailedAgain": 0, "Skipped": 0, "Reason": ($Parameter("OcuTalon.Fix.Kind.PartnerWarning", "NOTSETUP"))})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, notSent, {"StartedAt": (..T(-3800)), "EndedAt": (..T(-3700)), "Total": 2, "Resent": 0, "Completed": 0, "FailedAgain": 0, "Skipped": 2, "Reason": "Partner contact 2 is no longer a partner contact of Orders"})
	Set result = ..Command(host, "dismiss", incident, owner)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|closed", "the Dismiss closes the incident")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set keys = ..Keys(row)
	Do $$$AssertEquals($Length(keys, "summary.requestedPartner") - 1, 3, "each partner request has its requested line: "_keys)
	Do $$$AssertEquals($Length(keys, "summary.partnerSent") - 1, 1, "the sent notice ends with summary.partnerSent")
	Do $$$AssertEquals($Length(keys, "summary.partnerKept") - 1, 1, "the kept one with summary.partnerKept")
	Do $$$AssertEquals($Length(keys, "summary.partnerNotSent") - 1, 1, "and the one that reached nobody with summary.partnerNotSent")
	Do $$$AssertEquals($Length(keys, "summary.fixEnded") - 1, 0, "none of them has the counts line")
	Do $$$AssertEquals($Length(keys, "summary.fixStarted") - 1, 0, "nor a line that says a fix started: a delay notice is not a fix")
	Do $$$AssertEquals($Length(keys, "summary.requested,") - 1, 0, "nor the repair's requested line")
	Do $$$AssertEquals($Length(keys, "summary.noFixRan") - 1, 1, "a delay notice is not a fix, so the summary still says that no fix ran")
	Do $$$AssertEquals(..Slots(row, "summary.requestedPartner").count, 1, "the requested line counts the recipients")
	Set messages = ..Slots(row, "summary.messages")
	Do $$$AssertEquals(messages.failed_"|"_messages.resent_"|"_messages.completed_"|"_messages.failedAgain_"|"_messages.skipped, "50|0|0|0|0", "the message counts are unchanged by the notices")
	Set text = ##class(OcuTalon.Watch.Summary).Text(incident, "web", .sc)
	Do $$$AssertStatusOK(sc, "the summary renders")
	Do $$$AssertTrue(text [ ": OcuTalon asked for approval to send a delay notice to the partner contact.", "the requested line reads as ruled")
	Do $$$AssertTrue(text [ ": OcuTalon asked for approval to send a delay notice to 2 partner contacts.", "also for two recipients")
	Do $$$AssertTrue(text [ ": the delay notice went to the Simulated mailbox.", "the sent line")
	Do $$$AssertTrue(text [ ": the delay notice was approved and kept as a draft.", "the kept line")
	Do $$$AssertTrue(text [ ": the delay notice was not sent.", "and the not sent line")
}

/// A shadow instance of the probe.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture incidents.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsum"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The UTC time the seconds from now.
ClassMethod T(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
}

/// A fixture incident of the owner in the state, noticed 6600 seconds ago, whose first failure is 7200 seconds ago, with the fields after the defaults, in the
/// production and namespace (Zz.Summary<n> in ZZNS by default); its Ref.
Method Incident(owner As %String, state As %String, fields As %DynamicObject = "", production As %String = "", namespace As %String = "ZZNS") As %String
{
	If production = "" Set production = "Zz.Summary"_..Number
	Set all = {"State": (state), "OpenVariant": "", "FirstAt": (..T(-7200)), "LastAt": (..T(-3600)), "Count": 50, "NoticeCount": 50, "ItemNoun": (..#NOUN), "Cause": "The partner changed the date format.", "Element": "OrderDate", "FixSummary": "repair the date and resend the orders", "SampleError": "Field OrderDate was not a date."}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..T(-6600), namespace, production, all)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_","_ref
	Quit ref
}

/// A fixture approval request of the owner for the incident, in the state, raised at raisedAt, with the fields after the defaults; its Ref.
Method Request(owner As %String, incident As %String, state As %String, raisedAt As %String, fields As %DynamicObject = "") As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, raisedAt, fields)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// The incident's RequestRefs.
ClassMethod Link(incident As %String, refs As %String)
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = refs
	$$$ThrowOnError(row.%Save())
}

/// Deletes the failure groups of the incident.
ClassMethod DropGroups(incident As %String)
{
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident)
	For i = 1:1:groups.Count() {
		Do ##class(OcuTalon.Data.FailureGroup).%DeleteId(groups.GetAt(i).%Id())
	}
}

/// A failure group of the incident with its name, count and error summary, and its NoticeCount (the count unless another is given; "" for a group that formed
/// after the notice).
Method Group(incident As %String, seq As %Integer, item As %String, count As %Integer, error As %String, noticeCount As %String = "*")
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = seq
	Set group.ItemName = item
	Set group.ErrorPattern = error
	Set group.ErrorSummary = error
	Set group.Count = count
	Set group.NoticeCount = $Select(noticeCount = "*": count, 1: noticeCount)
	Set group.FirstAt = ..T(-7200)
	Set group.LastAt = ..T(-3600)
	$$$ThrowOnError(group.%Save())
}

/// A resolved incident of the owner whose first failure is 7200 seconds ago and whose last is lastOffset seconds from now (-3600 by default), with an approved request
/// (answered 5400 seconds ago on the channel, by the user; state approved unless another is given), its fix run (50 resent, 50 completed; 5000 to 3600 seconds ago),
/// and a diagnosis decision with the evidence line and two usage rows (0.0123 and 0.0045). The Refs of the incident, the request and the decision are returned.
Method Resolved(owner As %String, ByRef incident As %String, ByRef request As %String, ByRef decision As %String, lastOffset As %Integer = -3600, channel As %String = "phone", user As %String = "", state As %String = "approved", sampleError As %String = "Field OrderDate was not a date.")
{
	Set payload = {"evidence": ["OrderDate 16/10/2026 in the sample", "a second line"], "cause": "x"}.%ToJSON()
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "diagnose", ..T(-6700), {"Payload": (payload)})
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, owner, {"CostUSD": 0.0123, "InputTokens": 100})
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(decision, owner, {"CostUSD": 0.0045, "InputTokens": 40})
	Set ..Refs = ..Refs_","_decision
	Set incident = ..Incident(owner, "resolved", {"LastAt": (..T(lastOffset)), "DecisionRef": (decision), "SampleError": (sampleError)})
	Set request = ..Request(owner, incident, state, ..T(-6000), {"AnsweredChannel": (channel), "AnsweredAt": (..T(-5400)), "AnsweredBy": (user), "State": (state)})
	Do ..Link(incident, request)
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, request, {"StartedAt": (..T(-5000)), "EndedAt": (..T(-3600)), "Total": 50, "Resent": 50, "Completed": 50, "FailedAgain": 0, "Skipped": 0})
}

/// An IncidentCommand of the verb for the incident from the session, handled by the probe; the CommandResult.
Method Command(host As OcuTalon.Test.Watch.IncidentProbe, verb As %String, incident As %String, session As %String) As OcuTalon.Msg.CommandResult
{
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = verb
	Set command.IncidentRef = incident
	Set command.SessionRef = session
	Set command.Origin = "web_user"
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "the "_verb_" command is handled")
	Quit response
}

/// The summary Notifications that the probe recorded, in order.
ClassMethod Summaries(host As OcuTalon.Test.Watch.IncidentProbe) As %DynamicArray
{
	Set found = []
	If '$IsObject(host.Sent) Quit found
	For i = 0:1:host.Sent.%Size() - 1 {
		If host.Sent.%Get(i).kind = "summary" Do found.%Push(host.Sent.%Get(i))
	}
	Quit found
}

/// The keys of the stored summary's parts, comma-separated, in order.
ClassMethod Keys(row As OcuTalon.Data.Incident) As %String
{
	If row.Summary = "" Quit ""
	Set keys = ""
	Set iterator = {}.%FromJSON(row.Summary).parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_part.key
	}
	Quit keys
}

/// The slots of the first part with the key, "" when there is none.
ClassMethod Slots(row As OcuTalon.Data.Incident, key As %String) As %DynamicObject
{
	Set iterator = {}.%FromJSON(row.Summary).parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = key Quit
	}
	Quit $Select($Get(part) '= "" && (part.key = key): part.slots, 1: "")
}

/// The number of rows of the table in OcuTalon_Bridge_Data.
ClassMethod Count(table As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data."_table)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
