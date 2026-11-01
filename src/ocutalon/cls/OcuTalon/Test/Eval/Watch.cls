/// Tests of the watch of an evaluation run (Story 9.8; AD-15, AD-18, AD-22, AD-33): WatchOps.EvalWatch, RemoveEvalWatch and Fields, and the two readers
/// of the watch rows that must pass it by. WARM-SAFE: they start no production and send no message. The synthetic rows use the namespace ZZWATCH
/// and the production Zz.Watch.Production, with session Refs from Bridge.Ids.NewRef(); the Orders watch is set up through the real EvalWatch, which
/// asks the reader (OCUORDERS, which every throwaway stack holds). Every row and eval watch a test makes is removed after the test, and the rows of
/// ZZWATCH and the eval rows created since the class began are swept before and after the class.
///   - TestEvalWatch: an Orders watch has the owner eval, Kind production, the reader's namespace, production and display name, AskedBy the current
///     user, CreatedAt now, NextDueAt EVALNEXTDUE and empty run fields; fields equals Fields(row); each call writes its own row; no CheckChanged
///     message header was created;
///   - TestEvalWatchRefused: an unknown production, an unknown namespace and blank values are refused with error 5001 and MESSAGEUNKNOWN, with no row;
///   - TestFields: FIELDS holds exactly the stored properties of BackgroundCheck, and Fields reports them in that order;
///   - TestRemove: RemoveEvalWatch removes a row of owner eval only, answers OK and removed 0 for a row that is gone, and refuses another owner's
///     row, which stays;
///   - TestNotPolled: FailurePoller.Watched lists no production that only an eval row names, and counts only the other rows' CreatedAt;
///   - TestNeverDue: the Checks rule (a ZzChecks shadow instance) finds an eval watch due at no tick, and a row due in 2999 at a tick of 2999;
///   - TestStopRefusedForEval: a StopWatch with the SessionRef eval, given to the real OnStop through a shadow instance of the WatchOps probe
///     (OcuTalon.Test.Watch.OpsProbe, which records each CheckChanged it is asked to send), answers no_session, leaves the row as it was and sends
///     no CheckChanged.
Class OcuTalon.Test.Eval.Watch Extends %UnitTest.TestCase
{

/// The double of Checks.Process, and the operation under test.
Parameter CHECKS = "OcuTalon.Test.Eval.ZzChecks";

Parameter OPS = "OcuTalon.Watch.Ops";

/// The WatchOps whose sends to Checks are recorded: a shadow instance of the real WatchOps cannot send, so only the probe shows an attempted send.
Parameter PROBE = "OcuTalon.Test.Watch.OpsProbe";

/// The namespace and the production of the synthetic rows.
Parameter NAMESPACE = "ZZWATCH";

Parameter PRODUCTION = "Zz.Watch.Production";

/// The Refs of the eval watches that the test set up, comma-separated: removed after the test through RemoveEvalWatch.
Property Evals As %String(MAXLEN = "");

/// The IDs of the synthetic rows that the test saved, comma-separated: removed after the test.
Property Rows As %String(MAXLEN = "");

/// The largest message header ID when the test began.
Property HeaderMark As %Integer;

/// The time the class began (UTC, YYYY-MM-DDThh:mm:ssZ): the eval rows created since are the class's own.
Property Begun As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Begun = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Sweep("")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Evals = "", ..Rows = ""
	Set ..HeaderMark = ..MaxHeader()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Evals, ",") {
		Set ref = $Piece(..Evals, ",", i)
		If ref '= "" Do ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(ref)
	}
	For i = 1:1:$Length(..Rows, ",") {
		Set id = $Piece(..Rows, ",", i)
		If id '= "" Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	}
	Quit $$$OK
}

/// The class leaves nothing: no row of ZZWATCH and no eval watch created since the class began. The status names what was left, which is then removed.
Method OnAfterAllTests() As %Status
{
	Set left = ..Sweep(..Begun)
	Quit $Select(left = 0: $$$OK, 1: $SYSTEM.Status.Error(5001, "The class left "_left_" watch row(s)"))
}

/// An Orders watch for an evaluation run has every field the convention says, and sends nothing.
Method TestEvalWatch()
{
	Set ops = ..#OPS
	Set demo = "OcuTalon.Install.Step.Demo"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Do $$$AssertTrue(##class(OcuTalon.Watch.Reader).Admits(namespace, production, .display), "control: the reader admits the Orders production")
	Do $$$AssertEquals(display, "Orders", "with the display name Orders")
	Set begun = ##class(OcuTalon.Data.Time).NowUtc()
	Set before = ..Eval(namespace, production)
	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch(namespace, production, .fields)
	Do $$$AssertStatusOK(sc, "EvalWatch sets up a watch of the Orders production")
	If '$IsObject(fields) Quit
	Do ..Track(fields.%Get("Ref"))
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(fields.%Get("Ref"))
	Do $$$AssertTrue($IsObject(row), "the row is there")
	If '$IsObject(row) Quit
	Do $$$AssertEquals($Length(row.Ref), 22, "its Ref is a new 22-character Ref")
	Do $$$AssertEquals(row.SessionRef_"|"_row.Kind_"|"_row.Namespace_"|"_row.Production, "eval|"_$Parameter(ops, "KIND")_"|"_namespace_"|"_production, "its owner is eval, its Kind production, and it names the Orders production")
	Do $$$AssertEquals(row.DisplayName, display, "its display name is the reader's")
	Do $$$AssertEquals(row.AskedBy, $Username, "it was asked by the current user")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a UTC time: "_row.CreatedAt)
	Do $$$AssertTrue('(begun ] row.CreatedAt) && '(row.CreatedAt ] ##class(OcuTalon.Data.Time).NowUtc()), "and it is the time of the call: "_row.CreatedAt)
	Do $$$AssertEquals(row.NextDueAt, $Parameter(ops, "EVALNEXTDUE"), "NextDueAt is EVALNEXTDUE")
	Do $$$AssertEquals(row.NextDueAt, "9999-12-31T23:59:59Z", "which is the last second of the year 9999")
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result_"|"_row.Finding_"|"_row.LastRunHeaderId, "|||", "the run fields are empty")
	Do $$$AssertEquals(fields.%ToJSON(), ##class(OcuTalon.Watch.Ops).Fields(row).%ToJSON(), "fields is what Fields gives for the stored row")
	Do $$$AssertEquals(..CheckChanged(), 0, "no CheckChanged message header was created")

	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch(namespace, production, .again)
	Do $$$AssertStatusOK(sc, "a second call also succeeds")
	If $IsObject(again) {
		Do ..Track(again.%Get("Ref"))
		Do $$$AssertTrue(again.%Get("Ref") '= fields.%Get("Ref"), "and writes its own row")
		Do $$$AssertEquals(..Eval(namespace, production), before + 2, "so the production has two more eval watch rows")
	}
	Do $$$AssertEquals(..CheckChanged(), 0, "still no CheckChanged message header")
}

/// A production that the reader does not admit, and blank values, are refused with error 5001 and the sentence of MESSAGEUNKNOWN, and leave no row.
Method TestEvalWatchRefused()
{
	Set ops = ..#OPS
	Set demo = "OcuTalon.Install.Step.Demo"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Set before = ..Eval("", "")
	For case = $ListBuild(namespace, "Zz.Watch.Nothing"), $ListBuild(..#NAMESPACE, production), $ListBuild("", production), $ListBuild(namespace, ""), $ListBuild("", "") {
		Set label = $List(case, 1)_"/"_$List(case, 2)
		Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch($List(case, 1), $List(case, 2), .fields)
		Do $$$AssertTrue($$$ISERR(sc), label_": it is refused")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, label_": with error 5001")
		Do $$$AssertTrue($SYSTEM.Status.GetOneStatusText(sc) [ $Parameter(ops, "MESSAGEUNKNOWN"), label_": and the sentence of MESSAGEUNKNOWN")
		Do $$$AssertEquals($IsObject(fields), 0, label_": fields is not an object")
	}
	Do $$$AssertEquals(..Eval("", ""), before, "no row was written")
}

/// FIELDS is every stored property of BackgroundCheck: the properties that are neither transient nor calculated, and whose name does not start with %. Fields
/// reports them in the order of FIELDS.
Method TestFields()
{
	Set fields = $ListFromString($Parameter(..#OPS, "FIELDS"))
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Transient = 0 AND Calculated = 0", "OcuTalon.Data.BackgroundCheck")
	Do $$$AssertEquals(rs.%SQLCODE < 0, 0, "control: the class dictionary is read")
	Kill stored
	While rs.%Next() {
		Set name = rs.%Get("Name")
		If $Extract(name) '= "%" Set stored(name) = ""
	}
	Set missing = "", extra = "", position = 0, count = 0
	While $ListNext(fields, position, name) {
		Set count = count + 1
		If '$Data(stored(name)) Set missing = missing_" "_name
		Kill stored(name)
	}
	Set name = ""
	For {
		Set name = $Order(stored(name))
		If name = "" Quit
		Set extra = extra_" "_name
	}
	Do $$$AssertTrue(count >= 13, "FIELDS names at least the 13 properties of the row: "_count)
	Do $$$AssertEquals(missing, "", "FIELDS names no property that BackgroundCheck does not store")
	Do $$$AssertEquals(extra, "", "and every stored property of BackgroundCheck is in FIELDS")

	Set id = ..Row("eval", "zz")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%OpenId(id)
	Set order = "", iterator = ##class(OcuTalon.Watch.Ops).Fields(row).%GetIterator()
	While iterator.%GetNext(.key) {
		Set order = order_$Select(order = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(order, $Parameter(..#OPS, "FIELDS"), "Fields has one member for each name of FIELDS, in that order")
}

/// RemoveEvalWatch removes the row of an evaluation run and no other: a row that is gone is OK with removed 0, another owner's row is refused and stays,
/// and no other row is touched.
Method TestRemove()
{
	Set ops = ..#OPS
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set a = ..Row(eval, "a"), b = ..Row(eval, "b"), c = ..Row(eval, "c"), s = ..Row(session, "s")
	Set refA = ..RefOf(a), refB = ..RefOf(b), refC = ..RefOf(c), refS = ..RefOf(s)
	Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(b)
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).%ExistsId(b), 0, "control: the row b is already gone")

	Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(refA, .removed)
	Do $$$AssertStatusOK(sc, "RemoveEvalWatch removes the row a")
	Do $$$AssertEquals(removed_"|"_##class(OcuTalon.Data.BackgroundCheck).%ExistsId(a), "1|0", "removed is 1 and the row is gone")
	Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(refB, .removed)
	Do $$$AssertStatusOK(sc, "a row that is already gone is no error")
	Do $$$AssertEquals(removed, 0, "and removed is 0")
	Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(refA, .removed)
	Do $$$AssertStatusOK(sc, "the row a again is no error")
	Do $$$AssertEquals(removed, 0, "and removed is 0")
	For ref = "", "zz-no-such-ref" {
		Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(ref, .removed)
		Do $$$AssertStatusOK(sc, "'"_ref_"' is no error")
		Do $$$AssertEquals(removed, 0, "and removes nothing")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).%ExistsId(c), 1, "the other eval row c was not touched")

	Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(refS, .removed)
	Do $$$AssertTrue($$$ISERR(sc), "the Ref of a session's row is refused")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, "with error 5001")
	Do $$$AssertTrue($SYSTEM.Status.GetOneStatusText(sc) [ $Parameter(ops, "MESSAGENOTEVAL"), "and the sentence of MESSAGENOTEVAL")
	Do $$$AssertEquals(removed_"|"_##class(OcuTalon.Data.BackgroundCheck).%ExistsId(s), "0|1", "removed is 0 and the session's row stays")
}

/// FailurePoller polls a production only for the rows of the other owners: a production that only an eval row names is not listed, and the CreatedAt of an
/// eval row does not count in the earliest.
Method TestNotPolled()
{
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	Set id = ..Row(eval, "e", "2020-01-01T00:00:00Z")
	Set entries = ..Listed()
	Do $$$AssertEquals(entries.%Size(), 0, "a production that only an eval row names is not listed")
	Set sid = ..Row(##class(OcuTalon.Bridge.Ids).NewRef(), "s", "2020-06-01T00:00:00Z")
	Set entries = ..Listed()
	Do $$$AssertEquals(entries.%Size(), 1, "with a session's row it is listed once")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).created, "2020-06-01T00:00:00Z", "and created is the session's CreatedAt, not the older eval row's")
	Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	Set entries = ..Listed()
	Do $$$AssertEquals(entries.%Size(), 1, "control: without the eval row the production is listed")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).created, "2020-06-01T00:00:00Z", "with the same created")
}

/// Checks never finds an eval watch due: at the time now, and at a tick in 2999, the row of an evaluation run is not among the due rows, while a control row
/// due on 2999-01-01 is due at the tick of 2999 and not now.
Method TestNeverDue()
{
	Set demo = "OcuTalon.Install.Step.Demo"
	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch($Parameter(demo, "NAMESPACE"), $Parameter(demo, "PRODUCTION"), .fields)
	Do $$$AssertStatusOK(sc, "an Orders watch is set up")
	If '$IsObject(fields) Quit
	Do ..Track(fields.%Get("Ref"))
	Set control = ..Row(##class(OcuTalon.Bridge.Ids).NewRef(), "d", "2020-01-01T00:00:00Z", "2999-01-01T00:00:00Z")
	Set controlRef = ..RefOf(control)
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#CHECKS, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the Checks double is made")
	If '$IsObject(host) Quit
	Set due = ..Refs(host.DueAt(##class(OcuTalon.Data.Time).NowUtc()))
	Do $$$AssertEquals($Find(due, ","_fields.%Get("Ref")_",")_"|"_$Find(due, ","_controlRef_","), "0|0", "at the time now neither the eval watch nor the control row is due")
	Set due = ..Refs(host.DueAt("2999-12-31T23:59:59Z"))
	Do $$$AssertTrue($Find(due, ","_controlRef_",") > 0, "at a tick in 2999 the control row is due")
	Do $$$AssertEquals($Find(due, ","_fields.%Get("Ref")_","), 0, "and the eval watch is not")
	Set due = ..Refs(host.DueAt("9999-12-31T00:00:00Z"))
	Do $$$AssertEquals($Find(due, ","_fields.%Get("Ref")_","), 0, "nor at a tick in the last year")
}

/// A StopWatch of the owner eval for the Orders production, given to the real OnStop of a shadow instance of the WatchOps probe, answers no_session with
/// Ok 0, the eval watch row is as it was, and the probe recorded no CheckChanged.
Method TestStopRefusedForEval()
{
	Set demo = "OcuTalon.Install.Step.Demo"
	Set namespace = $Parameter(demo, "NAMESPACE"), production = $Parameter(demo, "PRODUCTION")
	Set sc = ##class(OcuTalon.Watch.Ops).EvalWatch(namespace, production, .fields)
	Do $$$AssertStatusOK(sc, "an Orders watch is set up")
	If '$IsObject(fields) Quit
	Do ..Track(fields.%Get("Ref"))
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the WatchOps probe is made")
	If '$IsObject(host) Quit
	Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set command.SessionRef = ##class(OcuTalon.Data.Ownership).#EVAL
	Set command.Namespace = namespace
	Set command.Production = production
	Do $$$AssertStatusOK(host.OnStop(command, .response), "OnStop answers OK")
	Do $$$AssertTrue($IsObject(response), "with a CommandResult")
	If $IsObject(response) Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", "which says no_session")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(fields.%Get("Ref"))
	Do $$$AssertTrue($IsObject(row), "the eval watch is still there")
	If $IsObject(row) Do $$$AssertEquals(##class(OcuTalon.Watch.Ops).Fields(row).%ToJSON(), fields.%ToJSON(), "and equals its setup record")
	Do $$$AssertEquals($Select($IsObject(host.Changes): host.Changes.%Size(), 1: 0), 0, "and OnStop asked for no CheckChanged")
}

/// --- helpers ---
/// Remembers the Ref of an eval watch for the clean-up.
Method Track(ref As %String) [ Private ]
{
	Set ..Evals = ..Evals_$Select(..Evals = "": "", 1: ",")_ref
}

/// Saves a watch row of Kind production for the synthetic production, owned by owner, with the times given (CreatedAt in 2020 and NextDueAt in the year
/// 9999 by default, so that the real Checks never runs it), and remembers it for the clean-up. Returns its ID.
Method Row(owner As %String, tag As %String, createdAt As %String = "2020-01-01T00:00:00Z", nextDueAt As %String = "9999-12-30T00:00:00Z") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = owner
	Set row.Kind = $Parameter(..#OPS, "KIND")
	Set row.Namespace = ..#NAMESPACE
	Set row.Production = ..#PRODUCTION
	Set row.DisplayName = "Zz watch "_tag
	Set row.AskedBy = "zz-user"
	Set row.CreatedAt = createdAt
	Set row.NextDueAt = nextDueAt
	Do $$$AssertStatusOK(row.%Save(), tag_": the synthetic row is saved")
	Set ..Rows = ..Rows_$Select(..Rows = "": "", 1: ",")_row.%Id()
	Quit row.%Id()
}

/// The Ref of the row.
ClassMethod RefOf(id As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%OpenId(id)
	Quit $Select($IsObject(row): row.Ref, 1: "")
}

/// The entries of FailurePoller.Watched that name the synthetic production.
ClassMethod Listed() As %DynamicArray [ Private ]
{
	Set entries = []
	Set iterator = ##class(OcuTalon.Watch.FailurePoller).Watched().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = ..#NAMESPACE) && (entry.production = ..#PRODUCTION) Do entries.%Push(entry)
	}
	Quit entries
}

/// The Refs of the due rows as ",ref1,ref2,", so that a Ref is found with its commas.
ClassMethod Refs(due As %DynamicArray) As %String [ Private ]
{
	Set text = ","
	Set iterator = due.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_one.ref_","
	}
	Quit text
}

/// The number of eval watch rows of the namespace and production, or, with no namespace, of all of them.
ClassMethod Eval(namespace As %String, production As %String) As %Integer [ Private ]
{
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	If namespace = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", eval)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? AND Namespace = ? AND Production = ?", eval, namespace, production)
	}
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The largest ID of the message headers, or 0.
ClassMethod MaxHeader() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of CheckChanged message headers created since the test began.
Method CheckChanged() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Checks.Msg.CheckChanged'", ..HeaderMark)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Deletes the rows of the synthetic namespace and, when begun is not empty, the eval watch rows created at or after it. Returns how many were deleted.
ClassMethod Sweep(begun As %String) As %Integer [ Private ]
{
	Kill ids
	If begun = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ?", ..#NAMESPACE)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ? OR (SessionRef = ? AND CreatedAt >= ?)", ..#NAMESPACE, ##class(OcuTalon.Data.Ownership).#EVAL, begun)
	}
	While result.%Next() {
		Set ids(result.%Get("ID")) = ""
	}
	Set count = 0, id = ""
	For {
		Set id = $Order(ids(id))
		If id = "" Quit
		Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
		Set count = count + 1
	}
	Quit count
}

}
