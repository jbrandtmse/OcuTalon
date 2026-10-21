/// The bridge's reply filter (AD-31): filters model-written text before any result leaves Decide, and runs before
/// Decide records anything, so every stored or emitted model text is already filtered. The default passes the text
/// through, so the bridge runs alone (FR-5). A host extends this class and names the subclass in the ReplyFilterClass
/// setting of the Decide item.
Class OcuTalon.Bridge.Ext.ReplyFilter
{

/// The text to use in place of text. Returns text unchanged by default.
ClassMethod Filter(text As %String) As %String
{
	Quit text
}

}
