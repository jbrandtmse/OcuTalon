/// The failures that one poll of FailurePoller found for one production and one scope, sent to IncidentManager (AD-15, AD-26). Lane A. A batch is
/// its own trace session: its SuperSession is the scope session's TraceRef (empty for the scope instance).
Class OcuTalon.Watch.Msg.FailureBatch Extends Ens.Request
{

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// The scope: the Ref of the session whose TraceRef tagged the failures, or instance.
Property OwnerRef As %String(MAXLEN = 22);

/// When the poll ran: UTC to the second. The batches of one poll share it.
Property PolledAt As %String(MAXLEN = 20);

/// The failures, each once, in the order they were read.
Property Failures As list Of OcuTalon.Watch.Msg.Failure;

Storage Default
{
<Data name="FailureBatchDefaultData">
<Subscript>"FailureBatch"</Subscript>
<Value name="1">
<Value>Namespace</Value>
</Value>
<Value name="2">
<Value>Production</Value>
</Value>
<Value name="3">
<Value>OwnerRef</Value>
</Value>
<Value name="4">
<Value>PolledAt</Value>
</Value>
<Value name="5">
<Value>Failures</Value>
</Value>
</Data>
<DefaultData>FailureBatchDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
