/// SettingsOps, the business operation that carries out the settings commands SetDemoMode, SaveSettings (from step 2, below), SetPersona,
/// ProposePersona and SetHeartbeat (AD-1, AD-19). It is the only run-time writer of OcuTalon.Data.Setting: it writes only the keys of ALLOWLIST and the
/// per-person keys of PERSONKEYS, and at sign-out deletes every per-person key of the ended session. For every accepted SetDemoMode it:
///   - writes the Settings audit entry first (AD-17), through Bridge.Audit.Record, so that no change is unaudited and the entry has the
///     one shape of its type;
///   - then writes the value of demo.mode, "1" or "0";
///   - then runs OcuTalon.Install.Step.Demo.Run() (AD-23), which creates or removes the demo namespace, and takes the step's
///     warnings.
/// For every accepted SetPersona (origin web_user, the session's own persona) it checks that the session has a row, validates the
/// values (PersonaProblem), writes the Settings audit entry first (setting persona, from and to in the form of AuditForm: the preset id
/// or the language name, never the custom text), then writes person.<SessionRef>.persona.preset, .language and .custom in one
/// transaction (WritePersona). A value that the chosen preset does not use is neither validated nor stored: its key is written empty.
/// For every accepted SetHeartbeat (origin web_user, the session's own heartbeat settings) it checks that the session has a row, validates
/// the values (HeartbeatProblem: on is 0 or 1; the interval is one of Checks.Beat INTERVALS; the hours are both empty, for all day, or both HH:MM
/// with the minutes 00, 15, 30 or 45; the checklist has at most Checks.Beat CHECKLISTMAX characters, no {{, no @{ and no control character other
/// than a line feed or carriage return), writes the Settings audit entry first (setting heartbeat, from and to in the form of HeartbeatAuditForm:
/// only the changed keys, the checklist as its length, never its text), then writes person.<SessionRef>.heartbeat.on, .interval, .from, .to and
/// .checklist in one transaction (WriteKeys, which WritePersona shares). Heartbeat(sessionRef) reads a person's values and their HeartbeatBeat
/// row's public view; SampleChecklist is the online demo's unsaved checklist.
/// ProposePersona (origin tool, Story 40.6) checks the session, the online-demo flag and the values like SetPersona, writes and audits no
/// persona key, and raises a request of kind setting (Bridge.Approval.Raise, ResultTarget SettingsOps, the DryRun {key, ownerRef, old, new}
/// whose old and new are the objects {preset, language, custom, text}) and sends one approval.persona notice to Notify (kind approval,
/// ApprovalRef the request's Ref). The request's outcome comes back as an ApprovalOutcome (Outcome): approved, it re-reads the request
/// through StartExecution and, when the stored persona still equals old, writes the stored new values as WritePersona does (the audit
/// entry names the request's AnsweredBy and AnsweredChannel), records done and sends the answered notice and then persona.applied; when
/// the persona changed since, it writes nothing, records failed and sends the answered notice and then persona.stale; rejected or
/// expired, it sends only the answered notice. An outcome that is not its own, or a repeat, is dropped with one warning.
/// It answers every command with a CommandResult (Ok, Outcome and Message) and never an error status. The outcomes:
///   - on, off: carried out; off_kept: off, and the step kept an OCUORDERS that is not its own (Ok 1);
///   - step_failed: the value is written and the step failed; the next start runs the step again (Ok 0);
///   - saved: the persona is saved (Ok 1; Data holds the saved preset, language and custom as JSON), or the heartbeat settings are saved (Ok 1;
///     Data holds the saved on (0 or 1), interval, from, to and checklist as JSON);
///   - bad_preset, bad_language, bad_custom, custom_not_offered (the online demo offers presets and a language only): the values are
///     refused and nothing was written (Ok 0);
///   - bad_on, bad_interval, bad_hours, bad_checklist: the heartbeat values are refused and nothing was written (Ok 0);
///   - no_session: the command's session has no row (Ok 0);
///   - not_audited: the audit entry could not be written (Record refuses it, for example when the command has no ActingUser), so nothing
///     was written (Ok 0);
///   - proposed: ProposePersona raised the request (Ok 1; Ref is its Ref and the Message the pending note); not_available: ProposePersona
///     on the online demo (Ok 0);
///   - unknown_command: a command class that this operation does not carry out (Ok 0);
///   - failed: an error was thrown, the request could not be raised, or a value could not be saved; a persona write that fails changes no
///     key (Ok 0).
/// Persona(sessionRef) and Heartbeat(sessionRef) read a person's values from their rows, ForgetPerson(sessionRef) deletes every per-person key of a session
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
/// The models section (Story 18.3; kind models) saves with the nested body {"agents": {<Agent>: {provider, model, secondProvider, secondModel}},
/// "prices": {<model>: {input, output, cacheRead, cacheWrite}}}, with exactly the three agents and exactly the models that Values lists in prices. The
/// order is AD-19's: the shape is validated (a failure names the offending agents and "prices.<model>"); every CheckModel runs before any write (a
/// refusal names <Agent>, or <Agent>.second for a second model); the prices of the changed models are written by Bridge.Settings.SetPrice inside one
/// transaction, which a refusal rolls back (the refusal names "prices.<model>", and nothing is audited or set); then each audit entry of a price, then each
/// SetModel with its audit entry (TriageAgent.model, TriageAgent.secondModel, price.<model>.<key>). A later failure puts back what was written (SetModel
/// and SetPrice with the old values) and audits each put-back. A value that equals the current one is dropped.
/// The email section (Stories 21.2, 21.6 and 21.3; kind email, slug channels) connects a mailbox: the body is {address, incoming, outgoing, user, password,
/// signIn, clientId, clientSecret, origin} where outgoing is optional (absent or empty: no outgoing server), password and clientSecret are SecretHandoff
/// references (or absent or empty to keep the stored one) and never the secrets, signIn is password (the default), google or microsoft, clientId is the
/// provider's client ID (required with a provider), and origin is the page's origin that the REST route adds (required with a provider; a person's body does
/// not hold it). SaveEmail takes the secrets from the hand-off, writes the product keys email.address and email.owner (the session of
/// the admin who saved, so the mailbox moves to the last saving admin), the credential OcuTalonMail (user name and password, used by both servers) and the
/// System Default Settings rows of EmailIn (POP3Server, POP3Port, Credentials, SSLConfig and Enabled) and of EmailOut (SMTPServer, SMTPPort,
/// Credentials, SSLConfig, SSLCheckServerIdentity and Enabled; a cleared outgoing server writes Enabled 0 and deletes the server rows), and has a
/// detached job update the production after every successful save, so that EmailIn and EmailOut start or restart, also when nothing changed and an
/// earlier update never ran. It is the only writer of all of these, and it refuses with not_available on the online demo. Values adds channels
/// {address, incoming, outgoing, user, passwordSet, signIn, clientId, clientSecretSet, signedIn} from the rows, the credential and the mark emailSignIn,
/// never a password or a client secret, and not on the online demo.
/// With a provider (Story 21.3; AD-1, AD-3, AD-19) the mailbox signs in with OAuth2 and keeps no password: the product keys email.signIn, email.clientId and
/// email.oauthOwned (what OcuTalon created or enabled in IRIS: client, server, app) are written, the credential OcuTalonMail keeps the user name and an empty
/// password (an earlier password is audited as email.credential removed), and OcuTalon.Channel.Email.OAuth, called here only (RegisterOAuth, RemoveOAuth,
/// OAuthStart, OAuthState), registers IRIS's OAuth2 client OcuTalonMail with the client secret, which then lives only there; a provider changed or a Password
/// saved removes the client and its tokens. Each change is audited without the secret: email.signIn (the method names), email.clientId (set, changed or
/// removed), email.clientSecret (set or removed), email.oauthOwned (the lists) and email.oauthApp (the web application /csp/sys/oauth2 enabled or disabled).
/// With a provider (Story 21.8) it also writes the rows OAuth2ApplicationName (OAUTHAPPLICATION) and OAuth2CallBackHandler (OAUTHHANDLER, Channel.Email.Token) on EmailIn
/// and, when it has an outgoing server, on EmailOut, so that the adapters log in with XOAUTH2; Password, or a cleared outgoing server, deletes them, and a failed save
/// puts them back like any row. No OAuth2Scope, OAuth2SessionId or OAuth2AuthProperties row is written.
/// The mark emailSignIn {at, provider, signedIn} follows each register, remove and check; the page's signedIn is that mark, and false after a poll failed on the sign-in after
/// the mark's time (Story 21.8; a reader of the mark emailPoll only). A MailSignIn (origin web_admin) with action start enables the web
/// application when it is disabled (audited) and answers Ok, Outcome started and Data {"url"}, IRIS's authorization address for the consent; action check answers
/// Outcome checked and Data {"signedIn"} and records the mark; a mailbox without a provider is refused with Data {"fields": ["signIn"]}, and the online demo
/// is not_available.
/// TestModel (origin web_admin) sends Bridge.Settings.TestRequest's request to Decide synchronously, waits at most TESTWAIT seconds, and answers the outcome
/// tested with Data {answered, seconds, reason} (an expired wait gives reason timeout), or refused with Data {"fields": ["agent"]} for an agent that
/// TestRequest refuses. It writes no setting and no audit entry; the Decision and Usage rows of the test request are Decide's, as Bridge.Settings.TestRequest describes.
/// CreateWebhook and SetWebhookSecret (Story 35.3, origin web_admin) take the secret from the command's Handoff uri through SecretHandoff.Take, never from a
/// property, a message or a log. On the online demo both answer not_available and write nothing. CreateWebhook validates the name and the secret (Data.Webhook
/// NameProblem, SecretProblem, NameTaken), writes the Settings audit entry first (setting webhook.<Ref>, from empty, to the name), then saves the Webhook row
/// with the salted hash for the session's own Ref. SetWebhookSecret needs a row of the command's own session (else not_found), validates the secret, audits
/// webhook.<Ref>.secret, then replaces the hash. The outcomes: done (Ok 1; Data {ref, name, createdAt} for a create); refused and name_taken (Ok 0; Data
/// {"fields": {name, secret}} with each refused field's catalog text); not_found, no_session, not_available, not_audited and failed (Ok 0). The secret and its hash
/// are in no result, audit entry or log line.
/// The on-call section (Story 36.4; kind oncall, slug on-call) chooses who is paged: its body is held by SecretHandoff and never by the command, whose Changes
/// is exactly {"handoff": uri}, so that no address or user name is in a traced message. SaveOnCall takes the body, which has the members primaryPerson,
/// primaryUser, primaryEmail, primaryChannels, the four backup members and escalationMinutes. A person is nobody (stored as "", "" and telegram,email), user (an
/// IRIS user with a Data.Session row) or email (an address, with no user). Every value is validated before anything is written: an address is trimmed and passes
/// IsAddress; the channels are a non-empty list of telegram and email without a repeat, stored in that order, each reachable (telegram only for a user who has a
/// session with a paired chat, email only with an address); the minutes are a whole number from 1 to 1440 (Field). A refusal names the fields (primaryUser,
/// primaryEmail, primaryChannels, the backup ones, escalationMinutes) and never a value. The seven oncall.* keys are written by SaveProduct, each change with
/// its Settings audit entry (from, to, the admin's user and session) and then its row, in one transaction. On the online demo it answers not_available and
/// Values has no on-call member. Values adds on-call {the seven values, users [{user, paired}], pagesBuilt}, never on the online demo. No on-call value is in
/// a log line, a result or a message.
Class OcuTalon.Core.SettingsOps Extends Ens.BusinessOperation
{

/// The setting keys that this operation writes, comma-separated.
Parameter ALLOWLIST = "demo.mode,digest.time,digest.channels,checks.thresholds.diskFreePercent,checks.thresholds.journalFreePercent,checks.thresholds.licenseUsePercent,checks.thresholds.queueMessages,checks.thresholds.queueWaitMinutes,email.address,email.owner,email.signIn,email.clientId,email.oauthOwned,oncall.primary.user,oncall.primary.email,oncall.primary.channels,oncall.backup.user,oncall.backup.email,oncall.backup.channels,oncall.escalationMinutes";

/// The per-person setting keys that this operation writes, comma-separated: person.<SessionRef>. followed by one of these (AD-19).
Parameter PERSONKEYS = "persona.preset,persona.language,persona.custom,heartbeat.on,heartbeat.interval,heartbeat.from,heartbeat.to,heartbeat.checklist";

/// The Message of the persona answers.
Parameter MESSAGESAVED = "Saved. Applies from your next message. Recorded in the audit log.";

Parameter MESSAGEBADLANGUAGE = "Use a language name only: letters, spaces, hyphens and parentheses, up to 40 characters.";

Parameter MESSAGEBADCUSTOM = "Use up to 1,000 characters, without {{ or @{.";

Parameter MESSAGECUSTOMNOTOFFERED = "On the online demo you can choose a preset or a language. Your choice lasts for this visit.";

Parameter MESSAGENOTSAVED = "Couldn't save. Nothing was changed.";

/// The Message of the heartbeat answers.
Parameter MESSAGEHEARTBEATSAVED = "Saved. Applies within a minute. Recorded in the audit log.";

Parameter MESSAGEBADCHECKLIST = "Use up to 1,000 characters, without {{ or @{.";

/// The Message of a proposal that was raised (the pending note of the Persona card).
Parameter MESSAGEPROPOSED = "OcuTalon suggested a change. It waits for your answer in Approval requests.";

/// The item that receives the outcome of this operation's requests: its name in the production.
Parameter RESULTTARGET = "SettingsOps";

/// The catalog keys of the persona notices: the proposal (kind approval), and the applied and stale results (kind result).
Parameter KEYPROPOSED = "approval.persona";

Parameter KEYAPPLIED = "persona.applied";

Parameter KEYSTALE = "persona.stale";

/// The catalog keys of the answered notices (kind answered), as for any request.
Parameter KEYAPPROVED = "answered.approved";

Parameter KEYREJECTED = "answered.rejected";

Parameter KEYEXPIRED = "answered.expired";

Parameter LOGDROPPED = "SettingsOps dropped an approval outcome: ";

Parameter LOGNOTICE = "SettingsOps could not send a notice: ";

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

/// Carries out the command and returns the CommandResult to answer; an ApprovalOutcome is handled by Outcome and answers "".
Method Carry(command As %RegisteredObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set class = $Select($IsObject(command): $ClassName(command), 1: "")
	If class = "OcuTalon.Bridge.Msg.ApprovalOutcome" {
		Do ..Outcome(command)
		Quit ""
	}
	If class = "OcuTalon.Msg.Command.SaveSettings" Quit ..Save(command)
	If class = "OcuTalon.Msg.Command.TestModel" Quit ..TestModel(command)
	If class = "OcuTalon.Msg.Command.MailSignIn" Quit ..SignIn(command)
	If class = "OcuTalon.Msg.Command.SetDemoMode" Quit ..SwitchDemo(command)
	If class = "OcuTalon.Msg.Command.SetPersona" Quit ..SavePersona(command)
	If class = "OcuTalon.Msg.Command.ProposePersona" Quit ..Propose(command)
	If class = "OcuTalon.Msg.Command.SetHeartbeat" Quit ..SaveHeartbeat(command)
	If class = "OcuTalon.Msg.Command.CreateWebhook" Quit ..CreateWebhook(command)
	If class = "OcuTalon.Msg.Command.SetWebhookSecret" Quit ..SetWebhookSecret(command)
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
/// origin, or the channel given, which overrides it; "" for an origin that is not in CHANNELS, which Record refuses). Every member is typed as a JSON string, as
/// Record requires (a value such as "1" would otherwise become a number). Record redacts and describes it.
ClassMethod AuditData(origin As %String, irisUser As %String, sessionRef As %String, setting As %String, from As %String, to As %String, channel As %String = "") As %DynamicObject [ Private ]
{
	If channel = "" Set channel = $Piece($Piece(","_..#CHANNELS, ","_origin_":", 2), ",", 1)
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
	Set sc = ..WritePersona(irisUser, sessionRef, "", command.Origin, preset, language, custom, .outcome)
	If $$$ISERR(sc) Quit ..Result(0, outcome, ..#MESSAGENOTSAVED)
	Set data = {}
	Do data.%Set("preset", preset, "string")
	Do data.%Set("language", language, "string")
	Do data.%Set("custom", custom, "string")
	Quit ..Result(1, "saved", ..#MESSAGESAVED, data.%ToJSON())
}

/// The persona write of SavePersona and of an approved proposal: the Settings audit entry first (setting persona, from the stored form and
/// to the new form of AuditForm, never the custom text; channel overrides the origin's when given), then the three keys in one
/// transaction. Returns an error status for a refused audit entry (outcome not_audited, logged) or a failed write (outcome failed, logged,
/// every key as it was); outcome is "" when it succeeds.
Method WritePersona(irisUser As %String, sessionRef As %String, channel As %String, origin As %String, preset As %String, language As %String, custom As %String, Output outcome As %String) As %Status [ Private ]
{
	Set from = ..AuditForm(..Stored(..PersonaKey(sessionRef, "preset")), ..Stored(..PersonaKey(sessionRef, "language")))
	Set keys = $ListBuild(..PersonaKey(sessionRef, "preset"), ..PersonaKey(sessionRef, "language"), ..PersonaKey(sessionRef, "custom"))
	Quit ..WriteKeys(irisUser, sessionRef, channel, origin, "persona", from, ..AuditForm(preset, language), keys, $ListBuild(preset, language, custom), .outcome)
}

/// The write that WritePersona and SaveHeartbeat share: the Settings audit entry first (the setting, from and to as given), then each key
/// of keys with the value at the same place of values, through Apply, in one transaction. Returns an error status for a refused audit entry
/// (outcome not_audited, logged) or a failed write (outcome failed, logged, every key as it was); outcome is "" when it succeeds.
Method WriteKeys(irisUser As %String, sessionRef As %String, channel As %String, origin As %String, setting As %String, from As %String, to As %String, keys As %List, values As %List, Output outcome As %String) As %Status [ Private ]
{
	Set outcome = ""
	Set sc = ..WriteAudit(..AuditData(origin, irisUser, sessionRef, setting, from, to, channel))
	If $$$ISERR(sc) {
		$$$LOGERROR("The Settings audit entry could not be written"_$Select($SYSTEM.Status.GetErrorText(sc) = "": "", 1: ": "_$SYSTEM.Status.GetErrorText(sc)))
		Set outcome = "not_audited"
		Quit sc
	}
	Set level = $TLevel
	TSTART
	Try {
		For i = 1:1:$ListLength(keys) {
			Set sc = ..Apply($List(keys, i), $List(values, i))
			If $$$ISERR(sc) Quit
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		If $TLevel > level TROLLBACK 1
		$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
		Set outcome = "failed"
		Quit sc
	}
	TCOMMIT
	Quit $$$OK
}

/// Carries out a SetHeartbeat and returns the CommandResult to answer (see the class description). The audit entry is written before the
/// keys, and the five keys are written in one transaction: a failed write rolls all of them back. A refused value writes and audits nothing.
Method SaveHeartbeat(command As OcuTalon.Msg.Command.SetHeartbeat) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sessionRef = command.SessionRef
	If '..HasSession(sessionRef, .irisUser) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	Set on = command.On, interval = command.Interval, from = command.From, to = command.To, checklist = command.Checklist
	Set message = ..HeartbeatProblem(on, interval, from, to, checklist, .outcome)
	If message '= "" Quit ..Result(0, outcome, message)
	Set new = ..HeartbeatObject(+on, +interval, from, to, checklist)
	Set old = ..HeartbeatValues(sessionRef)
	Set changed = ""
	For i = 1:1:$Length(##class(OcuTalon.Checks.Beat).#KEYS, ",") {
		Set name = $Piece(##class(OcuTalon.Checks.Beat).#KEYS, ",", i)
		If old.%Get(name) '= new.%Get(name) Set changed = changed_$ListBuild(name)
	}
	Set keys = "", values = ""
	For i = 1:1:$Length(##class(OcuTalon.Checks.Beat).#KEYS, ",") {
		Set name = $Piece(##class(OcuTalon.Checks.Beat).#KEYS, ",", i)
		Set keys = keys_$ListBuild(##class(OcuTalon.Checks.Beat).SettingKey(sessionRef, name))
		Set values = values_$ListBuild(new.%Get(name))
	}
	Set sc = ..WriteKeys(irisUser, sessionRef, "", command.Origin, "heartbeat", ..HeartbeatAuditForm(old, changed), ..HeartbeatAuditForm(new, changed), keys, values, .outcome)
	If $$$ISERR(sc) Quit ..Result(0, outcome, ..#MESSAGENOTSAVED)
	Quit ..Result(1, "saved", ..#MESSAGEHEARTBEATSAVED, new.%ToJSON())
}

/// The heartbeat values as the object that Checks.Beat.Values returns and the answer holds: on (number 0 or 1), interval (number), from, to
/// and checklist (strings).
ClassMethod HeartbeatObject(on As %Integer, interval As %Integer, from As %String, to As %String, checklist As %String) As %DynamicObject [ Private ]
{
	Set object = {}
	Do object.%Set("on", on, "number")
	Do object.%Set("interval", interval, "number")
	Do object.%Set("from", from, "string")
	Do object.%Set("to", to, "string")
	Do object.%Set("checklist", checklist, "string")
	Quit object
}

/// The session's heartbeat values as Checks.Beat.Values reads them (the defaults and the normalization are Checks'), with this process's cache entries
/// of the five keys dropped first (Values with stored 1), so that the values are the rows' and not a cached older value.
ClassMethod HeartbeatValues(sessionRef As %String) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Checks.Beat).Values(sessionRef, 1)
}

/// The refusal of heartbeat values: the plain Message to answer, and the outcome (bad_on, bad_interval, bad_hours or bad_checklist) in
/// outcome, or "" and "" when the values are acceptable. In order: on is 0 or 1; the interval is a canonical number in Checks.Beat INTERVALS;
/// the hours are both empty (all day) or both HH:MM with HH 00 to 23 and MM 00, 15, 30 or 45; the checklist has at most Checks.Beat
/// CHECKLISTMAX characters, as $Length counts them, holds no {{ and no @{ and no control character other than a line feed or carriage
/// return. Only the checklist's refusal has a message of its own; the others say that nothing was saved.
ClassMethod HeartbeatProblem(on As %String, interval As %String, from As %String, to As %String, checklist As %String, Output outcome As %String) As %String [ Private ]
{
	Set outcome = ""
	If (on '= "0") && (on '= "1") {
		Set outcome = "bad_on"
		Quit ..#MESSAGENOTSAVED
	}
	If (interval '= +interval) || '$ListFind($ListFromString(##class(OcuTalon.Checks.Beat).#INTERVALS), +interval) {
		Set outcome = "bad_interval"
		Quit ..#MESSAGENOTSAVED
	}
	Set clock = "^([01][0-9]|2[0-3]):(00|15|30|45)\z"
	If '(((from = "") && (to = "")) || ($Match(from, clock) && $Match(to, clock))) {
		Set outcome = "bad_hours"
		Quit ..#MESSAGENOTSAVED
	}
	If ($Length(checklist) > ##class(OcuTalon.Checks.Beat).#CHECKLISTMAX) || (checklist [ "{{") || (checklist [ "@{") || $Locate(checklist, "[\p{Cc}&&[^\n\r]]") {
		Set outcome = "bad_checklist"
		Quit ..#MESSAGEBADCHECKLIST
	}
	Quit ""
}

/// The form of heartbeat values in an audit entry: name=value for each name in changed (a list of Checks.Beat KEYS names), in KEYS order,
/// joined by "; ", the checklist as checklist=<n> characters, never its text; "" when nothing changed. values is an object with a member for
/// each name, as Checks.Beat.Values returns.
ClassMethod HeartbeatAuditForm(values As %DynamicObject, changed As %List) As %String
{
	Set form = ""
	For i = 1:1:$Length(##class(OcuTalon.Checks.Beat).#KEYS, ",") {
		Set name = $Piece(##class(OcuTalon.Checks.Beat).#KEYS, ",", i)
		If '$ListFind(changed, name) Continue
		Set part = name_"="_$Select(name = "checklist": $Length(values.%Get(name))_" characters", 1: values.%Get(name))
		Set form = form_$Select(form = "": "", 1: "; ")_part
	}
	Quit form
}

/// A person's heartbeat, read from the rows and never from the per-process cache: the public view of their settings and HeartbeatBeat row
/// (Live.Payload.Heartbeat.FromRow, the very view of the heartbeat event) as a dynamic object, with from and to always present, followed by
/// checklist (the stored text), sample (true only when the unsaved sample checklist is shown: on the online demo, when the session has no
/// checklist row), today ({"checkIns", "costUSD"}: the session's heartbeat Usage rows in the daily cap's day, Ownership.HeartbeatToday), lastFallbackReason
/// (a string, present only when the row's last beat was a fallback and the session's own decision of it names a reason) and onlineDemo (boolean).
/// None of them holds a decision Ref, an ItemId or a SessionRef. sc is an error status when the row could not be read (the settings are returned all the same), when its view could not be built
/// (the members after the view are then set all the same), or when today's Usage rows could not be read.
ClassMethod Heartbeat(sessionRef As %String, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	Set values = ..HeartbeatValues(sessionRef)
	Set row = ##class(OcuTalon.Data.Ownership).Heartbeat(sessionRef, .sc)
	Set result = {}
	Try {
		Set payload = ##class(OcuTalon.Live.Payload.Heartbeat).FromRow(row, values)
		Set status = payload.%JSONExportToString(.json)
		If $$$ISERR(status) Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		Set exported = {}.%FromJSON(json)
		Do result.%Set("on", exported.%Get("on"), "boolean")
		Do result.%Set("interval", exported.%Get("interval"), "number")
		Do result.%Set("from", values.from, "string")
		Do result.%Set("to", values.to, "string")
		Set iterator = exported.%GetIterator()
		While iterator.%GetNext(.name, .value, .type) {
			If '$ListFind($ListBuild("on", "interval", "from", "to"), name) Do result.%Set(name, value, type)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set sample = ('##class(OcuTalon.Data.Setting).KeyIndexExists(##class(OcuTalon.Checks.Beat).SettingKey(sessionRef, "checklist"))) && ..OnlineDemo()
	Do result.%Set("checklist", $Select(sample: ..SampleChecklist(), 1: values.checklist), "string")
	Do result.%Set("sample", sample, "boolean")
	Set todayStatus = $$$OK
	Do result.%Set("today", ##class(OcuTalon.Data.Ownership).HeartbeatToday(sessionRef, .todayStatus))
	If $$$ISERR(todayStatus) && $$$ISOK(sc) Set sc = todayStatus
	If ($IsObject(row) && row.LastFallback) {
		Set decision = ##class(OcuTalon.Data.Ownership).Decision(row.LastDecisionRef, sessionRef)
		If $IsObject(decision) && (decision.FallbackReason '= "") Do result.%Set("lastFallbackReason", decision.FallbackReason, "string")
	}
	Do result.%Set("onlineDemo", ..OnlineDemo(), "boolean")
	Quit result
}

/// The checklist that the online demo shows to a session with no saved checklist: three lines joined by line feeds. It is shown and never stored.
ClassMethod SampleChecklist() As %String
{
	Quit "Tell me if an Orders incident is still open or waiting for my approval."_$Char(10)_"Remind me of anything due in the next hour."_$Char(10)_"Ignore everything else."
}

/// Carries out a ProposePersona and returns the CommandResult to answer: the session check, the online-demo refusal and the values'
/// validation of SetPersona, then the request: it raises a request of kind setting for the session (OwnerRef, the session row's TraceRef,
/// ResultTarget SettingsOps, the DryRun {key, ownerRef, old, new} with old and new as PersonaPart builds them) and sends the
/// approval.persona notice. It answers proposed with the request's Ref; a raise that fails answers failed and sends nothing; a notice
/// that cannot be sent is logged and the answer is still proposed. No persona key is written and nothing is audited.
Method Propose(command As OcuTalon.Msg.Command.ProposePersona) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sessionRef = command.SessionRef
	If '..HasSession(sessionRef, , .traceRef) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	If ..OnlineDemo() Quit ..Result(0, "not_available", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED)
	Set preset = command.Preset
	Set language = $Select(preset = "language": command.Language, 1: "")
	Set custom = $Select(preset = "custom": command.Custom, 1: "")
	Set message = ..PersonaProblem(preset, language, custom, 0, .outcome)
	If message '= "" Quit ..Result(0, outcome, message)
	Set before = ..PersonaPart(..Stored(..PersonaKey(sessionRef, "preset")), ..Stored(..PersonaKey(sessionRef, "language")), ..Stored(..PersonaKey(sessionRef, "custom")))
	Set after = ..PersonaPart(preset, language, custom)
	Set dryRun = {}
	Do dryRun.%Set("key", ..PersonaRoot(sessionRef), "string")
	Do dryRun.%Set("ownerRef", sessionRef, "string")
	Do dryRun.%Set("old", before)
	Do dryRun.%Set("new", after)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set row.Kind = "setting"
	Set row.OwnerRef = sessionRef
	Set row.TraceRef = traceRef
	Set row.DryRun = dryRun.%ToJSON()
	Set row.ResultTarget = ..#RESULTTARGET
	Set sc = ..RaiseRequest(row, .ref)
	If $$$ISERR(sc) {
		$$$LOGERROR("The persona request could not be raised: "_$SYSTEM.Status.GetErrorText(sc))
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set notice = ..Notice("approval", ..#KEYPROPOSED, {"old": (before.%Get("text")), "new": (after.%Get("text"))}, sessionRef, ref)
	Do ..Send(notice)
	Set result = ..Result(1, "proposed", ..#MESSAGEPROPOSED)
	Set result.Ref = ref
	Quit result
}

/// The persona as the DryRun holds it: {preset, language, custom, text}. An empty preset is professional. text is what the person reads:
/// the preset's name, the language name for the language preset, or the custom text for the custom preset.
ClassMethod PersonaPart(preset As %String, language As %String, custom As %String) As %DynamicObject [ Private ]
{
	If preset = "" Set preset = "professional"
	Set entry = ##class(OcuTalon.Agent.Persona).Preset(preset)
	Set text = $Select(preset = "language": language, preset = "custom": custom, $IsObject(entry): entry.%Get("name"), 1: preset)
	Set part = {}
	Do part.%Set("preset", preset, "string")
	Do part.%Set("language", language, "string")
	Do part.%Set("custom", custom, "string")
	Do part.%Set("text", text, "string")
	Quit part
}

/// The DryRun key of a session's persona: person.<sessionRef>.persona.
ClassMethod PersonaRoot(sessionRef As %String) As %String [ Private ]
{
	Quit "person."_sessionRef_".persona"
}

/// Raises the request of the row (a seam for the tests): OcuTalon.Bridge.Approval.Raise with the session and the SuperSession of this job. ref is
/// the new request's Ref.
Method RaiseRequest(row As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Approval).Raise(row, .ref, , ..%SessionId, ..%SuperSession)
}

/// Sends the notification to the Notify item, asynchronously, with no answer wanted (a seam for the tests).
Method SendNotice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ..SendRequestAsync("Notify", notification, 0)
}

/// A notification of the kind with the catalog key and the slots, for the session and the request's Ref.
ClassMethod Notice(kind As %String, key As %String, slots As %DynamicObject, sessionRef As %String, approvalRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set notice = ##class(OcuTalon.Msg.Notification).%New()
	Set notice.Kind = kind
	Set notice.CatalogKey = key
	Set notice.Slots = slots.%ToJSON()
	Set notice.SessionRef = sessionRef
	Set notice.ApprovalRef = approvalRef
	Quit notice
}

/// Sends the notice; an error, or a throw, is logged and changes nothing else.
Method Send(notice As OcuTalon.Msg.Notification) [ Private ]
{
	Try {
		Set sc = ..SendNotice(notice)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) $$$LOGWARNING(..#LOGNOTICE_notice.CatalogKey_": "_$SYSTEM.Status.GetErrorText(sc))
}

/// An ApprovalOutcome from ApprovalHold for a request that this operation raised: approved, rejected or expired, as the request's row shows
/// it. Anything else is dropped with one warning and nothing is written, sent or changed: an unknown request, a request that is not a
/// setting request of this operation for its owner's own persona (Kind, ResultTarget, the DryRun's key and ownerRef), another outcome
/// (cancelled included), or an outcome that the row does not show (a repeat or a stale one).
///   - rejected, expired: the answered notice only;
///   - approved: Bridge.Approval.StartExecution (which refuses a request past its expiry), then, when the stored persona still equals the
///     DryRun's old (an empty stored preset is professional), WritePersona of the DryRun's new values and FinishExecution done; the
///     answered notice and then persona.applied. Otherwise nothing is written, FinishExecution says failed, and the notices are the
///     answered notice and then persona.stale. A start that is refused, a write that fails or throws, or a session that has ended is
///     logged, closes the request failed and sends the answered notice only.
Method Outcome(outcome As OcuTalon.Bridge.Msg.ApprovalOutcome) As %Status [ Private ]
{
	Set event = outcome.Outcome
	Set row = $Select(##class(OcuTalon.Bridge.Approval).IsRef(outcome.ApprovalRef): ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(outcome.ApprovalRef), 1: "")
	If '$ListFind($ListBuild("approved", "rejected", "expired"), event) || '..Owns(row, .dryRun) || (row.State '= event) {
		$$$LOGWARNING(..#LOGDROPPED_$Extract(outcome.ApprovalRef, 1, 64)_" "_$Extract(event, 1, 32)_" "_$Select($IsObject(row): row.State, 1: "none"))
		Quit $$$OK
	}
	Set ref = row.Ref
	Set sessionRef = row.OwnerRef
	Set answered = ..AnswerNotice(event, row)
	Set result = ""
	If event = "approved" {
		Set sc = ##class(OcuTalon.Bridge.Approval).StartExecution(ref)
		If $$$ISERR(sc) {
			$$$LOGERROR("The persona request "_ref_" could not be started: "_$SYSTEM.Status.GetErrorText(sc))
			Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, "failed")
			If $$$ISERR(sc) $$$LOGERROR("The persona request "_ref_" could not be closed: "_$SYSTEM.Status.GetErrorText(sc))
		} Else {
			Set finish = "failed"
			Try {
				Set stored = dryRun.%Get("new")
				If '..HasSession(sessionRef) {
					$$$LOGERROR("The persona request "_ref_" is for a session that has ended: nothing is written")
				} ElseIf ..PersonaIs(sessionRef, dryRun.%Get("old")) {
					Set sc = ..WritePersona(row.AnsweredBy, sessionRef, row.AnsweredChannel, "", stored.%Get("preset"), stored.%Get("language"), stored.%Get("custom"))
					Set finish = $Select($$$ISOK(sc): "done", 1: "failed")
					Set result = $Select($$$ISOK(sc): ..#KEYAPPLIED, 1: "")
				} Else {
					Set result = ..#KEYSTALE
				}
			} Catch exception {
				$$$LOGERROR("The persona request "_ref_" could not be carried out: "_$SYSTEM.Status.GetErrorText(exception.AsStatus()))
				Set finish = "failed", result = ""
			}
			Set sc = ##class(OcuTalon.Bridge.Approval).FinishExecution(ref, finish)
			If $$$ISERR(sc) $$$LOGERROR("The persona request "_ref_" could not be closed: "_$SYSTEM.Status.GetErrorText(sc))
		}
	}
	Do ..Send(answered)
	If result '= "" Do ..Send(..Notice("result", result, {}, sessionRef, ref))
	Quit $$$OK
}

/// 1 when the row is a setting request of this operation for its owner's own persona: Kind setting, ResultTarget RESULTTARGET, and a
/// DryRun whose key is person.<OwnerRef>.persona and whose ownerRef is the OwnerRef. dryRun is then the DryRun as an object.
ClassMethod Owns(row As OcuTalon.Bridge.Data.ApprovalRequest, Output dryRun As %DynamicObject) As %Boolean [ Private ]
{
	Set dryRun = ""
	If '$IsObject(row) || (row.Kind '= "setting") || (row.ResultTarget '= ..#RESULTTARGET) Quit 0
	Try {
		Set dryRun = {}.%FromJSON(row.DryRun)
		Set owns = (dryRun.%Get("key") = ..PersonaRoot(row.OwnerRef)) && (dryRun.%Get("ownerRef") = row.OwnerRef) && (dryRun.%GetTypeOf("old") = "object") && (dryRun.%GetTypeOf("new") = "object")
	} Catch exception {
		Set owns = 0
	}
	Quit owns
}

/// 1 when the stored persona of the session equals the DryRun's old object in preset, language and custom (an empty stored preset is
/// professional).
ClassMethod PersonaIs(sessionRef As %String, old As %DynamicObject) As %Boolean [ Private ]
{
	Set stored = ..PersonaPart(..Stored(..PersonaKey(sessionRef, "preset")), ..Stored(..PersonaKey(sessionRef, "language")), ..Stored(..PersonaKey(sessionRef, "custom")))
	Quit (stored.%Get("preset") = old.%Get("preset")) && (stored.%Get("language") = old.%Get("language")) && (stored.%Get("custom") = old.%Get("custom"))
}

/// The notification that answers an approved, rejected or expired request (kind answered): answered.approved and answered.rejected
/// with the channel and time of the answer, or answered.expired with the request's ExpiresAt; the request's Ref as ApprovalRef.
Method AnswerNotice(event As %String, row As OcuTalon.Bridge.Data.ApprovalRequest) As OcuTalon.Msg.Notification [ Private ]
{
	If event = "expired" {
		Set key = ..#KEYEXPIRED
		Set slots = {"time": (row.ExpiresAt)}
	} Else {
		Set key = $Select(event = "approved": ..#KEYAPPROVED, 1: ..#KEYREJECTED)
		Set slots = {"channel": (row.AnsweredChannel), "time": (row.AnsweredAt)}
	}
	Quit ..Notice("answered", key, slots, row.OwnerRef, row.Ref)
}

/// 1 when the session has a Session row; irisUser is then the row's IRIS user, else the user of this job (the rule of
/// SessionOps.IrisUser), and traceRef the row's TraceRef.
ClassMethod HasSession(sessionRef As %String, Output irisUser As %String, Output traceRef As %String) As %Boolean [ Private ]
{
	Set irisUser = $Username, traceRef = ""
	Set session = $Select(sessionRef = "": "", 1: ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef))
	If '$IsObject(session) Quit 0
	If session.IrisUser '= "" Set irisUser = session.IrisUser
	Set traceRef = session.TraceRef
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

/// The Message of an email save on the online demo (Public text P2).
Parameter MESSAGEUNAVAILABLE = "Email can't be connected on the online demo. Nothing was changed.";

/// The Interoperability credential that holds the mailbox's user name and password (AD-19).
Parameter CREDENTIAL = "OcuTalonMail";

/// The production item that reads the mailbox, and the one that sends email.
Parameter MAILITEM = "EmailIn";

Parameter SENDITEM = "EmailOut";

/// The Description of the System Default Settings rows of the mail item.
Parameter ROWDESCRIPTION = "Written by SettingsOps when an admin saves the mailbox (Stories 21.2 and 21.6); do not edit.";

/// The most characters of a mail password and of a client secret, and of a client ID.
Parameter PASSWORDMAX = 256;

Parameter CLIENTIDMAX = 256;

/// The sign-in methods, and the status mark of the sign-in state.
Parameter SIGNINS = "password,google,microsoft";

Parameter SIGNINMARK = "emailSignIn";

/// The rows of a provider sign-in on the mail items (Story 21.8): IRIS's OAuth2 client OcuTalonMail (the application name, as Channel.Email.OAuth names it)
/// and the handler class that gets its access token.
Parameter OAUTHAPPLICATION = "OcuTalonMail";

Parameter OAUTHHANDLER = "OcuTalon.Channel.Email.Token";

/// The POP3 port of a server written without one (implicit TLS), and the port that uses STARTTLS (RFC 2595).
Parameter DEFAULTPORT = 995;

Parameter STARTTLSPORT = 110;

/// The SMTP port of a server written without one (STARTTLS, RFC 6409), and the port that uses implicit TLS (RFC 8314); every other port uses STARTTLS.
Parameter DEFAULTSMTPPORT = 587;

Parameter IMPLICITSMTPPORT = 465;

/// How many times the detached production update tries, and the seconds between the tries.
Parameter UPDATETRIES = 3;

Parameter UPDATEPAUSE = 3;

/// The longest value of a bridge field that Save passes on to Bridge.Settings.
Parameter BRIDGEMAX = 200;

/// The agents whose models the models section changes, in the order of the page (the first runner items of Decide).
Parameter AGENTS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// The prices that the models section changes, in the order of the page: the keys of Bridge.Settings.SetPrice and the Price properties.
Parameter PRICEKEYS = "input,output,cacheRead,cacheWrite";

Parameter PRICEPROPERTIES = "InputPerMTok,OutputPerMTok,CacheReadPerMTok,CacheWritePerMTok";

/// How long TestModel waits for Decide's answer, in seconds. It is under the Web Gateway's response timeout and CommandsIn's TIMEOUT.
Parameter TESTWAIT = 45;

/// The sections of the settings page. A section has a slug, a kind (product: its fields are Data.Setting keys that this class writes; bridge:
/// its fields are bridge names that Bridge.Settings changes; demo: read here only, a SetDemoMode switches it) and its fields. A field has a name
/// (the page's and the API's), a key (product) or the bridge name, a type (int, time, channels, bridge or flag), its default and, for an int, its
/// range. A models section has no fields: its body is nested (SaveModels). An email section (Channels, Story 21.2) has its own save (SaveEmail) and its names are those of the form: its fields carry no key. An on-call section (Story 36.4) has its own save (SaveOnCall): its fields are the seven keyed values that it writes through SaveProduct, and the body that it validates also names each person's kind.
XData Sections [ MimeType = application/json ]
{
[
 {"slug": "models", "kind": "models", "fields": []},
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
  {"name": "demoMode", "key": "demo.mode", "type": "flag", "default": "0"}]},
 {"slug": "channels", "kind": "email", "fields": [
  {"name": "address"},
  {"name": "incoming"},
  {"name": "outgoing", "optional": 1},
  {"name": "user"},
  {"name": "signIn", "optional": 1},
  {"name": "clientId", "optional": 1},
  {"name": "password", "optional": 1},
  {"name": "clientSecret", "optional": 1}]},
 {"slug": "on-call", "kind": "oncall", "fields": [
  {"name": "primaryUser", "key": "oncall.primary.user", "default": ""},
  {"name": "primaryEmail", "key": "oncall.primary.email", "default": ""},
  {"name": "primaryChannels", "key": "oncall.primary.channels", "default": "telegram,email"},
  {"name": "backupUser", "key": "oncall.backup.user", "default": ""},
  {"name": "backupEmail", "key": "oncall.backup.email", "default": ""},
  {"name": "backupChannels", "key": "oncall.backup.channels", "default": "telegram,email"},
  {"name": "escalationMinutes", "key": "oncall.escalationMinutes", "type": "int", "min": 1, "max": 1440, "default": "15"}]}
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
/// "providers": Bridge.Settings.Providers(), "instanceZone": Bridge.Time.Zone(), "prices": Prices()}. A stored int that is not a whole number reads as its
/// default. It holds no key and no secret.
ClassMethod Values() As %DynamicObject
{
	Set sections = {}
	Set iterator = ..Sections().%GetIterator()
	While iterator.%GetNext(, .section) {
		If (section.kind = "bridge") || (section.kind = "models") || (section.kind = "email") || (section.kind = "oncall") Continue
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
	If '..OnlineDemo() Do sections.%Set("channels", ..EmailValues())
	If '..OnlineDemo() Do sections.%Set("on-call", ..OnCallValues())
	Quit {"sections": (sections), "bridge": (##class(OcuTalon.Bridge.Settings).Values()), "providers": (##class(OcuTalon.Bridge.Settings).Providers()), "instanceZone": (##class(OcuTalon.Bridge.Time).Zone()), "prices": (..Prices())}
}

/// The models that the models section prices: each model of each supported provider (Bridge.Settings.Providers, in the table's order) that has a
/// Price row of Bridge.Data.Price, in the table's order.
ClassMethod PriceModels() As %List
{
	Set models = ""
	Set providers = ##class(OcuTalon.Bridge.Settings).Providers().%GetIterator()
	While providers.%GetNext(, .row) {
		If 'row.supported Continue
		Set iterator = row.models.%GetIterator()
		While iterator.%GetNext(, .model) {
			If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) && '$ListFind(models, model) Set models = models_$ListBuild(model)
		}
	}
	Quit models
}

/// The prices of PriceModels read from the Price rows, as {model: {input, output, cacheRead, cacheWrite}} with numbers, in US dollars per million tokens.
ClassMethod Prices() As %DynamicObject
{
	Set prices = {}
	Set models = ..PriceModels()
	Set position = 0
	While $ListNext(models, position, model) {
		Set one = {}
		For i = 1:1:$Length(..#PRICEKEYS, ",") {
			Do one.%Set($Piece(..#PRICEKEYS, ",", i), ..PriceNow(model, $Piece(..#PRICEKEYS, ",", i)), "number")
		}
		Do prices.%Set(model, one)
	}
	Quit prices
}

/// The stored price of the model for one of PRICEKEYS, read from its Price row (0 when there is none).
ClassMethod PriceNow(model As %String, key As %String) As %Numeric [ Private ]
{
	Set row = $Select(##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model): ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model), 1: "")
	If '$IsObject(row) Quit 0
	Quit +$Property(row, $Piece(..#PRICEPROPERTIES, ",", $ListFind($ListFromString(..#PRICEKEYS), key)))
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
	If section.kind = "models" Quit ..SaveModels(command, changes)
	If section.kind = "email" Quit ..SaveEmail(command, changes)
	If section.kind = "oncall" Quit ..SaveOnCall(command, changes)
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
/// number, or holds "@{" is not; an int is a whole number of its range, a time is HH:MM, channels is a non-empty list of web, phone, telegram and email
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
			If '$ListFind($ListBuild("web", "phone", "telegram", "email"), one) || $ListFind(picked, one) Quit
			Set picked = picked_$ListBuild(one)
		}
		If $ListLength(picked) '= $Length(text, ",") Quit 0
		For one = "web", "phone", "telegram", "email" {
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

/// Saves the models section of a SaveSettings command (see the class description); changes is the parsed body. The shape is validated first
/// (ModelsShape), then every changed model goes through BridgeCheckModel, then the prices are written inside one transaction (a SetPrice that is
/// refused rolls it back), their audit entries follow, and then each SetModel with its audit entry. A later failure puts back what was written.
Method SaveModels(command As OcuTalon.Msg.Command.SaveSettings, changes As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set bad = []
	If '..ModelsShape(changes, bad) Quit ..Refused(bad)
	Do ..ModelsDiff(changes, .models, .prices)
	Set stub = 0
	For i = 0:1:models.%Size() - 1 {
		Set change = models.%Get(i)
		Set sc = ..BridgeCheckModel(change.agent, change.provider, change.model, change.second)
		If $$$ISOK(sc) Continue
		If ..NotImplemented(sc) {
			Set stub = 1
		} Else {
			Do ..AddField(bad, change.field)
		}
	}
	If bad.%Size() Quit ..Refused(bad)
	If stub Quit ..Result(0, "not_built", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTBUILT)
	Set done = [], priced = [], outcome = "done"
	Set level = $TLevel
	TSTART
	Try {
		For i = 0:1:prices.%Size() - 1 {
			Set change = prices.%Get(i)
			Set sc = ..BridgeSetPrice(change.model, change.prices, .old)
			If $$$ISERR(sc) {
				Do ..AddField(bad, "prices."_change.model)
				Continue
			}
			Set iterator = change.prices.%GetIterator()
			While iterator.%GetNext(.key, .value) {
				Do priced.%Push({"kind": "price", "model": (change.model), "key": (key), "from": (old.%Get(key)), "to": (+value)})
			}
		}
	} Catch exception {
		If $TLevel > level TROLLBACK 1
		$$$LOGERROR(exception.DisplayString())
		Set outcome = "failed"
	}
	If (outcome '= "done") || bad.%Size() {
		If $TLevel > level TROLLBACK 1
		If bad.%Size() Quit ..Refused(bad)
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	TCOMMIT
	For i = 0:1:priced.%Size() - 1 Do done.%Push(priced.%Get(i))
	Try {
		For i = 0:1:priced.%Size() - 1 {
			Set change = priced.%Get(i)
			Set sc =..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "price."_change.model_"."_change.key, ..NumberText(change.from), ..NumberText(change.to)))
			If $$$ISERR(sc) {
				Set text = $SYSTEM.Status.GetErrorText(sc)
				$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
				Set outcome = "not_audited"
				Quit
			}
		}
		For i = 0:1:models.%Size() - 1 {
			If outcome '= "done" Quit
			Set change = models.%Get(i)
			Set sc = ..BridgeSetModel(change.agent, change.provider, change.model, change.second, .old)
			If $$$ISERR(sc) {
				$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
				Set outcome = "failed"
				Quit
			}
			Do done.%Push({"kind": "model", "agent": (change.agent), "second": (change.second), "provider": (change.provider), "model": (change.model), "oldProvider": (change.oldProvider), "oldModel": (change.oldModel)})
			Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, ..ModelSetting(change.agent, change.second), ..ModelText(change.oldProvider, change.oldModel), ..ModelText(change.provider, change.model)))
			If $$$ISERR(sc) {
				Set text = $SYSTEM.Status.GetErrorText(sc)
				$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
				Set outcome = "not_audited"
			}
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set outcome = "failed"
	}
	If outcome '= "done" Do ..PutBackModels(command, done)
	If outcome = "not_audited" Quit ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
	If outcome = "failed" Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Quit ..Result(1, "done", ..#MESSAGESECTIONSAVED)
}

/// Puts back what SaveModels wrote (done, oldest first, is an array of {kind: price, model, key, from, to} and {kind: model, agent, second, provider, model,
/// oldProvider, oldModel}), newest first, with an audit entry for each. A value that cannot be put back is logged: the bridge keeps what it holds.
Method PutBackModels(command As OcuTalon.Msg.Command.SaveSettings, done As %DynamicArray) [ Private ]
{
	For i = done.%Size() - 1:-1:0 {
		Set change = done.%Get(i)
		If change.kind = "price" {
			Set back = {}
			Do back.%Set(change.key, change.from, "number")
			Set sc = ..BridgeSetPrice(change.model, back, .ignored)
			Set setting = "price."_change.model_"."_change.key
			Set from = ..NumberText(change.to), to = ..NumberText(change.from)
		} Else {
			Set sc = ..BridgeSetModel(change.agent, change.oldProvider, change.oldModel, change.second, .ignored)
			Set setting = ..ModelSetting(change.agent, change.second)
			Set from = ..ModelText(change.provider, change.model), to = ..ModelText(change.oldProvider, change.oldModel)
		}
		If $$$ISERR(sc) {
			$$$LOGERROR("The value of "_setting_" could not be put back: "_$SYSTEM.Status.GetErrorText(sc))
			Continue
		}
		Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, setting, from, to))
		If $$$ISERR(sc) $$$LOGERROR("The Settings audit entry of a value put back could not be written: "_$SYSTEM.Status.GetErrorText(sc))
	}
}

/// 1 when the body of the models section has the shape {"agents": {<Agent>: {provider, model, secondProvider, secondModel}}, "prices": {<model>: {input, output,
/// cacheRead, cacheWrite}}}: exactly the three AGENTS and exactly the PriceModels, each with exactly its members, as strings (prices: strings or numbers) of at
/// most BRIDGEMAX characters without "@{". Otherwise 0, and bad (a dynamic array) gets the names of the offending agents and "prices.<model>".
ClassMethod ModelsShape(changes As %DynamicObject, bad As %DynamicArray) As %Boolean [ Private ]
{
	Set ok = 1
	Set iterator = changes.%GetIterator()
	While iterator.%GetNext(.name) {
		If (name '= "agents") && (name '= "prices") {
			Do ..AddField(bad, $Extract(name, 1, 64))
			Set ok = 0
		}
	}
	For name = "agents", "prices" {
		If changes.%GetTypeOf(name) '= "object" {
			Do ..AddField(bad, name)
			Set ok = 0
		}
	}
	If 'ok Quit 0
	Set agents = changes.%Get("agents")
	Set iterator = agents.%GetIterator()
	While iterator.%GetNext(.name) {
		If '$ListFind($ListFromString(..#AGENTS), name) {
			Do ..AddField(bad, $Extract(name, 1, 64))
			Set ok = 0
		}
	}
	For i = 1:1:$Length(..#AGENTS, ",") {
		Set agent = $Piece(..#AGENTS, ",", i)
		If '..ValuesShape(agents, agent, "provider,model,secondProvider,secondModel", 0) {
			Do ..AddField(bad, agent)
			Set ok = 0
		}
	}
	Set prices = changes.%Get("prices")
	Set models = ..PriceModels()
	Set iterator = prices.%GetIterator()
	While iterator.%GetNext(.name) {
		If '$ListFind(models, name) {
			Do ..AddField(bad, "prices."_$Extract(name, 1, 64))
			Set ok = 0
		}
	}
	Set position = 0
	While $ListNext(models, position, model) {
		If '..ValuesShape(prices, model, ..#PRICEKEYS, 1) {
			Do ..AddField(bad, "prices."_model)
			Set ok = 0
		}
	}
	Quit ok
}

/// 1 when the member of the parent is an object with exactly the members of keys (a comma-separated list), each a string (or, when numbers is 1, a number or a
/// string) of at most BRIDGEMAX characters that holds no "@{".
ClassMethod ValuesShape(parent As %DynamicObject, member As %String, keys As %String, numbers As %Boolean) As %Boolean [ Private ]
{
	If parent.%GetTypeOf(member) '= "object" Quit 0
	Set object = parent.%Get(member)
	If object.%Size() '= $Length(keys, ",") Quit 0
	Set fine = 1
	For i = 1:1:$Length(keys, ",") {
		Set key = $Piece(keys, ",", i)
		Set type = object.%GetTypeOf(key)
		Set text = object.%Get(key)
		If ((type '= "string") && '(numbers && (type = "number"))) || ($Length(text) > ..#BRIDGEMAX) || (text [ "@{") Set fine = 0
	}
	Quit fine
}

/// Adds the field name to the dynamic array of refused names once.
ClassMethod AddField(bad As %DynamicArray, name As %String) [ Private ]
{
	For i = 0:1:bad.%Size() - 1 {
		If bad.%Get(i) = name Return
	}
	Do bad.%Push(name)
}

/// The changes of a models body against the current values: models is an array of {agent, second, provider, model, oldProvider, oldModel, field} for each
/// first or second model that differs, agent by agent, first model first; prices is an array of {model, prices} for each model with a price that differs,
/// prices holding only the changed keys with their values as given. A value that is not a number counts as a change (SetPrice refuses it).
Method ModelsDiff(changes As %DynamicObject, Output models As %DynamicArray, Output prices As %DynamicArray) [ Private ]
{
	Set models = [], prices = []
	Set agents = changes.%Get("agents")
	For i = 1:1:$Length(..#AGENTS, ",") {
		Set agent = $Piece(..#AGENTS, ",", i)
		Set given = agents.%Get(agent)
		Set oldProvider = ..BridgeCurrent(agent_".provider"), oldModel = ..BridgeCurrent(agent_".model")
		If (given.%Get("provider") '= oldProvider) || (given.%Get("model") '= oldModel) {
			Do models.%Push({"agent": (agent), "second": 0, "provider": (given.%Get("provider")), "model": (given.%Get("model")), "oldProvider": (oldProvider), "oldModel": (oldModel), "field": (agent)})
		}
		Set oldProvider = ..BridgeCurrent(agent_".secondProvider"), oldModel = ..BridgeCurrent(agent_".secondModel")
		If (given.%Get("secondProvider") '= oldProvider) || (given.%Get("secondModel") '= oldModel) {
			Do models.%Push({"agent": (agent), "second": 1, "provider": (given.%Get("secondProvider")), "model": (given.%Get("secondModel")), "oldProvider": (oldProvider), "oldModel": (oldModel), "field": (agent_".second")})
		}
	}
	Set list = ..PriceModels()
	Set position = 0
	While $ListNext(list, position, model) {
		Set given = changes.%Get("prices").%Get(model)
		Set changed = {}
		For j = 1:1:$Length(..#PRICEKEYS, ",") {
			Set key = $Piece(..#PRICEKEYS, ",", j)
			Set value = given.%Get(key)
			If $IsValidNum(value) && ((+value) = (+..BridgeCurrent("price."_model_"."_key))) Continue
			Do changed.%Set(key, value, given.%GetTypeOf(key))
		}
		If changed.%Size() Do prices.%Push({"model": (model), "prices": (changed)})
	}
}

/// The audit setting of an agent's model: <Agent>.model, or <Agent>.secondModel for a second model.
ClassMethod ModelSetting(agent As %String, second As %Boolean) As %String [ Private ]
{
	Quit agent_$Select(second: ".secondModel", 1: ".model")
}

/// The audit form of a model: <provider>/<model>, or "" when there is no model.
ClassMethod ModelText(provider As %String, model As %String) As %String [ Private ]
{
	Quit $Select(model = "": "", 1: provider_"/"_model)
}

/// The audit form of a price: its number with a zero before the point.
ClassMethod NumberText(number As %Numeric) As %String [ Private ]
{
	Set number = +number
	Quit $Select((number > 0) && (number < 1): "0"_number, 1: number)
}

/// Carries out a TestModel and returns the CommandResult to answer (see the class description).
Method TestModel(command As OcuTalon.Msg.Command.TestModel) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set sc = ..BridgeTest(command.Agent, .answer, .refused)
	If refused Quit ..Refused(["agent"])
	If $$$ISERR(sc) {
		$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit ..Result(1, "tested", "", answer.%ToJSON())
}

/// Saves the email section of a SaveSettings command (Stories 21.2 and 21.3; AD-1, AD-17, AD-19; see the class description); changes is the parsed body.
/// In order: the online demo refuses (not_available, nothing offered or read); every field is validated (EmailShape: address, incoming server
/// as host or host:port, user name, the sign-in method with its client ID and origin, and the secrets' hand-off references or nothing) and the secrets taken
/// from the hand-off, so that a refusal names every refused field and changes nothing; then the changes against the stored values, each with its Settings audit entry
/// written first (address and user as "set" or "changed", the server as host:port, the credential as "set" or "removed", the sign-in method as the two names,
/// the client ID as "set", "changed" or "removed", the client secret as "set" or "removed", the owner as the two Refs) and the product keys
/// email.address, email.owner, email.signIn and email.clientId written in one transaction; then the credential OcuTalonMail, the System Default Settings rows
/// of EmailIn and of EmailOut (the outgoing server is audited as email.outgoing, host or host:port off DEFAULTSMTPPORT; a cleared one writes Enabled 0 and
/// deletes the server rows, and with none saved before changes nothing), IRIS's OAuth2 client (RegisterOAuth with a provider, RemoveOAuth when a provider is
/// left; email.oauthOwned and the audit of an enabled or disabled web application follow), the production update that starts or restarts the items and the
/// mark emailSignIn. A failure after the transaction puts the product keys, the credential and the settings rows back as they were (PutBackEmail) and audits
/// the keys put back; a client first registered by this save (from Password) is removed again, and a client that this save replaced, changed or removed in IRIS is not restored: the old provider's client ID is removed and its mark says not signed in (ForgetClient). A save that changes nothing writes the settings rows that differ and nothing else, but still runs the update
/// (StartItem). The secrets are held in local variables only, and killed on every path.
Method SaveEmail(command As OcuTalon.Msg.Command.SaveSettings, changes As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ..OnlineDemo() Quit ..Result(0, "not_available", ..#MESSAGEUNAVAILABLE)
	Set bad = []
	Kill field
	Set unknown = ..EmailShape(changes, .field, bad)
	Set signIn = field("signIn"), provider = (signIn '= "password")
	If signIn = "" Quit ..Refused(bad)
	Set oldSignInKey = ..Stored("email.signIn"), oldSignIn = ..SignInStored(), oldClientId = ..Stored("email.clientId"), oldOwned = ..Stored("email.oauthOwned")
	Set secret = "", clientSecret = ""
	If 'provider {
		If $Get(field("password")) '= "" {
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(field("password"), .secret)
			If $$$ISERR(sc) || ..PasswordProblem(secret) {
				Kill secret
				Set secret = ""
				Do ..AddField(bad, "password")
			}
		} ElseIf '..PasswordStored() {
			Do ..AddField(bad, "password")
		}
	} Else {
		If $Get(field("clientSecret")) '= "" {
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(field("clientSecret"), .clientSecret)
			If $$$ISERR(sc) || ..PasswordProblem(clientSecret) {
				Kill clientSecret
				Set clientSecret = ""
				Do ..AddField(bad, "clientSecret")
			}
		} ElseIf (signIn '= oldSignIn) || (oldClientId = "") {
			Do ..AddField(bad, "clientSecret")
		}
	}
	If bad.%Size() || unknown {
		Kill secret, clientSecret, oldPassword
		Quit ..Refused(bad)
	}
	Set exists = ..ReadCredential(.oldUser, .oldPassword)
	Set passwordWas = exists && (oldPassword '= "")
	Set oldAddress = ..Stored("email.address"), oldOwner = ..Stored("email.owner")
	Set oldIncoming = ..IncomingForm(..ReadItemSetting(..#MAILITEM, "POP3Server"), ..ReadItemSetting(..#MAILITEM, "POP3Port"))
	Set newIncoming = ..IncomingForm(field("host"), field("port"))
	Set oldOutgoing = ..OutgoingForm(..ReadItemSetting(..#SENDITEM, "SMTPServer"), ..ReadItemSetting(..#SENDITEM, "SMTPPort"))
	Set newOutgoing = ..OutgoingForm(field("ohost"), field("oport"))
	Set todo = []
	If field("address") '= oldAddress Do todo.%Push({"setting": "email.address", "from": ($Select(oldAddress = "": "", 1: "set")), "to": ($Select(oldAddress = "": "set", 1: "changed")), "key": "email.address", "value": (field("address")), "old": (oldAddress)})
	If command.SessionRef '= oldOwner Do todo.%Push({"setting": "email.owner", "from": (oldOwner), "to": (command.SessionRef), "key": "email.owner", "value": (command.SessionRef), "old": (oldOwner)})
	If newIncoming '= oldIncoming Do todo.%Push({"setting": "email.incoming", "from": (oldIncoming), "to": (newIncoming), "key": "", "value": "", "old": ""})
	If newOutgoing '= oldOutgoing Do todo.%Push({"setting": "email.outgoing", "from": (oldOutgoing), "to": (newOutgoing), "key": "", "value": "", "old": ""})
	If 'exists || (field("user") '= oldUser) Do todo.%Push({"setting": "email.user", "from": ($Select('exists: "", 1: "set")), "to": ($Select('exists: "set", 1: "changed")), "key": "", "value": "", "old": ""})
	If signIn '= oldSignIn Do todo.%Push({"setting": "email.signIn", "from": (oldSignIn), "to": (signIn), "key": "email.signIn", "value": ($Select(provider: signIn, 1: "")), "old": (oldSignInKey)})
	If provider && (field("clientId") '= oldClientId) Do todo.%Push({"setting": "email.clientId", "from": ($Select(oldClientId = "": "", 1: "set")), "to": ($Select(oldClientId = "": "set", 1: "changed")), "key": "email.clientId", "value": (field("clientId")), "old": (oldClientId)})
	If 'provider && (oldClientId '= "") Do todo.%Push({"setting": "email.clientId", "from": "set", "to": "removed", "key": "email.clientId", "value": "", "old": (oldClientId)})
	If clientSecret '= "" Do todo.%Push({"setting": "email.clientSecret", "from": ($Select((signIn = oldSignIn) && (oldClientId '= ""): "set", 1: "")), "to": "set", "key": "", "value": "", "old": ""})
	If 'provider && (oldClientId '= "") Do todo.%Push({"setting": "email.clientSecret", "from": "set", "to": "removed", "key": "", "value": "", "old": ""})
	If secret '= "" Do todo.%Push({"setting": "email.credential", "from": ($Select(passwordWas: "set", 1: "")), "to": "set", "key": "", "value": "", "old": ""})
	If provider && passwordWas Do todo.%Push({"setting": "email.credential", "from": "set", "to": "removed", "key": "", "value": "", "old": ""})
	Set level = $TLevel
	TSTART
	Try {
		Set iterator = todo.%GetIterator()
		While iterator.%GetNext(, .one) {
			Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, one.setting, one.from, one.to))
			If $$$ISERR(sc) {
				TROLLBACK 1
				Set text = $SYSTEM.Status.GetErrorText(sc)
				$$$LOGERROR("The Settings audit entry could not be written"_$Select(text = "": "", 1: ": "_text))
				Kill secret, clientSecret, oldPassword
				Return ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
			}
			If one.key '= "" Set sc = ..Apply(one.key, one.value)
			If $$$ISERR(sc) {
				TROLLBACK 1
				$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
				Kill secret, clientSecret, oldPassword
				Return ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
			}
		}
		TCOMMIT
	} Catch exception {
		If $TLevel > level TROLLBACK 1
		$$$LOGERROR(exception.DisplayString())
		Kill secret, clientSecret, oldPassword
		Return ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set written = "", newOwned = oldOwned, changed = 0, app = "", didRegister = 0, didRemove = 0
	Set sc = $$$OK
	Kill rows
	Try {
		If provider {
			If 'exists || (field("user") '= oldUser) || passwordWas {
				Set sc = ..WriteCredential(field("user"), "", 'exists || passwordWas)
				If $$$ISOK(sc) Set written = written_$ListBuild("credential")
			}
		} ElseIf (secret '= "") || ('exists) || (field("user") '= oldUser) {
			Set sc = ..WriteCredential(field("user"), secret, 'exists || (secret '= ""))
			If $$$ISOK(sc) Set written = written_$ListBuild("credential")
		}
		If $$$ISOK(sc) Set sc = ..WriteItemSettings(..#MAILITEM, ..ItemRows(field("host"), field("port"), provider), .rows)
		If $$$ISOK(sc) && ((field("ohost") '= "") || (oldOutgoing '= "")) Set sc = ..WriteItemSettings(..#SENDITEM, ..OutRows(field("ohost"), field("oport"), provider), .rows)
		If $$$ISOK(sc) && provider {
			Set sc = ..RegisterOAuth(signIn, field("clientId"), clientSecret, field("origin"), oldOwned, .changed, .newOwned, .app)
			If $$$ISOK(sc) Set didRegister = 1
			If $$$ISOK(sc) Set sc = ..RecordOAuth(command, todo, oldOwned, newOwned, app)
		} ElseIf $$$ISOK(sc) && (oldSignIn '= "password") {
			Set sc = ..RemoveOAuth(oldOwned, .newOwned, .app)
			If $$$ISOK(sc) Set didRemove = 1
			If $$$ISOK(sc) Set sc = ..RecordOAuth(command, todo, oldOwned, newOwned, app)
		}
		If $$$ISOK(sc) Set sc = ..StartItem()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) {
		$$$LOGERROR($SYSTEM.Status.GetErrorText(sc))
		If didRegister && (oldSignIn = "password") {
			Set undone = ..RemoveOAuth(newOwned, .ignored, .undoApp)
			If $$$ISERR(undone) {
				$$$LOGERROR("The mail OAuth2 client could not be removed again: "_$SYSTEM.Status.GetErrorText(undone))
			} ElseIf undoApp '= "" {
				Set audited = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "email.oauthApp", "enabled", "disabled"))
				If $$$ISERR(audited) $$$LOGERROR("The Settings audit entry of the web application disabled again could not be written: "_$SYSTEM.Status.GetErrorText(audited))
			}
		}
		Do ..PutBackEmail(command, todo, $ListFind(written, "credential"), exists, oldUser, oldPassword, .rows)
		If (oldSignIn '= "password") && (didRemove || (didRegister && changed)) Do ..ForgetClient(command, oldSignIn, oldClientId)
		Kill secret, clientSecret, oldPassword
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	If provider {
		Do ..RecordSignIn(signIn, $Select(changed || (signIn '= oldSignIn): 0, 1: ..SignedInMark(signIn)))
	} ElseIf oldSignIn '= "password" {
		Do ..RecordSignIn("password", 0)
	}
	Kill secret, clientSecret, oldPassword
	Quit ..Result(1, "done", ..#MESSAGESECTIONSAVED)
}

/// After a failed save that already replaced, changed or removed IRIS's client of the old provider, which PutBackEmail cannot restore: the old
/// provider's client ID is removed (audited as email.clientId set to removed; not written when that audit fails) and the mark emailSignIn says not
/// signed in, so that Settings never shows the old provider as registered and signed in over a client that is no longer there (DW-1181).
Method ForgetClient(command As OcuTalon.Msg.Command.SaveSettings, provider As %String, clientId As %String) [ Private ]
{
	If clientId '= "" {
		Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "email.clientId", "set", "removed"))
		If $$$ISOK(sc) Set sc = ..Apply("email.clientId", "")
		If $$$ISERR(sc) $$$LOGERROR("The client ID of the mail OAuth2 client replaced by a failed save could not be removed: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do ..RecordSignIn(provider, 0)
}

/// The sign-in method that is saved: password, google or microsoft (an absent key is password).
ClassMethod SignInStored() As %String [ Private ]
{
	Set value = ..Stored("email.signIn")
	Quit $Select(value = "": "password", 1: value)
}

/// 1 when the credential OcuTalonMail exists and holds a password. A test subclass overrides ReadCredential, which it reads through.
ClassMethod PasswordStored() As %Boolean [ Private ]
{
	Set exists = ..ReadCredential(.user, .password)
	Set held = exists && (password '= "")
	Kill password
	Quit held
}

/// The audit entries and the key write that follow a call to IRIS's OAuth2 client: email.oauthApp when the call enabled or disabled the web application
/// (app is "enabled" or "disabled"), then email.oauthOwned when the list changed (the key is written after its audit entry, and added to todo so that a later
/// failure puts it back). An error status is the first failure; the call itself is not undone here.
Method RecordOAuth(command As %RegisteredObject, todo As %DynamicArray, oldOwned As %String, newOwned As %String, app As %String) As %Status [ Private ]
{
	If app '= "" {
		Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "email.oauthApp", $Select(app = "enabled": "disabled", 1: "enabled"), app))
		If $$$ISERR(sc) Quit sc
	}
	If newOwned = oldOwned Quit $$$OK
	Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "email.oauthOwned", oldOwned, newOwned))
	If $$$ISERR(sc) Quit sc
	Do todo.%Push({"setting": "email.oauthOwned", "from": (oldOwned), "to": (newOwned), "key": "email.oauthOwned", "value": (newOwned), "old": (oldOwned)})
	Quit ..Apply("email.oauthOwned", newOwned)
}

/// Registers IRIS's OAuth2 client for the provider (OcuTalon.Channel.Email.OAuth.Register); the one call. A test subclass overrides it.
Method RegisterOAuth(provider As %String, clientId As %String, clientSecret As %String, origin As %String, owned As %String, Output changed As %Boolean, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.OAuth).Register(provider, clientId, clientSecret, origin, owned, .changed, .nowOwned, .app)
}

/// Removes IRIS's OAuth2 client (OcuTalon.Channel.Email.OAuth.Remove); the one call. A test subclass overrides it.
Method RemoveOAuth(owned As %String, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.OAuth).Remove(owned, .nowOwned, .app)
}

/// Starts the sign-in (OcuTalon.Channel.Email.OAuth.Start); the one call. A test subclass overrides it.
Method OAuthStart(provider As %String, origin As %String, owned As %String, Output url As %String, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.OAuth).Start(provider, origin, owned, .url, .nowOwned, .app)
}

/// Whether IRIS's OAuth2 client holds the mailbox's tokens (OcuTalon.Channel.Email.OAuth.State); the one call. A test subclass overrides it.
Method OAuthState(Output signedIn As %Boolean) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Channel.Email.OAuth).State(.signedIn)
}

/// Records the status mark emailSignIn: {at, provider, signedIn}. A failure is logged and changes nothing else. A test subclass overrides it.
ClassMethod RecordSignIn(provider As %String, signedIn As %Boolean) [ Private ]
{
	Set value = {}
	Do value.%Set("at", ##class(OcuTalon.Data.Time).NowUtc(), "string")
	Do value.%Set("provider", provider, "string")
	Do value.%Set("signedIn", +signedIn, "number")
	Set sc = ##class(OcuTalon.Data.StatusMark).Record(..#SIGNINMARK, value.%ToJSON())
	If $$$ISERR(sc) $$$LOGERROR("The sign-in mark could not be recorded: "_$SYSTEM.Status.GetErrorText(sc))
}

/// 1 when the mark emailSignIn says that the provider is signed in and no poll has failed on the sign-in after it (PollFailedOnSignIn). A reader only: the mark
/// keeps its one writer.
ClassMethod SignedInMark(provider As %String) As %Boolean [ Private ]
{
	Set value = ##class(OcuTalon.Data.StatusMark).Get(..#SIGNINMARK)
	If value = "" Quit 0
	Try {
		Set mark = {}.%FromJSON(value)
		Set signedIn = (mark.provider = provider) && (+mark.signedIn = 1) && '..PollFailedOnSignIn(mark.at)
	} Catch {
		Set signedIn = 0
	}
	Quit signedIn
}

/// 1 when the mark emailPoll says that the latest poll failed with the sign-in reason (Channel.Email.Adapter REASONSIGNIN) after the time since, the time of the
/// mark emailSignIn: the provider's sign-in is no longer accepted, whatever the token row says. A poll from before the sign-in, or from the same second (a time stamp has
/// no finer grain, and the poll that failed just before the consent is in that second), is not counted.
ClassMethod PollFailedOnSignIn(since As %String) As %Boolean [ Private ]
{
	Set value = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Channel.Email.Adapter).#MARK)
	If value = "" Quit 0
	Try {
		Set poll = {}.%FromJSON(value)
		Set failed = (+poll.ok = 0) && (poll.reason = ##class(OcuTalon.Channel.Email.Adapter).#REASONSIGNIN) && (poll.at ] since)
	} Catch {
		Set failed = 0
	}
	Quit failed
}

/// Carries out a MailSignIn and returns the CommandResult to answer (see the class description). The online demo is not_available; an action that is not start
/// or check is refused naming action; a mailbox without a provider and a client ID is refused naming signIn, and a page origin that is not an http or https
/// origin naming origin, both before anything is called. A start that has to enable the web application writes the Settings audit entry of that
/// (email.oauthApp) and keeps email.oauthOwned; a failure, an unrecorded enable or a start that IRIS refuses after the enable included, is failed (Ok 0) and answers no address, with the enable still recorded.
Method SignIn(command As OcuTalon.Msg.Command.MailSignIn) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ..OnlineDemo() Quit ..Result(0, "not_available", ..#MESSAGEUNAVAILABLE)
	If (command.Action '= "start") && (command.Action '= "check") Quit ..Refused(["action"])
	Set signIn = ..SignInStored()
	If (signIn = "password") || (..Stored("email.clientId") = "") Quit ..Refused(["signIn"])
	If command.Action = "check" {
		Set sc = ..OAuthState(.signedIn)
		If $$$ISERR(sc) {
			$$$LOGERROR("The mail sign-in could not be checked: "_$SYSTEM.Status.GetErrorText(sc))
			Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
		}
		Do ..RecordSignIn(signIn, signedIn)
		Set data = {}
		Do data.%Set("signedIn", ''signedIn, "boolean")
		Quit ..Result(1, "checked", "", data.%ToJSON())
	}
	If '..IsOrigin(command.PageOrigin) Quit ..Refused(["origin"])
	Set owned = ..Stored("email.oauthOwned")
	Set sc = ..OAuthStart(signIn, command.PageOrigin, owned, .url, .nowOwned, .app)
	If $$$ISERR(sc) {
		$$$LOGERROR("The mail sign-in could not be started: "_$SYSTEM.Status.GetErrorText(sc))
		If ($Get(app) '= "") || ($Get(nowOwned, owned) '= owned) {
			Set nowOwned = $Get(nowOwned, owned)
			If $$$ISERR(..RecordOAuth(command, [], owned, nowOwned, $Get(app))) && (nowOwned '= owned) Do ..Apply("email.oauthOwned", nowOwned)
		}
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set todo = []
	Set sc = ..RecordOAuth(command, todo, owned, nowOwned, app)
	If $$$ISERR(sc) {
		$$$LOGERROR("The enabled web application could not be recorded: "_$SYSTEM.Status.GetErrorText(sc))
		If nowOwned '= owned Do ..Apply("email.oauthOwned", nowOwned)
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit ..Result(1, "started", "", {"url": (url)}.%ToJSON())
}

/// 1 when the text is the origin of a page: http or https, a host name, an IPv4 address or an IPv6 address in square brackets, and an optional port; at most 300 characters.
ClassMethod IsOrigin(text As %String) As %Boolean [ Private ]
{
	Quit ($Length(text) <= 300) && $Match(text, "^https?://([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?$")
}

/// Validates the body of the email section into field: address, host and port (the incoming server), ohost and oport (the outgoing server, both ""
/// for none), user (canonical), signIn (password, google or microsoft; password when absent), clientId, origin and password and clientSecret, the hand-off
/// references or "". Each refused field is named in bad: a field that is missing or is not a
/// JSON string (the outgoing server, signIn, clientId, origin and the two secrets may be missing or empty), one that holds "@{" or a control character, an address that is not
/// one address (IsAddress), a server that is not host or host:port (HostPort: a host name of letters, digits, hyphens and dots, lower-cased; a port 1
/// to 65535, else DEFAULTPORT for incoming and DEFAULTSMTPPORT for outgoing), a user name of 1 to 256 characters, a sign-in method that is not one of SIGNINS,
/// a client ID of more than CLIENTIDMAX characters or with white space, and a password or client secret that is not a
/// reference of SecretHandoff (a refused signIn leaves field("signIn") empty and the rules between the method and the other fields unchecked). With a provider the client ID and
/// the origin (IsOrigin) are required and a password is refused; the origin is not looked at with Password; with Password a client ID or a client
/// secret is refused.
ClassMethod EmailShape(changes As %DynamicObject, Output field, bad As %DynamicArray) As %Boolean [ Private ]
{
	Kill field
	Set field("address") = "", field("host") = "", field("port") = "", field("ohost") = "", field("oport") = "", field("user") = "", field("password") = ""
	Set field("signIn") = "password", field("clientId") = "", field("clientSecret") = "", field("origin") = ""
	For name = "address", "incoming", "outgoing", "user", "password", "signIn", "clientId", "clientSecret", "origin" {
		Set type = changes.%GetTypeOf(name)
		Set text = $Select(type = "string": changes.%Get(name), 1: "")
		If $ListFind($ListBuild("password", "outgoing", "signIn", "clientId", "clientSecret", "origin"), name) && ((type = "unassigned") || ((type = "string") && (text = ""))) Continue
		If (type '= "string") || (text [ "@{") || (..HasControl(text)) {
			Do ..AddField(bad, name)
			If name = "signIn" Set field("signIn") = ""
			Continue
		}
		If (name = "clientId") && ($ZStrip(text, "*W") '= text) {
			Do ..AddField(bad, name)
			Continue
		}
		Set text = $ZStrip(text, "<>W")
		If name = "address" {
			If '..IsAddress(text) {
				Do ..AddField(bad, name)
			} Else {
				Set field("address") = text
			}
		} ElseIf name = "incoming" {
			If '..HostPort(text, ..#DEFAULTPORT, .host, .port) {
				Do ..AddField(bad, name)
			} Else {
				Set field("host") = host, field("port") = port
			}
		} ElseIf name = "outgoing" {
			If '..HostPort(text, ..#DEFAULTSMTPPORT, .host, .port) {
				Do ..AddField(bad, name)
			} Else {
				Set field("ohost") = host, field("oport") = port
			}
		} ElseIf name = "user" {
			If ($Length(text) < 1) || ($Length(text) > 256) {
				Do ..AddField(bad, name)
			} Else {
				Set field("user") = text
			}
		} ElseIf name = "signIn" {
			If '$ListFind($ListFromString(..#SIGNINS), text) {
				Do ..AddField(bad, name)
				Set field("signIn") = ""
			} Else {
				Set field("signIn") = text
			}
		} ElseIf name = "clientId" {
			If ($Length(text) < 1) || ($Length(text) > ..#CLIENTIDMAX) {
				Do ..AddField(bad, name)
			} Else {
				Set field("clientId") = text
			}
		} ElseIf name = "origin" {
			Set field("origin") = text
		} Else {
			If '$Match(text, "^secret://handoff/[0-9A-F]{32}$") {
				Do ..AddField(bad, name)
			} Else {
				Set field(name) = text
			}
		}
	}
	If field("signIn") = "password" {
		For name = "clientId", "clientSecret" {
			If field(name) '= "" Do ..AddField(bad, name)
		}
	} ElseIf field("signIn") '= "" {
		If (field("clientId") = "") && '..Refusing(bad, "clientId") Do ..AddField(bad, "clientId")
		If '..IsOrigin(field("origin")) && '..Refusing(bad, "origin") Do ..AddField(bad, "origin")
		If (field("password") '= "") && '..Refusing(bad, "password") Do ..AddField(bad, "password")
	}
	Set unknown = 0
	Set iterator = changes.%GetIterator()
	While iterator.%GetNext(.name) {
		If '$ListFind($ListBuild("address", "incoming", "outgoing", "user", "password", "signIn", "clientId", "clientSecret", "origin"), name) Set unknown = 1
	}
	Quit unknown
}

/// 1 when the name is already one of the refused fields in bad.
ClassMethod Refusing(bad As %DynamicArray, name As %String) As %Boolean [ Private ]
{
	Set one = ""
	Set iterator = bad.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one = name Quit
	}
	Quit (one = name)
}

/// 1 when the text is one email address: 1 to 254 characters, no control character, one @, a local part of 1 to 64 characters without a space, a
/// comma, a semicolon, an angle bracket, a parenthesis, a square bracket, a backslash or a quote, and a domain with a dot. The one address rule of
/// the form (EmailShape) and of EmailOut's recipients.
ClassMethod IsAddress(text As %String) As %Boolean
{
	Set text = $Get(text)
	Quit (text '= "") && ($Length(text) <= 254) && '..HasControl(text) && $Match(text, "^[^@ ,;<>()\[\]\\""]{1,64}@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z0-9-]+$")
}

/// Splits a server written as host or host:port (text has no surrounding space). 1 and the lower-cased host and the port (defaultPort when the
/// text has none) when the host is letters, digits, hyphens and dots (1 to 253 characters, starting and ending with a letter or digit) and the
/// port 1 to 65535; otherwise 0.
ClassMethod HostPort(text As %String, defaultPort As %Integer, Output host As %String, Output port As %Integer) As %Boolean [ Private ]
{
	Set host = $Piece(text, ":", 1), port = $Select($Length(text, ":") = 2: $Piece(text, ":", 2), 1: defaultPort)
	If ($Length(text, ":") > 2) || '$Match(host, "^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$") || '$Match(port, "^[1-9][0-9]{0,4}$") || (port > 65535) Quit 0
	Set host = $ZConvert(host, "L"), port = +port
	Quit 1
}

/// 1 when the text holds a control character.
ClassMethod HasControl(text As %String) As %Boolean [ Private ]
{
	Quit ($ZStrip(text, "*C") '= text)
}

/// 1 when the password is not acceptable: empty, over PASSWORDMAX characters, with a control character or with "@{".
ClassMethod PasswordProblem(secret As %String) As %Boolean [ Private ]
{
	Quit (secret = "") || ($Length(secret) > ..#PASSWORDMAX) || ..HasControl(secret) || (secret [ "@{")
}

/// The incoming server as the page shows it and the audit records it: host, or host:port when the port is not DEFAULTPORT. "" for no host.
ClassMethod IncomingForm(host As %String, port As %String) As %String [ Private ]
{
	Quit ..ServerForm(host, port, ..#DEFAULTPORT)
}

/// The outgoing server as the page shows it and the audit records it: host, or host:port when the port is not DEFAULTSMTPPORT. "" for no host.
ClassMethod OutgoingForm(host As %String, port As %String) As %String [ Private ]
{
	Quit ..ServerForm(host, port, ..#DEFAULTSMTPPORT)
}

ClassMethod ServerForm(host As %String, port As %String, defaultPort As %Integer) As %String [ Private ]
{
	If host = "" Quit ""
	Quit host_$Select((port = "") || (port = defaultPort): "", 1: ":"_port)
}

/// The SSLConfig of the item for the port: the client configuration (implicit TLS), or with a star STARTTLS. The mailbox item (POP3) uses
/// STARTTLS on port STARTTLSPORT only; the sending item (SMTP) uses implicit TLS on port IMPLICITSMTPPORT only. There is no plain choice.
ClassMethod SslFor(port As %Integer, item As %String = {..#MAILITEM}) As %String [ Private ]
{
	Set starttls = $Select(item = ..#SENDITEM: (port '= ..#IMPLICITSMTPPORT), 1: (port = ..#STARTTLSPORT))
	Quit ##class(OcuTalon.Install.Step.SSL).#NAME_$Select(starttls: "*", 1: "")
}

/// The System Default Settings rows of EmailIn that a mailbox needs, as host and port: name, value pairs in a list, and the OAuth2 rows of OAuthRows (with provider 0
/// both marked for deletion, a third element 1).
ClassMethod ItemRows(host As %String, port As %Integer, provider As %Boolean = 0) As %List [ Private ]
{
	Quit $ListBuild($ListBuild("POP3Server", host), $ListBuild("POP3Port", port), $ListBuild("Credentials", ..#CREDENTIAL), $ListBuild("SSLConfig", ..SslFor(port)), $ListBuild("Enabled", 1)) _ ..OAuthRows(provider)
}

/// The System Default Settings rows that tell an item to sign in with OAuth2 (Story 21.8): with a provider OAuth2ApplicationName and OAuth2CallBackHandler,
/// otherwise the same two marked for deletion. No scope, session or auth-properties row is ever written: the handler names the session, and the scope is fixed
/// at consent.
ClassMethod OAuthRows(provider As %Boolean) As %List [ Private ]
{
	If provider Quit $ListBuild($ListBuild("OAuth2ApplicationName", ..#OAUTHAPPLICATION), $ListBuild("OAuth2CallBackHandler", ..#OAUTHHANDLER))
	Quit $ListBuild($ListBuild("OAuth2ApplicationName", "", 1), $ListBuild("OAuth2CallBackHandler", "", 1))
}

/// The System Default Settings rows of EmailOut for an outgoing server: name, value pairs, and a third element 1 for a row to delete. With a host: the
/// server, the port, the credential, the SSLConfig, SSLCheckServerIdentity 1, Enabled 1 and the OAuth2 rows of OAuthRows. With no host: Enabled 0 and the
/// server, port and OAuth2 rows deleted.
ClassMethod OutRows(host As %String, port As %Integer, provider As %Boolean = 0) As %List [ Private ]
{
	If host = "" Quit $ListBuild($ListBuild("Enabled", 0), $ListBuild("SMTPServer", "", 1), $ListBuild("SMTPPort", "", 1)) _ ..OAuthRows(0)
	Quit $ListBuild($ListBuild("SMTPServer", host), $ListBuild("SMTPPort", port), $ListBuild("Credentials", ..#CREDENTIAL), $ListBuild("SSLConfig", ..SslFor(port, ..#SENDITEM)), $ListBuild("SSLCheckServerIdentity", 1), $ListBuild("Enabled", 1)) _ ..OAuthRows(provider)
}

/// Writes the rows of the list (ItemRows or OutRows) of the item that differ from the stored ones, and deletes the rows marked for deletion that exist. It
/// adds to rows(item, name) the value each row had before ($ListBuild(existed, value)) for PutBackEmail. The first error stops the writes.
Method WriteItemSettings(item As %String, list As %List, ByRef rows) As %Status [ Private ]
{
	Set position = 0
	While $ListNext(list, position, one) {
		Set name = $List(one, 1), value = $List(one, 2), delete = +$ListGet(one, 3)
		Set existed = ..ItemSettingExists(item, name)
		Set old = ..ReadItemSetting(item, name)
		If delete && 'existed Continue
		If 'delete && existed && (old = value) Continue
		Set rows(item, name) = $ListBuild(existed, old)
		Set sc = $Select(delete: ..DeleteItemSetting(item, name), 1: ..WriteItemSetting(item, name, value))
		If $$$ISERR(sc) Quit
	}
	Quit $Get(sc, $$$OK)
}

/// Puts back what a failed email save changed: the product keys of todo (with an audit entry of each put back), the credential when it was written
/// (to oldUser and oldPassword, or deleted when there was none), and the settings rows of rows (by item and name, of EmailIn and EmailOut); then the production is updated again, its status
/// ignored. A step that cannot be put back is logged.
Method PutBackEmail(command As OcuTalon.Msg.Command.SaveSettings, todo As %DynamicArray, credentialWritten As %Boolean, existed As %Boolean, oldUser As %String, oldPassword As %String, ByRef rows) [ Private ]
{
	For i = todo.%Size() - 1:-1:0 {
		Set one = todo.%Get(i)
		If one.key = "" Continue
		Set sc = ..Apply(one.key, one.old)
		If $$$ISERR(sc) {
			$$$LOGERROR("The value of "_one.key_" could not be put back: "_$SYSTEM.Status.GetErrorText(sc))
			Continue
		}
		Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, one.setting, one.to, one.from))
		If $$$ISERR(sc) $$$LOGERROR("The Settings audit entry of a value put back could not be written: "_$SYSTEM.Status.GetErrorText(sc))
	}
	If credentialWritten {
		Set sc = $Select(existed: ..WriteCredential(oldUser, oldPassword, 1), 1: ..DeleteCredential())
		If $$$ISERR(sc) $$$LOGERROR("The mail credential could not be put back: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Set item = ""
	For {
		Set item = $Order(rows(item))
		Quit:item=""
		Set name = ""
		For {
			Set name = $Order(rows(item, name), 1, was)
			Quit:name=""
			Set sc = $Select($List(was, 1): ..WriteItemSetting(item, name, $List(was, 2)), 1: ..DeleteItemSetting(item, name))
			If $$$ISERR(sc) $$$LOGERROR("The setting "_name_" of the mail item "_item_" could not be put back: "_$SYSTEM.Status.GetErrorText(sc))
		}
	}
	Do ..StartItem()
}

/// The values of the email section for the page (Values): {address, incoming, outgoing, user, passwordSet, signIn, clientId, clientSecretSet, signedIn}. The user
/// name comes from the credential and the servers from the items' settings rows; the password is never read: passwordSet is whether the credential exists with the Password method (a provider keeps no password). With a
/// provider, clientSecretSet says that a client is registered (the secret itself is never read) and signedIn is the mark emailSignIn for that provider.
ClassMethod EmailValues() As %DynamicObject
{
	Set exists = 0, user = ""
	Try {
		Set exists = ..ReadCredential(.user, .password, 0)
	} Catch {
		Set exists = 0, user = ""
	}
	Kill password
	Set signIn = ..SignInStored(), clientId = ..Stored("email.clientId")
	Set values = {}
	Do values.%Set("address", ..Stored("email.address"), "string")
	Do values.%Set("incoming", ..IncomingForm(..ReadItemSetting(..#MAILITEM, "POP3Server"), ..ReadItemSetting(..#MAILITEM, "POP3Port")), "string")
	Do values.%Set("outgoing", ..OutgoingForm(..ReadItemSetting(..#SENDITEM, "SMTPServer"), ..ReadItemSetting(..#SENDITEM, "SMTPPort")), "string")
	Do values.%Set("user", $Select(exists: user, 1: ""), "string")
	Do values.%Set("passwordSet", (exists && (signIn = "password")), "boolean")
	Do values.%Set("signIn", signIn, "string")
	Do values.%Set("clientId", clientId, "string")
	Do values.%Set("clientSecretSet", ((signIn '= "password") && (clientId '= "")), "boolean")
	Do values.%Set("signedIn", $Select(signIn = "password": 0, 1: ..SignedInMark(signIn)), "boolean")
	Quit values
}

/// 1 when the credential OcuTalonMail exists; user is its user name, and password its password only when withPassword is 1 (the caller holds it
/// in memory and kills it; the page's read never loads it). A test subclass overrides it.
ClassMethod ReadCredential(Output user As %String, Output password As %String, withPassword As %Boolean = 1) As %Boolean
{
	Set user = "", password = ""
	If '##class(Ens.Config.Credentials).%ExistsId(..#CREDENTIAL) Quit 0
	Set credential = ##class(Ens.Config.Credentials).%OpenId(..#CREDENTIAL)
	If '$IsObject(credential) Quit 0
	Set user = credential.Username
	If withPassword Set password = credential.Password
	Quit 1
}

/// Writes the credential OcuTalonMail. With setPassword 0 only the user name changes and the stored password stays. A test subclass overrides it.
ClassMethod WriteCredential(user As %String, password As %String, setPassword As %Boolean) As %Status [ Private ]
{
	If setPassword Quit ##class(Ens.Config.Credentials).SetCredential(..#CREDENTIAL, user, password, 1)
	Set credential = ##class(Ens.Config.Credentials).%OpenId(..#CREDENTIAL)
	If '$IsObject(credential) Quit $SYSTEM.Status.Error(5001, "The mail credential cannot be opened")
	Set credential.Username = user
	Quit credential.%Save()
}

/// Deletes the credential OcuTalonMail. A test subclass overrides it.
ClassMethod DeleteCredential() As %Status [ Private ]
{
	If '##class(Ens.Config.Credentials).%ExistsId(..#CREDENTIAL) Quit $$$OK
	Quit ##class(Ens.Config.Credentials).%DeleteId(..#CREDENTIAL)
}

/// The System Default Settings row of the mail item (MAILITEM or SENDITEM) for the setting: its id. A test subclass overrides the four methods below that use it.
ClassMethod ItemSettingId(item As %String, name As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Install.Step.Production).#PRODUCTION_"||"_item_"||*||"_name
}

/// 1 when the settings row exists.
ClassMethod ItemSettingExists(item As %String, name As %String) As %Boolean [ Private ]
{
	Quit ##class(Ens.Config.DefaultSettings).%ExistsId(..ItemSettingId(item, name))
}

/// The value of the settings row, "" when there is none.
ClassMethod ReadItemSetting(item As %String, name As %String) As %String [ Private ]
{
	Set id = ..ItemSettingId(item, name)
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit ""
	Quit ##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue
}

/// Writes the settings row of the mail item.
ClassMethod WriteItemSetting(item As %String, name As %String, value As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).WriteDefault(##class(OcuTalon.Install.Step.Production).#PRODUCTION, item, name, value, ..#ROWDESCRIPTION)
}

/// Deletes the settings row of the mail item.
ClassMethod DeleteItemSetting(item As %String, name As %String) As %Status [ Private ]
{
	Set id = ..ItemSettingId(item, name)
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit $$$OK
	Quit ##class(Ens.Config.DefaultSettings).%DeleteId(id)
}

/// Starts the mail items, or restarts them when they run, so that they read their settings rows: the production update, run by a detached job (UpdateIn),
/// after every successful email save and not only when a row was written. Ens.Director.UpdateProduction changes nothing when nothing differs and starts an
/// enabled item that is not running, so an identical save repeated after an update that never ran (a failed one, or a stopped production) applies what was
/// saved (DW-1139).
/// The update is not called from this job: Ens.Director.UpdateProduction called inside a production job logs the job's registry as not clean and,
/// when an item does not stop in time, ends the calling job. The save does not wait for the update: the item starts within seconds, and the page
/// says that the change applies within a minute. With no OcuTalon production running it answers OK: the item reads its rows when the production
/// starts. An error status says that the detached job could not be started. A test subclass overrides it.
ClassMethod StartItem() As %Status [ Private ]
{
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= ##class(OcuTalon.Install.Step.Production).#PRODUCTION) Quit $$$OK
	Job ##class(OcuTalon.Core.SettingsOps).UpdateIn():($Namespace):5
	Quit $Select($Test: $$$OK, 1: $SYSTEM.Status.Error(5001, "The production update could not be started"))
}

/// The detached job of StartItem: updates the production, and tries again after a pause when the update does not end OK (at most UPDATETRIES
/// tries); when none ends OK it logs one error line. It runs outside every production job, writes nothing and logs no setting.
ClassMethod UpdateIn() [ Internal ]
{
	For try = 1:1:..#UPDATETRIES {
		Set sc = ##class(Ens.Director).UpdateProduction()
		If $SYSTEM.Status.IsOK(sc) Quit
		Hang ..#UPDATEPAUSE
	}
	If $SYSTEM.Status.IsError(sc) $$$LOGERROR("The production update that applies the mail settings did not end OK")
}

/// Restarts every agent runner item that has a job in the running OcuTalon.Production, so that each rebuilds its agent with the MCP servers
/// registered at that moment (AD-21). The production keeps running. The item list is the installer's (Install.Step.Production.Runners) and the
/// restart is Bridge.Timeouts.Restart's; an item that does not restart is the error. With no OcuTalon production running it answers OK and
/// restarts nothing: the next start builds every agent with the servers registered then.
ClassMethod RestartRunners() As %Status
{
	If '##class(Ens.Director).IsProductionRunning(.name) Set name = ""
	Quit ..RestartIn(name)
}

/// RestartRunners' work for the running production name ("" when none runs): only OcuTalon.Production's runner items restart, and any
/// other name answers OK and restarts nothing.
ClassMethod RestartIn(name As %String) As %Status [ Internal ]
{
	If name '= "OcuTalon.Production" Quit $$$OK
	Set sc = ##class(OcuTalon.Install.Step.Production).Runners(name, .runners)
	If $$$ISERR(sc) Quit sc
	Set list = ""
	For i = 1:1:runners {
		Set list = list _ $ListBuild($ListBuild($List(runners(i), 1), ""))
	}
	Quit ##class(OcuTalon.Bridge.Timeouts).Restart(name, list, 0)
}

/// Writes an MCP server's wallet secret and its Config Store entry AI.MCP.OcuTalon_<server> (AD-19, AD-21). Not built: Story 21.4 builds it.
/// Answers the error code 5003 and writes nothing, so that no caller believes a secret was stored.
ClassMethod SaveMcpEntry(server As %String, url As %String, secret As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5003)
}

/// Removes an MCP server's wallet secret and its Config Store entry (AD-19, AD-21). Not built: Story 21.4 builds it. Answers the error code 5003
/// and removes nothing.
ClassMethod RemoveMcpEntry(server As %String) As %Status
{
	Quit $SYSTEM.Status.Error(5003)
}

/// 1 when the status is the answer "not implemented" (code 5003) of a bridge stub.
ClassMethod NotImplemented(sc As %Status) As %Boolean [ Private ]
{
	Quit ''$ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003)
}

/// The bridge's current value of the field, "" when it holds none: Bridge.Time.Zone() for InstanceZone, Bridge.Settings.Values() for the
/// rest, <Agent>.provider, <Agent>.model, <Agent>.secondProvider and <Agent>.secondModel from its agents, and price.<model>.<key> from the Price row. A
/// test subclass overrides it.
Method BridgeCurrent(name As %String) As %String [ Private ]
{
	If name = "InstanceZone" Quit ##class(OcuTalon.Bridge.Time).Zone()
	If $Extract(name, 1, 6) = "price." {
		Set key = $Piece(name, ".", *)
		Quit ..PriceNow($Extract(name, 7, *-$Length(key)-1), key)
	}
	If name [ "." {
		Set agent = ##class(OcuTalon.Bridge.Settings).Values().agents.%Get($Piece(name, ".", 1))
		Quit $Select($IsObject(agent): agent.%Get($Piece(name, ".", 2)), 1: "")
	}
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

/// The one call of Bridge.Settings.CheckModel. A test subclass overrides it.
Method BridgeCheckModel(agent As %String, provider As %String, model As %String, second As %Boolean) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Settings).CheckModel(agent, provider, model, second)
}

/// The one call of Bridge.Settings.SetModel; old is {provider, model[, retryItem]} as it was. A test subclass overrides it.
Method BridgeSetModel(agent As %String, provider As %String, model As %String, second As %Boolean, Output old As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Settings).SetModel(agent, provider, model, second, .old)
}

/// The one call of Bridge.Settings.SetPrice; old holds all seven values as they were. A test subclass overrides it.
Method BridgeSetPrice(model As %String, prices As %DynamicObject, Output old As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Settings).SetPrice(model, prices, .old)
}

/// The model test of the agent: Bridge.Settings.TestRequest's request sent to Decide synchronously for at most TESTWAIT seconds, timed, and read by
/// TestAnswer into answer, {answered, seconds, reason}. refused is 1 (with the status TestRequest gave) when TestRequest refuses the agent. A wait that
/// expires leaves no response (the status is OK): the answer is then reason timeout. A test subclass overrides it.
Method BridgeTest(agent As %String, Output answer As %DynamicObject, Output refused As %Boolean) As %Status [ Private ]
{
	Set answer = "", refused = 0, response = ""
	Set sc = ##class(OcuTalon.Bridge.Settings).TestRequest(agent, .request)
	If $$$ISERR(sc) {
		Set refused = 1
		Quit sc
	}
	Set started = $ZHorolog
	Set sc = ..SendRequestSync("Decide", request, .response, ..#TESTWAIT)
	Set millis = ($ZHorolog - started * 1000) \ 1
	If $$$ISERR(sc) Quit sc
	Set answer = ##class(OcuTalon.Bridge.Settings).TestAnswer(response, millis)
	If '$IsObject(response) {
		Do answer.%Set("answered", 0, "boolean")
		Do answer.%Set("reason", "timeout", "string")
	}
	Quit $$$OK
}

/// The Message of a saved webhook (the accepted settings text).
Parameter MESSAGEWEBHOOKSAVED = "Saved. Applies within a minute. Recorded in the audit log.";

/// The seconds that TakeSecret waits for a handoff message that the REST process has already signaled.
Parameter HANDOFFWAIT = 2;

/// Carries out a CreateWebhook and returns the CommandResult to answer; see the class description.
Method CreateWebhook(command As OcuTalon.Msg.Command.CreateWebhook) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set secret = ""
	Set taken = ..TakeSecret(command.Handoff, .secret)
	If ..OnlineDemo() Quit ..Result(0, "not_available", ..WebhookFieldText("settings.webhooksOffOnDemo"))
	If $$$ISERR(taken) Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	If '..HasSession(command.SessionRef) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	Set name = $ZStrip(command.Name, "<>W")
	Set fields = {}
	Set problem = ##class(OcuTalon.Data.Webhook).NameProblem(command.Name)
	If problem '= "" Do fields.%Set("name", ..WebhookFieldText(problem, "@{"))
	Set problem = ##class(OcuTalon.Data.Webhook).SecretProblem(secret)
	If problem '= "" Do fields.%Set("secret", ..WebhookFieldText(problem, "@{"))
	If (fields.name = "") && ##class(OcuTalon.Data.Webhook).NameTaken(name) Do fields.%Set("name", ..WebhookFieldText("settings.webhookNameTaken", name))
	If fields.%Size() Quit ..WebhookResult("refused", fields)
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set setting = "webhook."_ref
	Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, setting, "", name))
	If $$$ISERR(sc) {
		$$$LOGERROR("The Settings audit entry of a webhook could not be written")
		Quit ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
	}
	Set row = ##class(OcuTalon.Data.Webhook).%New()
	Set row.Ref = ref
	Set row.Name = name
	Set row.SessionRef = command.SessionRef
	Set row.SecretHash = ##class(OcuTalon.Data.Webhook).HashSecret(secret)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $$$ISERR(sc) {
		Set undone = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, setting, name, ""))
		If ##class(OcuTalon.Data.Webhook).NameTaken(name) {
			Set fields = {}
			Do fields.%Set("name", ..WebhookFieldText("settings.webhookNameTaken", name))
			Quit ..WebhookResult("name_taken", fields)
		}
		$$$LOGERROR("A webhook could not be saved")
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set data = {"ref": (ref), "name": (name), "createdAt": (row.CreatedAt)}
	Quit ..Result(1, "done", ..#MESSAGEWEBHOOKSAVED, data.%ToJSON())
}

/// Carries out a SetWebhookSecret and returns the CommandResult to answer; see the class description.
Method SetWebhookSecret(command As OcuTalon.Msg.Command.SetWebhookSecret) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set secret = ""
	Set taken = ..TakeSecret(command.Handoff, .secret)
	If ..OnlineDemo() Quit ..Result(0, "not_available", ..WebhookFieldText("settings.webhooksOffOnDemo"))
	If $$$ISERR(taken) Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	If '..HasSession(command.SessionRef) Quit ..Result(0, "no_session", ..#MESSAGENOTSAVED)
	Set row = ##class(OcuTalon.Data.Webhook).Lookup(command.WebhookRef)
	If '$IsObject(row) || (row.SessionRef '= command.SessionRef) Quit ..Result(0, "not_found", ..#MESSAGENOTSAVED)
	Set problem = ##class(OcuTalon.Data.Webhook).SecretProblem(secret)
	If problem '= "" {
		Set fields = {}
		Do fields.%Set("secret", ..WebhookFieldText(problem, "@{"))
		Quit ..WebhookResult("refused", fields)
	}
	Set sc = ..WriteAudit(..AuditData(command.Origin, command.ActingUser, command.SessionRef, "webhook."_row.Ref_".secret", "", ""))
	If $$$ISERR(sc) {
		$$$LOGERROR("The Settings audit entry of a webhook secret could not be written")
		Quit ..Result(0, "not_audited", ..#MESSAGESECTIONNOTAUDITED)
	}
	Set row.SecretHash = ##class(OcuTalon.Data.Webhook).HashSecret(secret)
	Set sc = row.%Save()
	If $$$ISERR(sc) {
		$$$LOGERROR("A webhook secret could not be saved")
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit ..Result(1, "done", ..#MESSAGEWEBHOOKSAVED)
}

/// The secret behind a handoff uri (SecretHandoff.Take, waiting at most HANDOFFWAIT seconds); the status is an error when there is none. The secret goes
/// into no message, log or global.
ClassMethod TakeSecret(handoff As %String, Output secret As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.SecretHandoff).Take(handoff, .secret, ..#HANDOFFWAIT)
}

/// The refusal of a webhook command: Ok 0, the outcome (refused or name_taken), the plain not-saved Message and Data {"fields": {name, secret}}.
ClassMethod WebhookResult(outcome As %String, fields As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..Result(0, outcome, ..#MESSAGENOTSAVED, {"fields": (fields)}.%ToJSON())
}

/// The web text of a webhook catalog key: settings.refusedExpansion takes value as its marker, settings.webhookNameTaken as its name; every other key has no slot.
/// The REST route renders its field errors here too. An unreadable key gives the plain not-saved text.
ClassMethod WebhookFieldText(key As %String, value As %String = "") As %String
{
	Set slots = $Case(key, "settings.refusedExpansion": {"marker": (value)}, "settings.webhookNameTaken": {"name": (value)}, : {})
	Set text = ##class(OcuTalon.Msg.Catalog).Render(key, slots, "web", .sc)
	Quit $Select($$$ISERR(sc) || (text = ""): ..#MESSAGENOTSAVED, 1: text)
}

/// The Message of an on-call save on the online demo (the accepted text settings.onCallOffOnDemo).
Parameter MESSAGEONCALLOFF = "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.";

/// The channels that a person can be paged by, in the order that they are stored.
Parameter ONCALLCHANNELS = "telegram,email";

/// The longest user name that can be an OcuTalon user: a longer name is refused as <role>User without a lookup.
Parameter ONCALLUSERMAX = 128;

/// Saves the on-call section of a SaveSettings command (see the class description). changes is the parsed Changes, which holds exactly {"handoff": uri}: the
/// body of the section is behind the uri (SecretHandoff), so that no on-call value is in the command or in the trace. In order: the online demo is not_available
/// (the handoff is discarded); any other Changes is refused; a handoff with nothing behind it is failed; a body that is not a JSON object is refused; every value is
/// validated (OnCallProblems) and a refusal names fields only; then SaveProduct writes the changes, each after its audit entry.
Method SaveOnCall(command As OcuTalon.Msg.Command.SaveSettings, changes As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set handoff = $Select(changes.%GetTypeOf("handoff") = "string": changes.handoff, 1: "")
	If ..OnlineDemo() {
		Do ##class(OcuTalon.Core.SecretHandoff).Discard(handoff)
		Quit ..Result(0, "not_available", ..#MESSAGEONCALLOFF)
	}
	If (changes.%Size() '= 1) || (handoff = "") {
		Do ##class(OcuTalon.Core.SecretHandoff).Discard(handoff)
		Quit ..Refused([])
	}
	Set taken = ..TakeSecret(handoff, .text)
	If $$$ISERR(taken) Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(text)
	} Catch {
		Set body = ""
	}
	Kill text
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit ..Refused([])
	Set bad = ..OnCallProblems(body, .to, .odd)
	If bad.%Size() || odd Quit ..Refused(bad)
	Quit ..SaveProduct(command, ..Section("on-call"), .to)
}

/// The refused fields of an on-call body, as a dynamic array of field names in the form's order (primaryUser, primaryEmail, primaryChannels, the backup three, then
/// escalationMinutes), and in to the value to store for each field when none is refused. odd is 1 when the body has a member that is not one of the nine. A name
/// never carries a value.
ClassMethod OnCallProblems(body As %DynamicObject, Output to, Output odd As %Boolean) As %DynamicArray [ Private ]
{
	Kill to
	Set bad = [], odd = 0
	Set known = $ListBuild("escalationMinutes")
	For role = "primary", "backup" {
		For part = "Person", "User", "Email", "Channels" {
			Set known = known_$ListBuild(role_part)
		}
	}
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.name) {
		If '$ListFind(known, name) Set odd = 1
	}
	Do ..OnCallUsers(.users, .paired)
	For role = "primary", "backup" {
		Set named = ..OnCallRole(role, body, .to, .users, .paired)
		Set position = 0
		While $ListNext(named, position, name) {
			Do bad.%Push(name)
		}
	}
	Set field = ..OnCallField("escalationMinutes")
	If ..Field(field, body, .canonical) {
		Set to("escalationMinutes") = canonical
	} Else {
		Do bad.%Push("escalationMinutes")
	}
	Quit bad
}

/// The row of the on-call section's field with the name.
ClassMethod OnCallField(name As %String) As %DynamicObject [ Private ]
{
	Set fields = ..Section("on-call").fields.%GetIterator()
	While fields.%GetNext(, .field) {
		If field.name = name Quit
	}
	Quit field
}

/// Validates one role (primary or backup) of an on-call body, sets the role's three values to store in to (<role>User, <role>Email, <role>Channels) and returns the
/// names of its refused fields as a list, in the form's order. A member that is missing, is not a JSON string or holds "@{" refuses the field that shows it (the person
/// and the user name belong to the Person select, <role>User). The person nobody ignores the other three members. A user must have a Data.Session row (the name is
/// matched whatever its case and stored as the row holds it; one longer than ONCALLUSERMAX is refused without a lookup), and telegram
/// is reachable only when one of the user's sessions has a paired chat. An address, when the user has one or the person is by email, must pass IsAddress. Every
/// chosen channel must be reachable. A field whose input is refused is not judged again by a rule that needs it: an unknown user has no channels judged, and a refused
/// address does not make the channel email unreachable.
ClassMethod OnCallRole(role As %String, body As %DynamicObject, ByRef to, ByRef users, ByRef paired) As %List [ Private ]
{
	Set user = role_"User", email = role_"Email", channels = role_"Channels"
	Kill named
	If '..OnCallText(body, role_"Person", .kind) || '$ListFind($ListBuild("nobody", "user", "email"), kind) Set named(user) = ""
	If '..OnCallText(body, user, .name) Set named(user) = ""
	If '..OnCallText(body, email, .address) Set named(email) = ""
	If '..OnCallText(body, channels, .list) Set named(channels) = ""
	If '$Data(named) {
		If kind = "nobody" {
			Set to(user) = "", to(email) = "", to(channels) = ..#ONCALLCHANNELS
		} Else {
			Set name = $ZStrip(name, "<>W"), address = $ZStrip(address, "<>W")
			Set mailOk = ..IsAddress(address)
			Set mailBad = $Select(kind = "email": 'mailOk, 1: (address '= "") && 'mailOk)
			If mailBad Set named(email) = ""
			Set known = 0, chat = 0
			If kind = "user" {
				Set known = (name '= "") && ($Length(name) <= ..#ONCALLUSERMAX) && $Data(users($ZConvert(name, "U")))
				If known Set chat = $Data(paired($ZConvert(name, "U"))) > 0
				If 'known Set named(user) = ""
			}
			Set picked = ..OnCallChannels(list)
			If (kind = "email") || known {
				If picked = "" {
					Set named(channels) = ""
				} Else {
					If $ListFind(picked, "telegram") && 'chat Set named(channels) = ""
					If $ListFind(picked, "email") && 'mailOk && 'mailBad Set named(channels) = ""
				}
			}
			Set to(user) = $Select(known: users($ZConvert(name, "U")), 1: ""), to(email) = address, to(channels) = $ListToString(picked)
		}
	}
	Set result = ""
	For field = user, email, channels {
		If $Data(named(field)) Set result = result_$ListBuild(field)
	}
	Quit result
}

/// 1 when the member of the body is a JSON string without "@{"; text is then its value.
ClassMethod OnCallText(body As %DynamicObject, name As %String, Output text As %String) As %Boolean [ Private ]
{
	Set text = ""
	If body.%GetTypeOf(name) '= "string" Quit 0
	Set text = body.%Get(name)
	Quit (text '[ "@{")
}

/// The channels of the text (a comma list) in the order of ONCALLCHANNELS, as a list, or "" when the text is empty, names a channel that is not one of them, or
/// repeats one.
ClassMethod OnCallChannels(text As %String) As %List [ Private ]
{
	Set picked = ""
	For i = 1:1:$Length(text, ",") {
		Set one = $Piece(text, ",", i)
		If '$ListFind($ListFromString(..#ONCALLCHANNELS), one) || $ListFind(picked, one) Quit
		Set picked = picked_$ListBuild(one)
	}
	If $ListLength(picked) '= $Length(text, ",") Quit ""
	Set ordered = ""
	For one = "telegram", "email" {
		If $ListFind(picked, one) Set ordered = ordered_$ListBuild(one)
	}
	Quit ordered
}

/// The OcuTalon users, as a signed-in admin's request can read them: users(<upper-cased name>) is the name as a Data.Session row holds it, for every row that has
/// an IRIS user, and paired(<upper-cased name>) is set when one of the user's sessions has a Data.Pairing row (a chat row has a SessionRef only while it is
/// paired). The rows are read by object access from their extents, because the web process holds no SQL privilege on the tables (as Data.Webhook.ForSession reads).
ClassMethod OnCallUsers(Output users, Output paired) [ Private ]
{
	Kill users, paired
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.PairingD(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.Pairing).%OpenId(id)
		If $IsObject(row) && (row.SessionRef '= "") Set chats(row.SessionRef) = ""
	}
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.SessionD(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.Session).%OpenId(id)
		If '$IsObject(row) || (row.IrisUser = "") Continue
		Set key = $ZConvert(row.IrisUser, "U")
		If '$Data(users(key)) Set users(key) = row.IrisUser
		If $Data(chats(row.Ref)) Set paired(key) = ""
	}
}

/// The on-call member of GET /v1/settings, read from the rows and never from the cache: the seven stored values (an absent row reads as the default; the minutes as a
/// number, and the default for a stored value that is not a whole number), users (each IRIS user with a Data.Session row, once whatever the case of the name, in the order of the upper-cased names, with paired: 1 when one of
/// the user's sessions has a paired chat) and pagesBuilt (1 when OcuTalon.Data.Page is compiled).
ClassMethod OnCallValues() As %DynamicObject
{
	Set values = {}
	Set fields = ..Section("on-call").fields.%GetIterator()
	While fields.%GetNext(, .field) {
		Set stored = ..Stored(field.key)
		If stored = "" Set stored = field.default
		If field.type = "int" {
			Do values.%Set(field.name, $Select((stored ? 1.9N): +stored, 1: +field.default), "number")
		} Else {
			Do values.%Set(field.name, stored, "string")
		}
	}
	Do ..OnCallUsers(.names, .paired)
	Set users = []
	Set key = ""
	For {
		Set key = $Order(names(key), 1, name)
		Quit:key=""
		Set one = {}
		Do one.%Set("user", name, "string")
		Do one.%Set("paired", $Data(paired(key)) > 0, "boolean")
		Do users.%Push(one)
	}
	Do values.%Set("users", users)
	Do values.%Set("pagesBuilt", ##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Data.Page"), "boolean")
	Quit values
}

}
