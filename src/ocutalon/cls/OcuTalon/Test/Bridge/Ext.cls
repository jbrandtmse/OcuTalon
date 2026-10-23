/// Tests of the bridge's extension points and of its per-call context (Story 0.6, matrix rows 2, 6 and 7). Nothing starts
/// a production, and nothing is written to the audit log.
///   - TestAccessorInAnotherJob: a job that did not start the production reads the three extension classes of Decide
///     from the production definition, and gets "" with an error for a bad setting, item, production or class;
///   - TestValueFor: the accessor's general read of a host setting of the Decide item, and its errors (Story 1.4);
///   - TestExtensionBases: HostSink lists exactly its eight event types, accepts each, builds its three payloads with
///     exactly their keys, and BridgeSink adds nothing and publishes no live event; the reply filter and ReplyGuard pass
///     text through and Classification classifies nothing;
///   - TestWriteDefault (Story 1.7): WriteDefault creates the System Default Settings row of a setting (any class) with the value and the
///     description, changes the row when it exists, and ValueFor reads the value;
///   - TestContext: no context before Begin; Begin carries the request's fields and the SuperSession into Current; the
///     process-private context is invisible to another job; Put changes it; End removes it.
/// The run's number is n from ^OcuTalonTest("BridgeExt","n") (never reset); the child jobs report through
/// ^OcuTalonTest("BridgeExt",n,...), which OnBeforeAllTests and OnAfterAllTests delete with the reports of earlier runs.
Class OcuTalon.Test.Bridge.Ext Extends %UnitTest.TestCase
{

/// The production whose definition the accessor reads.
Parameter PRODUCTION = "OcuTalon.Production";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Set ..Number = $Increment(^OcuTalonTest("BridgeExt", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Quit $SYSTEM.Status.OK()
}

/// Row 2: from another job, ClassFor gives the host sink, the reply filter and the classification class that the
/// definition names (the last through the initial value of its setting), and gives "" with an error status for the
/// setting ZzClass, the item Zz<n>, the production Zz<n>.Production, and, for Check, a class that does not extend its
/// base, an empty class and a class that does not exist.
Method TestAccessorInAnotherJob()
{
	Set run = $Name(^OcuTalonTest("BridgeExt", ..Number))
	Kill @run
	Job ##class(OcuTalon.Test.Bridge.Ext).AccessorProbe(..Number, ..#PRODUCTION)
	Do ..WaitFor($Name(@run@("done")), 1, 60)
	Do $$$AssertEquals($Get(@run@("done")), 1, "the job finished")
	Do $$$AssertEquals($Get(@run@("namespace")), $Namespace, "the job ran in this namespace")
	Do $$$AssertEquals($Get(@run@("HostSinkClass")), "OcuTalon.Core.BridgeSink|1", "HostSinkClass is OcuTalon.Core.BridgeSink")
	Do $$$AssertEquals($Get(@run@("ReplyFilterClass")), "OcuTalon.Checks.ReplyGuard|1", "ReplyFilterClass is OcuTalon.Checks.ReplyGuard")
	Do $$$AssertEquals($Get(@run@("ClassificationClass")), "OcuTalon.Bridge.Ext.Classification|1", "ClassificationClass is OcuTalon.Bridge.Ext.Classification")
	For case = "setting", "item", "production", "check", "checkEmpty", "checkMissing" {
		Do $$$AssertEquals($Get(@run@(case)), "|0", "the "_case_" case gives an empty class and an error status")
	}
	Do $$$AssertTrue($Get(@run@("checkText")) [ "does not extend", "the error of the check names the problem: "_$Get(@run@("checkText")))
	Do $$$AssertTrue($Get(@run@("checkEmptyText")) [ "names no class", "an empty class is refused as such: "_$Get(@run@("checkEmptyText")))
	Do $$$AssertTrue($Get(@run@("checkMissingText")) [ "is not compiled", "a class that does not exist is refused as such: "_$Get(@run@("checkMissingText")))
	Kill @run
}

/// WriteDefault (the one writer of System Default Settings rows, AD-19): a row of the Decide item of the example production (which no one starts)
/// is created with the value and the description for any host class, ValueFor then reads the value, and a second write changes the same row
/// instead of making another. The row is deleted again.
Method TestWriteDefault()
{
	Set accessor = "OcuTalon.Bridge.Ext.Accessor"
	Set production = "OcuTalon.BridgeExample.Production"
	Set id = production_"||Decide||*||TimerSeconds"
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Try {
		Do $$$AssertStatusOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", 33, "First write."), "a row is written")
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "it exists, with the host class *")
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Do $$$AssertEquals(row.ProductionName_"|"_row.ItemName_"|"_row.HostClassName_"|"_row.SettingName_"|"_row.SettingValue_"|"_row.Description, production_"|Decide|*|TimerSeconds|33|First write.", "with the production, the item, the setting, the value and the description")
		Do $$$AssertEquals($ClassMethod(accessor, "ValueFor", "TimerSeconds", production, "Decide"), 33, "ValueFor reads the value")
		Do $$$AssertStatusOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", 44, "Second write."), "the row is written again")
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Do $$$AssertEquals(row.SettingValue_"|"_row.Description, "44|Second write.", "which changed the row")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.DefaultSettings WHERE ProductionName = ? AND ItemName = 'Decide' AND SettingName = 'TimerSeconds'", production)
		Do result.%Next()
		Do $$$AssertEquals(result.%GetData(1), 1, "and made no second row")
		Kill row
		Do $$$AssertStatusNotOK($ClassMethod(accessor, "WriteDefault", production, "Decide", "TimerSeconds", "x", "Not a number."), "a value that the setting's datatype refuses is an error status")
		Set stored = ##class(%SQL.Statement).%ExecDirect(, "SELECT SettingValue FROM Ens_Config.DefaultSettings WHERE ID = ?", id)
		Do stored.%Next()
		Do $$$AssertEquals(stored.%GetData(1), 44, "and the stored row keeps its value")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%ExistsId(id), 0, "the row is deleted again")
}

/// ValueFor (Story 1.4) reads any host setting of the item, from the item's settings, the System Default Settings and the property's
/// initial value, and gives "" with an error for an item, a setting or a production that is none; ClassFor builds on it.
Method TestValueFor()
{
	Set accessor = "OcuTalon.Bridge.Ext.Accessor"
	Set value = $ClassMethod(accessor, "ValueFor", "ReplyFilterClass", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "the ReplyFilterClass of Decide is read")
	Do $$$AssertEquals(value, "OcuTalon.Checks.ReplyGuard", "it is the class that the production names")
	Do $$$AssertEquals($ClassMethod(accessor, "ClassFor", "ReplyFilterClass", ..#PRODUCTION), value, "which is what ClassFor gives")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "a setting that is no extension class is read too")
	Do $$$AssertTrue(value ? 1.N, "TimerSeconds is a whole number: "_value)
	Set value = $ClassMethod(accessor, "ValueFor", "DailyCostCapUSD", ..#PRODUCTION, , .sc)
	Do $$$AssertStatusOK(sc, "so is DailyCostCapUSD")
	Do $$$AssertTrue($IsValidNum(value, "", 0), "which is a number of 0 or more: "_value)
	Set value = $ClassMethod(accessor, "ValueFor", "ZzNoSuchSetting", ..#PRODUCTION, , .sc)
	Do $$$AssertEquals(value, "", "a setting that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", ..#PRODUCTION, "ZzNoSuchItem", .sc)
	Do $$$AssertEquals(value, "", "an item that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ValueFor", "TimerSeconds", "Zz.NoSuchProduction", , .sc)
	Do $$$AssertEquals(value, "", "a production that does not exist gives an empty value")
	Do $$$AssertStatusNotOK(sc, "and an error status")
	Set value = $ClassMethod(accessor, "ClassFor", "TimerSeconds", ..#PRODUCTION, , .sc)
	Do $$$AssertEquals(value, "", "ClassFor still refuses a setting that is no extension setting")
	Do $$$AssertStatusNotOK(sc, "with an error status")
}

/// The job body of TestAccessorInAnotherJob: reads each case and records the class and 1 for OK, 0 for an error.
ClassMethod AccessorProbe(number As %Integer, production As %String)
{
	Set run = $Name(^OcuTalonTest("BridgeExt", number))
	Try {
		Set @run@("namespace") = $Namespace
		For setting = "HostSinkClass", "ReplyFilterClass", "ClassificationClass" {
			Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor(setting, production, , .sc)
			Set @run@(setting) = class_"|"_$SYSTEM.Status.IsOK(sc)
		}
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("ZzClass", production, , .sc)
		Set @run@("setting") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("HostSinkClass", production, "Zz"_number, .sc)
		Set @run@("item") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("HostSinkClass", "Zz"_number_".Production", , .sc)
		Set @run@("production") = class_"|"_$SYSTEM.Status.IsOK(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "%Library.String")
		Set @run@("check") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkText") = $SYSTEM.Status.GetErrorText(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "")
		Set @run@("checkEmpty") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkEmptyText") = $SYSTEM.Status.GetErrorText(sc)
		Set sc = ##class(OcuTalon.Bridge.Ext.Accessor).Check("HostSinkClass", "Zz"_number_".NoSuchClass")
		Set @run@("checkMissing") = "|"_$SYSTEM.Status.IsOK(sc)
		Set @run@("checkMissingText") = $SYSTEM.Status.GetErrorText(sc)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// Row 6: HostSink accepts each of its eight event types and lists exactly those in EVENTS, builds the three payloads
/// with exactly their keys, and BridgeSink extends it, does nothing and writes no live event; the reply filter and
/// ReplyGuard return text unchanged, and Classify returns "".
Method TestExtensionBases()
{
	Set expected = $ListBuild("turn.step", "decision.recorded", "approval.raised", "approval.answered", "approval.expired", "approval.cancelled", "approval.result", "budget.capped")
	Do $$$AssertEquals($ListFromString(##class(OcuTalon.Bridge.Ext.HostSink).#EVENTS), expected, "EVENTS lists exactly the eight event types")
	Set parameters = $ListBuild("TURNSTEP", "DECISIONRECORDED", "APPROVALRAISED", "APPROVALANSWERED", "APPROVALEXPIRED", "APPROVALCANCELLED", "APPROVALRESULT", "BUDGETCAPPED")
	For i = 1:1:8 {
		Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Ext.HostSink", $List(parameters, i)), $List(expected, i), $List(parameters, i)_" is "_$List(expected, i))
	}
	Set before = ..LiveEvents()
	For class = "OcuTalon.Bridge.Ext.HostSink", "OcuTalon.Core.BridgeSink" {
		For i = 1:1:8 {
			Do $$$AssertStatusOK($ClassMethod(class, "OnEvent", $List(expected, i), "zz", {}), class_" accepts "_$List(expected, i))
		}
	}
	Do $$$AssertEquals(..LiveEvents(), before, "BridgeSink writes no live event")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Core.BridgeSink", "%Extends", "OcuTalon.Bridge.Ext.HostSink"), "BridgeSink extends HostSink")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).RefPayload("r1")), "ref", "the ref payload has the key ref")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.HostSink).RefPayload("r1").ref, "r1", "and carries the Ref")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).TurnStepPayload("d1", "Asked the model")), "decisionRef,label", "the turn.step payload has the keys decisionRef and label")
	Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).TurnStepPayload("d1", "Asked the model")
	Do $$$AssertEquals(payload.decisionRef_"|"_payload.label, "d1|Asked the model", "and carries both")
	Do $$$AssertEquals(..Keys(##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2026-10-19")), "day", "the budget.capped payload has the key day")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2026-10-19").day, "2026-10-19", "and carries the day")

	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.ReplyFilter).Filter("text"), "text", "the default filter returns the text")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Everything I checked passed."), "Everything I checked passed.", "ReplyGuard returns the text, until Story 5.7")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Checks.ReplyGuard", "%Extends", "OcuTalon.Bridge.Ext.ReplyFilter"), "ReplyGuard extends ReplyFilter")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Classification).Classify("read_event_log"), "", "Classify returns an empty string")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Classification).Classify("read_event_log", {"a": 1}), "", "also with arguments")
}

/// Row 7: with no context, Active is 0 and Current is empty. After Begin, Active is 1 and Current carries the request's
/// fields and the SuperSession; the taint starts at 0. Another job sees no context. After Put("Tainted", 1), Current
/// is tainted; a name that is not a field is refused. A second Begin replaces the context and starts the taint and the
/// host data again. After End, Active is 0 again.
Method TestContext()
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context before Begin")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current(), "", "Current is empty before Begin")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "Put without a context is an error")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Begin("not a request"), "Begin takes a request")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and starts nothing")

	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = "zzitem"_..Number
	Set request.DecisionRef = "zzdec"_..Number
	Set request.OwnerRef = "zzowner"_..Number
	Set request.TraceRef = "zztrace"_..Number
	Set request.Channel = "web"
	Set request.ThreadSessionId = 4000 + ..Number
	Set super = "zzss"_..Number
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "Begin")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 1, "the context is active")
		Set current = ##class(OcuTalon.Bridge.Context).Current()
		Do $$$AssertTrue($IsObject(current), "Current is the context")
		Do $$$AssertEquals(current.Kind_"|"_current.Provenance_"|"_current.ItemId_"|"_current.DecisionRef, "turn|user|zzitem"_..Number_"|zzdec"_..Number, "Current carries Kind, Provenance, ItemId and DecisionRef")
		Do $$$AssertEquals(current.OwnerRef_"|"_current.TraceRef_"|"_current.Channel_"|"_current.ThreadSessionId, "zzowner"_..Number_"|zztrace"_..Number_"|web|"_(4000 + ..Number), "Current carries OwnerRef, TraceRef, Channel and ThreadSessionId")
		Do $$$AssertEquals(current.SuperSession, super, "Current carries the SuperSession")
		Do $$$AssertEquals(current.Tainted, 0, "the taint starts at 0")
		Do $$$AssertEquals(current.HostData, "", "and the host data is empty")

		Set run = $Name(^OcuTalonTest("BridgeExt", ..Number))
		Kill @run
		Job ##class(OcuTalon.Test.Bridge.Ext).ContextProbe(..Number)
		Do ..WaitFor($Name(@run@("done")), 1, 60)
		Do $$$AssertEquals($Get(@run@("done")), 1, "the other job finished")
		Do $$$AssertEquals($Get(@run@("active")), 0, "the other job sees no context")
		Do $$$AssertEquals($Get(@run@("current")), "", "and an empty Current")
		Kill @run

		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("Tainted", 1), "Put Tainted")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().Tainted, 1, "Current is tainted")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("HostData", "{""rows"":[]}"), "Put HostData")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().HostData, "{""rows"":[]}", "Current carries the host data")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Context).Put("ZzField", 1), "a name that is not a field is refused")

		Set again = ##class(OcuTalon.Bridge.Msg.Request).%New()
		Set again.OwnerRef = "zzagain"_..Number
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(again, "zzss2"_..Number), "a second Begin replaces the context")
		Set current = ##class(OcuTalon.Bridge.Context).Current()
		Do $$$AssertEquals(current.OwnerRef_"|"_current.SuperSession_"|"_current.ItemId, "zzagain"_..Number_"|zzss2"_..Number_"|", "Current carries only the second request's fields")
		Do $$$AssertEquals(current.Tainted_"|"_current.HostData, "0|", "and the taint and the host data start again")
	} Catch exception {
		Do $$$AssertTrue(0, "the context test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context after End")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current(), "", "Current is empty after End")
}

/// The job body of TestContext: records whether this process has a context.
ClassMethod ContextProbe(number As %Integer)
{
	Set run = $Name(^OcuTalonTest("BridgeExt", number))
	Set @run@("active") = ##class(OcuTalon.Bridge.Context).Active()
	Set @run@("current") = ##class(OcuTalon.Bridge.Context).Current()
	Set @run@("done") = 1
}

/// --- helpers ---
/// Deletes the reports of every run, this one and the runs that failed before: every node under the counter's level
/// except the counter itself.
ClassMethod CleanRuns() [ Private ]
{
	Set run = ""
	For {
		Set run = $Order(^OcuTalonTest("BridgeExt", run))
		Quit:run=""
		If run '= "n" Kill ^OcuTalonTest("BridgeExt", run)
	}
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The keys of a dynamic object as a comma list, in order.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
	}
	Quit keys
}

/// The rows of the live event table.
ClassMethod LiveEvents() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Live.Event")
	Do result.%Next()
	Quit result.%GetData(1)
}

}
