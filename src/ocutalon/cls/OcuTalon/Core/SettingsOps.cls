/// SettingsOps, the business operation that carries out the settings commands (AD-19). It is the only run-time writer of
/// OcuTalon.Data.Setting, and it writes only the keys of ALLOWLIST. Release 1 has one command, SetDemoMode. For every
/// accepted SetDemoMode it:
///   - writes the Settings audit entry first (AD-17), through Bridge.Audit.Record, so that no change is unaudited and the entry has the
///     one shape of its type;
///   - then writes the value of demo.mode, "1" or "0";
///   - then runs OcuTalon.Install.Step.Demo.Run() (AD-23), which creates or removes the demo namespace, and takes the step's
///     warnings.
/// It answers every command with a CommandResult (Ok, Outcome and Message) and never an error status. The outcomes:
///   - on, off: carried out; off_kept: off, and the step kept an OCUORDERS that is not its own (Ok 1);
///   - step_failed: the value is written and the step failed; the next start runs the step again (Ok 0);
///   - not_audited: the audit entry could not be written (Record refuses it, for example when the command has no ActingUser), so nothing
///     was written (Ok 0);
///   - unknown_command: a command class other than SetDemoMode (Ok 0);
///   - failed: an error was thrown, or the value could not be saved (Ok 0).
/// A written value applies to other processes when their 60-second Setting cache entries expire.
Class OcuTalon.Core.SettingsOps Extends Ens.BusinessOperation
{

/// The setting keys that this operation writes, comma-separated.
Parameter ALLOWLIST = "demo.mode";

/// The audit event data's channel for each origin: system is the terminal, web_admin the web page.
Parameter CHANNELS = "system:system,web_admin:web";

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
	If '$IsObject(command) || ($ClassName(command) '= "OcuTalon.Msg.Command.SetDemoMode") {
		Quit ..Result(0, "unknown_command", ##class(OcuTalon.Core.CommandsIn).#MESSAGEUNKNOWN)
	}
	Set key = ##class(OcuTalon.Install.Step.Demo).#MODEKEY
	Set value = $Select(command.DemoMode: "1", 1: "0")
	Set word = $Select(command.DemoMode: "on", 1: "off")
	Set sc = ..WriteAudit(..AuditData(command, key, ..Stored(key), value))
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

/// The audit event data of the command, in the shape of the Settings type (Bridge.Audit.Record): setting, from (the stored value before
/// the write, "" when the row is absent), to, irisUser (the command's ActingUser), sessionRef (the command's, possibly empty) and channel
/// (where the command came from; "" for an origin that is not in CHANNELS, which Record refuses). Every member is typed as a JSON string, as
/// Record requires (a value such as "1" would otherwise become a number). Record redacts and describes it.
ClassMethod AuditData(command As OcuTalon.Msg.Command.SetDemoMode, key As %String, from As %String, to As %String) As %DynamicObject [ Private ]
{
	Set channel = $Piece($Piece(","_..#CHANNELS, ","_command.Origin_":", 2), ",", 1)
	Set data = {}
	Do data.%Set("setting", key, "string")
	Do data.%Set("from", from, "string")
	Do data.%Set("to", to, "string")
	Do data.%Set("irisUser", command.ActingUser, "string")
	Do data.%Set("sessionRef", command.SessionRef, "string")
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

/// The guarded write: the value of the key, only when the key is on ALLOWLIST; any other key is an error status and no row is
/// written.
ClassMethod Apply(key As %String, value As %String) As %Status [ Private ]
{
	If '$ListFind($ListFromString(..#ALLOWLIST), key) Quit $SYSTEM.Status.Error(5001, "Setting '"_key_"' is not on the list of settings that can be changed here")
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

/// A CommandResult with the outcome and the message.
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

}
