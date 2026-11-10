/// A subclass of OcuTalon.Test.Core.ConversationProbe for the tests of the session starts (Story 41.3; AD-21): it overrides the private Request to record, for each request
/// that Conversation builds, $ListBuild(kind, the context as JSON, or "" for none) under ^OcuTalonTest("ConversationProbe", RunNumber, "context", n), and then builds the
/// request as Conversation does; and its read of the last replied turn fails with an error status while ^||ConversationStartProbe("failLast") is 1, and its read of whether a decision was served by a model (Story 41.12) while ^||ConversationStartProbe("failServed") is 1. It adds nothing else and
/// the product never refers to it.
Class OcuTalon.Test.Core.ConversationStartProbe Extends OcuTalon.Test.Core.ConversationProbe
{

/// The session's last replied turn: an error status and "" while ^||ConversationStartProbe("failLast") is 1, else Conversation's own read.
ClassMethod LastReplied(sessionRef As %String, Output sc As %Status) As OcuTalon.Data.Turn [ Private ]
{
	If $Get(^||ConversationStartProbe("failLast")) {
		Set sc = $SYSTEM.Status.Error(5001, "zz the read of the last replied turn failed")
		Quit ""
	}
	Quit ##super(sessionRef, .sc)
}

/// Whether the decision was served: an error status and 0 while ^||ConversationStartProbe("failServed") is 1, else Conversation's own read.
ClassMethod Served(decisionRef As %String, sessionRef As %String, Output sc As %Status) As %Boolean [ Private ]
{
	If $Get(^||ConversationStartProbe("failServed")) {
		Set sc = $SYSTEM.Status.Error(5001, "zz the read of the usage failed")
		Quit 0
	}
	Quit ##super(decisionRef, sessionRef, .sc)
}

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
