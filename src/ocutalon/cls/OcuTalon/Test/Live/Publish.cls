/// Tests of Live.Publish and Live.Event (matrix rows 1 to 3): the Seq of each stream, the refusals, and two jobs
/// publishing to one stream. Every stream is a fresh reference from Bridge.Ids.NewRef(), recorded in
/// ^OcuTalonTest("LivePublish","streams") so that OnBeforeAllTests removes what an interrupted run left, and
/// OnAfterAllTests removes the run's rows and counters. Nothing is published on the instance stream.
Class OcuTalon.Test.Live.Publish Extends %UnitTest.TestCase
{

/// The run's number, from ^OcuTalonTest("LivePublish","n"), which is never reset.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("LivePublish", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Three payloads of three types get Seq 1, 2 and 3 on one stream, each row with the stream, a Utc time, the type
/// and the payload's own JSON; another stream starts at 1.
Method TestSeqPerStream()
{
	Set stream = ..NewStream()
	Set other = ..NewStream()
	Set reminder = ##class(OcuTalon.Live.Payload.Reminder).%New()
	Set reminder.Ref = "ZzPub"_..Number_"r"
	Set reminder.Text = "zz reminder"
	Set status = ##class(OcuTalon.Live.Payload.Status).%New()
	Set status.Condition = "noModelKey"
	Set status.Active = 1
	Set incident = ##class(OcuTalon.Live.Payload.Incident).%New()
	Set incident.Ref = "ZzPub"_..Number_"i"
	Set incident.State = "open"
	Set incident.Count = 4

	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 0, "a stream with no event has LastSeq 0")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", reminder, .first), "reminder is published")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "status", status, .second), "status is published")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "incident", incident, .third), "incident is published")
	Do $$$AssertEquals(first_","_second_","_third, "1,2,3", "Seq runs 1, 2, 3")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 3, "LastSeq is 3")

	Set expected = $ListBuild($ListBuild(1, "reminder", ..Json(reminder)), $ListBuild(2, "status", ..Json(status)), $ListBuild(3, "incident", ..Json(incident)))
	Set rows = ..Rows(stream)
	Do $$$AssertEquals($ListLength(rows), 3, "three rows on the stream")
	For i = 1:1:3 {
		Set row = $List(rows, i)
		Set want = $List(expected, i)
		Do $$$AssertEquals($List(row, 1), $List(want, 1), "row "_i_" has Seq "_$List(want, 1))
		Do $$$AssertEquals($List(row, 2), stream, "row "_i_" has the stream")
		Do $$$AssertTrue($List(row, 3) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "row "_i_" has a Utc time: "_$List(row, 3))
		Do $$$AssertEquals($List(row, 4), $List(want, 2), "row "_i_" has the type")
		Do $$$AssertEquals($List(row, 5), $List(want, 3), "row "_i_" holds the payload's JSON")
	}

	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(other, "reminder", reminder, .otherSeq), "the second stream publishes")
	Do $$$AssertEquals(otherSeq, 1, "another stream starts at 1")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(other), 1, "its LastSeq is 1")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 3, "the first stream is unchanged")
}

/// An unknown type, a payload of another type's class, a payload that isn't an object, a bad stream and a call
/// inside a transaction each get an error status that names the problem, write no row and leave LastSeq alone.
Method TestRefuses()
{
	Set stream = ..NewStream()
	Set reminder = ##class(OcuTalon.Live.Payload.Reminder).%New()
	Set reminder.Ref = "ZzPub"_..Number_"x"
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", reminder), "one event is published first")
	Set status = ##class(OcuTalon.Live.Payload.Status).%New()

	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "zz.type", reminder, .seq)
	Do ..AssertRefused(sc, "zz.type", stream, 1, "an unknown type")
	Do $$$AssertEquals(seq, 0, "seq is 0 for a refusal")
	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", status, .seq)
	Do ..AssertRefused(sc, "OcuTalon.Live.Payload.Reminder", stream, 1, "a payload of another type's class")
	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", "not an object", .seq)
	Do ..AssertRefused(sc, "OcuTalon.Live.Payload.Reminder", stream, 1, "a payload that isn't an object")
	Set sc = ##class(OcuTalon.Live.Publish).Publish("", "reminder", reminder, .seq)
	Do ..AssertRefused(sc, "stream", "", 0, "an empty stream")
	Set sc = ##class(OcuTalon.Live.Publish).Publish("bad stream", "reminder", reminder, .seq)
	Do ..AssertRefused(sc, "stream", "bad stream", 0, "a stream that isn't a reference")
	Set sc = ##class(OcuTalon.Live.Publish).Publish($Extract(stream, 1, 21), "reminder", reminder, .seq)
	Do ..AssertRefused(sc, "stream", $Extract(stream, 1, 21), 0, "a reference of 21 characters")

	TSTART
	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", reminder, .seq)
	TROLLBACK
	Do ..AssertRefused(sc, "transaction", stream, 1, "a call inside a transaction")
	Do $$$AssertEquals($TLevel, 0, "no transaction is left open")
}

/// Two jobs publish 50 events each to one stream, started together: Seq runs 1 to 100 with no gap and no duplicate, and
/// the rows' ids are in Seq order.
Method TestSeqUnderLoad()
{
	Set stream = ..NewStream()
	Kill ^OcuTalonTest("LivePublish", "run", stream)
	Job ##class(OcuTalon.Test.Live.Publish).Burst(stream, 50)
	Job ##class(OcuTalon.Test.Live.Publish).Burst(stream, 50)
	Set deadline = $ZHorolog + 60
	While ($Get(^OcuTalonTest("LivePublish", "run", stream, "ready")) < 2) && ($ZHorolog < deadline) {
		Hang 0.01
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "run", stream, "ready")), 2, "both jobs are waiting to start")
	Set ^OcuTalonTest("LivePublish", "run", stream, "go") = 1
	Set deadline = $ZHorolog + 120
	While ($Get(^OcuTalonTest("LivePublish", "run", stream, "done")) < 2) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "run", stream, "done")), 2, "both jobs finished")
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "run", stream, "errors"), 0), 0, "no publish failed: "_$Get(^OcuTalonTest("LivePublish", "run", stream, "error", 1)))

	Set rows = ..Rows(stream)
	Do $$$AssertEquals($ListLength(rows), 100, "100 rows")
	Set wrong = ""
	For i = 1:1:$ListLength(rows) {
		If $List($List(rows, i), 1) '= i Set wrong = wrong_" "_i_"=" _$List($List(rows, i), 1)
	}
	Do $$$AssertEquals(wrong, "", "the rows, in id order, hold Seq 1 to 100 with no gap and no duplicate")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 100, "LastSeq is 100")
}

/// The job body of TestSeqUnderLoad: waits for the go signal, publishes count reminders to stream and records how it
/// ended.
ClassMethod Burst(stream As %String, count As %Integer)
{
	Do $Increment(^OcuTalonTest("LivePublish", "run", stream, "ready"))
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("LivePublish", "run", stream, "go")) && ($ZHorolog < deadline) {
	}
	Set errors = 0
	For i = 1:1:count {
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzBurst"_$Job_"x"_i
		Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload)
		If $SYSTEM.Status.IsError(sc) {
			Set errors = errors + 1
			Set ^OcuTalonTest("LivePublish", "run", stream, "error", errors) = $SYSTEM.Status.GetErrorText(sc)
		}
	}
	Do $Increment(^OcuTalonTest("LivePublish", "run", stream, "errors"), errors)
	Do $Increment(^OcuTalonTest("LivePublish", "run", stream, "done"))
}

/// A publish that fails inside its transaction (the insert clashes with the unique index of a row that Publish
/// doesn't know of) leaves no transaction, no raised counter and no row of its own, and the next publish takes the
/// Seq that the failed one would have had.
Method TestFailureLeavesNoGap()
{
	Set stream = ..NewStream()
	Set clash = ##class(OcuTalon.Live.Event).%New()
	Set clash.Seq = 1
	Set clash.Stream = stream
	Set clash.Ts = ##class(OcuTalon.Data.Time).NowUtc()
	Set clash.Type = "reminder"
	Set clash.Payload = "{}"
	Do $$$AssertStatusOK(clash.%Save(), "the clashing row is saved")
	Set clashId = clash.%Id()
	Set reminder = ##class(OcuTalon.Live.Payload.Reminder).%New()
	Set reminder.Ref = "ZzPub"_..Number_"f"

	Set sc = ##class(OcuTalon.Live.Publish).Publish(stream, "reminder", reminder, .seq)
	Do $$$AssertStatusNotOK(sc, "the insert that clashes with the unique index fails")
	Do $$$AssertEquals(seq, 0, "seq is 0")
	Do $$$AssertEquals($TLevel, 0, "no transaction is left open")
	If $TLevel > 0 TROLLBACK
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 0, "the counter is unchanged")
	Do $$$AssertEquals($ListLength(..Rows(stream)), 1, "no row is written but the clashing one")

	Do ##class(OcuTalon.Live.Event).%DeleteId(clashId)
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", reminder, .seq), "the next publish succeeds")
	Do $$$AssertEquals(seq, 1, "with Seq 1: no gap")
}

/// LastSeq never reports a Seq that is not committed: while another job holds the stream's lock with its counter
/// raised and its transaction open, a reader of LastSeq waits, and then reports the committed value.
Method TestLastSeqWaitsForAnOpenPublish()
{
	Set stream = ..NewStream()
	Kill ^OcuTalonTest("LivePublish", "hold", stream)
	Job ##class(OcuTalon.Test.Live.Publish).Holder(stream)
	Do ..WaitFor($Name(^OcuTalonTest("LivePublish", "hold", stream, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "hold", stream, "ready")), 1, "the publisher holds the lock with its transaction open")
	Job ##class(OcuTalon.Test.Live.Publish).Reader(stream)
	Do ..WaitFor($Name(^OcuTalonTest("LivePublish", "hold", stream, "started")), 60)
	Hang 1
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "hold", stream, "done"), 0), 0, "the reader is still waiting while the publisher's transaction is open")
	Set ^OcuTalonTest("LivePublish", "hold", stream, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("LivePublish", "hold", stream, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "hold", stream, "done")), 1, "the reader returns once the publisher has committed")
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "hold", stream, "value")), 1, "with the committed value")
	Do $$$AssertEquals($Get(^OcuTalonTest("LivePublish", "hold", stream, "error"), ""), "", "and no error")
}

/// The job body of TestLastSeqWaitsForAnOpenPublish: takes the stream's lock, raises the counter inside a
/// transaction, and commits when released.
ClassMethod Holder(stream As %String)
{
	Lock +^OcuTalonP.LiveEventC(stream):5
	If '$Test Quit
	TSTART
	Set ^OcuTalonP.LiveEventC(stream) = 1
	Set ^OcuTalonTest("LivePublish", "hold", stream, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("LivePublish", "hold", stream, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	TCOMMIT
	Lock -^OcuTalonP.LiveEventC(stream)
}

/// The job body of TestLastSeqWaitsForAnOpenPublish: reads LastSeq and records the value and the end.
ClassMethod Reader(stream As %String)
{
	Set ^OcuTalonTest("LivePublish", "hold", stream, "started") = 1
	Try {
		Set ^OcuTalonTest("LivePublish", "hold", stream, "value") = ##class(OcuTalon.Live.Publish).LastSeq(stream)
	} Catch exception {
		Set ^OcuTalonTest("LivePublish", "hold", stream, "error") = exception.DisplayString()
	}
	Set ^OcuTalonTest("LivePublish", "hold", stream, "done") = 1
}

/// --- helpers ---
/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// A fresh stream, recorded for the clean-up.
Method NewStream() As %String [ Private ]
{
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("LivePublish", "streams", stream) = ""
	Quit stream
}

/// The JSON a payload object exports.
ClassMethod Json(payload As %RegisteredObject) As %String [ Private ]
{
	Do payload.%JSONExportToString(.json)
	Quit json
}

/// The rows of a stream in id order, as a list of $ListBuild(Seq, Stream, Ts, Type, Payload).
ClassMethod Rows(stream As %String) As %List [ Private ]
{
	Set rows = ""
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Seq, Stream, Ts, Type, Payload FROM OcuTalon_Live.Event WHERE Stream = ? ORDER BY %ID")
	Set result = statement.%Execute(stream)
	While result.%Next() {
		Set rows = rows_$ListBuild($ListBuild(result.%Get("Seq"), result.%Get("Stream"), result.%Get("Ts"), result.%Get("Type"), result.%Get("Payload")))
	}
	Quit rows
}

/// Asserts that sc is an error that mentions the text, and that the stream still has rows rows.
Method AssertRefused(sc As %Status, text As %String, stream As %String, rows As %Integer, what As %String) [ Private ]
{
	Do $$$AssertStatusNotOK(sc, what_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ text, what_": the error names the problem: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ListLength(..Rows(stream)), rows, what_" writes no row")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), rows, what_" leaves LastSeq alone")
}

/// Deletes the rows and counters of every stream that this test recorded, in this or an earlier run.
ClassMethod Clean() [ Private ]
{
	Set stream = ""
	For {
		Set stream = $Order(^OcuTalonTest("LivePublish", "streams", stream))
		Quit:stream=""
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("DELETE FROM OcuTalon_Live.Event WHERE Stream = ?")
		Do statement.%Execute(stream)
		Kill ^OcuTalonP.LiveEventC(stream)
		Kill ^OcuTalonTest("LivePublish", "run", stream)
		Kill ^OcuTalonTest("LivePublish", "hold", stream)
		Kill ^OcuTalonTest("LivePublish", "streams", stream)
	}
}

}
