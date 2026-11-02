/// The runner's adapter whose cut of the history starts at a tool result, for Test.Bridge.Compaction: the compaction rule never gives such a
/// cut, so the fork it asks for has a tool result where a user message should come first, and Compaction.Check must refuse it. Nothing else
/// differs from the adapter.
Class OcuTalon.Test.Bridge.ZzCutAdapter Extends OcuTalon.Bridge.Adapter.Agent
{

/// The cut that keeps everything from the first tool message of the history to its end, and summarizes what comes before; the cut of the
/// adapter when the history has no tool message.
Method CutOf(context As %DynamicArray, Output older As %DynamicArray) As %Integer [ Private ]
{
	Set older = []
	For i = 0:1:context.%Size() - 1 {
		If context.%Get(i).role = "tool" {
			For j = 0:1:i - 1 {
				Do older.%Push(context.%Get(j))
			}
			Return context.%Size() - i
		}
	}
	Quit ##super(context, .older)
}

}
