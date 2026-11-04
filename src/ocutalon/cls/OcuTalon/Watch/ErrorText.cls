/// The error's own sentence out of the text of a failure (pure; AD-15, DW-35). An errored message's log text wraps the error in the business
/// process's own words: "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: <sentence>", a line
/// break and "  > ERROR #5001: <sentence>" again. Sentence gives <sentence>, the text a person can act on; it also drops the words a host adds
/// while it retries under an alert grace period and the varying "logged as" tail of a system error, so that failures of one cause carry one text.
/// Sentence calls nothing outside this class. Text is Sentence of the redacted raw text (OcuTalon.Bridge.Redact, the one class it calls), the one
/// composition that every consumer of a raw error uses (DW-261), and Summary is the first sentence of Text, short enough for a line of a notice. All
/// three are pure, so a tool's callback may use them (AD-6).
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

/// The longest summary, in characters.
Parameter SUMMARYMAX = 80;

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

/// The error's own sentence of a raw error text, redacted: Sentence(Redact.Text(raw)). The redactor goes first so that no token is cut in half by the
/// sentence rules; it is idempotent, so a text that is already redacted passes through unchanged.
ClassMethod Text(raw As %String) As %String
{
	Quit ..Sentence(##class(OcuTalon.Bridge.Redact).Text($Get(raw)))
}

/// The first sentence of Text(raw): up to and including its first ". ", "? " or "! " mark (the whole text when it has none), at most SUMMARYMAX characters.
/// A longer sentence is cut at its last space within SUMMARYMAX - 1 characters (at that many characters when it has no space) and ends with U+2026.
/// An empty text gives "". Summary(Text(raw)) equals Summary(raw).
ClassMethod Summary(raw As %String) As %String
{
	Set text = ..Text(raw)
	Set end = $Length(text)
	For stop = ". ", "? ", "! " {
		Set after = $Find(text, stop)
		If after && ((after - 2) < end) Set end = after - 2
	}
	Set text = $Extract(text, 1, end)
	Set max = ..#SUMMARYMAX
	If $Length(text) > max {
		Set head = $Extract(text, 1, max - 1)
		Set space = 0
		For i = $Length(head):-1:1 {
			If $Extract(head, i) = " " {
				Set space = i
				Quit
			}
		}
		If space > 1 Set head = $Extract(head, 1, space - 1)
		Set text = $ZStrip(head, ">W")_$Char(8230)
	}
	Quit text
}

}
