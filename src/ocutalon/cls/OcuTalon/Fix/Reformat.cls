/// The reformatters of a repair (AD-16): a fixed set of value formats registered in code, which a fix kind converts a field between. The model
/// only names two of them (the names of DATES and NUMBERS, written exactly and case-sensitive); the conversion is code. A value is converted as text:
///   - a date is one of the five date formats, with ASCII digits only and a real calendar date from 1840-12-31 to 9999-12-31 (the range of $ZDATEH);
///   - a number is one of the four number formats: an optional minus sign, whole digits (grouped in threes where the format groups, no leading
///     zero unless the whole part is 0), and, after the decimal separator, one or more digits. It is converted as digit strings: no arithmetic and no
///     rounding, so the digits of the fraction are kept as they are;
///   - a value is refused when it is empty, longer than MAXLENGTH, does not match its source format as a whole, or the two formats are one format or
///     belong to different families.
/// A value is only matched against fixed patterns and cut at fixed positions. It is never evaluated: nothing here runs code that is built from
/// a value, a name or a format, and no SQL. Pure: no database and no namespace. Lane A.
Class OcuTalon.Fix.Reformat
{

/// The date formats, separated by a vertical bar (a comma cannot separate the names, because a number format name holds one).
Parameter DATES = "YYYY-MM-DD|MM/DD/YYYY|DD/MM/YYYY|DD.MM.YYYY|YYYYMMDD";

/// The number formats, separated by a vertical bar.
Parameter NUMBERS = "1234.56|1234,56|1,234.56|1.234,56";

/// The longest value that is converted, in characters.
Parameter MAXLENGTH = 40;

/// The registered format names, the dates, then the numbers.
ClassMethod Names() As %List
{
	Quit $ListFromString(..#DATES, "|") _ $ListFromString(..#NUMBERS, "|")
}

/// The family of a format: date or number, else "" (an unknown name, or one written in another case).
ClassMethod Family(name As %String) As %String
{
	If $Get(name) = "" Quit ""
	If $ListFind($ListFromString(..#DATES, "|"), name) Quit "date"
	If $ListFind($ListFromString(..#NUMBERS, "|"), name) Quit "number"
	Quit ""
}

/// Converts value from the source format to the target format into result. An error status, with the reason, when a name is not registered, the two
/// are one format or of two families, or the value does not read in the source format (see the class description).
ClassMethod Convert(value As %String, source As %String, target As %String, Output result As %String) As %Status
{
	Set result = ""
	Set family = ..Family(source)
	If family = "" Quit $$$ERROR($$$GeneralError, "The format '"_$Get(source)_"' is not a registered format")
	If ..Family(target) = "" Quit $$$ERROR($$$GeneralError, "The format '"_$Get(target)_"' is not a registered format")
	If family '= ..Family(target) Quit $$$ERROR($$$GeneralError, "The formats '"_source_"' and '"_target_"' are not of one family")
	If source = target Quit $$$ERROR($$$GeneralError, "The formats are one format, '"_source_"'")
	Set value = $Get(value)
	If value = "" Quit $$$ERROR($$$GeneralError, "The value is empty")
	If $Length(value) > ..#MAXLENGTH Quit $$$ERROR($$$GeneralError, "The value is longer than "_..#MAXLENGTH_" characters")
	If family = "date" Quit ..ConvertDate(value, source, target, .result)
	Quit ..ConvertNumber(value, source, target, .result)
}

/// 1 when the value reads in the format (Convert's checks for the value and the format alone).
ClassMethod Reads(value As %String, format As %String) As %Boolean
{
	Set family = ..Family($Get(format))
	If family = "" Quit 0
	Set value = $Get(value)
	If (value = "") || ($Length(value) > ..#MAXLENGTH) Quit 0
	If family = "date" Quit $$$ISOK(..ParseDate(value, format, .year, .month, .day))
	Quit $$$ISOK(..ParseNumber(value, format, .sign, .whole, .fraction, .hasFraction))
}

/// The year, month and day of a date value in the format, or an error status when it does not match the format or is not a calendar date.
ClassMethod ParseDate(value As %String, format As %String, Output year As %String, Output month As %String, Output day As %String) As %Status [ Private ]
{
	Set (year, month, day) = ""
	Set shape = $Case(format, "YYYY-MM-DD": "[0-9]{4}-[0-9]{2}-[0-9]{2}", "MM/DD/YYYY": "[0-9]{2}/[0-9]{2}/[0-9]{4}", "DD/MM/YYYY": "[0-9]{2}/[0-9]{2}/[0-9]{4}", "DD.MM.YYYY": "[0-9]{2}[.][0-9]{2}[.][0-9]{4}", "YYYYMMDD": "[0-9]{8}", : "")
	If shape = "" Quit $$$ERROR($$$GeneralError, "The format '"_format_"' is not a date format")
	If '$Match(value, shape) Quit $$$ERROR($$$GeneralError, "The value does not match "_format)
	If format = "YYYY-MM-DD" {
		Set year = $Extract(value, 1, 4), month = $Extract(value, 6, 7), day = $Extract(value, 9, 10)
	} ElseIf format = "YYYYMMDD" {
		Set year = $Extract(value, 1, 4), month = $Extract(value, 5, 6), day = $Extract(value, 7, 8)
	} ElseIf format = "MM/DD/YYYY" {
		Set month = $Extract(value, 1, 2), day = $Extract(value, 4, 5), year = $Extract(value, 7, 10)
	} Else {
		Set day = $Extract(value, 1, 2), month = $Extract(value, 4, 5), year = $Extract(value, 7, 10)
	}
	If $ZDateH(year_"-"_month_"-"_day, 3, , , , , , , -1) < 0 Quit $$$ERROR($$$GeneralError, "The value is not a date of the calendar")
	Quit $$$OK
}

ClassMethod ConvertDate(value As %String, source As %String, target As %String, Output result As %String) As %Status [ Private ]
{
	Set sc = ..ParseDate(value, source, .year, .month, .day)
	If $$$ISERR(sc) Quit sc
	Set result = $Case(target, "YYYY-MM-DD": year_"-"_month_"-"_day, "MM/DD/YYYY": month_"/"_day_"/"_year, "DD/MM/YYYY": day_"/"_month_"/"_year, "DD.MM.YYYY": day_"."_month_"."_year, "YYYYMMDD": year_month_day, : "")
	If result = "" Quit $$$ERROR($$$GeneralError, "The format '"_target_"' is not a date format")
	Quit $$$OK
}

/// The group separator of a number format ("" for none) and its decimal separator.
ClassMethod Separators(format As %String, Output group As %String, Output decimal As %String) As %Status [ Private ]
{
	Set group = $Case(format, "1234.56": "", "1234,56": "", "1,234.56": ",", "1.234,56": ".", : "?")
	Set decimal = $Case(format, "1234.56": ".", "1234,56": ",", "1,234.56": ".", "1.234,56": ",", : "?")
	If decimal = "?" Quit $$$ERROR($$$GeneralError, "The format '"_format_"' is not a number format")
	Quit $$$OK
}

/// The sign ("-" or ""), the whole digits (group separators removed), the fraction digits and whether a decimal separator was written, of a number
/// value in the format, or an error status when it does not match the format.
ClassMethod ParseNumber(value As %String, format As %String, Output sign As %String, Output whole As %String, Output fraction As %String, Output hasFraction As %Boolean) As %Status [ Private ]
{
	Set (sign, whole, fraction) = ""
	Set hasFraction = 0
	Set sc = ..Separators(format, .group, .decimal)
	If $$$ISERR(sc) Quit sc
	Set body = value
	If $Extract(body) = "-" {
		Set sign = "-"
		Set body = $Extract(body, 2, *)
	}
	If $Find(body, decimal) {
		Set hasFraction = 1
		Set whole = $Piece(body, decimal, 1)
		Set fraction = $Piece(body, decimal, 2, *)
		If '$Match(fraction, "[0-9]+") Quit $$$ERROR($$$GeneralError, "The value does not match "_format)
	} Else {
		Set whole = body
	}
	If group = "" {
		If '$Match(whole, "(0|[1-9][0-9]*)") Quit $$$ERROR($$$GeneralError, "The value does not match "_format)
	} Else {
		Set shape = "(0|[1-9][0-9]{0,2}(["_group_"][0-9]{3})*)"
		If '$Match(whole, shape) Quit $$$ERROR($$$GeneralError, "The value does not match "_format)
		Set whole = $Translate(whole, group, "")
	}
	Quit $$$OK
}

ClassMethod ConvertNumber(value As %String, source As %String, target As %String, Output result As %String) As %Status [ Private ]
{
	Set sc = ..ParseNumber(value, source, .sign, .whole, .fraction, .hasFraction)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Separators(target, .group, .decimal)
	If $$$ISERR(sc) Quit sc
	Set text = ""
	If group = "" {
		Set text = whole
	} Else {
		Set rest = whole
		While $Length(rest) > 3 {
			Set text = group_$Extract(rest, *-2, *)_text
			Set rest = $Extract(rest, 1, *-3)
		}
		Set text = rest_text
	}
	Set result = sign_text_$Select(hasFraction: decimal_fraction, 1: "")
	Quit $$$OK
}

}
