/// Tests of the failed-publish branch of IncidentManager.Tell (Story 5.3, ledger entry DW-241; AD-12, AD-15). Tell publishes an event to each session that
/// Session.Recipients gives, logs one Type 3 warning per event when a publish fails, and leaves the rows alone. The tests need no production and no namespace
/// but their own: they call Tell on a shadow instance of Test.Watch.IncidentProbe in the test process, with fixture sessions, watch rows and incidents of
/// Test.Data.Fixture on a production nobody else watches, and read the sessions' streams and the event log.
///   - TestFailedPublishLeavesTheOthersTheirEvent: with another job holding the stream of the first of two recipients, the second still gets its event and
///     the first gets none, one warning that starts with LOGPUBLISH names the incident and the event type, and no warning says that the recipients could not
///     be read. With the streams of both recipients held, the event is still logged once, not once for each recipient; with both free again the next event
///     reaches both and nothing is logged. The order of the recipients is Session.Recipients' own, so the first held stream is the first of the list that it
///     gives.
/// The failed Recipients read has no test: Session.Recipients is called by name, so a probe cannot replace it, and the only way it answers an error is the
/// privilege check of its watchers' statement, which needs a process without %All (SET $ROLES can only add roles) and so an IRIS user made for the purpose.
/// The fixture rows are removed after each test, with their streams, and so are the warnings that these tests made.
Class OcuTalon.Test.Watch.Tell Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Watch.IncidentProbe";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The streams whose lock a test took with HoldStream and has not released.
Property Held As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WatchTell", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Held = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Held, ",") {
		If $Piece(..Held, ",", i) '= "" Do ..ReleaseStream($Piece(..Held, ",", i))
	}
	Set ..Held = ""
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ..RemoveWarnings()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("WatchTell", "hold")
	Quit $$$OK
}

Method TestFailedPublishLeavesTheOthersTheirEvent()
{
	Do ..Setup("pub", .a, .b, .incident, .row)
	If '$IsObject($Get(row)) Quit
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertStatusOK(sc, "the recipients of the instance incident are read")
	Do $$$AssertEquals($ListLength(recipients), 2, "two sessions watch its production")
	If $ListLength(recipients) '= 2 Quit
	Set first = $List(recipients, 1)
	Set second = $List(recipients, 2)
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "0|0", "control: neither stream has an event yet")

	Do host.Say(row, "watch.progress", ..Progress(incident, "noticed"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "1|1", "control: with both streams free, each recipient gets the event")
	Do $$$AssertEquals(..Warned(), 0, "and nothing is logged")

	Do ..HoldStream(first)
	Do host.Say(row, "watch.progress", ..Progress(incident, "settling"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "1|2", "with the first recipient's stream held, the second still gets the event and the first does not")
	Do $$$AssertEquals(..Warned(.text), 1, "one warning says that the event could not be published")
	Do $$$AssertTrue($Find(text, incident) && $Find(text, "(watch.progress)"), "naming the incident and the event type: "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, , "Tell", $Parameter(..#PROBE, "LOGTELL")), 0, "and none says that the recipients could not be read")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT FailureCount FROM OcuTalon_Data.Incident WHERE Ref = ?", incident)
	Do $$$AssertEquals($Select(rs.%Next(): rs.%GetData(1), 1: "gone"), 3, "the stored incident row stands as it was (read from the table, as the held row object would show its old values)")

	Do ..HoldStream(second)
	Set before = ..Warned()
	Do host.Say(row, "incident", ##class(OcuTalon.Live.Payload.Incident).FromRow(row))
	Do $$$AssertEquals(..Events(first, "incident")_"|"_..Events(second, "incident"), "0|0", "with both streams held, nobody gets the incident event")
	Do $$$AssertEquals(..Warned() - before, 1, "and it is logged once, not once for each recipient")

	Do ..ReleaseStream(first)
	Do ..ReleaseStream(second)
	Set before = ..Warned()
	Do host.Say(row, "watch.progress", ..Progress(incident, "diagnosing"))
	Do $$$AssertEquals(..Events(first)_"|"_..Events(second), "2|3", "with the streams free again, the next event reaches both")
	Do $$$AssertEquals(..Warned() - before, 0, "and logs nothing")
}

/// --- helpers ---
/// Two fixture sessions a and b that watch a production of this test, and an unnoticed instance incident of the production (its Ref, and the row as an
/// object). The name keeps the productions of the tests apart.
Method Setup(name As %String, Output a As %String, Output b As %String, Output incident As %String, Output row As OcuTalon.Data.Incident)
{
	Set production = "Zz.Tell"_..Number_"."_name
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zztell"_..Number_name_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zztell"_..Number_name_"b")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_a_","_b
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set ..Refs = ..Refs_","_incident
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertTrue($IsObject(row), "the fixture incident exists")
}

/// A shadow instance of the probe, in this process, as Test.Watch.Poller makes one of its probe.
Method Host() As OcuTalon.Test.Watch.IncidentProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A watch.progress payload.
ClassMethod Progress(ref As %String, stage As %String) As OcuTalon.Live.Payload.WatchProgress
{
	Set payload = ##class(OcuTalon.Live.Payload.WatchProgress).%New()
	Set payload.Ref = ref
	Set payload.Stage = stage
	Quit payload
}

/// The number of events of the type on the session's stream.
Method Events(session As %String, type As %String = "watch.progress") As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, type).%Size()
}

/// The number of the warnings that Tell logged since the test began (text is the newest one's), of both kinds.
Method Warned(Output text As %String) As %Integer
{
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Tell", "IncidentManager could not")
	Quit count
}

/// Removes the warnings that the tests of this class made.
Method RemoveWarnings()
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Tell", "IncidentManager could not")
}

/// Another job takes the stream's lock and holds it until ReleaseStream; this returns once the job holds it.
Method HoldStream(stream As %String)
{
	Kill ^OcuTalonTest("WatchTell", "hold", stream)
	Job ##class(OcuTalon.Test.Watch.Tell).Hold(stream)
	Do ..WaitFor($Name(^OcuTalonTest("WatchTell", "hold", stream, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("WatchTell", "hold", stream, "ready")), 1, "another job holds the lock of the stream "_stream)
	Set ..Held = ..Held_$Select(..Held = "": "", 1: ",")_stream
}

/// Lets the job that HoldStream started release the stream's lock, and returns once it has.
Method ReleaseStream(stream As %String)
{
	If '$Data(^OcuTalonTest("WatchTell", "hold", stream)) || $Get(^OcuTalonTest("WatchTell", "hold", stream, "done")) Quit
	Set ^OcuTalonTest("WatchTell", "hold", stream, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("WatchTell", "hold", stream, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("WatchTell", "hold", stream, "done")), 1, "the job lets go of the stream "_stream)
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer)
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The job body of HoldStream: holds the stream's lock until released, then ends.
ClassMethod Hold(stream As %String)
{
	Lock +^OcuTalonP.LiveEventC(stream):5
	If '$Test Quit
	Set ^OcuTalonTest("WatchTell", "hold", stream, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("WatchTell", "hold", stream, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Lock -^OcuTalonP.LiveEventC(stream)
	Set ^OcuTalonTest("WatchTell", "hold", stream, "done") = 1
}

}
