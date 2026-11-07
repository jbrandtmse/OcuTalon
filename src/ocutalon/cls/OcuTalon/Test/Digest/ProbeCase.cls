/// The base of the tests that compose a digest on a shadow instance of OcuTalon.Test.Digest.ProcessProbe (Story 17.7; Test.Digest.AllClear and
/// Test.Digest.EvalCase). The process zone is America/New_York, the window of a Compose ends at 2030-06-03 09:00 there unless a test says otherwise, the rows of
/// the checks come from fixture watches, their runs and OcuTalon.Test.Digest.CoverageProbe (or are fed to the process probe), and the digest.channels row is
/// taken out of the way before each test and put back after it. It is abstract and holds no Test method.
Class OcuTalon.Test.Digest.ProbeCase Extends OcuTalon.Test.Bridge.ZoneCase [ Abstract ]
{

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

Parameter COVERAGE = "OcuTalon.Test.Digest.CoverageProbe";

Parameter ZONE = "America/New_York";

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The digest.channels row before the test (ProcessProbe ForgetChannels).
Property ChannelsWas As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#COVERAGE, "Reset")
	Do $ClassMethod(..#PROBE, "Clean", "")
	Set ..ChannelsWas = $ClassMethod(..#PROBE, "ForgetChannels")
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $ClassMethod(..#PROBE, "Clean", ..Sessions)
	Do $ClassMethod(..#PROBE, "PutChannelsBack", ..ChannelsWas)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", $Piece(..Sessions, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = "", ..Sessions = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#COVERAGE, "Reset")
	Quit sc
}

Method Keep(ref As %String)
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzprobe")
	Do ..Keep(ref)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

Method Utc(local As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(local)
}

Method Host() As OcuTalon.Test.Digest.ProcessProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set host.%SessionId = $Parameter(..#PROBE, "TRACESESSION")
	Quit host
}

/// A Compose for the session whose window ends at the local time and starts minutes earlier (ten by default, so that a fixture watch with a run every minute
/// is not missed).
Method Compose(session As %String, endLocal As %String = "2030-06-03T09:00:00", key As %String = "", minutes As %Integer = 10) As OcuTalon.Digest.Msg.Compose
{
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = "requested"
	Set compose.IdempotencyKey = key
	Set compose.WindowEnd = ..Utc(endLocal)
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowEnd, -60 * minutes)
	Quit compose
}

/// Hands the Compose to the host and returns the status of the handling.
Method Handle(compose As OcuTalon.Digest.Msg.Compose, host As OcuTalon.Test.Digest.ProcessProbe) As %Status
{
	Kill response
	Quit host.OnRequest(compose, .response)
}

/// The Notification n that the probe recorded, as {session, kind, catalogKey, decisionRef, slots}; "" when there is none.
Method Notice(n As %Integer = 1) As %DynamicObject
{
	Set record = $ClassMethod(..#PROBE, "Record", "notice", n)
	If record = "" Quit ""
	Quit {"session": ($List(record, 1)), "kind": ($List(record, 2)), "catalogKey": ($List(record, 3)), "decisionRef": ($List(record, 4)), "slots": ({}.%FromJSON($List(record, 5)))}
}

/// The keys of the parts, comma-separated.
Method Keys(slots As %DynamicObject) As %String
{
	Set keys = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_part.key
	}
	Quit keys
}

/// The part with the key, or "".
Method Part(slots As %DynamicObject, key As %String) As %DynamicObject
{
	Set found = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		If part.key = key {
			Set found = part
			Quit
		}
	}
	Quit found
}

/// The Telegram rendering of one part or line.
Method RenderOne(key As %String, slots As %DynamicObject) As %String
{
	Set rendered = ##class(OcuTalon.Msg.Catalog).Render(key, slots, "telegram", .sc)
	Do $$$AssertStatusOK(sc, key_" renders")
	Quit rendered
}

/// The Telegram rendering of every part and, unless withLines is 0, every line, one on each line; an element that does not render fails the test.
Method Render(slots As %DynamicObject, withLines As %Boolean = 1) As %String
{
	Set text = ""
	Set iterator = slots.parts.%GetIterator()
	While iterator.%GetNext(, .part) {
		Set text = text_$Select(text = "": "", 1: $Char(10))_..RenderOne(part.key, part.slots)
	}
	If 'withLines Quit text
	Set iterator = slots.lines.%GetIterator()
	While iterator.%GetNext(, .line) {
		Set text = text_$Char(10)_..RenderOne(line.key, line.slots)
	}
	Quit text
}

/// The newest Sent row of the session, as an object of its fields; "" when there is none.
Method Sent(session As %String) As %DynamicObject
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 CatalogKey, Slots, AllClear FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", session)
	If 'rs.%Next() Quit ""
	Quit {"CatalogKey": (rs.%Get("CatalogKey")), "Slots": (rs.%Get("Slots")), "AllClear": (rs.%Get("AllClear"))}
}

Method SentRows(session As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// A watched row as the process probe's Feed takes it.
Method Watched(result As %String, entry As %String, finding As %String = "", checkedAt As %String = "2030-06-03T12:00:00Z") As %DynamicObject
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (checkedAt)}
}

/// A fixture production watch of the session, created before the window; its Ref. The entry of its row is "<name> production".
Method Watch(session As %String, production As %String, name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": (name)})
	Do ..Keep(ref)
	Quit ref
}

/// One CheckRun of the check, as it is.
Method Run(ref As %String, session As %String, ranAt As %String, result As %String)
{
	Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding) VALUES (?, ?, ?, ?, '', '')", ref, session, ranAt, result)
	Do $$$AssertTrue(insert.%SQLCODE '< 0, "a run is recorded: "_insert.%Message)
}

/// Ten passed runs of the check a minute apart, the first thirty seconds into the compose's window.
Method Every(ref As %String, session As %String, compose As OcuTalon.Digest.Msg.Compose)
{
	Set first = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowStart, 30)
	For i = 0:1:9 {
		Do ..Run(ref, session, ##class(OcuTalon.Data.Time).AddSeconds(first, 60 * i), "passed")
	}
}

}
