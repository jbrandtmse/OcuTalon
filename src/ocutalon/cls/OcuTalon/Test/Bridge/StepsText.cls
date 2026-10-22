/// The tool zz_steps_text of the step tests (Story 1.5 QA; AD-9, AD-31): a test fixture, never part of a production. Unlike
/// OcuTalon.Test.Bridge.StepsNote, which answers a dynamic object, Read answers TEXT: a %String that holds JSON, which is the form of
/// the product's own tools (OcuTalon.Tools.WatchFixture answers JSON text). AI Hub gives the policy such a result as a JSON string, so
/// the redactor has to look inside the string (OcuTalon.Bridge.Redact.Literal). For the topic keys the text is a JSON object that holds
/// the five kinds of secret under their own keys (the "text" values of StepsNote.Secret) and, under a key that is not sensitive, a
/// line of free text with four more (the "line" values): a model key and a bot token as they are, a password after "password=" and a chat id
/// after "chat_id=". Otherwise it is {"topic", "note": "All systems normal."}. A tool method runs inside AI Hub's callback, so it makes
/// no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.StepsText Extends %AI.Tool
{

/// The readable label of the step of every tool of this class (Consistency Conventions: Agent step labels).
Parameter STEPLABEL = "Reading the test report";

/// The report, as text.
ClassMethod Read(topic As %String = "") As %String
{
	If topic '= "keys" Quit {"topic": (topic), "note": "All systems normal."}.%ToJSON()
	Set report = {}
	For kind = "apiKey", "accessToken", "password", "chatId", "displayName" {
		Do report.%Set(kind, ##class(OcuTalon.Test.Bridge.StepsNote).Secret(kind, "text"))
	}
	Do report.%Set("line", "retry failed: password=" _ ..Line("password") _ " chat_id=" _ ..Line("chatId") _ " key " _ ..Line("apiKey") _ " bot " _ ..Line("accessToken"))
	Quit report.%ToJSON()
}

/// The "line" value of the kind.
ClassMethod Line(kind As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.StepsNote).Secret(kind, "line")
}

}
