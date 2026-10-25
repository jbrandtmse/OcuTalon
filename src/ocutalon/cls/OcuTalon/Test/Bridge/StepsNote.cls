/// The tool zz_steps_note of the step tests (Story 1.5; AD-9): a test fixture, never part of a production. Read hangs for a quarter of
/// a second, so that the duration of its step is measurable, and answers a dynamic object. For the topic keys the object holds the five
/// kinds of secret with their "result" values; otherwise it is {"topic", "note": "All systems normal."}. Secret(kind, where) gives
/// the ten fake secrets of the step tests: the five kinds apiKey, accessToken, password, chatId and displayName, each as the "arg" that the
/// scenario steps-secrets passes in and as the "result" that Read answers. The values are built here from fragments, and the scenario
/// writes the same values with JSON escapes, so that no file holds a key-like string. A tool method runs inside AI Hub's callback, so it
/// makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.StepsNote Extends %AI.Tool
{

/// The readable label of the step of every tool of this class (Consistency Conventions: Agent step labels).
Parameter STEPLABEL = "Reading the test note";

/// The note. The arguments after topic are the secrets of the scenario steps-secrets.
ClassMethod Read(topic As %String = "", apiKey As %String = "", accessToken As %String = "", password As %String = "", chatId As %String = "", displayName As %String = "") As %DynamicObject
{
	Hang 0.25
	If topic = "keys" {
		Quit {"topic": "keys", "apiKey": (..Secret("apiKey", "result")), "accessToken": (..Secret("accessToken", "result")), "password": (..Secret("password", "result")), "chatId": (..Secret("chatId", "result")), "displayName": (..Secret("displayName", "result"))}
	}
	Quit {"topic": (topic), "note": "All systems normal."}
}

/// The fake secret of the kind (apiKey, accessToken, password, chatId or displayName) in the place (arg or result: the ten strings of the
/// scenario steps-secrets; text, line or error: the strings of the scenario steps-secrets-text, which OcuTalon.Test.Bridge.StepsText and
/// OcuTalon.Test.Bridge.StepsCard return as TEXT): distinct strings for every kind and place.
/// The api key has the form of a model key, the access token that of a bot token, and the chat id and the display name those of a
/// Telegram identity.
ClassMethod Secret(kind As %String, where As %String) As %String
{
	Set number = $Select(where = "arg": 1, where = "result": 2, where = "text": 3, where = "line": 4, 1: 5)
	If kind = "apiKey" Quit "sk-" _ "ant-zzsteps-" _ where _ "-0123456789abcdefghijkl"
	If kind = "accessToken" Quit "555001100" _ number _ ":" _ "zzsteps-" _ where _ "-access-token-0123456789abcd"
	If kind = "password" Quit "Zz-Steps-Pass-" _ where _ "-4711"
	If kind = "chatId" Quit "777001100" _ number
	If kind = "displayName" Quit "Ada Zz-" _ where _ "-Display"
	Quit ""
}

/// The 14 fake secrets of the scenario steps-secrets-text, as a list: the five kinds in the places text (the keys of the report that
/// OcuTalon.Test.Bridge.StepsText answers) and error (the JSON body of the error that OcuTalon.Test.Bridge.StepsCard throws for the
/// owner refused), and four kinds in the place line (the free text of the report: a model key, a bot token, a password and a chat id).
ClassMethod TextValues() As %List
{
	Set values = ""
	For kind = "apiKey", "accessToken", "password", "chatId", "displayName" {
		Set values = values _ $ListBuild(..Secret(kind, "text"), ..Secret(kind, "error"))
	}
	For kind = "apiKey", "accessToken", "password", "chatId" {
		Set values = values _ $ListBuild(..Secret(kind, "line"))
	}
	Quit values
}

}
