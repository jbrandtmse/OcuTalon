/// QA pins for Story 24.4a that its own tests leave open (the redaction of a setting's values and the hand-off of the dry run's raw values; AD-16, AD-19, AD-31). It runs warm, on the
/// probe host of Test.Fix.Asked (the shadow IncidentManager whose RaiseRequest, SendNotice and SendDryRun record instead of sending) over fixture rows of its own, and needs no production:
///   - TestTakenBeforeAnEarlyExit (the matrix row "Hand-off taken", V6: "takes the entry as soon as an answer arrives, before any early exit"): a first-round answer for an incident that moved
///     on, a Reason and an empty Targets, a later round's answer for an incident with no ask on its way, for a closed one, a Reason and an empty Targets, and the chat ask's Reason and empty
///     Targets each end the entry, and raise and send nothing;
///   - TestLaterRoundMissingEntry (V6's added condition on Proposed's later round): an answer whose entry is gone raises no request, sends nothing, clears AskingSince, stores no marker and
///     logs one LOGLATER warning that names the kind's NOSTART; an answer whose entry is there stores the raw values, ends the entry and sends redacted slots;
///   - TestSummaryHoldsNoValue (the summary line and the digest paths, AC2): the summary of an incident whose rollback and undo of a token value ran holds no value, redacted or not, in
///     its parts, its slots or its rendered text, and still names the setting and the item (the digest, Digest.NeedsYou, reads only the incident's and the requests' names and times).
/// The fixtures build every token from fragments; each hand-off entry that a test offers is taken or discarded, and the rows and the warnings are removed after each test.
Class OcuTalon.Test.Watch.SettingValues Extends %UnitTest.TestCase
{

/// The Refs of the fixture SettingChange rows of the test being run, comma-separated.
Property Changes As %String(MAXLEN = "") [ Transient ];

/// The references of the hand-off entries that the test offered, as a list.
Property Uris As %List [ Transient ];

/// The helper that makes the fixture incidents and the probe host (a Test.Fix.Asked, not run as a test).
Property Asked As OcuTalon.Test.Fix.Asked [ Transient ];

/// A helper of Test.Fix.Asked for the test.
Method Begin(name As %String) As OcuTalon.Test.Fix.Asked [ Private ]
{
	Set ..Changes = ""
	Set ..Uris = ""
	Set asked = ##class(OcuTalon.Test.Fix.Asked).%New(..Manager)
	Do asked.OnBeforeAllTests()
	Do asked.OnBeforeOneTest(name)
	Set ..Asked = asked
	Quit asked
}

/// Discards the entries that are left, removes the SettingChange rows, the warnings and the fixture rows.
Method End(name As %String) [ Private ]
{
	For i = 1:1:$ListLength(..Uris) Do ##class(OcuTalon.Core.SecretHandoff).Discard($List(..Uris, i))
	For i = 1:1:$Length(..Changes, ",") {
		Set row = $Select($Piece(..Changes, ",", i) = "": "", 1: ##class(OcuTalon.Data.SettingChange).RefIndexOpen($Piece(..Changes, ",", i)))
		If $IsObject(row) Do ##class(OcuTalon.Data.SettingChange).%DeleteId(row.%Id())
	}
	Set mark = ..Asked.LogMark
	For start = ##class(OcuTalon.Watch.IncidentManager).#LOGPROPOSE, ##class(OcuTalon.Watch.IncidentManager).#LOGLATER, ##class(OcuTalon.Watch.IncidentManager).#LOGNOTICE {
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Proposed", start)
	}
	Do ..Asked.OnAfterOneTest(name)
	Set ..Asked = ""
	Set ..Changes = ""
	Set ..Uris = ""
}

/// A dry run of the rollback of a token URL on the item, as FixExecutor's setting kinds give it before the hand-off.
ClassMethod Dry() As %DynamicObject
{
	Quit {"item": "OrdersFromPartner", "field": "TargetConfigName", "before": (##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()), "after": "OrdersToWarehouse"}
}

/// Offers the values of the dry run (the object gets redacted values and the reference) with a lifetime of 4 seconds (each offer starts a detached job that lives that long, so the tests
/// keep them short), and remembers the reference so that End discards what is left.
Method Offer(dry As %DynamicObject) As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Fix.Executor).OfferValues(dry, 4), "the values are offered")
	Set ..Uris = ..Uris_$ListBuild(dry.values)
	Quit dry.values
}

/// 1 when the entry that the reference names still exists.
ClassMethod Held(uri As %String) As %Boolean
{
	Quit ##class(OcuTalon.Test.Watch.SettingCause).Held(uri)
}

/// The number of elements of a dynamic array that a probe recorded ("" when it recorded none).
ClassMethod Size(recorded As %DynamicArray) As %Integer
{
	Quit $Select($IsObject(recorded): recorded.%Size(), 1: 0)
}

/// The number of Notifications of kind approval that the probe recorded after the first from elements (the notices that carry a request).
ClassMethod Approvals(recorded As %DynamicArray, from As %Integer) As %Integer
{
	Set count = 0
	For i = from:1:..Size(recorded) - 1 {
		If recorded.%Get(i).kind = "approval" Set count = count + 1
	}
	Quit count
}

/// The DryRun that was "sent" for the incident: the rollback of the change.
ClassMethod AskOf(incident As %String, change As %String) As OcuTalon.Fix.Msg.DryRun
{
	Set ask = ##class(OcuTalon.Fix.Msg.DryRun).%New()
	Set ask.IncidentRef = incident
	Set ask.FixKind = "rollback_setting"
	Set ask.Parameters = {"change": (change)}.%ToJSON()
	Quit ask
}

/// A SettingChange of the fixture production, detected before the first failure of the fixture incidents, with the token URL as its old value; its Ref (remembered for End).
Method Change(asked As OcuTalon.Test.Fix.Asked) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Watch.SettingCause).Change(asked.T(-7500), "OrdersFromPartner", "TargetConfigName", ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl(), "OrdersToWarehouse")
	Set ..Changes = ..Changes_$Select(..Changes = "": "", 1: ",")_ref
	Quit ref
}

/// The number of Type 3 warnings since the mark that start with the text and hold the other text.
ClassMethod Warned(mark As %Integer, start As %String, holds As %String) As %Integer
{
	Set count = 0
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	While rs.%Next() {
		If rs.%GetData(1) [ holds Set count = count + 1
	}
	Quit count
}

/// V6 ("takes the entry as soon as an answer arrives, before any early exit"; the matrix row "Hand-off taken"): every answer that reaches IncidentManager ends its entry, also the one
/// that the method then drops. The first round's answer for an incident that moved on, with a Reason and with no Targets; the later round's answer with no ask on its way, for a closed
/// incident, with a Reason and with no Targets; and the chat ask's Reason and empty Targets. Each leaves no entry, raises no request and sends no Notification.
Method TestTakenBeforeAnEarlyExit()
{
	Set asked = ..Begin("TestTakenBeforeAnEarlyExit")
	Try {
		Set host = asked.Host()
		If '$IsObject(host) Quit
		Set owner = asked.Owner("early")
		Set change = "zzchangeref0000000010"
		// the first round (Proposed): the answer goes to an incident that is open and unnoticed, or to one that moved on
		For case = "movedon", "reason", "targets" {
			Set incident = $Select(case = "movedon": asked.Incident(owner, "awaiting_approval"), 1: asked.Incident(owner, "open", {"NoticedAt": ""}))
			Set dry = ..Dry()
			Set uri = ..Offer(dry)
			Set result = asked.Answer($Select(case = "targets": "", 1: "5"), dry)
			If case = "reason" Set result.Reason = "The setting is not one that OcuTalon can change."
			Set raised = ..Size(host.Raised)
			Set sent = ..Size(host.Sent)
			Do $$$AssertStatusOK(host.Dried(incident, ..AskOf(incident, change), result), "first round, "_case_": the answer is handled")
			Do $$$AssertEquals(..Held(uri), 0, "first round, "_case_": the entry was taken on receipt and is gone")
			Do $$$AssertEquals(..Size(host.Raised)_"|"_..Approvals(host.Sent, sent), raised_"|0", "first round, "_case_": no request is raised and no approval notice is sent")
		}
		// a later round (Proposed with later 1): no ask on its way, a closed incident, a Reason, no Targets
		For case = "stale", "closed", "reason", "targets" {
			Set fields = $Select(case = "stale": {}, 1: {"AskingSince": (asked.T(-30))})
			Set incident = asked.Incident(owner, $Select(case = "closed": "closed", 1: "awaiting_approval"), fields)
			Set dry = ..Dry()
			Set uri = ..Offer(dry)
			Set result = asked.Answer($Select(case = "targets": "", 1: "5"), dry)
			If case = "reason" Set result.Reason = "The setting is not one that OcuTalon can change."
			Set raised = ..Size(host.Raised)
			Set sent = ..Size(host.Sent)
			Do $$$AssertStatusOK(host.LaterDried(incident, ..AskOf(incident, change), result), "later round, "_case_": the answer is handled")
			Do $$$AssertEquals(..Held(uri), 0, "later round, "_case_": the entry was taken on receipt and is gone")
			Do $$$AssertEquals(..Size(host.Raised)_"|"_..Approvals(host.Sent, sent), raised_"|0", "later round, "_case_": no request is raised and no approval notice is sent")
		}
		// the chat ask (RaiseAsked): a Reason and no Targets
		For case = "reason", "targets" {
			Set incident = asked.Incident(owner, "resolved")
			Do asked.DoneRollback(owner, incident, change)
			Set dry = ..Dry()
			Set uri = ..Offer(dry)
			Set result = asked.Answer($Select(case = "targets": "", 1: "5"), dry)
			If case = "reason" Set result.Reason = "The setting is not one that OcuTalon can change."
			Set host.DryAnswer = result
			Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set raised = ..Size(host.Raised)
			Set sent = ..Size(host.Sent)
			Set response = asked.Ask(host, owner, incident, "undo_rollback", {})
			Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|"_$Select(case = "targets": "nothing", 1: "refused"), "chat ask, "_case_": the ask ends as the answer says")
			Do $$$AssertEquals(..Held(uri), 0, "chat ask, "_case_": the entry was taken on receipt and is gone")
			Do $$$AssertEquals(..Size(host.Raised)_"|"_..Size(host.Sent), raised_"|"_sent, "chat ask, "_case_": nothing is raised and nothing is sent")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "no error")
	}
	Do ..End("TestTakenBeforeAnEarlyExit")
}

/// V6's added condition on the later round of Proposed (it has no test of its own in 24.4a's first pass): the answer to a later round's dry run of a setting kind whose entry is gone raises no
/// request, sends nothing, clears AskingSince (the no-fix route does not exist for a noticed incident), stores nothing that holds the marker and logs one LOGLATER warning that names the
/// kind's NOSTART. The same answer with its entry there stores the raw values in the request, ends the entry and sends slots that are redacted.
Method TestLaterRoundMissingEntry()
{
	Set asked = ..Begin("TestLaterRoundMissingEntry")
	Try {
		Set host = asked.Host()
		If '$IsObject(host) Quit
		Set owner = asked.Owner("later")
		Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
		Set token = ##class(OcuTalon.Test.Watch.SettingCause).Token()
		Set change = ..Change(asked)
		// the entry is gone before the take
		Set incident = asked.Incident(owner, "awaiting_approval", {"AskingSince": (asked.T(-30)), "SettingChangeRef": (change)})
		Set dry = ..Dry()
		Set uri = ..Offer(dry)
		Do ##class(OcuTalon.Core.SecretHandoff).Discard(uri)
		Set result = asked.Answer("5", dry)
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Do $$$AssertStatusOK(host.LaterDried(incident, ..AskOf(incident, change), result), "the answer of the later round is handled")
		Do $$$AssertEquals(..Size(host.Raised)_"|"_..Size(host.Sent), "0|0", "no request is raised and nothing is sent")
		Do $$$AssertEquals($Find($Select($IsObject(host.Raised): host.Raised.%ToJSON(), 1: ""), "[redacted]"), 0, "and nothing that holds the marker is stored")
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Do $$$AssertEquals(row.AskingSince_"|"_row.State, "|awaiting_approval", "AskingSince is cleared and the state stands")
		Kill row
		Set nostart = ##class(OcuTalon.Fix.Kind.RollbackSetting).#NOSTART
		Do $$$AssertEquals(..Warned(mark, ##class(OcuTalon.Watch.IncidentManager).#LOGLATER_incident, nostart), 1, "one LOGLATER warning names the kind's NOSTART")
		// the entry is there: the request stores the raw values, the entry is ended, the notice's slots are redacted
		Set incident = asked.Incident(owner, "awaiting_approval", {"AskingSince": (asked.T(-30)), "SettingChangeRef": (change)})
		Set dry = ..Dry()
		Set uri = ..Offer(dry)
		Set result = asked.Answer("5", dry)
		Set host.RaiseRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(host.LaterDried(incident, ..AskOf(incident, change), result), "the answer with its entry is handled")
		Do $$$AssertEquals(..Held(uri), 0, "the entry was taken on receipt and is gone")
		Do $$$AssertEquals(..Size(host.Raised), 1, "one request is raised")
		If ..Size(host.Raised) = 1 {
			Set stored = {}.%FromJSON(host.Raised.%Get(0).dryRun)
			Do $$$AssertEquals(stored.before_"|"_stored.%IsDefined("values"), url_"|0", "its stored dry run holds the raw value and no reference")
		}
		Do $$$AssertEquals(..Size(host.Sent), 1, "one Notification is sent")
		If ..Size(host.Sent) = 1 {
			Set note = host.Sent.%Get(0)
			Do $$$AssertTrue((note.slots [ "[redacted]") && ($Find(note.slots, token) = 0), "its slots are redacted: "_note.slots)
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "no error")
	}
	Do ..End("TestLaterRoundMissingEntry")
}

/// AC2 (the summary line and the digest paths): the summary of a closed incident that ran a rollback and an undo of a change whose old value is a token URL holds no value on any line: not the
/// token, and not the marker (the lines name the setting and the item and nothing else). The parts are those of the setting kinds, so the test is not empty.
Method TestSummaryHoldsNoValue()
{
	Set asked = ..Begin("TestSummaryHoldsNoValue")
	Try {
		Set owner = asked.Owner("summary")
		Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
		Set token = ##class(OcuTalon.Test.Watch.SettingCause).Token()
		Set change = ..Change(asked)
		Set incident = asked.Incident(owner, "resolved", {"SettingChangeRef": (change)})
		Set rollbackDry = {"item": "OrdersFromPartner", "field": "TargetConfigName", "before": "OrdersToWarehouse", "after": (url)}.%ToJSON()
		Set undoDry = {"item": "OrdersFromPartner", "field": "TargetConfigName", "before": (url), "after": "OrdersToWarehouse"}.%ToJSON()
		Set parameters = {"change": (change)}.%ToJSON()
		Set rollback = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "done", asked.T(-6000), {"FixKind": "rollback_setting", "FixParameters": (parameters), "FixTargets": "5", "DryRun": (rollbackDry), "AnsweredChannel": "web", "AnsweredAt": (asked.T(-5900))})
		Set undo = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "done", asked.T(-5000), {"FixKind": "undo_rollback", "FixParameters": (parameters), "FixTargets": "5", "DryRun": (undoDry), "AnsweredChannel": "web", "AnsweredAt": (asked.T(-4900))})
		Set asked.Refs = asked.Refs_","_rollback_","_undo
		Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
		Set row.RequestRefs = rollback_","_undo
		Do $$$AssertStatusOK(row.%Save(), "the incident lists the two requests")
		Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, rollback, {"StartedAt": (asked.T(-5800)), "EndedAt": (asked.T(-5700)), "Total": 1, "Resent": 0, "Completed": 1, "FailedAgain": 0, "Skipped": 0})
		Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, undo, {"StartedAt": (asked.T(-4800)), "EndedAt": (asked.T(-4700)), "Total": 1, "Resent": 0, "Completed": 1, "FailedAgain": 0, "Skipped": 0})
		Set summary = ##class(OcuTalon.Watch.Summary).Build(row, "dismiss", asked.T(-60), 0, .sc)
		Do $$$AssertStatusOK(sc, "the summary is built")
		If '$IsObject(summary) Quit
		Set json = summary.%ToJSON()
		For key = "summary.requestedRollback", "summary.requestedUndoRollback", "summary.settingRestored", "summary.rollbackUndone" {
			Do $$$AssertTrue($Find(json, key) > 0, "the summary has the line "_key_" (the test is not empty)")
		}
		Do $$$AssertTrue($Find(json, "TargetConfigName") > 0, "and names the setting")
		Do $$$AssertEquals($Find(json, token), 0, "no part or slot holds the token")
		Do $$$AssertEquals($Find(json, "[redacted]"), 0, "and none holds the marker: the lines carry no value at all")
		Do $$$AssertEquals($Find(json, "OrdersToWarehouse"), 0, "nor the plain value")
		Set text = ##class(OcuTalon.Channel.DigestText).Text(json, "web", .sc)
		Do $$$AssertStatusOK(sc, "the summary renders for the web chat")
		Do $$$AssertTrue(($Find(text, "TargetConfigName") > 0) && ($Find(text, token) = 0) && ($Find(text, "[redacted]") = 0), "and the rendered text names the setting and holds no value: "_text)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "no error")
	}
	Do ..End("TestSummaryHoldsNoValue")
}

}
