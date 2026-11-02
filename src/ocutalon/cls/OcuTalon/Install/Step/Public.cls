/// The Public step: the public settings and the online demo's budget rows, written at every start (AD-19, AD-23).
///   - Run() clears readiness first (Settings.ClearReady), so readiness stays cleared on both entry points, the after-start script and
///     Registry.Run("ipm"), until Ready().
///   - The online demo (OCUTALON_ONLINE_DEMO is exactly 1): the start values of VARIABLES are read with $SYSTEM.Util.GetEnviron, a variable
///     that is set but empty counting as unset, and all of them are checked before anything is written. A value that is not accepted
///     refuses the step with an error that names the variable and the rule, never the value, and nothing is written. Then onlineDemo 1 and
///     the twelve other public keys are written through OcuTalon.Data.Public.Settings (the value, the default, or "" which removes the
///     key), and the three budget settings of Decide (DailyCostCapUSD, GatewaySpendUSD, GatewaySpendDate) are written as System Default
///     Settings rows of OcuTalon.Production. Every key and row is rewritten at every start (structural, AD-19).
///   - Any other value of the flag is a local install: onlineDemo 0 and no other public key. No gateway row is written, and the
///     DailyCostCapUSD row is seeded with 0 (off) only when no System Default Settings row of any specificity resolves it, because
///     OcuTalon.Core.SettingsOps owns an existing row from step 2.
///   - Ready() pins the page size of both public accounts (Users.PinTrace; OCUORDERS can come after the Users step, DW-160) and then
///     sets readiness, last in a start.
/// The public keys are read and written only through OcuTalon.Data.Public.Settings. The bridge is not changed: it reads the three rows
/// through its own accessor.
Class OcuTalon.Install.Step.Public Extends OcuTalon.Install.Step
{

/// The online-demo flag's variable.
Parameter FLAG = "OCUTALON_ONLINE_DEMO";

/// Each start variable and where it goes: a public key (public:<key>) or a setting of the Decide item (decide:<setting>).
Parameter VARIABLES = "OCUTALON_DEMO_USER=public:demoUser,OCUTALON_DEMO_PASSWORD=public:demoPassword,OCUTALON_READONLY_USER=public:readonlyUser,OCUTALON_READONLY_PASSWORD=public:readonlyPassword,OCUTALON_RESET_INTERVAL_HOURS=public:resetIntervalHours,OCUTALON_RESET_ANCHOR=public:resetAnchor,OCUTALON_LAST_RESET=public:lastReset,OCUTALON_LAST_RESET_KIND=public:lastResetKind,OCUTALON_PROXY_ADDRESS=public:proxyAddress,OCUTALON_CONNECTION_CAP=public:connectionCap,OCUTALON_CONNECTION_RESERVE=public:connectionReserve,OCUTALON_MESSAGE_ALLOWANCE=public:messageAllowance,OCUTALON_DAILY_COST_CAP_USD=decide:DailyCostCapUSD,OCUTALON_GATEWAY_SPEND_USD=decide:GatewaySpendUSD,OCUTALON_GATEWAY_SPEND_DATE=decide:GatewaySpendDate";

/// The production whose Decide item takes the budget rows.
Parameter PRODUCTION = "OcuTalon.Production";

/// The business host of the budget rows.
Parameter ITEM = "Decide";

/// The host class of the item, which the seed check resolves the setting against.
Parameter HOSTCLASS = "OcuTalon.Bridge.Process.Decide";

/// The daily cost cap that a flag-on start uses when the variable is unset, in US dollars.
Parameter DEFAULTCAP = 20;

/// Clears readiness, then writes the flag and, by the flag, the other keys and rows (the class comment).
ClassMethod Run() As %Status
{
	Set sc = ##class(OcuTalon.Data.Public.Settings).ClearReady()
	If $$$ISERR(sc) Quit sc
	If $SYSTEM.Util.GetEnviron(..#FLAG) '= "1" Quit ..RunLocal()
	Set sc = ..StartValues(.values)
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	If $$$ISERR(sc) Quit sc
	Set position = 0
	Set pairs = $ListFromString(..#VARIABLES)
	While $ListNext(pairs, position, pair) {
		Set variable = $Piece(pair, "=", 1)
		Set target = $Piece(pair, "=", 2)
		Set name = $Piece(target, ":", 2)
		If $Piece(target, ":", 1) = "public" {
			Set sc = ##class(OcuTalon.Data.Public.Settings).Set(name, values(variable))
		} Else {
			Set sc = ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, ..#ITEM, name, values(variable), "Written by the Public install step at every start from "_variable_"; do not edit.")
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// A local install: the flag 0 and nothing else of the public keys, no gateway row, and the seed of the cap.
ClassMethod RunLocal() As %Status [ Private ]
{
	Set sc = ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	If $$$ISERR(sc) Quit sc
	If ##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, ..#ITEM, ..#HOSTCLASS, "Host", "DailyCostCapUSD") Quit sc
	Quit ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, ..#ITEM, "DailyCostCapUSD", 0, "Seeded by the Public install step with 0 (off) on a local install; the settings page owns it from then on.")
}

/// The last step of a start: with the flag on, pins the page size of the two public accounts, then stores readiness. A pin that fails
/// fails the step and readiness stays cleared.
ClassMethod Ready() As %Status
{
	Set flag = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo", .sc)
	If $$$ISERR(sc) Quit sc
	If flag = 1 {
		For key = "demoUser", "readonlyUser" {
			Set name = ##class(OcuTalon.Data.Public.Settings).Get(key, .sc)
			If $$$ISERR(sc) Quit
			If name = "" Continue
			Set sc = ##class(OcuTalon.Install.Step.Users).PinTrace(name)
			If $$$ISERR(sc) Quit
		}
		If $$$ISERR(sc) Quit sc
	}
	Quit ##class(OcuTalon.Data.Public.Settings).SetReady()
}

/// Reads every start variable, applies its default when it is unset or empty, and checks it. values(variable) is the value to write
/// ("" for none). The first value that is not accepted gives the error, naming the variable and the rule, and nothing is written.
ClassMethod StartValues(Output values) As %Status [ Private ]
{
	Kill values
	Set position = 0
	Set pairs = $ListFromString(..#VARIABLES)
	While $ListNext(pairs, position, pair) {
		Set variable = $Piece(pair, "=", 1)
		Set value = $SYSTEM.Util.GetEnviron(variable)
		If value = "" Set value = ..Default(variable)
		Set values(variable) = value
		Set rule = ..Rule(variable)
		If '..Accepts(rule, value) Quit
		Set rule = ""
	}
	If rule '= "" Quit ..Refuse(variable, ..RuleText(rule))
	If +values("OCUTALON_CONNECTION_RESERVE") '< +values("OCUTALON_CONNECTION_CAP") Quit ..Refuse("OCUTALON_CONNECTION_RESERVE", ..RuleText("reserve"))
	Quit $SYSTEM.Status.OK()
}

/// The value of a variable that is unset or empty.
ClassMethod Default(variable As %String) As %String [ Private ]
{
	Quit $Case(variable, "OCUTALON_RESET_INTERVAL_HOURS": 4, "OCUTALON_CONNECTION_CAP": 8, "OCUTALON_CONNECTION_RESERVE": 2, "OCUTALON_MESSAGE_ALLOWANCE": 50, "OCUTALON_DAILY_COST_CAP_USD": ..#DEFAULTCAP, : "")
}

/// The rule of a variable: text (anything), above0, whole1, whole0, time, kind, money or date.
ClassMethod Rule(variable As %String) As %String [ Private ]
{
	Quit $Case(variable, "OCUTALON_RESET_INTERVAL_HOURS": "above0", "OCUTALON_RESET_ANCHOR": "time", "OCUTALON_LAST_RESET": "time", "OCUTALON_LAST_RESET_KIND": "kind", "OCUTALON_CONNECTION_CAP": "whole1", "OCUTALON_MESSAGE_ALLOWANCE": "whole1", "OCUTALON_CONNECTION_RESERVE": "whole0", "OCUTALON_DAILY_COST_CAP_USD": "money", "OCUTALON_GATEWAY_SPEND_USD": "money", "OCUTALON_GATEWAY_SPEND_DATE": "date", : "text")
}

/// 1 when the value meets the rule. An empty value is accepted by the rules of the variables that have no default.
ClassMethod Accepts(rule As %String, value As %String) As %Boolean [ Private ]
{
	If (value = "") && ((rule = "text") || (rule = "time") || (rule = "kind") || (rule = "money") || (rule = "date")) Quit 1
	If rule = "text" Quit 1
	If rule = "above0" Quit $IsValidNum(value) && (value > 0)
	If rule = "whole1" Quit (value ? 1.N) && (value > 0)
	If rule = "whole0" Quit (value ? 1.N)
	If rule = "time" Quit (value ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z") && ($ZDateTimeH($Translate($Extract(value, 1, 19), "T", " "), 3, 1, , , , , , , "") '= "")
	If rule = "kind" Quit (value = "scheduled") || (value = "unscheduled")
	If rule = "money" Quit $IsValidNum(value, "", 0)
	If rule = "date" Quit (value ? 4N1"-"2N1"-"2N) && ($ZDateH(value, 3, , , , , , , "") '= "")
	Quit 0
}

/// The rule as a sentence for the error text; reserve is the check of the reserve against the cap.
ClassMethod RuleText(rule As %String) As %String [ Private ]
{
	Quit $Case(rule, "above0": "must be a number above 0", "whole1": "must be a whole number of 1 or more", "whole0": "must be a whole number of 0 or more", "reserve": "must be below OCUTALON_CONNECTION_CAP", "time": "must be empty or a UTC time, YYYY-MM-DDThh:mm:ssZ, that names a real time", "kind": "must be empty, scheduled or unscheduled", "money": "must be empty or a number of 0 or more", "date": "must be empty or an existing date, YYYY-MM-DD", : "is not accepted")
}

/// The refusal of the step, naming the variable and the rule.
ClassMethod Refuse(variable As %String, text As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, $ClassName()_": "_variable_" "_text)
}

}
