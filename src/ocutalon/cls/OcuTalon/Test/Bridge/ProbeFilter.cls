/// A reply filter for the tests of Decide (Story 1.3): it puts "[f] " in front of the text, counts its calls in the
/// process-private global ^||ZzProbeFilter and keeps the text of each call in ^||ZzProbeFilter(<call>), so that a test can tell
/// that Decide filtered each model-written text exactly once and no code-written text. A text that holds the marker {blank}
/// is filtered down to the empty string, as a guard that removes a whole sentence would. The test that sets the global kills it.
Class OcuTalon.Test.Bridge.ProbeFilter Extends OcuTalon.Bridge.Ext.ReplyFilter
{

ClassMethod Filter(text As %String) As %String
{
	Set n = $Increment(^||ZzProbeFilter)
	Set ^||ZzProbeFilter(n) = text
	If text [ "{blank}" Quit ""
	Quit "[f] "_text
}

}
