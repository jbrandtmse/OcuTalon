/// An email that Channel.Email.Adapter read, as it hands it to EmailIn (AD-14, AD-30). It is never stored or sent: EmailIn reads it and
/// sends an Item. Uidl is the server's unique id, Sender the From line, Subject the subject line and Text the plain text of the body (an
/// HTML body with its tags removed), cut by the adapter; an email over the size limit has the headers only and an empty Text.
Class OcuTalon.Channel.Email.Mail Extends %RegisteredObject
{

/// The server's unique id of the email.
Property Uidl As %String(MAXLEN = 70);

/// The From line.
Property Sender As %String(MAXLEN = 1000);

/// The subject line.
Property Subject As %String(MAXLEN = 1000);

/// The body as plain text.
Property Text As %String(MAXLEN = "");

}
