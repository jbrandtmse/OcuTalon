/// Tests of the isolation of the evaluation run's watch from the watches of every other owner (Story 9.8; AD-15, AD-18, AD-22, AD-33). WARM-SAFE: they
/// start no production and send no message. The synthetic rows use the namespace ZZOWNERS and the productions Zz.Owners.Production.<tag>; the rows are never
/// due (NextDueAt in the year 9999 unless a test reads the rule at a tick in 2999), and every row and fixture session a test makes is removed after the
/// test, and the rows of ZZOWNERS are swept before and after the class.
///   - TestOtherOwnersPolled: FailurePoller.Watched lists a production for a row of a session, of the owner instance and of no owner, with the earliest
///     CreatedAt of those rows and in the order of the namespace and the production, and lists no production that only an eval row names;
///   - TestOtherOwnersDue: the Checks rule (a ZzChecks shadow instance) finds the rows of a session, of the owner instance and of no owner due at a tick
///     in 2999 one by one as their NextDueAt says, and never the eval row (NextDueAt EVALNEXTDUE), which sits beside them;
///   - TestOnlySessionsStop: a stop of a session removes its own row and sends the one CheckChanged (Stopped 1, the row's Ref and production), and
///     leaves the eval row and the instance row of the same production as they were; a stop of the owner eval, of the owner instance, and of a session
///     that has no row for the production, removes nothing and sends nothing;
///   - TestRemoveRefusesEveryOtherOwner: RemoveEvalWatch and EvalIn.Finish refuse the rows of the owner instance, of no owner and of a session, which
///     stay as they were;
///   - TestStartRefusedGivesNoWatches: a Start that the director refuses gives an empty array of setup records, never no array.
Class OcuTalon.Test.Eval.WatchOwners Extends %UnitTest.TestCase
{

/// The double of Checks.Process, the operation under test and the WatchOps whose sends to Checks are recorded.
Parameter CHECKS = "OcuTalon.Test.Eval.ZzChecks";

Parameter OPS = "OcuTalon.Watch.Ops";

Parameter PROBE = "OcuTalon.Test.Watch.OpsProbe";

/// The namespace of the synthetic rows and the start of their productions.
Parameter NAMESPACE = "ZZOWNERS";

Parameter PRODUCTION = "Zz.Owners.Production";

/// The IDs of the synthetic rows that the test saved, comma-separated: removed after the test.
Property Rows As %String(MAXLEN = "");

/// The Refs of the fixture sessions that the test made, comma-separated: removed after the test.
Property Sessions As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ..Sweep()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Rows = "", ..Sessions = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set id = $Piece(..Rows, ",", i)
		If id '= "" Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	}
	If ..Sessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Quit $$$OK
}

/// The class leaves nothing: no row of ZZOWNERS. The status names what was left, which is then removed.
Method OnAfterAllTests() As %Status
{
	Set left = ..Sweep()
	Quit $Select(left = 0: $$$OK, 1: $SYSTEM.Status.Error(5001, "The class left "_left_" watch row(s)"))
}

/// A row of a session, of the owner instance and of no owner is polled as it was before the eval watch existed: each production is listed once, created is
/// the earliest CreatedAt of its rows (the eval row's older time does not count), and the order is the namespace and the production. A production that only
/// an eval row names is not listed.
Method TestOtherOwnersPolled()
{
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	Set instance = ##class(OcuTalon.Data.Ownership).#INSTANCE
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Row(eval, "A", "2019-01-01T00:00:00Z")
	Do ..Row(session, "A", "2020-06-01T00:00:00Z")
	Do ..Row(instance, "A", "2020-03-01T00:00:00Z")
	Do ..Row(instance, "B", "2020-04-01T00:00:00Z")
	Do ..Row("", "C", "2020-05-01T00:00:00Z")
	Do ..Row(eval, "D", "2019-02-01T00:00:00Z")
	Do $$$AssertEquals(..Listed(), "A=2020-03-01T00:00:00Z;B=2020-04-01T00:00:00Z;C=2020-05-01T00:00:00Z", "the productions of a session, an instance row and a row with no owner are listed in order with the earliest CreatedAt of their rows, and D, which only an eval row names, is not")
}

/// The rows of a session, of the owner instance and of no owner are due when their NextDueAt says so, with an eval row beside them that is due at no tick.
Method TestOtherOwnersDue()
{
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	Set instance = ##class(OcuTalon.Data.Ownership).#INSTANCE
	Set sessionRow = ..Row(##class(OcuTalon.Bridge.Ids).NewRef(), "S", , "2999-01-01T00:00:00Z")
	Set instanceRow = ..Row(instance, "I", , "2999-01-02T00:00:00Z")
	Set noneRow = ..Row("", "N", , "2999-01-03T00:00:00Z")
	Set evalRow = ..Row(eval, "E", , $Parameter(..#OPS, "EVALNEXTDUE"))
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#CHECKS, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the Checks double is made")
	If '$IsObject(host) Quit
	Set s = ..RefOf(sessionRow), i = ..RefOf(instanceRow), n = ..RefOf(noneRow), e = ..RefOf(evalRow)
	Do $$$AssertEquals(..Due(host, ##class(OcuTalon.Data.Time).NowUtc(), s_","_i_","_n_","_e), "", "at the time now none of the four rows is due")
	Do $$$AssertEquals(..Due(host, "2999-01-01T00:00:00Z", s_","_i_","_n_","_e), "S", "at the first tick in 2999 the session's row is due and the others are not")
	Do $$$AssertEquals(..Due(host, "2999-01-02T00:00:00Z", s_","_i_","_n_","_e), "S,I", "a day later the instance row is due too")
	Do $$$AssertEquals(..Due(host, "2999-12-31T23:59:59Z", s_","_i_","_n_","_e), "S,I,N", "at the last tick of 2999 the row with no owner is due as well, and the eval row is still not")
	Do $$$AssertEquals(..Due(host, "9999-12-31T00:00:00Z", s_","_i_","_n_","_e), "S,I,N", "nor is it at a tick in the year 9999")
}

/// Only a session with a Session row stops a watch, and its stop sends the one CheckChanged: the row of the session goes, the eval row and the instance
/// row of the same production stay as they were, and a stop of the owner eval, of the owner instance, or of a session with no row for the production
/// removes nothing and sends nothing.
Method TestOnlySessionsStop()
{
	Set eval = ##class(OcuTalon.Data.Ownership).#EVAL
	Set instance = ##class(OcuTalon.Data.Ownership).#INSTANCE
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the WatchOps probe is made")
	If '$IsObject(host) Quit
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzowners")
	Set ..Sessions = session
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session("zzowners2")
	Set ..Sessions = ..Sessions_","_other
	Set own = ..Row(session, "S")
	Set evalRow = ..Row(eval, "S"), instanceRow = ..Row(instance, "S")
	Set ownRef = ..RefOf(own)
	Set evalBefore = ..Json(evalRow), instanceBefore = ..Json(instanceRow)

	Do $$$AssertStatusOK(host.OnStop(..Stop(other, "S"), .response), "a stop of a session that has no row for the production is answered")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_watching", "it says not_watching")
	Do $$$AssertEquals(..Sent(host), 0, "and sends nothing")
	Do $$$AssertEquals(..Json(evalRow)_"|"_..Json(instanceRow), evalBefore_"|"_instanceBefore, "the eval row and the instance row of the production are as they were")

	Do $$$AssertStatusOK(host.OnStop(..Stop(session, "S"), .response), "the stop of the session that watches is answered")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "1|stopped|"_ownRef, "it says stopped, with the Ref of its row")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).%ExistsId(own), 0, "the session's row is gone")
	Do $$$AssertEquals(..Sent(host), 1, "control: the stop of a session's row sent one CheckChanged")
	If ..Sent(host) = 1 {
		Set change = host.Changes.%Get(0)
		Do $$$AssertEquals(change.checkRef_"|"_change.sessionRef_"|"_change.stopped_"|"_change.namespace_"|"_change.production, ownRef_"|"_session_"|1|"_..#NAMESPACE_"|"_..Prod("S"), "for its Ref, the session, Stopped 1 and the production")
	}
	Do $$$AssertEquals(..Json(evalRow)_"|"_..Json(instanceRow), evalBefore_"|"_instanceBefore, "the eval row and the instance row are still as they were")

	Do $$$AssertStatusOK(host.OnStop(..Stop(session, "S"), .response), "a second stop of the same session is answered")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|not_watching", "it says not_watching, though the production has an eval row and an instance row")
	For owner = eval, instance {
		Do $$$AssertStatusOK(host.OnStop(..Stop(owner, "S"), .response), owner_": a stop is answered")
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|no_session", owner_": it says no_session")
	}
	Do $$$AssertEquals(..Sent(host), 1, "no other stop sent a CheckChanged")
	Do $$$AssertEquals(..Json(evalRow)_"|"_..Json(instanceRow), evalBefore_"|"_instanceBefore, "and the eval row and the instance row are as they were")
}

/// RemoveEvalWatch and EvalIn.Finish remove the watch of an evaluation run only: the row of the owner instance, of no owner and of a session each answer
/// error 5001 with MESSAGENOTEVAL, stay as they were, and a Finish that is given their Refs gives the first error.
Method TestRemoveRefusesEveryOtherOwner()
{
	Set instance = ##class(OcuTalon.Data.Ownership).#INSTANCE
	Set rows = $ListBuild(..Row(instance, "I"), ..Row("", "N"), ..Row(##class(OcuTalon.Bridge.Ids).NewRef(), "S"))
	Set labels = $ListBuild("the instance row", "the row with no owner", "the session's row")
	Set position = 0, records = []
	While $ListNext(rows, position, id) {
		Set label = $List(labels, $Increment(number))
		Set before = ..Json(id), ref = ..RefOf(id)
		Do records.%Push({"case": "zz-owners", "watch": ({}.%FromJSON(before))})
		Set sc = ##class(OcuTalon.Watch.Ops).RemoveEvalWatch(ref, .removed)
		Do $$$AssertTrue($$$ISERR(sc), label_": RemoveEvalWatch refuses it")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, label_": with error 5001")
		Do $$$AssertTrue($SYSTEM.Status.GetOneStatusText(sc) [ $Parameter(..#OPS, "MESSAGENOTEVAL"), label_": and the sentence of MESSAGENOTEVAL")
		Do $$$AssertEquals(removed_"|"_(..Json(id) = before), "0|1", label_": removed is 0 and the row is as it was")
	}
	Set sc = ##class(OcuTalon.Eval.In).Finish(records)
	Do $$$AssertTrue($$$ISERR(sc), "Finish refuses records that name those rows")
	Do $$$AssertTrue($SYSTEM.Status.GetOneStatusText(sc) [ $Parameter(..#OPS, "MESSAGENOTEVAL"), "with MESSAGENOTEVAL")
	Set position = 0, left = 0
	While $ListNext(rows, position, id) {
		Set left = left + ##class(OcuTalon.Data.BackgroundCheck).%ExistsId(id)
	}
	Do $$$AssertEquals(left, 3, "and the three rows are still there")
}

/// A Start that the director refuses (EvalIn is disabled in a throwaway that was not started for an evaluation) gives an empty array of setup records, and
/// no run Ref, no case sent and no skipped case. Where EvalIn is enabled, Start would run, so this test calls none; and Start is given a folder that holds no
/// case, so a stack where EvalIn runs although its Enabled setting is not 1 fails the test and sends nothing.
Method TestStartRefusedGivesNoWatches()
{
	Set id = "OcuTalon.Production||EvalIn||*||Enabled"
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) && (##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue = 1) {
		Do $$$LogMessage("EvalIn is enabled on this stack: Start would send the evaluation set, so this test calls none")
		Quit
	}
	Set empty = ##class(%File).NormalizeDirectory("zzwatchowners-no-cases", ##class(%File).NormalizeDirectory("Temp", $SYSTEM.Util.ManagerDirectory()))
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(empty), "control: the folder given to Start does not exist, so it holds no case")
	Set watches = "not an array"
	Set sc = ##class(OcuTalon.Eval.In).Start(empty, , .runRef, .sent, .skipped, .watches)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "Start is refused")
	Do $$$AssertEquals(runRef_"|"_sent_"|"_skipped.%Size(), "|0|0", "there is no run Ref, nothing was sent and no case is listed")
	Do $$$AssertTrue($IsObject(watches) && watches.%IsA("%Library.DynamicArray"), "watches is a dynamic array")
	If $IsObject(watches) && watches.%IsA("%Library.DynamicArray") Do $$$AssertEquals(watches.%Size(), 0, "and it is empty")
	Do $$$AssertStatusOK(##class(OcuTalon.Eval.In).Finish(watches), "so Finish can be given it")
}

/// --- helpers ---
/// The production of the tag, below the synthetic namespace.
ClassMethod Prod(tag As %String) As %String [ Private ]
{
	Quit ..#PRODUCTION_"."_tag
}

/// Saves a watch row of Kind production for the production of the tag, owned by owner, with the times given (CreatedAt in 2020 and NextDueAt in the year 9999
/// by default, so that the real Checks never runs it), and remembers it for the clean-up. Returns its ID.
Method Row(owner As %String, tag As %String, createdAt As %String = "2020-01-01T00:00:00Z", nextDueAt As %String = "9999-12-30T00:00:00Z") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = owner
	Set row.Kind = $Parameter(..#OPS, "KIND")
	Set row.Namespace = ..#NAMESPACE
	Set row.Production = ..Prod(tag)
	Set row.DisplayName = "Zz owners "_tag
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

/// The stored fields of the row as JSON text, or "gone" when there is none.
ClassMethod Json(id As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).%OpenId(id)
	Quit $Select($IsObject(row): ##class(OcuTalon.Watch.Ops).Fields(row).%ToJSON(), 1: "gone")
}

/// The entries of FailurePoller.Watched that name the synthetic namespace, as "<tag>=<created>" joined by semicolons.
ClassMethod Listed() As %String [ Private ]
{
	Set text = ""
	Set iterator = ##class(OcuTalon.Watch.FailurePoller).Watched().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.namespace = ..#NAMESPACE Set text = text_$Select(text = "": "", 1: ";")_$Piece(entry.production, ".", *)_"="_entry.created
	}
	Quit text
}

/// The tags (the last piece of the row's production) of the rows among the Refs (comma-separated) that the Checks rule finds due at the tick, joined by commas
/// in the order of the Refs given.
ClassMethod Due(host As OcuTalon.Test.Eval.ZzChecks, tickAt As %String, refs As %String) As %String [ Private ]
{
	Kill due
	Set iterator = host.DueAt(tickAt).%GetIterator()
	While iterator.%GetNext(, .one) {
		Set due(one.ref) = $Piece(one.production, ".", *)
	}
	Set text = ""
	For i = 1:1:$Length(refs, ",") {
		Set ref = $Piece(refs, ",", i)
		If $Data(due(ref)) Set text = text_$Select(text = "": "", 1: ",")_due(ref)
	}
	Quit text
}

/// A StopWatch for the session and the production of the tag.
ClassMethod Stop(session As %String, tag As %String) As OcuTalon.Msg.Command.StopWatch [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set command.SessionRef = session
	Set command.Namespace = ..#NAMESPACE
	Set command.Production = ..Prod(tag)
	Quit command
}

/// The number of CheckChanged messages that the probe recorded.
ClassMethod Sent(host As OcuTalon.Test.Watch.OpsProbe) As %Integer [ Private ]
{
	Quit $Select($IsObject(host.Changes): host.Changes.%Size(), 1: 0)
}

/// Deletes the rows of the synthetic namespace. Returns how many were deleted.
ClassMethod Sweep() As %Integer [ Private ]
{
	Kill ids
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.BackgroundCheck WHERE Namespace = ?", ..#NAMESPACE)
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
