/// One row per session's copy of an outbound message: what an *Out operation sent, and where, so that an edit in place finds it (AD-14). Lane B.
/// WebChatOut is the first writer (Story 2.7) and the web chat's copy of a notice card: its row keeps the card as it was shown
/// (Kind, the rendered Text, DecisionRef, DueAt and FallbackReason), so that a reload shows the card as it was sent (DW-62).
/// A row is read only through Ownership (RecentNotices for the chat, DeliveryFor for an edit in place).
Class OcuTalon.Data.Delivery Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Delivery";

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The channel's message id; for Telegram <ChatRef>:<message_id> (AD-14). For a web card, the card's Ref.
Property ChannelMessageId As %String(MAXLEN = 128);

/// The Ref of the approval request (AD-11).
Property ApprovalRef As %String(MAXLEN = 22);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

/// The kind of the notification the row delivers: one of Msg.Enum NOTIFICATIONKIND; empty for a reply.
Property Kind As %String(MAXLEN = 32);

/// The rendered text of a web notice card, exactly as it was sent; empty for any other row.
Property Text As %String(MAXLEN = "");

/// The Ref of the Decision row behind the notification, when a decision raised it (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// When the thing a reminder card is about is due, UTC to the second.
Property DueAt As %String(MAXLEN = 20);

/// The fallback reason the card shows: one of Msg.Enum FALLBACKREASON; empty when the card is not a fallback.
Property FallbackReason As %String(MAXLEN = 32);

Index ApprovalRefChannelOwnerRefIndex On (ApprovalRef, Channel, OwnerRef);

Index OwnerRefChannelIndex On (OwnerRef, Channel);

/// Records one session's copy of an outbound message: the channel's message id, the approval request it carries, if any, and
/// for a web card its kind, text, decision, due time and fallback reason. RecordedAt is the time now. An empty owner or a
/// channel outside Msg.Enum CHANNEL is an error status and records nothing. row is the saved row, "" when nothing was saved.
ClassMethod Record(ownerRef As %String, channel As %String, channelMessageId As %String, approvalRef As %String, kind As %String = "", text As %String = "", decisionRef As %String = "", dueAt As %String = "", fallbackReason As %String = "", Output row As OcuTalon.Data.Delivery) As %Status
{
	Set row = ""
	If $Get(ownerRef) = "" Quit $SYSTEM.Status.Error(5001, "A delivery needs the Ref of its owner")
	If '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#CHANNEL), $Get(channel)) Quit $SYSTEM.Status.Error(5001, "'"_$Get(channel)_"' is not a channel")
	Set row = ..%New()
	Set row.OwnerRef = ownerRef
	Set row.Channel = channel
	Set row.ChannelMessageId = $Get(channelMessageId)
	Set row.ApprovalRef = $Get(approvalRef)
	Set row.Kind = kind
	Set row.Text = text
	Set row.DecisionRef = decisionRef
	Set row.DueAt = dueAt
	Set row.FallbackReason = fallbackReason
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $SYSTEM.Status.IsError(sc) Set row = ""
	Quit sc
}

/// Finds the channel message id of the approval message to edit in place: the newest row of the owner whose approval Ref and
/// channel are exactly these (case-sensitive), read through Ownership.DeliveryFor. "" when there is none, for an empty value
/// and for the owners instance and eval, which have no rows to read (AD-14).
ClassMethod FindByApproval(approvalRef As %String, channel As %String, ownerRef As %String) As %String
{
	If ($Get(approvalRef) = "") || ($Get(channel) = "") || ($Get(ownerRef) = "") Quit ""
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryFor(approvalRef, channel, ownerRef, .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) Quit ""
	Quit row.ChannelMessageId
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
<Value name="7">
<Value>Kind</Value>
</Value>
<Value name="8">
<Value>Text</Value>
</Value>
<Value name="9">
<Value>DecisionRef</Value>
</Value>
<Value name="10">
<Value>DueAt</Value>
</Value>
<Value name="11">
<Value>FallbackReason</Value>
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
