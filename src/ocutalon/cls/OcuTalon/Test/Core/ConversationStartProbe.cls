/// A subclass of OcuTalon.Test.Core.ConversationProbe for the tests of the session starts (Story 41.3; AD-21): it overrides the private Request to record, for each request
/// that Conversation builds, $ListBuild(kind, the context as JSON, or "" for none) under ^OcuTalonTest("ConversationProbe", RunNumber, "context", n), and then builds the
/// request as Conversation does. It adds nothing else and the product never refers to it.
Class OcuTalon.Test.Core.ConversationStartProbe Extends OcuTalon.Test.Core.ConversationProbe
{

Method Request(turn As OcuTalon.Data.Turn, kind As %String, context As %DynamicObject = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set n = $Increment(^OcuTalonTest("ConversationProbe", ..RunNumber, "context"))
	Set ^OcuTalonTest("ConversationProbe", ..RunNumber, "context", n) = $ListBuild(kind, $Select($IsObject(context): context.%ToJSON(), 1: ""))
	Quit ##super(turn, kind, context)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
