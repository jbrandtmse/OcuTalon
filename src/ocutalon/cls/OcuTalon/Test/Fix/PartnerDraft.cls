/// Tests of the partner delay notice in IncidentManager (Story 23.5; AD-1, AD-6, AD-15, AD-20, AD-32): a ProposeFix for partner_warning, the draft's request to Decide, the end of the draft
/// and the events of the request, handled by a shadow instance of Test.Watch.IncidentProbe over fixture sessions, incidents and requests of Test.Data.Fixture. The probe records the
/// draft that the ask started (Drafts), the request to Decide (DraftRequests), the dry run asked (Asks, answered with the real kind's own dry run), the request raised (Raised) and each
/// Notification sent (Sent). Demo mode is on for each test and put back after it; they set the public flag onlineDemo in TestAllowance, so they run on the warm stack, never on a slot.
///   - TestAskStartsTheDraft (AC1): an ask on a resolved incident of the session answers drafting with the ruled message, starts one draft in the incident's trace session, asks no dry run, raises
///     nothing, tells nobody and leaves the incident as it was; an ask on an open and on an awaiting_approval incident does the same;
///   - TestDraftRequest (AC1): the request to Decide is a turn, untrusted, fresh, owned by the asking session, with a new ItemId, the kind's instruction and, as input, exactly what
///     Agent.Input renders of the kind's Facts: no sample error, evidence or fix summary of the incident;
///   - TestDraftRaised (AC1, AC2, AC9): the draft's text is normalised to one paragraph and raised as exactly one partner_warning request that holds the text and the recipient and is fixed to
///     contact 1, with the dry run's notice, recipients and simulated 1; the session gets one approval Notification incident.partnerRequest with the request's Ref, whose slots render as ruled for
///     the web, the phone and Telegram; the incident's state and open variant are as they were;
///   - TestAlreadyAsked (AC1): a pending or an approved request of the kind (whatever its text) makes the ask already_asked and starts no draft; a late draft raises nothing, writes one info line and tells
///     nobody; a rejected request does not block a new ask;
///   - TestRefusals (AC7): an item or an address is refused with NOITEM, no contact (demo mode off, or another production) with NOCONTACTS, a closed incident is not_found, a session that is not a recipient is
///     not_found and an incident that was not noticed is not_allowed; none starts a draft;
///   - TestAllowance (AC10): on the online demo a session with 19 incoming emails and notices is allowed one more notice, with 20 it is refused with ALLOWANCE, a sent notice counts, and the flag off lifts it;
///   - TestDraftFails (AC12): a fallback, an error answer, an answer that is no Reply, an empty text, a text over 1000 characters, a refused dry run, a failed raise and a request to Decide that cannot be sent each raise nothing and
///     tell the session result.partnerNotDrafted, with no ApprovalRef, which renders as ruled; a usable answer for an incident that was closed while the draft ran raises nothing and tells nobody;
///   - TestDraftCompletionRouting (AC12): Decide's answer and its error reach Drafted through the draft's completion key of OnResponse and OnError (an error under another key stays an error, an answer
///     under another key does nothing), as the framework calls them;
///   - TestStateNeverMoves (AC5, AC9): the approved, rejected, expired and result events of a partner request, on a resolved and on an open (rejected) incident, tell the session and leave the state and the open variant
///     as they were; approved sends the Execute at once, the others none; on a closed incident (the incident stays closed, nothing is carried out) an approved request is told as result.partnerNotSent with the kind's NOSTART as the reason, a final result (not sent, or sent) is told as it came, and a progress result, a rejection and an expiry are refused; and such a request is left out of the table's facts, while a repair request still counts;
///   - TestNoticeKeys (AC2): Notice.AskedKey and AskedSlots for the kind, and the result notice's slots;
///   - TestDraftRequestCarriesOutcome (AC3, AC6, Story 23.11): the request to Decide for a resolved incident with a reroute run holds the Outcome line of Count messages and no target name, with the rendered instruction (no {noun} token); one with no run holds no Outcome line.
Class OcuTalon.Test.Fix.PartnerDraft Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

Parameter PRODUCTION = "OcuTalon.Demo.Orders.Production";

Parameter ADDRESS = "it@orders-partner.example";

Parameter NOUN = "{""one"":""order"",""other"":""orders""}";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the incidents of the test being run, comma-separated.
Property Incidents As %String(MAXLEN = "");

/// The log row before the test.
Property LogMark As %Integer;

/// The demo.mode row as it was, for PutBack, and the public flag onlineDemo as it was.
Property Found As %Boolean;

Property Was As %String;

Property WasAt As %String;

Property OnlineWas As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("PartnerDraft", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .was, .wasAt)
	Set ..Found = found, ..Was = was, ..WasAt = wasAt
	Set ..OnlineWas = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
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
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..Found, ..Was, ..WasAt)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineWas)
	For method = "AskedDraft", "Drafted", "RaiseAsked", "NotDrafted" {
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, method, $Parameter(..#PROBE, "LOGDRAFT"))
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, method, $Parameter(..#PROBE, "LOGASK"))
	}
	Quit $$$OK
}

/// The ask: drafting, one draft started, nothing else.
Method TestAskStartsTheDraft()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("ask")
	For state = "resolved", "open", "awaiting_approval" {
		Set incident = ..Incident(owner, state)
		Set drafts = ..Count(host.Drafts)
		Set response = ..Ask(host, owner, incident, {})
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "1|drafting|", state_": the answer is drafting")
		Do $$$AssertEquals(response.Message, "I'm drafting the delay notice now. It will come as an approval request with the exact text and the recipients, and nothing is sent until it is approved.", state_": with the ruled message for the model")
		Do $$$AssertEquals(..Count(host.Drafts), drafts + 1, state_": one draft is started")
		Set draft = host.Drafts.%Get(host.Drafts.%Size() - 1)
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(draft.incidentRef_"|"_draft.sessionRef_"|"_draft.fixKind_"|"_draft.sessionId, incident_"|"_owner_"|partner_warning|"_stored.TraceHeaderId, state_": for the incident, the asking session and the kind, in the incident's trace session")
		Do $$$AssertEquals(stored.State_"|"_stored.RequestRefs, state_"|", state_": the incident is as it was")
	}
	Do $$$AssertEquals(..Count(host.Asks)_"|"_..Count(host.Raised)_"|"_..Count(host.Sent)_"|"_..Count(host.DryRuns), "0|0|0|0", "no dry run was asked, no request raised and nobody told")
	Set host.FailStartDraft = 1
	Set response = ..Ask(host, owner, ..Incident(owner, "resolved"), {})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "a draft that cannot be started is failed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "AskedDraft", $Parameter(..#PROBE, "LOGDRAFT")), 1, "with one Type 3 warning")
}

/// The request to Decide.
Method TestDraftRequest()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("req")
	Set incident = ..Incident(owner, "resolved", {"SampleError": "ERROR secret-sample-text", "FixSummary": "secret-fix-summary", "Element": "secret-element", "Cause": "The partner changed the date format."})
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(incident, owner)), "the draft is handled")
	Do $$$AssertEquals(..Count(host.DraftRequests), 1, "one request goes to Decide")
	If ..Count(host.DraftRequests) '= 1 Quit
	Set request = host.DraftRequests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.provenance_"|"_request.sessionMode_"|"_request.ownerRef_"|"_request.channel, "turn|untrusted|fresh|"_owner_"|system", "it is a turn, untrusted, fresh, owned by the asking session")
	Do $$$AssertEquals($Length(request.itemId), 22, "with a new ItemId")
	Do $$$AssertEquals(request.systemNote, ##class(OcuTalon.Fix.Kind.PartnerWarning).SystemNote(##class(OcuTalon.Data.Incident).RefIndexOpen(incident)), "and the kind's instruction for the incident's noun")
	Set carrier = ##class(OcuTalon.Msg.Item).%New()
	Set carrier.Channel = "system"
	Set carrier.Provenance = "untrusted"
	Set carrier.Subject = "Partner delay notice"
	Set carrier.Text = ##class(OcuTalon.Fix.Kind.PartnerWarning).Facts(##class(OcuTalon.Data.Incident).RefIndexOpen(incident))
	Do $$$AssertEquals($Piece(request.input, $Char(10, 10), 2, *), $Piece(##class(OcuTalon.Agent.Input).Render(carrier), $Char(10, 10), 2, *), "its input is exactly what Agent.Input renders of the kind's Facts (after the preamble, which holds the time)")
	For secret = "secret-sample-text", "secret-fix-summary", "secret-element" {
		Do $$$AssertEquals($Find(request.input, secret), 0, "the input holds no "_secret)
	}
	Do $$$AssertTrue($Find(request.input, "Orders Partner IT") > 0 && ($Find(request.input, "The partner changed the date format.") > 0), "but it holds the partner and the cause")
	Do $$$AssertTrue($Find(request.input, "Incident state: resolved") > 0, "and the incident's state")
	// a closed or missing incident drafts nothing
	Set closed = ..Incident(owner, "closed")
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(closed, owner)), "a draft for a closed incident is handled")
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(##class(OcuTalon.Bridge.Ids).NewRef(), owner)), "and one for an unknown incident")
	Do $$$AssertEquals(..Count(host.DraftRequests), 1, "and sends no request")
	Set host.FailSendDraft = 1
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(incident, owner)), "a request that cannot be sent is handled")
	Do $$$AssertEquals(..Count(host.Raised), 0, "it raises nothing")
	Do $$$AssertEquals(..Count(host.Sent), 1, "and tells the session that the draft failed")
}

/// The draft's end: one request, one notification, the state as it was.
Method TestDraftRaised()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("raise")
	For case = 1, 2 {
		Set incident = ..Incident(owner, $Select(case = 1: "resolved", 1: "open"), $Select(case = 1: {}, 1: {"OpenVariant": "rejected"}))
		Set host.DryAnswer = ""
		Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set ref = host.RaiseRef
		Set text = $Select(case = 1: "Orders from your feed failed.", 1: "  First line."_$Char(13, 10, 13, 10)_"Second"_$Char(9)_"line.  ")
		Set expected = $Select(case = 1: text, 1: "First line. Second line.")
		Set host.DryAnswer = ..RealAnswer(incident, expected)
		Set sent = ..Count(host.Sent)
		Do $$$AssertStatusOK(host.EndDraft(..Draft(incident, owner), ..Reply(text)), "case "_case_": the answer of Decide is handled")
		Do $$$AssertEquals(..Count(host.Raised), case, "case "_case_": one request is raised")
		Set row = host.Raised.%Get(host.Raised.%Size() - 1)
		Do $$$AssertEquals(row.kind_"|"_row.incidentRef_"|"_row.ownerRef_"|"_row.resultTarget_"|"_row.fixKind_"|"_row.fixTargets, "fix|"_incident_"|"_owner_"|IncidentManager|partner_warning|1", "case "_case_": a partner_warning request fixed to contact 1")
		Do $$$AssertEquals(row.fixParameters, {"text": (expected), "to": (..#ADDRESS)}.%ToJSON(), "case "_case_": its parameters are the normalised text and the recipient")
		Set dry = {}.%FromJSON(row.dryRun)
		Do $$$AssertEquals(dry.notice_"|"_dry.recipients.%Size()_"|"_dry.recipients.%Get(0).name_"|"_dry.recipients.%Get(0).address_"|"_dry.simulated, expected_"|1|Orders Partner IT|"_..#ADDRESS_"|1", "case "_case_": its dry run holds the exact text, every recipient and simulated 1")
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(stored.State_"|"_stored.OpenVariant_"|"_stored.RequestRefs, $Select(case = 1: "resolved|", 1: "open|rejected")_"|"_ref, "case "_case_": the incident keeps its state and open variant and lists the request")
		Do $$$AssertEquals(..Count(host.Sent), sent + 1, "case "_case_": the session gets one Notification")
		Set note = host.Sent.%Get(host.Sent.%Size() - 1)
		Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef, owner_"|approval|incident.partnerRequest|"_ref_"|"_incident, "case "_case_": of kind approval with the key incident.partnerRequest and the request's Ref")
		Set slots = {}.%FromJSON(note.slots)
		Do $$$AssertEquals(slots.recipients_"|"_slots.notice, "Orders Partner IT <"_..#ADDRESS_">|"_expected, "case "_case_": its slots are the recipients and the notice")
		Do $$$AssertEquals(slots.%Size(), 2, "case "_case_": and nothing else")
	}
	Set phone = ##class(OcuTalon.Msg.Catalog).Render("incident.partnerRequest", note.slots, "phone", .sc)
	Do $$$AssertStatusOK(sc, "the notice renders for the phone")
	Do $$$AssertEquals(phone, "I drafted a delay notice about this incident for Orders Partner IT <"_..#ADDRESS_">. Approve sending it?"_$Char(10, 10)_"Dry run: the notice below would go to the Simulated mailbox, not to a real inbox. The recipients are simulated partner contacts."_$Char(10, 10)_"First line. Second line."_$Char(10, 10)_"Nothing has been sent yet."_$Char(10, 10)_"Details and trace: on your OcuTalon page.", "as ruled, with the exact text and every recipient")
	Set web = ##class(OcuTalon.Msg.Catalog).Render("incident.partnerRequest", note.slots, "web", .sc)
	Do $$$AssertEquals($Piece(web, $Char(10), 1), "I drafted a delay notice about this incident for Orders Partner IT <"_..#ADDRESS_">.", "the web form has no question")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("incident.partnerRequest", note.slots, "telegram", .sc), phone, "and Telegram reads as the phone does")
}

/// An earlier request blocks the ask and a late draft.
Method TestAlreadyAsked()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("twice")
	Set incident = ..Incident(owner, "resolved")
	For state = "pending", "approved" {
		Set ref = ..Row(owner, incident, state, "First text.")
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Set stored.RequestRefs = ref
		Do $$$AssertStatusOK(stored.%Save(), state_": the incident lists the request")
		Kill stored
		Set response = ..Ask(host, owner, incident, {})
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|already_asked", state_": the ask is already_asked, whatever the text")
		Do $$$AssertEquals(response.Message, "That approval request is already waiting, so no second one was raised.", state_": with the ruled message")
		Do $$$AssertEquals(..Count(host.Drafts), 0, state_": no draft is started")
		Set sent = ..Count(host.Sent)
		Set host.DryAnswer = ..RealAnswer(incident, "Second text.")
		Do $$$AssertStatusOK(host.EndDraft(..Draft(incident, owner), ..Reply("Second text.")), state_": a late draft is handled")
		Do $$$AssertEquals(..Count(host.Raised)_"|"_(..Count(host.Sent) - sent), "0|0", state_": it raises nothing and tells nobody")
		Do $$$AssertEquals(..Info(), 1, state_": one info line says so")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGDRAFTED"))
	}
	Set old = ..Incident(owner, "resolved")
	Set ref = ..Row(owner, old, "rejected", "Old text.")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(old)
	Set stored.RequestRefs = ref
	Do $$$AssertStatusOK(stored.%Save(), "an incident that lists a rejected request")
	Kill stored
	Set response = ..Ask(host, owner, old, {})
	Do $$$AssertEquals(response.Outcome, "drafting", "a rejected request does not block a new ask")
}

/// The refusals of the ask, each before any draft.
Method TestRefusals()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("refuse")
	Set other = ..Owner("stranger")
	Set incident = ..Incident(owner, "resolved")
	Set response = ..Ask(host, owner, incident, {"item": "orders@attacker.example"})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|refused", "an item or address is refused")
	Do $$$AssertEquals(response.Message, "A delay notice takes no item or address: its recipients are the partner contacts set up for "_..#PRODUCTION, "with NOITEM and the production")
	Set response = ..Ask(host, owner, ..Incident(owner, "resolved", {"Production": "Zz.Other.Production"}), {})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|refused|No partner contacts are set up for Zz.Other.Production, so no delay notice was drafted", "a production with no contact is refused with NOCONTACTS")
	Do ..DemoMode(0)
	Set response = ..Ask(host, owner, incident, {})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|refused|No partner contacts are set up for "_..#PRODUCTION_", so no delay notice was drafted", "demo mode off: no contact, so NOCONTACTS")
	Do ..DemoMode(1)
	Set response = ..Ask(host, owner, ..Incident(owner, "closed"), {})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_found", "a closed incident is not found")
	Set response = ..Ask(host, other, incident, {})
	Do $$$AssertEquals(response.Outcome, "not_found", "so is an incident of another session")
	Set response = ..Ask(host, owner, ..Incident(owner, "open", {"NoticedAt": ""}), {})
	Do $$$AssertEquals(response.Outcome, "not_allowed", "an incident that was not noticed is not allowed")
	Set command = ..Command(owner, incident, {})
	Set command.Parameters = "not json"
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "parameters that are no object are handled")
	Do $$$AssertEquals(response.Outcome, "not_allowed", "and are not allowed")
	Do $$$AssertEquals(..Count(host.Drafts)_"|"_..Count(host.Asks)_"|"_..Count(host.Raised)_"|"_..Count(host.Sent), "0|0|0|0", "no draft, dry run, request or Notification")
}

/// The online demo's 20 simulated emails an hour, incoming and notices together.
Method TestAllowance()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("allow")
	Set incident = ..Incident(owner, "resolved")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	For i = 1:1:14 {
		Do ##class(OcuTalon.Test.Data.Fixture).SimMessage(owner, {"Kind": "mailbox", "Direction": "in", "CreatedAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -3000 + i)), "Subject": "zz mail"})
	}
	For i = 1:1:5 {
		Do ##class(OcuTalon.Test.Data.Fixture).SimMessage(owner, {"Kind": "mailbox", "Direction": "out", "CreatedAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -2000 + i)), "Subject": "zz notice", "ApprovalRef": "ZzApprovalRef00000001"})
	}
	Set response = ..Ask(host, owner, incident, {})
	Do $$$AssertEquals(response.Outcome, "drafting", "14 incoming emails and 5 notices: one more notice is allowed")
	Do ##class(OcuTalon.Test.Data.Fixture).SimMessage(owner, {"Kind": "mailbox", "Direction": "out", "CreatedAt": (##class(OcuTalon.Data.Time).AddSeconds(now, -1000)), "Subject": "zz notice", "ApprovalRef": "ZzApprovalRef00000002"})
	Set drafts = ..Count(host.Drafts)
	Set response = ..Ask(host, owner, incident, {})
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|refused", "with a sixth notice, 20 simulated emails: refused")
	Do $$$AssertEquals(response.Message, "The online demo allows 20 simulated emails an hour, and this session has used them for now, so no delay notice was drafted", "with ALLOWANCE")
	Do $$$AssertEquals(..Count(host.Drafts), drafts, "nothing is drafted")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set response = ..Ask(host, owner, incident, {})
	Do $$$AssertEquals(response.Outcome, "drafting", "with the flag off there is no limit")
}

/// A draft that fails raises nothing and says so.
Method TestDraftFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("fails")
	Set incident = ..Incident(owner, "resolved")
	Set long = $Translate($Justify("", 1001), " ", "a")
	Set cases = $ListBuild("fallback", "error", "notreply", "empty", "blank", "long", "refused", "raise", "nodry")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set host.FailRaise = 0
		Set host.DryAnswer = ..RealAnswer(incident, "A notice.")
		Set answer = ..Reply("A notice.")
		Set error = $$$OK
		If case = "fallback" Set answer.Fallback = 1, answer.FallbackReason = "timeout"
		If case = "error" Set error = $SYSTEM.Status.Error(5001, "Decide refused the request"), answer = ""
		If case = "notreply" Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
		If case = "empty" Set answer.Text = ""
		If case = "blank" Set answer.Text = $Char(13, 10, 9)_" "
		If case = "long" Set answer.Text = long
		If case = "refused" {
			Set refused = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
			Set refused.Reason = "The recipients are not the contacts"
			Set host.DryAnswer = refused
		}
		If case = "raise" Set host.FailRaise = 1
		If case = "nodry" Set host.DryAnswer = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
		Set sent = ..Count(host.Sent)
		Set raised = ..Count(host.Raised)
		Do $$$AssertStatusOK(host.EndDraft(..Draft(incident, owner), answer, error), case_": the end of the draft is handled")
		Do $$$AssertEquals(..Count(host.Raised), raised + $Select(case = "raise": 1, 1: 0), case_": nothing is raised"_$Select(case = "raise": " (the failed raise was recorded and saved nothing)", 1: ""))
		Do $$$AssertEquals(..Count(host.Sent), sent + 1, case_": one Notification is sent")
		Set note = host.Sent.%Get(host.Sent.%Size() - 1)
		Do $$$AssertEquals(note.sessionRef_"|"_note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.slots, owner_"|result|result.partnerNotDrafted||"_incident_"|{}", case_": a result with the key result.partnerNotDrafted, no ApprovalRef and no slots")
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(stored.State_"|"_stored.RequestRefs, "resolved|", case_": the incident is as it was")
	}
	Set closed = ..Incident(owner, "closed")
	Set host.FailRaise = 0
	Set host.DryAnswer = ..RealAnswer(closed, "A notice.")
	Set sent = ..Count(host.Sent)
	Set raised = ..Count(host.Raised)
	Do $$$AssertStatusOK(host.EndDraft(..Draft(closed, owner), ..Reply("A notice.")), "the end of a draft whose incident was closed while it ran is handled")
	Do $$$AssertEquals((..Count(host.Raised) - raised)_"|"_(..Count(host.Sent) - sent), "0|0", "it raises nothing and tells nobody: a closed incident is left alone")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("result.partnerNotDrafted", {}, "phone", .sc), "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again.", "the notice renders as ruled")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("result.partnerNotDrafted", {}, "web", .sc), "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again.", "for the web chat too")
}

/// Decide's answer and error of a draft reach the draft's end through the completion key, as the framework calls them.
Method TestDraftCompletionRouting()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("route")
	Set incident = ..Incident(owner, "resolved")
	Set host.DryAnswer = ..RealAnswer(incident, "A notice.")
	Set key = host.#DRAFTKEY
	Set sent = ..Count(host.Sent)
	Do $$$AssertStatusOK(host.DraftRefused(..Draft(incident, owner), $SYSTEM.Status.Error(5001, "Decide refused the request")), "the error of the draft's key is handled")
	Do $$$AssertEquals(..Count(host.Raised), 0, "an error of the draft's key raises nothing")
	Do $$$AssertEquals(..Count(host.Sent), sent + 1, "and tells the session once")
	If ..Count(host.Sent) = sent + 1 Do $$$AssertEquals(host.Sent.%Get(host.Sent.%Size() - 1).catalogKey, "result.partnerNotDrafted", "with result.partnerNotDrafted")
	Set sent = ..Count(host.Sent)
	Set fallback = ..Reply("A notice.")
	Set fallback.Fallback = 1
	Set fallback.FallbackReason = "timeout"
	Do $$$AssertStatusOK(host.DraftAnswered(..Draft(incident, owner), fallback), "a fallback answer of the draft's key is handled")
	Do $$$AssertEquals(..Count(host.Raised)_"|"_..Count(host.Sent), "0|"_(sent + 1), "it raises nothing and tells the session once")
	Set error = $SYSTEM.Status.Error(5001, "Decide refused the request")
	Do $$$AssertEquals(host.DraftRefused(..Draft(incident, owner), error, "other"), error, "an error under another key stays an error")
	Do $$$AssertStatusOK(host.DraftAnswered(..Draft(incident, owner), ..Reply("A notice."), "other"), "an answer under another key is handled")
	Do $$$AssertEquals(..Count(host.Raised)_"|"_..Count(host.Sent), "0|"_(sent + 1), "and does nothing")
	Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(host.DraftAnswered(..Draft(incident, owner), ..Reply("A notice."), key), "a usable answer of the draft's key is handled")
	Do $$$AssertEquals(..Count(host.Raised), 1, "it raises the request")
}

/// The events of a partner request never move the incident.
Method TestStateNeverMoves()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("moves")
	For variant = "resolved", "open" {
		For event = "approved", "rejected", "expired", "result" {
			Set incident = ..Incident(owner, variant, $Select(variant = "open": {"OpenVariant": "rejected"}, 1: {}))
			Set ref = ..Row(owner, incident, $Select(event = "result": "done", 1: event), "A notice.")
			Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
			Set stored.RequestRefs = ref
			Do $$$AssertStatusOK(stored.%Save(), variant_" "_event_": the incident lists the request")
			Kill stored
			Set label = variant_" "_event
			Set sent = ..Count(host.Sent)
			Set executed = ..Count(host.Executed)
			If event = "result" {
				Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
				Set result.ApprovalRef = ref
				Set result.IncidentRef = incident
				Set result.Final = 1
				Set result.Total = 1
				Set result.Completed = 1
				Set result.Reason = ""
				Do $$$AssertStatusOK(host.OnRequest(result, .answer), label_": the result is handled")
			} Else {
				Set outcome = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
				Set outcome.ApprovalRef = ref
				Set outcome.IncidentRef = incident
				Set outcome.Outcome = event
				Do $$$AssertStatusOK(host.OnRequest(outcome, .answer), label_": the outcome is handled")
			}
			Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
			Do $$$AssertEquals(stored.State_"|"_stored.OpenVariant, variant_"|"_$Select(variant = "open": "rejected", 1: ""), label_": the state and the open variant are as they were")
			Do $$$AssertEquals(..Count(host.Sent), sent + 1, label_": the session is told once")
			Set note = host.Sent.%Get(host.Sent.%Size() - 1)
			Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef, $Select(event = "result": "result|result.partnerSent", 1: "answered|answered."_event)_"|"_ref, label_": with the notice of the event")
			Do $$$AssertEquals(..Count(host.Executed), executed + $Select(event = "approved": 1, 1: 0), label_": "_$Select(event = "approved": "the Execute goes out at once", 1: "no Execute goes out"))
			If event = "approved" Do $$$AssertEquals(host.Executed.%Get(host.Executed.%Size() - 1).approvalRef, ref, label_": for the request")
		}
	}
	// a closed incident stays closed and nothing is carried out: an approved request is told as not sent, with the kind's NOSTART as the reason
	Set closed = ..Incident(owner, "closed")
	Set ref = ..Row(owner, closed, "approved", "A notice.")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(closed)
	Set stored.RequestRefs = ref
	Do $$$AssertStatusOK(stored.%Save(), "a closed incident that lists a request")
	Kill stored
	Set sent = ..Count(host.Sent)
	Set executed = ..Count(host.Executed)
	Set outcome = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%New()
	Set outcome.ApprovalRef = ref
	Set outcome.IncidentRef = closed
	Set outcome.Outcome = "approved"
	Do $$$AssertStatusOK(host.OnRequest(outcome, .answer), "the outcome is handled")
	Do $$$AssertEquals(..Count(host.Sent)_"|"_(..Count(host.Executed) - executed), (sent + 1)_"|0", "on a closed incident an approval is told once and sends no Execute")
	Set note = host.Sent.%Get(host.Sent.%Size() - 1)
	Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef, "result|result.partnerNotSent|"_ref, "it is told as a result that did not send, for the request")
	Do $$$AssertEquals({}.%FromJSON(note.slots).reason, ##class(OcuTalon.Fix.Kind.PartnerWarning).#NOSTART, "with the kind's NOSTART as the reason")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(closed)
	Do $$$AssertEquals(stored.State_"|"_stored.OpenVariant, "closed|", "the incident stays closed")
	Kill stored
	// the final result of a run that ended after the close is told as it came (the executor has closed the request by then), and the other events are refused
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set row.State = "failed"
	Do $$$AssertStatusOK(row.%Save(), "the run that could not start has closed the request failed")
	Kill row
	Set sent = ..Count(host.Sent)
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = ref
	Set result.IncidentRef = closed
	Set result.Final = 1
	Set result.Total = 1
	Set result.Reason = ##class(OcuTalon.Fix.Executor).#UNUSABLE
	Do $$$AssertStatusOK(host.OnRequest(result, .answer), "the result is handled")
	Do $$$AssertEquals(..Count(host.Sent), sent + 1, "a final result after the close is told once")
	Set note = host.Sent.%Get(host.Sent.%Size() - 1)
	Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.partnerNotSent|"_ref, "as result.partnerNotSent")
	Do $$$AssertEquals({}.%FromJSON(note.slots).reason, ##class(OcuTalon.Fix.Executor).#UNUSABLE, "with the reason it came with")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set row.State = "done"
	Do $$$AssertStatusOK(row.%Save(), "the run that sent has closed the request done")
	Kill row
	Set sent = ..Count(host.Sent)
	Set result.Reason = ""
	Set result.Completed = 1
	Do $$$AssertStatusOK(host.OnRequest(result, .answer), "a sent result is handled")
	Set note = host.Sent.%Get(host.Sent.%Size() - 1)
	Do $$$AssertEquals(..Count(host.Sent)_"|"_note.catalogKey, (sent + 1)_"|result.partnerSent", "a final result that sent after the close is told as it came")
	Set sent = ..Count(host.Sent)
	Set result.Final = 0
	Do $$$AssertStatusOK(host.OnRequest(result, .answer), "a progress result is handled")
	Do $$$AssertEquals(..Count(host.Sent), sent, "a result still in progress after the close tells nobody")
	For event = "rejected", "expired" {
		Set other = ..Row(owner, closed, event, "A notice.")
		Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(closed)
		Set stored.RequestRefs = stored.RequestRefs_","_other
		Do $$$AssertStatusOK(stored.%Save(), event_": the closed incident lists another request")
		Kill stored
		Set outcome.ApprovalRef = other
		Set outcome.Outcome = event
		Do $$$AssertStatusOK(host.OnRequest(outcome, .answer), event_": the outcome is handled")
	}
	Do $$$AssertEquals(..Count(host.Sent)_"|"_(..Count(host.Executed) - executed), sent_"|0", "a rejection and an expiry after the close tell nobody and send no Execute")
	// the table's facts
	Set incident = ..Incident(owner, "resolved")
	Set partner = ..Row(owner, incident, "pending", "A notice.")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set stored.RequestRefs = partner
	Do $$$AssertStatusOK(stored.%Save(), "an incident with a pending partner request")
	Set facts = host.FactsNow(stored, "raised")
	Do $$$AssertEquals(facts.pending_"|"_facts.waiting, "0|0", "the request is not counted in the table's facts")
	Set repair = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "pending", , {"FixKind": "repair_resend", "FixParameters": "{}", "FixTargets": "5", "ResultTarget": "IncidentManager"})
	Set ..Refs = ..Refs_","_repair
	Set stored.RequestRefs = partner_","_repair
	Do $$$AssertStatusOK(stored.%Save(), "and a pending repair too")
	Set facts = host.FactsNow(stored, "raised")
	Do $$$AssertEquals(facts.pending, 1, "the repair request is counted")
}

Method TestNoticeKeys()
{
	Set notice = "OcuTalon.Watch.Notice"
	Set incident = ##class(OcuTalon.Data.Incident).%New()
	Set incident.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals($ClassMethod(notice, "AskedKey", "partner_warning")_"|"_$ClassMethod(notice, "AskedKey", "repair_resend"), "incident.partnerRequest|", "the kind has its approval key")
	Set dry = {"notice": "A notice.", "recipients": [{"name": "A", "address": "a@x.example"}, {"name": "B", "address": "b@x.example"}], "simulated": 1}
	Set slots = $ClassMethod(notice, "AskedSlots", "partner_warning", dry, incident, .sc)
	Do $$$AssertStatusOK(sc, "the slots are built")
	Do $$$AssertEquals(slots.%ToJSON(), "{""recipients"":""A <a@x.example>, B <b@x.example>"",""notice"":""A notice.""}", "every recipient, in order, and the notice")
	For missing = "notice", "recipients" {
		Set copy = {}.%FromJSON(dry.%ToJSON())
		Do copy.%Remove(missing)
		Do $ClassMethod(notice, "AskedSlots", "partner_warning", copy, incident, .sc)
		Do $$$AssertStatusNotOK(sc, "a dry run without "_missing_" gives no slots")
	}
	Do $ClassMethod(notice, "AskedSlots", "partner_warning", {"notice": "A.", "recipients": []}, incident, .sc)
	Do $$$AssertStatusNotOK(sc, "and one with no recipient gives none")
}

/// Story 23.11 (AC3, AC6): the draft's request holds the Outcome line that the records give, and the instruction with the noun filled in.
Method TestDraftRequestCarriesOutcome()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("outcome")
	Set incident = ..Incident(owner, "resolved")
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "done", , {"FixKind": "reroute", "FixParameters": ({"target": "OrdersForReview"}.%ToJSON()), "FixTargets": "1,2,3"})
	Set ..Refs = ..Refs_","_request
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, request, {"Total": 3, "Resent": 3, "Completed": 3, "FailedAgain": 0, "Skipped": 0, "Interrupted": 0})
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = request
	$$$ThrowOnError(row.%Save())
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(incident, owner)), "the draft is handled")
	Do $$$AssertEquals(..Count(host.DraftRequests), 1, "one request goes to Decide")
	If ..Count(host.DraftRequests) '= 1 Quit
	Set sent = host.DraftRequests.%Get(0)
	Do $$$AssertTrue($Find(sent.input, "Outcome: the 3 affected orders were resent by another route.") > 0, "its input holds the Outcome line of the incident's Count")
	Do $$$AssertEquals($Find(sent.input, "OrdersForReview"), 0, "and no target name")
	Do $$$AssertEquals(sent.systemNote, ##class(OcuTalon.Fix.Kind.PartnerWarning).SystemNote(row), "its instruction is the rendered one")
	Do $$$AssertEquals($Find(sent.systemNote, "{noun}"), 0, "with no {noun} token left")
	Do $$$AssertTrue($Find(sent.systemNote, "If there is no Outcome fact, don't say whether the orders went through.") > 0, "and the noun in the ruled sentence")
	Set bare = ..Incident(owner, "resolved")
	Do $$$AssertStatusOK(host.BeginDraft(..Draft(bare, owner)), "a draft for a resolved incident with no run is handled")
	Do $$$AssertEquals(..Count(host.DraftRequests), 2, "and sends its request")
	If ..Count(host.DraftRequests) '= 2 Quit
	Do $$$AssertEquals($Find(host.DraftRequests.%Get(1).input, "Outcome:"), 0, "whose input holds no Outcome line")
}

/// --- helpers ---
Method DemoMode(on As %Boolean)
{
	Do ##class(OcuTalon.Test.Demo.Step).Put(+on, ##class(OcuTalon.Data.Time).NowUtc())
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
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzdraft"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

ClassMethod T(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
}

/// A fixture incident of the owner in the state (noticed unless fields say otherwise) on the Orders production, with a failure group of 3 orders at OrdersFromPartner; its Ref.
Method Incident(owner As %String, state As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"State": (state), "OpenVariant": "", "FirstAt": (..T(-7200)), "LastAt": (..T(-3600)), "Count": 3, "NoticeCount": 3, "ItemNoun": (..#NOUN), "Cause": "The partner changed the date format."}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set noticed = $Select(all.%IsDefined("NoticedAt"): all.NoticedAt, 1: ..T(-6600))
	Do all.%Remove("NoticedAt")
	Set production = $Select(all.%IsDefined("Production"): all.Production, 1: ..#PRODUCTION)
	Do all.%Remove("Production")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticed, "ZZNS", production, all)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_","_ref
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = ref
	Set group.Seq = 1
	Set group.ItemName = "OrdersFromPartner"
	Set group.ErrorPattern = "The order date was not in the expected format"
	Set group.ErrorSummary = "The order date was not in the expected format"
	Set group.Seen = "h1,h2,h3"
	Set group.Count = 3
	Set group.NoticeCount = 3
	Set group.FirstAt = ..T(-7200)
	Set group.LastAt = ..T(-3600)
	$$$ThrowOnError(group.%Save())
	Quit ref
}

/// The row of a partner_warning request of the incident in the state, with the text, as Approval.Raise would have made it; its Ref.
Method Row(owner As %String, incident As %String, state As %String, text As %String) As %String
{
	Set all = {"FixKind": "partner_warning", "FixTargets": "1", "ResultTarget": "IncidentManager"}
	Do all.%Set("FixParameters", {"text": (text), "to": (..#ADDRESS)}.%ToJSON())
	Do all.%Set("DryRun", {"notice": (text), "recipients": [{"name": "Orders Partner IT", "address": (..#ADDRESS)}], "simulated": 1}.%ToJSON())
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , all)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// The answer of FixExecutor to the dry run of the notice: the real kind's own dry run for the incident.
Method RealAnswer(incident As %String, text As %String) As OcuTalon.Fix.Msg.DryRunResult
{
	Set answer = ##class(OcuTalon.Fix.Msg.DryRunResult).%New()
	Set sc = ##class(OcuTalon.Fix.Kind.PartnerWarning).DryRun(##class(OcuTalon.Data.Incident).RefIndexOpen(incident), {"text": (text), "to": (..#ADDRESS)}, .targets, .dry)
	If $$$ISERR(sc) {
		Set answer.Reason = $SYSTEM.Status.GetErrorText(sc)
		Quit answer
	}
	Set answer.Targets = targets
	Set answer.DryRun = dry.%ToJSON()
	Quit answer
}

/// A Reply of Decide with the text.
ClassMethod Reply(text As %String) As OcuTalon.Bridge.Msg.Reply
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Quit reply
}

/// A Draft request for the incident and the session.
ClassMethod Draft(incident As %String, session As %String) As OcuTalon.Watch.Msg.Draft
{
	Set draft = ##class(OcuTalon.Watch.Msg.Draft).%New()
	Set draft.IncidentRef = incident
	Set draft.SessionRef = session
	Set draft.FixKind = "partner_warning"
	Quit draft
}

/// A ProposeFix of partner_warning for the incident from the session.
Method Command(session As %String, incident As %String, parameters As %DynamicObject) As OcuTalon.Msg.Command.ProposeFix
{
	Set command = ##class(OcuTalon.Msg.Command.ProposeFix).%New()
	Set command.SessionRef = session
	Set command.IncidentRef = incident
	Set command.FixKind = "partner_warning"
	Set command.Parameters = parameters.%ToJSON()
	Set command.Origin = "tool"
	Quit command
}

/// The CommandResult of a ProposeFix handled by the probe.
Method Ask(host As OcuTalon.Test.Watch.IncidentProbe, session As %String, incident As %String, parameters As %DynamicObject) As OcuTalon.Msg.CommandResult
{
	Set response = ""
	Do $$$AssertStatusOK(host.OnRequest(..Command(session, incident, parameters), .response), "the ask is handled")
	Quit response
}

/// The number of entries of a probe's list; 0 for a list that was never made.
ClassMethod Count(list As %DynamicArray) As %Integer
{
	Quit $Select($IsObject(list): list.%Size(), 1: 0)
}

/// The number of info lines of the late draft since the test began.
Method Info() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGDRAFTED"))
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
