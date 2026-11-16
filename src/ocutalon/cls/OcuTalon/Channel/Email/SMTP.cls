/// The SMTP client of Channel.Email.Sender (Story 23.15, DW-1429): %Net.SMTP that says whether a send reached the point where the message data began. %Net.SMTP names no step in a
/// timeout (SMTPTimeout), so a status alone cannot tell a server that never answered the greeting, EHLO, STARTTLS, AUTH, MAIL FROM or RCPT TO (the message was never handed over)
/// from one that stopped answering after the data began (the message may have been taken). DataBegan is the one fact that tells them apart: Send sets it to 0 when it starts, and
/// SendMessage, which %Net.SMTP calls only after the server's 354 answer to DATA and before it writes the first header, sets it to 1. Sender.MayHaveSent reads it. Nothing else is changed:
/// every command, timeout, setting and status is %Net.SMTP's.
Class OcuTalon.Channel.Email.SMTP Extends %Net.SMTP
{

/// 1 once the server has answered DATA with its 354 and the message data was started, in the latest Send; 0 before that, and for a Send that stopped earlier.
Property DataBegan As %Boolean [ InitialExpression = 0 ];

/// Sends the message as %Net.SMTP does, with DataBegan 0 until the data begins.
Method Send(msg As %Net.MailMessage) As %Status
{
	Set ..DataBegan = 0
	Quit ##super(msg)
}

/// %Net.SMTP's step that writes the headers and the body, called only after the server's 354: the data has begun.
Method SendMessage(msg As %Net.MailMessage) [ Internal, Private ]
{
	Set ..DataBegan = 1
	Do ##super(msg)
}

}
