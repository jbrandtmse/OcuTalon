/// Test of the part of Triage's instructions that handles the user's own chat message (Story 30.5, DW-500; AD-28, AD-7). Nothing
/// is written anywhere and no model is called.
///   - TestUserMessageParagraph: the INSTRUCTIONS tell Triage that a message with no channel line that is not quoted is the user's own, that it
///     is always answered ("tellnow"), that its one reason only says what kind of message it is, and that the reasons never describe the state of
///     a production, what Triage can or cannot look up or access, or whether anything needs the user, also when the user asks to resend, approve or change
///     something (the paragraph on arriving items that ask for these is not about the user's own message);
///   - TestNoToolsSentence: the INSTRUCTIONS no longer say "You have no tools", which fed reasons that describe Triage's tool limits.
///   - TestRememberSentence (Story 30.9, DW-890): the paragraph ends with the one sentence that makes a request to remember or forget something the
///     user's own message, to be decided "tellnow" with the one reason and a confidence, and the sentence is held once, right after the paragraph's
///     former last sentence.
/// The mock cannot show a real model's wording: the user-turn cases of the evaluation set score it in a release-candidate run.
Class OcuTalon.Test.Agent.TriageUserTurn Extends %UnitTest.TestCase
{

/// The paragraph names the user's own message, the always-answered outcome, the example reasons and each thing the reasons must never describe.
Method TestUserMessageParagraph()
{
	Set text = ..Instructions()
	Do $$$AssertTrue(text '= "", "Triage has instructions")
	For phrase = "The user's own message.", "does not say which channel it arrived on", "is not quoted", "the user's own chat message", "it is always answered, so choose ""tellnow""", "A question from the user; the user is answered directly.", "A request from the user; the user is answered directly.", "Never describe the state of a production", "what you can or cannot look up or access", "whether anything needs the user", "OcuTalon answers the user separately", "This holds also when the user asks OcuTalon to resend, approve or change something", "never about the user's own message." {
		Do $$$AssertTrue(text [ phrase, "the instructions say '"_phrase_"'")
	}
	Do $$$AssertTrue(text [ "Decide from the message alone.", "and Triage is told to decide from the message alone")
	Do $$$AssertTrue('(text [ "{{"), "and the instructions hold no template token (AD-7)")
}

/// The sentence that told Triage it has no tools is gone.
Method TestNoToolsSentence()
{
	Set text = ..Instructions()
	Do $$$AssertTrue('(text [ "You have no tools"), "the instructions do not say 'You have no tools'")
}

/// A request to remember or forget something is the user's own message: the sentence is held once, follows the paragraph's last sentence after one
/// space, and ends the paragraph.
Method TestRememberSentence()
{
	Set text = ..Instructions()
	Set before = "never about the user's own message."
	Set sentence = "A request to remember or forget something is also the user's own message: choose ""tellnow"" for it, give the one reason, and give a confidence as for any other message."
	Do $$$AssertEquals($Length(text, sentence) - 1, 1, "the instructions hold the remember sentence exactly once")
	Do $$$AssertTrue(text [ (before_" "_sentence_$Char(10)_$Char(10)_"An item on the channel heartbeat"), "it follows 'never about the user's own message.' and one space, and the paragraph ends after it")
}

/// --- helpers ---
/// The INSTRUCTIONS block of the compiled Triage class as text, with no carriage return.
ClassMethod Instructions() As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Agent.Triage||INSTRUCTIONS")
	If '$IsObject(xdata) Quit ""
	Quit $Replace(xdata.Data.Read(1000000), $Char(13), "")
}

}
