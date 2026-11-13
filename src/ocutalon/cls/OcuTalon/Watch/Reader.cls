Include (Ensemble, EnsConstants, EnsErrors)

/// The reader of the productions that OcuTalon can watch (AD-3, AD-4, AD-6): the only class that switches namespace to look at a production, and
/// the only place that checks the service user's read access to a namespace. The watch tools and WatchOps both use it, so a tool and the
/// owner of the watch agree on what can be watched.
///   - Productions lists one entry per readable Interoperability namespace: its own current production, the one that
///     Ens.Director.GetProductionStatus gives, else the namespace's last production as Ens.Director.GetActiveProductionName gives it (the last one
///     started there, or the one set to start automatically when none had started), so that a cleanly stopped production can still be watched and a
///     watch on it stopped (DW-222). A namespace that never started a production has no entry, and no
///     other Ens.Config.Production row is ever an entry (DW-38). An entry is
///     {"namespace", "production" (the class name), "displayName", "state"}. The display name is the Description of the production's definition, or the
///     class name when the description is empty. The state is the running state that Ens.Director.GetProductionStatus gives for the namespace (running,
///     stopped, suspended, troubled, network_stopped, timeout or unknown), as Failures reads it, and no other field says it. A namespace is readable when the user of the ServiceUser setting of Decide holds Read on the
///     resource of the namespace's default global database ($SYSTEM.Security.CheckUserPermission). An unreadable namespace, and one that
///     cannot be entered, are left out. On the online demo (the public flag onlineDemo) the list holds only the Orders demo production, when
///     it is readable.
///   - Find gives the entries that a name matches: the name is made like a display name (Label: trimmed, white-space runs made one space), a
///     trailing " production" is dropped, and the rest is compared without regard to case with the display name and with the class name. An
///     optional namespace narrows the match. Matches is that rule over any list of entries (the stop resolver uses it on a session's own watches).
///   - Label turns a production's description into its display name: white-space runs become one space and the text is cut to 128 characters
///     (the length of the DisplayName of the command and of the watch's row), so that a long or multi-line description never fails a start.
///   - Admits says whether one namespace and production are an entry, and gives its display name.
///   - OnlineDemo says whether the list is limited to Orders.
///   - Failures reads a watched production's new failures (Story 5.2; AD-15) and its running state (Story 5.6) from the namespace, inside the same one switching method: the
///     production must be the namespace's own (outcome not_current otherwise), and the service user must be able to read the namespace, which is
///     checked before any switch (outcome unreadable, nothing entered). A failure is a message header in Status 8 (Error) from the given time on,
///     whatever its IsError, with the raw text of its error, or an event-log row of Type 2 (Error) or 6 (Alert) with no session; a log row with a
///     session is only the text of its header. Each row of the output array is {"kind" (header, error or alert), "headerId", "sessionId",
///     "superSession", "item", "source", "bodyClass", "at" (IRIS UTC, as stored), "logId", "errorText"}, in time and id order, at most limit.
///     It also gives, from the same switch, the names of the production's items that are disabled as IRIS runs them (disabled, in ID order, each
///     name once: an item's stored Enabled unless a System Default Setting Enabled overrides it, and no name of which another item is enabled) and the
///     time IRIS recorded when the production last stopped (stoppedAt, as stored, "" when none): both only with the outcome read.
///     With the outcome read it also gives, from the same switch, errored (the names of the production's enabled items whose %Status in the host
///     monitor is Error, in name order) and queues (one {"name", "count", "oldestAt"} for each item of the production that has messages in Status 2,
///     Queued: their number and the UTC time, YYYY-MM-DDThh:mm:ssZ, of the oldest; the header stores the target in upper case, so the item is matched without regard to case and named as the production names it). Either is "" (not an array) when it could not be read, so that a
///     caller never takes an unread queue for an empty one; every other outcome gives [] for both.
///   - Vitals reads the instance's vital signs (Story 17.5) and switches no namespace: the uptime, the volume's free share and the size limit of each
///     of OcuTalon's databases and of the databases of the watched namespaces (Database), the free share of the journal's volume, the license use and
///     the count of the severe lines (severity 2 and 3) of messages.log, and of the files IRIS keeps when it switches it, in a window, without
///     IRIS's own two start-up lines (StartNoise; Story 17.13). It reads no privileged API: only counts and percentages leave
///     it, never the text of a log line. Each sign has its own outcome, read or error, so one sign that cannot be read never hides the others.
///   - Evidence reads the evidence of the failures with the given keys (Story 5.4), inside the same switching method and under the same two
///     checks as Failures (readable before any switch, outcome unreadable or not_current). It gives the snapshot as the reader snapshot of
///     Story 0.10 (format ocutalon.readerSnapshot/1): failures (one per header key: the header's fields, its error text chosen as Failures
///     chooses it, and body, the stored datatype properties of its message body, read through the class dictionary), eventLog (the rows of
///     the failures' sessions and of the log keys), items (the named item only, with its settings) and trace (the first failure's session, at
///     most TRACEMAX headers). The settings whose name holds credential, password, passwd, passphrase, secret, token, key, auth, bearer or cookie
///     (CredentialName) are left out after the switch, before Evidence returns, also when the read fails. The texts are raw, line breaks
///     included: the caller redacts them. Given resent 1 (Story 7.3), each failure also gains resentBy, an array of the ids of the headers of its session
///     whose Description names it as resent: the ids that follow "Resent " and precede any ":" (IRIS writes "Resent <id>[,<earlier ids>][: <description>]" on a
///     copy, whoever resends it); without the flag the failures have no such member.
///   - Items reads the production's items for the item fix kinds (Story 23.2) inside the same switching method and under the same two checks: one {"id", "name",
///     "className", "businessType", "enabled"} per item, enabled as IRIS runs it.
///   - Settings reads the setting history marks of a production (Story 36.1): the namespace's production-change counter and the production's start mark, and
///     with full every item's effective settings (its stored settings with the class defaults and the System Default Settings that apply), inside the same switching
///     method and under the same two checks. Items that share a name are one: the first of them that is enabled as IRIS runs it, else the first. A setting that
///     references an Ens.Config.Credentials entry keeps the ID it holds; any other setting whose name CredentialName matches loses its value and is given a
///     salted hash, which only tells a later read that the value changed. It writes nothing.
///   - Good reads, for each failed header given as a reference (Story 7.9), the newest good messages from the same source: at most limit headers of Status 9 (Completed),
///     IsError 0 and Type 1 (Request) whose SourceConfigName, TargetConfigName, MessageBodyClassName and SuperSession all equal the reference's (an empty SuperSession
///     matches only an empty one), highest header id first, no id twice. It reads them inside Current, under the same two checks as Evidence, through the same
///     per-header read, and gives the failures of that snapshot (the shape Evidence gives) as good.
/// The Orders identity is read from OcuTalon.Install.Step.Demo (NAMESPACE and PRODUCTION), never copied. The namespace switch is in one method,
/// Current, which calls no OcuTalon class while it is in the other namespace. A reader runs inside AI Hub's callback, so this class makes no
/// AI Hub call, no Python call and no session call (AD-6).
Class OcuTalon.Watch.Reader
{

/// The longest the reader waits for the production lock of a namespace, in seconds.
Parameter LOCKSECONDS = 1;

/// OcuTalon's own namespace, whose databases Vitals reads.
Parameter HOME = "OCUTALON";

/// A global that the private database holds, whose destination Vitals reads (the sample of Install.Step.PrivateData).
Parameter PRIVATESAMPLE = "^OcuTalonP.Zz";

/// The file of the instance's messages, in the manager directory.
Parameter MESSAGESLOG = "messages.log";

/// The files that IRIS keeps when it switches messages.log, in the manager directory (messages.old_YYYYMMDD, then messages.old_YYYYMMDD_1 and so on).
Parameter SWITCHEDLOGS = "messages.old_*";

/// The longest line of messages.log that Vitals reads whole, in characters. The rest of a longer line is read as the next line, which no
/// timestamp starts.
Parameter LINEMAX = 4000;

/// IRIS's own start-up line at severity 2, the whole text after the severity, as builds 154 and 109 write it at every start (Story 17.13, Task 0).
/// SevereLines does not count a line of exactly this text.
Parameter NOISESHARDING = "[Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM";

/// The start of IRIS's own start-up line at severity 2 that a start in a new container writes (builds 154 and 109; Story 17.13, Task 0), with its
/// closing space. The container id follows it (12 to 64 lower-case hex digits) and nothing else. SevereLines does not count such a line.
Parameter NOISEFAILOVER = "[Utility.Event] System appears to have failed over from node ";

/// The most headers in the trace of an evidence snapshot.
Parameter TRACEMAX = 20;

/// The most event-log rows in an evidence snapshot.
Parameter LOGMAX = 100;

/// The longest value of a message body's property in an evidence snapshot, in characters.
Parameter VALUEMAX = 1000;

/// The parts of a setting's name that make its value one that must never leave the reader, in lower case, comma-separated.
Parameter CREDENTIALPARTS = "credential,password,passwd,passphrase,secret,token,key,auth,bearer,cookie";

/// The trailing word that a name may carry: "the Orders production".
Parameter SUFFIX = " production";

/// The entries of every readable namespace, as a dynamic array of {"namespace", "production", "displayName"}, in namespace order. The
/// ServiceUser setting that cannot be read is an error, never an empty list.
ClassMethod Productions() As %DynamicArray
{
	Set list = []
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	Set onlyOrders = ..OnlineDemo()
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set ordersProduction = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	$$$ThrowOnError(##class(%SYS.Namespace).ListAll(.namespaces))
	Set namespace = ""
	For {
		Set namespace = $Order(namespaces(namespace))
		Quit:namespace=""
		If $Extract(namespace) = "^" Continue
		If onlyOrders && (namespace '= orders) Continue
		If '##class(%Library.EnsembleMgr).IsEnsembleNamespace(namespace) Continue
		If '..Readable(user, namespace) Continue
		Set production = ..Current(namespace, .description, , , , , , , , , , .state)
		If production = "" Continue
		If onlyOrders && (production '= ordersProduction) Continue
		Set label = ..Label(description)
		Do list.%Push({"namespace": (namespace), "production": (production), "displayName": ($Select(label '= "": label, 1: production)), "state": (state)})
	}
	Quit list
}

/// The entries that name matches (see the class description), in the order of Productions. namespace, when it is not empty, keeps only the
/// entries of that namespace, compared without regard to case. A name that is empty after trimming matches nothing.
ClassMethod Find(name As %String, namespace As %String = "") As %DynamicArray
{
	If ..Normalize(name) = "" Quit []
	Quit ..Matches(..Productions(), name, namespace)
}

/// The entries of the list (a dynamic array of {"namespace", "production", "displayName"}) that the name matches, in the list's order: the rule of
/// Find, over any list. It reads nothing.
ClassMethod Matches(entries As %DynamicArray, name As %String, namespace As %String = "") As %DynamicArray
{
	Set matches = []
	Set wanted = ..Normalize(name)
	If wanted = "" Quit matches
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (namespace '= "") && ($ZConvert(entry.namespace, "L") '= $ZConvert($ZStrip(namespace, "<>W"), "L")) Continue
		If (..Normalize(entry.displayName) = wanted) || ($ZConvert(entry.production, "L") = wanted) {
			Do matches.%Push(entry)
		}
	}
	Quit matches
}

/// 1 when namespace and production are an entry of Productions, with its display name in displayName; otherwise 0 and "".
ClassMethod Admits(namespace As %String, production As %String, Output displayName As %String) As %Boolean
{
	Set displayName = ""
	If (namespace = "") || (production = "") Quit 0
	Set iterator = ..Productions().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = namespace) && (entry.production = production) {
			Set displayName = entry.displayName
			Quit
		}
	}
	Quit (displayName '= "")
}

/// 1 when the instance is the online demo, whose list is limited to the Orders demo production.
ClassMethod OnlineDemo() As %Boolean
{
	Quit (+##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 0)
}

/// The display name of a description (pure): white-space runs (line breaks and tabs included) become one space, the ends are trimmed and the
/// text is cut to 128 characters, the length of DisplayName in the StartWatch command and in BackgroundCheck.
ClassMethod Label(description As %String) As %String
{
	Set text = $ZStrip($Translate($Get(description), $Char(9, 10, 13), "   "), "<>W")
	Set text = $Extract($ZStrip(text, "=W"), 1, 128)
	Quit $ZStrip(text, "<>W")
}

/// A name for comparison: made like a display name (Label), in lower case, without a trailing " production".
ClassMethod Normalize(name As %String) As %String [ Private ]
{
	Set text = $ZConvert(..Label($Get(name)), "L")
	Set suffix = ..#SUFFIX
	If ($Length(text) > $Length(suffix)) && ($Extract(text, *-$Length(suffix)+1, *) = suffix) {
		Set text = $ZStrip($Extract(text, 1, *-$Length(suffix)), "<>W")
	}
	Quit text
}

/// 1 when the user holds Read on the resource of the namespace's default global database. Switches no namespace: the resource comes from
/// the namespace table.
ClassMethod Readable(user As %String, namespace As %String) As %Boolean [ Private ]
{
	Kill info
	Do ##class(%SYS.Namespace).GetNSInfo(namespace, .info)
	Set resource = $Get(info("Resource"))
	If resource = "" Set resource = $Get(info("GlobalDB", "Resource"))
	If resource = "" Quit 0
	Quit ''$SYSTEM.Security.CheckUserPermission(user, resource, "R")
}

/// The new failures of the production in the namespace, from the time from (an IRIS UTC stamp) on, at most limit (see the class description), as a
/// dynamic array in rows. The outcome: read (rows holds what was found, possibly nothing), unreadable (the service user cannot read the namespace:
/// nothing was entered and rows is empty) or not_current (the production is not the namespace's own, or a name is empty: nothing was read). A namespace that cannot
/// be read for another reason is an error. state is the production's running state, read in the same switch: running, stopped, suspended, troubled or
/// network_stopped; timeout when Ens.Director.GetProductionStatus could not take the runtime lock in LOCKSECONDS; unknown for any other error or
/// state; and "" with the outcomes unreadable and not_current. disabled is the dynamic array of the names of the production's disabled items and
/// stoppedAt the production's recorded stop time, as stored (see the class description): [] and "" with every outcome but read. errored and queues are
/// read in the same switch with the outcome read (see the class description): [] with every other outcome.
ClassMethod Failures(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String, Output disabled As %DynamicArray, Output stoppedAt As %String, Output errored As %DynamicArray, Output queues As %DynamicArray) As %String
{
	Set rows = []
	Set state = ""
	Set disabled = []
	Set stoppedAt = ""
	Set errored = []
	Set queues = []
	If (namespace = "") || (production = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, from, limit, .rows, .outcome, .fault, , , , .state, , .disabled, .stoppedAt, .errored, .queues)
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The failures of "_production_" in "_namespace_" could not be read: "_fault))
	Quit outcome
}

/// The raw vital signs of the instance (see the class description), as a dynamic object with a member per sign, each with its own outcome (read or
/// error), no rounding, and no namespace switch:
///   - instance: {"outcome", "upSeconds"}, the whole seconds since the instance started ($ZHorolog);
///   - databases: an array of Database entries, one for each distinct directory of OcuTalon's code, data, private and public databases (found
///     through %SYS.Namespace) and of the code and data databases of each namespace in namespaces (a %List). A namespace that does not exist is
///     one entry named as the namespace, with the outcome error, and so is each of its databases that cannot be found;
///   - journal: {"outcome", "directory", "freePercent"}, the free share of the volume of the primary journal directory;
///   - license: {"outcome", "units", "consumed", "usePercent"}; a license of no units is an error;
///   - systemLog: {"outcome", "count"}, the lines of severity 2 or 3 in messages.log and the files IRIS kept when it switched it (in the manager directory) whose time lies in [fromUtc, toUtc]
///     (UTC, YYYY-MM-DDThh:mm:ssZ; an empty end leaves that side open), except IRIS's own two start-up lines at severity 2 (StartNoise), which are never counted.
///     The file's times are local, read in the instance zone (Data.Time.FromLocal).
ClassMethod Vitals(namespaces As %List = "", fromUtc As %String = "", toUtc As %String = "") As %DynamicObject
{
	Set vitals = {"instance": {"outcome": "error", "upSeconds": ""}, "databases": [], "journal": {"outcome": "error", "directory": "", "freePercent": ""}, "license": {"outcome": "error", "units": "", "consumed": "", "usePercent": ""}, "systemLog": {"outcome": "error", "count": ""}}
	Try {
		Set vitals.instance = {"outcome": "read", "upSeconds": ($ZHorolog \ 1)}
	} Catch {
		Set vitals.instance = {"outcome": "error", "upSeconds": ""}
	}
	Try {
		Set vitals.databases = ..Databases($Get(namespaces))
	} Catch {
		Set vitals.databases = [{"name": (..#HOME), "directory": "", "volumeFreePercent": "", "maxBlocks": "", "outcome": "error"}]
	}
	Try {
		Set directory = ##class(%SYS.Journal.System).GetPrimaryDirectory()
		If directory '= "" {
			Set free = ..VolumeFree(directory)
			If free '= "" Set vitals.journal = {"outcome": "read", "directory": (directory), "freePercent": (free)}
		}
	} Catch {
		Set vitals.journal = {"outcome": "error", "directory": "", "freePercent": ""}
	}
	Try {
		Set units = $SYSTEM.License.KeyLicenseUnits()
		Set consumed = $SYSTEM.License.LUConsumed()
		If (units > 0) && (consumed '< 0) Set vitals.license = {"outcome": "read", "units": (+units), "consumed": (+consumed), "usePercent": (consumed * 100 / units)}
	} Catch {
		Set vitals.license = {"outcome": "error", "units": "", "consumed": "", "usePercent": ""}
	}
	Try {
		Set count = ..SevereLines($Get(fromUtc), $Get(toUtc))
		If count '= "" Set vitals.systemLog = {"outcome": "read", "count": (count)}
	} Catch {
		Set vitals.systemLog = {"outcome": "error", "count": ""}
	}
	Quit vitals
}

/// The reading of one database directory, as a dynamic object {"name" (the directory's last folder, in upper case), "directory" (with its closing
/// separator), "volumeFreePercent" (the free share of the directory's volume, unrounded, 0 to 100), "maxBlocks" (the database's maximum size in
/// blocks, 0 when it has none; read with $$GetDatabaseInfo^%SYS.DATABASE, which needs no privilege), "outcome" (read or error)}. A directory
/// that cannot be read, or whose maximum is not a whole number, is the outcome error with "" for both numbers. It switches no namespace and calls no API that needs %Admin_Operate.
ClassMethod Database(directory As %String) As %DynamicObject
{
	Set directory = $Select($Get(directory) = "": "", 1: ##class(%File).NormalizeDirectory(directory))
	Set entry = {"name": (..DatabaseName(directory)), "directory": (directory), "volumeFreePercent": "", "maxBlocks": "", "outcome": "error"}
	Try {
		If directory '= "" {
			Set free = ..VolumeFree(directory)
			Set info = ""
			Set sc = $$GetDatabaseInfo^%SYS.DATABASE(directory, .info)
			Set max = $Piece(info, ",", 6)
			If (free '= "") && sc && (max ? 1.N) {
				Set entry.volumeFreePercent = free
				Set entry.maxBlocks = +max
				Set entry.outcome = "read"
			}
		}
	} Catch {
		Set entry.volumeFreePercent = ""
		Set entry.maxBlocks = ""
		Set entry.outcome = "error"
	}
	Quit entry
}

/// The upper-case name of the last folder of a directory: /opt/irisapp/mgr/ocutalon_data/ is OCUTALON_DATA.
ClassMethod DatabaseName(directory As %String) As %String [ Private ]
{
	Set path = $Translate($Get(directory), "\", "/")
	While $Extract(path, *) = "/" {
		Set path = $Extract(path, 1, *-1)
	}
	Quit $ZConvert($Piece(path, "/", $Length(path, "/")), "U")
}

/// The free share, in percent and unrounded, of the volume that holds the directory, or "" when it cannot be read.
ClassMethod VolumeFree(directory As %String) As %String [ Private ]
{
	Set sc = ##class(%File).GetDirectorySpace(directory, .free, .total, 0)
	If $$$ISERR(sc) || (+total '> 0) Quit ""
	Quit free * 100 / total
}

/// The Database entries of OcuTalon's databases and of the code and data databases of each namespace (a %List), one for each distinct directory.
ClassMethod Databases(namespaces As %List) As %DynamicArray [ Private ]
{
	Set databases = []
	Set home = ..#HOME
	Kill info
	Do ##class(%SYS.Namespace).GetAllNSInfo(home, .info)
	Do ..Add(databases, .seen, $Get(info("RoutineDB", "Directory")), home)
	Do ..Add(databases, .seen, $Get(info("GlobalDB", "Directory")), home)
	Do ..Add(databases, .seen, $Piece(##class(%SYS.Namespace).GetGlobalDest(home, ..#PRIVATESAMPLE), "^", 2), home)
	Do ..Add(databases, .seen, $Piece(##class(%SYS.Namespace).GetGlobalDest(home, "^"_##class(OcuTalon.Data.Public.Settings).#GLOBALNAME), "^", 2), home)
	Set position = 0
	While $ListNext($Get(namespaces), position, namespace) {
		If namespace = home Continue
		Kill info
		If '##class(%SYS.Namespace).Exists(namespace) {
			Do databases.%Push({"name": ($ZConvert(namespace, "U")), "directory": "", "volumeFreePercent": "", "maxBlocks": "", "outcome": "error"})
			Continue
		}
		Do ##class(%SYS.Namespace).GetAllNSInfo(namespace, .info)
		Do ..Add(databases, .seen, $Get(info("RoutineDB", "Directory")), namespace)
		Do ..Add(databases, .seen, $Get(info("GlobalDB", "Directory")), namespace)
	}
	Quit databases
}

/// Appends the reading of the directory to databases, unless seen holds it already; an empty directory is an unreadable entry named as the namespace.
ClassMethod Add(databases As %DynamicArray, ByRef seen, directory As %String, namespace As %String) [ Private ]
{
	If directory = "" {
		Do databases.%Push({"name": ($ZConvert(namespace, "U")), "directory": "", "volumeFreePercent": "", "maxBlocks": "", "outcome": "error"})
		Quit
	}
	Set directory = ##class(%File).NormalizeDirectory(directory)
	If $Data(seen(directory)) Quit
	Set seen(directory) = ""
	Do databases.%Push(..Database(directory))
}

/// The number of lines of severity 2 or 3 in messages.log whose time is in [fromUtc, toUtc], or "" when a file cannot be read. IRIS switches the log
/// when it passes its size limit and keeps the previous file as messages.old_YYYYMMDD, then messages.old_YYYYMMDD_1 and so on, so the count reads the
/// current file, then the switched files newest first, and stops after the first file whose first timed line is before fromUtc (an older file holds nothing newer). A line starts MM/DD/YY-hh:mm:ss:mmm (pid) severity; the time is local. IRIS's own two start-up lines (StartNoise) are not counted, in any file; every
/// other line of severity 2 or 3 is. The text of a line is never kept.
ClassMethod SevereLines(fromUtc As %String, toUtc As %String) As %String [ Private ]
{
	Set directory = $SYSTEM.Util.ManagerDirectory()
	Set path = ##class(%File).NormalizeFilename(directory_..#MESSAGESLOG)
	If '##class(%File).Exists(path) Quit ""
	Kill switched
	Set file = $ZSearch(directory_..#SWITCHEDLOGS)
	While file '= "" {
		Set modified = ##class(%File).GetFileDateModified(file, 1)
		Set switched($Piece(modified, ",") * 86400 + $Piece(modified, ",", 2), file) = ""
		Set file = $ZSearch("")
	}
	Set files = $ListBuild(path)
	Set key = ""
	For {
		Set key = $Order(switched(key), -1)
		Quit:key=""
		Set file = ""
		For {
			Set file = $Order(switched(key, file))
			Quit:file=""
			Set files = files_$ListBuild(file)
		}
	}
	Set count = 0
	Set ok = 1
	Set position = 0
	While ok && $ListNext(files, position, file) {
		If '..SevereLinesIn(file, $Get(fromUtc), $Get(toUtc), .count, .first) {
			Set ok = 0
		} ElseIf ($Get(fromUtc) '= "") && (first '= "") && (fromUtc ] first) {
			Quit
		}
	}
	Quit $Select(ok: count, 1: "")
}

/// Adds to count the lines of severity 2 or 3 of one log file whose time is in [fromUtc, toUtc], and gives in first the UTC time of the file's first timed
/// line ("" when it has none). Returns 0 when the file cannot be read.
ClassMethod SevereLinesIn(path As %String, fromUtc As %String, toUtc As %String, ByRef count As %Integer, Output first As %String) As %Boolean [ Private ]
{
	Set first = ""
	Set stream = ##class(%Stream.FileCharacter).%New()
	If $$$ISERR(stream.LinkToFile(path)) Quit 0
	Set sc = $$$OK
	While 'stream.AtEnd {
		Set line = stream.ReadLine(..#LINEMAX, .sc)
		If $$$ISERR(sc) Quit
		If line '? 2N1"/"2N1"/"2N1"-"2N1":"2N1":"2N1":"3N1" ".E Continue
		Set severity = $Piece(line, " ", 3)
		If (first '= "") && (severity '= 2) && (severity '= 3) Continue
		Set utc = ##class(OcuTalon.Data.Time).FromLocal("20"_$Extract(line, 7, 8)_"-"_$Extract(line, 1, 2)_"-"_$Extract(line, 4, 5)_"T"_$Extract(line, 10, 17))
		If utc = "" Continue
		If first = "" Set first = utc
		If (severity '= 2) && (severity '= 3) Continue
		If (fromUtc '= "") && (fromUtc ] utc) Continue
		If (toUtc '= "") && (utc ] toUtc) Continue
		If ..StartNoise(line) Continue
		Set count = count + 1
	}
	Quit $$$ISOK(sc)
}

/// 1 when the line is one of IRIS's own two start-up lines (Story 17.13): its severity is 2 and the text after the severity is exactly NOISESHARDING, or
/// NOISEFAILOVER followed by 12 to 64 lower-case hex digits (a container id) and nothing else. Any other line, a near miss or the same text at another
/// severity, is 0, so it counts. The line is compared in memory only.
ClassMethod StartNoise(line As %String) As %Boolean [ Private ]
{
	If $Piece(line, " ", 3) '= 2 Quit 0
	Set text = $Piece(line, " ", 4, *)
	If text = ..#NOISESHARDING Quit 1
	Set length = $Length(..#NOISEFAILOVER)
	If $Extract(text, 1, length) '= ..#NOISEFAILOVER Quit 0
	Quit ($Extract(text, length + 1, *) ? 12.64(1N,1"a",1"b",1"c",1"d",1"e",1"f"))
}

/// The evidence of the failures with the keys (comma-separated, h<header id> or l<log id>, as OcuTalon.Watch.Mark.KeyOf gives them) of the
/// production's item in the namespace, as the reader snapshot in snapshot (see the class description; always a dynamic object, with empty lists when
/// nothing was read). The outcome: read, unreadable (the service user cannot read the namespace: nothing was entered) or not_current (the production
/// is not the namespace's own, or a name is empty: nothing was read). A namespace that cannot be read for another reason is an error. resent 1 adds
/// resentBy to each failure (see the class description).
ClassMethod Evidence(namespace As %String, production As %String, item As %String, keys As %String, Output snapshot As %DynamicObject, resent As %Boolean = 0) As %String
{
	Set snapshot = {"format": "ocutalon.readerSnapshot/1", "source": {"namespace": ($Get(namespace)), "production": ($Get(production)), "item": ($Get(item))}, "failures": [], "eventLog": [], "items": [], "trace": []}
	If ($Get(namespace) = "") || ($Get(production) = "") || ($Get(item) = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, "", 0, .rows, .outcome, .fault, item, $Get(keys), .snapshot, , resent)
	Set items = snapshot.items
	For i = 0:1:items.%Size() - 1 {
		Set settings = items.%Get(i).settings
		Kill left
		Set iterator = settings.%GetIterator()
		While iterator.%GetNext(.name) {
			If ..CredentialName(name) Set left(name) = ""
		}
		Set name = ""
		For {
			Set name = $Order(left(name))
			Quit:name=""
			Do settings.%Remove(name)
		}
	}
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The evidence of "_production_" in "_namespace_" could not be read: "_fault))
	Quit outcome
}

/// The newest good messages of the same source as each reference (see the class description), for the production's item in the namespace: references are failed
/// header ids, comma-separated, and good (a dynamic array) holds, for each reference in turn, at most limit headers in the shape of an Evidence failure (the header's
/// fields, status and body), highest header id first, no header twice. The outcome is read (good holds what was found, possibly nothing), unreadable (the service user
/// cannot read the namespace: nothing was entered) or not_current (the production is not the namespace's own, or a name is empty: nothing was read), as for Evidence.
/// A namespace that cannot be read for another reason is an error. It writes nothing.
ClassMethod Good(namespace As %String, production As %String, item As %String, references As %String, limit As %Integer, Output good As %DynamicArray) As %String
{
	Set good = []
	Set snapshot = {"format": "ocutalon.readerSnapshot/1", "source": {"namespace": ($Get(namespace)), "production": ($Get(production)), "item": ($Get(item))}, "failures": [], "eventLog": [], "items": [], "trace": []}
	If ($Get(namespace) = "") || ($Get(production) = "") || ($Get(item) = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Set keys = ""
	For i = 1:1:$Length($Get(references), ",") {
		Set id = $Piece(references, ",", i)
		If id ? 1.N Set keys = keys _ $Select(keys = "": "", 1: ",") _ "g" _ id
	}
	Set limit = +$Get(limit)
	Do ..Current(namespace, .description, production, "", limit, .rows, .outcome, .fault, item, $Select(limit > 0: keys, 1: ""), .snapshot)
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The good messages of "_production_" in "_namespace_" could not be read: "_fault))
	Set good = snapshot.failures
	Quit outcome
}

/// The items of the production in the namespace (see the class description), for the item fix kinds: items (a dynamic array) holds one {"id" (the Ens.Config.Item id,
/// a whole number), "name", "className", "businessType" (service, process, operation or unknown) and "enabled" (1 or 0, as IRIS runs the item: the stored Enabled unless
/// a System Default Setting Enabled overrides it)} per item, in id order. The outcome is read (items holds what was found, possibly nothing), unreadable (the service
/// user cannot read the namespace: nothing was entered) or not_current (the production is not the namespace's own, or a name is empty: nothing was read), as for Failures.
/// A namespace that cannot be read for another reason is an error. It writes nothing and switches namespace in Current only.
ClassMethod Items(namespace As %String, production As %String, Output items As %DynamicArray) As %String
{
	Set items = []
	If ($Get(namespace) = "") || ($Get(production) = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, , 0, .rows, .outcome, .fault, , , , , , , , , , 1, .items)
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The items of "_production_" in "_namespace_" could not be read: "_fault))
	Quit outcome
}

/// The setting history marks of the production in the namespace and, with full, its settings (see the class description), for SettingHistory: marks is
/// {"counter" (the namespace's production-change counter, "" when it has none), "started" (the production's start time and check sum, joined by "|")}, read
/// before the settings; settings is a sorted array of {"item", "target", "setting", "value", "source" (production, default or class), "credential" (1 for a
/// secret value), "hash"}. A setting that references an Ens.Config.Credentials entry keeps its value, the ID, with credential 0. Any other setting whose name
/// CredentialName matches is a secret: its value is "" and credential 1, and hash is the salt.hash of Data.Webhook.HashSecret, kept from salts (a dynamic object
/// of "item|target|setting" to the earlier hash) when it still matches the value, so that a change of the secret is told and nothing else is. The outcome is
/// read (marks, and settings with full, hold what was found), unreadable (the service user cannot read the namespace: nothing was entered) or not_current (the
/// production is not the namespace's own, or a name is empty: nothing was read), as for Failures; marks are empty and settings [] with the others. A namespace that
/// cannot be read for another reason is an error. Items that share a name are one: the settings of the first of them that is enabled as IRIS runs it (the stored
/// Enabled unless a System Default Setting Enabled overrides it), else of the first. It writes nothing and switches namespace in Current only.
ClassMethod Settings(namespace As %String, production As %String, full As %Boolean = 0, salts As %DynamicObject = "", Output marks As %DynamicObject, Output settings As %DynamicArray) As %String
{
	Set marks = {"counter": "", "started": ""}
	Set settings = []
	If ($Get(namespace) = "") || ($Get(production) = "") Quit "not_current"
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	If $$$ISERR(sc) $$$ThrowStatus(sc)
	If '..Readable(user, namespace) Quit "unreadable"
	Do ..Current(namespace, .description, production, , 0, .rows, .outcome, .fault, , , , , , , , , , 0, , 1, +$Get(full), .readMarks, .readList)
	If fault '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, "The settings of "_production_" in "_namespace_" could not be read: "_fault))
	If outcome '= "read" Quit outcome
	Set marks = readMarks
	Set iterator = readList.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do settings.%Push(..SettingEntry(entry, salts))
	}
	Quit outcome
}

/// One entry of Settings' settings from an entry of Current's list ({"item", "target", "setting", "value", "source", "reference"}): a Credentials reference (reference
/// 1, or a setting named Credentials in any case) keeps its value with credential 0 and no hash; any other setting whose name CredentialName matches is a secret, with
/// value "" and credential 1, and its hash is the earlier one in salts (see Settings) while it still matches the value, else a new one; the rest keep their value (pure).
ClassMethod SettingEntry(entry As %DynamicObject, salts As %DynamicObject = "") As %DynamicObject
{
	Set credential = 0
	Set hash = ""
	Set value = entry.value
	If '(entry.reference || ($ZConvert(entry.setting, "L") = "credentials")) && ..CredentialName(entry.setting) {
		Set credential = 1
		If value '= "" {
			Set earlier = $Select($IsObject(salts): salts.%Get(..SaltKey(entry.item, entry.target, entry.setting)), 1: "")
			Set hash = $Select((earlier '= "") && ##class(OcuTalon.Data.Webhook).Matches(earlier, value): earlier, 1: ##class(OcuTalon.Data.Webhook).HashSecret(value))
		}
		Set value = ""
	}
	Quit {"item": (entry.item), "target": (entry.target), "setting": (entry.setting), "value": (value), "source": (entry.source), "credential": (credential), "hash": (hash)}
}

/// The key of a setting in salts (see Settings): the item, the target and the setting's name, joined by "|" (pure).
ClassMethod SaltKey(item As %String, target As %String, setting As %String) As %String
{
	Quit $Get(item)_"|"_$Get(target)_"|"_$Get(setting)
}

/// 1 when the name of a setting is one whose value must never leave the reader: it holds one of CREDENTIALPARTS, in any case (pure).
ClassMethod CredentialName(name As %String) As %Boolean
{
	Set lower = $ZConvert($Get(name), "L")
	Set parts = $ListFromString(..#CREDENTIALPARTS)
	Set position = 0
	While $ListNext(parts, position, part) {
		If lower [ part Return 1
	}
	Quit 0
}

/// The name of the namespace's own current production, and its definition's Description, as written, in description: the running production as
/// Ens.Director.GetProductionStatus gives it, else the namespace's last production (Ens.Director.GetActiveProductionName). "" when the namespace has
/// none, or when it cannot be entered or read (fault holds why). This is the one method that switches namespace, and it calls no OcuTalon class
/// there, this one's methods included (Productions makes the display name, Failures its answers).
/// When production is not empty it also reads that production's failures (Failures): outcome is not_current when production is not the name that
/// is returned, otherwise read, and rows (a dynamic array) holds the failures from the stamp from on, at most limit, in the order of their time
/// and id, headers before log rows of one time. The text of a header's error is the Type 2 row whose MessageId is the header and whose SessionId
/// matches; else the session's Type 2 row of the header's target; else the header's own ErrorStatus text when IsError; else "".
/// When item is not empty (Evidence) it reads, instead of the failures from a time on, the evidence of the failures with the keys (comma-separated
/// h<header id> and l<log id>) into snapshot, by the same rule for the text of a header's error (see Evidence for the shape). The body of a header
/// is read through the class dictionary: the stored datatype properties of its class, at most VALUEMAX characters each.
/// A key g<header id> in keys (Good only, with limit as the most per reference) stands for the newest good messages of the same source as that header: the headers of Status 9,
/// IsError 0 and Type 1 whose SourceConfigName, TargetConfigName, MessageBodyClassName and SuperSession equal the header's, highest id first, each read as a key h<id> is.
/// state is the production's running state from the same GetProductionStatus call (see Failures): "" when the production is not the namespace's own or the
/// read threw. With the outcome read, disabled (a dynamic array) holds the names of the production's items that are disabled as IRIS runs them (the
/// Ens_Config.Item rows of the production, each Enabled overridden by a System Default Setting Enabled when one matches, as Ens.Director decides; a name
/// of which another item is enabled is not disabled), in ID order, each name once, and stoppedAt the stop time that Ens.Director wrote for the production
/// (^Ens.Configuration("csp","Activity",production,"stopped"), IRIS UTC as stored; killed at a start), "" when there is none; with every other outcome,
/// and when the read threw, they are [] and "". resent 1 (Evidence only) adds resentBy to each failure: the ids of the headers of its session whose Description names it as resent.
/// With readSettings 1 and the outcome read, settingMarks is {"counter", "started"} (the namespace's production-change counter and the production's start time and check sum, read first) and, with fullSettings 1, settingList is a sorted array of {"item", "target", "setting", "value", "source", "reference"} for every item (PopulateVirtualSettings and the item's stored settings, "reference" 1 for a Credentials reference). The values are raw: Settings is the one caller, and it hashes and drops the secret ones. Otherwise they are {"counter": "", "started": ""} and [].
ClassMethod Current(namespace As %String, Output description As %String, production As %String = "", from As %String = "", limit As %Integer = 0, Output rows As %DynamicArray, Output outcome As %String, Output fault As %String, item As %String = "", keys As %String = "", Output snapshot As %DynamicObject, Output state As %String, resent As %Boolean = 0, Output disabled As %DynamicArray, Output stoppedAt As %String, Output errored As %DynamicArray, Output queues As %DynamicArray, listItems As %Boolean = 0, Output items As %DynamicArray, readSettings As %Boolean = 0, fullSettings As %Boolean = 0, Output settingMarks As %DynamicObject, Output settingList As %DynamicArray) As %String [ Private ]
{
	Set items = []
	Set settingMarks = {"counter": "", "started": ""}
	Set settingList = []
	Set description = ""
	Set name = ""
	Set rows = []
	Set disabled = []
	Set stoppedAt = ""
	Set errored = []
	Set queues = []
	Set outcome = ""
	Set fault = ""
	Set state = ""
	Set evidence = (item '= "")
	Set lock = ..#LOCKSECONDS
	New $NAMESPACE
	Try {
		Set $NAMESPACE = namespace
		Set sc = ##class(Ens.Director).GetProductionStatus(.name, .code, lock, 1)
		If $$$ISERR(sc) Set name = ""
		Set state = $Select($$$ISERR(sc): $Select($SYSTEM.Status.Equals(sc, $$$EnsErrCanNotAcquireRuntimeLock): "timeout", 1: "unknown"), 1: $Case(+$Get(code), $$$eProductionStateRunning: "running", $$$eProductionStateStopped: "stopped", $$$eProductionStateSuspended: "suspended", $$$eProductionStateTroubled: "troubled", $$$eProductionStateNetworkStopped: "network_stopped", : "unknown"))
		If name = "" Set name = ##class(Ens.Director).GetActiveProductionName()
		If name '= "" {
			Set definition = ##class(Ens.Config.Production).%OpenId(name)
			If $IsObject(definition) Set description = definition.Description
		}
		If production '= "" {
			If (name = "") || (name '= production) {
				Set outcome = "not_current"
				Set state = ""
			} Else {
				Set outcome = "read"
				Set stoppedAt = $Get(^Ens.Configuration("csp", "Activity", name, "stopped"))
				Set stored = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, ClassName, Enabled, ID FROM Ens_Config.Item WHERE Production = ? ORDER BY ID", name)
				If stored.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, stored.%Message))
				Set cfgCount = 0
				While stored.%Next() {
					Set cfgName = stored.%GetData(1)
					Set cfgAll($ZConvert(cfgName, "U")) = cfgName
					Set cfgEnabled = stored.%GetData(3)
					If ##class(Ens.Config.DefaultSettings).%GetSetting(name, cfgName, stored.%GetData(2), "", "Enabled", .cfgSetting) Set cfgEnabled = cfgSetting
					If listItems {
						Set cfgType = $Case(+##class(Ens.Config.Item).%OpenId(stored.%GetData(4)).BusinessType(), $$$eHostTypeService: "service", $$$eHostTypeProcess: "process", $$$eHostTypeOperation: "operation", : "unknown")
						Do items.%Push({"id": (+stored.%GetData(4)), "name": (cfgName), "className": (stored.%GetData(2)), "businessType": (cfgType), "enabled": (''cfgEnabled)})
					}
					If cfgEnabled {
						Set cfgOn(cfgName) = ""
					} Else {
						Set cfgCount = cfgCount + 1
						Set cfgOff(cfgCount) = cfgName
					}
				}
				For cfgI = 1:1:cfgCount {
					Set cfgName = cfgOff(cfgI)
					If $Data(cfgOn(cfgName)) || $Data(cfgGiven(cfgName)) Continue
					Set cfgGiven(cfgName) = ""
					Do disabled.%Push(cfgName)
				}
				Try {
					Set cfgName = ""
					For {
						Set cfgName = $Order(cfgOn(cfgName))
						Quit:cfgName=""
						If $$$GetHostMonitor(cfgName, "%Status") = "Error" Do errored.%Push(cfgName)
					}
					Set queued = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName, COUNT(*), MIN(TimeCreated) FROM Ens.MessageHeader WHERE Status = 2 GROUP BY TargetConfigName")
					If queued.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, queued.%Message))
					While queued.%Next() {
						Set queueItem = $ZConvert(queued.%GetData(1), "U")
						If (queueItem = "") || '$Data(cfgAll(queueItem)) Continue
						Set oldest = $Piece(queued.%GetData(3), ".", 1)
						Do queues.%Push({"name": (cfgAll(queueItem)), "count": (+queued.%GetData(2)), "oldestAt": ($Select(oldest = "": "", 1: $Translate(oldest, " ", "T")_"Z"))})
					}
				} Catch unread {
					Set errored = ""
					Set queues = ""
				}
				Set headerIds = ""
				Set logIds = ""
				If evidence {
					Set referenceIds = ""
					For i = 1:1:$Length(keys, ",") {
						Set key = $Piece(keys, ",", i)
						If key ? 1"h".N {
							Set headerIds = headerIds _ $ListBuild(+$Extract(key, 2, *))
						} ElseIf key ? 1"l".N {
							Set logIds = logIds _ $ListBuild(+$Extract(key, 2, *))
						} ElseIf key ? 1"g".N {
							Set referenceIds = referenceIds _ $ListBuild(+$Extract(key, 2, *))
						}
					}
					If $ListLength(referenceIds) && (limit > 0) {
						Set reference = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(reference.%Prepare("SELECT SourceConfigName, TargetConfigName, MessageBodyClassName, SuperSession FROM Ens.MessageHeader WHERE ID = ?", 1))
						Set newestTagged = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(newestTagged.%Prepare("SELECT TOP ? ID FROM Ens.MessageHeader WHERE Status = 9 AND IsError = 0 AND Type = 1 AND SourceConfigName = ? AND TargetConfigName = ? AND MessageBodyClassName = ? AND SuperSession = ? ORDER BY ID DESC", 1))
						Set newestUntagged = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(newestUntagged.%Prepare("SELECT TOP ? ID FROM Ens.MessageHeader WHERE Status = 9 AND IsError = 0 AND Type = 1 AND SourceConfigName = ? AND TargetConfigName = ? AND MessageBodyClassName = ? AND (SuperSession IS NULL OR SuperSession = '') ORDER BY ID DESC", 1))
						For r = 1:1:$ListLength(referenceIds) {
							Set result = reference.%Execute($List(referenceIds, r))
							If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
							If 'result.%Next() Continue
							Set refSource = result.%GetData(1)
							Set refTarget = result.%GetData(2)
							Set refClass = result.%GetData(3)
							Set refSuper = result.%GetData(4)
							If refSuper = "" {
								Set result = newestUntagged.%Execute(limit, refSource, refTarget, refClass)
							} Else {
								Set result = newestTagged.%Execute(limit, refSource, refTarget, refClass, refSuper)
							}
							If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
							While result.%Next() {
								Set goodId = +result.%GetData(1)
								If $ListFind(headerIds, goodId) Continue
								Set headerIds = headerIds _ $ListBuild(goodId)
							}
						}
					}
				}
				Set passes = $Select(evidence: $ListLength(headerIds), limit > 0: 1, 1: 0)
				If passes {
					Set headers = ##class(%SQL.Statement).%New()
					If evidence {
						$$$ThrowOnError(headers.%Prepare("SELECT ID, SessionId, SuperSession, SourceConfigName, TargetConfigName, MessageBodyClassName, IsError, ErrorStatus, TimeProcessed, MessageBodyId, TimeCreated, Status FROM Ens.MessageHeader WHERE ID = ?", 1))
					} Else {
						$$$ThrowOnError(headers.%Prepare("SELECT TOP ? ID, SessionId, SuperSession, SourceConfigName, TargetConfigName, MessageBodyClassName, IsError, ErrorStatus, TimeProcessed, MessageBodyId, TimeCreated, Status FROM Ens.MessageHeader WHERE Status = 8 AND TimeProcessed >= ? ORDER BY TimeProcessed, ID", 1))
					}
					Set texts = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(texts.%Prepare("SELECT ID, MessageId, ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? AND Type = 2 ORDER BY ID", 1))
					If evidence && resent {
						Set siblings = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(siblings.%Prepare("SELECT ID, Description FROM Ens.MessageHeader WHERE SessionId = ? AND Description %STARTSWITH 'Resent ' ORDER BY ID", 1))
					}
					If limit > 0 {
						Set orphans = ##class(%SQL.Statement).%New()
						$$$ThrowOnError(orphans.%Prepare("SELECT TOP ? ID, Type, ConfigName, Text, TimeLogged FROM Ens_Util.Log WHERE TimeLogged >= ? AND Type IN (2, 6) AND SessionId IS NULL ORDER BY TimeLogged, ID", 1))
					}
					For pass = 1:1:passes {
						If evidence {
							Set result = headers.%Execute($List(headerIds, pass))
						} Else {
							Set result = headers.%Execute(limit, from)
						}
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set id = result.%GetData(1)
							Set sessionId = result.%GetData(2)
							Set target = result.%GetData(5)
							Set text = ""
							Set byItem = ""
							Set exact = 0
							Set logId = ""
							If sessionId '= "" {
								Set logs = texts.%Execute(sessionId)
								If logs.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, logs.%Message))
								While logs.%Next() {
									If logs.%GetData(2) = id {
										Set text = logs.%GetData(4)
										Set logId = logs.%GetData(1)
										Set exact = 1
										Quit
									}
									If (byItem = "") && (logs.%GetData(3) = target) {
										Set byItem = logs.%GetData(4)
										Set byItemId = logs.%GetData(1)
									}
								}
								If 'exact && (byItem '= "") {
									Set text = byItem
									Set logId = byItemId
								}
							}
							If (text = "") && result.%GetData(7) Set text = $SYSTEM.Status.GetErrorText(result.%GetData(8))
							If evidence {
								Set failure = {"headerId": (id), "sessionId": (sessionId), "superSession": (result.%GetData(3)), "timeCreated": ($Translate($Piece(result.%GetData(11), ".", 1), " ", "T")_"Z"), "timeProcessed": ($Translate($Piece(result.%GetData(9), ".", 1), " ", "T")_"Z"), "sourceConfigName": (result.%GetData(4)), "targetConfigName": (target), "bodyClass": (result.%GetData(6)), "bodyId": (result.%GetData(10)), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(result.%GetData(12)))}
								Do failure.%Set("isError", +result.%GetData(7), "boolean")
								Set failure.error = text
								Set body = {}
								Set bodyClass = result.%GetData(6)
								If (bodyClass '= "") && (result.%GetData(10) '= "") && ##class(%Dictionary.CompiledClass).%ExistsId(bodyClass) && $ClassMethod(bodyClass, "%Extends", "%Library.Persistent") {
									Try {
										Set object = $ClassMethod(bodyClass, "%OpenId", result.%GetData(10))
										If $IsObject(object) {
											Set props = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Type FROM %Dictionary.CompiledProperty WHERE parent = ? AND Private = 0 AND Calculated = 0 AND Transient = 0 AND MultiDimensional = 0 AND Relationship = 0 ORDER BY SequenceNumber", bodyClass)
											If props.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, props.%Message))
											While props.%Next() {
												If ##class(%Dictionary.CompiledProperty).%OpenId(bodyClass_"||"_props.%Get("Name")).Collection '= "" Continue
												Set type = ##class(%Dictionary.CompiledClass).%OpenId(props.%Get("Type"))
												If '$IsObject(type) || (type.ClassType '= "datatype") Continue
												Set value = $Property(object, props.%Get("Name"))
												If $Length(value) > ..#VALUEMAX Set value = $Extract(value, 1, ..#VALUEMAX)
												Do body.%Set(props.%Get("Name"), value)
											}
										}
									} Catch {
										Set body = {}
									}
								}
								Set failure.body = body
								If resent {
									Set resentBy = []
									If sessionId '= "" {
										Set copies = siblings.%Execute(sessionId)
										If copies.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, copies.%Message))
										While copies.%Next() {
											Set list = ","_$Translate($Piece($Extract(copies.%GetData(2), 8, *), ":", 1), " ")_","
											If list [ (","_id_",") Do resentBy.%Push(copies.%GetData(1))
										}
									}
									Set failure.resentBy = resentBy
								}
								Do snapshot.failures.%Push(failure)
								If sessionId '= "" Set sessions(sessionId) = ""
								If pass = 1 Set traceSession = sessionId
							} Else {
								Set found(result.%GetData(9), 1, id) = {"kind": "header", "headerId": (id), "sessionId": (sessionId), "superSession": (result.%GetData(3)), "item": (target), "source": (result.%GetData(4)), "bodyClass": (result.%GetData(6)), "at": (result.%GetData(9)), "logId": (logId), "errorText": (text)}
							}
						}
					}
					If 'evidence {
						Set result = orphans.%Execute(limit, from)
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set id = result.%GetData(1)
							Set found(result.%GetData(5), 2, id) = {"kind": ($Select(result.%GetData(2) = 6: "alert", 1: "error")), "headerId": "", "sessionId": "", "superSession": "", "item": (result.%GetData(3)), "source": "", "bodyClass": "", "at": (result.%GetData(5)), "logId": (id), "errorText": (result.%GetData(4))}
						}
						Set at = ""
						For {
							Set at = $Order(found(at))
							Quit:at=""
							Set order = ""
							For {
								Set order = $Order(found(at, order))
								Quit:order=""
								Set id = ""
								For {
									Set id = $Order(found(at, order, id), 1, row)
									Quit:id=""
									If rows.%Size() '< limit Quit
									Do rows.%Push(row)
								}
							}
						}
					}
				}
				If evidence {
					If $IsObject($Get(definition)) {
						For i = 1:1:definition.Items.Count() {
							Set entry = definition.Items.GetAt(i)
							If entry.Name '= item Continue
							Set settings = {}
							For j = 1:1:entry.Settings.Count() {
								Do settings.%Set(entry.Settings.GetAt(j).Name, entry.Settings.GetAt(j).Value)
							}
							Do snapshot.items.%Push({"name": (entry.Name), "className": (entry.ClassName), "enabled": (+entry.Enabled), "poolSize": (+entry.PoolSize), "settings": (settings)})
							Quit
						}
					}
					Set bySession = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(bySession.%Prepare("SELECT ID, TimeLogged, Type, ConfigName, SourceClass, SourceMethod, SessionId, Text FROM Ens_Util.Log WHERE SessionId = ? ORDER BY ID", 1))
					Set byId = ##class(%SQL.Statement).%New()
					$$$ThrowOnError(byId.%Prepare("SELECT ID, TimeLogged, Type, ConfigName, SourceClass, SourceMethod, SessionId, Text FROM Ens_Util.Log WHERE ID = ?", 1))
					Set count = 0
					Set session = ""
					For {
						Set session = $Order(sessions(session))
						Quit:session=""
						Set count = count + 1
						Set argument(count) = $ListBuild("session", session)
					}
					For i = 1:1:$ListLength(logIds) {
						Set count = count + 1
						Set argument(count) = $ListBuild("id", $List(logIds, i))
					}
					For i = 1:1:count {
						If $List(argument(i), 1) = "session" {
							Set result = bySession.%Execute($List(argument(i), 2))
						} Else {
							Set result = byId.%Execute($List(argument(i), 2))
						}
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While (snapshot.eventLog.%Size() < ..#LOGMAX) && result.%Next() {
							If $Data(logged(result.%Get("ID"))) Continue
							Set logged(result.%Get("ID")) = ""
							Do snapshot.eventLog.%Push({"id": (result.%Get("ID")), "timeLogged": ($Translate($Piece(result.%Get("TimeLogged"), ".", 1), " ", "T")_"Z"), "type": (##class(Ens.DataType.LogType).LogicalToDisplay(result.%Get("Type"))), "configName": (result.%Get("ConfigName")), "sourceClass": (result.%Get("SourceClass")), "sourceMethod": (result.%Get("SourceMethod")), "sessionId": (result.%Get("SessionId")), "text": (result.%Get("Text"))})
						}
					}
					If $Get(traceSession) '= "" {
						Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP ? ID, Type, SourceConfigName, TargetConfigName, MessageBodyClassName, Status, TimeCreated, IsError FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", ..#TRACEMAX, traceSession)
						If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, result.%Message))
						While result.%Next() {
							Set entry = {"headerId": (result.%Get("ID")), "type": (##class(Ens.DataType.MessageType).LogicalToDisplay(result.%Get("Type"))), "sourceConfigName": (result.%Get("SourceConfigName")), "targetConfigName": (result.%Get("TargetConfigName")), "bodyClass": (result.%Get("MessageBodyClassName")), "status": (##class(Ens.DataType.MessageStatus).LogicalToDisplay(result.%Get("Status"))), "timeCreated": ($Translate($Piece(result.%Get("TimeCreated"), ".", 1), " ", "T")_"Z")}
							Do entry.%Set("isError", +result.%Get("IsError"), "boolean")
							Do snapshot.trace.%Push(entry)
						}
					}
				}
				If readSettings {
					Set settingMarks = {"counter": ($$$EnsProdModCounterGet), "started": ($Get($$$EnsRuntime("StartTime"))_"|"_$Get($$$EnsRuntime("CheckSum")))}
					If fullSettings && $IsObject($Get(definition)) {
						For stI = 1:1:definition.Items.Count() {
							Set stItem = definition.Items.GetAt(stI)
							Set stEnabled = $Select(##class(Ens.Config.DefaultSettings).%GetSetting(name, stItem.Name, stItem.ClassName, "", "Enabled", .stSetting): stSetting, 1: stItem.Enabled)
							If '$Data(stPick(stItem.Name)) || ('stPick(stItem.Name, "on") && stEnabled) {
								Set stPick(stItem.Name) = stI
								Set stPick(stItem.Name, "on") = ''stEnabled
							}
						}
						For stI = 1:1:definition.Items.Count() {
							Set stItem = definition.Items.GetAt(stI)
							If stPick(stItem.Name) '= stI Continue
							Kill stRow
							Try {
								$$$ThrowOnError(stItem.PopulateVirtualSettings())
								For stJ = 1:1:stItem.VirtualSettings.Count() {
									Set stData = stItem.VirtualSettings.GetAt(stJ)
									Set stRow($List(stData, 1), $List(stData, 2)) = $ListBuild($List(stData, 3), $Case($List(stData, 4), $$$eConfigSettingValueTypeProduction: "production", $$$eConfigSettingValueTypeRegistry: "production", $$$eConfigSettingValueTypeSystem: "default", : "class"), ($Extract($List(stData, 18), 1, 19) = "credentialsSelector"))
								}
							} Catch stSkipped {
								Kill stRow
							}
							For stJ = 1:1:stItem.Settings.Count() {
								Set stStored = stItem.Settings.GetAt(stJ)
								If '$Data(stRow(stStored.Target, stStored.Name)) Set stRow(stStored.Target, stStored.Name) = $ListBuild(stStored.Value, "production", 0)
							}
							Set stTarget = ""
							For {
								Set stTarget = $Order(stRow(stTarget))
								Quit:stTarget=""
								Set stName = ""
								For {
									Set stName = $Order(stRow(stTarget, stName), 1, stCell)
									Quit:stName=""
									Set stAll(stItem.Name, stTarget, stName) = stCell
								}
							}
						}
						Set stItemName = ""
						For {
							Set stItemName = $Order(stAll(stItemName))
							Quit:stItemName=""
							Set stTarget = ""
							For {
								Set stTarget = $Order(stAll(stItemName, stTarget))
								Quit:stTarget=""
								Set stName = ""
								For {
									Set stName = $Order(stAll(stItemName, stTarget, stName), 1, stCell)
									Quit:stName=""
									Do settingList.%Push({"item": (stItemName), "target": (stTarget), "setting": (stName), "value": ($List(stCell, 1)), "source": ($List(stCell, 2)), "reference": (+$List(stCell, 3))})
								}
							}
						}
					}
				}
			}
		}
	} Catch exception {
		Set name = ""
		Set description = ""
		Set rows = []
		Set outcome = ""
		Set state = ""
		Set disabled = []
		Set stoppedAt = ""
		Set errored = []
		Set queues = []
		Set items = []
		Set settingMarks = {"counter": "", "started": ""}
		Set settingList = []
		Set fault = exception.DisplayString()
	}
	Quit name
}

}
