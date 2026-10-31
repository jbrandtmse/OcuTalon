/// The Telegram step (AD-23): the one switch of the Telegram items TelegramIn and TelegramOut. At every start it writes the System
/// Default Setting row Enabled of each item, through the one writer of OcuTalon.Install.Step.Production (the bridge's accessor):
/// 1 only when OcuTalon.Channel.Telegram.In.Included() returns 1 and TELEGRAM_BOT_TOKEN is not empty, and 0 otherwise. The rows are
/// structural (AD-19): the step rewrites them at every start, so a value set by hand in them does not last, and a token removed since the
/// last start leaves Telegram off at this one. A row overrides the Enabled flag of the production definition, which keeps false
/// (AD-3). The registry runs this step before Production, so the start reads the rows.
/// When the step leaves the items disabled it records the Telegram state off through OcuTalon.Data.StatusMark (AD-14). When it
/// enables them it leaves the mark alone: it belongs to TelegramIn.
/// It also writes the structural ApiBase row of both items at every start (Base): the value of OCUTALON_TELEGRAM_API_BASE, or the
/// public Bot API when the variable is empty, so that removing the override restores the default (AD-19).
/// The step reads only whether the token is present. It never stores, returns, logs or writes the token to a row, a description or a
/// status text (AD-14, AD-19). It prints no warning.
Class OcuTalon.Install.Step.Telegram Extends OcuTalon.Install.Step
{

/// The production of this installation.
Parameter PRODUCTION = "OcuTalon.Production";

/// The items that the step switches.
Parameter ITEMS = "TelegramIn,TelegramOut";

/// The environment variable that holds the bot token.
Parameter TOKENVAR = "TELEGRAM_BOT_TOKEN";

/// Switches the Telegram items from Included() and the environment, and writes their ApiBase rows from the environment: see the class.
/// The first failure is the status.
ClassMethod Run() As %Status
{
	Set sc = ..Apply(##class(OcuTalon.Channel.Telegram.In).Included(), ..TokenSet())
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..Base($SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR))
}

/// Writes the ApiBase row of both items: the value, or the public Bot API when it is empty. The rows are structural (AD-19): the step
/// writes them at every start. The first failure is the status.
ClassMethod Base(value As %String) As %Status
{
	Set value = $Get(value)
	Set base = $Select(value = "": ##class(OcuTalon.Channel.Telegram.Api).#PUBLICBASE, 1: value)
	Set description = "Written by the Telegram install step at every start from "_##class(OcuTalon.Channel.Telegram.Api).#BASEVAR_" (the public Bot API when it is empty); do not edit."
	Set sc = $$$OK
	For i = 1:1:$Length(..#ITEMS, ",") {
		Set sc = ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, $Piece(..#ITEMS, ",", i), "ApiBase", base, description)
		If $SYSTEM.Status.IsError(sc) Quit
	}
	Quit sc
}

/// 1 when TELEGRAM_BOT_TOKEN in the environment is not empty, and 0 otherwise. Nothing else is returned.
ClassMethod TokenSet() As %Boolean
{
	Quit $SYSTEM.Util.GetEnviron(..#TOKENVAR) '= ""
}

/// Writes the Enabled row of both items: 1 only when included and tokenSet are both 1, and 0 otherwise. On the disabled path it also
/// records the Telegram state off with no bot user name; on the enabled path the mark is left as it is. The first failure is the status.
ClassMethod Apply(included As %Boolean, tokenSet As %Boolean) As %Status
{
	Set enabled = $Select(included && tokenSet: 1, 1: 0)
	Set description = "Written by the Telegram install step at every start: 1 only when this release includes Telegram and TELEGRAM_BOT_TOKEN is set; do not edit."
	Set sc = $$$OK
	For i = 1:1:$Length(..#ITEMS, ",") {
		Set sc = ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, $Piece(..#ITEMS, ",", i), "Enabled", enabled, description)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit sc
	If 'enabled Quit ##class(OcuTalon.Data.StatusMark).RecordTelegram("off", "")
	Quit $$$OK
}

}
