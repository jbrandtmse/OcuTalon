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
	Do $$$AssertEquals(..Count(user), 0, "no row to begin with")
	Set first = ##class(OcuTalon.Data.Session).ForUser(user, .sc)
	Do $$$AssertStatusOK(sc, "the first call")
	Do $$$AssertTrue($IsObject(first), "the first call returns the row")
	Do $$$AssertEquals(..Count(user), 1, "one row is created")
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
	Do $$$AssertEquals(..Count(user), 1, "still one row")

	Set other = ##class(OcuTalon.Data.Session).ForUser("zzsessother"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "another user")
	Do $$$AssertTrue(other.%Id() '= first.%Id(), "another user has another row")
	Do $$$AssertTrue((other.Ref '= first.Ref) && (other.TraceRef '= first.TraceRef) && (other.Epoch '= first.Epoch), "with other references")
}

/// Recipients: a session-owned record goes to its session; an instance incident to every session that watches its
/// production, on a local install; an unwatched one, an eval record, an unknown Ref and any instance record with
/// onlineDemo on go to nobody.
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
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients(a), $ListBuild(a), "a session-owned record goes to its session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients(a, own), $ListBuild(a), "also when it names an incident")
	Set list = ##class(OcuTalon.Data.Session).Recipients("instance", instanceWatched)
	Do $$$AssertEquals($ListLength(list), 2, "an instance incident goes to the two sessions that watch its production")
	Do $$$AssertTrue($ListFind(list, a) && $ListFind(list, b), "A and B")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("instance", instanceUnwatched), "", "an unwatched instance incident goes to nobody")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("instance", own), "", "an incident that a session owns is not an instance incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("instance", "zzmissing"_..Number), "", "nor is a missing one")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("instance"), "", "instance with no incident goes to nobody")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("eval", eval), "", "an eval record goes to nobody")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("eval"), "", "also with no incident")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("zzunknown"_..Number), "", "an unknown Ref goes to nobody")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients(""), "", "an empty owner goes to nobody")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients("instance", instanceWatched), "", "with onlineDemo on, an instance incident goes to nobody")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).Recipients(a, own), $ListBuild(a), "and a session-owned record still goes to its session")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
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
		If (..Count(user_i) '= 1) || ($Get(@run@("ref", i, 1)) = "") || ($Get(@run@("ref", i, 1)) '= $Get(@run@("ref", i, 2))) Set split = split_" "_i
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

/// --- helpers ---
/// Waits up to seconds for the global node named by ref to reach count.
ClassMethod WaitFor(ref As %String, count As %Integer, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(@ref) < count) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The rows of a user, matched without regard to case.
ClassMethod Count(user As %String) As %Integer [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Session WHERE IrisUser = ?")
	Set result = statement.%Execute(user)
	Do result.%Next()
	Quit result.%GetData(1)
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
