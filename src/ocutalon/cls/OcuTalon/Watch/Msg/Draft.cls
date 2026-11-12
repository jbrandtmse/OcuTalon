/// The order to draft a fix kind's text (Story 23.5; AD-6, AD-15): IncidentManager sends it to itself, asynchronously, in the incident's trace session, when the chat asks for a
/// kind with DRAFTED 1 (partner_warning), so that the ask is answered at once and the draft runs after it. It names the incident (IncidentRef), the session that asked (SessionRef,
/// the owner of the draft's turn) and the kind (FixKind, the NAME of a class of OcuTalon.Fix.Kind). Lane A.
Class OcuTalon.Watch.Msg.Draft Extends Ens.Request
{

/// The Ref of the incident that the draft is about.
Property IncidentRef As %String(MAXLEN = 22);

/// The Ref of the session that asked for the draft.
Property SessionRef As %String(MAXLEN = 22);

/// The kind whose text is drafted.
Property FixKind As %String(MAXLEN = 32);

Storage Default
{
<Data name="DraftDefaultData">
<Subscript>"Draft"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>FixKind</Value>
</Value>
</Data>
<DefaultData>DraftDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
