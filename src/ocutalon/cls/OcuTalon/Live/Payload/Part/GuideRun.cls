/// The current run's total for the guide's finish state (AD-12, AD-20); Lane B publishes it in guide.state.
Class OcuTalon.Live.Payload.Part.GuideRun Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The decisions recorded in the run.
Property Decisions As %Integer(%JSONFIELDNAME = "decisions");

/// The run's tokens: input (cache tokens included) and output together.
Property Tokens As %Integer(%JSONFIELDNAME = "tokens");

/// The run's cost in US dollars.
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUSD", SCALE = 6);

/// The display names of the models the run used, in order of first use.
Property Models As list Of %String(%JSONFIELDNAME = "models", MAXLEN = 128);

}
