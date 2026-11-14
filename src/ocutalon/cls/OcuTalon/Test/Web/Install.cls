/// Tests of the Web step's declarations (matrix rows 17, 20 and 21; Story 35.3): the application table (five applications off the online demo, four
/// on it), the webhook application's properties, the trace application of a namespace, the trace role's and the webhook role's grants (none of the
/// latter on the online demo), Apply, BundleCheck, the removal of the old bundle's files, the removal of the earlier builds' hashed files from the served folder
/// (RemoveStaleBundle and its guards, BuildFolder, Prepare) and the trace role's SQL privilege. The real applications, roles, user and bundle folders are never touched: Apply and the SQL
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

/// The application table of the Web step, key by key, off the online demo: five applications, every key passed, an empty CORS list, the
/// session event class OcuTalon.Web.SessionEvents on /ocutalon alone, and /ocutalon/hook unauthenticated and outside the sign-in group with the role OcuTalonWebhook.
/// The online-demo flag is put back, also after a failure.
Method TestDefinitions()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Set sc = ##class(OcuTalon.Install.Step.Web).Definitions(.apps)
		Do $$$AssertStatusOK(sc, "Definitions")
		Set names = ""
		Set name = ""
		For {
			Set name = $Order(apps(name))
			Quit:name=""
			Set names = names_$Select(names = "": "", 1: ",")_name
		}
		Do $$$AssertEquals(names, "/ocutalon,/ocutalon/api,/ocutalon/hook,/ocutalon/public,/ocutalon/trace/ocutalon", "the five applications")
		For name = "/ocutalon", "/ocutalon/api", "/ocutalon/hook", "/ocutalon/public", "/ocutalon/trace/ocutalon" {
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
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// The online demo has no webhook (Story 35.3, AD-25): with the flag on, Definitions lists the four applications and no /ocutalon/hook, Grants declares
/// only the trace role's six grants, so the Roles step never creates OcuTalonWebhook there, and GrantsFor(0) declares the webhook role's three grants besides.
/// The flag is put back, also after a failure.
Method TestOnlineDemoNoHook()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Definitions(.apps), "Definitions with the flag on")
		Do $$$AssertEquals($Data(apps("/ocutalon/hook")), 0, "no /ocutalon/hook application on the online demo")
		Set names = ""
		Set name = ""
		For {
			Set name = $Order(apps(name))
			Quit:name=""
			Set names = names_$Select(names = "": "", 1: ",")_name
		}
		Do $$$AssertEquals(names, "/ocutalon,/ocutalon/api,/ocutalon/public,/ocutalon/trace/ocutalon", "the four applications")
		Set grants = ##class(OcuTalon.Install.Step.Web).Grants()
		Do $$$AssertEquals(grants.%Size(), 6, "six grants on the online demo")
		Set webhook = 0
		For i = 0:1:grants.%Size() - 1 {
			If grants.%Get(i).role = ##class(OcuTalon.Install.Step.Web).#HOOKROLE Set webhook = webhook + 1
		}
		Do $$$AssertEquals(webhook, 0, "no grant of the webhook role on the online demo")
		Set all = ##class(OcuTalon.Install.Step.Web).GrantsFor(0)
		Do $$$AssertEquals(all.%Size(), 9, "GrantsFor(0) adds the webhook role's three")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Set local = ##class(OcuTalon.Install.Step.Web).Grants()
		Do $$$AssertEquals(local.%Size(), 9, "nine grants off the online demo")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// The CSP session timeout (Story 16.4, matrix row 1): with the online-demo flag on, /ocutalon, /ocutalon/api and the OCUTALON trace
/// application get 120 seconds and /ocutalon/public keeps 28800; with the flag off, or absent, every application keeps 28800. The
/// OCUORDERS trace application the Demo step builds takes the same timeout as the OCUTALON one. The public setting onlineDemo is put
/// back, also after a failure; Expected (the flag off) is unchanged.
Method TestOnlineDemoTimeout()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).#ONLINETIMEOUT, 120, "the online demo's timeout is 120 seconds")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).#LOCALTIMEOUT, 28800, "a local install's is 8 hours")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Definitions(.apps), "Definitions with the flag on")
		Do $$$AssertEquals(apps("/ocutalon", "Timeout"), 120, "flag on: /ocutalon")
		Do $$$AssertEquals(apps("/ocutalon/api", "Timeout"), 120, "flag on: /ocutalon/api")
		Do $$$AssertEquals(apps("/ocutalon/trace/ocutalon", "Timeout"), 120, "flag on: the OCUTALON trace application")
		Do $$$AssertEquals(apps("/ocutalon/public", "Timeout"), 28800, "flag on: /ocutalon/public keeps 8 hours")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).TraceApp("OCUORDERS", .orders), "/ocutalon/trace/ocuorders", "the OCUORDERS trace application")
		Do $$$AssertEquals(orders("Timeout"), 120, "flag on: the OCUORDERS trace application")
		Do $$$AssertEquals(apps("/ocutalon", "Path"), $SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/", "the other properties are unchanged")
		For flag = 0, "" {
			Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
			Kill apps, orders
			Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Definitions(.apps), "Definitions with the flag '"_flag_"'")
			Set name = ""
			For {
				Set name = $Order(apps(name))
				Quit:name=""
				Do $$$AssertEquals(apps(name, "Timeout"), 28800, "flag '"_flag_"': "_name_" keeps 8 hours")
			}
			Do ##class(OcuTalon.Install.Step.Web).TraceApp("OCUORDERS", .orders)
			Do $$$AssertEquals(orders("Timeout"), 28800, "flag '"_flag_"': the OCUORDERS trace application keeps 8 hours")
		}
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
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
	Set hash = ##class(OcuTalon.Data.AddressCounter).AddressHash(address)
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("WebInstall", "streams", stream) = ""
	For days = 90, 0 {
		Do ##class(OcuTalon.Data.AddressCounter).%DeleteExtent()
		Set old = ..CounterRow(hash, 3660)
		Set recent = ..CounterRow(hash, 3540)
		Do $$$AssertTrue((old '= "") && (recent '= ""), "both counter rows are saved (days "_days_")")
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

/// The Web area's purge also keeps the uploads that nobody took to one hour (AD-27, Story 34.3, DW-752): Purge(90) and Purge(0) each delete an upload
/// made 3,660 seconds ago, keep one made 3,540 seconds ago and still purge the live events older than 24 hours. The purge is at the real clock and takes
/// the rows of every session, so this class runs only on a throwaway (Rule 21).
Method TestPurgeUploads()
{
	Set session = "ZzWeb"_..Number_"u"
	Set stream = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ^OcuTalonTest("WebInstall", "streams", stream) = ""
	For days = 90, 0 {
		Set old = ..UploadRef(session, 3660)
		Set recent = ..UploadRef(session, 3540)
		Do $$$AssertTrue((old '= "") && (recent '= ""), "both uploads are stored (days "_days_")")
		Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
		Set payload.Ref = "ZzWeb"_..Number_"u"_days
		Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stream, "reminder", payload, .seq), "an event is published")
		Do ##class(OcuTalon.Test.Data.Fixture).SetEventTs(stream, seq, ##class(OcuTalon.Test.Data.Fixture).HoursAgo(25))
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Purge(days), "the Web area's Purge("_days_")")
		Do $$$AssertEquals(##class(OcuTalon.Data.Upload).RefIndexExists(old), 0, "the 61-minute upload is deleted (days "_days_")")
		Do $$$AssertEquals(##class(OcuTalon.Data.Upload).RefIndexExists(recent), 1, "the 59-minute upload is kept (days "_days_")")
		Do $$$AssertEquals($ListFind($ListFromString(##class(OcuTalon.Test.Data.Fixture).EventSeqs(stream)), seq), 0, "the aged live event is purged too (days "_days_")")
		Do ##class(OcuTalon.Data.Upload).DropSession(session)
	}
}

/// The Web area's purge also deletes the sent files older than daysToKeep days (AD-27, Story 25.3): Purge(90) deletes a file made 91 days ago and keeps one made
/// 89 days ago. The purge is at the real clock and takes the rows of every session, so this class runs only on a throwaway (Rule 21).
Method TestPurgeSentFiles()
{
	Set session = "ZzWeb"_..Number_"f"
	Set old = ..SentFileRef(session, 91 * 86400)
	Set recent = ..SentFileRef(session, 89 * 86400)
	Try {
		Do $$$AssertTrue((old '= "") && (recent '= ""), "both files are stored")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Purge(90), "the Web area's Purge(90)")
		Do $$$AssertEquals(##class(OcuTalon.Data.SentFile).RefIndexExists(old), 0, "the file 91 days old is deleted")
		Do $$$AssertEquals(##class(OcuTalon.Data.SentFile).RefIndexExists(recent), 1, "the file 89 days old is kept")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the purge ran")
	}
	Do ##class(OcuTalon.Data.SentFile).DropSession(session)
}

/// The Web area's purge also runs the webhook counters' purge (AD-27, Story 35.3): Purge(90) deletes an accepted-event window three hours old, keeps the
/// current one, and writes the rejections that are still pending after 60 seconds as one audit entry. The purge is at the real clock and takes the
/// counters of every webhook, so this class runs only on a throwaway (Rule 21).
Method TestPurgeWebhookCounters()
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef(), slot = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set old = $Extract(##class(OcuTalon.Data.Time).AddSeconds(now, -10800), 1, 13)
	Set current = $Extract(now, 1, 13)
	Set ^OcuTalonP.WebhookC("a", ref, old) = 5
	Set ^OcuTalonP.WebhookC("a", ref, current) = 6
	Set ^OcuTalonP.WebhookC("r", slot) = $ListBuild(##class(OcuTalon.Data.Time).AddSeconds(now, -120), 3)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Purge(90), "the Web area's Purge")
		Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", ref, old)), 0, "the window three hours old is deleted")
		Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("a", ref, current)), 1, "the current window is kept")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", slot)
		Do $$$AssertEquals(entries.%Size(), 1, "the pending rejections are written as one audit entry")
		If entries.%Size() Do $$$AssertEquals(entries.%Get(0).data.counts.rejected, 3, "with their count")
		Do $$$AssertEquals($ListGet(^OcuTalonP.WebhookC("r", slot), 2), 0, "and none stays pending")
	} Catch exception {
		Do $$$AssertTrue(0, "the purge's checks ran: "_exception.DisplayString())
	}
	Kill ^OcuTalonP.WebhookC("a", ref), ^OcuTalonP.WebhookC("r", slot)
}

/// An upload of the session made the given number of seconds ago; returns its Ref, or "" when it could not be stored.
ClassMethod UploadRef(session As %String, secondsAgo As %Integer) As %String [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write("zz")
	Do bytes.Rewind()
	Set ref = ##class(OcuTalon.Data.Upload).Put(session, bytes, .sc)
	If ref = "" Quit ""
	Set row = ##class(OcuTalon.Data.Upload).RefIndexOpen(ref)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	If $SYSTEM.Status.IsError(row.%Save()) Quit ""
	Quit ref
}

/// A sent file of the session made the given number of seconds ago; returns its Ref, or "" when it could not be saved.
ClassMethod SentFileRef(session As %String, secondsAgo As %Integer) As %String [ Private ]
{
	Set bytes = ##class(%Stream.TmpBinary).%New()
	Do bytes.Write("%PDF-1.4 zz")
	Do bytes.Rewind()
	Set ref = ##class(OcuTalon.Data.SentFile).Put(session, "web", "zz.pdf", "application/pdf", bytes, .sc)
	If ref = "" Quit ""
	Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(ref)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	If $SYSTEM.Status.IsError(row.%Save()) Quit ""
	Quit ref
}

/// A counter row of the hash created the given number of seconds ago; returns its id, or "" when it could not be saved.
ClassMethod CounterRow(hash As %String, secondsAgo As %Integer) As %Integer [ Private ]
{
	Set row = ##class(OcuTalon.Data.AddressCounter).%New()
	Set row.AddressHash = hash
	Set row.CreatedAt = ##class(OcuTalon.Data.AddressCounter).Shift(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	If $SYSTEM.Status.IsError(row.%Save()) Quit ""
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
/// resources that AD-24 forbids to every OcuTalon role. The webhook role (Story 35.3, off the online demo) holds exactly Read on the code database and
/// Read and Write on the data and private databases, the least set that Task 0 measured, and never %All or an %Ens_* resource. The Users step adds two roles without a resource.
Method TestGrants()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do ..CheckGrants()
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

Method CheckGrants() [ Private ]
{
	Set grants = ##class(OcuTalon.Install.Step.Web).Grants()
	Do $$$AssertEquals(grants.%Size(), 9, "nine grants: the trace role's six and the webhook role's three")
	Set hook = ##class(OcuTalon.Install.Step.Web).#HOOKROLE
	Set seen = "", hookSeen = ""
	For i = 0:1:grants.%Size() - 1 {
		Set grant = grants.%Get(i)
		If grant.role = hook {
			Set hookSeen(grant.resource) = grant.permission
			Do $$$AssertTrue(($Extract(grant.resource, 1, 5) '= "%Ens_") && (grant.resource '= "%All"), "the webhook role holds no %All and no %Ens_ resource ("_grant.resource_")")
			Continue
		}
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
	Do $$$AssertEquals($Get(hookSeen("%DB_OCUTALON_CODE")), "R", "the webhook role: Read on the code database")
	Do $$$AssertEquals($Get(hookSeen("%DB_OCUTALON_DATA")), "RW", "the webhook role: Read and Write on the data database")
	Do $$$AssertEquals($Get(hookSeen("%DB_OCUTALON_PRIVATE")), "RW", "the webhook role: Read and Write on the private database")
	Set hookCount = 0, name = ""
	For {
		Set name = $Order(hookSeen(name))
		Quit:name=""
		Set hookCount = hookCount + 1
	}
	Do $$$AssertEquals(hookCount, 3, "and nothing else")

	Set sc = ##class(OcuTalon.Install.Registry).Declared("Grants", .declared)
	Do $$$AssertStatusOK(sc, "the declarations of all the areas")
	Set holds = 0, webhook = 0
	Set user = 0
	Set n = ""
	For {
		Set n = $Order(declared(n))
		Quit:n=""
		Set role = declared(n).role
		If role = "OcuTalonTraceViewer" Set holds = holds + 1
		If role = hook Set webhook = webhook + 1
		If (role = "OcuTalonUser") || (role = "OcuTalonAdmin") {
			Set user = user + 1
			Do $$$AssertEquals(declared(n).resource, "", role_" holds no resource")
		}
		If ($Extract(role, 1, 8) = "OcuTalon") && (role '= hook) {
			Do $$$AssertTrue(..Forbidden(declared(n).resource) = 0, "no OcuTalon role holds the forbidden "_declared(n).resource)
		}
	}
	Do $$$AssertEquals(holds, 6, "the registry sees the trace role's six grants")
	Do $$$AssertEquals(webhook, 3, "the registry sees the webhook role's three grants")
	Do $$$AssertEquals(user, 2, "the registry sees the two roles without a resource")
}

/// RemoveHook, which Run calls on the online demo, deletes an application that exists and is no error for one that does not. The test uses the fixture
/// application, never the real /ocutalon/hook.
Method TestRemoveHook()
{
	Do ..RemoveApplication()
	Do ##class(OcuTalon.Install.Step.Web).TraceApp("OCUTALON", .props)
	Set props("CookiePath") = ..Application_"/"
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Apply(..Application, .props), "a stand-in application is made")
	Do $$$AssertEquals(..Application(.stored), 1, "it exists")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveHook(..Application), "RemoveHook deletes it")
	Do $$$AssertEquals(..Application(.stored), 0, "and it is gone")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveHook(..Application), "an application that is not there is no error")
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

/// The removal of an earlier build's hashed files from the served folder, over every row of the rule except the stuck file: each top-level file that
/// matches STALEFILES and that the build lacks goes (the script, its map, a chunk, a polyfills file and a stylesheet), each is named by a "removed old
/// web file" line, every file of the build stays byte for byte, a folder named like a bundle file stays, the build folder is unchanged and a second run changes nothing.
Method TestRemoveStaleBundle()
{
	Set base = ..Directory_"zzbundle"_..Number_"s/"
	Set served = base_"served/"
	Set build = base_"build/"
	Do ..SeedBundle(build)
	Do ..SeedServed(served)
	Do ..Seed(served, "main-OLD88888.js/keep.txt", "keep")
	Set stale = "main-OLD11111.js|main-OLD11111.js.map|chunk-OLD22222.js|polyfills-OLD33333.js|styles-OLD44444.css"
	Set kept = ..Tree(build)_"|main-OLD88888.js|main-OLD88888.js/keep.txt|"_..#SURVIVORS
	Do $$$AssertEquals(..Tree(served), ..Sorted(..Tree(build)_"|main-OLD88888.js|main-OLD88888.js/keep.txt|"_..#SURVIVORS_"|"_stale), "the served folder holds the build, the survivors and the stale files")
	Set buildBefore = ..Tree(build)
	Set indexBefore = ..ReadFile(served_"index.html")
	Set mainBefore = ..ReadFile(served_"main-AB12CD34.js")

	Do ..Warnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle")
	Do $$$AssertEquals(..Tree(served), ..Sorted(kept), "only the stale files are gone")
	Do $$$AssertEquals(..Warnings(), "removed old web file chunk-OLD22222.js|removed old web file main-OLD11111.js|removed old web file main-OLD11111.js.map|removed old web file polyfills-OLD33333.js|removed old web file styles-OLD44444.css", "each removal is named")
	Do $$$AssertEquals(..Tree(build), buildBefore, "the build folder is unchanged")
	Do $$$AssertEquals(..ReadFile(served_"index.html"), indexBefore, "index.html is byte for byte")
	Do $$$AssertEquals(..ReadFile(served_"main-AB12CD34.js"), mainBefore, "and so is the build's script")
	Do $$$AssertEquals(..ReadFile(served_"zz-keep.txt"), "keep", "a survivor keeps its content")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "a second run")
	Do $$$AssertEquals(..Tree(served), ..Sorted(kept), "changes nothing")
	Do $$$AssertEquals(..Warnings(), "", "and says nothing")
}

/// Guard (i): only the top level of the served folder is scanned. A file that matches STALEFILES in a subfolder, and a folder that is named like a bundle file, stay.
Method TestStaleKeepsNestedFiles()
{
	Set base = ..Directory_"zzbundle"_..Number_"n/"
	Set served = base_"served/"
	Set build = base_"build/"
	Do ..SeedBundle(build)
	Do ..SeedBundle(served)
	Do ..Seed(served, "assets/main-OLD66666.js", "keep")
	Do ..Seed(served, "assets/fonts/chunk-OLD66666.js", "keep")
	Do ..Seed(served, "zz/main-OLD77777.js", "keep")
	Do ..Seed(served, "main-OLD88888.js/styles-OLD99999.css", "keep")
	Do ..Seed(served, "main-OLD11111.js", "stale")
	Set before = ..Tree(served)
	Do ..Warnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle")
	Do $$$AssertEquals(..Tree(served), ..RemoveName(before, "main-OLD11111.js"), "the top-level stale file is gone and nothing nested or folder-like is")
	Do $$$AssertEquals(..Warnings(), "removed old web file main-OLD11111.js", "and only it is named")
}

/// Guard (ii): a top-level file that does not match STALEFILES stays, whatever the build holds: an admin's file, a backup copy, a different case, a name outside the hash alphabet and an extension that is not js, css or map.
Method TestStaleKeepsOtherNames()
{
	Set base = ..Directory_"zzbundle"_..Number_"o/"
	Set served = base_"served/"
	Set build = base_"build/"
	Do ..SeedBundle(build)
	Do ..SeedBundle(served)
	Set names = $ListFromString(..#SURVIVORS, "|")
	Set position = 0
	While $ListNext(names, position, name) {
		If name '[ "/", name '= "zz" Do ..Seed(served, name, "mine")
	}
	Do ..Seed(served, "main-OLD55555.json", "mine")
	Do ..Seed(served, "main-OLD11111.js", "stale")
	Set before = ..Tree(served)
	Do ..Warnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle")
	Do $$$AssertEquals(..Tree(served), ..RemoveName(before, "main-OLD11111.js"), "only the file that matches STALEFILES and is not in the build is gone")
	Do $$$AssertEquals(..ReadFile(served_"zz-admin-note.txt"), "mine", "the admin's note keeps its content")
	Do $$$AssertEquals(..Warnings(), "removed old web file main-OLD11111.js", "and only the stale file is named")
}

/// Guard (iv): nothing is removed unless the served index.html is byte-equal to the build's (another build is served). The step is silent then.
Method TestStaleNeedsTheSameIndex()
{
	Set base = ..Directory_"zzbundle"_..Number_"i/"
	Set served = base_"served/"
	Set build = base_"build/"
	Do ..SeedBundle(build)
	Do ..SeedBundle(served)
	Do ..Seed(served, "main-OLD11111.js", "stale")
	Do ##class(%File).Delete(served_"index.html")
	Do ..Seed(served, "index.html", ..ReadFile(build_"index.html")_"<!-- another build -->")
	Set before = ..Tree(served)
	Do ..Warnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle")
	Do $$$AssertEquals(..Tree(served), before, "a different index.html: nothing is removed")
	Do $$$AssertEquals(..Warnings(), "", "and nothing is said")
	Do ##class(%File).Delete(served_"index.html")
	Do ..Seed(served, "index.html", ..ReadFile(build_"index.html"))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "the same index.html")
	Do $$$AssertEquals(..Tree(served), ..RemoveName(before, "main-OLD11111.js"), "removes the stale file")
	Do ..Warnings()
}

/// Guard (v): with no usable build list nothing is removed, the step is still OK and one warning line says why: no build folder, a missing folder, an empty one,
/// and one without index.html.
Method TestStaleNeedsABuildList()
{
	Set base = ..Directory_"zzbundle"_..Number_"v/"
	Set served = base_"served/"
	Do ..SeedBundle(served)
	Do ..Seed(served, "main-OLD11111.js", "stale")
	Set before = ..Tree(served)
	Do ##class(%File).CreateDirectoryChain(base_"empty/")
	Do ..Seed(base_"noindex/", "main-AB12CD34.js", "main")
	Set builds = $ListBuild("", base_"missing/", base_"empty/", base_"noindex/")
	Set labels = $ListBuild("no build folder", "a missing folder", "an empty folder", "a folder without index.html")
	Set position = 0
	Set at = 0
	While $ListNext(builds, position, build) {
		Set at = at + 1
		Set label = $List(labels, at)
		Do ..Warnings()
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle with "_label)
		Do $$$AssertEquals(..Tree(served), before, label_": nothing is removed")
		Set warnings = ..Warnings()
		Do $$$AssertTrue(warnings [ "no old web file was removed" && ($Length(warnings, "|") = 1), label_": one warning line says so: "_warnings)
	}
}

/// A file that can't be deleted gives a WARN line that names it, and the step is still OK: the stale files sit in a folder that is read-only, and once it is writable again the
/// next run removes them. Skipped where the folder can be written to anyway (a superuser).
Method TestRemoveStaleBundleWarns()
{
	Set base = ..Directory_"zzbundle"_..Number_"w/"
	Set served = base_"served/"
	Set build = base_"build/"
	Do ..SeedBundle(build)
	Do ..SeedBundle(served)
	Do ..Seed(served, "main-OLD11111.js", "stale")
	Do ..Seed(served, "chunk-OLD22222.js", "stale")
	Set before = ..Tree(served)
	Set folder = $Extract(served, 1, $Length(served) - 1)
	Set attributes = ##class(%File).Attributes(folder)
	Set locked = ##class(%File).SetReadOnly(folder)
	Set writable = 0
	If locked {
		Set probe = served_"zz-probe.txt"
		Do ..Seed(served, "zz-probe.txt", "probe")
		Set writable = ##class(%File).Exists(probe)
	}
	Set error = ""
	Try {
		If 'locked || writable {
			Do $$$AssertSkipped("The served folder can't be made read-only here: "_$Select('locked: "SetReadOnly failed", 1: "it is writable anyway"))
		} Else {
			Do ..Warnings()
			Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "RemoveStaleBundle")
			Set warnings = ..Warnings()
			Do $$$AssertEquals(warnings, "the old web file chunk-OLD22222.js could not be deleted|the old web file main-OLD11111.js could not be deleted", "each stuck file is named")
			Do $$$AssertEquals(..Tree(served), before, "and stays")
		}
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(%File).SetAttributes(folder, attributes)
	Do ##class(%File).Delete(served_"zz-probe.txt")
	Do $$$AssertEquals(error, "", "no error was thrown")
	If locked, 'writable {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).RemoveStaleBundle(served, build), "the next run, with the folder writable")
		Do $$$AssertEquals(..Tree(served), ..RemoveName(..RemoveName(before, "main-OLD11111.js"), "chunk-OLD22222.js"), "removes the stale files")
		Do ..Warnings()
	}
}

/// BuildFolder is the first of ocutalon/csp/ and src/ocutalon/csp/ below the root that holds index.html: each alone, both (ocutalon/csp/ wins), neither and no root.
/// On OcuTalon's image the installed module's root is /opt/ocutalon/src/; elsewhere that part is skipped.
Method TestBuildFolder()
{
	Set base = ..Directory_"zzbundle"_..Number_"b/"
	Do ..Seed(base_"a/ocutalon/csp/", "index.html", "a")
	Do ..Seed(base_"b/src/ocutalon/csp/", "index.html", "b")
	Do ..Seed(base_"c/ocutalon/csp/", "index.html", "c")
	Do ..Seed(base_"c/src/ocutalon/csp/", "index.html", "c")
	Do ..Seed(base_"d/ocutalon/csp/", "main-AB12CD34.js", "d")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).#BUILDFOLDERS, "ocutalon/csp/,src/ocutalon/csp/", "the two FileCopy sources")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(base_"a/"), base_"a/ocutalon/csp/", "ocutalon/csp/ alone")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(base_"b"), base_"b/src/ocutalon/csp/", "src/ocutalon/csp/ alone, a root without its closing separator")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(base_"c/"), base_"c/ocutalon/csp/", "both: ocutalon/csp/ wins")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(base_"d/"), "", "a folder without index.html is not a build")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(base_"none/"), "", "neither")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).BuildFolder(""), "", "no root")
	If ##class(%File).Exists(##class(OcuTalon.Install.Step.Demo).#VERSIONFILE) {
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).ModuleRoot(), "/opt/ocutalon/src/", "on the image the module's root is the baked source folder")
		Do $$$AssertTrue(##class(%File).Exists(##class(OcuTalon.Install.Step.Web).BuildFolder()_"index.html"), "and BuildFolder() finds the build there")
	} Else {
		Do $$$AssertSkipped("Not OcuTalon's image: "_##class(OcuTalon.Install.Step.Demo).#VERSIONFILE_" does not exist on this instance, so its module root is not known")
	}
}

/// Prepare, given the build folder, removes the stale file that was planted in the served folder and keeps the rest.
Method TestPrepareRemovesStale()
{
	Set data = ..Directory_"zzbundle"_..Number_"r/"
	Set build = ..Directory_"zzbundle"_..Number_"r-build/"
	Do ..SeedBundle(build)
	Do ..SeedBundle(data_"csp/ocutalon-web/")
	Do ..Seed(data_"csp/ocutalon-web/", "main-OLD11111.js", "stale")
	Do ..Seed(data_"csp/ocutalon-web/", "zz-admin-note.txt", "mine")
	Do ..Warnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Prepare(data, build), "Prepare")
	Do $$$AssertEquals(..Tree(data_"csp/ocutalon-web/"), ..Sorted(..Tree(build)_"|zz-admin-note.txt"), "the stale file is gone and the rest stays")
	Do $$$AssertEquals(..Warnings(), "removed old web file main-OLD11111.js", "and it is named")
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

/// The top-level survivors of the stale-file rule, joined by |: names that do not match STALEFILES, and files in subfolders.
Parameter SURVIVORS = "zz-keep.txt|zz-admin-note.txt|main-AB12CD34.js.bak|Main-OLD55555.js|main-zz_stale.js|assets/main-OLD66666.js|zz|zz/main-OLD77777.js";

/// A served folder: the bundle, the survivors and the stale files of TestRemoveStaleBundle.
ClassMethod SeedServed(dir As %String) [ Private ]
{
	Do ..SeedBundle(dir)
	Set files = $ListFromString(..#SURVIVORS, "|")
	Set position = 0
	While $ListNext(files, position, name) {
		If name '= "zz" Do ..Seed(dir, name, "keep")
	}
	Set stale = $ListFromString("main-OLD11111.js|main-OLD11111.js.map|chunk-OLD22222.js|polyfills-OLD33333.js|styles-OLD44444.css", "|")
	Set position = 0
	While $ListNext(stale, position, name) {
		Do ..Seed(dir, name, "stale")
	}
}

/// The names of a |-joined list, sorted by name.
ClassMethod Sorted(list As %String) As %String [ Private ]
{
	Kill names
	Set parts = $ListFromString(list, "|")
	Set position = 0
	While $ListNext(parts, position, part) {
		Set names(part) = ""
	}
	Set sorted = ""
	Set name = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Set sorted = sorted_$Select(sorted = "": "", 1: "|")_name
	}
	Quit sorted
}

/// A |-joined list without one name.
ClassMethod RemoveName(list As %String, remove As %String) As %String [ Private ]
{
	Set kept = ""
	Set parts = $ListFromString(list, "|")
	Set position = 0
	While $ListNext(parts, position, part) {
		If part '= remove Set kept = kept_$Select(kept = "": "", 1: "|")_part
	}
	Quit kept
}

/// The warning lines that the Web step recorded since the last call, joined by | and sorted, and clears them.
ClassMethod Warnings() As %String [ Private ]
{
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Kill sorted
	Set position = 0
	While $ListNext(lines, position, line) {
		Set sorted(line) = ""
	}
	Set text = ""
	Set line = ""
	For {
		Set line = $Order(sorted(line))
		Quit:line=""
		Set text = text_$Select(text = "": "", 1: "|")_line
	}
	Quit text
}

/// The content of a file.
ClassMethod ReadFile(file As %String) As %String [ Private ]
{
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(file)
	Set text = stream.Read(32000)
	Quit text
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
	If name = "/ocutalon/hook" {
		Set expected("AutheEnabled") = 64
		Set expected("GroupById") = ""
		Set expected("DispatchClass") = "OcuTalon.Web.Hook"
		Set expected("Path") = ""
		Set expected("ServeFiles") = 0
		Set expected("CookiePath") = "/ocutalon/hook/"
		Set expected("MatchRoles") = ":OcuTalonWebhook"
		Set expected("PermittedClasses") = ""
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
