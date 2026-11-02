/// SettingsOps, the business operation that carries out the settings commands SetDemoMode, SetPersona and ProposePersona (AD-1,
/// AD-19). It is the only run-time writer of OcuTalon.Data.Setting, and it writes only the keys of ALLOWLIST and the per-person keys
/// of PERSONKEYS. For every accepted SetDemoMode it:
///   - writes the Settings audit entry first (AD-17), through Bridge.Audit.Record, so that no change is unaudited and the entry has the
///     one shape of its type;
///   - then writes the value of demo.mode, "1" or "0";
///   - then runs OcuTalon.Install.Step.Demo.Run() (AD-23), which creates or removes the demo namespace, and takes the step's
///     warnings.
/// For every accepted SetPersona (origin web_user, the session's own persona) it checks that the session has a row, validates the
/// values (PersonaProblem), writes the Settings audit entry first (setting persona, from and to in the form of AuditForm: the preset id
/// or the language name, never the custom text), then writes person.<SessionRef>.persona.preset, .language and .custom in one
/// transaction. A value that the chosen preset does not use is neither validated nor stored: its key is written empty. ProposePersona
/// (origin tool) checks the session, the online-demo flag and the values like SetPersona and writes and audits nothing.
/// It answers every command with a CommandResult (Ok, Outcome and Message) and never an error status. The outcomes:
///   - on, off: carried out; off_kept: off, and the step kept an OCUORDERS that is not its own (Ok 1);
///   - step_failed: the value is written and the step failed; the next start runs the step again (Ok 0);
///   - saved: the persona is saved (Ok 1; Data holds the saved preset, language and custom as JSON);
///   - bad_preset, bad_language, bad_custom, custom_not_offered (the online demo offers presets and a language only): the values are
///     refused and nothing was written (Ok 0);
///   - no_session: the command's session has no row (Ok 0);
///   - not_audited: the audit entry could not be written, so nothing was written (Ok 0);
///   - not_available: ProposePersona on the online demo; not_built: ProposePersona with valid values, which is not built yet (Ok 0);
///   - unknown_command: a command class that this operation does not carry out (Ok 0);
///   - failed: an error was thrown, or a value could not be saved; a persona write that fails changes no key (Ok 0).
/// Persona(sessionRef) reads a person's values from their rows, ForgetPerson(sessionRef) deletes every per-person key of a session
/// (SessionOps.End calls it), and PersonaKey names a persona key. A written value applies to other processes when their 60-second
/// Setting cache entries expire.
Class OcuTalon.Core.SettingsOps Extends Ens.BusinessOperation
{

/// The setting keys that this operation writes, comma-separated.
Parameter ALLOWLIST = "demo.mode";

/// The per-person setting keys that this operation writes, comma-separated: person.<SessionRef>. followed by one of these (AD-19).
Parameter PERSONKEYS = "persona.preset,persona.language,persona.custom";

/// The Message of the persona answers.
Parameter MESSAGESAVED = "Saved. Applies from your next message. Recorded in the audit log.";

Parameter MESSAGEBADLANGUAGE = "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters.";

Parameter MESSAGEBADCUSTOM = "Use up to 1,000 characters, without {{ or @{.";

Parameter MESSAGECUSTOMNOTOFFERED = "On the online demo you can choose a preset or a language. Your choice lasts for this visit.";

Parameter MESSAGENOTSAVED = "Couldn't save. Nothing was changed.";

/// The audit event data's channel for each origin: system is the terminal, web_admin the web page.
Parameter CHANNELS = "system:system,web_admin:web,web_user:web";

/// The Message of an answer. {v} is on or off, and {error} the plain text of an error.
Parameter MESSAGEON = "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change.";

Parameter MESSAGEOFF = "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change.";

Parameter MESSAGEKEPT = "Demo mode is off. {how} Reload the OcuTalon page in a minute to see the change.";

Parameter MESSAGESTEPFAILED = "Demo mode is set to {v}, but the Demo step failed: {error}. OcuTalon runs the step again at its next start.";

Parameter MESSAGENOTAUDITED = "OcuTalon couldn't write the audit entry, so demo mode was not changed.";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Try {
		Set pResponse = ..Carry($Get(pRequest))
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pResponse = ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// Carries out the command and returns the CommandResult to answer.
Method Carry(command As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set class = $Select($IsObject(command): $ClassName(command), 1: "")
	If class = "OcuTalon.Msg.Command.SetDemoMode" Quit ..SwitchDemo(command)
	If class = "OcuTalon.Msg.Command.SetPersona" Quit ..SavePersona(command)
	If class = "OcuTalon.Msg.Command.ProposePersona" Quit ..Propose(command)
	Quit ..Result(0, "unknown_command", ##class(OcuTalon.Core.CommandsIn).#MESSAGEUNKNOWN)
}

/// Carries out a SetDemoMode and returns the CommandResult to answer.
Method SwitchDemo(command As OcuTalon.Msg.Command.SetDemoMode) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set key = ##class(OcuTalon.Install.Step.Demo).#MODEKEY
	Set value = $Select(command.DemoMode: "1", 1: "0")
	Set word = $Select(command.DemoMode: "on", 1: "off")
	Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, key, ..Stored(key), value))
	If $$$ISERR(sc) {
		Set text = $SYSTEM.Status.GetErrorText(sc)
		$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
		Quit ..Result(0, "not_audited", ..#MESSAGENOTAUDITED)
	}
	Set sc = ..Apply(key, value)
	If $$$ISERR(sc) {
		$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set sc = ..RunStep(.kept, .warnings)
	If $$$ISERR(sc) {
		Set text = ##class(OcuTalon.Core.Admin).ErrorText(sc)
		$$$LOGERROR("The Demo step failed: "_text)
		Quit ..Result(0, "step_failed", $Replace($Replace(..#MESSAGESTEPFAILED, "{v}", word), "{error}", text))
	}
	If (word = "off") && (kept '= "") Quit ..Result(1, "off_kept", $Replace(..#MESSAGEKEPT, "{how}", kept))
	Quit ..Result(1, word, $Select(word = "on": ..#MESSAGEON, 1: ..#MESSAGEOFF))
}

/// The audit event data of a change, in the shape of the Settings type (Bridge.Audit.Record): setting, from (the stored value before
/// the write, "" when the row is absent), to, irisUser, sessionRef (possibly empty) and channel (where the command came from, by its
/// origin; "" for an origin that is not in CHANNELS, which Record refuses). Every member is typed as a JSON string, as
/// Record requires (a value such as "1" would otherwise become a number). Record redacts and describes it.
ClassMethod AuditData(origin As %String, irisUser As %String, sessionRef As %String, setting As %String, from As %String, to As %String) As %DynamicObject [ Private ]
{
	Set channel = $Piece($Piece(","_..#CHANNELS, ","_origin_":", 2), ",", 1)
	Set data = {}
	Do data.%Set("setting", setting, "string")
	Do data.%Set("from", from, "string")
	Do data.%Set("to", to, "string")
	Do data.%Set("irisUser", irisUser, "string")
	Do data.%Set("sessionRef", sessionRef, "string")
	Do data.%Set("channel", channel, "string")
	Quit data
}

/// The value stored for the key right now, read from its row and never from the per-process cache, or "" when the row is absent.
ClassMethod Stored(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The one audit write of the class: an entry of type Settings, through the one writer of product code. A test subclass overrides it.
Method WriteAudit(data As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Settings", data)
}

/// The guarded write: the value of the key, only when the key is on ALLOWLIST or is person.<Ref>.<one of PERSONKEYS>; any other
/// key is an error status and no row is written.
ClassMethod Apply(key As %String, value As %String) As %Status [ Private ]
{
	If '$ListFind($ListFromString(..#ALLOWLIST), key) && '..IsPersonKey(key) Quit $SYSTEM.Status.Error(5001, "Setting '"_key_"' is not on the list of settings that can be changed here")
	Quit ##class(OcuTalon.Data.Setting).Set(key, value)
}

/// Runs the Demo step and takes its warnings. kept is the "how" sentence of the demoKept mark when the step kept an OCUORDERS
/// that it did not create, and "" otherwise. An error thrown by the step is its error status.
Method RunStep(Output kept As %String, Output warnings As %List) As %Status [ Private ]
{
	Set kept = "", warnings = ""
	Try {
		Set sc = ..RunDemo()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set warnings = ##class(OcuTalon.Install.Step).TakeWarnings()
	Set position = 0
	While $ListNext(warnings, position, line) {
		$$$LOGWARNING(line)
	}
	If $$$ISOK(sc) Set kept = ..Kept()
	Quit sc
}

/// The one call of the Demo step. A test subclass overrides it.
Method RunDemo() As %Status [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Demo).Run()
}

/// The "how" sentence of the demoKept mark, or "" when the mark is not set.
ClassMethod Kept() As %String [ Private ]
{
	Set note = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Install.Step.Demo).#KEPTMARK)
	If note = "" Quit ""
	Quit {}.%FromJSON(note).how
}

/// Carries out a SetPersona and returns the CommandResult to answer (see the class description). The audit entry is written before
/// the keys, and the three keys are written in one transaction: a failed write rolls all of them back.
Method SavePersona(command As OcuTalon.Msg.Command.SetPersona) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sessionRef = command.SessionRef
	If '..HasSession(sessionRef, .irisUser) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	Set preset = command.Preset
	Set language = $Select(preset = "language": command.Language, 1: "")
	Set custom = $Select(preset = "custom": command.Custom, 1: "")
	Set message = ..PersonaProblem(preset, language, custom, ..OnlineDemo(), .outcome)
	If message '= "" Quit ..Result(0, outcome, message)
	Set from = ..AuditForm(..Stored(..PersonaKey(sessionRef, "preset")), ..Stored(..PersonaKey(sessionRef, "language")))
	Set sc = ..WriteAudit(..AuditData(command.Origin, irisUser, sessionRef, "persona", from, ..AuditForm(preset, language)))
	If $$$ISERR(sc) {
		$$$LOGERROR("The Settings audit entry could not be written"_$Select($SYSTEM.Status.GetErrorText(sc) = "": "", 1: ": "_$SYSTEM.Status.GetErrorText(sc)))
		Quit ..Result(0, "not_audited", ..#MESSAGENOTSAVED)
	}
	Set values = $ListBuild(preset, language, custom)
	Set level = $TLevel
	TSTART
	Try {
		Set names = $ListFromString("preset,language,custom")
		For i = 1:1:3 {
			Set sc = ..Apply(..PersonaKey(sessionRef, $List(names, i)), $List(values, i))
			If $$$ISERR(sc) Quit
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		If $TLevel > level TROLLBACK 1
		$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
		Quit ..Result(0, "failed", ..#MESSAGENOTSAVED)
	}
	TCOMMIT
	Set data = {}
	Do data.%Set("preset", preset, "string")
	Do data.%Set("language", language, "string")
	Do data.%Set("custom", custom, "string")
	Quit ..Result(1, "saved", ..#MESSAGESAVED, data.%ToJSON())
}

/// Carries out a ProposePersona and returns the CommandResult to answer: the session check, the online-demo refusal and the
/// values' validation of SetPersona, then not_built. Nothing is written or audited.
Method Propose(command As OcuTalon.Msg.Command.ProposePersona) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..HasSession(command.SessionRef) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	If ..OnlineDemo() Quit ..Result(0, "not_available", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED)
	Set preset = command.Preset
	Set message = ..PersonaProblem(preset, $Select(preset = "language": command.Language, 1: ""), $Select(preset = "custom": command.Custom, 1: ""), 0, .outcome)
	If message '= "" Quit ..Result(0, outcome, message)
	Quit ..Result(0, "not_built", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTBUILT)
}

/// 1 when the session has a Session row; irisUser is then the row's IRIS user, else the user of this job (the rule of
/// SessionOps.IrisUser).
ClassMethod HasSession(sessionRef As %String, Output irisUser As %String) As %Boolean [ Private ]
{
	Set irisUser = $Username
	Set session = $Select(sessionRef = "": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef))
	If '$IsObject(session) Quit 0
	If session.IrisUser '= "" Set irisUser = session.IrisUser
	Quit 1
}

/// 1 when the online-demo flag is set.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// The refusal of persona values: the plain Message to answer, and the outcome (bad_preset, custom_not_offered, bad_language or
/// bad_custom) in outcome, or "" and "" when the values are acceptable. In order: the preset is one of Msg.Enum PERSONAPRESET; the
/// custom preset is not offered on the online demo; the language preset has a language name (letters, spaces, hyphens and
/// parentheses, 40 characters at most); the custom preset has 1 to 1,000 characters (UTF-16 units) that are not blank, hold no {{
/// and no @{ and no control character other than a line feed or carriage return. Values that the preset does not use are not checked.
ClassMethod PersonaProblem(preset As %String, language As %String, custom As %String, onlineDemo As %Boolean, Output outcome As %String) As %String [ Private ]
{
	Set outcome = ""
	If (preset = "") || '$ListFind($ListFromString(##class(OcuTalon.Msg.Enum).#PERSONAPRESET), preset) {
		Set outcome = "bad_preset"
		Quit ..#MESSAGENOTSAVED
	}
	If (preset = "custom") && onlineDemo {
		Set outcome = "custom_not_offered"
		Quit ..#MESSAGECUSTOMNOTOFFERED
	}
	If (preset = "language") && '$Match(language, "^\p{L}[\p{L} ()-]{0,39}\z") {
		Set outcome = "bad_language"
		Quit ..#MESSAGEBADLANGUAGE
	}
	If (preset = "custom") && (($Length(custom) > 1000) || $Match(custom, "^\s*\z") || (custom [ "{{") || (custom [ "@{") || $Locate(custom, "[\p{Cc}&&[^\n\r]]")) {
		Set outcome = "bad_custom"
		Quit ..#MESSAGEBADCUSTOM
	}
	Quit ""
}

/// The form of a persona in an audit entry: the preset id, or "language: " and the name for the language preset. An empty preset is
/// professional, the default. The custom text is never part of it.
ClassMethod AuditForm(preset As %String, language As %String) As %String
{
	If preset = "" Quit "professional"
	Quit $Select(preset = "language": "language: "_language, 1: preset)
}

/// The key of a person's persona value: person.<sessionRef>.persona.<name>, name being preset, language or custom.
ClassMethod PersonaKey(sessionRef As %String, name As %String) As %String
{
	Quit "person."_sessionRef_".persona."_name
}

/// 1 when the key is person.<22-character Ref>. followed by one of PERSONKEYS.
ClassMethod IsPersonKey(key As %String) As %Boolean [ Private ]
{
	If $Extract(key, 1, 7) '= "person." Quit 0
	Quit ##class(OcuTalon.Bridge.Approval).IsRef($Extract(key, 8, 29)) && ($Extract(key, 30) = ".") && ''$ListFind($ListFromString(..#PERSONKEYS), $Extract(key, 31, *))
}

/// A person's persona, read from the rows and never from the per-process cache, as {preset, language, custom, customOffered,
/// pendingRef}: Professional with empty language and custom when no key is stored; customOffered is false on the online demo;
/// pendingRef is the Ref of the newest pending approval request of kind setting that the session owns, else "". sc is an error
/// status when the pending request could not be read; the values are returned all the same.
ClassMethod Persona(sessionRef As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set preset = ..Stored(..PersonaKey(sessionRef, "preset"))
	Set pendingRef = ""
	Try {
		Set rows = ##class(OcuTalon.Data.Ownership).Approvals(sessionRef, .sc)
		If $$$ISERR($Get(sc, 1)) Quit
		For i = 1:1:rows.Count() {
			Set request = rows.GetAt(i)
			If (request.Kind = "setting") && (request.OwnerRef = sessionRef) Set pendingRef = request.Ref
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set result = {}
	Do result.%Set("preset", $Select(preset = "": "professional", 1: preset), "string")
	Do result.%Set("language", ..Stored(..PersonaKey(sessionRef, "language")), "string")
	Do result.%Set("custom", ..Stored(..PersonaKey(sessionRef, "custom")), "string")
	Do result.%Set("customOffered", '..OnlineDemo(), "boolean")
	Do result.%Set("pendingRef", pendingRef, "string")
	Quit result
}

/// Deletes every per-person setting of the session (every row whose key starts with person.<sessionRef>.) and this process's cache
/// entries for them. A value that is not a 22-character Ref is refused with an error status and nothing is deleted. The status is
/// the first failed delete's, after every row was tried.
ClassMethod ForgetPerson(sessionRef As %String) As %Status
{
	If '##class(OcuTalon.Bridge.Approval).IsRef(sessionRef) Quit $SYSTEM.Status.Error(5001, "A session reference is 22 characters of A-Z, a-z, 0-9, - and _")
	Set prefix = "person."_sessionRef_"."
	Set result = $$$OK
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ""Key"" FROM OcuTalon_Data.Setting WHERE ""Key"" %STARTSWITH ?", prefix)
	While rs.%Next() {
		If $Extract(rs.%Get("Key"), 1, $Length(prefix)) '= prefix Continue
		Set sc = ##class(OcuTalon.Data.Setting).%DeleteId(rs.%Get("ID"))
		If $$$ISERR(sc) && $$$ISOK(result) Set result = sc
	}
	If rs.%SQLCODE < 0 && $$$ISOK(result) Set result = $SYSTEM.Status.Error(5001, "The per-person settings could not be read: "_rs.%Message)
	Set key = prefix
	For {
		Set key = $Order(^||OcuTalon.Setting(key))
		If $Extract(key, 1, $Length(prefix)) '= prefix Quit
		Kill ^||OcuTalon.Setting(key)
	}
	Quit result
}

/// A CommandResult with the outcome, the message and the data (JSON, "" for none).
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String, data As %String = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Set result.Data = data
	Quit result
}

}
