/// The functions of OcuTalon's routing rules (AD-4, AD-14, AD-30, AD-32), for the conditions of OcuTalon.Core.Rule.Outcome and
/// OcuTalon.Core.Rule.Notify. The function names are unique across every Ens.Rule.FunctionSet, so no other function set may
/// use them. Each function answers 0 or 1 and never throws.
Class OcuTalon.Core.Rule.Functions Extends Ens.Rule.FunctionSet
{

/// 1 when ref is the Ref of a session that has a Session row; 0 for the owners instance and eval, an empty Ref and an unknown one.
ClassMethod IsSession(ref As %String) As %Boolean
{
	Try {
		Set session = ($Get(ref) '= "") && ($ListLength(##class(OcuTalon.Data.Session).Recipients(ref)) = 1)
	} Catch exception {
		Set session = 0
	}
	Quit session
}

/// 1 when demo mode is on: the demo.mode setting is "1" (Install.Step.Demo).
ClassMethod DemoOn() As %Boolean
{
	Try {
		Set on = (##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1")
	} Catch exception {
		Set on = 0
	}
	Quit on
}

/// 1 when this release includes Telegram (Channel.Telegram.In.Included).
ClassMethod TelegramOn() As %Boolean
{
	Quit ''##class(OcuTalon.Channel.Telegram.In).Included()
}

/// 1 when Telegram is included and the session has a Pairing row, read through Ownership.
ClassMethod TelegramPaired(sessionRef As %String) As %Boolean
{
	Try {
		Set paired = 0
		If ..TelegramOn() && ($Get(sessionRef) '= "") {
			Set paired = $IsObject(##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc))
		}
	} Catch exception {
		Set paired = 0
	}
	Quit paired
}

/// 1 when digest.channels names the channel (web, phone or telegram): the setting's comma-separated names, each trimmed and lowercased,
/// or SettingsOps' declared default when the setting has no row. A name that is not one of the three never counts, and neither does an
/// empty channel. Any error gives 0.
ClassMethod DigestNamed(channel As %String) As %Boolean
{
	Try {
		Set wanted = $ZConvert($ZStrip($Get(channel), "<>W"), "L")
		Set named = 0
		If $ListFind($ListBuild("web", "phone", "telegram"), wanted) {
			Set default = ##class(OcuTalon.Core.SettingsOps).Section("daily-digest")
			Set value = ##class(OcuTalon.Data.Setting).Get("digest.channels", $Select($IsObject(default): ..ChannelsDefault(default), 1: ""))
			For i = 1:1:$Length(value, ",") {
				If $ZConvert($ZStrip($Piece(value, ",", i), "<>W"), "L") = wanted Set named = 1
			}
		}
	} Catch exception {
		Set named = 0
	}
	Quit named
}

/// The declared default of the channels field of the daily-digest section.
ClassMethod ChannelsDefault(section As %DynamicObject) As %String [ Private ]
{
	Set default = ""
	Set fields = section.fields.%GetIterator()
	While fields.%GetNext(, .field) {
		If field.name = "channels" Set default = field.default
	}
	Quit default
}

}
