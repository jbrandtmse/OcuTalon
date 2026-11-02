/// Tests of the time a tool answer shows to the model (Story 30.5; DW-519, DW-484): OcuTalon.Tools.CommandCall TimeLabel and Answer.
///   - TestTimeLabel: "" for an empty time; Data.Time.ForMessage of the time for a local install (online 0); the same with " ET" after it for the online demo (online 1); the label is the
///     catalog's own (Msg.Catalog RenderAt of watch.time), so a time on another day reads as the catalog shows it; a time that is not a UTC stamp gives "";
///   - TestAnswerDue: the due time of a result's answer carries " ET" on the online demo and none on a local install, and the answer keeps its keys (due, dueLocal, message, ok); a result with no
///     due time has neither.
/// The onlineDemo setting is put back after each test, also after a failure. Nothing else is written.
Class OcuTalon.Test.Tools.CommandCallTime Extends %UnitTest.TestCase
{

Parameter CALL = "OcuTalon.Tools.CommandCall";

/// The setting before the test changed it, and whether it did.
Property Before As %String;

Property Saved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Saved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Before)
		Set ..Saved = 0
	}
	Quit $$$OK
}

Method TestTimeLabel()
{
	Set utc = ##class(OcuTalon.Data.Time).NowUtc()
	Set other = ##class(OcuTalon.Data.Time).AddSeconds(utc, 3 * 86400)
	Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", "", 0), "", "an empty time has no label on a local install")
	Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", "", 1), "", "and none on the online demo")
	For time = utc, other {
		Set shown = ##class(OcuTalon.Data.Time).ForMessage(time)
		Do $$$AssertTrue(shown '= "", "control: ForMessage shows "_time_" as "_shown)
		Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", time, 0), shown, time_": on a local install the label is ForMessage's")
		Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", time, 1), shown_" ET", time_": on the online demo it has ET after it")
		Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", time, 1), ##class(OcuTalon.Msg.Catalog).RenderAt("watch.time", {"time": (time)}.%ToJSON(), "web", "", 1), time_": and it is what the catalog renders")
	}
	Do $$$AssertEquals($ClassMethod(..#CALL, "TimeLabel", "tomorrow", 1), "", "a time that is not a UTC stamp has no label")
}

Method TestAnswerDue()
{
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Set due = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 3600)
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 1
	Set result.Message = "The reminder is set."
	Set result.DueAt = due
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1), "the online demo is on")
	Set answer = $ClassMethod(..#CALL, "Answer", result)
	Do $$$AssertEquals(answer.due, ##class(OcuTalon.Data.Time).ForMessage(due)_" ET", "on the online demo due is ForMessage with ET")
	Do $$$AssertEquals(..Keys(answer), "due,dueLocal,message,ok", "and the answer keeps its keys")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0), "the online demo is off")
	Set answer = $ClassMethod(..#CALL, "Answer", result)
	Do $$$AssertEquals(answer.due, ##class(OcuTalon.Data.Time).ForMessage(due), "on a local install due is ForMessage")
	Do $$$AssertEquals(..Keys(answer), "due,dueLocal,message,ok", "with the same keys")
	Set result.DueAt = ""
	Set answer = $ClassMethod(..#CALL, "Answer", result)
	Do $$$AssertEquals(..Keys(answer), "message,ok", "a result with no due time has neither due nor dueLocal")
}

/// The keys of the object, sorted, comma-separated.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Kill sorted
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set sorted(key) = ""
	}
	Set text = "", key = ""
	For {
		Set key = $Order(sorted(key))
		If key = "" Quit
		Set text = text _ $Select(text = "": "", 1: ",") _ key
	}
	Quit text
}

}
