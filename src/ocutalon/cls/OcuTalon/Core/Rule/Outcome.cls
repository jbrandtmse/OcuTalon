/// The rule of the OutcomeRouter item (AD-30, AD-32), which routes each ItemDecision by its outcome. Its one rule set routes
/// OcuTalon.Msg.ItemDecision on named properties only; within the rule the first condition that holds wins:
///   - OwnerRef eval: nothing (an evaluation never reaches a notification, AD-22);
///   - Outcome digest: the ItemDecision, unchanged, to DigestStore;
///   - Outcome tellnow or act with a session as owner (Functions.IsSession): to Notify through the transform
///     OcuTalon.Core.Rule.Notice, which makes the tell-now Notification;
///   - anything else, ignore and an instance owner's tell now or act: nothing. An ignore leaves only the Decision row that
///     Decide recorded and the ItemDecision that this router received.
Class OcuTalon.Core.Rule.Outcome Extends Ens.Rule.Definition [ CompileAfter = (OcuTalon.Core.Rule.Functions, OcuTalon.Core.Rule.Notice) ]
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="OcuTalon.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="ItemDecision">
<constraint name="msgClass" value="OcuTalon.Msg.ItemDecision"></constraint>
<when condition="Document.OwnerRef=&quot;eval&quot;">
</when>
<when condition="Document.Outcome=&quot;digest&quot;">
<send transform="" target="DigestStore"></send>
</when>
<when condition="(Document.Outcome=&quot;tellnow&quot; || Document.Outcome=&quot;act&quot;) &amp;&amp; IsSession(Document.OwnerRef)">
<send transform="OcuTalon.Core.Rule.Notice" target="Notify"></send>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
