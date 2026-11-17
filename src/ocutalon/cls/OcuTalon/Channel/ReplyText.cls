/// The text of a reply for a channel that sends plain text (Story 27.2; AD-14, AD-28, AD-32, UX-DR108). It is the shared rendering code of the *Out operations that
/// send an OcuTalon.Msg.Outbound as text (OcuTalon.Channel.Slack.Out), and only they call it: producers never render. Text(request, channel) is what the Telegram channel
/// sends for the same reply (OcuTalon.Channel.Telegram.Out OnOutbound), for the channel:
///   - the reply's Text, else the rendering of its CatalogKey through OcuTalon.Msg.Catalog.Render for the channel; a render error is an error status and the text "";
///   - when the reply has a CheckKey whose sentence is not "", a blank line and the check sentence: checks.allPassed, checks.everythingElsePassed and checks.nothingWatched
///     give the catalog text, and checks.notEverything and checks.notEverythingRestPassed are rendered with whatFailed, built from the CheckRows (result, entry, finding,
///     checkedAt): every row that did not pass and has an entry, the failed rows first, each group in row order, as "{entry} ({finding}, at {time})" with the finding's
///     first letter in lower case and an empty part left out, joined with "; ". The time is Data.Time.ForMessage of checkedAt, with " ET" on the online demo, and "at" is
///     "on" before a dated time. When no row is left, or the key is any other, or the sentence cannot be rendered, the sentence is "" and the reply goes alone; the last two
///     give a warning text in warning (the error's text through Bridge.Redact), "" otherwise;
///   - when OcuTalon.Memory.Learned shows lines for the reply's Learned entries (for the channel), a blank line and the lines, one per line (LF).
/// The text holds no id and no name that the reply's own text does not hold. It writes nothing and logs nothing.
Class OcuTalon.Channel.ReplyText [ Abstract ]
{

/// The check keys whose catalog text is the whole sentence.
Parameter PLAINKEYS = "checks.allPassed,checks.everythingElsePassed,checks.nothingWatched";

/// The check keys whose text names what failed, in its whatFailed slot.
Parameter FAILEDKEYS = "checks.notEverything,checks.notEverythingRestPassed";

/// The separator of the rows in whatFailed.
Parameter SEPARATOR = "; ";

/// The text of a reply for the channel (see the class comment). The status is an error, and the text "", when the reply's catalog text cannot be rendered. warning is the
/// text of a check sentence that was left out because it could not be built, else "".
ClassMethod Text(request As OcuTalon.Msg.Outbound, channel As %String, Output sc As %Status, Output warning As %String) As %String
{
	Set sc = $$$OK
	Set warning = ""
	Set text = request.Text
	If (text = "") && (request.CatalogKey '= "") {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, channel, .sc)
		If $SYSTEM.Status.IsError(sc) Quit ""
	}
	Set sentence = ..CheckSentence(request.CheckKey, request.CheckRows, channel, .warning)
	If sentence '= "" Set text = text_$Char(10, 10)_sentence
	Set lines = ##class(OcuTalon.Memory.Learned).Lines(request.Learned, request.Text, channel)
	If lines.%Size() Set text = text_$Char(10, 10)_..Joined(lines)
	Quit text
}

/// The lines of a dynamic array of text, one per line (LF).
ClassMethod Joined(lines As %DynamicArray) As %String [ Private ]
{
	Set joined = ""
	Set iterator = lines.%GetIterator()
	While iterator.%GetNext(, .line) {
		Set joined = joined_$Select(joined = "": "", 1: $Char(10))_line
	}
	Quit joined
}

/// The check sentence of a reply (see the class comment): "" for no key, for no row to name and, with the warning text, for any other key or a sentence that cannot be
/// rendered.
ClassMethod CheckSentence(key As %String, rowsJson As %String, channel As %String, Output warning As %String) As %String [ Private ]
{
	Set warning = ""
	If key = "" Quit ""
	Set sentence = ""
	Set sc = $$$OK
	Try {
		If $ListFind($ListFromString(..#PLAINKEYS), key) {
			Set sentence = ##class(OcuTalon.Msg.Catalog).Render(key, "", channel, .sc)
		} ElseIf $ListFind($ListFromString(..#FAILEDKEYS), key) {
			Set failed = ..WhatFailed(rowsJson)
			If failed '= "" Set sentence = ##class(OcuTalon.Msg.Catalog).Render(key, {"whatFailed": (failed)}.%ToJSON(), channel, .sc)
		} Else {
			Set sc = $SYSTEM.Status.Error(5001, "the check key is not one that gives a sentence")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) {
		Set warning = ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc))
		Quit ""
	}
	Quit sentence
}

/// What did not pass, as one text: every row (a JSON array) whose result is not passed and that has an entry, the failed rows first and
/// then the others, each group in row order, as "{entry} ({finding}, at {time})", joined with "; ". "" when no row is left or the rows
/// cannot be read.
ClassMethod WhatFailed(rowsJson As %String) As %String [ Private ]
{
	If rowsJson = "" Quit ""
	Set rows = ""
	Try {
		Set rows = ##class(%DynamicAbstractObject).%FromJSON(rowsJson)
	} Catch {
		Set rows = ""
	}
	If '$IsObject(rows) || 'rows.%IsA("%Library.DynamicArray") Quit ""
	Set onlineDemo = +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set failed = "", other = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If '$IsObject(row) || 'row.%IsA("%Library.DynamicObject") Continue
		If row.result = "passed" Continue
		Set entry = ..Field(row, "entry")
		If entry = "" Continue
		Set finding = ..Field(row, "finding")
		Set finding = $ZConvert($Extract(finding), "L")_$Extract(finding, 2, *)
		Set clock = ..Field(row, "checkedAt")
		Set dated = 0
		If clock '= "" {
			Set clock = ##class(OcuTalon.Data.Time).ForMessage(clock)
			Set dated = (clock '= "") && (clock '? 2N1":"2N)
			If clock '= "" Set clock = clock_$Select(onlineDemo: " ET", 1: "")
		}
		Set detail = ""
		Set at = $Select(dated: "on ", 1: "at ")
		If (finding '= "") && (clock '= "") {
			Set detail = finding_", "_at_clock
		} ElseIf finding '= "" {
			Set detail = finding
		} ElseIf clock '= "" {
			Set detail = at_clock
		}
		Set named = $Select(detail = "": entry, 1: entry_" ("_detail_")")
		If row.result = "failed" {
			Set failed = failed_$ListBuild(named)
		} Else {
			Set other = other_$ListBuild(named)
		}
	}
	Quit $ListToString(failed_other, ..#SEPARATOR)
}

/// A row's string field, trimmed of white space at both ends; "" for anything that is not a string.
ClassMethod Field(row As %DynamicObject, name As %String) As %String [ Private ]
{
	If row.%GetTypeOf(name) '= "string" Quit ""
	Quit $ZStrip(row.%Get(name), "<>W")
}

}
