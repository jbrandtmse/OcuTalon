/// Tests of Data.Session: ForUser (matrix row 8), one durable row per IRIS user, matched without regard to case, with a
/// Ref, a TraceRef and an Epoch of its own; and Recipients (Story 2.2), who receives what an owner owns. The fixture
/// users are zzsess<n> and zzsessother<n>, with n from ^OcuTalonTest("SessionForUser","n") (never reset);
/// OnBeforeAllTests and OnAfterAllTests delete every session row of a user name that starts with zzsess, and the rows
/// of Test.Data.Fixture. onlineDemo is saved and put back.
Class OcuTalon.Test.Data.Session Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SessionForUser", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// The first call creates the row; a second call, and one with the user name in upper case, return the same row and
/// the same Epoch. The row's references are distinct 22-character base64url strings.
Method TestFindsOrCreates()
{
	Set user = "zzsess"_..Number
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 0, "no row to begin with")
	Set first = ##class(OcuTalon.Data.Session).ForUser(user, .sc)
	Do $$$AssertStatusOK(sc, "the first call")
	Do $$$AssertTrue($IsObject(first), "the first call returns the row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 1, "one row is created")
	Do $$$AssertEquals(first.IrisUser, user, "the row keeps the user name")
	For field = "Ref", "TraceRef", "Epoch" {
		Do $$$AssertTrue($Property(first, field) ? 22(1AN,1"-",1"_"), field_" is 22 base64url characters: "_$Property(first, field))
	}
	Do $$$AssertTrue((first.Ref '= first.TraceRef) && (first.Ref '= first.Epoch) && (first.TraceRef '= first.Epoch), "Ref, TraceRef and Epoch differ")
	Do $$$AssertTrue(first.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "CreatedAt is a Utc time: "_first.CreatedAt)

	Set again = ##class(OcuTalon.Data.Session).ForUser(user, .sc)
	Do $$$AssertStatusOK(sc, "the second call")
	Do $$$AssertEquals(again.%Id(), first.%Id(), "the second call returns the same row")
	Do $$$AssertEquals(again.Epoch, first.Epoch, "with the same Epoch")
	Set upper = ##class(OcuTalon.Data.Session).ForUser($ZConvert(user, "U"), .sc)
	Do $$$AssertStatusOK(sc, "the call with the user in upper case")
	Do $$$AssertEquals(upper.%Id(), first.%Id(), "it returns the same row")
	Do $$$AssertEquals(upper.Epoch, first.Epoch, "with the same Epoch")
	Do $$$AssertEquals(upper.Ref, first.Ref, "and the same Ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 1, "still one row")

	Set other = ##class(OcuTalon.Data.Session).ForUser("zzsessother"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "another user")
	Do $$$AssertTrue(other.%Id() '= first.%Id(), "another user has another row")
	Do $$$AssertTrue((other.Ref '= first.Ref) && (other.TraceRef '= first.TraceRef) && (other.Epoch '= first.Epoch), "with other references")
}

/// NewVisitor and ForResume (Story 16.3, matrix rows 1 and 5): a visitor row is always created, with its own Ref, TraceRef and Epoch,
/// the user, the CSP session id and the SHA-256 (base64url, 43 characters, no padding) of a new 22-character reference, and no
/// property equals the reference; two calls for one user make two rows; ForResume opens the row of the reference and answers "" for
/// a malformed value, an unknown reference and the empty string; an empty user is refused with no row.
Method TestNewVisitorAndForResume()
{
	Set user = "zzsess"_..Number_"visitor"
	Set first = ##class(OcuTalon.Data.Session).NewVisitor(user, "ZzSessVisitorA", .reference, .sc)
	Do $$$AssertStatusOK(sc, "the first call")
	Do $$$AssertTrue($IsObject(first), "it returns a row")
	If '$IsObject(first) Quit
	Do ##class(OcuTalon.Test.Data.Fixture).Adopt(first)
	Do $$$AssertTrue(reference ? 22(1AN,1"-",1"_"), "the reference is 22 base64url characters")
	Do $$$AssertEquals(first.ResumeHash, ##class(OcuTalon.Data.Session).Hash(reference), "the row keeps the hash")
	Do $$$AssertTrue(first.ResumeHash ? 43(1AN,1"-",1"_"), "the hash is 43 base64url characters: "_first.ResumeHash)
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Hash(""), "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU", "the hash of the empty text is SHA-256's")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Hash("abc"), "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0", "the hash of abc is SHA-256's")
	Do $$$AssertEquals(first.CspSessionId, "ZzSessVisitorA", "the row records the CSP session")
	Do $$$AssertEquals(first.IrisUser, user, "and the user")
	For field = "Ref", "TraceRef", "Epoch" {
		Do $$$AssertTrue($Property(first, field) ? 22(1AN,1"-",1"_"), field_" is 22 base64url characters")
	}
	Set found = 0
	For field = "Ref", "TraceRef", "IrisUser", "CreatedAt", "Epoch", "ThreadSessionId", "ThreadDay", "ResumeHash", "CspSessionId" {
		If $Property(first, field) = reference Set found = 1
	}
	Do $$$AssertEquals(found, 0, "no property equals the reference")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 1, "one row")

	Set second = ##class(OcuTalon.Data.Session).NewVisitor(user, "ZzSessVisitorB", .other, .sc)
	Do $$$AssertStatusOK(sc, "the second call")
	If $IsObject(second) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(second)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).SessionCount(user), 2, "it makes a second row for the same user")
	Do $$$AssertTrue($IsObject(second) && (second.Ref '= first.Ref) && (second.Epoch '= first.Epoch) && (other '= reference), "with its own Ref, Epoch and reference")

	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(reference).%Id(), first.%Id(), "ForResume opens the first row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(other).%Id(), second.%Id(), "and the second")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(##class(OcuTalon.Bridge.Ids).NewRef()), "", "an unknown reference opens no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(""), "", "the empty reference opens no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(reference_"x"), "", "a reference of 23 characters opens no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume($Extract(reference, 1, 21)), "", "a reference of 21 characters opens no row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume($Extract(reference, 1, 21)_"!"), "", "a character outside the alphabet opens no row")
	Set lower = $ZConvert(reference, "L")
	If lower '= reference Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(lower), "", "the case of a reference matters: its lower-case form opens no row")
	Set upper = $ZConvert(reference, "U")
	If upper '= reference Do $$$AssertEquals(##class(OcuTalon.Data.Session).ForResume(upper), "", "nor does its upper-case form")

	Set before = ..CountAll()
	Set none = ##class(OcuTalon.Data.Session).NewVisitor("", "ZzSessVisitorC", .nothing, .sc)
	Do $$$AssertStatusNotOK(sc, "an empty user is an error")
	Do $$$AssertEquals(none_"|"_nothing, "|", "with no row and no reference")
	Do $$$AssertEquals(..CountAll(), before, "and no row is created")
}

/// Recipients: a session-owned record goes to its session; an instance incident to every session that watches its
/// production, on a local install; an unwatched one, an eval record, an unknown Ref and any instance record with
/// onlineDemo on go to nobody. The status is OK in every one of these cases: only a failed watcher read (DW-68) makes it
/// an error.
Method TestRecipients()
{
	Set a = ##class(OcuTalon.Test.Data.Fixture).Session("zzsessrecip"_..Number_"a")
	Set b = ##class(OcuTalon.Test.Data.Fixture).Session("zzsessrecip"_..Number_"b")
	Set watched = "Zz.Recip"_..Number_".Watched"
	Do ##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", watched)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", watched)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", "Zz.Recip"_..Number_".OnlyB")
	Set instanceWatched = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", watched)
	Set instanceUnwatched = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", "Zz.Recip"_..Number_".Nobody")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Incident(a, , "ZZNS", watched)
	Set eval = ##class(OcuTalon.Test.Data.Fixture).Incident("eval", , "ZZNS", watched)

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ..AssertRecipients(a, "", $ListBuild(a), "a session-owned record goes to its session")
	Do ..AssertRecipients(a, own, $ListBuild(a), "also when it names an incident")
	Set list = ##class(OcuTalon.Data.Session).Recipients("instance", instanceWatched, .sc)
	Do $$$AssertStatusOK(sc, "the status of an instance incident is OK")
	Do $$$AssertEquals($ListLength(list), 2, "an instance incident goes to the two sessions that watch its production")
	Do $$$AssertTrue($ListFind(list, a) && $ListFind(list, b), "A and B")
	Do ..AssertRecipients("instance", instanceUnwatched, "", "an unwatched instance incident goes to nobody")
	Do ..AssertRecipients("instance", own, "", "an incident that a session owns is not an instance incident")
	Do ..AssertRecipients("instance", "zzmissing"_..Number, "", "nor is a missing one")
	Do ..AssertRecipients("instance", "", "", "instance with no incident goes to nobody")
	Do ..AssertRecipients("eval", eval, "", "an eval record goes to nobody")
	Do ..AssertRecipients("eval", "", "", "also with no incident")
	Do ..AssertRecipients("zzunknown"_..Number, "", "", "an unknown Ref goes to nobody")
	Do ..AssertRecipients("", "", "", "an empty owner goes to nobody")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..AssertRecipients("instance", instanceWatched, "", "with onlineDemo on, an instance incident goes to nobody")
	Do ..AssertRecipients(a, own, $ListBuild(a), "and a session-owned record still goes to its session")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// Asserts what Recipients answers for the owner and the incident, and that its status is OK.
Method AssertRecipients(owner As %String, incident As %String, expected As %List, text As %String) [ Private ]
{
	Set got = ##class(OcuTalon.Data.Session).Recipients(owner, incident, .sc)
	Do $$$AssertEquals(got, expected, text)
	Do $$$AssertStatusOK(sc, "the status is OK: "_text)
}

/// An empty user name is refused, and no row is created.
Method TestRefusesAnEmptyUser()
{
	Set before = ..CountAll()
	Set session = ##class(OcuTalon.Data.Session).ForUser("", .sc)
	Do $$$AssertStatusNotOK(sc, "an empty user name is an error")
	Do $$$AssertEquals(session, "", "and returns no row")
	Do $$$AssertEquals(..CountAll(), before, "no row is created")
}

/// Two jobs make the first call for each of 20 new users, in step, at the same moment: for every user both get the
/// same row, and the user has one row.
Method TestConcurrentFirstCall()
{
	Set user = "zzsessrace"_..Number_"x"
	Set run = $Name(^OcuTalonTest("SessionForUser", "run", user))
	Kill @run
	Job ##class(OcuTalon.Test.Data.Session).Racer(user, 20)
	Job ##class(OcuTalon.Test.Data.Session).Racer(user, 20)
	Do ..WaitFor($Name(@run@("started")), 2, 60)
	Do $$$AssertEquals($Get(@run@("started")), 2, "both jobs are waiting to start")
	Set @run@("go") = 1
	Do ..WaitFor($Name(@run@("done")), 2, 120)
	Do $$$AssertEquals($Get(@run@("done")), 2, "both jobs finished")
	Do $$$AssertEquals($Get(@run@("error"), ""), "", "without an error")
	Set split = ""
	For i = 1:1:20 {
		If (##class(OcuTalon.Test.Data.Fixture).SessionCount(user_i) '= 1) || ($Get(@run@("ref", i, 1)) = "") || ($Get(@run@("ref", i, 1)) '= $Get(@run@("ref", i, 2))) Set split = split_" "_i
	}
	Do $$$AssertEquals(split, "", "every user has one row, and both jobs got its Ref")
	Kill @run
}

/// The job body of TestConcurrentFirstCall: waits for the go signal, then for each of count users waits for the other
/// job, calls ForUser and records the row's Ref.
ClassMethod Racer(user As %String, count As %Integer)
{
	Set run = $Name(^OcuTalonTest("SessionForUser", "run", user))
	Do $Increment(@run@("started"))
	Set deadline = $ZHorolog + 60
	While '$Get(@run@("go")) && ($ZHorolog < deadline) {
	}
	For i = 1:1:count {
		Set n = $Increment(@run@("ready", i))
		Set deadline = $ZHorolog + 30
		While ($Get(@run@("ready", i)) < 2) && ($ZHorolog < deadline) {
		}
		Set session = ##class(OcuTalon.Data.Session).ForUser(user_i, .sc)
		If $SYSTEM.Status.IsError(sc) {
			Set @run@("error") = $SYSTEM.Status.GetErrorText(sc)
		} Else {
			Set @run@("ref", i, n) = session.Ref
		}
	}
	Do $Increment(@run@("done"))
}

/// The sign-out mark (U-174): 0 for an unknown or empty ref, each MarkSignedOut raises one session's count by 1 and leaves another's
/// alone, and an empty ref raises nothing. The fixture refs are fresh references, and their marks are removed after.
Method TestSignOutMark()
{
	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set second = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(first), 0, "an unknown ref has mark 0")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(""), 0, "an empty ref has mark 0")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).MarkSignedOut(first), "the first mark")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).MarkSignedOut(first), "the second mark")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(first), 2, "two calls give +2")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(second), 0, "another ref's mark is unchanged")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).MarkSignedOut(second), "a mark on the other ref")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).SignOuts(first)_"|"_##class(OcuTalon.Data.Session).SignOuts(second), "2|1", "each ref counts on its own")
	Set count = ..MarkCount()
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Session).MarkSignedOut(""), "an empty ref is accepted")
	Do $$$AssertEquals(..MarkCount(), count, "and raises nothing")
	Kill ^OcuTalonP.SessionM(first), ^OcuTalonP.SessionM(second)
}

/// --- helpers ---
/// The number of sessions that hold a sign-out mark.
ClassMethod MarkCount() As %Integer [ Private ]
{
	Set count = 0
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonP.SessionM(ref))
		Quit:ref=""
		Set count = count + 1
	}
	Quit count
}

/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

ClassMethod CountAll() As %Integer [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Session")
	Set result = statement.%Execute()
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes the fixture rows: every session of a user name that starts with zzsess.
ClassMethod Clean() [ Private ]
{
	Kill ^OcuTalonTest("SessionForUser", "run")
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzsess'")
	Do statement.%Execute()
}

}
