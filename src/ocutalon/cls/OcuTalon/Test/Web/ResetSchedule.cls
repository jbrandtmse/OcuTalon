Include Ensemble

/// Tests of the reset schedule as the page and the monitor read it (Story 16.8; AD-12, AD-19, AD-25). One next reset,
/// OcuTalon.Data.Public.Settings.NextReset, is what every reader gives:
///   - TestOneNextResetEverywhere: /ocutalon/public/status, /state's nextReset (the last key, after traceAccount), the reset event
///     that StatusMonitor publishes and the resume cookie's expiry all give the same time;
///   - TestLocalSnapshotKeepsItsKeys: with the flag off, or with no schedule, /state has no nextReset and no resetSoon;
///   - TestResetSoonAndResetThroughTheMonitor: the monitor's first run is silent, a reset inside 300 s publishes the resetSoon
///     condition and the reset event, a run with nothing changed publishes nothing, a clear publishes active false, and with the flag
///     off neither resetSoon nor a reset event is published; /state's status holds resetSoon last while it is active;
///   - TestResetSoonThreshold: the condition's threshold is 300 s.
/// It drives a shadow instance of Test.Core.StatusMonitorProbe on the stream of a fixture session, zzresetsched<n>. It saves the
/// public settings it sets and puts them back, and removes the fixture session, its events and its counter.
Class OcuTalon.Test.Web.ResetSchedule Extends %UnitTest.TestCase
{

/// The public settings that the tests change.
Parameter KEYS = "onlineDemo,resetAnchor,resetIntervalHours,lastReset,lastResetKind,readonlyUser,readonlyPassword";

/// saved(key) = the value held before the tests.
Property Saved As %String [ MultiDimensional ];

/// The run's number.
Property Number As %Integer;

/// The fixture session.
Property Session As OcuTalon.Data.Session;

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set position = 0
	Set keys = $ListFromString(..#KEYS)
	While $ListNext(keys, position, key) {
		Set ..Saved(key) = ##class(OcuTalon.Data.Public.Settings).Get(key)
	}
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("ResetSchedule", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Set ..Session = ##class(OcuTalon.Data.Session).ForUser("zzresetsched"_..Number, .sc)
	Do ..ClearOf(..Session.Ref)
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit sc
}

Method OnAfterOneTest() As %Status
{
	If $TLevel > 0 TROLLBACK
	Do ..ClearOf(..Session.Ref)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "OnProcessInput", "StatusMonitor could not")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Restore()
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// Row 3: with the flag on, an anchor an hour ahead and the read-only account set, the public status, /state, the monitor's reset
/// event and the cookie's expiry all give the one next reset; /state's keys are the local keys, then traceAccount, then nextReset.
Method TestOneNextResetEverywhere()
{
	Set error = ""
	Try {
		Do ..Schedule(1, 3600)
		Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyUser", "ResetReader"_..Number)
		Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyPassword", "pw"_..Number_"zz")
		Set next = ##class(OcuTalon.Data.Public.Settings).NextReset()
		Do $$$AssertEquals(next, ##class(OcuTalon.Data.Public.Settings).Get("resetAnchor"), "the next reset is the anchor an hour ahead")

		Set public = ##class(OcuTalon.Web.Public.Status).Body()
		Set state = ##class(OcuTalon.Web.Api).StateBody(..Session)
		Do $$$AssertEquals(public.nextReset, next, "/ocutalon/public/status gives the next reset")
		Do $$$AssertEquals(state.nextReset, next, "/state gives the next reset")
		Do $$$AssertEquals(..LastKey(state), "nextReset", "nextReset is /state's last key")
		Do $$$AssertTrue(..KeyList(state) [ ",traceAccount,nextReset", "after traceAccount ("_..KeyList(state)_")")
		Do $$$AssertEquals(state.%GetTypeOf("nextReset"), "string", "nextReset is a string")

		Set probe = ..Probe()
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ##class(OcuTalon.Data.Public.Settings).Shift(next, 7200))
		Set moved = ##class(OcuTalon.Data.Public.Settings).NextReset()
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Set events = ..Events()
		Do $$$AssertEquals(events.%Size(), 1, "the reset event is the one event of the run")
		Do $$$AssertEquals(events.%Get(0).type, "reset", "of type reset")
		Do $$$AssertEquals(events.%Get(0).payload.nextReset, moved, "carrying the next reset")
		Do $$$AssertEquals(##class(OcuTalon.Web.Public.Status).Body().nextReset, moved, "which is what the public status gives now")
		Do $$$AssertEquals(##class(OcuTalon.Web.Api).StateBody(..Session).nextReset, moved, "and /state")
		Do $$$AssertEquals(##class(OcuTalon.Web.SessionEvents).CookieExpiry(moved), ..CookieForm(moved), "the cookie expires at it")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ..Restore()
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// Row 4: with the flag off and an anchor set, or with the flag on and no anchor, /state has no nextReset, its keys are the local
/// ones and its status has no resetSoon.
Method TestLocalSnapshotKeepsItsKeys()
{
	Set error = ""
	Try {
		Set local = "version,instanceZone,epoch,streams,chat,rail,user,onlineDemo,demoMode,models,telegram,status"
		Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyUser", "")
		Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyPassword", "")

		Do ..Schedule(0, 120)
		Set state = ##class(OcuTalon.Web.Api).StateBody(..Session)
		Do $$$AssertEquals(..KeyList(state), local, "flag 0 with an anchor: the local keys")
		Do $$$AssertEquals(state.%GetTypeOf("nextReset"), "unassigned", "flag 0: no nextReset")
		Do $$$AssertNotTrue((","_..StatusConditions(state)_",") [ ",resetSoon,", "flag 0: no resetSoon in status")

		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", "")
		Set state = ##class(OcuTalon.Web.Api).StateBody(..Session)
		Do $$$AssertEquals(..KeyList(state), local, "flag 1 with no anchor: the local keys")
		Do $$$AssertNotTrue((","_..StatusConditions(state)_",") [ ",resetSoon,", "flag 1 with no anchor: no resetSoon in status")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ..Restore()
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// Row 5: the monitor through the probe. Run 1 (a reset an hour ahead) is silent. Run 2 (120 s ahead) publishes resetSoon active
/// with no slots, then the reset event. Run 3 changes nothing and publishes nothing. Run 4 (an hour ahead again) publishes
/// resetSoon with active false, then the reset event. Run 5 (120 s ahead, flag off) publishes nothing. /state's status holds
/// resetSoon last while it is active.
Method TestResetSoonAndResetThroughTheMonitor()
{
	Set error = ""
	Try {
		Do ..Schedule(1, 3600)
		Set probe = ..Probe()
		Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "run 1 returns OK")
		Do $$$AssertEquals(..Events().%Size(), 0, "run 1 is silent")

		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ..InSeconds(120))
		Set soon = ##class(OcuTalon.Data.Public.Settings).NextReset()
		Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "run 2 returns OK")
		Set events = ..Events()
		Do $$$AssertEquals(events.%Size(), 2, "run 2 publishes two events")
		Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.%ToJSON(), "status|{""condition"":""resetSoon"",""active"":true}", "resetSoon, active, with no slots")
		Do $$$AssertEquals(events.%Get(1).type_"|"_events.%Get(1).payload.%ToJSON(), "reset|{""nextReset"":"""_soon_"""}", "then the reset event")
		Set state = ##class(OcuTalon.Web.Api).StateBody(..Session)
		Do $$$AssertEquals($Piece(..StatusConditions(state), ",", *), "resetSoon", "/state's status holds resetSoon last while it is active ("_..StatusConditions(state)_")")
		Do $$$AssertEquals(state.nextReset, soon, "and nextReset is the same time")

		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Events().%Size(), 2, "run 3 changes nothing and publishes nothing")

		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ..InSeconds(3600))
		Set far = ##class(OcuTalon.Data.Public.Settings).NextReset()
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Set events = ..Events()
		Do $$$AssertEquals(events.%Size(), 4, "run 4 publishes two events")
		Do $$$AssertEquals(events.%Get(2).type_"|"_events.%Get(2).payload.%ToJSON(), "status|{""condition"":""resetSoon"",""active"":false}", "resetSoon cleared, with no slots")
		Do $$$AssertEquals(events.%Get(3).type_"|"_events.%Get(3).payload.%ToJSON(), "reset|{""nextReset"":"""_far_"""}", "then the reset event with the new time")
		Do $$$AssertNotTrue((","_..StatusConditions(##class(OcuTalon.Web.Api).StateBody(..Session))_",") [ ",resetSoon,", "/state's status no longer holds resetSoon")

		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ..InSeconds(120))
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Events().%Size(), 4, "run 5 with the flag off publishes nothing")
		Do $$$AssertEquals(##class(OcuTalon.Core.StatusMonitor).ResetSoon().Active, 0, "and resetSoon is inactive with the flag off")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ..Restore()
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// An unchanged schedule publishes no reset event on any later run, and a first run never publishes one.
Method TestResetEventPublishesOnChangeOnly()
{
	Set error = ""
	Try {
		Do ..Schedule(1, 3600)
		Set probe = ..Probe()
		For run = 1:1:3 {
			Do probe.OnProcessInput($$$NULLOREF, .output)
		}
		Do $$$AssertEquals(..Events().%Size(), 0, "three runs with the same schedule publish nothing")
		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", "")
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Events().%Size(), 0, "no schedule: an empty value is never published")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ..Restore()
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// The condition's threshold: a reset 400 s ahead is not soon, one 120 s ahead is, and with the flag off none is.
Method TestResetSoonThreshold()
{
	Set error = ""
	Try {
		Do ..Schedule(1, 400)
		Do $$$AssertEquals(##class(OcuTalon.Core.StatusMonitor).ResetSoon().Active, 0, "400 s ahead is not soon")
		Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ..InSeconds(120))
		Set condition = ##class(OcuTalon.Core.StatusMonitor).ResetSoon()
		Do $$$AssertEquals(condition.Active, 1, "120 s ahead is soon")
		Do $$$AssertEquals(condition.Condition, "resetSoon", "the condition is resetSoon")
		Do $$$AssertEquals(condition.Slots, "", "it has no slots")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do $$$AssertEquals(##class(OcuTalon.Core.StatusMonitor).ResetSoon().Active, 0, "with the flag off, never")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ..Restore()
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// Sets the flag and a schedule whose next reset is seconds ahead (an anchor, with an interval of 4 hours), and clears the last
/// reset. Anything that depends on how near the reset is sets the anchor relative to now.
Method Schedule(flag As %Boolean, seconds As %Integer) [ Private ]
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
	Do ##class(OcuTalon.Data.Public.Settings).Set("resetIntervalHours", 4)
	Do ##class(OcuTalon.Data.Public.Settings).Set("lastReset", "")
	Do ##class(OcuTalon.Data.Public.Settings).Set("lastResetKind", "")
	Do ##class(OcuTalon.Data.Public.Settings).Set("resetAnchor", ..InSeconds(seconds))
}

/// The UTC time that is the given number of seconds from now.
ClassMethod InSeconds(seconds As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Public.Settings).Shift($Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z", seconds)
}

/// The cookie date of a UTC time, built here independently of SessionEvents.
ClassMethod CookieForm(utc As %String) As %String [ Private ]
{
	Set days = $ZDateTimeH($Translate($Extract(utc, 1, 10), "T", " ")_" 00:00:00", 3, 1)
	Set weekday = $Piece("Sun,Mon,Tue,Wed,Thu,Fri,Sat", ",", $ZDate(+days, 10) + 1)
	Set month = $Piece("Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec", ",", +$Extract(utc, 6, 7))
	Quit weekday_", "_$Extract(utc, 9, 10)_" "_month_" "_$Extract(utc, 1, 4)_" "_$Extract(utc, 12, 19)_" GMT"
}

/// A shadow instance of the probe, on the fixture session's stream, with every key present and no budget cap.
Method Probe() As OcuTalon.Test.Core.StatusMonitorProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.StatusMonitorProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.StreamRef = ..Session.Ref
	Set probe.KeysReading = {"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}
	Set budget = {"spent": 0, "cap": 0, "resetsAt": ""}
	Do budget.%Set("capped", 0, "boolean")
	Set probe.BudgetReading = budget
	Quit probe
}

/// The events of the fixture stream, as the page's envelopes.
Method Events() As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Live.Event).Since(..Session.Ref, 0, 200, "session")
}

/// The keys of a dynamic object, comma-separated, in order.
ClassMethod KeyList(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

ClassMethod LastKey(object As %DynamicObject) As %String [ Private ]
{
	Quit $Piece(..KeyList(object), ",", *)
}

/// The condition names in /state's status, comma-separated, in order.
ClassMethod StatusConditions(state As %DynamicObject) As %String [ Private ]
{
	Set names = ""
	For i = 0:1:state.status.%Size() - 1 {
		Set names = names_$Select(names = "": "", 1: ",")_state.status.%Get(i).condition
	}
	Quit names
}

/// Puts back every public setting that the tests set.
Method Restore() [ Private ]
{
	Set key = ""
	For {
		Set key = $Order(..Saved(key), 1, value)
		Quit:key=""
		Do ##class(OcuTalon.Data.Public.Settings).Set(key, value)
	}
}

/// Removes the events and the counter of a stream.
ClassMethod ClearOf(stream As %String) [ Private ]
{
	If stream = "" Quit
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
	Kill ^OcuTalonP.LiveEventC(stream)
}

/// Deletes the fixture sessions with their events and counters.
ClassMethod Clean() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzresetsched'")
	While result.%Next() {
		Do ..ClearOf(result.%Get("Ref"))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzresetsched'")
}

}
