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

/// 1 when Slack is on (Channel.Slack.In.On) and the session has a Data.SlackLink row, read by the session's Ref. Any error gives 0.
ClassMethod SlackLinked(sessionRef As %String) As %Boolean
{
	Try {
		Set linked = 0
		If ($Get(sessionRef) '= "") && ##class(OcuTalon.Channel.Slack.In).On() {
			Set linked = ''##class(OcuTalon.Data.SlackLink).SessionRefIndexExists(sessionRef)
		}
	} Catch exception {
		Set linked = 0
	}
	Quit linked
}

/// 1 when digest.channels names the channel (web, phone, telegram or email): the setting's comma-separated names, each trimmed and lowercased,
/// or SettingsOps' declared default when the setting has no row. A name that is not one of the four never counts, and neither does an
/// empty channel. Any error gives 0.
ClassMethod DigestNamed(channel As %String) As %Boolean
{
	Try {
		Set wanted = $ZConvert($ZStrip($Get(channel), "<>W"), "L")
		Set named = 0
		If $ListFind($ListBuild("web", "phone", "telegram", "email"), wanted) {
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

/// 1 when a digest of the session goes by email (Story 21.7): not the online demo, digest.channels names email, the session is the mailbox owner
/// (the product key email.owner), email.address is an address and EmailOut has an alive job. email.owner and email.address are read from their rows, never
/// the cache; digest.channels and onlineDemo through Data.Setting.Get, as the other functions of Notify read them. Any error gives 0. The recipient is not decided here: EmailOut works it out itself from email.address.
ClassMethod DigestEmail(sessionRef As %String) As %Boolean
{
	Try {
		Set yes = 0
		Set sessionRef = $Get(sessionRef)
		If (sessionRef '= "") && (##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1) && ..DigestNamed("email") {
			If (sessionRef = ##class(OcuTalon.Data.Setting).Fresh("email.owner")) && ##class(OcuTalon.Core.SettingsOps).IsAddress(##class(OcuTalon.Data.Setting).Fresh("email.address")) {
				Set yes = ''##class(OcuTalon.Core.CommandsIn).ItemRunning("EmailOut")
			}
		}
	} Catch exception {
		Set yes = 0
	}
	Quit yes
}

/// 1 when the Data.Page row that decisionRef names (its Ref exactly) exists and sessionRef is a session (IsSession): the page of a user, which always gets a web chat card
/// in that session (Story 24.3a). 0 for a Ref with no row, a person given only as an address (SessionRef instance), the online demo and any error.
ClassMethod PageWeb(decisionRef As %String, sessionRef As %String) As %Boolean
{
	Try {
		Set yes = 0
		If (##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1) && ..IsSession($Get(sessionRef)) {
			Set yes = ''$IsObject(..PageRow($Get(decisionRef)))
		}
	} Catch exception {
		Set yes = 0
	}
	Quit yes
}

/// 1 when the Data.Page row that decisionRef names exists and its Channels names the channel (telegram or email; the list is a comma list, each name trimmed and lowercased).
/// 0 for a Ref with no row, any other channel, the online demo and any error. The row is read by object access.
ClassMethod PageChannel(decisionRef As %String, channel As %String) As %Boolean
{
	Try {
		Set yes = 0
		Set wanted = $ZConvert($ZStrip($Get(channel), "<>W"), "L")
		If (wanted '= "") && (##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1) {
			Set page = ..PageRow($Get(decisionRef))
			If $IsObject(page) {
				For i = 1:1:$Length(page.Channels, ",") {
					If $ZConvert($ZStrip($Piece(page.Channels, ",", i), "<>W"), "L") = wanted Set yes = 1
				}
			}
		}
	} Catch exception {
		Set yes = 0
	}
	Quit yes
}

/// 1 when a page goes by email (Story 24.3a): not the online demo, the Data.Page row of decisionRef names email in its Channels (PageChannel) and EmailOut has an alive job.
/// The recipient is not decided here: EmailOut works it out itself from the role's on-call key. Any error gives 0.
ClassMethod PageEmail(decisionRef As %String) As %Boolean
{
	Try {
		Set yes = 0
		If (##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1) && ..PageChannel($Get(decisionRef), "email") Set yes = ''##class(OcuTalon.Core.CommandsIn).ItemRunning("EmailOut")
	} Catch exception {
		Set yes = 0
	}
	Quit yes
}

/// The Data.Page row whose Ref is exactly ref, or "".
ClassMethod PageRow(ref As %String) As OcuTalon.Data.Page [ Private ]
{
	If ref = "" Quit ""
	Set page = ##class(OcuTalon.Data.Page).RefIndexOpen(ref)
	Quit $Select($IsObject(page) && (page.Ref = ref): page, 1: "")
}

/// The channels a digest of the session goes to, as a list in the order web, phone, telegram, email: the ones that digest.channels names and that are
/// available to the session, which are the channels that Notify's rule for kind digest sends it to. The list is empty when none holds. Any error gives
/// the channels found so far.
ClassMethod DigestChannels(sessionRef As %String) As %List
{
	Set channels = ""
	Try {
		If ..DigestNamed("web") Set channels = channels_$ListBuild("web")
		If ..DemoOn() && ..DigestNamed("phone") Set channels = channels_$ListBuild("phone")
		If ..TelegramPaired(sessionRef) && ..DigestNamed("telegram") Set channels = channels_$ListBuild("telegram")
		If ..DigestEmail(sessionRef) Set channels = channels_$ListBuild("email")
	} Catch exception {
	}
	Quit channels
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
