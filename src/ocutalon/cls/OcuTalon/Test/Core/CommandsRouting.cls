/// Tests of how CommandsIn routes and checks commands (Story 2.3; AD-1, AD-22, AD-26). Safe on a slot: no production runs
/// there, so the tests call OnProcessInput on a shadow instance of OcuTalon.Test.Core.CommandsInProbe, which sends to
/// OcuTalon.Test.Core.CommandsOwner instead of the production. The real Interoperability path is the job of
/// OcuTalon.Test.Core.CommandsInProduction. The oracle of the origin rules and every text are written out here, never read from
/// CommandsIn.
///   - TestRoutes: each of the 10 verbs, with an origin it accepts, reaches exactly its owner item with the same object, key,
///     session and origin, and the owner's result comes back as the same object; Dismiss arrives as an IncidentCommand;
///   - TestOriginRules: every verb by every origin, "zz" and "" included, is routed or refused as the oracle says, and a refusal
///     sends nothing;
///   - TestToolGovernanceRefused: SetDemoMode, Pair, Unpair, EndSession and an IncidentCommand from tool send nothing;
///   - TestContextMeansTool: a bridge context makes the origin tool, whatever the command says;
///   - TestToolDismissOwnIncident: a tool dismisses only an incident that Ownership.Incident returns for its session;
///   - TestStubOwner: an owner stub of either kind gives not_built;
///   - TestOwnerFailure: an owner error, no answer, a wrong answer and a thrown error give failed, and the status is OK;
///   - TestUnknownCommand: a class that is not in the table, and an origin outside the enumeration, send nothing;
///   - TestThread: the send joins the context's thread session and SuperSession;
///   - TestSuperSessionFromSession: outside a context the SuperSession is the TraceRef of the command's session.
/// The run's number is n from ^OcuTalonTest("CommandsRouting","n") (never reset); the owner records the calls of a run under
/// ^OcuTalonTest("CommandsRouting", n), which OnBeforeAllTests and OnAfterAllTests delete with the runs before it. The
/// context of the test process is ended before and after the tests, onlineDemo is put back, and the fixture rows are removed
/// by Test.Data.Fixture.Clean.
Class OcuTalon.Test.Core.CommandsRouting Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..CleanRuns()
	Set ..Number = $Increment(^OcuTalonTest("CommandsRouting", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ..CleanRuns()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $SYSTEM.Status.OK()
}

/// Each verb, with an origin it accepts, reaches its one owner item and nothing else. The owner gets the command object
/// itself (Dismiss: an IncidentCommand with Verb "dismiss"), so the key, session and origin arrive unchanged, and the owner's
/// result is the answer, as the same object.
Method TestRoutes()
{
	Set session = ..Session("routes")
	Set table = $ListBuild("SetReminder|ReminderOps|web_user", "CancelReminder|ReminderOps|web_admin", "ListReminders|ReminderOps|telegram", "StartWatch|WatchOps|tool", "StopWatch|WatchOps|timer", "Dismiss|IncidentManager|web_user", "SetDemoMode|SettingsOps|system", "Pair|SessionOps|telegram", "Unpair|SessionOps|web_user", "EndSession|SessionOps|web_admin")
	Do $$$AssertEquals($ListLength(table), 10, "all 10 verbs are tried")
	For i = 1:1:$ListLength(table) {
		Set verb = $Piece($List(table, i), "|", 1)
		Set owner = $Piece($List(table, i), "|", 2)
		Set origin = $Piece($List(table, i), "|", 3)
		Set probe = ..NewProbe("ok")
		Set command = ..NewCommand(verb, origin, session, "zzkey"_..Number_verb)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(..Calls(), 1, verb_" is sent once")
		Do $$$AssertEquals(..Call(1, "target"), owner, verb_" goes to "_owner)
		Do $$$AssertEquals(..Call(1, "key"), "zzkey"_..Number_verb, verb_": the key arrives unchanged")
		Do $$$AssertEquals(..Call(1, "sessionRef"), session, verb_": the session arrives unchanged")
		Do $$$AssertEquals(..Call(1, "origin"), origin, verb_": the origin arrives unchanged")
		If verb = "Dismiss" {
			Do $$$AssertEquals(..Call(1, "class"), "OcuTalon.Msg.IncidentCommand", "Dismiss arrives as an IncidentCommand")
			Do $$$AssertEquals(..Call(1, "verb"), "dismiss", "with the verb dismiss")
			Do $$$AssertEquals(..Call(1, "incidentRef"), "zzinc"_..Number, "and the incident")
		} Else {
			Do $$$AssertEquals(..Call(1, "class"), "OcuTalon.Msg.Command."_verb, verb_" arrives as its own class")
			Set same = (probe.LastRequest = command)
			Do $$$AssertEquals(same, 1, verb_": the owner gets the command object itself")
		}
		Set same = (output = probe.LastResponse)
		Do $$$AssertEquals(same, 1, verb_": the owner's result is the answer, as the same object")
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome_"|"_output.Message, "1|test|"_owner, verb_": and it is unchanged")
	}
}

/// Every verb by every origin, "zz" and "" too, against an oracle written out here. An accepted pair is routed to its owner;
/// a refused one gets not_allowed with its text, and the owner records nothing. The Dismiss of a tool is of an incident
/// that the session can see.
Method TestOriginRules()
{
	Set session = ..Session("rules")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session)
	Set ..Refs = ..Refs_","_incident
	Set verbs = $ListBuild("SetReminder", "CancelReminder", "ListReminders", "StartWatch", "StopWatch", "Dismiss", "SetDemoMode", "Pair", "Unpair", "EndSession")
	Set origins = $ListBuild("web_user", "web_admin", "telegram", "tool", "timer", "system", "zz", "")
	Set routed = 0
	Set refused = 0
	For v = 1:1:$ListLength(verbs) {
		For o = 1:1:$ListLength(origins) {
			Set verb = $List(verbs, v)
			Set origin = $List(origins, o)
			Set probe = ..NewProbe("ok")
			Set command = ..NewCommand(verb, origin, session, "zzkey"_..Number)
			If verb = "Dismiss" Set command.IncidentRef = incident
			Do probe.OnProcessInput(command, .output)
			Set expected = ..Expected(verb, origin)
			Set label = verb_" from '"_origin_"'"
			If expected = "" {
				Set routed = routed + 1
				Do $$$AssertEquals(..Calls(), 1, label_" is routed")
				Do $$$AssertEquals(..Call(1, "target"), ..OwnerOf(verb), label_" goes to "_..OwnerOf(verb))
				Do $$$AssertEquals(output.Ok, 1, label_" is answered by the owner")
			} Else {
				Set refused = refused + 1
				Do $$$AssertEquals(..Calls(), 0, label_" sends nothing")
				Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", label_" is not_allowed")
				Do $$$AssertEquals(output.Message, expected, label_" says why")
			}
		}
	}
	Do $$$AssertEquals(routed + refused, 80, "all 80 pairs were tried")
	Do $$$AssertTrue(routed > 0 && (refused > 0), "some pairs are routed and some refused: "_routed_" and "_refused)
}

/// A tool may not send a governance verb, whatever its session: nothing is sent. An IncidentCommand is not a verb of the table.
Method TestToolGovernanceRefused()
{
	Set session = ..Session("governance")
	Set probe = ..NewProbe("ok")
	For verb = "SetDemoMode", "Pair", "Unpair", "EndSession" {
		Set command = ..NewCommand(verb, "tool", session, "zzkey"_..Number)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", verb_" from a tool is not_allowed")
		Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", verb_" from a tool says so")
	}
	Set command = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set command.Verb = "dismiss"
	Set command.IncidentRef = "zzinc"_..Number
	Set command.SessionRef = session
	Set command.Origin = "tool"
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|unknown_command", "an IncidentCommand from a tool is not a command of the table")
	Do $$$AssertEquals(..Calls(), 0, "nothing was sent to any owner")
}

/// While a bridge context is active the origin is tool, whatever the command says: SetDemoMode that says web_admin is refused
/// as from the chat, and goes through once the context has ended.
Method TestContextMeansTool()
{
	Set session = ..Session("context")
	Set probe = ..NewProbe("ok")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), "zzss"_..Number), "a context begins")
	Try {
		Set command = ..NewCommand("SetDemoMode", "web_admin", session, "zzkey"_..Number)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "SetDemoMode that says web_admin is refused inside a context")
		Do $$$AssertEquals(output.Message, "That can't be done from the chat. Nothing was changed.", "as from the chat")
		Do $$$AssertEquals(..Calls(), 0, "and nothing is sent")
		Set command = ..NewCommand("ListReminders", "zz", session, "zzkey"_..Number)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok, 1, "a tool verb is routed inside a context, whatever origin the command says")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	Set before = ..Calls()
	Set command = ..NewCommand("SetDemoMode", "web_admin", session, "zzkey"_..Number)
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(output.Ok, 1, "SetDemoMode from web_admin is routed once the context has ended")
	Do $$$AssertEquals(..Calls(), before + 1, "and it is sent")
	Do $$$AssertEquals(..Call(before + 1, "target"), "SettingsOps", "to SettingsOps")
}

/// A tool dismisses only an incident that the session can see: its own noticed incident, or on a local install an instance
/// incident of a production the session watches. Every other incident is not_found and nothing is sent.
Method TestToolDismissOwnIncident()
{
	Set a = ..Session("dismissa")
	Set b = ..Session("dismissb")
	Set production = "Zz.Cmd"_..Number_".Production"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set own = ..Incident(a, "2030-01-01T10:00:00Z", production)
	Set bOwn = ..Incident(b, "2030-01-01T10:00:00Z", production)
	Set unnoticed = ..Incident(a, "", production)
	Set eval = ..Incident("eval", "2030-01-01T10:00:00Z", production)
	Set instance = ..Incident("instance", "2030-01-01T10:00:00Z", production)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set answer = "This session has no such incident. Nothing was changed."
	Set probe = ..NewProbe("ok")

	Do ..Dismiss(probe, a, own, .output)
	Do $$$AssertEquals(output.Ok, 1, "a tool dismisses its own noticed incident")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "class")_"|"_..Call(1, "incidentRef"), "IncidentManager|OcuTalon.Msg.IncidentCommand|"_own, "it goes to IncidentManager")
	Do ..Dismiss(probe, b, instance, .output)
	Do $$$AssertEquals(output.Ok, 1, "and the instance incident of a production it watches, on a local install")
	Do $$$AssertEquals(..Calls(), 2, "both were sent")

	Set refusals = $ListBuild(a_"|"_bOwn_"|another session's incident", a_"|"_unnoticed_"|an unnoticed incident", a_"|"_eval_"|an eval incident", a_"|zzmissing"_..Number_"|an unknown Ref", a_"||an empty Ref", "|"_own_"|an empty session", a_"|"_instance_"|an instance incident of a production it does not watch")
	For i = 1:1:$ListLength(refusals) {
		Set one = $List(refusals, i)
		Do ..Dismiss(probe, $Piece(one, "|", 1), $Piece(one, "|", 2), .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_found", "a tool is refused "_$Piece(one, "|", 3))
		Do $$$AssertEquals(output.Message, answer, "with the text for an incident it can't see")
	}
	Do $$$AssertEquals(..Calls(), 2, "no refusal sent anything")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Dismiss(probe, b, instance, .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_found", "with onlineDemo on, the instance incident is not found")
	Do ..Dismiss(probe, a, own, .output)
	Do $$$AssertEquals(output.Ok, 1, "and the session's own incident still is")
	Do $$$AssertEquals(..Calls(), 3, "which is sent")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// An owner that is still a stub gives not_built whether it is an operation (code 5003) or a process (<Ens>ErrBPTerminated
/// that carries it), with Ok 0 and a status that is OK.
Method TestStubOwner()
{
	Set session = ..Session("stub")
	For mode = "stub-op", "stub-bp" {
		Set probe = ..NewProbe(mode)
		Set command = ..NewCommand("ListReminders", "web_user", session, "zzkey"_..Number)
		Set sc = probe.OnProcessInput(command, .output)
		Do $$$AssertStatusOK(sc, mode_": the status is OK")
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_built", mode_": not_built")
		Do $$$AssertEquals(output.Message, "This part of OcuTalon isn't built yet. Nothing was changed.", mode_": and it says so")
		Do $$$AssertEquals(..Calls(), 1, mode_": the command was sent")
	}
}

/// An owner that fails another way, or answers with nothing or the wrong class, gives failed; so does an error thrown inside
/// the service, which also writes one event-log row (the test deletes it). The status is always OK.
Method TestOwnerFailure()
{
	Set session = ..Session("failure")
	For mode = "error", "none", "wrong" {
		Set probe = ..NewProbe(mode)
		Set command = ..NewCommand("ListReminders", "web_user", session, "zzkey"_..Number)
		Set sc = probe.OnProcessInput(command, .output)
		Do $$$AssertStatusOK(sc, mode_": the status is OK")
		Do $$$AssertEquals($Select($IsObject(output): $ClassName(output), 1: "no object"), "OcuTalon.Msg.CommandResult", mode_": the answer is a CommandResult")
		If $IsObject(output) && output.%IsA("OcuTalon.Msg.CommandResult") {
			Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", mode_": failed")
			Do $$$AssertEquals(output.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", mode_": and it says so")
		}
	}
	Set before = ..LastLogId()
	Set probe = ..NewProbe("throw")
	Set command = ..NewCommand("ListReminders", "web_user", session, "zzkey"_..Number)
	Set sc = probe.OnProcessInput(command, .output)
	Do $$$AssertStatusOK(sc, "throw: the status is OK")
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|failed", "throw: failed")
	Do $$$AssertEquals(output.Message, "Something went wrong inside OcuTalon, so the command may not have finished.", "throw: and it says so")
	Set rows = ..LogRowsAfter(before, $ClassName(probe))
	Do $$$AssertEquals($ListLength(rows), 1, "throw: one event-log row from the service")
	For i = 1:1:$ListLength(rows) {
		Do ##class(Ens.Util.Log).%DeleteId($List(rows, i))
	}
}

/// A class that is not in the table (an IncidentCommand, a message that is not a command, a value that is not an object) is
/// unknown_command; a verb from an origin outside the enumeration is not_allowed. Nothing is sent.
Method TestUnknownCommand()
{
	Set session = ..Session("unknown")
	Set probe = ..NewProbe("ok")
	Set incident = ##class(OcuTalon.Msg.IncidentCommand).%New()
	Set incident.Verb = "closeQuiet"
	Set incident.IncidentRef = "zzinc"_..Number
	Set incident.SessionRef = session
	Set incident.Origin = "system"
	Set labels = $ListBuild("an IncidentCommand", "a message that is not a command", "a dynamic object", "an empty value", "a string")
	For i = 1:1:$ListLength(labels) {
		Set value = $Case(i, 1: incident, 2: ##class(Ens.StringRequest).%New("zz"), 3: {"Origin": "system"}, 4: "", : "zz")
		Do probe.OnProcessInput(value, .output)
		Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|unknown_command", $List(labels, i)_" is unknown_command")
		Do $$$AssertEquals(output.Message, "OcuTalon doesn't know that command. Nothing was changed.", $List(labels, i)_": and it says so")
	}
	Set command = ..NewCommand("ListReminders", "zz", session, "zzkey"_..Number)
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(output.Ok_"|"_output.Outcome, "0|not_allowed", "a verb with an origin outside the enumeration is not_allowed")
	Do $$$AssertEquals(output.Message, "OcuTalon can't take that command from here. Nothing was changed.", "and it says so")
	Do $$$AssertEquals(..Calls(), 0, "nothing was sent")
}

/// Inside a context the send is in the thread session of the context's ThreadSessionId, with its SuperSession; with no
/// ThreadSessionId it is a session of its own that still carries the SuperSession.
Method TestThread()
{
	Set session = ..Session("thread")
	Set super = "zzss"_..Number
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.ThreadSessionId = 424242
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, super), "a context with a thread session begins")
	Try {
		Set probe = ..NewProbe("ok")
		Set command = ..NewCommand("ListReminders", "web_user", session, "zzkey"_..Number)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(..Calls(), 1, "the command is sent")
		Do $$$AssertEquals(probe.SeenSessionId, 424242, "in the thread session of the context")
		Do $$$AssertEquals(probe.SeenSuperSession, super, "with the SuperSession of the context")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(##class(OcuTalon.Bridge.Msg.Request).%New(), super), "a context with no thread session begins")
	Try {
		Set probe = ..NewProbe("ok")
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(probe.SeenSessionId, "", "with no ThreadSessionId the send starts a session of its own")
		Do $$$AssertEquals(probe.SeenSuperSession, super, "which still carries the SuperSession")
	} Catch exception {
		Do $$$AssertTrue(0, "a call inside a context threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// With no context the send starts a session of its own, and its SuperSession is the TraceRef of the Session row of the
/// command's SessionRef; with no SessionRef, an unknown one or the literal instance there is no SuperSession.
Method TestSuperSessionFromSession()
{
	Set session = ..Session("super")
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do $$$AssertTrue(traceRef '= "", "the fixture session has a TraceRef: "_traceRef)
	Set probe = ..NewProbe("ok")
	Set command = ..NewCommand("ListReminders", "web_user", session, "zzkey"_..Number)
	Do probe.OnProcessInput(command, .output)
	Do $$$AssertEquals(probe.SeenSuperSession, traceRef, "the SuperSession is the TraceRef of the command's session")
	Do $$$AssertEquals(probe.SeenSessionId, "", "and the send starts a session of its own")
	For ref = "", "zzmissing"_..Number, "instance" {
		Set probe = ..NewProbe("ok")
		Set command = ..NewCommand("ListReminders", "web_user", ref, "zzkey"_..Number)
		Do probe.OnProcessInput(command, .output)
		Do $$$AssertEquals(output.Ok, 1, "the command of session '"_ref_"' is sent")
		Do $$$AssertEquals(probe.SeenSuperSession, "", "with no SuperSession for session '"_ref_"'")
	}
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzcmd"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture incident; its Ref is kept for the clean-up.
Method Incident(owner As %String, noticedAt As %String, production As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticedAt, "ZZNS", production)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// A shadow instance of the probe whose owner answers by the mode, with the calls of the run cleared.
Method NewProbe(mode As %String) As OcuTalon.Test.Core.CommandsInProbe [ Private ]
{
	Kill ^OcuTalonTest("CommandsRouting", ..Number)
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.CommandsInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Set probe.AnswerMode = mode
	Quit probe
}

/// A command of the verb with the origin, session and key; a Dismiss names the incident zzinc<n>.
Method NewCommand(verb As %String, origin As %String, sessionRef As %String, key As %String) As OcuTalon.Msg.Command [ Private ]
{
	Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
	Set command.Origin = origin
	Set command.SessionRef = sessionRef
	Set command.IdempotencyKey = key
	If verb = "Dismiss" Set command.IncidentRef = "zzinc"_..Number
	Quit command
}

/// A tool's Dismiss of the incident for the session, through the probe; output is the answer.
Method Dismiss(probe As OcuTalon.Test.Core.CommandsInProbe, sessionRef As %String, incidentRef As %String, Output output As OcuTalon.Msg.CommandResult) [ Private ]
{
	Set command = ..NewCommand("Dismiss", "tool", sessionRef, "zzkey"_..Number)
	Set command.IncidentRef = incidentRef
	Do probe.OnProcessInput(command, .output)
}

/// The number of calls the owner has recorded in this run.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("CommandsRouting", ..Number))
}

/// One field of the owner's nth call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("CommandsRouting", ..Number, n, field))
}

/// The owner item that carries the verb out, as the test's own oracle has it.
ClassMethod OwnerOf(verb As %String) As %String [ Private ]
{
	Quit $Case(verb, "SetReminder": "ReminderOps", "CancelReminder": "ReminderOps", "ListReminders": "ReminderOps", "StartWatch": "WatchOps", "StopWatch": "WatchOps", "Dismiss": "IncidentManager", "SetDemoMode": "SettingsOps", : "SessionOps")
}

/// The oracle of the origin rules: "" when the verb from the origin is routed, otherwise the text of its refusal.
ClassMethod Expected(verb As %String, origin As %String) As %String [ Private ]
{
	Set everyone = $ListBuild("web_user", "web_admin", "telegram", "tool", "timer", "system")
	If (origin = "tool") && '$ListFind($ListBuild("SetReminder", "CancelReminder", "ListReminders", "StartWatch", "StopWatch", "Dismiss"), verb) {
		Quit "That can't be done from the chat. Nothing was changed."
	}
	If verb = "SetDemoMode" {
		If '$ListFind($ListBuild("system", "web_admin"), origin) Quit "Only an OcuTalon admin can change settings. Nothing was changed."
		Quit ""
	}
	If verb = "Pair" {
		If origin '= "telegram" Quit "A pairing completes only from Telegram. Nothing was changed."
		Quit ""
	}
	If '$ListFind(everyone, origin) Quit "OcuTalon can't take that command from here. Nothing was changed."
	Quit ""
}

/// The highest ID of the event log, 0 when it is empty.
ClassMethod LastLogId() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The IDs of the event-log rows above the ID that the service wrote, as a list. $$$LOGERROR names the class of the running
/// object as the source, so a probe's row carries the probe's class and the production's carries OcuTalon.Core.CommandsIn.
ClassMethod LogRowsAfter(id As %Integer, sourceClass As %String) As %List [ Private ]
{
	Set rows = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ? AND SourceMethod = 'OnProcessInput' ORDER BY ID", id, sourceClass)
	While result.%Next() {
		Set rows = rows_$ListBuild(result.%Get("ID"))
	}
	Quit rows
}

/// Deletes the calls recorded by the runs, not the counter of the run numbers.
ClassMethod CleanRuns() [ Private ]
{
	Set run = ""
	For {
		Set run = $Order(^OcuTalonTest("CommandsRouting", run))
		Quit:run=""
		If run '= "n" Kill ^OcuTalonTest("CommandsRouting", run)
	}
}

}
