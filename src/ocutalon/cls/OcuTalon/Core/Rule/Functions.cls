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

}
