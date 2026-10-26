/// The error's own sentence out of the text of a failure (pure; AD-15, DW-35). An errored message's log text wraps the error in the business
/// process's own words: "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: <sentence>", a line
/// break and "  > ERROR #5001: <sentence>" again. Sentence gives <sentence>, the text a person can act on. It makes no call outside this
/// class, so a tool's callback may use it (AD-6).
Class OcuTalon.Watch.ErrorText
{

/// The longest sentence, in characters.
Parameter MAXLENGTH = 1000;

/// The wrapper's own words before the error: "Terminating BP", and the text that ends them.
Parameter WRAPPER = "Terminating BP";

Parameter WRAPPEREND = " due to error: ";

/// The text that opens the next line of a nested error.
Parameter NESTED = "  > ";

/// The leading "ERROR #<n>: " or "ERROR <Ens>Name: " of an error text, as a regular expression.
Parameter PREFIX = "^ERROR (#[0-9]+|<[^>]+>[A-Za-z0-9_.]+): ?";

/// The error's own sentence of the text: after the first " due to error: " when the text holds "Terminating BP", up to the first line break or
/// "  > ", without a leading "ERROR #<n>: " or "ERROR <Ens>Name: ", trimmed, at most MAXLENGTH characters. Text with none of those is
/// returned trimmed; an empty text gives "".
ClassMethod Sentence(text As %String) As %String
{
	Set text = $Get(text)
	Set end = ..#WRAPPEREND
	If (text [ ..#WRAPPER) && (text [ end) Set text = $Piece(text, end, 2, *)
	Set cut = $Length(text) + 1
	For stop = $Char(13), $Char(10), ..#NESTED {
		Set after = $Find(text, stop)
		If after && ((after - $Length(stop)) < cut) Set cut = after - $Length(stop)
	}
	Set text = $ZStrip($Extract(text, 1, cut - 1), "<>W")
	While $Locate(text, ..#PREFIX, 1, next) {
		Set text = $ZStrip($Extract(text, next, *), "<>W")
	}
	Quit $Extract(text, 1, ..#MAXLENGTH)
}

}
