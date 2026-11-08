/// The checks that live:session-data (docker/tests/test-session-data.sh) runs inside the stack after two online-demo visitors added documents and saved memories and
/// one of them signed out through the real route (Story 19.5; AD-3, AD-4, AD-21, AD-25). The class has no state of its own: it skips unless the script has left
/// the SessionRefs and the Session row ids of the visitor that signed out and of the one that stayed, as "<signed out>|<stayed>|<id of the first>|<id of the second>",
/// in ^OcuTalonTest("Docs", "sessions") (the script deletes the node): a Session row is gone after the sign-out, so the first id names its tables. It runs in the CI shard too, where it skips, so the class always compiles and loads.
///   - TestSignedOut: the visitor that signed out has no table, no _Config table, no class, no global, no Document row and no memory (Facts), the whole
///     stack holds only the tables of the visitor that stayed (Facts of every session is Facts of that visitor), a second
///     OcuTalon.Docs.DropSession and OcuTalon.Memory.DropSession for it are OK and change nothing, and a turn for it makes nothing (Docs.TurnTools gives no tool and
///     Facts is as it was);
///   - TestStayed: the visitor that stayed has both tables, their classes, their globals in OCUTALON_PRIVATE and none in OCUTALON_DATA, one ready Document row and one
///     memory, nothing in ^IRIS.KNNIndex, and a search of its table through a bare %AI.ToolMgr finds its own document only.
/// Facts(sessionRef, id) is also the script's own reading of the stack, before any visitor ("" names every session), and Seen(mark, needle) its reading of the
/// mock's log.
Class OcuTalon.Test.Docs.SessionLive Extends %UnitTest.TestCase
{

Parameter STORE = "OcuTalon.Docs.Store";

/// "tables|classes|globals|documents|memories" for the session, as numbers: the SQL tables OcuTalonKB.S<id> and OcuTalonKB.S<id>_Config that exist (0 to 2), the
/// compiled classes of those two tables (0 to 2), the globals of both databases that belong to them (^OcuTalonP.KBS<id>, ^OcuTalonP.KBS<id>Config and the
/// subnodes of either: the names that start with OcuTalonP.KBS<id> and go on with anything but a digit), and the OcuTalon_Data.Document rows whose OwnerRef is the
/// session and the OcuTalon_Data.Memory rows whose SessionRef is. With sessionRef "" it counts every session's tables and classes (every OcuTalonKB.S followed by a
/// digit), their globals (every name that starts with OcuTalonP.KBS and a digit), and every Document and Memory row there is, so that "0|0|0|0|0" is the state of an
/// install before any visitor. With an id, the tables and classes of the Session row with that id are counted whether or not the row still exists, and sessionRef
/// names the Document and Memory rows. Facts changes nothing.
ClassMethod Facts(sessionRef As %String = "", id As %Integer = "") As %String
{
	Set tables = 0, classes = 0, globals = 0
	If id '= "" {
		Set ids = id
	} ElseIf sessionRef '= "" {
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
		Set ids = $Select($IsObject(row) && (row.Ref = sessionRef): row.%Id(), 1: "")
	} Else {
		Set ids = ""
	}
	If (sessionRef '= "") && (ids = "") {
		// A Ref with no Session row (after the sign-out removed it) has no table that the rule can name.
		Set documents = ..Count("OcuTalon_Data.Document", "OwnerRef", sessionRef)
		Quit "0|0|0|" _ documents _ "|" _ ..Count("OcuTalon_Data.Memory", "SessionRef", sessionRef)
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'OcuTalonKB'")
	While rs.%Next() {
		If ..Mine(rs.%Get("TABLE_NAME"), ids, "_Config") Set tables = tables + 1
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'OcuTalonKB.S'")
	While rs.%Next() {
		If ..Mine($Piece(rs.%Get("Name"), ".", 2), ids, "Config") Set classes = classes + 1
	}
	Set home = $Namespace
	New $Namespace
	Set $Namespace = "%SYS"
	For database = "OCUTALON_PRIVATE", "OCUTALON_DATA" {
		Do ##class(Config.Databases).Get(database, .properties)
		Set reference = "^^" _ ##class(%File).NormalizeDirectory(properties("Directory"))
		Set found = $Order(^$|reference|GLOBAL(""))
		While found '= "" {
			If ..MineGlobal(found, ids) Set globals = globals + 1
			Set found = $Order(^$|reference|GLOBAL(found))
		}
	}
	Set $Namespace = home
	Quit tables _ "|" _ classes _ "|" _ globals _ "|" _ ..Count("OcuTalon_Data.Document", "OwnerRef", sessionRef) _ "|" _ ..Count("OcuTalon_Data.Memory", "SessionRef", sessionRef)
}

/// 1 when the name (a table name or the class name without its package) is S<id> or S<id><suffix> for the id, or for any id when ids is "".
ClassMethod Mine(name As %String, ids As %String, suffix As %String) As %Boolean [ Private ]
{
	If $Extract(name) '= "S" Quit 0
	Set rest = $Extract(name, 2, *)
	If ids = "" Quit rest ?1.N.1(1"_Config",1"Config")
	Quit (rest = ids) || (rest = (ids _ suffix))
}

/// 1 when the global name belongs to the session's tables (OcuTalonP.KBS<id> and then anything but a digit), or to any session's when ids is "".
ClassMethod MineGlobal(name As %String, ids As %String) As %Boolean [ Private ]
{
	// The names of ^$GLOBAL carry the caret.
	If $Extract(name) = "^" Set name = $Extract(name, 2, *)
	If $Extract(name, 1, 13) '= "OcuTalonP.KBS" Quit 0
	Set rest = $Extract(name, 14, *)
	Set digits = ""
	For i = 1:1:$Length(rest) {
		If $Extract(rest, i) '? 1N Quit
		Set digits = digits _ $Extract(rest, i)
	}
	If digits = "" Quit 0
	If ids = "" Quit 1
	Quit digits = ids
}

/// The number of rows of the table whose column is the value (every row when the value is empty).
ClassMethod Count(table As %String, column As %String, value As %String) As %Integer [ Private ]
{
	If value = "" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table)
	} Else {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM " _ table _ " WHERE " _ column _ " = ?", value)
	}
	If rs.%SQLCODE < 0 Quit -1
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// What the model was given as tool results in the requests of the mock's log after the mark that carry the needle (the text a turn of the script
/// carries): "<sources>|<memory refs>", each comma-separated and sorted: the sources of the passages that the documents tool returned and the Refs of the
/// memories that search_memories returned. The mark is the Test.Contract.Mock LogMark of the script. A log that cannot be read gives "unreadable".
ClassMethod Seen(mark As %Integer, needle As %String) As %String
{
	If $ClassMethod("OcuTalon.Test.Contract.Mock", "LogSince", mark, .entries) '= 1 Quit "unreadable"
	Set requests = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, needle)
	Set position = 0
	For n = 0:1:requests.%Size() - 1 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(n))
		Set position = 0
		While $ListNext(results, position, text) {
			Try {
				Set value = {}.%FromJSON(text)
			} Catch {
				Continue
			}
			If value.%IsA("%Library.DynamicArray") {
				Set iterator = value.%GetIterator()
				While iterator.%GetNext(, .item) {
					If $IsObject(item) && $IsObject(item.metadata) Set sources(item.metadata.source) = ""
				}
			} ElseIf $IsObject(value.memories) {
				Set iterator = value.memories.%GetIterator()
				While iterator.%GetNext(, .item) {
					If $IsObject(item) Set refs(item.ref) = ""
				}
			}
		}
	}
	Quit ..Joined(.sources) _ "|" _ ..Joined(.refs)
}

/// The subscripts of the array, sorted and comma-separated.
ClassMethod Joined(ByRef array) As %String [ Private ]
{
	Set text = ""
	Set key = ""
	For {
		Set key = $Order(array(key))
		Quit:key=""
		Set text = text _ $Select(text = "": "", 1: ",") _ key
	}
	Quit text
}

/// The SessionRefs and Session row ids that the script named; 0 when it named none (the test then skips).
Method Named(Output signedOut As %String, Output stayed As %String, Output signedOutId As %String, Output stayedId As %String) As %Boolean [ Private ]
{
	Set value = $Get(^OcuTalonTest("Docs", "sessions"))
	If $Length(value, "|") '= 4 {
		Do $$$AssertSkipped("live:session-data has not named two sessions (^OcuTalonTest(""Docs"",""sessions""))")
		Quit 0
	}
	Set signedOut = $Piece(value, "|", 1)
	Set stayed = $Piece(value, "|", 2)
	Set signedOutId = $Piece(value, "|", 3)
	Set stayedId = $Piece(value, "|", 4)
	Quit 1
}

Method TestSignedOut()
{
	If '..Named(.signedOut, .stayed, .signedOutId, .stayedId) Quit
	Do $$$AssertEquals(..Facts(signedOut, signedOutId), "0|0|0|0|0", "the visitor that signed out has no table, class, global, document or memory")
	Do $$$AssertEquals(..Facts(""), ..Facts(stayed, stayedId), "and the stack holds only the tables, classes, globals, documents and memories of the visitor that stayed")
	Do $$$AssertStatusOK(##class(OcuTalon.Docs).DropSession(signedOut), "a second OcuTalon.Docs.DropSession is OK")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory).DropSession(signedOut), "and so is a second OcuTalon.Memory.DropSession")
	Do $$$AssertEquals(..Facts(signedOut, signedOutId), "0|0|0|0|0", "and they change nothing")
	Set before = ..Facts("")
	Set sc = ##class(OcuTalon.Docs.TurnTools).Tools(signedOut, "turn", .tools)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ tools.Count(), "1|0", "a turn of the visitor that signed out gets no tool")
	Do $$$AssertEquals(..Facts(""), before, "and makes no table, class or global of anyone's")
}

Method TestStayed()
{
	If '..Named(.signedOut, .stayed, .signedOutId, .stayedId) Quit
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(stayed)
	Do $$$AssertTrue($IsObject(row), "the visitor that stayed has a Session row")
	If '$IsObject(row) Quit
	Set id = row.%Id()
	Set table = "OcuTalonKB.S" _ id
	Do $$$AssertEquals($Piece(..Facts(stayed), "|", 1, 2), "2|2", "it has both tables and both classes")
	Do $$$AssertTrue($Piece(..Facts(stayed), "|", 3) '< 2, "and its globals: " _ $Piece(..Facts(stayed), "|", 3))
	Do $$$AssertEquals($Piece(..Facts(stayed), "|", 4, 5), "1|1", "one document and one memory")
	Set private = ##class(%File).NormalizeDirectory($Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.MemoryD"), "^", 2))
	For global = "^OcuTalonP.KBS" _ id, "^OcuTalonP.KBS" _ id _ "Config" {
		Set resolved = ##class(%SYS.Namespace).GetGlobalDest($Namespace, global)
		Do $$$AssertEquals(##class(%File).NormalizeDirectory($Piece(resolved, "^", 2)), private, global _ " resolves to the private database")
	}
	Do $$$AssertEquals($Data(^IRIS.KNNIndex), 0, "^IRIS.KNNIndex holds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.TurnTools).DataDatabase("OcuTalonP.KBS"), "", "and OCUTALON_DATA holds no knowledge-base global")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, State, KnowledgeBase FROM OcuTalon_Data.Document WHERE OwnerRef = ?", stayed)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%Get("State") _ "|" _ rs.%Get("KnowledgeBase"), "ready|" _ table, "its document is ready, in its own table")
	Set sc = ##class(OcuTalon.Docs.TurnTools).Tools(stayed, "turn", .tools)
	Do $$$AssertEquals($$$ISOK(sc) _ "|" _ tools.Count(), "1|1", "a turn of the visitor that stayed gets the tool")
	If tools.Count() '= 1 Quit
	Set agent = ##class(%AI.Agent).%New()
	Do tools.GetAt(1).AddToManager(agent.ToolManager)
	Set result = agent.ToolManager.ExecuteTool("documents", {"query": "how do I rotate the certificate?"})
	Set other = 0, own = 0
	Set iterator = result.value.%GetIterator()
	While iterator.%GetNext(, .item) {
		If item.metadata.source = rs.%Get("Ref") Set own = own + 1
		Else  Set other = other + 1
	}
	Do $$$AssertEquals(own > 0, 1, "a search of its table finds its own document")
	Do $$$AssertEquals(other, 0, "and no other source")
}

}
