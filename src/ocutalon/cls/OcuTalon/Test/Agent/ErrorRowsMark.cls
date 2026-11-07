Include Ensemble

/// Pins the header mark of RunnerFixture.ErrorRows (Story 11.28, DW-688). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21):
/// TestTimerRowsAroundTheMark needs OcuTalon.Production running with every item (RunnerFixture.ReadyReason, as Test.Agent.Runners
/// does) and the real Ens.Alarm host; TestOtherRowsKept writes event-log rows of its own.
///   - TestTimerRowsAroundTheMark: two real timers whose request headers are deleted, as a test's clean-up leaves them. Timer A is planted
///     before the event mark and the header mark, timer B after them. Ens.Alarm writes the "can not be found, timer event ignored" row
///     of each after the event mark. Read with the header mark, the row of A is absent and the row of B is present; read without it,
///     both are present;
///   - TestOtherRowsKept: synthetic Ens.Alarm and other rows. With the header mark, only the Type 2 Ens.Alarm timer-ignored row
///     whose number is at or below the mark is left out: the number above the mark, another ConfigName, an empty or non-numeric number,
///     another wording and a Type 6 row are kept. Without the header mark, every row is kept.
/// The tests check membership by the header id or the label of a row, never the whole list, since an unrelated row of the production
/// can appear in the log. They wait by polling, up to ROWSECONDS, and delete what they created.
Class OcuTalon.Test.Agent.ErrorRowsMark Extends %UnitTest.TestCase
{

/// The fixture that the tests share.
Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The most a test waits for the row of a planted timer, in seconds. A timer of 3 or 8 seconds wakes within a second of its time on
/// an idle host, and the ceiling covers a loaded one.
Parameter ROWSECONDS = 90;

/// The Timeout of timer A, in seconds. It is planted, its header is deleted and the marks are taken before it wakes.
Parameter TIMERA = 8;

/// The Timeout of timer B, in seconds.
Parameter TIMERB = 3;

/// The text that Ens.Alarm writes when the request header of a timer is gone, up to the number.
Parameter TIMERTEXT = "can not be found, timer event ignored";

/// The planted timers of the running test, as a list of the header ids that the timers were planted with.
Property Planted As %List;

/// The ids of the Ens.AlarmRequest bodies that the planting created.
Property Bodies As %List;

/// The ids of the synthetic event-log rows that the running test created.
Property Synthetic As %List;

/// The event mark from before the running test planted anything: the rows that the cleanup waits for are after it.
Property Mark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Planted = ""
	Set ..Bodies = ""
	Set ..Synthetic = ""
	Set ..Mark = $ClassMethod(..#FIXTURE, "EventMark")
	Quit $$$OK
}

/// Deletes what the test created: the synthetic rows, the Ens.Alarm rows of the planted timers (a timer whose row has not appeared is
/// waited for once more, up to ROWSECONDS, so that no planted timer outlives its test), the headers that remain of the planting and
/// its AlarmRequest bodies.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Synthetic, position, id) {
		Do ##class(Ens.Util.Log).%DeleteId(id)
	}
	Set ..Synthetic = ""
	Set position = 0
	While $ListNext(..Planted, position, headerId) {
		Set id = ..WaitRow(headerId, ..Mark)
		If id '= "" Do ##class(Ens.Util.Log).%DeleteId(id)
	}
	Set ..Planted = ""
	Set position = 0
	While $ListNext(..Bodies, position, bodyId) {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE MessageBodyClassName = 'Ens.AlarmRequest' AND MessageBodyId = ?", bodyId)
		While result.%Next() {
			Do ##class(Ens.MessageHeader).%DeleteId(result.%GetData(1))
		}
		Do ##class(Ens.AlarmRequest).%DeleteId(bodyId)
	}
	Set ..Bodies = ""
	Quit $$$OK
}

/// Real timers around the marks. A control first: the row of A lands after the event mark, so that "A is left out" is not vacuous.
Method TestTimerRowsAroundTheMark()
{
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set headerA = ..Plant(..#TIMERA)
	If headerA = "" Quit
	Set eventMark = $ClassMethod(fixture, "EventMark")
	// the mark is taken while A's header still exists: HeaderMark is the highest id, and a deleted header at the top would lower it
	Set headerMark = $ClassMethod(fixture, "HeaderMark")
	Do ..Drop(headerA)
	Set headerB = ..Plant(..#TIMERB)
	If headerB = "" Quit
	Do ..Drop(headerB)
	Do $$$AssertTrue(headerA <= headerMark, "timer A's header "_headerA_" is at or below the header mark "_headerMark)
	Do $$$AssertTrue(headerB > headerMark, "timer B's header "_headerB_" is above the header mark "_headerMark)
	Set rowA = ..WaitRow(headerA, eventMark)
	Set rowB = ..WaitRow(headerB, eventMark)
	Do $$$AssertTrue(rowA > eventMark, "control: the timer-ignored row of header "_headerA_" landed after the event mark "_eventMark_" within "_..#ROWSECONDS_" seconds, so that leaving it out can be seen: '"_rowA_"'")
	Do $$$AssertTrue(rowB > eventMark, "the timer-ignored row of header "_headerB_" landed after the event mark "_eventMark_" within "_..#ROWSECONDS_" seconds: '"_rowB_"'")
	If (rowA = "") || (rowB = "") Quit
	Set marked = $ClassMethod(fixture, "ErrorRows", eventMark, headerMark)
	Do $$$AssertTrue('..HasTimerRow(marked, headerA), "with the header mark, the row of header "_headerA_" (at or below the mark) is left out")
	Do $$$AssertTrue(..HasTimerRow(marked, headerB), "with the header mark, the row of header "_headerB_" (above the mark) is kept")
	Set plain = $ClassMethod(fixture, "ErrorRows", eventMark)
	Do $$$AssertTrue(..HasTimerRow(plain, headerA), "without the header mark, the row of header "_headerA_" is kept")
	Do $$$AssertTrue(..HasTimerRow(plain, headerB), "without the header mark, the row of header "_headerB_" is kept")
}

/// Synthetic rows: only the Type 2 Ens.Alarm timer-ignored row with a number at or below the header mark is left out.
Method TestOtherRowsKept()
{
	Set fixture = ..#FIXTURE
	Set headerMark = $ClassMethod(fixture, "HeaderMark")
	Set eventMark = $ClassMethod(fixture, "EventMark")
	// label, type, ConfigName, text before the label: the first case is the one row that is left out with the header mark
	Set cases = $ListBuild(
		$ListBuild("below-mark", 2, "Ens.Alarm", ..TimerText(headerMark, "below-mark")),
		$ListBuild("above-mark", 2, "Ens.Alarm", ..TimerText(headerMark + 1, "above-mark")),
		$ListBuild("low-number", 2, "Ens.Alarm", ..TimerText($Select(headerMark < 1: 0, 1: 1), "low-number")),
		$ListBuild("other-config", 2, "Ens.AlarmOther", ..TimerText(headerMark, "other-config")),
		$ListBuild("empty-number", 2, "Ens.Alarm", ..TimerText("", "empty-number")),
		$ListBuild("letter-number", 2, "Ens.Alarm", ..TimerText("12x", "letter-number")),
		$ListBuild("other-wording", 2, "Ens.Alarm", "Message '"_headerMark_"' was not found, timer ignored. Timer ID ='other-wording'."),
		$ListBuild("alert", 6, "Ens.Alarm", ..TimerText(headerMark, "alert")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set id = ..MakeLog($List(case, 2), $List(case, 3), $List(case, 4))
		Do $$$AssertTrue(id > eventMark, "the "_$List(case, 1)_" row is written after the event mark: '"_id_"'")
		If id = "" Quit
		Set ..Synthetic = ..Synthetic _ $ListBuild(id)
	}
	Set marked = $ClassMethod(fixture, "ErrorRows", eventMark, headerMark)
	Set plain = $ClassMethod(fixture, "ErrorRows", eventMark)
	Set emptied = $ClassMethod(fixture, "ErrorRows", eventMark, "")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		// the number at or below the mark is left out with the mark, and only that one
		Set expected = $Select((label = "below-mark") || (label = "low-number"): 0, 1: 1)
		Do $$$AssertEquals(..HasLabel(marked, label), expected, "with the header mark, the "_label_" row is "_$Select(expected: "kept", 1: "left out"))
		Do $$$AssertTrue(..HasLabel(plain, label), "without the header mark, the "_label_" row is kept")
		Do $$$AssertTrue(..HasLabel(emptied, label), "with an empty header mark, the "_label_" row is kept")
	}
}

/// The text of Ens.Alarm's timer-ignored row for the number, with the label in the place of the timer id.
ClassMethod TimerText(number As %String, label As %String) As %String [ Private ]
{
	Quit "Message '"_number_"' "_..#TIMERTEXT_". Timer ID ='"_label_"'. Sent request to ScheduleHandler to check for production differences."
}

/// An event-log row in this namespace of the type (2 error, 6 alert), ConfigName and text. Its id, or "".
ClassMethod MakeLog(type As %Integer, config As %String, text As %String) As %Integer [ Private ]
{
	Set log = ##class(Ens.Util.Log).%New()
	Set log.Type = type
	Set log.ConfigName = config
	Set log.Text = text
	Set log.TimeLogged = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set sc = log.%Save()
	Quit $Select($$$ISOK(sc): log.%Id(), 1: "")
}

/// Plants a timer: an Ens.AlarmRequest of the Timeout, sent to Ens.Alarm with a call that waits one second. The id of its request
/// header, or "" (the test fails with the reason). Drop deletes the header, so that the timer wakes to a header that is gone.
Method Plant(timeout As %Integer) As %Integer [ Private ]
{
	Set request = ##class(Ens.AlarmRequest).%New()
	Set request.Timeout = timeout
	Set sc = request.%Save()
	If $$$ISERR(sc) {
		Do $$$AssertStatusOK(sc, "an AlarmRequest of "_timeout_" seconds is saved")
		Quit ""
	}
	Set ..Bodies = ..Bodies _ $ListBuild(request.%Id())
	// the call times out after a second, since the answer of Ens.Alarm comes with the timer; the header is the thing to find
	Set sc = $ClassMethod(..#FIXTURE, "Send", "Ens.Alarm", request, .response, , 1)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE TargetConfigName = 'Ens.Alarm' AND MessageBodyClassName = 'Ens.AlarmRequest' AND MessageBodyId = ? ORDER BY ID DESC", request.%Id())
	If '(result.%Next()) {
		Do $$$AssertTrue(0, "the request of the "_timeout_" second timer has a header addressed to Ens.Alarm (the send gave: "_$Select($$$ISOK(sc): "OK", 1: $SYSTEM.Status.GetErrorText(sc))_")")
		Quit ""
	}
	Set headerId = result.%GetData(1)
	Set ..Planted = ..Planted _ $ListBuild(headerId)
	// Ens.Alarm sets the header Delivered when it takes the request up, before it registers the timer, which needs only the header id
	If '..WaitTakenUp(headerId) {
		Do $$$AssertTrue(0, "Ens.Alarm took up the request of header "_headerId_" within "_..#ROWSECONDS_" seconds")
		Quit ""
	}
	Quit headerId
}

/// 1 when the request header has left the Created and Queued states, polling up to ROWSECONDS.
Method WaitTakenUp(headerId As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#ROWSECONDS
	Set taken = 0
	While 'taken {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status FROM Ens.MessageHeader WHERE ID = ?", headerId)
		If result.%Next() && (result.%GetData(1) '= "Created") && (result.%GetData(1) '= "Queued") Set taken = 1 Continue
		If $ZHorolog >= deadline Quit
		Hang 0.1
	}
	Quit taken
}

/// Deletes the request header of a planted timer, as a test's clean-up does.
Method Drop(headerId As %Integer) [ Private ]
{
	Do $$$AssertStatusOK(##class(Ens.MessageHeader).%DeleteId(headerId), "the header "_headerId_" of a planted timer is deleted")
}

/// The id of the event-log row that Ens.Alarm wrote for the header (Type 2, id above the mark), polling up to ROWSECONDS, or "".
Method WaitRow(headerId As %Integer, mark As %Integer) As %Integer [ Private ]
{
	Set deadline = $ZHorolog + ..#ROWSECONDS
	Set text = "Message '"_headerId_"' "_..#TIMERTEXT
	While 1 {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND ConfigName = 'Ens.Alarm' AND Text [ ? ORDER BY ID", mark, text)
		If result.%Next() Quit
		If $ZHorolog >= deadline Quit
		Hang 0.25
	}
	Quit $Select(result.%SQLCODE = 0: result.%GetData(1), 1: "")
}

/// 1 when a row of the list is the timer-ignored row of Ens.Alarm for the header id.
ClassMethod HasTimerRow(rows As %List, headerId As %Integer) As %Boolean [ Private ]
{
	Set wanted = "2: Ens.Alarm: Message '"_headerId_"' "_..#TIMERTEXT
	Set found = 0
	Set position = 0
	While $ListNext(rows, position, row) {
		If $Extract(row, 1, $Length(wanted)) = wanted Set found = 1 Quit
	}
	Quit found
}

/// 1 when a row of the list carries the label (the Timer ID of a synthetic row).
ClassMethod HasLabel(rows As %List, label As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set position = 0
	While $ListNext(rows, position, row) {
		If row [ ("Timer ID ='"_label_"'") Set found = 1 Quit
	}
	Quit found
}

}
