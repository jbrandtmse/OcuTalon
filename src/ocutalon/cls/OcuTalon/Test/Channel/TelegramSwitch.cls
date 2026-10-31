/// Tests of the Telegram install step (Story 12.1; AD-23, AD-14, AD-19). Nothing here starts or stops a production and nothing calls
/// Ens.Director: the tests pin the enable branch at the System Default Setting rows that a start reads, with the same
/// Ens.Config.DefaultSettings.%GetSetting call that OcuTalon.Install.Step.Production.Runners() uses. They run anywhere.
///   - TestApply: the four combinations of Included() and a token being set. The rows of TelegramIn and TelegramOut are 1 only for
///     (1, 1), the mark is off for the other three, and it is left as it was for (1, 1);
///   - TestRun: Run() reads the seam and the environment of the stack it runs in: both rows are 1 exactly when the seam is 1 and
///     TELEGRAM_BOT_TOKEN is not empty, and no row value, row description or status text holds the token;
///   - TestStructural: a row set to 1 by hand is 0 again after Run() with the seam at 0;
///   - TestRowDescription: each row's description says that the step writes it at every start, from the release and the token variable;
///   - TestPrintsNothing: Apply() and Run() write nothing to the current device (no WARN line, no user-facing text); a probe shows
///     that the capture sees output.
/// The two Enabled rows, the two ApiBase rows (Run() writes them from Story 12.2 on), the Telegram mark and the seam
/// ^OcuTalonTest("TelegramIncluded") are saved before the tests and put back after them.
Class OcuTalon.Test.Channel.TelegramSwitch Extends %UnitTest.TestCase
{

/// The production and the items that the step switches.
Parameter PRODUCTION = "OcuTalon.Production";

/// The rows as found: for each item and setting (Enabled, ApiBase) a list of (existed, value, description).
Property Found As %String [ MultiDimensional ];

/// The mark as found, "" when it had no row.
Property MarkFound As %String(MAXLEN = "");

/// The seam as found: $Data and its value.
Property SeamData As %Integer;

Property SeamValue As %String;

Method OnBeforeAllTests() As %Status
{
	For item = "TelegramIn", "TelegramOut" {
		For setting = "Enabled", "ApiBase" {
			Set id = ..RowId(item, setting)
			If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
				Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
				Set ..Found(item, setting) = $ListBuild(1, row.SettingValue, row.Description)
			} Else {
				Set ..Found(item, setting) = $ListBuild(0, "", "")
			}
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
		For setting = "Enabled", "ApiBase" {
			Set found = ..Found(item, setting)
			If $List(found, 1) {
				Do ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, item, setting, $List(found, 2), $List(found, 3))
			} ElseIf ##class(Ens.Config.DefaultSettings).%ExistsId(..RowId(item, setting)) {
				Do ##class(Ens.Config.DefaultSettings).%DeleteId(..RowId(item, setting))
			}
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
		Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
		Set status = ##class(OcuTalon.Install.Step.Telegram).Run()
		Do $$$AssertStatusOK(status, label_" succeeds")
		Set want = seam && (token '= "")
		Do $$$AssertEquals(..Resolved("TelegramIn"), want, label_": TelegramIn's row is "_want)
		Do $$$AssertEquals(..Resolved("TelegramOut"), want, label_": TelegramOut's row is "_want)
		Set state = ##class(OcuTalon.Data.StatusMark).TelegramState(.bot)
		Do $$$AssertEquals(state_"|"_bot, $Select(want: "on|ocutalon_ci_bot", 1: "off|"), label_": the mark is "_$Select(want: "left as it was", 1: "off"))
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

/// Each row's description is an admin note: it says that the step writes the row at every start, from the release and from the
/// token variable (by name; the value is never read into it). Checked on the enabled and the disabled path.
Method TestRowDescription()
{
	For included = 0, 1 {
		Set label = "Apply("_included_", "_included_")"
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Telegram).Apply(included, included), label_" succeeds")
		For item = "TelegramIn", "TelegramOut" {
			Set description = ##class(Ens.Config.DefaultSettings).%OpenId(..RowId(item)).Description
			Do $$$AssertTrue($Find(description, "every start") > 0, label_": "_item_"'s description says that the step writes the row at every start")
			Do $$$AssertTrue($Find(description, "TELEGRAM_BOT_TOKEN") > 0, label_": "_item_"'s description names the token variable")
		}
	}
}

/// The step prints no WARN line and no user-facing text: Apply() on both paths and Run() with the seam at 0 and at 1 write nothing.
Method TestPrintsNothing()
{
	Do $$$AssertEquals(..Printed("Write ""probe"""), "probe", "the capture sees what is written to the current device")
	Do $$$AssertEquals(..Printed("Do ##class(OcuTalon.Install.Step.Telegram).Apply(0, 0)"), "", "Apply(0, 0) prints nothing")
	Do $$$AssertEquals(..Printed("Do ##class(OcuTalon.Install.Step.Telegram).Apply(1, 1)"), "", "Apply(1, 1) prints nothing")
	For seam = 0, 1 {
		Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(seam)
		Do $$$AssertEquals(..Printed("Do ##class(OcuTalon.Install.Step.Telegram).Run()"), "", "Run() with the seam at "_seam_" prints nothing")
	}
}

/// What the code writes to the current device, captured through a temporary file; the device is restored whatever happens.
ClassMethod Printed(code As %String) As %String [ Private ]
{
	Set file = ##class(%File).TempFilename("txt"), original = $IO, text = "", opened = 0
	Try {
		Open file:"NWS":5
		If $Test {
			Set opened = 1
			Use file
			Xecute code
			Use original
			Close file
			Set opened = 0
			Set stream = ##class(%Stream.FileCharacter).%New()
			Do stream.LinkToFile(file)
			Set text = stream.Read(32000)
			Kill stream
		} Else {
			Set text = "capture file not opened"
		}
	} Catch ex {
		Use original
		If opened Close file
		Set text = "capture failed: "_ex.DisplayString()
	}
	Do ##class(%File).Delete(file)
	Quit text
}

/// The id of an item's row of the setting (Enabled by default).
ClassMethod RowId(item As %String, setting As %String = "Enabled") As %String [ Private ]
{
	Quit ..#PRODUCTION_"||"_item_"||*||"_setting
}

/// The Enabled value that a start resolves for the item, as OcuTalon.Install.Step.Production.Runners() reads it, or "-" when no row exists.
ClassMethod Resolved(item As %String) As %String [ Private ]
{
	Set class = $Select(item = "TelegramIn": "OcuTalon.Channel.Telegram.In", 1: "OcuTalon.Channel.Telegram.Out")
	If '##class(Ens.Config.DefaultSettings).%GetSetting(..#PRODUCTION, item, class, "", "Enabled", .value) Quit "-"
	Quit value
}

}
