/// One row per session's copy of an outbound message: what an *Out operation sent, and where, so that an edit in place finds it (AD-14). Lane B implements the methods in Story 2.7.
Class OcuTalon.Data.Delivery Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Delivery";

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The channel's message id; for Telegram <ChatRef>:<message_id> (AD-14).
Property ChannelMessageId As %String(MAXLEN = 128);

/// The Ref of the approval request (AD-11).
Property ApprovalRef As %String(MAXLEN = 22);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index ApprovalRefChannelOwnerRefIndex On (ApprovalRef, Channel, OwnerRef);

/// Records one session's copy of an outbound message and the approval request it carries, if any.
/// Not implemented yet: it returns an error status, so that a caller cannot mistake the stub for a recorded delivery
/// (AD-14). Lane B implements it in Story 2.7.
ClassMethod Record(ownerRef As %String, channel As %String, channelMessageId As %String, approvalRef As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "OcuTalon.Data.Delivery.Record is not implemented yet (Story 2.7)")
}

/// Finds the channel message id of the approval message to edit in place. Not implemented yet: it returns "",
/// the answer for a delivery that was never recorded (AD-14). Lane B implements it in Story 2.7.
ClassMethod FindByApproval(approvalRef As %String, channel As %String, ownerRef As %String) As %String
{
	Quit ""
}

Storage Default
{
<Data name="DeliveryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OwnerRef</Value>
</Value>
<Value name="3">
<Value>Channel</Value>
</Value>
<Value name="4">
<Value>ChannelMessageId</Value>
</Value>
<Value name="5">
<Value>ApprovalRef</Value>
</Value>
<Value name="6">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.DeliveryD</DataLocation>
<DefaultData>DeliveryDefaultData</DefaultData>
<IdLocation>^OcuTalonP.DeliveryD</IdLocation>
<IndexLocation>^OcuTalonP.DeliveryI</IndexLocation>
<StreamLocation>^OcuTalonP.DeliveryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
