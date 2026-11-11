/// The order to send one approved delay notice to the Simulated mailbox of one session (AD-14, AD-16; Story 23.5): FixExecutor sends it to SimMailboxOut, synchronously, once for
/// each recipient and each session of the incident. Text is the notice, the approved row's text byte for byte, and is never rendered as a catalog template; the subject is the
/// catalog key CatalogKey with Slots. ApprovalRef is the approved request's Ref, which the saved mail carries, and IncidentRef the incident's. Lane A.
Class OcuTalon.Fix.Msg.PartnerNotice Extends Ens.Request
{

/// The owning session's Ref: the session whose mailbox receives the notice.
Property SessionRef As %String(MAXLEN = 22);

/// The approved request's Ref.
Property ApprovalRef As %String(MAXLEN = 22);

/// The incident's Ref.
Property IncidentRef As %String(MAXLEN = 22);

/// The catalog key of the subject.
Property CatalogKey As %String(MAXLEN = 128);

/// The slots of the subject, as JSON.
Property Slots As %String(MAXLEN = "");

/// The notice: the body of the mail, as approved.
Property Text As %String(MAXLEN = "");

Storage Default
{
<Data name="PartnerNoticeDefaultData">
<Subscript>"PartnerNotice"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>ApprovalRef</Value>
</Value>
<Value name="3">
<Value>IncidentRef</Value>
</Value>
<Value name="4">
<Value>CatalogKey</Value>
</Value>
<Value name="5">
<Value>Slots</Value>
</Value>
<Value name="6">
<Value>Text</Value>
</Value>
</Data>
<DefaultData>PartnerNoticeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
