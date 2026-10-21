/// An approval request: the row is the truth, and its state changes only through OcuTalon.Bridge.Approval (AD-11). Lane A.
Class OcuTalon.Bridge.Data.ApprovalRequest Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.Approval";

/// The keys of the stored dry run of a repair and resend fix; later fix kinds add their own (AD-16).
Parameter DRYRUNKEYS = "affected,resend,leftOut,field,before,after,itemNoun";

/// An unguessable random reference (AD-11).
Property Ref As %String(MAXLEN = 22);

/// One of Msg.Enum APPROVALKIND.
Property Kind As %String(MAXLEN = 32);

/// The incident, when there is one.
Property IncidentRef As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// One of Msg.Enum APPROVALSTATE.
Property State As %String(MAXLEN = 32);

/// The stored dry run, as JSON with the keys of DRYRUNKEYS (AD-16).
Property DryRun As %String(MAXLEN = "");

/// The tool of a tool_call request.
Property ToolName As %String(MAXLEN = 128);

/// The exact arguments of a tool_call request, as JSON.
Property ToolArguments As %String(MAXLEN = "");

/// The role a person needs to answer (AD-11).
Property RequiredRole As %String(MAXLEN = 128);

/// The production item that receives the outcome (AD-11).
Property ResultTarget As %String(MAXLEN = 128);

/// The session's trace reference: the SuperSession that its messages carry (AD-26).
Property TraceRef As %String(MAXLEN = 22);

/// When the request was raised.
Property RaisedAt As %String(MAXLEN = 20);

/// When the request expires: 24 hours after it was raised (AD-11).
Property ExpiresAt As %String(MAXLEN = 20);

/// The action that answered the request.
Property AnsweredAction As %String(MAXLEN = 32);

/// The channel that answered the request.
Property AnsweredChannel As %String(MAXLEN = 32);

/// The IRIS user who answered.
Property AnsweredBy As %String(MAXLEN = 128);

/// When the request was answered.
Property AnsweredAt As %String(MAXLEN = 20);

/// done, failed or interrupted, from FinishExecution (AD-11).
Property Result As %String(MAXLEN = 32);

/// When the run finished.
Property FinishedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index IncidentRefIndex On IncidentRef;

Index OwnerRefIndex On OwnerRef;

Storage Default
{
<Data name="ApprovalRequestDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>Kind</Value>
</Value>
<Value name="4">
<Value>IncidentRef</Value>
</Value>
<Value name="5">
<Value>OwnerRef</Value>
</Value>
<Value name="6">
<Value>State</Value>
</Value>
<Value name="7">
<Value>DryRun</Value>
</Value>
<Value name="8">
<Value>ToolName</Value>
</Value>
<Value name="9">
<Value>ToolArguments</Value>
</Value>
<Value name="10">
<Value>RequiredRole</Value>
</Value>
<Value name="11">
<Value>ResultTarget</Value>
</Value>
<Value name="12">
<Value>TraceRef</Value>
</Value>
<Value name="13">
<Value>RaisedAt</Value>
</Value>
<Value name="14">
<Value>ExpiresAt</Value>
</Value>
<Value name="15">
<Value>AnsweredAction</Value>
</Value>
<Value name="16">
<Value>AnsweredChannel</Value>
</Value>
<Value name="17">
<Value>AnsweredBy</Value>
</Value>
<Value name="18">
<Value>AnsweredAt</Value>
</Value>
<Value name="19">
<Value>Result</Value>
</Value>
<Value name="20">
<Value>FinishedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.ApprovalD</DataLocation>
<DefaultData>ApprovalRequestDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.ApprovalD</IdLocation>
<IndexLocation>^OcuTalonBP.ApprovalI</IndexLocation>
<StreamLocation>^OcuTalonBP.ApprovalS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
