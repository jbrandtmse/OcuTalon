Include (Ensemble, %sySecurity)

/// The Demo step (AD-3, AD-23): with demo mode on it creates the namespace OCUORDERS, enables Interoperability there,
/// adds the OCUORDERS trace application and the trace role's OCUORDERS grants, and starts OcuTalon.Demo.Orders.Production.
/// With demo mode off it removes everything it created, and keeps an OCUORDERS that it did not create (below). It runs at
/// every start in its place in the registry's order, and again whenever Story 4.1 switches demo mode.
///   - The mode is the product setting demo.mode ("1" is on). The step seeds it at every run, with 1 where the image's
///     version file exists (the Docker install) and 0 where it does not (an IPM install), and never overwrites a row.
///   - It creates only what is missing and never recreates a database file that exists. It owns the namespace OCUORDERS
///     whose default destinations are its own two directories (below the manager directory), the objects named below, and
///     nothing else: a foreign OCUORDERS makes the on path fail and the off path keep it.
///   - OCUORDERS has the code database OCUORDERS_CODE and the data database OCUORDERS_DATA, with the resources
///     %DB_OCUORDERS_CODE and %DB_OCUORDERS_DATA (no public permission). Its package mappings give it OcuTalon.Demo.Orders
///     (OCUTALON_CODE) and the two public packages and the public global (OCUTALON_PUBLIC). Interoperability is enabled with
///     EnableNamespace and its install flag, which runs no HealthShare Foundation installer on either image: the namespace
///     holds no Foundation artefact, and OcuTalon deletes none.
///   - With demo mode on the step also gives the service role (OcuTalonServiceRole) Read on the data database resource %DB_OCUORDERS_DATA and
///     nothing else of OCUORDERS (no code database, no SQL grant, no write), so that OcuTalon.Watch.Reader, which judges a namespace by the
///     service user's read access, lists the Orders production (veto U-79). The off path and the keep path remove that grant; a missing
///     service role fails the on path with a plain sentence (ServiceRole, WithOrdersData).
///   - Off removes the namespace, both databases with their directories, the mappings, the web applications of the
///     namespace, its Interoperability markers and role, its SQL privileges, its resources and the trace role's OCUORDERS
///     grants. Each removal runs only when its object exists, so the off path does nothing when nothing is there.
///   - Off keeps an OCUORDERS that is not the step's own (its databases are foreign), and one in which another production is
///     defined or is not stopped. It deletes, stops, starts and changes nothing inside it: its namespace, databases and files,
///     mappings, Interoperability markers and role, productions and other web applications stay. It removes only OcuTalon's own
///     access: the trace application, the trace role's OCUORDERS database grants and its SQL privileges in the namespace
///     (AD-24). It then warns (Install.Step.Warn) with the sentence of the on path's refusal, records the status mark
///     demoKept (OcuTalon.Data.StatusMark), whose value is the JSON {"text","namespace","globals","routines","how"} with the
///     sentence, the namespace's default databases and the owner's sentence that says what was kept and how to remove the
///     namespace by hand (the "how" field), and returns OK, so the start ends ready. A create or a remove that succeeds
///     clears the mark, and an error leaves it as it was.
/// The step switches namespace in three methods, each with New $NAMESPACE: System (to %SYS), ServiceRole (to %SYS and back for its one pure call) and Orders (to OCUORDERS). Neither
/// calls a method of this class while it is in its target namespace, because OcuTalon.* classes resolve in neither; System
/// returns to the caller's namespace for the one pure call it needs.
Class OcuTalon.Install.Step.Demo Extends OcuTalon.Install.Step
{

/// The setting that holds the mode: "1" for on, anything else off.
Parameter MODEKEY = "demo.mode";

/// The namespace of the demo.
Parameter NAMESPACE = "OCUORDERS";

/// The production the step starts in the namespace.
Parameter PRODUCTION = "OcuTalon.Demo.Orders.Production";

/// The code database of the namespace.
Parameter CODEDB = "OCUORDERS_CODE";

/// The data database of the namespace.
Parameter DATADB = "OCUORDERS_DATA";

/// The status mark that holds the note of a kept OCUORDERS; absent when the last run created or removed.
Parameter KEPTMARK = "demoKept";

/// The file that exists only in OcuTalon's image: it tells the Docker install from an IPM install.
Parameter VERSIONFILE = "/opt/ocutalon/version";

/// The longest the step waits for every item to run, in seconds.
Parameter WAITSECONDS = 60;

/// The longest a stop waits for the jobs to stop, in seconds.
Parameter STOPSECONDS = 30;

/// The job statuses that mean a job does not run.
Parameter DEADSTATUSES = "error,halted,terminated";

/// Applies the mode: "create" makes the demo and starts its production, "remove" removes it, "keep" leaves the namespace and
/// removes only OcuTalon's access to it, and "error" does nothing (see Plan). The seed is written before the plan is made; a
/// seed that cannot be written throws its error (Mode), which Install.Registry's RunStep reports as a failed step. A kept
/// namespace (from Plan, or from Orders(0) for another production) is warned about and recorded as the mark demoKept, whose
/// "how" sentence names what the namespace holds, and Run returns OK; a create or a remove that succeeds deletes the mark.
ClassMethod Run() As %Status
{
	Set exists = ##class(%SYS.Namespace).Exists(..#NAMESPACE)
	Set action = ..Plan(..Mode(), exists, ..Owned(), .sc, .kept, .what)
	If action = "create" {
		Set sc = ..System(1)
		If $$$ISOK(sc) {
			Set name = ##class(OcuTalon.Install.Step.Web).TraceApp(..#NAMESPACE, .props)
			Set sc = ##class(OcuTalon.Install.Step.Web).Apply(name, .props)
		}
		If $$$ISOK(sc) Set sc = ..Orders(1)
	} ElseIf action = "remove" {
		Set sc = $$$OK
		If exists && ##class(%Library.EnsembleMgr).IsEnsembleNamespace(..#NAMESPACE) {
			Set sc = ..Orders(0, .kept, .what)
		}
		If $$$ISOK(sc) && (kept = "") Set sc = ..System(0)
	}
	If $$$ISERR(sc) Quit sc
	If kept '= "" {
		Set sc = ..System(0, kept, what, .note)
		If $$$ISERR(sc) Quit sc
		Do ..Warn(kept)
		Quit ##class(OcuTalon.Data.StatusMark).Record(..#KEPTMARK, note)
	}
	Quit ##class(OcuTalon.Data.StatusMark).Record(..#KEPTMARK, "")
}

/// What to do, from the mode and the state of the namespace. Pure.
///   - on, and the namespace exists but is not the step's own: "error", with sc the refusal;
///   - on otherwise: "create";
///   - off, and the namespace exists but is not the step's own: "keep", with kept the sentence of the refusal;
///   - off otherwise: "remove", which also cleans the step's own leftovers when the namespace is gone. Orders(0) may still
///     turn it into a keep.
/// kept is "" except for "keep". what is "" too, and for "keep" it is the fact that the sentence names, as the phrase that the
/// note's "how" sentence takes after "because it holds" (System).
ClassMethod Plan(on As %Boolean, exists As %Boolean, owned As %Boolean, Output sc As %Status, Output kept As %String, Output what As %String) As %String
{
	Set sc = $$$OK
	Set kept = ""
	Set what = ""
	Set foreign = "Namespace "_..#NAMESPACE_" exists and uses databases that OcuTalon did not create, so the Demo step leaves it alone."
	If on {
		If exists && 'owned {
			Set sc = $$$ERROR($$$GeneralError, foreign)
			Quit "error"
		}
		Quit "create"
	}
	If exists && 'owned {
		Set kept = foreign
		Set what = "databases that OcuTalon did not create"
		Quit "keep"
	}
	Quit "remove"
}

/// 1 when demo mode is on. Seeds the setting with DefaultMode() when the row is absent, drops this process's cache entry of
/// it (Seed does), and reads it: the mode is on only for the value "1". A seed that fails throws its status, so that a row
/// that cannot be written never switches demo mode off.
ClassMethod Mode() As %Boolean
{
	$$$ThrowOnError(##class(OcuTalon.Data.Setting).Seed(..#MODEKEY, ..DefaultMode()))
	Quit (##class(OcuTalon.Data.Setting).Get(..#MODEKEY) = "1")
}

/// The seed of demo mode: 1 when the image's version file exists (the Docker install), 0 otherwise (an IPM install).
ClassMethod DefaultMode(versionFile As %String = {..#VERSIONFILE}) As %Boolean
{
	Quit ''##class(%File).Exists(versionFile)
}

/// A role's resource list ("resource:permission,...") with the OCUORDERS database resources added with Read (on), or
/// removed (off). A listed OCUORDERS resource keeps its place and is set to Read; any other entry stays as it was. Pure and
/// idempotent.
ClassMethod WithOrders(resources As %String, on As %Boolean) As %String
{
	Set own = $ListBuild("%DB_"_..#CODEDB, "%DB_"_..#DATADB)
	Set result = ""
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If entry = "" Continue
		Set name = $Piece(entry, ":", 1)
		If $ListFind(own, name) {
			Set seen(name) = ""
			If 'on Continue
			Set entry = name_":R"
		}
		Set result = result _ $Select(result = "": "", 1: ",") _ entry
	}
	If on {
		Set position = 0
		While $ListNext(own, position, name) {
			If '$Data(seen(name)) Set result = result _ $Select(result = "": "", 1: ",") _ name_":R"
		}
	}
	Quit result
}

/// A role's resource list ("resource:permission,...") with Read on the OCUORDERS data database alone (%DB_OCUORDERS_DATA:R) added
/// (on), or removed (off): the grant of the service role (U-79), which never holds the code database. A listed entry keeps its place
/// and is set to Read; any other entry stays as it was, the code database's included. Pure and idempotent.
ClassMethod WithOrdersData(resources As %String, on As %Boolean) As %String
{
	Set own = "%DB_"_..#DATADB
	Set result = ""
	Set seen = 0
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If entry = "" Continue
		If $Piece(entry, ":", 1) = own {
			Set seen = 1
			If 'on Continue
			Set entry = own_":R"
		}
		Set result = result _ $Select(result = "": "", 1: ",") _ entry
	}
	If on && 'seen Set result = result _ $Select(result = "": "", 1: ",") _ own_":R"
	Quit result
}

/// The directory of one of the step's databases: below the manager directory, in lower case, with its closing slash.
ClassMethod Directory(db As %String) As %String
{
	Quit ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory()_$ZConvert(db, "L"))
}

/// 1 when the namespace exists and is the step's own: its default destination for globals is the step's data directory and
/// its default destination for routines is the step's code directory. 0 for a namespace that does not exist. Switches no
/// namespace.
ClassMethod Owned(namespace As %String = {..#NAMESPACE}) As %Boolean
{
	If '##class(%SYS.Namespace).Exists(namespace) Quit 0
	If ##class(%SYS.Namespace).GetGlobalDest(namespace, "^ZZOcuTalonOwned") '= ("^"_..Directory(..#DATADB)) Quit 0
	Quit (##class(%SYS.Namespace).GetRoutineDest(namespace, "ZZOcuTalonOwned.1", "INT") = ("^"_..Directory(..#CODEDB)))
}

/// Creates (on) or removes (off) everything of the step that lives in %SYS and in the CPF. Runs in %SYS, where only the
/// system classes resolve. Every action is idempotent.
/// With keep (the sentence of the warning) given, off keeps the namespace: it deletes only the trace application, the trace
/// role's OCUORDERS database grants and its SQL privileges in the namespace, and returns in note the JSON
/// {"text": keep, "namespace", "globals", "routines", "how"}, "globals" and "routines" being the namespace's default databases.
/// "how" is the owner's sentence, with what (the fact that keep names, as a phrase) in place of {what was kept}:
/// "OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace
/// OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal."
ClassMethod System(on As %Boolean, keep As %String = "", what As %String = "", Output note As %String) As %Status [ Private ]
{
	Set home = $Namespace
	Set ns = ..#NAMESPACE
	Set role = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Set traceApp = ##class(OcuTalon.Install.Step.Web).TraceApp(ns)
	Set note = ""
	Set publicGlobal = ##class(OcuTalon.Data.Public.Settings).#GLOBALNAME
	Set dirs(..#CODEDB) = ..Directory(..#CODEDB)
	Set dirs(..#DATADB) = ..Directory(..#DATADB)
	Set resources(..#CODEDB) = "%DB_"_..#CODEDB
	Set resources(..#DATADB) = "%DB_"_..#DATADB
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set sc = $$$OK
	If on {
		#; Resources: no public permission.
		Set db = ""
		For {
			Set db = $Order(resources(db))
			Quit:db=""
			If ##class(Security.Resources).Exists(resources(db)) Continue
			Set sc = ##class(Security.Resources).Create(resources(db), "OCUORDERS "_$ZConvert($Piece(db, "_", 2), "L")_" database")
			If $$$ISERR(sc) Quit
		}
		If $$$ISERR(sc) Quit sc
		#; Databases: the directory, the file only when it is absent, then the CPF entry.
		Set db = ""
		For {
			Set db = $Order(dirs(db))
			Quit:db=""
			Set dir = dirs(db)
			If '##class(%File).DirectoryExists(dir) && '##class(%File).CreateDirectoryChain(dir) {
				Set sc = $$$ERROR($$$GeneralError, "The Demo step could not create the directory "_dir)
				Quit
			}
			If '##class(%File).Exists(dir_"IRIS.DAT") {
				Set sc = ##class(SYS.Database).CreateDatabase(dir, , , , resources(db))
				If $$$ISERR(sc) Quit
			}
			Kill props
			If ##class(Config.Databases).Exists(db) {
				Set sc = ##class(Config.Databases).Get(db, .props)
				If $$$ISERR(sc) Quit
				If ##class(%File).NormalizeDirectory(props("Directory")) '= dir {
					Set sc = $$$ERROR($$$GeneralError, "The database "_db_" exists with the directory "_props("Directory")_", not "_dir_", so the Demo step cannot use it.")
					Quit
				}
			} Else {
				Set props("Directory") = dir
				Set sc = ##class(Config.Databases).Create(db, .props)
				If $$$ISERR(sc) Quit
			}
		}
		If $$$ISERR(sc) Quit sc
		#; The namespace, then its mappings.
		If '##class(Config.Namespaces).Exists(ns) {
			Kill props
			Set props("Globals") = ..#DATADB
			Set props("Routines") = ..#CODEDB
			Set sc = ##class(Config.Namespaces).Create(ns, .props)
			If $$$ISERR(sc) Quit sc
		}
		Set maps = $ListBuild($ListBuild("Config.MapPackages", "OcuTalon.Demo.Orders", "OCUTALON_CODE"), $ListBuild("Config.MapPackages", "OcuTalon.Web.Public", "OCUTALON_PUBLIC"), $ListBuild("Config.MapPackages", "OcuTalon.Data.Public", "OCUTALON_PUBLIC"), $ListBuild("Config.MapGlobals", publicGlobal, "OCUTALON_PUBLIC"))
		For i = 1:1:$ListLength(maps) {
			Set map = $List(maps, i)
			Kill props
			If $ClassMethod($List(map, 1), "Exists", ns, $List(map, 2)) {
				Set sc = $ClassMethod($List(map, 1), "Get", ns, $List(map, 2), .props)
				If $$$ISOK(sc) && ($Get(props("Database")) '= $List(map, 3)) {
					Set props("Database") = $List(map, 3)
					Set sc = $ClassMethod($List(map, 1), "Modify", ns, $List(map, 2), .props)
				}
			} Else {
				Set props("Database") = $List(map, 3)
				Set sc = $ClassMethod($List(map, 1), "Create", ns, $List(map, 2), .props)
			}
			If $$$ISERR(sc) Quit
		}
		If $$$ISERR(sc) Quit sc
		#; Interoperability: the install flag runs no Foundation installer.
		If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(ns) {
			Set sc = ##class(%Library.EnsembleMgr).EnableNamespace(ns, 0, , 1)
			If $$$ISERR(sc) Quit sc
		}
		#; The trace role: Read on the OCUORDERS databases.
		If '##class(Security.Roles).Exists(role) Quit $$$ERROR($$$GeneralError, "The role "_role_" does not exist, so the Demo step cannot grant it the OCUORDERS databases.")
		Kill props
		Set sc = ##class(Security.Roles).Get(role, .props)
		If $$$ISERR(sc) Quit sc
		Set current = $Get(props("Resources"))
		Set $NAMESPACE = home
		Set wanted = ..WithOrders(current, 1)
		Set $NAMESPACE = "%SYS"
		If wanted '= current {
			Kill props
			Set props("Resources") = wanted
			Set sc = ##class(Security.Roles).Modify(role, .props)
			If $$$ISERR(sc) Quit sc
		}
		#; The service role: Read on the OCUORDERS data database only, so that Watch.Reader finds the Orders production (U-79).
		Set $NAMESPACE = home
		Set sc = ..ServiceRole(1)
		Set $NAMESPACE = "%SYS"
		Quit sc
	}
	#; Off: applications first, then the grants, the namespace, the markers, the SQL privileges, the databases, the resources.
	#; Keep: the trace application, the grants and the trace role's SQL privileges only, then the note.
	If keep '= "" {
		If ##class(Security.Applications).Exists(traceApp) Set apps(traceApp) = ""
	} Else {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Path FROM Security.Applications WHERE NameSpace = ?", ns)
		If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The Demo step could not list the web applications of "_ns_": "_rs.%Message)
		While rs.%Next() {
			Set apps(rs.%Get("Name")) = rs.%Get("Path")
		}
	}
	Set portalDir = ##class(%File).NormalizeDirectory($SYSTEM.Util.DataDirectory()_"csp/"_$ZConvert(ns, "L"))
	Set app = ""
	For {
		Set app = $Order(apps(app), 1, path)
		Quit:app=""
		Set sc = ##class(Security.Applications).Delete(app)
		If $$$ISERR(sc) Quit
		If (path '= "") && (##class(%File).NormalizeDirectory(path) = portalDir) && ##class(%File).DirectoryExists(portalDir) {
			If '##class(%File).RemoveDirectoryTree(portalDir) Set sc = $$$ERROR($$$GeneralError, "The Demo step could not remove the directory "_portalDir)
		}
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	If ##class(Security.Roles).Exists(role) {
		Kill props
		Set sc = ##class(Security.Roles).Get(role, .props)
		If $$$ISERR(sc) Quit sc
		Set current = $Get(props("Resources"))
		Set $NAMESPACE = home
		Set wanted = ..WithOrders(current, 0)
		Set $NAMESPACE = "%SYS"
		If wanted '= current {
			Kill props
			Set props("Resources") = wanted
			Set sc = ##class(Security.Roles).Modify(role, .props)
			If $$$ISERR(sc) Quit sc
		}
	}
	Set $NAMESPACE = home
	Set sc = ..ServiceRole(0)
	Set $NAMESPACE = "%SYS"
	If $$$ISERR(sc) Quit sc
	If keep = "" {
		If ##class(Config.Namespaces).Exists(ns) {
			Set sc = ##class(Config.Namespaces).Delete(ns)
			If $$$ISERR(sc) Quit sc
		}
		If $Data(^%SYS("Ensemble", "InstalledNamespace", ns)) {
			Set sc = ##class(%Library.EnsembleMgr).DisableNamespace(ns)
			If $$$ISERR(sc) Quit sc
		}
		Set interopRole = $$$InteropNSRole(ns)
		If ##class(Security.Roles).Exists(interopRole) {
			Set sc = ##class(Security.Roles).Delete(interopRole)
			If $$$ISERR(sc) Quit sc
		}
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, SQLObject, Privilege, Grantee, Grantor FROM Security.SQLPrivileges WHERE Namespace = ?", ns)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The Demo step could not list the SQL privileges of "_ns_": "_rs.%Message)
	While rs.%Next() {
		If (keep '= "") && (rs.%Get("Grantee") '= role) Continue
		Set privs($Increment(privs)) = $ListBuild(rs.%Get("Namespace"), rs.%Get("SQLObject"), rs.%Get("Privilege"), rs.%Get("Grantee"), rs.%Get("Grantor"))
	}
	For i = 1:1:+$Get(privs) {
		Set sc = ##class(Security.SQLPrivileges).%DeleteId($ListToString(privs(i), "||"))
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	If keep '= "" {
		Kill props
		Set sc = ##class(Config.Namespaces).Get(ns, .props)
		If $$$ISERR(sc) Quit sc
		Set how = "OcuTalon left the "_ns_" namespace in place because it holds "_what_". To remove it, delete the namespace "_ns_" and its databases "_..#CODEDB_" and "_..#DATADB_" in the Management Portal."
		Set note = {"text": (keep), "namespace": (ns), "globals": ($Get(props("Globals"))), "routines": ($Get(props("Routines"))), "how": (how)}.%ToJSON()
		Quit $$$OK
	}
	#; Databases, innermost directory first: those whose directory is a step directory or below one.
	Set rs = ##class(%ResultSet).%New("Config.Databases:List")
	Set sc = rs.Execute()
	If $$$ISERR(sc) Quit sc
	While rs.Next() {
		Set dir = ##class(%File).NormalizeDirectory(rs.Get("Directory"))
		If ($Extract(dir, 1, $Length(dirs(..#CODEDB))) = dirs(..#CODEDB)) || ($Extract(dir, 1, $Length(dirs(..#DATADB))) = dirs(..#DATADB)) {
			Set owned($Length(dir), rs.Get("Name")) = dir
			If $Extract(rs.Get("Name"), 1, 9) = "OCUORDERS" Set gone("%DB_"_rs.Get("Name")) = ""
		}
	}
	Set length = ""
	For {
		Set length = $Order(owned(length), -1)
		Quit:length=""
		Set db = ""
		For {
			Set db = $Order(owned(length, db), 1, dir)
			Quit:db=""
			Set sc = ##class(Config.Databases).Delete(db)
			If $$$ISERR(sc) Quit
			If ##class(%File).Exists(dir_"IRIS.DAT") {
				Set sc = ##class(SYS.Database).DeleteDatabase(dir)
				If $$$ISERR(sc) Quit
			}
			If ##class(%File).DirectoryExists(dir) && '##class(%File).RemoveDirectoryTree(dir) {
				Set sc = $$$ERROR($$$GeneralError, "The Demo step could not remove the directory "_dir)
				Quit
			}
		}
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	#; A database that was never entered in the CPF leaves its directory.
	Set db = ""
	For {
		Set db = $Order(dirs(db))
		Quit:db=""
		Set dir = dirs(db)
		If ##class(%File).Exists(dir_"IRIS.DAT") {
			Set sc = ##class(SYS.Database).DeleteDatabase(dir)
			If $$$ISERR(sc) Quit
		}
		If ##class(%File).DirectoryExists(dir) && '##class(%File).RemoveDirectoryTree(dir) {
			Set sc = $$$ERROR($$$GeneralError, "The Demo step could not remove the directory "_dir)
			Quit
		}
	}
	If $$$ISERR(sc) Quit sc
	#; Resources, and the roles of the same name: the step's two, and those of its other databases (the non-Health image's
	#; Interoperability creates a SECONDARY database with its own).
	Set db = ""
	For {
		Set db = $Order(resources(db))
		Quit:db=""
		Set gone(resources(db)) = ""
	}
	Set name = ""
	For {
		Set name = $Order(gone(name))
		Quit:name=""
		If ##class(Security.Roles).Exists(name) {
			Set sc = ##class(Security.Roles).Delete(name)
			If $$$ISERR(sc) Quit
		}
		If ##class(Security.Resources).Exists(name) {
			Set sc = ##class(Security.Resources).Delete(name)
			If $$$ISERR(sc) Quit
		}
	}
	Quit sc
}

/// Gives (on) or takes from (off) the service role its Read on the OCUORDERS data database, by WithOrdersData. Runs in the
/// namespace where OcuTalon classes resolve (System calls it after switching back from %SYS), reads and writes the role in %SYS and
/// returns in the namespace it was called in. On, a missing role is an error; off, a missing role has nothing to remove.
ClassMethod ServiceRole(on As %Boolean) As %Status [ Private ]
{
	Set home = $Namespace
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If '##class(Security.Roles).Exists(role) {
		If 'on Quit $$$OK
		Quit $$$ERROR($$$GeneralError, "The role "_role_" does not exist, so the Demo step cannot grant it the OCUORDERS data database.")
	}
	Kill props
	Set sc = ##class(Security.Roles).Get(role, .props)
	If $$$ISERR(sc) Quit sc
	Set current = $Get(props("Resources"))
	Set $NAMESPACE = home
	Set wanted = ..WithOrdersData(current, on)
	Set $NAMESPACE = "%SYS"
	If wanted = current Quit $$$OK
	Kill props
	Set props("Resources") = wanted
	Quit ##class(Security.Roles).Modify(role, .props)
}

/// Grants the trace role SQL SELECT on Ens.MessageHeader and starts the Orders production (on), or stops the production and
/// revokes the grant (off). Runs in OCUORDERS, where only OcuTalon.Demo.Orders, Ens, EnsLib and % classes resolve, so it calls
/// no method of this class there. The state machine and the item-run predicate are Install.Step.Production's (Start,
/// NotRunning), restated for this namespace.
///   - on: a running production of this name is left; Troubled is recovered and started; Stopped or Suspended is started,
///     after its definition is loaded from the class (the class is compiled in OCUTALON, so this namespace has no
///     definition of its own); another production that is running, Troubled or Suspended is an error and nothing is stopped.
///     Then it polls once a second, up to WAITSECONDS, until the production runs and every enabled item with a pool has an
///     alive job that is not in error, halted or terminated.
///   - off: another production that is not stopped, or any other production defined in the namespace, is not touched: kept
///     is set to the sentence that says so and what to the fact that it names ("the production <name>", with ", which is not
///     stopped" where it is not), nothing is stopped, started or removed, and the status is OK (the caller keeps the
///     namespace); otherwise a running or Troubled production of this name is stopped (STOPSECONDS, forced).
/// kept and what are "" unless the off path keeps the namespace. The on path's refusal of another production keeps its error.
ClassMethod Orders(on As %Boolean, Output kept As %String, Output what As %String) As %Status [ Private ]
{
	Set kept = ""
	Set what = ""
	Set ns = ..#NAMESPACE
	Set production = ..#PRODUCTION
	Set role = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Set wait = ..#WAITSECONDS
	Set stop = ..#STOPSECONDS
	Set dead = $ListFromString(..#DEADSTATUSES)
	New $NAMESPACE
	Set $NAMESPACE = ns
	Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
	If $$$ISERR(sc) Quit sc
	If (name '= "") && (name '= production) && ((state = $$$eProductionStateRunning) || (state = $$$eProductionStateTroubled) || (state = $$$eProductionStateSuspended)) {
		Set message = "The production "_name_" is in namespace "_ns_" and is not stopped, so the Demo step leaves it alone."
		If on Quit $$$ERROR($$$GeneralError, message)
		Set kept = message
		Set what = "the production "_name_", which is not stopped"
		Quit $$$OK
	}
	If on {
		If $SYSTEM.SQL.Security.CheckPrivilege(role, 1, "Ens.MessageHeader", "s") '= 1 {
			Set sc = $SYSTEM.SQL.Security.GrantPrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
			If $$$ISERR(sc) Quit sc
		}
		If '((state = $$$eProductionStateRunning) && (name = production)) {
			If state = $$$eProductionStateTroubled {
				Set sc = ##class(Ens.Director).RecoverProduction()
				If $$$ISERR(sc) Quit sc
			}
			Set sc = ##class(Ens.Config.Production).LoadFromClass(production)
			If $$$ISERR(sc) Quit sc
			Set sc = ##class(Ens.Director).StartProduction(production)
			If $$$ISERR(sc) Quit sc
		}
		Set deadline = $ZHorolog + wait
		For {
			Kill alive
			Set missing = ""
			If '##class(Ens.Director).IsProductionRunning(.running) || (running '= production) {
				Set missing = production_" is not running"
			} Else {
				Set rs = ##class(%ResultSet).%New("Ens.Job:Enumerate")
				If $$$ISOK(rs.Execute()) {
					While rs.Next() {
						If rs.Get("State") '= "Alive" Continue
						If $ListFind(dead, rs.Get("Status")) Continue
						Set alive(rs.Get("ConfigName")) = ""
					}
				}
				Set item = ""
				For {
					Set item = $Order($$$ConfigRoot(item))
					Quit:item=""
					If item = "%Production" Continue
					If '$Get($$$ConfigIsEnabled(item)) Continue
					If '$Get($$$ConfigPoolSize(item)) Continue
					If '$Data(alive(item)) Set missing = missing _ $Select(missing = "": "", 1: ",") _ item
				}
				If missing '= "" Set missing = "these items do not run: "_missing
			}
			If missing = "" Quit
			If $ZHorolog >= deadline {
				Quit
			}
			Hang 1
		}
		If missing '= "" Quit $$$ERROR($$$GeneralError, production_" did not finish starting in "_wait_" s: "_missing)
		Quit $$$OK
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Name FROM Ens_Config.Production WHERE Name <> ?", production)
	If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "The Demo step could not list the productions of "_ns_": "_rs.%Message)
	If rs.%Next() {
		Set kept = "The production "_rs.%Get("Name")_" is in namespace "_ns_", so the Demo step leaves it alone."
		Set what = "the production "_rs.%Get("Name")
		Quit $$$OK
	}
	If (name = production) && ((state = $$$eProductionStateRunning) || (state = $$$eProductionStateTroubled)) {
		Set sc = ##class(Ens.Director).StopProduction(stop, 1)
		If $$$ISERR(sc) Quit sc
	}
	If $SYSTEM.SQL.Security.CheckPrivilege(role, 1, "Ens.MessageHeader", "s") = 1 {
		Set sc = $SYSTEM.SQL.Security.RevokePrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
	}
	Quit sc
}

}
