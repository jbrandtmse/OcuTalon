/// Tests of the GotIt branch of OcuTalon.Core.SessionOps and of the Handled step of End (Story 12.12; AD-4, AD-14), over a shadow instance of
/// Test.Core.GotItProbe, which captures the Notifications instead of sending them. Safe on a slot: no production is needed. The sessions and
/// the Decisions are fixture rows; every test removes its sessions, Decisions and Handled rows by Ref in OnAfterOneTest.
///   - TestPressMarksHandled: one Handled row {Ref, SessionRef, telegram, now} and one handled Notice with the Decision's Ref; Ok 1, handled;
///   - TestSecondPressNoOp: a second press, from telegram and from web, is already_handled and changes nothing, with no second Notice;
///   - TestOtherSessionRefused: another session's tell-now Ref, unhandled and handled, is not_found and changes nothing;
///   - TestNotTellNowRefused: an act and an ignore Decision are not_found;
///   - TestNotARefRefused: "", a text that is no reference and a reference that names nothing are not_found;
///   - TestExactRefRequired: the session's own tell-now Ref in another letter case is not_found, because a Ref is compared exactly;
///   - TestBadChannelRefused: a Channel that is no CHANNEL value is not_found;
///   - TestNoticeFailureStands: a failed notice send leaves the row, with one warning, and answers handled;
///   - TestSaveFailure: a save that fails with the notice still unmarked is failed (Ok 0), with one warning, no row and no Notice; a save that fails because
///     another press won the Ref is already_handled (Ok 1), with one row and no Notice;
///   - TestEndDeletesHandled: End deletes the ended session's rows and keeps another session's;
///   - TestEndHandledFailureCounts: a failed or thrown delete is answered failed, the resume hash is kept, and a later End finishes.
/// Every refusal asserts that no row and no Notice was made.
Class OcuTalon.Test.Core.GotIt Extends %UnitTest.TestCase
{

/// The probe, a subclass of the operation.
Parameter PROBE = "OcuTalon.Test.Core.GotItProbe";

/// The run's number.
Property Number As %Integer;

/// The count of sessions made, for their IRIS users.
Property Sessions As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture sessions and Decisions of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs whose Handled rows the test may have made, comma-separated.
Property HandledRefs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("GotIt", "n"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("GotItProbe")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = "", ..HandledRefs = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..HandledRefs, ",") {
		Set ref = $Piece(..HandledRefs, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Handled).%DeleteId(row.%Id())
		}
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

/// A press of a tell-now notice of the session: one Handled row {the Decision's Ref, the session, now, telegram} and one Notification of kind
/// handled for the session with the Decision's Ref, and the answer is Ok 1, handled.
Method TestPressMarksHandled()
{
	Set probe = ..Probe()
	Set session = ..Session("press")
	Set ref = ..Decision(session, "tellnow")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set result = ..Press(probe, session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "Ok 1, handled")
	Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "the Handled row exists")
	Do $$$AssertEquals(row.SessionRef_"|"_row.Channel, session_"|telegram", "it holds the session and the channel")
	Do $$$AssertTrue($Match(row.HandledAt, "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"), "HandledAt is a UTC time to the second: "_row.HandledAt)
	Do $$$AssertTrue((before '] row.HandledAt) && (row.HandledAt '] ##class(OcuTalon.Data.Time).AddSeconds(before, 5)), "and it is within 5 s of now")
	Do $$$AssertEquals(..Rows(), 1, "and it is the only row of the test")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "one Notification is sent")
	Set notice = probe.Notices.GetAt(1)
	Do $$$AssertEquals(notice.Kind_"|"_notice.DecisionRef_"|"_notice.SessionRef, "handled|"_ref_"|"_session, "of kind handled, with the Decision's Ref and the session")
	Do $$$AssertEquals(notice.CatalogKey_"|"_notice.Slots, "|{}", "and no text")
}

/// A second press is already_handled from telegram or from web: the first row's time and channel stay, and no second Notification is sent.
Method TestSecondPressNoOp()
{
	Set probe = ..Probe()
	Set session = ..Session("second")
	Set ref = ..Decision(session, "tellnow")
	Set result = ..Press(probe, session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "the first press is handled")
	Set first = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref).HandledAt
	For channel = "telegram", "web" {
		Set result = ..Press(probe, session, ref, channel)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_handled", channel_": Ok 1, already_handled")
		Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
		Do $$$AssertEquals(row.HandledAt_"|"_row.Channel, first_"|telegram", channel_": the first row is unchanged")
		Do $$$AssertEquals(..Rows(), 1, channel_": still one row")
		Do $$$AssertEquals(probe.Notices.Count(), 1, channel_": still one Notification")
	}
}

/// Another session's tell-now Ref is not_found whether it is unhandled or handled by that session, and nothing changes.
Method TestOtherSessionRefused()
{
	Set probe = ..Probe()
	Set sessionA = ..Session("ownera")
	Set sessionB = ..Session("ownerb")
	Set ref = ..Decision(sessionB, "tellnow")
	Set result = ..Press(probe, sessionA, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "unhandled: Ok 0, not_found")
	Do ..AssertNothingMade(probe, "unhandled")
	Set result = ..Press(probe, sessionB, ref, "web")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "the owner's press is handled")
	Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
	Set at = row.HandledAt
	Set result = ..Press(probe, sessionA, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", "handled by B: Ok 0, not_found")
	Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Channel_"|"_row.HandledAt, sessionB_"|web|"_at, "B's row is unchanged")
	Do $$$AssertEquals(..Rows(), 1, "and it is the only row")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "and only B's press sent a Notification")
}

/// A Decision of the session whose Outcome is act or ignore is not_found.
Method TestNotTellNowRefused()
{
	Set probe = ..Probe()
	Set session = ..Session("nottellnow")
	For outcome = "act", "ignore" {
		Set ref = ..Decision(session, outcome)
		Set result = ..Press(probe, session, ref, "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", outcome_": Ok 0, not_found")
		Do ..AssertNothingMade(probe, outcome)
	}
}

/// A Ref that is empty, is no reference, or names no Decision is not_found.
Method TestNotARefRefused()
{
	Set probe = ..Probe()
	Set session = ..Session("notaref")
	For ref = "", "notaref", ##class(OcuTalon.Bridge.Ids).NewRef() {
		If ref '= "" Set ..HandledRefs = ..HandledRefs_$Select(..HandledRefs = "": "", 1: ",")_ref
		Set result = ..Press(probe, session, ref, "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", """"_ref_""": Ok 0, not_found")
		Do ..AssertNothingMade(probe, """"_ref_"""")
	}
}

/// The session's own tell-now Ref in another letter case is not_found, with no row for either spelling: a Ref is compared exactly.
Method TestExactRefRequired()
{
	Set probe = ..Probe()
	Set session = ..Session("exactref")
	Set ref = ..Decision(session, "tellnow")
	Set variants = 0
	For variant = $ZConvert(ref, "L"), $ZConvert(ref, "U") {
		If variant = ref Continue
		Set variants = variants + 1
		Set ..HandledRefs = ..HandledRefs_","_variant
		Set result = ..Press(probe, session, variant, "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", variant_": Ok 0, not_found")
		Do ..AssertNothingMade(probe, variant)
	}
	Do $$$AssertTrue(variants > 0, "the Ref has a letter, so a spelling in another case was pressed")
}

/// A Channel that is no Msg.Enum CHANNEL value is not_found, even for the session's own tell-now Ref.
Method TestBadChannelRefused()
{
	Set probe = ..Probe()
	Set session = ..Session("badchannel")
	Set ref = ..Decision(session, "tellnow")
	For channel = "zz", "" {
		Set result = ..Press(probe, session, ref, channel)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_found", """"_channel_""": Ok 0, not_found")
		Do ..AssertNothingMade(probe, """"_channel_"""")
	}
}

/// A Notification that can't be sent is a warning: the row stands and the answer is Ok 1, handled.
Method TestNoticeFailureStands()
{
	Set probe = ..Probe()
	Set probe.NoticeAnswer = "error"
	Set session = ..Session("noticefails")
	Set ref = ..Decision(session, "tellnow")
	Set warnings = ..Logged("the handled notice of session "_session)
	Set result = ..Press(probe, session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "Ok 1, handled")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(ref), 1, "the row stands")
	Do $$$AssertEquals(..Logged("the handled notice of session "_session), warnings + 1, "with one warning naming the session")
}

/// A save that fails with the notice still unmarked is failed: no row, no Notification and one warning. A save that fails because the Ref was
/// marked meanwhile is already_handled: one row and no Notification.
Method TestSaveFailure()
{
	Set probe = ..Probe()
	Set session = ..Session("savefails")
	Set ref = ..Decision(session, "tellnow")
	Set probe.FailSave = "error"
	Set warnings = ..Logged("the notice could not be marked as handled")
	Set result = ..Press(probe, session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an unsaved row: Ok 0, failed")
	Do ..AssertNothingMade(probe, "unsaved")
	Do $$$AssertEquals(..Logged("the notice could not be marked as handled"), warnings + 1, "with one warning")
	Set probe.FailSave = "raced"
	Set result = ..Press(probe, session, ref, "telegram")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|already_handled", "a lost race: Ok 1, already_handled")
	Do $$$AssertEquals(..Rows(), 1, "with the winner's row")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "and no Notification")
}

/// End deletes the ended session's Handled rows and keeps another session's.
Method TestEndDeletesHandled()
{
	Set probe = ..Probe()
	Set sessionA = ..Session("endA")
	Set sessionB = ..Session("endB")
	Set refA1 = ..Decision(sessionA, "tellnow"), refA2 = ..Decision(sessionA, "tellnow"), refB = ..Decision(sessionB, "tellnow")
	For pair = $ListBuild(sessionA, refA1), $ListBuild(sessionA, refA2), $ListBuild(sessionB, refB) {
		Set result = ..Press(probe, $List(pair, 1), $List(pair, 2), "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", "a press is handled")
	}
	Set result = ..End(probe, sessionA)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(refA1) + ##class(OcuTalon.Data.Handled).RefIndexExists(refA2), 0, "A's rows are gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(refB), 1, "B's row stays")
}

/// A Handled delete that fails (an error status, or an error thrown) is answered failed after the step was tried and the other steps ran; the
/// resume hash is kept and the row stays; a later End, when the delete works, answers ended and deletes the row.
Method TestEndHandledFailureCounts()
{
	For mode = "error", "throw" {
		Set probe = ..Probe()
		Set probe.FailHandled = mode
		Set session = ..Session("endfail"_mode)
		Set ref = ..Decision(session, "tellnow")
		Do ..SetResumeHash(session, "zzgotit"_..Number_mode)
		Set result = ..Press(probe, session, ref, "telegram")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|handled", mode_": a press is handled")
		Set calls = +$Get(^OcuTalonTest("GotItProbe"))
		Set result = ..End(probe, session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", mode_": Ok 0, failed")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("GotItProbe")), calls + 1, mode_": the step was tried")
		Do $$$AssertEquals($Get(^OcuTalonTest("GotItProbe", calls + 1)), session, mode_": for the session")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash("zzgotit"_..Number_mode), mode_": the resume hash is kept")
		Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(ref), 1, mode_": the row stays")
		Set probe.FailHandled = ""
		Set result = ..End(probe, session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", mode_": a later End answers ended")
		Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(ref), 0, mode_": and the row is gone")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, "", mode_": and the hash is cleared")
	}
}

/// --- helpers ---
/// A shadow instance of the probe.
Method Probe() As OcuTalon.Test.Core.GotItProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// A fixture session, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Sessions = ..Sessions + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzgotit"_..Number_name_..Sessions)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A decide Decision of the owner with the outcome, recorded for the clean-up (and its Handled row, if any). Returns its Ref.
Method Decision(owner As %String, outcome As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Outcome": (outcome)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..HandledRefs = ..HandledRefs_$Select(..HandledRefs = "": "", 1: ",")_ref
	Quit ref
}

/// Sends a GotIt to the probe and returns its CommandResult.
Method Press(probe As OcuTalon.Test.Core.GotItProbe, session As %String, ref As %String, channel As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.GotIt).%New()
	Set command.Origin = $Select(channel = "telegram": "telegram", 1: "web_user")
	Set command.SessionRef = session
	Set command.Ref = ref
	Set command.Channel = channel
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// Sends an EndSession to the probe and returns its CommandResult.
Method End(probe As OcuTalon.Test.Core.GotItProbe, session As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()
	Set command.Origin = "web_user"
	Set command.SessionRef = session
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The number of Handled rows of the test's Decisions.
Method Rows() As %Integer [ Private ]
{
	Set count = 0
	For i = 1:1:$Length(..HandledRefs, ",") {
		Set ref = $Piece(..HandledRefs, ",", i)
		If ref '= "" Set count = count + ##class(OcuTalon.Data.Handled).RefIndexExists(ref)
	}
	Quit count
}

/// Asserts that the test made no Handled row and the probe captured no Notification.
Method AssertNothingMade(probe As OcuTalon.Test.Core.GotItProbe, label As %String) [ Private ]
{
	Do $$$AssertEquals(..Rows(), 0, label_": no Handled row")
	Do $$$AssertEquals(probe.Notices.Count(), 0, label_": no Notification")
}

/// Gives the fixture session a resume hash, the hash of the text.
Method SetResumeHash(session As %String, text As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash(text)
	Do $$$AssertStatusOK(row.%Save(), "the fixture session holds a resume hash")
}

/// The number of Event Log warnings whose text contains the text.
Method Logged(text As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
