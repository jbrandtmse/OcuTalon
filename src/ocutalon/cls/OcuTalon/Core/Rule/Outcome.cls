/// The rule of the OutcomeRouter item (AD-30), which routes each ItemDecision by its outcome. A stub until Story 2.7: its one rule set holds no rule, so the router accepts a message and routes nothing.
Class OcuTalon.Core.Rule.Outcome Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.MsgRouter.RuleAssist";

/// Marks a rule that is not built yet. The owner deletes this parameter when it builds the rule;
/// Story 11.5's release check refuses an enabled router whose rule class still has it.
Parameter STUB = 1;

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="OcuTalon.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
</ruleSet>
</ruleDefinition>
}

}
