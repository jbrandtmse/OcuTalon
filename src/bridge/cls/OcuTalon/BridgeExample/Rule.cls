/// The routing rule of ExampleRouter (FR-5, AD-30): it routes each OcuTalon.BridgeExample.Msg.Decided by the two properties Fallback and
/// Outcome only. The rules run in this order, and each ends with a return:
///   1. a fallback decision goes to ExampleFallbackOut;
///   2. the outcomes tellnow and act go to ExampleNotifyOut;
///   3. digest goes to ExampleDigestOut;
///   4. ignore goes nowhere, so that the router completes and only records it.
Class OcuTalon.BridgeExample.Rule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="OcuTalon.BridgeExample.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="Fallback" disabled="false">
<constraint name="msgClass" value="OcuTalon.BridgeExample.Msg.Decided"></constraint>
<when condition="Document.Fallback=1">
<send transform="" target="ExampleFallbackOut"></send>
<return></return>
</when>
</rule>
<rule name="TellNow" disabled="false">
<constraint name="msgClass" value="OcuTalon.BridgeExample.Msg.Decided"></constraint>
<when condition="(Document.Outcome=&quot;tellnow&quot;)||(Document.Outcome=&quot;act&quot;)">
<send transform="" target="ExampleNotifyOut"></send>
<return></return>
</when>
</rule>
<rule name="Digest" disabled="false">
<constraint name="msgClass" value="OcuTalon.BridgeExample.Msg.Decided"></constraint>
<when condition="Document.Outcome=&quot;digest&quot;">
<send transform="" target="ExampleDigestOut"></send>
<return></return>
</when>
</rule>
<rule name="Ignore" disabled="false">
<constraint name="msgClass" value="OcuTalon.BridgeExample.Msg.Decided"></constraint>
<when condition="Document.Outcome=&quot;ignore&quot;">
<return></return>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
