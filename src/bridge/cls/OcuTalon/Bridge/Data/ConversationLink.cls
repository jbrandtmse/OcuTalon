/// Maps (OwnerRef, agent) to an AI session; only the runner writes it, and only for turn requests with provenance user (AD-6). Lane A.
Class OcuTalon.Bridge.Data.ConversationLink Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.ConvLink";

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The agent of the conversation.
Property Agent As %String(MAXLEN = 32);

/// The AI session's id.
Property SessionId As %String(MAXLEN = 128);

Index OwnerRefAgentIndex On (OwnerRef, Agent) [ Unique ];

Storage Default
{
<Data name="ConversationLinkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OwnerRef</Value>
</Value>
<Value name="3">
<Value>Agent</Value>
</Value>
<Value name="4">
<Value>SessionId</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.ConvLinkD</DataLocation>
<DefaultData>ConversationLinkDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.ConvLinkD</IdLocation>
<IndexLocation>^OcuTalonBP.ConvLinkI</IndexLocation>
<StreamLocation>^OcuTalonBP.ConvLinkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
