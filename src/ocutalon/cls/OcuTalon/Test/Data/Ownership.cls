/// Tests of the ownership API (Story 2.2; AD-4, AD-13 as amended): how the CSP session is attached and resolved, what
/// each read returns and in which order, the scope of instance records, that an incident is visible only once noticed,
/// that an eval record never is, that a find answers "" for everything a session can't see, that a second session gets
/// none of the first session's rows for every row kind (condition 3), and that Rows refuses an empty owner and an
/// unknown kind (condition 1). Story 2.6 adds the decision find (TestDecisionRead) and the cost totals over the usage rows
/// (TestTurnCost, TestRunCost), whose figures are written out. Story 2.7 adds the notice cards and the delivery find (RecentNotices,
/// DeliveryFor; TestRecentNotices). Every row comes from Test.Data.Fixture, which Clean removes; the users are zzown<n>, with n
/// from ^OcuTalonTest("Ownership","n") (never reset). onlineDemo is saved and put back. Story 2.8 adds ApprovalIncident
/// (TestApprovalIncident) and the status of Watchers (TestInstanceScope). Story 2.13 adds the turn of an Item (TestTurnOfItem), which
/// the isolation and refusal tests cover as the row kind turnOfItem.
Class OcuTalon.Test.Data.Ownership Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("Ownership", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

/// Each test starts with the flag off, also after a test that turned it on and stopped on an error.
Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// Attach finds or creates the user's one durable session and records its Ref in the CSP session: two CSP sessions of
/// one user get one row and one Ref.
Method TestAttachReuses()
{
	New %session
	Set user = "zzown"_..Number_"attach"
	Set first = ##class(%CSP.Session).%New("ZzOwnA", 0)
	Set second = ##class(%CSP.Session).%New("ZzOwnB", 0)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 0, "no row to begin with")
	Set %session = first
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Ownership).Attach(user), "the first CSP session attaches")
	Set %session = second
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Ownership).Attach(user), "the second CSP session attaches")
	Do ..AdoptUser(user)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 1, "one row for the user")
	Set ref = first.Data("OcuTalon.SessionRef")
	Do $$$AssertTrue(ref ? 22(1AN,1"-",1"_"), "the first CSP session holds a Ref: "_ref)
	Do $$$AssertEquals(second.Data("OcuTalon.SessionRef"), ref, "the second CSP session holds the same Ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForUser(user).Ref, ref, "and it is the row's")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Ownership).Attach(""), "an empty user name is an error")
	Set %session = ""
	Do $$$AssertStatusNotOK(##class(OcuTalon.Data.Ownership).Attach(user), "with no CSP session, Attach is an error")
}

/// SessionRef takes the Ref recorded in the CSP session when that row exists and belongs to the signed-in user; a
/// missing or foreign one is attached again from the user name. A row that the test did not create is left alone.
Method TestSessionRefFromTheCspSession()
{
	New %session
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set later = ##class(OcuTalon.Test.Data.Fixture).Session($ZConvert($Username, "L"))
	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"other")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set %session = ##class(%CSP.Session).%New("ZzOwnC", 0)

	Set %session.Data("OcuTalon.SessionRef") = later
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertStatusOK(sc, "the recorded Ref is resolved")
	Do $$$AssertEquals(ref, later, "the recorded Ref wins over the user's first row, whatever the case of the user name")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and no row is created")
	Set %session.Data("OcuTalon.SessionRef") = mine
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(), mine, "another recorded Ref of the same user wins too")

	Set expected = ##class(OcuTalon.Data.Session).ForUser($Username).Ref
	Set %session.Data("OcuTalon.SessionRef") = foreign
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertStatusOK(sc, "a foreign Ref is replaced")
	Do $$$AssertEquals(ref, expected, "by the signed-in user's own session")
	Do $$$AssertEquals(%session.Data("OcuTalon.SessionRef"), expected, "which is now recorded")
	Set %session.Data("OcuTalon.SessionRef") = "zzmissing"_..Number
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(), expected, "a Ref with no row is replaced the same way")
	Kill %session.Data("OcuTalon.SessionRef")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(), expected, "so is no Ref at all")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "no session row is created by any of this")

	Set %session = ""
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertEquals(ref, "", "with no CSP session the result is empty")
	Do $$$AssertStatusNotOK(sc, "and the status an error")
}

/// On the online demo (Story 16.3, matrix row 8) SessionRef never resolves by user name: with no Ref in the CSP session the result is
/// "" with an error and no row is created for the user; the Ref of a row of the signed-in user is returned; the Ref of another user's
/// row gives "" and an error. With the flag off the lazy attach of Story 2.2 is unchanged for the same three calls.
Method TestSessionRefOnTheOnlineDemo()
{
	New %session
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"onlineother")
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set %session = ##class(%CSP.Session).%New("ZzOwnOnline", 0)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")

	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertEquals(ref, "", "online: with no Ref attached the result is empty")
	Do $$$AssertStatusNotOK(sc, "and the status an error")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "and no row is created for the user")
	Do $$$AssertEquals($Get(%session.Data("OcuTalon.SessionRef")), "", "nothing is attached")
	Set %session.Data("OcuTalon.SessionRef") = mine
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertStatusOK(sc, "online: the Ref of the user's row is resolved")
	Do $$$AssertEquals(ref, mine, "it is returned")
	Set %session.Data("OcuTalon.SessionRef") = foreign
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Do $$$AssertEquals(ref, "", "online: another user's Ref gives an empty result")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set %session.Data("OcuTalon.SessionRef") = "zzmissing"_..Number
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(.sc), "", "online: a Ref with no row gives an empty result")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before, "no row is created by any of this")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Kill %session.Data("OcuTalon.SessionRef")
	Set expected = ##class(OcuTalon.Data.Session).ForUser($Username).Ref
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(.sc), expected, "flag off: no Ref is attached from the user name")
	Set %session.Data("OcuTalon.SessionRef") = mine
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(), mine, "flag off: the user's Ref is returned")
	Set %session.Data("OcuTalon.SessionRef") = foreign
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).SessionRef(), expected, "flag off: another user's Ref is replaced by the user's own")
}

/// StartVisitor and Resume (Story 16.3, matrix rows 3 and 8): StartVisitor creates a row of the signed-in user with the CSP session
/// id and a hash of the new reference, and records its Ref; Resume of that reference in another CSP session records the same Ref and
/// the new id; Resume answers "" with OK for a reference of no row or of another user's row, and an error with no CSP session.
Method TestResumeAndStartVisitor()
{
	New %session
	Set before = ##class(OcuTalon.Test.Data.Fixture).SessionCount($Username)
	Set %session = ##class(%CSP.Session).%New("ZzOwnVisitorA", 0)
	Set ref = ##class(OcuTalon.Data.Ownership).StartVisitor(.reference, .sc)
	Do $$$AssertStatusOK(sc, "StartVisitor answers OK")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "it returns the Ref of a new row")
	If $IsObject(row) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before + 1, "one row is created")
	Do $$$AssertEquals(%session.Data("OcuTalon.SessionRef"), ref, "its Ref is in the CSP session")
	Do $$$AssertTrue(reference ? 22(1AN,1"-",1"_"), "the reference is 22 base64url characters")
	If $IsObject(row) {
		Do $$$AssertEquals(row.IrisUser, $Username, "the row is the signed-in user's")
		Do $$$AssertEquals(row.CspSessionId, "ZzOwnVisitorA", "it records the CSP session")
		Do $$$AssertEquals(row.ResumeHash, ##class(OcuTalon.Data.Session).Hash(reference), "and the hash of the reference")
	}

	Set %session = ##class(%CSP.Session).%New("ZzOwnVisitorB", 0)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Resume(reference, .sc), ref, "Resume returns the row's Ref")
	Do $$$AssertStatusOK(sc, "with OK")
	Do $$$AssertEquals(%session.Data("OcuTalon.SessionRef"), ref, "records it in the new CSP session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).CspSessionId, "ZzOwnVisitorB", "and the new CSP session on the row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount($Username), before + 1, "no row is created")

	Set %session = ##class(%CSP.Session).%New("ZzOwnVisitorC", 0)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Resume(##class(OcuTalon.Bridge.Ids).NewRef(), .sc), "", "an unknown reference gives an empty result")
	Do $$$AssertStatusOK(sc, "with OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Resume("short", .sc), "", "so does a malformed one")
	Do $$$AssertEquals($Get(%session.Data("OcuTalon.SessionRef")), "", "and nothing is attached")
	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"resumeother")
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set foreignRow = ##class(OcuTalon.Data.Session).RefIndexOpen(foreign)
	Set foreignRow.ResumeHash = ##class(OcuTalon.Data.Session).Hash(other)
	Do $$$AssertStatusOK(foreignRow.%Save(), "the other user's row takes a resume hash")
	Set opened = ##class(OcuTalon.Data.Session).ForResume(other)
	Do $$$AssertEquals($Select($IsObject(opened): opened.Ref, 1: ""), foreign, "and its reference opens it")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Resume(other, .sc), "", "another user's row is not resumed")
	Do $$$AssertStatusOK(sc, "with OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(foreign).CspSessionId, "", "and is not touched")

	Set %session = ""
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Resume(reference, .sc), "", "with no CSP session Resume gives an empty result")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).StartVisitor(.again, .sc), "", "so does StartVisitor")
	Do $$$AssertStatusNotOK(sc, "with an error")
	Do $$$AssertEquals(again, "", "and no reference")
}

/// A session reads its own records of every kind and none of another session's.
Method TestOwnRecordsOnly()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Do ..Seed(a, .ra1)
	Do ..Seed(a, .ra2)
	Do ..Seed(b, .rb)
	Do ..ReadAll(a, .seen)
	Do $$$AssertEquals(seen("turns"), ra1("turn")_","_ra2("turn")_","_ra1("queued")_","_ra2("queued")_","_ra1("replied")_","_ra2("replied"), "A's turns, by CreatedAt and then ID")
	Do $$$AssertEquals(seen("turnqueue"), ra1("queued")_","_ra2("queued"), "A's queued turns")
	Do $$$AssertEquals(seen("lastreplied"), ra2("replied"), "A's newest replied turn: the later ID of the tie")
	Do $$$AssertEquals(seen("reminders"), ra1("reminder")_","_ra2("reminder"), "A's reminders")
	Do $$$AssertEquals(seen("checks"), ra1("check")_","_ra2("check"), "A's checks")
	Do $$$AssertEquals(seen("decisions"), ra2("decision")_","_ra1("decision"), "A's decisions, newest first")
	Do $$$AssertEquals(seen("incidents"), ra1("incident")_","_ra2("incident"), "A's incidents")
	Do $$$AssertEquals(seen("approvals"), ra1("approval")_","_ra2("approval"), "A's approvals")
	Do $$$AssertEquals(seen("pairing"), ra1("pairing"), "A's pairing, the first row")
	Do ..ReadAll(b, .seen)
	Do $$$AssertEquals(seen("turns"), rb("turns"), "B reads its own turn rows and no other")
	Do $$$AssertEquals(seen("turnqueue")_"|"_seen("lastreplied")_"|"_seen("turnbyclient"), rb("queued")_"|"_rb("replied")_"|"_rb("queued"), "and its own queue, replied turn and clientId turn")
	For kind = "reminder", "check", "decision", "incident", "approval" {
		Do $$$AssertEquals(seen(kind_"s"), rb(kind), "B reads its own "_kind_" row and no other")
	}
	Do $$$AssertEquals(seen("pairing"), rb("pairing"), "B's pairing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(ra1("incident"), a).Ref, ra1("incident"), "A finds its own incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(rb("approval"), b).Ref, rb("approval"), "B finds its own approval")
}

/// An instance incident, and its pending request, are visible to the sessions whose checks watch the production, on a
/// local install only.
Method TestInstanceScope()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Set c = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"c")
	Set one = "Zz.Own"_..Number_".One"
	Set two = "Zz.Own"_..Number_".Two"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", one)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", one)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", two)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(c, "ZZOTHER", one)
	Set incidentOne = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "2030-01-01T10:00:00Z", "ZZNS", one)
	Set incidentTwo = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "2030-01-01T11:00:00Z", "ZZNS", two)
	Set requestOne = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incidentOne)
	Set requestTwo = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incidentTwo)
	Set requestNone = ##class(OcuTalon.Test.Data.Fixture).Approval("instance")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "2030-01-01T09:00:00Z")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ..ReadAll(a, .seen)
	Do $$$AssertEquals(seen("incidents"), own_","_incidentOne, "A sees its own incident and the instance incident of the production it watches")
	Do $$$AssertEquals(seen("recentincidents"), incidentOne_","_own, "and the newest-first read of the snapshot sees the same two, newest first")
	Do $$$AssertEquals(seen("approvals"), requestOne, "and that incident's request, not the other production's, and not a request with no incident")
	Do ..ReadAll(b, .seen)
	Do $$$AssertEquals(seen("incidents"), incidentOne_","_incidentTwo, "B watches both productions and sees both incidents")
	Do $$$AssertEquals(seen("recentincidents"), incidentTwo_","_incidentOne, "newest first in the snapshot's read")
	Do $$$AssertEquals(seen("approvals"), requestOne_","_requestTwo, "and both requests")
	Do ..ReadAll(c, .seen)
	Do $$$AssertEquals(seen("incidents")_"|"_seen("approvals")_"|"_seen("recentincidents"), "||", "C watches the production in another namespace and sees nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(incidentTwo, a), "", "A does not find the unwatched incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(requestTwo, a), "", "or its request")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(requestNone, b), "", "nobody finds an instance request with no incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(incidentTwo, b).Ref, incidentTwo, "B finds it")
	Set watchers = ##class(OcuTalon.Data.Ownership).Watchers("ZZNS", one, .sc)
	Do $$$AssertStatusOK(sc, "the read of the first production's watchers")
	Do $$$AssertEquals($ListLength(watchers), 2, "two sessions watch the first production")
	Do $$$AssertTrue($ListFind(watchers, a) && $ListFind(watchers, b), "A and B")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", two, .sc)), 1, "one watches the second")
	Do $$$AssertStatusOK(sc, "the read of the second production's watchers")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", "Zz.Nobody", .sc), "", "none watches another")
	Do $$$AssertStatusOK(sc, "nobody watching is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("", one, .sc), "", "an empty namespace gives none")
	Do $$$AssertStatusOK(sc, "also without an error")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..ReadAll(a, .seen)
	Do $$$AssertEquals(seen("incidents"), own, "with onlineDemo on, A sees only its own incident")
	Do $$$AssertEquals(seen("recentincidents"), own, "also in the snapshot's read")
	Do $$$AssertEquals(seen("approvals"), "", "and no instance request")
	Do ..ReadAll(b, .seen)
	Do $$$AssertEquals(seen("incidents")_"|"_seen("approvals")_"|"_seen("recentincidents"), "||", "B sees no instance record")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(incidentOne, a), "", "an instance incident is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(requestOne, a), "", "nor its request")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(own, a).Ref, own, "the session's own incident still is")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", one, .sc), "", "and nobody watches")
	Do $$$AssertStatusOK(sc, "with no error")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// ApprovalIncident gives the IncidentRef of an instance request, and "" for a session's request, an eval request, an unknown
/// Ref, the Ref in another case, an empty Ref and a Ref with a quote or LIKE wildcards in it (a bound value, never a syntax error),
/// always with an OK status (DW-68).
Method TestApprovalIncident()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", "Zz.Own"_..Number_".Incident")
	Set instance = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set instanceNone = ##class(OcuTalon.Test.Data.Fixture).Approval("instance")
	Set session = ##class(OcuTalon.Test.Data.Fixture).Approval(a, incident)
	Set eval = ##class(OcuTalon.Test.Data.Fixture).Approval("eval", incident)
	Set other = $ZConvert(instance, "U")
	If other = instance Set other = $ZConvert(instance, "L")
	Do $$$AssertTrue(other '= instance, "the Ref changes with its case")
	Do ..AssertIncident(instance, incident, "an instance request gives its IncidentRef")
	Do ..AssertIncident(instanceNone, "", "an instance request with no incident gives none")
	Do ..AssertIncident(session, "", "a session's request gives none")
	Do ..AssertIncident(eval, "", "an eval request gives none")
	Do ..AssertIncident("zzunknown"_..Number, "", "an unknown Ref gives none")
	Do ..AssertIncident(other, "", "the Ref in another case gives none")
	Do ..AssertIncident("", "", "an empty Ref gives none")
	Do ..AssertIncident("zz'"_..Number, "", "a Ref with a quote is only a value: it finds none and is no error")
	Do ..AssertIncident("zz"_..Number_"%_", "", "so is one with the wildcards of LIKE")
}

/// Asserts what ApprovalIncident answers for the Ref, and that its status is OK.
Method AssertIncident(ref As %String, expected As %String, text As %String) [ Private ]
{
	Set got = ##class(OcuTalon.Data.Ownership).ApprovalIncident(ref, .sc)
	Do $$$AssertEquals(got, expected, text)
	Do $$$AssertStatusOK(sc, "the status is OK: "_text)
}

/// An incident is visible only once NoticedAt is set: its own, and an instance incident of a watched production.
Method TestOnlyNoticedIncidents()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set production = "Zz.Own"_..Number_".Noticed"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)
	Set noticed = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "2030-01-01T10:00:00Z")
	Set unnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "")
	Set instanceNoticed = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "2030-01-01T11:00:00Z", "ZZNS", production)
	Set instanceUnnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set rows = ##class(OcuTalon.Data.Ownership).Incidents(a, .sc)
	Do $$$AssertStatusOK(sc, "the read")
	Do $$$AssertEquals(..Refs(rows), noticed_","_instanceNoticed, "only the noticed incidents are read")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(unnoticed, a), "", "the session's own unnoticed incident is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(instanceUnnoticed, a), "", "nor the instance's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(noticed, a).Ref, noticed, "the noticed one is")
}

/// An eval record is never visible: not in a read, not to a find, and not as an owner.
Method TestEvalNeverVisible()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set production = "Zz.Own"_..Number_".Eval"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("eval", "2030-01-01T10:00:00Z", "ZZNS", production)
	Set approval = ##class(OcuTalon.Test.Data.Fixture).Approval("eval", incident)
	Do ##class(OcuTalon.Test.Data.Fixture).Decision("eval")
	Do ..ReadAll(a, .seen)
	Do $$$AssertEquals(seen("incidents")_"|"_seen("approvals")_"|"_seen("decisions"), "||", "A reads no eval record, though it watches the production")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(incident, a), "", "an eval incident is not found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(approval, a), "", "nor an eval request")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Data.Session).Recipients("eval", incident)), 0, "and nobody receives it")
	Set rows = ##class(OcuTalon.Test.Data.OwnershipProbe).Call("decisions", "eval", .sc, 20)
	Do $$$AssertStatusNotOK(sc, "eval is refused as an owner")
	Do $$$AssertEquals(rows.Count(), 0, "with no rows")
}

/// A find answers "" for every case a session can't see, and the row for the cases it can.
Method TestFinds()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Set watched = "Zz.Own"_..Number_".Watched"
	Set unwatched = "Zz.Own"_..Number_".Unwatched"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", watched)
	Set own = ##class(OcuTalon.Test.Data.Fixture).Incident(a)
	Set ownUnnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "")
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Incident(b)
	Set eval = ##class(OcuTalon.Test.Data.Fixture).Incident("eval")
	Set instanceWatched = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", watched)
	Set instanceUnwatched = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", unwatched)
	Set instanceUnnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", watched)
	Set ownApproval = ##class(OcuTalon.Test.Data.Fixture).Approval(a, own)
	Set ownAnswered = ##class(OcuTalon.Test.Data.Fixture).Approval(a, own, "answered")
	Set theirApproval = ##class(OcuTalon.Test.Data.Fixture).Approval(b, theirs)
	Set evalApproval = ##class(OcuTalon.Test.Data.Fixture).Approval("eval", eval)
	Set watchedApproval = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", instanceWatched)
	Set unwatchedApproval = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", instanceUnwatched)
	Set unnoticedApproval = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", instanceUnnoticed)

	For ref = theirs, ownUnnoticed, eval, instanceUnwatched, instanceUnnoticed, "zzmissing"_..Number, "", theirApproval {
		Set found = ##class(OcuTalon.Data.Ownership).Incident(ref, a, .sc)
		Do $$$AssertEquals(found, "", "Incident("_ref_") is not found")
		Do $$$AssertStatusOK(sc, "and that is not an error")
	}
	For ref = theirApproval, evalApproval, unwatchedApproval, unnoticedApproval, "zzmissing"_..Number, "", own {
		Set found = ##class(OcuTalon.Data.Ownership).Approval(ref, a, .sc)
		Do $$$AssertEquals(found, "", "Approval("_ref_") is not found")
		Do $$$AssertStatusOK(sc, "and that is not an error")
	}
	For ref = own, instanceWatched {
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(ref, a).Ref, ref, "Incident("_ref_") is found")
	}
	For ref = ownApproval, ownAnswered, watchedApproval {
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(ref, a).Ref, ref, "Approval("_ref_") is found, whatever its state")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(own, ""), "", "with no session nothing is found")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(own, b), "", "another session does not find it")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(ownApproval, b), "", "nor the request")
}

/// The order and the filter of every read.
Method TestOrders()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set t1 = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:02Z")
	Set t2 = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z")
	Set t3 = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z")
	Set rows = ##class(OcuTalon.Data.Ownership).Turns(a)
	Do $$$AssertEquals(..Refs(rows), t2_","_t3_","_t1, "turns: by CreatedAt, then ID")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).RecentTurns(a, 2)), t1_","_t3, "recent turns: the two newest, newest first, the later ID first on a tie")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).RecentTurns(a)), t1_","_t3_","_t2, "recent turns: all of them within the default of 100")

	Set r1 = ##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-01-01T12:00:00Z")
	Set r2 = ##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-01-01T11:00:00Z")
	Do ##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-01-01T10:00:00Z", "fired")
	Do ##class(OcuTalon.Test.Data.Fixture).Reminder(a, "2030-01-01T09:00:00Z", "cancelled")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Reminders(a)), r2_","_r1, "reminders: pending only, by DueAt")

	Set c1 = ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Order.B")
	Set c2 = ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", "Zz.Order.A")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Checks(a)), c1_","_c2, "checks: by ID")

	Set d1 = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", "2030-01-01T10:00:00Z")
	Set d2 = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", "2030-01-01T12:00:00Z")
	Set d3 = ##class(OcuTalon.Test.Data.Fixture).Decision(a, "decide", "2030-01-01T11:00:00Z")
	Do ##class(OcuTalon.Test.Data.Fixture).Decision(a, "turn", "2030-01-01T13:00:00Z")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Decisions(a)), d2_","_d3_","_d1, "decisions: decide only, newest first")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Decisions(a, 2)), d2_","_d3, "decisions: at most max")

	Set i1 = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "2030-01-01T12:00:00Z")
	Set i2 = ##class(OcuTalon.Test.Data.Fixture).Incident(a, "2030-01-01T11:00:00Z")
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(a, "")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Incidents(a)), i2_","_i1, "incidents: noticed only, by NoticedAt")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).RecentIncidents(a, 1)), i1, "recent incidents: the newest noticed incident only")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).RecentIncidents(a)), i1_","_i2, "recent incidents: noticed only, newest first")

	Set p1 = ##class(OcuTalon.Test.Data.Fixture).Approval(a, , , "2030-01-01T12:00:00Z")
	Set p2 = ##class(OcuTalon.Test.Data.Fixture).Approval(a, , , "2030-01-01T11:00:00Z")
	Do ##class(OcuTalon.Test.Data.Fixture).Approval(a, , "answered", "2030-01-01T10:00:00Z")
	Do $$$AssertEquals(..Refs(##class(OcuTalon.Data.Ownership).Approvals(a)), p2_","_p1, "approvals: pending only, by RaisedAt")

	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(a), "", "pairing: none")
	Set pair = ##class(OcuTalon.Test.Data.Fixture).Pairing(a)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(a).Ref, pair, "pairing: the row")
}

/// AD-13 condition 3: sessions A and B each get one row of every kind, and a read with one's SessionRef holds none of the
/// other's rows. A find with B's SessionRef answers "" for A's refs, and the reverse.
Method TestIsolationEveryRowKind()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Do ..Seed(a, .ra)
	Do ..Seed(b, .rb)
	Do ..ReadAll(a, .seenA, ra("decision"), ra("deliveryapproval"), ra("itemid"), ra("decisionitem"))
	Do ..ReadAll(b, .seenB, rb("decision"), rb("deliveryapproval"), rb("itemid"), rb("decisionitem"))
	Do ..ReadAll(b, .crossB, ra("decision"), ra("deliveryapproval"), ra("itemid"), ra("decisionitem"))
	Do ..ReadAll(a, .crossA, rb("decision"), rb("deliveryapproval"), rb("itemid"), rb("decisionitem"))
	Set kinds = $ListBuild($ListBuild("turns", "turns"), $ListBuild("turnqueue", "queued"), $ListBuild("lastreplied", "replied"), $ListBuild("turnbyclient", "queued"), $ListBuild("turnofitem", "turn"), $ListBuild("reminders", "reminder"), $ListBuild("checks", "check"), $ListBuild("decisions", "decision"), $ListBuild("incidents", "incident"), $ListBuild("approvals", "approval"), $ListBuild("pairing", "pairing"), $ListBuild("recentturns", "recentturns"), $ListBuild("recentincidents", "incident"), $ListBuild("decision", "decision"), $ListBuild("turnusage", "decision"), $ListBuild("runusage", "decision"), $ListBuild("rundecisions", "decision"), $ListBuild("recentnotices", "notice"), $ListBuild("recentphone", "phone"), $ListBuild("recentmail", "mail"), $ListBuild("decisionofitem", "decision"), $ListBuild("delivery", "notice"))
	Set position = 0
	While $ListNext(kinds, position, pair) {
		Set read = $List(pair, 1), kind = $List(pair, 2)
		Do $$$AssertEquals(seenA(read), ra(kind), "A reads only its own "_kind)
		Do $$$AssertEquals(seenB(read), rb(kind), "B reads only its own "_kind)
		Do $$$AssertTrue(seenB(read) '[ ra(kind), "B's "_read_" holds none of A's")
		Do $$$AssertTrue(seenA(read) '[ rb(kind), "A's "_read_" holds none of B's")
	}
	Do $$$AssertEquals(seenA("runusage")_"|"_seenA("rundecisions"), ra("decision")_"|"_ra("decision"), "A's usage and decisions since a time are its own, with one usage row and one decision")
	For read = "decision", "turnusage" {
		Do $$$AssertEquals(crossB(read), "", "B reads nothing of A's decision through "_read)
		Do $$$AssertEquals(crossA(read), "", "A reads nothing of B's decision through "_read)
	}
	Do $$$AssertEquals(crossB("decisionofitem")_"|"_crossA("decisionofitem"), "|", "neither finds the other's decision by its ItemId")
	Do $$$AssertEquals(crossB("turnofitem"), "", "B finds nothing of A's turn by A's ItemId")
	Do $$$AssertEquals(crossA("turnofitem"), "", "A finds nothing of B's turn by B's ItemId")
	Do $$$AssertEquals(crossB("delivery"), "", "B finds nothing of A's delivery by A's approval Ref")
	Do $$$AssertEquals(crossA("delivery"), "", "A finds nothing of B's delivery by B's approval Ref")
	Do $$$AssertEquals(seenA("recentnotices")_"|"_seenB("recentnotices"), ra("notice")_"|"_rb("notice"), "each session's notice cards are its own, and only the card kinds")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(ra("incident"), b), "", "B does not find A's incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(ra("approval"), b), "", "B does not find A's approval")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(rb("incident"), a), "", "A does not find B's incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(rb("approval"), a), "", "A does not find B's approval")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incident(ra("incident"), a).Ref, ra("incident"), "A finds its own incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Approval(rb("approval"), b).Ref, rb("approval"), "B finds its own approval")
}

/// AD-13 condition 1: Rows refuses an empty owner Ref and a kind it does not define, with an error status and no rows.
/// The test reaches the private method through Test.Data.OwnershipProbe, a subclass; the public reads are refused the
/// same way for an empty SessionRef.
Method TestRowsRefuses()
{
	Set probe = "OcuTalon.Test.Data.OwnershipProbe"
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Do ..Seed(a, .ra)
	Set rows = $ClassMethod(probe, "Call", "turns", "", .sc)
	Do $$$AssertStatusNotOK(sc, "an empty owner Ref is an error")
	Do $$$AssertEquals(rows.Count(), 0, "with no rows")
	Set rows = $ClassMethod(probe, "Call", "zzkind", a, .sc)
	Do $$$AssertStatusNotOK(sc, "an unknown kind is an error")
	Do $$$AssertEquals(rows.Count(), 0, "with no rows")
	Set rows = $ClassMethod(probe, "Call", "turns' OR '1'='1", a, .sc)
	Do $$$AssertStatusNotOK(sc, "a kind that is SQL text is an unknown kind")
	Do $$$AssertEquals(rows.Count(), 0, "with no rows")
	For owner = "instance", "eval", "Instance", "EVAL", "instance ", "EVAL  ", "eval"_$Char(9), "Instance"_$Char(160) {
		Set rows = $ClassMethod(probe, "Call", "turns", owner, .sc)
		Do $$$AssertStatusNotOK(sc, "'"_$ZConvert(owner, "O", "URL")_"' (URL-encoded) is not a session's Ref")
		Do $$$AssertEquals(rows.Count(), 0, "with no rows")
	}
	For kind = "turnByClient", "turnOfItem", "turnQueue", "lastReplied", "recentTurns", "recentIncidents", "decision", "turnUsage", "runUsage", "runDecisions", "recentNotices", "recentPhone", "recentMail", "decisionOfItem", "deliveryByApproval" {
		Set rows = $ClassMethod(probe, "Call", kind, "", .sc, "zzownshared", "zzownshared")
		Do $$$AssertStatusNotOK(sc, kind_": an empty owner Ref is an error")
		Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		For owner = "eval", "instance", "EVAL " {
			Set rows = $ClassMethod(probe, "Call", kind, owner, .sc, "zzownshared", "zzownshared")
			Do $$$AssertStatusNotOK(sc, kind_": "_owner_" is not a session's Ref")
			Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		}
	}
	Set rows = $ClassMethod(probe, "Call", "turns", a, .sc)
	Do $$$AssertStatusOK(sc, "a session's Ref is accepted")
	Do $$$AssertEquals(rows.Count(), 3, "and gives its rows")
	Set rows = $ClassMethod(probe, "Call", "decisions", a, .sc, 1)
	Do $$$AssertStatusOK(sc, "a further argument is bound")

	For read = "Turns", "TurnQueue", "LastRepliedTurn", "Reminders", "Checks", "Incidents", "Approvals", "Pairing" {
		Kill sc
		Set result = $ClassMethod("OcuTalon.Data.Ownership", read, "", .sc)
		Do $$$AssertStatusNotOK(sc, read_" with an empty SessionRef is an error")
	}
	Kill sc
	Set result = ##class(OcuTalon.Data.Ownership).TurnByClient("", "zzownshared", .sc)
	Do $$$AssertEquals(result, "", "TurnByClient with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Kill sc
	Set result = ##class(OcuTalon.Data.Ownership).Decisions("", 20, .sc)
	Do $$$AssertStatusNotOK(sc, "Decisions with an empty SessionRef is an error")
	Kill sc
	Set result = ##class(OcuTalon.Data.Ownership).RecentTurns("", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "RecentTurns with an empty SessionRef is an error")
	Do $$$AssertEquals(result.Count(), 0, "and reads no row")
	Kill sc
	Set result = ##class(OcuTalon.Data.Ownership).RecentIncidents("", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "RecentIncidents with an empty SessionRef is an error")
	Do $$$AssertEquals(result.Count(), 0, "and reads no row")
	Set found = ##class(OcuTalon.Data.Ownership).Incident(ra("incident"), "", .sc)
	Do $$$AssertEquals(found, "", "Incident with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Set found = ##class(OcuTalon.Data.Ownership).Approval(ra("approval"), "", .sc)
	Do $$$AssertEquals(found, "", "Approval with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Set found = ##class(OcuTalon.Data.Ownership).Decision(ra("decision"), "", .sc)
	Do $$$AssertEquals(found, "", "Decision with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Kill sc
	Set result = ##class(OcuTalon.Data.Ownership).RecentNotices("", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "RecentNotices with an empty SessionRef is an error")
	Do $$$AssertEquals(result.Count(), 0, "and reads no row")
	Set result = ##class(OcuTalon.Data.Ownership).RecentPhone("", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "RecentPhone with an empty SessionRef is an error")
	Do $$$AssertEquals(result.Count(), 0, "and reads no row")
	Set found = ##class(OcuTalon.Data.Ownership).DeliveryFor(ra("deliveryapproval"), "web", "", .sc)
	Do $$$AssertEquals(found, "", "DeliveryFor with an empty SessionRef finds nothing")
	Do $$$AssertStatusNotOK(sc, "and says why")
	For owner = "instance", "eval" {
		Set found = ##class(OcuTalon.Data.Ownership).DeliveryFor(ra("deliveryapproval"), "web", owner, .sc)
		Do $$$AssertEquals(found, "", "DeliveryFor for the owner "_owner_" finds nothing")
		Do $$$AssertStatusNotOK(sc, "and says why")
		Set result = ##class(OcuTalon.Data.Ownership).RecentNotices(owner, 100, .sc)
		Do $$$AssertEquals(result.Count(), 0, "RecentNotices for the owner "_owner_" reads no row")
		Do $$$AssertStatusNotOK(sc, "and says why")
		Set result = ##class(OcuTalon.Data.Ownership).RecentPhone(owner, 100, .sc)
		Do $$$AssertEquals(result.Count(), 0, "RecentPhone for the owner "_owner_" reads no row")
		Do $$$AssertStatusNotOK(sc, "and says why")
	}
	Set cost = ##class(OcuTalon.Data.Ownership).RunCost("", "", .sc)
	Do $$$AssertEquals(cost.%ToJSON(), "{}", "RunCost with an empty SessionRef gives {}")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Set cost = ##class(OcuTalon.Data.Ownership).RunCost("eval", "", .sc)
	Do $$$AssertEquals(cost.%ToJSON(), "{}", "RunCost for the owner eval gives {}")
	Do $$$AssertStatusNotOK(sc, "and says why")
}

/// Decision finds a decision of any kind that the session owns, and answers "" for another session's, an eval one, an
/// instance one, an empty or unknown Ref and an empty or eval owner.
Method TestDecisionRead()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"a")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"b")
	Set triage = $ClassMethod(fixture, "Decision", a, "decide")
	Set reply = $ClassMethod(fixture, "Decision", a, "turn")
	Set theirs = $ClassMethod(fixture, "Decision", b, "decide")
	Set eval = $ClassMethod(fixture, "Decision", "eval", "decide")
	Set instance = $ClassMethod(fixture, "Decision", "instance", "decide")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", triage, a, .sc).Ref, triage, "A finds its decide decision")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", reply, a).Kind, "turn", "and its turn decision")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", triage, b, .sc), "", "B does not find A's decision")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", theirs, a), "", "A does not find B's")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", eval, a), "", "an eval decision is not found")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", instance, a), "", "nor an instance decision")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", "", a, .sc), "", "an empty Ref finds nothing")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", "zzmissing"_..Number, a), "", "an unknown Ref finds nothing")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", triage_"' OR '1'='1", a), "", "a Ref is only ever a bound value")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", eval, "eval", .sc), "", "the owner eval finds nothing, even for its own decision")
	Do $$$AssertStatusNotOK(sc, "and says why")
	Do $$$AssertEquals($ClassMethod(ownership, "Decision", instance, "instance", .sc), "", "the owner instance finds nothing, even for its own decision")
	Do $$$AssertStatusNotOK(sc, "and says why")
}

/// TurnCost totals the usage rows of the turn's two decisions that the turn's session owns. Session A's turn has a triage
/// decision with two usage rows (1,000 + 10 input, 300 + 1 output, 50 cache read, 10 cache write, $0.0003 + $0.0001) and a
/// reply decision with one estimated row (84 input, 12 output, $0.0005): 1,094 input, 313 output, 50 cache read, 10 cache
/// write and $0.0009. Rows of session B, of eval and of instance with the same DecisionRefs, and a row of A's for another
/// decision, are not counted. A turn with no usage rows totals 0, a turn with one decision totals that decision's rows, and an
/// unknown turn gives {} and an error.
Method TestTurnCost()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"a")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"b")
	Set triage = $ClassMethod(fixture, "Decision", a, "decide")
	Set reply = $ClassMethod(fixture, "Decision", a, "turn")
	Set other = $ClassMethod(fixture, "Decision", a, "decide")
	Set turn = $ClassMethod(fixture, "Turn", a)
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(turn)
	Set row.TriageDecisionRef = triage
	Set row.TurnDecisionRef = reply
	Do $$$AssertStatusOK(row.%Save(), "the turn has both decisions")
	Do $ClassMethod(fixture, "Usage", triage, a, {"InputTokens": 1000, "OutputTokens": 300, "CacheReadTokens": 50, "CacheWriteTokens": 10, "CostUSD": 0.0003})
	Do $ClassMethod(fixture, "Usage", triage, a, {"InputTokens": 10, "OutputTokens": 1, "CostUSD": 0.0001})
	Do $ClassMethod(fixture, "Usage", reply, a, {"InputTokens": 84, "OutputTokens": 12, "CostUSD": 0.0005, "Estimated": 1})
	Do $ClassMethod(fixture, "Usage", other, a, {"InputTokens": 5000, "OutputTokens": 5000, "CostUSD": 0.9})
	For ref = triage, reply {
		Do $ClassMethod(fixture, "Usage", ref, b, {"InputTokens": 7000, "OutputTokens": 7000, "CacheReadTokens": 7000, "CacheWriteTokens": 7000, "CostUSD": 0.7})
		Do $ClassMethod(fixture, "Usage", ref, "eval", {"InputTokens": 8000, "OutputTokens": 8000, "CacheReadTokens": 8000, "CacheWriteTokens": 8000, "CostUSD": 0.8})
		Do $ClassMethod(fixture, "Usage", ref, "instance", {"InputTokens": 6000, "OutputTokens": 6000, "CacheReadTokens": 6000, "CacheWriteTokens": 6000, "CostUSD": 0.6})
	}
	Set cost = $ClassMethod(ownership, "TurnCost", turn, .sc)
	Do $$$AssertStatusOK(sc, "the totals are read")
	Do $$$AssertEquals(+cost.inputTokens, 1094, "input tokens: 1,000 + 10 + 84 and no other owner's")
	Do $$$AssertEquals(+cost.outputTokens, 313, "output tokens: 300 + 1 + 12")
	Do $$$AssertEquals(+cost.cacheReadTokens, 50, "cache-read tokens")
	Do $$$AssertEquals(+cost.cacheWriteTokens, 10, "cache-write tokens")
	Do $$$AssertEquals(+cost.costUSD, 0.0009, "cost: 0.0003 + 0.0001 + 0.0005")
	Do $$$AssertEquals(cost.%GetTypeOf("costUSD")_"|"_cost.%GetTypeOf("inputTokens"), "number|number", "the totals are numbers")

	Set lone = $ClassMethod(fixture, "Turn", a)
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(lone)
	Set row.TurnDecisionRef = reply
	Do $$$AssertStatusOK(row.%Save(), "a turn with a reply decision only")
	Set cost = $ClassMethod(ownership, "TurnCost", lone, .sc)
	Do $$$AssertStatusOK(sc, "is read")
	Do $$$AssertEquals(+cost.inputTokens_"|"_+cost.outputTokens_"|"_+cost.costUSD, "84|12|.0005", "and totals that decision's rows")
	Set none = $ClassMethod(fixture, "Turn", a)
	Set cost = $ClassMethod(ownership, "TurnCost", none, .sc)
	Do $$$AssertStatusOK(sc, "a turn with no decision is read")
	Do $$$AssertEquals(+cost.inputTokens_"|"_+cost.outputTokens_"|"_+cost.cacheReadTokens_"|"_+cost.cacheWriteTokens_"|"_+cost.costUSD, "0|0|0|0|0", "and totals 0 for each figure")
	Do $$$AssertEquals(cost.%GetTypeOf("costUSD"), "number", "as numbers")
	Set missing = $ClassMethod(ownership, "TurnCost", "zzmissing"_..Number, .sc)
	Do $$$AssertEquals(missing.%ToJSON(), "{}", "an unknown turn gives {}")
	Do $$$AssertStatusNotOK(sc, "and an error")
	Set missing = $ClassMethod(ownership, "TurnCost", "", .sc)
	Do $$$AssertEquals(missing.%ToJSON(), "{}", "so does an empty Ref")
	Do $$$AssertStatusNotOK(sc, "with an error")
}

/// RunCost totals the session's usage rows recorded since a time and counts its decisions from then on. Session A has usage
/// rows at 10:00 (claude-haiku-5-5; 100 input, 10 output, 5 cache read, 1 cache write, $0.0010), 10:05 (claude-sonnet-5-5; 200,
/// 20, 6, 2, $0.0020) and 10:10 (claude-haiku-5-5; 300, 30, 7, 3, $0.0030), and decisions at the same times. Since 10:05 the
/// totals are those of the last two rows (500, 50, 13, 5, $0.0050), with 2 decisions and the models in first-use order
/// (sonnet, haiku); an empty since counts all three (600, 60, 18, 6, $0.0060; 3 decisions; haiku, sonnet). Rows of session B
/// and of eval are not counted. A read that fails gives {} and an error.
Method TestRunCost()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"a")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"b")
	Set haiku = "claude-haiku-5-5", sonnet = "claude-sonnet-5-5"
	Set d1 = $ClassMethod(fixture, "Decision", a, "decide", "2030-01-01T10:00:00Z")
	Set d2 = $ClassMethod(fixture, "Decision", a, "decide", "2030-01-01T10:05:00Z")
	Set d3 = $ClassMethod(fixture, "Decision", a, "turn", "2030-01-01T10:10:00Z")
	Do $ClassMethod(fixture, "Usage", d1, a, {"RecordedAt": "2030-01-01T10:00:00Z", "Model": (haiku), "InputTokens": 100, "OutputTokens": 10, "CacheReadTokens": 5, "CacheWriteTokens": 1, "CostUSD": 0.001})
	Do $ClassMethod(fixture, "Usage", d2, a, {"RecordedAt": "2030-01-01T10:05:00Z", "Model": (sonnet), "InputTokens": 200, "OutputTokens": 20, "CacheReadTokens": 6, "CacheWriteTokens": 2, "CostUSD": 0.002})
	Do $ClassMethod(fixture, "Usage", d3, a, {"RecordedAt": "2030-01-01T10:10:00Z", "Model": (haiku), "InputTokens": 300, "OutputTokens": 30, "CacheReadTokens": 7, "CacheWriteTokens": 3, "CostUSD": 0.003})
	Set e1 = $ClassMethod(fixture, "Decision", "eval", "decide", "2030-01-01T10:10:00Z")
	Do $ClassMethod(fixture, "Usage", e1, "eval", {"RecordedAt": "2030-01-01T10:10:00Z", "InputTokens": 9000, "OutputTokens": 9000, "CostUSD": 0.9})
	Set b1 = $ClassMethod(fixture, "Decision", b, "decide", "2030-01-01T10:10:00Z")
	Do $ClassMethod(fixture, "Usage", b1, b, {"RecordedAt": "2030-01-01T10:10:00Z", "InputTokens": 8000, "OutputTokens": 8000, "CostUSD": 0.8})

	Set cost = $ClassMethod(ownership, "RunCost", a, "2030-01-01T10:05:00Z", .sc)
	Do $$$AssertStatusOK(sc, "the totals are read")
	Do $$$AssertEquals(+cost.decisions, 2, "decisions since 10:05: the one at 10:05 and the one at 10:10")
	Do $$$AssertEquals(+cost.inputTokens_"|"_+cost.outputTokens_"|"_+cost.cacheReadTokens_"|"_+cost.cacheWriteTokens_"|"_+cost.costUSD, "500|50|13|5|.005", "the last two rows' totals")
	Do $$$AssertEquals(cost.models.%ToJSON(), "[""claude-sonnet-5-5"",""claude-haiku-5-5""]", "models in first-use order")
	Set cost = $ClassMethod(ownership, "RunCost", a, "", .sc)
	Do $$$AssertStatusOK(sc, "an empty since is read")
	Do $$$AssertEquals(+cost.decisions, 3, "an empty since counts every decision")
	Do $$$AssertEquals(+cost.inputTokens_"|"_+cost.outputTokens_"|"_+cost.cacheReadTokens_"|"_+cost.cacheWriteTokens_"|"_+cost.costUSD, "600|60|18|6|.006", "and every row")
	Do $$$AssertEquals(cost.models.%ToJSON(), "[""claude-haiku-5-5"",""claude-sonnet-5-5""]", "with the models in first-use order")
	Set cost = $ClassMethod(ownership, "RunCost", a, "2030-01-01T10:10:01Z", .sc)
	Do $$$AssertStatusOK(sc, "a time after every row is read")
	Do $$$AssertEquals(+cost.decisions_"|"_+cost.inputTokens_"|"_+cost.costUSD_"|"_cost.models.%Size(), "0|0|0|0", "and totals nothing")
	Set cost = $ClassMethod(ownership, "RunCost", b, "", .sc)
	Do $$$AssertEquals(+cost.decisions_"|"_+cost.inputTokens_"|"_+cost.costUSD, "1|8000|.8", "B totals only its own rows")
	Set cost = $ClassMethod(ownership, "RunCost", "eval", "", .sc)
	Do $$$AssertEquals(cost.%ToJSON(), "{}", "the owner eval gives {}")
	Do $$$AssertStatusNotOK(sc, "and an error")
}

/// TurnByClient finds the session's turn of a page's clientId, matching the clientId exactly (case included), and answers ""
/// for an empty clientId, an unknown one, and another session's: both sessions can hold the same clientId.
Method TestTurnByClient()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Turn(a, , "done", "zz mine", "zzClient"_..Number)
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Turn(b, , "queued", "zz theirs", "zzClient"_..Number)
	Set only = ##class(OcuTalon.Test.Data.Fixture).Turn(b, , "queued", "zz only b", "zzOnlyB"_..Number)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzClient"_..Number, .sc).Ref, mine, "A finds its turn")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(b, "zzClient"_..Number).Ref, theirs, "B finds its own turn for the same clientId")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzOnlyB"_..Number, .sc), "", "A does not find B's clientId")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzclient"_..Number), "", "the clientId matches exactly: another case finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, ""), "", "an empty clientId finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzunknown"), "", "an unknown clientId finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzClient"_..Number_"' OR '1'='1"), "", "a clientId is only ever a bound value")
}

/// TurnOfItem finds the session's turn made from an Item, matching the ItemId exactly (case included), and answers "" for
/// an empty ItemId, an unknown one, one that differs only in case, and another session's turn; an owner that is no session
/// (empty, eval, instance) is an error. The turn comes back whole, with the header and the indexes of its trace.
Method TestTurnOfItem()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Set mine = ##class(OcuTalon.Test.Data.Fixture).Turn(a, , "done", "zz mine")
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Turn(b, , "done", "zz theirs")
	Set item = "ZzItem"_..Number_"Mine"
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(mine)
	Set row.ItemId = item
	Set row.TraceHeaderId = 9001
	Set row.TraceItemIndex = 46
	Set row.TraceItemIndexNoEvents = 30
	Do $$$AssertStatusOK(row.%Save(), "A's turn takes its Item and its trace target")
	Set other = "ZzItem"_..Number_"Theirs"
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(theirs)
	Set row.ItemId = other
	Do $$$AssertStatusOK(row.%Save(), "B's turn takes its Item")
	Set found = ##class(OcuTalon.Data.Ownership).TurnOfItem(item, a, .sc)
	Do $$$AssertEquals(found.Ref, mine, "A finds its turn by the Item")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Do $$$AssertEquals(found.TraceHeaderId_"|"_found.TraceItemIndex_"|"_found.TraceItemIndexNoEvents, "9001|46|30", "and the turn carries its trace target and indexes")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem(other, b).Ref, theirs, "B finds its own turn by its own Item")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem(other, a, .sc), "", "A does not find B's turn")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem(item, b, .sc), "", "B does not find A's turn")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem("ZzItem"_..Number_"Unknown", a, .sc), "", "an unknown Item finds nothing")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem($ZConvert(item, "L"), a, .sc), "", "the Item matches exactly: another case finds nothing")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem($ZConvert(item, "U"), a), "", "nor does the upper case")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem("", a, .sc), "", "an empty Item finds nothing")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem(item_"' OR '1'='1", a), "", "an Item is only ever a bound value")
	For owner = "", "eval", "instance" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnOfItem(item, owner, .sc), "", "the owner '"_owner_"' finds nothing")
		Do $$$AssertStatusNotOK(sc, "and says why")
	}
}

/// TurnQueue holds the session's queued and running turns, never a done one, by CreatedAt and then ID.
Method TestTurnQueueOrder()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Set late = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:03Z", "queued")
	Set early = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z", "queued")
	Set tied = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z", "running")
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:00Z", "done")
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(b, "2030-01-01T10:00:02Z", "queued")
	Set rows = ##class(OcuTalon.Data.Ownership).TurnQueue(a, .sc)
	Do $$$AssertStatusOK(sc, "the queue is read")
	Do $$$AssertEquals(..Refs(rows), early_","_tied_","_late, "queued and running only, by CreatedAt and then ID")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnQueue(##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"c")).Count(), 0, "a session with no turn has an empty queue")
}

/// LastRepliedTurn is the newest done turn that has a reply decision: a done turn without one, and a turn that is not done, are
/// skipped; the newest by CreatedAt wins, and the later ID wins a tie.
Method TestLastRepliedTurn()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzown"_..Number_"b")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastRepliedTurn(a, .sc), "", "no turn: none")
	Do $$$AssertStatusOK(sc, "and that is not an error")
	Set plain = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:05Z", "done")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastRepliedTurn(a), "", "a done turn with no reply decision is skipped")
	Set old = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z", "done")
	Set first = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:02Z", "done")
	Set second = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:02Z", "done")
	Set running = ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:09Z", "running")
	Set other = ##class(OcuTalon.Test.Data.Fixture).Turn(b, "2030-01-01T10:00:09Z", "done")
	For ref = old, first, second, running, other {
		Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
		Set row.TurnDecisionRef = "zzdecision"
		Do row.%Save()
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastRepliedTurn(a).Ref, second, "the newest done turn with a reply decision: the later ID wins a tie, a running turn and another session's are skipped")
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(second)
	Set row.Tainted = 1
	Do row.%Save()
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastRepliedTurn(a).Tainted, 1, "and its Tainted flag is readable")
}

/// RecentNotices gives the session's web cards of the kinds tellnow and reminder, newest RecordedAt first and then newest ID
/// first, at most max: a card of another kind, of another channel, a reply (kind empty) and another session's cards are left out,
/// and every kind that WebChatOut makes a card of (its CARDKINDS) is one.
/// DeliveryFor gives the newest row for the approval Ref and channel, and "" for a Ref in another case, another channel, another
/// session and an empty value.
Method TestRecentNotices()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"na")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"nb")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentNotices", a)), "", "no cards to begin with")
	Set c1 = $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:02Z"})
	Set c2 = $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:03Z", "Kind": "reminder"})
	Set c3 = $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:03Z"})
	Set c4 = $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:01Z"})
	Do $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:09Z", "Kind": "incident"})
	Do $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:09Z", "Kind": ""})
	Do $ClassMethod(fixture, "Delivery", a, {"RecordedAt": "2030-01-01T10:00:09Z", "Channel": "telegram"})
	Do $ClassMethod(fixture, "Delivery", b, {"RecordedAt": "2030-01-01T10:00:09Z"})
	Do $ClassMethod(fixture, "Delivery", "instance", {"RecordedAt": "2030-01-01T10:00:09Z"})
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentNotices", a)), c3_","_c2_","_c1_","_c4, "the cards of kind tellnow and reminder on the web, newest first, the later ID first at the same second")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentNotices", a, 2)), c3_","_c2, "at most max of them, the newest")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentNotices", a, 1)), c3, "one")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentNotices", b).Count(), 1, "another session has its own card only")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentNotices", ##class(OcuTalon.Bridge.Ids).NewRef()).Count(), 0, "a session with no row has none")
	Set kinds = $ListFromString(##class(OcuTalon.Channel.WebChat.Out).#CARDKINDS)
	Set tied = $ClassMethod(fixture, "Session", "zzown"_..Number_"nc")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Do $ClassMethod(fixture, "Delivery", tied, {"RecordedAt": "2030-01-01T10:00:05Z", "Kind": (kind)})
	}
	Do $$$AssertEquals($ClassMethod(ownership, "RecentNotices", tied).Count(), $ListLength(kinds), "every kind that WebChatOut makes a card of is a card of the snapshot's chat")

	Set approval = "ZzApproval"_..Number
	Do $ClassMethod(fixture, "Delivery", a, {"ApprovalRef": (approval), "Channel": "telegram", "Kind": "", "ChannelMessageId": "ZzChat:1"})
	Set d2 = $ClassMethod(fixture, "Delivery", a, {"ApprovalRef": (approval), "Channel": "telegram", "Kind": "", "ChannelMessageId": "ZzChat:2"})
	Do $ClassMethod(fixture, "Delivery", b, {"ApprovalRef": (approval), "Channel": "telegram", "Kind": "", "ChannelMessageId": "ZzTheirs:1"})
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", approval, "telegram", a).ChannelMessageId, d2, "DeliveryFor gives the newest row of the session for the approval Ref and channel")
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", approval, "telegram", b).ChannelMessageId, "ZzTheirs:1", "another session gets its own")
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", approval, "phone", a), "", "another channel finds nothing")
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", $ZConvert(approval, "L"), "telegram", a), "", "a Ref in another case finds nothing")
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", "", "telegram", a), "", "an empty Ref finds nothing")
	Do $$$AssertEquals($ClassMethod(ownership, "DeliveryFor", approval, "", a), "", "an empty channel finds nothing")
}

/// RecentPhone gives the session's simulated-phone messages (SimMessage rows of Kind phone), newest CreatedAt first and then
/// newest ID first, at most max: a mailbox message and another session's messages are left out.
Method TestRecentPhone()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"pa")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"pb")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentPhone", a)), "", "no messages to begin with")
	Set m1 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:02Z"})
	Set m2 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:03Z"})
	Set m3 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:03Z"})
	Set m4 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:01Z"})
	Do $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:09Z", "Kind": "mailbox"})
	Do $ClassMethod(fixture, "SimMessage", b, {"CreatedAt": "2030-01-01T10:00:09Z"})
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentPhone", a)), m3_","_m2_","_m1_","_m4, "the phone messages, newest first, the later ID first at the same second")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentPhone", a, 2)), m3_","_m2, "at most max of them, the newest")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentPhone", b).Count(), 1, "another session has its own message only")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentPhone", ##class(OcuTalon.Bridge.Ids).NewRef()).Count(), 0, "a session with no row has none")
}

/// RecentMail gives the session's simulated-mailbox emails (SimMessage rows of Kind mailbox, incoming and sent), newest CreatedAt
/// first and then newest ID first, at most max: phone messages and another session's emails are left out.
Method TestRecentMail()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"ma")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"mb")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentMail", a)), "", "no emails to begin with")
	Set m1 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:02Z", "Kind": "mailbox", "Direction": "in"})
	Set m2 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:03Z", "Kind": "mailbox", "Direction": "out"})
	Set m3 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:03Z", "Kind": "mailbox", "Direction": "in"})
	Set m4 = $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:01Z", "Kind": "mailbox", "Direction": "in"})
	Do $ClassMethod(fixture, "SimMessage", a, {"CreatedAt": "2030-01-01T10:00:09Z"})
	Do $ClassMethod(fixture, "SimMessage", b, {"CreatedAt": "2030-01-01T10:00:09Z", "Kind": "mailbox", "Direction": "in"})
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentMail", a)), m3_","_m2_","_m1_","_m4, "the emails, newest first, the later ID first at the same second, with no phone message")
	Do $$$AssertEquals(..Refs($ClassMethod(ownership, "RecentMail", a, 2)), m3_","_m2, "at most max of them, the newest")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentMail", b).Count(), 1, "another session has its own email only")
	Do $$$AssertEquals($ClassMethod(ownership, "RecentMail", ##class(OcuTalon.Bridge.Ids).NewRef()).Count(), 0, "a session with no row has none")
	Do $ClassMethod(ownership, "RecentMail", "", 100, .sc)
	Do $$$AssertStatusNotOK(sc, "an empty SessionRef is an error")
}

/// DecisionOfItem gives the session's own decision of kind decide for an Item: a decision of another owner, one of another kind
/// for the same Item, an empty ItemId, an unknown one and one that differs only in case answer "".
Method TestDecisionOfItem()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ownership = "OcuTalon.Data.Ownership"
	Set a = $ClassMethod(fixture, "Session", "zzown"_..Number_"da")
	Set b = $ClassMethod(fixture, "Session", "zzown"_..Number_"db")
	Set own = $ClassMethod(fixture, "Decision", a)
	Set ownItem = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(own).ItemId
	Set theirs = $ClassMethod(fixture, "Decision", b)
	Set theirItem = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(theirs).ItemId
	Set turn = $ClassMethod(fixture, "Decision", a, "turn")
	Set turnItem = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(turn).ItemId
	Set found = $ClassMethod(ownership, "DecisionOfItem", ownItem, a, .sc)
	Do $$$AssertStatusOK(sc, "the read works")
	Do $$$AssertEquals($IsObject(found) && (found.Ref = own), 1, "the session's own decide decision is found")
	Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", theirItem, a), "", "another owner's decision is not found")
	Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", ownItem, b), "", "nor by another session")
	Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", turnItem, a), "", "a decision of kind turn is not found")
	Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", "", a), "", "an empty ItemId finds nothing")
	Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", $ZConvert(ownItem, "L")_"x", a), "", "an unknown ItemId finds nothing")
	If $ZConvert(ownItem, "L") '= ownItem Do $$$AssertEquals($ClassMethod(ownership, "DecisionOfItem", $ZConvert(ownItem, "L"), a), "", "an ItemId in another case finds nothing")
	Do $ClassMethod(ownership, "DecisionOfItem", ownItem, "", .sc)
	Do $$$AssertStatusNotOK(sc, "an empty SessionRef is an error")
}

/// --- helpers ---
/// One row of every kind for the session: ref(kind) = the row's Ref. Its incident is noticed and its approval pending.
ClassMethod Seed(sessionRef As %String, Output ref) [ Private ]
{
	Kill ref
	Set ref("turn") = ##class(OcuTalon.Test.Data.Fixture).Turn(sessionRef, "2030-01-01T10:00:01Z")
	Set ref("itemid") = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref("turn")).ItemId
	Set ref("queued") = ##class(OcuTalon.Test.Data.Fixture).Turn(sessionRef, "2030-01-01T10:00:02Z", "queued", "zz queued", "zzownshared")
	Set ref("replied") = ##class(OcuTalon.Test.Data.Fixture).Turn(sessionRef, "2030-01-01T10:00:03Z", "done", "zz replied", "zzownreplied")
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref("replied"))
	Set row.TurnDecisionRef = "zzdecision"
	Do row.%Save()
	Set ref("turns") = ref("turn")_","_ref("queued")_","_ref("replied")
	Set ref("recentturns") = ref("replied")_","_ref("queued")_","_ref("turn")
	Set ref("reminder") = ##class(OcuTalon.Test.Data.Fixture).Reminder(sessionRef)
	Set ref("check") = ##class(OcuTalon.Test.Data.Fixture).Check(sessionRef, "ZZNS", "Zz.Seed."_$Extract(sessionRef, 1, 6))
	Set ref("decision") = ##class(OcuTalon.Test.Data.Fixture).Decision(sessionRef)
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref("decision"), sessionRef)
	Set ref("incident") = ##class(OcuTalon.Test.Data.Fixture).Incident(sessionRef)
	Set ref("approval") = ##class(OcuTalon.Test.Data.Fixture).Approval(sessionRef, ref("incident"))
	Set ref("pairing") = ##class(OcuTalon.Test.Data.Fixture).Pairing(sessionRef)
	Set ref("deliveryapproval") = "ZzApproval"_$Extract(sessionRef, 1, 12)
	Set ref("notice") = ##class(OcuTalon.Test.Data.Fixture).Delivery(sessionRef, {"ApprovalRef": (ref("deliveryapproval")), "Kind": "reminder"})
	Do ##class(OcuTalon.Test.Data.Fixture).Delivery(sessionRef, {"Kind": "incident", "ChannelMessageId": ""})
	Do ##class(OcuTalon.Test.Data.Fixture).Delivery(sessionRef, {"Channel": "telegram", "ApprovalRef": (ref("deliveryapproval"))})
	Set ref("phone") = ##class(OcuTalon.Test.Data.Fixture).SimMessage(sessionRef)
	Set ref("mail") = ##class(OcuTalon.Test.Data.Fixture).SimMessage(sessionRef, {"Kind": "mailbox", "Direction": "in"})
	Set ref("decisionitem") = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref("decision")).ItemId
}

/// Every read of the session: seen(read) = the Refs it returned, comma-separated (a usage row stands for its DecisionRef).
/// With decisionRef, also the decision find and the usage reads that name it: seen("decision"), seen("turnusage") (both the
/// turn's decision refs set to it), seen("runusage") and seen("rundecisions") (since a time long ago). With itemId, also the turn
/// of that Item: seen("turnofitem"). With decisionItemId, also the session's decide decision of that Item: seen("decisionofitem").
Method ReadAll(sessionRef As %String, Output seen, decisionRef As %String = "", approvalRef As %String = "", itemId As %String = "", decisionItemId As %String = "") [ Private ]
{
	Kill seen
	If itemId '= "" {
		Set turn = ##class(OcuTalon.Data.Ownership).TurnOfItem(itemId, sessionRef, .sc)
		Do $$$AssertStatusOK(sc, "TurnOfItem reads")
		Set seen("turnofitem") = $Select($IsObject(turn): turn.Ref, 1: "")
	}
	If decisionRef '= "" {
		Set found = ##class(OcuTalon.Data.Ownership).Decision(decisionRef, sessionRef, .sc)
		Do $$$AssertStatusOK(sc, "Decision reads")
		Set seen("decision") = $Select($IsObject(found): found.Ref, 1: "")
		Set probe = "OcuTalon.Test.Data.OwnershipProbe"
		Set rows = $ClassMethod(probe, "Call", "turnUsage", sessionRef, .sc, decisionRef, decisionRef)
		Do $$$AssertStatusOK(sc, "the turn usage reads")
		Set seen("turnusage") = ..Refs(rows)
		Set rows = $ClassMethod(probe, "Call", "runUsage", sessionRef, .sc, "2000-01-01T00:00:00Z")
		Do $$$AssertStatusOK(sc, "the run usage reads")
		Set seen("runusage") = ..Refs(rows)
		Set rows = $ClassMethod(probe, "Call", "runDecisions", sessionRef, .sc, "2000-01-01T00:00:00Z")
		Do $$$AssertStatusOK(sc, "the run decisions read")
		Set seen("rundecisions") = ..Refs(rows)
	}
	Set ownership = "OcuTalon.Data.Ownership"
	For read = "Turns", "Reminders", "Checks", "Incidents", "Approvals" {
		Set rows = $ClassMethod(ownership, read, sessionRef, .sc)
		Do $$$AssertStatusOK(sc, read_" reads")
		Set seen($ZConvert(read, "L")) = ..Refs(rows)
	}
	Set rows = ##class(OcuTalon.Data.Ownership).Decisions(sessionRef, 20, .sc)
	Do $$$AssertStatusOK(sc, "Decisions reads")
	Set seen("decisions") = ..Refs(rows)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentTurns(sessionRef, 100, .sc)
	Do $$$AssertStatusOK(sc, "RecentTurns reads")
	Set seen("recentturns") = ..Refs(rows)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentIncidents(sessionRef, 100, .sc)
	Do $$$AssertStatusOK(sc, "RecentIncidents reads")
	Set seen("recentincidents") = ..Refs(rows)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentNotices(sessionRef, 100, .sc)
	Do $$$AssertStatusOK(sc, "RecentNotices reads")
	Set seen("recentnotices") = ..Refs(rows)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(sessionRef, 100, .sc)
	Do $$$AssertStatusOK(sc, "RecentPhone reads")
	Set seen("recentphone") = ..Refs(rows)
	Set rows = ##class(OcuTalon.Data.Ownership).RecentMail(sessionRef, 100, .sc)
	Do $$$AssertStatusOK(sc, "RecentMail reads")
	Set seen("recentmail") = ..Refs(rows)
	Set found = ##class(OcuTalon.Data.Ownership).DecisionOfItem(decisionItemId, sessionRef, .sc)
	Do $$$AssertStatusOK(sc, "DecisionOfItem reads")
	Set seen("decisionofitem") = $Select($IsObject(found): found.Ref, 1: "")
	Set found = ##class(OcuTalon.Data.Ownership).DeliveryFor(approvalRef, "web", sessionRef, .sc)
	Do $$$AssertStatusOK(sc, "DeliveryFor reads")
	Set seen("delivery") = $Select($IsObject(found): found.ChannelMessageId, 1: "")
	Set rows = ##class(OcuTalon.Data.Ownership).TurnQueue(sessionRef, .sc)
	Do $$$AssertStatusOK(sc, "TurnQueue reads")
	Set seen("turnqueue") = ..Refs(rows)
	Set turn = ##class(OcuTalon.Data.Ownership).LastRepliedTurn(sessionRef, .sc)
	Do $$$AssertStatusOK(sc, "LastRepliedTurn reads")
	Set seen("lastreplied") = $Select($IsObject(turn): turn.Ref, 1: "")
	Set turn = ##class(OcuTalon.Data.Ownership).TurnByClient(sessionRef, "zzownshared", .sc)
	Do $$$AssertStatusOK(sc, "TurnByClient reads")
	Set seen("turnbyclient") = $Select($IsObject(turn): turn.Ref, 1: "")
	Set pairing = ##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc)
	Do $$$AssertStatusOK(sc, "Pairing reads")
	Set seen("pairing") = $Select($IsObject(pairing): pairing.Ref, 1: "")
}

/// The Refs of the rows of a list, in order, comma-separated. A usage row has no Ref, and stands for its DecisionRef; a Delivery
/// row has none either, and stands for its ChannelMessageId.
ClassMethod Refs(rows As %ListOfObjects) As %String [ Private ]
{
	Set refs = ""
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set refs = refs_$Select(refs = "": "", 1: ",")_$Select(row.%IsA("OcuTalon.Bridge.Data.Usage"): row.DecisionRef, row.%IsA("OcuTalon.Data.Delivery"): row.ChannelMessageId, 1: row.Ref)
	}
	Quit refs
}

/// Records the user's session rows for Clean (a row made by Attach or ForUser).
ClassMethod AdoptUser(user As %String) [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT ID FROM OcuTalon_Data.Session WHERE IrisUser = ?")
	Set result = statement.%Execute(user)
	While result.%Next() {
		Do ##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Session).%OpenId(result.%Get("ID")))
	}
}

}
