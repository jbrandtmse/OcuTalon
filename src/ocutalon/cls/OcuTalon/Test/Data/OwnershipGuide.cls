/// Tests of the six reads that Story 4.2 adds to Data.Ownership for the demo guide: ReminderSetOrFired, NewestIncident,
/// IncidentInProgress, IncidentApprovals, LatestBreakFeedRun and LastEvent. For each: its content and order, the isolation between two
/// sessions A and B (a row of the other session, instance or eval never shows, and an instance incident shows only on a local install
/// to the session that watches its production), and the refusal of an empty, instance or eval owner through Test.Data.OwnershipProbe,
/// which calls Rows. Every row comes from Test.Data.Fixture; the users are zzownguide<n>. onlineDemo is saved and put back.
Class OcuTalon.Test.Data.OwnershipGuide Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("OwnershipGuide", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// The newest pending or fired reminder by CreatedAt (then ID); a cancelled one and another session's never answer.
Method TestReminderSetOrFired()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession(), b = ..NewSession()
	Set read = ##class(OcuTalon.Data.Ownership).ReminderSetOrFired(a, .sc)
	Do $$$AssertStatusOK(sc, "the read works")
	Do $$$AssertEquals(read, "", "a session with no reminder gets none")
	Set pending = $ClassMethod(fixture, "Reminder", a, , "pending", {"CreatedAt": "2030-01-01T10:00:00Z"})
	Set fired = $ClassMethod(fixture, "Reminder", a, , "fired", {"CreatedAt": "2030-01-01T10:00:05Z"})
	Set cancelled = $ClassMethod(fixture, "Reminder", a, , "cancelled", {"CreatedAt": "2030-01-01T10:00:09Z"})
	Set theirs = $ClassMethod(fixture, "Reminder", b, , "pending", {"CreatedAt": "2030-01-01T10:00:20Z"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).ReminderSetOrFired(a, .sc).Ref, fired, "the newest pending or fired reminder, not the cancelled one")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).ReminderSetOrFired(b, .sc).Ref, theirs, "B gets its own")
	Do $ClassMethod(fixture, "Clean", fired)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).ReminderSetOrFired(a, .sc).Ref, pending, "then the pending one")
	Do $ClassMethod(fixture, "Clean", pending)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).ReminderSetOrFired(a, .sc), "", "a cancelled reminder alone answers none")
}

/// The newest noticed incident of the production since a time, by NoticedAt and then ID; the namespace matches in any case.
/// Unnoticed, other-production and other-session incidents never answer; an instance incident answers on a local install to the
/// session that watches its production, and never with onlineDemo 1.
Method TestNewestIncident()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession(), b = ..NewSession()
	Set first = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:00Z")
	Set second = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:10Z")
	Set tie = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:10Z")
	Do $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:20Z", "ZZNS", "Zz.Other")
	Do $ClassMethod(fixture, "Incident", a, "", "ZZNS", "Zz.Production")
	Do $ClassMethod(fixture, "Incident", b, "2030-01-01T10:00:30Z")
	Do $ClassMethod(fixture, "Incident", "eval", "2030-01-01T10:00:40Z")
	Do $ClassMethod(fixture, "Incident", "instance", "2030-01-01T10:00:50Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Production", "", .sc).Ref, tie, "an empty since counts all: the newest, the larger ID on a tie")
	Do $$$AssertStatusOK(sc, "the read works")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "zzns", "Zz.Production", "", .sc).Ref, tie, "the namespace matches in any case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Production", "2030-01-01T10:00:10Z", .sc).Ref, tie, "an incident noticed at since counts")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Production", "2030-01-01T10:00:11Z", .sc), "", "none noticed since a later time")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Other", "", .sc) '= "", 1, "the other production's incident is found by its production")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(b, "ZZNS", "Zz.Production", "", .sc).OwnerRef, b, "B gets its own incident, never A's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Missing", "", .sc), "", "an unknown production answers none")

	Set watcher = ..NewSession()
	Do $ClassMethod(fixture, "Check", watcher, "ZZNS", "Zz.Production")
	Set viaInstance = ##class(OcuTalon.Data.Ownership).NewestIncident(watcher, "ZZNS", "Zz.Production", "", .sc)
	Do $$$AssertEquals(viaInstance.OwnerRef, "instance", "a watcher sees the instance incident on a local install")
	Set stranger = ..NewSession()
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(stranger, "ZZNS", "Zz.Production", "", .sc), "", "a session that does not watch the production does not")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(watcher, "ZZNS", "Zz.Production", "", .sc), "", "and nobody does with onlineDemo 1")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).NewestIncident(a, "ZZNS", "Zz.Production", "", .sc).Ref, tie, "an own incident still does")
}

/// The newest incident of the production that is open, awaiting approval or fixing; a resolved, closed or unnoticed one and
/// another session's never answer.
Method TestIncidentInProgress()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession(), b = ..NewSession()
	Do $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:00Z", , , {"State": "resolved"})
	Do $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:01Z", , , {"State": "closed"})
	Do $ClassMethod(fixture, "Incident", a, "", , , {"State": "open"})
	Do $ClassMethod(fixture, "Incident", b, "2030-01-01T10:00:02Z", , , {"State": "open"})
	Do $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:03Z", "ZZNS", "Zz.Other", {"State": "open"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(a, "ZZNS", "Zz.Production", .sc), "", "resolved, closed, unnoticed, other-production and other sessions' incidents do not count")
	Do $$$AssertStatusOK(sc, "the read works")
	Set open = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:04Z", , , {"State": "open"})
	Set fixing = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:05Z", , , {"State": "fixing"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(a, "zzns", "Zz.Production", .sc).Ref, fixing, "the newest in-progress incident")
	Do $ClassMethod(fixture, "Clean", fixing)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(a, "ZZNS", "Zz.Production", .sc).Ref, open, "then the open one")
	Set waiting = $ClassMethod(fixture, "Incident", a, "2030-01-01T10:00:06Z", , , {"State": "awaiting_approval"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(a, "ZZNS", "Zz.Production", .sc).Ref, waiting, "an incident awaiting approval counts")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(b, "ZZNS", "Zz.Production", .sc).OwnerRef, b, "B gets its own")

	Set watcher = ..NewSession()
	Do $ClassMethod(fixture, "Check", watcher, "ZZNS", "Zz.Production")
	Do $ClassMethod(fixture, "Incident", "instance", "2030-01-01T10:00:07Z", , , {"State": "open"})
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(watcher, "ZZNS", "Zz.Production", .sc).OwnerRef, "instance", "a watcher sees an open instance incident on a local install")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentInProgress(watcher, "ZZNS", "Zz.Production", .sc), "", "and not with onlineDemo 1")
}

/// The requests of one incident that the session can see, in any state, by RaisedAt and then ID. Another session sees none of them,
/// and an instance request shows to a session that watches the instance incident's production on a local install.
Method TestIncidentApprovals()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession(), b = ..NewSession()
	Set incident = $ClassMethod(fixture, "Incident", a)
	Set other = $ClassMethod(fixture, "Incident", a)
	Set late = $ClassMethod(fixture, "Approval", a, incident, "done", "2030-01-01T10:00:30Z")
	Set early = $ClassMethod(fixture, "Approval", a, incident, "rejected", "2030-01-01T10:00:10Z")
	Set tieOne = $ClassMethod(fixture, "Approval", a, incident, "expired", "2030-01-01T10:00:20Z")
	Set tieTwo = $ClassMethod(fixture, "Approval", a, incident, "pending", "2030-01-01T10:00:20Z")
	Do $ClassMethod(fixture, "Approval", a, other, "approved")
	Do $ClassMethod(fixture, "Approval", "eval", incident)
	Set rows = ##class(OcuTalon.Data.Ownership).IncidentApprovals(incident, a, .sc)
	Do $$$AssertStatusOK(sc, "the read works")
	Set refs = ""
	For i = 1:1:rows.Count() {
		Set refs = refs_$Select(refs = "": "", 1: ",")_rows.GetAt(i).Ref
	}
	Do $$$AssertEquals(refs, early_","_tieOne_","_tieTwo_","_late, "the incident's requests of every state, by RaisedAt and then ID")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentApprovals(incident, b, .sc).Count(), 0, "B sees none of them")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentApprovals("", a, .sc).Count(), 0, "an empty incident Ref answers none")

	Set watcher = ..NewSession()
	Do $ClassMethod(fixture, "Check", watcher, "ZZNS", "Zz.Production")
	Set shared = $ClassMethod(fixture, "Incident", "instance", "2030-01-01T10:00:00Z", "ZZNS", "Zz.Production")
	Set request = $ClassMethod(fixture, "Approval", "instance", shared, "approved")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentApprovals(shared, watcher, .sc).GetAt(1).Ref, request, "a watcher sees the instance request on a local install")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentApprovals(shared, b, .sc).Count(), 0, "a session that does not watch does not")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).IncidentApprovals(shared, watcher, .sc).Count(), 0, "nobody does with onlineDemo 1")
}

/// The latest run by StartedAt and then ID; another session's runs never answer.
Method TestLatestBreakFeedRun()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession(), b = ..NewSession()
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(a, .sc), "", "no run, none")
	Do $$$AssertStatusOK(sc, "the read works")
	Do $ClassMethod(fixture, "BreakFeedRun", a, "sent", "2030-01-01T10:00:20Z")
	Do $ClassMethod(fixture, "BreakFeedRun", a, "sent", "2030-01-01T10:00:10Z")
	Do $ClassMethod(fixture, "BreakFeedRun", b, "sending", "2030-01-01T10:00:30Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(a, .sc).StartedAt, "2030-01-01T10:00:20Z", "the run with the latest StartedAt, whatever the ID")
	Do $ClassMethod(fixture, "BreakFeedRun", a, "sending", "2030-01-01T10:00:20Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(a, .sc).State, "sending", "on a tie the larger ID")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(b, .sc).SessionRef, b, "B gets its own run")
}

/// The newest event of the type on the session's own stream, by Seq; another stream's events and other types never answer.
Method TestLastEvent()
{
	Set a = ..NewSession(), b = ..NewSession()
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastEvent(a, "guide.state", .sc), "", "no event, none")
	Do $$$AssertStatusOK(sc, "the read works")
	Do ..PublishGuide(a, 1)
	Do ..PublishStatus(a)
	Do ..PublishGuide(a, 2)
	Do ..PublishStatus(a)
	Do ..PublishGuide(b, 7)
	Set last = ##class(OcuTalon.Data.Ownership).LastEvent(a, "guide.state", .sc)
	Do $$$AssertEquals(last.Seq_"|"_last.Stream_"|"_last.Type, "3|"_a_"|guide.state", "the newest guide.state of A's stream")
	Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(last.Payload).runEpoch, 2, "with its payload")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastEvent(a, "status", .sc).Seq, 4, "the type decides")
	Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(##class(OcuTalon.Data.Ownership).LastEvent(b, "guide.state", .sc).Payload).runEpoch, 7, "B gets its own stream's event")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastEvent(a, "check", .sc), "", "a type with no event, none")
}

/// Every new read refuses an empty, instance or eval owner (in any case): the statement is not prepared, sc is an error and nothing is
/// returned. Rows is called through Test.Data.OwnershipProbe for each kind, and the public methods are called with the same owners.
Method TestRefusedOwners()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set kinds = $ListBuild($ListBuild("reminderSetOrFired"), $ListBuild("newestIncident", "ZZNS", "Zz.Production", "", 1), $ListBuild("incidentInProgress", "ZZNS", "Zz.Production", 1), $ListBuild("incidentApprovals", "zz", 1), $ListBuild("latestBreakFeedRun"), $ListBuild("lastEvent", "guide.state"))
	Set owners = $ListBuild("", "instance", "INSTANCE", "Instance ", "eval", "EVAL")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set ownerPosition = 0
		While $ListNext(owners, ownerPosition, owner) {
			Kill args
			Set args = $ListLength(kind) - 1
			For j = 1:1:args Set args(j) = $List(kind, j + 1)
			Set rows = $ClassMethod(probe, "Call", $List(kind, 1), owner, .sc, args...)
			Do $$$AssertStatusNotOK(sc, $List(kind, 1)_" refuses the owner '"_owner_"'")
			Do $$$AssertEquals(rows.Count(), 0, $List(kind, 1)_" returns nothing for '"_owner_"'")
		}
	}
	For owner = "", "instance", "eval" {
		Do ##class(OcuTalon.Data.Ownership).ReminderSetOrFired(owner, .sc)
		Do $$$AssertStatusNotOK(sc, "ReminderSetOrFired refuses '"_owner_"'")
		Do ##class(OcuTalon.Data.Ownership).NewestIncident(owner, "ZZNS", "Zz.Production", "", .sc)
		Do $$$AssertStatusNotOK(sc, "NewestIncident refuses '"_owner_"'")
		Do ##class(OcuTalon.Data.Ownership).IncidentInProgress(owner, "ZZNS", "Zz.Production", .sc)
		Do $$$AssertStatusNotOK(sc, "IncidentInProgress refuses '"_owner_"'")
		Do ##class(OcuTalon.Data.Ownership).IncidentApprovals("zz", owner, .sc)
		Do $$$AssertStatusNotOK(sc, "IncidentApprovals refuses '"_owner_"'")
		Do ##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(owner, .sc)
		Do $$$AssertStatusNotOK(sc, "LatestBreakFeedRun refuses '"_owner_"'")
		Do ##class(OcuTalon.Data.Ownership).LastEvent(owner, "status", .sc)
		Do $$$AssertStatusNotOK(sc, "LastEvent refuses '"_owner_"'")
	}
}

/// A new fixture session, which Fixture.Clean removes.
Method NewSession() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session("zzownguide"_..Number)
}

/// Publishes a guide.state event with the epoch on the stream.
Method PublishGuide(stream As %String, epoch As %Integer) [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.GuideState).%New()
	Set payload.RunEpoch = epoch
	Set payload.Step = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "guide.state", payload), "a guide.state is published")
}

/// Publishes a status event on the stream.
Method PublishStatus(stream As %String) [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.Status).%New()
	Set payload.Condition = "noModelKey"
	Set payload.Active = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "status", payload), "a status is published")
}

}
