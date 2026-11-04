/// A message the page posted, as the REST surface hands it to WebChatIn (AD-14, AD-30). It is never stored or sent: WebChatIn
/// reads it and sends an Item.
Class OcuTalon.Channel.WebChat.Post Extends %RegisteredObject
{

/// The session's Ref, from Ownership.SessionRef (AD-4).
Property SessionRef As %String(MAXLEN = 22);

/// The page's own id for the message.
Property ClientId As %String(MAXLEN = 128);

/// The user's message.
Property Text As %String(MAXLEN = "");

/// True when the text came from a guide prompt.
Property FromGuide As %Boolean [ InitialExpression = 0 ];

}
