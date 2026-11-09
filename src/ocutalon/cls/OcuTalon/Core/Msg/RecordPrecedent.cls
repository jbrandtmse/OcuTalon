/// The record of an approval answer as a precedent, as AnswerOps hands it to PrecedentOps (AD-21, AD-29; Story 41.2). It carries the Ref of the approval
/// request, the action (approve or reject), the channel the answer came from and the answering session's Ref. PrecedentOps accepts it from AnswerOps only.
Class OcuTalon.Core.Msg.RecordPrecedent Extends Ens.Request
{

/// Every message to PrecedentOps is answered with a CommandResult.
Parameter RESPONSECLASSNAME = "OcuTalon.Msg.CommandResult";

/// The Ref of the approval request.
Property ApprovalRef As %String(MAXLEN = 22);

/// approve or reject.
Property Action As %String(MAXLEN = 32);

/// The channel the answer came from (Msg.Enum CHANNEL).
Property Channel As %String(MAXLEN = 32);

/// The Ref of the answering session.
Property SessionRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="RecordPrecedentDefaultData">
<Subscript>"RecordPrecedent"</Subscript>
<Value name="1">
<Value>ApprovalRef</Value>
</Value>
<Value name="2">
<Value>Action</Value>
</Value>
<Value name="3">
<Value>Channel</Value>
</Value>
<Value name="4">
<Value>SessionRef</Value>
</Value>
</Data>
<DefaultData>RecordPrecedentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
