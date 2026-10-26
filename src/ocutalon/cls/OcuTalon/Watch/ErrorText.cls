/// The error's own sentence out of the text of a failure (pure; AD-15, DW-35). An errored message's log text wraps the error in the business
/// process's own words: "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: <sentence>", a line
/// break and "  > ERROR #5001: <sentence>" again. Sentence gives <sentence>, the text a person can act on; it also drops the words a host adds
/// while it retries under an alert grace period and the varying "logged as" tail of a system error, so that failures of one cause carry one text.
/// It makes no call outside this class, so a tool's callback may use it (AD-6).
Class OcuTalon.Watch.ErrorText
{

/// The longest sentence, in characters.
Parameter MAXLENGTH = 1000;

/// The wrapper's own words before the error: "Terminating BP", and the text that ends them.
Parameter WRAPPER = "Terminating BP";

Parameter WRAPPEREND = " due to error: ";

/// The text that opens the next line of a nested error.
Parameter NESTED = "  > ";

/// The varying tail that Interoperability appends to a system error ("logged as" a date, a number and a source line).
Parameter LOGGED = " -- logged as ";

/// The leading "ERROR #<n>: " or "ERROR <Ens>Name: " of an error text, as a regular expression.
Parameter PREFIX = "^ERROR (#[0-9]+|<[^>]+>[A-Za-z0-9_.]+): ?";

/// The leading words of an error that a host logs while it retries under an alert grace period, as a regular expression.
Parameter GRACE = "^(Not Alerting during|Alerting at expiration of) retry grace period \([0-9]+\) for ";

/// The error's own sentence of the text: after the last " due to error: " of the "Terminating BP" wrappers that the text holds (a business process
/// that failed on another's error nests them), up to the first line break, "  > " or " -- logged as ", without the leading "ERROR #<n>: ",
/// "ERROR <Ens>Name: " and retry grace period words, trimmed, at most MAXLENGTH characters. Text with none of those is returned trimmed; an empty
/// text gives "".
ClassMethod Sentence(text As %String) As %String
{
	Set text = $Get(text)
	Set end = ..#WRAPPEREND
	While (text [ ..#WRAPPER) && (text [ end) {
		Set text = $Piece(text, end, 2, *)
	}
	Set cut = $Length(text) + 1
	For stop = $Char(13), $Char(10), ..#NESTED, ..#LOGGED {
		Set after = $Find(text, stop)
		If after && ((after - $Length(stop)) < cut) Set cut = after - $Length(stop)
	}
	Set text = $ZStrip($Extract(text, 1, cut - 1), "<>W")
	While $Locate(text, ..#PREFIX, 1, next) || $Locate(text, ..#GRACE, 1, next) {
		Set text = $ZStrip($Extract(text, next, *), "<>W")
	}
	Quit $Extract(text, 1, ..#MAXLENGTH)
}

}
