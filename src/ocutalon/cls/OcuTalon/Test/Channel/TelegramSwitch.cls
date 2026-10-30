/// Tests of the Telegram install step (Story 12.1; AD-23, AD-14, AD-19). Nothing here starts or stops a production and nothing calls
/// Ens.Director: the tests pin the enable branch at the System Default Setting rows that a start reads, with the same
/// Ens.Config.DefaultSettings.%GetSetting call that OcuTalon.Install.Step.Production.Runners() uses. They run anywhere.
///   - TestApply: the four combinations of Included() and a token being set. The rows of TelegramIn and TelegramOut are 1 only for
///     (1, 1), the mark is off for the other three, and it is left as it was for (1, 1);
///   - TestRun: Run() reads the seam and the environment of the stack it runs in: both rows are 1 exactly when the seam is 1 and
///     TELEGRAM_BOT_TOKEN is not empty, and no row value, row description or status text holds the token;
///   - TestStructural: a row set to 1 by hand is 0 again after Run() with the seam at 0.
/// The two rows, the Telegram mark and the seam ^OcuTalonTest("TelegramIncluded") are saved before the tests and put back after them.
Class OcuTalon.Test.Channel.TelegramSwitch Extends %UnitTest.TestCase
{

/// The production and the items that the step switches.
Parameter PRODUCTION = "OcuTalon.Production";

/// The rows as found: for each item a list of (existed, value, description).
Property Found As %String [ MultiDimensional ];

/// The mark as found, "" when it had no row.
Property MarkFound As %String(MAXLEN = "");

/// The seam as found: $Data and its value.
Property SeamData As %Integer;

Property SeamValue As %String;

Method OnBeforeAllTests() As %Status
{
	For item = "TelegramIn", "TelegramOut" {
		Set id = ..RowId(item)
		If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
			Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
			Set ..Found(item) = $ListBuild(1, row.SettingValue, row.Description)
		} Else {
			Set ..Found(item) = $ListBuild(0, "", "")
		}
	}
	Set ..MarkFound = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK)
	Set ..SeamData = $Data(^OcuTalonTest("TelegramIncluded"))
	Set ..SeamValue = $Get(^OcuTalonTest("TelegramIncluded"))
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	For item = "TelegramIn", "TelegramOut" {
		Set found = ..Found(item)
		If $List(found, 1) {
			Do ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, item, "Enabled", $List(found, 2), $List(found, 3))
		} ElseIf ##class(Ens.Config.DefaultSettings).%ExistsId(..RowId(item)) {
			Do ##class(Ens.Config.DefaultSettings).%DeleteId(..RowId(item))
		}
	}
	Do ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK, ..MarkFound)
	If ..SeamData {
		Set ^OcuTalonTest("TelegramIncluded") = ..SeamValue
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
	Quit $$$OK
}

/// Every combination of Included() and a token being set: both rows, and the mark. The mark was on before each call.
Method TestApply()
{
	For included = 0, 1 {
		For tokenSet = 0, 1 {
			Set label = "Apply("_included_", "_tokenSet_")"
			Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
			Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Telegram).Apply(included, tokenSet), label_" succeeds")
			Set want = included && tokenSet
			Do $$$AssertEquals(..Resolved("TelegramIn"), want, label_": TelegramIn's row is "_want)
			Do $$$AssertEquals(..Resolved("TelegramOut"), want, label_": TelegramOut's row is "_want)
			Set state = ##class(OcuTalon.Data.StatusMark).TelegramState(.bot)
			If want {
				Do $$$AssertEquals(state_"|"_bot, "on|ocutalon_ci_bot", label_": the mark is left as it was")
			} Else {
				Do $$$AssertEquals(state_"|"_bot, "off|", label_": the mark is off")
				Do $$$AssertTrue(##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK) '= "", label_": the mark has a row")
			}
		}
	}
	Do ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK, "")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Telegram).Apply(0, 0), "Apply(0, 0) with no mark succeeds")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(), "off", "and records off")
	Do $$$AssertTrue(##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK) '= "", "as a row, so that the mark exists")
}

/// Run() with the seam at 0 and at 1, in the environment of this stack.
Method TestRun()
{
	Set token = $SYSTEM.Util.GetEnviron("TELEGRAM_BOT_TOKEN")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Telegram).TokenSet(), (token '= ""), "TokenSet() says whether the environment holds a token")
	For seam = 0, 1 {
		Set label = "Run() with the seam at "_seam
		Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(seam)
		Set status = ##class(OcuTalon.Install.Step.Telegram).Run()
		Do $$$AssertStatusOK(status, label_" succeeds")
		Set want = seam && (token '= "")
		Do $$$AssertEquals(..Resolved("TelegramIn"), want, label_": TelegramIn's row is "_want)
		Do $$$AssertEquals(..Resolved("TelegramOut"), want, label_": TelegramOut's row is "_want)
		Set leaked = 0
		If token '= "" {
			For item = "TelegramIn", "TelegramOut" {
				Set row = ##class(Ens.Config.DefaultSettings).%OpenId(..RowId(item))
				If $Find(row.SettingValue_"|"_row.Description_"|"_$SYSTEM.Status.GetErrorText(status), token) Set leaked = 1
			}
			If $Find(##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Data.StatusMark).#TELEGRAMMARK), token) Set leaked = 1
		}
		Do $$$AssertEquals(leaked, 0, label_": no row value, description, status text or mark holds the token")
	}
}

/// The rows are structural: a row set to 1 by hand is 0 again after Run() with the seam at 0.
Method TestStructural()
{
	Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(0)
	For item = "TelegramIn", "TelegramOut" {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, item, "Enabled", 1, "set by hand"), item_"'s row is set to 1 by hand")
		Do $$$AssertEquals(..Resolved(item), 1, item_"'s row holds 1")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Telegram).Run(), "Run() with the seam at 0 succeeds")
	For item = "TelegramIn", "TelegramOut" {
		Do $$$AssertEquals(..Resolved(item), 0, item_"'s row is 0 again")
	}
}

/// The id of an item's Enabled row.
ClassMethod RowId(item As %String) As %String [ Private ]
{
	Quit ..#PRODUCTION_"||"_item_"||*||Enabled"
}

/// The Enabled value that a start resolves for the item, as OcuTalon.Install.Step.Production.Runners() reads it, or "-" when no row exists.
ClassMethod Resolved(item As %String) As %String [ Private ]
{
	Set class = $Select(item = "TelegramIn": "OcuTalon.Channel.Telegram.In", 1: "OcuTalon.Channel.Telegram.Out")
	If '##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, item, class, "", "Enabled", .value) Quit "-"
	Quit value
}

}
