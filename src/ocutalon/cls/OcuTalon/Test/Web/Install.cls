/// Tests of the Web step's declarations (matrix rows 17, 20 and 21): the application table, the trace application of a
/// namespace, the trace role's grants, Apply, BundleCheck, the removal of the old bundle's files and the trace
/// role's SQL privilege. The real applications, roles, user and bundle folders are never touched: Apply and the SQL
/// grant run on fixtures (ZzWeb<n>), and the bundle tests on folders under the fixture folder (zzbundle<n>), which
/// OnAfterAllTests removes.
Class OcuTalon.Test.Web.Install Extends %UnitTest.TestCase
{

/// The fixture's number: the application is /zzweb<n>, the roles ZzWeb<n>RoleA and ZzWeb<n>RoleB.
Property Number As %Integer;

Property Application As %String;

Property RoleA As %String;

Property RoleB As %String;

Property Directory As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("WebInstall", "n"))
	Set ..Application = "/zzweb"_..Number
	Set ..RoleA = "ZzWeb"_..Number_"RoleA"
	Set ..RoleB = "ZzWeb"_..Number_"RoleB"
	Set file = ##class(%File).TempFilename("d")
	Do ##class(%File).Delete(file)
	Set ..Directory = ##class(%File).NormalizeDirectory(file)
	Quit ..CreateRoles()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	If ..Directory '= "" Do ##class(%File).RemoveDirectoryTree(..Directory)
	Quit $SYSTEM.Status.OK()
}

/// The application table of the Web step, key by key: four applications, every key passed, an empty CORS list, and the
/// session event class OcuTalon.Web.SessionEvents on /ocutalon alone.
Method TestDefinitions()
{
	Set sc = ##class(OcuTalon.Install.Step.Web).Definitions(.apps)
	Do $$$AssertStatusOK(sc, "Definitions")
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(apps(name))
		Quit:name=""
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "/ocutalon,/ocutalon/api,/ocutalon/public,/ocutalon/trace/ocutalon", "the four applications")
	For name = "/ocutalon", "/ocutalon/api", "/ocutalon/public", "/ocutalon/trace/ocutalon" {
		Kill expected
		Do ..Expected(name, .expected)
		Set key = ""
		For {
			Set key = $Order(expected(key))
			Quit:key=""
			Do $$$AssertEquals($Get(apps(name, key), "<undefined>"), expected(key), name_" "_key)
		}
		Set key = ""
		For {
			Set key = $Order(apps(name, key))
			Quit:key=""
			Do $$$AssertTrue($Data(expected(key)), name_" "_key_" is in the table")
		}
	}
}

/// The Web area declares the live-event purge (AD-27, Story 30.2 calls it): Purge(90) deletes every live event older than
/// 24 hours, whatever the number, keeps the newer ones and leaves the stream's counter alone. It deletes the events of
/// every stream, rows this test did not create too, so this class runs only on a throwaway (Rule 21).
Method TestPurgeDeclaration()
{
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("WebInstall", "streams", stream) = ""
	For i = 1:1:2 {
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzWeb"_..Number_"p"_i
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload, .seq), "event "_i_" is published")
	}
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("UPDATE OcuTalon_Live.Event SET Ts = ? WHERE Stream = ? AND Seq = 1")
	Do statement.%Execute(##class(OcuTalon.Test.Data.Fixture).HoursAgo(25), stream)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).EventSeqs(stream), "1,2", "two events, the first aged to 25 hours")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Purge(90), "the Web area's Purge")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).EventSeqs(stream), "2", "the aged event is deleted and the fresh one kept, whatever the number of days")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(stream), 2, "the stream's counter is unchanged")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload, .seq), "the next event is published")
	Do $$$AssertEquals(seq, 3, "and continues the stream's Seq")
}

/// The Web area's purge also keeps the address counter to one hour (AD-27, Story 16.3, matrix row 13): Purge(90) and Purge(0) each delete
/// a counter row that is 61 minutes old, keep one that is 59 minutes old and still purge the live events older than 24 hours. Like
/// TestPurgeDeclaration it deletes the rows of every address and stream, so this class runs only on a throwaway (Rule 21).
Method TestPurgeAddressCounter()
{
	Set address = "zz-webinstall-"_..Number_"-counter"
	Set hash = ##class(OcuTalon.Data.Session).Hash(address)
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("WebInstall", "streams", stream) = ""
	For days = 90, 0 {
		Do ##class(OcuTalon.Data.AddressCounter).%DeleteExtent()
		Set old = ..CounterRow(hash, 3660)
		Set recent = ..CounterRow(hash, 3540)
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzWeb"_..Number_"c"_days
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload, .seq), "an event is published")
		Do ##class(OcuTalon.Test.Data.Fixture).SetEventTs(stream, seq, ##class(OcuTalon.Test.Data.Fixture).HoursAgo(25))
		Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).Recent(address, .oldest), 1, "Recent counts the 59-minute row only (days "_days_")")
		Do $$$AssertEquals(oldest, ##class(OcuTalon.Data.AddressCounter).%OpenId(recent).CreatedAt, "and returns its time as the oldest")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Purge(days), "the Web area's Purge("_days_")")
		Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(old), 0, "the 61-minute row is deleted")
		Do $$$AssertEquals(##class(OcuTalon.Data.AddressCounter).%ExistsId(recent), 1, "the 59-minute row is kept")
		Do $$$AssertEquals($ListFind($ListFromString(##class(OcuTalon.Test.Data.Fixture).EventSeqs(stream)), seq), 0, "the aged live event is purged too (days "_days_")")
	}
	Do ##class(OcuTalon.Data.AddressCounter).%DeleteExtent()
}

/// A counter row of the hash created the given number of seconds ago; returns its id.
ClassMethod CounterRow(hash As %String, secondsAgo As %Integer) As %Integer [ Private ]
{
	Set row = ##class(OcuTalon.Data.AddressCounter).%New()
	Set row.AddressHash = hash
	Set row.CreatedAt = ##class(OcuTalon.Data.AddressCounter).Shift(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	Do row.%Save()
	Quit row.%Id()
}

/// The trace application of a namespace: its name from the namespace, AD-24's seven permitted classes, no
/// application roles and no dispatch class.
Method TestTraceApp()
{
	Set name = ##class(OcuTalon.Install.Step.Web).TraceApp("ZZNS", .props)
	Do $$$AssertEquals(name, "/ocutalon/trace/zzns", "the name is the namespace in lower case")
	Do $$$AssertEquals(props("NameSpace"), "ZZNS", "the namespace")
	Do $$$AssertEquals(props("CookiePath"), "/ocutalon/trace/zzns/", "the cookie path")
	Do $$$AssertEquals(props("GroupById"), "OcuTalon", "the sign-in group")
	Do $$$AssertEquals(props("MatchRoles"), "", "no application roles")
	Do $$$AssertEquals(props("DispatchClass"), "", "no dispatch class")
	Do $$$AssertEquals(props("ServeFiles"), 1, "ServeFiles 1")
	Do $$$AssertEquals(props("CSPZENEnabled"), 1, "the ZEN pages are enabled")
	Do $$$AssertEquals(props("PermittedClasses"), ..SevenClasses(), "exactly the seven classes of AD-24")
	Do $$$AssertEquals($Length(props("PermittedClasses"), ","), 7, "seven classes")
	Kill expected
	Do ..Expected("/ocutalon/trace/ocutalon", .expected)
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).TraceApp("OCUTALON", .props), "/ocutalon/trace/ocutalon", "the OCUTALON trace application")
	Set key = ""
	For {
		Set key = $Order(expected(key))
		Quit:key=""
		Do $$$AssertEquals($Get(props(key), "<undefined>"), expected(key), "OCUTALON trace "_key)
	}
}

/// The trace role: exactly Use on four Ens resources and Read on the data and code databases, and none of the
/// resources that AD-24 forbids to every OcuTalon role. The Users step adds two roles without a resource.
Method TestGrants()
{
	Set grants = ##class(OcuTalon.Install.Step.Web).Grants()
	Do $$$AssertEquals(grants.%Size(), 6, "six grants")
	Set seen = ""
	For i = 0:1:grants.%Size() - 1 {
		Set grant = grants.%Get(i)
		Do $$$AssertEquals(grant.role, "OcuTalonTraceViewer", "the grant "_i_" is the trace role's")
		Set seen(grant.resource) = grant.permission
		Do $$$AssertTrue(..Forbidden(grant.resource) = 0, grant.resource_" is not a forbidden resource")
	}
	Do $$$AssertEquals($Get(seen("%Ens_Portal")), "U", "Use on %Ens_Portal")
	Do $$$AssertEquals($Get(seen("%Ens_MessageTrace")), "U", "Use on %Ens_MessageTrace")
	Do $$$AssertEquals($Get(seen("%Ens_MessageHeader")), "U", "Use on %Ens_MessageHeader")
	Do $$$AssertEquals($Get(seen("%Ens_MessageContent")), "U", "Use on %Ens_MessageContent")
	Do $$$AssertEquals($Get(seen("%DB_OCUTALON_DATA")), "R", "Read on the data database")
	Do $$$AssertEquals($Get(seen("%DB_OCUTALON_CODE")), "R", "Read on the code database")

	Set sc = ##class(OcuTalon.Install.Registry).Declared("Grants", .declared)
	Do $$$AssertStatusOK(sc, "the declarations of all the areas")
	Set holds = 0
	Set user = 0
	Set n = ""
	For {
		Set n = $Order(declared(n))
		Quit:n=""
		Set role = declared(n).role
		If role = "OcuTalonTraceViewer" Set holds = holds + 1
		If (role = "OcuTalonUser") || (role = "OcuTalonAdmin") {
			Set user = user + 1
			Do $$$AssertEquals(declared(n).resource, "", role_" holds no resource")
		}
		If $Extract(role, 1, 8) = "OcuTalon" {
			Do $$$AssertTrue(..Forbidden(declared(n).resource) = 0, "no OcuTalon role holds the forbidden "_declared(n).resource)
		}
	}
	Do $$$AssertEquals(holds, 6, "the registry sees the trace role's six grants")
	Do $$$AssertEquals(user, 2, "the registry sees the two roles without a resource")
}

/// Apply creates an application with the given properties and, when it exists, modifies it back to them.
Method TestApply()
{
	Do ..RemoveApplication()
	Do $$$AssertEquals(..Application(.stored), 0, "no fixture application to begin with")
	Do ##class(OcuTalon.Install.Step.Web).TraceApp("OCUTALON", .props)
	Set props("CookiePath") = ..Application_"/"
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Apply(..Application, .props), "Apply creates the application")
	Do $$$AssertEquals(..Application(.stored), 1, "the application exists")
	Do ..AssertProperties(.props, .stored, "created")
	Do $$$AssertEquals($Get(stored("CorsAllowlist")), "", "no CORS list")

	Kill changes
	Set changes("Enabled") = 0
	Set changes("Timeout") = 100
	Set changes("ServeFiles") = 3
	Set changes("GroupById") = "ZzOther"
	Set changes("PermittedClasses") = ""
	Set changes("AutheEnabled") = 64
	Set changes("CorsAllowlist") = "https://zz.example.com"
	Do ..ModifyApplication(.changes)
	Do ..Application(.stored)
	Do $$$AssertEquals(stored("Timeout"), 100, "the timeout was changed by hand")
	Do $$$AssertEquals(stored("GroupById"), "ZzOther", "the group was changed by hand")
	Do $$$AssertEquals(stored("CorsAllowlist"), "https://zz.example.com", "a CORS list was added by hand")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Apply(..Application, .props), "Apply modifies the application")
	Do ..Application(.stored)
	Do ..AssertProperties(.props, .stored, "restored")
	Do $$$AssertEquals($Get(stored("CorsAllowlist")), "", "the CORS list added by hand is gone")
}

/// The bundle folder must hold index.html; the error names the path that is missing.
Method TestBundleCheck()
{
	Do ##class(%File).CreateDirectoryChain(..Directory)
	Set index = ..Directory_"index.html"
	Do ##class(%File).Delete(index)
	Set sc = ##class(OcuTalon.Install.Step.Web).BundleCheck(..Directory)
	Do $$$AssertStatusNotOK(sc, "BundleCheck fails without index.html")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ index, "the error names the path: "_$SYSTEM.Status.GetErrorText(sc))
	Set sc = ##class(OcuTalon.Install.Step.Web).BundleCheck($Extract(..Directory, 1, $Length(..Directory) - 1))
	Do $$$AssertStatusNotOK(sc, "the folder name without its trailing separator fails the same way")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ index, "and names the same path")

	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(index)
	Do stream.Write("<!doctype html>")
	Do $$$AssertStatusOK(stream.%Save(), "index.html is written")
	Kill stream
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).BundleCheck(..Directory), "BundleCheck passes with index.html")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).BundleCheck($Extract(..Directory, 1, $Length(..Directory) - 1)), "and without the trailing separator")
}

/// The step reads the new bundle folder, csp/ocutalon-web/, and only then cleans the old one: without the new
/// folder's index.html the step fails, naming that path, and the old folder is untouched.
Method TestPrepareReadsTheNewFolder()
{
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).#BUNDLEFOLDER, "csp/ocutalon-web/", "the bundle folder")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).#OLDBUNDLEFOLDER, "csp/ocutalon/", "the old bundle folder")
	Set data = ..Directory_"zzbundle"_..Number_"p/"
	Do ..Seed(data_"csp/ocutalon/", "index.html", "<!doctype html><base href=""/ocutalon/"">")
	Do ..Seed(data_"csp/ocutalon/", "main-AB12CD34.js", "old")
	Set sc = ##class(OcuTalon.Install.Step.Web).Prepare(data)
	Do $$$AssertStatusNotOK(sc, "the step fails without the new folder")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ (data_"csp/ocutalon-web/index.html"), "and names the new folder's index.html: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Tree(data_"csp/ocutalon/"), "index.html|main-AB12CD34.js", "the old folder is untouched")

	Do ..Seed(data_"csp/ocutalon-web/", "index.html", "<!doctype html><base href=""/ocutalon/"">")
	Set sc = ##class(OcuTalon.Install.Step.Web).Prepare($Extract(data, 1, $Length(data) - 1))
	Do $$$AssertStatusOK(sc, "the step passes with the new folder, and a data directory without its closing separator")
	Do $$$AssertEquals(..Tree(data_"csp/ocutalon/"), "", "and the old folder has lost OcuTalon's files")
	Do $$$AssertTrue(##class(%File).DirectoryExists(data_"csp/ocutalon/"), "the old folder itself stays")
	Do $$$AssertEquals(..Tree(data_"csp/ocutalon-web/"), "index.html", "the new folder is untouched")
}

/// Only OcuTalon's own files leave the old folder, and only when its index.html is OcuTalon's: index.html,
/// 3rdpartylicenses.txt, the hashed top-level scripts and stylesheets, the assets that the new folder also holds, and
/// the folders that this leaves empty. Anything else stays, and a second run changes nothing.
Method TestRemoveOldBundle()
{
	Set base = ..Directory_"zzbundle"_..Number_"/"
	Set old = base_"old/"
	Set new = base_"new/"
	Do ..SeedBundle(new)
	Do ..SeedBundle(old)
	Do ..Seed(old, "zz-keep.txt", "keep")
	Do ..Seed(old, "assets/zz/keep.txt", "keep")
	Do ..Seed(old, "polyfills-QR34ST56.js", "old")
	Do ..Seed(old, "main-AB12CD34.js.map", "old")
	Do ..Seed(old, "main.js", "keep")
	Do ..Seed(old, "app-AB12CD34.js", "keep")
	Do ..Seed(old, "main-AB12CD34.json", "keep")
	Do ..Seed(old, "Main-AB12CD34.js", "keep")
	Do $$$AssertTrue(##class(%File).Exists(old_"assets/fonts/Inter-Regular.woff2"), "the old folder holds an asset that the new one also holds")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(old, new), "RemoveOldBundle")
	Do $$$AssertEquals(..Tree(old), "Main-AB12CD34.js|app-AB12CD34.js|assets|assets/zz|assets/zz/keep.txt|main-AB12CD34.json|main.js|zz-keep.txt", "only what is not OcuTalon's remains")
	Do $$$AssertEquals(..Tree(new), "3rdpartylicenses.txt|assets|assets/fonts|assets/fonts/Inter-Regular.woff2|chunk-EF56GH78.js|index.html|main-AB12CD34.js|styles-IJ90KL12.css", "the new folder is untouched")
	Do $$$AssertTrue(##class(%File).Exists(new_"assets/fonts/Inter-Regular.woff2") && ##class(%File).Exists(new_"index.html"), "the new folder still holds its files")
	Set before = ..Tree(old)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(old, new), "a second run")
	Do $$$AssertEquals(..Tree(old), before, "changes nothing")

	Set theirs = base_"theirs/"
	Do ..SeedBundle(theirs)
	Do ..Seed(theirs, "index.html", "<!doctype html><base href=""/other/"">")
	Set before = ..Tree(theirs)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(theirs, new), "an index.html that isn't OcuTalon's")
	Do $$$AssertEquals(..Tree(theirs), before, "removes nothing")

	Set noindex = base_"noindex/"
	Do ..Seed(noindex, "main-AB12CD34.js", "old")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(noindex, new), "a folder without an index.html")
	Do $$$AssertEquals(..Tree(noindex), "main-AB12CD34.js", "removes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(base_"missing/", new), "no old folder")
	Do $$$AssertTrue('##class(%File).DirectoryExists(base_"missing/"), "and none is created")
}

/// An asset that only the old folder holds stays, with the folders above it; a file that can't be deleted gives an
/// error status that names it, the files after it are left, and index.html with them, so that the next run removes
/// the rest.
Method TestRemoveOldBundleKeepsAndFails()
{
	Set base = ..Directory_"zzbundle"_..Number_"k/"
	Set old = base_"old/"
	Set new = base_"new/"
	Do ..SeedBundle(new)
	Do ..SeedBundle(old)
	Do ..Seed(old, "assets/fonts/zz-extra.woff2", "keep")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(old, new), "RemoveOldBundle")
	Do $$$AssertEquals(..Tree(old), "assets|assets/fonts|assets/fonts/zz-extra.woff2", "an asset that is not in the new folder stays, with its folders")

	Set stuck = base_"stuck/"
	Do ..SeedBundle(stuck)
	Do ##class(%File).Delete(stuck_"3rdpartylicenses.txt")
	Do ##class(%File).CreateDirectoryChain(stuck_"3rdpartylicenses.txt/")
	Set sc = ##class(OcuTalon.Install.Step.Web).RemoveOldBundle(stuck, new)
	Do $$$AssertStatusNotOK(sc, "a file that can't be deleted is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "3rdpartylicenses.txt", "and the error names it: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue(##class(%File).Exists(stuck_"index.html"), "index.html stays, so the next start repeats the removal")
	Do $$$AssertTrue(##class(%File).Exists(stuck_"main-AB12CD34.js"), "and so does the script after the stuck file")
	Do ##class(%File).RemoveDirectory(stuck_"3rdpartylicenses.txt/")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveOldBundle(stuck, new), "the next run")
	Do $$$AssertEquals(..Tree(stuck), "", "removes the rest of OcuTalon's files")
}

/// The trace role's SQL privilege is granted once, in the current namespace, to the role that is named.
Method TestGrantTraceSql()
{
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 0, "the fixture role holds no privilege to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).GrantTraceSql(..RoleA), "GrantTraceSql")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 1, "SELECT on Ens.MessageHeader")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).GrantTraceSql(..RoleA), "GrantTraceSql again")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 1, "still SELECT")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleB, 1, "Ens.MessageHeader", "s"), 0, "another role holds nothing")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "i"), 0, "and the role holds no more than SELECT")
}

/// --- fixtures ---
/// Writes a file below dir, creating the folders on the way.
ClassMethod Seed(dir As %String, relative As %String, text As %String) [ Private ]
{
	Set file = ##class(%File).NormalizeDirectory(dir)_relative
	Do ##class(%File).CreateDirectoryChain(##class(%File).GetDirectory(file))
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(file)
	Do stream.Write(text)
	Do stream.%Save()
}

/// A bundle: OcuTalon's index.html and licences, hashed scripts and stylesheet, and one font.
ClassMethod SeedBundle(dir As %String) [ Private ]
{
	Do ..Seed(dir, "index.html", "<!doctype html><html><head><base href=""/ocutalon/""></head></html>")
	Do ..Seed(dir, "main-AB12CD34.js", "main")
	Do ..Seed(dir, "chunk-EF56GH78.js", "chunk")
	Do ..Seed(dir, "styles-IJ90KL12.css", "styles")
	Do ..Seed(dir, "3rdpartylicenses.txt", "licences")
	Do ..Seed(dir, "assets/fonts/Inter-Regular.woff2", "font")
}

/// The files and folders below dir, relative to it, sorted, joined by |.
ClassMethod Tree(dir As %String) As %String [ Private ]
{
	Set dir = ##class(%File).NormalizeDirectory(dir)
	Kill found
	Do ..Walk(dir, "", .found)
	Set tree = ""
	Set path = ""
	For {
		Set path = $Order(found(path))
		Quit:path=""
		Set tree = tree_$Select(tree = "": "", 1: "|")_path
	}
	Quit tree
}

ClassMethod Walk(dir As %String, prefix As %String, ByRef found) [ Private ]
{
	Set rows = ##class(%ResultSet).%New("%File:FileSet")
	Do rows.Execute(dir, "*", "Name", 1)
	Kill entries
	While rows.Next() {
		Set entries($Increment(entries)) = $ListBuild(rows.Get("Name"), rows.Get("Type"))
	}
	Set i = ""
	For {
		Set i = $Order(entries(i), 1, entry)
		Quit:i=""
		Set name = prefix_##class(%File).GetFilename($List(entry, 1))
		Set found(name) = ""
		If $List(entry, 2) = "D" Do ..Walk(##class(%File).NormalizeDirectory($List(entry, 1)), name_"/", .found)
	}
}

/// The table of the Design Notes for an application: expected(key) = value.
ClassMethod Expected(name As %String, Output expected) [ Private ]
{
	Kill expected
	Set expected("NameSpace") = "OCUTALON"
	Set expected("Enabled") = 1
	Set expected("AutheEnabled") = 32
	Set expected("GroupById") = "OcuTalon"
	Set expected("SessionScope") = 2
	Set expected("Timeout") = 28800
	Set expected("LoginPage") = ""
	Set expected("InbndWebServicesEnabled") = 0
	Set expected("IsNameSpaceDefault") = 0
	Set expected("AutoCompile") = 0
	Set expected("CSPZENEnabled") = 1
	Set expected("CorsAllowlist") = ""
	Set expected("EventClass") = ""
	If name = "/ocutalon/trace/ocutalon" {
		Set expected("DispatchClass") = ""
		Set expected("Path") = ""
		Set expected("ServeFiles") = 1
		Set expected("CookiePath") = "/ocutalon/trace/ocutalon/"
		Set expected("MatchRoles") = ""
		Set expected("PermittedClasses") = ..SevenClasses()
		Quit
	}
	If name = "/ocutalon/public" {
		Set expected("AutheEnabled") = 64
		Set expected("GroupById") = ""
		Set expected("DispatchClass") = "OcuTalon.Web.Public.Status"
		Set expected("Path") = ""
		Set expected("ServeFiles") = 0
		Set expected("CookiePath") = "/ocutalon/public/"
		Set expected("MatchRoles") = ""
		Set expected("PermittedClasses") = ""
		Quit
	}
	Set expected("CookiePath") = "/ocutalon/"
	Set expected("MatchRoles") = ":%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE"
	Set expected("PermittedClasses") = ""
	If name = "/ocutalon" {
		Set expected("DispatchClass") = "OcuTalon.Web.Public.Shell"
		Set expected("EventClass") = "OcuTalon.Web.SessionEvents"
		Set expected("Path") = $SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/"
		Set expected("ServeFiles") = 3
	} Else {
		Set expected("DispatchClass") = "OcuTalon.Web.Api"
		Set expected("Path") = ""
		Set expected("ServeFiles") = 0
	}
}

/// AD-24's seven classes, as S7 tested them.
ClassMethod SevenClasses() As %String [ Private ]
{
	Quit "1(1""%CSP.Broker"",1""EnsPortal.VisualTrace"",1""EnsPortal.SVG.VisualTrace"",1""EnsPortal.VisualTraceLegend"",1""EnsPortal.SVG.TraceLegend"",1""EnsPortal.MessageContents"",1""EnsPortal.MessageViewer"")"
}

/// 1 for a resource that no OcuTalon role may hold (AD-24).
ClassMethod Forbidden(resource As %String) As %Boolean [ Private ]
{
	If $ListFind($ListBuild("%All", "%Development", "%Ens_MessageEditResend", "%Ens_MessageDiscard", "%Ens_ProductionRun", "%Ens_ProductionConfig", "%DB_OCUTALON_PRIVATE", "%DB_OCUTALON_PUBLIC"), resource) Quit 1
	Quit $Extract(resource, 1, 13) = "%Ens_Workflow"
}

/// Asserts that every given property is stored with that value.
Method AssertProperties(ByRef props, ByRef stored, label As %String) [ Private ]
{
	Set key = ""
	For {
		Set key = $Order(props(key))
		Quit:key=""
		Do $$$AssertEquals($Get(stored(key), "<undefined>"), props(key), label_" "_key)
	}
}

/// 1 when the fixture application exists; stored(property) holds its properties.
Method Application(Output stored) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill stored
	If '##class(Security.Applications).Exists(..Application) Quit 0
	Do ##class(Security.Applications).Get(..Application, .stored)
	Quit 1
}

Method ModifyApplication(ByRef changes) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Applications).Modify(..Application, .changes)
}

Method RemoveApplication() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Applications).Exists(..Application) Do ##class(Security.Applications).Delete(..Application)
}

Method CreateRoles() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = ##class(Security.Roles).Create(..RoleA, "OcuTalon test fixture", "")
	If $SYSTEM.Status.IsOK(sc) Set sc = ##class(Security.Roles).Create(..RoleB, "OcuTalon test fixture", "")
	Quit sc
}

/// Deletes every fixture application and role that an earlier run may have left, with the role's SQL
/// privilege, and the fixture's nodes.
ClassMethod Clean() [ Private ]
{
	Set stream = ""
	For {
		Set stream = $Order(^OcuTalonTest("WebInstall", "streams", stream))
		Quit:stream=""
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("DELETE FROM OcuTalon_Live.Event WHERE Stream = ?")
		Do statement.%Execute(stream)
		Kill ^OcuTalonP.LiveEventC(stream)
	}
	Kill ^OcuTalonTest("WebInstall")
	New $Namespace
	Set home = $Namespace
	Set $Namespace = "%SYS"
	Set roles = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Roles WHERE Name %STARTSWITH 'ZzWeb'")
	While result.%Next() {
		Set roles = roles_$ListBuild(result.%GetData(1))
	}
	Set position = 0
	While $ListNext(roles, position, role) {
		Set $Namespace = home
		Do $SYSTEM.SQL.Security.RevokePrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
		Set $Namespace = "%SYS"
		Do ##class(Security.Roles).Delete(role)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Applications WHERE Name %STARTSWITH '/zzweb'")
	While result.%Next() {
		Do ##class(Security.Applications).Delete(result.%GetData(1))
	}
}

}
