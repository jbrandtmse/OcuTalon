/// Tests of ReplyText (Story 27.2; AD-14, AD-28, AD-32): the text of a reply for a plain-text channel is the text that Telegram sends for the same reply. They need no production
/// and no mock.
///   - TestSameAsTelegram: the cases of Test.Channel.TelegramOut TestCheckSentence (the failed row first with its time, a dated time, the all-clear, only a passed row, an unknown key,
///     the online demo's " ET", an entry alone, a time alone and a row with no entry, rows that are not rows, notEverything, everythingElsePassed) give the same sentences,
///     for the channel slack, whose catalog text is Telegram's;
///   - TestLearnedLines: the lines of Memory.Learned follow the reply, and its check sentence when there is one, as TelegramOut TestLearnedLines gives them;
///   - TestFallbackKey: a reply with no text and a catalog key is the rendering of the key for the channel; a key that cannot be rendered is an error status and the text "";
///   - TestWarning: a check key that gives no sentence leaves the sentence out and returns its warning, redacted and with no id; a good sentence leaves the warning empty.
Class OcuTalon.Test.Channel.ReplyText Extends %UnitTest.TestCase
{

Parameter CHANNEL = "slack";

/// A reply with the text, the check key and the rows (a dynamic array, or "" for none).
ClassMethod WithChecks(key As %String, rows As %DynamicArray) As OcuTalon.Msg.Outbound [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Outbound).%New()
	Set message.SessionRef = "zzreplytext"
	Set message.OriginChannel = "slack"
	Set message.Text = "zz reply"
	Set message.CheckKey = key
	If $IsObject(rows) Set message.CheckRows = rows.%ToJSON()
	Quit message
}

/// The time of a check row as the sentence shows it before any " ET": "at " and the message time, or "on " and the dated message time.
ClassMethod When(utc As %String) As %String [ Private ]
{
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(utc)
	Quit $Select(clock '? 2N1":"2N: "on ", 1: "at ") _ clock
}

/// The text of the reply for slack, with the status asserted OK.
Method TextOf(message As OcuTalon.Msg.Outbound, Output warning As %String) As %String [ Private ]
{
	Set text = ##class(OcuTalon.Channel.ReplyText).Text(message, ..#CHANNEL, .sc, .warning)
	Do $$$AssertStatusOK(sc, "the text is made")
	Quit text
}

Method TestSameAsTelegram()
{
	Set settings = "OcuTalon.Data.Public.Settings"
	Set savedDemo = $ClassMethod(settings, "Get", "onlineDemo")
	Try {
		Do $ClassMethod(settings, "Set", "onlineDemo", 0)
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set recent = ##class(OcuTalon.Data.Time).AddSeconds(now, -120)
		Set old = ##class(OcuTalon.Data.Time).AddSeconds(now, -3 * 86400)
		Set rest = ##class(OcuTalon.Msg.Catalog).Render("checks.everythingElsePassed", "", "telegram")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("checks.everythingElsePassed", "", "slack"), rest, "the catalog gives slack the text it gives telegram")
		Set blank = $Char(10, 10)

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}, {"result": "not_checked", "entry": "Beta", "finding": "Not run yet", "checkedAt": ""}, {"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}]
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.notEverythingRestPassed", rows)), "zz reply"_blank_"Not everything: Gamma (stopped, "_..When(recent)_"); Beta (not run yet). "_rest, "(a) the failed row comes first, with its time, then the other; the passed row is not named")

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (old)}, {"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}]
		Set shown = ##class(OcuTalon.Data.Time).ForMessage(old)
		Do $$$AssertTrue(shown '? 2N1":"2N, "its time carries a weekday")
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.notEverythingRestPassed", rows)), "zz reply"_blank_"Not everything: Gamma (stopped, on "_shown_"). "_rest, "(b) the sentence says on and the dated time")

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}, {"result": "passed", "entry": "Beta", "finding": "", "checkedAt": (recent)}]
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.allPassed", rows)), "zz reply"_blank_"Everything I checked passed.", "(c) the all-clear is the catalog text, from the key")

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}]
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.notEverything", rows), .warning), "zz reply", "(d) only a passed row: the reply goes alone, as the rows never make an all-clear")
		Do $$$AssertEquals(warning, "", "and with no warning")
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.nope", rows), .warning), "zz reply", "(e) an unknown check key: the reply goes alone")
		Do $$$AssertTrue(warning '= "", "with a warning")

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}]
		Do $ClassMethod(settings, "Set", "onlineDemo", 1)
		Set text = ..TextOf(..WithChecks("checks.notEverythingRestPassed", rows))
		Do $ClassMethod(settings, "Set", "onlineDemo", 0)
		Do $$$AssertEquals(text, "zz reply"_blank_"Not everything: Gamma (stopped, "_..When(recent)_" ET). "_rest, "(f) on the online demo the time is followed by ET")

		Set rows = [{"result": "failed", "entry": "Delta", "finding": "", "checkedAt": ""}, {"result": "failed", "entry": "Epsilon", "finding": "", "checkedAt": (recent)}, {"result": "failed", "entry": "", "finding": "Orphan", "checkedAt": (recent)}, {"result": "failed", "entry": "Zeta", "finding": "Broke", "checkedAt": ""}]
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.notEverythingRestPassed", rows)), "zz reply"_blank_"Not everything: Delta; Epsilon ("_..When(recent)_"); Zeta (broke). "_rest, "(g) an entry alone is named, a time alone follows at or on, a row with no entry is left out")

		For bad = "not json", "{}" {
			Set reply = ..WithChecks("checks.notEverythingRestPassed", "")
			Set reply.CheckRows = bad
			Do $$$AssertEquals(..TextOf(reply), "zz reply", "(h) CheckRows '"_bad_"': the reply goes alone")
		}

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}, {"result": "not_checked", "entry": "Beta", "finding": "Not run yet", "checkedAt": ""}]
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.notEverything", rows)), "zz reply"_blank_"Not everything: Gamma (stopped, "_..When(recent)_"); Beta (not run yet).", "(i) nothing passed: the sentence names what failed and claims nothing else")
		Do $$$AssertEquals(..TextOf(..WithChecks("checks.everythingElsePassed", rows)), "zz reply"_blank_"Everything else I checked passed.", "(j) the key's catalog text")
		Do $$$AssertEquals(..TextOf(..WithChecks("", rows)), "zz reply", "(k) no check key: the reply alone")
	} Catch ex {
		Do $$$AssertTrue(0, "the parity test failed: "_ex.DisplayString())
	}
	Do $ClassMethod(settings, "Set", "onlineDemo", savedDemo)
}

Method TestLearnedLines()
{
	Set blank = $Char(10, 10)
	Set ellipsis = $Char(8230)
	Set line = "I'll remember this: ""{fact}"". You can tell me to forget it."
	Set message = ..WithChecks("", "")
	Set message.Text = "Noted."
	Set message.Learned = [{"memoryRef": "zzm1", "text": "The Results partner's contact is Lee."}].%ToJSON()
	Do $$$AssertEquals(..TextOf(message), "Noted."_blank_"I'll remember this: ""The Results partner's contact is Lee"". You can tell me to forget it.", "(a) the reply, a blank line, and the ruled line with one full stop removed")

	Set message.Text = "Noted again."
	Set message.Learned = [{"memoryRef": "zzm1", "text": "<b>Lee</b> & *co* [x](y)"}, {"memoryRef": "zzm2", "text": "Second fact"}].%ToJSON()
	Do $$$AssertEquals(..TextOf(message), "Noted again."_blank_$Replace(line, "{fact}", "<b>Lee</b> & *co* [x](y)")_$Char(10)_$Replace(line, "{fact}", "Second fact"), "(b) markup in the facts is kept as written, and the lines are in order, one per line")

	Set long = $Translate($Justify("", 300), " ", "c")
	Set message.Text = "Noted long."
	Set message.Learned = [{"memoryRef": "zzm3", "text": (long)}].%ToJSON()
	Do $$$AssertEquals(..TextOf(message), "Noted long."_blank_$Replace(line, "{fact}", $Extract(long, 1, 199)_ellipsis), "(c) a 300-character fact is cut to 199 characters and an ellipsis")

	Set message.Text = "I'll remember that Lee is the contact."
	Set message.Learned = [{"memoryRef": "zzm1", "text": "Lee is the contact."}].%ToJSON()
	Do $$$AssertEquals(..TextOf(message), "I'll remember that Lee is the contact.", "(d) a reply that already says it adds nothing")

	Set message.Text = "Done."
	Set message.Learned = "[]"
	Do $$$AssertEquals(..TextOf(message), "Done.", "(e) no entry: the reply alone")

	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set recent = ##class(OcuTalon.Data.Time).AddSeconds(now, -120)
	Set message = ..WithChecks("checks.allPassed", [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}])
	Set message.Learned = [{"memoryRef": "zzm1", "text": "Lee is the contact."}].%ToJSON()
	Do $$$AssertEquals(..TextOf(message), "zz reply"_blank_"Everything I checked passed."_blank_$Replace(line, "{fact}", "Lee is the contact"), "(f) the check sentence comes first, then the line")
}

Method TestFallbackKey()
{
	Set message = ##class(OcuTalon.Msg.Outbound).%New()
	Set message.SessionRef = "zzreplytext"
	Set message.OriginChannel = "slack"
	Set message.CatalogKey = "press.rejected"
	Set message.Slots = "{}"
	Set expected = ##class(OcuTalon.Msg.Catalog).Render("press.rejected", {}, "telegram")
	Do $$$AssertEquals(..TextOf(message), expected, "a reply with no text is the rendering of its catalog key, as for telegram")
	Do $$$AssertEquals(expected, "Rejected. Nothing was changed.", "which is the catalog's sentence")
	Set message.Text = "zz own text"
	Do $$$AssertEquals(..TextOf(message), "zz own text", "a reply with a text is that text")
	Set message.Text = ""
	Set message.CatalogKey = "no.such.key"
	Set text = ##class(OcuTalon.Channel.ReplyText).Text(message, ..#CHANNEL, .sc, .warning)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a key that cannot be rendered is an error status")
	Do $$$AssertEquals(text, "", "and the text is empty")
}

Method TestWarning()
{
	Set message = ..WithChecks("checks.nope", [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": ""}])
	Do $$$AssertEquals(..TextOf(message, .warning), "zz reply", "a check key that gives no sentence leaves it out")
	Do $$$AssertTrue(warning [ "the check key is not one that gives a sentence", "and returns the reason: "_warning)
	Set message = ..WithChecks("checks.allPassed", "")
	Do $$$AssertEquals(..TextOf(message, .warning), "zz reply"_$Char(10, 10)_"Everything I checked passed.", "a good sentence is added")
	Do $$$AssertEquals(warning, "", "with an empty warning")
}

}
