/// Every outbound message that is not a reply (AD-32). Producers never render text; the *Out operations render the catalog key. Lane B.
Class OcuTalon.Msg.Notification Extends Ens.Request
{

/// The session that receives the notification.
Property SessionRef As %String(MAXLEN = 22);

/// The paired chat's Ref, never a chat id (AD-14).
Property ChatRef As %String(MAXLEN = 22);

/// One of Msg.Enum NOTIFICATIONKIND (AD-32).
Property Kind As %String(MAXLEN = 32);

/// The catalog key of a notice whose text is fixed by code (AD-14, AD-32).
Property CatalogKey As %String(MAXLEN = 128);

/// The slots as JSON: times as UTC ISO 8601, counts as integers, the item noun as itemNoun {"one","other"} (AD-32).
Property Slots As %String(MAXLEN = "");

/// The approval request's Ref when the notice carries Approve and Reject, or answers one (AD-32).
Property ApprovalRef As %String(MAXLEN = 22);

/// The incident's Ref, when there is one (AD-32).
Property IncidentRef As %String(MAXLEN = 22);

/// The Ref of the Decision row that holds the attention decision (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="NotificationDefaultData">
<Subscript>"Notification"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>ChatRef</Value>
</Value>
<Value name="3">
<Value>Kind</Value>
</Value>
<Value name="4">
<Value>CatalogKey</Value>
</Value>
<Value name="5">
<Value>Slots</Value>
</Value>
<Value name="6">
<Value>ApprovalRef</Value>
</Value>
<Value name="7">
<Value>IncidentRef</Value>
</Value>
<Value name="8">
<Value>DecisionRef</Value>
</Value>
</Data>
<DefaultData>NotificationDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
