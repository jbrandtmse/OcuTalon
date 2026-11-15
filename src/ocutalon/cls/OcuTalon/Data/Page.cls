/// One page of an on-call person (AD-15, Story 23.4; Lane A): one row for each person that an incident paged, the on-call person first (Role oncall) and, once
/// nobody acknowledged in time, the backup (Role backup). IncidentManager's job is the only writer, through Watch.Paging, and the Watch area's Purge the only deleter
/// (with the incident). The page's Ref is the DecisionRef of every channel's copy, and unguessable (Bridge.Ids.NewRef).
///   - Person is an OcuTalon user name or an email address, never a Telegram identity: it is contact data at rest, as the on-call setting keys are, and it is in no
///     Ens message body or header, log line, audit entry or payload. The rendered text of a channel's copy of the page, and that copy's Delivery row, name the backup
///     or the person (Watch.Paging.Text renders them).
///   - Channels is the person's channel list when the page was made (oncall.primary.channels or oncall.backup.channels).
///   - AcknowledgedAt and AcknowledgedChannel are set once, by the first acknowledgement. EscalationRef is the Ref of the escalation timer that was asked for
///     the page, empty when none was (a backup page never has one).
///   - OfIncident reads the rows of an incident by object access only, so that a REST request may call it (AD-13); Marked is the acknowledgement time, as
///     Handled.Marked is a notice's.
Class OcuTalon.Data.Page Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Page";

/// The roles, in the order OfIncident lists them.
Parameter ROLES = "oncall,backup";

/// The status code of a %DeleteId whose row is already gone ($$$DeleteObjectNotFound).
Parameter NOTFOUND [ Final ] = 5810;

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Compared exactly.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The incident that was paged. Compared exactly.
Property IncidentRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// oncall or backup. Compared exactly.
Property Role As %String(COLLATION = "EXACT", MAXLEN = 16) [ SqlFieldName = PageRole ];

/// The paged person: an OcuTalon user name or an email address.
Property Person As %String(MAXLEN = 320);

/// The person's channels when the page was made, a comma list.
Property Channels As %String(MAXLEN = 64);

/// When the page was recorded, UTC to the second.
Property SentAt As %String(MAXLEN = 20);

/// When the first acknowledgement came, UTC to the second; empty until then.
Property AcknowledgedAt As %String(MAXLEN = 20);

/// The channel of the first acknowledgement: web, phone or telegram.
Property AcknowledgedChannel As %String(MAXLEN = 32);

/// The Ref of the escalation timer asked for this page; empty when none was.
Property EscalationRef As %String(MAXLEN = 22);

Index RefIndex On Ref [ Unique ];

Index IncidentRoleIndex On (IncidentRef, Role) [ Unique ];

/// The rows of the incident, the on-call page first, by object access only: IncidentRoleIndexExists and %OpenId. A row whose incident or role is not the one asked for
/// (the index compares exactly, so none is) is left out.
ClassMethod OfIncident(incidentRef As %String) As %ListOfObjects
{
	Set list = ##class(%ListOfObjects).%New()
	If $Get(incidentRef) = "" Quit list
	For i = 1:1:$Length(..#ROLES, ",") {
		Set role = $Piece(..#ROLES, ",", i)
		If '..IncidentRoleIndexExists(incidentRef, role, .id) Continue
		Set row = ..%OpenId(id)
		If $IsObject(row) && (row.IncidentRef = incidentRef) && (row.Role = role) Do list.Insert(row)
	}
	Quit list
}

/// When the page was acknowledged, UTC to the second, or "" when it is not (or the Ref is empty or unknown).
ClassMethod Marked(ref As %String) As %String
{
	If $Get(ref) = "" Quit ""
	Set row = ..RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.AcknowledgedAt, 1: "")
}

Storage Default
{
<Data name="PageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>IncidentRef</Value>
</Value>
<Value name="4">
<Value>Role</Value>
</Value>
<Value name="5">
<Value>Person</Value>
</Value>
<Value name="6">
<Value>Channels</Value>
</Value>
<Value name="7">
<Value>SentAt</Value>
</Value>
<Value name="8">
<Value>AcknowledgedAt</Value>
</Value>
<Value name="9">
<Value>AcknowledgedChannel</Value>
</Value>
<Value name="10">
<Value>EscalationRef</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.PageD</DataLocation>
<DefaultData>PageDefaultData</DefaultData>
<IdLocation>^OcuTalonP.PageD</IdLocation>
<IndexLocation>^OcuTalonP.PageI</IndexLocation>
<StreamLocation>^OcuTalonP.PageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
