/// The answer to an approval request, as AnswersIn hands it to AnswerOps (AD-4, AD-11). It carries the Ref of the request, the
/// action (approve or reject), the channel it came from and the answering session's Ref. It carries no user name: AnswerOps reads
/// the session's IRIS user from the Session row.
Class OcuTalon.Core.Msg.Answer Extends Ens.Request
{

/// The Ref of the approval request.
Property Ref As %String(MAXLEN = 22);

/// approve or reject.
Property Action As %String(MAXLEN = 16);

/// The channel the answer came from (Bridge Msg.Enum CHANNEL).
Property Channel As %String(MAXLEN = 16);

/// The Ref of the answering session.
Property SessionRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="AnswerDefaultData">
<Subscript>"Answer"</Subscript>
<Value name="1">
<Value>Ref</Value>
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
<DefaultData>AnswerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
