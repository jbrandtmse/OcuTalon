/// Tests of OcuTalon.Eval.PersonaChecks, the pure checks of the persona sweep (Story 40.7; AC 2, 4, 5). WARM-SAFE: every method runs on fixed
/// strings and touches no table, no production and no file.
///   - TestSpanishReply: a Spanish reply with and without accents is Spanish; an English reply and the can't-write reply are not; exactly three Spanish
///     words are enough and two are not.
///   - TestCantWrite: the count of can't-write phrases is 0, 1 or 2 (a curly apostrophe counts as a straight one), every phrase of the list counts once
///     and CantWriteReply wants an English reply with exactly one.
///   - TestAllClear, TestVoiceMarkers: the Spanish all-clear phrases (accents folded) and the pirate words, exclamation marks and emoji.
///   - TestFacts: counts, times and production names in and out, and what SameFacts says of a rewording and of a changed count, time or name.
///   - TestKnownNames: the identifiers of a case's own input.
///   - TestTellNowFrame: the tell-now frame around a multi-line reason that holds braces, an exclamation mark and an emoji, and not around a blank summary or reason.
Class OcuTalon.Test.Eval.PersonaChecks Extends %UnitTest.TestCase
{

Method TestSpanishReply()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Set accents = "Todo est"_$Char(225)_" bien. El mensaje de la producci"_$Char(243)_"n es para usted."
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", accents), 1, "a Spanish reply with accents is Spanish")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "todo esta bien, el mensaje de la produccion es para usted"), 1, "and so is one without")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "TODO EST"_$Char(193)_" BIEN: EL MENSAJE ES MUY CLARO"), 1, "whatever the case")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "El mensaje es claro."), 1, "three Spanish words are enough")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "El mensaje claro."), 0, "two are not")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "The CI mock looked at the productions."), 0, "an English reply is not Spanish")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", "I can't write in Spanish, so I'm answering in English. El mensaje es claro."), 0, "a reply that says it can't write the language is not Spanish")
	Do $$$AssertEquals($ClassMethod(check, "SpanishReply", ""), 0, "an empty reply is not Spanish")
	Do $$$AssertEquals($ClassMethod(check, "Count", "El mensaje y la produccion", $Parameter(check, "SPANISHWORDS")), 5, "Count counts every occurrence of a word of the list")
}

Method TestCantWrite()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Do $$$AssertEquals($ClassMethod(check, "CantWrite", "The check results are listed below."), 0, "no phrase counts 0")
	Do $$$AssertEquals($ClassMethod(check, "CantWrite", "I can't write in Zorblish, so I'm answering in English."), 1, "one phrase counts 1")
	Do $$$AssertEquals($ClassMethod(check, "CantWrite", "I can"_$Char(8217)_"t write in Zorblish."), 1, "and a curly apostrophe is a straight one")
	Do $$$AssertEquals($ClassMethod(check, "CantWrite", "I can't write it. I cannot write it either."), 2, "two phrases count 2")
	Set list = $ListFromString($Parameter(check, "CANTWRITE"))
	Set position = 0
	While $ListNext(list, position, phrase) {
		Do $$$AssertEquals($ClassMethod(check, "CantWrite", "Sorry, I "_phrase_" Zorblish."), 1, "the phrase '"_phrase_"' counts once")
	}
	Set english = " The check results are listed below and you can read them."
	Do $$$AssertEquals($ClassMethod(check, "CantWriteReply", "I can't write in Zorblish, so I'm answering in English."_english), 1, "an English reply with one phrase is the can't-write answer")
	Do $$$AssertEquals($ClassMethod(check, "CantWriteReply", "I can't write in Zorblish. I cannot write it at all."_english), 0, "two phrases are not")
	Do $$$AssertEquals($ClassMethod(check, "CantWriteReply", "The check results are listed below and you can read them."), 0, "no phrase is not")
	Do $$$AssertEquals($ClassMethod(check, "CantWriteReply", "I can't write Zorblish."), 0, "a phrase with fewer than three English words is not")
	Do $$$AssertEquals($ClassMethod(check, "CantWriteReply", "Todo esta bien. No puedo escribir en Zorblish: can't write."), 0, "and neither is a reply in another language")
}

Method TestAllClear()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Set list = $ListFromString($Parameter(check, "SPANISHALLCLEAR"))
	Set position = 0
	While $ListNext(list, position, phrase) {
		Set found = $ClassMethod(check, "AllClearFound", "Hola. "_$ZConvert(phrase, "U")_". Gracias.")
		Do $$$AssertTrue(found.%ToJSON() [ (""""_phrase_""""), "the phrase '"_phrase_"' is found in capitals ("_found.%ToJSON()_")")
	}
	Do $$$AssertEquals($ClassMethod(check, "AllClearFound", "Todo est"_$Char(225)_" bien.").%ToJSON(), "[""todo esta bien""]", "an accent is folded")
	Do $$$AssertEquals($ClassMethod(check, "AllClearFound", "Todo va bien, sin problemas.").%ToJSON(), "[""todo va bien"",""sin problemas""]", "two phrases are found once each, in list order")
	Do $$$AssertEquals($ClassMethod(check, "AllClearFound", "Todo bien. Todo bien.").%ToJSON(), "[""todo bien""]", "and a repeated phrase once")
	Do $$$AssertEquals($ClassMethod(check, "AllClearFound", "Hay un problema con la produccion.").%ToJSON(), "[]", "a failure in Spanish has none")
	Do $$$AssertEquals($ClassMethod(check, "AllClearFound", "Everything is fine.").%ToJSON(), "[]", "and English has none")
}

Method TestVoiceMarkers()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "The Orders production is running."), 0, "a plain reply has none")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "Yes, the yes-man said so."), 0, "'yes' is not 'ye'")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "Ahoy matey!"), 3, "two pirate words and one exclamation mark")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "Ye landlubber, aye."), 3, "ye, landlubber and aye")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "All fine "_$Char(55357, 56834)_$Char(55356, 57152)), 2, "emoji of the supplementary range count")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "Anchor "_$Char(9875)_" ok"), 1, "and so does one of the range U+2600 to U+27BF")
	Do $$$AssertEquals($ClassMethod(check, "VoiceMarkers", "Caf"_$Char(233)_" is open."), 0, "an accented letter is none")
}

Method TestFacts()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Set names = ["Orders.Process", "OrderDate", "HL7", "Results"]
	Set plain = "Orders.Process failed 3 times at 9:05 and 2026-10-16T18:13:00Z; OrderDate is bad; 12 left on HL7."
	Set facts = $ClassMethod(check, "Facts", plain, names)
	Do $$$AssertEquals(facts.counts.%ToJSON(), "[3,12]", "the counts are the integers outside times and names")
	Do $$$AssertEquals(facts.times.%ToJSON(), "[""2026-10-16T18:13:00Z"",""9:05""]", "the times are the clock time and the date-time")
	Do $$$AssertEquals(facts.names.%ToJSON(), "[""HL7"",""OrderDate"",""Orders.Process""]", "the names are the ones the text mentions, sorted, and Results is not mentioned")
	Set pirate = "Arr, shipmate! Aye, the OrderDate on Orders.Process failed 3 times, at 9:05, and 2026-10-16T18:13:00Z was the time; 12 left on HL7."
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", pirate, names)), 1, "a rewording that keeps every fact has the same facts")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", $Replace(pirate, "3 times", "4 times"), names)), 0, "a changed count differs")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", $Replace(pirate, "9:05", "9:06"), names)), 0, "a changed time differs")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", $Replace(pirate, "2026-10-16", "2026-10-17"), names)), 0, "a changed date differs")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", $Replace(pirate, "OrderDate", "the date"), names)), 0, "a lost name differs")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", facts, $ClassMethod(check, "Facts", pirate_" Also 5 more.", names)), 0, "an added count differs")
	Set times = $ClassMethod(check, "Facts", "It ran at 09:05:30 and at 14:00, on 2026-10-16 13:00.", "")
	Do $$$AssertEquals(times.times.%ToJSON(), "[""09:05:30"",""14:00"",""2026-10-16 13:00""]", "HH:MM:SS, HH:MM and a date with a time are times")
	Do $$$AssertEquals(times.counts.%ToJSON(), "[]", "and none of their digits is a count")
	Set prefixed = $ClassMethod(check, "Facts", "Orders20 and Orders2 failed 4 times.", ["Orders2", "Orders20"])
	Do $$$AssertEquals(prefixed.counts.%ToJSON()_"|"_prefixed.names.%ToJSON(), "[4]|[""Orders2"",""Orders20""]", "a name that starts another name leaves no digit behind as a count")
	Set unnamed = $ClassMethod(check, "Facts", "Two failures on HL7 today.", "")
	Do $$$AssertEquals(unnamed.counts.%ToJSON(), "[7]", "a digit in a name that the input does not know is a count")
	Do $$$AssertEquals($ClassMethod(check, "SameFacts", "", facts), 0, "no facts object is not the same")
}

Method TestKnownNames()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Set names = $ClassMethod(check, "KnownNames", "Orders.Process failed on OrderDate at 3 sites; see HL7 and the end.")
	Do $$$AssertEquals(names.%ToJSON(), "[""Orders.Process"",""OrderDate"",""HL7""]", "a dotted name and names with two capitals are known, a plain word and a sentence-final one are not")
	Do $$$AssertEquals($ClassMethod(check, "KnownNames", "").%ToJSON(), "[]", "an empty input has none")
	Do $$$AssertEquals($ClassMethod(check, "KnownNames", "OrderDate and OrderDate again").%ToJSON(), "[""OrderDate""]", "each name once")
}

Method TestTellNowFrame()
{
	Set check = "OcuTalon.Eval.PersonaChecks"
	Do $$$AssertEquals($ClassMethod(check, "TellNowFrame", "An order failed", "Ahoy! The {hold} leaks,"_$Char(10)_"shipmate "_$Char(55357, 56834)_"."), 1, "a multi-line reason with braces, an exclamation mark and an emoji is in the frame")
	Do $$$AssertEquals($ClassMethod(check, "TellNowFrame", "", "A reason."), 0, "a blank summary has no frame")
	Do $$$AssertEquals($ClassMethod(check, "TellNowFrame", "An order failed", ""), 0, "and a blank reason has no slot text")
}

}
