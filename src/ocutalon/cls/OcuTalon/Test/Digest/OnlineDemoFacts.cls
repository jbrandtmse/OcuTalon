/// The online-demo digest names no host path, IP address, user name or key (Story 17.11; DW-898, the keep-condition of U-303; AD-18, AD-19, AD-25, AD-28,
/// AD-32). With the online demo on (Data.Public.Settings onlineDemo 1), a visitor can ask for the digest, and it shows the demo instance's own vital
/// signs and the Orders production's coverage row. The class plants made-up values in the instance facts that the digest reads, composes a
/// visitor's digest through the real Digest.Process (Composed and Finish) and the real Checks.Coverage.Build, and renders it with
/// OcuTalon.Channel.DigestText Text(slots, "web"). Only the seams of Test.Digest.ProcessProbe and Test.Digest.CoverageProbe are under test control: the
/// vital signs, the live read, the gaps and the recording of the sends.
///   - the planted values are a host path, an IP address (from the documentation range 203.0.113.0/24), a user name, an sk-ant- key, a Telegram bot
///     token and one made-up key shape for each other alternative of KEYLIKE; the keys are built from fragments at run time, so that no line of
///     this file holds key-like text. They are planted where the online demo
///     really holds them: the session's IrisUser, the watch's AskedBy, the directories of the databases and of the journal, and the error texts, items,
///     sources, queue names and body classes of the live read;
///   - TestFailingDigest (the pin): databases, journal, license and system log failing and the production troubled. The text holds the two failed
///     lines, and neither the text nor the Notification's whole Slots JSON holds a planted value (without regard to case), a match of any alternative of
///     Test.Bridge.Redact KEYLIKE or an IPv4 shape;
///   - TestPassingDigest: healthy readings with the directories still under the planted path, and failures of another visitor's trace that the online
///     demo does not count. The text holds the healthy sentence, the production sentence and the reserved sentence, with the same absences.
/// A failure message names a planted value by its label only; the digest text and the planted values never go into a result or a log. The digest makes
/// no model request (nothing is saved for later). The class needs the process zone and the digest.channels row of ProbeCase, and puts the onlineDemo key
/// back after each test; it creates and removes every row it reads, and it plants key-shaped values in IRIS rows, so it runs on a throwaway stack only.
Class OcuTalon.Test.Digest.OnlineDemoFacts Extends OcuTalon.Test.Digest.ProbeCase
{

Parameter PRODUCTION = "Zz.Leak.Orders";

/// The onlineDemo key before the test.
Property SavedOnline As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit sc
}

/// The planted user name.
ClassMethod User() As %String
{
	Quit "zzcarol"
}

/// The planted IP address, from the documentation range 203.0.113.0/24.
ClassMethod Ip() As %String
{
	Quit "203.0.113.57"
}

/// The planted host path.
ClassMethod Path() As %String
{
	Quit "/home/" _ ..User() _ "/" _ ..Ip() _ "/mgr/"
}

/// The planted sk-ant- key, built from fragments.
ClassMethod AntKey() As %String
{
	Quit "sk-" _ "ant-api03-" _ $Translate($Justify("", 40), " ", "Z")
}

/// The planted Telegram bot token, built from fragments.
ClassMethod BotToken() As %String
{
	Quit "987654321" _ ":" _ "AAH" _ $Translate($Justify("", 32), " ", "z")
}

/// The name that the live read gives to an item, a source, a body class and a queue.
ClassMethod CarrierName() As %String
{
	Quit ..User() _ "@" _ ..Ip()
}

/// The planted key shapes of the other alternatives of KEYLIKE (a GitHub token, a GitHub fine-grained token, a DigitalOcean token, an AWS access key
/// id and a private key header), built from fragments, as a $ListBuild in the order of OtherLabels.
ClassMethod OtherKeys() As %List
{
	Quit $ListBuild("gh" _ "p_" _ $Translate($Justify("", 24), " ", "x"), "github" _ "_pat_" _ $Translate($Justify("", 24), " ", "y"), "dop" _ "_v1_" _ $Translate($Justify("", 24), " ", "b"), "AK" _ "IA" _ $Translate($Justify("", 16), " ", "Q"), "-----" _ "BEGIN " _ "RSA PRIVATE KEY")
}

/// The labels of OtherKeys.
ClassMethod OtherLabels() As %List
{
	Quit $ListBuild("GitHub token shape", "GitHub fine-grained token shape", "DigitalOcean token shape", "AWS access key shape", "private key header")
}

/// One error text that holds all the planted values.
ClassMethod Carrier() As %String
{
	Set text = "refused for " _ ..CarrierName() _ " at " _ ..Path() _ "ocutalon_data/ with " _ ..AntKey() _ " and " _ ..BotToken()
	Set others = ..OtherKeys()
	For i = 1:1:$ListLength(others) Set text = text _ " " _ $List(others, i)
	Quit text
}

/// The vital signs: the databases, the journal and the license as given, the instance up 3 days, every directory under the planted path.
ClassMethod Vitals(dataFree As %Integer, ordersFree As %Integer, journalFree As %Integer, licenseUse As %Integer, severe As %Integer) As %DynamicObject
{
	Quit {"instance": {"outcome": "read", "upSeconds": 259500}, "databases": [{"name": "OCUTALON_DATA", "directory": (..Path() _ "ocutalon_data/"), "volumeFreePercent": (dataFree), "maxBlocks": 0, "outcome": "read"}, {"name": "OCUORDERS_DATA", "directory": (..Path() _ "ocuorders_data/"), "volumeFreePercent": (ordersFree), "maxBlocks": 0, "outcome": "read"}], "journal": {"outcome": "read", "directory": (..Path() _ "journal/"), "freePercent": (journalFree)}, "license": {"outcome": "read", "units": 100, "consumed": (licenseUse), "usePercent": (licenseUse)}, "systemLog": {"outcome": "read", "count": (severe)}}
}

/// Two failures of the trace, every raw string of the live read holding the planted values.
ClassMethod Failures(trace As %String) As %DynamicArray
{
	Set rows = []
	For i = 1:1:2 {
		Do rows.%Push({"kind": "header", "superSession": (trace), "item": (..CarrierName()), "source": (..CarrierName()), "bodyClass": (..CarrierName()), "errorText": (..Carrier())})
	}
	Quit rows
}

/// Composes the digest of a visitor (the session of the planted user, whose Orders watch is asked for by the planted user and has ten passed runs in the
/// window) and gives {text, sc, json}: the text of Text(slots, "web"), its status and the Slots of the one Notification as stored. The failing
/// digest takes the failures of the visitor's own trace; the passing one, those of another visitor's.
Method Digest(failing As %Boolean) As %DynamicObject
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session(..User())
	Do ..Keep(session)
	Set ..Sessions = ..Sessions _ $Select(..Sessions = "": "", 1: ",") _ session
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session(..User())
	Do ..Keep(other)
	Set ..Sessions = ..Sessions _ "," _ other
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen($Select(failing: session, 1: other)).TraceRef
	Set compose = ..Compose(session, "2030-06-03T09:00:00", session _ ":leak")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", ..#PRODUCTION, {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": "Orders", "AskedBy": (..User())})
	Do ..Keep(ref)
	Do ..Every(ref, session, compose)
	If failing {
		Do $ClassMethod(..#COVERAGE, "Feed", ..Vitals(3, 4, 8, 95, 2))
		Do $ClassMethod(..#COVERAGE, "FeedRead", ..#PRODUCTION, {"state": "troubled", "errored": [(..CarrierName())], "disabled": [(..CarrierName())], "queues": [{"name": (..CarrierName()), "count": 150, "oldestAt": (..Ago(900))}], "rows": (..Failures(trace))})
	} Else {
		Do $ClassMethod(..#COVERAGE, "Feed", ..Vitals(40, 40, 50, 20, 0))
		Do $ClassMethod(..#COVERAGE, "FeedRead", ..#PRODUCTION, {"queues": [{"name": (..CarrierName()), "count": 3, "oldestAt": (..Ago(30))}], "rows": (..Failures(trace))})
	}
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(compose, host), "the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "one Notification is sent")
	Set record = $ClassMethod(..#PROBE, "Record", "notice", 1)
	Set json = $Select(record = "": "", 1: $List(record, 5))
	Set text = ##class(OcuTalon.Channel.DigestText).Text(json, "web", .sc)
	Quit {"text": (text), "sc": (sc), "json": (json)}
}

/// The time that many seconds ago, UTC.
ClassMethod Ago(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -seconds)
}

/// Asserts that the live read was consumed and that a digest came out: one live read of the production, the vital signs read, an OK status, a text.
Method Consumed(got As %DynamicObject, label As %String)
{
	Set calls = $ClassMethod(..#COVERAGE, "Calls")
	Do $$$AssertEquals(calls.%Size(), 1, label _ ": one live read")
	Do $$$AssertEquals(calls.%Get(0).production, ..#PRODUCTION, label _ ": of the watched production")
	Do $$$AssertTrue(+$Get(^||CoverageProbe("vitalsCalls")) > 0, label _ ": the vital signs were read")
	Do $$$AssertStatusOK(got.sc, label _ ": the digest renders")
	Do $$$AssertTrue(got.text '= "", label _ ": and the text is not empty")
	Do $$$AssertTrue(got.json '= "", label _ ": and the Slots are not empty")
}

/// Asserts that none of the planted values, no alternative of KEYLIKE and no IPv4 shape is in the text; where names the text ("the text" or "the Slots").
/// Only labels go into the messages.
Method Absent(text As %String, where As %String)
{
	Set lower = $ZConvert(text, "L")
	Set plain = $ZConvert($Translate(text, "\", ""), "L")
	Set labels = $ListBuild("host path", "IP address", "user name", "sk-ant- key shape", "Telegram token shape", "sk-ant- prefix", "Telegram bot id") _ ..OtherLabels()
	Set values = $ListBuild(..Path(), ..Ip(), ..User(), ..AntKey(), ..BotToken(), "sk-" _ "ant-", "987654321" _ ":") _ ..OtherKeys()
	For i = 1:1:$ListLength(values) {
		Set value = $ZConvert($List(values, i), "L")
		Set found = (lower [ value) || (plain [ value)
		Do $$$AssertTrue('found, where _ " has no planted " _ $List(labels, i))
	}
	Set alternatives = $ListFromString(##class(OcuTalon.Test.Bridge.Redact).#KEYLIKE, "|")
	For i = 1:1:$ListLength(alternatives) {
		Set matched = ##class(%Regex.Matcher).%New($List(alternatives, i), text).Locate()
		Do $$$AssertTrue('matched, where _ " has no match of KEYLIKE alternative " _ i)
	}
	Set matched = ##class(%Regex.Matcher).%New("[0-9]{1,3}(\.[0-9]{1,3}){3}", text).Locate()
	Do $$$AssertTrue('matched, where _ " has no IPv4 shape")
}

/// The pin (DW-898): the failing digest names no planted value, in the text or in the Slots.
Method TestFailingDigest()
{
	Set got = ..Digest(1)
	Do ..Consumed(got, "failing")
	Do $$$AssertTrue(got.text [ "Failed: database space (OCUTALON_DATA 3% free, OCUORDERS_DATA 4% free, at", "the text names the databases that are short of space")
	Do $$$AssertTrue(got.text [ "Failed: Orders production (Production troubled, 1 item in error, 1 item disabled, 2 new failures, 150 messages queued, a message waiting 15 minutes, at", "and the production in trouble")
	Do ..Absent(got.text, "the text")
	Do ..Absent(got.json, "the Slots")
}

/// The passing digest names no planted value either; another visitor's failures are not counted on the online demo.
Method TestPassingDigest()
{
	Set got = ..Digest(0)
	Do ..Consumed(got, "passing")
	Do $$$AssertTrue(got.text [ "Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.", "the text holds the healthy sentence")
	Do $$$AssertTrue(got.text [ "I checked the Orders production (all running, no errors, no backlog).", "and the production sentence")
	Do $$$AssertTrue(got.text [ "Everything I checked passed.", "and the reserved sentence")
	Do ..Absent(got.text, "the text")
	Do ..Absent(got.json, "the Slots")
}

}
