/// One failure of a watched production, as FailurePoller reports it inside a FailureBatch (AD-15). Lane A.
Class OcuTalon.Watch.Msg.Failure Extends %SerialObject
{

/// header for a message header in the error status, error or alert for an event-log row with no session.
Property Kind As %String(MAXLEN = 16);

/// The id of the failed message header in the watched namespace; empty for a log row.
Property HeaderId As %Integer;

/// The session id of the failed message in the watched namespace; empty for a log row.
Property SessionId As %Integer;

/// The configuration item that failed: the target of the header, or the ConfigName of the log row.
Property ItemName As %String(MAXLEN = 128);

/// The configuration item that sent the failed message; empty for a log row.
Property SourceName As %String(MAXLEN = 128);

/// The class of the failed message's body; empty for a log row.
Property BodyClass As %String(MAXLEN = 256);

/// The error's own sentence (OcuTalon.Watch.ErrorText.Sentence).
Property ErrorText As %String(MAXLEN = 1000);

/// When it failed: UTC, YYYY-MM-DDTHH:MM:SSZ.
Property FailedAt As %String(MAXLEN = 20);

/// The id of the event-log row that holds the error text, or of the log row itself; empty when there is none.
Property LogId As %Integer;

Storage Default
{
<Data name="FailureState">
<Value name="1">
<Value>Kind</Value>
</Value>
<Value name="2">
<Value>HeaderId</Value>
</Value>
<Value name="3">
<Value>SessionId</Value>
</Value>
<Value name="4">
<Value>ItemName</Value>
</Value>
<Value name="5">
<Value>SourceName</Value>
</Value>
<Value name="6">
<Value>BodyClass</Value>
</Value>
<Value name="7">
<Value>ErrorText</Value>
</Value>
<Value name="8">
<Value>FailedAt</Value>
</Value>
<Value name="9">
<Value>LogId</Value>
</Value>
</Data>
<State>FailureState</State>
<StreamLocation>^OcuTalon.Watch.Msg.FailureS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
