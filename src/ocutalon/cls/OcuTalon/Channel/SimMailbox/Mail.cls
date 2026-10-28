/// An email the page asked to simulate, as the REST surface hands it to SimMailboxIn (AD-14, AD-30). It is never stored or
/// sent: SimMailboxIn reads it and records and sends an Item. A Sample (one of SimMailboxIn's sample names) replaces Sender,
/// Subject and Text with the sample's own fields.
Class OcuTalon.Channel.SimMailbox.Mail Extends %RegisteredObject
{

/// The session's Ref, from Ownership.SessionRef (AD-4).
Property SessionRef As %String(MAXLEN = 22);

/// The name of a sample email, or empty for a typed one.
Property Sample As %String(MAXLEN = 64);

/// The From line.
Property Sender As %String(MAXLEN = 1000);

/// The subject line.
Property Subject As %String(MAXLEN = 1000);

/// The body.
Property Text As %String(MAXLEN = "");

}
