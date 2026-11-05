/// SettingsOps, the business operation that carries out the settings commands SetDemoMode, SaveSettings (from step 2, below), SetPersona
/// and ProposePersona (AD-1, AD-19). It is the only run-time writer of OcuTalon.Data.Setting: it writes only the keys of ALLOWLIST and the
/// per-person keys of PERSONKEYS, and at sign-out deletes every per-person key of the ended session. For every accepted SetDemoMode it:
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
///   - not_audited: the audit entry could not be written (Record refuses it, for example when the command has no ActingUser), so nothing
///     was written (Ok 0);
///   - not_available: ProposePersona on the online demo; not_built: ProposePersona with valid values, which is not built yet (Ok 0);
///   - unknown_command: a command class that this operation does not carry out (Ok 0);
///   - failed: an error was thrown, or a value could not be saved; a persona write that fails changes no key (Ok 0).
/// Persona(sessionRef) reads a person's values from their rows, ForgetPerson(sessionRef) deletes every per-person key of a session
/// (SessionOps.End calls it), and PersonaKey names a persona key. A written value applies to other processes when their 60-second
/// Setting cache entries expire.
/// SaveSettings saves one section of the settings page (XData Sections: the section's fields, each with its key or bridge name, its kind and
/// its default). The outcomes are done (Ok 1; a save that changes nothing is done too), refused (a value, a field or the section is not
/// acceptable; Data is {"fields": [the names of the refused fields]}), not_built (a bridge value's Check answered "not implemented", code 5003:
/// the bridge side is still a stub), not_audited, failed and unknown_command. A section's save is all or nothing:
///   - every value is validated first, and a refused value, which includes any value that holds "@{", changes nothing and writes no audit entry;
///   - the values that differ from the stored ones are the changes; no change writes nothing;
///   - product keys: in one transaction, for each change its audit entry (WriteAudit), then its row (Apply); a failure rolls the transaction back;
///   - bridge values: every Check first; then, for each change, Bridge.Settings.Set and its audit entry (the old value comes from Set); a failure
///     Sets the earlier values back and audits that.
/// Each changed value has its own Settings audit entry. Values answers the settings page's GET body, read from the rows and never from the cache.
Class OcuTalon.Core.SettingsOps Extends Ens.BusinessOperation
{

/// The setting keys that this operation writes, comma-separated.
Parameter ALLOWLIST = "demo.mode,digest.time,digest.channels,checks.thresholds.diskFreePercent,checks.thresholds.journalFreePercent,checks.thresholds.licenseUsePercent,checks.thresholds.queueMessages,checks.thresholds.queueWaitMinutes";

/// The per-person setting keys that this operation writes, comma-separated: person.<SessionRef>. followed by one of these (AD-19).
Parameter PERSONKEYS = "persona.preset,persona.language,persona.custom";

/// The Message of the persona answers.
Parameter MESSAGESAVED = "Saved. Applies from your next message. Recorded in the audit log.";

Parameter MESSAGEBADLANGUAGE = "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters.";

Parameter MESSAGEBADCUSTOM = "Use up to 1,000 characters, without {{ or @{.";

Parameter MESSAGECUSTOMNOTOFFERED = "On the online demo you can choose a preset or a language. Your choice lasts for this visit.";

Parameter MESSAGENOTSAVED = "Couldn't save. Nothing was changed.";

/// The audit event data's channel for each origin: system is the terminal, web_admin and web_user the web page.
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
	If class = "OcuTalon.Msg.Command.SaveSettings" Quit ..Save(command)
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

/// The Message of a saved section, and of a section that was refused or not audited.
Parameter MESSAGESECTIONSAVED = "The settings were saved.";

Parameter MESSAGESECTIONREFUSED = "A value was refused, so nothing was changed.";

Parameter MESSAGESECTIONNOTAUDITED = "OcuTalon couldn't write the audit entry, so nothing was saved.";

/// The longest value of a bridge field that Save passes on to Bridge.Settings.
Parameter BRIDGEMAX = 200;

/// The sections of the settings page. A section has a slug, a kind (product: its fields are Data.Setting keys that this class writes; bridge:
/// its fields are bridge names that Bridge.Settings changes; demo: read here only, a SetDemoMode switches it) and its fields. A field has a name
/// (the page's and the API's), a key (product) or the bridge name, a type (int, time, channels, bridge or flag), its default and, for an int, its
/// range. A section without a row here (Models, Channels) has no save yet.
XData Sections [ MimeType = application/json ]
{
[
 {"slug": "budgets", "kind": "bridge", "fields": [
  {"name": "DecisionTokenBudget", "type": "bridge"},
  {"name": "DailyCostCapUSD", "type": "bridge"}]},
 {"slug": "daily-digest", "kind": "product", "fields": [
  {"name": "time", "key": "digest.time", "type": "time", "default": "08:00"},
  {"name": "channels", "key": "digest.channels", "type": "channels", "default": "web,phone,telegram"}]},
 {"slug": "time-zone", "kind": "bridge", "fields": [
  {"name": "InstanceZone", "type": "bridge"}]},
 {"slug": "check-thresholds", "kind": "product", "fields": [
  {"name": "diskFreePercent", "key": "checks.thresholds.diskFreePercent", "type": "int", "min": 1, "max": 100, "default": "10"},
  {"name": "journalFreePercent", "key": "checks.thresholds.journalFreePercent", "type": "int", "min": 1, "max": 100, "default": "10"},
  {"name": "licenseUsePercent", "key": "checks.thresholds.licenseUsePercent", "type": "int", "min": 1, "max": 100, "default": "90"},
  {"name": "queueMessages", "key": "checks.thresholds.queueMessages", "type": "int", "min": 1, "max": 1000000, "default": "100"},
  {"name": "queueWaitMinutes", "key": "checks.thresholds.queueWaitMinutes", "type": "int", "min": 1, "max": 1000000, "default": "10"}]},
 {"slug": "demo-mode", "kind": "demo", "fields": [
  {"name": "demoMode", "key": "demo.mode", "type": "flag", "default": "0"}]}
]
}

/// The sections, as a dynamic array of the rows of XData Sections.
ClassMethod Sections() As %DynamicArray
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.SettingsOps||Sections").Data)
}

/// The row of the section with the slug, or "" when there is none.
ClassMethod Section(slug As %String) As %DynamicObject
{
	Set found = ""
	Set iterator = ..Sections().%GetIterator()
	While iterator.%GetNext(, .section) {
		If section.slug = slug {
			Set found = section
			Quit
		}
	}
	Quit found
}

/// The body of GET /v1/settings, read from the rows through Stored and never from the per-process cache, so that a page loaded right after
/// a save shows the saved values: {"sections": {slug: {field: value}} for each product and demo section, "bridge": Bridge.Settings.Values(),
/// "providers": Bridge.Settings.Providers(), "instanceZone": Bridge.Time.Zone()}. A stored int that is not a whole number reads as its default.
/// It holds no key and no secret.
ClassMethod Values() As %DynamicObject
{
	Set sections = {}
	Set iterator = ..Sections().%GetIterator()
	While iterator.%GetNext(, .section) {
		If section.kind = "bridge" Continue
		Set values = {}
		Set fields = section.fields.%GetIterator()
		While fields.%GetNext(, .field) {
			Set stored = ..Stored(field.key)
			If stored = "" Set stored = field.default
			Set whole = (stored ? 1.9N)
			If field.type = "int" {
				Do values.%Set(field.name, $Select(whole: +stored, 1: +field.default), "number")
			} ElseIf field.type = "flag" {
				Do values.%Set(field.name, (stored = "1"), "boolean")
			} Else {
				Do values.%Set(field.name, stored, "string")
			}
		}
		Do sections.%Set(section.slug, values)
	}
	Quit {"sections": (sections), "bridge": (##class(OcuTalon.Bridge.Settings).Values()), "providers": (##class(OcuTalon.Bridge.Settings).Providers()), "instanceZone": (##class(OcuTalon.Bridge.Time).Zone())}
}

/// Saves the section of a SaveSettings command: see the class description.
Method Save(command As OcuTalon.Msg.Command.SaveSettings) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set section = ..Section(command.Slug)
	If '$IsObject(section) || (section.kind = "demo") Quit ..Refused([])
	Try {
		Set changes = ##class(%DynamicAbstractObject).%FromJSON(command.Changes)
	} Catch {
		Set changes = ""
	}
	If '$IsObject(changes) || 'changes.%IsA("%Library.DynamicObject") Quit ..Refused([])
	Set bad = [], refused = 0, wanted = ""
	Set fields = section.fields.%GetIterator()
	While fields.%GetNext(, .field) {
		Set wanted = wanted_$ListBuild(field.name)
		If ..Field(field, changes, .canonical) {
			Set to(field.name) = canonical
		} Else {
			Do bad.%Push(field.name)
			Set refused = 1
		}
	}
	Set iterator = changes.%GetIterator()
	While iterator.%GetNext(.name) {
		If '$ListFind(wanted, name) Set refused = 1
	}
	If refused Quit ..Refused(bad)
	If section.kind = "bridge" Quit ..SaveBridge(command, section, .to)
	Quit ..SaveProduct(command, section, .to)
}

/// A refusal: Outcome refused, and Data the names of the refused fields.
ClassMethod Refused(bad As %DynamicArray) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ..Result(0, "refused", ..#MESSAGESECTIONREFUSED)
	Set result.Data = {"fields": (bad)}.%ToJSON()
	Quit result
}

/// 1 when the body's value of the field is acceptable, and canonical is its form to store. A value that is missing, is not a JSON string or
/// number, or holds "@{" is not; an int is a whole number of its range, a time is HH:MM, channels is a non-empty list of web, phone and telegram
/// without a repeat (stored in that order), and a bridge value is a string of at most BRIDGEMAX characters (the bridge checks the rest).
ClassMethod Field(field As %DynamicObject, changes As %DynamicObject, Output canonical As %String) As %Boolean [ Private ]
{
	Set canonical = ""
	Set type = changes.%GetTypeOf(field.name)
	If (type '= "string") && (type '= "number") Quit 0
	Set text = changes.%Get(field.name)
	If text [ "@{" Quit 0
	If field.type = "int" {
		If text '? 1.9N Quit 0
		Set number = +text
		If (number < field.min) || (number > field.max) Quit 0
		Set canonical = number
		Quit 1
	}
	If field.type = "time" {
		If (type '= "string") || '$Match(text, "^([01][0-9]|2[0-3]):[0-5][0-9]$") Quit 0
		Set canonical = text
		Quit 1
	}
	If field.type = "channels" {
		If type '= "string" Quit 0
		Set picked = ""
		For i = 1:1:$Length(text, ",") {
			Set one = $Piece(text, ",", i)
			If '$ListFind($ListBuild("web", "phone", "telegram"), one) || $ListFind(picked, one) Quit
			Set picked = picked_$ListBuild(one)
		}
		If $ListLength(picked) '= $Length(text, ",") Quit 0
		For one = "web", "phone", "telegram" {
			If $ListFind(picked, one) Set canonical = canonical_$Select(canonical = "": "", 1: ",")_one
		}
		Quit 1
	}
	If field.type = "bridge" {
		Set text = $ZStrip(text, "<>W")
		If $Length(text) > ..#BRIDGEMAX Quit 0
		Set canonical = text
		Quit 1
	}
	Quit 0
}

/// The values of a product section that differ from the stored ones (an absent row reads as the field's default) are written, each with its
/// audit entry first, in one transaction. A failure rolls the transaction back.
Method SaveProduct(command As OcuTalon.Msg.Command.SaveSettings, section As %DynamicObject, ByRef to) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set changed = []
	Set fields = section.fields.%GetIterator()
	While fields.%GetNext(, .field) {
		Set from = ..Stored(field.key)
		If from = "" Set from = field.default
		If to(field.name) '= from Do changed.%Push({"key": (field.key), "from": (from), "to": (to(field.name))})
	}
	If 'changed.%Size() Quit ..Result(1, "done", ..#MESSAGESECTIONSAVED)
	Set level = $TLEVEL
	TSTART
	Try {
		Set iterator = changed.%GetIterator()
		While iterator.%GetNext(, .change) {
			Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, change.key, change.from, change.to))
			If $$$ISERR(sc) {
				TROLLBACK 1
				Set text = $SYSTEM.Status.GetErrorText(sc)
				$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
				Return ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
			}
			Set sc = ..Apply(change.key, change.to)
			If $$$ISERR(sc) {
				TROLLBACK 1
				$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
				Return ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
			}
		}
		TCOMMIT
	} Catch exception {
		If $TLEVEL > level TROLLBACK 1
		$$$LOGERROR(exception.DisplayString())
		Return ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit ..Result(1, "done", ..#MESSAGESECTIONSAVED)
}

/// The values of a bridge section that differ from the bridge's current ones: every Check first (a value that Check refuses refuses the whole
/// section, and a Check that answers "not implemented" gives not_built and changes nothing), then each Set with its audit entry. A failure puts the
/// values already set back, with an audit entry for each, and gives not_audited or failed.
Method SaveBridge(command As OcuTalon.Msg.Command.SaveSettings, section As %DynamicObject, ByRef to) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set changed = [], bad = [], stub = 0
	Set fields = section.fields.%GetIterator()
	While fields.%GetNext(, .field) {
		If to(field.name) = ..BridgeCurrent(field.name) Continue
		Set sc = ..BridgeCheck(field.name, to(field.name))
		If $$$ISERR(sc) {
			If ..NotImplemented(sc) {
				Set stub = 1
			} Else {
				Do bad.%Push(field.name)
			}
			Continue
		}
		Do changed.%Push({"name": (field.name), "to": (to(field.name))})
	}
	If bad.%Size() Quit ..Refused(bad)
	If stub Quit ..Result(0, "not_built", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTBUILT)
	Set done = [], outcome = "done"
	Try {
		For i = 0:1:changed.%Size() - 1 {
			Set change = changed.%Get(i)
			Set sc = ..BridgeSet(change.name, change.to, .old)
			If $$$ISERR(sc) {
				$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
				Set outcome = "failed"
			} Else {
				Do done.%Push({"name": (change.name), "from": (old), "to": (change.to)})
				Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, change.name, old, change.to))
				If $$$ISERR(sc) {
					Set text = $SYSTEM.Status.GetErrorText(sc)
					$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
					Set outcome = "not_audited"
				}
			}
			If outcome '= "done" Quit
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set outcome = "failed"
	}
	If outcome '= "done" Do ..PutBack(command, done)
	If outcome = "not_audited" Quit ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
	If outcome = "failed" Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Quit ..Result(1, "done", ..#MESSAGESECTIONSAVED)
}

/// Sets the bridge values of done (an array of {name, from, to}) back, newest first, and audits each put back. A value that cannot be put back
/// is logged: the bridge keeps what it holds.
Method PutBack(command As OcuTalon.Msg.Command.SaveSettings, done As %DynamicArray) [ Private ]
{
	For i = done.%Size() - 1:-1:0 {
		Set change = done.%Get(i)
		Set sc = ..BridgeSet(change.name, change.from, .ignored)
		If $$$ISERR(sc) {
			$$$LOGERROR("The value of "_change.name_" could not be put back: "_$SYSTEM.Status.GetErrorText(sc))
			Continue
		}
		Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, change.name, change.to, change.from))
		If $$$ISERR(sc) $$$LOGERROR("The Settings audit entry of a value put back could not be written: "_$SYSTEM.Status.GetErrorText(sc))
	}
}

/// 1 when the status is the answer "not implemented" (code 5003) of a bridge stub.
ClassMethod NotImplemented(sc As %Status) As %Boolean [ Private ]
{
	Quit ''$ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003)
}

/// The bridge's current value of the field, "" when it holds none: Bridge.Time.Zone() for InstanceZone and Bridge.Settings.Values() for the
/// rest. A test subclass overrides it.
Method BridgeCurrent(name As %String) As %String [ Private ]
{
	If name = "InstanceZone" Quit ##class(OcuTalon.Bridge.Time).Zone()
	Set current = ##class(OcuTalon.Bridge.Settings).Values()
	Quit $Select(current.%IsDefined(name): current.%Get(name), 1: "")
}

/// The one call of Bridge.Settings.Check. A test subclass overrides it.
Method BridgeCheck(name As %String, value As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Settings).Check(name, value)
}

/// The one call of Bridge.Settings.Set; old is the value it replaced. A test subclass overrides it.
Method BridgeSet(name As %String, value As %String, Output old As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Settings).Set(name, value, .old)
}

}
