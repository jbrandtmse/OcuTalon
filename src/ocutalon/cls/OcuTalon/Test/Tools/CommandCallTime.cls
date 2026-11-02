/// Tests of the time a tool answer shows to the model (Story 30.5; DW-519, DW-484): OcuTalon.Tools.CommandCall TimeLabel, Answer and Listed.
///   - TestTimeLabel: "" for an empty time; Data.Time.ForMessage of the time for a local install (online 0); the same with " ET" after it for the online demo (online 1); the label is the
///     catalog's own (Msg.Catalog RenderAt of watch.time), so a time on another day reads as the catalog shows it; a time that is not a UTC stamp gives "";
///   - TestAnswerDue: the due time of a result's answer carries " ET" on the online demo and none on a local install, and the answer keeps its keys (due, dueLocal, message, ok); a result with no
///     due time has neither.
///   - TestListedDue (DW-559): the due time of each reminder in Listed's answer (the reminders list) carries " ET" on the online demo and none on a local install;
///   - (QA) TestSetReminderReplyOnTheTool: the reply of the set_reminder tool itself (Tools.ReminderTools SetReminder, which Chat calls), with the CI double behind the CommandsIn item,
///     carries " ET" after its due time on the online demo and none on a local install (DW-484). It needs the running production of a throwaway or CI stack and is recorded
///     as skipped, with the reason, where there is none.
/// The onlineDemo setting, the CommandsIn item's class and the context are put back after each test, also after a failure. Nothing else is written.
Class OcuTalon.Test.Tools.CommandCallTime Extends %UnitTest.TestCase
{

Parameter CALL = "OcuTalon.Tools.CommandCall";

/// The setting before the test changed it, and whether it did.
Property Before As %String;

Property Saved As %Boolean [ InitialExpression = 0 ];

/// What the CommandsIn item had before the double was put behind it, as the JSON text RunnerFixture.UseItemClass gave, or "" while the double is not behind it.
Property Swap As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = $$$OK
	If ..Saved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..Before)
		Set ..Saved = 0
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	If ..Swap '= "" {
		Set saved = {}.%FromJSON(..Swap)
		Set ..Swap = ""
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass("CommandsIn", saved)
		Set made = ##class(Ens.Director).CreateBusinessService("CommandsIn", .service)
		If $$$ISERR(made) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, made)
		} ElseIf $ClassName(service) '= saved.className {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The CommandsIn item runs "_$ClassName(service)_" after the restore, not "_saved.className))
		}
	}
	Quit sc
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

/// The reminders list (Listed) shows each due time through TimeLabel: " ET" on the online demo, none on a local install (DW-559).
Method TestListedDue()
{
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Set due = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 3600)
	Set shown = ##class(OcuTalon.Data.Time).ForMessage(due)
	Do $$$AssertTrue(shown '= "", "control: ForMessage shows the due time as "_shown)
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = 1
	Set result.Data = {"reminders": [{"ref": "zzReminder", "text": "stretch", "dueAt": (due)}]}.%ToJSON()
	For online = 1, 0 {
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online), "the online demo is "_$Select(online: "on", 1: "off"))
		Set answer = $ClassMethod(..#CALL, "Listed", result)
		Set first = $Select($IsObject(answer.reminders): answer.reminders.%Get(0), 1: "")
		Do $$$AssertEquals($Select($IsObject(first): answer.ok_"|"_first.ref_"|"_first.due, 1: ""), "1|zzReminder|"_shown_$Select(online: " ET", 1: ""), "online demo "_online_": the list's due is ForMessage"_$Select(online: " with ET", 1: ""))
	}
}

/// (QA, DW-484) What the model reads after set_reminder: the tool's own reply, through the double that stands for the owner. On the online demo its due time carries " ET";
/// on a local install it is the plain ForMessage. Pins the path from the tool to Answer's TimeLabel, which TestAnswerDue pins only from Answer on.
Method TestSetReminderReplyOnTheTool()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertSkipped("The set_reminder reply needs the running production of a throwaway or CI stack: "_reason)
		Quit
	}
	Set sc = $ClassMethod(fixture, "UseItemClass", "CommandsIn", "OcuTalon.Test.Tools.CommandsDouble", .saved)
	If $IsObject(saved) Set ..Swap = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "the double is put behind the CommandsIn item")
	If $$$ISERR(sc) Quit
	Kill ^OcuTalonTest("CommandsDouble")
	Set ..Before = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = 1
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for a session's turn")
	Set due = $Parameter("OcuTalon.Test.Tools.CommandsDouble", "SETDUEAT")
	Set shown = ##class(OcuTalon.Data.Time).ForMessage(due)
	Do $$$AssertTrue(shown '= "", "control: ForMessage shows the double's due time as "_shown)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1), "the online demo is on")
	Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 60)
	Do $$$AssertEquals(answer.ok_"|"_answer.due, "1|"_shown_" ET", "on the online demo the tool's reply has the zone label after its due time")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0), "the online demo is off")
	Set answer = ##class(OcuTalon.Tools.ReminderTools).SetReminder("stretch", 60)
	Do $$$AssertEquals(answer.ok_"|"_answer.due, "1|"_shown, "on a local install it has none")
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
