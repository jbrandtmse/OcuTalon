/// AnswerOps' reply to an Answer: the result of Approval.Answer (done, already_answered, expired, not_found or not_allowed), or
/// bad_answer when AnswersIn refused the action or channel. WinnerAction, WinnerChannel and WinnerAt describe the answer that
/// won when the result is already_answered, and are empty otherwise.
Class OcuTalon.Core.Msg.AnswerResult Extends Ens.Response
{

/// done, already_answered, expired, not_found, not_allowed or bad_answer.
Property Result As %String(MAXLEN = 16);

/// The action of the winning answer.
Property WinnerAction As %String(MAXLEN = 16);

/// The channel of the winning answer.
Property WinnerChannel As %String(MAXLEN = 16);

/// The UTC time of the winning answer.
Property WinnerAt As %String(MAXLEN = 40);

Storage Default
{
<Data name="AnswerResultDefaultData">
<Subscript>"AnswerResult"</Subscript>
<Value name="1">
<Value>Result</Value>
</Value>
<Value name="2">
<Value>WinnerAction</Value>
</Value>
<Value name="3">
<Value>WinnerChannel</Value>
</Value>
<Value name="4">
<Value>WinnerAt</Value>
</Value>
</Data>
<DefaultData>AnswerResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
