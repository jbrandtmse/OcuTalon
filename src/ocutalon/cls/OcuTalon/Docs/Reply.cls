/// The documents half of the reply filter (AD-28, AD-31, Story 19.4; Lane A; DW-720): a pure function of a reply's text and its HostData JSON. The model is
/// told to answer "None of your documents cover that." when no passage answers the question, and code builds HostData.citations from the passages that clear
/// the score floor (OcuTalon.Bridge.Citations). A reply must never carry both: when the reply's HostData holds a non-empty citations array, Apply removes every
/// occurrence of the sentence from the text, with ReplyGuard's matching rule (case ignored, no letter or digit at either edge, the run of . ! ? , ; : after
/// it taken with the match, and the spaces of a changed line collapsed; a line that is left empty is dropped). The text is returned unchanged when HostData is
/// empty, is not a JSON object, has no citations member or holds an empty one, so a reply with no citation may say the sentence, and the citations are never
/// touched. A text that is only the sentence comes back empty, and Decide treats an empty filtered text as invalid: a turn that ran a tool is not retried
/// (Decide.Retryable), so a reply with citations takes Decide's fallback, and the sentence never leaves Decide next to a citation. OcuTalon.Checks.ReplyGuard.Filter calls it with the HostData that Decide hands to the reply filter.
Class OcuTalon.Docs.Reply
{

/// The sentence that the model says when no document covers the question (UX-DR144).
Parameter NONE = "None of your documents cover that.";

/// The text without the sentence when hostData holds citations, else the text as it is. It never throws: a failure returns the text unchanged.
ClassMethod Apply(text As %String, hostData As %String = "") As %String
{
	Set result = $Get(text)
	Try {
		If '..HasCitations($Get(hostData)) Quit
		Set phrase = $ZStrip(..#NONE, ">", ".")
		Set result = ##class(OcuTalon.Checks.ReplyGuard).Strip(result, ##class(OcuTalon.Checks.ReplyGuard).PatternOf(phrase))
	} Catch exception {
		Set result = $Get(text)
	}
	Quit result
}

/// 1 when hostData is a JSON object whose citations member is a non-empty array.
ClassMethod HasCitations(hostData As %String) As %Boolean
{
	If $ZStrip(hostData, "*WC") = "" Quit 0
	Set has = 0
	Try {
		Set data = {}.%FromJSON(hostData)
		If $IsObject(data) && (data.%GetTypeOf("citations") = "array") Set has = (data.citations.%Size() > 0)
	} Catch exception {
		Set has = 0
	}
	Quit has
}

}
