/// End-to-end tests of the Orders production in namespace OCUORDERS (Story 0.10). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): it needs the namespace OCUORDERS, which the Demo step creates at the start of a Docker install and which a
/// slot never has. Where OCUORDERS does not exist, or the Orders production does not run there, every test fails with that
/// reason, so that a broken Demo step can never give a green shard.
///   - TestTheStepOwnsOrders: the step owns the namespace it created, and demo mode is on;
///   - TestOneOrderInEachFormat: an order in YYYY-MM-DD completes at OrdersToWarehouse; an order in MM/DD/YYYY fails at
///     OrdersFromPartner with the transform's error in the event log; both carry the caller's reference as SuperSession;
///   - TestPartnerKeepsNoState: two batches in different formats, one after the other, each pass or fail by their own format;
///   - TestBadBatchSendsNothing: a bad batch is refused with an error that names the value, and no message is sent;
///   - TestRepairedCopyGoesThrough: a failed order resent with the date repaired completes, and the original stays errored;
///   - TestSnapshotIsReadableAndCurrent: the committed evaluation case and snapshot under /opt/ocutalon/eval are readable, and a
///     fresh recording has the same projection as the committed one;
///   - TestHoldHidesFailures: while HoldFailures is in force a watcher of Orders makes no incident from failing orders, and its
///     guide stays at step 3 with Break the feed active;
///   - TestReleaseHidesLeftovers: the failures that an earlier sender left (its session gone, so they count as instance) are
///     never read after ReleaseFailures, whatever mark the last reading left;
///   - TestReleaseKeepsLaterFailures: failing orders sent after ReleaseFailures are read as before and become an incident.
/// A failed order has header Status 8 (Error) at OrdersFromPartner, with IsError 0 and an empty ErrorStatus, because it is a
/// request with no response; its error text is the event-log row of Type 2 (Error) for that item and session.
/// Switching to OCUORDERS happens only in Snapshot, the class methods below (Running, Send, Count, Sessions, Headers, ErrorTexts and Resend; all but Resend
/// are public, with WaitCount, for Test.Demo.BreakFeedProduction and the demo-path step) and Test.Data.Fixture.RemoveMessages, each of
/// which calls only classes that resolve there (OcuTalon.Demo.Orders, Ens, EnsLib and % classes) while it is there and returns plain
/// values or dynamic objects.
/// Every test makes its references before it switches, and OnAfterAllTests deletes the headers, bodies and event-log rows of the
/// references of the run.
/// The failing orders that a test sends are real failures to the real FailurePoller and IncidentManager of OCUTALON, which would turn
/// them into Orders incidents that later tests of the stack (the demo guide's, Test.Live.GuideRefresh) would see. So a sender of failing
/// Orders messages holds the Orders WatchMark ahead while it runs (HoldFailures: MarkAt is HOLDSECONDS ahead, so no reading starts
/// before the end of the hold) and, when its batches are complete, releases it (ReleaseFailures: MarkAt is the release time, so none of
/// its failures is ever read, removed or not, and later failures are read as before). This class holds in OnBeforeAllTests and again in
/// OnBeforeOneTest and releases in OnAfterAllTests; Test.Demo.BreakFeedProduction and the floor specs (web/e2e/support/guide.ts) do the
/// same, and so should any other test that sends real failing Orders messages. OnAfterOneTest deletes the incidents that a test's
/// watchers made.
Class OcuTalon.Test.Demo.Production Extends %UnitTest.TestCase
{

/// The namespace of the demo.
Parameter NAMESPACE = "OCUORDERS";

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Demo.Orders.Production";

/// The folder of the evaluation case, as a throwaway mounts it.
Parameter EVALFOLDER = "/opt/ocutalon/eval/orders-date-format/";

/// How long a wait for messages lasts, in seconds.
Parameter WAITSECONDS = 60;

/// How far ahead of now HoldFailures puts the Orders WatchMark, in seconds.
Parameter HOLDSECONDS = 600;

/// How long a test waits for FailurePoller to have polled at least twice (its CallInterval is 3 s), in seconds.
Parameter POLLWAIT = 7;

/// The 22-character references that this run used.
Property Refs As %DynamicArray;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// 1 when OnBeforeAllTests held the Orders failures, so that OnAfterAllTests releases them.
Property Held As %Boolean;

/// The Refs of the fixture sessions of the running test that watch Orders, comma-separated.
Property Watchers As %String(MAXLEN = "");

/// The newest Incident id when the running test began, "" before the first test.
Property IncidentFloor As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Refs = []
	Set ..Missing = ""
	Set ..Held = 0
	Set ..Watchers = ""
	Set ..IncidentFloor = ""
	If '##class(%SYS.Namespace).Exists(..#NAMESPACE) {
		Set ..Missing = "OCUORDERS does not exist: this class runs in throwaways and CI only (Rule 21)"
	} ElseIf '..Running() {
		Set ..Missing = "The Orders production does not run in OCUORDERS"
	}
	If ..Missing = "" {
		Set sc = ..HoldFailures()
		If $$$ISOK(sc) {
			Set ..Held = 1
		} Else {
			Set ..Missing = "The Orders failures could not be held: "_$SYSTEM.Status.GetErrorText(sc)
		}
	}
	Quit $$$OK
}

/// Holds the failures again (a test that released them in the middle leaves them free) and notes the newest incident, so that
/// OnAfterOneTest deletes only what the test caused.
Method OnBeforeOneTest() As %Status
{
	Set ..Watchers = ""
	Set ..IncidentFloor = ""
	If ..Missing = "" {
		Set sc = ..HoldFailures()
		If $$$ISERR(sc) Set ..Missing = "The Orders failures could not be held: "_$SYSTEM.Status.GetErrorText(sc)
	}
	If ..Missing = "" Set ..IncidentFloor = ##class(OcuTalon.Test.Watch.Case).Top("OcuTalon_Data.Incident", "OCUTALON")
	Quit $$$OK
}

/// Deletes the incidents of the test's watchers and the instance incidents made since it began, with their groups and decisions,
/// then the fixture rows.
Method OnAfterOneTest() As %Status
{
	If ..Missing = "" {
		For i = 1:1:$Length(..Watchers, ",") {
			Set ref = $Piece(..Watchers, ",", i)
			If ref '= "" Do ##class(OcuTalon.Test.Watch.Case).DropIncidentRows("SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = ?", ref)
		}
		If ..IncidentFloor '= "" Do ##class(OcuTalon.Test.Watch.Case).DropIncidentRows("SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = 'instance' AND ID > ?", ..IncidentFloor)
	}
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Refs, ..#NAMESPACE)
	If ..Held Do ..ReleaseFailures()
	Quit $$$OK
}

/// The step owns the namespace that it created, and demo mode is on in the throwaway.
Method TestTheStepOwnsOrders()
{
	If '..Guard() Quit
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Owned(), 1, "Owned() is 1 for the namespace that the step created")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on in the throwaway")
}

/// Rows 9 and 10: one order in each format.
Method TestOneOrderInEachFormat()
{
	If '..Guard() Quit
	Set good = ..NewRef()
	Set bad = ..NewRef()
	Do $$$AssertEquals(..Send(1, "YYYY-MM-DD", good, "2026-10-16"), "", "the order in the expected format is sent")
	Do $$$AssertEquals(..Send(1, "MM/DD/YYYY", bad, "2026-10-16"), "", "the order in the changed format is sent")
	Do $$$AssertEquals(..WaitCount(good, "OrdersToWarehouse", 9, 1), 1, "the good order completes at OrdersToWarehouse")
	Do $$$AssertEquals(..WaitCount(good, "OrdersFromPartner", 9, 1), 1, "the good order completes at OrdersFromPartner")
	Do $$$AssertEquals(..WaitCount(bad, "OrdersFromPartner", 8, 1), 1, "the bad order fails at OrdersFromPartner")

	Set headers = ..Headers(good)
	Do $$$AssertEquals(headers.%Size(), 2, "the good order has two headers")
	Set sessions = ""
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		Do $$$AssertEquals(header.superSession, good, "header "_header.id_" carries the caller's reference")
		Do $$$AssertEquals(header.status, 9, "header "_header.id_" is completed")
		Set sessions = header.sessionId
		If header.target = "OrdersFromPartner" {
			Do $$$AssertEquals(header.bodyClass, "OcuTalon.Demo.Orders.PartnerOrder", "the order reaches the transform")
			Do $$$AssertEquals(header.body.OrderDate, "2026-10-16", "the order date is as sent")
		} Else {
			Do $$$AssertEquals(header.target, "OrdersToWarehouse", "the other header is for the warehouse")
			Do $$$AssertEquals(header.bodyClass, "OcuTalon.Demo.Orders.WarehouseOrder", "the warehouse takes a WarehouseOrder")
			Do $$$AssertEquals(header.body.OrderDate, $ZDATEH("2026-10-16", 3), "the warehouse order date is the day number")
		}
	}
	Set goodSession = sessions
	Do $$$AssertEquals(..ErrorTexts(goodSession).%Size(), 0, "the good order's session logs no error at OrdersFromPartner")

	Set headers = ..Headers(bad)
	Do $$$AssertEquals(headers.%Size(), 1, "the bad order has one header: nothing reaches the warehouse")
	If headers.%Size() = 1 {
		Set header = headers.%Get(0)
		Do $$$AssertEquals(header.source_"->"_header.target, "PartnerOrdersIn->OrdersFromPartner", "the bad order fails at OrdersFromPartner")
		Do $$$AssertEquals(header.status, 8, "the bad order is in status Error")
		Do $$$AssertEquals(header.superSession, bad, "the bad order carries the caller's reference")
		Do $$$AssertEquals(header.body.OrderDate, "10/16/2026", "the bad order keeps its date as sent")
		Do $$$AssertTrue(header.sessionId '= goodSession, "the two orders are in different sessions")
		Set texts = ..ErrorTexts(header.sessionId)
		Set found = 0
		For i = 0:1:texts.%Size() - 1 {
			If texts.%Get(i) [ "ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'." Set found = 1
		}
		Do $$$AssertTrue(found, "the event log holds the transform's error at OrdersFromPartner")
	}
}

/// Row 11: no state is kept between batches.
Method TestPartnerKeepsNoState()
{
	If '..Guard() Quit
	Set refA = ..NewRef()
	Set refB = ..NewRef()
	Do $$$AssertEquals(..Send(3, "MM/DD/YYYY", refA, "2026-10-16"), "", "the batch in the changed format is sent")
	Do $$$AssertEquals(..Send(2, "YYYY-MM-DD", refB, "2026-10-16"), "", "the batch in the expected format is sent after it")
	Do $$$AssertEquals(..WaitCount(refA, "OrdersFromPartner", 8, 3), 3, "all 3 orders of the first batch fail")
	Do $$$AssertEquals(..WaitCount(refB, "OrdersToWarehouse", 9, 2), 2, "both orders of the second batch complete")
	Do $$$AssertEquals(..Count(refB, "OrdersFromPartner", 8), 0, "none of the second batch fails")
	Do $$$AssertEquals(..Count(refA, "OrdersToWarehouse", 9), 0, "none of the first batch reaches the warehouse")
	Do $$$AssertEquals(..Sessions(refA), 3, "each order of the first batch is in its own session")
	Do $$$AssertEquals(..Sessions(refB), 2, "each order of the second batch is in its own session")
}

/// Row 12, in OCUORDERS: a bad batch is refused, naming the value, and nothing is sent.
Method TestBadBatchSendsNothing()
{
	If '..Guard() Quit
	Set cases = $ListBuild(
		$ListBuild(0, "YYYY-MM-DD", "2026-10-16", "The batch size must be a whole number from 1 to 1000, not '0'."),
		$ListBuild(1001, "YYYY-MM-DD", "2026-10-16", "The batch size must be a whole number from 1 to 1000, not '1001'."),
		$ListBuild("x", "YYYY-MM-DD", "2026-10-16", "The batch size must be a whole number from 1 to 1000, not 'x'."),
		$ListBuild(1, "DD.MM.YYYY", "2026-10-16", "The date format must be YYYY-MM-DD or MM/DD/YYYY, not 'DD.MM.YYYY'."),
		$ListBuild(1, "YYYY-MM-DD", "10/16/2026", "The order date must be a date written YYYY-MM-DD, not '10/16/2026'."))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ref = ..NewRef()
		Set text = ..Send($List(case, 1), $List(case, 2), ref, $List(case, 3))
		Do $$$AssertEquals(text, "ERROR #5001: "_$List(case, 4), "the batch is refused: "_$List(case, 4))
		Do $$$AssertEquals(..Headers(ref).%Size(), 0, "nothing is sent for the refused batch")
	}
	Set text = ..Send(1, "YYYY-MM-DD", "abc", "2026-10-16")
	Do $$$AssertEquals(text, "ERROR #5001: The trace reference must be empty or 22 characters of A-Z, a-z, 0-9, - and _, not 'abc'.", "a trace reference that is not 22 characters is refused")
	Do $$$AssertEquals(..Headers("abc").%Size(), 0, "nothing is sent for the refused reference")
}

/// Row 13: a failed order resent to OrdersFromPartner with the date repaired completes at OrdersToWarehouse, the original stays
/// errored, and the copy keeps the reference.
Method TestRepairedCopyGoesThrough()
{
	If '..Guard() Quit
	Set ref = ..NewRef()
	Do $$$AssertEquals(..Send(1, "MM/DD/YYYY", ref, "2026-10-16"), "", "the order in the changed format is sent")
	Do $$$AssertEquals(..WaitCount(ref, "OrdersFromPartner", 8, 1), 1, "the order fails")
	Set failed = ..Headers(ref).%Get(0)
	Set resent = ..Resend(failed.id, "2026-10-16")
	Do $$$AssertEquals(resent.error, "", "the repaired copy is resent")
	Do $$$AssertEquals(..WaitCount(ref, "OrdersToWarehouse", 9, 1), 1, "the repaired copy reaches the warehouse")
	Do $$$AssertEquals(..WaitCount(ref, "OrdersFromPartner", 9, 1), 1, "the repaired copy completes at OrdersFromPartner")
	Set headers = ..Headers(ref)
	Set copy = ""
	Set original = ""
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If header.id = resent.id Set copy = header
		If header.id = failed.id Set original = header
	}
	Do $$$AssertTrue($IsObject(copy), "the copy is a header of the reference")
	If $IsObject(copy) {
		Do $$$AssertEquals(copy.status, 9, "the copy is completed")
		Do $$$AssertEquals(copy.superSession, ref, "the copy keeps the reference")
		Do $$$AssertEquals(copy.body.OrderDate, "2026-10-16", "the copy holds the repaired date")
	}
	Do $$$AssertTrue($IsObject(original), "the original is still a header of the reference")
	If $IsObject(original) Do $$$AssertEquals(original.status, 8, "the original stays errored")
}

/// Row 14: the committed case and snapshot are readable and current.
Method TestSnapshotIsReadableAndCurrent()
{
	If '..Guard() Quit
	Set case = ..ReadJson(..#EVALFOLDER_"case.json")
	Set committed = ..ReadJson(..#EVALFOLDER_"snapshot.json")
	Do $$$AssertTrue($IsObject(case), "case.json is readable under "_..#EVALFOLDER)
	Do $$$AssertTrue($IsObject(committed), "snapshot.json is readable under "_..#EVALFOLDER)
	If '$IsObject(case) || '$IsObject(committed) Quit
	Do $$$AssertEquals(case.name, "orders-date-format", "the case is named orders-date-format")
	Do $$$AssertEquals(case.kind, "incident", "the case is an incident")
	Do $$$AssertEquals(case.heldOut, 0, "the case is not held out")
	Do $$$AssertEquals(case.snapshot, "snapshot.json", "the case names its snapshot")
	Do $$$AssertEquals(case.expectation.causeCategory, "data_format_change", "the expected cause is a data format change")
	Do $$$AssertEquals(case.expectation.elementAtFault, "OrderDate", "the expected element at fault is OrderDate")
	Do $$$AssertEquals(case.expectation.fixKind, "repair_resend", "the expected fix is a repair and resend")
	Do $$$AssertEquals(committed.format, "ocutalon.readerSnapshot/1", "the snapshot has its format")
	Do $$$AssertEquals(committed.failures.%Size(), 50, "the snapshot holds 50 failures")
	For i = 0:1:committed.failures.%Size() - 1 {
		Set failure = committed.failures.%Get(i)
		If failure.targetConfigName '= "OrdersFromPartner" Do $$$AssertEquals(failure.targetConfigName, "OrdersFromPartner", "failure "_i_" is at OrdersFromPartner")
		If failure.body.OrderDate '= "10/16/2026" Do $$$AssertEquals(failure.body.OrderDate, "10/16/2026", "failure "_i_" has the changed date")
		If failure.error '[ "Expected YYYY-MM-DD, got '10/16/2026'." Do $$$AssertTrue(0, "failure "_i_" carries the transform's error")
	}
	Do $$$AssertTrue(committed.items.%Size() = 3, "the snapshot holds the three items' settings")
	Do $$$AssertTrue(committed.trace.%Size() > 0, "the snapshot holds a trace excerpt")

	Set ref = ..NewRef()
	Do $$$AssertEquals(..Send(50, "MM/DD/YYYY", ref, "2026-10-16"), "", "a fresh batch of 50 is sent")
	Do $$$AssertEquals(..WaitCount(ref, "OrdersFromPartner", 8, 50), 50, "all 50 orders fail")
	Set fresh = ..Snapshot(ref, {"count": 50, "dateFormat": "MM/DD/YYYY", "orderDate": "2026-10-16"})
	Do $$$AssertEquals(..Projection(fresh).%ToJSON(), ..Projection(committed).%ToJSON(), "a fresh recording has the committed snapshot's projection")
}

/// While the failures are held, a watcher of Orders reads none of the failing orders that are sent: no incident comes of them, and its
/// guide stays at step 3 with Break the feed active.
Method TestHoldHidesFailures()
{
	If '..Guard() Quit
	Set start = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(..HoldFailures(), "the failures are held")
	Set watcher = ..FixtureSession(1, .trace)
	Set other = ..NewRef()
	Do $$$AssertEquals(..Send(3, "MM/DD/YYYY", trace, "2026-10-16"), "", "3 failing orders are sent with the watcher's trace reference")
	Do $$$AssertEquals(..Send(1, "MM/DD/YYYY", other, "2026-10-16"), "", "1 failing order is sent with a reference that no session owns")
	Do $$$AssertEquals(..WaitCount(trace, "OrdersFromPartner", 8, 3), 3, "the 3 orders fail")
	Do $$$AssertEquals(..WaitCount(other, "OrdersFromPartner", 8, 1), 1, "the other order fails")
	Hang ..#POLLWAIT
	Do $$$AssertEquals(..IncidentsSince(start), 0, "no Orders incident was made since the test began")
	Set guide = ##class(OcuTalon.Demo.Guide).Compute(watcher)
	Do $$$AssertEquals(guide.BreakFeed.Active, 1, "Break the feed is active in the watcher's guide")
	Do $$$AssertEquals(guide.Steps.GetAt(3).Done, 0, "step 3 is not done in the watcher's guide")
}

/// Failures that an earlier sender left, whose session is gone (so they count as instance), are never read once the failures are
/// released, even when the last reading left the mark before them: a new watcher sees no incident and Break the feed active.
Method TestReleaseHidesLeftovers()
{
	If '..Guard() Quit
	Set start = ##class(OcuTalon.Data.Time).NowUtc()
	Set stamp = ##class(OcuTalon.Watch.Mark).Normal($ZDateTime($ZTimeStamp, 3, 1, 3))
	Do $$$AssertStatusOK(..PutMark(##class(OcuTalon.Watch.Mark).Shift(stamp, -5)), "the mark is 5 s before the failures, as an earlier reading leaves it")
	Set sender = ..FixtureSession(0, .trace)
	Set other = ..NewRef()
	Do $$$AssertEquals(..Send(2, "MM/DD/YYYY", trace, "2026-10-16"), "", "2 failing orders are sent with the sender's trace reference")
	Do $$$AssertEquals(..Send(1, "MM/DD/YYYY", other, "2026-10-16"), "", "1 failing order is sent with a reference that no session owns")
	Do $$$AssertEquals(..WaitCount(trace, "OrdersFromPartner", 8, 2), 2, "the 2 orders fail")
	Do $$$AssertEquals(..WaitCount(other, "OrdersFromPartner", 8, 1), 1, "the other order fails")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(sender)
	// Longer than the settle quiet time (watch.settleQuietSeconds, 10 by default): the leftovers are older than a reading would wait for.
	Hang 11
	Do $$$AssertStatusOK(..ReleaseFailures(), "the failures are released")
	Set watcher = ..FixtureSession(1)
	Hang ..#POLLWAIT
	Do $$$AssertEquals(..IncidentsSince(start), 0, "no Orders incident was made since the test began")
	Set incident = ##class(OcuTalon.Data.Ownership).NewestIncident(watcher, ..#NAMESPACE, ..#PRODUCTION, "", .sc)
	Do $$$AssertEquals($Select($IsObject(incident): incident.Ref, 1: ""), "", "the watcher sees no incident of the production")
	Set busy = ##class(OcuTalon.Data.Ownership).IncidentInProgress(watcher, ..#NAMESPACE, ..#PRODUCTION, .sc)
	Do $$$AssertEquals($Select($IsObject(busy): busy.Ref, 1: ""), "", "the watcher sees no incident in progress")
	Do $$$AssertEquals(##class(OcuTalon.Demo.Guide).Compute(watcher).BreakFeed.Active, 1, "Break the feed is active in the watcher's guide")
}

/// Failing orders sent after the release are read as before: the watcher gets an incident within 15 s.
Method TestReleaseKeepsLaterFailures()
{
	If '..Guard() Quit
	Do $$$AssertStatusOK(..ReleaseFailures(), "the failures are released")
	Set watcher = ..FixtureSession(1, .trace)
	Do $$$AssertEquals(..Send(2, "MM/DD/YYYY", trace, "2026-10-16"), "", "2 failing orders are sent with the watcher's trace reference")
	Set deadline = $ZHorolog + 15
	For {
		Set found = ..IncidentsOf(watcher)
		If found || ($ZHorolog > deadline) Quit
		Hang 0.5
	}
	Do $$$AssertTrue(found > 0, "an incident of the watcher appears within 15 s")
	Do ##class(OcuTalon.Test.Watch.Case).DropIncidentRows("SELECT ID FROM OcuTalon_Data.Incident WHERE OwnerRef = ?", watcher)
}

/// Holds the Orders WatchMark HOLDSECONDS ahead of now, with no failure marked as seen, so that FailurePoller reads nothing that the
/// holder sends. Creates the row when there is none. Runs in OCUTALON and touches no other row.
ClassMethod HoldFailures() As %Status
{
	Quit ..PutMark(##class(OcuTalon.Watch.Mark).Shift(..NowStamp(), ..#HOLDSECONDS))
}

/// Puts the Orders WatchMark at the release time (now plus the reading's overlap, so that the next reading starts at the release
/// time), with no failure marked as seen: none of the failures sent before is ever read, and the failures sent later are read as
/// before. Call it when the holder's batches are complete. Runs in OCUTALON and touches no other row.
ClassMethod ReleaseFailures() As %Status
{
	Quit ..PutMark(##class(OcuTalon.Watch.Mark).Shift(..NowStamp(), ##class(OcuTalon.Watch.Mark).#OVERLAP))
}

/// Writes the Orders WatchMark row (namespace and production of this class) with the stamp as MarkAt and no Seen, creating it when it
/// does not exist.
ClassMethod PutMark(markAt As %String) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Data.WatchMark).NamespaceProductionIndexOpen(..#NAMESPACE, ..#PRODUCTION)
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Data.WatchMark).%New()
		Set row.Namespace = ..#NAMESPACE
		Set row.Production = ..#PRODUCTION
	}
	Set row.MarkAt = markAt
	Set row.Seen = ""
	Quit row.%Save()
}

/// Now as a stamp: UTC, YYYY-MM-DD HH:MM:SS.sss.
ClassMethod NowStamp() As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Mark).Normal($ZDateTime($ZTimeStamp, 3, 1, 3))
}

/// A fixture session, kept for the clean-up; its Ref is returned and its TraceRef is in trace (and in Refs). With watching, it
/// watches Orders and is one of the test's Watchers.
Method FixtureSession(watching As %Boolean, Output trace As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzdemoprod")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
	Do ..Refs.%Push(trace)
	If watching {
		Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NAMESPACE, ..#PRODUCTION)
		Set ..Watchers = ..Watchers_$Select(..Watchers = "": "", 1: ",")_ref
	}
	Quit ref
}

/// The number of Orders incidents whose first failure is between the stamp (UTC, YYYY-MM-DDThh:mm:ssZ) and now.
ClassMethod IncidentsSince(start As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Incident WHERE Namespace = ? AND Production = ? AND FirstAt >= ? AND FirstAt <= ?", ..#NAMESPACE, ..#PRODUCTION, start, ##class(OcuTalon.Data.Time).NowUtc())
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of Orders incidents that the owner (a session's Ref) has.
ClassMethod IncidentsOf(ownerRef As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Incident WHERE OwnerRef = ? AND Namespace = ? AND Production = ?", ownerRef, ..#NAMESPACE, ..#PRODUCTION)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The reference of a fixture, kept for the clean-up.
Method NewRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Refs.%Push(ref)
	Quit ref
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The projection of a snapshot that two recordings of the same behaviour share: the failures sorted by order number, each
/// with its source, target, body class, status, isError, error and body; the items as recorded; the trace entries' type,
/// source, target, body class, status and isError; the sorted pairs of type and item of the event log; and the count. Ids,
/// times and session numbers are left out. Runs in OCUTALON.
ClassMethod Projection(snapshot As %DynamicObject) As %DynamicObject
{
	Set result = {}
	For i = 0:1:snapshot.failures.%Size() - 1 {
		Set failure = snapshot.failures.%Get(i)
		Set kept = {"source": (failure.sourceConfigName), "target": (failure.targetConfigName), "bodyClass": (failure.bodyClass), "status": (failure.status)}
		Do kept.%Set("isError", failure.isError, "boolean")
		Set kept.error = failure.error
		Set kept.body = failure.body
		Set failures(failure.body.OrderNumber_"|"_i) = kept
	}
	Set sorted = []
	Set key = ""
	For {
		Set key = $Order(failures(key), 1, kept)
		Quit:key=""
		Do sorted.%Push(kept)
	}
	Set result.failures = sorted
	Set result.items = snapshot.items
	Set trace = []
	For i = 0:1:snapshot.trace.%Size() - 1 {
		Set entry = snapshot.trace.%Get(i)
		Set kept = {"type": (entry.type), "source": (entry.sourceConfigName), "target": (entry.targetConfigName), "bodyClass": (entry.bodyClass), "status": (entry.status)}
		Do kept.%Set("isError", entry.isError, "boolean")
		Do trace.%Push(kept)
	}
	Set result.trace = trace
	For i = 0:1:snapshot.eventLog.%Size() - 1 {
		Set row = snapshot.eventLog.%Get(i)
		Set pairs(row.type_"|"_row.configName_"|"_i) = row.type_"|"_row.configName
	}
	Set log = []
	Set key = ""
	For {
		Set key = $Order(pairs(key), 1, pair)
		Quit:key=""
		Do log.%Push(pair)
	}
	Set result.eventLog = log
	Set result.count = snapshot.failures.%Size()
	Quit result
}

/// Sends the recording batch (50 orders in MM/DD/YYYY dated 2026-10-16), waits for its 50 failures, and writes the snapshot of
/// them to file as JSON. Used by docker/tests/record-eval.sh in a throwaway; the batch's messages are deleted afterwards.
ClassMethod Record(file As %String) As %Status
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set text = ..Send(50, "MM/DD/YYYY", ref, "2026-10-16")
	If text '= "" Quit $$$ERROR($$$GeneralError, "The recording batch was not sent: "_text)
	Set count = ..WaitCount(ref, "OrdersFromPartner", 8, 50)
	If count '= 50 {
		Do ..RemoveMessages([(ref)])
		Quit $$$ERROR($$$GeneralError, "The recording batch has "_count_" failures after "_..#WAITSECONDS_" s, not 50")
	}
	Set snapshot = ..Snapshot(ref, {"count": 50, "dateFormat": "MM/DD/YYYY", "orderDate": "2026-10-16"})
	Do ..RemoveMessages([(ref)])
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set sc = stream.LinkToFile(file)
	If $$$ISERR(sc) Quit sc
	Do snapshot.%ToJSON(stream)
	Quit stream.%Save()
}

/// The JSON file as a dynamic object, or "" when it cannot be read.
ClassMethod ReadJson(file As %String) As %DynamicObject [ Private ]
{
	If '##class(%File).Exists(file) Quit ""
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(file)) Quit ""
	Try {
		Set object = ##class(%DynamicAbstractObject).%FromJSON(stream)
	} Catch {
		Set object = ""
	}
	Quit object
}

/// Polls up to WAITSECONDS for count headers of the reference at the item in the status, and returns the count last seen.
ClassMethod WaitCount(ref As %String, item As %String, status As %Integer, count As %Integer) As %Integer
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	For {
		Set seen = ..Count(ref, item, status)
		If (seen >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.5
	}
	Quit seen
}

/// Whether the Orders production runs in OCUORDERS.
ClassMethod Running() As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Quit ''##class(Ens.Director).IsProductionRunning(.name) && (name = ..#PRODUCTION)
}

/// Sends a batch through the partner in OCUORDERS; "" when it is accepted, else the error text.
ClassMethod Send(count, dateFormat As %String, ref As %String, orderDate As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set sc = ##class(OcuTalon.Demo.Orders.Partner).Send(count, dateFormat, ref, orderDate)
	Quit $Select($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// The number of headers of the reference at the item in the status.
ClassMethod Count(ref As %String, item As %String, status As %Integer) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SuperSession = ? AND TargetConfigName = ? AND Status = ?", ref, item, status)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of different sessions among the headers of the reference.
ClassMethod Sessions(ref As %String) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(DISTINCT SessionId) FROM Ens.MessageHeader WHERE SuperSession = ?", ref)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The headers whose SuperSession is the reference, in order, as dynamic objects: id, sessionId, superSession, source, target,
/// bodyClass, bodyId, status (the number), isError, errorText, type, timeCreated, timeProcessed and the body's own fields.
ClassMethod Headers(ref As %String) As %DynamicArray
{
	Set result = []
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SuperSession = ? ORDER BY ID", ref)
	While rs.%Next() {
		Set header = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID"))
		Set entry = {"id": (header.%Id()), "sessionId": (header.SessionId), "superSession": (header.SuperSession), "source": (header.SourceConfigName), "target": (header.TargetConfigName), "bodyClass": (header.MessageBodyClassName), "bodyId": (header.MessageBodyId), "status": (+header.Status), "type": (+header.Type), "timeCreated": (header.TimeCreated), "timeProcessed": (header.TimeProcessed)}
		Do entry.%Set("isError", header.IsError, "boolean")
		Set entry.errorText = $Select(header.IsError: $Translate($SYSTEM.Status.GetErrorText(header.ErrorStatus), $Char(13, 10), "  "), 1: "")
		Set body = {}
		If header.MessageBodyClassName '= "" {
			Set object = $ClassMethod(header.MessageBodyClassName, "%OpenId", header.MessageBodyId)
			If $IsObject(object) {
				For name = "OrderNumber", "OrderDate", "Sku", "Quantity" {
					Do body.%Set(name, $Property(object, name))
				}
			}
		}
		Set entry.body = body
		Do result.%Push(entry)
	}
	Quit result
}

/// The texts of the event-log rows of Type 2 (Error) for the session at OrdersFromPartner, as a dynamic array.
ClassMethod ErrorTexts(session As %String) As %DynamicArray
{
	Set result = []
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2 AND ConfigName = 'OrdersFromPartner' ORDER BY ID", session)
	While rs.%Next() {
		Do result.%Push(rs.%Get("Text"))
	}
	Quit result
}

/// Resends the header's message to OrdersFromPartner as a copy whose order date is the given one. Returns {id, error}: the new
/// header's id, and the error text or "".
ClassMethod Resend(headerId As %String, date As %String) As %DynamicObject [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
	Set copy = ##class(OcuTalon.Demo.Orders.PartnerOrder).%OpenId(header.MessageBodyId)
	Set copy = copy.%ConstructClone()
	Set copy.OrderDate = date
	Set sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(headerId, .newId, "OrdersFromPartner", copy)
	Quit {"id": ($Get(newId)), "error": ($Select($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc)))}
}

/// Deletes the headers, the bodies and the event-log rows of the sessions of the references, in OCUORDERS.
ClassMethod RemoveMessages(refs As %DynamicArray) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(refs, ..#NAMESPACE)
}

/// The snapshot of the failures of the batch that carries the reference, as one dynamic object (the reader snapshot of Story
/// 0.10, format ocutalon.readerSnapshot/1; times are UTC, written YYYY-MM-DDThh:mm:ssZ):
///   - format, recordedAt, and source {namespace, production, item, batch{count, dateFormat, orderDate}}, the batch as given;
///   - failures: for each header of the reference at OrdersFromPartner in status Error: headerId, sessionId, superSession,
///     timeCreated, timeProcessed, sourceConfigName, targetConfigName, bodyClass, bodyId, status (the display name), isError
///     (the header's own flag), error (the text of the event-log row of Type 2 for the item in the failure's session) and
///     body {OrderNumber, OrderDate, Sku, Quantity};
///   - eventLog: for the sessions of the batch, in order: id, timeLogged, type, configName, sourceClass, sourceMethod,
///     sessionId, text;
///   - items: from the production definition: name, className, enabled, poolSize and settings {name: value}, with the
///     settings whose name holds Credentials, Password, Token or Key (any case) left out;
///   - trace: the headers of the first failure's session, in order: headerId, type, sourceConfigName, targetConfigName,
///     bodyClass, status, isError, timeCreated.
/// Call it in OCUTALON: it switches to OCUORDERS itself, after it has read this class's parameters.
ClassMethod Snapshot(traceRef As %String, batch As %DynamicObject = "") As %DynamicObject
{
	Set snapshot = {"format": "ocutalon.readerSnapshot/1"}
	Set snapshot.recordedAt = $Translate($ZDATETIME($ZTIMESTAMP, 3, 1, 0), " ", "T")_"Z"
	Set snapshot.source = {"namespace": (..#NAMESPACE), "production": (..#PRODUCTION), "item": "PartnerOrdersIn"}
	Set snapshot.source.batch = $Select($IsObject(batch): batch, 1: {})
	Set failures = []
	Set eventLog = []
	Set items = []
	Set trace = []
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SuperSession = ? AND TargetConfigName = 'OrdersFromPartner' AND Status = 8 ORDER BY ID", traceRef)
	While rs.%Next() {
		Set header = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID"))
		Set failure = {"headerId": (header.%Id()), "sessionId": (header.SessionId), "superSession": (header.SuperSession), "timeCreated": ($Translate($Piece(header.TimeCreated, ".", 1), " ", "T")_"Z"), "timeProcessed": ($Translate($Piece(header.TimeProcessed, ".", 1), " ", "T")_"Z"), "sourceConfigName": (header.SourceConfigName), "targetConfigName": (header.TargetConfigName), "bodyClass": (header.MessageBodyClassName), "bodyId": (header.MessageBodyId), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(header.Status))}
		Do failure.%Set("isError", header.IsError, "boolean")
		Set log = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2 AND ConfigName = 'OrdersFromPartner' ORDER BY ID", header.SessionId)
		Set failure.error = $Select(log.%Next(): $Translate(log.%Get("Text"), $Char(13, 10), "  "), 1: "")
		Set object = $ClassMethod(header.MessageBodyClassName, "%OpenId", header.MessageBodyId)
		Set body = {}
		If $IsObject(object) {
			For name = "OrderNumber", "OrderDate", "Sku", "Quantity" {
				Do body.%Set(name, $Property(object, name))
			}
		}
		Set failure.body = body
		Do failures.%Push(failure)
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, TimeLogged, Type, ConfigName, SourceClass, SourceMethod, SessionId, Text FROM Ens_Util.Log WHERE SessionId IN (SELECT SessionId FROM Ens.MessageHeader WHERE SuperSession = ?) ORDER BY ID", traceRef)
	While rs.%Next() {
		Do eventLog.%Push({"id": (rs.%Get("ID")), "timeLogged": ($Translate($Piece(rs.%Get("TimeLogged"), ".", 1), " ", "T")_"Z"), "type": (##class(Ens.DataType.LogType).LogicalToDisplay(rs.%Get("Type"))), "configName": (rs.%Get("ConfigName")), "sourceClass": (rs.%Get("SourceClass")), "sourceMethod": (rs.%Get("SourceMethod")), "sessionId": (rs.%Get("SessionId")), "text": ($Translate(rs.%Get("Text"), $Char(13, 10), "  "))})
	}
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If $IsObject(production) {
		For i = 1:1:production.Items.Count() {
			Set item = production.Items.GetAt(i)
			Set settings = {}
			For j = 1:1:item.Settings.Count() {
				Set setting = item.Settings.GetAt(j)
				Set lower = $ZConvert(setting.Name, "L")
				If (lower [ "credentials") || (lower [ "password") || (lower [ "token") || (lower [ "key") Continue
				Do settings.%Set(setting.Name, setting.Value)
			}
			Do items.%Push({"name": (item.Name), "className": (item.ClassName), "enabled": (item.Enabled), "poolSize": (item.PoolSize), "settings": (settings)})
		}
	}
	If failures.%Size() > 0 {
		Set session = failures.%Get(0).sessionId
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", session)
		While rs.%Next() {
			Set header = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID"))
			Set entry = {"headerId": (header.%Id()), "type": (##class(Ens.DataType.MessageType).LogicalToDisplay(header.Type)), "sourceConfigName": (header.SourceConfigName), "targetConfigName": (header.TargetConfigName), "bodyClass": (header.MessageBodyClassName), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(header.Status)), "timeCreated": ($Translate($Piece(header.TimeCreated, ".", 1), " ", "T")_"Z")}
			Do entry.%Set("isError", header.IsError, "boolean")
			Do trace.%Push(entry)
		}
	}
	Set snapshot.failures = failures
	Set snapshot.eventLog = eventLog
	Set snapshot.items = items
	Set snapshot.trace = trace
	Quit snapshot
}

}
