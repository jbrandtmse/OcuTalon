/// The page that an incident's first notice sent, in the incident payload (Story 23.4; AD-12, AD-15; Lane A): its state (paged, escalated when the backup was paged, or
/// acknowledged), when the on-call person was paged, and when and on which channel the first acknowledgement came. It names no person: the paged person's name, address and
/// session are in no payload.
Class OcuTalon.Live.Payload.Part.Page Extends (%RegisteredObject, %JSON.Adaptor)
{

/// paged, escalated or acknowledged.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16);

/// When the on-call person was paged, UTC to the second.
Property PagedAt As %String(%JSONFIELDNAME = "pagedAt", MAXLEN = 20);

/// When the first acknowledgement came, UTC to the second; empty until then.
Property AcknowledgedAt As %String(%JSONFIELDNAME = "acknowledgedAt", MAXLEN = 20);

/// The channel of the first acknowledgement: web, phone or telegram; empty until then.
Property Channel As %String(%JSONFIELDNAME = "channel", MAXLEN = 32);

}
