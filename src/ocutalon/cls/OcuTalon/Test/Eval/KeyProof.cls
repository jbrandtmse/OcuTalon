/// The scans of the key proof (Story 9.10; AD-19, AD-22, AD-26): where, in the IRIS instance of a throwaway, a value shows up. THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): eval/run.sh --release-candidate --on-mock calls Scan before its teardown, when the key-path rehearsal
/// (the switch --key-path) has put a fake key through eval/compose.release-candidate.yml into the iris container. The helpers read the key only from the
/// environment of the process, never take it from a script, and return counts and places (a database and a global, a store, a namespace and a message
/// id), never the value.
///   - GlobalHits(value, databases, .places, .stats): the number of nodes of the globals of the local databases that hold the value in a subscript or in
///     their data. An empty databases means every local database that is mounted and not read-only; a database that is read-only cannot receive the
///     value, and is named in stats.skipped. It is -1 for an empty value and for any database or global that cannot be read, so that a scan that saw
///     nothing never reads as clean.
///   - TraceHits(value, after, .places, .stats): the number of messages of every Interoperability namespace (Ens.MessageHeader with an ID above after)
///     whose header or body holds the value, each exported as XML (a header and a body are %XML.Adaptor); -1 for an empty value and for any message or
///     body that cannot be opened or exported.
///   - Scan(): the figures of the proof for the value of ANTHROPIC_API_KEY: the global scan, the stores (Test.Agent.KeyScan.Find), the trace and the CI
///     mock's log, each with a positive control (the demo case's name must be found in the globals, a stored placeholder in the stores, the demo case's
///     name in the trace), and Print writes the CHK lines that eval/run.sh reads. A scan that finds nothing and whose control finds nothing fails there.
/// The tests are warm-safe: each writes a fresh control value and removes what it made.
///   - TestGlobalHits: a value is found as data and as a subscript when the scan is scoped to the database that holds the global, a value nobody holds
///     gives 0, an empty value gives -1 and a database that does not exist gives -1, and the database can be named by its name or its directory;
///   - TestTraceHits: a message body and its header that hold a value are found after a mark and not before it, a value nobody holds gives 0, and an
///     empty value gives -1;
///   - TestTraceHitsUnreadableBody: a header whose body cannot be opened gives -1 and is named;
///   - TestLines: the CHK lines that eval/run.sh reads, in their field order, for a scan built by hand;
///   - TestScanRefusesNoKey: with the key variable unset, Scan gives a reason and no figures.
Class OcuTalon.Test.Eval.KeyProof Extends %UnitTest.TestCase
{

/// The characters read at a time from an exported message.
Parameter CHUNK = 32000;

/// The most places that a result names.
Parameter MAXPLACES = 20;

/// The test-only global of the tests.
Parameter TESTGLOBAL = "^OcuTalonTest";

/// The nodes of ^OcuTalonTest("KeyProof") hold a control value as data and as a subscript, and are found only when the scan covers the database that
/// holds the global.
Method TestGlobalHits()
{
	Set value = "keyproof-control-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Kill ^OcuTalonTest("KeyProof")
	Try {
		Set ^OcuTalonTest("KeyProof", "data") = "before "_value_" after"
		Set ^OcuTalonTest("KeyProof", "sub-"_value) = ""
		Set directory = $Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, ..#TESTGLOBAL), "^", 2)
		Do $$$AssertTrue(directory '= "", "the database of the test global is found")
		Set hits = ..GlobalHits(value, directory, .places, .stats)
		Do $$$AssertEquals(hits, 2, "the value is found as data and as a subscript")
		Do $$$AssertTrue(places.%Size() = 1, "in one global")
		Do $$$AssertTrue(places.%Get(0) [ ":^OcuTalonTest", "which is named by its database: "_places.%Get(0))
		Do $$$AssertTrue(places.%Get(0) '[ value, "and the place never holds the value")
		Do $$$AssertEquals(stats.databases_"|"_stats.unreadable.%Size(), "1|0", "one database was scanned and every global could be read")
		Do $$$AssertTrue(stats.globals > 0 && (stats.nodes > 0), "with its globals and nodes counted")
		Set listStats = {"skipped": [], "unreadable": []}
		Do ..Databases(directory, .list, .listStats)
		Do $$$AssertEquals(list.%Size(), 1, "the database is listed by its directory")
		Do $$$AssertEquals(..GlobalHits(value, list.%Get(0).name), 2, "and is found by its name as well")
		Do $$$AssertEquals(..GlobalHits(value_"-nobody", directory), 0, "a value nobody holds gives 0")
		Do $$$AssertEquals(..GlobalHits("", directory), -1, "an empty value gives -1")
		Do $$$AssertEquals(..GlobalHits(value, "zz-no-such-database"), -1, "a database that does not exist gives -1")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the global scan runs without an exception")
	}
	Kill ^OcuTalonTest("KeyProof")
}

/// An IncidentCase body that holds a control value and a header that points at it are found after a mark and not before it.
Method TestTraceHits()
{
	Set value = "keyproof-control-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set bodyId = "", headerId = ""
	Try {
		Set mark = ..HeaderMark()
		Set body = ##class(OcuTalon.Eval.Msg.IncidentCase).%New()
		Set body.IncidentRef = "zzkeyproof"
		Set body.SourceItemId = "zz-keyproof"
		Set body.Snapshot = "{""note"":"""_value_"""}"
		Do $$$AssertStatusOK(body.%Save(), "the body is saved")
		Set bodyId = body.%Id()
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.MessageBodyClassName = $ClassName(body)
		Set header.MessageBodyId = bodyId
		Set header.SourceConfigName = "ZzKeyProof"
		Set header.TargetConfigName = "ZzKeyProof"
		Set header.Type = 1
		Do $$$AssertStatusOK(header.%Save(), "the header is saved")
		Set headerId = header.%Id()
		Set hits = ..TraceHits(value, mark, .places, .stats)
		Do $$$AssertEquals(hits, 1, "the value is found in the body of one message")
		Do $$$AssertEquals(places.%Get(0), $Namespace_":"_headerId, "which is named by its namespace and header id")
		Do $$$AssertTrue(places.%Get(0) '[ value, "and the place never holds the value")
		Do $$$AssertTrue(stats.namespaces > 0 && (stats.messages > 0) && (stats.unreadable.%Size() = 0), "the namespaces and messages are counted and none was unreadable")
		Do $$$AssertTrue(..ListHas(stats.bodyClasses, "OcuTalon.Eval.Msg.IncidentCase"), "the body class is named")
		Do $$$AssertEquals(..TraceHits(value, headerId, .after), 0, "a message at or before the mark is not scanned")
		Do $$$AssertEquals(..TraceHits(value_"-nobody", mark), 0, "a value nobody holds gives 0")
		Do $$$AssertEquals(..TraceHits("", mark), -1, "an empty value gives -1")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the trace scan runs without an exception")
	}
	If headerId '= "" Do ##class(Ens.MessageHeader).%DeleteId(headerId)
	If bodyId '= "" Do ##class(OcuTalon.Eval.Msg.IncidentCase).%DeleteId(bodyId)
}

/// A header whose body cannot be opened makes the trace scan unreadable (-1) and is named by its namespace and header id.
Method TestTraceHitsUnreadableBody()
{
	Set headerId = ""
	Try {
		Set mark = ..HeaderMark()
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.MessageBodyClassName = "OcuTalon.Eval.Msg.IncidentCase"
		Set header.MessageBodyId = "zz-no-such-body"
		Set header.SourceConfigName = "ZzKeyProof"
		Set header.TargetConfigName = "ZzKeyProof"
		Set header.Type = 1
		Do $$$AssertStatusOK(header.%Save(), "the header is saved")
		Set headerId = header.%Id()
		Set hits = ..TraceHits("keyproof-control-nobody", mark, .places, .stats)
		Do $$$AssertEquals(hits, -1, "a body that cannot be opened gives -1")
		Do $$$AssertTrue(..ListHas(stats.unreadable, $Namespace_":"_headerId), "and its header is named")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the trace scan runs without an exception")
	}
	If headerId '= "" Do ##class(Ens.MessageHeader).%DeleteId(headerId)
}

/// Lines gives the CHK lines that eval/run.sh reads, in its field order, for a scan built by hand, and Print writes them.
Method TestLines()
{
	Set scan = {"keyLength": 66, "globals": {"hits": 0, "places": [], "stats": {"databases": 16, "skipped": ["IRISLIB (read-only)", "ENSLIB (read-only)"], "globals": 800, "nodes": 4000000, "seconds": 3.2, "unreadable": []}, "control": 5}, "stores": {"places": ["entry x"], "control": 3}, "trace": {"hits": 1, "places": ["OCUTALON:42"], "stats": {"namespaces": 6, "messages": 1287, "bodyClasses": ["A.B", "C.D"], "unreadable": []}, "control": 66}, "mock": {"requests": 219, "offLength": 0}}
	Set lines = ..Lines(scan)
	Do $$$AssertEquals($ListLength(lines), 5, "five lines")
	Do $$$AssertEquals($List(lines, 1), "CHK|keylength|66", "the key length")
	Do $$$AssertEquals($List(lines, 2), "CHK|globals|0|5|16|IRISLIB (read-only);ENSLIB (read-only)|800|4000000|3.2||", "the globals line: hits, control, databases, skipped, globals, nodes, seconds, places, unreadable")
	Do $$$AssertEquals($List(lines, 3), "CHK|stores|1|3|entry x", "the stores line: places, control, places")
	Do $$$AssertEquals($List(lines, 4), "CHK|trace|1|66|6|1287|A.B;C.D|OCUTALON:42|", "the trace line: hits, control, namespaces, messages, body classes, places, unreadable")
	Do $$$AssertEquals($List(lines, 5), "CHK|mock|219|0", "the mock line: requests, requests with another key length")
	Do $$$AssertEquals($List(..Lines({"reason": "no key | here"}), 1), "CHK|noscan|no key / here", "a refusal is one line without a pipe")
}

/// With the key variable unset, Scan refuses and scans nothing.
Method TestScanRefusesNoKey()
{
	Set name = ##class(OcuTalon.Test.Agent.KeyScan).#KEYVARIABLE
	Set had = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv(name)
	Set previous = $SYSTEM.Util.GetEnviron(name)
	Try {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(name)
		Set scan = ..Scan()
		Do $$$AssertTrue(scan.%Get("reason") '= "", "Scan gives a reason")
		Do $$$AssertEquals(scan.%Size(), 1, "and no figure")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "Scan runs without an exception")
	}
	If had {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(name, previous)
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.KeyScan).HasEnv(name), had, "the key variable is as it was found")
}

/// --- the scans ---
/// The number of nodes of the local databases that hold the value in a subscript or in their data (see the class description). places lists up to
/// MAXPLACES entries <database>:^<global>; stats is {databases, skipped[], globals, nodes, seconds, unreadable[]}.
ClassMethod GlobalHits(value As %String, databases As %String = "", Output places As %DynamicArray, Output stats As %DynamicObject) As %Integer
{
	Quit ..Walk(value, "", databases, .places, .stats, .control)
}

/// The number of messages whose header or body holds the value (see the class description). places lists up to MAXPLACES entries <namespace>:<header
/// id>; stats is {namespaces, messages, bodyClasses[], unreadable[]}.
ClassMethod TraceHits(value As %String, after As %Integer = 0, Output places As %DynamicArray, Output stats As %DynamicObject) As %Integer
{
	Quit ..Trace(value, "", after, .places, .stats, .control)
}

/// The figures of the proof for the value of ANTHROPIC_API_KEY, or {"reason": ...} when the variable is empty and nothing was scanned:
///   {keyLength, globals{hits, places, stats, control}, stores{places, control}, trace{hits, places, stats, control}, mock{requests, offLength}}.
/// The controls count what the scans must find: the demo case's name in the globals and in the trace, and the Provider step's placeholder in the stores
/// (the entries of the runners). mock.requests is the number of /v1/ requests in the CI mock's log (-1 when the log cannot be read) and offLength the
/// number among them whose key length is not the key's.
ClassMethod Scan() As %DynamicObject
{
	Set key = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Agent.KeyScan).#KEYVARIABLE)
	If key = "" Quit {"reason": "the key variable is empty in the environment of this process: nothing was scanned"}
	Set demo = ##class(OcuTalon.Eval.Report).#DEMOCASE
	Set scan = {"keyLength": ($Length(key))}

	Set hits = ..Walk(key, demo, "", .places, .stats, .control)
	Set scan.globals = {"hits": (hits), "places": (places), "stats": (stats), "control": (control)}

	Set stores = ##class(OcuTalon.Test.Agent.KeyScan).Find(key)
	Set storePlaces = []
	Set position = 0
	While $ListNext(stores, position, store) {
		Do storePlaces.%Push(store)
	}
	Set controlStores = ##class(OcuTalon.Test.Agent.KeyScan).Find(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER)
	Set entries = 0
	Set position = 0
	While $ListNext(controlStores, position, store) {
		If $Extract(store, 1, 6) = "entry " Set entries = entries + 1
	}
	Set scan.stores = {"places": (storePlaces), "control": (entries)}

	Set hits = ..Trace(key, demo, 0, .places, .stats, .control)
	Set scan.trace = {"hits": (hits), "places": (places), "stats": (stats), "control": (control)}

	Set requests = 0, off = 0
	If $SYSTEM.Status.IsError(##class(OcuTalon.Test.Contract.Mock).LogSince(0, .entries)) {
		Set requests = -1
	} Else {
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If $Extract(entry.%Get("path"), 1, 4) '= "/v1/" Continue
			Set requests = requests + 1
			If entry.%Get("keyLength") '= $Length(key) Set off = off + 1
		}
	}
	Set scan.mock = {"requests": (requests), "offLength": (off)}
	Quit scan
}

/// Writes the CHK lines of a Scan result, for eval/run.sh. Every figure is a count, a name or a place; no line holds the value.
///   CHK|keylength|<length>   or   CHK|noscan|<reason>
///   CHK|globals|<hits>|<control>|<databases>|<skipped>|<globals>|<nodes>|<seconds>|<places>|<unreadable>
///   CHK|stores|<number of places>|<control>|<places>
///   CHK|trace|<hits>|<control>|<namespaces>|<messages>|<body classes>|<places>|<unreadable>
///   CHK|mock|<requests>|<requests with another key length>
/// A list in a line is separated by semicolons.
ClassMethod Print(scan As %DynamicObject)
{
	Set lines = ..Lines(scan)
	For i = 1:1:$ListLength(lines) {
		Write !, $List(lines, i)
	}
}

/// The CHK lines of Print, as a list.
ClassMethod Lines(scan As %DynamicObject) As %List
{
	If scan.%Get("reason") '= "" Quit $ListBuild("CHK|noscan|" _ ..Plain(scan.reason))
	Set globals = scan.globals, stores = scan.stores, trace = scan.trace
	Quit $ListBuild("CHK|keylength|" _ scan.keyLength,
		"CHK|globals|" _ globals.hits _ "|" _ globals.control _ "|" _ globals.stats.databases _ "|" _ ..Join(globals.stats.skipped) _ "|" _ globals.stats.globals _ "|" _ globals.stats.nodes _ "|" _ globals.stats.seconds _ "|" _ ..Join(globals.places) _ "|" _ ..Join(globals.stats.unreadable),
		"CHK|stores|" _ stores.places.%Size() _ "|" _ stores.control _ "|" _ ..Join(stores.places),
		"CHK|trace|" _ trace.hits _ "|" _ trace.control _ "|" _ trace.stats.namespaces _ "|" _ trace.stats.messages _ "|" _ ..Join(trace.stats.bodyClasses) _ "|" _ ..Join(trace.places) _ "|" _ ..Join(trace.stats.unreadable),
		"CHK|mock|" _ scan.mock.requests _ "|" _ scan.mock.offLength)
}

/// The walk of the globals: value and control (the control, when not empty, is counted apart in controlHits and decides nothing).
ClassMethod Walk(value As %String, control As %String, databases As %String, Output places As %DynamicArray, Output stats As %DynamicObject, Output controlHits As %Integer) As %Integer [ Private ]
{
	Set places = [], controlHits = 0
	Set stats = {"databases": 0, "skipped": [], "globals": 0, "nodes": 0, "seconds": 0, "unreadable": []}
	If value = "" Quit -1
	Set begun = $ZHorolog, hits = 0
	Do ..Databases(databases, .list, .stats)
	For i = 0:1:list.%Size() - 1 {
		Set database = list.%Get(i)
		Set stats.databases = stats.databases + 1
		Set rows = ##class(%ResultSet).%New("%SYS.GlobalQuery:DirectoryList")
		If $SYSTEM.Status.IsError(rows.Execute(database.directory, "", "*", 1, 0, 1)) {
			Do stats.unreadable.%Push(database.name_" (the list of globals)")
			Continue
		}
		While rows.Next() {
			Set name = rows.Get("Name")
			Set stats.globals = stats.globals + 1
			Set nodes = 0, found = 0, controlFound = 0, readable = 1
			Try {
				Set reference = "^|""^^"_database.directory_"""|"_name
				Set data = ""
				If $Data(@reference, data) # 2 {
					Set nodes = 1
					If data [ value Set found = found + 1
					If (control '= "") && (data [ control) Set controlFound = controlFound + 1
				}
				For {
					Set reference = $Query(@reference, 1, data)
					Quit:reference=""
					Set nodes = nodes + 1
					If (reference [ value) || (data [ value) Set found = found + 1
					If (control '= "") && ((reference [ control) || (data [ control)) Set controlFound = controlFound + 1
				}
			} Catch exception {
				Set readable = 0
			}
			Set stats.nodes = stats.nodes + nodes
			Set controlHits = controlHits + controlFound
			If 'readable {
				Do stats.unreadable.%Push(database.name_":^"_name)
			} ElseIf found {
				Set hits = hits + found
				If places.%Size() < ..#MAXPLACES Do places.%Push(database.name_":^"_name)
			}
		}
	}
	Set stats.seconds = $Number($ZHorolog - begun, 2)
	If stats.unreadable.%Size() Quit -1
	Quit hits
}

/// The local databases to scan, as {name, directory} in list, and in stats the databases that were skipped as read-only or not mounted (stats.skipped) and
/// the ones that could not be listed or opened (stats.unreadable). selection is a comma-separated list of names or directories; empty means all. A
/// selected database that does not exist is unreadable.
ClassMethod Databases(selection As %String, Output list As %DynamicArray, ByRef stats As %DynamicObject) [ Private ]
{
	Set list = []
	New $Namespace
	Set $Namespace = "%SYS"
	Set rows = ##class(%ResultSet).%New("Config.Databases:List")
	If $SYSTEM.Status.IsError(rows.Execute("*", "", 1)) {
		Do stats.unreadable.%Push("the list of databases")
		Quit
	}
	Kill wanted
	Set count = 0
	For i = 1:1:$Length(selection, ",") {
		Set item = $ZStrip($Piece(selection, ",", i), "<>W")
		If item = "" Continue
		Set count = count + 1
		Set wanted(count) = $ZConvert(item, "U"), wanted(count, "dir") = $Select((item [ "/") || (item [ $Char(92)): $ZConvert(##class(%File).NormalizeDirectory(item), "U"), 1: ""), wanted(count, "found") = 0
	}
	While rows.Next() {
		Set name = rows.Get("Name")
		Set directory = ##class(%File).NormalizeDirectory(rows.Get("Directory"))
		If count {
			Set selected = 0
			For n = 1:1:count {
				If (wanted(n) = $ZConvert(name, "U")) || ((wanted(n, "dir") '= "") && (wanted(n, "dir") = $ZConvert(directory, "U"))) Set wanted(n, "found") = 1, selected = 1
			}
			If 'selected Continue
		}
		Set database = ##class(SYS.Database).%OpenId(directory)
		If '$IsObject(database) {
			Do stats.unreadable.%Push(name_" (not opened)")
		} ElseIf 'database.Mounted {
			Do stats.skipped.%Push(name_" (not mounted)")
		} ElseIf database.ReadOnly || database.ReadOnlyMounted {
			Do stats.skipped.%Push(name_" (read-only)")
		} Else {
			Do list.%Push({"name": (name), "directory": (directory)})
		}
	}
	For n = 1:1:count {
		If 'wanted(n, "found") Do stats.unreadable.%Push("a selected database that does not exist")
	}
}

/// The walk of the messages: value and control as in Walk. It exports each header and each body of the Interoperability namespaces, with the one
/// implementation in this method so that it needs nothing of this class in the namespace that it visits.
ClassMethod Trace(value As %String, control As %String, after As %Integer, Output places As %DynamicArray, Output stats As %DynamicObject, Output controlHits As %Integer) As %Integer [ Private ]
{
	Set places = [], controlHits = 0
	Set stats = {"namespaces": 0, "messages": 0, "bodyClasses": [], "unreadable": []}
	If value = "" Quit -1
	Set hits = 0, classes = "", chunkSize = ..#CHUNK, maxPlaces = ..#MAXPLACES
	New $Namespace
	Do ##class(%SYS.Namespace).ListAll(.all)
	Set namespace = ""
	For {
		Set namespace = $Order(all(namespace))
		Quit:namespace=""
		If ($Extract(namespace) = "^") || '##class(%Library.EnsembleMgr).IsEnsembleNamespace(namespace) Continue
		Set stats.namespaces = stats.namespaces + 1
		Try {
			Set $Namespace = namespace
			Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? ORDER BY ID", +after)
			If rows.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rows.%SQLCODE, rows.%Message)
			While rows.%Next() {
				Set id = rows.%GetData(1), class = rows.%GetData(2), bodyId = rows.%GetData(3)
				Set stats.messages = stats.messages + 1
				If class '= "" Set classes(class) = ""
				Set found = 0, controlFound = 0, readable = 1
				Kill one, two
				Try {
					Set header = ##class(Ens.MessageHeader).%OpenId(id, , .sc)
					If '$IsObject(header) Throw ##class(%Exception.StatusException).CreateFromStatus($Select($SYSTEM.Status.IsError(sc): sc, 1: $SYSTEM.Status.Error(5001, "the header could not be opened")))
					Set one = ##class(%Stream.TmpCharacter).%New()
					Set sc = header.XMLExportToStream(.one)
					If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
					Set parts = 1
					If bodyId '= "" {
						Set body = $ClassMethod(class, "%OpenId", bodyId, , .sc)
						If '$IsObject(body) Throw ##class(%Exception.StatusException).CreateFromStatus($Select($SYSTEM.Status.IsError(sc): sc, 1: $SYSTEM.Status.Error(5001, "the body could not be opened")))
						Set two = ##class(%Stream.TmpCharacter).%New()
						Set sc = body.XMLExportToStream(.two)
						If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
						Set parts = 2
					}
					For part = 1:1:parts {
						For which = 1:1:2 {
							Set needle = $Select(which = 1: value, 1: control)
							If needle = "" Continue
							Set stream = $Select(part = 1: one, 1: two)
							Do stream.Rewind()
							Set tail = "", keep = $Length(needle) - 1, hit = 0
							While 'stream.AtEnd {
								Set size = chunkSize
								Set chunk = tail_stream.Read(.size)
								If chunk [ needle {
									Set hit = 1
									Quit
								}
								Set tail = $Select(keep > 0: $Extract(chunk, $Select($Length(chunk) > keep: $Length(chunk) - keep + 1, 1: 1), *), 1: "")
							}
							If hit {
								If which = 1 {
									Set found = 1
								} Else {
									Set controlFound = 1
								}
							}
						}
					}
				} Catch exception {
					Set readable = 0
				}
				Kill one, two
				Set controlHits = controlHits + controlFound
				If 'readable {
					Do stats.unreadable.%Push(namespace_":"_id)
				} ElseIf found {
					Set hits = hits + 1
					If places.%Size() < maxPlaces Do places.%Push(namespace_":"_id)
				}
			}
		} Catch exception {
			Do stats.unreadable.%Push(namespace_" ("_$Extract($SYSTEM.Status.GetErrorText(exception.AsStatus()), 1, 120)_")")
		}
	}
	Set class = ""
	For {
		Set class = $Order(classes(class))
		Quit:class=""
		Do stats.bodyClasses.%Push(class)
	}
	If stats.unreadable.%Size() Quit -1
	Quit hits
}

/// --- helpers ---
/// The highest ID of the message headers of this namespace: the mark that TraceHits reads from.
ClassMethod HeaderMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// 1 when the dynamic array of strings holds the string.
ClassMethod ListHas(list As %DynamicArray, text As %String) As %Boolean [ Private ]
{
	Set found = 0
	For i = 0:1:list.%Size() - 1 {
		If list.%Get(i) = text Set found = 1
	}
	Quit found
}

/// The strings of a dynamic array joined by semicolons, on one line without a pipe.
ClassMethod Join(list As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:list.%Size() - 1 {
		Set text = text_$Select(i: ";", 1: "")_..Plain(list.%Get(i))
	}
	Quit text
}

/// A text on one line without a pipe.
ClassMethod Plain(text As %String) As %String [ Private ]
{
	Quit $Translate(text, "|"_$Char(13, 10), "/  ")
}

}
