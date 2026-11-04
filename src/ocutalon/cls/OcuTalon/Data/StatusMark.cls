/// A named status mark, such as the last heartbeat tick or the Telegram state (AD-18). Lane B.
Class OcuTalon.Data.StatusMark Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.StatusMark";

/// The name of the mark; unique.
Property Mark As %String(MAXLEN = 128);

/// The value of the mark.
Property Value As %String(MAXLEN = 1000);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index MarkIndex On Mark [ Unique ];

/// Creates or replaces the row of the mark, with the value and RecordedAt (UTC, to the second), which a replace stamps
/// again. An empty value deletes the row; an empty mark name is an error status that says the mark is empty.
ClassMethod Record(mark As %String, value As %String) As %Status
{
	If $Get(mark) = "" Quit $SYSTEM.Status.Error(5001, "A status mark needs a name: the mark is empty")
	Set row = ..MarkIndexOpen(mark)
	If $Get(value) = "" {
		If $IsObject(row) Quit ..%DeleteId(row.%Id())
		Quit $SYSTEM.Status.OK()
	}
	If '$IsObject(row) {
		Set row = ..%New()
		Set row.Mark = mark
	}
	Set row.Value = value
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// The value of the mark, or "" when it has no row.
ClassMethod Get(mark As %String) As %String
{
	If $Get(mark) = "" Quit ""
	Set row = ..MarkIndexOpen(mark)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The mark that holds the Telegram state (AD-14): the JSON {"state", "botUserName"}, so that the two change together. Written only
/// by RecordTelegram.
Parameter TELEGRAMMARK = "telegramState";

/// The values of the Telegram state.
Parameter TELEGRAMSTATES = "off,on,rejected";

/// Records the Telegram state: state is off, on or rejected, and botUserName is the bot's user name (letters, digits and underscores, at
/// most 64 characters) or empty. Both are written to the one mark telegramState. Any other value is an error status that names the
/// rule, and the mark is unchanged.
ClassMethod RecordTelegram(state As %String, botUserName As %String) As %Status
{
	Set state = $Get(state), botUserName = $Get(botUserName)
	If '$ListFind($ListFromString(..#TELEGRAMSTATES), state) {
		Quit $SYSTEM.Status.Error(5001, "The Telegram state is one of "_..#TELEGRAMSTATES)
	}
	If '$Match(botUserName, "^[A-Za-z0-9_]{0,64}$") {
		Quit $SYSTEM.Status.Error(5001, "The bot's user name is at most 64 letters, digits and underscores")
	}
	Quit ..Record(..#TELEGRAMMARK, {"state": (state), "botUserName": (botUserName)}.%ToJSON())
}

/// The Telegram state, off, on or rejected, and in botUserName the bot's user name. With no mark, or a mark that is not RecordTelegram's,
/// the state is off and the user name is empty.
ClassMethod TelegramState(Output botUserName As %String) As %String
{
	Set botUserName = ""
	Set state = "off"
	Try {
		Set value = ..Get(..#TELEGRAMMARK)
		If value '= "" {
			Set mark = {}.%FromJSON(value)
			If $ListFind($ListFromString(..#TELEGRAMSTATES), mark.state) {
				Set state = mark.state
				Set botUserName = $Select(mark.%GetTypeOf("botUserName") = "string": mark.botUserName, 1: "")
			}
		}
	} Catch {
		Set state = "off"
		Set botUserName = ""
	}
	Quit state
}

Storage Default
{
<Data name="StatusMarkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Mark</Value>
</Value>
<Value name="3">
<Value>Value</Value>
</Value>
<Value name="4">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.StatusMarkD</DataLocation>
<DefaultData>StatusMarkDefaultData</DefaultData>
<IdLocation>^OcuTalonP.StatusMarkD</IdLocation>
<IndexLocation>^OcuTalonP.StatusMarkI</IndexLocation>
<StreamLocation>^OcuTalonP.StatusMarkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
