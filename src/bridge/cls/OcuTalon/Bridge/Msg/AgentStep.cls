/// One step of an agent turn, sent to AgentSteps (AD-9, AD-26). Lane A.
Class OcuTalon.Bridge.Msg.AgentStep Extends Ens.Request
{

/// The Ref of the Decision row of the Decide call this step belongs to (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// The step's position in the turn.
Property Position As %Integer;

/// model or tool.
Property StepKind As %String(MAXLEN = 32);

/// The readable name of the step.
Property Label As %String(MAXLEN = 1000);

/// A redacted one-line summary of the step.
Property Summary As %String(MAXLEN = 1000);

/// Duration of the step in milliseconds.
Property DurationMs As %Integer;

/// ok, denied or error.
Property Status As %String(MAXLEN = 32);

/// The step's estimated token count.
Property EstimatedTokens As %Integer;

Storage Default
{
<Data name="AgentStepDefaultData">
<Subscript>"AgentStep"</Subscript>
<Value name="1">
<Value>DecisionRef</Value>
</Value>
<Value name="2">
<Value>Position</Value>
</Value>
<Value name="3">
<Value>StepKind</Value>
</Value>
<Value name="4">
<Value>Label</Value>
</Value>
<Value name="5">
<Value>Summary</Value>
</Value>
<Value name="6">
<Value>DurationMs</Value>
</Value>
<Value name="7">
<Value>Status</Value>
</Value>
<Value name="8">
<Value>EstimatedTokens</Value>
</Value>
</Data>
<DefaultData>AgentStepDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
