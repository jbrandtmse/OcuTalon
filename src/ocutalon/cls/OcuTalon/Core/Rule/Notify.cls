/// The rule of the Notify item (AD-4, AD-14, AD-32), which routes each reply and notification to the channels. Its one rule set
/// routes on the message class, Kind, OriginChannel, ChatRef and the session's channels (Functions.DemoOn, TelegramOn and
/// TelegramPaired); within a rule the first condition that holds wins:
///   - OcuTalon.Msg.Outbound (a reply): WebChatOut, and TelegramOut as well when OriginChannel is telegram and the session
///     is paired;
///   - OcuTalon.Msg.Notification of Kind pairing: TelegramOut alone when ChatRef is set and Telegram is included, otherwise
///     nothing;
///   - Kind allowance: WebChatOut, and TelegramOut as well when the session is paired;
///   - Kind digest: the session's own channels that digest.channels also names (Functions.DigestNamed): WebChatOut when web is named,
///     SimPhoneOut when phone is named and demo mode is on, TelegramOut when telegram is named and the session is paired; nothing
///     when none holds. A digest never takes the generic route below;
///   - Kind digest, in the rule DigestEmail beside the one above: EmailOut as well when Functions.DigestEmail holds for the session (digest.channels
///     names email, the session owns the mailbox, email.address is an address, EmailOut has an alive job, not the online demo; Story 21.7). Its
///     send adds to the targets of the rule above, so EmailOut is the one channel that never needs the combinations of the rule above;
///   - any other Kind: WebChatOut, SimPhoneOut as well when demo mode is on, and TelegramOut as well when the session is paired.
/// A session is paired only while Telegram is included, so a release without Telegram never sends to TelegramOut.
Class OcuTalon.Core.Rule.Notify Extends Ens.Rule.Definition [ CompileAfter = OcuTalon.Core.Rule.Functions ]
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="OcuTalon.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="Outbound">
<constraint name="msgClass" value="OcuTalon.Msg.Outbound"></constraint>
<when condition="Document.OriginChannel=&quot;telegram&quot; &amp;&amp; TelegramPaired(Document.SessionRef)">
<send transform="" target="WebChatOut,TelegramOut"></send>
</when>
<otherwise>
<send transform="" target="WebChatOut"></send>
</otherwise>
</rule>
<rule name="Notification">
<constraint name="msgClass" value="OcuTalon.Msg.Notification"></constraint>
<when condition="Document.Kind=&quot;pairing&quot; &amp;&amp; Document.ChatRef!=&quot;&quot; &amp;&amp; TelegramOn()">
<send transform="" target="TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;pairing&quot;">
</when>
<when condition="Document.Kind=&quot;allowance&quot; &amp;&amp; TelegramPaired(Document.SessionRef)">
<send transform="" target="WebChatOut,TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;allowance&quot;">
<send transform="" target="WebChatOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DigestNamed(&quot;web&quot;)) &amp;&amp; (DemoOn() &amp;&amp; DigestNamed(&quot;phone&quot;)) &amp;&amp; (TelegramPaired(Document.SessionRef) &amp;&amp; DigestNamed(&quot;telegram&quot;))">
<send transform="" target="WebChatOut,SimPhoneOut,TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DigestNamed(&quot;web&quot;)) &amp;&amp; (DemoOn() &amp;&amp; DigestNamed(&quot;phone&quot;))">
<send transform="" target="WebChatOut,SimPhoneOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DigestNamed(&quot;web&quot;)) &amp;&amp; (TelegramPaired(Document.SessionRef) &amp;&amp; DigestNamed(&quot;telegram&quot;))">
<send transform="" target="WebChatOut,TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DigestNamed(&quot;web&quot;))">
<send transform="" target="WebChatOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DemoOn() &amp;&amp; DigestNamed(&quot;phone&quot;)) &amp;&amp; (TelegramPaired(Document.SessionRef) &amp;&amp; DigestNamed(&quot;telegram&quot;))">
<send transform="" target="SimPhoneOut,TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (DemoOn() &amp;&amp; DigestNamed(&quot;phone&quot;))">
<send transform="" target="SimPhoneOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; (TelegramPaired(Document.SessionRef) &amp;&amp; DigestNamed(&quot;telegram&quot;))">
<send transform="" target="TelegramOut"></send>
</when>
<when condition="Document.Kind=&quot;digest&quot;">
</when>
<when condition="DemoOn() &amp;&amp; TelegramPaired(Document.SessionRef)">
<send transform="" target="WebChatOut,SimPhoneOut,TelegramOut"></send>
</when>
<when condition="DemoOn()">
<send transform="" target="WebChatOut,SimPhoneOut"></send>
</when>
<when condition="TelegramPaired(Document.SessionRef)">
<send transform="" target="WebChatOut,TelegramOut"></send>
</when>
<otherwise>
<send transform="" target="WebChatOut"></send>
</otherwise>
</rule>
<rule name="DigestEmail">
<constraint name="msgClass" value="OcuTalon.Msg.Notification"></constraint>
<when condition="Document.Kind=&quot;digest&quot; &amp;&amp; DigestEmail(Document.SessionRef)">
<send transform="" target="EmailOut"></send>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
