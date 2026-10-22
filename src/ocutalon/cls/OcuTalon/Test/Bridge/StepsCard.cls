/// The tool zz_steps_card of the step tests (Story 1.5; AD-9): a test fixture, never part of a production. Read answers
/// {"owner", "card": "On call: <owner>"}, and for the owner locked it throws an error whose text names the password and the key it was
/// given: "The card of locked is locked: password=<password> apiKey=<key>". The arguments after owner are the secrets of the scenario
/// steps-secrets. A tool method runs inside AI Hub's callback, so it makes no AI Hub call and no Python call (AD-6).
Class OcuTalon.Test.Bridge.StepsCard Extends %AI.Tool
{

/// The readable label of the step of this tool (Consistency Conventions: Agent step labels): the parameter of the tool's own name.
Parameter STEPLABELZZSTEPSCARD = "Reading the test card";

/// The card of the owner.
ClassMethod Read(owner As %String = "", password As %String = "", chatId As %String = "", displayName As %String = "", apiKey As %String = "", accessToken As %String = "") As %DynamicObject
{
	If owner = "locked" {
		$$$ThrowStatus($$$ERROR($$$GeneralError, "The card of " _ owner _ " is locked: password=" _ password _ " apiKey=" _ apiKey))
	}
	Quit {"owner": (owner), "card": ("On call: " _ owner)}
}

}
