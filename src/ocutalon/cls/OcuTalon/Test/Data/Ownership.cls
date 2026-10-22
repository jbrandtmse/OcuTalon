/// Tests of the ownership API (Story 2.2; AD-4, AD-13 as amended): how the CSP session is attached and resolved, what
/// each read returns and in which order, the scope of instance records, that an incident is visible only once noticed,
/// that an eval record never is, that a find answers "" for everything a session can't see, that a second session gets
/// none of the first session's rows for every row kind (condition 3), and that Rows refuses an empty owner and an
/// unknown kind (condition 1). Every row comes from Test.Data.Fixture, which Clean removes; the users are zzown<n>, with n
/// from ^OcuTalonTest("Ownership","n") (never reset). onlineDemo is saved and put back.
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
	Set watchers = ##class(OcuTalon.Data.Ownership).Watchers("ZZNS", one)
	Do $$$AssertEquals($ListLength(watchers), 2, "two sessions watch the first production")
	Do $$$AssertTrue($ListFind(watchers, a) && $ListFind(watchers, b), "A and B")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", two)), 1, "one watches the second")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", "Zz.Nobody"), "", "none watches another")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("", one), "", "an empty namespace gives none")

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
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Watchers("ZZNS", one), "", "and nobody watches")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
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
	Do ..ReadAll(a, .seenA)
	Do ..ReadAll(b, .seenB)
	Set kinds = $ListBuild($ListBuild("turns", "turns"), $ListBuild("turnqueue", "queued"), $ListBuild("lastreplied", "replied"), $ListBuild("turnbyclient", "queued"), $ListBuild("reminders", "reminder"), $ListBuild("checks", "check"), $ListBuild("decisions", "decision"), $ListBuild("incidents", "incident"), $ListBuild("approvals", "approval"), $ListBuild("pairing", "pairing"), $ListBuild("recentturns", "recentturns"), $ListBuild("recentincidents", "incident"))
	Set position = 0
	While $ListNext(kinds, position, pair) {
		Set read = $List(pair, 1), kind = $List(pair, 2)
		Do $$$AssertEquals(seenA(read), ra(kind), "A reads only its own "_kind)
		Do $$$AssertEquals(seenB(read), rb(kind), "B reads only its own "_kind)
		Do $$$AssertTrue(seenB(read) '[ ra(kind), "B's "_read_" holds none of A's")
		Do $$$AssertTrue(seenA(read) '[ rb(kind), "A's "_read_" holds none of B's")
	}
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
	For kind = "turnByClient", "turnQueue", "lastReplied", "recentTurns", "recentIncidents" {
		Set rows = $ClassMethod(probe, "Call", kind, "", .sc, "zzownshared")
		Do $$$AssertStatusNotOK(sc, kind_": an empty owner Ref is an error")
		Do $$$AssertEquals(rows.Count(), 0, kind_": with no rows")
		Set rows = $ClassMethod(probe, "Call", kind, "eval", .sc, "zzownshared")
		Do $$$AssertStatusNotOK(sc, kind_": eval is not a session's Ref")
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

/// --- helpers ---
/// One row of every kind for the session: ref(kind) = the row's Ref. Its incident is noticed and its approval pending.
ClassMethod Seed(sessionRef As %String, Output ref) [ Private ]
{
	Kill ref
	Set ref("turn") = ##class(OcuTalon.Test.Data.Fixture).Turn(sessionRef, "2030-01-01T10:00:01Z")
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
	Set ref("incident") = ##class(OcuTalon.Test.Data.Fixture).Incident(sessionRef)
	Set ref("approval") = ##class(OcuTalon.Test.Data.Fixture).Approval(sessionRef, ref("incident"))
	Set ref("pairing") = ##class(OcuTalon.Test.Data.Fixture).Pairing(sessionRef)
}

/// Every read of the session: seen(read) = the Refs it returned, comma-separated.
Method ReadAll(sessionRef As %String, Output seen) [ Private ]
{
	Kill seen
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

/// The Refs of the rows of a list, in order, comma-separated.
ClassMethod Refs(rows As %ListOfObjects) As %String [ Private ]
{
	Set refs = ""
	For i = 1:1:rows.Count() {
		Set refs = refs_$Select(refs = "": "", 1: ",")_rows.GetAt(i).Ref
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
