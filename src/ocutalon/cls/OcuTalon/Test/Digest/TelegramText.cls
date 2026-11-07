/// The golden test of the digest text that TelegramOut sends (Story 17.10; AD-32). It is safe on a slot: no production runs. A shadow instance of
/// OcuTalon.Test.Digest.TelegramOutProbe handles a digest Notification as the framework would, and the probe records the text that TelegramOut gives
/// to Send. The process zone is America/New_York and the onlineDemo key is off, so that every time reads the same on every run. Each expected text is
/// written out here, never read from the catalog, and its pieces are joined with a line feed. The text must be the same before and after the digest
/// rendering moved out of TelegramOut into OcuTalon.Channel.DigestText.
///   - TestFullDigest: greeting, vital signs, the checked part with checks.notEverythingRestPassed, three coverage lines (passed, failed and not checked,
///     with dated times), what needs the user, what was saved for later and the cost, in that order; the message goes as plain text with no markup;
///   - TestNoAfterLines: parts with none of the after-lines keys end with the coverage lines;
///   - TestEmptyLines: an empty lines array leaves out the lines and adds no empty line;
///   - TestEmptyParts: an empty parts array gives the coverage lines alone;
///   - TestUnknownKey: a part with an unknown key is an error and nothing is sent;
///   - TestNoLines: Slots with no lines are the error "the digest's Slots have no parts or no lines" and nothing is sent;
///   - TestOneHelper: neither TelegramOut nor WebChatOut defines DigestText, Pieces, Piece or AFTERLINES (the digest rendering is one helper, not a copy), and
///     the OnNotification of both names OcuTalon.Channel.DigestText.
Class OcuTalon.Test.Digest.TelegramText Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter PROBE = "OcuTalon.Test.Digest.TelegramOutProbe";

Parameter ZONE = "America/New_York";

/// The onlineDemo key before the test.
Property SavedOnline As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $ClassMethod(..#PROBE, "Reset")
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do $ClassMethod(..#PROBE, "Reset")
	Quit sc
}

/// A shadow instance of the probe, handling the digest Notification whose Slots are slots (JSON); the status that OnNotification returns.
Method Handle(slots As %String) As %Status
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set message = ##class(OcuTalon.Msg.Notification).%New()
	Set message.Kind = "digest"
	Set message.CatalogKey = "checks.everythingElsePassed"
	Set message.Slots = slots
	Kill response
	Quit host.OnNotification(message, .response)
}

/// The greeting part, the vital-signs part and the checked part that the digests of the tests start with.
ClassMethod Head() As %String [ Private ]
{
	Quit "{""key"":""digest.greetingMorning"",""slots"":{}},"
		_"{""key"":""digest.healthy"",""slots"":{""count"":3,""itemNoun"":{""one"":""day"",""other"":""days""},""databasesFull"":60,""licenseUse"":20}},"
		_"{""key"":""digest.checked"",""slots"":{""checked"":""the Chat agent and the Watch agent""}},"
}

Method TestFullDigest()
{
	Set slots = "{""parts"":["_..Head()
		_"{""key"":""checks.notEverythingRestPassed"",""slots"":{""whatFailed"":""the Orders service and the Billing service""}},"
		_"{""key"":""digest.needsYouOne"",""slots"":{""what"":""approve the Orders restart""}},"
		_"{""key"":""digest.saved"",""slots"":{""count"":2,""summary"":""Two routine alerts were handled.""}},"
		_"{""key"":""digest.cost"",""slots"":{""cost"":0.042}}],"
		_"""lines"":["
		_"{""key"":""digest.passed"",""slots"":{""entry"":""the Chat agent"",""time"":""2030-06-01T12:00:00Z""}},"
		_"{""key"":""digest.failed"",""slots"":{""entry"":""the Orders service"",""finding"":""the queue is stuck"",""time"":""2030-06-01T12:30:00Z""}},"
		_"{""key"":""digest.notCheckedMissed"",""slots"":{""entry"":""the Billing service"",""from"":""2030-05-31T12:00:00Z"",""to"":""2030-06-01T12:00:00Z""}}],"
		_"""rows"":[]}"
	Set expected = "Good morning."
		_$Char(10)_"Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%."
		_$Char(10)_"I checked the Chat agent and the Watch agent."
		_$Char(10)_"Not everything: the Orders service and the Billing service. Everything else I checked passed."
		_$Char(10)_"Passed: the Chat agent (at Jun 1, 2030 at 08:00)."
		_$Char(10)_"Failed: the Orders service (the queue is stuck, on Jun 1, 2030 at 08:30)."
		_$Char(10)_"Not checked: the Billing service (the check didn't run between May 31, 2030 at 08:00 and Jun 1, 2030 at 08:00)."
		_$Char(10)_"One thing needs you: approve the Orders restart."
		_$Char(10)_"Saved for later (2): Two routine alerts were handled."
		_$Char(10)_"Yesterday's cost: $0.04."
	Do $$$AssertStatusOK(..Handle(slots), "the digest is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 1, "one message is sent")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "TextOf", 1), expected, "the text is the golden text")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "MarkupOf", 1), "", "it has no markup")
}

Method TestNoAfterLines()
{
	Set slots = "{""parts"":["
		_"{""key"":""digest.greetingEvening"",""slots"":{}},"
		_"{""key"":""digest.checkedQuiet"",""slots"":{""checked"":""the Chat agent""}},"
		_"{""key"":""checks.allPassed"",""slots"":{}}],"
		_"""lines"":["
		_"{""key"":""digest.passed"",""slots"":{""entry"":""the Chat agent"",""time"":""2030-06-01T12:00:00Z""}}],"
		_"""rows"":[]}"
	Set expected = "Good evening."
		_$Char(10)_"I checked the Chat agent (all running, no errors, no backlog)."
		_$Char(10)_"Everything I checked passed."
		_$Char(10)_"Passed: the Chat agent (at Jun 1, 2030 at 08:00)."
	Do $$$AssertStatusOK(..Handle(slots), "the digest is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 1, "one message is sent")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "TextOf", 1), expected, "the coverage lines come last")
}

Method TestEmptyLines()
{
	Set slots = "{""parts"":["
		_"{""key"":""digest.greetingAfternoon"",""slots"":{}},"
		_"{""key"":""digest.savedNone"",""slots"":{}},"
		_"{""key"":""digest.cost"",""slots"":{""cost"":0}}],"
		_"""lines"":[],""rows"":[]}"
	Set expected = "Good afternoon."
		_$Char(10)_"Nothing was saved for later."
		_$Char(10)_"Yesterday's cost: $0.00."
	Do $$$AssertStatusOK(..Handle(slots), "the digest is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 1, "one message is sent")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "TextOf", 1), expected, "no lines and no empty line")
}

Method TestEmptyParts()
{
	Set slots = "{""parts"":[],""lines"":["
		_"{""key"":""digest.passed"",""slots"":{""entry"":""the Chat agent"",""time"":""2030-06-01T12:00:00Z""}},"
		_"{""key"":""digest.failed"",""slots"":{""entry"":""the Orders service"",""finding"":""the queue is stuck"",""time"":""2030-06-01T12:30:00Z""}}],"
		_"""rows"":[]}"
	Set expected = "Passed: the Chat agent (at Jun 1, 2030 at 08:00)."
		_$Char(10)_"Failed: the Orders service (the queue is stuck, on Jun 1, 2030 at 08:30)."
	Do $$$AssertStatusOK(..Handle(slots), "the digest is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 1, "one message is sent")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "TextOf", 1), expected, "the lines alone, with no leading line break")
}

Method TestUnknownKey()
{
	Set slots = "{""parts"":["_..Head()
		_"{""key"":""digest.noSuchKey"",""slots"":{}}],""lines"":[],""rows"":[]}"
	Do $$$AssertStatusNotOK(..Handle(slots), "an unknown key is an error")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 0, "and nothing is sent")
}

Method TestNoLines()
{
	Set slots = "{""parts"":[{""key"":""digest.greetingMorning"",""slots"":{}}],""rows"":[]}"
	Set sc = ..Handle(slots)
	Do $$$AssertStatusNotOK(sc, "Slots with no lines are an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "the digest's Slots have no parts or no lines", "and the error says why")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count"), 0, "and nothing is sent")
}


Method TestOneHelper()
{
	For class = "OcuTalon.Channel.Telegram.Out", "OcuTalon.Channel.WebChat.Out" {
		For name = "DigestText", "Pieces", "Piece" {
			Do $$$AssertEquals(##class(%Dictionary.CompiledMethod).%ExistsId(class_"||"_name), 0, class_" defines no "_name)
		}
		Do $$$AssertEquals(##class(%Dictionary.CompiledParameter).%ExistsId(class_"||AFTERLINES"), 0, class_" defines no AFTERLINES")
		Set method = ##class(%Dictionary.CompiledMethod).%OpenId(class_"||OnNotification")
		Do $$$AssertTrue($IsObject(method), class_" has an OnNotification")
		If $IsObject(method) {
			Set code = method.Implementation.Read(32000)
			Do $$$AssertTrue(code [ "OcuTalon.Channel.DigestText", class_" names OcuTalon.Channel.DigestText")
		}
	}
	Do $$$AssertEquals(##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Channel.DigestText||Text"), 1, "the helper has Text")
	Do $$$AssertEquals(##class(%Dictionary.CompiledParameter).%ExistsId("OcuTalon.Channel.DigestText||AFTERLINES"), 1, "and AFTERLINES")
}

}
