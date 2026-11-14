/// McpOps (AD-1, AD-21, AD-29, AD-33; Lane A): the item of the production that owns the MCP servers an admin registers. It is the only writer of
/// OcuTalon.Mcp.Server and of OcuTalon.Mcp.ToolClassification, and it answers AddMcpServer, RemoveMcpServer and ClassifyTool with an
/// OcuTalon.Msg.CommandResult, and it answers SetSourcePoll and RemoveSourcePoll too (Story 22.5):
///   - SetSourcePoll makes one Read-only tool of a registered server a source, or changes that source: the one BackgroundCheck row of Kind source of the command's session
///     with that name (Watch.Ops SetSource), in one transaction with its MCP audit entry (change source_set, outcome created or updated; the entry never holds an argument),
///     then one CheckChanged. It answers saved with the row's Ref, or not_read_only, not_found, bad_name, reserved_name, bad_arguments or bad_interval, and a refusal writes nothing;
///     a command whose session has no row is failed, and an audit that fails undoes the change (not_audited).
///   - A source's name may not be the one the digest's coverage list gives the connected mailbox (Checks.Coverage ENTRYMAILBOX), in any letter case, after the trim: that is the outcome
///     reserved_name with MESSAGESOURCERESERVED, so the list never shows two entries of one name (DW-1325). "My Mailbox" and "Mailboxes" are different names and are accepted. The
///     Settings relay (Story 21.5) reads the outcome.
///   - RemoveSourcePoll removes the source of a Ref, whatever admin set it, in one transaction with its audit entry (source_removed), then sends a CheckChanged with Stopped 1.
///     It answers removed, or not_found, or not_audited when the audit fails (the source stays). RemoveMcpServer removes the sources of the server too, each in its own
///     transaction, after the drop of the entry and the wallet secret and before Restart; a source that cannot be removed stays, with one warning that names its Ref.
///   - Both source verbs pass the same checks as the three verbs below before anything is written (Refusal: the sender, the origin web_admin, the acting user, the
///     online demo), with the same not_allowed answers. The CheckChanged goes to the Checks item through the seam SendChanged, a private method a test subclass overrides.
///   - AddMcpServer, RemoveMcpServer and ClassifyTool come from CommandsIn with Origin web_admin. Each handler re-checks that the sender is CommandsIn,
///     that the Origin is web_admin (a bridge context counts as origin tool), that ActingUser is not empty and that the install is not the online demo,
///     before it writes anything; a refusal has the outcome not_allowed, and a wrong sender or origin or a missing acting user is also one warning.
///   - The order of an add is Validate (name, address), Register (the row, then the resource and its grant through OcuTalon.Install.Step.Mcp.Grant, then the
///     wallet secret and the Config Store entry), Audit (an MCP entry), Restart (SettingsOps.RestartRunners, after the server's lock is released). A remove is Unregister (the tool rows and the
///     row, then Install.Step.Mcp.Revoke), Audit, then, once the removal has committed, the cancel of the pending approval requests of the server's tools (Approval CancelPending,
///     in the admin's name; a failure is one warning and the removal stands), then the drop of the entry and the wallet secret (a failure is one warning and the
///     removal stands), Restart. A classification is Validate, Save, Audit (a Tool entry; no restart, since the gate reads the rows). An audit that fails undoes
///     the change, and the outcome is not_audited. A restart that fails keeps the change (the next start attaches it), and the outcome is failed.
///   - The address of a server is https://, or http:// to this computer (127.0.0.1, localhost or [::1]) for development, with no user information and no
///     @{ in it (AD-19). An add whose address holds a ? or a # (a query string or a fragment) is refused too, as bad_address with MESSAGEQUERY (Story 21.4), so that no
///     query string sits in the entry's address; AddressAllowed, which Mcp.Proxy asks at call time, is unchanged. This class writes the credential only to the wallet key
///     OcuTalon_MCP_<server>.Key and the address only to the Config Store entry AI.MCP.OcuTalon_<server>, in its own job (Story 21.4; the credential reaches it only
///     through the command's Handoff, a SecretHandoff uri, taken once), and it never logs, audits or puts in a notice the address, a credential or the error text of the
///     wallet, the Config Store or AI Hub. The address also travels in the command and in the settings list, and IRIS's own audit entry of the entry's creation holds it.
///   - Tools: the tools of a server for Settings.
///   - RecordAttach: writes what a runner reported about one attach (OcuTalon.Mcp.Attach.OnAttach) to the server's row (AttachStatus, AttachReason,
///     AttachedAt, RefusedTools) and, for an attached server, keeps one ToolClassification row for each tool it listed or refused (a new one is
///     unclassified, with the fingerprint the report gives), deletes the rows of tools it no longer lists, and clears the classification of a tool whose
///     fingerprint changed (ClearChanged). A server with no row is an error and nothing is written.
///   - ClearChanged: the one way a classified tool becomes unclassified because its fingerprint changed; it audits the change and tells the admins.
///   - Admin notices (kind status, sent to Ownership.AdminSessions) go out once for each transition: a server that turns unavailable
///     (mcp.serverUnavailable), a tool newly refused because it has a built-in's name (mcp.toolShadowsBuiltIn) and a tool that changed
///     (mcp.toolChanged). The same report again sends nothing.
/// The seams OnlineDemo, AdminSessions, Notice, Restart and WriteAudit are private class methods that a test subclass overrides.
Class OcuTalon.Mcp.Ops Extends Ens.BusinessOperation
{

/// The statuses of an attach that a row holds.
Parameter STATUSES = "attached,unavailable";

/// The item that sends the three verbs.
Parameter COMMANDSENDER = "CommandsIn";

/// The only origin the three verbs are carried out for.
Parameter ORIGIN = "web_admin";

/// The longest a stored fingerprint is.
Parameter FINGERPRINTLENGTH = 64;

/// The hosts that an http:// address may name.
Parameter LOOPBACKHOSTS = "127.0.0.1,localhost,[::1]";

Parameter MESSAGEADDED = "The MCP server was added. Its tools count as risky until an admin classifies them.";

Parameter MESSAGEREMOVED = "The MCP server was removed, so its tools can't be used.";

Parameter MESSAGEADDRESS = "An MCP server's address must start with https:// (or point to this computer, for development). Nothing was changed.";

Parameter MESSAGEQUERY = "An MCP server's address can't hold a query string (the part after ?). Put a key in Secret instead. Nothing was changed.";

Parameter MESSAGENAME = "An MCP server's name is a letter followed by up to 39 letters, digits or underscores. Nothing was changed.";

Parameter MESSAGEEXISTS = "An MCP server with that name already exists. Nothing was changed.";

Parameter MESSAGENOSERVER = "There is no MCP server with that name. Nothing was changed.";

Parameter MESSAGENOTOOL = "That MCP server has no tool with that name. Nothing was changed.";

Parameter MESSAGECLASSIFICATION = "A tool is Unclassified, Read-only or Risky. Nothing was changed.";

Parameter MESSAGESAVED = "Saved";

Parameter MESSAGENOTREADONLY = "Only a Read-only tool can be a source. Nothing was changed.";

Parameter MESSAGESOURCENAME = "A source's name is 1 to 100 characters. Nothing was changed.";

Parameter MESSAGESOURCERESERVED = "That name belongs to the connected mailbox. Choose another name.";

Parameter MESSAGESOURCEARGUMENTS = "A source's arguments must be a JSON object of up to 4,000 characters, with no secret in it. Nothing was changed.";

Parameter MESSAGESOURCEINTERVAL = "A source is polled every 5 to 1,440 minutes. Nothing was changed.";

Parameter MESSAGENOSOURCE = "There is no source with that reference. Nothing was changed.";

Parameter MESSAGESOURCEREMOVED = "The source was removed.";

/// The configuration item that publishes the change of a check (AD-33).
Parameter CHECKS = "Checks";

/// The fewest and the most minutes between two polls of a source.
Parameter INTERVALMIN = 5;

Parameter INTERVALMAX = 1440;

/// The longest a source's name is, in characters, and the longest the text of its arguments is.
Parameter NAMEMAX = 100;

Parameter ARGUMENTSMAX = 4000;

/// The description of the entry that SaveEntry writes.
Parameter ENTRYDESCRIPTION = "Written by McpOps for an MCP server an admin added; do not edit.";

/// The read and edit resource of that entry: the Config Store's default (AD-19).
Parameter ENTRYRESOURCE = "%Admin_ConfigStore";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.AddMcpServer">
<Method>OnAdd</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.RemoveMcpServer">
<Method>OnRemove</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.ClassifyTool">
<Method>OnClassify</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.SetSourcePoll">
<Method>OnSetSource</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Command.RemoveSourcePoll">
<Method>OnRemoveSource</Method>
</MapItem>
</MapItems>
}

/// Registers a server: the row, the resource and its grant, the audit entry, the restart of the runners. See the class description.
Method OnAdd(request As OcuTalon.Msg.Command.AddMcpServer, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ..Refusal(request, "AddMcpServer")
	If $IsObject(response) Quit $$$OK
	Set server = request.Server
	If '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Quit ..Answer(.response, 0, "bad_name", ..#MESSAGENAME)
	If '..AddressAllowed(request.Url) Quit ..Answer(.response, 0, "bad_address", ..#MESSAGEADDRESS)
	If (request.Url [ "?") || (request.Url [ "#") Quit ..Answer(.response, 0, "bad_address", ..#MESSAGEQUERY)
	If '..Lock(server) Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Set sc = $$$OK
	Set restart = 0
	Try {
		Set sc = ..Register(request, .response, .restart)
	} Catch exception {
		Set response = ""
		Set restart = 0
		Set sc = ..Failed(.response, "the MCP server could not be added", exception.AsStatus())
	}
	Lock -^OcuTalon.Mcp.Server(server)
	If restart Quit ..Restarted(.response, "added", ..#MESSAGEADDED, "the runners could not be restarted after the MCP server was added")
	Quit sc
}

/// Removes a server: its tool rows, its row, its resource and grant, the audit entry, the restart of the runners. See the class description.
Method OnRemove(request As OcuTalon.Msg.Command.RemoveMcpServer, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ..Refusal(request, "RemoveMcpServer")
	If $IsObject(response) Quit $$$OK
	Set server = request.Server
	If '..Lock(server) Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Set sc = $$$OK
	Set restart = 0
	Try {
		Set sc = ..Unregister(request, .response, .restart)
	} Catch exception {
		Set response = ""
		Set restart = 0
		Set sc = ..Failed(.response, "the MCP server could not be removed", exception.AsStatus())
	}
	Lock -^OcuTalon.Mcp.Server(server)
	If restart Quit ..Restarted(.response, "removed", ..#MESSAGEREMOVED, "the runners could not be restarted after the MCP server was removed")
	Quit sc
}

/// Sets the classification of one tool: the row, the audit entry. See the class description.
Method OnClassify(request As OcuTalon.Msg.Command.ClassifyTool, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ..Refusal(request, "ClassifyTool")
	If $IsObject(response) Quit $$$OK
	Set server = request.Server
	If '..Lock(server) Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Set sc = $$$OK
	Try {
		Set sc = ..Classify(request, .response)
	} Catch exception {
		Set response = ""
		Set sc = ..Failed(.response, "the tool could not be classified", exception.AsStatus())
	}
	Lock -^OcuTalon.Mcp.Server(server)
	Quit sc
}

/// Makes one Read-only tool of a server a source of the command's session, or changes it: the row, the audit entry, the CheckChanged. See the class description.
Method OnSetSource(request As OcuTalon.Msg.Command.SetSourcePoll, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ..Refusal(request, "SetSourcePoll")
	If $IsObject(response) Quit $$$OK
	Set sessionRef = request.SessionRef
	If (sessionRef = "") || '$IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)) Quit ..Failed(.response, "the source command names no session", $SYSTEM.Status.Error(5001, "No session"))
	Set server = request.Server
	Set row = ""
	If $Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	If '$IsObject(row) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOSERVER)
	Set stored = row.Name
	Set tool = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(stored, request.Tool)
	If '$IsObject(tool) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOTOOL)
	If tool.Classification '= "read-only" Quit ..Answer(.response, 0, "not_read_only", ..#MESSAGENOTREADONLY)
	Set name = $ZStrip(request.Name, "<>W")
	If ($Length(name) < 1) || ($Length(name) > ..#NAMEMAX) || ($ZStrip(name, "*C") '= name) Quit ..Answer(.response, 0, "bad_name", ..#MESSAGESOURCENAME)
	If $ZConvert(name, "L") = $ZConvert(##class(OcuTalon.Checks.Coverage).#ENTRYMAILBOX, "L") Quit ..Answer(.response, 0, "reserved_name", ..#MESSAGESOURCERESERVED)
	Set arguments = ..Normalised(request.Arguments)
	If arguments = "" Quit ..Answer(.response, 0, "bad_arguments", ..#MESSAGESOURCEARGUMENTS)
	Set interval = request.IntervalMinutes
	If '$IsValidNum(interval) || (interval '= (interval \ 1)) || (interval < ..#INTERVALMIN) || (interval > ..#INTERVALMAX) Quit ..Answer(.response, 0, "bad_interval", ..#MESSAGESOURCEINTERVAL)
	If '..Lock(stored) Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Set sc = $$$OK
	Set ref = ""
	Try {
		Set sc = ..SaveSource(request, stored, request.Tool, name, arguments, +interval, .response, .ref)
	} Catch exception {
		Set response = ""
		Set ref = ""
		Set sc = ..Failed(.response, "the source could not be set", exception.AsStatus())
	}
	Lock -^OcuTalon.Mcp.Server(stored)
	If ref '= "" Do ..Changed(ref, sessionRef, 0, "source", name)
	Quit sc
}

/// Removes the source of the command's Ref: the row, the audit entry, the CheckChanged. See the class description.
Method OnRemoveSource(request As OcuTalon.Msg.Command.RemoveSourcePoll, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ..Refusal(request, "RemoveSourcePoll")
	If $IsObject(response) Quit $$$OK
	Set row = $Select(request.SourceRef = "": "", 1: ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(request.SourceRef))
	If '$IsObject(row) || (row.Kind '= ##class(OcuTalon.Watch.Ops).#SOURCEKIND) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOSOURCE)
	Set server = row.Server
	If '..Lock(server) Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	Set sc = $$$OK
	Set fields = ""
	Try {
		Set sc = ..RemoveRow(request.SourceRef, request, .fields, .audited)
		If $$$ISERR(sc) {
			Set sc = ..Failed(.response, "the source could not be removed", sc, $Select(audited: "failed", 1: "not_audited"))
		} ElseIf fields = "" {
			Set sc = ..Answer(.response, 0, "not_found", ..#MESSAGENOSOURCE)
		} Else {
			Set sc = ..Answer(.response, 1, "removed", ..#MESSAGESOURCEREMOVED)
		}
	} Catch exception {
		Set response = ""
		Set fields = ""
		Set sc = ..Failed(.response, "the source could not be removed", exception.AsStatus())
	}
	Lock -^OcuTalon.Mcp.Server(server)
	If fields '= "" Do ..Changed(request.SourceRef, fields.SessionRef, 1, "source", fields.DisplayName)
	Quit sc
}

/// The add, under the server's lock: Validate has passed its name and address, so this is Register and Audit. restart is 1 when the change is saved and
/// audited, so that the caller restarts the runners once the lock is released.
Method Register(request As OcuTalon.Msg.Command.AddMcpServer, Output response As OcuTalon.Msg.CommandResult, Output restart As %Boolean) As %Status [ Private ]
{
	Set server = request.Server
	Set restart = 0
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(server) Quit ..Answer(.response, 0, "exists", ..#MESSAGEEXISTS)
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $$$ISERR(sc) Quit ..Failed(.response, "the MCP server row could not be saved", sc)
	Set id = row.%Id()
	Set sc = ##class(OcuTalon.Install.Step.Mcp).Grant(server)
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Quit ..Failed(.response, "the MCP server's resource could not be made", sc)
	}
	Set sc = ..SaveEntry(server, request.Url, request.Handoff)
	If $$$ISERR(sc) {
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(server)
		Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		$$$LOGWARNING("OcuTalon.Mcp.Ops: the entry or the wallet secret of the MCP server could not be written, so the addition was undone")
		Quit ..Answer(.response, 0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set sc = ..WriteAudit("MCP", ..McpData("added", server, request))
	If $$$ISERR(sc) {
		Do ..DropEntry(server)
		Do ##class(OcuTalon.Install.Step.Mcp).Revoke(server)
		Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		Quit ..Failed(.response, "the addition of the MCP server could not be audited, so it was undone", sc, "not_audited")
	}
	Set restart = 1
	Quit ..Answer(.response, 1, "added", ..#MESSAGEADDED)
}

/// The remove, under the server's lock: Unregister (the rows and the grant, in one transaction with the audit). restart is 1 when the change is saved and
/// audited, so that the caller restarts the runners once the lock is released. The row is found by its name in any letter case (NameIndex), and the entry and
/// the wallet secret are dropped under the row's own name, since their names are exact.
Method Unregister(request As OcuTalon.Msg.Command.RemoveMcpServer, Output response As OcuTalon.Msg.CommandResult, Output restart As %Boolean) As %Status [ Private ]
{
	Set server = request.Server
	Set restart = 0
	Set id = ""
	If $Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Do ##class(OcuTalon.Mcp.Server).NameIndexExists(server, .id)
	If id = "" Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOSERVER)
	Set stored = ##class(OcuTalon.Mcp.Server).NameGetStored(id)
	Set level = $TLevel
	TSTART
	Try {
		Set sc = ..DeleteTools(server)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Mcp.Server).%DeleteId(id)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Install.Step.Mcp).Revoke(server)
		If $$$ISERR(sc) {
			TROLLBACK
			Quit
		}
		Set sc = ..WriteAudit("MCP", ..McpData("removed", server, request))
		If $$$ISERR(sc) {
			TROLLBACK
			Do ##class(OcuTalon.Install.Step.Mcp).Grant(server)
			Set audited = 0
			Quit
		}
		TCOMMIT
	} Catch exception {
		If $TLevel > level TROLLBACK
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit ..Failed(.response, "the MCP server could not be removed", sc, $Select($Get(audited) = 0: "not_audited", 1: "failed"))
	Do ..CancelPending(server, request)
	If $$$ISERR(..DropEntry(stored)) $$$LOGWARNING("OcuTalon.Mcp.Ops: the entry or the wallet secret of the removed MCP server could not all be dropped")
	Do ..RemoveSources(stored, request)
	Set restart = 1
	Quit ..Answer(.response, 1, "removed", ..#MESSAGEREMOVED)
}

/// Cancels the pending approval requests of the tools of the server that Unregister has just removed and committed (Story 22.4; AD-11): Approval CancelPending for the server's
/// toolref (Attach Toolref), in the name of the acting admin, with the channel and the session of the command (the members of the removal's audit entry). A request that cannot be
/// cancelled, and a failure of the call, are one warning; the removal and its answer stand. A request that is approved and not yet run is not cancelled (AD-11 allows only a pending
/// request to be): the gate denies its replay because the server is no longer registered.
Method CancelPending(server As %String, request As OcuTalon.Msg.Command.RemoveMcpServer) [ Private ]
{
	Try {
		Set who = ..McpData("removed", server, request)
		Set sc = ##class(OcuTalon.Bridge.Approval).CancelPending(##class(OcuTalon.Mcp.Attach).Toolref(server), , who.channel, who.irisUser, who.sessionRef, .count)
		If $$$ISERR(sc) $$$LOGWARNING("OcuTalon.Mcp.Ops: the pending requests of the removed MCP server could not all be cancelled: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Mcp.Ops: the pending requests of the removed MCP server could not be cancelled: " _ ##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// Writes the wallet secret and the Config Store entry of a server that Register has just saved (Story 21.4; AD-19, AD-21), in this job: any leftover entry, key or
/// collection of that name is dropped first (the row is the truth); then, when handoff is not empty, the secret is taken from it once (SecretHandoff Take; a secret
/// that holds @{ is refused) and kept as the key OcuTalon_MCP_<server>.Key of the collection OcuTalon_MCP_<server> (Edit %Admin_Wallet:USE, Use the server's resource);
/// then the entry AI.MCP.OcuTalon_<server> is made with the address and, with a secret, a bearer token that is the secret:// reference of that key. What was made is
/// dropped again when a later step fails. The local copy of the secret is cleared on every path, nothing is logged here and no error text is kept. It never throws.
ClassMethod SaveEntry(server As %String, url As %String, handoff As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Set secret = ""
	Try {
		Set collection = ##class(OcuTalon.Install.Step.Mcp).#RESOURCEPREFIX _ server
		Set sc = ..DropEntry(server)
		If $$$ISOK(sc) && ($Get(handoff) '= "") {
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(handoff, .secret)
			If $$$ISOK(sc) && ((secret [ "@{") || (secret = "")) Set sc = $$$ERROR($$$GeneralError, "The credential cannot be stored")
		}
		If $$$ISOK(sc) && (secret '= "") {
			Set sc = ##class(%Wallet.Collection).Create(collection, {"EditResource": "%Admin_Wallet:USE", "UseResource": (collection _ ":USE")})
			If $$$ISOK(sc) Set sc = ##class(%Wallet.KeyValue).Create(collection _ ".Key", {"Secret": {"token": (secret)}, "RequireTLS": 0, "Usage": "CUSTOM"})
		}
		If $$$ISOK(sc) Set sc = ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
		If $$$ISOK(sc) {
			Set details = {"transport": "remote", "url": (url)}
			If secret '= "" Set details.auth = {"type": "bearer", "token": ("secret://" _ collection _ ".Key#token")}
			Set sc = ##class(%ConfigStore.Configuration).Create("AI", "MCP", "", ##class(OcuTalon.Mcp.Attach).#ENTRYPREFIX _ server, details, "", ..#ENTRYDESCRIPTION, ..#ENTRYRESOURCE, ..#ENTRYRESOURCE, 1, (secret '= ""))
		}
	} Catch {
		Set sc = $$$ERROR($$$GeneralError, "The entry of the MCP server could not be written")
	}
	Set secret = ""
	If $$$ISERR(sc) Do ..DropEntry(server)
	Quit sc
}

/// Drops the Config Store entry AI.MCP.OcuTalon_<server>, the wallet key OcuTalon_MCP_<server>.Key and the collection OcuTalon_MCP_<server>, each where it exists
/// (Story 21.4). The status is an error when any of them could not be dropped, with no error text of the wallet or the Config Store in it. It never throws.
ClassMethod DropEntry(server As %String) As %Status [ Private ]
{
	Set failed = 0
	Try {
		Set collection = ##class(OcuTalon.Install.Step.Mcp).#RESOURCEPREFIX _ server
		Set fqn = "AI.MCP." _ ##class(OcuTalon.Mcp.Attach).#ENTRYPREFIX _ server
		If ##class(%ConfigStore.Configuration).Exists(fqn) && $$$ISERR(##class(%ConfigStore.Configuration).Delete(fqn)) Set failed = 1
		If ##class(%Wallet.Secret).Exists(collection _ ".Key") && $$$ISERR(##class(%Wallet.KeyValue).Delete(collection _ ".Key")) Set failed = 1
		If ##class(%Wallet.Collection).Exists(collection) && $$$ISERR(##class(%Wallet.Collection).Delete(collection)) Set failed = 1
	} Catch {
		Set failed = 1
	}
	Quit $Select(failed: $$$ERROR($$$GeneralError, "The entry of the MCP server could not be dropped"), 1: $$$OK)
}

/// The restart of the runners after a saved change: the answer is the outcome and message given, or failed when the restart fails (the change is kept).
Method Restarted(Output response As OcuTalon.Msg.CommandResult, outcome As %String, message As %String, what As %String) As %Status [ Private ]
{
	Set sc = ..Restart()
	If $$$ISERR(sc) Quit ..Failed(.response, what, sc)
	Quit ..Answer(.response, 1, outcome, message)
}

/// The classification, under the server's lock.
Method Classify(request As OcuTalon.Msg.Command.ClassifyTool, Output response As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set server = request.Server
	Set word = request.Classification
	If '$ListFind($ListFromString(##class(OcuTalon.Mcp.ToolClassification).#CLASSIFICATIONS), word) Quit ..Answer(.response, 0, "bad_classification", ..#MESSAGECLASSIFICATION)
	If '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) || '##class(OcuTalon.Mcp.Server).NameIndexExists(server) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOSERVER)
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, request.Tool)
	If '$IsObject(row) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOTOOL)
	Set before = row.Classification
	Set beforeAt = row.ChangedAt
	Set row.Classification = word
	Set row.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $$$ISERR(sc) Quit ..Failed(.response, "the classification could not be saved", sc)
	Set sc = ..WriteAudit("Tool", ..ToolData(server, request.Tool, word, request.ActingUser, request.SessionRef, request.Origin))
	If $$$ISERR(sc) {
		Set row.Classification = before
		Set row.ChangedAt = beforeAt
		Do row.%Save()
		Quit ..Failed(.response, "the classification could not be audited, so it was undone", sc, "not_audited")
	}
	Quit ..Answer(.response, 1, "saved", ..#MESSAGESAVED)
}

/// The set of a source, under the server's lock (OnSetSource has validated every value; the tool is re-read here and must still be classified read-only): Watch.Ops SetSource and the audit entry in one transaction. ref is the row's Ref
/// when the change is saved and audited, else "".
Method SaveSource(request As OcuTalon.Msg.Command.SetSourcePoll, server As %String, tool As %String, name As %String, arguments As %String, interval As %Integer, Output response As OcuTalon.Msg.CommandResult, Output ref As %String) As %Status [ Private ]
{
	Set ref = ""
	If '##class(OcuTalon.Mcp.Server).NameIndexExists(server) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOSERVER)
	Set classified = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, tool)
	If '$IsObject(classified) Quit ..Answer(.response, 0, "not_found", ..#MESSAGENOTOOL)
	If classified.Classification '= "read-only" Quit ..Answer(.response, 0, "not_read_only", ..#MESSAGENOTREADONLY)
	Set level = $TLevel
	Set audited = 1
	TSTART
	Try {
		Set sc = ##class(OcuTalon.Watch.Ops).SetSource(request.SessionRef, server, tool, name, arguments, interval, request.ActingUser, .made, .created)
		If $$$ISOK(sc) {
			Set data = ..McpData("source_set", server, request)
			Do data.%Set("tool", tool, "string")
			Do data.%Set("outcome", $Select(created: "created", 1: "updated"), "string")
			Set sc = ..WriteAudit("MCP", data)
			If $$$ISERR(sc) Set audited = 0
		}
		If $$$ISERR(sc) {
			TROLLBACK
			Quit
		}
		TCOMMIT
	} Catch exception {
		If $TLevel > level TROLLBACK
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) Quit ..Failed(.response, "the source could not be set", sc, $Select(audited: "failed", 1: "not_audited"))
	Set ref = made
	Quit ..Answer(.response, 1, "saved", ..#MESSAGESAVED, ref)
}

/// Removes the source of the Ref and audits it (source_removed, outcome removed, in the name of the command's acting admin), in one transaction. The caller holds the lock
/// of the source's server. fields is the row's fields (Watch.Ops Fields), or "" when there is no source of that Ref. audited is 0 when the audit entry was the failure,
/// and then the removal is rolled back.
Method RemoveRow(ref As %String, command As OcuTalon.Msg.Command, Output fields As %DynamicObject, Output audited As %Boolean) As %Status [ Private ]
{
	Set fields = ""
	Set audited = 1
	Set level = $TLevel
	TSTART
	Try {
		Set sc = ##class(OcuTalon.Watch.Ops).RemoveSource(ref, .removed)
		If $$$ISOK(sc) && $IsObject(removed) {
			Set data = ..McpData("source_removed", removed.Server, command)
			Do data.%Set("tool", removed.Tool, "string")
			Do data.%Set("outcome", "removed", "string")
			Set sc = ..WriteAudit("MCP", data)
			If $$$ISERR(sc) Set audited = 0
		}
		If $$$ISERR(sc) {
			TROLLBACK
			Quit
		}
		TCOMMIT
		Set fields = removed
	} Catch exception {
		If $TLevel > level TROLLBACK
		Set fields = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Removes the sources of a server that Unregister has just removed and committed (Story 22.5), each in its own transaction with its audit entry (source_removed, in the
/// name of the admin who removed the server), then one CheckChanged each. A source that cannot be removed or audited stays, with one warning, and the removal stands.
Method RemoveSources(server As %String, request As OcuTalon.Msg.Command.RemoveMcpServer) [ Private ]
{
	Try {
		Set refs = ##class(OcuTalon.Watch.Ops).SourcesOf(server)
		Set iterator = refs.%GetIterator()
		While iterator.%GetNext(, .ref) {
			Set fields = ""
			Try {
				Set sc = ..RemoveRow(ref, request, .fields, .audited)
			} Catch exception {
				Set sc = exception.AsStatus()
			}
			If $$$ISERR(sc) {
				$$$LOGWARNING("OcuTalon.Mcp.Ops: the source " _ ref _ " of the removed MCP server could not be removed: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
			} ElseIf fields '= "" {
				Do ..Changed(ref, fields.SessionRef, 1, "source", fields.DisplayName)
			}
		}
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Mcp.Ops: the sources of the removed MCP server could not be read: " _ ##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// The text of the arguments as the one normal JSON object text (%FromJSON, then %ToJSON, with the members in their order): "" means {}. "" is the answer when the text is
/// not a JSON object, is longer than ARGUMENTSMAX once normalised, or holds secret:// (in any letter case) or @{ (AD-19), since the text is never an empty string otherwise.
ClassMethod Normalised(arguments As %String) As %String [ Private ]
{
	If $IsObject(arguments) Quit ""
	If arguments = "" Quit "{}"
	Try {
		Set parsed = ##class(%Library.DynamicAbstractObject).%FromJSON(arguments)
		If '$IsObject(parsed) || 'parsed.%IsA("%Library.DynamicObject") {
			Set text = ""
		} Else {
			Set text = parsed.%ToJSON()
			If ($Length(text) > ..#ARGUMENTSMAX) || ($ZConvert(text, "L") [ "secret://") || (text [ "@{") Set text = ""
		}
	} Catch {
		Set text = ""
	}
	Quit text
}

/// Tells the Checks item that a check was set (stopped 0) or removed (stopped 1), through SendChanged: a CheckChanged of the kind, with an empty namespace and production.
/// A failed send, or an exception, is one warning and changes nothing else.
Method Changed(ref As %String, sessionRef As %String, stopped As %Boolean, kind As %String, displayName As %String) [ Private ]
{
	Try {
		Set message = ##class(OcuTalon.Checks.Msg.CheckChanged).%New()
		Set message.CheckRef = ref
		Set message.SessionRef = sessionRef
		Set message.Stopped = stopped
		Set message.Kind = kind
		Set message.DisplayName = displayName
		Set sc = ..SendChanged(message)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) $$$LOGWARNING("OcuTalon.Mcp.Ops: the check change " _ ref _ " could not be sent: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
}

/// Sends the message to the Checks item, asynchronously, with no answer wanted (a seam for the tests).
Method SendChanged(message As OcuTalon.Checks.Msg.CheckChanged) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#CHECKS, message)
}

/// The tools of the server for Settings, as a %DynamicArray of {"name", "classification", "status"} sorted by name. The status is refused for a tool in the
/// row's RefusedTools, else unavailable while the server's last attach was unavailable, else available. A server that is not registered, and an empty name,
/// are an error.
ClassMethod Tools(server As %String, Output tools As %DynamicArray) As %Status
{
	Set tools = []
	Set row = ""
	If $Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
	If '$IsObject(row) Quit $SYSTEM.Status.Error(5001, "There is no MCP server with that name")
	Set refused = row.RefusedTools
	Set down = (row.AttachStatus = "unavailable")
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Tool, Classification FROM OcuTalon_Mcp.ToolClassification WHERE Server = ? ORDER BY %EXACT(Tool)")
	If $$$ISERR(sc) Quit sc
	Set result = statement.%Execute(server)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	While result.%Next(.sc) {
		Set name = result.%Get("Tool")
		Set status = $Select($ListFind(refused, name): "refused", down: "unavailable", 1: "available")
		Do tools.%Push({"name": (name), "classification": (result.%Get("Classification")), "status": (status)})
	}
	Quit sc
}

/// Writes the report of one attach ({"status", "reason", "tools", "refused", "fingerprints"}, OcuTalon.Bridge.Ext.McpServers) to the row of the server and,
/// for an attached server, to its ToolClassification rows (see the class description). The admin notices of the transitions it finds go out after the
/// rows are saved.
ClassMethod RecordAttach(server As %String, report As %DynamicObject) As %Status
{
	If '$IsObject($Get(report)) Quit $$$ERROR($$$GeneralError, "The attach report is not an object")
	Set sc = $$$OK
	Kill events
	Set saved = 0
	Lock +^OcuTalon.Mcp.Server(server):5
	If '$Test Quit $$$ERROR($$$GeneralError, "The MCP server "_server_" is busy, so its attach report was not recorded")
	Try {
		Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server, , .sc)
		If '$IsObject(row) {
			Set sc = $$$ERROR($$$GeneralError, "There is no MCP server named "_server_", so its attach report was not recorded")
		} Else {
			Set was = row.AttachStatus
			Set wasRefused = row.RefusedTools
			Set status = report.%Get("status")
			Set reason = report.%Get("reason")
			Set row.AttachStatus = $Select($ListFind($ListFromString(..#STATUSES), status): status, 1: "")
			Set row.AttachReason = $Select($ListFind($ListFromString(##class(OcuTalon.Bridge.Ext.McpServers).#REASONS), reason): reason, 1: "")
			If row.AttachStatus = "attached" Set row.AttachedAt = ##class(OcuTalon.Data.Time).NowUtc()
			Set row.RefusedTools = ..NamesOf(report.%Get("refused"))
			Set sc = row.%Save()
			If $$$ISOK(sc) {
				Set saved = 1
				If (row.AttachStatus = "unavailable") && (was '= "unavailable") Set events("unavailable") = ""
				Set position = 0
				While $ListNext(row.RefusedTools, position, name) {
					If '$ListFind(wasRefused, name) Set events("shadow", name) = ""
				}
				If row.AttachStatus = "attached" Set sc = ..SyncTools(server, report, .events)
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Mcp.Server(server)
	If saved Do ..Notify(server, .events)
	Quit sc
}

/// Clears the classification of a tool whose fingerprint changed: when the tool has a row whose fingerprint is not the fingerprint given, the row becomes
/// unclassified with the new fingerprint, the change is audited (a Tool entry, unclassified, irisUser the running user, channel system) and each admin
/// session gets one mcp.toolChanged notice. An unclassified row only takes the new fingerprint, and a tool with no row, or whose row already has the
/// fingerprint, changes nothing. The status is an error when the row could not be saved or the change could not be audited (the row stays cleared).
ClassMethod ClearChanged(server As %String, tool As %String, fingerprint As %String) As %Status
{
	Set sc = $$$OK
	Kill events
	Lock +^OcuTalon.Mcp.Server(server):5
	If '$Test Quit $$$ERROR($$$GeneralError, "The MCP server "_server_" is busy, so the changed tool was not cleared")
	Try {
		Set sc = ..ClearRow(server, tool, fingerprint, .events)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Mcp.Server(server)
	Do ..Notify(server, .events)
	Quit sc
}

/// ClearChanged's work, for a caller that holds the server's lock. events("changed", tool) is set when the row was cleared.
ClassMethod ClearRow(server As %String, tool As %String, fingerprint As %String, ByRef events) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, tool)
	If '$IsObject(row) || (row.Fingerprint = fingerprint) Quit $$$OK
	Set classified = (row.Classification '= "unclassified")
	Set row.Fingerprint = fingerprint
	If classified {
		Set row.Classification = "unclassified"
		Set row.ChangedAt = ##class(OcuTalon.Data.Time).NowUtc()
	}
	Set sc = row.%Save()
	If $$$ISERR(sc) || 'classified Quit sc
	Set events("changed", tool) = ""
	Set user = $Select($Username '= "": $Username, 1: "OcuTalon")
	Quit ..WriteAudit("Tool", ..ToolData(server, tool, "unclassified", user, "", "system"))
}

/// Keeps one row for each tool of an attached server's report: the listed tools with their fingerprints, then the refused ones with an empty fingerprint.
/// A row of a tool that the report no longer lists or refuses is deleted. A listed tool whose fingerprint changed is cleared (ClearRow). The caller
/// holds the server's lock.
ClassMethod SyncTools(server As %String, report As %DynamicObject, ByRef events) As %Status [ Private ]
{
	Set listed = ..NamesOf(report.%Get("tools"))
	Set refused = ..NamesOf(report.%Get("refused"))
	Set fingerprints = report.%Get("fingerprints")
	Set known = $IsObject(fingerprints) && fingerprints.%IsA("%Library.DynamicObject")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = $$$OK
	Set position = 0
	While $ListNext(listed, position, name) {
		If ..Skipped(name) Continue
		Set fingerprint = $Select(known && (fingerprints.%GetTypeOf(name) = "string"): fingerprints.%Get(name), 1: "")
		If $Length(fingerprint) > ..#FINGERPRINTLENGTH Set fingerprint = ""
		Set one = ..KeepRow(server, name, fingerprint, now, .events)
		If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, one)
		Set keep(name) = ""
	}
	Set position = 0
	While $ListNext(refused, position, name) {
		If ..Skipped(name) Continue
		Set one = ..KeepRow(server, name, "", now, .events, 1)
		If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, one)
		Set keep(name) = ""
	}
	Set statement = ##class(%SQL.Statement).%New()
	Set one = statement.%Prepare("SELECT %ID AS RowId, Tool FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?")
	If $$$ISERR(one) Quit $SYSTEM.Status.AppendStatus(sc, one)
	Set result = statement.%Execute(server)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.AppendStatus(sc, $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message))
	While result.%Next() {
		If '$Data(keep(result.%Get("Tool"))) Set stale(result.%Get("RowId")) = ""
	}
	Set id = ""
	For {
		Set id = $Order(stale(id))
		Quit:id=""
		Set one = ##class(OcuTalon.Mcp.ToolClassification).%DeleteId(id)
		If $$$ISERR(one) Set sc = $SYSTEM.Status.AppendStatus(sc, one)
	}
	Quit sc
}

/// 1 for a tool name that cannot be stored: empty, or longer than a Tool.
ClassMethod Skipped(name As %String) As %Boolean [ Private ]
{
	Quit (name = "") || ($Length(name) > 128)
}

/// Makes the row of one tool as the report has it. A new row is unclassified. An existing row whose fingerprint is not the reported one is cleared, or, when
/// the tool is refused (it has no fingerprint), only has its fingerprint emptied.
ClassMethod KeepRow(server As %String, tool As %String, fingerprint As %String, now As %String, ByRef events, refused As %Boolean = 0) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, tool)
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
		Set row.Server = server
		Set row.Tool = tool
		Set row.Fingerprint = fingerprint
		Set row.ChangedAt = now
		Quit row.%Save()
	}
	If row.Fingerprint = fingerprint Quit $$$OK
	If refused {
		Set row.Fingerprint = fingerprint
		Quit row.%Save()
	}
	Quit ..ClearRow(server, tool, fingerprint, .events)
}

/// Sends the admin notices of the events (events("unavailable"), events("shadow", tool), events("changed", tool)) to every admin session. A read of the
/// admins' sessions that fails is one warning and no notice; a notice that cannot be sent is one warning. Nothing here changes a row.
ClassMethod Notify(server As %String, ByRef events) As %Status [ Private ]
{
	If '$Data(events) Quit $$$OK
	Set admins = ..AdminSessions(.sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING("OcuTalon.Mcp.Ops: the admins' sessions could not be read, so the notices about the MCP server " _ server _ " were not sent")
		Quit sc
	}
	Set position = 0
	While $ListNext(admins, position, ref) {
		If $Data(events("unavailable")) Do ..Send(ref, "mcp.serverUnavailable", {"server": (server), "time": (##class(OcuTalon.Data.Time).NowUtc())})
		Set tool = ""
		For {
			Set tool = $Order(events("shadow", tool))
			Quit:tool=""
			Do ..Send(ref, "mcp.toolShadowsBuiltIn", {"server": (server), "tool": (tool)})
		}
		Set tool = ""
		For {
			Set tool = $Order(events("changed", tool))
			Quit:tool=""
			Do ..Send(ref, "mcp.toolChanged", {"tool": (tool), "server": (server)})
		}
	}
	Quit $$$OK
}

/// One notice (kind status, the catalog key and its slots) to the session; a failed send is one warning.
ClassMethod Send(sessionRef As %String, key As %String, slots As %DynamicObject) [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.Kind = "status"
	Set notification.CatalogKey = key
	Set notification.Slots = slots.%ToJSON()
	Try {
		Set sc = ..Notice(notification)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $$$ISERR(sc) $$$LOGWARNING("OcuTalon.Mcp.Ops: the notice " _ key _ " could not be sent: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
}

/// 1 when the address is one an MCP server may have: https://, or http:// to 127.0.0.1, localhost or [::1], with a host, an optional numeric port of 1 to 65535, no
/// user information, no control character, space or backslash, and no @{ (AD-19). The host is read from the address as a client would read it.
ClassMethod AddressAllowed(url As %String) As %Boolean
{
	If $IsObject(url) || ($Length(url) = 0) || (url [ "@{") || ($ZStrip(url, "*C") '= url) || (url [ " ") || (url [ "\") Quit 0
	Set lower = $ZConvert(url, "L")
	Set secure = ($Extract(lower, 1, 8) = "https://")
	If 'secure && ($Extract(lower, 1, 7) '= "http://") Quit 0
	Set rest = $Extract(url, $Select(secure: 9, 1: 8), *)
	Set authority = $Piece($Piece($Piece(rest, "/", 1), "?", 1), "#", 1)
	If authority [ "@" Quit 0
	If $Extract(authority, 1) = "[" {
		If authority '[ "]" Quit 0
		Set host = $Piece(authority, "]", 1) _ "]"
		Set port = $Piece(authority, "]", 2, *)
	} Else {
		Set host = $Piece(authority, ":", 1)
		Set port = $Select(authority [ ":": ":" _ $Piece(authority, ":", 2, *), 1: "")
	}
	If host = "" Quit 0
	If (port '= "") && (($Extract(port, 1) '= ":") || ($Extract(port, 2, *) '? 1.5N) || ('$Extract(port, 2, *)) || ($Extract(port, 2, *) > 65535)) Quit 0
	If secure Quit 1
	Quit ''$ListFind($ListFromString(..#LOOPBACKHOSTS), $ZConvert(host, "L"))
}

/// The tool rows of a server, deleted.
ClassMethod DeleteTools(server As %String) As %Status [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?")
	If $$$ISERR(sc) Quit sc
	Set result = statement.%Execute(server)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Quit $$$OK
}

/// The refusal of a command from the wrong sender or origin, with no acting user, or on the online demo: a CommandResult with Ok 0 and the outcome
/// not_allowed, or "" when the command may go on. A wrong sender or origin and a missing acting user are one warning each. Nothing is written.
Method Refusal(command As OcuTalon.Msg.Command, verb As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set origin = command.Origin
	Set fromTool = (origin = "tool") || ##class(OcuTalon.Bridge.Context).Active()
	If fromTool || (..Source() '= ..#COMMANDSENDER) || (origin '= ..#ORIGIN) || (command.ActingUser = "") {
		$$$LOGWARNING("OcuTalon.Mcp.Ops: refused " _ verb _ " from '" _ $Extract(..Source(), 1, 64) _ "' with origin '" _ $Extract(origin, 1, 32) _ "'")
		Set message = $Select(fromTool: ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTFROMTOOL, 1: ##class(OcuTalon.Core.CommandsIn).#MESSAGEADMINONLY)
		Do ..Answer(.refusal, 0, "not_allowed", message)
		Quit refusal
	}
	If ..OnlineDemo() {
		Do ..Answer(.refusal, 0, "not_allowed", ##class(OcuTalon.Core.CommandsIn).#MESSAGENOTALLOWED)
		Quit refusal
	}
	Quit ""
}

/// The item that sent the message being handled: the SourceConfigName of its header, else "".
Method Source() As %String [ Private ]
{
	Quit $Select($IsObject(..%RequestHeader): ..%RequestHeader.SourceConfigName, 1: "")
}

/// Takes the lock that serialises the changes of one server; 1 when it is held. The caller releases it.
ClassMethod Lock(server As %String) As %Boolean [ Private ]
{
	Lock +^OcuTalon.Mcp.Server(server):5
	Quit $Test
}

/// The data of an MCP audit entry for the command: the change, the server, the acting user, the command's session and the channel of its origin.
ClassMethod McpData(change As %String, server As %String, command As OcuTalon.Msg.Command) As %DynamicObject [ Private ]
{
	Set data = {}
	Do data.%Set("change", change, "string")
	Do data.%Set("server", server, "string")
	Do ..Common(data, command.ActingUser, command.SessionRef, command.Origin)
	Quit data
}

/// The data of a Tool audit entry: the server is the source, and a read-only classification is audited as safe with readOnly 1.
ClassMethod ToolData(server As %String, tool As %String, classification As %String, irisUser As %String, sessionRef As %String, origin As %String) As %DynamicObject [ Private ]
{
	Set data = {}
	Do data.%Set("source", server, "string")
	Do data.%Set("tool", tool, "string")
	Do data.%Set("classification", $Case(classification, "read-only": "safe", : classification), "string")
	Do data.%Set("readOnly", +(classification = "read-only"), "number")
	Do ..Common(data, irisUser, sessionRef, origin)
	Quit data
}

/// The members every audit entry has. The channel is web for origin web_admin and system for origin system.
ClassMethod Common(data As %DynamicObject, irisUser As %String, sessionRef As %String, origin As %String) [ Private ]
{
	Do data.%Set("irisUser", irisUser, "string")
	Do data.%Set("sessionRef", sessionRef, "string")
	Do data.%Set("channel", $Case(origin, "web_admin": "web", : "system"), "string")
}

/// Builds the CommandResult in response (with the Ref, when given) and returns OK.
ClassMethod Answer(ByRef response As OcuTalon.Msg.CommandResult, ok As %Boolean, outcome As %String, message As %String, ref As %String = "") As %Status [ Private ]
{
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	Set response.Ok = ok
	Set response.Outcome = outcome
	Set response.Message = message
	Set response.Ref = ref
	Quit $$$OK
}

/// A failure: one warning with the reason (its text passes the redactor) and the answer with Ok 0 and the outcome (failed unless given). The change, if
/// any was saved, is as the caller left it. Returns OK, so the command is answered.
ClassMethod Failed(ByRef response As OcuTalon.Msg.CommandResult, what As %String, sc As %Status, outcome As %String = "failed") As %Status [ Private ]
{
	$$$LOGWARNING("OcuTalon.Mcp.Ops: " _ what _ ": " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	Quit ..Answer(.response, 0, outcome, ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
}

/// The names in a %DynamicArray of strings as a list; anything else gives an empty list.
ClassMethod NamesOf(array As %DynamicArray) As %List [ Private ]
{
	Set names = ""
	If '$IsObject(array) || ('array.%IsA("%Library.DynamicArray")) Quit names
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .name) {
		If '$IsObject(name) Set names = names _ $ListBuild(name)
	}
	Quit names
}

/// 1 on the online demo (the Setting onlineDemo holds 1), as BridgeSink and PrecedentOps read it. A seam for the tests.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// The Refs of the admins' sessions (Ownership.AdminSessions), with sc an error when the read failed. A seam for the tests.
ClassMethod AdminSessions(Output sc As %Status) As %List [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).AdminSessions(.sc)
}

/// The one send of a notice: the notification through NoticesIn. A seam for the tests.
ClassMethod Notice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.NoticesIn).Send(notification)
}

/// The restart of every runner, so that each builds its agent with the servers registered now. A seam for the tests.
ClassMethod Restart() As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.SettingsOps).RestartRunners()
}

/// The one audit write of the class: an entry of the type through the one writer of product code. A seam for the tests.
ClassMethod WriteAudit(type As %String, data As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record(type, data)
}

}
