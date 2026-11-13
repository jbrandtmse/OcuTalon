/// The per-call context (AD-6): the runner sets it before a model call, and the gate and the tools read it. It holds
/// the request's fields, including the caller's thread session id and the SuperSession, the taint of the turn and the
/// host data that a tool fills, the characters that the tool results of the current model step have used (ToolResultChars, AD-10) and the
/// number of commands that the tools of the call have submitted (CommandCount, AD-1): a host's tools number the commands that they submit in
/// one call with it, and Begin starts it at 0, so a call that runs again numbers its commands from 1 again.
/// It lives in the process-private global ^||OcuTalonBP.Context, not in a local variable,
/// because a callback of AI Hub may New local variables; it ends with the process, and a job that did not call Begin
/// sees no context.
/// The context of a replay (kind tool, Replay.Run) also holds the grant of the approved call (Grant): one entry of the same global that the gate
/// consumes at the first call that matches it (TakeGrant). The grant is not a field: Current and Put never expose or set it, and Begin and End kill it.
/// The context of a request that composes tools (AD-6, AD-10, AD-21) also holds the turn's MCP map: for each MCP tool that the serving tool manager lists,
/// the fingerprint of its server, name, description and input schema (SetMcpTools), which the gate reads for a call (McpFingerprint). SetMcpTools also keeps, from the
/// (server, toolref) pairs of the servers that the adapter recorded, the name that the host gives each server and its toolref (McpToolref, McpServerOf), so that the gate
/// can classify a call of the governed proxy, which names a server and a tool, as it classifies the native call of the same tool, and can name the server in the proxy
/// call that replaces a native one (Story 22.3). Like the grant, the map is not a field, and Begin and End kill it. A tool that is not in the map has no fingerprint.
/// Story 22.4: once TakeGrant consumed the grant it keeps the approved call (source, name, ToolFingerprint) in a node of its own (ApprovedFingerprint), and the governed
/// proxy notes the reason word of a replay that it refused (NoteReplayRefusal, ReplayRefusal); both nodes are outside FIELDS, and Begin and End kill them.
Class OcuTalon.Bridge.Context Extends %RegisteredObject
{

/// The names that Begin copies from the request and that Put may set, comma-separated.
Parameter FIELDS = "Kind,Provenance,ItemId,DecisionRef,OwnerRef,TraceRef,Channel,ThreadSessionId,SuperSession,Runner,Tainted,HostData,ToolResultChars,CommandCount";

/// One of Msg.Enum REQUESTKIND.
Property Kind As %String(MAXLEN = 32);

/// One of Msg.Enum PROVENANCE.
Property Provenance As %String(MAXLEN = 32);

/// The item's Ref.
Property ItemId As %String(MAXLEN = 22);

Property DecisionRef As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

Property TraceRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The caller's own trace session id.
Property ThreadSessionId As %Integer;

/// The SuperSession that the messages of the call carry.
Property SuperSession As %String(MAXLEN = 64);

/// The runner item (its config name) whose job holds the context: the gate copies it into the approval request of a held call, so that the
/// request is replayed in the same runner (DW-194). Empty for a context that no runner began.
Property Runner As %String(MAXLEN = 128);

/// True when a tool result that is not trusted output has reached the turn (AD-10). The gate sets it when it allows a call whose tool is
/// not trusted output, and a tool may set it itself. Begin starts every turn at 0, an untrusted turn included: the provenance says whether
/// the item came from the user, and this says whether such a result reached the model.
Property Tainted As %Boolean [ InitialExpression = 0 ];

/// JSON a tool may fill, such as check rows.
Property HostData As %String(MAXLEN = "");

/// The characters that the results of the tools of the current model step have used (the shared base of the built-in tools keeps the total, AD-10). Begin
/// sets it to 0, and the step renderer sets it to 0 at every model response, so the results of one model step share one room.
Property ToolResultChars As %Integer [ InitialExpression = 0 ];

/// The number of commands that the tools of the call have submitted so far. A host's tools number the commands that they submit in one call
/// with it: the next command is number CommandCount plus 1, which the tool writes back with Put. Begin sets it to 0, so a call that runs again
/// numbers its commands from 1 again.
Property CommandCount As %Integer [ InitialExpression = 0 ];

/// Starts the context of this process from the request, with the SuperSession of the call and the runner item (empty for none), and replaces a
/// context that is already set (and kills its grant). The taint starts at 0, the host data empty, and the tool result characters and the command count at 0.
ClassMethod Begin(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", runner As %String = "") As %Status
{
	If '$IsObject(request) || '$ClassMethod($ClassName(request), "%Extends", "OcuTalon.Bridge.Msg.Request") {
		Quit $SYSTEM.Status.Error(5001, "A context starts from an OcuTalon.Bridge.Msg.Request")
	}
	Kill ^||OcuTalonBP.Context
	Set ^||OcuTalonBP.Context = 1
	For name = "Kind", "Provenance", "ItemId", "DecisionRef", "OwnerRef", "TraceRef", "Channel", "ThreadSessionId" {
		Set ^||OcuTalonBP.Context(name) = $Property(request, name)
	}
	Set ^||OcuTalonBP.Context("SuperSession") = superSession
	Set ^||OcuTalonBP.Context("Runner") = runner
	Set ^||OcuTalonBP.Context("Tainted") = 0
	Set ^||OcuTalonBP.Context("HostData") = ""
	Set ^||OcuTalonBP.Context("ToolResultChars") = 0
	Set ^||OcuTalonBP.Context("CommandCount") = 0
	Quit $SYSTEM.Status.OK()
}

/// Ends the context of this process, and its grant. Does nothing when there is none.
ClassMethod End()
{
	Kill ^||OcuTalonBP.Context
}

/// 1 when this process has a context.
ClassMethod Active() As %Boolean
{
	Quit $Data(^||OcuTalonBP.Context) # 2
}

/// A copy of this process's context, or "" when there is none. Changing the copy changes nothing: use Put.
ClassMethod Current() As OcuTalon.Bridge.Context
{
	If '..Active() Quit ""
	Set context = ..%New()
	For i = 1:1:$Length(..#FIELDS, ",") {
		Set name = $Piece(..#FIELDS, ",", i)
		Set $Property(context, name) = $Get(^||OcuTalonBP.Context(name))
	}
	Quit context
}

/// Sets one field of this process's context. An error when there is no context or the name is not one of FIELDS.
ClassMethod Put(name As %String, value As %String) As %Status
{
	If '..Active() Quit $SYSTEM.Status.Error(5001, "There is no context to put "_name_" into")
	If '$ListFind($ListFromString(..#FIELDS), name) Quit $SYSTEM.Status.Error(5001, "'"_name_"' is not a field of the context")
	Set ^||OcuTalonBP.Context(name) = value
	Quit $SYSTEM.Status.OK()
}

/// The node of the grant of the replay, in the same process-private global as the context and outside FIELDS.
Parameter GRANT = "grant";

/// The node of the call that the grant approved, once TakeGrant consumed the grant (the source, the name and the ToolFingerprint of the approved row), in the same process-private global as the context and outside FIELDS.
Parameter APPROVED = "approved";

/// The node of the reason word of a refused replay (NoteReplayRefusal), in the same process-private global as the context and outside FIELDS.
Parameter REFUSAL = "refusal";

/// The node of the turn's MCP map, in the same process-private global as the context and outside FIELDS.
Parameter MCP = "mcp";

/// The node of the host's names for the servers of the turn's MCP map (server name to toolref), outside FIELDS.
Parameter MCPSERVERS = "mcpservers";

/// The node of the native MCP calls that the gate rewrote into calls of the proxy, in the order of the rewrites, for each tool name (outside FIELDS): the host's name for the server.
Parameter REROUTED = "rerouted";

/// The prefix of the tool_ref of an MCP tool (any letter case).
Parameter MCPPREFIX = "mcp:";

/// The longest server or tool name that the map keeps, in characters: a longer one is left out, so that it has no fingerprint and counts as unclassified.
Parameter MCPKEYMAX = 400;

/// Replaces the turn's MCP map with the tools of the catalog (the %Discover() list of the tool manager that serves the request): for each entry whose tool_ref
/// starts mcp:, the fingerprint (ToolFingerprint) of the tool_ref as the server, the name, the description and the parameters. An entry that has no name, whose
/// tool_ref or name is too long to key (each over MCPKEYMAX, or both together over the length of a global reference), or whose parameters are text that is not
/// JSON gets no fingerprint. servers is empty, or a dynamic object from the host's name of each server to its toolref (the spec that the adapter attached), which
/// McpToolref and McpServerOf read; a member that is not a toolref that starts mcp: is left out. An error when there is no context (the old map, if any, is then not
/// touched) or the catalog is not an array; it never throws.
ClassMethod SetMcpTools(catalog As %DynamicArray, servers As %DynamicObject = "") As %Status
{
	If '..Active() Quit $SYSTEM.Status.Error(5001, "There is no context to put the MCP tools into")
	If '$IsObject(catalog) || 'catalog.%IsA("%Library.DynamicArray") Quit $SYSTEM.Status.Error(5001, "The MCP catalog is not an array")
	Kill ^||OcuTalonBP.Context(..#MCP), ^||OcuTalonBP.Context(..#MCPSERVERS)
	If $IsObject(servers) && servers.%IsA("%Library.DynamicObject") {
		Set named = servers.%GetIterator()
		While named.%GetNext(.host, .toolref, .type) {
			If (type '= "string") || '..IsMcpRef(toolref) || (host = "") || ($Length(host) > ..#MCPKEYMAX) || ($Length(toolref) > ..#MCPKEYMAX) Continue
			Try {
				Set ^||OcuTalonBP.Context(..#MCPSERVERS, host) = toolref
			} Catch {
			}
		}
	}
	Set iterator = catalog.%GetIterator()
	While iterator.%GetNext(, .tool) {
		If '$IsObject(tool) || (tool.%GetTypeOf("tool_ref") '= "string") || (tool.%GetTypeOf("name") '= "string") Continue
		Set server = tool.%Get("tool_ref")
		Set name = tool.%Get("name")
		If '..IsMcpRef(server) || (name = "") || ($Length(server) > ..#MCPKEYMAX) || ($Length(name) > ..#MCPKEYMAX) Continue
		Set fingerprint = ""
		Try {
			Set fingerprint = ..ToolFingerprint(server, name, tool.%Get("description"), tool.%Get("parameters"))
		} Catch {
			Set fingerprint = ""
		}
		If fingerprint = "" Continue
		Try {
			Set ^||OcuTalonBP.Context(..#MCP, server, name) = fingerprint
		} Catch {
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// The fingerprint that the turn's MCP map holds for the tool of the name on the server (the tool_ref), or "" when the map has none, there is no map or no
/// context (also for a server and name too long to key together). It never throws.
ClassMethod McpFingerprint(server As %String, name As %String) As %String
{
	If '..Active() || (server = "") || (name = "") || ($Length(server) > ..#MCPKEYMAX) || ($Length(name) > ..#MCPKEYMAX) Quit ""
	Try {
		Set fingerprint = $Get(^||OcuTalonBP.Context(..#MCP, server, name))
	} Catch {
		Set fingerprint = ""
	}
	Quit fingerprint
}

/// The toolref that the turn's map holds for the server of the host's name, or "" when it holds none (a server that the adapter did not record, no map, no context). It
/// never throws.
ClassMethod McpToolref(server As %String) As %String
{
	If '..Active() || (server = "") || ($Length(server) > ..#MCPKEYMAX) Quit ""
	Set toolref = ""
	Try {
		Set toolref = $Get(^||OcuTalonBP.Context(..#MCPSERVERS, server))
	} Catch {
		Set toolref = ""
	}
	Quit toolref
}

/// Notes that the gate rewrote a native call of the tool of the name, on the server of the host's name, into a call of the proxy. AI Hub hands the step audit policy the call
/// as the model made it (the tool's name and arguments) with the metadata of the proxy tool that ran, so the step record finds the server of such a call here (ReroutedServer),
/// in the order of the rewrites. It does nothing for a name or server that is empty or too long, and when there is no context; it never throws.
ClassMethod NoteRerouted(name As %String, server As %String)
{
	If '..Active() || (name = "") || (server = "") || ($Length(name) > ..#MCPKEYMAX) || ($Length(server) > ..#MCPKEYMAX) Quit
	Try {
		Set count = $Increment(^||OcuTalonBP.Context(..#REROUTED, name))
		Set ^||OcuTalonBP.Context(..#REROUTED, name, count) = server
	} Catch {
	}
}

/// The host's name for the server of the nth call of the tool of the name that the gate rewrote into a call of the proxy (NoteRerouted), or "" when there is none. It never throws.
ClassMethod ReroutedServer(name As %String, n As %Integer) As %String
{
	If '..Active() || (name = "") || ($Length(name) > ..#MCPKEYMAX) || (n < 1) Quit ""
	Set server = ""
	Try {
		Set server = $Get(^||OcuTalonBP.Context(..#REROUTED, name, n))
	} Catch {
		Set server = ""
	}
	Quit server
}

/// The host's name for the server whose toolref the turn's map holds, or "" when it holds none. It never throws.
ClassMethod McpServerOf(toolref As %String) As %String
{
	If '..Active() || (toolref = "") Quit ""
	Set found = ""
	Try {
		Set host = ""
		For {
			Set host = $Order(^||OcuTalonBP.Context(..#MCPSERVERS, host), 1, value)
			Quit:host=""
			If value = toolref {
				Set found = host
				Quit
			}
		}
	} Catch {
		Set found = ""
	}
	Quit found
}

/// 1 when the tool_ref starts mcp: (in any letter case).
ClassMethod IsMcpRef(toolRef As %String) As %Boolean [ Private ]
{
	Quit $ZConvert($Extract(toolRef, 1, $Length(..#MCPPREFIX)), "L") = ..#MCPPREFIX
}

/// Builds the grant of the replay from the approval request with the Ref, in the context of this process: $ListBuild(Ref, ToolName, the hash of the
/// canonical ToolArguments, ToolSource, ToolFingerprint). Only a tool_call row in the state executing gives a grant (the replay starts the run first, StartExecution);
/// any other row, a missing row and a process with no context are an error and leave no grant. A grant already there is replaced.
ClassMethod Grant(ref As %String) As %Status
{
	Kill ^||OcuTalonBP.Context(..#GRANT)
	If '..Active() Quit $SYSTEM.Status.Error(5001, "There is no context to grant the call of "_$Extract(ref, 1, 64)_" in")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) || $$$ISERR(row.%Reload()) Quit $SYSTEM.Status.Error(5001, "There is no approval request "_$Extract(ref, 1, 64)_" to grant")
	If (row.Kind '= "tool_call") || (row.State '= "executing") {
		Quit $SYSTEM.Status.Error(5001, "The approval request "_ref_" is a "_row.Kind_" in the state "_row.State_", and only an executing tool_call is granted")
	}
	Set hash = ""
	Set failure = $SYSTEM.Status.Error(5001, "The arguments of the approval request "_ref_" cannot be hashed")
	Try {
		Set hash = ..ArgumentsHash(row.ToolArguments)
	} Catch exception {
		Set hash = ""
		Set failure = exception.AsStatus()
	}
	If hash = "" Quit failure
	Kill ^||OcuTalonBP.Context(..#APPROVED), ^||OcuTalonBP.Context(..#REFUSAL)
	Set ^||OcuTalonBP.Context(..#GRANT) = $ListBuild(ref, row.ToolName, hash, row.ToolSource, row.ToolFingerprint)
	Quit $SYSTEM.Status.OK()
}

/// 1 and the grant is gone when the call matches it: the name, the hash of the canonical arguments (key order and number spelling do not matter)
/// and the source are all equal. Any other call, a hash that cannot be made and a process with no grant give 0 and leave the grant as it was.
ClassMethod TakeGrant(name As %String, arguments As %RegisteredObject, source As %String) As %Boolean
{
	If '..Active() || '$Data(^||OcuTalonBP.Context(..#GRANT)) Quit 0
	Set grant = ^||OcuTalonBP.Context(..#GRANT)
	Set hash = ""
	Try {
		Set hash = ..ArgumentsHash(arguments)
	} Catch {
		Set hash = ""
	}
	If (hash = "") || (name '= $ListGet(grant, 2)) || (hash '= $ListGet(grant, 3)) || (source '= $ListGet(grant, 4)) Quit 0
	Kill ^||OcuTalonBP.Context(..#GRANT)
	Set ^||OcuTalonBP.Context(..#APPROVED) = $ListBuild(source, name, $ListGet(grant, 5))
	Quit 1
}

/// The ToolFingerprint of the approved call of the tool of the name, once TakeGrant has consumed the grant for it: the fingerprint the MCP tool had at the hold. It is
/// "" for any other tool, for a call that took no grant, for a replay of a row that carries no fingerprint and for a process with no context. The governed proxy
/// reads it to know that it runs an approved call and which fingerprint the tool must still have (Story 22.4). The node ends with the context.
ClassMethod ApprovedFingerprint(tool As %String) As %String
{
	If '..Active() || '$Data(^||OcuTalonBP.Context(..#APPROVED)) Quit ""
	Set approved = ^||OcuTalonBP.Context(..#APPROVED)
	Quit $Select(tool = $ListGet(approved, 2): $ListGet(approved, 3), 1: "")
}

/// Notes the reason word of a replay whose proxy call was refused (the proxy's changed, failed, timeout or demo; failed and timeout can come after the request reached the
/// server), so that the replay can tell a refusal from a result: the tool answers a sentence either way. The last word noted stands. It does nothing for an empty word and when there is no context; it never throws.
ClassMethod NoteReplayRefusal(word As %String)
{
	If '..Active() || ($Get(word) = "") Quit
	Try {
		Set ^||OcuTalonBP.Context(..#REFUSAL) = word
	} Catch {
	}
}

/// The reason word that NoteReplayRefusal noted in this context, or "" when there is none. It never throws.
ClassMethod ReplayRefusal() As %String
{
	If '..Active() Quit ""
	Quit $Get(^||OcuTalonBP.Context(..#REFUSAL))
}

/// The source of the grant (the ToolSource of the approved row), or "" when there is none.
ClassMethod GrantSource() As %String
{
	If '..Active() || '$Data(^||OcuTalonBP.Context(..#GRANT)) Quit ""
	Quit $ListGet(^||OcuTalonBP.Context(..#GRANT), 4)
}

/// The hash of the canonical form of the arguments, an object or JSON text (blank text is {}): SHA-256 of the UTF-8 text, base64. The canonical form
/// sorts the keys of every object, keeps the order of every array, writes a number as +value (so 1.0, 1 and 1e0 are one) and writes a string and a
/// literal by its type. It throws for text that is not JSON.
ClassMethod ArgumentsHash(arguments As %RegisteredObject) As %String
{
	Quit $SYSTEM.Encryption.Base64Encode(..Digest(arguments), 1)
}

/// The fingerprint of an MCP tool: 64 lower-case hexadecimal characters, the SHA-256 (Digest) of the canonical form of {"server": server, "name": name,
/// "description": description, "parameters": parameters}, so it changes when the server (the tool_ref the tool was listed under), the tool's name, its description
/// or its input schema changes and in no other case. server and name are text, as is the description; the parameters are the tool's input schema as an object or
/// JSON text (blank text is {}). It throws for parameters that are text and not JSON.
ClassMethod ToolFingerprint(server As %String, name As %String, description As %String, parameters As %RegisteredObject) As %String
{
	If $IsObject(parameters) {
		Set schema = parameters
	} ElseIf $ZStrip(parameters, "*WC") = "" {
		Set schema = {}
	} Else {
		Set schema = ##class(%Library.DynamicAbstractObject).%FromJSON(parameters)
	}
	Set value = {}
	Do value.%Set("server", server, "string")
	Do value.%Set("name", name, "string")
	Do value.%Set("description", description, "string")
	Do value.%Set("parameters", schema)
	Set digest = ..Digest(value)
	Set hex = ""
	For i = 1:1:$Length(digest) {
		Set hex = hex _ $ZConvert($Extract($ZHex(256 + $Ascii(digest, i)), 2, 3), "L")
	}
	Quit hex
}

/// The SHA-256 of the UTF-8 text of the canonical form of the arguments (see ArgumentsHash), as the 32 bytes of the digest.
ClassMethod Digest(arguments As %RegisteredObject) As %String [ Private ]
{
	If $IsObject(arguments) {
		Set value = arguments
	} ElseIf $ZStrip(arguments, "*WC") = "" {
		Set value = {}
	} Else {
		Set value = ##class(%Library.DynamicAbstractObject).%FromJSON(arguments)
	}
	If '$IsObject(value) || 'value.%IsA("%Library.DynamicAbstractObject") $$$ThrowStatus($SYSTEM.Status.Error(5001, "The arguments are not a JSON object or array"))
	Quit $SYSTEM.Encryption.SHAHash(256, $ZConvert(..Canonical(value, $Select(value.%IsA("%Library.DynamicArray"): "array", 1: "object")), "O", "UTF8"))
}

/// The canonical text of a JSON value of the type (%GetTypeOf): see ArgumentsHash.
ClassMethod Canonical(value, type As %String) As %String [ Private ]
{
	If type = "object" {
		Kill keys
		Set iterator = value.%GetIterator()
		While iterator.%GetNext(.key) {
			Set keys("k" _ key) = ""
		}
		Set text = ""
		Set sorted = ""
		For {
			Set sorted = $Order(keys(sorted))
			If sorted = "" Quit
			Set key = $Extract(sorted, 2, *)
			Set text = text _ $Select(text = "": "", 1: ",") _ ..Quoted(key) _ ":" _ ..Canonical(value.%Get(key), value.%GetTypeOf(key))
		}
		Quit "{" _ text _ "}"
	}
	If type = "array" {
		Set text = ""
		Set iterator = value.%GetIterator()
		While iterator.%GetNext(.index, .item, .itemType) {
			Set text = text _ $Select(index = 0: "", 1: ",") _ ..Canonical(item, itemType)
		}
		Quit "[" _ text _ "]"
	}
	If type = "number" Quit +value
	If type = "boolean" Quit $Select(value: "true", 1: "false")
	If type = "string" Quit ..Quoted(value)
	Quit "null"
}

/// The JSON text of one string.
ClassMethod Quoted(text As %String) As %String [ Private ]
{
	Set holder = []
	Do holder.%Push(text, "string")
	Set json = holder.%ToJSON()
	Quit $Extract(json, 2, *-1)
}

}
